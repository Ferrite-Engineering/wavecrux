# Test data helpers — Open Core verification

This folder is for ad-hoc helper scripts that produce additional test data on demand. Most fixtures are pre-generated and committed under sibling folders; helpers are only needed when:

- Stress-sized files (>10 MB) that we deliberately do not commit.
- Synthetic VCDs at exotic timescales for regression checks.
- Streaming-pipe producers used for the interactive-VCD test.

## Protocol decoder fixture corpus structure

Every per-decoder fixture directory under `test/fixtures/protocol/<decoder>/` and `verification/fixtures/protocol/<decoder>/` is split into two tiers:

```
<decoder>/
├── generated/    # Deterministic VCDs + JSON snapshots emitted by tool/generate_*.dart
│                 # — re-runnable in seconds, 100% reproducible, the unit-test backbone.
└── captured/     # Traces acquired from public open-source projects (verilog-ethernet,
                  # verilog-axi, picorv32, OpenTitan, etc.) — direct VCD/FST files or
                  # locally rebuilt via iverilog/verilator from upstream testbenches.
                  # Each fixture has a license-attributed PROVENANCE.md entry.
```

Captured fixtures supplement the deterministic synthetic corpus with real-world bus behavior (production burst rates, error-injection patterns, idle-cycle distributions, multi-second SoC traces). The license allow-list is enforced by `test/static/captured_fixture_licenses_test.dart`: only MIT/BSD/Apache-2.0/ISC/CC0/public-domain captures are permitted, and every captured fixture file must have a matching entry in its directory's `PROVENANCE.md`.

The same split applies one level up: `verification/fixtures/protocol/<decoder>/` mirrors the structure so the verification-guide flow exercises both tiers. The `verification/fixtures/protocol/multi/` coexistence harness is exempt — it composes from the per-decoder corpora rather than holding its own.

Regeneration commands continue to work unchanged — the generators write into `<decoder>/generated/` automatically.

## GTKWave `.gtkw` session-import corpus (Section 6.6)

The GTKWave save-file corpus under `test/fixtures/gtkw/` follows the same
`generated/` + `captured/` discipline as the protocol decoders. Unlike the
decoder corpora, there is **no duplicate `verification/fixtures/gtkw/` copy** —
the verification flow (§6.6) references `test/fixtures/gtkw/` directly. The
layout is enforced by `test/static/gtkw_fixture_layout_test.dart`.

```
test/fixtures/gtkw/
├── generated/    # synthetic saves + paired fixture.vcd + sample_filter.txt,
│                 # each .gtkw with .expected_parse.json (parser output) and
│                 # .expected_session.json (full parse→import result golden).
└── captured/     # real GTKWave saves from public projects (Apache/MIT/BSD),
                  # each with a PROVENANCE.md entry and an .expected_parse.json.
                  # No import golden — referenced dumpfiles aren't committed.
```

The goldens are the gtkw analog of a decoder's `.expected_transactions.json`:
the parse golden pins the VCD-independent parser output, and the session golden
pins the full pipeline (parse → match against `fixture.vcd`'s variables →
`SessionState`). The captured tier proves a messy real-world save — full of
`[size]`/`[pos]`/`[sst_*]`/`[pattern_trace]`/`[savefile]` directives WaveCrux
does not model — still imports without error.

To regenerate the synthetic fixtures and **all** goldens (generated + captured):

```bash
dart run tool/generate_gtkw_fixtures.dart
```

The script writes the synthetic `.gtkw` inputs, `fixture.vcd`, and
`sample_filter.txt` from canonical in-source definitions, then computes every
`.expected_parse.json` / `.expected_session.json`. It re-reads (never rewrites)
the committed real `captured/*.gtkw` files and refreshes their parse goldens.
After regenerating:

```bash
flutter test test/services/session/ test/features/viewer/gtkw_import_pipeline_test.dart test/static/gtkw_*
```

### Adding a captured `.gtkw`

1. Download the `.gtkw` from a permissively-licensed (MIT/BSD/Apache-2.0/ISC/CC0/public-domain) public project — **not** GTKWave's own GPL `examples/`.
2. Drop it in `test/fixtures/gtkw/captured/` with a descriptive name.
3. Add a `PROVENANCE.md` block (source repo, commit SHA, license + SPDX, hand-verified anchors).
4. Run `dart run tool/generate_gtkw_fixtures.dart` to mint its `.expected_parse.json`, then `flutter test test/static/gtkw_* test/services/session/gtkw_golden_test.dart`.

## Streaming VCD producer (Section 13 of the detail guide)

Save the following as `streaming_vcd.sh`, `chmod +x`, and consume from a fifo:

```bash
#!/usr/bin/env bash
# Pure-bash VCD streamer — emits a valid header, sleeps so the user can see
# the hierarchy populate, then loops emitting timestamps and value changes.
cat <<'HDR'
$date Mon May  3 09:00:00 2026 $end
$version stream-test 1.0 $end
$timescale 1 ns $end
$scope module top $end
$var wire 1 ! clk $end
$var wire 8 " counter $end
$upscope $end
$enddefinitions $end
$dumpvars
0!
b00000000 "
$end
HDR

sleep 0.5

t=0
val=0
while :; do
  t=$((t+5))
  echo "#${t}"
  if (( t % 10 == 0 )); then echo "1!"; else echo "0!"; fi
  val=$(( (val + 1) & 0xFF ))
  printf 'b'
  for ((i=7;i>=0;i--)); do printf '%d' $(( (val >> i) & 1 )); done
  printf ' "\n'
  sleep 0.05
done
```

## Stress VCD generator

Use the in-app **Diagnostics → Generator** tab. Configure 1000 signals, 50 ms duration, "high" complexity. The generated file is the canonical large-design fixture for performance verification.

## RISC-V instruction-trace fixtures (Section 5.7)

The four RISC-V **fetch-trace** fixtures (`riscv_rv32i_basic`, `riscv_rv32im_arith`, `riscv_rv64i_basic`, `riscv_pc_present`) are produced from a deterministic Dart emitter that hand-encodes a few cycles of fetch trace per scenario. Each VCD has a paired `.expected_transactions.json`. The same files are mirrored under `test/fixtures/protocol/riscv/` so the unit tests and the manual verification flow share inputs.

The same emitter also writes the **RVFI retire-trace** fixture (`riscv_rvfi_retire`), which carries the full riscv-formal channel bundle for a single-issue in-order core running a short ISA-legal program. Its companion is a `.expected_retire_stream.json` (not `.expected_transactions.json`) — it feeds the RISC-V trace substrate in `lib/services/riscv/`, not the protocol decoder. Every expected disassembly in both families is cross-checked against the real `InstructionDisassembler` before the generator writes anything, so a hand-encoding typo fails the generator rather than baking a wrong fixture.

To regenerate from the source scenarios in `tool/generate_riscv_fixtures.dart`:

```bash
dart run tool/generate_riscv_fixtures.dart
```

The script writes both the test-tree and verification-tree copies. After regenerating, run the test suite:

```bash
flutter test test/services/decoders/isa/
```

A separate, optional **Verilator-based authentic trace** path is documented inline in `verification/VERIFICATION_GUIDE.md` §5.7 — useful for cross-checking the hand-encoded fixtures against output from a real RISC-V simulation, and for producing larger traces than the hand-emitter can comfortably express.

### The two captured RISC-V fixtures — not from the generator

Everything above is emitted by us, which makes it a regression lock and not
evidence. Two fixtures under `protocol/riscv/captured/` come from cores we did
not write, each with its own rebuild recipe under `.../captured/helpers/`:

| Fixture | Core | Toolchain | Rebuild |
|---|---|---|---|
| `riscv_picorv32_wb_ez.fst` | YosysHQ `picorv32_wb` (ISC), vendored in-tree | iverilog + vvp | `cd helpers/picorv32 && make && make install` |
| `riscv_ibex_rvfi_trap.fst` | lowRISC `ibex_top` (Apache-2.0) @ `3250d994`, **fetched at a pinned commit, not vendored** | Verilator 5.050 `+define+RVFI`, then `fst2vcd` → `trim.py` → `vcd2fst` | `cd helpers/ibex && make && make install` |

Neither needs cocotb or a RISC-V GNU toolchain — both programs are hand-encoded.

The Ibex capture is the corpus's only real-core **RVFI** trace and is what the
`lib/services/riscv/` substrate is tested against in
`test/services/riscv/riscv_ibex_captured_rvfi_test.dart`. Read
`helpers/ibex/README.md` before regenerating it: the trim step exists because
Verilator ignores `$dumpvars` scope arguments, and the capture's 21 pinned
consistency violations are **upstream Ibex RVFI deviations**, not a WaveCrux
regression (verification §10B.1.10).

After rebuilding either one, regenerate the decoded snapshots:

```bash
REGENERATE=1 flutter test test/services/decoders/riscv_captured_fixtures_test.dart
```

and mirror the regenerated `.expected_transactions.json` into
`verification/fixtures/protocol/riscv/captured/`.

## Wishbone B3 / B4 fixtures (Section 5.7)

The seven Wishbone fixtures cover the full B3 + B4 surface area:

| Fixture | What it exercises |
|---|---|
| `wishbone_b3_classic_basic` | Single read/write/err/rty handshakes |
| `wishbone_b3_burst_incr` | Linear (BTE=00) incrementing burst, 4 beats |
| `wishbone_b3_burst_wrap` | 4-beat-wrap (BTE=01) burst + constant-address (CTI=001) burst |
| `wishbone_b3_classic_violations` | All 9 B3-mode protocol-violation classes |
| `wishbone_b4_pipelined_basic` | Pipelined read + write, no stall, no overlap |
| `wishbone_b4_pipelined_stall` | Pipelined back-to-back with stalls and outstanding-count tracking |
| `wishbone_b4_pipelined_violations` | B4-specific violations (signal-change-while-stalled, mutex termination, CYC drop with outstanding) |

To regenerate from the source scenarios in `tool/generate_wishbone_fixtures.dart`:

```bash
dart run tool/generate_wishbone_fixtures.dart
```

The script writes both the test-tree and verification-tree copies. After regenerating, run the test suite:

```bash
flutter test test/services/decoders/wishbone_decoder_test.dart
```

The expected-transactions JSON is computed by running the decoder under test against the generated VCD timeline. The decoder unit tests then assert hand-verified anchor points (key transaction labels, counts, error flags) on top of the JSON-snapshot diff so a silent regression in decoder output is still caught.

## AHB-Lite fixtures (Section 5.8)

Eight AHB-Lite fixtures cover the core single-master AMBA AHB-Lite surface area:

| Fixture | What it exercises |
|---|---|
| `ahb_lite_single_basic` | One SINGLE read followed by one SINGLE write, both OKAY |
| `ahb_lite_incr_burst` | INCR4 read burst — 4 child beats + 1 parent record |
| `ahb_lite_wrap_burst` | WRAP4 read burst with mid-window start (0x108 → 0x10C → 0x100 → 0x104) |
| `ahb_lite_incr_undefined` | INCR (undefined-length) read with mid-burst BUSY insertion |
| `ahb_lite_wait_states` | SINGLE read with 2 HREADY=0 wait states |
| `ahb_lite_error_response` | SINGLE write completed with proper two-cycle ERROR handshake |
| `ahb_lite_locked_transfer` | HMASTLOCK read-modify-write with HPROT bound |
| `ahb_lite_violations` | Exercises 7 detectable protocol-violation classes (BUSY-in-SINGLE, SEQ-without-NONSEQ, HBURST mid-burst change, HADDR not-expected-next, HSIZE > data_width, misalignment, single-cycle ERROR) |

To regenerate from the source scenarios in `tool/generate_ahb_lite_fixtures.dart`:

```bash
dart run tool/generate_ahb_lite_fixtures.dart
```

The script writes both the test-tree and verification-tree copies. After regenerating, run the test suite:

```bash
flutter test test/services/decoders/ahb_lite_decoder_test.dart
```

## SPI flash command fixtures — stacked decoder (Section 5.10)

Seven fixtures cover the full JEDEC SPI flash command surface and the WEL state machine:

| Fixture | What it exercises |
|---|---|
| `spi_flash_rdid` | RDID (0x9F) — reads 3-byte JEDEC ID from MISO |
| `spi_flash_wren_pp` | WREN (0x06) + Page Program (0x02) — WEL enables write |
| `spi_flash_read` | READ (0x03) — 24-bit address, 2 data bytes from MISO |
| `spi_flash_wren_se` | WREN (0x06) + Sector Erase (0x20) — erase with WEL |
| `spi_flash_wel_violation` | PP without prior WREN → `write_without_wel` error |
| `spi_flash_rdsr` | RDSR (0x05) — status register 0x02 (WEL bit set) |
| `spi_flash_fast_read` | FAST_READ (0x0B) — 1 dummy byte + 1 data byte |

Each VCD encodes raw SPI bus signals at Mode 0 (CPOL=0, CPHA=0). The fixture generator chains the SPI decoder and the SPI flash decoder to produce the expected JSON. Each fixture has a paired `.expected_transactions.json`.

To regenerate from the source scenarios in `tool/generate_spi_flash_fixtures.dart`:

```bash
dart run tool/generate_spi_flash_fixtures.dart
```

The script writes both the test-tree and verification-tree copies. After regenerating, run the test suite:

```bash
flutter test test/services/decoders/spi_flash/spi_flash_decoder_test.dart
```

## X-Trace fixture (Section 6.2)

`verification/fixtures/vcd/xtrace.vcd` is the manual-verification fixture for the X-Trace causal-chain feature. The hand-crafted VCD places six wires under a single `top` scope so they are mutual siblings for the X-Trace heuristic:

| Signal | Role at T=200 ns |
|---|---|
| `data_out` (8-bit) | Goes fully `x` — the queried root |
| `status` (1-bit) | Goes `x` — co-temporal sibling shown in the causal chain |
| `clk` (1-bit) | Toggling clock, no X — uninvolved |
| `enable` (1-bit) | Constant `1`, no X — uninvolved |
| `addr` (8-bit) | `8'h11`, no X — uninvolved |
| `clean_sig` (1-bit) | Constant `0`, no X — uninvolved |

The simulation runs from T=0 to T=300 ns; the X event lives at T=200 ns so the verifier can position the cursor either side of the origin while exercising the marker overlay and the cursor-jump-from-chain-node steps.

To regenerate from the source scenario in `tool/generate_xtrace_fixture.dart`:

```bash
dart run tool/generate_xtrace_fixture.dart
```

The script overwrites `verification/fixtures/vcd/xtrace.vcd` in place. There is no `expected_transactions.json` companion — X-Trace is verified end-to-end through the manual flow described in `VERIFICATION_GUIDE.md` §6.2 rather than through a decoder-style JSON snapshot.

## LXT / LXT2 legacy-format fixtures (Section 22.13)

WaveCrux opens GTKWave's legacy `.lxt` (2003 streaming) and `.lxt2` (2005 block-indexed) captures by transparently converting them to FST on open (the clean-room `lxt2fst` Rust crate at `native/lxt2fst/`), then loading the FST through the existing wellen pipeline. The verification suite shares the test-tree legacy fixtures directly rather than maintaining a duplicate copy — they live under `test/fixtures/legacy/` and the manual flow references them from there:

| Fixture | LXT2 | LXT | What it exercises |
|---|---|---|---|
| `simple_counter` | ✓ | ✓ | 8-bit counter + toggling clock (~50 transitions). Smallest known-answer file; the only one also converted to classic LXT. Used for happy-path open + cache-hit verification (§22.13.1, §22.13.2). |
| `multi_scope` | ✓ | | Nested hierarchy (`top.cpu.alu`, `top.cpu.regfile`) — scope-walk and full-path resolution. Used for File Info "Original format" row verification (§22.13.7). |
| `vector_signals` | ✓ | | 32-/64-bit vectors, `x`/`z` states, real-valued signals. |
| `string_values` | ✓ | | VCD `$var string` signals (`s`-prefixed value changes) — pins the LXT2 string-encoding path. |
| `large_sample` | ✓ | | ~5 MB committed capture (4 cross-checked probe signals + bulk filler) for the progress-bar / performance path. **A true ~50 MB capture for the progress-dialog verification (§22.13.4) is not committed** — regenerate locally with `--large` (see below). |

Each committed fixture ships with a source `.vcd` (the ground-truth input) and a `.expected.json` (the wellen-loaded value/hierarchy snapshot used for round-trip assertions).

To regenerate the committed fixtures:

```bash
dart run tool/regenerate_legacy_fixtures.dart
```

To additionally regenerate the uncommitted ~50 MB progress-dialog capture into `build/legacy_perf/large_sample.lxt2`:

```bash
dart run tool/regenerate_legacy_fixtures.dart --large
```

After regenerating, run the related Dart and Rust tests:

```bash
flutter test test/services/waveform/legacy_format_detector_test.dart \
             test/services/waveform/lxt2fst_cache_test.dart \
             test/services/waveform/legacy_conversion_controller_test.dart \
             test/services/waveform/lxt2fst_bridge_equivalence_test.dart \
             test/features/viewer/providers/waveform_source_provider_lxt2_test.dart \
             test/widgets/legacy_format_banner_test.dart \
             test/widgets/legacy_conversion_progress_dialog_test.dart
cd native/lxt2fst && cargo test
```

### GTKWave tool dependency (developer-machine only — never shipped)

Regeneration requires GTKWave's `vcd2lxt` and `vcd2lxt2` CLIs on `PATH`. They are a **developer-machine build dependency only** — WaveCrux never bundles, links against, or ships them, and converts legacy files at runtime with the clean-room `lxt2fst` crate instead. The regenerator script locates them via `PATH` and exits with an actionable message if either is missing:

```bash
# macOS
brew install gtkwave
# Debian/Ubuntu
sudo apt-get install gtkwave
```

The legacy LXT/LXT2 formats are frozen, so no GTKWave version tracking is needed; any reasonably recent GTKWave produces compatible output.

## Feature-coexistence fixtures (Section 15)

Two combined fixtures live under `verification/fixtures/protocol/multi/` for the feature-coexistence integration tests (`integration_test/coexistence/`). Both are derived from the known-good single-bus fixtures so their decode output is guaranteed to match the originals.

| Fixture | What it is | Used by |
|---|---|---|
| `spi_i2c_basic.vcd` | `protocol/spi/generated/spi_basic.vcd`'s `spi_tb` scope + `protocol/i2c/generated/i2c_basic.vcd`'s `i2c_tb` scope (I²C identifier codes remapped to a disjoint set), timelines interleaved. Companions: `spi_i2c_basic.spi.expected_transactions.json` and `spi_i2c_basic.i2c.expected_transactions.json` — verbatim copies of the source companions (one per decoder). | `multi_decoder_coexistence_test.dart` |
| `spi_xtrace.vcd` | `protocol/spi/generated/spi_basic.vcd` augmented with an 8-bit `data_out` wire that goes fully `x` at T=620 ns (after the last SPI change at T=590, so the SPI decode is unchanged). No expected companion — the SPI side matches `spi_basic`'s, and X-Trace is verified via provider state. | `decoder_xtrace_coexistence_test.dart` |

To regenerate:

```bash
dart run tool/generate_multi_coexistence_fixture.dart   # spi_i2c_basic.vcd + 2 companions
dart run tool/generate_spi_xtrace_fixture.dart          # spi_xtrace.vcd
```

Re-run these after editing either source fixture (`spi_basic.vcd` / `i2c_basic.vcd`) so the combined files and the copied expected companions stay in sync.

The diff, pattern-search, Stage + FSM + RTL and tablet Stage + FSM coexistence tests reuse existing fixtures (`protocol/spi/generated/spi_basic.vcd`, `protocol/spi/generated/spi_mode1.vcd`, `stage/stage_demo.vcd`) and, for Stage + FSM + RTL, a throwaway stems + Verilog source pair written to a temp directory at runtime (RTL stems reference absolute on-disk source paths, which cannot be committed portably).

## Stage board out-of-box demo fixtures (Section 10.4)

Each educational FPGA board widget ships a compelling "out-of-box demo" fixture under `verification/fixtures/stage/boards/<board>/`, generated from a single Dart script:

```bash
dart run tool/generate_board_demo_fixtures.dart
```

For every board (`basys3`, `nexys_a7`, `de10_lite`, `arty_a7`) this writes two VCDs — `<board>_demo_per_bit.vcd` and `<board>_demo_vector.vcd` — into both `test/fixtures/stage/boards/<board>/` and `verification/fixtures/stage/boards/<board>/` (the script mirrors them automatically; no separate copy step). The per-bit file names every LED / switch / numeric button as an individual 1-bit signal (`led0`, `sw0`, `btn0`, …) so auto-bind resolves them through the exact / per-bit tier; the vector file collapses each family into a single packed bus (`leds`, `sws`, `btn`, `key`) so auto-bind resolves them through the vector-fan-out tier. Both files are driven by the same exciting self-test — a six-pattern LED light show (cylon / VU bar / theater chase / switch-register mirror / expand-from-centre / sparkle), a coherent decoded seven-segment readout (Basys 3: free-running hex counter; Nexys A7: live accelerometer X/Y; DE10-Lite: 3-axis accelerometer X/Y/Z) with every digit exercised across its full 0–F range, evolving slide switches, and staggered button presses — so binding either one animates the board identically. Seven-segment fields are coherent decoded values sliced into per-digit nibbles (see `_SegField` in the generator), not a per-digit cascade. The integration test `test/fixtures/stage/boards/board_demo_fixtures_test.dart` parses every fixture and asserts the expected auto-bind tier for each board.
