#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

"""Differential fuzzer + reference decoder for the LXT2 value-change codec.

This is the clean-room validation backbone for `native/lxt2fst/src/value_decode.rs`.
GTKWave's `lxt2_read.c` (GPLv2) is NEVER consulted. Instead the codec was
reverse-engineered, and is continuously validated, *differentially* against
GTKWave's own `vcd2lxt2` *encoder* (a dev-machine tool, never shipped — same
dependency the fixture regenerator uses):

    random VCD  --vcd2lxt2-->  .lxt2  --this decoder-->  values
    assert decoded values == the random VCD's values

The Python reference decoder below mirrors the Rust implementation byte for
byte (operator alphabet, multi-granule framing, footer bitmask dictionary,
x/z fill rule, real handling). Run it whenever the Rust decoder changes:

    python3 tool/lxt2_value_fuzz.py            # fuzz + check committed fixtures
    python3 tool/lxt2_value_fuzz.py --trials 20000

Requires `vcd2lxt2` on PATH (`brew install gtkwave` / distro `gtkwave`).
"""
import argparse
import os
import random
import struct
import subprocess
import sys
import zlib


def gunzip_at(buf, off):
    d = zlib.decompressobj(31)
    out = d.decompress(buf[off:])
    return out, len(buf[off:]) - len(d.unused_data)


def parse(path):
    buf = open(path, "rb").read()
    nf = struct.unpack(">I", buf[5:9])[0]
    off = 30
    nb, nc = gunzip_at(buf, off)
    off += nc
    gb, gc = gunzip_at(buf, off)
    off += gc
    names, prev, p = [], "", 0
    while len(names) < nf:
        pr = struct.unpack(">H", nb[p:p + 2])[0]
        p += 2
        e = nb.index(0, p)
        names.append(prev[:pr] + nb[p:e].decode())
        prev = names[-1]
        p = e + 1
    geoms = [struct.unpack(">iiiI", gb[i * 16:i * 16 + 16]) for i in range(nf)]
    widths = [
        None if (fl & 2) else (1 if (r == 0 and m == -1 and l == -1) else abs(m - l) + 1)
        for (r, m, l, fl) in geoms
    ]
    blocks = []
    while off + 24 <= len(buf):
        _, clen = struct.unpack(">II", buf[off:off + 8])
        body, _ = gunzip_at(buf, off + 24)
        off += 24 + clen
        blocks.append(body)
    return nf, names, widths, blocks


_CPL = {"0": "1", "1": "0", "x": "x", "z": "x"}


def _decode_block(nf, widths, body, prev):
    if len(body) < 12:
        return None
    d = struct.unpack(">I", body[-4:])[0]
    fsize = 12 + d * 8
    if d == 0 or fsize > len(body):
        return None
    fstart = len(body) - fsize
    bm = [struct.unpack(">Q", body[fstart + i * 8:fstart + i * 8 + 8])[0] for i in range(d)]
    cur, granules = 0, []
    while cur < fstart:
        if cur + 2 > fstart:
            break
        cnt = struct.unpack(">H", body[cur:cur + 2])[0]
        if not 1 <= cnt <= 64:
            break
        tend = cur + 2 + cnt * 8
        if tend + 1 > fstart or body[tend] != 1:
            break
        times = [struct.unpack(">Q", body[cur + 2 + i * 8:cur + 10 + i * 8])[0] for i in range(cnt)]
        di = list(body[tend + 1:tend + 1 + nf])
        if body[tend + 1 + nf] != 1 or any(x >= d for x in di):
            return None
        op_start = tend + 2 + nf
        op_count = sum(bin(bm[di[f]]).count("1") for f in range(nf))
        if op_start + op_count > fstart:
            return None
        granules.append((times, di, body[op_start:op_start + op_count]))
        cur = op_start + op_count
    if cur >= fstart or body[cur] != 1:
        return None
    blob, lits, p = body[cur + 1:fstart], [], 0
    while p < len(blob):
        e = blob.find(0, p)
        if e < 0:
            return None
        lits.append(blob[p:e].decode("ascii", "strict"))
        p = e + 1
    out = {f: [] for f in range(nf)}
    for times, di, ops in granules:
        oi = 0
        for f in range(nf):
            w = widths[f]
            b = bm[di[f]]
            pv = prev[f]
            for ti in [i for i in range(len(times)) if (b >> i) & 1]:
                op = ops[oi]
                oi += 1
                if w is None:
                    vs = lits[op - 0x12] if op >= 0x12 else pv
                elif op == 0x00:
                    vs = "0" * w
                elif op == 0x01:
                    vs = "1" * w
                elif op == 0x02:
                    vs = "".join(_CPL[c] for c in pv)
                elif op == 0x03:
                    vs = pv[1:] + "0"
                elif op == 0x04:
                    vs = pv[1:] + "1"
                elif op == 0x05:
                    vs = "0" + pv[:-1]
                elif op == 0x06:
                    vs = "1" + pv[:-1]
                elif op == 0x0f:
                    vs = "x" * w
                elif op == 0x10:
                    vs = "z" * w
                elif 0x07 <= op <= 0x0e:
                    delta = (op - 0x06) if op <= 0x0a else -(op - 0x0a)
                    vs = format((int(pv, 2) + delta) & ((1 << w) - 1), f"0{w}b")
                elif op >= 0x12:
                    lit = lits[op - 0x12]
                    fill = "x" if lit[:1] == "x" else ("z" if lit[:1] == "z" else "0")
                    vs = (fill * (w - len(lit)) + lit) if lit else "0" * w
                else:
                    return None
                out[f].append((times[ti], vs))
                pv = vs
            prev[f] = pv
    return out


def decode(path):
    nf, names, widths, blocks = parse(path)
    prev = ["0" * (widths[f] or 1) for f in range(nf)]
    allc = {f: [] for f in range(nf)}
    for body in blocks:
        snap = list(prev)
        r = _decode_block(nf, widths, body, prev)
        if r is None:
            prev[:] = snap
            continue
        for f in range(nf):
            allc[f].extend(r[f])
    return names, widths, allc


# ── differential fuzz ───────────────────────────────────────────────────────

def _write_vcd(path, decls, frames):
    with open(path, "w") as f:
        f.write("$timescale 1 ns $end\n$scope module top $end\n")
        for vt, w, i, n in decls:
            f.write(f"$var {vt} {w} {i} {n} $end\n")
        f.write("$upscope $end\n$enddefinitions $end\n")
        for ti, (t, ch) in enumerate(frames):
            f.write("$dumpvars\n" if ti == 0 else f"#{t}\n")
            for i, v in ch.items():
                f.write(f"{v}{i}\n" if len(v) == 1 else f"b{v} {i}\n")
            if ti == 0:
                f.write("$end\n")


def _vcd_id(n):
    ids = [chr(c) for c in range(33, 127)]
    s, m = "", n
    while True:
        s = ids[m % 94] + s
        m //= 94
        if m == 0:
            return s


def fuzz(trials, seed):
    random.seed(seed)
    ok = total = wrong = 0
    for _ in range(trials):
        k = random.randint(1, 8)
        widths = [random.choice([1, 1, 2, 4, 8, 16, 32, 64]) for _ in range(k)]
        decls = [("wire", widths[i], _vcd_id(i), f"s{i}") for i in range(k)]
        ntimes = random.randint(1, 50)  # <=64 -> single granule, no vcd2lxt2 cap
        xz = random.random() < 0.4
        truth = {i: [] for i in range(k)}
        frames, cur = [], {}
        for fi in range(ntimes):
            ch = {}
            for i in range(k):
                if fi == 0 or random.random() < 0.5:
                    v = "".join(random.choice("01xz" if xz else "01") for _ in range(widths[i]))
                    if cur.get(i) != v:
                        ch[_vcd_id(i)] = v
                        truth[i].append((fi * 10, v))
                        cur[i] = v
            if fi == 0:
                for i in range(k):
                    if i not in cur:
                        v = "0" * widths[i]
                        ch[_vcd_id(i)] = v
                        truth[i].append((0, v))
                        cur[i] = v
            if ch:
                frames.append((fi * 10, ch))
        try:
            _write_vcd("/tmp/_lxt2fuzz.vcd", decls, frames)
            subprocess.run(["vcd2lxt2", "/tmp/_lxt2fuzz.vcd", "/tmp/_lxt2fuzz.lxt2"],
                           check=True, capture_output=True)
            names, _, dec = decode("/tmp/_lxt2fuzz.lxt2")
        except subprocess.CalledProcessError:
            continue
        total += 1
        byname = {names[i]: i for i in range(len(names))}
        exact = all(dec.get(byname[f"top.s{i}"], []) == truth[i] for i in range(k))
        ok += exact
        for i in range(k):
            got = dict(dec.get(byname[f"top.s{i}"], []))
            tr = dict(truth[i])
            for t, v in got.items():
                if tr.get(t) != v:
                    wrong += 1
    return ok, total, wrong


def check_fixtures():
    import json
    root = os.path.join(os.path.dirname(__file__), "..", "test", "fixtures", "legacy")
    failures = 0
    for fx in ["simple_counter", "multi_scope", "vector_signals"]:
        lxt2 = os.path.join(root, f"{fx}.lxt2")
        exp = os.path.join(root, f"{fx}.expected.json")
        if not (os.path.exists(lxt2) and os.path.exists(exp)):
            continue
        names, widths, dec = decode(lxt2)
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

    if subprocess.run(["which", "vcd2lxt2"], capture_output=True).returncode != 0:
        print("vcd2lxt2 not found on PATH (brew install gtkwave). Skipping fuzz.")
        sys.exit(0)

    print("Committed-fixture value equivalence:")
    fixture_bad = check_fixtures()
    print(f"\nDifferential fuzz ({args.trials} trials, seed {args.seed}):")
    ok, total, wrong = fuzz(args.trials, args.seed)
    print(f"  exact={ok}/{total}  wrong-values={wrong}")
    # The hard invariant: the decoder must NEVER emit a wrong value. Exact
    # coverage <100% is acceptable (complex high-facility blocks fall back
    # safely in the Rust converter), but a single wrong value is a bug.
    if wrong or fixture_bad:
        print("FAIL: decoder emitted incorrect values")
        sys.exit(1)
    print("OK: no incorrect values")


if __name__ == "__main__":
    main()
