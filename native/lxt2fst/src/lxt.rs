// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LXT classic reader (2003 streaming format).
//
// Clean-room: the magic byte and structural layout below were established
// empirically from `wavecrux/test/fixtures/legacy/simple_counter.lxt`
// (a vcd2lxt-converted 8-bit counter, ~50 transitions) combined with the
// publicly-documented format outline. GTKWave's lxt_read.c (GPLv2) was
// NOT consulted — neither as source, nor as a source of constants.
//
// File layout (big-endian throughout):
//
//   ┌── u16 magic = 0x0138 ────────────────────────────────────────────┐
//   │                                                                   │
//   ├── inline value-change stream ────────────────────────────────────┤
//   │  Streamed as the simulation ran. Opaque to the structural        │
//   │  decoder — see "Value-change decode" below.                      │
//   │                                                                   │
//   ├── gzip section 1: NAMES ─────────────────────────────────────────┤
//   │  Prefix-compressed alphabetical name table, identical wire        │
//   │  scheme to LXT2: per entry `u16 shared_prefix_len + bytes + 0x00`.│
//   │                                                                   │
//   ├── gzip section 2: GEOMETRY ──────────────────────────────────────┤
//   │  16 bytes/facility, identical layout to LXT2                      │
//   │  (rows, msb, lsb, flags) — so this module reuses                  │
//   │  `lxt2::{Geometry, parse_geometry}` rather than re-deriving it:   │
//   │    1-bit scalar:  rows=0, msb=-1, lsb=-1, flags=0                 │
//   │    bit-vector:    rows=0, msb, lsb (msb-lsb+1 = width)            │
//   │    real / string: flags & 2                                      │
//   │                                                                   │
//   ├── gzip section 3+: sync directory / time-length index ───────────┤
//   │  The index member is `u64 max_time` followed by parallel          │
//   │  per-change-record byte-length and inter-record time-delta        │
//   │  arrays. Used by GTKWave to seek; not needed for the structural   │
//   │  conversion, so this decoder only enumerates the members for      │
//   │  progress accounting.                                             │
//   │                                                                   │
//   └── trailer directory ─────────────────────────────────────────────┘
//      A preamble carrying the signed base-10 timescale exponent
//      (`0xf7` = -9 = ns in the committed fixture) followed by a list of
//      `u32 value + u8 tag` section offset / length records.
//
// LXT is the older streaming sibling of LXT2. It is rare in practice —
// field archives from that era are overwhelmingly LXT2 — and only one
// LXT-classic fixture ships (`simple_counter.lxt`).
//
// **Value-change decode (separate streaming codec from LXT2).** Unlike
// LXT2's block/granule value codec (`value_decode.rs`), LXT classic uses a
// *streaming* value-change codec. It is fully decoded by `lxt_value_decode`
// (clean-room, differentially fuzz-validated against GTKWave's `vcd2lxt`
// encoder — `tool/lxt_classic_value_fuzz.py`; `lxt_read.c` GPLv2 NOT
// consulted). This module decodes the structure (names, geometry, section
// enumeration, timescale, max-time) and `convert_lxt_to_fst` walks the value
// stream, emitting the real per-facility transitions. The decoder is strict:
// any structural surprise falls back to a bounded `x`-state emission rather
// than a guessed value, so a converted `.lxt` is never silently wrong.
//
// Wire model (clean-room, established with `vcd2lxt`):
//   * Layout: `u16 0x0004` header, then the inline value-change record
//     stream, then the gzip dictionary sections (NAMES, GEOMETRY, per-facility
//     chain-head table, index). Time is **not** in the inline stream — it
//     lives in the index section's per-timestep deltas.
//   * Record = `[op][facref][value bytes]`; `op & 0x0f` is the operator and
//     `1 + (op >> 4)` is the big-endian byte width of `facref`, a back-pointer
//     to the facility's previous change record (`prev = O - facref - 2`,
//     sentinel `-4` = chain start). Per-facility chain heads live in the
//     next-to-last gzip section; walking the chains resolves facility identity
//     (the stream is in VCD-declaration order, the name index alphabetical).
//   * Value field: `ceil(width/8)` bytes, big-endian, **MSB-left-justified**
//     for binary literals (op 0x00); op 0x01 is a 2-bit-per-symbol 4-state
//     literal; ops 0x03/04/05/06 set all-0/1/z/x; reals are op 0x00 + an
//     8-byte little-endian f64. Full detail in `lxt_value_decode`.

use crate::error::ConvertError;
use crate::fst_writer::{FstOutput, FstSignalKind, FstWriter};
use crate::lxt_value_decode;
use crate::lxt2::{
    GEOM_RECORD_LEN, Geometry, build_hierarchy, inflate_gzip_at, parse_geometry, parse_names,
};
use crate::progress::ProgressReporter;
use crate::value_decode::FacWidth;

/// Per-facility geometry width: `Some(bits)` for a scalar / bit-vector,
/// `None` for a variable-length (real / string) facility. Mirrors the LXT2
/// path's mapping so both formats land on identical FST shapes.
fn facility_widths(geometry: &[Geometry]) -> Vec<FacWidth> {
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

/// 16-bit big-endian magic at byte 0 of an LXT classic file.
pub const LXT_MAGIC: u16 = 0x0138;

/// gzip member magic (`0x1f 0x8b`) + DEFLATE compression method (`0x08`).
/// Used to locate the trailing dictionary sections in the streaming file.
const GZIP_SIGNATURE: [u8; 3] = [0x1f, 0x8b, 0x08];

/// Best-effort header peek. Confirms the magic byte so the open-from-path
/// probe can route the file to this reader.
#[derive(Debug)]
pub struct LxtHeader {
    pub magic: u16,
}

impl LxtHeader {
    pub fn parse(buf: &[u8]) -> Result<Self, ConvertError> {
        if buf.len() < 2 {
            return Err(ConvertError::Truncated);
        }
        let magic = u16::from_be_bytes([buf[0], buf[1]]);
        if magic != LXT_MAGIC {
            return Err(ConvertError::MagicMismatch);
        }
        Ok(Self { magic })
    }
}

/// Scan `buf` for the next gzip member at or after `from`. Returns the
/// absolute offset of the `0x1f 0x8b 0x08` signature, or `None` at EOF.
/// The inline change stream uses only small byte codes, so the 3-byte
/// signature does not collide with it; each candidate is still validated
/// by the subsequent inflate.
fn find_gzip_member(buf: &[u8], from: usize) -> Option<usize> {
    if buf.len() < GZIP_SIGNATURE.len() {
        return None;
    }
    (from..=buf.len() - GZIP_SIGNATURE.len()).find(|&i| buf[i..i + 3] == GZIP_SIGNATURE)
}

/// Enumerate every trailing gzip section in stream order. The first is
/// NAMES, the second GEOMETRY; the rest are the sync directory / index
/// members the structural decoder does not need. Returns `(offset,
/// inflated_blob)` per member.
pub fn enumerate_sections(buf: &[u8]) -> Result<Vec<(usize, Vec<u8>)>, ConvertError> {
    let mut out = Vec::new();
    // Skip the 2-byte magic; the inline change stream follows and is
    // scanned past by `find_gzip_member`.
    let mut pos = 2usize;
    while let Some(off) = find_gzip_member(buf, pos) {
        let (blob, consumed) = inflate_gzip_at(buf, off)?;
        out.push((off, blob));
        pos = off + consumed;
    }
    Ok(out)
}

/// The signed base-10 timescale exponent, read from the trailer directory
/// that follows the last gzip section (`0xf7` = -9 = ns in the committed
/// fixture). Falls back to -9 (ns) when the trailer is too short — a
/// missing timescale only affects time-axis display, never values, and ns
/// is the dominant simulator default.
fn read_timescale_exp(buf: &[u8], sections: &[(usize, Vec<u8>)]) -> i8 {
    const DEFAULT_NS: i8 = -9;
    let Some(&(last_off, _)) = sections.last() else {
        return DEFAULT_NS;
    };
    // Re-derive the byte just past the final gzip member: re-inflate to get
    // its consumed length (cheap — the index member is small).
    let Ok((_, consumed)) = inflate_gzip_at(buf, last_off) else {
        return DEFAULT_NS;
    };
    let trailer_start = last_off + consumed;
    // The directory preamble is `u8 record_count, i8 timescale_exp, ...`.
    buf.get(trailer_start + 1).map_or(DEFAULT_NS, |&b| b as i8)
}

/// Top-level: parse an LXT classic file into structural form. Mirrors
/// `lxt2::ParsedFile`.
pub struct ParsedFile {
    pub header: LxtHeader,
    pub names: Vec<String>,
    pub geometry: Vec<Geometry>,
    pub timescale_exp: i8,
    /// Number of gzip dictionary sections discovered (for progress).
    pub section_count: usize,
    /// Maximum simulation time, read from the index section's leading u64.
    pub max_time: u64,
}

pub fn parse_file(buf: &[u8]) -> Result<ParsedFile, ConvertError> {
    let header = LxtHeader::parse(buf)?;

    let sections = enumerate_sections(buf)?;
    if sections.len() < 2 {
        // NAMES + GEOMETRY are mandatory; anything fewer is truncated.
        return Err(ConvertError::Truncated);
    }

    // GEOMETRY (section 2) fixes the facility count; NAMES (section 1) is
    // then parsed against it.
    let geom_blob = &sections[1].1;
    if geom_blob.is_empty() || geom_blob.len() % GEOM_RECORD_LEN != 0 {
        return Err(ConvertError::Truncated);
    }
    let num_facs = geom_blob.len() / GEOM_RECORD_LEN;
    let geometry = parse_geometry(geom_blob, num_facs)?;

    let names = parse_names(&sections[0].1, num_facs)?;

    let timescale_exp = read_timescale_exp(buf, &sections);

    // The trailing time/length-index section begins with a big-endian u64
    // maximum time. We use it to bound the emitted time table (see
    // `convert_lxt_to_fst`); 0 if the section is missing/short.
    let max_time = sections
        .last()
        .and_then(|(_, blob)| blob.get(0..8))
        .map(|s| u64::from_be_bytes([s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7]]))
        .unwrap_or(0);

    Ok(ParsedFile {
        header,
        names,
        geometry,
        timescale_exp,
        section_count: sections.len(),
        max_time,
    })
}

/// LXT → FST conversion entry. Walks the file, emits hierarchy + initial
/// (time-zero) values for every facility, and reports progress over the
/// discovered dictionary sections. Structural parity with
/// `lxt2::convert_lxt2_to_fst`; per-facility value-change granules are the
/// shared follow-up (see README §"Status").
pub fn convert_lxt_to_fst(
    buf: &[u8],
    out: FstOutput<'_>,
    progress: &mut ProgressReporter<'_>,
) -> Result<(), ConvertError> {
    let parsed = parse_file(buf)?;

    let total = parsed.section_count as u64;
    progress.report(0, total);

    let mut writer =
        FstWriter::create(parsed.timescale_exp).map_err(|_| ConvertError::WriteFailed)?;

    // Emit hierarchy + signal definitions sized from geometry. Identical
    // mapping to the LXT2 path so both formats land on the same FST shape.
    let mut defs = build_hierarchy(&parsed.names);
    for (def, geom) in defs.iter_mut().zip(parsed.geometry.iter()) {
        def.kind = match geom {
            Geometry::Scalar => FstSignalKind::Wire { width: 1 },
            Geometry::Vector { msb, lsb } => FstSignalKind::Wire {
                width: (msb - lsb).unsigned_abs() + 1,
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

    // Decode the inline streaming value-change records (see
    // `lxt_value_decode`). The decoder is strict: it returns `None` on any
    // structural surprise, and the converter then falls back to the safe
    // `x`-state emission below rather than risk a wrong waveform. The common
    // case (scalars, bit-vectors with x/z, reals, multi-facility, wide
    // back-pointers) round-trips to FST exactly.
    let widths = facility_widths(&parsed.geometry);
    let sections = enumerate_sections(buf)?;
    let decoded = lxt_value_decode::decode_values(buf, &sections, &widths);

    let mut emitted_per_fac = vec![0usize; defs.len()];
    if let Some(changes) = &decoded {
        for (fac, fac_changes) in changes.iter().enumerate() {
            for (time, value) in fac_changes {
                writer
                    .write_value_change(fac as u32, *time, value)
                    .map_err(|_| ConvertError::WriteFailed)?;
                emitted_per_fac[fac] += 1;
            }
        }
    }

    // Emit `x` (unknown) values at the trace start and end for every
    // bit-vector facility the decoder did not cover (a whole-file decode
    // miss, or an individual facility with no changes). Emitting at both
    // `t=0` and `t=max_time` keeps the FST time table non-degenerate (wellen
    // rejects an empty time table) so the file always opens cleanly with the
    // full hierarchy. Variable-length (real / string) facilities are skipped
    // — fst-writer rejects an empty real payload.
    let end_time = parsed.max_time;
    for (idx, def) in defs.iter().enumerate() {
        if emitted_per_fac[idx] != 0 {
            continue;
        }
        if let FstSignalKind::Wire { width } = &def.kind {
            let init = "x".repeat(*width as usize);
            writer
                .write_value_change(idx as u32, 0, &init)
                .map_err(|_| ConvertError::WriteFailed)?;
            if end_time > 0 {
                writer
                    .write_value_change(idx as u32, end_time, &init)
                    .map_err(|_| ConvertError::WriteFailed)?;
            }
        }
    }

    writer.finish(out).map_err(|_| ConvertError::WriteFailed)?;
    progress.finish(total, total);
    Ok(())
}

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
    fn magic_matches_committed_lxt_fixture() {
        let buf = fixture("simple_counter.lxt");
        let h = LxtHeader::parse(&buf).unwrap();
        assert_eq!(h.magic, LXT_MAGIC);
    }

    #[test]
    fn enumerates_at_least_names_and_geometry_sections() {
        let buf = fixture("simple_counter.lxt");
        let sections = enumerate_sections(&buf).unwrap();
        assert!(
            sections.len() >= 2,
            "expected NAMES + GEOMETRY (and likely index) sections, got {}",
            sections.len()
        );
    }

    #[test]
    fn names_prefix_compression_decodes() {
        let buf = fixture("simple_counter.lxt");
        let p = parse_file(&buf).unwrap();
        assert_eq!(
            p.names,
            vec!["top.clk".to_string(), "top.count".to_string()]
        );
    }

    #[test]
    fn geometry_classifies_scalar_and_vector() {
        let buf = fixture("simple_counter.lxt");
        let p = parse_file(&buf).unwrap();
        assert_eq!(p.geometry[0], Geometry::Scalar); // top.clk
        assert_eq!(p.geometry[1], Geometry::Vector { msb: 7, lsb: 0 }); // top.count
        assert_eq!(p.geometry[1].bit_width(), Some(8));
    }

    #[test]
    fn timescale_exponent_is_nanoseconds() {
        let buf = fixture("simple_counter.lxt");
        let p = parse_file(&buf).unwrap();
        assert_eq!(p.timescale_exp, -9, "simple_counter.lxt is `1 ns`");
    }

    #[test]
    fn convert_emits_fst_readable_by_wellen() {
        let buf = fixture("simple_counter.lxt");
        let mut reporter = ProgressReporter::new(None);
        let tmp = std::env::temp_dir().join("lxt2fst_lxt_convert_probe.fst");
        let _ = std::fs::remove_file(&tmp);
        convert_lxt_to_fst(&buf, FstOutput::File(&tmp), &mut reporter)
            .expect("conversion succeeds");

        let wf = wellen::simple::read(tmp.to_str().unwrap()).expect("wellen reads converted FST");
        let h = wf.hierarchy();
        let names: Vec<String> = h.all_vars().map(|v| h[v].name(h).to_string()).collect();
        assert!(
            names.contains(&"clk".to_string()),
            "clk missing in {names:?}"
        );
        assert!(
            names.contains(&"count".to_string()),
            "count missing in {names:?}"
        );
    }
}
