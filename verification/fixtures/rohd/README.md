# ROHD fixtures (ROHD 0.7 or later, source tracing)

Real output of a small ROHD design with source tracing on:

| File | What it is |
|---|---|
| `top.vcd` | The waveform ROHD's WaveDumper wrote for a short run: 32 signals across `top`, the keyword-named instance `reg_`, ROHD's own `flipflop`, `sequential`, `combinational`, `adder` and `add` modules, and a struct's fields |
| `Top.flc.json` | The source-trace file (version 6) for the same run |

The VCD carries no source data; the sidecar is what joins its signals to Dart
lines. The instance `reg` is `reg_` in the waveform because `reg` is a
SystemVerilog keyword.

## Provenance

| Input | Pinned to |
|---|---|
| `intel/rohd` (BSD-3-Clause) | `2d84f73abfb1ba95c64d218e9b13a12e8416249c`, `main` on 2026-10-27, which is ROHD 0.6.11 plus source tracing (the work released as 0.7) |
| `intel/rohd-vf` (BSD-3-Clause) | `dd830d3b83438dfa5a06b0f0d8841eca16e97046` |
| Dart SDK | 3.13.5 |

The design (`generator/design.dart.txt`) is ours; only the output of running it
against ROHD is kept here. Absolute paths from the machine that generated the
files are rewritten to `/work/rohd_fixture`, a folder that does not exist, so
the tests copy the files into a temporary Dart package before resolving paths.

## Regenerate

```bash
verification/fixtures/rohd/generator/generate.sh <empty work dir> verification/fixtures/rohd \
  top.vcd Top.flc.json
```

Needs network access the first time, for the two git dependencies. The `.txt`
suffix on the generator's Dart sources keeps the analyzer and the formatter from
treating them as part of this package.
