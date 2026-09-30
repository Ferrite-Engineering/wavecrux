// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LXT-classic per-facility value-change decoder.
//
// Clean-room: the streaming value codec decoded here was established
// empirically by *differential fuzzing* against GTKWave's own `vcd2lxt`
// encoder — generate a random VCD, encode it with `vcd2lxt`, decode it with
// this logic, and assert the round-trip reproduces the source VCD exactly.
// GTKWave's `lxt_read.c` (GPLv2) was NOT consulted — not as source, not as a
// source of constants. The fuzz harness lives at `tool/lxt_classic_value_fuzz.py`;
// it validates this decoder against thousands of randomized inputs (every
// width, x/z states, reals, multi-facility, >256-byte back-pointers).
//
// LXT-classic is a *streaming* codec, distinct from LXT2's block/granule codec
// (`value_decode.rs`). The wire model, in full:
//
//   * **Record** = `[op-byte][facref][value bytes]`.
//       - `op = op_byte & 0x0f` selects the value operator.
//       - `facref` is a big-endian back-pointer occupying `1 + (op_byte >> 4)`
//         bytes (so a back-distance ≥ 256 sets the `0x10` flag and uses 2
//         bytes, ≥ 65536 sets `0x20` and uses 3, …).
//   * **Back-pointer**: a record at region byte-offset `O` whose facref is `r`
//     links to its facility's previous change record at `O - r - 2`. The
//     sentinel value `-4` (i.e. `r == O + 2`) marks the *oldest* record in a
//     facility's chain.
//   * **Chain heads**: the next-to-last gzip section is a `u32[num_facs]` table
//     of the *file* offset of each facility's most-recent change record,
//     indexed by the (alphabetical) geometry/name index. Walking each chain
//     backward via the facref links recovers that facility's changes
//     newest-first — and resolves facility identity exactly (the inline stream
//     itself is emitted in VCD-declaration order, which need not match the
//     alphabetical name index).
//   * **Operators** (applied per record):
//       0x00 binary literal — `ceil(w/8)` big-endian bytes, MSB-left-justified.
//       0x01 4-state literal — `ceil(2w/8)` bytes, 2 bits/symbol
//            (00→'0', 01→'1', 10→'z', 11→'x'), MSB-justified.
//       0x03 all-'0'   0x04 all-'1'   0x05 all-'z'   0x06 all-'x'.
//     A variable-length (real) facility uses 0x00 followed by an 8-byte
//     *little-endian* IEEE-754 f64.
//   * **Times** live in the last gzip section (the index): `u64 max_time`,
//     `u32 stream_offset`, `u32[T]` per-timestep record-group byte lengths
//     (last entry 0), then `u32[T-1]` inter-timestep time deltas. Records are
//     laid out contiguously per timestep group, so a record's offset selects
//     its timestep, hence its absolute time.
//
// The decoder is intentionally *strict*: any structural surprise (an unknown
// operator, an out-of-range back-pointer, a chain cycle, a head-count mismatch,
// a record offset with no timestep) returns `None`, so the converter falls back
// to a safe `x`-state emission rather than risk a wrong waveform. This is why a
// converted `.lxt` is never silently wrong — it decodes only what it can prove.

use crate::value_decode::FacWidth;

fn be_u64(b: &[u8], off: usize) -> Option<u64> {
    b.get(off..off + 8)
        .map(|s| u64::from_be_bytes([s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7]]))
}

/// Read a `u32` array out of a section blob (whole multiples of 4 bytes).
fn u32_array(blob: &[u8]) -> Vec<u32> {
    (0..blob.len() / 4)
        .map(|i| {
            u32::from_be_bytes([
                blob[i * 4],
                blob[i * 4 + 1],
                blob[i * 4 + 2],
                blob[i * 4 + 3],
            ])
        })
        .collect()
}

/// One decoded record: its predecessor's region offset (or `None` at the chain
/// start) and the value string. The record's byte length is not needed — the
/// chain is walked backward via `prev`, never forward.
struct Record {
    prev: Option<usize>,
    value: String,
}

/// Decode the record at region offset `O` for facility `f` (width `w`).
fn read_record(reg: &[u8], o: usize, w: FacWidth) -> Option<Record> {
    let op_byte = *reg.get(o)?;
    let op = op_byte & 0x0f;
    let fb = 1 + (op_byte >> 4) as usize;
    if fb > 4 {
        return None;
    }
    let facref = {
        let bytes = reg.get(o + 1..o + 1 + fb)?;
        let mut v = 0u64;
        for &b in bytes {
            v = (v << 8) | b as u64;
        }
        v
    };
    let hlen = 1 + fb;
    // prev = O - facref - 2; sentinel -4 ⇒ chain start.
    let signed_prev = o as i64 - facref as i64 - 2;
    let prev = if signed_prev == -4 {
        None
    } else if signed_prev >= 0 {
        Some(signed_prev as usize)
    } else {
        return None;
    };

    let (value, _len) = match w {
        None => {
            // variable-length (real): 0x00 + 8-byte little-endian f64.
            if op != 0x00 {
                return None;
            }
            let raw = reg.get(o + hlen..o + hlen + 8)?;
            let f = f64::from_le_bytes([
                raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
            ]);
            (format_real(f), hlen + 8)
        }
        Some(width) => {
            let w = width as usize;
            if w == 0 {
                return None;
            }
            match op {
                0x03 => ("0".repeat(w), hlen),
                0x04 => ("1".repeat(w), hlen),
                0x05 => ("z".repeat(w), hlen),
                0x06 => ("x".repeat(w), hlen),
                0x00 => {
                    let nbytes = w.div_ceil(8);
                    let raw = reg.get(o + hlen..o + hlen + nbytes)?;
                    (bits_msb_justified(raw, w), hlen + nbytes)
                }
                0x01 => {
                    let nb2 = (2 * w).div_ceil(8);
                    let raw = reg.get(o + hlen..o + hlen + nb2)?;
                    (four_state_msb_justified(raw, w), hlen + nb2)
                }
                _ => return None,
            }
        }
    };
    Some(Record { prev, value })
}

/// Decode a binary literal: the value's `w` bits occupy the top `w` bits of the
/// big-endian byte slice (`ceil(w/8)` bytes), MSB first.
fn bits_msb_justified(raw: &[u8], w: usize) -> String {
    let mut s = String::with_capacity(w);
    for j in 0..w {
        // MSB-justified: the j-th value bit (MSB first) is the j-th bit from
        // the top of the slice.
        let bit = (raw[j / 8] >> (7 - (j % 8))) & 1;
        s.push(if bit == 1 { '1' } else { '0' });
    }
    s
}

/// Decode a 4-state literal: `w` symbols of 2 bits each, MSB-justified in the
/// big-endian byte slice (`ceil(2w/8)` bytes). 00→'0' 01→'1' 10→'z' 11→'x'.
fn four_state_msb_justified(raw: &[u8], w: usize) -> String {
    const SYMS: [char; 4] = ['0', '1', 'z', 'x'];
    let mut s = String::with_capacity(w);
    for j in 0..w {
        // MSB-justified: symbol j (MSB first) occupies the two bits at offsets
        // 2j and 2j+1 from the top of the slice.
        let hi_pos = 2 * j;
        let lo_pos = 2 * j + 1;
        let hi = (raw[hi_pos / 8] >> (7 - (hi_pos % 8))) & 1;
        let lo = (raw[lo_pos / 8] >> (7 - (lo_pos % 8))) & 1;
        s.push(SYMS[((hi << 1) | lo) as usize]);
    }
    s
}

/// Format an f64 as the ASCII decimal the FST real path parses back (shortest
/// round-tripping representation). NaN/inf fall back to `"nan"` to match the
/// writer's non-numeric handling.
fn format_real(f: f64) -> String {
    if f.is_finite() {
        format!("{f}")
    } else {
        "nan".to_string()
    }
}

/// Decode all per-facility value changes from an LXT-classic file.
///
/// `buf` is the whole file, `sections` the inflated trailing gzip members in
/// stream order (as produced by `lxt::enumerate_sections`: `[NAMES, GEOMETRY,
/// …, chain_heads, index]`), and `widths` the per-facility geometry widths.
/// Returns `None` (caller falls back to a safe `x`-state emission) on any
/// structural mismatch — the decoder never emits a guessed value.
pub fn decode_values(
    buf: &[u8],
    sections: &[(usize, Vec<u8>)],
    widths: &[FacWidth],
) -> Option<Vec<Vec<(u64, String)>>> {
    let nf = widths.len();
    if sections.len() < 4 {
        return None;
    }
    let first_gzip = sections[0].0;
    // Record region: after the 2-byte magic + 2-byte header, up to the 8-byte
    // NAMES section framing ([u32 num_facs][u32 names_inflated_len]) that
    // immediately precedes the first gzip member.
    if first_gzip < 12 {
        return None;
    }
    let reg = buf.get(4..first_gzip - 8)?;

    // Chain heads (next-to-last section): file offset of each facility's most
    // recent change record, indexed by alphabetical geometry index.
    let heads = u32_array(&sections[sections.len() - 2].1);
    if heads.len() != nf {
        return None;
    }

    // Index (last section): max_time, stream_offset, per-timestep byte lengths,
    // time deltas.
    let index = &sections[sections.len() - 1].1;
    let _max_time = be_u64(index, 0)?;
    let after = u32_array(index.get(8..)?);
    if after.is_empty() {
        return None;
    }
    let total = after.len();
    if !total.is_multiple_of(2) {
        return None;
    }
    let t = total / 2; // number of timesteps
    // after = [stream_offset, A[0..T], D[0..T-1]]
    let a = &after[1..1 + t];
    let d = &after[1 + t..];
    if d.len() + 1 != t {
        return None;
    }

    // Absolute times per timestep (cumulative deltas from 0).
    let mut times = Vec::with_capacity(t);
    let mut acc = 0u64;
    times.push(0u64);
    for &delta in d {
        acc = acc.checked_add(delta as u64)?;
        times.push(acc);
    }

    // Timestep byte-group boundaries within the record region.
    let mut bounds: Vec<(usize, usize, u64)> = Vec::with_capacity(t);
    let mut pos = 0usize;
    for k in 0..t {
        let len = if k < t - 1 {
            a[k] as usize
        } else {
            reg.len().checked_sub(pos)?
        };
        let end = pos.checked_add(len)?;
        if end > reg.len() {
            return None;
        }
        bounds.push((pos, end, times[k]));
        pos = end;
    }
    let time_of = |o: usize| -> Option<u64> {
        bounds
            .iter()
            .find(|&&(s, e, _)| s <= o && o < e)
            .map(|&(_, _, tm)| tm)
    };

    // Walk each facility's back-pointer chain from its head, newest → oldest.
    let mut out: Vec<Vec<(u64, String)>> = vec![Vec::new(); nf];
    for f in 0..nf {
        let head = heads[f] as usize;
        let mut o = head.checked_sub(4)?; // file offset → region offset
        let mut seen = std::collections::HashSet::new();
        let mut chain: Vec<(u64, String)> = Vec::new();
        loop {
            if o >= reg.len() || !seen.insert(o) {
                return None;
            }
            let rec = read_record(reg, o, widths[f])?;
            let tm = time_of(o)?;
            chain.push((tm, rec.value));
            match rec.prev {
                Some(p) => o = p,
                None => break,
            }
        }
        chain.reverse();
        out[f] = chain;
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bits_msb_justified_handles_widths() {
        assert_eq!(bits_msb_justified(&[0xab], 8), "10101011");
        assert_eq!(bits_msb_justified(&[0x50], 4), "0101"); // 0x5 left-justified
        assert_eq!(bits_msb_justified(&[0xab, 0xc0], 12), "101010111100");
        assert_eq!(bits_msb_justified(&[0x80], 1), "1");
        assert_eq!(bits_msb_justified(&[0x00], 1), "0");
    }

    #[test]
    fn four_state_decodes_symbols() {
        // 4-bit "x0x0" -> 11 00 11 00 = 0xcc
        assert_eq!(four_state_msb_justified(&[0xcc], 4), "x0x0");
        // "1z1z" -> 01 10 01 10 = 0x66
        assert_eq!(four_state_msb_justified(&[0x66], 4), "1z1z");
        // "000x" -> 00 00 00 11 = 0x03
        assert_eq!(four_state_msb_justified(&[0x03], 4), "000x");
        // 8-bit "10xz10xz" -> 0x4e 0x4e
        assert_eq!(four_state_msb_justified(&[0x4e, 0x4e], 8), "10xz10xz");
    }

    #[test]
    fn format_real_round_trips() {
        assert_eq!(format_real(1.5), "1.5");
        assert_eq!(format_real(-2.25), "-2.25");
        assert_eq!(format_real(0.0), "0");
        assert_eq!(format_real(f64::NAN), "nan");
    }
}
