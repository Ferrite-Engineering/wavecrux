#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

"""Differential fuzzer + reference decoder for the LXT-classic value codec.

This is the clean-room validation backbone for
`native/lxt2fst/src/lxt_value_decode.rs`. GTKWave's `lxt_read.c` (GPLv2) is
NEVER consulted. Instead the codec was reverse-engineered, and is continuously
validated, *differentially* against GTKWave's own `vcd2lxt` *encoder* (a
dev-machine tool, never shipped — the same dependency the fixture regenerator
uses):

    random VCD  --vcd2lxt-->  .lxt  --this decoder-->  values
    assert decoded values == the random VCD's values

The Python reference decoder below mirrors the Rust implementation
(`lxt_value_decode.rs`) byte for byte: the `[op][facref][value]` record framing,
the multi-byte back-pointer (`1 + (op>>4)` big-endian facref bytes), the
per-facility chain-head table, the operator alphabet (binary/4-state literals,
all-0/1/z/x), little-endian f64 reals, and the per-timestep time index. Run it
whenever the Rust decoder changes:

    python3 tool/lxt_classic_value_fuzz.py            # fuzz + check committed fixtures
    python3 tool/lxt_classic_value_fuzz.py --trials 20000

Requires `vcd2lxt` on PATH (`brew install gtkwave` / distro `gtkwave`).

LXT-classic is a *streaming* codec, distinct from LXT2's block/granule codec —
see `tool/lxt2_value_fuzz.py` for that format's validator.
"""
import argparse
import os
import random
import struct
import subprocess
import sys
import zlib


# ── structural parse ─────────────────────────────────────────────────────────

def _gunzip_at(buf, off):
    d = zlib.decompressobj(31)
    out = d.decompress(buf[off:])
    return out, len(buf[off:]) - len(d.unused_data)


def _gzip_members(buf):
    sig = bytes([0x1f, 0x8b, 0x08])
    pos, m = 2, []
    while True:
        i = buf.find(sig, pos)
        if i < 0:
            break
        m.append(i)
        pos = i + 1
    return m


def _u32s(b):
    return [struct.unpack(">I", b[i:i + 4])[0] for i in range(0, len(b) - 3, 4)]


def parse_struct(buf):
    """Return (nf, names, widths, max_time, A, D, record_region, chain_heads)."""
    m = _gzip_members(buf)
    nb, _ = _gunzip_at(buf, m[0])           # NAMES (prefix-compressed, alphabetical)
    gb, _ = _gunzip_at(buf, m[1])           # GEOMETRY (16 bytes/facility)
    nf = len(gb) // 16
    geoms = [struct.unpack(">iiiI", gb[i * 16:i * 16 + 16]) for i in range(nf)]
    widths = [
        None if (fl & 2) else (1 if (r == 0 and ms == -1 and ls == -1) else abs(ms - ls) + 1)
        for (r, ms, ls, fl) in geoms
    ]
    names, prev, p = [], "", 0
    while len(names) < nf:
        pr = struct.unpack(">H", nb[p:p + 2])[0]
        p += 2
        e = nb.index(0, p)
        names.append(prev[:pr] + nb[p:e].decode())
        prev = names[-1]
        p = e + 1
    heads = _u32s(_gunzip_at(buf, m[-2])[0])   # per-facility chain-head FILE offsets
    idx, _ = _gunzip_at(buf, m[-1])            # index: max_time + timestep tables
    max_time = struct.unpack(">Q", idx[:8])[0]
    lst = _u32s(idx[8:])
    T = len(lst) // 2
    A = lst[1:1 + T]                           # per-timestep record-group byte lengths
    D = lst[1 + T:]                            # inter-timestep time deltas (T-1)
    reg = buf[4:m[0] - 8]                       # record region (after the 8-byte NAMES framing)
    return nf, names, widths, max_time, A, D, reg, heads


# ── value-change decode ──────────────────────────────────────────────────────

def _read_record(reg, o, w):
    """Decode the record at region offset `o` (width `w`).

    Returns (prev_offset_or_None, value, byte_len) or None on a structural miss.
    """
    opb = reg[o]
    op = opb & 0x0f
    fb = 1 + (opb >> 4)
    if fb > 4:
        return None
    facref = int.from_bytes(reg[o + 1:o + 1 + fb], "big")
    hlen = 1 + fb
    sp = o - facref - 2
    prev = None if sp == -4 else (sp if sp >= 0 else "bad")
    if prev == "bad":
        return None
    if w is None:
        if op != 0x00:
            return None
        val = struct.unpack("<d", reg[o + hlen:o + hlen + 8])[0]
        return prev, val, hlen + 8
    nbytes = (w + 7) // 8
    if op == 0x03:
        return prev, "0" * w, hlen
    if op == 0x04:
        return prev, "1" * w, hlen
    if op == 0x05:
        return prev, "z" * w, hlen
    if op == 0x06:
        return prev, "x" * w, hlen
    if op == 0x00:
        num = int.from_bytes(reg[o + hlen:o + hlen + nbytes], "big") >> (nbytes * 8 - w)
        return prev, format(num, f"0{w}b"), hlen + nbytes
    if op == 0x01:
        nb2 = (2 * w + 7) // 8
        num = int.from_bytes(reg[o + hlen:o + hlen + nb2], "big") >> (nb2 * 8 - 2 * w)
        syms = "01zx"
        val = "".join(syms[(num >> (2 * (w - 1 - j))) & 3] for j in range(w))
        return prev, val, hlen + nb2
    return None


def decode(path):
    """Decode `path` to (names, widths, {fac_index: [(time, value), ...]})."""
    buf = open(path, "rb").read()
    nf, names, widths, max_time, A, D, reg, heads = parse_struct(buf)
    if len(heads) != nf:
        return names, widths, None
    times = [0]
    for d in D:
        times.append(times[-1] + d)
    T = len(A)
    bounds, pos = [], 0
    for k in range(T):
        ln = A[k] if k < T - 1 else (len(reg) - pos)
        bounds.append((pos, pos + ln, times[k]))
        pos += ln

    def time_of(o):
        for s, e, t in bounds:
            if s <= o < e:
                return t
        return None

    out = {f: [] for f in range(nf)}
    for f in range(nf):
        o = heads[f] - 4               # file offset -> region offset
        seen, chain = set(), []
        while o is not None:
            if o < 0 or o >= len(reg) or o in seen:
                return names, widths, None
            seen.add(o)
            r = _read_record(reg, o, widths[f])
            if r is None:
                return names, widths, None
            prev, val, _ = r
            t = time_of(o)
            if t is None:
                return names, widths, None
            chain.append((t, val))
            o = prev
        out[f] = list(reversed(chain))
    return names, widths, out


# ── differential fuzz ────────────────────────────────────────────────────────

def _vcd_id(n):
    ids = [chr(c) for c in range(33, 127)]
    s, m = "", n
    while True:
        s = ids[m % 94] + s
        m //= 94
        if m == 0:
            return s


def _write_vcd(path, decls, frames, real_ids):
    with open(path, "w") as f:
        f.write("$timescale 1 ns $end\n$scope module top $end\n")
        for vt, w, i, n in decls:
            f.write(f"$var {vt} {w} {i} {n} $end\n")
        f.write("$upscope $end\n$enddefinitions $end\n")
        for ti, (t, ch) in enumerate(frames):
            f.write("$dumpvars\n" if ti == 0 else f"#{t}\n")
            for i, v in ch.items():
                if i in real_ids:
                    f.write(f"r{v} {i}\n")
                else:
                    f.write(f"{v}{i}\n" if len(v) == 1 else f"b{v} {i}\n")
            if ti == 0:
                f.write("$end\n")


def fuzz(trials, seed):
    random.seed(seed)
    ok = total = wrong = fb = 0
    pool = [1, 1, 1, 2, 3, 4, 5, 7, 8, 12, 16, 17, 31, 32, 33, 64]
    for _ in range(trials):
        k = random.randint(1, random.choice([3, 8, 30, 120]))
        kinds = [("real", 0) if random.random() < 0.15 else ("wire", random.choice(pool))
                 for _ in range(k)]
        decls = [(kt, (w or 1), _vcd_id(i), f"s{i}") for i, (kt, w) in enumerate(kinds)]
        real_ids = {_vcd_id(i) for i, (kt, _) in enumerate(kinds) if kt == "real"}
        xz = random.random() < 0.5
        nt = random.randint(2, random.choice([5, 20, 60]))
        gap = random.choice([1, 7, 10, 1000])
        truth = {i: [] for i in range(k)}
        frames, cur = [], {}
        for fi in range(nt):
            ch = {}
            for i, (kt, w) in enumerate(kinds):
                if fi == 0 or random.random() < 0.4:
                    if kt == "real":
                        v = random.choice(["1.5", "-2.25", "3.0", "0.0", "1e10", "-0.125", "42.0"])
                    else:
                        al = "01xz" if xz else "01"
                        v = "".join(random.choice(al) for _ in range(w))
                    if cur.get(i) != v:
                        ch[_vcd_id(i)] = v
                        truth[i].append((fi * gap, v))
                        cur[i] = v
            if fi == 0:
                for i, (kt, w) in enumerate(kinds):
                    if i not in cur:
                        v = "0.0" if kt == "real" else "0" * w
                        ch[_vcd_id(i)] = v
                        truth[i].append((0, v))
                        cur[i] = v
            if ch:
                frames.append((fi * gap, ch))
        if len(frames) < 2:
            continue
        try:
            _write_vcd("/tmp/_lxtfuzz.vcd", decls, frames, real_ids)
            subprocess.run(["vcd2lxt", "/tmp/_lxtfuzz.vcd", "/tmp/_lxtfuzz.lxt"],
                           check=True, capture_output=True)
            names, _, dec = decode("/tmp/_lxtfuzz.lxt")
        except subprocess.CalledProcessError:
            continue
        total += 1
        if dec is None:
            fb += 1
            continue
        byname = {names[i]: i for i in range(len(names))}

        def norm(i, lst):
            return [(t, float(v)) for t, v in lst] if kinds[i][0] == "real" else lst

        exact = all(dec.get(byname[f"top.s{i}"], []) == norm(i, truth[i]) for i in range(k))
        ok += exact
        for i in range(k):
            got = dict(dec.get(byname[f"top.s{i}"], []))
            tr = dict(norm(i, truth[i]))
            for t, v in got.items():
                if tr.get(t) != v:
                    wrong += 1
    return ok, total, wrong, fb


def check_fixtures():
    import json
    root = os.path.join(os.path.dirname(__file__), "..", "test", "fixtures", "legacy")
    failures = 0
    for fx in ["simple_counter"]:
        lxt = os.path.join(root, f"{fx}.lxt")
        exp = os.path.join(root, f"{fx}.expected.json")
        if not (os.path.exists(lxt) and os.path.exists(exp)):
            continue
        names, widths, dec = decode(lxt)
        if dec is None:
            print(f"  {fx}: DECODE FAILED")
            failures += 1
            continue
        signals = json.load(open(exp))["signals"]
        byname = {names[i]: i for i in range(len(names))}
        ok = bad = 0
        for sig, info in signals.items():
            fi = byname.get(sig)
            if fi is None:
                continue
            got = {t: v for t, v in dec[fi]}
            for ch in info["allChanges"]:
                want, g = ch["value"], got.get(ch["time"])
                same = g == want
                if not same and g is not None:
                    try:
                        same = abs(float(g) - float(want)) < 1e-9
                    except ValueError:
                        same = False
                ok += same
                bad += not same
        print(f"  {fx}: {ok} ok, {bad} bad")
        failures += bad
    return failures


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--trials", type=int, default=3000)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()

    if subprocess.run(["which", "vcd2lxt"], capture_output=True).returncode != 0:
        print("vcd2lxt not found on PATH (brew install gtkwave). Skipping fuzz.")
        sys.exit(0)

    print("Committed-fixture value equivalence:")
    fixture_bad = check_fixtures()
    print(f"\nDifferential fuzz ({args.trials} trials, seed {args.seed}):")
    ok, total, wrong, fb = fuzz(args.trials, args.seed)
    print(f"  exact={ok}/{total}  fallback={fb}  wrong-values={wrong}")
    # The hard invariant: the decoder must NEVER emit a wrong value. Exact
    # coverage <100% is acceptable (an unvalidated structure falls back safely
    # in the Rust converter), but a single wrong value is a bug.
    if wrong or fixture_bad:
        print("FAIL: decoder emitted incorrect values")
        sys.exit(1)
    print("OK: no incorrect values")


if __name__ == "__main__":
    main()
