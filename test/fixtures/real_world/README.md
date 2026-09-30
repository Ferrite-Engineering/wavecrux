# Real-world VCD/FST/GHW parser-robustness corpus

This directory holds **parser-only** fixtures: a curated zoo of waveform
files acquired from a variety of public open-source projects, simulators,
and tooling pipelines. The goal is **prove WaveCrux's parser doesn't fall
over on real-world quirks** — not to drive decoder behaviour. Files here
are *opened*, the hierarchy is walked, and a handful of signal values are
sampled to confirm wellen (the Rust parser, both FFI and WASM) returns
without crashing. No decoder is run; no transactions are asserted.

The decoder-targeted captured corpus lives next door at
[`../protocol/<decoder>/captured/`](../protocol/) and exercises the
per-decoder semantics. The two are complementary:

- `protocol/<decoder>/captured/` → snapshot-matched decoded transactions.
- `real_world/` → "did the parser crash" smoke screen across diverse
  simulator outputs.

## Why both directories exist

The decoder captured corpus is necessarily narrow: every fixture targets
one decoder, so the variety of simulator outputs is bounded by what each
decoder's source IP happened to emit. The real-world zoo widens that —
Synopsys VCS reference traces, Cadence Xcelium examples, Verilator
self-tests, iverilog public CI artifacts, Aldec Riviera-PRO samples,
older GTKWave demo VCDs (frozen format, no `$dumpoff`), cocotb internal
self-test outputs, Yosys synth dumps (different metadata than sim
traces), and intentionally-large stress files all live here. The
parser must survive every one without a Rust panic, SIGSEGV, or
FFI-thread death.

## License allow-list

Same allow-list as the captured corpus:

- MIT
- BSD-2-Clause / BSD-3-Clause
- Apache-2.0
- ISC
- CC0-1.0
- public domain

GPL/AGPL/proprietary files are excluded by policy. The static guardrail
`test/static/real_world_fixture_provenance_test.dart` walks every
committed file in this directory tree and fails the build if any file
lacks a matching `.provenance.json` sidecar with a license from the
allow-list.

## File layout

```
real_world/
├── README.md                       — this file
├── <name>.fst                      — the trace (FST preferred, .vcd accepted)
├── <name>.provenance.json          — sibling sidecar (mandatory)
├── helpers/                        — optional download/regenerate scripts
└── ...
```

> **Compressed VCDs (`.vcd.zst` / `.vcd.gz`) are not currently supported.**
> wellen 0.20 does not natively decompress either format, and adding a
> Dart-side decompression shim is out of scope for the parser-only zoo.
> If wellen gains native compressed-input support in a future release,
> add `.zst` / `.gz` to the `_waveformExtensions` allow-list in both
> [`test/services/waveform/_real_world_zoo_test.dart`](../../services/waveform/_real_world_zoo_test.dart)
> and [`test/static/real_world_fixture_provenance_test.dart`](../../static/real_world_fixture_provenance_test.dart),
> then commit a compressed-VCD fixture (e.g. an extended picorv32 run
> compressed with `zstd -19`).

The directory is flat — no per-source subfolders — so the parser sweep
test (`test/services/waveform/_real_world_zoo_test.dart`) can walk it
in a single pass. Filenames should encode the source + scenario:
`<source>_<scenario>.<ext>` (e.g. `cocotbext_axi_self_test.fst`,
`gtkwave_legacy_demo.vcd.zst`, `verilator_picorv32_trace.fst`).

## `.provenance.json` schema

```json
{
  "source_url": "https://github.com/<owner>/<repo>",
  "source_commit": "<sha>",
  "license": "MIT",
  "license_spdx": "MIT",
  "simulator": "iverilog",
  "simulator_version": "11.0",
  "acquired_date": "2026-MM-DD",
  "size_bytes": 123456,
  "brief_description": "1-2 sentence scenario summary",
  "anchors": [
    "scope `top.dut` exists with 8+ variables",
    "signal `clk` toggles ≥10 times in the trace"
  ]
}
```

`anchors` are advisory — the parser sweep doesn't enforce them, but
they give future maintainers a hint about what the file is supposed to
contain.

## Adding a fixture

1. Drop the trace file under `real_world/` (FST preferred; `.vcd.zst`
   for large VCDs that don't survive `vcd2fst` cleanly; raw `.vcd` only
   if absolutely necessary).
2. Author a `<name>.provenance.json` sidecar covering the schema above.
3. Run the parser sweep:
   ```bash
   flutter test test/services/waveform/_real_world_zoo_test.dart
   ```
4. Run the static guardrail:
   ```bash
   flutter test test/static/real_world_fixture_provenance_test.dart
   ```

Both must pass before commit.

## Size budget

Target ≤100 MB additional committed corpus. Prefer FST over VCD. If a
file exceeds 10 MB raw, commit a smaller representative slice and
document the full file's source URL in `.provenance.json` (with a
download-on-demand script under `helpers/` for regeneration). The
budget is shared across both the captured-decoder corpus AND this zoo.

## Current inventory (2026-05-31)

Populated as part of the protocol-decoder robustness initiative
close-out. Eight fixtures spanning six simulator origins and two file
formats:

| Fixture | Source | Sim origin | Format | Size |
|---|---|---|---|---|
| `picorv32_ez_testbench.vcd` | [YosysHQ/picorv32](https://github.com/YosysHQ/picorv32) (ISC) | iverilog 13.0 | VCD | 279 KB |
| `picorv32_long_fst_extended.fst` | YosysHQ/picorv32 + vcd2fst | iverilog 13.0 → vcd2fst | FST | 537 KB |
| `picosoc_spiflash_tb.vcd` | YosysHQ/picorv32 picosoc subdir | iverilog 13.0 | VCD | 19 KB |
| `verilator_tracing_example.fst` | [verilator/verilator](https://github.com/verilator/verilator) (CC0-1.0 example) | Verilator 5.048 | FST | 847 B |
| `yosys_simple_assign.vcd` | [YosysHQ/yosys](https://github.com/YosysHQ/yosys) (ISC) | yosys internal sim | VCD | 168 B |
| `ghdl_vhdl_uut.vcd` | YosysHQ/yosys tests/sim corpus | GHDL (VHDL) | VCD | 418 B |
| `cocotb_simple_dff.fst` | [cocotb/cocotb](https://github.com/cocotb/cocotb) (BSD-3) example | iverilog 13.0 + cocotb 2.0.1 | FST | 611 B |
| `cocotb_matrix_multiplier.fst` | cocotb/cocotb (BSD-3) example | iverilog 13.0 + cocotb 2.0.1 | FST | 37 KB |
| `wavecrux_vhdl_types.ghw` | in-house `tool/ghw_fixtures/` (CC0-1.0) | GHDL 6.0 (VHDL-2008) | **GHW** | 2.9 KB |

Total committed: ~875 KB (well under the 100 MB cap; ~99 MB of headroom
remains for future fixtures).

## Acquisition gaps — vendor and compressed formats

These were considered for the initial population and intentionally
deferred. Filling them is a "nice to have" follow-up, not a robustness
blocker.

- **Synopsys VCS / Cadence Xcelium / Aldec Riviera-PRO reference
  traces.** Require vendor portal accounts (solvnet / Cadence Online
  Support / Aldec support). Worth filling if a contributor has access.
- **GTKWave demo VCDs.** The historical `gtkwave/` repo ships
  `lib/libgtkwave/test/files/*.vcd` covering frozen-format quirks
  (no `$dumpoff`, hashkill, evcd, timezero, …) but the repo itself
  is GPL-2 — outside the allow-list. A standalone re-publication of
  those test files under MIT/BSD/CC0 would unblock that axis.
- **Compressed VCDs (`.vcd.zst` / `.vcd.gz`).** wellen 0.20 lacks
  native decompression; see the note in the File layout section above.
- **Real values / strings / multi-MB stress file.** Each of the
  fixtures we ship uses only `0/1/x/z` bit values; a fixture with
  `r` (real) or string variables would extend coverage. A 100+ MB
  cocotbext-axi crossbar trace was considered but punted to keep the
  committed corpus small — when one is added, prefer the
  download-on-demand pattern under `helpers/`.

## Why this corpus is parser-only, not decoder-driven

The decoder-targeted captured fixtures already exercise the parser on
real-world data — every captured `.fst` is parsed before being decoded.
That coverage is real, but it's bounded by what the decoder's source IP
chooses to emit. A user who opens a Synopsys VCS trace from a
non-protocol context (just hierarchy browsing, no decoder activated)
exercises a *different* code path through the parser. The real-world
zoo tests that path explicitly: open, list hierarchy, sample values,
confirm no crash, then close. If the file is too quirky for any
decoder to make sense of it, the parser still must not fall over.
