// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LXT2 per-facility value-change decoder.
//
// Clean-room: the granule/operator encoding decoded here was established
// empirically by *differential fuzzing* against GTKWave's own `vcd2lxt2`
// encoder — generate a random VCD, encode it with `vcd2lxt2`, decode it
// with this logic, and assert the round-trip reproduces the source VCD
// exactly. GTKWave's `lxt2_read.c` (GPLv2) was NOT consulted. The fuzz
// harness lives at `tool/lxt2_value_fuzz.py`; it validates this decoder
// against thousands of randomized inputs (every width, x/z states, reals,
// multi-facility, multi-granule).
//
// Decoded block-body layout (after gzip inflate):
//
//   [granule_0][granule_1]…[granule_{G-1}]  0x01  [literal blob]  [footer]
//
//   granule_g = u16 cnt                       — number of change-times
//               u64[cnt] times                — the change-time table
//               0x01                          — granule header marker
//               u8[num_facs] dict_idx         — per-facility bitmask index
//               0x01                          — header terminator
//               <ops>                         — facility-major op stream
//
//   footer    = u64[D] bitmask_dict           — distinct per-facility change
//               u32 _, u32 _, u32 D             bitmasks (LSB = earliest time)
//
// Per facility f in granule g, the change-bitmask is
// `bitmask_dict[dict_idx_g[f]]`; its population count is f's op count in
// that granule, and its set bits select which `times` entries changed.
// Literal ops index a shared, block-level ASCII blob whose codes increment
// in time-major emission order starting at 0x12.
//
// **Operator alphabet** (applied to the previous value of the facility):
//   0x00 set all-0      0x01 set all-1        0x02 complement (~, x/z→x)
//   0x03 «1            0x04 «1|1             0x05 »1        0x06 »1|MSB
//   0x07..0x0a +1..+4   0x0b..0x0e -1..-4
//   0x0f set all-x      0x10 set all-z        0x12+ literal MVL string
// Shifts/complement operate on the 4-state bit string (preserve x/z);
// the ±N deltas are integer arithmetic on a pure-binary value.
//
// The decoder is intentionally *strict*: any structural surprise (an
// unexpected delimiter, an out-of-range index, a malformed literal, a
// delta applied to an x/z value) returns `None` so the caller can fall
// back to a safe initial-value emission rather than risk emitting a wrong
// waveform. This is why the converter never corrupts a trace: it decodes
// only what it can prove, and falls back otherwise.

/// A facility's geometry width: `Some(bits)` for a bit-vector / scalar,
/// `None` for a variable-length (real / string) facility.
pub type FacWidth = Option<u32>;

/// Read a big-endian `u16` at `off`, or `None` if out of range.
fn be_u16(b: &[u8], off: usize) -> Option<u16> {
    b.get(off..off + 2)
        .map(|s| u16::from_be_bytes([s[0], s[1]]))
}

fn be_u32(b: &[u8], off: usize) -> Option<u32> {
    b.get(off..off + 4)
        .map(|s| u32::from_be_bytes([s[0], s[1], s[2], s[3]]))
}

fn be_u64(b: &[u8], off: usize) -> Option<u64> {
    b.get(off..off + 8)
        .map(|s| u64::from_be_bytes([s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7]]))
}

/// One parsed granule: its change-times plus the raw op stream and the
/// per-facility change bitmasks (already resolved through the dictionary).
struct Granule<'a> {
    times: Vec<u64>,
    dict_idx: &'a [u8],
    ops: &'a [u8],
}

/// Complement a single 4-state symbol (Verilog `~`: 0↔1, x→x, z→x).
fn complement_sym(c: u8) -> Option<u8> {
    match c {
        b'0' => Some(b'1'),
        b'1' => Some(b'0'),
        b'x' => Some(b'x'),
        b'z' => Some(b'x'),
        _ => None,
    }
}

/// Add `delta` (small, ±) to a pure-binary MVL string, width-preserving.
/// Returns `None` if the value contains x/z (delta is then undefined).
fn binary_delta(prev: &[u8], delta: i64) -> Option<Vec<u8>> {
    if prev.iter().any(|&c| c != b'0' && c != b'1') {
        return None;
    }
    let w = prev.len();
    // Ripple-add the integer `delta` (in [-4, 4]) onto the MSB-first bit
    // string so arbitrary widths work with no integer overflow. Leftover
    // carry wraps (mask to width) — matching vcd2lxt2 / VCD modular
    // semantics for an N-bit reg.
    let mut bits: Vec<i64> = prev.iter().map(|&c| (c - b'0') as i64).collect();
    let mut carry = delta;
    for i in (0..w).rev() {
        let total = bits[i] + carry;
        bits[i] = total.rem_euclid(2);
        carry = total.div_euclid(2);
    }
    Some(bits.iter().map(|&b| b'0' + b as u8).collect())
}

/// Left-extend a stored literal MVL string to `width` using the Verilog
/// VCD rule: fill with `x`/`z` when the value's leading symbol is `x`/`z`,
/// else `0`.
fn extend_literal(lit: &[u8], width: usize) -> Vec<u8> {
    if lit.is_empty() {
        return vec![b'0'; width];
    }
    if lit.len() >= width {
        return lit.to_vec();
    }
    let fill = match lit[0] {
        b'x' => b'x',
        b'z' => b'z',
        _ => b'0',
    };
    let mut out = vec![fill; width - lit.len()];
    out.extend_from_slice(lit);
    out
}

/// Decode the value-change region of one decompressed block body into a
/// per-facility list of `(time, value-string)` changes.
///
/// `prev` carries each facility's last value across blocks (and is updated
/// in place). Returns `None` if the block does not validate — the caller
/// should then leave `prev` untouched and fall back.
pub fn decode_block_values(
    body: &[u8],
    widths: &[FacWidth],
    prev: &mut [Vec<u8>],
) -> Option<Vec<Vec<(u64, String)>>> {
    let nf = widths.len();
    if body.len() < 12 {
        return None;
    }
    let d = be_u32(body, body.len() - 4)? as usize;
    let footer_size = 12 + d * 8;
    if d == 0 || footer_size > body.len() {
        return None;
    }
    let footer_start = body.len() - footer_size;
    let mut bitmask_dict = Vec::with_capacity(d);
    for i in 0..d {
        bitmask_dict.push(be_u64(body, footer_start + i * 8)?);
    }

    // ── parse granules ────────────────────────────────────────────────
    let mut granules: Vec<Granule> = Vec::new();
    let mut cur = 0usize;
    while cur < footer_start {
        let cnt = match be_u16(body, cur) {
            Some(c) => c as usize,
            None => break,
        };
        // A real granule's time count is in [1, 64]; anything else means we
        // have reached the trailing `0x01` + literal-blob region.
        if !(1..=64).contains(&cnt) {
            break;
        }
        let tend = cur + 2 + cnt * 8;
        if tend + 1 > footer_start {
            break;
        }
        if body.get(tend) != Some(&0x01) {
            break;
        }
        let mut times = Vec::with_capacity(cnt);
        for i in 0..cnt {
            times.push(be_u64(body, cur + 2 + i * 8)?);
        }
        let di_start = tend + 1;
        let dict_idx = body.get(di_start..di_start + nf)?;
        if body.get(di_start + nf) != Some(&0x01) {
            // Unrecognised header terminator (e.g. the high-facility
            // variant we have not fully decoded). Fail safe.
            return None;
        }
        if dict_idx.iter().any(|&x| x as usize >= d) {
            return None;
        }
        let op_count: usize = (0..nf)
            .map(|f| bitmask_dict[dict_idx[f] as usize].count_ones() as usize)
            .sum();
        let op_start = di_start + nf + 1;
        if op_start + op_count > footer_start {
            return None;
        }
        let ops = body.get(op_start..op_start + op_count)?;
        granules.push(Granule {
            times,
            dict_idx,
            ops,
        });
        cur = op_start + op_count;
    }

    // ── shared literal blob (after the granules, before the footer) ─────
    if body.get(cur) != Some(&0x01) {
        return None;
    }
    let blob = body.get(cur + 1..footer_start)?;
    let mut lits: Vec<&[u8]> = Vec::new();
    let mut p = 0usize;
    while p < blob.len() {
        let e = blob[p..].iter().position(|&b| b == 0)? + p;
        let s = &blob[p..e];
        if !s.iter().all(|&c| c.is_ascii()) {
            return None;
        }
        lits.push(s);
        p = e + 1;
    }

    // ── decode each granule, facility-major, carrying prev ──────────────
    let mut out: Vec<Vec<(u64, String)>> = vec![Vec::new(); nf];
    for g in &granules {
        let mut oi = 0usize;
        for f in 0..nf {
            let w = widths[f];
            let bm = bitmask_dict[g.dict_idx[f] as usize];
            let pv = &mut prev[f];
            for (ti, &time) in g.times.iter().enumerate() {
                if (bm >> ti) & 1 == 0 {
                    continue;
                }
                let op = *g.ops.get(oi)?;
                oi += 1;
                let new: Vec<u8> = match w {
                    None => {
                        // variable-length (real / string): literal text, or
                        // a repeat (0x01) of the previous value.
                        if op >= 0x12 {
                            lits.get((op - 0x12) as usize)?.to_vec()
                        } else if op == 0x01 {
                            pv.clone()
                        } else {
                            return None;
                        }
                    }
                    Some(width) => {
                        let width = width as usize;
                        match op {
                            0x00 => vec![b'0'; width],
                            0x01 => vec![b'1'; width],
                            0x02 => {
                                let mut v = Vec::with_capacity(width);
                                for &c in pv.iter() {
                                    v.push(complement_sym(c)?);
                                }
                                v
                            }
                            0x03 => {
                                if pv.len() != width || width == 0 {
                                    return None;
                                }
                                let mut v = pv[1..].to_vec();
                                v.push(b'0');
                                v
                            }
                            0x04 => {
                                if pv.len() != width || width == 0 {
                                    return None;
                                }
                                let mut v = pv[1..].to_vec();
                                v.push(b'1');
                                v
                            }
                            0x05 => {
                                if pv.len() != width || width == 0 {
                                    return None;
                                }
                                let mut v = vec![b'0'];
                                v.extend_from_slice(&pv[..width - 1]);
                                v
                            }
                            0x06 => {
                                if pv.len() != width || width == 0 {
                                    return None;
                                }
                                let mut v = vec![b'1'];
                                v.extend_from_slice(&pv[..width - 1]);
                                v
                            }
                            0x07..=0x0a => binary_delta(pv, (op - 0x06) as i64)?,
                            0x0b..=0x0e => binary_delta(pv, -((op - 0x0a) as i64))?,
                            0x0f => vec![b'x'; width],
                            0x10 => vec![b'z'; width],
                            0x12..=0xff => extend_literal(lits.get((op - 0x12) as usize)?, width),
                            _ => return None,
                        }
                    }
                };
                if matches!(w, Some(width) if new.len() != width as usize) {
                    return None;
                }
                let s = String::from_utf8(new.clone()).ok()?;
                out[f].push((time, s));
                *pv = new;
            }
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn binary_delta_increments_and_wraps() {
        assert_eq!(binary_delta(b"00000000", 1).unwrap(), b"00000001");
        assert_eq!(binary_delta(b"00000001", 1).unwrap(), b"00000010");
        assert_eq!(binary_delta(b"11111111", 1).unwrap(), b"00000000"); // wrap
        assert_eq!(binary_delta(b"00000010", -1).unwrap(), b"00000001");
        assert_eq!(binary_delta(b"00000000", -1).unwrap(), b"11111111"); // wrap
        assert_eq!(binary_delta(b"00000101", 2).unwrap(), b"00000111");
        assert!(binary_delta(b"0000x001", 1).is_none()); // x/z → undefined
    }

    #[test]
    fn extend_literal_uses_vcd_fill_rule() {
        assert_eq!(extend_literal(b"x1z", 4), b"xx1z"); // leading x → x-fill
        assert_eq!(extend_literal(b"0x", 4), b"000x"); // leading 0 → 0-fill
        assert_eq!(extend_literal(b"1x0z", 8), b"00001x0z"); // leading 1 → 0-fill
        assert_eq!(extend_literal(b"", 3), b"000"); // empty → zero
        assert_eq!(extend_literal(b"zz00", 4), b"zz00"); // full width
    }

    #[test]
    fn complement_handles_four_state() {
        assert_eq!(complement_sym(b'0'), Some(b'1'));
        assert_eq!(complement_sym(b'1'), Some(b'0'));
        assert_eq!(complement_sym(b'x'), Some(b'x'));
        assert_eq!(complement_sym(b'z'), Some(b'x'));
        assert_eq!(complement_sym(b'q'), None);
    }
}
