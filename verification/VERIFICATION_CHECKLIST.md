# WaveCrux — Open Core Verification Checklist (Summary)

> **Purpose.** Quick pre-release sign-off list. For step-by-step instructions, fixture inventory, and rationale, see `VERIFICATION_GUIDE.md` (sibling, this folder).
>
> **Workflow.** Tick each box as it's verified. Print or copy this file per release. Capture a `baseline_report_<release>.txt` from Diagnostics → Copy Report at the start; re-run for any tab that changes.

> **Coverage markers.** Every bullet carries a `[Coverage: …]` tag indicating whether it is automated and how. Bullets tagged `WIDGET` or `INTEGRATION_TEST` (without `pending`) are protected by CI and may be skipped during sign-off unless the relevant test files have changed. Bullets tagged `INTEGRATION_TEST — pending`, `WIDGET — pending`, `MANUAL`, or `HYBRID` must be exercised by hand. Full taxonomy in `VERIFICATION_GUIDE.md` §1.4. Pending integration_test items are queued in `integration_test/PENDING.md`.

---

## Release metadata

- Version: ____________________
- Build SHA: ____________________
- Verified by: ____________________
- Date: ____________________
- Platform(s) tested: ____________________

---

## Pre-flight

- [ ] Debug or profile build with diagnostics panel always available, OR release build with diagnostics opt-in enabled in Settings → Advanced — `[Coverage: MANUAL]`
- [ ] All fixtures present under `verification/fixtures/` — `[Coverage: MANUAL]` (one-time per release)
- [ ] Baseline diagnostics report captured: `baseline_report_<release>.txt` — `[Coverage: MANUAL]`
- [ ] **Malformed file shows the parser's reason, not a generic error** — opening a bad VCD (e.g. `test/fixtures/vcd/malformed_value_change.vcd`) shows wellen's own message (*"expected an id for a value change"*) under the localized load-error title, with no `Exception:` prefix (§2.2.1). Desktop/Android rebuild `libwellen_ffi` automatically; iOS needs `scripts/build_ios.sh` after FFI changes — `[Coverage: UNIT (Rust)]` (`wellen_ffi/src/lib.rs` open-error tests) + `[Coverage: UNIT (Dart, real FFI)]` (`waveform_source_provider_open_test.dart` — "malformed VCD surfaces wellen's reason") + `[Coverage: MANUAL]` (error overlay)

---

## 1. Diagnostics panel — verify first

- [ ] Opens via toolbar, command palette, and keyboard shortcut — `[Coverage: WIDGET]` (`test/features/diagnostics/widgets/app_diagnostics_dialog_test.dart` and `test/features/command_palette/widgets/command_palette_dialog_test.dart` both exercise the open-paths)
- [ ] All 7 tabs present: File Info, Memory, Render, Signal Health, Generator, Benchmarks, Diagnostics meta — `[Coverage: WIDGET]` (per-tab tests in `test/features/diagnostics/widgets/`)
- [ ] **File Info** populates correctly for `protocol/spi/generated/spi_basic.vcd` (signal count, transitions, timescale, format) — `[Coverage: WIDGET]` (`test/features/diagnostics/widgets/file_info_panel_test.dart` plus service-side `test/services/diagnostics/`)
- [ ] **Memory** values increase with file load and decrease on close — `[Coverage: HYBRID]` (`test/features/diagnostics/widgets/app_diagnostics_dialog_test.dart` covers the Memory-section presentation; absolute MB values are environment-dependent and remain manual)
- [ ] **Render** updates live as you scroll/zoom; "transaction paint" non-zero with a decoder active — `[Coverage: HYBRID]` (`test/features/diagnostics/widgets/pane_render_stats_popover_test.dart` + `test/features/viewer/widgets/render_stats_collector_test.dart` cover presentation and counters; perceptual liveness during scroll/zoom remains manual)
- [ ] **Signal Health** detects clocks and X/Z-only signals correctly — `[Coverage: WIDGET]` (`test/features/diagnostics/widgets/signal_health_panel_test.dart` + service-side tests)
- [ ] **Generator** produces a synthetic VCD that loads — `[Coverage: WIDGET]` (`test/features/tools/widgets/generate_test_vcd_dialog_test.dart` — the generator moved from the diagnostics dialog to Tools → Generate Test VCD)
- [ ] **Benchmarks** complete and print mean/median parse + render numbers — `[Coverage: WIDGET]` (`test/features/diagnostics/widgets/parser_benchmark_runner_test.dart`); absolute thresholds `[Coverage: HYBRID]`
- [ ] **Copy Report** produces clean GitHub-paste-ready output — `[Coverage: WIDGET]` (`test/services/diagnostics/app_diagnostics_report_service_test.dart` covers `AppDiagnosticsReportService` formatting)
- [ ] Provider override (Force Dart / Force Wellen / Default) works — `[Coverage: MANUAL]` (no committed automated test; verified manually)

---

## 2. Signal search & direction filtering

- [ ] Substring search works — `[Coverage: WIDGET]` (`test/services/signal_query/signal_search_service_test.dart` + `test/features/search/widgets/signal_search_dialog_test.dart`)
- [ ] Glob mode toggle changes `*` semantics — `[Coverage: WIDGET]` (`test/services/signal_query/signal_search_service_test.dart`)
- [ ] Type filter chips (Wire, Reg, Integer, Real) narrow correctly — `[Coverage: WIDGET]` (`test/features/search/widgets/signal_search_dialog_test.dart`)
- [ ] Direction chips (Input, Output, Inout) return **empty** on any VCD incl. `vcd/direction_test.vcd` — VCD carries no port direction, so all signals are `Unknown` (graceful path). Positive selection blocked on a direction-bearing FST/GHW fixture (§4 backlog) — `[Coverage: WIDGET]` (positive path via synthetic vars in `test/services/signal_query/signal_search_service_test.dart`)
- [ ] Direction chips return empty (not error) on a plain VCD with no direction metadata — `[Coverage: WIDGET]` (`test/services/signal_query/signal_search_service_test.dart` — empty-direction-set case is the documented regression catch)
- [ ] Prefix syntax `+I+`, `+O+`, `+IO+` parses + applies (returns empty on direction-less VCD) — `[Coverage: WIDGET]` (`test/services/signal_query/signal_search_service_test.dart`)
- [ ] Search dialog holds a fixed size across empty/populated results (no balloon on empty) — `[Coverage: WIDGET]` (`test/features/search/widgets/signal_search_dialog_test.dart` — "results region keeps a fixed height when empty")
- [ ] Ticking one FST alias row (several rows sharing one signalRef) leaves its siblings unticked, and "Add 1 Signal" adds exactly one — `[Coverage: WIDGET]` (`test/features/search/widgets/signal_search_dialog_test.dart` — "checking one FST alias row leaves its siblings unchecked")

---

## 2A. Signal hierarchy tree — multi-select, parameter values, apply-decoder-to-selection (§4A)

Fixture: `vcd/parameter_multiselect.vcd` (+ `.expected.json`).

- [ ] Parameter leaves show inline `= <value>` badge (`WIDTH = 8`, `DEPTH = 32`) without adding to the viewer; plain real `freq_mhz` shows no badge — `[Coverage: WIDGET + UNIT]` (`test/features/signal_tree/widgets/variable_tree_leaf_test.dart` — "parameter value badge", `test/features/signal_tree/providers/parameter_value_provider_test.dart`)
- [ ] Right-click on a parameter shows a non-interactive `name = value` header (full-value reveal) — `[Coverage: WIDGET]` (leaf test — "context menu header reveals the full value")
- [ ] Ctrl/Cmd+click toggles selection without adding; Shift+click selects the visible range from the anchor; plain tap adds one signal, clears selection, and re-anchors — `[Coverage: WIDGET + UNIT]` (leaf test — "multi-selection gestures", `signal_tree_providers_test.dart` — "selectRangeTo")
- [ ] "Add N Selected to Viewer" appears only on a selected row with ≥ 2 selected; adds in tree order with distinct colors — `[Coverage: WIDGET]` (leaf test — "multi-selection context menu")
- [ ] Bulk add is idempotent: signals already on the canvas are skipped (plain-tap → Shift+click range → bulk add never duplicates the first signal); single-tap duplicates still allowed — `[Coverage: WIDGET + UNIT]` (leaf test — "skips signals already on the canvas", `signal_group_test.dart` — `displayedSignalRefs`)
- [ ] Reconfiguring a decoder from the **transaction table** writes to the **active tab**, not the root container (open two tabs with different decoder configs; edit in tab B; tab A unchanged) — `[Coverage: WIDGET]` (`transaction_table_panel_test.dart` — two-container shape, mutation-verified) + `[Coverage: STATIC]` (crux-shared `route_mounted_scope_leak_test.dart` guards the class)
- [ ] "Apply Decoder to Selection…" opens the picker scoped to the selection; chosen decoder's config dialog pre-fills bindings via auto-bind and lists only selected signals in the dropdowns; unresolved bindings stay empty and required-binding validation still gates Apply — `[Coverage: WIDGET]` (leaf test — "opens the decoder picker", `test/features/decoders/widgets/decoder_config_dialog_prefill_test.dart`)
- [ ] Natural sort (0.2.6): hierarchy lists `[2]` before `[10]` (scopes + variables); Settings → Waveform Defaults toggle flips to declaration order live; Shift+click ranges and bulk-add order match the rendered order in both states — `[Coverage: UNIT + WIDGET]` (`natural_compare_test.dart`, `hierarchy_natural_sort_test.dart`, `settings_screen_test.dart`)
- [ ] FST alias safety (0.2.3): on an FST with cross-scope aliased nets, selecting rows in one scope highlights only those rows, and "Apply Decoder to Selection…" shows the clicked scope's names (auto-bind fills) — never a same-ref alias from another scope — `[Coverage: WIDGET + UNIT]` (leaf test — "FST alias regression", `signal_variables_map_provider_test.dart` — alias group)
- [ ] Context-menu bulk items render in all four locales without exceptions — `[Coverage: WIDGET]` (leaf test — locale sweep en/zh_CN/ja/ko)
- [ ] End-to-end fixture pass per §4A.3 (badges → range-select → bulk add → apply SPI → transactions decode) — `[Coverage: MANUAL]`
- [ ] Scope-row click latency (§4A.7): a single click on a scope header expands/collapses it **immediately** (assert on the first frame — no 300 ms dead zone); rapid clicks all register; a double-click deliberately toggles twice; right-click menu unaffected; on touch a flick-scroll started on a scope header scrolls without expanding — `[Coverage: WIDGET]` (`test/features/signal_tree/widgets/scope_tree_node_test.dart` — "toggles expansion on the very next frame", "the row registers no double-tap recognizer", "two taps inside the double-tap window both toggle") + `[Coverage: MANUAL]` (touch flick-scroll)
- [ ] **Signal tree from the keyboard (§4A.8)**: the tree is one Tab stop after the search field; Up/Down/Home/End/Page keys move, Right expands then enters, Left collapses then goes to the parent, Enter/Space toggle a scope or add + select a signal (announced, added once when held); arrows/Home/End/Space do not pan, jump or play while the tree is focused; Ctrl+Shift+Arrow still resizes the dock; a click moves the row without taking focus; focus survives scrolling the row out of the lazy list; Shift+Up/Down select a range and Ctrl+Space toggles without adding; Shift+F10 or the Menu key opens the row menu over the row on its first item, every item (Add All in Scope, Copy Signal Path, Add Selected, Apply Decoder to Selection) runs from the keyboard, and closing it returns focus to the row; NVDA reads the instructions once, then "name, button, collapsed/expanded, N signals" or "name, [msb:0], button, selected" — `[Coverage: UNIT + WIDGET]` (`signal_tree_navigation_test.dart`, `signal_tree_row_list_test.dart`, `signal_tree_menu_anchor_test.dart`, `test/accessibility/screen_reader_test.dart` with `goldens/signal_tree.txt`) + `[Coverage: MANUAL]` (real screen reader)

---

## 2B. Bulk signal removal (§4B)

Fixture: `vcd/parameter_multiselect.vcd`.

- [ ] **Remove All in Scope** sits directly below Add All in Scope on a scope's menu; removes that scope's signals (nested scopes and grouped rows too, groups kept) in one update; "Removed N signals" + **Undo** restores them in place; none on the canvas → "No signals from this scope are on the canvas" — `[Coverage: WIDGET]` (`test/features/signal_tree/widgets/scope_tree_node_test.dart` — "Remove All in Scope")
- [ ] Signals list multi-select: Shift+click range, Cmd/Ctrl+click toggle, highlighted rows report `selected`; **Delete** and **Backspace** remove the selection in one update with **Undo**; **Remove Selected** on a selected row only — `[Coverage: WIDGET]` (`test/features/viewer/widgets/signal_list_panel_test.dart` — "bulk removal")
- [ ] Video Scene 3 flow: right-click scope → Remove All in Scope → Undo → signals return → Shift+click three rows → Delete — `[Coverage: WIDGET]` (same file — "video scene") + `[Coverage: MANUAL]` (§4B.3 steps 1–3)
- [ ] Group header menu: **Ungroup** keeps the signals; **Remove Group and Signals** removes header + rows with **Undo** — `[Coverage: WIDGET + UNIT]` (`signal_list_panel_test.dart`, `signal_group_providers_test.dart` — "bulk removal")
- [ ] **View → Clear Canvas** (and palette) empties the active tab only, keeps cursor/markers/decoders/zoom, greyed on an empty canvas, "Canvas cleared" + **Undo**; **Edit → Remove Selected Signals** matches Delete — `[Coverage: WIDGET + UNIT]` (`viewer_screen_test.dart` — "Clear Canvas empties the ACTIVE TAB's list", `active_tab_action_flags_provider_test.dart`)
- [ ] Save after Clear Canvas → reopen → canvas stays empty — `[Coverage: UNIT]` (`session_providers_test.dart` — "a cleared canvas saves as an empty list") + `[Coverage: MANUAL]` (§4B.3 step 10)
- [ ] New menu items and snackbars render in zh_CN / ja / ko without exceptions — `[Coverage: WIDGET]` (locale sweeps in the three files above and `signal_removal_feedback_test.dart`)
- [ ] Clearing several thousand signals is one rebuild burst with no raster fault — `[Coverage: MANUAL]` (§4B.4)

---

## 3. Open Core protocol decoders

### Decoder picker

- [ ] Picker is grouped into collapsible category sections (`ExpansionTile` per populated `DecoderCategory`); empty categories not shown — `[Coverage: WIDGET]` (`test/features/decoders/widgets/decoder_picker_dialog_test.dart`)
- [ ] Section order on open-core: **Serial Bus (3) → AMBA (3)**, locale-independent (verified across en / zh-CN / ja / ko) — `[Coverage: WIDGET]` (`test/features/decoders/widgets/decoder_picker_dialog_open_core_set_test.dart` — "section ordering across locales" parameterized over en/zh/ja/ko, asserts Serial Bus above AMBA via y-coordinate)
- [ ] Decoder parameter labels / descriptions / enum-value labels localize via the `decoderConfigLabelResolverFactoryProvider` ARB-key indirection (SPI/RISC-V/I²C/AHB-Lite/Wishbone/SPI-Flash) with raw `displayName` fallback for plugin decoders; acronyms preserved in CJK — `[Coverage: WIDGET + UNIT]` (`test/features/decoders/providers/decoder_config_label_resolver_provider_test.dart` locale sweep, `test/domain/models/decoder_parameter_test.dart`)
- [ ] Section header uses the `pickerCategoryHeader` format `<Localized Name> (<count>)` — `[Coverage: WIDGET]` (`decoder_picker_dialog_test.dart` — "renders the localized category label in section header")
- [ ] All sections start expanded; collapse/expand toggle works — `[Coverage: WIDGET]` (`test/features/decoders/widgets/decoder_picker_dialog_test.dart` — "all categories initially expanded — children visible" + "tapping section header collapses children, tapping again re-expands")
- [ ] Lists exactly the 8 Open Core decoders (SPI, I²C, UART, AXI4-Lite, APB, AHB-Lite, Wishbone, RISC-V) — no Pro decoders visible — `[Coverage: WIDGET]` (`test/features/decoders/widgets/decoder_picker_dialog_open_core_set_test.dart` — "full-set enumeration" asserts all 8 decoders visible, `DecoderRegistry.listDecoders()` length 8, and no `FeatureTierBadge`/`PRO`/`ENT` chips render)
- [ ] SPI/I²C/UART → Serial Bus; AXI4-Lite/APB/AHB-Lite/Wishbone → AMBA — `[Coverage: WIDGET]` (`test/features/decoders/widgets/decoder_picker_dialog_open_core_set_test.dart` — "category assignment" asserts each decoder appears under its expected ExpansionTile via `find.descendant`, plus a regression guard that the other 5 categories do not render)
- [ ] Required-signal validation blocks Apply when bindings are incomplete — `[Coverage: WIDGET]` (`test/features/decoders/widgets/decoder_config_dialog_test.dart`)
- [ ] Auto-bind bus coherence: when a trace exposes the same bus under two scopes (e.g. master interface `tb.M_*` + DUT internals `tb.DUV.*`), auto-bind does not mix scopes — fuzzy (Tier D) matches are confined to the Tier A winning scope, so a coherent bus is bound (or signals left unbound for the user to pick) rather than an incoherent cross-scope mix — `[Coverage: UNIT]` (`test/services/decoders/decoder_auto_bind_service_test.dart` — "Bus coherence guard" group: cross-scope fuzzy suppressed, in-scope fuzzy still binds)
- [ ] Instance numbering: SPI #1, SPI #2, …, with no number reuse — `[Coverage: WIDGET]` (`test/features/decoders/providers/active_decoders_provider_test.dart` — "increments instanceNumber per decoder type" + "instanceNumber is not reused after removeDecoder" + "resets instanceNumber counter so new decoders start from 1" after clearAll)
- [ ] Reconfigure existing decoder → transactions re-decode — `[Coverage: WIDGET]` (`test/features/decoders/providers/active_decoders_provider_test.dart` — "replaces config for matching id" covers the config-update side; transactions are populated by a subsequent `decodeAll` call as covered in "populates transactions for registered decoder")

### SPI

- [ ] `protocol/spi/generated/spi_basic.vcd` decodes match `spi_basic.expected_transactions.json` — `[Coverage: WIDGET]` (`test/services/decoders/spi_decoder_test.dart` — fixture round-trip)
- [ ] All four CPOL/CPHA modes verified — `[Coverage: WIDGET]` (`test/services/decoders/spi_decoder_test.dart` — parameterized over modes)
- [ ] MSB-first vs LSB-first toggle effects observed — `[Coverage: WIDGET]` (`test/services/decoders/spi_decoder_test.dart`)
- [ ] Glitch case flagged as error — `[Coverage: WIDGET]` (`test/services/decoders/spi_decoder_test.dart`)
- [ ] Wrong bindings don't crash — `[Coverage: WIDGET]` (`test/services/decoders/spi_decoder_test.dart`)
- [ ] SPI activates from picker → real FFI parse → transactions render in transaction-table panel — `[Coverage: INTEGRATION_TEST — pending]`
- [ ] Captured fixture `nandland_spi_master_mode3_loopback.fst` (MIT-licensed nandland/spi-master `SPI_Master_With_Single_CS` in mode-3 self-loopback) decodes to 1 transaction matching the committed snapshot — `[Coverage: WIDGET]` (`test/services/decoders/spi_captured_fixtures_test.dart` — fixture auto-discovery sweep, <1 s)
- [ ] Captured `nandland_spi_master_mode3_loopback.fst` activates end-to-end through the decoder picker — `[Coverage: INTEGRATION_TEST]` (`integration_test/decoders/spi_captured_integration_test.dart`)

### I²C

- [ ] `protocol/i2c/generated/i2c_basic.vcd` 4 known transactions match the expected JSON — `[Coverage: WIDGET]` (`test/services/decoders/i2c_decoder_test.dart`)
- [ ] NACK on address flagged as error — `[Coverage: WIDGET]` (`test/services/decoders/i2c_decoder_test.dart`)
- [ ] Repeated START decoded as single compound transaction — `[Coverage: WIDGET]` (`test/services/decoders/i2c_decoder_test.dart`)
- [ ] Captured fixture `i2c_forencich_master_slave.fst` (real SDA/SCL traffic from `i2c_master` writing to an addressed `i2c_slave` on an open-drain bus, `alexforencich/verilog-i2c` @ `a65be40`, MIT) decodes to 2 transactions matching the committed snapshot — `I²C 0x50 W 2 bytes` (0xAB 0xCD) and `I²C 0x50 W 0x42` — `[Coverage: WIDGET]` (`test/services/decoders/i2c_captured_fixtures_test.dart` — fixture auto-discovery sweep, <1 s). No cocotb or MyHDL dependency — pure-Verilog testbench under `helpers/forencich/`, documented in `helpers/forencich/README.md`.
- [ ] Captured `i2c_forencich_master_slave.fst` activates end-to-end through the decoder picker — `[Coverage: INTEGRATION_TEST]` (`integration_test/decoders/i2c_captured_integration_test.dart`)
- [ ] Tap-to-jump on canvas blocks works — `[Coverage: INTEGRATION_TEST — pending]` (canvas tap-on-transaction → cursor jump; gesture arena interaction; queued)

### UART

- [ ] `protocol/uart/generated/uart_basic.vcd` decodes match expected JSON — `[Coverage: WIDGET]` (`test/services/decoders/uart_decoder_test.dart`)
- [ ] Parity error flagged — `[Coverage: WIDGET]` (`test/services/decoders/uart_decoder_test.dart`)
- [ ] Framing error flagged — `[Coverage: WIDGET]` (`test/services/decoders/uart_decoder_test.dart`)
- [ ] **Auto-timescale regression**: 1 ps timescale VCD decodes correctly with no manual config — `[Coverage: WIDGET]` (`test/services/decoders/uart_decoder_test.dart` — auto-timescale-derivation case is the documented regression catch)
- [ ] **Captured-fixture sweep** (3 ben-marshall/uart FSTs at 9600 / 115200 / 11520 bps) decode matches the per-fixture `.expected_transactions.json` snapshots and the `PROVENANCE.md` hand-verified anchors — `[Coverage: WIDGET]` (`test/services/decoders/uart_captured_fixtures_test.dart` auto-discovers every fixture under `test/fixtures/protocol/uart/captured/`)
- [ ] Captured `ben_marshall_tx_9600bps.fst` activates end-to-end through the decoder picker and surfaces 1 grouped 20-byte transaction — `[Coverage: INTEGRATION_TEST]` (`integration_test/decoders/uart_captured_integration_test.dart`)

**Bit timing (P46, wavecrux b0a517ba).** A UART in an HDL testbench is written
against a clock and a `CLKS_PER_BIT` constant; nobody picks a baud. Scenario 04
decoded to *nothing* because the design ran at 12.5 Mbaud and the decoder
defaulted to 9600. Note while verifying: a wrong bit period does **not**
generally produce silence — it produces confident garbage. 9600 was wrong by
four orders of magnitude; a subtler mismatch decodes plausible wrong bytes.

- [ ] **`timing_mode` defaults to `baud`** and an omitted parameter behaves exactly as before — every decoder config already in the wild omits it — `[Coverage: WIDGET]` (`test/services/decoders/uart_timing_mode_test.dart`)
- [ ] **`clocks_per_bit` decodes the scenario-04 trace** (`always #5 clk`, `CLKS_PER_BIT = 8`, 1 ns timescale) that `baud_rate = 9600` finds nothing in — the reproduction and the fix in one file — `[Coverage: WIDGET]` (same file)
- [ ] **Clocks-per-bit and the equivalent baud agree** (12.5 Mbaud ≡ 8 clocks at a 10 ns period) — proves it is a restatement of the timing, not a second decode path — `[Coverage: WIDGET]` (same file)
- [ ] **The clock period is measured, not assumed** — halving the clock changes the decoded byte; a gated clock's idle stretch does not skew it, because the median inter-edge gap is used rather than the mean — `[Coverage: WIDGET]` (same file)
- [ ] **`clocks_per_bit` without a bound `clk` decodes nothing** rather than inventing a period — `[Coverage: WIDGET]` (same file)
- [ ] **`auto` recovers the bit period from the line** at two different bit periods without being told — GCD of inter-edge gaps, falling back to the shortest gap when the GCD collapses under jitter — `[Coverage: WIDGET]` (same file)
- [ ] **The `clk` binding is optional**, so a TX-only capture still configures with two clicks — `[Coverage: WIDGET]` (same file)
- [ ] **The picker shows all three modes with readable labels** and the parameter descriptions say which mode each of `baud_rate` / `clocks_per_bit` applies to — `[Coverage: MANUAL]`

### AXI4-Lite

- [ ] `protocol/axi4lite/generated/axi4lite_basic.vcd` reads/writes match expected JSON — `[Coverage: WIDGET]` (`test/services/decoders/axi4lite_decoder_test.dart`)
- [ ] SLVERR / DECERR flagged as errors — `[Coverage: WIDGET]` (`test/services/decoders/axi4lite_decoder_test.dart`)
- [ ] Back-to-back transactions kept separate — `[Coverage: WIDGET]` (`test/services/decoders/axi4lite_decoder_test.dart`)
- [ ] Captured fixture `forencich_axil_ram.fst` (9-scenario AXI4-Lite RAM exerciser — 4 writes, 4 reads, 1 stress — from `alexforencich/verilog-axi` @ `516bd5d`, MIT) decodes to 3712 transactions matching the committed snapshot — `[Coverage: WIDGET]` (`test/services/decoders/axi4lite_captured_fixtures_test.dart` — fixture auto-discovery sweep, <2 s). Capture pipeline (cocotb venv + `iverilog_dump.v` aresetn patch) mirrors the Pro AXI4 Full pipeline; documented in `helpers/cocotb_setup.md`.
- [ ] Captured `forencich_axil_ram.fst` activates end-to-end through the decoder picker — `[Coverage: INTEGRATION_TEST]` (`integration_test/decoders/axi4lite_captured_integration_test.dart`)

### APB

- [ ] `protocol/apb/generated/apb_basic.vcd` 4 transactions match expected JSON — `[Coverage: WIDGET]` (`test/services/decoders/apb_decoder_test.dart`)
- [ ] IDLE → SETUP → ACCESS state machine correctly identified (no spurious incomplete-transaction warnings) — `[Coverage: WIDGET]` (`test/services/decoders/apb_decoder_test.dart`)
- [ ] PREADY wait state decoded as single transaction — `[Coverage: WIDGET]` (`test/services/decoders/apb_decoder_test.dart`)
- [ ] PSLVERR transaction flagged as error — `[Coverage: WIDGET]` (`test/services/decoders/apb_decoder_test.dart`)
- [x] Multi-instance (APB #1 + APB #2) work independently — `[Coverage: WIDGET]` (`test/features/decoders/providers/active_decoders_provider_test.dart` — "increments instanceNumber per decoder type" + "appends multiple decoders in order" + "leaves other decoders unchanged" cover the multi-instance state model; APB-specific decode-correctness covered by `test/services/decoders/apb_decoder_test.dart`) + `[Coverage: INTEGRATION_TEST]` (`integration_test/decoders/apb_integration_test.dart` — "APB #1 + APB #2" picker-activation scenario)
- [ ] Captured fixture `apb_axil2apb.fst` (AXI-Lite → APB bridge traffic from `ZipCPU/wb2axip` @ `df8e7649`, Apache-2.0 — Gisselquist `axil2apb` driving `apbslave`) decodes to 10 transactions matching the committed snapshot, including a partial-strobe write (`PWSTRB=0x3`) whose readback yields `0xDEADC0DE` from a prior `0xDEADBEEF` — `[Coverage: WIDGET]` (`test/services/decoders/apb_captured_fixtures_test.dart` — fixture auto-discovery sweep, <1 s). No cocotb dependency — pure-Verilog testbench under `helpers/apb/`, documented in `helpers/apb/README.md`.
- [ ] Captured `apb_axil2apb.fst` activates end-to-end through the decoder picker — `[Coverage: INTEGRATION_TEST]` (`integration_test/decoders/apb_captured_integration_test.dart`)

### Wishbone (Open Core)

- [ ] `protocol/wishbone/generated/wishbone_b3_classic_basic.vcd` 4 transactions match expected JSON (W ack, R ack, R err, W rty) — `[Coverage: WIDGET]` (`test/services/decoders/wishbone_decoder_test.dart`)
- [ ] `protocol/wishbone/generated/wishbone_b3_burst_incr.vcd` linear (BTE=00) incrementing burst: 4 child beats + 1 parent record — `[Coverage: WIDGET]` (`wishbone_decoder_test.dart` — fixture round-trip)
- [ ] `protocol/wishbone/generated/wishbone_b3_burst_wrap.vcd` 4-beat wrap (BTE=01) addresses cycle `0x108 → 0x10C → 0x100 → 0x104` AND constant-address (CTI=001) burst preserves `0x200` across beats — `[Coverage: WIDGET]` (`wishbone_decoder_test.dart` — fixture round-trip)
- [ ] `protocol/wishbone/generated/wishbone_b3_classic_violations.vcd` exercises every B3 violation class (mutex termination, STB-without-CYC, termination-without-CYC, WE mid-cycle, const-burst ADR change, incrementing-burst WE/SEL/ADR change, reserved CTI, BTE-with-classic-CTI, misalignment) — `[Coverage: WIDGET]` (`wishbone_decoder_test.dart`)
- [ ] `check_alignment=false` parameter suppresses misalignment violation while leaving other 8 violations active — `[Coverage: WIDGET]` (`wishbone_decoder_test.dart`)
- [ ] `protocol/wishbone/generated/wishbone_b4_pipelined_basic.vcd` 2 transactions decode with `cycle=Pipelined` and per-request `latency` field — `[Coverage: WIDGET]` (`wishbone_decoder_test.dart` — fixture round-trip)
- [ ] `protocol/wishbone/generated/wishbone_b4_pipelined_stall.vcd` 3 outstanding requests matched in FIFO order at `0x100`/`0x104`/`0x108` — `[Coverage: WIDGET]` (`wishbone_decoder_test.dart` — fixture round-trip)
- [ ] B4 selected with `stall` unbound emits a single warning transaction and falls back to classic decode — `[Coverage: WIDGET]` (`wishbone_decoder_test.dart`)
- [ ] `protocol/wishbone/generated/wishbone_b4_pipelined_violations.vcd` flags signal-change-while-stalled (B4-only violation) and mutex-termination — `[Coverage: WIDGET]` (`wishbone_decoder_test.dart` — fixture round-trip)
- [ ] Multi-instance Wishbone #1 (B3) + Wishbone #2 (B4) work independently with separate parameter sets — `[Coverage: WIDGET]` (`test/features/decoders/providers/active_decoders_provider_test.dart` — multi-instance state model; Wishbone-specific decode covered above)
- [ ] Per-instance configuration round-trips through session save/load (revision, addr_width, data_width, granularity, endianness, check_alignment) — `[Coverage: MANUAL]`
- [ ] CTI/BTE unbound: every cycle decodes as Classic with no spurious violations — `[Coverage: WIDGET]` (`wishbone_decoder_test.dart`)
- [ ] Wishbone entry appears under AMBA category in the decoder picker (CJK locale sweep — en/zh_CN/zh/ja/ko all render) — `[Coverage: WIDGET]` (`test/features/decoders/widgets/decoder_picker_dialog_open_core_set_test.dart`)
- [ ] Captured fixture `wishbone_picorv32_wb_ez.fst` (real RV32I ifetch + load/store loop running on `picorv32_wb` from `YosysHQ/picorv32` @ `87c89ac`, ISC) decodes to 10 B3 Classic transactions matching the committed snapshot, including a `W 0x3FC = 0x00000000` counter init and `W 0x3FC = 0x00000001` showing the increment + branch-back round-trip — `[Coverage: WIDGET]` (`test/services/decoders/wishbone_captured_fixtures_test.dart` — fixture auto-discovery sweep, <1 s). No cocotb or RISC-V toolchain dependency — pure-Verilog testbench under `helpers/picorv32/`, documented in `helpers/picorv32/README.md`.
- [ ] Captured `wishbone_picorv32_wb_ez.fst` activates end-to-end through the decoder picker — `[Coverage: INTEGRATION_TEST]` (`integration_test/decoders/wishbone_captured_integration_test.dart`)

### AHB-Lite (Open Core)

- [ ] `protocol/ahb_lite/generated/ahb_lite_single_basic.vcd` 2 transactions (R + W OKAY) match expected JSON — `[Coverage: WIDGET]` (`test/services/decoders/ahb_lite_decoder_test.dart` — "SINGLE basic fixture" group)
- [ ] `protocol/ahb_lite/generated/ahb_lite_incr_burst.vcd` INCR4 read burst: 4 child beats + 1 parent record (`burst_id`/`beat_index` linkage) — `[Coverage: WIDGET]` (`ahb_lite_decoder_test.dart` — fixture round-trip)
- [ ] `protocol/ahb_lite/generated/ahb_lite_wrap_burst.vcd` WRAP4 burst wraps inside 16-byte window: `0x108 → 0x10C → 0x100 → 0x104` (start mid-window is valid) — `[Coverage: WIDGET]` (`ahb_lite_decoder_test.dart` — fixture round-trip)
- [ ] `protocol/ahb_lite/generated/ahb_lite_incr_undefined.vcd` INCR (undefined) burst with mid-burst BUSY: 3 beats + 1 parent, BUSY does not produce an extra beat — `[Coverage: WIDGET]` (`ahb_lite_decoder_test.dart` — fixture round-trip)
- [ ] `protocol/ahb_lite/generated/ahb_lite_wait_states.vcd` SINGLE read with 2 wait states recorded in `fields["wait_states"]` — `[Coverage: WIDGET]` (`ahb_lite_decoder_test.dart` — fixture round-trip)
- [ ] `protocol/ahb_lite/generated/ahb_lite_error_response.vcd` two-cycle ERROR handshake produces a single ERROR beat without violation 7 surfacing — `[Coverage: WIDGET]` (`ahb_lite_decoder_test.dart` — fixture round-trip)
- [ ] `protocol/ahb_lite/generated/ahb_lite_locked_transfer.vcd` HMASTLOCK and HPROT (decoded into named flags) propagate into transaction `fields` when the optional signals are bound; absent when unbound — `[Coverage: WIDGET]` (`ahb_lite_decoder_test.dart` — "locked transfer fixture" + "optional bindings" groups)
- [ ] `protocol/ahb_lite/generated/ahb_lite_violations.vcd` exercises the 7 detectable violation classes (BUSY-in-SINGLE, SEQ-without-NONSEQ, HBURST-mid-burst-change, HADDR-not-expected-next, HSIZE-wider-than-data_width, misalignment, single-cycle-ERROR) — `[Coverage: WIDGET]` (`ahb_lite_decoder_test.dart` — "protocol violations fixture" group)
- [ ] `check_alignment=false` parameter suppresses misalignment violation while leaving the other 6 violations active — `[Coverage: WIDGET]` (`ahb_lite_decoder_test.dart` — "check_alignment parameter" group)
- [ ] `data_width=64` parameter unlocks HSIZE=doubleword without violation 5 — `[Coverage: WIDGET]` (`ahb_lite_decoder_test.dart` — "data_width parameter" group)
- [ ] Reset mid-burst flushes the burst-parent record and a fresh transfer after reset decodes normally — `[Coverage: WIDGET]` (`ahb_lite_decoder_test.dart` — "reset" group)
- [ ] Multi-instance AHB-Lite #1 + #2 with different parameter sets work independently — `[Coverage: WIDGET]` (`ahb_lite_decoder_test.dart` — "multi-instance independence" group; provider-level state model in `test/features/decoders/providers/active_decoders_provider_test.dart`)
- [ ] Per-instance configuration round-trips through session save/load (addr_width, data_width, check_alignment, wait_state_threshold) — `[Coverage: UNIT]` (`test/services/session/session_decoder_round_trip_test.dart` — "two AHB-Lite instances round-trip distinct mixed-type per-instance configuration"; asserts integer params survive without int→double coercion and instances stay independent). Full in-app loop still MANUAL (§5.8.8).
- [ ] Wait-state warning (violation 8) fires when `wait_state_threshold` is set below the actual stall length — `[Coverage: WIDGET]` (`ahb_lite_decoder_test.dart` — "wait_state warning (violation 8) at threshold exceeded" lowers the threshold on `ahb_lite_wait_states.vcd` and asserts the "HREADY held low" warning)
- [ ] Address-phase signal stability during wait state (IHI 0033 §3.4) is intentionally NOT detected by this decoder — relies on simulator assertions; no checklist item beyond an awareness note — `[Coverage: MANUAL]`
- [ ] AHB-Lite entry appears under AMBA category in the decoder picker (CJK locale sweep — en/zh_CN/zh/ja/ko all render) — `[Coverage: WIDGET]` (`test/features/decoders/widgets/decoder_picker_dialog_open_core_set_test.dart`)
- [ ] Captured fixture `ahb_lite_shalan_dmac.fst` (real AHB-Lite master traffic from `MS_DMAC_AHBL` doing 5 word reads from `0x4000_0000…0x4000_0010` and 5 word writes to `0x5000_0000…0x5000_0010`, `shalan/MS_DMAC_AHBL` @ `d2ea9e3`, Apache-2.0) decodes to 10 SINGLE-beat transactions matching the committed snapshot — `[Coverage: WIDGET]` (`test/services/decoders/ahb_lite_captured_fixtures_test.dart` — fixture auto-discovery sweep, <1 s). No UVM/cocotb dependency — pure-Verilog testbench under `helpers/shalan/` configuring the DMAC and capturing its master port; HBURST/HRESP tied to constants (SINGLE/OKAY) since the DMAC doesn't model bursts or error responses. Documented in `helpers/shalan/README.md`.
- [ ] Captured `ahb_lite_shalan_dmac.fst` activates end-to-end through the decoder picker — `[Coverage: INTEGRATION_TEST]` (`integration_test/decoders/ahb_lite_captured_integration_test.dart`)

### RISC-V instruction trace (Open Core)

- [ ] All 10 bundled `assets/decoders/isa/riscv/*.toml` files parse cleanly — `[Coverage: WIDGET]` (`test/services/decoders/isa/instruction_set_toml_loader_test.dart`)
- [ ] All 10 TOMLs are **discovered** from the asset manifest (not a hardcoded filename list), under both the bare `assets/decoders/isa/riscv/` key and the `packages/wavecrux/` key used when wavecrux is a path dependency — `[Coverage: WIDGET]` (`test/services/decoders/isa/isa_decoder_assets_test.dart`)
- [ ] Discovered sets load in a deterministic order with RV32I before RV64I, independent of manifest iteration order, and the RV32I/RV64I shift-immediates remain the only cross-set encoding ambiguity in the corpus — `[Coverage: WIDGET]` (`test/services/decoders/isa/isa_set_load_order_test.dart`)
- [ ] `protocol/riscv/generated/riscv_rv32i_basic.vcd` 6 transactions match expected JSON (one per RV32I format type: R/I-ALU/S/I-Load/U/system) — `[Coverage: WIDGET]` (`test/services/decoders/isa/riscv_decoder_test.dart`)
- [ ] `protocol/riscv/generated/riscv_rv32im_arith.vcd` mul/div decode under `ext_m=true` — `[Coverage: WIDGET]` (`riscv_decoder_test.dart`)
- [ ] `protocol/riscv/generated/riscv_rv32im_arith.vcd` decodes as UNKNOWN INSN under `ext_m=false` (extension gating) — `[Coverage: WIDGET]` (`riscv_decoder_test.dart`)
- [ ] `protocol/riscv/generated/riscv_rv64i_basic.vcd` ld/sd/addw + redefined 6-bit-shamt slli decode under `xlen=64` — `[Coverage: WIDGET]` (`riscv_decoder_test.dart`)
- [ ] `protocol/riscv/generated/riscv_pc_present.vcd` PC appears in label `[0x…]` and in `fields["pc"]` (XLEN=32 → 8-nibble) — `[Coverage: WIDGET]` (`riscv_decoder_test.dart`)
- [ ] `valid` signal gating skips low-valid cycles — `[Coverage: WIDGET]` (`riscv_decoder_test.dart`)
- [ ] x/z on `instruction` silently skips that cycle — `[Coverage: WIDGET]` (`riscv_decoder_test.dart`)
- [ ] Unknown encoding emits `UNKNOWN INSN (0x…)` error transaction with `isError = true` — `[Coverage: WIDGET]` (`riscv_decoder_test.dart`)
- [ ] Sign extension of I-type signed immediates (e.g. `addi t0, t1, -1`) — `[Coverage: WIDGET]` (`test/services/decoders/isa/instruction_disassembler_test.dart`)
- [ ] U-type `unsigned = true` flips imm to hex-unsigned (e.g. `lui a0, 0xfffff`) — `[Coverage: WIDGET]` (`instruction_disassembler_test.dart`)
- [ ] "Instruction Trace" category appears in decoder picker (CJK locale sweep — en/zh_CN/zh/ja/ko all render) — `[Coverage: MANUAL]`
- [ ] Surfer `instruction-decoder` `.toml` file (drop-in from <https://github.com/ics-jku/instruction-decoder>) loads and decodes equivalently — `[Coverage: MANUAL]` (cross-tool compatibility per VERIFICATION_GUIDE.md §5.9.8)
- [ ] Captured fixture `riscv_picorv32_wb_ez.fst` (real RV32I ifetch trace from `picorv32_wb` driven by hand-encoded RV32I memory image, `YosysHQ/picorv32` @ `87c89ac`, ISC) decodes to 7 transactions matching the committed snapshot, covering one full loop iteration plus the wrap-around fetch after the `jal` backward branch — `[Coverage: WIDGET]` (`test/services/decoders/riscv_captured_fixtures_test.dart` — fixture auto-discovery sweep, <1 s). No cocotb or RISC-V toolchain dependency — pure-Verilog testbench under `helpers/picorv32/` connecting `picorv32_wb`'s `mem_instr` port to a derived `ifetch_valid` strobe, documented in `helpers/picorv32/README.md`.
- [ ] Captured `riscv_picorv32_wb_ez.fst` activates end-to-end through the decoder picker — `[Coverage: INTEGRATION_TEST]` (`integration_test/decoders/riscv_captured_integration_test.dart`)
- [ ] Captured fixture `riscv_ibex_rvfi_trap.fst` (real RVFI retire stream from lowRISC's Ibex @ `3250d994`, Apache-2.0, Verilator 5.050 `+define+RVFI`) decodes to 26 transactions matching the committed snapshot — `[Coverage: WIDGET]` (`test/services/decoders/riscv_captured_fixtures_test.dart` — fixture auto-discovery sweep). Three rows read `UNKNOWN INSN` (two `csrrs`, one `wfi`) and that is correct: no Zicsr TOML ships in `assets/decoders/isa/riscv/`. No cocotb, no RISC-V toolchain — program hand-encoded by `helpers/ibex/assemble.py`, recipe in `helpers/ibex/README.md`.
- [ ] The RVFI substrate against that same capture: auto-detection binds all 21 channels at the real two-deep scope `tb_ibex_rvfi.u_ibex_top` without binding any `rvfi_ext_*` sibling; retire reconstruction yields 26 retirements with dense `rvfi_order` 1–26 and real byte masks — `[Coverage: UNIT]` (`test/services/riscv/riscv_ibex_captured_rvfi_test.dart`)
- [ ] The consistency checker against that capture reports **exactly 19 violations of exactly one kind** (`memoryAccessUnexpected`), with the other five rules clean — the one documented upstream Ibex RVFI deviation, pinned rather than suppressed — `[Coverage: UNIT]` (same; rationale in VERIFICATION_GUIDE.md §10B.1.10)
- [ ] `controlFlow` and `trapConsistency` stay silent at the `ecall`, because the handler's first retirement asserts `rvfi_intr` — the RVFI handler-entry exemption, corrected 2026-08-20 — `[Coverage: UNIT]` (same)
- [ ] **Optional**: authentic Verilator-generated trace decodes consistently with picorv32 source program — `[Coverage: MANUAL]` (recipe in VERIFICATION_GUIDE.md §5.9.10; not required for sign-off)

### SPI flash command decoder (Open Core)

- [ ] `parentDecoderId` field on `SpiFlashDecoder.decoderDefinition` is `'spi'` — `[Coverage: WIDGET]` (`test/services/decoders/spi_flash/spi_flash_decoder_test.dart` — "definition parentDecoderId is spi")
- [ ] `protocol/spi_flash/generated/spi_flash_rdid.vcd` → 1 transaction: label **RDID**, `jedec_id = 0xEF-0x40-0x18` — `[Coverage: WIDGET]` (`spi_flash_decoder_test.dart` — fixture: spi_flash_rdid group)
- [ ] `protocol/spi_flash/generated/spi_flash_wren_pp.vcd` → 2 transactions: **WREN** then **PP** at 0x012000 with data 0xAA 0xBB — `[Coverage: WIDGET]` (`spi_flash_decoder_test.dart` — fixture: spi_flash_wren_pp group)
- [ ] `protocol/spi_flash/generated/spi_flash_read.vcd` → 1 transaction: **READ** at 0x001000, data 0x55 0xAA — `[Coverage: WIDGET]` (`spi_flash_decoder_test.dart` — fixture: spi_flash_read group)
- [ ] `protocol/spi_flash/generated/spi_flash_wren_se.vcd` → 2 transactions: **WREN** then **SE** at 0x010000 — `[Coverage: WIDGET]` (`spi_flash_decoder_test.dart` — fixture: spi_flash_wren_se group)
- [ ] `protocol/spi_flash/generated/spi_flash_wel_violation.vcd` → 1 error transaction: **PP** with `errorMessage = write_without_wel` — `[Coverage: WIDGET]` (`spi_flash_decoder_test.dart` — fixture: spi_flash_wel_violation group)
- [ ] `protocol/spi_flash/generated/spi_flash_rdsr.vcd` → 1 transaction: **RDSR** with `status` field — `[Coverage: WIDGET]` (`spi_flash_decoder_test.dart` — fixture: spi_flash_rdsr group)
- [ ] `protocol/spi_flash/generated/spi_flash_fast_read.vcd` → 1 transaction: **FAST_READ** at 0x002000, data 0xAB (1 dummy byte consumed) — `[Coverage: WIDGET]` (`spi_flash_decoder_test.dart` — fixture: spi_flash_fast_read group)
- [ ] Stacked decoder entry appears in picker only when SPI decoder is already active — `[Coverage: WIDGET]` (`decoder_picker_dialog_stacked_test.dart` — "no Stacked Decoders section when no parent decoder is active" + the SPI-active appearance case)
- [ ] No PRO/ENT tier badge renders on Open Core picker rows (parent SPI + stacked SPI Flash) — `[Coverage: WIDGET]` (`decoder_picker_dialog_stacked_test.dart` — "no PRO/ENT FeatureTierBadge renders on Open Core picker rows" asserts `find.byType(WaveCruxFeatureTierBadge)` is `findsNothing`)
- [ ] No PRO tier badge on the SPI flash decoder picker row (Open Core) — `[Coverage: MANUAL]` (VERIFICATION_GUIDE.md §5.10.8)
- [ ] WEL state machine: double WREN → second WREN is `double_wren` error — `[Coverage: WIDGET]` (`spi_flash_decoder_test.dart` — "WREN (0x06) double WREN → double_wren error on second")
- [ ] WRDI clears WEL → subsequent PP → `write_without_wel` — `[Coverage: WIDGET]` (`spi_flash_decoder_test.dart` — "WREN (0x06) WRDI clears WEL so subsequent PP → write_without_wel")
- [ ] Captured fixture `picorv32_spiflash_single_wire.fst` (ISC-licensed YosysHQ/picorv32 `spiflash` model exercising RDID + READ + FAST_READ) decodes to 3 transactions matching the committed snapshot — `[Coverage: WIDGET]` (`test/services/decoders/spi_flash_captured_fixtures_test.dart` — fixture auto-discovery sweep, <1 s)
- [ ] Captured `picorv32_spiflash_single_wire.fst` activates end-to-end through the decoder picker (SPI parent + SPI Flash stacked) — `[Coverage: INTEGRATION_TEST]` (`integration_test/decoders/spi_flash_captured_integration_test.dart`)

### Transaction overlay & table

- [ ] Colored blocks render on transaction lane; error blocks visually distinct — `[Coverage: WIDGET]` (`test/features/viewer/widgets/waveform_canvas_transaction_test.dart`)
- [ ] Zoom-Fit on a large decode draws density bars (not a blank/partial lane), error bars stay red, and bars resolve into labelled blocks as you zoom in — `[Coverage: UNIT]` (`test/features/viewer/rendering/transaction_painter_test.dart` — "density coalescing" + "visible window" groups; perceptual smoothness MANUAL)
- [ ] Multi-decoder lanes coexist without collision — `[Coverage: WIDGET]` (`test/features/viewer/widgets/waveform_canvas_transaction_test.dart` — "renders multiple decoder lanes without exception" exercises the canvas layout path with a second decoder added)
- [ ] Tap block → cursor jumps + viewport pans — `[Coverage: INTEGRATION_TEST — pending]` (gesture arena + viewport pan; queued)
- [ ] Table populates, sorts, filters, CSV-exports — `[Coverage: WIDGET]` (`test/features/decoders/widgets/transaction_table_panel_test.dart`)
- [ ] **Transaction table from the keyboard and a screen reader (§5.12.4)**: Decoder filter is a named button (value = current filter) whose menu opens on its first item with Enter/Space, with Configure {decoder} / Remove {decoder} reachable and focus returning on close; sort headers are named buttons with sort state; the rows are one Tab stop (Up/Down/Home/End/Page, Left/Right scroll, Enter/Space = click) that the app keymap does not take; each row is one sentence ("2, APB #1, 25 to 35, R 0x… to 0x…", ", error: …" when flagged); arrows in decoder labels are spoken as words, visible label and snapshots unchanged — `[Coverage: UNIT + WIDGET]` (`speakable_text_test.dart`, `transaction_table_body_test.dart`, `transaction_table_panel_keyboard_test.dart`, `test/accessibility/screen_reader_test.dart` with `goldens/transaction_table.txt`) + `[Coverage: MANUAL]` (real screen reader)
- [ ] Row click → cursor jumps + on-canvas highlight — `[Coverage: WIDGET]` (`test/features/decoders/widgets/transaction_table_panel_test.dart` — "tapping a row marks transaction as selected" covers the canvas-highlight side via `selectedTransactionNotifierProvider`; "tapping a row also places primary cursor at transaction startTime" covers the cursor-jump side. Together they verify all three side-effects of `_onRowTap` — `select()`, `placePrimary()`, and `jumpToTime()` — reach their respective providers)

### Shared decoder value helpers (§5.13)

- [ ] Strict vs lenient parser split behaves per spec: strict rejects `x`/`z` (returns null), lenient coerces to `0` and otherwise agrees with strict — `[Coverage: UNIT]` (`test/services/decoders/decoder_value_helpers_test.dart`)
- [ ] `vcdVectorWidth` reports the observed bit width, so an active-low 1-bit line idling high inverts to `0` (not `0xFE`) — `[Coverage: UNIT]` (same file — "width drives an active-low inversion mask correctly")
- [ ] `vcdVectorBytesLsbFirst` is byte-identical to the `BigInt` shift-and-mask it replaces, zero-fills short vectors, and drops digits above the byte count — `[Coverage: UNIT]` (same file)
- [ ] Large payload fields render capped with a `… (+N more bytes)` suffix while the sibling `byte_count` field still reports the full size; data-path fields (`raw_frame_hex`) stay uncapped — `[Coverage: UNIT]` (same file — `bytesToHexCapped` / `joinCapped` groups; transaction-table rendering MANUAL)

---

## 4. Analysis features

### Waveform diff

- [ ] Match colors correct (green identical, red differs, gray unmatched) — `[Coverage: WIDGET]` (`test/services/diff/waveform_diff_service_test.dart` covers the diff classification; presentation `test/features/comparison/widgets/diff_summary_panel_test.dart`)
- [ ] XOR `⊕` lanes appear under red signals — `[Coverage: WIDGET — pending]` (canvas-side XOR lane rendering; check `test/features/viewer/widgets/waveform_canvas_test.dart` and queue if missing)
- [ ] Amber bands on time ruler at every divergence — `[Coverage: WIDGET — pending]` (time-ruler divergence markers; queued)
- [ ] Prev/next divergence navigation, with wrap-around — `[Coverage: WIDGET]` (`test/features/comparison/providers/diff_provider_test.dart` + `test/features/comparison/widgets/diff_toolbar_test.dart`)
- [ ] Diff summary counts correct, shown in the left pane (signal tree swaps to the diff summary panel while diff is active) — `[Coverage: WIDGET]` (`test/features/comparison/widgets/diff_summary_panel_test.dart`; left-pane swap `test/features/viewer/screens/viewer_screen_test.dart`)
- [ ] Close diff → all diff state cleared, left pane restores the signal tree — `[Coverage: WIDGET]` (`test/features/comparison/providers/diff_provider_test.dart`; left-pane restore `test/features/viewer/screens/viewer_screen_test.dart`)
- [ ] Compare file against itself → all green, 0 divergences — `[Coverage: WIDGET]` (`test/services/diff/waveform_diff_service_test.dart` — identity case)
- [ ] Open new file while diff active → diff state clears (regression catch) — `[Coverage: WIDGET]` (`test/features/comparison/providers/diff_provider_test.dart` — regression catch)

### X-Trace

- [ ] Right-click X-valued signal → "Trace X Origin" works — `[Coverage: INTEGRATION_TEST — pending]` (right-click gesture-arena interaction; service-side covered, dispatch path queued)
- [ ] Causal chain panel populates correctly — `[Coverage: WIDGET]` (`test/features/viewer/widgets/x_trace_panel_test.dart` + `test/services/signal_query/x_trace_service_test.dart`)
- [ ] Red lines + diamond markers on involved lanes only — `[Coverage: WIDGET — pending]` (canvas-side X-Trace overlay rendering; queued)
- [ ] Subtle red tint covers involved lanes from origin time rightward — `[Coverage: WIDGET — pending]`
- [ ] Click chain node → cursor jumps — `[Coverage: WIDGET]` (`test/features/viewer/widgets/x_trace_panel_test.dart`)
- [ ] Trace X Origin selects the **X-Trace** tab and opens a collapsed bottom dock (or reveals it in the right dock if moved there) — `[Coverage: UNIT]` (`test/features/viewer/providers/x_trace_provider_test.dart`, `traceXAndReveal` group)
- [ ] A refused trace still mounts the X-Trace tab, showing the localized reason in the error colour (announced to screen readers); the tab × clears it — `[Coverage: WIDGET]` (`bottom_dock_test.dart`, `x_trace_panel_test.dart` with CJK sweep)
- [ ] Open new file while X-Trace active → state clears (regression catch) — `[Coverage: WIDGET]` (provider-side state-clearing test)
- [ ] Close a tab / reload a saved workspace → the tab's per-tab `ProviderContainer` is structurally evicted (crux_workspace `WorkspaceScopeReconciler`, registered at bootstrap), so closed tabs don't leak and a revived `TabId` never inherits the dead tab's state (§6.2.4) — `[Coverage: UNIT]` (`test/services/tabs/workspace_scope_reconciler_test.dart`)

### Switching activity

- [ ] Transition counts match testbench design — `[Coverage: WIDGET]` (`test/services/signal_query/switching_activity_service_test.dart`)
- [ ] Clock detection cross-references cleanly with Signal Health — `[Coverage: WIDGET]` (cross-check between `switching_activity_service_test.dart` and `signal_health_panel_test.dart`)
- [ ] Heatmap visible on signal tree — `[Coverage: WIDGET]` (`test/features/viewer/widgets/activity_heatmap_overlay_test.dart`)
- [ ] CSV export works — `[Coverage: WIDGET]` (`test/features/viewer/widgets/activity_report_panel_test.dart`)
- [ ] Banner dismissable — `[Coverage: WIDGET]` (`test/features/viewer/widgets/activity_report_panel_test.dart`)

### Pattern search

- [ ] Builder mode AND/OR/NOT correct on known fixture — `[Coverage: WIDGET]` (`test/services/signal_query/pattern_search_service_test.dart` + `test/features/viewer/widgets/pattern_search_dialog_test.dart`)
- [ ] Expression mode parser works — `[Coverage: WIDGET]` (`test/services/signal_query/pattern_search_service_test.dart`)
- [ ] X/Z values: no parse error, 0 matches (regression catch) — `[Coverage: WIDGET]` (`test/services/signal_query/pattern_search_service_test.dart` — documented X/Z regression case)
- [ ] Match highlights on time ruler + canvas — `[Coverage: WIDGET — pending]` (canvas + time-ruler highlight rendering; queued)
- [ ] Prev/next match navigation — `[Coverage: WIDGET]` (`test/features/viewer/widgets/pattern_search_toolbar_test.dart`)
- [ ] Open new file while pattern search active → state clears — `[Coverage: WIDGET]` (provider-side regression case)

### Process filter & static translate filter

- [ ] Static `.txt` translate filter from `gtkw/sample_filter.txt` applies — `[Coverage: WIDGET]` (`test/services/translate/translate_filter_service_test.dart`)
- [ ] Process filter script `fsm_filter.sh` translates values live — `[Coverage: WIDGET]` (`test/services/translate/process_filter_service_test.dart`)
- [ ] Process kill mid-session → graceful fallback to raw values — `[Coverage: WIDGET]` (`test/services/translate/process_filter_service_test.dart`)
- [ ] Process timeout / hang → graceful fallback — `[Coverage: WIDGET]` (`test/services/translate/process_filter_service_test.dart`)
- [ ] Filter binary missing → clear error — `[Coverage: WIDGET]` (`test/services/translate/process_filter_service_test.dart`)

### GTKWave `.gtkw` session import

Fixtures live under `test/fixtures/gtkw/{generated,captured}/` (consumed directly by verification — no duplicate copy); regenerate goldens with `dart run tool/generate_gtkw_fixtures.dart`.

- [ ] `generated/simple_signals.gtkw` reconstructs signal list — `[Coverage: AUTOMATED]` (`test/services/session/gtkw_parser_test.dart` + `gtkw_import_service_test.dart`)
- [ ] `generated/groups.gtkw` reconstructs named groups — `[Coverage: AUTOMATED]` (gtkw_import_service_test.dart)
- [ ] `generated/format_flags.gtkw` reconstructs per-signal display formats — `[Coverage: AUTOMATED]` (gtkw_import_service_test.dart)
- [ ] `generated/colors_and_markers.gtkw` reconstructs colors, markers A=30/B=50 and the primary cursor at 40 (the `*` line's field 1 is GTKWave's primary marker, not marker A) — `[Coverage: AUTOMATED]` (gtkw_parser_test.dart, gtkw_import_pipeline_test.dart)
- [ ] `generated/translate_refs.gtkw` imports all five signals with none unmatched; `data` shows labels from `sample_filter.txt` (re-anchored from the `^1` absolute path via `[savefile]`); **Filters not applied (3)** lists the missing `^2` file, the `^>` filter process and the `^<` transaction filter — `[Coverage: AUTOMATED]` (gtkw_parser_test.dart, gtkw_import_service_test.dart, gtkw_golden_test.dart, gtkw_import_pipeline_test.dart)
- [ ] `.gtkw` zoom and `[timestart]` land the view where GTKWave had it (a zoom wider than the dump lands on fit-all), and `[treeopen]` scopes open in the hierarchy tree — `[Coverage: AUTOMATED]` (`test/features/viewer/providers/gtkw_import_apply_test.dart`)
- [ ] Full parse→import pipeline matches `generated/*.expected_session.json` goldens — `[Coverage: AUTOMATED]` (`test/services/session/gtkw_golden_test.dart`)
- [ ] Captured real-world saves (`captured/*.gtkw`: Sonata/Ibex, ben-marshall UART, fpxx, BubbleFifo) parse without throwing + match `*.expected_parse.json` — `[Coverage: AUTOMATED]` (gtkw_golden_test.dart captured group)
- [ ] Import orchestration applies groups/markers/colors/formats into live providers — `[Coverage: AUTOMATED]` (`test/features/viewer/gtkw_import_pipeline_test.dart`)
- [ ] End-to-end: real app + real wellen FFI parse of `fixture.vcd`, `.gtkw` paths resolve against live variables (0 unmatched) — `[Coverage: INTEGRATION]` (`integration_test/session/gtkw_import_integration_test.dart`, nightly sweep)
- [ ] Malformed / adversarial `.gtkw` input never throws — `[Coverage: AUTOMATED]` (gtkw_parser_test.dart adversarial group)
- [ ] Corpus discipline: generated/captured layout, golden companions, captured-license allow-list — `[Coverage: AUTOMATED]` (`test/static/gtkw_fixture_layout_test.dart`, `gtkw_captured_fixture_companion_test.dart`, `gtkw_captured_fixture_licenses_test.dart`)
- [ ] Import-result dialog shows matched/unmatched counts — `[Coverage: AUTOMATED]` (`test/features/viewer/widgets/gtkw_import_result_dialog_test.dart`)

---

## 5. Cocotb log correlation

- [ ] `cocotb/basic_log.txt` loads and panel populates — `[Coverage: WIDGET]` (`test/services/cocotb/cocotb_log_parser_test.dart` + `test/features/cocotb/widgets/cocotb_log_panel_test.dart`)
- [ ] Severity-colored ticks on time ruler (blue INFO, amber WARNING, red ERROR/CRITICAL) — `[Coverage: WIDGET]` (`test/features/cocotb/widgets/cocotb_timeline_overlay_test.dart`)
- [ ] Click entry → cursor jumps + viewport pans — `[Coverage: WIDGET]` (`test/features/cocotb/widgets/cocotb_log_entry_row_test.dart` covers the dispatch); viewport-pan side `[Coverage: INTEGRATION_TEST — pending]`
- [ ] Test-name dropdown filter works — `[Coverage: WIDGET]` (`test/features/cocotb/providers/` + panel test)
- [ ] Severity chip filters work — `[Coverage: WIDGET]` (`test/features/cocotb/widgets/cocotb_severity_chips_test.dart`)
- [ ] Keyword search works — `[Coverage: WIDGET]` (`test/features/cocotb/providers/`)
- [ ] Combined filter intersection correct — `[Coverage: WIDGET]` (`test/features/cocotb/providers/` — AND-semantics test)
- [ ] Right-click context menu (Jump to time, Copy message, Filter to test) — `[Coverage: WIDGET]` (`cocotb_log_entry_row_test.dart`); long-press touch path `[Coverage: INTEGRATION_TEST — pending]`
- [ ] `edge_cases_log.txt` (multi-unit timestamps fs/ps/ns/µs/ms/s) clicks to correct waveform time — `[Coverage: WIDGET]` (`cocotb_log_parser_test.dart` covers all SI-unit conversions; full click-to-cursor flow `[Coverage: INTEGRATION_TEST — pending]`)
- [ ] Stress log (10 k+ entries) loads + filters without UI freeze — `[Coverage: HYBRID]` (`cocotb_log_parser_test.dart` covers parse correctness; UI freeze under load `[Coverage: MANUAL]`)
- [ ] Empty log file → empty state, no crash — `[Coverage: WIDGET]` (`cocotb_log_panel_test.dart`)
- [ ] Malformed lines mixed with good lines → bad lines skipped — `[Coverage: WIDGET]` (`cocotb_log_parser_test.dart` — tolerant-of-malformed-lines case)
- [ ] Unload Cocotb log → panel + ruler ticks both cleared — `[Coverage: WIDGET]` (provider-side state clear)

---

## 6. Integration & platform features

### Streaming/interactive VCD

- [ ] `--pipe <fifo>` mode: header parses → hierarchy visible, transitions appear progressively — `[Coverage: INTEGRATION_TEST — pending]` (real FIFO + real parse; queued)
- [ ] Stdin mode same behavior — `[Coverage: INTEGRATION_TEST — pending]`
- [ ] LIVE badge shown — `[Coverage: WIDGET]` (`test/features/viewer/widgets/viewer_toolbar_test.dart` — "LIVE badge and stop button absent when not streaming" + "LIVE badge and stop button shown when StreamingViewerStarting" + "LIVE badge and stop button shown when StreamingViewerActive" + locale-sweep "LIVE badge renders in $locale without exceptions". The badge lives on the toolbar, not the status bar — corrects the earlier-marker assumption)
- [ ] Stop button finalizes and lets user browse received data — `[Coverage: INTEGRATION_TEST — pending]`
- [ ] Producer EOF → graceful finalize — `[Coverage: INTEGRATION_TEST — pending]`
- [ ] Producer emits malformed VCD partway → clear error, partial data preserved — `[Coverage: INTEGRATION_TEST — pending]`

### FSDB error path

- [ ] Open `.fsdb` without `fsdb2vcd` → clear dialog with link to Synopsys tools — `[Coverage: WIDGET]` (`test/features/viewer/widgets/fsdb_conversion_dialog_test.dart`)
- [ ] Dialog dismisses cleanly — `[Coverage: WIDGET]` (`fsdb_conversion_dialog_test.dart`)

### Remote Control API (WCP)

- [ ] Server start/stop in Settings works; port 54321 visible — `[Coverage: WIDGET]` (`test/services/remote/wcp_server_test.dart` + `wcp_notifier_test.dart` cover start/stop behavior + isRunning/connectedClients state; Settings-pane wiring: `test/features/settings/screens/settings_screen_test.dart` — "when remote control is enabled, port + server-status rows appear")
- [ ] Greeting handshake completes on connect (version `"0"` per the pinned upstream spec); WaveCrux extension commands announced; client greeting with an unsupported major version draws `error: "greeting"` — `[Coverage: WIDGET]` (`wcp_server_test.dart`)
- [x] Spec envelope end-to-end: id-less commands with top-level params (`add_items` via `items`), command-echo responses, in-order pipelined replies, spec-shaped errors, deprecated `add_variables`/`add_scope` aliases — `[Coverage: WIDGET]` (`wcp_server_test.dart` — `WcpServer — spec envelope` group) + `[Coverage: INTEGRATION_TEST]` (`integration_test/remote_control/wcp_spec_envelope_test.dart`)
- [x] `add_items` partial failure adds/registers nothing; `remove_items` on a marker id clears the marker; `get_item_list` reflects UI-added/-removed items — `[Coverage: WIDGET]` (`remote_control_notifier_test.dart`) + `[Coverage: INTEGRATION_TEST]` (`wcp_spec_envelope_test.dart`)
- [x] `wavecrux-ctl add-items top.clk` adds signal to canvas — `[Coverage: WIDGET]` (`wcp_server_test.dart`); CLI client + canvas push `[Coverage: INTEGRATION_TEST]` (`integration_test/remote_control/wcp_add_signal_cli_subprocess_test.dart` — spawns the real `tool/wavecrux_ctl` CLI as an OS subprocess via `Process.run`, driving `load` then `add top.clk`, and asserts the signal lands in `signalGroupsProvider`)
- [x] `set_cursor`, `set_viewport_range`, `zoom_to_fit`, `add_markers`, `remove_items`, `load`, `reload`, `clear` all work — `[Coverage: WIDGET]` (`wcp_server_test.dart`); end-to-end via real socket `[Coverage: INTEGRATION_TEST]` (`set_cursor`: `wcp_set_cursor_test.dart`; `set_viewport_range`: `wcp_set_viewport_range_test.dart`; `load`: `wcp_load_test.dart`; `reload`: `wcp_reload_event_test.dart`; `zoom_to_fit` / `add_markers` / `remove_items`: `wcp_zoom_marker_remove_test.dart`; `clear` remains WIDGET-only)
- [ ] `waveforms_loaded` event fired after `load`/`reload` — `[Coverage: WIDGET]` (`wcp_server_test.dart`)
- [ ] WaveCrux extensions (`wavecrux.getValueAt`, `getHierarchy`, `getState`) work — `[Coverage: WIDGET]` (`wcp_server_test.dart`); `getValueAt` also end-to-end via real socket `[Coverage: INTEGRATION_TEST]` (`integration_test/remote_control/wcp_get_value_test.dart`)
- [x] WaveCrux extension `wavecrux.setActiveTab` (with and without explicit `pane_id`) targets the right tab + focuses its pane — `[Coverage: WIDGET]` (`test/services/remote/remote_control_notifier_test.dart` — `RemoteControlNotifier — wavecrux.setActiveTab` group)
- [ ] Unknown command → WCP error response — `[Coverage: WIDGET]` (`wcp_server_test.dart`)
- [x] Multiple concurrent connections OK — `[Coverage: WIDGET]` (`wcp_server_test.dart`) + `[Coverage: INTEGRATION_TEST]` (`integration_test/remote_control/wcp_multi_connection_test.dart` — two real simultaneous TCP client sockets against one running app; `connectedClients` tracks both, per-connection response routing has no cross-talk, a broadcast event triggered by one client reaches both, both clients' commands land in shared provider state, and `connectedClients` drops correctly on disconnect)
- [ ] Stop server → connection refused — `[Coverage: WIDGET]` (`wcp_notifier_test.dart`)
- [ ] Diagnostics report includes remote-control status — `[Coverage: WIDGET — pending]` (**feature gap, not test gap**: `lib/services/diagnostics/app_diagnostics_report_service.dart` does not currently emit a Remote Control section. Closing requires (a) adding the section querying `wcpNotifierProvider`, then (b) extending `app_diagnostics_report_service_test.dart`. Tracked in `integration_test/PENDING.md`.)

### Flutter Web

- [ ] File picker upload works — `[Coverage: INTEGRATION_TEST — pending]` (web platform integration; queued)
- [ ] Drag-and-drop onto the empty-canvas state works — `[Coverage: INTEGRATION_TEST — pending]`
- [x] URL `?file=<url>` loads (with CORS) — `[Coverage: INTEGRATION_TEST]` (`integration_test/web/web_url_file_load_test.dart` — real fetch against `tool/cors_fixture_server.dart`, both the CORS-permissive success path and the CORS-blocked error path)
- [ ] All disabled features show "Not available on web" rather than crashing (FSDB, process filters, interactive VCD, remote API, file watcher) — `[Coverage: WIDGET — pending]` (each feature already has a `kIsWeb` early-return guard in source: `lib/services/translate/process_filter_service.dart` (3 sites), `lib/services/waveform/streaming_vcd_service.dart` (1 site), `lib/services/waveform/file_watcher_service.dart` (1 site). Closing this gap means running per-feature widget tests under `flutter test --platform chrome` so `kIsWeb` is `true` at compile time — currently the standard `flutter test` runs with `kIsWeb=false` and exercises only the desktop branch. Tracked in `integration_test/PENDING.md` as a CI infrastructure item rather than a missing-test gap.)
- [ ] Renders acceptably with ~50 signals — `[Coverage: MANUAL]` (perceptual)
- [ ] Diagnostics Memory tab handles missing process RSS gracefully — `[Coverage: WIDGET]` (`memory_stats_panel_test.dart` should cover the missing-RSS branch)

### Help links

- [ ] All `?` icons / "Learn more →" links open the right docs URL — `[Coverage: WIDGET]` (`lib/shared/widgets/help_link.dart` is the centralized helper; check `test/shared/widgets/` for coverage and queue any missing per-call-site tests)

### macOS native file-picker entitlement (§8.6)

- [ ] macOS `File → Open` shows the native open panel — no `ENTITLEMENT_NOT_FOUND` exception — in both a debug and a release/profile build — `[Coverage: MANUAL]` (`file_picker` 12.x hard-checks `com.apple.security.files.user-selected.read-write`, present in both `macos/Runner/*.entitlements`, even with the sandbox disabled)
- [ ] macOS save panel (VCD export / session save) shows without an entitlement error — `[Coverage: MANUAL]`

### macOS runtime file-open (Finder / `open -a`), incl. during a large restore (§8.7)

- [ ] `open -a "WaveCrux" small.vcd` (and Finder double-click / drag-to-Dock) opens a tab while a **large workspace is still restoring** — the open is queued on the reconcile barrier and applied once restore settles, never dropped (prereqs + repro in §8.7.2–8.7.3; generate a big trace with `tool/generate_scale_fixtures.dart`, no simulator needed) — `[Coverage: WIDGET]` (`viewer_screen_phone_incoming_file_test.dart` — "runtime open arriving mid-restore is QUEUED…") + real Apple-event delivery `[Coverage: MANUAL]`
- [ ] Re-opening the **same** path (`open -a …` again after closing the tab) reaches the viewer instead of being a go_router no-op (monotonic `req` token) — `[Coverage: UNIT]` (`router_test.dart` — "stamps a monotonic req token for repeat opens") + `[Coverage: MANUAL]`

### Dropping files on the desktop window (§8.8)

- [ ] macOS, Windows and Linux: dragging a file from the file manager over **any** part of the window (welcome screen, open waveform, toolbar, status bar; title bar on Windows/Linux) shows the green "Drop to open" overlay; dragging back out clears it with nothing opened — `[Coverage: WIDGET]` (`desktop_file_drop_target_test.dart`) + real OS drag `[Coverage: MANUAL]` per platform
- [ ] A dropped waveform opens in a **new tab** on the welcome screen and over an open waveform; several files in one drop each get a tab; each lands in Recent Files — `[Coverage: WIDGET]` (`viewer_screen_file_drop_test.dart`) + `[Coverage: INTEGRATION_TEST]` (`integration_test/workspace/empty_canvas_drag_drop_test.dart`)
- [ ] A dropped `.gtkw` imports into the active tab (Import Complete dialog, no new tab); with nothing open the same dialog lists the signals as not found; a waveform + its `.gtkw` dropped together opens the waveform then applies the session — `[Coverage: WIDGET]` (`viewer_screen_file_drop_test.dart`)
- [ ] A non-waveform drop opens into **Failed to load waveform**, never a silent no-op; `.fsdb` gets the conversion offer — `[Coverage: WIDGET]` (unsupported) + `[Coverage: MANUAL]` (FSDB, needs `fsdb2vcd`)
- [ ] No overlay and no open while a dialog (e.g. Settings) is in front; tab-chip reorder, signal drags and the Stage bindings pane's drop still work with no overlay — `[Coverage: WIDGET]` (dialog / gate) + `[Coverage: MANUAL]` (in-app drags)

### User-contributed decoder plugin loader (§22.5.4)

- [ ] First-launch acknowledgment dialog explains that plugins run as native code; user can decline — `[Coverage: WIDGET]` (`test/features/settings/widgets/plugin_safety_dialog_test.dart`)
- [ ] Build the 1-Wire demonstrator (`make` in `examples/decoder-plugin-demo/`); copy the artifact into the per-user plugin directory; restart WaveCrux — `[Coverage: MANUAL]`
- [ ] Settings → Decoders → Plugins lists the demonstrator with status `loaded`, ABI `1.1`, decoder id `examples.onewire`, and a `1 decoder` count line — `[Coverage: WIDGET]` (`test/features/settings/widgets/decoder_plugins_panel_demo_integration_test.dart`)
- [ ] A plugin exporting the optional ABI 1.1 `wavecrux_decoder_plugin_name` / `_description` symbols shows its self-reported name + description + `N decoders` count on the card (instead of the first decoder's name); plugins without the symbols fall back to the first decoder's name — `[Coverage: WIDGET]` (`test/services/decoders/ffi/ffi_decoder_loader_test.dart` `test_plugin_named`; `test/features/settings/widgets/decoder_plugins_panel_test.dart`)
- [ ] Decoder picker shows `1-Wire (demo plugin)` under the User-Contributed group — `[Coverage: MANUAL]` (registry-level coverage in `test/services/decoders/ffi/ffi_decoder_loader_test.dart`)
- [ ] Round-trip against `examples/decoder-plugin-demo/fixtures/onewire_basic.vcd` produces the canonical RESET / PRESENCE / BYTE 0x33 / BYTE 0x28 transactions, byte-for-byte — `[Coverage: WIDGET]` (`test/services/decoders/ffi/onewire_demo_integration_test.dart`)
- [ ] Per-plugin disable toggle hides the decoder from the picker on Reload but keeps the row in the panel — `[Coverage: WIDGET]` (`decoder_plugins_panel_demo_integration_test.dart`)
- [ ] ABI-mismatch / missing-symbol / corrupt-manifest plugin variants surface non-`loaded` rows with diagnostic messages — `[Coverage: WIDGET]` (`test/services/decoders/ffi/ffi_decoder_loader_test.dart`)
- [ ] Two plugins claiming the same decoder id: first wins, second logs "already taken" — `[Coverage: WIDGET]` (same file)
- [ ] `WAVECRUX_DECODER_PATH` env var prepends directories to the search path; relative paths rejected — `[Coverage: WIDGET]` (`test/services/decoders/ffi/plugin_directory_resolver_test.dart`)
- [ ] Rust companion port at `examples/decoder-plugin-demo-rust/` builds via `cargo build --release` and produces a byte-equivalent decoder — `[Coverage: MANUAL]` (the integration test exercises the C port; verifying the Rust port is a developer-time check)

---

## 7. Mobile / tablet / adaptive layout

- [ ] iPhone portrait: phone layout (drawer + bottom sheet) — `[Coverage: WIDGET]` (`device_class_provider_test.dart` covers the phone classification; `test/features/viewer/screens/viewer_screen_test.dart` covers the phone signal-tree drawer + no-values-endDrawer behavior); real-device feel `[Coverage: INTEGRATION_TEST — pending]`
- [ ] iPhone signal-tree drawer is populated with the active tab's signals (reads the per-tab scope, not the empty root) — you can browse and add signals — `[Coverage: WIDGET]` (`test/features/viewer/screens/viewer_screen_test.dart` — "phone signal-tree drawer reads the active tab scope, not the empty root")
- [ ] iPhone landscape: phone-landscape layout (waveform-focused, not tablet) — `[Coverage: WIDGET]` (`device_class_provider_test.dart` — compound width+height classification)
- [ ] iPad landscape: tablet multi-pane — `[Coverage: WIDGET]`; on-device `[Coverage: INTEGRATION_TEST — pending]`
- [ ] iPad split-screen narrow: drops to phone layout — `[Coverage: WIDGET]` (`device_class_provider_test.dart`); on-device `[Coverage: INTEGRATION_TEST — pending]`
- [ ] Desktop window resized narrow: drops to phone layout at breakpoint — `[Coverage: WIDGET]` (`device_class_provider_test.dart` — compound width+height classification + resize re-eval)
- [ ] Desktop full size: full IdeLayout — `[Coverage: WIDGET]` (`test/features/viewer/screens/viewer_screen_test.dart` — "renders the IdeLayout when at least one tab is open")
- [ ] Ultrawide display (≥21:9 / 32:9): fresh workspace seeds *wider* default signal-tree / value-column panes (≈360/280, then ≈420/320) so names + values stop truncating while the canvas keeps the bulk; only affects un-dragged defaults; normal (<21:9) screens unchanged (§9.1.3 step 7) — `[Coverage: UNIT]` (`pane_defaults_test.dart`)
- [ ] Narrow viewport (<800 dp wide — foldable inner display in portrait, iPad mini portrait, narrow browser tab): fresh workspace seeds *narrower* default panes (≈220/160) so the waveform canvas keeps a usable share of the width instead of ~23%; only affects un-dragged defaults; pane *visibility* unchanged; ≥800 dp unchanged — `[Coverage: UNIT]` (`pane_defaults_test.dart`)
- [ ] iPhone Duo: cover screen is phone layout; unfolding to the inner display switches to the multi-pane tablet layout with the side docks restored to the user's prior visibility; folding back force-hides them without losing the preference; no dropped frames or lost viewport across the transition — `[Coverage: UNIT]` (`device_class_test.dart` "iPhone Duo poses") + on-hardware `[Coverage: MANUAL — pending hardware]`
- [ ] Share sheet "Open With WaveCrux" works for `.vcd` / `.fst` / `.ghw` / `.wavecrux` — `[Coverage: INTEGRATION_TEST — pending]` (real OS share sheet; queued)
- [ ] Same-named re-share reloads the replaced `SharedImports/<name>` contents into the existing tab (phone drawer shows the NEW hierarchy; identical contents = no reload flicker); sharing the path of a restored-but-unloaded tab loads it (§9.2.4) — `[Coverage: WIDGET]` (`test/features/viewer/screens/viewer_screen_phone_incoming_file_test.dart`) + `[Coverage: UNIT]` (`waveform_source_provider_open_test.dart` staleness stat) + real native copy path `[Coverage: MANUAL]`
- [ ] Document picker on mobile loads files — `[Coverage: INTEGRATION_TEST — pending]`
- [ ] Phone large-file warning at >100 MB — `[Coverage: WIDGET]` (`test/features/viewer/widgets/large_file_warning_dialog_test.dart`)
- [ ] Tablet large-file warning at >250 MB — `[Coverage: WIDGET]` (`large_file_warning_dialog_test.dart` parameterized over device class)
- [ ] Memory guard unloads non-visible signals under pressure — `[Coverage: WIDGET]` (`test/services/mobile/mobile_memory_guard_service_test.dart`)
- [x] Re-fetch on scroll back is transparent — `[Coverage: INTEGRATION_TEST]` (`integration_test/canvas/scroll_back_refetch_test.dart`)
- [x] OS memory warning → drops caches, no crash — `[Coverage: WIDGET]` (`mobile_memory_guard_service_test.dart` covers the unload pathway) + `[Coverage: INTEGRATION_TEST]` (`integration_test/mobile/os_memory_pressure_test.dart` — real `handleMemoryPressure()` callback)
- [ ] Pinch zoom, two-finger pan, tap cursor, long-press menu all work — `[Coverage: WIDGET]` (`test/features/viewer/widgets/waveform_gesture_handler_test.dart`); real touch arena `[Coverage: INTEGRATION_TEST — pending]`
- [ ] **App-wide two-finger trackpad scroll** (macOS/iPad) — the signal-tree (SST), transaction table, diagnostics panels, cocotb log, and the signal-list names column all scroll under a two-finger trackpad swipe (not just scrollbar/wheel); names column + canvas scroll by the same amount (not double); canvas pinch still zooms; a click/tap still registers (mouse excluded from `dragDevices`) — `[Coverage: UNIT]` (`test/app_scroll_drag_devices_test.dart`) + `[Coverage: WIDGET]` (`test/features/signal_tree/widgets/signal_tree_panel_trackpad_scroll_test.dart` positive + control); real trackpad feel + single-vs-double + pinch/tap `[Coverage: MANUAL]` (§9.4.4)
- [ ] Drawer swipe vs canvas pan don't conflict — `[Coverage: INTEGRATION_TEST]` (`integration_test/gestures/gesture_conflict_drawer_canvas_test.dart` — canvas touch-swipe stays a pan/no cursor scrub + no spurious drawer; phone drawer opens cleanly). Drawer half is **phone-class only** (desktop runner classifies 390×844 as tablet → mobile track); the left-EDGE drawer-open gesture *winner* is gesture-arena, **faithful only on a real device** (manual).
- [ ] Bottom sheet drag vs canvas pan don't conflict — `[Coverage: INTEGRATION_TEST — pending]`
- [ ] Orientation change preserves file, signals, cursor, drawer state, diff/X-Trace state — `[Coverage: WIDGET]` (state is held in Riverpod providers, so it survives the layout rebuild by construction; `device_class_provider_test.dart` covers the re-classification on a resize/orientation size change); real orientation change `[Coverage: INTEGRATION_TEST — pending]`
- [ ] iOS **release archive** (TestFlight/IPA) opens a VCD on a physical device — wellen FFI symbols survive archive stripping (`STRIP_STYLE = non-global` on Runner Release/Profile; debug builds can NOT catch this — §9.6) — `[Coverage: STATIC]` (`test/static/ios_runner_strip_style_test.dart`) + on-device open from TestFlight build `[Coverage: MANUAL]` + `dyld_info -exports` archive spot check `[Coverage: MANUAL]`

---

## 8. Stage (built-in widgets)

- [ ] Primitives respond to cursor scrubbing: LED, switch, 7-seg, gauge, level bar, state indicator, bus readout, signal graph — `[Coverage: WIDGET]` (`test/features/stage/widgets/primitives/`)
- [ ] Add-Widget picker is grouped into collapsible category sections (`ExpansionTile` per populated `StageWidgetCategory`); empty categories not shown — `[Coverage: WIDGET]` (`test/features/stage/widgets/stage_widget_picker_dialog_test.dart`)
- [ ] Section order: **Primitive → Peripheral → Instrument → Board → Protocol → Custom**, locale-independent (verified across en / zh-CN / ja / ko). On open-core only Primitive, Instrument, and Board sections render — Peripheral, Protocol, Custom are empty in open core — `[Coverage: WIDGET]` (`test/features/stage/widgets/stage_widget_picker_dialog_section_ordering_test.dart` — open-core populated-set ordering across en/zh/ja/ko, regression guard against unpopulated categories rendering, plus a full-set ordering test simulating the Stage Pro shipped state)
- [ ] Section header uses the `pickerCategoryHeader` format `<Localized Name> (<count>)` — `[Coverage: WIDGET]` (`stage_widget_picker_dialog_test.dart`)
- [ ] Stage tab click latency (§10.3.1): clicking an inactive tab switches panels **on the press**, before the button is released; rapid tab clicks all register; a double-click both switches to the tab and opens Rename; right-click/long-press menu and screen-reader activation unaffected — `[Coverage: WIDGET]` (`test/features/stage/widgets/stage_panel_test.dart` — "tapping an inactive tab selects its panel", "a tab selects on pointer-down, before the pointer lifts", "double-tapping a tab selects it as well as renaming it") + `[Coverage: MANUAL]` (screen-reader activation)
- [ ] All sections start expanded; collapse/expand toggle works — `[Coverage: WIDGET]` (`stage_widget_picker_dialog_test.dart`)
- [ ] Open-core widgets land in the right category: LED/Switch/7-seg/Bus Readout → Primitive; Level Bar/State Indicator/Signal Graph → Instrument; Basys 3/DE10-Lite/Nexys A7/Arty A7 → Board — `[Coverage: WIDGET]` (`test/features/stage/widgets/stage_widget_renderer_registry_test.dart`)
- [ ] Non-board widget display names localize (picker / instance header / bindings pane) via `displayNameKey` → `stageConfigLabelResolverFactoryProvider`; board names stay English vendor product names; every declared key resolves (en/zh_CN/ja/ko) — `[Coverage: WIDGET/UNIT]` (`test/features/stage/widgets/stage_widget_display_name_localization_test.dart` — has-key drift guard exempting board category + resolver locale sweep)
- [ ] **Basys 3** board widget renders all slots and binds correctly — `[Coverage: WIDGET]` (`test/features/stage/widgets/boards/`)
- [ ] **DE10-Lite** board widget renders all slots and binds correctly — `[Coverage: WIDGET]` (`test/features/stage/widgets/boards/`)
- [ ] **Nexys A7** board widget renders all slots and binds correctly — `[Coverage: WIDGET]` (`test/features/stage/widgets/boards/`)
- [ ] **Arty A7** board widget renders all slots; RGB LED slots show "Upgrade to Pro" hint — `[Coverage: WIDGET]` (`test/features/stage/widgets/boards/` covers the slot layout + hint sentinel resolution)
- [ ] Trademark disclaimer surfaced via info-icon tooltip on each board — `[Coverage: WIDGET]` (board widget tests assert tooltip presence)
- [ ] Each board has a compelling out-of-box demo fixture in both per-bit and vector form (`stage/boards/<board>/<board>_demo_{per_bit,vector}.vcd`); per-bit binds via exact-match, vector binds via fan-out, both run the same six-pattern LED light show, coherent decoded seven-segment readout (Basys 3 hex counter; Nexys A7 accel X/Y; DE10-Lite 3-axis accel — every digit exercised across 0–F), and staggered button presses identically — `[Coverage: INTEGRATION]` (`test/fixtures/stage/boards/board_demo_fixtures_test.dart`)
- [ ] Signal drag from signal tree → Stage slot binds — `[Coverage: WIDGET]` (`test/features/stage/widgets/stage_instance_tile_test.dart` + `stage_bindings_pane_test.dart`)
- [ ] Signal drag from signal list panel → Stage slot also binds (two-source design) — `[Coverage: WIDGET]` (`test/features/viewer/widgets/signal_list_panel_test.dart` covers the source side; binding side covered above)
- [ ] Drag-to-Stage horizontal does not steal vertical reorder gesture — `[Coverage: WIDGET]` (`signal_list_panel_test.dart` axis-affinity test)
- [ ] Bindings inspector (tall config section, e.g. Tachometer) and the signal binding picker scroll with a **two-finger trackpad** swipe, not just the mouse wheel; a single-finger tap still taps (`dragDevices` re-adds trackpad+touch, mouse excluded) — `[Coverage: WIDGET]` (`stage_bindings_pane_test.dart` "trackpad scroll" group + `signal_binding_picker_dialog_test.dart` "re-enables trackpad two-finger scroll"; trackpad-feel + tap-still-taps stays MANUAL)
- [ ] Session save → reload → Stage configuration restored — `[Coverage: WIDGET]` (`test/services/session/session_service_test.dart`)
- [ ] Stage hidden on phone, visible on tablet and desktop — `[Coverage: WIDGET]` (`test/features/stage/widgets/stage_panel_test.dart` + `device_class_provider_test.dart`)
- [ ] Stage tab bar does not overflow when the panel is hosted in an ultra-narrow pane (e.g. transiently during a workspace pane split, ~92 dp wide): the tab strip + three trailing action buttons scroll horizontally instead of asserting a `RenderFlex overflowed` — `[Coverage: WIDGET]` (`test/features/stage/widgets/stage_panel_test.dart` — "tab bar does not overflow when hosted in an ultra-narrow pane")
- [ ] Binding a widget to a missing/invalid signal settles to an error snapshot (not a perpetual loading spinner) and never crashes the app via an uncaught async load error — `[Coverage: UNIT]` (`test/features/stage/providers/stage_signal_provider_test.dart` — "failed load is contained, not thrown"; `test/domain/models/stage_signal_snapshot_test.dart` — error kind)
- [ ] **Tachometer Rive reference widget** — bind `rpm`/`redline`/`shift` (→ `level_ramp`/`toggle_a`/`toggle_b` in `stage_demo.vcd`), scrub: the styled gauge sweeps the needle (1D blend on `rpm`), **the redline arc glows while `redline` is high** (SM Layer 2), and **an amber rim flash pops on each `shift` rising edge** (SM Layer 3) — all three composite independently (§10.10) — `[Coverage: MANUAL]` (live Rive render)
- [ ] **Tachometer range knob keeps a lowered Max RPM** — setting Max RPM = 200 with default Warning/Redline (6500/7500) sweeps the full arc; the zones clamp into `[min, max]` instead of `fromMap` reverting the whole config to 8000; degenerate `min ≥ max` falls the range back to defaults — `[Coverage: UNIT]` (`test/features/stage/widgets/tachometer/domain/tachometer_config_test.dart` — clamp + regression + degenerate-range groups)
- [ ] **Numeric config field commits on tab/blur, not just Enter** — typing into a Stage widget's numeric config field and tabbing/clicking away commits the value — `[Coverage: WIDGET]` (`test/features/stage/widgets/stage_widget_config_editor_test.dart` — "commits typed value on focus loss")
- [ ] **Bindings pane shows the signal path, not the opaque ref** — a bound row renders `Variable.fullPath` (e.g. `top.level_ramp`), not wellen's opaque `signalRef` handle (`10`); falls back to the raw ref when the signal is absent from the loaded file — `[Coverage: WIDGET]` (`test/features/stage/widgets/stage_bindings_pane_test.dart` — "signalRef resolves to a human path")
- [ ] **Tachometer renders in BOTH the open-core build and the Pro build** — the curated asset resolves via the bare `assets/...` key (open-core) and the `packages/wavecrux/...` fallback (Pro overlay); verify the gauge renders in the Pro app, not the "Widget failed to load" placeholder (§10.10) — `[Coverage: UNIT]` (`test/features/stage/runtime/bundled_stage_asset_loader_test.dart` — bare + packages/<owner>/ fallback) + `[Coverage: MANUAL]` (run the Pro app)

#### Community custom-widget live rendering (`.wcrux-widget` render bridge — §10.11)

- [ ] **A community `.wcrux-widget` (manifest + `.riv`, no Dart) renders and animates live** — load `test/fixtures/stage/community_widget/community_gauge.wcrux-widget` via Settings → Custom Widgets, drop **Community Gauge** on a Stage panel, bind `rpm`/`redline`/`shift` → `level_ramp`/`toggle_a`/`toggle_b`, scrub: the artboard animates through the generic runtime (default-state-machine resolution + manifest-driven input routing), no Tachometer-specific code (§10.11) — `[Coverage: MANUAL]` + `[Coverage: INTEGRATION_TEST — pending]` (rive_native unavailable headless)
- [ ] **Custom-widget capability is open-core end-to-end** — the **Settings → Custom Widgets** section is present in the Settings rail (entry point now wired), is **ungated** (no PRO badge on the header, available at every tier), and a loaded community bundle (**Community Gauge**) carries **no PRO chip** in the picker (registers at `openCore` tier) — `[Coverage: WIDGET]` (`settings_screen_test.dart` rail categories; `custom_widgets_panel_test.dart` — "panel is open-core") + `[Coverage: UNIT]` (`picker_integration_test.dart` — openCore tier)
- [ ] **Community widget survives session reload** — a saved session with a Community Gauge instance comes back as the live gauge after a full quit/relaunch, **without** visiting Settings first (eager startup bundle load); an unresolved tile shows a brief spinner, not a stuck "Unknown widget" — `[Coverage: WIDGET]` (`stage_instance_tile_test.dart` — spinner-while-loading) + `[Coverage: MANUAL]` (quit/relaunch)
- [ ] **Bundle registers a definition + renderer (Rive) and clears both on removal**; the tile shows "Bind …"/the live artboard, never "Unknown widget", while installed; a painter-runtime bundle registers a definition only — `[Coverage: UNIT]` (`test/features/stage/bundle/custom_widget_bundle_manager_test.dart`; `test/plugins/stage_registry_test.dart`; `test/features/stage/widgets/stage_widget_renderer_registry_test.dart`)
- [ ] **Manifest → generic input mapping** — missing-required detection, manifest-declared normalizer resolution, default normalize (bool/double/analog/X/Z), hold-stale on non-value snapshots — `[Coverage: UNIT]` (`test/features/stage/runtime/generic_manifest_input_mapper_test.dart`)
- [ ] **Misnamed / missing required input → localized "Widget failed to load" placeholder, no crash**; empty/malformed `.riv` → same placeholder — `[Coverage: WIDGET]` (`test/features/stage/runtime/community_rive_stage_renderer_test.dart` — empty `.riv` locale sweep en/zh-CN/ja/ko) + `[Coverage: MANUAL]` (misnamed-input bundle)
- [ ] **Committed community fixture loads + parses** (`community_gauge.wcrux-widget`, regenerable via `tool/generate_community_widget_fixture.dart`) — `[Coverage: UNIT]` (`test/fixtures/stage/community_widget/community_gauge_fixture_test.dart`)

### RISC-V Core Designer widgets — RVFI Commit Inspector (Open Core, §10B)

- [ ] **Open core, uncrippled** — `riscv_commit` appears in Add-Widget → Instrument with **no tier badge**, no row cap, no watermark, no in-view Pro nag, and the consistency checker is fully enabled. Any of those is a tier-line regression, not a cosmetic one: correctness is free, and a crippled free widget lands worse than an omitted one — `[Coverage: UNIT]` (`test/features/stage/widgets/riscv/riscv_commit_stage_widget_test.dart`) + `[Coverage: MANUAL]` (picker badge)
- [ ] **Auto-bind maps the whole 21-channel RVFI bundle in one action**, under the widget's own dialog title ("Auto-bind RVFI channels", not the board heading), including the hierarchy-prefixed form the fixture uses; already-bound pins are never overwritten — `[Coverage: WIDGET]` (`test/features/stage/widgets/stage_bindings_pane_test.dart` — auto-bind affordance group) + `[Coverage: UNIT]` (`riscv_commit_stage_widget_test.dart` — pin names parse back as canonical RVFI ports)
- [ ] **Commit log shows real operand values under ABI naming** (`t0 = 0x0000_0005`, `[0x0000_1000] ← 0x0000_000c`); `rd_addr == 0` shows *no* register effect; clicking a row moves the primary cursor to that retirement — `[Coverage: WIDGET]` (`test/features/stage/widgets/riscv/riscv_commit_stage_renderer_test.dart`)
- [ ] **Architectural register file is reconstructed at the cursor**, correct by construction; an unwritten register reads `—`, never `0` (unknown ≠ zero); backward scrub rebuilds — `[Coverage: WIDGET]` (same) + `[Coverage: UNIT]` (`test/services/riscv/riscv_arch_state_service_test.dart`)
- [ ] **Memory and trap logs** list the fixture's store/load and the trapping `ecall` with its privilege level; both are clickable — `[Coverage: WIDGET]` (same)
- [ ] **The consistency checker: every rule has a corrupted fixture that fires it and a clean fixture that does not**, and each corrupted fixture fires **its rule and no other** — `[Coverage: UNIT]` (`test/services/riscv/riscv_consistency_fixtures_test.dart` over `riscv_rvfi_bad_{pc_wdata,x0_write,rd_addr,mem_mask,order,trap}.vcd`) + `[Coverage: UNIT]` (`riscv_consistency_checker_test.dart` — each rule in isolation, plus every must-not-fire case)
- [ ] **Violation messages are specific and actionable**, naming the values that disagree ("sw accesses 4 bytes, but the rvfi_mem byte masks cover 2"), never a generic "inconsistency detected"; they render **inline on the offending commit row** and clicking one moves the cursor to that retirement — `[Coverage: WIDGET]` (`riscv_commit_stage_renderer_test.dart`) + `[Coverage: UNIT]` (`riscv_commit_messages_test.dart` — all 13 kinds × 5 locales, all args interpolated)
- [ ] **Misalignment is a Warning, not an Error** — RISC-V permits misaligned accesses; flagging them as violations would be a false positive on correct hardware — `[Coverage: UNIT]` (`riscv_consistency_checker_test.dart`)
- [ ] **Reduced binding set degrades the views instead of refusing to render**, names every missing channel by its Verilog port name, and **names the checks that could not run** — a quiet result from a rule that never executed is the one way this widget could mislead someone — `[Coverage: WIDGET]` (`riscv_commit_stage_renderer_test.dart` — reduced binding set group) + `[Coverage: UNIT]` (`riscv_consistency_checker_test.dart` — rule gating)
- [ ] **Lazy-load trap**: every bound pin is loaded before the substrate walks the source, so a bundle bound to signals the user never added to the viewer still populates. An empty inspector on a good trace is this defect, not a bad file (ARCHITECTURE §6.6 rule 1) — `[Coverage: WIDGET]` (`test/features/stage/widgets/riscv/riscv_commit_lazy_load_test.dart`)
- [ ] **44 × 44 dp touch targets on every tappable row in all five views**, and a locale sweep en / zh-CN / zh / ja / ko across all of them — `[Coverage: WIDGET]` (`riscv_commit_stage_renderer_test.dart`)
- [ ] Config (register naming, register count, memory log depth) applies live and survives session save/reload — `[Coverage: WIDGET]` (`riscv_commit_stage_renderer_test.dart` naming; `[Coverage: MANUAL]` session round-trip)
- [ ] **Cross-probe landing ([CXP §9.9](https://edacrux.app/cxp#sec-9-9) semantic stream coordinate, §10B.1.9)** — SimCrux's "Debug in WaveCrux" on a *failing bounded proof* opens the counterexample **and lands the cursor on the failing step**, not at time zero; the Commit Inspector's banner names the check and the step (`insn_sub_ch0 · step 7 of 20`) — `[Coverage: UNIT]` (`test/services/remote/cxp/cxp_inbound_handlers_test.dart` — stream-coordinate group) + `[Coverage: WIDGET]` (`test/features/stage/widgets/riscv/riscv_commit_landing_banner_test.dart`) + `[Coverage: MANUAL]` (SimCrux → WaveCrux round trip)
- [ ] **The landing is actually VISIBLE on a freshly opened tab** — a tab the cross-probe opened has no Stage panel, so it gets one: an RVFI Commit Inspector, auto-bound through `RvfiDetectionService`, revealed in the bottom dock, with the step-7 retirement as the current row. Landing the cursor at the right instant on an empty canvas is the defect this closes — `[Coverage: WIDGET]` (`test/services/remote/cxp/riscv_counterexample_handoff_test.dart` — from the committed trace on disk) + `[Coverage: UNIT]` (`test/features/stage/providers/riscv_commit_auto_stage_test.dart`)
- [ ] **The landed retirement is INSIDE the viewport, not merely in the list** — the Commits view scrolls the landed row into view, and the panel is mounted (720 × 420, dock raised to 480) with room for five or six rows around it. A tinted current row painted below the fold, that the user has to enlarge the panel to find, is the defect: existence is not visibility — `[Coverage: WIDGET]` (`test/features/stage/widgets/riscv/riscv_commit_log_landing_scroll_test.dart` — geometry, plus the first-row / short-log / repeat-landing edges; `riscv_counterexample_handoff_test.dart` asserts the row's paint rect against the list's) + `[Coverage: UNIT]` (`riscv_commit_auto_stage_test.dart` — mount size and raise-only dock growth)
- [ ] **An already-open, user-arranged tab is NOT rearranged** — the same coordinate arriving at a tab the user set up moves the cursor and touches nothing else: no panel, no dock, no second inspector, and the banner claims no mount. `[Coverage: WIDGET]` (`riscv_counterexample_handoff_test.dart`)
- [ ] **The auto-mounted panel accounts for itself** — the banner states that the incoming cross-probe opened it and bound it; the whole mount is **one** undo step — `[Coverage: WIDGET]` (`riscv_commit_landing_banner_test.dart`) + `[Coverage: UNIT]` (`test/features/stage/providers/riscv_commit_auto_stage_test.dart`)
- [ ] **Replayed evidence is labelled as replayed** — a coordinate carrying `riscv.mode = demo` renders *"Replayed demo fixture, not a measured solver run."* A landing that reports the check and the step **without** that line is a defect, not a cosmetic miss: it lets a rehearsed demo screenshot read as a measured result — `[Coverage: WIDGET]` (`riscv_commit_landing_banner_test.dart`) + `[Coverage: UNIT]` (`cxp_inbound_handlers_test.dart`)
- [ ] **Every unresolvable coordinate degrades, none throws** — no RVFI bundle, no uniform step grid, a step past the end, an unaddressable hart, a `riscv.pc` disagreement, or a `stream_id` this build never heard of: the **element is still honoured** and the ack carries the reason SimCrux toasts. An unknown stream is never a protocol error (CXP §9.9.1) — `[Coverage: UNIT]` (`test/services/remote/cxp/riscv_stream_coordinate_resolver_test.dart` + `cxp_inbound_handlers_test.dart`)
- [ ] **No tier gate on the coordinate path** — the whole SimCrux → WaveCrux hand-off resolves on an unlicensed build — a counterexample hand-off answers whether a core is correct, which is never gated. A badge, nag, or licence check appearing here is a tier-line regression — `[Coverage: UNIT]` (`cxp_inbound_handlers_test.dart` — the stream-coordinate group runs on a container with no licence override)
- [ ] Behaviour against a **real captured core trace** (Ibex) — `[Coverage: MANUAL]` (pending the captured fixture)

### Stage Playback (animated playhead, §10A)

- [ ] Play auto-advances the primary cursor and bound Stage widgets animate; Pause freezes; Stop returns to the range start — `[Coverage: UNIT]` (`test/features/cursors/providers/playback_provider_test.dart`; reactive chain proven by "a bound Stage signal re-samples the new cursor value")
- [ ] Speed presets 5 s / 10 s / 30 s play the whole range in that many wall-clock seconds, file-independently (ps- and second-scale) — `[Coverage: UNIT]` (`playback_provider_test.dart` — "duration speed is file-independent")
- [ ] No-loop stops at the end and pins the cursor; Loop range wraps; Loop A–B loops between the two cursors and falls back to whole-range when the secondary is unset — `[Coverage: UNIT]` (`playback_provider_test.dart`)
- [ ] Follow-playhead recentres the viewport only when the playhead leaves the visible window; off = no recentre — `[Coverage: UNIT]` (`playback_provider_test.dart` — viewport follow)
- [ ] `togglePlayback` (default **Space**) is enabled only when a file is loaded AND the Stage panel is visible — greyed in toolbar/menu, omitted from palette, Space inert otherwise; binding is collision-free — `[Coverage: UNIT]` (`test/core/shortcuts/action_descriptors_test.dart` + `shortcut_bindings_test.dart`)
- [ ] Transport renders all controls, buttons call the right notifier methods, 44×44 touch targets, empty-Stage hint shows, locale sweep en/zh/ja/ko — `[Coverage: WIDGET]` (`test/features/stage/widgets/stage_playback_transport_test.dart`)
- [ ] Power mode (sim-time/s) is engine-only this phase (unit-tested); the transport UI exposes only duration presets — `[Coverage: UNIT]` (`playback_provider_test.dart` — power mode)
- [ ] Animated-playhead visual feel (smooth sweep, motor-spin perception) — `[Coverage: MANUAL]`

---

## 9. FSM visualization

- [ ] Right-click state register → Visualize FSM works — `[Coverage: WIDGET]` (`test/features/viewer/widgets/fsm_annotate_dialog_test.dart` + `fsm_panel_test.dart`); right-click dispatch end-to-end `[Coverage: INTEGRATION_TEST]` (`integration_test/gestures/fsm_context_menu_dispatch_test.dart` — row right-click → "Visualize as FSM" → FSM panel + ≥1-node bubble diagram)
- [ ] State graph shows actually-observed transitions — `[Coverage: WIDGET]` (`test/services/signal_query/fsm_analysis_service_test.dart` + `fsm_layout_service_test.dart` + `test/features/viewer/widgets/fsm_bubble_painter_test.dart`)
- [ ] Active-state highlight follows cursor live — `[Coverage: WIDGET]` (`fsm_panel_test.dart` cursor-sync test)
- [ ] Click state node → cursor jumps to first occurrence — `[Coverage: WIDGET]` (`fsm_panel_test.dart`)
- [ ] Symbolic state names from translate filter / stems file decode correctly — `[Coverage: WIDGET]` (`fsm_analysis_service_test.dart`)
- [ ] Open new file while FSM active → state clears — `[Coverage: WIDGET]` (provider-side regression case)
- [ ] User FSM annotations (state-name labels) persist across session save → close → reopen — `[Coverage: WIDGET]` (`fsm_annotation_test.dart` JSON group, `session_state_test.dart` "fsmAnnotations", `session_service_test.dart` "fsm annotations preserved") + `[Coverage: INTEGRATION_TEST]` (Pro `composite_workspace_round_trip_test.dart`)

### FSM analyzer robustness (FSM robustness plan)

- [ ] `FsmModel` derived from real-parser VCDs matches committed goldens, incl. the real **PicoRV32 `cpu_state`** capture (ISC, 7 states / 21 transitions) — `[Coverage: UNIT]` (`test/services/signal_query/fsm_golden_test.dart`; regenerate VCDs via `dart run tool/generate_fsm_fixtures.dart` + capture via `tool/generate_picorv32_fsm_capture.sh`, goldens via `REGENERATE=1`)
- [ ] Analyzer never crashes/hangs on pathological signals (all-X/Z, x/z chain break, simultaneous-tick, >2³² range, non-monotonic, 256-bit, 1024 states) — `[Coverage: UNIT]` (`fsm_edge_cases_test.dart`)
- [ ] Structural invariants hold over 500 random streams vs an independent oracle — `[Coverage: UNIT]` (`fsm_fuzz_test.dart`)
- [ ] Large-FSM layout stays usable (N up to 4096: finite, bounded, distinct; N=50 pins the circle) + perf/stress budgets — `[Coverage: UNIT]` (`fsm_stress_test.dart`)
- [ ] FSM fixture corpus is self-enforcing (layout split, golden companions, captured license/provenance) — `[Coverage: UNIT]` (`test/static/fsm_fixture_layout_test.dart`, `fsm_fixture_companion_test.dart`, `captured_fixture_licenses_test.dart`)

---

## 10. RTL source annotation (desktop only)

- [ ] Stems file loads — `[Coverage: WIDGET]` (`test/services/rtl_source/` and `test/features/rtl_source/providers/`)
- [ ] **Generate RTL Stems… (Tools menu)** produces a stems file from a Verilog/VHDL source tree (no GTKWave needed); auto-detects top, reports warnings, auto-loads — `[Coverage: UNIT+INTEGRATION+WIDGET]` (`stems_generator_test.dart`, `stems_generation_e2e_test.dart`, `generate_stems_dialog_test.dart`)
- [ ] Generated stems round-trip: generate → write → load → signal resolves to the correct source file:line (Verilog + VHDL) — `[Coverage: INTEGRATION]` (`stems_generation_e2e_test.dart`)
- [ ] Generate dialog: ambiguous-top and no-modules errors keep the dialog open with guidance — `[Coverage: WIDGET]` (`generate_stems_dialog_test.dart`)
- [ ] **Import Verilator AST (JSON)… (Tools menu)** converts a `verilator --json-only` dump (`V<top>.tree.json` + auto-located `.tree.meta.json`) to a portable `.stems`, auto-loads, and reports mapping count / warnings — `[Coverage: UNIT+WIDGET]` (`verilator_ast_stems_importer_test.dart`, `import_verilator_ast_dialog_test.dart`, fixtures `test/fixtures/rtl_source/verilator_ast/`)
- [ ] Imported AST stems carry elaborated per-instance paths incl. unrolled generate scopes (`top.gen_blink[0].u_blink.led`) — `[Coverage: UNIT+WIDGET]` (genloop fixture in both test files)
- [ ] Import dialog: missing-meta and ambiguous-top errors keep the dialog open with guidance (typing a top module resolves); prior stems state untouched on failure — `[Coverage: WIDGET]` (`import_verilator_ast_dialog_test.dart`)
- [ ] Source code displays with syntax highlighting — `[Coverage: WIDGET]` (`test/features/rtl_source/widgets/rtl_source_panel_test.dart`)
- [ ] Inline value annotations match cursor time — `[Coverage: WIDGET]` (`rtl_source_panel_test.dart`)
- [ ] Live update on cursor scrub — `[Coverage: WIDGET]` (`rtl_source_panel_test.dart`)
- [ ] Source → waveform navigation works — `[Coverage: WIDGET]` (`rtl_source_panel_test.dart`)
- [ ] Waveform → source navigation works — `[Coverage: WIDGET]` (`rtl_source_panel_test.dart`)
- [ ] Signal with no stems mapping handled gracefully — `[Coverage: WIDGET]` (`rtl_source_panel_test.dart`)
- [ ] Hidden on phone and tablet — `[Coverage: WIDGET]` (`test/features/rtl_source/widgets/rtl_source_device_class_test.dart`)
- [ ] Hidden when desktop window resized below tablet breakpoint — `[Coverage: WIDGET]` (`rtl_source_device_class_test.dart` parameterized over breakpoint widths)
- [ ] Cmd/Ctrl+Shift+R toggle reveals the panel on the ACTIVE tab (per-tab scope) and forces the right pane open — `[Coverage: WIDGET]` (`viewer_screen_test.dart` — "toggleRtlSourcePanel flips the ACTIVE TAB state…")
- [ ] Empty-state "Load Stems File…" CTA present; header fits the narrow right pane with no overflow (en/zh/ja/ko) — `[Coverage: WIDGET]` (`rtl_source_panel_test.dart` — "narrow right pane (no overflow)")
- [ ] Per-tab independence: toggling RTL in one tab does not affect another — `[Coverage: WIDGET]` (`viewer_screen_test.dart`)

---

## 10a. Workspace and file lifecycle (§16)

- [x] Empty-canvas state — recent files list, drag-drop, stale-entry handling — `[Coverage: WIDGET]` (`test/features/workspace/widgets/wavecrux_empty_canvas_test.dart`); drag-drop on the desktop window `[Coverage: WIDGET]` + `[Coverage: INTEGRATION_TEST]` (§8.8; the OS drag itself is manual) *(the empty-canvas state supersedes the legacy Welcome screen — see §22.9.1)*
- [ ] Cold-start tab restoration — **lazy mount + deferred load** (§16.1.5): a multi-tab / split-pane workspace restores all tab **chips**, loads only each pane's **active** tab up front, and loads + renders every other tab on first click (instant thereafter); all panels work on each tab; drag-reorder doesn't re-mount; no GPU crash on Windows + Intel. **Single tab with a Stage board** (Nexys A7 wired on the Stage) also restores without crashing — the board is serialized out of the restore burst via `stageStartupRenderGateProvider` (brief placeholder spinner, then the board builds on its own frame). — `[Coverage: WIDGET]` (`test/shared/widgets/lazy_indexed_stack_test.dart`, `test/features/stage/widgets/stage_panel_test.dart`) + `[Coverage: UNIT]` (`test/features/stage/providers/stage_startup_render_gate_provider_test.dart`) + `[Coverage: INTEGRATION_TEST]` (`integration_test/tabs/multi_tab_pane_stress_test.dart`, `startup_restoration_test.dart`); Windows+Intel GPU-crash regression `[Coverage: MANUAL]` (relaunch-loop repro kept with the Pro overlay)
- [ ] Open a file **after** restore (File→Open / recent / drag-drop / second launch) loads it **exactly once** — the deferred-load listener owns only restored tabs and does not start a second concurrent load that strands the canvas on a **permanent loading spinner** (§16.1.5.3) — `[Coverage: INTEGRATION_TEST]` (`integration_test/workspace/open_after_restore_no_double_load_test.dart`)
- [ ] Design manifest (§16.1.8) — `<design>.crux-project` opens its `waveform:` from **File → Open File** (listed in the picker), Finder double-click on macOS, and the CLI (file or design folder); a legacy bare `.crux-project` opens with the rename notice; a folder with two manifests is refused with both names — `[Coverage: UNIT]` (`test/services/session/crux_project_resolution_test.dart`) + `[Coverage: WIDGET]` (`test/features/viewer/screens/viewer_screen_phone_incoming_file_test.dart`) + `[Coverage: MANUAL]` (picker, Finder)
- [ ] Session recovery — crash-loop breaker (§16.1.7): force-quit during the cold-start load → next launch **suppresses auto-load** (tab chips present, no waveform reopened) and shows the **recovery banner**; **Open last session** loads the previous active waveform; the sentinel clears so a second relaunch auto-restores. Works on **mobile** (the only recovery path there). **Render-time crash:** a session that loads fine but crashes *during render* (e.g. a Stage tab wiring the Nexys A7 board that trips the Windows/Intel concurrent-GPU-init crash) is caught too — disarm waits for a rendered content frame, so reload crashes **at most once** then recovers via the banner (regression guard; previously it crash-looped). — `[Coverage: UNIT]` (`test/services/session/restore_guard_service_test.dart`, `startup_recovery_providers_test.dart`) + `[Coverage: WIDGET]` (`test/features/workspace/widgets/recovery_banner_test.dart`) + force-quit-mid-load and render-crash-on-reload end-to-end `[Coverage: MANUAL]`
- [ ] `--no-restore` (desktop) launches without reopening waveforms and **deletes nothing** (relaunch without the flag restores) — `[Coverage: UNIT]` (`test/services/cli/cli_args_test.dart`) + `[Coverage: MANUAL]`
- [ ] `--reset` (desktop) clears `workspace.json` + the `sessions/` sidecars + legacy `last_session.json`, launches empty, prints a stdout confirmation, and **keeps** settings / keymap / recent files — `[Coverage: UNIT]` (`test/services/session/session_reset_test.dart`, `cli_args_test.dart`) + on-disk-at-boot `[Coverage: MANUAL]`
- [ ] In-app reset — banner **Reset** and **Settings → File handling → Reset workspace & sessions** both clear the live workspace **and** all on-disk session state (same as `--reset`); reachable on mobile — `[Coverage: WIDGET]` (`test/features/workspace/commands/reset_workspace_command_test.dart`, `test/features/settings/screens/settings_screen_test.dart`)
- [ ] Workspace-corrupt banner — an unreadable `workspace.json` is quarantined to `workspace.json.corrupt-<timestamp>`, the app starts empty, and the banner shows the *corrupt* message (no **Open last session** action) — `[Coverage: UNIT]` (`crux_workspace` `workspace_service_test.dart` quarantine) + banner reason `[Coverage: WIDGET]` (`recovery_banner_test.dart`) + `[Coverage: MANUAL]`
- [ ] Settings screen — Appearance, Defaults, Keyboard Shortcuts, File Handling; activating a light/dark preset re-themes immediately (no separate light/dark/system selector — it was removed as redundant); ⌘/Ctrl+Shift+K (Toggle Theme) flips between the default light/dark presets; persists across launches — `[Coverage: WIDGET]` (`test/features/settings/screens/settings_screen_test.dart`, `test/core/theme/theme_brightness_toggle_test.dart`); persistence across launches `[Coverage: WIDGET]` (`test/services/settings/`)
- [ ] Legacy theme-id migration — a beta profile with the old `wavecrux-dark` / `wavecrux-light` preset ids persisted (renamed to `crux-dark` / `crux-light` in the 2026-07 crux-shared round) keeps the chosen theme on first launch after upgrade; a light-theme user is NOT dropped into dark mode (transparent read-path alias, no prompt). A `.wavecrux` session carrying `"activeTheme": "wavecrux-dark"` restores correctly too — `[Coverage: UNIT]` (`test/core/theme/wavecrux_color_theme_bootstrap_test.dart`)
- [ ] Waveform-canvas token values (22 tokens × 6 presets = 132 colors) are pinned — they now arrive via WaveCrux's product-registered `PresetTokenOverlay` (moved out of crux_theme's shared presets so the other three products don't carry a waveform palette they can't paint); rendered result is byte-identical, incl. oled-xr `selection` = `0x2AFFFFFF` — `[Coverage: UNIT]` (`test/core/theme/wavecrux_canvas_preset_overlay_test.dart`)
- [ ] Theme-pack browser (Settings → Appearance → Theme packs) — Import/Export flow document text through the host (crux_theme `ThemePackStore` seam) instead of `dart:io` handles, so it renders on web; desktop/mobile Import reads file contents, Export writes the encoded pack to the chosen path — `[Coverage: WIDGET]` (`test/features/settings/widgets/color_theme_section_test.dart`)
- [ ] **OLED XR** preset — true-black (`#000000`) canvas **and** chrome (toolbar / panel headers / status bar / tab bar) for Micro-OLED XR / AR glasses (no backlight bloom, easier on the eyes at high nits); X-state fill, amber cursor (`#FFD400`), cyan secondary (`#00E5FF`), green markers (`#34FF8A`) and a true-black ruler with near-white (`#E8E8E8`) labels stay legible at XR optics' low angular resolution; brand-neutral; persists + Toggle-Theme flips to WaveCrux Light (§16.2.2 step 6) — `[Coverage: UNIT]` (`crux_theme` `builtin_presets_test.dart` — preset present, `oled-xr` chrome category + signature token spot-checks); on-glasses bloom/legibility feel `[Coverage: MANUAL]`
- [ ] **Boost Legibility for XR / Large Displays** toggle (Appearance, below font slider) — thickens scalar/bus/analog traces + lane dividers (~1.6×) and floors in-canvas text at ~14 px so signals stay readable on far-viewed / XR screens; off by default, persists, independent of the OLED XR preset; off → canvas returns to exact default weights (§16.2.2 step 7) — `[Coverage: WIDGET]` (`settings_screen_test.dart` toggle round-trip + `waveform_canvas_render_object_scale_test.dart` lineWidthScale propagation) + `[Coverage: UNIT]` (`app_settings_test.dart`, `settings_service_test.dart`); on-glasses stroke feel `[Coverage: MANUAL]`
- [ ] Settings screen layout — dual-pane master-detail: left **category rail** + right **detail pane**; ≥ 620 dp side-by-side (VerticalDivider), below it collapses to list → detail with an in-pane back button; Appearance selected by default; CXP Cross-Probe is its own category sibling to Remote Control; Appearance shows Presets / Color overrides / Theme packs whose data surfaces (`surfaceContainerHighest`) read distinctly from the grouping cards (`surfaceContainerLow`); preset cards are compact (no empty area); rows clear card margins on all sides; no About category (About lives in Help → About) — `[Coverage: WIDGET]` (`test/features/settings/screens/settings_screen_test.dart` — "renders a category rail beside a detail pane", "rail lists the platform-independent categories", "narrow layout … back button", "no About category", "groups detail content into bordered Cards"); preset sizing + section-vs-data tone + row margins + visual polish `[Coverage: MANUAL]`
- [ ] Keyboard shortcuts editable — Settings → Keyboard Shortcuts lists actions by category with binding chips + Import…/Export…/Reset all; pencil captures a new chord (applies immediately, palette/menu/overflow re-render), backspace unbinds, reset returns to default; customizations persist across relaunch — `[Coverage: WIDGET]` (`test/features/settings/widgets/shortcuts/shortcuts_settings_section_test.dart`), `[Coverage: UNIT]` (`test/core/shortcuts/shortcut_bindings_provider_test.dart` persistence group)
- [ ] Keyboard shortcut capture — macOS Caps Lock→Control remap captures as ⌃ (held Caps Lock treated as Control), while a Caps Lock *lock* toggle does not add Control — `[Coverage: WIDGET]` (`crux-shared/packages/crux_keybindings/test/widgets/shortcut_capture_field_test.dart`)
- [ ] Keyboard shortcut conflict warning is **asymmetric** — rebinding onto an in-use chord shows "Takes precedence over …" (amber) on the customized winner and "Won't fire — shadowed by …" (red error) on the shadowed owner; "Won't" renders with a **single** apostrophe, not a doubled `Won''t` (issue #42 — simple ICU message, no apostrophe un-escaping) — `[Coverage: UNIT]` (`test/core/shortcuts/shortcut_conflicts_test.dart`) + `[Coverage: WIDGET]` (section test, issue #36 bug 1)
- [ ] Close File has **no default keyboard binding**; Cmd/Ctrl+W closes the tab only; no conflict warning on a fresh profile (issue #37, `kIntentionalShadows` removed) — `[Coverage: UNIT]` (`test/core/shortcuts/shortcut_bindings_test.dart` collision-free guard + `shortcut_conflicts_test.dart` default-keymap guard)
- [ ] Command Palette opener reachable from **Help menu / overflow** (not from the palette itself); recovery path after unbinding Cmd/Ctrl+Shift+P (issue #38) — `[Coverage: UNIT]` (`test/core/shortcuts/action_descriptors_test.dart` menu+overflow contains / palette excludes) + `[Coverage: WIDGET]` (menu-bar conformance)
- [ ] Keyboard shortcut conflict **summary banner** — a red "N shortcut conflict(s) need attention" banner shows at the top of the section whenever any conflict exists (stays visible when affected rows are off-screen); gone when resolved — `[Coverage: WIDGET]` (section test + `crux_keybindings` editor test, issue #36 bug 2)
- [ ] Keyboard shortcut conflict **precedence** — pressing a contested chord fires the freshly-remapped (customized) action, not the default owner; deterministic and independent of enum declaration order — `[Coverage: WIDGET]` (`test/core/shortcuts/shortcut_manager_widget_test.dart`) + `[Coverage: UNIT]` (`resolveShortcutConflicts`, issue #36 bug 3)
- [ ] Keymap export/import — Export writes `wavecrux.crux-keymap.json` (diffs-from-default, versioned envelope); Import applies it; empty/invalid files message without crashing; a keymap **saved by a newer version** shows the distinct "saved by a newer version of WaveCrux" message (not the generic failure, not a raw exception); company-standard file reproduces on another profile — `[Coverage: WIDGET]` (`test/features/settings/widgets/shortcuts/shortcuts_settings_section_test.dart` export/import + "importing a keymap from a newer version shows the version-specific message") + `[Coverage: UNIT]` (upstream `crux_keybindings` keymap-codec / `KeymapSchemaVersionException` tests)
- [ ] Keymap cross-platform round-trip — macOS Cmd/Option ↔ Windows/Linux Ctrl/Alt; literal Ctrl+Tab stays Ctrl on macOS — `[Coverage: UNIT]` (upstream `crux_keybindings` key-binding cross-platform round-trip tests) + cross-OS hardware check `[Coverage: MANUAL]`
- [ ] Keymap **presets** — Settings → Keyboard Shortcuts has a **Preset** dropdown (WaveCrux (Default) / GTKWave); selecting **GTKWave** rebinds search→`Alt+S`, export→`Ctrl/Cmd+P`, format keys→`Alt+X/D/B/O`, collision-free, inheriting all other defaults; persists across relaunch; hand-editing flips to **Custom**; re-selecting WaveCrux clears the diff (§16.2.7) — `[Coverage: UNIT]` (`test/core/shortcuts/keymap_presets_test.dart`, `shortcut_bindings_provider_test.dart` applyPreset group) + `[Coverage: WIDGET]` (`shortcuts_settings_section_test.dart`)
- [ ] Mouse-wheel direction — Settings → Waveform Defaults "Mouse wheel scrolls through time" toggle (default off); **off**: plain wheel scrolls signals, Shift+wheel pans time; **on** (GTKWave): plain wheel pans time, Shift+wheel scrolls signals; Ctrl/Cmd+wheel zooms at pointer in both; trackpad gestures unaffected; persists across relaunch (§16.2.8) — `[Coverage: WIDGET]` (`waveform_scroll_modifier_interceptor_test.dart` default + navigate-time groups) + `[Coverage: UNIT]` (`settings_service_test.dart`, `settings_providers_test.dart`); perceptual feel `[Coverage: MANUAL]`
- [ ] Auto-reload — Prompt mode triggers reload prompt on file change; Auto mode reloads silently with snackbar; Off mode does nothing — `[Coverage: WIDGET]` (`test/features/settings/providers/` + the file-watcher service tests). Auto-mode silent reload end-to-end `[Coverage: INTEGRATION_TEST]` (`integration_test/auto_reload/auto_reload_auto_mode_test.dart` — extra signal appears, no prompt banner, cursor + per-signal format preserved). Prompt-mode end-to-end `[Coverage: INTEGRATION_TEST]` (`integration_test/session/auto_reload_test.dart` — **currently failing on macOS runner**, tracked as a follow-up).
- [ ] File deletion notification appears when loaded file is deleted from disk — `[Coverage: WIDGET]` (file-watcher service test); real-FS deletion `[Coverage: INTEGRATION_TEST]` (`integration_test/auto_reload/file_deletion_test.dart` — deletion snackbar + in-memory data retained)
- [ ] Auto-reload disabled/hidden on web — `[Coverage: WIDGET — pending]` (the *behavior* is gated: `lib/services/waveform/file_watcher_service.dart` has `if (kIsWeb) return;` so the watcher is a no-op on web. The Settings → Auto-reload UI is *not* hidden — it renders on web but has no effect. Closing this gap requires either (a) wrapping the auto-reload Settings section in a `kIsWeb` check so it disappears on web, or (b) running the full SettingsScreen widget test under `flutter test --platform chrome` to assert the section's rendering matches the intent. Either way the gap is partly a feature-level decision; tracked in `integration_test/PENDING.md`.)

## 10b. Display formats and translate filters (§17)

- [ ] Every format (binary/hex/oct/dec-signed/dec-unsigned/ASCII) on `vcd/vector_formats.vcd` matches `.expected.json` — `[Coverage: WIDGET]` (`test/services/value_format/value_format_service_test.dart` — 137 cases)
- [ ] x/z propagation: hex per-nibble, octal per-trit, decimal whole-value, ASCII per-byte — `[Coverage: WIDGET]` (`value_format_service_test.dart`)
- [ ] Signed decimal two's-complement: 8-bit `0xFF`=−1, `0x80`=−128, `0x7F`=127 — `[Coverage: WIDGET]` (`value_format_service_test.dart`)
- [ ] ASCII with non-printable bytes renders safely (no glyph artifacts) — `[Coverage: WIDGET]` (`value_format_service_test.dart`)
- [ ] 256-bit and 1024-bit signals render in reasonable time — `[Coverage: HYBRID]` (`value_format_service_test.dart` covers correctness up to 1024-bit; render-time perception `[Coverage: MANUAL]`)
- [ ] Per-signal format persists across session save/reload — `[Coverage: WIDGET]` (`test/services/session/session_service_test.dart`)
- [ ] Static `.txt` translate filter applies and toggles off cleanly — `[Coverage: WIDGET]` (`test/services/translate/translate_filter_service_test.dart`)

**Extended display formats (§17.10–17.16)**

- [ ] IEEE-754 float 32: `3F800000`→`1.0`, `7F800000`→`Inf`, `7FC00000`→`NaN`, x/z→graceful — `[Coverage: WIDGET]` (`value_format_service_test.dart`)
- [ ] IEEE-754 double 64: `3FF0000000000000`→`1.0`, Inf, NaN, x/z→graceful — `[Coverage: WIDGET]` (`value_format_service_test.dart`)
- [ ] Q-format: Q7.8 `0x0100`→`1.0`, UQ0.15 `0x4000`→`0.5`, x/z→graceful — `[Coverage: WIDGET]` (`value_format_service_test.dart`)
- [ ] QFormatConfigDialog: renders sliders + preview, OK returns correct config, Cancel returns null, locale sweep en/zh_CN/ja/ko — `[Coverage: WIDGET]` (`test/shared/widgets/q_format_config_dialog_test.dart`)
- [ ] Signed-magnitude 8-bit: `0x01`→`+1`, `0x81`→`-1`, `0xFF`→`-127`, x/z→graceful — `[Coverage: WIDGET]` (`value_format_service_test.dart`)
- [ ] Gray code 4-bit: `0000`→0 … `1000`→8, full table, x/z→graceful — `[Coverage: WIDGET]` (`value_format_service_test.dart`)
- [ ] Named enum (first-class): value mapped to label, unmapped→raw hex fallback, session round-trip preserves mapping — `[Coverage: WIDGET]` (`value_format_service_test.dart`, `session_service_test.dart`)
- [ ] NamedEnumEditorDialog: render, add row, delete row, OK returns correct NamedEnumConfig, Cancel returns null, invalid value disables OK, locale sweep en/zh_CN/ja/ko — `[Coverage: WIDGET]` (`test/shared/widgets/named_enum_editor_dialog_test.dart`)
- [ ] Named enum import from `.txt` filter file populates editor rows — `[Coverage: MANUAL]` (§17.14 step 8)
- [ ] Named enum export writes `.txt` file with correct `<value>  <label>` format — `[Coverage: MANUAL]` (§17.14 step 9)
- [ ] `setSignalTranslatorConfigByRef` / `setSignalFormatByRef` mutation on top-level and nested signals — `[Coverage: WIDGET]` (`test/features/viewer/providers/signal_group_providers_test.dart`)
- [ ] Format & translator config are **per-instance** (§17.15) — two rows of one signal can carry different Q-format/named-enum/custom-translator configs; editing one row leaves the other unchanged; `byRef` still fans out as the "apply to all" path (issue #39) — `[Coverage: WIDGET]` (`test/features/viewer/providers/signal_group_providers_test.dart` "setSignalTranslatorConfigById" group)
- [ ] Value-column context menu fits a short window (§17.16, issue #40) — the 12 display formats are collapsed behind a single "Display Format ▸" entry that opens a nested format menu; translator / copy / filter entries stay reachable at minimum window height — `[Coverage: WIDGET]` (`test/features/viewer/widgets/value_column_row_test.dart` — top-level collapses formats; nested menu reveals them)

**Value-display layout — aligned three-column lane geometry, desktop/tablet (§17.18)**

- [ ] Signal-names, canvas, and value column are pixel-aligned across signals, group headers, separators, comments, and custom/sub-min lane heights — `[Coverage: WIDGET]` (`test/features/viewer/widgets/lane_alignment_test.dart` — the regression guard for the original drift bug)
- [ ] Synchronized vertical scroll reaches the **last** lane with no bounce-back, and values stay on their waves: names list, canvas, and value column share one scroll top + `maxScrollExtent` **with a timeline overlay active** (Pro SVA strip is always mounted) and across bottom-panel hidden/shown/resized (§17.18.5a) — `[Coverage: INTEGRATION_TEST]` (`integration_test/canvas/value_column_scroll_alignment_test.dart` — injects a 10 dp overlay, asserts all three tops + extents) + `[Coverage: UNIT]` (`canvasViewportHeightProvider` in `value_column_provider_test.dart`); perceptual smoothness `[Coverage: MANUAL]`
- [ ] Resizing a lane (signal-names handle) reflows all three columns in lockstep, live during the drag — `[Coverage: WIDGET]` (`lane_alignment_test.dart` resize step) + drag-handle write `[Coverage: WIDGET]` (`signal_list_panel_test.dart`); perceptual smoothness `[Coverage: MANUAL]`
- [ ] Double-tapping a signal name resets its lane to the **user's configured** default lane height (Settings → Waveform Defaults), not a fixed 30 dp — `[Coverage: WIDGET]` (`signal_list_panel_test.dart` — "double-tap reset honours the configured default lane height"; mutation-verified against the old hardcoded `30`)
- [ ] `LaneGeometry` heights/offsets, signal min-clamp, fixed group/separator/comment heights, no upper bound (200 cap is the writer's) — `[Coverage: UNIT]` (`test/services/waveform_geom/lane_geometry_test.dart`)
- [ ] Shared `laneGeometryProvider` hands one instance per equal `LaneMetrics`; recomputes on signal-list change — `[Coverage: UNIT]` (`test/features/viewer/providers/lane_geometry_provider_test.dart`)
- [ ] Value column shows the active tab's values per-tab (not blank): `laneGeometryProvider` resolves the per-tab `signalGroupsProvider`, not the empty root scope — `[Coverage: UNIT]` (`test/features/viewer/providers/lane_geometry_provider_test.dart` — "resolves the per-tab signal list, not the empty root scope")
- [ ] Store-raw-render-clamped: sub-44 dp lane saved on desktop reopens at stored value on desktop, renders at 44 dp floor on touch — `[Coverage: HYBRID]` (clamp logic `[Coverage: UNIT]` `lane_geometry_test.dart`; cross-device-class save/reopen `[Coverage: MANUAL]` §17.17.6)
- [ ] Value pane keeps its manual show/hide toggle (not forced always-on); stays aligned when re-shown — `[Coverage: MANUAL]` (§17.17.5)

**Value-display layout — phone inline-at-cursor overlay (§17.17.7)**

- [ ] Placing the cursor shows a value label on every visible signal lane, pinned to the lane band at the cursor x; cleared when there is no cursor — `[Coverage: WIDGET]` (`test/features/viewer/widgets/inline_cursor_value_overlay_test.dart`)
- [ ] Scrub-through: horizontal drag moves the cursor and live-updates labels — no freeze — and pinch/pan still work with the overlay shown — `[Coverage: WIDGET]` (`waveform_gesture_handler_test.dart` scrub reaches handler) + perceptual smoothness `[Coverage: MANUAL]` (§17.17.7)
- [ ] Default placement right of the cursor; flips left within a label-width of the right edge — `[Coverage: WIDGET]` (`inline_cursor_value_overlay_test.dart`)
- [ ] Long bus value truncates with ellipsis; tapping expands it in place to the full value; tap again/elsewhere collapses — `[Coverage: WIDGET]` (`inline_cursor_value_overlay_test.dart`)
- [ ] Tap-to-expand is the only interactive surface: truncated label is a translucent, tap-only (no long-press) detector, non-truncated is `IgnorePointer`, hit surface ≥ 44×44 — `[Coverage: WIDGET]` (`inline_cursor_value_overlay_test.dart`)
- [ ] Inline values exposed as a single combined cursor-readout (time + each visible signal's full value), not one node per lane — `[Coverage: WIDGET]` (`inline_cursor_value_overlay_test.dart`); real VoiceOver/TalkBack pass `[Coverage: MANUAL]` (§17.17.7)
- [ ] Phone has NO values drawer anymore (no right-edge value chevron, no edge-swipe panel); desktop/tablet value pane unaffected — `[Coverage: WIDGET]` (`test/features/viewer/screens/viewer_screen_test.dart`)
- [ ] Inline label locale sweep en/zh_CN/ja/ko — `[Coverage: WIDGET]` (`inline_cursor_value_overlay_test.dart`)

## 10c. Cursors, named markers, time ruler (§18)

- [ ] Primary cursor placement on tap; secondary on right-click / Shift+tap — `[Coverage: WIDGET]` (`test/features/cursors/providers/cursor_providers_test.dart` + `test/features/viewer/widgets/cursor_overlay_test.dart`)
- [ ] Status bar shows cursor time, secondary, delta, frequency — `[Coverage: WIDGET]` (`test/features/viewer/widgets/status_bar_test.dart`)
- [ ] Named markers: **M** then a–z sets at cursor; **⇧M** then a–z jumps; "press a–z" hint + Esc/timeout cancel — `[Coverage: UNIT/WIDGET]` (`marker_chord_controller_test.dart` + `shortcut_wiring_test.dart`)
- [ ] **M / palette arm regardless of focus** (click chrome / open the palette via ⌘⇧P, then M+letter still sets) — `[Coverage: UNIT]` (`marker_chord_providers_test.dart` arm/complete; app-level global handler)
- [ ] **Any letter, any order** completes the chord (a, b, k — no sequential restriction) — `[Coverage: UNIT]` (`marker_chord_providers_test.dart`)
- [ ] **Completing key wins over a colliding nav key**: M then q/w/a/s/d/e sets the marker and does NOT pan/zoom/step — `[Coverage: MANUAL/UNIT]` (`_onKeyEvent` chord-first; pieces in `marker_chord_providers_test.dart` + `shortcut_wiring_test.dart`)
- [ ] **Bare-letter nav (WASD/QE/Z) works from chrome** (focus off the waveform body) — handled by the viewer global key handler, excluded from focus Shortcuts — `[Coverage: UNIT]` (`shortcut_wiring_test.dart` global key-handled set). Arrows/Home/End remain focus-scoped by design.
- [ ] Set Marker greys out without a cursor; Jump/Remove Marker grey out without a marker (precise per-action gating) — `[Coverage: UNIT]` (`action_descriptors_test.dart` "context gating")
- [ ] Remove marker: time-ruler right-click on a flag, and "Remove Marker…" command picker — `[Coverage: WIDGET]` (`time_ruler_widget_test.dart`)
- [ ] No shortcut key is double-bound (every declared key dispatches an action) — `[Coverage: UNIT/WIDGET]` (`shortcut_bindings_test.dart` collisions + `shortcut_wiring_test.dart`)
- [ ] Markers persist across session save/restore — `[Coverage: WIDGET]` (`session_service_test.dart`)
- [ ] Time ruler tick auto-scale across zoom levels (ps → ns → µs → ms) — `[Coverage: WIDGET]` (`test/features/viewer/widgets/time_ruler_widget_test.dart` + `test/services/time_format/`)
- [ ] **Zoom out cannot go past the end of the trace.** On a **short** trace (tens of ticks — the SimCrux counterexample fixtures are ideal), press Zoom Out repeatedly: the most zoomed-out state is fit-all, and the button/menu row **greys out** there. Reaching a viewport wider than the trace — data crushed to the left with an empty expanse to the right, correctable only by Fit All — is the defect. Mirror case: Zoom In stops with one tick across the viewport and greys out. Fit All is never greyed. Panning at any zoom cannot scroll the viewport clear of the data — `[Coverage: UNIT]` (`test/services/waveform_geom/time_mapper_test.dart` min/max/canZoom groups; `test/features/viewer/providers/time_providers_test.dart` "a 70-tick trace in a 1400 px viewport") + `[Coverage: UNIT]` (`action_descriptors_test.dart` "zoom gating", `active_tab_action_flags_provider_test.dart`); real wheel/pinch feel `[Coverage: MANUAL]`
- [ ] Q/E next-prev transition keyboard navigation — `[Coverage: UNIT]` (the live path in `viewer_screen.dart` calls `WaveformDataSource.nextTransition`/`prevTransition` directly — its query logic is covered by `test/services/waveform/wellen_provider_test.dart`; the E/Q key binding by `test/core/shortcuts/shortcut_bindings_test.dart`)
- [ ] Next/Prev Transition + Jump to Start/End require a cursor (toolbar buttons + menu/palette greyed without one; t=0 fallback removed) — `[Coverage: WIDGET/UNIT]` (`viewer_toolbar_test.dart` "transition buttons disabled with a file but no cursor" + `action_descriptors_test.dart`)
- [ ] Touch device cursor/marker hit area ≥ 44 dp — `[Coverage: WIDGET]` (`time_ruler_widget_test.dart` includes touch-target compliance assertion per ARCHITECTURE.md §3.1.8.11)
- [ ] Window resize keeps cursors/ruler correct (waveform fills width, scrollbar thumb + secondary cursor/blue ruler marker not stuck at stale positions) — `[Coverage: WIDGET]` (`waveform_canvas_test.dart` "resize guard re-syncs TimeMapper after a stale/dropped update"); macOS live-resize feel `[Coverage: MANUAL]`

## 10d. Command palette (§19)

- [ ] Opens on Ctrl/Cmd+Shift+P — `[Coverage: WIDGET]` (`test/features/command_palette/widgets/command_palette_dialog_test.dart` + shortcut binding test)
- [ ] Fuzzy search filters action list in real time — `[Coverage: WIDGET]` (`command_palette_dialog_test.dart`)
- [ ] Each row shows label + category + shortcut binding — `[Coverage: WIDGET]` (`command_palette_dialog_test.dart`)
- [ ] ↑/↓ navigation, Enter executes, Esc dismisses — `[Coverage: WIDGET]` (`command_palette_dialog_test.dart` keyboard navigation tests)
- [ ] No-results empty state — `[Coverage: WIDGET]` (`command_palette_dialog_test.dart`)
- [ ] Diagnostics action gated on `diagnosticsAvailableProvider` — `[Coverage: WIDGET]` (`command_palette_dialog_test.dart` — `kDebugMode`-gated visibility test)
- [ ] Locale sweep (zh_CN, ja, ko) — `[Coverage: WIDGET]` (`command_palette_dialog_test.dart` includes locale sweep)

## 10e. Export — VCD/SAIF/PNG/SVG/clipboard (§20)

**SAIF switching activity.** Deliberately the only "power analysis" WaveCrux
does. It is switching activity, not power — nothing here computes watts, and if a
future change starts naming things "power" that scope decision is being lost. What a verifier is checking is whether the *numbers are true*.

- [ ] **`T0 + T1 + TX + TZ` equals the analysis window exactly, per bit** — the invariant that catches nearly every accumulation bug, and the first thing a consuming tool notices — `[Coverage: UNIT]` (`test/services/export/saif_export_test.dart`)
- [ ] **Unknown time before a signal's first value is `TX`, not `T0`** — calling it 0 would invent a window of settled-low time and under-report activity on a net that was never driven — `[Coverage: UNIT]` (same file)
- [ ] **Only 0↔1 counts as a toggle** — a settle out of `x` is not a physical transition, and counting it inflates an energy estimate — `[Coverage: UNIT]` (same file)
- [ ] **Buses emit one entry per bit**, LSB at index 0, with escaped `\[n\]` labels; scalars carry no index — `[Coverage: UNIT]` (same file)
- [ ] **Real `TX` / `TZ` are reported, not hardcoded to zero** — Verilator's own emitter hardcodes them because it has two-value logic; reading four-state data is the one place this exporter does better, and only a test keeps it that way — `[Coverage: UNIT]` (same file)
- [ ] **Real-valued signals are skipped, not approximated** — SAIF describes bit-level dwell time and a `real` has no bits — `[Coverage: MANUAL]` (export a trace containing a `real`; confirm it is absent from the file rather than present with invented values)
- [ ] **The document parses in a consuming tool** — the one check no unit test can make. Read the file with whatever power tool is to hand and confirm the instance tree and net names match the design — `[Coverage: MANUAL]`
- [ ] **Export dialog fits a short window** — the SAIF option made it a four-format list, and on a 600 dp-tall viewport the actions row went off-screen in test. Open the dialog on a short/landscape window and confirm Cancel and Export… are both reachable — `[Coverage: MANUAL]` (two widget tests pump a taller surface rather than assert this)


- [ ] SAIF export writes a `.saif` and reports the path; a cancelled save picker leaves no file and no error — `[Coverage: MANUAL]`
- [ ] VCD export round-trip: export → re-parse → values match at sampled times — `[Coverage: WIDGET]` (`test/services/vcd_writer/vcd_writer_service_test.dart`)
- [ ] PNG export at 1× / 2× / 3× resolution — `[Coverage: WIDGET]` (`test/services/export/image_export_service_test.dart`)
- [ ] SVG export preserves text as real text, shapes as vectors — `[Coverage: WIDGET]` (`image_export_service_test.dart`)
- [ ] Copy Value (cursor value), Copy Full Path, Copy as JSON (transaction) — `[Coverage: WIDGET]` (`test/features/viewer/widgets/value_column_row_test.dart` + `signal_list_panel_test.dart` + `transaction_table_panel_test.dart`)
- [ ] Empty-state messaging when nothing to export — `[Coverage: WIDGET]` (`test/features/viewer/widgets/export_dialog_test.dart`)

## 10f. Action discoverability — menu bar / overflow / toolbar (§21)

- [ ] macOS: native `PlatformMenuBar` with all `ActionCategory` groups, shortcut bindings inline, file-dependent disable, locale sweep — `[Coverage: WIDGET]` (`test/features/menu_bar/widgets/desktop_menu_bar_test.dart`)
- [ ] **Windows & Linux: in-window Material `MenuBar` renders (these show NO menus with the old macOS-only `PlatformMenuBar`)** — `[Coverage: WIDGET]` (`desktop_menu_bar_test.dart` — `linux:`/`windows:` groups) + `[Coverage: INTEGRATION]` (`integration_test/menu_bar/desktop_menu_bar_test.dart` — real-app launch asserts the menu bar renders on the host OS; Win/Linux taps View → Toggle Theme end-to-end)
- [ ] Settings is in the app/File menu, never Help: macOS app menu = About·Settings·Quit; Win/Linux fold Settings+Quit into File, About in Help — `[Coverage: WIDGET]` (`desktop_menu_bar_test.dart`)
- [ ] **Menu-bound keyboard shortcuts fire by keyboard on all 3 desktop OSes — incl. macOS native menu (⇧⌘S / ⌘E / ⇧⌘I) without first clicking the canvas** (regression: a global `Shortcuts` catch-all consumed unhandled chords and suppressed the macOS native-menu key-equivalent; menu clicks masked it) — `[Coverage: WIDGET]` (`test/core/shortcuts/shortcut_manager_widget_test.dart` — "unhandled-intent fall-through") + `[Coverage: MANUAL]` (end-to-end native `NSMenu` key-equivalent, §21.3 step 5a)
- [ ] **Pressing a modal-opening shortcut twice (or auto-repeat) opens exactly one surface — no stacked dialogs** (Tab Diagnostics, Export, command palette, search, App Diagnostics, decoder picker, Settings, About, pane Render Stats); re-opening after close still works — `[Coverage: UNIT]` (`test/core/ui/modal_guard_test.dart`) + `[Coverage: MANUAL]` (per-surface end-to-end, §21.3 step 5b)
- [ ] **Keys pressed in a dialog stay in the dialog** (§21.3 step 5c): Escape in Settings or the signal search dialog closes it without clearing cursors; W/D and M+letter do nothing to the waveform while a dialog or menu is on top, and work again once it closes — `[Coverage: WIDGET]` (`test/accessibility/screen_reader_test.dart` — "keys pressed in a dialog stay in the dialog") + `[Coverage: MANUAL]` (Settings end-to-end)
- [ ] Menu item order + logical separators match `kMenuLayout`; table covers exactly the menu-visible set (no dupes, category-consistent) — `[Coverage: UNIT]` (`test/core/shortcuts/menu_layout_test.dart`)
- [ ] Phone: the toolbar's overflow icon opens a categorized bottom sheet — `[Coverage: WIDGET]` (`test/features/viewer/widgets/viewer_toolbar_test.dart` — "overflow menu" group; `test/core/shortcuts/action_surface_conformance_test.dart`)
- [ ] Tablet: overflow opens a popup menu — `[Coverage: WIDGET]` (`viewer_toolbar_test.dart` — "a tablet gets a popup menu, not a sheet")
- [ ] Phone/tablet: overflow file-dependent items (Add Protocol Decoder, zoom, export, …) enabled when a file is open, grayed only when none — gating reads the active tab's filePath, not the root-scope per-tab `waveformIsLoadedProvider` — `[Coverage: WIDGET]` (`test/core/shortcuts/action_context_provider_test.dart` — "fileLoaded follows the active tab filePath"; `action_surface_conformance_test.dart` — overflow enablement)
- [ ] Toolbar `skip_previous` / `skip_next` (Q/E) buttons present and work — `[Coverage: WIDGET]` (`test/features/viewer/widgets/viewer_toolbar_test.dart`)
- [ ] New `ShortcutAction` automatically appears in menu bar / overflow / palette — `[Coverage: WIDGET]` (`test/core/shortcuts/` enumeration tests + the menu/overflow/palette tests all derive from the enum)
- [ ] Diagnostics + statistics-strip toggle gated correctly per device class — `[Coverage: WIDGET]` (`desktop_menu_bar_test.dart` + `test/features/statistics/widgets/live_statistics_strip_test.dart`)
- [ ] Win/Linux native-like menu theming: compact 13 px regular weight, visible hover, app-surface background, left-aligned — `[Coverage: UNIT]` (`test/core/theme/wavecrux_theme_test.dart` menu-bar group) + MANUAL visual feel
- [ ] Win/Linux Alt-key mnemonics + menu mode (VS Code parity): hold Alt underlines a unique letter per menu (F/V/N/S/T/H, gap below glyph); **tap Alt** latches underlines + focuses first menu (primary outline); Left/Right/Down/Enter/Esc navigate; Alt+letter and bare-letter-in-mode open; all 4 locales; no conflict with Ctrl/Cmd; underline no longer flickers every-other-press — `[Coverage: WIDGET]` (`mnemonic_menu_bar_test.dart` key sequences + `menu_mnemonics_test.dart`) + `[Coverage: UNIT]` (`action_category_test.dart`) + MANUAL (arrow traversal + visual feel)

### 10g. Custom window chrome — Windows/Linux frameless title bar (§21.10)

- [ ] Win/Linux: no OS title bar; one slim custom strip with app logo at far-left (no app-name text), menus inline, min/maximize/close at right — `[Coverage: WIDGET]` (`desktop_menu_bar_test.dart` Win/Linux + `test/features/window_chrome/widgets/window_title_bar_test.dart`)
- [ ] Caption buttons minimize/maximize-restore/close behave natively; glyph follows maximize state — `[Coverage: WIDGET]` (`window_caption_buttons_test.dart`) + MANUAL (real window ops)
- [ ] Drag region moves window; double-click toggles maximize; window resizes from edges + casts shadow — `[Coverage: MANUAL]` (validate Linux X11 **and** Wayland)
- [ ] `useCustomWindowChrome` true on Win/Linux, false on macOS/mobile — `[Coverage: UNIT]` (`test/features/window_chrome/window_chrome_platform_test.dart`)
- [ ] **Leading tab insertion slot reachable under the Linux resize border** — the window's 8 dp left drag-to-resize border would otherwise occlude the first tab insertion slot (at x∈[0,8]), making "drag a tab before the first tab" a silent no-op. The tab strip insets past it on Linux (`windowChromeLeftResizeEdge`); confirm a tab can be dropped into the first position on Linux — `[Coverage: WIDGET]` (`window_chrome_platform_test.dart` predicate + `viewer_tab_bar_drag_reorder_test.dart` inset present on Linux/absent elsewhere) + `[Coverage: INTEGRATION_TEST]` (`tab_drag_reorder_test.dart` "drag second tab before first")
- [ ] macOS unaffected: native title bar + top-of-screen system menu retained — `[Coverage: MANUAL]`

### Action-surface single source of truth (`descriptorFor` / `actionContextProvider`)

All five surfaces (toolbar, menu bar, overflow, command palette, **and the keyboard**) render from / dispatch through the one `descriptorFor` table — visibility, enablement, and tier are declared once and conformance-checked. `[Coverage: WIDGET]` (`test/core/shortcuts/action_surface_conformance_test.dart`, `action_descriptors_test.dart`, `action_context_provider_test.dart`).

- [ ] Command palette **omits** the `setFormat*` family, `Next/Previous Tab`, and `Jump to Tab 1–9` (keyboard-/context-only; previously leaked into the palette) — `[Coverage: WIDGET]` (conformance "hidden families never appear")
- [ ] Command palette omits file-dependent actions when no file is loaded and lists them once a file is open (matches the menu/overflow greying) — `[Coverage: WIDGET]` (conformance "file-gated actions absent without a file, present with")
- [ ] Context-state gating: Set Marker / Clear Cursors / Jump-to-Start/End / Next-Prev Transition require a cursor; Jump/Remove Marker require a marker; Next/Prev Divergence require an active diff; Next/Prev Pattern Match require a match; Clear Cocotb Log requires a loaded log; Stage Undo/Redo require the Stage panel open — `[Coverage: UNIT]` (`action_descriptors_test.dart` "context gating" + `active_tab_action_flags_provider_test.dart`)
- [ ] Collaboration actions gate on session state everywhere: `Share/Join` only when not in a session; `Stop Sharing` only while hosting; `Leave Session` only as a non-host participant; `Export Session Recording` only with a session/recording — `[Coverage: WIDGET]` (conformance "collaboration actions gate on session state" + `action_descriptors_test.dart`)
- [ ] Phone hides device-gated actions in the overflow (diagnostics surfaces, cross-probe panel, statistics strip, RTL panel, pane operations); `Move Tab to Other Pane` is command-palette-only — `[Coverage: WIDGET]` (conformance "presence matches groupedActionsFor(overflow) on phone")
- [ ] Pro/Enterprise actions show a tier badge in overflow + palette and a `(PRO)`/`(ENT)` suffix in the native menu bar — `[Coverage: WIDGET]` (conformance menu presence incl. tier suffix; Pro badge coverage in the Pro overlay)
- [ ] Adding a new `ShortcutAction` fails to compile until `descriptorFor` has a case (exhaustive switch) — `[Coverage: COMPILE]`
- [ ] **Keyboard parity (WC9-C):** firing a shortcut for an action the table reports as **disabled** invokes no handler — no dialog, no state change. Swept table-driven over every disabled `ShortcutAction` — `[Coverage: WIDGET]` (`test/core/shortcuts/shortcut_dispatch_conformance_test.dart`)
- [ ] **Keyboard feedback (WC9-C follow-on):** the same refused shortcut *explains itself* — a snackbar naming the first unmet `ActionRequirement` (e.g. no cursor → "Place a cursor in the waveform to use this command."), localized in all four locales — `[Coverage: WIDGET]` (`shortcut_dispatch_conformance_test.dart` sweep + locale sweep; `action_requirement_test.dart`)
- [ ] **Jump to Start / Jump to End** with a file loaded but **no primary cursor**: menu greyed AND `Home`/`End` inert; set a cursor and both work — `[Coverage: WIDGET]` (`shortcut_dispatch_conformance_test.dart`) + `[Coverage: MANUAL]` (§21.8)
- [ ] **Share / Join Session** chords while already in a session do not open a second dialog (previously the dialog opened and only noticed the session afterwards) — `[Coverage: WIDGET]` (`shortcut_dispatch_conformance_test.dart`) + `[Coverage: MANUAL]` (§21.8)
- [ ] **Add Decoder with no file loaded** does not open the picker but *does* tell the user to load a waveform file ("Load a waveform file to use this command.") — the WC9-C guidance regression, restored — `[Coverage: WIDGET]` (`viewer_screen_test.dart` — "addDecoder shortcut with no file loaded explains itself instead of opening the picker")
- [ ] **Held disabled chord** shows exactly one hint at a time and queues nothing behind it — `[Coverage: WIDGET]` (`viewer_screen_test.dart` — "holding a disabled shortcut does not stack duplicate hints")

## 10g. Mobile UI standards (§22, per ARCHITECTURE.md §3.1.8)

- [ ] `MobileMetrics.of(context, deviceClass)` returns desktop sizes on desktop, touch sizes on phone/tablet (and on touch hosts at any width, including iPad Pro at desktop class) — `[Coverage: WIDGET]` (covered in core MobileMetrics tests under `test/core/`)
- [ ] Every interactive element on touch ≥ 44 × 44 dp hit area — `[Coverage: WIDGET]` (per-widget touch-target tests are mandatory per ARCHITECTURE.md §3.1.8.11; coverage spread across many widget tests)
- [ ] Drag affordances visible: signal-list reorder handle, lane resize grip, panel splitters (6 dp visual / 32 dp hit on touch), filled cursor triangles — `[Coverage: WIDGET]` (`signal_list_panel_test.dart` + `time_ruler_widget_test.dart`); splitter visual on real touch `[Coverage: INTEGRATION_TEST — pending]`
- [ ] Long-press = right-click on signal-list, signal-tree, cocotb log, canvas, transaction table — `[Coverage: WIDGET]` (per-row PlatformContextMenu tests in respective panel tests); real touch arena `[Coverage: INTEGRATION_TEST — pending]`
- [ ] Inner `onTap` does NOT fire after context-menu dismissal (translucent hit-test) — `[Coverage: WIDGET]` (gesture-bubbling regression tests in panel tests)
- [ ] In-row `Tooltip` uses `triggerMode: manual` — no tooltip races on touch — `[Coverage: WIDGET]` (regression test in row tests; static-analyzable invariant)
- [ ] Status-bar panel chevrons: left/center/right, direction-flip on toggle, hidden on phone — `[Coverage: WIDGET]` (`test/features/viewer/widgets/status_bar_test.dart`)
- [ ] Splitter `bottomMinSize` ≥ 80 dp; splitters always reachable when panel shown — `[Coverage: STATIC]` for the min-size invariant (`test/static/viewer_screen_pane_min_sizes_test.dart` — reads `viewer_screen.dart`'s per-tab `CruxIdeLayout` construction and asserts each `<pane>MinSize: PaneSize.pixel(N)` meets its floor: bottom ≥ 80, left/right ≥ 150, center ≥ 120 dp). Replaces the former `desktop_layout_min_sizes_test.dart`, which guarded the same constants on the now-deleted dead `DesktopLayout` widget rather than the live `ViewerScreen` path (B6). The "splitters always reachable" half (no chevron/overlay covers a splitter hit zone) is covered structurally by the status-bar-chevron tests (chevrons live in the status bar, not on panel headers, not as overlays)
- [ ] Phone-width force-hide of side/bottom panes; user preference preserved on resize back — `[Coverage: WIDGET]` (`test/features/viewer/screens/viewer_screen_test.dart` covers `_syncControllerToState` behavior)
- [ ] No `RenderFlex overflowed` at 320 dp wide — `[Coverage: WIDGET]` (per-chrome 320×568 surface assertion in `viewer_toolbar_test.dart`, `status_bar_test.dart` per ARCHITECTURE.md §3.1.8.12)
- [ ] Text scaling clamped to 0.85× / 1.5× — the clamp is applied at the app root (`lib/app.dart` `MediaQuery.withClampedTextScaling` inside `MaterialApp.builder`) and again around the status bar (`status_bar.dart`). `[Coverage: MANUAL]` — the former `adaptive_scaffold_test.dart` reference exercised the clamp on the now-deleted dead `AdaptiveScaffold` (B6), not this live app-root wrapper, so there is no automated coverage of the production clamp today; verify by raising OS text size past 150% and confirming chrome does not overflow. (Candidate for a small widget test asserting the app-root `MediaQueryData.textScaler` clamp.)
- [ ] `TextOverflow.ellipsis` paired with hover tooltip and/or context-menu path header — `[Coverage: WIDGET]` (`signal_list_panel_test.dart` covers the signal-list pattern; per-call-site coverage via row tests)

## 11. Performance

- [ ] Desktop: 1000 signals @ 60 fps avg — `[Coverage: HYBRID]` (`test/benchmarks/` covers parser/render numerically; perceptual 60 fps `[Coverage: MANUAL]`)
- [ ] Tablet: 500 signals @ 60 fps avg — `[Coverage: MANUAL]`
- [ ] Phone: 100 signals smooth — `[Coverage: MANUAL]`
- [ ] Parser benchmark within 10 % of prior baseline — `[Coverage: WIDGET]` (`test/benchmarks/` parser benchmarks; threshold check is automatable)
- [ ] Render benchmark within 10 % of prior baseline — `[Coverage: WIDGET]` (`test/services/render_benchmark/`)
- [x] 5-minute scroll session: memory stable, not growing without bound — `[Coverage: INTEGRATION_TEST]` (`integration_test/canvas/scroll_memory_soak_test.dart` — sustained scroll + zoom + pan soak, ≈5m42s real run; deterministic loaded-signal-count bound + tolerant median-RSS growth canary via `MemoryStatsService`)
- [ ] **Wide-file "Add All in Scope"** (§13.8) — on a generated `scale_2000sig.vcd` (`dart run tool/generate_scale_fixtures.dart`): names appear instantly, the first screenful paints within a beat (no multi-second freeze), the **status-bar progress indicator** advances then clears, lanes **fill incrementally**, scrolling all 2000 lanes stays **smooth**, and Memory stays **bounded** (LRU unloads off-screen). Cancel (×) stops promptly; scroll-during-load supersedes cleanly — `[Coverage: UNIT]` (`signal_load_planner_test.dart` viewport-gating + LRU, `signal_load_progress_provider_test.dart`) + `[Coverage: WIDGET]` (`signal_load_indicator_test.dart`); incremental-fill + 60 fps scroll perceptual `[Coverage: MANUAL]`
- [ ] Live statistics strip toggle and gating (desktop only); session-persisted — `[Coverage: WIDGET]` (`test/features/statistics/widgets/live_statistics_strip_test.dart` + `session_service_test.dart`)
- [ ] **Massive-hierarchy open** (§13.8A) — a gate-level FST with 100k+ scopes / 1M+ variables opens in seconds (no 5 s-era TimeoutException); hierarchy build is linear (walk-wide shared scratch buffers, not per-scope); open watchdog scales with file size (30 s + 1 s/MB, 10 min cap); malformed-VCD hang still recovers — `[Coverage: UNIT]` (`wellen_provider_failure_paths_test.dart` — scaledOpenTimeout group; hierarchy correctness via existing known-answer FFI fixture tests) + end-to-end `[Coverage: MANUAL]`
- [ ] **Flat lazy signal tree** (§13.8A) — expanding/collapsing ANY scope is instant, including the 64k-variable gate-level scope (viewport-only row builds; pre-0.2.4 eager recursion took minutes); search filtering stays per-keystroke fluid with it expanded; all row gestures/menus unchanged; same-scope alias twins (shared ref or duplicated escaped name) don't crash — `[Coverage: UNIT + WIDGET]` (`signal_tree_rows_test.dart`, `signal_tree_panel_test.dart` — "flat lazy tree") + perceptual smoothness on the gate-level reference FST `[Coverage: MANUAL]`
- [ ] **"Add All in Scope" never goes silent** (§13.8 steps 7–8) — the status-bar indicator is up from the moment the menu closes (indeterminate during the scope walk, then Adding, then Loading) with no gap before waveforms paint, below 5000 signals as well; a few very dense signals show the loading indicator after ~200 ms, a few light ones never flash it — `[Coverage: WIDGET]` (`scope_tree_node_test.dart` "Add All in Scope", `waveform_canvas_load_progress_test.dart`, `signal_load_indicator_test.dart`) + perceptual `[Coverage: MANUAL]`
- [ ] **Million-signal "Add All in Scope"** (§13.8) — ≥5000-var batches take the chunked path: context menu closes immediately (no frozen-menu freeze), status-bar indicator runs an "Adding signals" phase then hands off to the loading phase, entries land in ONE state update, cancel during Adding applies nothing; entry ids are run-tag+counter (no per-entry UUID); ≥50k-entry autosave encodes compact on a worker isolate; signal-list group-target scan hoisted to once per rebuild — `[Coverage: UNIT + WIDGET]` (`signal_group_providers_test.dart` addSignalsChunked, `signal_load_progress_provider_test.dart` phases, `scope_tree_node_test.dart` "Add All in Scope", `session_service_test.dart` large-session save) + perceptual smoothness on the gate-level reference FST `[Coverage: MANUAL]`

---

## 11A. Rendering golden tests (ARCHITECTURE §8.9 Layer 5)

> Goldens are macOS-baselined and macOS/native-FFI-gated; the macOS CI `test` job exercises them. Regenerate with `flutter test --update-goldens test/features/viewer/rendering/waveform_canvas_golden_test.dart` and eyeball the PNGs before committing. See VERIFICATION_GUIDE.md §13A.

- [ ] Scalar + 8-bit bus render baseline (dark theme) — `[Coverage: WIDGET]` (`waveform_canvas_golden_test.dart` → `goldens/scalar_basics_dark.png`)
- [ ] Multi-bit vector/bus parallelograms incl. x/z (dark theme) — `[Coverage: WIDGET]` (`goldens/vector_formats_dark.png`)
- [ ] Analog/real interpolated traces + inline cursor (dark theme) — `[Coverage: WIDGET]` (`goldens/analog_real_dark.png`)
- [ ] Oscilloscope preset: signal colors + x-state hatch — `[Coverage: WIDGET]` (`goldens/vector_formats_oscilloscope.png`)
- [ ] Oscilloscope preset: analog traces + inline cursor sample on the preset's canvas — `[Coverage: WIDGET]` (`goldens/analog_real_oscilloscope.png`)

---

## 12. Edge cases / break-it tests

- [ ] Empty VCD: counts = 0, no crash — `[Coverage: WIDGET]` (`test/services/waveform/` covers parser empty-VCD case)
- [ ] X/Z-only signals: flagged in Signal Health — `[Coverage: WIDGET]` (`test/services/diagnostics/` signal-integrity tests)
- [ ] Decoder on wrong signals: no crash, garbage results acceptable — `[Coverage: WIDGET]` (each `test/services/decoders/*_test.dart` includes a "wrong bindings" robustness test)
- [ ] Remove + re-add decoder: same transactions on second add — `[Coverage: WIDGET]` (`test/features/decoders/providers/active_decoders_provider_test.dart` — "remove + re-add decoder → same transactions on second add" decodes once, removes, re-adds with same config, decodes again, asserts the transaction lists are equal. Guards against stale signal-load caches or stateful decoder instances leaking across remove/re-add cycles)
- [ ] Open new file with diff/X-Trace/pattern-search/switching-activity/FSM active: ALL clear — `[Coverage: WIDGET]` (`test/features/viewer/providers/waveform_source_provider_test.dart` — explicit "openFile clears X" + "close clears X" cases for all 5 features (XTraceState, DiffState, PatternSearchState, SwitchingActivityState, FsmViewState + FsmAnnotation map). Each test forces the provider into a non-default state via a testable subclass, calls openFile/close, then asserts state has reset to default — catches the regression where someone removes a `ref.read(xNotifier).clearX()` call from `openFile`/`openFromBytes`/`attachStreamingSource`)
- [ ] Malformed-VCD corpus: clear errors, no crashes — `[Coverage: WIDGET — pending]` (full-corpus parser robustness test is not yet in `test/services/waveform/`; queued. Needs fixtures acquired through the `test/fixtures/real_world/` provenance process — the FastWaveBackend corpus formerly named here was removed 2026-07-31 as unlicensed, see `NOTICES` §15)
- [ ] Vendor-specific corpus (Aldec/Cadence/Mentor/Synopsys/Verilator): all open — `[Coverage: WIDGET — pending]` (the `real_world/` zoo already covers part of this matrix)
- [ ] `vcd/deep_hierarchy.vcd`: 10+ levels expand correctly — `[Coverage: WIDGET]` (`test/services/waveform/` covers parser; tree expansion `test/features/signal_tree/widgets/` covers UI)
- [ ] Identifier edge cases: full ASCII range loads correctly — `[Coverage: WIDGET]` (`test/services/waveform/` parser tests against `identifier_edge_cases.vcd` fixture)

---

## 12.1 SigRok bridge plugin (downloadable, opt-in — separate `wavecrux-sigrok-bridge` repo)

> Skip this section if the bridge is not installed. The bridge is a downloadable, opt-in plugin distributed via GitHub Releases on `wavecrux/wavecrux-sigrok-bridge`. See VERIFICATION_GUIDE.md §22.5.4.1 for the full walkthrough.

- [ ] Bridge installed: shim binary in per-user plugin directory; subprocess on PATH or sibling — `[Coverage: MANUAL]`
- [ ] Settings → Decoders → Plugins shows the bridge with status `loaded`, ABI `1.0`, GPLv3+ description visible — `[Coverage: AUTOMATED]` (`test/services/decoders/ffi/sigrok_bridge_smoke_test.dart` confirms load via `DecoderRegistry`; visible-in-UI is manual)
- [ ] All five reference decoders decode correctly against their fixture VCDs (1-Wire / JTAG / PWM / DMX512 / Modbus) — `[Coverage: AUTOMATED]` (bridge repo's own CI; WaveCrux side covers shim ↔ bridge load)
- [ ] License-isolation invariant 2 (no GPL linkage in the shim) — `[Coverage: AUTOMATED]` (bridge repo's `.github/workflows/isolation.yaml`; this is a hard gate on every bridge release)
- [ ] Subprocess kill mid-session: WaveCrux does not crash, error transaction surfaces, next activation respawns — `[Coverage: MANUAL]`
- [ ] ABI mismatch path: bridge built against future MAJOR shows `abiMismatch` row, no decoders appear in picker — `[Coverage: MANUAL]`
- [ ] X/Z policy default (`glitch`): indeterminate bits produce a glitch annotation, no libsigrokdecode-side garbage — `[Coverage: MANUAL]`
- [ ] X/Z policy override (`coerce_last`) per-instance: behaves correctly for a fixture with brief reset-time X-storm — `[Coverage: MANUAL]`

---

## 12.2 About Box (§22.6)
- [ ] About presents as a modal dialog on desktop AND desktop-browser web (was mobile slide-in on web); pushed full-screen route on phone/tablet — `[Coverage: WIDGET]` (crux-shared `crux_about_dialog_test.dart`)
- [ ] Empty-canvas header shows the muted "Version X.Y.Z" line with the real running version (web's only always-visible version surface) — `[Coverage: WIDGET]` (`wavecrux_empty_canvas_test.dart`)

- [ ] Dialog rendered by the shared `crux_about_dialog` package (`CruxAboutDialog`); `WaveCruxAboutDialog.openAdaptive` maps WaveCrux providers/strings onto it — behavior unchanged by the lift — `[Coverage: WIDGET]` (`test/features/about/widgets/wavecrux_about_dialog_test.dart` opens via `openAdaptive`)
- [ ] Dialog opens from platform menu bar (macOS: WaveCrux → About; Win/Linux: Help → About) — `[Coverage: MANUAL]`
- [ ] "About WaveCrux" title visible — `[Coverage: WIDGET]` (`test/features/about/widgets/wavecrux_about_dialog_test.dart`)
- [ ] Version, build number, git SHA visible from `applicationBuildInfoProvider` — `[Coverage: WIDGET]` (same file)
- [ ] Ferrite Engineering company name in branding banner — `[Coverage: WIDGET]` (same file)
- [ ] "Public Beta" chip visible when `kBetaPeriod = true`; absent when `false` — `[Coverage: WIDGET]` (same file)
- [ ] No edition chip for Open Core; "EDU" badge for EDU tier — `[Coverage: WIDGET]` (same file)
- [ ] "Copy Version Info" button enabled after async load; clipboard content is structured plain text — `[Coverage: WIDGET]` (`wavecrux_about_dialog_test.dart` — "Copy Version Info button is enabled once build info loads" + "tapping Copy Version Info writes the structured build info to the clipboard" mocks `SystemChannels.platform` and asserts the captured text contains app name + version + build + git SHA + OS + arch + Flutter/Dart versions; string format unit-tested in `crux_about_dialog`'s `aboutVersionInfoText` group)
- [ ] "Acknowledgments" screen opens; shows wellen, Flutter, flutter_riverpod entries; BSD 3-Clause and MIT badges visible; back button returns — `[Coverage: WIDGET]` (`test/features/about/widgets/about_acknowledgments_screen_test.dart`)
- [ ] "Visit Website" and "Report Issue" buttons open correct browser URLs — `[Coverage: MANUAL]`
- [ ] wellen BSD-3-Clause expander taps without exception — `[Coverage: WIDGET]` (`test/features/about/widgets/wavecrux_about_dialog_test.dart`)
- [ ] No RenderFlex overflow at phone (400 dp), tablet (800 dp), desktop (1400 dp) — `[Coverage: WIDGET]` (same file)
- [ ] No exception in en, zh, ja, ko locale sweeps — `[Coverage: WIDGET]` (same file)
- [ ] `applicationEditionProvider` returns "Open Core" by default — `[Coverage: WIDGET]` (`test/core/app_info/application_edition_provider_test.dart`)
- [ ] `applicationBuildInfoProvider` and `applicationBrandingProvider` return expected values when overridden — `[Coverage: WIDGET]` (`test/core/app_info/application_build_info_provider_test.dart`, `test/core/app_info/application_branding_provider_test.dart`)

---

## 12.3 Color Theming & Customization (Open Core — §22.7)

> Settings → Appearance renders
> `crux_theme`'s `ThemeAppearanceSection` composer in place of the
> bespoke preset grid / palette editor / quick-override pickers. The
> palette editor is retired (the package only stores scalar `Color`
> tokens today); the four-token quick-override picker is subsumed by
> the package's `TokenCategorySection`. Internal package surfaces are
> covered upstream in `crux_theme`'s own test suite.

### Preset switching — end-to-end visual check (post-Session 5 fix)

Picking a preset must repaint EVERY surface, not just the preset card outline. The bugs that motivated these bullets were: chrome stayed dark on WaveCrux Light, canvas background never re-tinted, and Solarized Dark's chrome tokens were ignored entirely.

- [ ] Picking `WaveCrux Light` flips MaterialApp brightness to light: scaffold, AppBar, panel surfaces, settings dialog, tab bar all visibly light — `[Coverage: MANUAL]`
- [ ] Picking `WaveCrux Dark` from light state flips brightness back to dark — `[Coverage: MANUAL]`
- [ ] Picking `Solarized Dark` (a preset with `chrome.*` tokens) repaints the toolbar, scaffold, and panel backgrounds with Solarized hues (NOT default Material-3 dark) — `[Coverage: MANUAL]`
- [ ] Picking `Oscilloscope` repaints chrome with phosphor-green-on-black hues — `[Coverage: MANUAL]`
- [ ] Waveform canvas background paints the active preset's `canvas.background` token (visible difference between WaveCrux Dark, Solarized Dark, and Oscilloscope) — `[Coverage: MANUAL]`
- [ ] Lane backgrounds alternate using `canvas.lane.backgroundOdd` / `canvas.lane.backgroundEven` (subtle but visible row striping at typical zoom) — `[Coverage: MANUAL]`
- [ ] Every cursor, marker and ruler token in Color overrides → Canvas repaints its element when edited (`cursor.primary`/`secondary` lines + ruler triangles, `cursor.delta` band, `marker.line`, `marker.flag`/`flagText`, `ruler.background`/`tick`/`label`/`cursorTime`), unedited Crux Dark / Crux Light paint the cursor layer and ruler exactly as before the tokens were wired, and Solarized Dark, High Contrast Dark, Oscilloscope and OLED XR paint their designed cursor, marker and ruler palette (§22.7.8a) — `[Coverage: WIDGET]` (`test/features/viewer/widgets/canvas_theme_tokens_paint_test.dart`)
- [ ] Settings → Appearance → "Waveform Font Size" slider visibly resizes the in-canvas value labels and group-header labels at 8, 12, 18, 24 — `[Coverage: MANUAL]`
- [ ] Font size choice survives an app restart — `[Coverage: AUTOMATED]` (`test/services/settings/settings_service_test.dart` round-trip)

- [ ] All 5 built-in presets activate without crash; canvas background changes immediately — `[Coverage: WIDGET]` (`test/features/settings/widgets/color_theme_section_test.dart`)
- [ ] Tapping a preset card persists `activeThemeName` to `AppSettings` (write-through path) — `[Coverage: AUTOMATED]` (same)
- [ ] Active preset name persists in session file and is restored on reopen — `[Coverage: AUTOMATED]` (`test/services/session/session_service_test.dart` — `activeThemeName` round-trip tests)
- [ ] Theme-not-found fallback: `wavecrux-dark` activated, snackbar shown — `[Coverage: MANUAL]`
- [ ] Import valid `.crux-theme.json` via Theme pack browser: pack appears in installed list, Activate applies tokens — `[Coverage: MANUAL]`
- [ ] Import invalid JSON: rejected with error snackbar, installed list unchanged — `[Coverage: AUTOMATED]` (`crux_theme` package suite)
- [ ] Import unknown `brightness` value: rejected with error snackbar — `[Coverage: AUTOMATED]` (`crux_theme` package suite)
- [ ] Import file with invalid hex token: pack installs, bad token silently falls back to registered default — `[Coverage: AUTOMATED]` (`crux_theme` package suite)
- [ ] Export active theme: `.crux-theme.json` contains expected keys (schemaVersion, id, displayName, brightness, tokens) — `[Coverage: AUTOMATED]` (`test/features/settings/widgets/color_theme_section_test.dart` — "export writes the active theme to the picked path")
- [ ] Import button invokes injected `pickPackFile` callback — `[Coverage: AUTOMATED]` (same)
- [ ] Export button invokes injected `pickExportLocation` callback — `[Coverage: AUTOMATED]` (same)
- [ ] Per-token color picker: tapping a swatch opens `ColorPickerDialog`; picking a color updates the swatch and re-paints the canvas — `[Coverage: MANUAL]` (`crux_theme` covers the package widget; WaveCrux integration is manual)
- [ ] Per-token reset: tapping reset removes the override from `AppSettings.themeOverrides` and the token returns to the preset default — `[Coverage: MANUAL]`
- [ ] Token override persists across app restart — `[Coverage: MANUAL]`
- [ ] Uninstall confirmation dialog: Cancel keeps the pack installed; Uninstall removes it from the list and from `${appSupportDir}/themes/` — `[Coverage: MANUAL]`
- [ ] GTKWave `.gtkw` import with `[bgcolor]` → canvas background and theme unchanged (`[bgcolor]` is not imported) — `[Coverage: AUTOMATED]` (`test/services/session/gtkw_parser_test.dart` and `test/services/session/gtkw_import_service_test.dart`)
- [ ] GTKWave `.gtkw` import with invalid `[bgcolor]` hex → import completes — `[Coverage: AUTOMATED]` (same)
- [ ] Chrome-only theme pack (no `canvas` key) → canvas uses preset defaults, chrome updates — `[Coverage: MANUAL]`
- [ ] No RenderFlex overflow in Settings → Appearance at 320 dp width — `[Coverage: WIDGET]` (`crux_theme` package suite covers internal widgets)
- [ ] No exception in en, zh_CN, zh, ja, ko locale sweeps for Settings → Appearance — `[Coverage: WIDGET]` (`test/features/settings/widgets/color_theme_section_test.dart` — full five-locale sweep)
- [ ] `WaveCruxThemeAppearanceStrings` exposes every interface slot (ARB-drift guard) — `[Coverage: AUTOMATED]` (same)
- [ ] `ColorThemeSection` renders the three composer surfaces (`PresetPicker`, `TokenCategorySection`, `ThemePackBrowser`) — `[Coverage: AUTOMATED]` (same)

---

## 12.4 Multi-Tab Workspace (Open Core — §22.8)

- [x] No `+` new-tab button and no Cmd/Ctrl+T new-tab shortcut — WaveCrux intentionally omits every blank-new-tab affordance (a blank tab is a dead-end: File→Open always creates a new tab and a blank tab exposes no in-tab way to load anything) — `[Coverage: WIDGET + UNIT]` (`test/features/workspace/widgets/wavecrux_empty_canvas_test.dart` — `emptyCanvasNewTabButton` is `findsNothing`; `test/core/shortcuts/shortcut_action_test.dart` — `ShortcutAction.values` no longer contains `newTab`)
- [x] Open file → always opens in a new tab; never replaces an existing tab — `[Coverage: AUTOMATED]` (`test/features/tabs/providers/tab_providers_test.dart` — "openFile always appends — never replaces an existing tab")
- [x] Close tab × → tab removed; closing last tab leaves the tab list empty and the empty-canvas state renders — `[Coverage: AUTOMATED]` (`test/features/tabs/providers/tab_providers_test.dart` — "closing the last tab leaves the list empty")
- [ ] Tab switching preserves per-tab cursor, zoom, and signal arrangement — `[Coverage: MANUAL]`
- [x] Per-tab provider scoping — no provider reads per-tab state from root scope (issue #44 bug class; Stage bindings, FSM diagram, memory guard) — `[Coverage: AUTOMATED]` (`test/static/per_tab_provider_scope_leak_test.dart` structural guard over the whole class; `test/services/tabs/per_tab_scope_behavior_test.dart` real parent/child container behavior; `test/services/tabs/wavecrux_tab_overrides_test.dart` #44 + FSM + timescale override pins; manual UX steps in §22.9.15)
- [x] Panel visibility is **per-tab** (signal-tree, value-column, bottom/transaction, Stage, statistics strip) — toggling a chevron / toolbar button / menu item affects only the active tab, even for two tabs in the same split pane; a new tab starts at clean-slate defaults (does not inherit another tab's open panel); the chevron indicator and rendered panel always agree (the per-pane split-brain is structurally gone). Each tab's arrangement persists in its session sidecar and restores across restart — `[Coverage: AUTOMATED]` (`test/features/viewer/screens/viewer_screen_test.dart` — "panel visibility is per-tab — a new tab keeps its own default…"; `test/services/panes/pane_container_manager_test.dart` — panel layout not isolated per-pane; `test/features/viewer/providers/session_providers_test.dart` — panel-layout restore) + `[Coverage: MANUAL]` for same-pane/split-pane independence and cross-restart persistence per §22.9.16
- [ ] Tab bar rendered on desktop and tablet; absent on phone — `[Coverage: WIDGET]` (same file)
- [ ] Tab overflow → left/right scroll chevrons appear when tab count exceeds bar width — `[Coverage: WIDGET — pending]`
- [x] Drag-to-reorder tab chips updates `tabListProvider` ordering — `[Coverage: UNIT + INTEGRATION_TEST]` (`test/features/workspace/providers/workspace_provider_test.dart` notifier `reorderTab` contract, `integration_test/tabs/tab_drag_reorder_test.dart` full-app gesture; no headless widget-level drag test is committed)
- [ ] Tab context menu (post-swap parity, §16.1.6): monospace full-path header (§3.1.8.14), Duplicate Tab, Move to New Window (disabled), Reveal in Finder/Explorer/Files, Tab Diagnostics, Close Tab, Close Other Tabs, Close Tabs to the Right — `[Coverage: WIDGET]` (`test/features/panes/widgets/wavecrux_pane_host_test.dart` header + close + duplicate) + `[Coverage: MANUAL]` (Reveal opens the OS browser)
- [ ] Tab chip parity after the crux_workspace swap (§16.1.6): full file path on label hover-tooltip; name-bearing close-button tooltip ("Close <name>"); whole-chip drag with no handle icon + reachable leading insertion slot; focused-pane border full-strength at 3 dp / unfocused faint at rest — `[Coverage: WIDGET]` (`test/features/panes/widgets/wavecrux_pane_host_test.dart`; `crux_workspace` `viewer_tab_bar_parity_seams_test.dart`, `pane_host_seams_test.dart`)
- [ ] Active-pane border behaviour (§16.1.6, Issues #45/#46): **un-split** → no border at all (suppressed); **split** → focused pane accented at 3 dp, unfocused faint, both panes locked at 3 dp so switching focus does not squeeze/shift content — `[Coverage: WIDGET]` (`test/features/panes/widgets/wavecrux_pane_host_test.dart` — "un-split: the pane border is suppressed (transparent)" + "split: borders are 3 dp on both panes (no squeeze) …"; `crux_workspace` `pane_host_seams_test.dart` `isSplit` seam)
- [ ] Split-pane reorder regression: reordering a tab within the **second** pane lands at the dropped position (pane-local → global index translation via `reorderTabInPane`) — `[Coverage: UNIT]` (`crux_workspace` `viewer_tab_bar_parity_seams_test.dart` — "maps a pane-local index to the correct global position")
- [ ] "Move to New Window" is visible but disabled (`kMultiWindowAvailable = false`); tooltip explains — `[Coverage: MANUAL]`
- [ ] Keyboard shortcuts: close tab (Cmd/Ctrl+W), next/prev tab (Ctrl+Tab / Ctrl+Shift+Tab), jump to tab 1–9 (there is no new-tab shortcut) — `[Coverage: MANUAL]`
- [ ] All tab keyboard shortcuts appear in command palette under File category — `[Coverage: MANUAL]`
- [ ] CLI `wavecrux a.fst b.vcd` → two separate tabs opened — `[Coverage: INTEGRATION_TEST — pending]`
- [ ] Startup restoration: quit with 2 tabs → relaunch → same 2 tabs reopen (when `restoreTabsOnLaunch = true`) — `[Coverage: INTEGRATION_TEST — pending]`
- [ ] Startup restoration disabled in Settings → relaunch starts with the empty-canvas state — `[Coverage: MANUAL]` *(the "Welcome tab" is retired — an empty workspace renders the empty-canvas state)*
- [ ] Corrupt `last_session.json` → graceful fallback to the empty-canvas state, no crash — `[Coverage: AUTOMATED]` (`test/services/session/last_session_service_test.dart` — invalid JSON / wrong root type) *(workspace.json supersedes last_session.json)*
- [ ] `LastSessionManifest` JSON round-trip (tabs with and without sessionFilePath, empty manifest, edge-case fromJson inputs) — `[Coverage: AUTOMATED]` (`test/domain/models/last_session_manifest_test.dart`)
- [ ] `LastSessionService` save / load / clear / overwrite / graceful degradation — `[Coverage: AUTOMATED]` (`test/services/session/last_session_service_test.dart`)
- [ ] `NoopTabDetachingDelegate` and `NoopPanelPopOutDelegate` all four methods complete without throwing — `[Coverage: MANUAL]` (no dedicated unit-test file is committed today; the noop delegates live in `lib/core/windowing/` — see VERIFICATION_GUIDE.md "Delegate noops")
- [ ] Session save/load is per-tab: Cmd+S saves the active tab only — `[Coverage: MANUAL]`
- [ ] Panel context switches on tab change: waveform canvas, value column, signal tree, transaction view all reflect the new tab's state — `[Coverage: MANUAL]`
- [ ] Waveform diff panel: switching tabs while diff is open updates to the active tab's waveform — `[Coverage: MANUAL]`
- [ ] Diagnostics panel: switching tabs updates File Info, Memory, and Signal Health to the active tab's file — `[Coverage: MANUAL]`
- [ ] Status bar (cursor time, filename, zoom) updates immediately on tab switch — `[Coverage: MANUAL]`
- [ ] Phone: no tab bar rendered; Settings → General shows informational note about multi-tab on desktop — `[Coverage: WIDGET]` (same file)
- [ ] No RenderFlex overflow in tab bar at 600 dp, 1200 dp, 1920 dp widths — `[Coverage: WIDGET]` (same file)
- [ ] No exception in en, zh, ja, ko locale sweeps for tab bar and tab chip — `[Coverage: WIDGET]` (same file)
- [ ] `TabId` equality, hashCode, and round-trip serialization — `[Coverage: AUTOMATED]` (lives upstream at `crux-shared/packages/crux_workspace/test/tab_id_test.dart`)
- [ ] `WavecruxTab` construction, `copyWith`, dirty/detached state transitions — `[Coverage: AUTOMATED]` (`test/domain/models/wavecrux_tab_test.dart`)
- [x] `TabListNotifier`: open, close, reorder, dirty-marking, detach — closing last tab leaves the list empty (empty-canvas state) — `[Coverage: AUTOMATED]` (`test/features/tabs/providers/tab_providers_test.dart`) *(file path moved from `features/viewer/providers/` to `features/tabs/providers/`)*
- [ ] Per-tab provider isolation: mutations in container A do not affect container B; global providers resolve from root — `[Coverage: AUTOMATED]` (`test/services/tabs/tab_container_manager_test.dart`)
- [ ] **Screen-level surfaces resolve the ACTIVE TAB's per-tab providers, not the empty root scope.** Modals/drawers pushed by the root navigator (and root-scope chrome) must be re-bound to the active tab's container (or fed its data). With a file open, verify each reflects the active tab's data — not blank/disabled/no-file: signal-tree drawer (phone), value column, mobile overflow menu + command palette (Add Decoder & other file actions enabled), phone bottom-panel sheet (transaction table / FSM / X-Trace / switching-activity panels), Stage "Add Widget" picker (writes the tab's Stage workspace), Stage signal-binding picker (shows the tab's signals), FSM annotate dialog + phone FSM sheet (the tab's FSM), and cross-probe "send selection" (non-null cursor time). Switch tabs and re-verify each follows the focused tab. — `[Coverage: WIDGET]` (per-surface scope-guard tests, e.g. `command_palette_dialog_test.dart`, `action_context_provider_test.dart`, `viewer_screen_test.dart`, `lane_geometry_provider_test.dart`) + `[Coverage: MANUAL]` for the full multi-tab sweep
- [ ] Mobile memory guard unloads idle signals under pressure by reading the **active tab's** loaded source (not the empty root) — `[Coverage: MANUAL]` (memory-pressure scenario; the scope read is structural)

---

## 12.5 Workspace Model & Split-Pane (Open Core — §22.9)

> The workspace model supersedes the per-tab session model and the Welcome screen. The bullets below cover the workspace surface; some multi-tab bullets above are partially superseded but retained for traceability.

- [x] Empty-canvas startup state renders on a clean install (no Welcome tab visible) — `[Coverage: WIDGET]` (`test/features/workspace/widgets/wavecrux_empty_canvas_test.dart`, `test/features/viewer/screens/viewer_screen_test.dart` — `'renders EmptyCanvasState when the tab list is empty'`)
- [x] Recent files and recent workspaces list on empty-canvas state — `[Coverage: WIDGET]` (`test/features/workspace/widgets/wavecrux_empty_canvas_test.dart` — recent-files data path, no-recent-files hint, recent-workspaces placeholder hint)
- [x] Empty-canvas header shows the **official animated app icon** (`GlowingAppIcon`, same as the About dialog) and it pulses — not the static `waves_outlined` glyph (restores the animated logo lost with the separate welcome window) — `[Coverage: WIDGET]` (`test/features/workspace/widgets/wavecrux_empty_canvas_test.dart` — renders without exception; the perpetual-animation pump constraint is handled) + animation feel `[Coverage: MANUAL]` per §22.9.1
- [x] Empty-canvas docs hint "Visit **docs.wavecrux.app**" — the domain is a live link (underlined, primary color) that opens `https://docs.wavecrux.app` in the system browser; the linked domain is locale-independent so it works across en/zh_CN/ja/ko — `[Coverage: WIDGET]` (`test/features/workspace/widgets/empty_canvas_docs_hint_test.dart` — locale sweep + `tapOnText` on the domain span invokes the launch seam) + real browser open `[Coverage: MANUAL]` per §22.9.1
- [x] Recent files list does NOT show per-tab session sidecar paths (`{appSupportDir}/sessions/{tab-uuid}.json` — the real on-disk extension, written through the base `crux_workspace` service's `.json` default, **not** `.wavecrux`) — sidecar paths are rejected by `addFile` and any pre-existing persisted entries are stripped on next launch by `build()`; the guard matches `…/sessions/{uuid}.<ext>` generically so the `.json` files are caught (Issue 29) — `[Coverage: WIDGET]` (`test/features/workspace/providers/recent_files_provider_test.dart` — `'addFile silently rejects .json sidecar paths'` + `'build() one-shot cleanup also removes previously-persisted .json sidecars'`)
- [x] Recent files **records the waveform files the user actually opens** (`.vcd`/`.fst`/`.ghw`/`.fsdb`/`.lxt`/`.lxt2`) — opening via picker / CLI arg / recent-tap / last-session tab all land in the list; FSDB records the original `.fsdb` path, not the converted `.fst`; a declined size warning or cancelled FSDB conversion does not record (Issue: waveform opens were previously never recorded) — `[Coverage: MANUAL]` per §22.9.1.1 (the `addFile` site is in `ViewerScreen._openPath`, exercised end-to-end)
- [x] Saved sessions (`.wavecrux`) and imported GTKWave sessions (`.gtkw`) appear in Recent Files; `.wavecrux-workspace` files do **not** (they have their own Recent Workspaces list) — `[Coverage: MANUAL]` per §22.9.1.1
- [x] Tapping a Recent Files entry routes by type — waveform → new tab, `.wavecrux` → session loader (no waveform-parse error), `.gtkw` → GTKWave import against the active waveform (regression: the recent-tap handler previously fed every entry to the waveform loader) — `[Coverage: MANUAL]` per §22.9.1.1 (`ViewerScreen._openRecentFile` dispatch)
- [ ] Settings reachable from empty-canvas (`Cmd+,` / `Ctrl+,`) without opening a file — `[Coverage: MANUAL]` (the ViewerToolbar continues to render around the empty-canvas body so its Settings button works; verify on desktop and tablet)
- [ ] App Diagnostics reachable from empty-canvas — `[Coverage: MANUAL]` (same chrome path as Settings — the diagnostics affordance lives in the toolbar above the empty-canvas body)
- [x] File→Open always creates a new tab (never replaces existing tab) — `[Coverage: AUTOMATED]` (`test/features/tabs/providers/tab_providers_test.dart` — `'openFile always appends — never replaces an existing tab'`)
- [x] Tab close has no "unsaved changes" prompt — `[Coverage: AUTOMATED]` (`test/static/no_legacy_discard_prompt_test.dart` — guards against re-introducing `confirmDiscardSession` / `DiscardSessionDialog` / `sessionDirtyNotifierProvider`)
- [x] **Closing a tab while a long analysis is still running is silent and clean** — start an X-trace, pattern search, switching-activity analysis, waveform diff, or (Pro) an AI Advisor question, then close the tab before it finishes: no error toast, no console `UnmountedRefException`, and the app stays responsive. The in-flight work finishes into the void rather than publishing to a disposed tab — `[Coverage: AUTOMATED]` (`test/features/viewer/providers/notifier_dispose_race_test.dart` disposes the container mid-await for X-trace / pattern search / switching activity and asserts each completes without throwing) + `[Coverage: MANUAL]` for the diff and AI-advisor arms, which need a real second file / a real model key
- [x] **Closing a tab with a comparison file loaded releases the second waveform** — open a diff, close the tab, and confirm process memory drops by roughly the comparison file's size (App Diagnostics → Memory). The second native source is now closed on notifier disposal; previously nothing closed it and the whole comparison file leaked for the life of the process — `[Coverage: MANUAL]` (`DiffNotifier.build`'s `ref.onDispose`; memory delta is not assertable in a unit test)
- [x] App quit has no "unsaved changes" prompt — `[Coverage: AUTOMATED]` (same grep guard, since the quit handler was the only remaining caller)
- [x] Workspace auto-saved to `{appSupportDir}/workspace.json` on tab/pane mutations — `[Coverage: AUTOMATED]` (`test/services/workspace/wavecrux_workspace_codec_test.dart`, `test/features/workspace/providers/workspace_provider_test.dart` — `flushPendingSave` / "save is triggered after mutations")
- [ ] **Window size / position / maximized restore (Windows / Linux)** — geometry persisted **live** on resize/move/maximize (debounced `WindowListener`, written to `workspace.json` `extras.windowBounds` during the session, not quit-only — so it survives a hard window-close / killed debug session) and re-applied before the window's first show (no open-small-then-jump flash); off-screen / degenerate / stale geometry is sanitized (centered at saved size, floored to 800×500) rather than restoring off-screen; `--reset` and first launch open default centered 1280×720; macOS/web out of scope — `[Coverage: AUTOMATED]` (`test/services/workspace/window_bounds_store_test.dart` extras+peek; `test/features/workspace/providers/workspace_provider_test.dart` `setWindowBounds`; sanitize/clamp coverage pending `test/domain/models/window_bounds_test.dart` and fail-soft-read + persister-lifecycle coverage pending `test/features/window_chrome/window_chrome_test.dart`) + `[Coverage: MANUAL]` for the resize→save→reload loop / survive-hard-kill / multi-monitor off-screen recovery / maximized round-trip per §22.9.3a
- [ ] **Resizing with a file open never resets the tab (regression)** — the live geometry write is an *incremental* workspace edit (`crux.WorkspaceNotifier.mutate`), never a document replacement (`replaceWith`): dragging/maximizing the window with a waveform open must not throw `ProviderScope was rebuilt with a different ProviderScope ancestor`, and cursor / zoom / group expansion / decoders must survive every resize in both single-pane and split-pane layouts — `[Coverage: AUTOMATED]` (`test/features/workspace/providers/window_bounds_scope_preservation_test.dart`) + `[Coverage: MANUAL]` for the on-screen drag/maximize sweep per §22.9.3a
- [x] Per-tab session sidecar (`{appSupportDir}/sessions/{tabId}.json`) written on lifecycle paused/detached for each tab so cursors, signal arrangement, zoom, markers, Stage workspace, translate filters, panel visibility survive a restart — `[Coverage: MANUAL]` (interactive: open file, place primary cursor, zoom in, add a signal group, quit, relaunch, confirm state restores); sidecar helpers exercised by `test/features/workspace/providers/workspace_provider_test.dart`
- [x] Active pane and active tab focus restored on launch (no "nothing focused" state after relaunch); falls back to first tab in the active pane when the persisted active tab was dropped — `[Coverage: MANUAL]` (interactive: relaunch and confirm pane border + tab chip both show focus)
- [x] Closing a tab deletes its session sidecar so orphan files do not accumulate under `{appSupportDir}/sessions/` — `[Coverage: MANUAL]` (no committed automated test asserts the orphan-cleanup; `TabListNotifier.closeTab` invokes `deleteSidecar` via the workspace-mirror chain)
- [ ] Workspace restored on launch — multiple tabs, active-tab pointer, cursor + zoom — `[Coverage: INTEGRATION_TEST — pending]` (`integration_test/workspace/restore_one_tab_test.dart`)
- [ ] Workspace restored on launch under split-pane (both panes) — `[Coverage: INTEGRATION_TEST — pending]` (`integration_test/workspace/restore_split_pane_test.dart`)
- [ ] Empty workspace restored on launch (no tabs were open at quit) — `[Coverage: INTEGRATION_TEST — pending]` (`integration_test/workspace/restore_empty_test.dart`)
- [x] Missing-file-on-restore: drops tab, snackbar listed, no crash — `[Coverage: AUTOMATED]` (`test/features/workspace/providers/workspace_provider_test.dart` — `'missing-file restoration drops the tab from the workspace'` covers the provider seam the lifecycle hook reads; end-to-end snackbar coverage remains pending the integration test at `integration_test/workspace/missing_file_test.dart`)
- [x] `last_session.json` one-shot migration on first launch — old file deleted, new workspace.json created — `[Coverage: AUTOMATED]` (`test/services/workspace/last_session_migration_test.dart`)
- [x] `Workspace` / `WorkspaceTab` / `WorkspacePane` model round-trip, schema versioning — `[Coverage: AUTOMATED]` (`test/services/workspace/wavecrux_workspace_codec_test.dart` — model round-trip incl. `paneId` + schema versioning; `PaneId` itself lives upstream in `crux_workspace`)
- [x] `workspaceProvider` round-trip + active-tab/active-pane providers — `[Coverage: AUTOMATED]` (`test/features/workspace/providers/workspace_provider_test.dart`)
- [x] `File → Reset Workspace` — single confirmation, empties workspace — `[Coverage: WIDGET]` (`test/features/workspace/commands/reset_workspace_command_test.dart` — cancel branch, confirm-then-empty, locale sweep across en/zh_CN/ja/ko)
- [x] `File → New Workspace` — saves current under a name, then resets — `[Coverage: WIDGET]` (`test/features/workspace/commands/new_workspace_command_test.dart` — cancel-picker branch, write-then-reset, save-error snackbar, locale sweep)
- [x] `File → Save Workspace As…` creates a `.wavecrux-workspace` file — `[Coverage: WIDGET]` (`test/features/workspace/commands/save_workspace_as_command_test.dart` — write success, working workspace preserved (no reset), failure-reason surfaced)
- [x] `File → Open Workspace…` loads a `.wavecrux-workspace` file into a new workspace — `[Coverage: WIDGET]` (`test/features/workspace/commands/open_workspace_command_test.dart` — replace flow, schema-version rejection, non-object root rejection, missing-file rejection; end-to-end navigation flow remains covered by manual sign-off until `integration_test/workspace/named_workspace_test.dart` lands)
- [x] `File → Export Tab as Session…` writes a `.wavecrux` file (one tab) — `[Coverage: WIDGET]` (`test/features/workspace/commands/export_tab_command_test.dart` — success + sessionFilePath stamping, unwritable-path failure, stale-tab tolerance)
- [x] Open `.wavecrux` opens as a new tab in current workspace — `[Coverage: AUTOMATED]` (covered by the multi-tab bullets — `TabListNotifier.openSession` always appends; see `test/features/tabs/providers/tab_providers_test.dart`; CLI dispatch covered by `test/services/cli/cli_args_test.dart`)
- [x] Recent workspaces list — `[Coverage: AUTOMATED + WIDGET]` (`test/features/workspace/providers/recent_workspaces_provider_test.dart` — persistence, MRU dedup, 10-cap, remove, clear; `test/features/workspace/widgets/wavecrux_empty_canvas_test.dart` — list rendering, tap dispatch, empty-state hint, null-callback fallback)
- [x] CLI `--workspace <path>` flag opens a named workspace at startup — `[Coverage: AUTOMATED]` (`test/services/cli/cli_args_test.dart` — flag parsing, bare positional `.wavecrux-workspace` routing, case-insensitivity, trailing-flag guard; end-to-end startup hydration remains covered by manual sign-off until `integration_test/workspace/cli_workspace_test.dart` lands)
- [x] CLI `--help` prints usage and lists every flag — `[Coverage: AUTOMATED]` (`test/services/cli/cli_args_test.dart` — `cliHelpText` mentions every supported flag and the auto-routed extensions)
- [x] `Tools → Generate Test VCD…` shows destination picker; "Generate & Open in New Tab" / "Generate & Reveal" / Close — `[Coverage: WIDGET]` (`test/features/tools/widgets/generate_test_vcd_dialog_test.dart` — locale sweep en/zh_CN/ja/ko, all controls render, buttons disabled until destination chosen, choosing destination enables them, write+append-tab flow, write+reveal flow, Close dismisses, touch-target ≥ 36 dp)
- [x] Generator no longer appears inside the diagnostics dialog (moved to Tools → Generate Test VCD) — `[Coverage: MANUAL]` (no committed test asserts the generator's absence from the diagnostics surface; the App Diagnostics dialog now renders only Memory + Frame Stats per `test/features/diagnostics/widgets/app_diagnostics_dialog_test.dart`)
- [ ] CLI `wavecrux a.fst b.vcd` appends both files to the active pane of the workspace — `[Coverage: INTEGRATION_TEST — pending]` (extend `integration_test/tabs/cli_multi_file_test.dart`)
- [x] `PaneHost` widget hosts one or two panes; pane focus indicator visible — `[Coverage: WIDGET]` (`test/features/panes/widgets/wavecrux_pane_host_test.dart` — pane-host render + focus border; single-pane / after-split rendering in `test/features/viewer/screens/viewer_screen_test.dart`)
- [x] `View → Split Pane Right` (`Cmd+\`) creates a second pane and moves active tab — `[Coverage: UNIT]` (`test/features/panes/providers/active_pane_id_provider_test.dart` — `'updates when splitPane creates a second pane and focuses it'`)
- [x] `View → Close Pane` (`Cmd+K W`) merges tabs back into surviving pane — `[Coverage: WIDGET]` (`test/features/panes/providers/active_pane_id_provider_test.dart` — `'closePane merges tabs and falls back to the surviving pane'`)
- [x] Closing last tab in non-active pane auto-collapses to single pane — `[Coverage: WIDGET]` (`test/features/workspace/providers/workspace_provider_test.dart` — `WorkspaceNotifier.removeTab` drops the empty non-active pane; behavioral coverage via the same pane_host_test scenarios)
- [x] Drag-tab between panes updates `WorkspaceTab.paneId` — `[Coverage: UNIT]` (`test/features/workspace/providers/workspace_provider_test.dart` — `moveTabToPane` reassigns `paneId`)
- [x] Dragging a tab between panes does NOT crash semantics — the per-tab waveform `RepaintBoundary` `GlobalKey` is scoped per **(host pane, tab)** so the canvas rebuilds in the target pane instead of migrating the live element across two `IndexedStack`s (which tripped the `identical(childRenderObject, parentRenderObject)` flushSemantics assertion + null-check crash, most visible on Linux). Same scoping fixes a latent "Multiple widgets used the same GlobalKey" when a `PaneId.primary`-sentinel tab is hosted by two panes — `[Coverage: WIDGET]` (`test/features/viewer/screens/viewer_screen_test.dart` — `'dragging a tab between panes does not crash semantics (cross-pane reparent)'` (fails pre-fix), `'moving a tab between two non-primary panes does not crash semantics'`) + `[Coverage: MANUAL]` (the framework `identical(...)` assertion needs the desktop binding — drag a tab between two panes with the console open, expect no exception)
- [x] Moving a tab that was created before workspace hydration (carries the `PaneId.primary` sentinel and was never mirrored into the document — e.g. the web cold-start race, Issue 22) into a split pane records it in the destination AND drops the stranded empty original pane (no dangling empty pane in the document) — `[Coverage: UNIT]` (`test/features/workspace/providers/workspace_provider_test.dart` — the boot-race / stranded-empty-pane collapse on load; end-to-end in `integration_test/workspace/empty_pane_no_persist_test.dart`)
- [x] No-empty-sibling-pane invariant across the full persistence path (load + flush) — `_flushWorkspace` drops empty panes from the snapshot when at least one populated pane survives; `WaveCruxWorkspaceNotifier.build()` applies the same sanitization on load so a legacy workspace.json that already encodes a stranded empty pane self-heals on cold start. Closes the user-reported "two panes visible with no UI to close the empty one" regression — `[Coverage: WIDGET]` (`test/features/workspace/providers/workspace_provider_test.dart` — `'build sanitizes a loaded workspace by dropping empty sibling panes'` and `'build keeps exactly one pane (no tabs) when the loaded workspace has multiple empty panes'`) + `[Coverage: INTEGRATION_TEST]` (`integration_test/workspace/empty_pane_no_persist_test.dart` — boot with a stranded pane in workspace.json, close-last-tab + immediate flush; asserts persisted document never carries an empty sibling)
- [x] Split-pane device gating: hidden on phone, hidden on tablet width < 1000 dp — `[Coverage: MANUAL]` (no committed automated test exercises the phone / narrow-tablet split-pane device gate; verified visually)
- [ ] File→Open / command palette actions target the active pane — `[Coverage: WIDGET — pending]`
- [ ] WCP `wcp.load`, `set_cursor`, etc. target the active pane's active tab — `[Coverage: MANUAL]`
- [x] WCP `wavecrux.setActiveTab` extension accepts optional `paneId` — `[Coverage: WIDGET]` (`test/services/remote/remote_control_notifier_test.dart` — `RemoteControlNotifier — wavecrux.setActiveTab` group: greeting announcement, activation with/without `pane_id`, error code 6 for unknown tab, error code 6 when tab is not hosted by named pane, error code 3 for missing/invalid `tab_id` / `pane_id`)
- [x] Live statistics strip: app-level segments (memory, FPS) continuous across pane focus — `[Coverage: WIDGET]` (`test/features/statistics/widgets/live_statistics_strip_test.dart` — `'memory and FPS segments stay continuous across pane focus changes'`)
- [x] Live statistics strip: per-pane segments (paint time, render time) swap with active pane; per-pane history retained — `[Coverage: WIDGET]` (`test/features/statistics/widgets/live_statistics_strip_test.dart` — `'reads paint time from the active pane container'` + `'swaps paint-time sparkline content when active pane changes'` + `'omits pane indicator when only one pane exists'`)
- [x] Live statistics strip: zero cross-pane sparkline contamination — pulsing the root-scope `renderStatsCollectorProvider` must NOT feed the root `paneRenderStatsProvider`, so per-pane sparkline buffers can never be polluted by samples that bypassed the per-pane override. Pre-fix (Issue 31), a dead root-scope `onPaint` bridge mixed any pulse into the root notifier — the bridge has been removed and the only collector→notifier path lives in `PaneContainerManager._attachBridge` — `[Coverage: WIDGET]` (`test/features/diagnostics/providers/render_pipeline_stats_provider_test.dart` — `'pulsing the root collector does NOT feed root paneRenderStatsProvider'`)
- [x] Telemetry events `workspace.restored`, `workspace.created`, `workspace.reset`, `workspace.named.saved`, `workspace.named.opened`, `pane.split`, `pane.closed`, `tab.dragged_to_pane`, `tab.exported` emitted — `[Coverage: AUTOMATED]` (`test/services/telemetry/workspace_events_test.dart` covers the WorkspaceNotifier emissions; `workspace.named.saved` + `tab.exported` covered by `test/features/workspace/commands/save_workspace_as_command_test.dart` and `test/features/workspace/commands/export_tab_command_test.dart` flows respectively; default `NoopTelemetryService` keeps open-core builds inert)
- [x] Phone: workspace restoration honors single-tab fallback (most-recent active tab restored; other tabs offered under "Other tabs from your last session") — `[Coverage: AUTOMATED + WIDGET]` (`test/features/workspace/workspace_restore_strategy_test.dart` — pure-function decision branches for phone, phone-landscape, tablet, desktop, edge cases; `test/features/workspace/widgets/wavecrux_empty_canvas_test.dart` — phone surfaces the section with rows, hides when empty, hidden on tablet/desktop, tap dispatches to `onOpenOtherTab`; `test/features/workspace/providers/other_tabs_from_last_session_provider_test.dart` covers the parking provider)
- [x] ARB sweep partial: `welcomeTitle`, `welcomeAppName`, `welcomeAppVersion`, `welcomeTagline`, `welcomeOpenFile`, `welcomeRecentFiles`, `welcomeRemoveRecentFile`, `welcomeUseBackupParser*` strings removed in en/zh_CN/zh/ja/ko; `emptyCanvas*` strings added (`emptyCanvasTitle`, `emptyCanvasSubtitle`, `emptyCanvasOpenFile`, `emptyCanvasOpenWorkspace`, `emptyCanvasNewTab`, `emptyCanvasRecentFiles`, `emptyCanvasNoRecentFiles`, `emptyCanvasRecentWorkspaces`, `emptyCanvasNoRecentWorkspaces`, `emptyCanvasRemoveRecentFile`, `emptyCanvasDocsHint`); `diagnosticsTabGenerator`, `diagnosticsSignalCount`, `diagnosticsDuration`, `diagnosticsIncludeAnalog`, `diagnosticsIncludeXz`, `diagnosticsSeed`, `diagnosticsGenerateAndOpen` removed in all five ARB files; `toolsGenerateTestVcd*` strings added (`toolsGenerateTestVcdTitle`, `…SignalCount`, `…Duration`, `…IncludeAnalog`, `…IncludeXz`, `…Seed`, `…DestinationLabel`, `…ChooseDestination`, `…NoDestination`, `…GenerateAndOpen`, `…GenerateAndReveal`, `…Close`, `…SavePickerTitle`, `…GenerateError`) plus `shortcutActionGenerateTestVcd`; the split-pane work adds `shortcutActionSplitPaneRight`, `shortcutActionClosePane`, `shortcutActionFocusOtherPane`, `shortcutActionMoveTabToOtherPane`, `dragTabToPaneDropHint`; the phone single-tab fallback adds `emptyCanvasOtherTabsFromLastSession` across all five ARB files. `lastSession*`, `workspace*`, `resetWorkspace*` additions complete; remaining ARB additions land with their features — `[Coverage: STATIC]` (grep guard)
- [x] `lib/features/welcome/` directory removed entirely — `[Coverage: STATIC]` (grep guard)
- [ ] `WavecruxTab.kind` field removed; only `waveform` semantics remain — `[Coverage: AUTOMATED]` (compile-time guarantee)
- [x] `WavecruxTab.isDirty` field removed; auto-save retired the user-visible "unsaved changes" concept — `[Coverage: AUTOMATED]` (compile-time guarantee — no `isDirty` field on the model)
- [x] Session per-tab extension payload seam (`extraSessionPayloadCodecsProvider` + reserved `extensions` map) — unknown-namespace preserve-unknown round-trip, codec capture/restore via `ProviderContainer`, lenient read of `version > _kCurrentVersion`, and v1 read-back all pass; `.wavecrux` schema bumped to v2 — `[Coverage: AUTOMATED]` (`test/services/session/session_extensions_round_trip_test.dart`, `test/services/session/session_extensions_codec_test.dart`); cross-tier-open / live-autosave preserve-unknown remain `[Coverage: MANUAL]` per VERIFICATION_GUIDE.md §22.9.14
- [x] Extension-codec seam is wired into the **live `SessionNotifier._snapshot` / `_restore`** path (capture overlays codecs onto the preserve-unknown base; restore replays after the waveform source is ready) — previously the codecs were exercised only via the standalone `SessionExtensions` helper — `[Coverage: AUTOMATED]` (`test/features/viewer/providers/session_providers_test.dart` — "session-extension codec wiring" group)
- [x] Protocol decoder persistence — `SessionState.decoders` round-trips through `SessionService`; restore re-adds each decoder with its `instanceNumber` ("SPI #2" stays "SPI #2") and runs `decodeAll()` against the freshly-opened source; unknown decoderId (Pro decoder on Open Core, uninstalled plugin) skipped silently with a single `debugPrint`; `openFile` grew `preserveDecoders:` so the active-decoders provider never observes a transient `[]` during restore — `[Coverage: AUTOMATED]` (`test/services/session/session_decoder_{round_trip,backward_read,unknown_id}_test.dart`, `test/domain/models/{decoder_config,persisted_decoder}_test.dart`) + `[Coverage: INTEGRATION_TEST]` (`integration_test/decoders/decoder_restore_on_open_test.dart` — boots SPI+I²C fixture, snapshots, restores, asserts no flicker via `container.listen`); cross-tier-open Pro half + auto-reload preserve-decoders remain `[Coverage: MANUAL]` per VERIFICATION_GUIDE.md §22.9.14

---

## 12.6 Diagnostics Restructuring (Open Core — §22.10)

> The seven-tab `DiagnosticsDialog` is retired and split into three surfaces. Bullet groups in §1 (Diagnostics panel — verify first) and the surrounding diagnostics references in earlier sections are superseded by the surfaces below.

- [ ] Tab Diagnostics drawer opens from tab context menu, command palette, and keyboard shortcut (Cmd/Ctrl+Shift+I) — `[Coverage: WIDGET]` (`test/features/diagnostics/widgets/tab_diagnostics_drawer_test.dart`)
- [ ] Drawer shows three sections: File Info, Signal Health, Benchmark This File — `[Coverage: WIDGET]` (same file)
- [ ] File Info: every metric value (Format, Total Signals, Transitions, File Size with unit, Parse Time with unit) renders inside the drawer with no right-edge clipping; the entire panel scrolls vertically as one (legacy per-section 320-dp fold removed). The "Signals by Direction" section is reachable by scrolling past "Signals by Type". Pre-fix (Issues 32/33), the panels were pinned to 720 dp inside a horizontal scroll view and hid both the value column and the by-direction section — `[Coverage: WIDGET]` (`File Info section reachability` group in `tab_diagnostics_drawer_test.dart`)
- [ ] File Info → File Path row supports the §3.1.8.14 truncated-text reveal: desktop hover tooltip surfaces the full path; right-click / long-press opens a `PlatformContextMenu` whose first item is the non-interactive monospace full-path header and whose second item ("Copy File Path") copies the absolute path to the clipboard and shows the "Copied path to clipboard" snackbar (Issue 23) — `[Coverage: MANUAL]`
- [ ] Tab Diagnostics drawer is non-modal at the pointer-event level: with the drawer open, the tab close (×) button and every other chrome surface (toolbar, status bar, signal list) outside the drawer's right-aligned Material region remain interactive. Pre-fix, the dialog's `ModalBarrier` captured every event outside the drawer (Issue 24) — `[Coverage: WIDGET]` (`tab_diagnostics_drawer_test.dart` `pointer events outside the drawer reach underlying widgets (Issue 24)`)
- [ ] Drawer follows active tab on tab switch — `[Coverage: WIDGET]` (same file)
- [ ] Drawer auto-dismisses when its target tab closes — `[Coverage: WIDGET]` (same file)
- [ ] "Copy Tab Diagnostics Report" emits structured plain text including tab identification — `[Coverage: WIDGET]` (clipboard write captured in widget test)
- [ ] App Diagnostics dialog opens from `Tools → App Diagnostics…`, palette, keyboard shortcut (Cmd/Ctrl+Shift+M) — `[Coverage: WIDGET]` (`test/features/diagnostics/widgets/app_diagnostics_dialog_test.dart`)
- [ ] App Diagnostics dialog shows Memory + Frame Stats sections only (no per-tab content) — `[Coverage: WIDGET]` (same file)
- [ ] Memory section: per-tab breakdown table with wellen DB and decompressed signal counts — `[Coverage: WIDGET]` (same file)
- [ ] "Copy Full Diagnostics Report" aggregates app + active pane + per-tab data — `[Coverage: WIDGET]` (clipboard write captured in widget test)
- [ ] Logs section: live-updating ring-buffer view with level filter (Quiet/Normal/Detailed/Verbose), Copy, and Clear; colour-coded newest-first lines — `[Coverage: WIDGET]` (`test/features/diagnostics/widgets/logs_panel_test.dart`); `[Coverage: MANUAL]` (§3.3.4a live update)
- [ ] Settings → Diagnostics → Log Verbosity dropdown (default Normal) drives the console threshold + Logs default filter, persists across restart, and does NOT change what bug reports capture — `[Coverage: UNIT]` (`settings_service_test.dart`, `settings_providers_test.dart`, `log_console_sink_test.dart`, `log_verbosity_level_test.dart`); `[Coverage: MANUAL]` (§3.3.4a steps 6–7)
- [ ] Pane Render Stats popover anchored to `i`-icon in each pane's tab bar — `[Coverage: WIDGET]` (`test/features/diagnostics/widgets/pane_render_stats_popover_test.dart`)
- [ ] Pane Render Stats popover reports the **actual** canvas pixel dimensions when the canvas is in its empty-state placeholder (no signals loaded). Pre-fix the popover reported `0×0 px` because the empty-state branch passed `Size.zero` to the stats collector (Issue 26) — `[Coverage: WIDGET]` (`stats report the actual canvas size for empty lanes (Issue 26)` in `test/features/viewer/rendering/waveform_canvas_render_object_test.dart`)
- [ ] Two simultaneous popovers under split-pane stay isolated to their pane — `[Coverage: WIDGET]` (same file) and `[Coverage: INTEGRATION_TEST — pending]` (`integration_test/diagnostics/pane_popover_isolation_test.dart`)
- [ ] Tapping pane B's `i`-icon while pane A's popover is open opens B's popover on the first tap AND leaves A's popover visible alongside it; each popover dismisses via its own `×` button (or Escape) — pre-fix `showMenu`'s modal barrier dismissed A and ate the click on B (Issue 27) — `[Coverage: WIDGET]` (`two panes show their own distinct stats` and `tapping pane B's anchor while pane A's popover is open opens B without an extra click` in `pane_render_stats_popover_test.dart`)
- [ ] Active-pane switch does not move popover contents between panes — `[Coverage: INTEGRATION_TEST — pending]` (same)
- [ ] `diagnosticsEnabledProvider` (renamed from `diagnosticsAvailableProvider`) gates all three surfaces uniformly — `[Coverage: WIDGET]` (existing provider tests renamed in place)
- [ ] When `diagnosticsEnabledProvider = false` in release build: `i`-icon hidden on pane tab bars; menu entries absent; palette entries absent — `[Coverage: WIDGET]` (`hidden when diagnosticsEnabledProvider = false` cases in widget tests)
- [ ] Legacy `DiagnosticsScreen` and `_DiagnosticsDialog` widgets deleted — `[Coverage: STATIC]` (`test/static/no_legacy_diagnostics_test.dart`)
- [ ] ARB sweep: legacy `diagnosticsTab*`, `diagnosticsTitle`, `diagnosticsCopyReport*`, `shortcutActionOpenDiagnostics` strings removed across en/zh_CN/zh/ja/ko; `tabDiagnostics*`, `appDiagnostics*`, `paneRenderStats*` added — `[Coverage: STATIC]` (grep guard in `test/static/no_legacy_diagnostics_test.dart`)
- [ ] Locale sweep: all three surfaces render with no overflow at phone (400 dp — hidden), tablet (800 dp), desktop (1400 dp) — `[Coverage: WIDGET]` (per-surface widget tests' locale sweep)

---

## 12.7 Web WASM Parsing (Open Core — §22.11)

> The `wellen` Rust crate ships as a WebAssembly module so the Flutter Web build decodes VCD/FST/GHW with the same parser as desktop/mobile. The pure-Dart VCD parser is retired and wellen-WASM is the only web backend; a WASM load failure surfaces a "WebAssembly is required" guidance UI instead of silently falling back.

- [ ] `dart run tool/build_web_wasm.dart` rebuilds + copies + bundle-size gate passes locally — `[Coverage: STATIC]` (manual developer step; CI runs the same script in the `wasm` job)
- [ ] `web/wasm/wellen_wasm_bg.wasm` is committed and gzipped size ≤ 1.5 MB — `[Coverage: AUTOMATED]` (`test/native/wellen_wasm_bundle_size_test.dart`)
- [ ] `web/wasm/wellen_wasm.js` and `web/wasm/wellen_wasm_loader.js` are committed alongside the binary — `[Coverage: AUTOMATED]` (`test/native/wellen_wasm_bundle_size_test.dart`)
- [ ] `web/index.html` includes the loader script as `<script type="module" src="wasm/wellen_wasm_loader.js">` — `[Coverage: MANUAL]` (visual check; regression would manifest as runtime missing-loader error)
- [ ] CI `wasm` job builds the crate, gates bundle size, and uploads `wellen-wasm-pkg` for the `build-web` job — `[Coverage: AUTOMATED]` (`.github/workflows/ci.yml`)
- [ ] Web build: `flutter build web --release` succeeds end-to-end with the wasm artifact in place — `[Coverage: AUTOMATED]` (`build-web` job in `ci.yml`)
- [ ] Web file picker accepts `.vcd`, `.fst`, `.ghw` (not just `.vcd`) — `[Coverage: AUTOMATED]` (`test/services/waveform/web_file_loader_test.dart`)
- [ ] `WebFileLoader.fileSizeWarningThresholdBytes` raised to 100 MB (was 50 MB) — `[Coverage: AUTOMATED]` (same file)
- [ ] `WellenWasmProvider` stub semantics on non-web hosts — `[Coverage: AUTOMATED]` (`test/services/waveform/wellen_wasm_provider_stub_test.dart`)
- [ ] `wellen_wasm` Rust unit tests pass: format detection by extension, magic bytes, timescale-unit-exp mapping, ABI version constant — `[Coverage: AUTOMATED]` (`cargo test` in `native/wellen_wasm/`; runs in CI `wasm` job)
- [ ] Open VCD on web → uses `WellenWasmProvider` (the only web backend) — `[Coverage: MANUAL]`
- [ ] Open FST on web → opens successfully (new capability) — `[Coverage: MANUAL]`
- [ ] Open GHW on web → opens successfully (new capability) — `[Coverage: MANUAL]`
- [ ] Cross-bridge equivalence (FFI vs WASM): every VCD/FST/GHW fixture returns identical values across both providers — `[Coverage: INTEGRATION_TEST — pending]` (`integration_test/web/wellen_wasm_open_and_query_test.dart` and the Chrome-headless FFI-vs-WASM cross-bridge test tracked in `integration_test/PENDING.md`)
- [ ] **WebAssembly required error path** (replacement for the old fallback path): delete the .wasm asset → opening any waveform raises `WebAssemblyRequiredError` and the canvas centre shows the "WebAssembly is required" guidance UI (no Retry button) — `[Coverage: WIDGET]` (`test/features/viewer/widgets/waveform_view_center_test.dart` covers the UI; `[Coverage: MANUAL]` for the live `flutter run -d chrome` repro)
- [ ] Static grep guard: no `DartVcdProvider` / `WaveformProviderMode` / `ParserComparison*` references in `lib/` — `[Coverage: STATIC]` (`test/static/no_dart_vcd_parser_test.dart`)
- [ ] FSDB on web rejected at picker (only vcd/fst/ghw allowed) — `[Coverage: MANUAL]`
- [ ] No COOP/COEP HTTP headers required to run the wasm (single-threaded build) — `[Coverage: MANUAL]` (verify in DevTools network panel)
- [ ] No memory leaks across repeated open/close cycles on web — `[Coverage: MANUAL]` (watch App Diagnostics → Memory)

---

## 12.8 CXP server + cross-probe panel (Open Core — §22.12)

- [ ] Server starts at launch when `cxpServerEnabled = true` (default); status row in Settings → Remote Control reads "Running on port 54322" — `[Coverage: MANUAL]` (`[Coverage: UNIT]` lifecycle in `test/services/remote/cxp/wavecrux_cxp_server_test.dart`)
- [ ] Manifest `wavecrux-<pid>-<startedAt>.json` exists in the **suite-shared** directory (`~/Library/Application Support/crux/cxp/peers/` on macOS — NOT the per-app container) while the server runs and disappears on toggle off — `[Coverage: MANUAL]` (`[Coverage: UNIT]` in `wavecrux_cxp_server_test.dart`; shared-dir resolution `crux_cxp` `peer_connectivity_test.dart`)
- [ ] CXP port change in Settings → Remote Control restarts the server on the new port — `[Coverage: MANUAL]` (lifecycle bridge covered by `[Coverage: INTEGRATION_TEST]` in `cxp_integration_test.dart`)
- [ ] Editor command field accepts shell strings (e.g. `code -g`, `subl`, `nvr --remote-silent`); empty disables open-source — `[Coverage: UNIT]` (`test/services/remote/cxp/cxp_inbound_handlers_test.dart`)
- [ ] Cross-probe panel opens via command palette → `Show Cross-Probe Panel` — `[Coverage: UNIT]` (`test/features/remote/widgets/cross_probe_panel_test.dart` covers the widget; `[Coverage: MANUAL]` for the palette dispatch)
- [ ] Cross-probe panel shows offline banner when CXP server is stopped — `[Coverage: UNIT]` (`cross_probe_panel_test.dart`)
- [ ] Peer manifest written by a sibling app appears in the **Connected Peers** section within ~3 s — `[Coverage: UNIT]` (`wavecrux_cxp_server_test.dart` discovery group)
- [ ] **Cross-product discovery + connection (beta W2/S1, §22.12.2b):** WaveCrux + a second post-fix suite app on one machine mutually list each other as connected peers within ~5 s; rows persist past 5 minutes (manifest heartbeat); own manifest never listed as a peer; panel shows the shared **discovery directory** line — `[Coverage: UNIT]` (`crux_cxp` `peer_connectivity_test.dart` two-server mutual connect + heartbeat; `wavecrux_cxp_server_test.dart` "peer connector" group + self-filter) + real two-app flow `[Coverage: MANUAL]`
- [ ] **Real traffic over a connector-dialed link, not just presence (§22.12.2, 2026-07-20 fix):** with two suite apps connected, drive one actual cross-probe action and confirm the ack — a peer list that looks healthy does NOT imply working traffic; the two fail independently — `[Coverage: UNIT]` (`wavecrux_cxp_server_test.dart` "peer connector" group, e2e product-traffic case) + real two-app action `[Coverage: MANUAL]`
- [ ] **Unreachable-peer indicator (§22.12.2c, one-way connectivity):** a manifest pointing at a closed port raises a persistent **Unreachable peers** section (warning icon + "Couldn't reach `<peer>`" + host:port); the section is absent when every peer is reachable; a peer we cannot dial but that dialed us appears in BOTH Connected Peers and Unreachable peers — `[Coverage: UNIT]` (`wavecrux_cxp_server_test.dart` "dial failures (unreachable peer)" group; `cross_probe_panel_test.dart` indicator present/absent + locale sweep) + `[Coverage: INTEGRATION_TEST]` (`cxp_integration_test.dart` "surfaces connector dial failures into cxpDialFailuresProvider") + real two-app one-way case `[Coverage: MANUAL]`. Not tier-gated; beta behavior identical to post-beta.
- [ ] `notify_selection` broadcast on signal click reaches a subscribed peer with `ElementKind.signal` and the canonical path — `[Coverage: UNIT]` (`cxp_selection_emitter_test.dart`)
- [ ] Cursor moves broadcast a debounced `notify_selection` carrying `metadata.wavecrux.cursor_time_fs` — `[Coverage: UNIT]` (`cxp_selection_emitter_test.dart`)
- [ ] Marker create broadcasts `notify_selection` with `ElementKind.marker` — `[Coverage: UNIT]` (`cxp_selection_emitter_test.dart`)
- [ ] Inbound `request_highlight` for a signal adds it to the viewer and focuses it; ack returns `honored: true` — `[Coverage: INTEGRATION_TEST]` (`cxp_integration_test.dart`)
- [ ] Inbound `request_highlight` for a scope adds every variable beneath it — `[Coverage: UNIT]` (`cxp_inbound_handlers_test.dart`)
- [ ] Inbound `request_highlight` for a marker moves the primary cursor — `[Coverage: UNIT]` (`cxp_inbound_handlers_test.dart`)
- [ ] Inbound `request_open_source` shells to the configured editor command with `file:line:column` target — `[Coverage: INTEGRATION_TEST]` (`cxp_integration_test.dart`)
- [ ] Inbound `request_open_source` with empty editor command replies `honored: false, reason: "no editor command configured"` — `[Coverage: UNIT]` (`cxp_inbound_handlers_test.dart`)
- [ ] Event log records both inbound and outbound traffic with direction arrows — `[Coverage: INTEGRATION_TEST]` (`cxp_integration_test.dart`)
- [ ] WaveCruxNameResolver round-trips every native ElementKind (signal slices preserved, escape prefix preserved, marker a–z, file:line:column) — `[Coverage: UNIT]` (`wavecrux_name_resolver_test.dart`)
- [ ] `ElementKind` is an **open** wire type (2026-07 crux-shared round): an element kind this build has never heard of — sent by a newer peer — is **ignored gracefully** everywhere (name resolver returns `null`; `request_highlight` replies `honored: false`), never throwing or guessing it is signal-like — `[Coverage: UNIT]` (`wavecrux_name_resolver_test.dart` "unknown element kinds" group + `cxp_inbound_handlers_test.dart` "a kind this build has never heard of is ignored gracefully")
- [ ] Locale sweep (en/zh_CN/ja/ko) on the cross-probe panel and the CXP Settings sub-section — `[Coverage: UNIT]` (`cross_probe_panel_test.dart` locale sweep; `[Coverage: MANUAL]` for the Settings sub-section sweep)
- [ ] crux_cxp conformance suite passes (`cd wavecrux/crux-shared && melos run test`) — exercises `LocalCxpServer` which `WaveCruxCxpServer` wraps — `[Coverage: UNIT]` (package-level)

---

## 12.9 LXT / LXT2 Legacy Format Support (Open Core — §22.13)

- [ ] **Happy-path open: small LXT2 file** — `simple_counter.lxt2` opens; hierarchy + signal values match `simple_counter.expected.json`; a sibling `simple_counter.fst` + `.lxt2cache.json` are written next to the source — `[Coverage: UNIT]` (`waveform_source_provider_lxt2_test.dart` + `lxt2fst_bridge_equivalence_test.dart`); `[Coverage: MANUAL]` (end-to-end file-picker flow)
- [ ] **Cache hit on second open is instant** — closing and reopening the same `.lxt2` skips the converter (no progress dialog), legacy banner is suppressed on the cache hit — `[Coverage: UNIT]` (`lxt2fst_cache_test.dart` fresh-hit case); `[Coverage: MANUAL]` (UI feel)
- [ ] **App-cache fallback path** — copy fixture into a read-only directory; conversion succeeds; `.fst` lands under `${appCacheDir}/legacy_conversions/<sha256>.fst` with sidecar — `[Coverage: UNIT]` (`lxt2fst_cache_test.dart` read-only sibling case); `[Coverage: MANUAL]` (real-FS check)
- [ ] **Large-file progress dialog** — open a regenerated `~50 MB` `large_sample.lxt2` (`dart run tool/regenerate_legacy_fixtures.dart --large`); modal progress dialog shows title (`lxt2ConversionTitle`), status (`lxt2ConversionStatus`), filename (`lxt2ConversionFile`); progress bar moves monotonically driven by `(blocks_done, total_blocks)` — `[Coverage: MANUAL]` (`[Coverage: UNIT]` for monotonic progress emission in `legacy_conversion_controller_test.dart`)
- [ ] **Cancel mid-conversion** — pressing Cancel terminates the converter, dismisses the dialog, leaves no partial `.fst` or `.lxt2cache.json` on disk; viewer returns to previous state — `[Coverage: UNIT]` (`legacy_conversion_controller_test.dart` cancel path); `[Coverage: MANUAL]` (UI dismissal)
- [ ] **Legacy banner: first-open visibility** — banner appears above waveform with localized `legacyFormatBannerMessage`, both placeholders interpolated; "Don't show again" + "Dismiss" actions render — `[Coverage: UNIT]` (`test/widgets/legacy_format_banner_test.dart`)
- [ ] **Legacy banner: Don't-show-again persists** — tapping "Don't show again" flips `AppSettings.suppressLegacyFormatBanner` and suppresses future first-open banners — `[Coverage: UNIT]` (`legacy_format_banner_test.dart` + `settings_service_test.dart`)
- [ ] **Diagnostics → File Info "Original format" row** — visible for LXT2 origins with `diagnosticsFileInfoOriginalFormatValue` formatting; hidden for non-legacy files — `[Coverage: UNIT]` (`file_info_panel_test.dart` Original Format row group)
- [ ] **Locale sweep on dialog + banner + File Info row** — en/zh_CN/ja/ko render `lxt2ConversionTitle`/`lxt2ConversionStatus`/`lxt2ConversionFile`/`legacyFormatBannerMessage`/`legacyFormatBannerDontShowAgain`/`legacyFormatBannerDismiss`/`diagnosticsFileInfoOriginalFormat`/`diagnosticsFileInfoOriginalFormatValue` cleanly with no overflow — `[Coverage: UNIT]` (locale sweeps in `legacy_conversion_progress_dialog_test.dart` + `legacy_format_banner_test.dart` + `file_info_panel_test.dart`)
- [ ] **LXT2 full value decode** — opening `simple_counter.lxt2` / `multi_scope.lxt2` / `vector_signals.lxt2` shows the **real** transitions on the canvas (counter increments, ALU/regfile vectors, x/z buses, and real voltages/currents) — not just `x`. Values match `.expected.json` — `[Coverage: UNIT]` (`lxt2fst_bridge_equivalence_test.dart` valueAt timeline + `round_trip::*_value_equivalence`; continuously cross-checked vs GTKWave's `vcd2lxt2` by `tool/lxt2_value_fuzz.py`, hard invariant = never a wrong value)
- [ ] **LXT classic full open** — opening `simple_counter.lxt` converts successfully (no `Unsupported`, no crash); signal tree shows the `top` scope with `clk` + 8-bit `count` (names + geometry decoded), File Info "Original format" reads `LXT`, sibling `.fst` + `.lxt2cache.json` written; canvas shows the **real** transitions (`clk` toggles 0/1 every 10 ns, `count` increments `0x00..0x31`) — identical to the `.lxt2` waveform. LXT-classic's streaming value codec is now decoded by `lxt_value_decode` (clean-room, differentially fuzz-validated vs `vcd2lxt`, strict fallback to x-state on any unvalidated structure) — `[Coverage: UNIT]` (`native/lxt2fst/src/{lxt,lxt_value_decode}.rs` tests + `round_trip::lxt_classic_value_equivalence_post_decoder` + `lxt2fst_bridge_equivalence_test`; fuzzer `tool/lxt_classic_value_fuzz.py`)
- [ ] **Magic-byte detection** — `LegacyFormatDetector` classifies LXT / LXT2 / not-legacy from the first 2 bytes; renamed `.fst → .lxt2` falls through to wellen unchanged — `[Coverage: UNIT]` (`legacy_format_detector_test.dart`)
- [ ] **Stale-cache reconvert** — touching the source `.lxt2` after caching triggers reconversion on next open; size mismatch via sidecar triggers reconversion; missing sidecar treats cache as stale — `[Coverage: UNIT]` (`lxt2fst_cache_test.dart` stale cases)
- [ ] **WASM bundle stays under budget** — gzipped `lxt2fst_bg.wasm` ≤ 400 KiB — `[Coverage: STATIC]` (`test/native/lxt2fst_wasm_bundle_size_test.dart`)
- [ ] **Fixtures committed** — `test/fixtures/legacy/{simple_counter,multi_scope,vector_signals,string_values,large_sample}.{lxt,lxt2,vcd,expected.json}` under `test/fixtures/legacy/`; the verification suite shares them via direct reference (see `verification/fixtures/helpers/README.md`) — `[Coverage: STATIC]` (presence checked in `lxt2fst_bridge_equivalence_test.dart` setup)
- [ ] **Regenerator documented** — `dart run tool/regenerate_legacy_fixtures.dart` (and `--large` for the uncommitted 50 MB perf fixture) regenerates VCDs, ground-truth JSON, and shells to `vcd2lxt` / `vcd2lxt2`; entry in `verification/fixtures/helpers/README.md` — `[Coverage: MANUAL]` (dev-machine tool)

---

## 12.10 Translator Registry + Structured TranslationResult (Open Core — §22.14)

- [ ] **No visible change across all formats** — cycling a bus signal through every `DisplayFormat` renders identical digits / `X` / `Z` markers / enum labels to the pre-registry renderer (value column, in-lane bus label, RTL-source hover) — `[Coverage: UNIT]` (`translator_registry_test.dart` parity group); `[Coverage: MANUAL]` (on-screen sweep §22.14.1)
- [ ] **Stage bus-readout parity** — Bus Readout widget shows the same prefixed value + red `X`/`Z` styling as before — `[Coverage: UNIT]` (`bus_readout_stage_widget_test.dart`); `[Coverage: MANUAL]` (§22.14.2)
- [ ] **Built-in translator** — `text` delegates verbatim to `ValueFormatService`; `validity` derived from x/z; returns no `fields` — `[Coverage: UNIT]` (`builtin_value_translator_test.dart`)
- [ ] **Registry extension point** — built-in resolves with no overrides; overriding `extraTranslatorsProvider` adds a translator and an entry under `builtin.valueFormat` wins (the Stage 2 / Pro seam) — `[Coverage: UNIT]` (`translator_registry_test.dart`)
- [ ] **Structured-result models** — `TranslationResult` / `TranslatedField` equality, copyWith, defaults, deep field equality; `TranslationRequest` equality incl. config — `[Coverage: UNIT]` (`translation_result_test.dart`, `translated_field_test.dart`, `translator_test.dart`)
- [ ] **Domain stays Flutter-free** — color carried as `int? colorArgb`; no `dart:ui` / `package:flutter` import in `translation_result.dart` / `translated_field.dart` / `translator.dart` — `[Coverage: STATIC]` (analyze + import review)

## 12.11 Declarative Struct/Bitfield Translators + Child-Row UI (Open Core — §22.15)

- [ ] **Bitfield decode** — named subfields slice MSB-indexed `[hiBit:loBit]`, each formatted by the built-in formatter (incl. enum table + nested struct); summary `{name=val, …}` — `[Coverage: UNIT]` (`bitfield_translator_test.dart`)
- [ ] **Invalid/out-of-range specs** — all-invalid config falls back flat (no fields); an invalid field among valid ones renders `X` but keeps its child row — `[Coverage: UNIT]` (`bitfield_translator_test.dart`)
- [ ] **Web/desktop parity** — pure-Dart deterministic output, identical on VM and WASM — `[Coverage: UNIT]` (`bitfield_translator_test.dart` parity test)
- [ ] **RISC-V disassembly translator (Open Core, no tier gate)** — RV32I/RV64I + compressed decode inline; mnemonic + operand fields; unknown/x fallback — `[Coverage: UNIT]` (`riscv_disasm_translator_test.dart`)
- [ ] **Child-row alignment** — expanding a bitfield-bound signal reserves identical vertical space in value column, canvas, and signal-names list (subfields never drift from their wave); geometry inflation via `signalChildRowCounts` — `[Coverage: UNIT]` (`translator_expansion_provider_test.dart`); `[Coverage: MANUAL]` (§22.15.2)
- [ ] **Expand affordance** — ≥ 44×44 dp touch target; collapsed/expanded states; expansion state survives rebuild/orientation — `[Coverage: UNIT]` (`value_column_row_translator_test.dart`, `translator_expansion_provider_test.dart`)
- [ ] **Authoring + binding** — Settings → Custom Translators add/edit/rename/delete; value-column "Custom translator…" binds (custom or RISC-V); binding stored in `translatorConfig` and persists in the session — `[Coverage: UNIT]` (`custom_translators_panel_test.dart`, `custom_translator_editor_dialog_test.dart`, `bind_custom_translator_dialog_test.dart`); `[Coverage: MANUAL]` (§22.15.1, persistence)
- [ ] **Clear reverts format too (issue #41)** — value-column "Clear custom translator" resets the binding **and** the row's display format to default hex, so a non-default format set before binding doesn't leave a stale "translated-looking" value; targets only the matching row — `[Coverage: UNIT]` (`signal_group_providers_test.dart` "clearSignalTranslatorById"); `[Coverage: MANUAL]` (§22.15.2)
- [ ] **Lower signals not clipped on expand (issue #43)** — expanding a translator-bound signal's child rows reserves blank space that extends the canvas content height; signals below it (incl. last-row, last-in-group, and transaction-lane cases) stay painted instead of disappearing — `[Coverage: WIDGET]` (`waveform_canvas_test.dart` "issue #43"); `[Coverage: MANUAL]` (§22.15.2)
- [ ] **Registry** — `builtin.bitfield` seeded by default; `builtin.riscvDisasm` registered once its TOML assets load — `[Coverage: UNIT]` (`translator_registry_test.dart`)
- [ ] **Locale sweep** — child-row value column, Custom Translators panel, and editor dialog render exception-free in en/zh_CN/ja/ko — `[Coverage: UNIT]` (panel/dialog/value-row tests)

---

## 12.12 Beta Issue Reporter (Open Core — §22.16)

- [ ] **Entry points** — Help menu "Submit Issue", command palette, and About box "Report Issue" all open the same dialog; no tier badge (open to all tiers) — `[Coverage: UNIT]` (`action_surface_conformance_test.dart`); `[Coverage: MANUAL]` (§22.16)
- [ ] **Summary field label** — the title text field reads **Issue Summary** (not "Submit Issue") — `[Coverage: UNIT]` (`issue_reporter_dialog_test.dart`)
- [ ] **Category tiles** — App & Environment locked on; Session State / Diagnostics / Screenshot toggleable, all default on; Screenshot tile hidden on iOS/Android and web — `[Coverage: UNIT]` (`issue_reporter_dialog_test.dart`)
- [ ] **Diagnostics section never blank** — `## Diagnostics` always carries the Full Diagnostics Report snapshot (memory/frame/file/signal health) plus a **Session log** subsection; uncaught framework/async errors are captured into the log via `captureFlutterErrors()` (clean session → "(no errors or warnings logged this session)") — `[Coverage: UNIT]` (`issue_reporter_service_test.dart`, `issue_reporter_log_buffer_test.dart`); `[Coverage: MANUAL]` (§22.16 Diagnostics section)
- [ ] **Live preview + scroll** — expanding the preview and toggling a category adds/removes its `## <title>` section in lock-step; the dialog body scrolls via two-finger trackpad/touch drag (not only the wheel) with a visible Scrollbar — `[Coverage: UNIT]` (`issue_reporter_dialog_test.dart`); `[Coverage: MANUAL]` (§22.16 scroll)
- [ ] **Submit → close + URL + clipboard** — the dialog closes; browser opens GitHub new-issue URL with title + `bug,user-report,<platform>` labels; target repo is the fixed open-core slug `Ferrite-Engineering/wavecrux`, independent of `kBetaPeriod`; body is pre-filled into the URL when it fits the ~6 KB cap (pre-filled toast), otherwise dropped and pasted from the clipboard (paste toast); body always on the clipboard — `[Coverage: UNIT]` (`issue_reporter_service_test.dart`, `issue_reporter_dialog_test.dart`); `[Coverage: MANUAL]` (§22.16 golden path)
- [ ] **Screenshot path (desktop)** — PNG saved to OS temp dir and revealed in the file manager; excluded path writes nothing — `[Coverage: MANUAL]` (§22.16)
- [ ] **Log buffer** — 500-entry ring captures startup + runtime WARNING+ and recent any-level lines plus uncaught framework/async errors (`captureFlutterErrors`); fenced code block, timestamp dedup — `[Coverage: UNIT]` (`issue_reporter_log_buffer_test.dart`, `issue_reporter_service_test.dart`)
- [ ] **Privacy audit** — Session State body carries no file paths and no decoder config values — `[Coverage: UNIT]` (`issue_reporter_service_test.dart`); `[Coverage: MANUAL]` (§22.16 privacy audit)
- [ ] **Locale sweep** — dialog renders exception-free in en/zh_CN/ja/ko at phone/tablet/desktop widths — `[Coverage: UNIT]` (`issue_reporter_dialog_test.dart`)
- [ ] **Tier gate (post-beta)** — `kBetaPeriod = false` keeps the action available to every tier with no badge and no gate (`requiredTier: openCore`) — `[Coverage: UNIT]` (`action_surface_conformance_test.dart`); `[Coverage: MANUAL]` (§22.16.1)

---

## 12.13 Beta build expiry (Open Core — §22.17)

- [ ] **Active / never-expires** — `BETA_EXPIRY=20990101` (or no `--dart-define`) renders no banner and no modal — `[Coverage: UNIT]` (`beta_expiry_provider_test.dart`); `[Coverage: MANUAL]` (§22.17 active path)
- [ ] **Expiring-soon banner** — a date 1–7 days out shows the dismissible banner with a plural-correct day count and a Download action — `[Coverage: UNIT]` (`beta_expiry_banner_test.dart`, `beta_expiry_gate_test.dart`); `[Coverage: MANUAL]` (§22.17)
- [ ] **Banner dismiss + resume re-surface** — ✕ hides the banner for the session; resume re-evaluates and re-surfaces it — `[Coverage: UNIT]` (`beta_expiry_gate_test.dart` dismiss); `[Coverage: MANUAL → HYBRID]` (resume re-check, §22.17)
- [ ] **Expired blocking modal** — today/past date shows a non-dismissable modal over a dimmed, non-interactable viewer; back gesture blocked; Download latest build action — `[Coverage: UNIT]` (`beta_expiry_blocking_overlay_test.dart`, `beta_expiry_gate_test.dart`); `[Coverage: MANUAL]` (§22.17)
- [ ] **Quit from the expired modal** — the Quit WaveCrux button exits the app; verify specifically on Windows/Linux where the custom-chrome close button is blocked behind the modal barrier — `[Coverage: UNIT]` (`beta_expiry_gate_test.dart` `betaExpiryExitApp` seam); `[Coverage: MANUAL]` (process exit, §22.17 expired path step 5)
- [ ] **Download action** — banner and modal both open `https://wavecrux.app/download` — `[Coverage: UNIT]` (`beta_expiry_gate_test.dart`, injected launcher); `[Coverage: MANUAL]` (§22.17)
- [ ] **Boundaries** — exact-day = expired; 7 days out = banner, 8 days out = nothing — `[Coverage: UNIT]` (`beta_expiry_test.dart` day-before/exact/day-after)
- [ ] **Locale sweep** — banner + modal render exception-free in en/zh_CN/ja/ko — `[Coverage: UNIT]` (`beta_expiry_banner_test.dart`, `beta_expiry_blocking_overlay_test.dart`)
- [ ] **Post-beta no-op** — `kBetaPeriod = false` makes `kBetaExpiry` null, so no banner/modal for any tier regardless of `BETA_EXPIRY` — `[Coverage: UNIT]` (`beta_expiry_test.dart` notApplicable); `[Coverage: MANUAL]` (§22.17 no-op path)

---

## 12.14 AI Waveform Assistant — open-core seams (Open Core — §22.18)

- [ ] **Unconfigured model client** — default `aiModelClientProvider` is `NoopAiModelClient`; `isConfigured == false`; `send` yields one typed `notConfigured` event and completes without throwing — `[Coverage: UNIT]` (`test/services/ai/noop_ai_model_client_test.dart`, `test/core/providers/ai_model_client_provider_test.dart`)
- [ ] **Tool registry** — `aiToolRegistryProvider` exposes exactly the six viewer-navigation tools; `extraAiToolsProvider` appends; duplicate name trips the guard — `[Coverage: UNIT]` (`test/core/providers/ai_tool_registry_provider_test.dart`, `test/services/ai/ai_tool_registry_test.dart`)
- [ ] **Grounded tools** — `searchSignal` / `getTransitionsInWindow` / `listDecodedTransactions` / `jumpCursor` / `addMarker` return correct data against a loaded source; citations resolve to real coordinates — `[Coverage: UNIT]` (`test/services/ai/tools/viewer_navigation_tools_test.dart`)
- [ ] **`getSelectionContext` determinism + X-origin** — same selection + window → identical payload; folds in transitions, overlapping transactions, and a grounded X-origin trace — `[Coverage: UNIT]` (`test/services/ai/tools/viewer_navigation_tools_test.dart`)
- [ ] **No-waveform safety** — each data tool returns a typed `AiToolResult.failure` (never throws, never fabricates) when nothing is loaded — `[Coverage: UNIT]` (`test/services/ai/tools/viewer_navigation_tools_test.dart`)
- [ ] **Tier-agnostic seam** — seams are Open Core with no `FeatureGate`/`FeatureTierBadge`; gating lives on the consuming features (Explain Selection = openCore, AI Advisor = pro), verified when the UI lands — `[Coverage: MANUAL → pending]` (§22.18)

---

## 12.15 AI Waveform Assistant — Settings → AI config + Experimental gate (Open Core — §22.19)

- [ ] **Build-flag gate** — `kAiExperimental` default false; with the flag off there is no AI section anywhere; `--dart-define=AI_EXPERIMENTAL=true` offers it — `[Coverage: UNIT]` (`crux_license` `ai_experimental_test.dart`); `[Coverage: MANUAL]` (§22.19 steps 1–2)
- [ ] **Toggle gates config both ways** — flag on + toggle off shows only the toggle + Experimental chip; toggling on reveals provider/endpoint/key; toggling off hides them — `[Coverage: UNIT]` (`test/features/settings/widgets/ai_settings_section_test.dart`, `crux_license` `ai_experimental_provider_test.dart`)
- [ ] **Secure-storage key** — API key round-trips through `AiKeyStore` (per-provider), empty key deletes the secret, and the key is never in `shared_preferences`/session/logs — `[Coverage: UNIT]` (`test/services/ai/secure_storage_ai_key_store_test.dart`, `test/services/settings/settings_service_test.dart`); `[Coverage: MANUAL]` (§22.19 cross-restart persistence)
- [ ] **No-model empty state** — a cloud provider with no key shows "No model configured"; entering a key (or selecting Local Ollama) clears it — `[Coverage: UNIT]` (`ai_settings_section_test.dart`)
- [ ] **Provider/endpoint persistence** — selected provider + endpoint survive a round-trip; provider switch reloads that provider's own key — `[Coverage: UNIT]` (`settings_service_test.dart`, `ai_settings_section_test.dart`)
- [ ] **Experimental chip + a11y** — chip renders in en/zh_CN/ja/ko; toggle and clear-key controls ≥ 44 dp — `[Coverage: UNIT]` (`experimental_chip_test.dart`, `ai_settings_section_test.dart`)

---

## 12.16 AI Waveform Assistant — "Explain Selection" (Open Core, non-agentic — §22.20)

- [ ] **Action gating** — `aiExplainSelection` is openCore (no badge), hidden when experimental AI is off, disabled without a configured model + non-empty selection + loaded file, enabled + in the palette when all gates pass — `[Coverage: UNIT]` (`test/core/shortcuts/ai_explain_selection_gating_test.dart`)
- [ ] **Single non-agentic call** — one `AiModelClient` call (system + user, no tools); response parsed into text + citation segments — `[Coverage: UNIT]` (`explain_selection_test.dart`, `explain_selection_provider_test.dart`)
- [ ] **Grounded citations jump** — a resolved citation jumps the cursor to the exact cited tick and selects the cited signal — `[Coverage: UNIT]` (`explain_selection_result_panel_test.dart`, `explain_selection_test.dart`)
- [ ] **Could-not-locate, never wrong jump** — an unresolvable citation (unknown signal / out-of-range time) renders a non-clickable "Could not locate" chip and performs no jump — `[Coverage: UNIT]` (`explain_selection_test.dart`, `explain_selection_result_panel_test.dart`)
- [ ] **Phases + a11y** — no-model / empty-selection / error messages; Experimental chip in the header; 44 dp close button; locale sweep en/zh_CN/ja/ko — `[Coverage: UNIT]` (`explain_selection_result_panel_test.dart`)
- [ ] **End-to-end with a real key** — explanation quality + citation accuracy against a live BYO endpoint (concrete client from the overlay) — `[Coverage: MANUAL]` (§22.20)

---

## 12.17 Signal selection from the waveform + Clear selection (Open Core — §22.21)

- [ ] **Ctrl/Cmd-click selects from the value column** — Ctrl/Cmd-clicking a value cell toggles that signal's selection; a plain click keeps its existing copy/cycle action and does not change the selection — `[Coverage: WIDGET]` (`value_column_row_test.dart`)
- [ ] **Selection highlight** — a selected value row paints the primary tint (low opacity), consistent with the Signal Tree leaf; an unselected row does not — `[Coverage: WIDGET]` (`value_column_row_test.dart`)
- [ ] **Touch "Select Signal" menu item** — the value row's long-press context menu carries a "Select Signal" item that toggles the selection — `[Coverage: WIDGET]` (`value_column_row_test.dart`)
- [ ] **Status-bar ✕ clears** — the ✕ next to the selected-signal indicator appears only when a selection exists (and never on phone) and clears the whole selection on tap — `[Coverage: WIDGET]` (`status_bar_test.dart`)
- [ ] **`clearSignalSelection` action** — wired into the descriptor / Navigate menu / overflow / command palette; enabled only while a selection exists — `[Coverage: WIDGET]` (`action_surface_conformance_test.dart`, `menu_layout_test.dart`, `shortcut_action_test.dart`)
- [ ] **Escape clears** — Escape clears the signal selection (alongside cursors) via the viewer's global key handler; the underlying `SelectedVariablesNotifier.clear()` is unit-tested — `[Coverage: WIDGET]` (`signal_tree_providers_test.dart`) + `[Coverage: MANUAL]` (keystroke wiring, §22.21)

---

## 12.18 Session restore parity — active panel, pane sizes, signal-tree state (Open Core — §22.22)

- [ ] **Active bottom panel restores** — cocotb-log / RTL-source panel visibility persists and re-docks on relaunch; the cocotb log and RTL stems files are re-loaded fail-soft (moved/deleted file → empty panel, no error) — `[Coverage: WIDGET]` (`session_service_test.dart` "v3 session-restore state", `session_providers_test.dart` round-trip) + `[Coverage: MANUAL]` (quit→relaunch, §22.22)
- [ ] **Pane sizes restore** — left / right / bottom pane sizes persist and re-apply on relaunch; drag-to-resize writes through the sink; `CruxIdeLayout` reconciles a restored size onto its live controller — `[Coverage: WIDGET]` (`panel_layout_provider_test.dart`, `crux_ide_layout_test.dart`, `session_providers_test.dart`)
- [ ] **Signal-tree state restores** — expand/collapse set, search text, selection, and scroll offset persist and re-apply; stale paths/refs are harmless; a restored non-empty search drives search-expansion — `[Coverage: WIDGET]` (`signal_tree_providers_test.dart`, `signal_tree_panel_test.dart` "session-restore seeding", `session_service_test.dart`, `session_providers_test.dart`)
- [ ] **`.wavecrux` schema bumped to v3** — new `panels` content keys (`cocotbLogPanel`/`rtlSource` + paths + `sizes`) and top-level `signalTreeState`; all omitted at defaults (byte-stable); a v1/v2 doc reads with lenient defaults — `[Coverage: WIDGET]` (`session_service_test.dart`, `session_extensions_round_trip_test.dart`)
- [ ] **Full quit → relaunch** — panel + sizes + tree state actually restored in the running app — `[Coverage: MANUAL]` (§22.22 steps 1–2)

---

## 12.19 Update mechanism (Open Core — §22.23)

Fixtures: `verification/fixtures/update/` (`manifest_update_available.json`, `manifest_mandatory.json`, `manifest_up_to_date.json`, `manifest_malformed.json`).

- [ ] **Golden path** — a newer manifest version shows the banner "WaveCrux X.Y.Z is available."; View Changes opens `changelog_url`; Update Now opens the download page (desktop/web) / store (mobile) — `[Coverage: UNIT]` (`update_banner_test.dart`, `update_manifest_test.dart`); `[Coverage: MANUAL]` (§22.23 golden path, `manifest_update_available.json`)
- [ ] Web build never shows the update banner (self-updating surface; check still runs for server_time hardening); desktop against the same manifest does — `[Coverage: WIDGET]` (`update_banner_test.dart` — "web never shows the banner")
- [ ] **Dismiss** — Dismiss hides the banner for the session and it re-appears only for a *newer* version — `[Coverage: UNIT]` (`update_banner_test.dart`); `[Coverage: MANUAL]` (§22.23)
- [ ] **Mandatory non-dismissible** — `mandatory: true` (and below-`min_supported_version`) render a banner with no Dismiss; forced-mandatory below the floor is never suppressed — `[Coverage: UNIT]` (`update_banner_test.dart`, `http_update_check_service_test.dart`); `[Coverage: MANUAL]` (§22.23, `manifest_mandatory.json`)
- [ ] **Manual Check for Updates** — Help / overflow / palette + About-box button; available → banner, current → "You're on the latest version (X.Y.Z)" toast, error → non-fatal toast — `[Coverage: UNIT]` (`action_descriptors_test.dart`, `wavecrux_about_dialog_test.dart`, `update_check_action_test.dart`); `[Coverage: MANUAL]` (§22.23)
- [ ] **Auto-check toggle** — Settings → General toggle (default on); off suppresses launch/periodic checks; manual check still runs — `[Coverage: UNIT]` (`settings_screen_test.dart`, `settings_service_test.dart`, `update_status_provider_test.dart`); `[Coverage: MANUAL]` (§22.23, `manifest_up_to_date.json`)
- [ ] **Malformed-manifest soft-fail** — invalid manifest → no crash, no banner; manual check shows the non-fatal error — `[Coverage: UNIT]` (`update_manifest_test.dart`, `http_update_check_service_test.dart`); `[Coverage: MANUAL]` (§22.23, `manifest_malformed.json`)
- [ ] **Never-throws contract** — network / non-200 / parse failures resolve to a typed error state, never a thrown raw error — `[Coverage: UNIT]` (`http_update_check_service_test.dart`, `update_status_provider_test.dart`)
- [ ] **Server-time clock-back hardening** — observed `server_time` (persisted, monotonic) feeds the beta-expiry clock; setting the device clock back no longer defers expiry; fresh/offline install falls back to the device clock — `[Coverage: UNIT]` (`beta_expiry_test.dart`, `observed_server_time_provider_test.dart`); `[Coverage: MANUAL → HYBRID]` (§22.23 clock-back path, §22.17)
- [ ] **Tier-gate (openCore — no-op)** — `checkForUpdates` is openCore (no badge); the gate is a no-op under `kBetaPeriod = true` **and** `false` — `[Coverage: UNIT]` (`action_descriptors_test.dart`)
- [ ] **Locale sweep** — banner + toasts render exception-free in en/zh_CN/ja/ko — `[Coverage: MANUAL]` (the `crux_updates` banner tests sweep text direction and text scale with a product string set, not locales; no WaveCrux test renders the banner or toasts under zh_CN/ja/ko)

---

## 12.20 Bundled sample waveform (0.2.0, §22.24)

- [ ] **Welcome screen offers [Open Sample Waveform]** on phone, phone-landscape, tablet, and desktop — phone especially, where [Open Workspace…] is absent and this is the only path to content without an external file — `[Coverage: WIDGET]` (`wavecrux_empty_canvas_test.dart`); `[Coverage: MANUAL]` (§22.24)
- [ ] **Tap opens a tab named "WaveCrux Sample.vcd"** with five scopes (`spi_tb`, `i2c_tb`, `uart_tb`, `axi4lite_tb`, `apb_tb`) — `[Coverage: MANUAL → INTEGRATION candidate]` (§22.24 steps 3–4)
- [ ] **Decoders overlay transactions on the sample** (attach SPI to `spi_tb`) — this is the "it visibly works" demonstration — `[Coverage: MANUAL]` (§22.24 step 6)
- [ ] **Shipped asset has not drifted** — byte-identical to `verification/fixtures/protocol/multi/all5_basic.vcd`, parseable, all five scopes, under budget — `[Coverage: UNIT]` (`sample_waveform_service_test.dart`)
- [ ] **Repeat taps / truncated copy self-repair** — the sample is rewritten each invocation, so an interrupted write does not poison it permanently — `[Coverage: UNIT]` (`sample_waveform_service_test.dart`); `[Coverage: MANUAL]` (§22.24 edge cases)
- [ ] **Locale sweep** — button renders exception-free in en/zh_CN/ja/ko — `[Coverage: WIDGET]` (`wavecrux_empty_canvas_test.dart`)
- [ ] **iOS launch screen is the app mark, not a white flash** — cold-start a dark-mode iPhone and confirm the rounded WaveCrux icon appears on dark navy, with no white frame before the UI paints (delete + reinstall first; iOS caches launch screens) — `[Coverage: STATIC]` (`ios_launch_image_test.dart`); `[Coverage: MANUAL]`

## 12.21 App-store distribution surface (0.2.0, §22.25)

**Run this group against a mobile store build AND a desktop control before every store upload.**

- [ ] **No PRO/ENT rows in the mobile overflow menu** — *Debug Advisor*, *SVA panel/load/clear*, *AI Waveform Assistant*, *Convert PCAP to VCD*, *Share/Join/Stop/Leave Session*, *Export Session Recording*, Presenter Mode entries are **absent, not greyed** — `[Coverage: UNIT]` (`tier_gated_action_mobile_suppression_test.dart`); `[Coverage: WIDGET]` (`viewer_toolbar_test.dart` — "Open Core on a phone lists no PRO/ENT rows"); `[Coverage: MANUAL]` (§22.25 step 1)
- [ ] **No PRO/ENT entries in the mobile command palette** — `[Coverage: UNIT]` (`tier_gated_action_mobile_suppression_test.dart`); `[Coverage: MANUAL]` (§22.25 step 2)
- [ ] **Open Core rows all still present on mobile** — the suppression must not have emptied the sheet — `[Coverage: WIDGET]` (`viewer_toolbar_test.dart` — same test); `[Coverage: MANUAL]` (§22.25 step 3)
- [ ] **Desktop control still shows PRO/ENT rows with badges** — the suppression is mobile-only — `[Coverage: UNIT]` (`tier_gated_action_mobile_suppression_test.dart`); `[Coverage: MANUAL]` (§22.25 step 7)
- [ ] **No "Public Beta" chip in About on mobile**; present on desktop while `kBetaPeriod` is true — `bootstrap` overrides `betaPeriodProvider` to false on mobile hosts — `[Coverage: WIDGET]` (`wavecrux_about_dialog_test.dart`); `[Coverage: MANUAL]` (§22.25 steps 4, 8 — run as a control pair)
- [ ] **No Settings → AI Assistant category** in the store build (`AI_EXPERIMENTAL=false`); present on desktop — `[Coverage: UNIT]` (`settings_screen_test.dart`); `[Coverage: MANUAL]` (§22.25 step 5)
- [ ] **RGB LED binding hint carries no upsell on mobile** — reads "renders a single color channel", with no mention of Pro or upgrading; desktop keeps the upgrade wording — `[Coverage: WIDGET]` (`arty_a7_stage_widget_test.dart`); `[Coverage: MANUAL]` (§22.25 steps 6, 9)
- [ ] **Mobile browser is not a mobile host** — a phone on app.wavecrux.app keeps desktop behavior (chip + PRO/ENT rows) — `[Coverage: UNIT]` (`platform_utils_test.dart`); `[Coverage: MANUAL]` (§22.25 edge cases)
- [ ] **Tier-gate both regimes** — mobile suppression keys off whether the build *implements* the actions, not off `kBetaPeriod`, so it holds under `kBetaPeriod = true` **and** `false`; no upgrade dialog or external purchase CTA can appear on a store build — `[Coverage: UNIT]` (`tier_gated_action_mobile_suppression_test.dart`)
- [ ] **Pro mobile escape hatch intact** — `tierGatedActionsAvailableProvider` is overridable to `true` so a future Pro mobile build keeps its features — `[Coverage: UNIT]` (`tier_gated_action_mobile_suppression_test.dart`)

## 12.22 Shipped `examples/` sessions (0.2.0, §22.26)

- [ ] **`File → Open File` accepts a `.wavecrux`** — the picker's extension list includes `wavecrux` and the post-pick dispatch routes it to the session loader; there is no separate "open session" item — `[Coverage: MANUAL]` (§22.26 step 1)
- [ ] **`five-buses.wavecrux` opens with its trace from any working directory** — the relative `sourceFilePath` resolves against the session file's own directory, not the process CWD — `[Coverage: UNIT]` (`test/examples/examples_test.dart`); `[Coverage: MANUAL]` (§22.26 step 2)
- [ ] **Five signal groups, APB collapsed** — group collapse state round-trips through the session — `[Coverage: MANUAL]` (§22.26 step 3)
- [ ] **Transaction table populated on open** with all five decoders' output, no manual binding — this is the "it visibly works" moment for the decoder surface — `[Coverage: UNIT]` (`examples_test.dart` decodes all five through the registry factories and matches the committed expectations); `[Coverage: MANUAL]` (§22.26 steps 4–5)
- [ ] **`pipeline-diagram.wavecrux` opens with the Stage panel visible** and one Pipeline Diagram tile across IF/ID/EX/MEM/WB; clicking a cell seeks the cursor and the raw lanes agree — `[Coverage: MANUAL]` (§22.26 steps 6–8)
- [ ] **No baked reference has gone stale** — every signal path resolves, every signal/Stage/decoder `ref` equals what the committed trace produces. Restore does *not* re-resolve Stage and decoder refs, and a signal whose path matches nothing is dropped **without an error**, so this can only be caught by test — `[Coverage: UNIT]` (`examples_test.dart`)
- [ ] **Both `.vcd` copies have not drifted** from `verification/fixtures/protocol/multi/all5_basic.vcd` and `test/fixtures/protocol/riscv/generated/riscv_pipeline_5stage.vcd` — `[Coverage: UNIT]` (`examples_test.dart`)
- [ ] **Every example is guarded and documented** — a `.wavecrux` added to `examples/` without a guard entry or a README entry fails — `[Coverage: UNIT]` (`examples_test.dart`)
- [ ] **Open Core only** — neither example mounts a Pro Stage widget or names a Pro decoder, in either `kBetaPeriod` regime — `[Coverage: UNIT]` (`examples_test.dart` resolves both against the open-core registries)

---

## 12.23 Digital bus rendered as an analog trace (§22.27)

The rule to hold in mind: the analog toggle is **orthogonal to the display
format**. The format decides what number the bits are; the toggle decides how
that number is drawn. Every item below is really a check that those two axes
stayed independent.

- [ ] **A `real` signal still renders as a curve with nothing turned on** — the historical path is untouched — `[Coverage: UNIT]` (`analog_digital_lane_test.dart` — the default extractor); `[Coverage: MANUAL]` (§22.27 step 2)
- [ ] **`Render as analog` appears on BOTH the signal-name row menu and the value-column menu**, applies immediately, and flips to `Render as digital` for a row already analog. Two entry points on purpose: the format menu is value-column-only, but GTKWave puts Data Format on the signal name, so that is where a migrating user looks first — `[Coverage: WIDGET]` (`value_column_row_test.dart`, `signal_list_panel_test.dart`); `[Coverage: MANUAL]` (§22.27 steps 3, 5)
- [ ] **Changing the format re-shapes the curve without touching the toggle** — the same bus is a raw sawtooth under hex and a ±3.5 sine under Q4.12 — `[Coverage: UNIT]` (`analog_digital_lane_test.dart`, `numeric_value_test.dart`); `[Coverage: MANUAL]` (§22.27 step 4)
- [ ] **Turning the curve off leaves the format set** — the two settings persist independently — `[Coverage: WIDGET]` (`value_column_row_test.dart`); `[Coverage: MANUAL]` (§22.27 step 5)
- [ ] **A hex bus is not plotted by parsing its digits** — `"1e5"` is 485, not 100 000. The single most damaging way to implement this wrong, and invisible on most values — `[Coverage: UNIT]` (`numeric_value_test.dart`)
- [ ] **Gray-coded buses decode before plotting** — plotting raw Gray draws a sawtooth the design never had — `[Coverage: UNIT]` (`numeric_value_test.dart`)
- [ ] **`x` / `z` runs render as gaps, never as zeros** — a gap drawn on the axis is indistinguishable from a real zero sample — `[Coverage: UNIT]` (`analog_digital_lane_test.dart`, `analog_fixture_golden_test.dart`); `[Coverage: MANUAL]` (§22.27 step 6)
- [ ] **Lanes not opted in stay digital** — verified against a fixture carrying analog and digital signals simultaneously, so a change that converted every lane fails — `[Coverage: UNIT]` (`analog_fixture_golden_test.dart`); `[Coverage: MANUAL]` (§22.27 step 7)
- [ ] **Pro translators reach the renderer through `Translator.translate` only** — open core never learns what bf16 is; a translator that throws or returns a label degrades to the bus magnitude rather than crashing the canvas — `[Coverage: UNIT]` (`analog_value_extractor_test.dart`)
- [ ] **`renderAsAnalog` round-trips through `.wavecrux`**, is omitted from the file when false, and a session written before the feature loads as digital — `[Coverage: UNIT]` (`session_service_test.dart`); `[Coverage: MANUAL]` (§22.27 step 8)
- [ ] **`.gtkw` analog flags import** — `TR_ANALOG_STEP` / `TR_ANALOG_INTERPOLATED` arrive already switched to analog; an unflagged trace does not — `[Coverage: UNIT]` (`gtkw_parser_test.dart`, `gtkw_golden_test.dart`); `[Coverage: MANUAL]` (§22.27)
- [ ] **`.gtkw` radix decode is correct** — the `@` word is a bit set over GTKWave's `TraceEntFlagBits`, not a low-byte enumeration; a hex-formatted bus imports as hex. Regression check for the mapping this release replaced — `[Coverage: UNIT]` (`gtkw_parser_test.dart` — one case per radix, plus the `@420` signed-with-no-radix form the fpxx_adder capture carries)
- [ ] **The analog fixture corpus regenerates deterministically** — `dart run tool/generate_analog_fixtures.dart` then `REGENERATE=1 flutter test test/services/waveform/analog_fixture_golden_test.dart` leaves the tree unchanged — `[Coverage: UNIT]` (`analog_fixture_golden_test.dart`)

---

## 13. Cross-feature integration

- [x] All 5 Open Core decoders (SPI, I²C, UART, AXI4-Lite, APB) simultaneously — `[Coverage: INTEGRATION_TEST]` (`integration_test/coexistence/multi_decoder_coexistence_test.dart` — second scenario against `protocol/multi/all5_basic.vcd`, generated by `tool/generate_multi_coexistence_fixture.dart`'s `_generateAllFiveFixture`; per-decoder counts match each decoder's own expected companion, panning preserves all 5). The open-core decoder set has since grown beyond these 5 (AHB-Lite, Wishbone, CAN, AXIS, Avalon-MM/ST) — coexistence coverage for the newer decoders remains open; re-file a dedicated item if still wanted.
- [x] SPI + I²C decoders coexist on a combined bus (correct per-decoder counts, panning preserves both) — `[Coverage: INTEGRATION_TEST]` (`integration_test/coexistence/multi_decoder_coexistence_test.dart`; fixture `protocol/multi/spi_i2c_basic.vcd` + `.spi.`/`.i2c.expected_transactions.json`)
- [x] Decoder + diff — `[Coverage: INTEGRATION_TEST]` (`integration_test/coexistence/decoder_diff_coexistence_test.dart`; SPI overlay survives diff mode, divergence + XOR present)
- [x] Decoder + X-Trace — `[Coverage: INTEGRATION_TEST]` (`integration_test/coexistence/decoder_xtrace_coexistence_test.dart`; fixture `protocol/multi/spi_xtrace.vcd`; X-Trace panel renders, SPI decode intact)
- [x] Decoder + pattern search — `[Coverage: INTEGRATION_TEST]` (`integration_test/coexistence/decoder_pattern_search_coexistence_test.dart`; `sclk == 1` matches alongside intact SPI overlay)
- [x] Stage + FSM + RTL on desktop — `[Coverage: INTEGRATION_TEST]` (`integration_test/coexistence/stage_fsm_rtl_coexistence_test.dart`; Stage + RTL co-mounted, FSM panel renders in shared dock slot, scrub updates all)
- [x] Tablet with Stage + FSM — `[Coverage: INTEGRATION_TEST]` (`integration_test/coexistence/tablet_stage_fsm_test.dart`; 1024×768, no overflow, scrub updates both)
- [x] Session round-trip with Stage active, FSM open, statistics strip expanded, multiple decoders bound, custom panel sizes — `[Coverage: INTEGRATION_TEST]` (`integration_test/coexistence/composite_workspace_round_trip_test.dart`). **Passing** — the earlier "currently failing / FSM annotations not serialized" note was stale (the wiring landed; see VERIFICATION_GUIDE §15.7) and has been corrected here. The scenario now also activates an I²C decoder on tab A and a UART decoder on tab B before save, asserting both survive the round-trip with `decoderId` / `instanceNumber` / `config.signalBindings` intact.

---

## 13A. Telemetry — cross-platform end-to-end pass (staging)

> **Run 2026-08-05/06** against the **staging** dataset `crux_telemetry_dev`, from
> builds made with `--dart-define=TELEMETRY_DEV=true`. Reading the staging dataset
> needs maintainer credentials for the ingestion backend.
>
> **Method per cell.** Build with the dev flag, launch, let the app settle, quit,
> **launch again** — the launch flush ships the *previous* session's queue — quit,
> then read the dataset after the 60–90 s ingest delay. No UI interaction is needed,
> because under the dev flag consent `unset` counts as `enabled`.
>
> **Attribution.** All four products ship `0.6.0`, so `app_version` cannot separate
> the runs. Rows are attributed by **`installation_id` (`blob8`)**: every platform has
> its own app-support container, simulator container, emulator data partition or
> browser origin, so each run mints a distinct id (recorded below). Runs were
> serialised, so the UTC window corroborates the id. Bring-up probe rows are excluded
> by `blob2 = '0.6.0'` (probes are `8.8.x` / `9.8.x` / `9.9.x`), and the Worker's own
> contract fixture by `blob8 != '6f1b0d3e-2a44-4c9e-9f1a-8d5b7c2e4a10'`.

| Platform | `os` | `form_factor` expected | observed | Result |
|---|---|---|---|---|
| macOS 26.6 (Apple silicon), release | `macos` | `desktop` | `desktop` | **PASS** |
| Chrome 151, release web build | `web` | `web` | `web` | **PASS** — re-run 2026-08-06 after the D1 fix; installation `30b79c61-6e2c-4b4d-8073-09588514cb50` |
| iOS simulator — iPhone 16 Pro | `ios` | `phone` | `phone` | **PASS** |
| iOS simulator — iPad Pro 11-inch (M4) | `ios` | `tablet` | `tablet` | **PASS** |
| Android emulator — `Medium_Phone_API_35` | `android` | `phone` | `phone` | **PASS** |
| Android emulator — `Pixel_Tablet`, portrait | `android` | `tablet` | `tablet` on **5 of 5** launches, zero `desktop` | **PASS** — re-run 2026-08-06 after the D2 fix; installation `677fce8a-4373-4d49-9dba-e6244a43c3a3` |
| Android emulator — `Pixel_Tablet`, landscape | `android` | `desktop` at 1280 dp | `desktop` | **PASS**. It still cannot distinguish a correct answer from a default by itself — but the portrait cell above now can, and a unit test pins both ends (`telemetry_platform_test.dart` → `D2 — the wired seam on a tablet host`) |
| Physical iPhone — `MartinPhone` | `ios` | `phone` | — | **DEFERRED** — the device was locked, so the developer disk image could not be mounted (`kAMDMobileImageMounterDeviceLocked`). Not a wireless-flakiness deferral: the build signed and produced `build/ios/iphoneos/Runner.app`; only the install failed. Unlock the phone and re-run the install command in §15.1 |
| Windows | `windows` | `desktop` | — | **DEFERRED** — no Windows machine on this host |
| Linux | `linux` | `desktop` | — | **DEFERRED** — no Linux machine on this host |

- [x] Every passing row carried the right envelope: `product=wavecrux`, `locale=en`, `country=US` (stamped at the edge), `license_tier=openCore`, and a normalized `session_start` — `[Coverage: MANUAL]` (staging dataset)
- [x] Coalescing works end to end — the two launches' identical `workspace.restored {panes=1,tabs=0}` arrived as **one row with `count=2`** on iOS and Android, and as two rows when the properties differed — `[Coverage: MANUAL]`
- [x] `_sample_interval = 1` on every row, so the `product/event_name/properties` index is not sampling at this volume — `[Coverage: MANUAL]`
- [x] Catalog events beyond the launch path reached the dataset: `file.opened {format=vcd}` (Android) — `[Coverage: MANUAL]`

**Installation ids for the passing rows** — macOS `cab8d6f8-014b-4e8e-b370-c882c35a1918` · iPhone 16 Pro sim `2c9fd523-2ddf-49d4-983b-afda4e2091a5` · iPad Pro 11 M4 sim `e102f858-b56d-4c27-8ca0-4b64b5b9dcd3` · Android phone `ec9b67b6-d0a1-4943-89e8-9666d028cb5b` · Android tablet `3ddcab20-2b9a-4b18-be95-09cebe354225` (2026-08-05).

**Re-run 2026-08-06** — Chrome web `30b79c61-6e2c-4b4d-8073-09588514cb50` · Android tablet `677fce8a-4373-4d49-9dba-e6244a43c3a3` (fresh install, so a new id) · macOS `cab8d6f8-…` for the consent-`disabled` cell, which is asserted on producing **no** row.

### 13A.1 Picking up the deferred cells on another machine

```bash
# Physical iPhone — unlock the device first, then:
flutter build ios --debug --dart-define=TELEMETRY_DEV=true
xcrun devicectl device install app --device <udid> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --device <udid> com.ferriteengineering.wavecrux
#   quit, launch a second time, then read the dataset ~90 s later.

# Windows / Linux — on a host of that OS:
flutter build windows --release --dart-define=TELEMETRY_DEV=true   # or: build linux
#   launch the built binary twice, quitting in between, then:
#   then query the staging dataset (maintainer credentials required).
```

### 13A.1b Re-run 2026-08-06 — all three defects fixed

crux-shared pinned at `1c30b1f` (`crux_telemetry` 0.3.0). Every cell below is a
real client on a real platform with `--dart-define=TELEMETRY_DEV=true`, attributed
by `installation_id`; no `curl` was substituted for a platform run.

| Cell | Evidence | Result |
|---|---|---|
| Chrome 151, release web build × 4 products | one row each, `os=web`, `form_factor=web`, `locale=en`, `license_tier=openCore`, `country=US`, ~70 s after the page load. WaveCrux `30b79c61-…`, NetCrux `4818fdcc-…`, LintCrux `14c6c298-…`, SimCrux `5a0805ba-…` | **PASS** (was: zero rows, all four) |
| `Pixel_Tablet` portrait, release APK, 5 launches | `sw800dp-w800dp-h1280dp … port` confirmed by `am get-config` before each run. **5 rows, all `form_factor=tablet`, zero `desktop`** — installation `677fce8a-…` | **PASS** (was: 1 of 4 correct) |
| `consent = disabled` + dev flag, macOS release, 2 launches | **zero** rows from installation `cab8d6f8-…` in the run window; the only row that id has ever produced is the pre-fix one at `00:47:51Z`. **No `telemetry_queue.jsonl` was created** at either the sandboxed or unsandboxed path | **PASS** (was: a real staging row) |
| Production dataset, 90 days | 0 rows | **PASS**, unchanged |

Two things the re-run found that the original pass could not:

- **The Android release APK had no network access at all.** The Flutter template
  declares `android.permission.INTERNET` in `android/app/src/debug/` and
  `profile/` only. A release build therefore ships without it, and the update
  check and telemetry both swallow their errors by contract — so they report
  nothing rather than reporting a failure. The original pass got Android rows
  because `flutter run` is a *debug* build. Fixed in
  `android/app/src/main/AndroidManifest.xml`; **this was blocking §12.19's
  update check in every release build too**, not only telemetry.
- **D3's fix needed a third gate state.** Making the gate wait for the consent
  store creates a window, and the store's read does not *start* until something
  reads the telemetry graph — so `workspace.restored`, emitted from
  `WorkspaceNotifier.build()`, is inside it by construction. Resolving the no-op
  there **discarded** the launch counter, which on web is the entire session.
  `TelemetryGate { open, closed, pending }` and `PendingTelemetryService` buffer
  that window instead. Related: `WorkspaceNotifier` held the resolved service in
  a field, which froze the first frame's verdict for the whole session — now
  read per event, with `test/static/telemetry_service_not_captured_test.dart`
  scanning `lib/` so it cannot come back.

### 13A.2 The negative cases

- [x] **A beta build without the dev flag performs zero telemetry HTTP.** Primary
  evidence is the traffic-level beta-inert test — `[Coverage: PACKAGE]`
  (`crux_telemetry`'s `telemetryServiceProvider` suite, 64 tests, sweeps all 12
  `policy × consent` cells asserting an empty request list) — plus this repo's own
  group — `[Coverage: UNIT]` (`test/core/providers/telemetry_service_provider_test.dart`,
  8 tests). Corroborated at runtime — `[Coverage: MANUAL]`: a NetCrux release built
  with **no** `--dart-define` was launched twice and **never created
  `telemetry_queue.jsonl` at all** (the live service is never constructed, so
  `record()` hits the no-op and nothing touches disk or the network), and the
  **production** dataset `crux_telemetry` holds **0 rows over 90 days**.
- [x] **Consent `disabled` with the dev flag sends nothing.** — **PASS** on the 2026-08-06 re-run (§13A.1b): two launches of a `TELEMETRY_DEV` macOS release with `flutter.telemetry.consent = disabled` produced zero rows and wrote no queue file. See D3.

### 13A.3 Defects found — all three FIXED on 2026-08-06

- [x] **D1 — web builds never transmit; the `web` `form_factor` is unreachable in
  practice.** All four products' release web builds produced **zero** rows across two
  page loads each. A full Chrome `--log-net-log` capture over a 90 s WaveCrux web
  session shows **zero requests to `telemetry.edacrux.app`** (the same capture holds
  300 references to the page's own assets, so the capture itself is sound).
  Mechanism, reproduced hermetically against `LiveTelemetryService` with a
  `directoryFactory` that throws (exactly what web does): on web `path_provider` is
  unavailable, so `TelemetryEventQueue` degrades to memory-only and `load()` returns
  empty; `start()`'s launch flush therefore runs against an empty `_pending` and
  returns at `if (_pending.isEmpty) return;` **without arming anything**; the only
  remaining trigger is the 6-hourly timer, which no browser session survives. On
  desktop and mobile the disk queue carries events to the next launch, which is why
  only web is affected. **Not a shipping-harm defect today** (the whole pipeline is
  dark-launched until `kBetaPeriod` flips), but the field exists to answer "does the
  web build earn its maintenance" and it cannot. Fix is a design call between
  (a) backing the queue with the `TelemetryStorage` seam on web so it survives a
  reload, or (b) arming a short follow-up flush when the launch flush finds the queue
  empty — (b) changes the documented "this session's events go out on the next
  six-hourly tick or the next launch" contract on every platform. **FIXED
  2026-08-06** in `crux_telemetry` 0.3.0: option (b), scoped to the volatile
  queue only, so the contract is unchanged wherever it actually holds. Where
  `TelemetryEventQueue.hasPersistentBacking()` is false, `record()` arms one
  flush per `volatileFlushInterval` (60 s, a named constant on
  `CruxTelemetryConfig`) — per window, not per event, so a busy session still
  makes progress — and the host's hidden/paused/detached signal flushes too,
  through Flutter's own `AppLifecycleListener` rather than a `dart:html`
  dependency. Re-run: all four products' web builds now report (§13A.1b).
- [x] **D2 — `form_factor` races the first layout, and reports the pre-layout default
  when it loses.** On `Pixel_Tablet` held in **portrait** — the activity's own
  configuration reading `sw800dp w800dp h1280dp 320dpi xlrg port`, which
  `DeviceClass.fromSize` classifies unambiguously as `tablet` — four consecutive
  launches of the *same build on the same device in the same orientation* reported:

  | flush | `form_factor` |
  |---|---|
  | 00:53:10Z | `desktop` |
  | 00:53:52Z | **`tablet`** |
  | 00:55:14Z | `desktop` |
  | 00:56:14Z | `desktop` |

  So the value is **non-deterministic**, which rules out a breakpoint disagreement and
  leaves only a race. `resolveTelemetryEnvelope` reads `telemetryFormFactorProvider`
  at **flush** time; the launch flush is driven from `start()`, which runs on the
  first read of `telemetryServiceProvider` inside `WorkspaceNotifier.build()` —
  *before* `DisplaySizeFeed` (mounted in `MaterialApp.builder`) has pushed a size.
  With `displaySizeProvider` still `null`, `deviceClassForSize(null)` returns
  `DeviceClass.desktop`. `device_class_provider.dart` asserts that this default "is
  never observed" because the splash screen precedes the first widget tree — true for
  layout consumers, which build *inside* the tree, and false for telemetry, which
  reads the provider from a service ahead of it. A race is the worse failure mode
  than a flat wrong value: it biases `desktop` upward by an unknown, device-speed-
  dependent amount instead of being visible as an obviously wrong constant, and the
  iPhone / iPad / Android-phone cells all happened to win it, which is exactly how
  this would have passed a less repetitive check. (The landscape `Pixel_Tablet` run
  also reported `desktop`, but it cannot distinguish the two causes — at 1280 dp wide
  the breakpoints legitimately give `desktop`. Only the portrait runs separate them.)
  **FIXED 2026-08-06.** Neither of the two options considered: the form factor is
  not knowable before the first frame, and holding the launch flush would put a
  network decision behind a layout event. Instead `telemetryFormFactorProvider`
  became `Provider<String?>` and `resolveTelemetryEnvelope` defers on `null` —
  the same defer-and-retry the pipeline already applied to an unresolved
  `app_version`, and for a sharper reason: a bad `app_version` is rejected by the
  Worker and the loss is visible, whereas a bad `form_factor` is accepted and
  reads as measurement forever. WaveCrux supplies that `null` through
  `resolvedDeviceClassForSize`, which is `deviceClassForSize` without the
  pre-layout default; the doc comment claiming that default "is never observed"
  is corrected rather than deleted, because it was right about the layout
  consumers it was written for. `kIsWeb` and a native desktop host never defer —
  neither races anything. A deferred flush retries after 60 s on every host, or
  D2's fix would have handed the queue to a next launch that raced the same
  frame again. Re-run: **5 of 5 launches reported `tablet`, zero `desktop`**
  (§13A.1b).
- [x] **D3 — a stored consent of `disabled` still transmits under the dev flag.**
  With `flutter.telemetry.consent = disabled` in WaveCrux's preferences and a
  `TELEMETRY_DEV=true` build, two launches produced a real row in the staging dataset
  (`workspace.restored`, `count=2`, installation `cab8d6f8-…` — the very installation
  whose consent is `disabled`), and `telemetry_queue.jsonl` was written on disk.
  Cause: `TelemetryConsentStore.build()` publishes `TelemetryConsentState.unset`
  **synchronously** and loads the persisted value asynchronously, while
  `telemetryEnabledProvider` computes
  `consent == enabled || (dev && consent == unset)` — so for the first frames of a
  cold start a stored `disabled` is indistinguishable from "not answered", and under
  the dev flag the gate opens. The store's own doc calls the `unset`-first default
  "harmless" for the gate because "`unset` reads as 'do not collect' either way",
  which is true only when `dev` is false. **Blast radius is dev builds only**: with
  `dev == false` the beta branch short-circuits synchronously during the beta, and
  post-flip the gate reads `consent == enabled`, where `unset` fails safe. No
  shipping build is affected and the beta promise is intact — but the guarantee
  §6.1/§8 documents for the dev flag is broken. Note the 36-cell gating matrix in
  `crux_telemetry` cannot catch this: it seeds consent by assigning
  `notifier.state` directly, so **no cell exercises a value read back through
  storage**. Fix: gate the dev-flag `unset` promotion on the store having settled
  (the store already owns a `loaded` completer), and add a storage-backed cell to the
  matrix. **FIXED 2026-08-06** in `crux_telemetry` 0.3.0, pinned in all four
  products at crux-shared `1c30b1f`: the dev-flag promotion of `unset` now waits
  on `telemetryConsentReadyProvider`, the same `loaded` signal the disclosure
  already waited on, and the 36-cell matrix settles the store before asserting
  rather than seeding `notifier.state` synchronously. The package gained a
  pre-load group that seeds *storage* behind a gated read, and this repo gained
  the same assertion through `WavecruxTelemetryStorage` and `SharedPreferences`.

  Two consequences that only a real client showed, both now fixed and both
  covered by tests. First, waiting creates a window that is not incidental: the
  store's read does not *start* until something reads the telemetry graph, so
  `workspace.restored` — emitted from `WorkspaceNotifier.build()` — is inside it
  by construction, and resolving the no-op there **discarded** it rather than
  deferring it. The gate is a tri-state now
  (`TelemetryGate { open, closed, pending }`), `PendingTelemetryService` buffers
  the window, and the buffer is replayed into the live service when the gate
  opens or dropped when it closes; the beta never enters that state. Second,
  `WorkspaceNotifier` held the resolved service in a field, which froze the first
  frame's verdict for the whole session — read per event now, with
  `test/static/telemetry_service_not_captured_test.dart` scanning `lib/` for the
  shape. Re-run: **zero rows and no queue file** from the `disabled`
  installation (§13A.1b).

---

## 14. Final report

- [ ] Diagnostics report archived for each major fixture under release version — `[Coverage: MANUAL]` (process artifact)
- [ ] Open issues filed for any failures — `[Coverage: MANUAL]`
- [ ] Sign-off captured (name + date below) — `[Coverage: MANUAL]`

---

**Sign-off:** ____________________  **Date:** ____________________

---

*Document version: v1.2 (2026-07-20). Update alongside `VERIFICATION_GUIDE.md` whenever a new feature lands. v1.1 added §12.19 Update mechanism (§22.23). v1.2 added §12.20 Bundled sample waveform (§22.24) and §12.21 App-store distribution surface (§22.25), both landed in 0.2.0 in response to the App Store review rejection of 0.1.0 (2) under Guidelines 2.1 and 2.2.*

## 12.24 Waveform annotations (§22.28)

- [ ] **Discovery, on a fresh profile:** View ▸ Annotations Panel opens the
      panel with **no** annotations and shows the Option-click hint; right-click
      offers the three add actions; Edit ▸ Add Annotation at Cursor (⇧A) works
      with a cursor and one selected signal
- [ ] **View ▸ Show Annotations (⌘/Ctrl+⇧N)** hides and shows every note, and
      the state persists — a control that did **not** exist until 2026-08-13
      although the state and the export integration did
- [ ] The Annotations panel has a **close button**, and closing it deletes no
      notes and stays closed as new ones are added
- [ ] **⇧A with a signal selected in the signal list and a cursor placed**
      creates a note on that lane — check with a *real* selection; the
      fullPath-vs-signalRef mismatch shipped twice and fails silently
- [ ] The band **confine (⌄) control appears** when exactly one signal is
      selected — same resolver, same trap
- [ ] **Shift+drag a region, then Edit ▸ Annotate Selected Range** — the band
      covers exactly the grey zone. This is the route that did not exist: bands
      were reachable only from the canvas long-press menu, which nobody
      performs with a mouse
- [ ] With no drag selection it falls back to both cursors; with neither it
      says which is missing
- [ ] **Drag a band edge slowly, in many small movements** — it must land where
      the pointer did, not accelerate away
- [ ] **Committing text un-collapses the note** — it must not snap back to a dot
- [ ] The balloon's **⌄ folds it back**; tapping the dot expands it again
- [ ] A **band shows its panel number** and its **text is editable**, including
      the delta pre-filled at creation
- [ ] Editing a note from the **"Not displayed"** group shows its signal first;
      one under **"Not in this file"** explains instead of doing nothing
- [ ] Every panel row has a **⋮** that opens without a perceptible delay
- [ ] ⋮ ▸ Delete works, **including on a "Not displayed" orphan** — the case it
      exists for, since an orphan draws no balloon and so has no ✕
- [ ] ⋮ ▸ Collapse / Expand on canvas folds and unfolds the note — previously
      only the walkthrough could fold one
- [ ] ⋮ ▸ Set anchor time… moves the note to a typed tick, clamps out-of-range,
      and **the moved note does not go drifted**
- [ ] The Drifted-only chip carries an amber swatch and explains what amber
      means; the exported SVG uses the same amber

- [ ] Option/Alt-click a lane creates a note; typing + Enter commits it
- [ ] Alt-click off a lane creates nothing and says why
- [ ] A click near a transition snaps to the edge; the modifier places freely
- [ ] Dragging a balloon moves the label, not the anchor, and never the cursor
- [ ] Every balloon is grabbable, including the earliest and the most-moved
- [ ] Collapsed dot expands on click; × deletes with an Undo snackbar
- [ ] Editing the trace and letting the watcher reload flags the affected note
      as drifted; changing it back clears the flag
- [ ] Switching that row hex → decimal does NOT drift it
- [ ] Annotations panel lists every note, including "Not displayed" and
      "Not in this file"; Show signal restores the lane
- [ ] Filter text and Drifted-only narrow the list; an empty result says so
- [ ] Session save/reopen restores notes, positions and witness state
- [ ] PNG export includes annotations; unticking excludes them and the canvas
      is left showing them afterwards
- [ ] With PNG selected, Time range and Signals are disabled and explained

## 12.25 The `.wavecruxpack` share bundle (§22.29)

- [ ] File ▸ Share Annotated Waveform… is in the File menu and the palette,
      and is NOT on the toolbar and has no keyboard binding
- [ ] The disclosure dialog appears before the save dialog
- [ ] It lists every signal **path** — not a count — plus the time range, the
      embedded author names and the predicted size
- [ ] Strip author names is offered only when something is attributed
- [ ] Cancel writes nothing and opens no save dialog
- [ ] Opening the pack where the original dump is absent restores the annotated
      view from the bundled waveform
- [ ] Stripped names really are absent; the note text is not
- [ ] Reopening the same pack replaces the previous extraction
- [ ] Unzipped by hand: session.wavecrux, waveform.vcd, preview.png, README.txt,
      with the README naming wavecrux.app/open
- [ ] Above the email threshold it warns and still proceeds; past the ceiling it
      refuses and never opens the save dialog
- [ ] A text file renamed `.wavecruxpack` says it is not a pack; a real zip with
      no session says the session is missing
- [ ] macOS Finder shows the WaveCrux document type for `.wavecruxpack`

## 12.26 Arrow and band authoring (§22.30)

- [ ] Alt-click makes a callout; Alt-drag makes an arrow from the press point
- [ ] An arrow dragged only a pixel or two is not created at all
- [ ] One ⌘Z removes a whole arrow, create and drag together
- [ ] Right-click offers both band flavours; each pre-fills the measured delta
- [ ] Dragging one band edge leaves the other where it was
- [ ] The span readout shows live while an edge is held, and only then
- [ ] Dragging an edge past the other does not swap the handles
- [ ] One ⌘Z reverts a whole edge drag
- [ ] The scope toggle confines / un-confines without moving start or end
- [ ] With zero or several signals selected, no confine control is offered
- [ ] Clicking an annotation rings it; ⌥←/→ moves one tick, ⌥⇧←/→ one edge
- [ ] A nudged note stays **resolved** — it must not report drift
- [ ] Nudging past the last edge holds position and does not pan the viewport
- [ ] Bare ←/→ still pan

## 12.27 Annotations in SVG export (§22.31)

- [ ] SVG + Visible + Visible Signals matches what is on screen
- [ ] SVG + Full Simulation + All Loaded Signals really covers more than the
      viewport, and the document grows taller to fit the lanes
- [ ] Callout, arrow and band all appear in the exported SVG
- [ ] A collapsed note exports as a numbered dot
- [ ] A drifted note exports dashed and amber, matching the canvas
- [ ] Orphaned / unresolved notes export nothing
- [ ] Untick Include annotations — none appear; same for the visibility toggle
- [ ] A body containing `< & > " '` still **opens in a browser**
- [ ] A long body wraps across lines rather than being cut to ~10 characters

## 12.28 Walkthrough mode (§22.32)

- [ ] `]` centres and expands the next note; `[` the previous
- [ ] `[` with no tour running opens at the last note
- [ ] Wrapping either way **says so** rather than going silent
- [ ] Each landing keeps the zoom and scrolls the row into view
- [ ] ⌥→ after a step nudges the note the tour is on
- [ ] **One ⌘Z after a tour undoes your last real edit, not a fold**
- [ ] ▶ steps immediately, then on the dwell; a changed dwell applies now
- [ ] ⏸ keeps the position, ⏹ clears it, and ⏹ hides when there is nothing
- [ ] The three commands vanish from the menu and palette with no annotations
- [ ] Rebinding `]` works — they are ordinary ShortcutActions
- [ ] Stepping while following a session detaches follow

## 12.29 Session annotation layers and adoption (§22.33)

- [ ] Ending a session raises a **non-modal strip**, not a dialog, naming the
      note count and the participant count
- [ ] Keep all adopts everything as one named layer; Keep only mine adopts just
      yours — **still as a layer**
- [ ] Keep only mine is **absent**, not greyed, when every note is already yours
- [ ] Discard keeps nothing and registers no layer
- [ ] **✕ keeps everything** — a closed prompt takes the branch that does not
      lose work irreversibly
- [ ] "Don't ask again" keeps and persists; a later session adopts with no
      prompt. The preference can only ever mean *keep*
- [ ] A session that produced no notes shows no strip
- [ ] The panel groups adopted notes under the layer name, your own above them
- [ ] The eye hides a layer from the canvas and the walkthrough but **not** from
      the panel
- [ ] The trash deletes the group and its notes together; one ⌘Z restores them all
- [ ] An emptied layer stops showing a heading
- [ ] An adopted note cannot be edited — a lock, and **Duplicate as mine**,
      which produces a new note with your name, no layer and no frozen colour
- [ ] Deleting an adopted note is allowed; rewriting it under its author's name
      is not
- [ ] Layer, name, visibility and frozen colours survive save → close → reopen
- [ ] A document with `layerId`s and no registry loads as an unnamed group,
      never as lost notes
- [ ] **A second session reassigning palette slots does not recolour the first
      layer** — `[Coverage: UNIT + MANUAL — Guide §22.33 step 20]`

