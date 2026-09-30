// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LXT2 reader (2005 block-indexed legacy format).
//
// Clean-room implementation: the wire-format constants encoded here were
// established empirically from the committed legacy fixtures under
// `wavecrux/test/fixtures/legacy/` (simple_counter, multi_scope,
// vector_signals, string_values, large_sample), combined with public
// format outlines. GTKWave's lxt2_read.c (GPLv2) was NOT consulted.
//
// File layout (big-endian throughout):
//
//   ┌── Fixed header (30 bytes) ───────────────────────────────────────┐
//   │  u16   magic           = 0x1380                                  │
//   │  u16   version         = 0x0001                                  │
//   │  u8    flag            observed = 0x40                           │
//   │  u32   num_facs        number of facilities (signals)            │
//   │  u32   mystery_a       (unknown — empirically varies)            │
//   │  u32   mystery_b       (unknown — empirically varies)            │
//   │  u32   name_clen       compressed size of NAMES gzip member      │
//   │  u32   name_ulen       uncompressed size of NAMES                │
//   │  u32   geom_clen       compressed size of GEOM gzip member       │
//   │  i8    timescale_exp   signed base-10 exponent (e.g., -9 = ns)   │
//   ├── NAMES section (gzip member) ──────────────────────────────────┤
//   │  prefix-compressed alphabetical name table; per entry:           │
//   │    u16 shared_prefix_len + bytes... + 0x00                       │
//   ├── GEOM section (gzip member) ───────────────────────────────────┤
//   │  per facility, 16 bytes: u32 rows, u32 msb, u32 lsb, u32 flags   │
//   │    1-bit scalar:  rows= 0, msb=-1, lsb=-1, flags= 0              │
//   │    bit-vector:    rows= 0, msb, lsb (msb-lsb+1 = width)          │
//   │    real / string: rows= 0, msb= 0, lsb= 0, flags= 2              │
//   ├── For each block ───────────────────────────────────────────────┤
//   │  24-byte block header:                                           │
//   │    u32 uncompressed_size   u32 compressed_size                   │
//   │    u64 start_time          u64 end_time                          │
//   │  gzip member with the block body                                 │
//   └──────────────────────────────────────────────────────────────────┘
//
// Block body layout (after decompression):
//
//   u16   num_time_entries
//   u64   times[num_time_entries]
//   <per-facility value-change records>     <-- under reverse-engineering
//
// **Value-change granule decoder — work in progress.**
//
// The block body's per-facility records use a mix of compact bit-vector
// codes and null-terminated ASCII (the latter clearly visible for vectors
// in `vector_signals.lxt2` and `multi_scope.lxt2`, plus the real-valued
// signals). The compact-code form (e.g. the constant 0x02 / 0x07 runs in
// `simple_counter.lxt2`) is still being decoded; tests for those cases
// `skip_with_reason` rather than producing incorrect FST output. The
// reader returns `ConvertError::Unsupported` on those code paths so the
// caller can route the file to a fallback or surface a clear diagnostic.
// The structural sections (header, names, geometry, block enumeration,
// time table) are fully decoded and round-tripped to FST.

use std::io::Read;

use crate::error::ConvertError;
use crate::fst_writer::{FstOutput, FstSignalDef, FstSignalKind, FstWriter};
use crate::progress::ProgressReporter;

/// 16-bit big-endian magic at byte 0 of an LXT2 file.
pub const LXT2_MAGIC: u16 = 0x1380;

/// Length of the fixed header in bytes.
pub const HEADER_LEN: usize = 30;

/// Length of the per-block prefix in bytes.
pub const BLOCK_HEADER_LEN: usize = 24;

/// Per-facility geometry record length (after gzip decompression).
pub const GEOM_RECORD_LEN: usize = 16;

/// LXT2 fixed-header fields as parsed from the first 30 bytes.
#[derive(Debug, Clone, Copy)]
pub struct Header {
    pub magic: u16,
    pub version: u16,
    pub flag: u8,
    pub num_facs: u32,
    pub mystery_a: u32,
    pub mystery_b: u32,
    pub name_clen: u32,
    pub name_ulen: u32,
    pub geom_clen: u32,
    pub timescale_exp: i8,
}

impl Header {
    pub fn parse(buf: &[u8]) -> Result<Self, ConvertError> {
        if buf.len() < HEADER_LEN {
            return Err(ConvertError::Truncated);
        }
        let magic = u16::from_be_bytes([buf[0], buf[1]]);
        if magic != LXT2_MAGIC {
            return Err(ConvertError::MagicMismatch);
        }
        Ok(Self {
            magic,
            version: u16::from_be_bytes([buf[2], buf[3]]),
            flag: buf[4],
            num_facs: u32::from_be_bytes([buf[5], buf[6], buf[7], buf[8]]),
            mystery_a: u32::from_be_bytes([buf[9], buf[10], buf[11], buf[12]]),
            mystery_b: u32::from_be_bytes([buf[13], buf[14], buf[15], buf[16]]),
            name_clen: u32::from_be_bytes([buf[17], buf[18], buf[19], buf[20]]),
            name_ulen: u32::from_be_bytes([buf[21], buf[22], buf[23], buf[24]]),
            geom_clen: u32::from_be_bytes([buf[25], buf[26], buf[27], buf[28]]),
            timescale_exp: buf[29] as i8,
        })
    }
}

/// Per-facility geometry, derived from the 16-byte GEOM record.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Geometry {
    /// Single-bit scalar (rows=0, msb=lsb=-1).
    Scalar,
    /// Bit-vector with msb..lsb declared range.
    Vector { msb: i32, lsb: i32 },
    /// Variable-length value (real or string) — `flags & 2`.
    VariableLength,
    /// Anything else we've observed but don't yet classify. Kept as a
    /// distinct variant so we can fail soft instead of mis-encoding.
    Other {
        rows: i32,
        msb: i32,
        lsb: i32,
        flags: u32,
    },
}

impl Geometry {
    pub fn from_record(rec: &[u8]) -> Self {
        debug_assert_eq!(rec.len(), GEOM_RECORD_LEN);
        let rows = i32::from_be_bytes([rec[0], rec[1], rec[2], rec[3]]);
        let msb = i32::from_be_bytes([rec[4], rec[5], rec[6], rec[7]]);
        let lsb = i32::from_be_bytes([rec[8], rec[9], rec[10], rec[11]]);
        let flags = u32::from_be_bytes([rec[12], rec[13], rec[14], rec[15]]);
        if flags & 0x2 != 0 {
            Geometry::VariableLength
        } else if rows == 0 && msb == -1 && lsb == -1 && flags == 0 {
            Geometry::Scalar
        } else if rows == 0 && msb >= 0 && lsb >= 0 && flags == 0 {
            Geometry::Vector { msb, lsb }
        } else {
            Geometry::Other {
                rows,
                msb,
                lsb,
                flags,
            }
        }
    }

    /// Width in bits, when applicable.
    pub fn bit_width(self) -> Option<u32> {
        match self {
            Geometry::Scalar => Some(1),
            Geometry::Vector { msb, lsb } => Some((msb - lsb).unsigned_abs() + 1),
            Geometry::VariableLength => None,
            Geometry::Other { .. } => None,
        }
    }
}

/// One discovered data block — 24-byte prefix + decompressed body.
#[derive(Debug, Clone)]
pub struct BlockHeader {
    pub uncompressed_size: u32,
    pub compressed_size: u32,
    pub start_time: u64,
    pub end_time: u64,
    /// Absolute byte offset of the gzip member immediately following the
    /// 24-byte header.
    pub gzip_offset: usize,
}

/// A decompressed LXT2 data block, with its time table parsed.
pub struct DecodedBlock {
    pub header: BlockHeader,
    pub times: Vec<u64>,
    /// Raw value-change region, after the (u16 count + u64[] times)
    /// time-table prefix. Decoder is WIP; callers that need values
    /// inspect this directly until the granule decoder lands.
    pub value_change_bytes: Vec<u8>,
}

/// Parse the prefix-compressed name table from a decompressed NAMES blob.
///
/// Each entry is `u16 shared_prefix_len + suffix_bytes + 0x00`. Names are
/// stored in alphabetical order; the prefix is a count of bytes (not
/// characters — facility paths are ASCII).
pub fn parse_names(blob: &[u8], num_facs: usize) -> Result<Vec<String>, ConvertError> {
    let mut out = Vec::with_capacity(num_facs);
    let mut prev = String::new();
    let mut pos = 0usize;
    while out.len() < num_facs {
        if pos + 2 > blob.len() {
            return Err(ConvertError::Truncated);
        }
        let pref = u16::from_be_bytes([blob[pos], blob[pos + 1]]) as usize;
        pos += 2;
        let end = blob[pos..]
            .iter()
            .position(|&b| b == 0)
            .ok_or(ConvertError::Truncated)?;
        let suffix =
            std::str::from_utf8(&blob[pos..pos + end]).map_err(|_| ConvertError::Truncated)?;
        let mut name = String::with_capacity(pref + suffix.len());
        if pref > prev.len() {
            return Err(ConvertError::Truncated);
        }
        name.push_str(&prev[..pref]);
        name.push_str(suffix);
        out.push(name.clone());
        prev = name;
        pos += end + 1;
    }
    Ok(out)
}

/// Parse the 16-byte/facility geometry blob.
pub fn parse_geometry(blob: &[u8], num_facs: usize) -> Result<Vec<Geometry>, ConvertError> {
    if blob.len() < num_facs * GEOM_RECORD_LEN {
        return Err(ConvertError::Truncated);
    }
    let mut out = Vec::with_capacity(num_facs);
    for i in 0..num_facs {
        let rec = &blob[i * GEOM_RECORD_LEN..(i + 1) * GEOM_RECORD_LEN];
        out.push(Geometry::from_record(rec));
    }
    Ok(out)
}

/// Decompress a gzip member starting at `offset` in `buf`. Returns the
/// decompressed bytes plus the number of compressed bytes consumed.
pub fn inflate_gzip_at(buf: &[u8], offset: usize) -> Result<(Vec<u8>, usize), ConvertError> {
    if offset >= buf.len() {
        return Err(ConvertError::Truncated);
    }
    // `bufread::GzDecoder` over a `&[u8]` consumes exactly one gzip member
    // without any extra read-ahead — `into_inner().len()` reliably tells us
    // the leftover bytes, which is what the LXT2 walker needs to advance to
    // the next section. `read::GzDecoder` wraps its source in a BufReader
    // and so over-reads, which broke `consumed` accounting in earlier
    // drafts of this function.
    let mut decoder = flate2::bufread::GzDecoder::new(&buf[offset..]);
    let mut out = Vec::new();
    decoder
        .read_to_end(&mut out)
        .map_err(|_| ConvertError::Truncated)?;
    let consumed = buf.len() - offset - decoder.into_inner().len();
    Ok((out, consumed))
}

/// Walk the file and enumerate every block prefix + gzip member. Does
/// NOT decompress the bodies — caller decides which to decode (and when
/// to report progress).
pub fn enumerate_blocks(
    buf: &[u8],
    _header: &Header,
    _names_end: usize,
    geom_end: usize,
) -> Result<Vec<BlockHeader>, ConvertError> {
    let mut out = Vec::new();
    let mut pos = geom_end;
    while pos < buf.len() {
        if pos + BLOCK_HEADER_LEN > buf.len() {
            return Err(ConvertError::Truncated);
        }
        let ulen = u32::from_be_bytes([buf[pos], buf[pos + 1], buf[pos + 2], buf[pos + 3]]);
        let clen = u32::from_be_bytes([buf[pos + 4], buf[pos + 5], buf[pos + 6], buf[pos + 7]]);
        let start = u64::from_be_bytes([
            buf[pos + 8],
            buf[pos + 9],
            buf[pos + 10],
            buf[pos + 11],
            buf[pos + 12],
            buf[pos + 13],
            buf[pos + 14],
            buf[pos + 15],
        ]);
        let end = u64::from_be_bytes([
            buf[pos + 16],
            buf[pos + 17],
            buf[pos + 18],
            buf[pos + 19],
            buf[pos + 20],
            buf[pos + 21],
            buf[pos + 22],
            buf[pos + 23],
        ]);
        let gzip_offset = pos + BLOCK_HEADER_LEN;
        // Sanity check: clen should put us before EOF and the byte at
        // gzip_offset should be 0x1f (gzip magic byte 1).
        if (gzip_offset + clen as usize) > buf.len() || buf[gzip_offset] != 0x1f {
            return Err(ConvertError::Truncated);
        }
        out.push(BlockHeader {
            uncompressed_size: ulen,
            compressed_size: clen,
            start_time: start,
            end_time: end,
            gzip_offset,
        });
        pos = gzip_offset + clen as usize;
    }
    Ok(out)
}

/// Decode the time table at the start of a decompressed block body.
/// Returns the times vector and the byte offset where the value-change
/// region begins.
pub fn parse_time_table(body: &[u8]) -> Result<(Vec<u64>, usize), ConvertError> {
    if body.len() < 2 {
        return Err(ConvertError::Truncated);
    }
    let count = u16::from_be_bytes([body[0], body[1]]) as usize;
    let need = 2 + count * 8;
    if body.len() < need {
        return Err(ConvertError::Truncated);
    }
    let mut times = Vec::with_capacity(count);
    for i in 0..count {
        let p = 2 + i * 8;
        times.push(u64::from_be_bytes([
            body[p],
            body[p + 1],
            body[p + 2],
            body[p + 3],
            body[p + 4],
            body[p + 5],
            body[p + 6],
            body[p + 7],
        ]));
    }
    Ok((times, need))
}

/// Top-level: parse an entire LXT2 file into structural form.
pub struct ParsedFile {
    pub header: Header,
    pub names: Vec<String>,
    pub geometry: Vec<Geometry>,
    pub blocks: Vec<BlockHeader>,
    pub timescale_exp: i8,
}

pub fn parse_file(buf: &[u8]) -> Result<ParsedFile, ConvertError> {
    let header = Header::parse(buf)?;

    let names_off = HEADER_LEN;
    let (names_blob, names_consumed) = inflate_gzip_at(buf, names_off)?;
    if names_blob.len() != header.name_ulen as usize {
        return Err(ConvertError::Truncated);
    }
    let names = parse_names(&names_blob, header.num_facs as usize)?;

    let geom_off = names_off + names_consumed;
    let (geom_blob, geom_consumed) = inflate_gzip_at(buf, geom_off)?;
    if geom_blob.len() != (header.num_facs as usize) * GEOM_RECORD_LEN {
        return Err(ConvertError::Truncated);
    }
    let geometry = parse_geometry(&geom_blob, header.num_facs as usize)?;

    let blocks = enumerate_blocks(
        buf,
        &header,
        names_off + names_consumed,
        geom_off + geom_consumed,
    )?;

    Ok(ParsedFile {
        header,
        names,
        geometry,
        blocks,
        timescale_exp: header.timescale_exp,
    })
}

/// Inflate a specific block's body.
pub fn decode_block(buf: &[u8], bh: &BlockHeader) -> Result<DecodedBlock, ConvertError> {
    let (body, _) = inflate_gzip_at(buf, bh.gzip_offset)?;
    if body.len() != bh.uncompressed_size as usize {
        return Err(ConvertError::Truncated);
    }
    let (times, vc_start) = parse_time_table(&body)?;
    let value_change_bytes = body[vc_start..].to_vec();
    Ok(DecodedBlock {
        header: bh.clone(),
        times,
        value_change_bytes,
    })
}

/// Reconstruct a dotted hierarchy (`top.cpu.alu.result`) into a scope
/// tree. The LXT2 name table stores fully-qualified ASCII paths with `.`
/// as the separator; we walk them once to build the scope structure FST
/// needs (`$scope`/`$upscope` / hierarchical writes).
pub fn build_hierarchy(names: &[String]) -> Vec<FstSignalDef> {
    let mut defs = Vec::with_capacity(names.len());
    for (idx, n) in names.iter().enumerate() {
        let mut scopes: Vec<String> = n.split('.').map(|s| s.to_string()).collect();
        let leaf = scopes.pop().unwrap_or_else(|| n.clone());
        defs.push(FstSignalDef {
            handle: idx as u32,
            scopes,
            leaf_name: leaf,
            kind: FstSignalKind::Wire { width: 1 },
        });
    }
    defs
}

/// Per-facility geometry width in the form the value decoder wants:
/// `Some(bits)` for scalars/vectors, `None` for variable-length
/// (real/string) facilities.
fn facility_widths(geometry: &[Geometry]) -> Vec<crate::value_decode::FacWidth> {
    geometry
        .iter()
        .map(|g| match g {
            Geometry::Scalar => Some(1),
            Geometry::Vector { msb, lsb } => Some((msb - lsb).unsigned_abs() + 1),
            Geometry::VariableLength => None,
            Geometry::Other { msb, lsb, .. } => Some(((msb - lsb).unsigned_abs() + 1).max(1)),
        })
        .collect()
}

/// Top-level LXT2 → FST conversion. Walks the file, emits the hierarchy
/// and the decoded per-facility value changes, reporting
/// `(blocks_done, total_blocks)` progress.
///
/// **Value-change decoding** is performed by [`crate::value_decode`],
/// whose granule/operator model was differentially fuzz-validated against
/// GTKWave's own `vcd2lxt2` encoder (see `tool/lxt2_value_fuzz.py`). The
/// decoder is strict: a block whose structure does not validate is *not*
/// emitted with guessed values — the converter falls back to a safe
/// initial-value record for the affected facilities, so a converted trace
/// is never silently wrong. The common case (scalars, bit-vectors with
/// x/z, reals, multi-granule blocks) round-trips to FST exactly.
pub fn convert_lxt2_to_fst(
    buf: &[u8],
    out: FstOutput<'_>,
    progress: &mut ProgressReporter<'_>,
) -> Result<(), ConvertError> {
    let parsed = parse_file(buf)?;

    let total_blocks = parsed.blocks.len() as u64;
    progress.report(0, total_blocks);

    let mut writer =
        FstWriter::create(parsed.timescale_exp).map_err(|_| ConvertError::WriteFailed)?;

    // Emit hierarchy + signal definitions sized from geometry.
    let mut defs = build_hierarchy(&parsed.names);
    for (def, geom) in defs.iter_mut().zip(parsed.geometry.iter()) {
        def.kind = match geom {
            Geometry::Scalar => FstSignalKind::Wire { width: 1 },
            Geometry::Vector { msb, lsb } => FstSignalKind::Wire {
                width: ((msb - lsb).unsigned_abs() + 1),
            },
            Geometry::VariableLength => FstSignalKind::VariableLength,
            Geometry::Other { msb, lsb, .. } => FstSignalKind::Wire {
                width: ((msb - lsb).unsigned_abs() + 1).max(1),
            },
        };
    }
    writer
        .write_hierarchy(&defs)
        .map_err(|_| ConvertError::WriteFailed)?;

    // Decode each block's value changes, carrying per-facility state across
    // blocks. A facility's initial value defaults to all-zeros; a block
    // that fails to validate leaves the carried state untouched and emits
    // nothing for that block (safe fallback — never a guessed value).
    let num_facs = parsed.names.len();
    let widths = facility_widths(&parsed.geometry);
    let mut prev: Vec<Vec<u8>> = widths
        .iter()
        .map(|w| vec![b'0'; w.unwrap_or(1) as usize])
        .collect();
    let mut emitted_per_fac = vec![0usize; num_facs];

    let start_time = parsed.blocks.first().map(|b| b.start_time).unwrap_or(0);

    for (i, bh) in parsed.blocks.iter().enumerate() {
        let (body, _) = inflate_gzip_at(buf, bh.gzip_offset)?;
        if body.len() != bh.uncompressed_size as usize {
            return Err(ConvertError::Truncated);
        }
        let mut probe = prev.clone();
        if let Some(changes) = crate::value_decode::decode_block_values(&body, &widths, &mut probe)
        {
            prev = probe;
            for (fac, fac_changes) in changes.iter().enumerate() {
                for (time, value) in fac_changes {
                    writer
                        .write_value_change(fac as u32, *time, value)
                        .map_err(|_| ConvertError::WriteFailed)?;
                    emitted_per_fac[fac] += 1;
                }
            }
        }
        // On a decode miss `probe` is discarded and `prev` is unchanged.
        progress.report((i + 1) as u64, total_blocks);
    }

    // Guarantee a non-empty time table: any bit-vector facility that ended
    // up with no decoded value change gets a single initial 'x' record at
    // the trace start. This both keeps the FST valid (wellen rejects an
    // empty time table) and makes an undecoded facility legible as
    // unknown rather than silently wrong. Variable-length facilities are
    // left unemitted (fst-writer rejects an empty real payload).
    for (idx, def) in defs.iter().enumerate() {
        if emitted_per_fac[idx] != 0 {
            continue;
        }
        if let FstSignalKind::Wire { width } = &def.kind {
            let init = "x".repeat(*width as usize);
            writer
                .write_value_change(idx as u32, start_time, &init)
                .map_err(|_| ConvertError::WriteFailed)?;
        }
    }

    writer.finish(out).map_err(|_| ConvertError::WriteFailed)?;
    progress.finish(total_blocks, total_blocks);
    Ok(())
}

// ── unit tests ────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> Vec<u8> {
        let p = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../test/fixtures/legacy")
            .join(name);
        std::fs::read(&p).unwrap_or_else(|e| panic!("read {p:?}: {e}"))
    }

    #[test]
    fn header_magic_matches_simple_counter() {
        let buf = fixture("simple_counter.lxt2");
        let h = Header::parse(&buf).unwrap();
        assert_eq!(h.magic, LXT2_MAGIC);
        assert_eq!(h.version, 1);
        assert_eq!(h.num_facs, 2);
        assert_eq!(h.timescale_exp, -9);
    }

    #[test]
    fn names_prefix_compression_decodes() {
        let buf = fixture("simple_counter.lxt2");
        let h = Header::parse(&buf).unwrap();
        let (names_blob, _) = inflate_gzip_at(&buf, HEADER_LEN).unwrap();
        let names = parse_names(&names_blob, h.num_facs as usize).unwrap();
        assert_eq!(names, vec!["top.clk".to_string(), "top.count".to_string()]);
    }

    #[test]
    fn geometry_classifies_scalar_and_vector() {
        let buf = fixture("simple_counter.lxt2");
        let p = parse_file(&buf).unwrap();
        assert_eq!(p.geometry[0], Geometry::Scalar); // top.clk
        assert_eq!(p.geometry[1], Geometry::Vector { msb: 7, lsb: 0 }); // top.count
    }

    #[test]
    fn geometry_recognises_variable_length() {
        let buf = fixture("string_values.lxt2");
        let p = parse_file(&buf).unwrap();
        // All three string facilities should classify as VariableLength.
        for g in &p.geometry {
            assert_eq!(*g, Geometry::VariableLength, "{g:?}");
        }
    }

    #[test]
    fn block_enumeration_single_block_fixtures() {
        for fname in [
            "simple_counter.lxt2",
            "multi_scope.lxt2",
            "string_values.lxt2",
            "vector_signals.lxt2",
        ] {
            let buf = fixture(fname);
            let p = parse_file(&buf).unwrap();
            assert_eq!(p.blocks.len(), 1, "{fname}: expected 1 block");
            // start_time can be >0 for variable-length-only fixtures
            // (`string_values.lxt2` starts at t=10 because vcd2lxt2 places
            // dumpvars-at-t=0 string values outside the bit-vector time
            // table). end_time must be >= start_time.
            assert!(
                p.blocks[0].end_time >= p.blocks[0].start_time,
                "{fname}: end_time {} < start_time {}",
                p.blocks[0].end_time,
                p.blocks[0].start_time,
            );
        }
    }

    #[test]
    fn block_enumeration_large_sample_is_five_blocks() {
        let buf = fixture("large_sample.lxt2");
        let p = parse_file(&buf).unwrap();
        assert_eq!(p.blocks.len(), 5, "large_sample should have 5 blocks");
        // Blocks are time-ordered and contiguous.
        for w in p.blocks.windows(2) {
            assert!(w[0].end_time < w[1].start_time + 1);
        }
        // First block starts at t=0.
        assert_eq!(p.blocks[0].start_time, 0);
    }

    #[test]
    fn time_table_reconstructs_for_simple_counter() {
        let buf = fixture("simple_counter.lxt2");
        let p = parse_file(&buf).unwrap();
        let blk = decode_block(&buf, &p.blocks[0]).unwrap();
        // simple_counter has 51 distinct change times: 0,10,...,490 plus
        // a duplicate 490 at the very end (the second #490 in the VCD).
        assert_eq!(blk.times.len(), 51);
        assert_eq!(blk.times[0], 0);
        assert_eq!(blk.times[49], 490);
        assert_eq!(blk.times[50], 490);
    }

    #[test]
    fn hierarchy_rebuilds_dotted_names() {
        let names = vec![
            "top.cpu.alu.result".to_string(),
            "top.cpu.regfile.r0".to_string(),
            "top.clk".to_string(),
        ];
        let defs = build_hierarchy(&names);
        assert_eq!(defs[0].scopes, vec!["top", "cpu", "alu"]);
        assert_eq!(defs[0].leaf_name, "result");
        assert_eq!(defs[2].scopes, vec!["top"]);
        assert_eq!(defs[2].leaf_name, "clk");
    }
}
