# LXT / LXT2 legacy-format test fixtures

Fixtures for **LXT / LXT2 legacy format support**. WaveCrux opens
GTKWave's legacy `.lxt` (2003 streaming) and `.lxt2` (2005 block-indexed)
captures by transparently converting them to FST on open (the `lxt2fst` crate),
then loading the FST through the existing wellen pipeline.

These fixtures back the bridge-equivalence and round-trip tests: each legacy
file converts to FST, loads via `WellenProvider`, and must produce the same
query results as the **ground truth** captured here from the source VCD.

## Contents

Each fixture ships a source `.vcd`, one or more legacy conversions, and a
`.expected.json` ground-truth companion.

| Fixture | Source | LXT2 | LXT | Exercises |
|---|---|---|---|---|
| `simple_counter` | ✓ | ✓ | ✓ | 8-bit counter + toggling clock (~50 transitions). Smallest known-answer file; the only one also converted to classic LXT. |
| `multi_scope` | ✓ | ✓ | | Nested hierarchy (`top.cpu.alu`, `top.cpu.regfile`) — scope-walk and full-path resolution. |
| `vector_signals` | ✓ | ✓ | | 32-/64-bit vectors, `x`/`z` states, real-valued signals. |
| `string_values` | ✓ | ✓ | | VCD `$var string` signals (`s`-prefixed value changes) — pins the LXT2 string-encoding path. |
| `large_sample` | ✓ | ✓ | | ~5 MB capture (4 cross-checked probe signals + bulk filler) for the progress-bar / performance path. |

### `<fixture>.expected.json`

The **wellen-loaded ground truth** of the source VCD: the values
`valueAt` / `changesInRange` / `nextTransition` / `prevTransition` return for
every cross-checked signal, probed densely across the full timeline, plus the
hierarchy metadata (`varType`, `bitWidth`, `direction`) and timescale.

Notes that keep the JSON in lock-step with wellen's actual output:

* **Vectors are full-width.** wellen left-extends VCD vectors to the declared
  bit width, so values are stored padded (e.g. an 8-bit `1` is `"00000001"`).
  `x`/`z` are preserved per-bit, lower-case.
* **Reals are raw source strings.** wellen may normalize scientific notation /
  trailing zeros, so verifiers compare reals **numerically** with a small
  tolerance, not by string equality.
* **`large_sample` cross-checks only the four `top.bench` probe signals.** The
  `top.bench.bulk.*` filler signals exist solely to grow the file and are
  intentionally absent from the JSON.

The committed ground truth was verified to match wellen's real VCD load
(metadata, hierarchy, and all four query methods across every fixture).

## Regenerating

The fixtures are produced by [`tool/regenerate_legacy_fixtures.dart`](../../../tool/regenerate_legacy_fixtures.dart),
which authors each source VCD by construction, derives the `.expected.json`
from the same transition lists, and shells out to GTKWave's converters:

```bash
dart run tool/regenerate_legacy_fixtures.dart
```

Add `--large` to additionally regenerate a true **~50 MB** capture of the same
shape into `build/legacy_perf/` (uncommitted) for hands-on progress-bar /
performance runs:

```bash
dart run tool/regenerate_legacy_fixtures.dart --large
```

## GTKWave tool dependency (dev-machine only — never shipped)

Regeneration requires GTKWave's `vcd2lxt` and `vcd2lxt2` CLIs on `PATH`. They
are a **developer-machine build dependency only** — WaveCrux never bundles,
links against, or ships them, and converts legacy files at runtime with the
clean-room `lxt2fst` crate instead. The script locates them via `PATH` and
exits with an actionable message if either is missing.

```bash
# macOS
brew install gtkwave
# Debian/Ubuntu
sudo apt-get install gtkwave
```

The legacy LXT/LXT2 formats are frozen, so no GTKWave version tracking is
needed; any reasonably recent GTKWave produces compatible output.
