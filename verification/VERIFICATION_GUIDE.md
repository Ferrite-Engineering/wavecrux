# WaveCrux — Open Core Verification Guide (Detailed)

> **Purpose.** Pre-release end-user verification reference for every Open Core feature. Run the relevant sections before any tagged release of the open-core viewer; for a major release, run all sections.
>
> **Companion documents.** `VERIFICATION_CHECKLIST.md` (sibling, this folder) is the quick sign-off bullet list. Pro/Enterprise feature verification lives with the closed-source Pro overlay and is not duplicated here.
>
> **Source.** Consolidated from the earlier per-feature verification guides plus the v1.0 master verification document handed over on 2026-05-03. This is the canonical pre-release reference for the open-core viewer.

---

## Table of contents

1. [How to use this document](#1-how-to-use-this-document)
2. [Test data and fixture setup](#2-test-data-and-fixture-setup)
3. [Diagnostics panel](#3-diagnostics-panel)
4. [Signal search and direction filtering](#4-signal-search-and-direction-filtering)
4A. [Signal hierarchy tree — multi-select, parameter values, apply-decoder-to-selection](#4a-signal-hierarchy-tree--multi-select-parameter-values-apply-decoder-to-selection)
5. [Protocol decoders (Open Core)](#5-protocol-decoders-open-core)
6. [Analysis and search features](#6-analysis-and-search-features)
7. [Cocotb log file correlation](#7-cocotb-log-file-correlation)
8. [Integration and platform features](#8-integration-and-platform-features)
9. [Mobile, tablet, and adaptive layout](#9-mobile-tablet-and-adaptive-layout)
10. [Stage (built-in widgets)](#10-stage-built-in-widgets)
10A. [Stage Playback (animated playhead)](#10a-stage-playback-animated-playhead)
10B. [RISC-V Core Designer widgets (Open Core)](#10b-risc-v-core-designer-widgets-open-core)
11. [FSM state visualization](#11-fsm-state-visualization)
12. [RTL source annotation](#12-rtl-source-annotation)
13. [Performance verification](#13-performance-verification)
13A. [Waveform canvas rendering goldens (ARCHITECTURE §8.9 Layer 5)](#13a-waveform-canvas-rendering-goldens-architecture-89-layer-5)
14. [Edge cases and break-it tests](#14-edge-cases-and-break-it-tests)
15. [Cross-feature integration](#15-cross-feature-integration)
16. [Workspace and file lifecycle](#16-workspace-and-file-lifecycle)
17. [Value display formats and translate filters](#17-value-display-formats-and-translate-filters)
18. [Cursors, named markers, and the time ruler](#18-cursors-named-markers-and-the-time-ruler)
19. [Command palette](#19-command-palette)
20. [Export (VCD / PNG / SVG / clipboard)](#20-export-vcd--png--svg--clipboard)
21. [Action discoverability — desktop menu bar and mobile overflow menu](#21-action-discoverability--desktop-menu-bar-and-mobile-overflow-menu)
22. [Mobile UI standards (per ARCHITECTURE.md §3.1.8)](#22-mobile-ui-standards-per-architecturemd-3018)
23. [Sign-off checklist](#23-sign-off-checklist)
24. [Automation roadmap summary](#24-automation-roadmap-summary)

---

## 1. How to use this document

### 1.1 Pre-release flow

1. Generate test data once (Section 2). Fixtures under `verification/fixtures/` are pre-built — only regenerate them when an underlying generator changes.
2. Run **Section 3 (Diagnostics) first** — the diagnostics panel is the instrument used to verify everything else.
3. Sections 4–8 cover the desktop core feature surface (signal search, decoders, analysis, cocotb, integration/platform).
4. Sections 9–13 cover mobile/tablet, Stage, FSM, RTL annotation, and performance.
5. Section 14 (edge cases) and Section 15 (cross-feature) catch the failure classes that pass unit tests but break in real use.
6. Sections 16–22 cover the baseline and discoverability surface: workspace lifecycle, display formats, cursors/markers, command palette, export, action discoverability, mobile UI standards.
7. Sign off via Section 23 and archive the diagnostics report.

### 1.2 Per-test format

Each test follows a consistent structure:

- **What it does** — plain-language description of the feature, written for someone who isn't already an expert in HDL or the protocol involved.
- **Setup** — what test data, configuration, or pre-conditions are needed.
- **Steps and expected behavior** — exact actions and what correct output looks like.
- **Diagnostics-assisted verification** — what to cross-reference in the diagnostics panel to confirm the feature is working at a deeper level than what the UI shows.
- **Edge cases / break-it tests** — error conditions, empty states, malformed input, stress conditions.
- **Automation Assessment** — guidance on whether the test belongs in the integration test suite, should remain manual, or is a hybrid.

### 1.3 Reporting failures

When something doesn't match expectations, capture:

- A description of what you saw vs. what was expected.
- A screenshot if it's a UI/rendering issue.
- A diagnostics report (Diagnostics → Copy Report) if it's a behavioural issue.
- The test file used and the exact step number.

### 1.4 Coverage status legend

Each verification item in this guide and in `VERIFICATION_CHECKLIST.md` carries a coverage marker indicating whether (and how) it has been automated. The marker tells you whether a human still has to run the check before sign-off, or whether an automated test already protects the surface.

| Marker | Meaning | Pre-release human action |
|---|---|---|
| **`[Coverage: WIDGET]`** | Covered by a `flutter_test` widget or unit test that wires the full Riverpod `ProviderScope` (option B in the test taxonomy). The Pro CI suite running these tests is sufficient regression protection. | Skip during sign-off unless the test file changed. |
| **`[Coverage: INTEGRATION_TEST]`** | Covered by a Flutter `integration_test/` test that exercises a fully running app on a real device or simulator (option A). Run as part of the platform-smoke matrix. | Skip per platform once the integration_test job is green for that platform. |
| **`[Coverage: INTEGRATION_TEST — pending]`** | Best automated as a Flutter `integration_test/` (option A), but not yet implemented. Tracked in `integration_test/PENDING.md`. | **Run manually until the test lands.** |
| **`[Coverage: WIDGET — pending]`** | Could be covered by a widget test with full provider scope but is not yet implemented. Tracked in `integration_test/PENDING.md`. | **Run manually until the test lands.** |
| **`[Coverage: MANUAL]`** | Inherently requires human judgement — UX feel, visual polish, cross-OS share-sheet behavior, accessibility-tool interaction, performance perception, app store review compliance, etc. Will not be automated. | **Always run during sign-off.** |
| **`[Coverage: HYBRID]`** | A mix — direction/threshold/format is automated but the absolute value (e.g. memory MB, FPS) requires human judgement under realistic load. | **Run manually for the human-judgement portion.** |

Markers may be appended to either the bullet in the checklist, the row in an Automation Assessment table, or after a step description in the guide. When a test file is referenced, the path is relative to the repo root (e.g. `test/features/decoders/widgets/decoder_picker_dialog_test.dart`).

---

## 2. Test data and fixture setup

### 2.1 Prerequisites

- WaveCrux running in debug or profile build (so the diagnostics panel is always available).
- **Icarus Verilog** installed (`iverilog` and `vvp` on `$PATH`) — only needed if you regenerate fixtures.
- **Python 3** — only needed for stress-log generation.
- **A second terminal** for streaming-pipe and remote-control tests.

### 2.2 Fixture inventory

All fixtures live under `verification/fixtures/` and are committed to the repo. The complete inventory:

| Folder | Purpose |
|---|---|
| `vcd/scalar_basics.vcd` | 1-bit signals with all four states (0, 1, x, z); transitions; glitches |
| `vcd/vector_formats.vcd` | Multi-bit buses 1/4/8/16/32/64 with x/z in partial nibbles |
| `vcd/analog_real.vcd` | Real-valued signals: negative, zero, very small, very large |
| `vcd/deep_hierarchy.vcd` | 10+ levels of nested scopes; duplicate names at different scopes |
| `vcd/direction_test.vcd` | Mixed wire/reg signals across nested scopes. **Note:** despite the name, VCD carries no port direction — every signal parses as `Unknown`. Exercises the *graceful-empty* direction path, not positive direction filtering. (See §4 — a direction-bearing FST/GHW fixture is still needed for positive manual verification.) |
| `vcd/xtrace.vcd` | Cross-probe / X-trace seed VCD used by the CXP server + cross-probe panel tests (§22.12) |
| `vcd/parameter_multiselect.vcd` + `.expected.json` | HDL parameters (`WIDTH`=8, `DEPTH`=32) + a plain real signal (`freq_mhz`, no badge) + SPI-named signals in a child scope. Backs §4A: inline parameter-value badges, hierarchy multi-select, and apply-decoder-to-selection with auto-bind prefill |
| `vcd/<*.expected.json>` | Companion known-answer JSON for each VCD above |
| `protocol/spi/generated/spi_basic.vcd` + `.expected_transactions.json` | SPI: two simple Mode-0 transactions (legacy fixture; backs the hardcoded unit-test arrays) |
| `protocol/spi/spi_mode{0,1,2,3}.vcd` + `.expected_transactions.json` | SPI: one fixture per CPOL/CPHA mode — two transactions each (1-byte + 2-byte) |
| `protocol/spi/generated/spi_glitch.vcd` + `.expected_transactions.json` | SPI: Mode-0 with one MOSI change exactly on a sample edge — decoder flags `isError: true` with "MOSI changes at sample edge t=…" |
| `protocol/i2c/generated/i2c_basic.vcd` + `.expected_transactions.json` | I²C: legacy two-transaction fixture (write `0x55` to `0x48` ACK; address-NACK to `0x20`) |
| `protocol/i2c/generated/i2c_full.vcd` + `.expected_transactions.json` | I²C: write ACK, read with final NACK (normal), address-NACK error, and a repeated-START write→read pair (5 transactions) |
| `protocol/uart/generated/uart_basic.vcd` + `.expected_transactions.json` | UART: TX "Hi" (clean), TX "U" (framing error), RX "OK" — at 1 Mbaud, no parity |
| `protocol/uart/generated/uart_parity.vcd` + `.expected_transactions.json` | UART: TX 'A' (even-parity correct) + TX 'B' (even-parity deliberately flipped — decoder reports "Parity error") |
| `protocol/axi4lite/generated/axi4lite_basic.vcd` + `.expected_transactions.json` | AXI4-Lite reads/writes plus error responses |
| `protocol/apb/generated/apb_basic.vcd` + `.expected_transactions.json` | APB IDLE→SETUP→ACCESS state machine, wait state, PSLVERR |
| `protocol/wishbone/generated/wishbone_b3_classic_basic.vcd` + `.expected_transactions.json` | Wishbone B3 Classic — single-cycle reads/writes |
| `protocol/wishbone/generated/wishbone_b3_classic_violations.vcd` + `.expected_transactions.json` | Wishbone B3 Classic — protocol violations (ACK without CYC/STB, ERR/RTY) |
| `protocol/wishbone/generated/wishbone_b3_burst_incr.vcd` + `.expected_transactions.json` | Wishbone B3 — incrementing burst transfers (CTI=010, BTE=00) |
| `protocol/wishbone/generated/wishbone_b3_burst_wrap.vcd` + `.expected_transactions.json` | Wishbone B3 — wrap-burst transfers (CTI=010, BTE=01/10/11) |
| `protocol/wishbone/generated/wishbone_b4_pipelined_basic.vcd` + `.expected_transactions.json` | Wishbone B4 Pipelined — back-to-back STB with no STALL |
| `protocol/wishbone/generated/wishbone_b4_pipelined_stall.vcd` + `.expected_transactions.json` | Wishbone B4 Pipelined — STALL backpressure handling |
| `protocol/wishbone/generated/wishbone_b4_pipelined_violations.vcd` + `.expected_transactions.json` | Wishbone B4 Pipelined — protocol violation detection |
| `protocol/ahb_lite/generated/ahb_lite_single_basic.vcd` + `.expected_transactions.json` | AHB-Lite — single (non-burst) NONSEQ transfers |
| `protocol/ahb_lite/generated/ahb_lite_incr_burst.vcd` + `.expected_transactions.json` | AHB-Lite — INCR burst (NONSEQ → SEQ chain) |
| `protocol/ahb_lite/generated/ahb_lite_incr_undefined.vcd` + `.expected_transactions.json` | AHB-Lite — INCR undefined-length burst |
| `protocol/ahb_lite/generated/ahb_lite_wrap_burst.vcd` + `.expected_transactions.json` | AHB-Lite — WRAP4/WRAP8/WRAP16 burst |
| `protocol/ahb_lite/generated/ahb_lite_wait_states.vcd` + `.expected_transactions.json` | AHB-Lite — HREADY low for multi-cycle wait states |
| `protocol/ahb_lite/generated/ahb_lite_error_response.vcd` + `.expected_transactions.json` | AHB-Lite — two-cycle ERROR response (HRESP=1) |
| `protocol/ahb_lite/generated/ahb_lite_locked_transfer.vcd` + `.expected_transactions.json` | AHB-Lite — HMASTLOCK held high across a transfer pair |
| `protocol/ahb_lite/generated/ahb_lite_violations.vcd` + `.expected_transactions.json` | AHB-Lite — protocol violations (illegal HTRANS, HBURST mismatch) |
| `protocol/spi_flash/generated/spi_flash_rdid.vcd` + `.expected_transactions.json` | SPI flash — RDID (0x9F) JEDEC ID readback |
| `protocol/spi_flash/generated/spi_flash_rdsr.vcd` + `.expected_transactions.json` | SPI flash — RDSR (0x05) status register read |
| `protocol/spi_flash/generated/spi_flash_read.vcd` + `.expected_transactions.json` | SPI flash — READ (0x03) single-byte / multi-byte reads |
| `protocol/spi_flash/generated/spi_flash_fast_read.vcd` + `.expected_transactions.json` | SPI flash — FAST_READ (0x0B) with dummy byte |
| `protocol/spi_flash/generated/spi_flash_wren_pp.vcd` + `.expected_transactions.json` | SPI flash — WREN (0x06) + PAGE_PROGRAM (0x02) sequence |
| `protocol/spi_flash/generated/spi_flash_wren_se.vcd` + `.expected_transactions.json` | SPI flash — WREN (0x06) + SECTOR_ERASE (0x20) sequence |
| `protocol/spi_flash/generated/spi_flash_wel_violation.vcd` + `.expected_transactions.json` | SPI flash — WEL violation (PP/SE attempted without preceding WREN) |
| `protocol/riscv/generated/riscv_rv32i_basic.vcd` + `.expected_transactions.json` | RISC-V RV32I — basic instruction trace (loads/stores/branches) |
| `protocol/riscv/generated/riscv_rv32im_arith.vcd` + `.expected_transactions.json` | RISC-V RV32IM — arithmetic + M-extension (mul/div) trace |
| `protocol/riscv/generated/riscv_rv64i_basic.vcd` + `.expected_transactions.json` | RISC-V RV64I — 64-bit instruction trace |
| `protocol/riscv/generated/riscv_pc_present.vcd` + `.expected_transactions.json` | RISC-V — PC-present trace mode (separate PC signal binding) |
| `protocol/riscv/generated/riscv_rvfi_retire.vcd` + `.expected_retire_stream.json` | RISC-V — full riscv-formal RVFI channel bundle for a single-issue in-order core; known-good retire stream for the `lib/services/riscv/` trace substrate (includes back-to-back retirements under one `rvfi_valid` pulse, a store, a load, an x0 write, a taken branch, and a trapping `ecall`) |
| `protocol/riscv/captured/riscv_picorv32_wb_ez.fst` + `.fixture.json` + `.expected_transactions.json` | RISC-V — **captured** RV32I instruction-fetch trace off YosysHQ's `picorv32_wb` (ISC), built with iverilog from a vendored core; §5.9.9 |
| `protocol/riscv/captured/riscv_ibex_rvfi_trap.fst` + `.fixture.json` + `.expected_transactions.json` | RISC-V — **captured** real-core RVFI retire stream off lowRISC's `ibex_top` (Apache-2.0, commit `3250d994`), built with Verilator 5.050 and `+define+RVFI`. 26 retirements over arithmetic, word/byte/halfword load-store pairs, a taken forward `beq`, a backward `bne` loop and a trapping `ecall`. The only fixture in the corpus whose signal names, hierarchy and retirement timing were not chosen by us; §10B.1.10 |
| `test/fixtures/gtkw/generated/*.gtkw`, `…/fixture.vcd`, `…/sample_filter.txt` | GTKWave session-import fixtures (synthetic) + golden snapshots |
| `test/fixtures/gtkw/captured/*.gtkw` | Real GTKWave saves from public projects (Apache/MIT/BSD), with `PROVENANCE.md` |
| `cocotb/basic_log.txt`, `cocotb/edge_cases_log.txt` | Cocotb log correlation fixtures |
| `stage/stage_demo.vcd` | Stage built-in widget exercise file |
| `stage/boards/<board>/<board>_demo_per_bit.vcd` | Per-board out-of-box demo — individual per-bit slot signals (basys3, nexys_a7, de10_lite, arty_a7) |
| `stage/boards/<board>/<board>_demo_vector.vcd` | Per-board out-of-box demo — packed `leds`/`sws` vector buses (fan-out tier) |
| `helpers/README.md` | Bash streaming generator + stress-data instructions |

#### 2.2.1 Malformed-file error messaging

When the parser (wellen) rejects a file, the viewer's error overlay must show **wellen's own reason** beneath the localized "couldn't load" title — not a generic "Failed to open file". The reason is the parser's English text (e.g. for a bad scalar value-change, *"expected an id for a value change"*), surfaced verbatim so an HDL engineer can find the defect in their VCD/FST.

**Steps.** Open a malformed VCD — the committed unit fixture `test/fixtures/vcd/malformed_value_change.vcd` (a scalar change `0 !` written value-SPACE-id, which is invalid) is a ready example. The canvas-centre error overlay shows the localized title (`waveformCenterLoadError`) and, below it, the wellen reason with **no** `Exception:` prefix.

**How it works.** The Rust `wellen_open` stashes `simple::read`'s error in a thread-local; `wellen_last_open_error()` (handle-free) returns it; the FFI isolate forwards it and the provider throws a typed `WaveformOpenException(reason)` whose `toString()` is the bare reason. The error UI already renders `error.toString()` under the title.

**Platform note.** Desktop (macOS/Linux/Windows) and Android rebuild `libwellen_ffi` automatically as part of the Flutter build (CMake / Xcode / gradle cargo steps). **iOS links the committed `WellenFFI.xcframework`** — rebuild it with `scripts/build_ios.sh` whenever the FFI surface changes, or the new symbol is missing on iOS.

**Web (WASM)** carries the reason too: the `wellen_wasm` Rust crate already throws a `JsError` with wellen's message (`map_err(into_js_err)`); `WellenWasmProvider.openBytes` catches it and rethrows the same `WaveformOpenException`. Dart-only change, no wasm rebuild. It can't be exercised headlessly — the bare `flutter test --platform chrome` harness doesn't load the wasm module — so verify it **manually in a browser build**: drag a malformed VCD onto the web app and confirm the reason shows under the load-error title.

**Automation Assessment.**

| Test | Coverage |
|---|---|
| `wellen_open` captures the reason; `wellen_last_open_error` returns it; cleared on success | **UNIT (Rust)** (`native/wellen_ffi/src/lib.rs` — `test_open_error_message_on_malformed_vcd`, `test_open_error_cleared_after_success`) |
| Malformed VCD → `WaveformOpenException` with wellen's reason (not the generic fallback), clean `toString()` | **UNIT (Dart, real FFI)** (`test/features/viewer/providers/waveform_source_provider_open_test.dart` — "a malformed VCD surfaces wellen's reason") |
| Reason shown in the canvas-centre error overlay | **MANUAL** (open the malformed fixture) |

### 2.3 Baseline diagnostics report

Before starting any verification cycle, open `protocol/spi/generated/spi_basic.vcd` and capture a diagnostics report via **Diagnostics → Copy Report**. Save it as `baseline_report_<release>.txt` alongside the release artifacts. Every test that captures a diagnostics report references this baseline to detect regressions.

---

## 3. Diagnostics panel

> **Verify diagnostics first.** Once you're comfortable with the diagnostics tabs, you use them as instruments during the rest of testing. Every later section in this document references diagnostics checks.

### 3.1 What it does

The diagnostics surfaces expose the engine internals — file metadata, parser performance, memory usage, render statistics, signal-health analysis, and a synthetic VCD generator. The legacy single tabbed dialog is split into three surfaces (Tab Diagnostics drawer, App Diagnostics dialog, Pane Render Stats popover) and moved the synthetic generator to `Tools → Generate Test VCD…`. In debug and profile builds the surfaces are always available; in release builds they are opt-in via Settings → Advanced.

### 3.2 Setup

- Debug or profile build.
- Any VCD (e.g., `protocol/spi/generated/spi_basic.vcd`).

### 3.3 Steps and expected behavior

#### 3.3.1 Access affordances

The legacy single diagnostics dialog is split into three independent surfaces, each with its own access path:

- **App Diagnostics dialog** (process-wide, modal):
  - The toolbar **bug icon** in the main viewer toolbar opens this surface specifically.
  - `Tools → App Diagnostics…` menu entry.
  - Command palette (`Ctrl/Cmd+Shift+P` → "App Diagnostics").
  - Keyboard shortcut **`Ctrl/Cmd+Shift+M`**.
- **Tab Diagnostics drawer** (per-tab, follows the active tab):
  - Tab context menu → "Tab Diagnostics".
  - Command palette → "Tab Diagnostics".
  - Keyboard shortcut **`Ctrl/Cmd+Shift+I`**.
- **Pane Render Stats popover** (per-pane):
  - The `i`-icon on each pane's tab bar (popover anchor — no menu / palette / shortcut entry).

#### 3.3.2 Surface inventory

> The legacy single seven-tab "Diagnostics panel" dialog is split into three surfaces (§22.10), and the "Parser Backend" section of the Tab Diagnostics drawer is retired. The list below documents what each modern surface owns; the legacy-tab walk-throughs in §3.3.3–§3.3.10 are kept as tombstones with notes pointing at their replacements.

- **Tab Diagnostics drawer** (per-tab — opened from tab context menu / palette / `Cmd/Ctrl+Shift+I`): three sections — **File Info** (file path, size, format, parse time, signal counts, transitions, timescale, signals by direction, signals by type), **Signal Health** (constant signals, X/Z-only signals, detected clocks, glitch counts), **Benchmark This File** (re-parses the active file with a fresh `WellenProvider` and records timing).
- **App Diagnostics dialog** (process-wide — opened from `Tools → App Diagnostics…` / palette / `Cmd/Ctrl+Shift+M`): **Memory** (wellen DB size, loaded signal count, process RSS on desktop, per-tab breakdown table) and **Frame Stats** (current/average/worst frame time, frame budget overruns).
- **Pane Render Stats popover** (per-pane — anchored to each pane's tab-bar `i`-icon): visible signal rows, visible transitions, paint-time breakdown, canvas dimensions, last-frame timestamp.
- **Tools menu**: `Tools → Generate Test VCD…` (synthetic VCD generator — moved out of the legacy diagnostics dialog; controls for signal count, duration, complexity, with a destination picker on save).

#### 3.3.3 Tab Diagnostics drawer — File Info section

1. Load `protocol/spi/generated/spi_basic.vcd`. Open the **Tab Diagnostics drawer** (`Ctrl/Cmd+Shift+I`). Expand the File Info section.
2. Verify it shows: file path, file size in human-readable units (e.g. "1.1 MB"), format ("VCD"), parse time with unit (e.g. "46.3 ms"), signal count, transition count, timescale string. **Values must render fully inside the drawer** with no right-edge clipping — the value column is right-aligned but stays bounded by the drawer's width (Issues 32/33 regression — the legacy 720-dp pin pushed the value column past the drawer's right edge on drawers < 720 dp wide; the drawer now lets panels adapt to its actual width).
3. Scroll the drawer down past "Signals by type". Verify the **"Signals by direction"** section appears. For any VCD (including `vcd/direction_test.vcd`) this shows "Unknown: N" — VCD format records no port direction, so every signal is Unknown. Real Input/Output/Inout counts require an FST or GHW source whose simulator recorded port direction (no such fixture is committed yet — see §4). (Issue 33 regression — the section previously sat below the 320-dp internal-scroll fold and looked absent.)
4. Verify "Signals by type" — wire/reg/integer/real counts.

#### 3.3.4 App Diagnostics dialog — Memory section

1. Open the **App Diagnostics dialog** (`Ctrl/Cmd+Shift+M` or `Tools → App Diagnostics…`). Inspect the Memory section.
2. Load a small file. Note baseline numbers (wellen DB size, loaded signal count, process RSS on desktop).
3. Open `Tools → Generate Test VCD…`, generate a 1000-signal synthetic VCD, load it. Verify the numbers increase proportionally.
4. Add many signals to the canvas. Verify "loaded signal count" increases.
5. Open the **per-tab memory breakdown table** in the same Memory section. Verify each open tab is listed with its individual memory cost.
6. Close the file (or load a different one in the active tab). Verify memory drops back down.

#### 3.3.4a App Diagnostics dialog — Logs section + Log Verbosity

Covers the in-app **Logs** panel (App Diagnostics dialog) and the **Settings → Diagnostics → Log Verbosity** dropdown. Both read the same in-memory ring buffer (`IssueReporterLogBuffer`) that feeds the issue reporter; the buffer always captures **every** level, so this UI never changes what a bug report contains.

1. Open the **App Diagnostics dialog** (`Ctrl/Cmd+Shift+M`) and scroll to the **Logs** section (below Frame Stats). It shows a level-filter dropdown (Quiet / Normal / Detailed / Verbose), Copy and Clear buttons, and a scrolling list of recent log lines (`HH:MM:SS LEVEL logger: message`), newest first, colour-coded by level (SEVERE = error red, WARNING = amber, INFO = default, FINE = muted).
2. **Live update:** trigger a logged event while the dialog is open — e.g. attempt to open a malformed file in another tab's flow, or wait for a background event (auto-save, collab). Confirm new entries appear at the top without reopening the dialog. (The dialog is modal, so drive ambient/background activity; for watch-while-using, use the console at Verbose — see step 6.)
3. **Filter:** set the dropdown to **Quiet** and confirm only WARNING/SEVERE lines remain; set it to **Verbose** and confirm FINE breadcrumbs (e.g. `wavecrux_pro.collab` per-broadcast send errors) appear. The filter is panel-local and defaults to the Settings verbosity.
4. **Copy:** click Copy. The visible (filtered) lines land on the clipboard as plain text; a "Logs copied to clipboard" snackbar confirms.
5. **Clear:** click Clear. The list empties and shows "No log entries at this level." (This clears the shared ring buffer, so a subsequent issue report's Diagnostics → Session log also starts empty.)
6. **Settings → Diagnostics → Log Verbosity:** change the dropdown (default **Normal**). This sets the **console** print threshold (visible in the terminal during `flutter run`) and the Logs panel's default filter. Set it to **Verbose**, reproduce an action, and confirm FINE lines print to the console live. Confirm the choice persists across an app restart.
7. **Report independence:** with verbosity at **Quiet**, file an issue (`Help → Submit Issue`) and confirm the Diagnostics → Session log still contains INFO/FINE lines — proving capture is independent of the display setting.

#### 3.3.5 Pane Render Stats popover (per-pane)

1. Load any file with at least one decoder active so transactions paint.
2. Click the `i`-icon on the active pane's tab bar to open the **Pane Render Stats popover**.
3. Verify these metrics update live:
   - Visible signal rows.
   - Visible transitions (depends on zoom).
   - Paint time breakdown with individual phases listed.
   - Canvas pixel dimensions.
   - Last-frame timestamp.
4. **Interactive test:** zoom in close — visible transitions should decrease. Zoom out — count should increase.
5. Scroll the signal list — visible signal rows should change as items scroll out of view.
6. With a split-pane workspace, open the popover on each pane independently and verify the metrics differ per pane (each pane has its own paint pipeline).

#### 3.3.6 Tab Diagnostics drawer — Signal Health section

1. Load `vcd/scalar_basics.vcd`. Open the **Tab Diagnostics drawer** and expand Signal Health.
2. Verify transitions are counted correctly per signal.
3. Load a synthetic VCD with deliberate undriven wires. Verify they are flagged as "X/Z-only".
4. Load a file containing periodic clocks. Verify clocks are detected with frequency estimates that match the testbench.

#### 3.3.7 Tools menu — Generate Test VCD…

1. Open `Tools → Generate Test VCD…` (moved out of the legacy diagnostics dialog).
2. Configure: 100 signals, 10 ms duration, "medium" complexity. Click Generate and choose a destination via the save dialog.
3. Verify the generated file opens correctly and the signal count matches the configuration.

#### 3.3.8 Tab Diagnostics drawer — Benchmark This File section

1. With a file loaded, open the **Tab Diagnostics drawer** and expand "Benchmark This File". Run the parser benchmark. It should re-parse the current file N times with a fresh `WellenProvider` and report mean/median parse times.
2. Capture results as a baseline for later regression comparisons.
3. **Render benchmark:** `RenderBenchmarkService` exists in `lib/services/diagnostics/` but has no UI dispatch yet — it is invoked from tests only. Nothing to verify here from the UI.

#### 3.3.9 Copy Report — the bug-report payload

Each diagnostics surface exposes its own **Copy Report** button (there is no single FAB):

1. With a complex session open (file loaded, decoder active, signals on canvas), open the **App Diagnostics dialog** (`Ctrl/Cmd+Shift+M`) and click its **Copy Full Diagnostics Report** button. Paste into a text editor.
2. Verify the report contains: header with "WaveCrux Diagnostics Report", timestamp, app version, platform, plus the Memory and Frame Stats fields.
3. Repeat with the Tab Diagnostics drawer's per-tab Copy action — verify it includes File Info, Signal Health, and any captured benchmark numbers for the active tab.
4. Verify formatting in both surfaces: byte sizes are human-readable (MB, not raw bytes); times are formatted (ms, not raw ns); the report is clean enough to paste into a GitHub issue.

#### 3.3.10 Provider override — REMOVED

> The "Force Dart" / "Force Wellen" override and the surrounding `ProviderOverridePanel` were retired when the dual-parser model was simplified to one backend per platform (FFI on desktop/mobile, WASM on web). Nothing to verify in this section; left as a tombstone so a reviewer searching for the old "provider override" workflow finds the explanation.

### 3.4 Diagnostics-assisted verification baseline

After verifying diagnostics works, capture one fresh diagnostics report per major fixture (`spi_basic.vcd`, `apb_basic.vcd`, etc.) and save them as named baselines (`spi_baseline_report.txt`, etc.). These are referenced throughout this document.

### 3.5 Edge cases / break-it tests

- Open the diagnostics panel **before** any file is loaded. Tabs should render gracefully with empty/zero values, not exceptions.
- Run benchmarks with no file loaded — should be disabled or show "no file" state, not crash.

### 3.6 Automation Assessment

| Test | Coverage | Rationale |
|---|---|---|
| Tab inventory and switchability | **WIDGET** (`test/features/diagnostics/widgets/`) | Per-tab widget tests cover tab presence and switch behavior. |
| File Info field population for known fixtures | **WIDGET** (`test/features/diagnostics/widgets/file_info_panel_test.dart` + `test/services/diagnostics/`) | Known-answer test: load `spi_basic.vcd`, assert signal count and transition count. High value as regression catch. |
| Memory tab values increase/decrease appropriately | **HYBRID** (`test/features/diagnostics/widgets/memory_stats_panel_test.dart` covers presentation; absolute MB values remain MANUAL) | Direction (increase/decrease) is automatable; absolute values are flaky in CI. |
| Render tab updates during scroll/zoom | **HYBRID** (`test/features/diagnostics/widgets/pane_render_stats_popover_test.dart` + `render_stats_collector_test.dart` cover counters; perceptual liveness during scroll/zoom remains MANUAL) | Visual responsiveness is hard to assert reliably. |
| Signal Health flags match known fixtures | **WIDGET** (`test/features/diagnostics/widgets/signal_health_panel_test.dart` + service-side tests) | Known-answer regression catch. |
| Copy Report content correctness | **WIDGET** (`test/services/diagnostics/app_diagnostics_report_service_test.dart`, `tab_diagnostics_report_service_test.dart`) | Format and presence of fields are easy to assert. |
| Diagnostics panel discovery affordances | **MANUAL** | Discoverability is a UX judgement. |

---

## 4. Signal search and direction filtering

### 4.1 What it does

The signal search dialog lets you find signals by name, scope path, type (wire/reg/integer/real), and **direction** (input/output/inout) before adding them to the canvas. Direction filtering uses GTKWave-compatible prefix syntax (`+I+`, `+O+`, `+IO+`) that engineers migrating from GTKWave already know.

> **IMPORTANT — no direction-bearing fixture exists yet.** VCD format records
> **no** port direction; every signal parsed from a VCD is `Unknown`. The
> `vcd/direction_test.vcd` fixture (and its `vcd2fst`-generated FST mirror) are
> therefore **all-Unknown** — confirmed by `direction_test.expected.json`
> (`"direction": "unknown"` for every signal). So the manual steps below
> verify the **graceful-empty** direction path (chips and `+I+/+O+` prefixes
> correctly return nothing, no crash), **not** positive direction filtering.
> The positive path — Input/Output/Inout actually selecting signals — is fully
> covered by unit tests against synthetic variables
> (`test/services/signal_query/signal_search_service_test.dart`). Promoting
> steps 4–8 to positive manual verification is **blocked on committing a real
> direction-bearing FST or GHW fixture** (one whose simulator recorded port
> direction — `vcd2fst` cannot synthesise it). Tracked as a fixture-backlog
> item.

### 4.2 Setup

- `vcd/direction_test.vcd` (mixed wire/reg across nested scopes; **all signals parse as `Unknown` direction** — see note above). Signal names: `clk`, `valid`, `data_out[7:0]`, `data_in[7:0]`, `bidir_bus[3:0]`, `reset_n`.
- `protocol/spi/generated/spi_basic.vcd` (a plain VCD with no direction metadata — second graceful-behavior fixture).

### 4.3 Steps and expected behavior

1. Load `vcd/direction_test.vcd`. Open the search dialog.
2. With an empty search box, verify the full list of signals shows.
3. Test glob mode toggle: enter `*` in glob mode → all signals match. In substring mode, `*` is a literal character that matches nothing (the dialog shows the empty state — see step 6a). **Mode (Glob/Substring) governs only how the *name* part of the query matches; it has no effect on the type/direction chips or on the `+I+/+O+` prefixes.**
4. Click the **Input** filter chip — verify it returns **empty** (no signal in this VCD has a known direction). **Expected**, per the note above. Same for **Output** (step 5) and **Inout** (step 6).
5. (See step 4 — Output chip returns empty.)
6. (See step 4 — Inout chip returns empty.)
6a. With every result hidden (e.g. substring `*`, or an active direction chip), confirm the dialog shows the centered "No signals match your search" message **without changing size** — the results region holds a fixed height whether populated or empty (regression: the empty state previously ballooned the dialog to full height).
7. Click **Wire** and **Reg** — verify type filtering works (this *is* recorded in VCD: `valid`, `data_out`, `bidir_bus` are wires; `clk`, `data_in`, `reset_n` are regs in the top scope).
8. Test prefix syntax against real signal names: `+I+clk` strips the `+I+` prefix, substring-matches `clk`, then applies the input-direction filter → returns **empty** (because `clk`'s direction is Unknown). This confirms the prefix is parsed and applied; it cannot select until a direction-bearing fixture lands. (The prefix *parsing + filtering* logic is unit-tested both ways in `signal_search_service_test.dart`.)
9. Now load `protocol/spi/generated/spi_basic.vcd` (a second plain VCD with no direction metadata).
10. Click Input/Output/Inout chips — verify they all return empty results gracefully (no error). Same root cause: VCD records no direction.
11. Verify File Info shows "Signals by direction: Unknown: N" for both VCDs.
12. **FST alias multi-select.** Open an FST whose hierarchy aliases one net
    into several scopes (a net wired through ports appears in every scope it
    crosses, all sharing one wellen signalRef — e.g. a Wishbone `wb_cyc_i`
    seen at both the testbench and the slave level). Search for that name so
    two or more alias rows are listed, then tick the checkbox on exactly one.
    Verify only that row's checkbox turns on, the action button reads "Add 1
    Signal", and pressing it adds exactly one signal. Selection is keyed by
    full hierarchical path (row identity), matching the hierarchy tree; a
    ref-keyed selection ticked every alias at once and bulk-added all of them.

### 4.4 Diagnostics-assisted verification

- File Info → "Signals by direction" should reconcile with the chip behavior. For these VCD fixtures it reports "Unknown: N", and correspondingly the Input/Output/Inout chips all return empty. (Once a direction-bearing FST/GHW fixture is committed, File Info's non-zero Input/Output/Inout counts must match the per-chip result counts.)

### 4.5 Edge cases

- Empty search box + filter chip — should narrow without requiring text (here: to empty, since direction is Unknown).
- Combine type filter (Wire) and direction filter (Input) — should show wires that are inputs (empty for these fixtures; non-empty once a direction fixture lands).
- Search for a term that doesn't exist — empty state, not error, and the dialog does not resize (see step 6a).

### 4.6 Automation Assessment

| Test | Coverage | Rationale |
|---|---|---|
| Direction filtering selects correct signals (positive path) | **WIDGET** (`test/services/signal_query/signal_search_service_test.dart` against synthetic direction-tagged variables) | No direction-bearing parser fixture exists; synthetic vars exercise the filter logic with exact known-answer counts. |
| Direction chips return empty on direction-less source without crash | **WIDGET** (`test/services/signal_query/signal_search_service_test.dart` — empty-direction-set case) | Critical regression catch — matches the manual graceful path. |
| Prefix syntax (`+I+`/`+O+`/`+IO+`) parses and applies | **WIDGET** (`test/services/signal_query/signal_search_service_test.dart`) | Easy assertions on filtered list. |
| Glob vs substring mode toggle works | **WIDGET** (`test/features/search/widgets/signal_search_dialog_test.dart`) | UI state assertion. |
| Dialog holds fixed size across empty/populated results | **WIDGET** (`test/features/search/widgets/signal_search_dialog_test.dart` — "results region keeps a fixed height when empty") | Regression for the empty-state balloon bug. |
| FST alias rows select independently; "Add N" adds only the ticked row | **WIDGET** (`test/features/search/widgets/signal_search_dialog_test.dart` — "checking one FST alias row leaves its siblings unchecked" + "Add Selected adds only the checked alias") | Two rows sharing one signalRef is the exact FST aliasing shape; ref-keyed selection conflated them. |
| Direction filtering through the parser (end-to-end) | **MANUAL (blocked)** — needs a committed direction-bearing FST/GHW fixture | Backlog item; promote steps 4–8 to positive verification when it lands. |

---

## 4A. Signal hierarchy tree — multi-select, parameter values, apply-decoder-to-selection

### 4A.1 What it does

Three hierarchy-tree (SST panel) behaviors added on beta feedback:

1. **Inline parameter values.** Leaves whose dump declares them as HDL parameters (`VarType.parameter` / `realParameter`) show their constant value directly in the row (`WIDTH  = 8  [7:0]`), read lazily via `loadSignal` + `valueAt(startTime)` — the parameter is never added to the timeline by displaying it. Values format as unsigned decimal; real parameters pass through (e.g. `3.14`).
2. **Multi-select → bulk add.** Ctrl/Cmd+click toggles row selection (existing); **Shift+click now selects the visible range** between the last interaction and the clicked row. The context menu on any selected row (when ≥ 2 rows are selected) gains **"Add N Selected to Viewer"**, which adds the selection in tree order via the existing batch API.
3. **Apply decoder to selection.** The same context menu gains **"Apply Decoder to Selection…"**, which opens the decoder picker scoped to only the selected signals; on decoder choice the config dialog opens with its binding dropdowns restricted to the selection **and pre-filled by the auto-bind name heuristic** (same five-tier engine as the config dialog's Auto-bind button — see §5.1). Unresolvable bindings stay empty and required-binding validation still gates Apply.

### 4A.2 Setup

- Load `vcd/parameter_multiselect.vcd` (see §2.2). Hierarchy: `top` (parameters `WIDTH`, `DEPTH`, real `freq_mhz`) → `top.spi` (`sclk`, `mosi`, `miso`, `cs`).

### 4A.3 Steps and expected behavior

1. Expand `top`. Verify `WIDTH` shows an inline `= 8` badge and `DEPTH` shows `= 32`, both without either signal appearing in the viewer's signal list. `freq_mhz` shows **no** value badge (it is a plain real signal, not a parameter — VCD cannot mark real parameters).
2. Right-click `WIDTH` — the context menu's first row is a non-interactive monospace header `WIDTH = 8` (the truncation-reveal counterpart of the badge; on very long values the badge ellipsizes at ~120 dp and this header shows the full value).
3. Expand `top.spi`. Ctrl/Cmd+click `sclk` — row highlights, nothing is added to the viewer. Shift+click `cs` — `sclk`, `mosi`, `miso`, `cs` all highlight (visible range). Shift+click `mosi` — range shrinks to `sclk`…`mosi` (anchor stays at `sclk`).
4. Plain-click any row — that signal is added to the viewer AND the row becomes the (single) highlighted selection, so the click has visible local feedback and the Shift+click range anchor is on-screen. A Shift+click afterwards ranges from that row.
5. Select `sclk`…`cs` again (4 rows). Right-click a **selected** row: verify **"Add 4 Selected to Viewer"** and **"Apply Decoder to Selection…"** appear. Right-click an **unselected** row (e.g. `WIDTH`): verify neither bulk item appears.
6. Tap "Add 4 Selected to Viewer" — all four land in the viewer in tree order (sclk, mosi, miso, cs), each with a distinct auto-assigned color.
6a. **Idempotent bulk add.** Plain-tap `sclk` (it is added to the viewer), then Shift+click `cs` (range-selects sclk…cs, 4 rows), then "Add 4 Selected to Viewer": `sclk` is **not** duplicated — only mosi/miso/cs are appended, and `sclk` appears exactly once. The menu label still reads the selection count (4), matching the highlighted rows. Deliberate duplicates of one signal (e.g. two rows with different radixes) remain possible via repeated single-tap, which does not dedupe.
7. Re-select the four SPI signals; tap "Apply Decoder to Selection…". The decoder picker opens normally (all categories). Pick **SPI**: the config dialog opens with SCLK/MOSI/MISO/CS **already bound** to `top.spi.*` (exact-suffix auto-bind) and every binding dropdown lists **only the four selected signals**. Apply — the decoder activates and transactions decode.
8. Repeat step 7 but select only `sclk` and `mosi` before applying. In the SPI config dialog, `sclk`/`mosi` pre-fill; `miso`/`cs` stay unbound (optional — Apply still allowed). The dropdowns offer only the two selected signals.
9. Search-filter interaction: type `s` in the tree search box, then Shift+click across the filtered rows — the range covers only **visible** (filtered) rows.
10. Collapse `top.spi` with rows still selected, right-click a selected-but-hidden state is impossible (rows are hidden); re-expand — selection persists.

### 4A.4 Diagnostics-assisted verification

- After step 1, open Tab Diagnostics → Memory: the parameter signals appear as loaded (single-change) signals; total decompressed count rises by 2 without any viewer rows added.

### 4A.5 Edge cases

- File with **no** parameters: no badges anywhere, no errors.
- Simulators that dump parameters as plain `wire`/`reg`: indistinguishable from signals — no badge (document, don't fix; the dump lacks the type).
- Shift+click with no prior interaction: selects only the clicked row.
- Shift+click after the anchor's scope was collapsed: falls back to selecting only the clicked row.
- "Add N Selected to Viewer" with every selected signal already displayed: the action is a no-op (menu item still shown; nothing appended, nothing duplicated).
- "Apply Decoder to Selection…" with a selection matching no decoder channel names: config dialog opens with all bindings empty; required-binding validation blocks Apply as usual.
- Tier-gated (PRO/ENT) decoders picked from the selection-scoped picker still show tier badges and route through the same feature gate as the toolbar flow (`kBetaPeriod` short-circuit during beta; upgrade dialog post-beta — see §5.1 and the Pro guide).
- **Natural (alphanumeric) sort (0.2.6).** The hierarchy sorts scopes and variables naturally: digit runs compare numerically, so bit-blasted gate-level names list `[0] [1] [2] … [10] [11]` instead of the dump's `[0] [1] [10] [11] [2]` (requested by the wellen author against the GF180 netlist). Sorting happens once at hierarchy build, so the rendered rows, Shift+click ranges, and bulk-add order always agree; escaped-identifier twins keep their dump order relative to each other (stable sort). **Settings → Waveform Defaults → "Sort hierarchy alphanumerically"** toggles it (default ON); turning it off restores the file's declaration order live, without reloading. Verify both states on a gate-level FST and confirm a bulk "Add Selected" lands in the on-screen order in both. `[Coverage: UNIT]` (`natural_compare_test.dart`, `hierarchy_natural_sort_test.dart` — both toggle states, instance identity, twin stability) + **WIDGET** (`settings_screen_test.dart` — toggle default + persistence).
- **FST signal aliasing (0.2.3 regression fix).** FST dumps report a net wired through ports as *multiple hierarchy rows sharing one signal ref* (e.g. `wb_stream_reader_tb.clk` and `…wb_ram0.wb_clk_i` are the same signal). Selection is keyed by the row's **full path**, so: selecting a row in one scope must **not** highlight its aliases in other scopes, and "Apply Decoder to Selection…" must list **the names from the scope the user clicked** — never an alias's name from elsewhere in the hierarchy (the original defect: wrong-scope names + auto-bind matching nothing). Verify with an FST that aliases signals across scopes (a Wishbone testbench like fusesoc `wb_streamer`'s `wb_stream_reader_tb.fst` is ideal): expand two scopes sharing nets, select 4–5 pins in ONE scope, apply a Wishbone-shaped decoder, and confirm the config dialog shows exactly the clicked scope's pin names with auto-bind filled.

### 4A.6 Automation Assessment

| Test | Coverage | Rationale |
|---|---|---|
| Parameter badge renders value; no badge without source / for non-parameters | **WIDGET** (`test/features/signal_tree/widgets/variable_tree_leaf_test.dart` — "parameter value badge" group) | Deterministic with mocked source. |
| `parameterValue` provider: load + valueAt(startTime), decimal format, real passthrough, null paths | **UNIT** (`test/features/signal_tree/providers/parameter_value_provider_test.dart`) | Pure provider logic. |
| Tree-order flattening (expansion, search, child-scopes-before-variables) | **UNIT** (`test/features/signal_tree/utils/variable_tree_order_test.dart`) | Pure function, known answers. |
| Shift+click range / anchor semantics | **UNIT** (`signal_tree_providers_test.dart` — "selectRangeTo" group) + **WIDGET** (leaf test "multi-selection gestures") | Real key events drive HardwareKeyboard in widget test. |
| Bulk context-menu items appear only for ≥2 selected incl. row; add-in-tree-order; picker scoped to subset with autoBind | **WIDGET** (leaf test "multi-selection context menu" group, incl. en/zh_CN/ja/ko sweep) | Full gesture-to-provider assertions. |
| Bulk add skips already-displayed signals (tap → range → add doesn't duplicate); `displayedSignalRefs` recursion | **WIDGET** (leaf test — "skips signals already on the canvas") + **UNIT** (`test/domain/models/signal_group_test.dart` — displayedSignalRefs group) | The exact beta-reported flow, gesture-driven. |
| Auto-bind prefill on open (confident bindings pre-filled, unresolved left empty, off by default) | **WIDGET** (`test/features/decoders/widgets/decoder_config_dialog_prefill_test.dart`) | Deterministic against synthetic signal maps. |
| FST aliasing: alias rows selectable independently; decoder subset carries the clicked scope's Variables; path-keyed map keeps aliases distinct | **WIDGET** (leaf test — "FST alias regression (wb_streamer report)" group) + **UNIT** (`signal_variables_map_provider_test.dart` — alias group) | Synthetic two-scopes-one-ref hierarchy reproduces the wellen FST alias shape deterministically. |
| End-to-end: fixture load → badges → select → apply SPI → transactions decode | **MANUAL** (this section) / integration-test candidate | Crosses file open + FFI + three dialogs; good future integration test. |

### 4A.7 Scope-row click latency — expand/collapse is instant

#### What it does

Clicking a scope header in the hierarchy tree expands or collapses it **immediately**, on the frame the mouse button is released. It used to take ~300 ms: the row registered a double-tap handler that ran the identical toggle, and a double-tap recognizer holds the gesture arena open for `kDoubleTapTimeout` before a single tap is allowed to win it. Every single click on the most-used control in the app paid that delay for a double-click that did nothing extra. The double-tap handler is gone.

#### Steps and expected behavior

1. Load any file with nested scopes (`vcd/parameter_multiselect.vcd` is enough; a gate-level FST is the more convincing test).
2. Single-click a collapsed scope header. The arrow flips and the children appear with **no perceptible pause** — it should feel like the tree moved under your finger, not after it. Click it again: collapses just as fast.
3. Click rapidly down a column of scope headers. Every click registers; none is swallowed.
4. **Double-click a scope header.** Expected: it toggles **twice** — expands, then collapses (net: unchanged). This is the deliberate trade-off; a double-click is a rare gesture on a click-to-toggle tree and paying ~300 ms on every single click to make it toggle once was the wrong trade.
5. Right-click a scope header — "Add All in Scope" still opens instantly (right-click was never affected; it never entered the tap arena).
6. On touch (iPad / phone): flick-scroll the tree starting **on a scope header**. The scroll must start and the scope must **not** expand — expansion still fires on release-without-drag, never on press. This is why the tree keeps `onTap` rather than the pointer-down treatment used for Stage tabs (§10.3.1) — a press-to-expand on a gate-level scope would fire an expensive frame on every scroll attempt.

#### Edge cases

- Scope with no children and no variables: clicking it does nothing (no arrow, no state change).
- Click, then drag off the row before releasing: no toggle (drag-to-cancel preserved).

#### Automation Assessment

| Test | Coverage | Rationale |
|---|---|---|
| Tap toggles expansion on the **first frame** after the tap, with no clock advance (both directions, arrow icon flips) | **WIDGET** (`test/features/signal_tree/widgets/scope_tree_node_test.dart` — "toggles expansion on the very next frame") | The assertion must not advance the clock; a `pump(500 ms)` hides the defect entirely. Verified to fail against the pre-fix widget. |
| Row registers no double-tap recognizer (structural guard) | **WIDGET** (same file — "the row registers no double-tap recognizer") | Cheap guard against the pattern being reintroduced. |
| Two taps inside the double-tap window both toggle (documents the trade-off) | **WIDGET** (same file — "two taps inside the double-tap window both toggle") | Pins the deliberate behavior change so it cannot regress silently. |
| Empty scope: tap is a no-op | **WIDGET** (same file — "tap on an empty scope does not expand it") | Deterministic. |
| Touch flick-scroll starting on a scope header does not expand | **MANUAL** (step 6) | Needs a real scroll gesture on a real touch host; good integration-test candidate. |

### 4A.8 Signal tree from the keyboard and a screen reader

#### What it does

The hierarchy tree is operable without a mouse. Before this, its rows were plain click targets: Tab skipped them, a screen reader could not reach a signal, and the only keyboard route to adding one was Ctrl+F. An external NVDA pass reported it as the main gap in the viewer.

- **One Tab stop.** Tab from the search field lands on the tree; the next Tab leaves it. Tabbing back returns to the row the keyboard (or the last click) was on.
- **Tree keys.** Up / Down move between visible rows; Home / End go to the first / last row; Page Up / Page Down move a screenful. Right expands a collapsed scope, or moves into an expanded one. Left collapses an expanded scope, or moves to the row's parent scope. Enter or Space does what a click does: a scope toggles, a signal is added to the viewer and becomes the selected row.
- **Selection and the context menu without a pointer.** Shift+Up / Shift+Down extend a range of selected signals (Shift+click); Ctrl+Space toggles the current signal in the selection without adding it (Ctrl/Cmd+click). Shift+F10 or the Menu key opens the current row's context menu over the row — the same items a right-click shows, including the bulk items when several signals are selected. Focus starts on the first item, and closing the menu (by choosing an item or with Escape) returns focus to the same row. Adding signals from the menu is announced too ("2 signals added to the viewer").
- **The tree's keys win while it has focus.** Left / Right no longer pan the waveform and Home / End no longer jump the viewport while focus is in the tree; Space does not start Stage playback there. Other modified keys are not taken (Ctrl+Shift+Arrow still resizes the dock). Bare letters (W A S D Q E Z, M chords) still drive the waveform from anywhere, as before.
- **What a screen reader says.** Entering the tree reads short keyboard instructions once. Each row is one button: a scope is "name, button, collapsed / expanded, N signals"; a signal is "name, button" with its bit range for vectors ("ARADDR, [31:0]") and "selected" when selected; a parameter adds its value. Adding a signal is announced ("ARADDR added to the viewer").
- **Visible focus.** The current row has a 2 px primary-colored outline while the tree has keyboard focus.
- **Clicks don't steal focus.** Clicking a row moves the tree's current row but leaves keyboard focus where it was, so arrow keys keep panning the waveform for someone who clicks signals in and then pans.

#### Setup

- Load `vcd/parameter_multiselect.vcd` (see §2.2). For the screen-reader steps: NVDA on Windows, or VoiceOver on macOS.
- For the lazy-list step, any file with a scope of a few hundred signals (a gate-level FST is ideal).

#### Steps and expected behavior

1. Click in the Signal Tree search field, then press **Tab**. The first row (`top`) gets a visible outline. NVDA reads the keyboard instructions, then "top, button, collapsed".
2. **Right**: `top` expands (outline stays on `top`, "expanded"). **Right** again: moves to the first child row.
3. **Down** / **Up** walk the visible rows in the order shown. **End** jumps to the last row and the list scrolls so it is fully visible; **Home** returns to the top.
4. Move to `top.spi`, expand it, move to `sclk`, press **Enter**. `sclk` is added to the waveform, the row shows the selected highlight, NVDA says "sclk added to the viewer", and focus stays on the row. **Space** on another signal does the same. Holding **Enter** adds the signal once, not once per key repeat.
5. **Left** on a signal moves to its scope; **Left** on an expanded scope collapses it; **Left** on a collapsed top-level scope does nothing.
6. With the tree focused, press **Left**, **Right**, **Home**, **End** and **Space**: none of them pans or jumps the waveform or starts Stage playback. Press **Tab** to leave the tree and repeat: now they act on the waveform as usual.
7. With the tree focused press **Ctrl+Shift+Right** (Cmd+Shift+Right on macOS): the left dock widens, and the current row does not change.
8. Press **Tab** to leave, click a different signal row with the mouse, then Shift+Tab back into the tree: the outline is on the clicked row.
9. **Lazy list.** In a scope with hundreds of signals press **End**, then scroll the tree back to the top with the mouse wheel. Press **Up**: focus is still in the tree, the list scrolls back to the second-to-last row, and it is announced.
10. With a deep row current, click the **Collapse All** header button. With the tree focused (Tab back into it if focus moved), the outline is on the top-level scope that contained the row, not on an arbitrary row.
11. **Context menu from the keyboard.** On `top` press **Shift+F10**: the menu opens next to the row (not at the window corner) with **Add All in Scope** focused, and NVDA reads it. Press **Enter**: every signal in `top` is added, NVDA says "N signals added to the viewer", and the outline is back on `top`. On a signal press the **Menu** key (Windows keyboards): **Add to Viewer** is focused; **Down** then **Enter** on **Copy Signal Path** puts the full path on the clipboard. Open the menu again and press **Escape**: it closes and focus is on the same row.
12. **Bulk actions from the keyboard.** In `top.spi`, move to its first signal and press **Shift+Down** three times: all four SPI signals are selected, nothing is added. **Ctrl+Space** on the last one deselects it. **Shift+F10**, choose **Add 3 Selected to Viewer**: the three are added in tree order and announced. **Shift+F10** again, choose **Apply Decoder to Selection…**: the decoder picker opens scoped to the selection; **Escape** closes it and focus is back on the row.

#### Edge cases

- Search filter active: arrows walk only the filtered rows; Right on an expanded scope whose children are all filtered out does nothing.
- An empty scope (no children, no signals) has no expanded state; Enter and Right do nothing.
- Touch platforms (iPad, phones): rows keep their tap / long-press behavior; the keyboard instructions are not read by VoiceOver / TalkBack, since those navigate by swiping.
- Shift+Up / Shift+Down onto a scope row moves without changing the selection (only signals are selectable); the range continues when the next signal is reached. A range started on an unselected signal is anchored there.
- Ctrl+Space on macOS may be taken by the input-source switcher when several input sources are enabled; Shift+Up / Shift+Down still select, and Cmd+click remains.

#### Automation Assessment

| Test | Coverage | Rationale |
|---|---|---|
| Parent / first-child / current-row resolution over the flat row list (collapse to ancestor, rebuilt hierarchy, twin paths) | **UNIT** (`test/features/signal_tree/utils/signal_tree_navigation_test.dart`) | Pure functions over known row lists. |
| One Tab stop; Tab back returns to the last row; a click moves the row without taking focus; one focus ring | **WIDGET** (`test/features/signal_tree/widgets/signal_tree_row_list_test.dart` — "one Tab stop" group) | Real key events through the real traversal policy. |
| Up/Down/Home/End/Page keys, Right/Left expand-enter/collapse-leave, modified keys left to the app | **WIDGET** (same file — "tree keys" group) | Deterministic. |
| Enter/Space add and select a signal and announce it; held Enter adds once; Enter/Space toggle a scope | **WIDGET** (same file — "activation" group) | Announcements recorded from the accessibility channel. |
| Arrows, Home, End and Space do not reach the viewer's bindings while the tree is focused (with a control proving they do from elsewhere) | **WIDGET** (same file — "the app keymap" group) | Uses the real `ShortcutManagerWidget` and keymap. |
| Focus survives the current row being scrolled out of the lazy list's build window; End scrolls the last row into view; Collapse All resolves to the ancestor | **WIDGET** (same file — "the lazy list" group) | Rows beyond the build window are actually disposed in the test. |
| Shift+F10 and the Menu key open the row's menu over the row with its first item focused; Add All in Scope, Copy Signal Path, Add Selected and Apply Decoder to Selection all run from the keyboard; Escape and choosing an item return focus to the same row (also after the decoder dialog closes); Shift+Up/Down range selection and Ctrl+Space toggle without adding | **WIDGET** (same file — "the context menu and selection keys" group) + **UNIT/WIDGET** (`signal_tree_menu_anchor_test.dart` — row rect after scrolling) | Real key events; items chosen with Down and Enter, never tapped. |
| Adding signals from any row menu item is announced (single, selected, whole scope, chunked scope) | **WIDGET** (`scope_tree_node_test.dart` — "small scope adds synchronously", "large scope takes the chunked path"; `variable_tree_leaf_test.dart` — "Add to Viewer from the menu is announced", "Add N selected") | Announcements recorded from the accessibility channel. |
| Row semantics: name, width, value, expanded/selected, focus reporting, semantics focus action | **WIDGET** (same file — "what a screen reader hears"; `scope_tree_node_test.dart` and `variable_tree_leaf_test.dart` — "screen reader and keyboard" groups) | Mirrors what the desktop bridge sends. |
| What is heard, keystroke by keystroke, in the real viewer (pinned transcript) and the tree as a Tab stop in the whole-viewer walk | **WIDGET** (`test/accessibility/screen_reader_test.dart` — `goldens/signal_tree.txt`, `goldens/viewer_file_open.txt`) | Golden diffs are reviewed like UI diffs. |
| NVDA / VoiceOver actually speak the rows, instructions and menu items as modelled | **MANUAL** (steps 1, 4, 9, 11) | Needs a real screen reader; batched with the external tester's re-check. |

---

## 5. Protocol decoders (Open Core)

> The Open Core tier ships SPI, I²C, UART, AXI4-Lite, APB, AHB-Lite, Wishbone and SPI flash, plus the RISC-V instruction-trace decoder. AXI4 full / USB / PCIe TLP / JTAG / MDIO / Ethernet are Pro-tier and verified separately with the Pro overlay.

### 5.1 Decoder picker and setup flow

#### 5.1.1 What it does

The decoder picker dialog lists all available protocol decoders, lets you bind specific signals to protocol pins, validates that required signals are bound before allowing apply, and exposes per-decoder configuration parameters. In Pro-licensed builds the picker also surfaces Pro decoders with a `PRO` badge — open-core builds list only the open-core five.

#### 5.1.1a Steps — reconfiguring a decoder from the transaction table writes to the ACTIVE TAB

1. Open two tabs with **different** waveforms, and add a decoder in each. Give the two decoders visibly different configuration (a different bit order, polarity, or bound signal).
2. In tab B, open the **transaction table** panel, click the decoder filter dropdown, and choose **Configure…** on the decoder.
3. Change a parameter and confirm. **The edit must apply to tab B's decoder.** Switch to tab A and confirm its decoder is *unchanged*.
4. Repeat the same edit from the two other entry points — the decoder list entry's Configure action, and the decoder picker — and confirm each also writes to the tab it was opened from.

**Why this section exists.** A dialog route is a child of the Navigator, which sits **above** the per-tab `UncontrolledProviderScope`. So `ref` inside `DecoderConfigDialog` resolves the *root* container, where no file is loaded. Two of the three call sites already pre-read the signal map and the decoders notifier from their own per-tab `ref` and pass them in; the transaction-table panel did not, so the edit was written to the root notifier and the active tab silently kept its old configuration — no error, no visible change. Found 2026-07-21 by crux-shared's new `route_mounted_scope_leak_test` static guard; NetCrux hit the same defect class first.

**Edge case worth checking once:** the failure is invisible in any single-tab session, because with one tab open the root and tab containers hold equivalent state. Two tabs are required to see it.

| Check | Automatable? | How |
|---|---|---|
| Configure from the transaction table targets the active tab's notifier | **WIDGET** (`transaction_table_panel_test.dart` — "Configure hands the dialog the ACTIVE TAB container, not the root") | Builds the real two-container shape (root parent + per-tab child) and asserts the dialog receives the tab's notifier. Mutation-verified: reverting the fix gives `Expected: same instance as <_FixedDecodersNotifier> / Actual: <null>`. Note every *other* test in that file uses one `ProviderScope`, so none of them could ever have caught this. |
| No route-mounted widget reads per-tab state without a bound scope | **STATIC** (crux-shared `route_mounted_scope_leak_test.dart`) | Guards the whole class rather than this one site. |
| Cross-tab isolation end-to-end | **MANUAL** | Needs two real waveforms and two tabs. |

#### 5.1.2 Steps

1. Load `protocol/spi/generated/spi_basic.vcd`. Find the decoder entry point (toolbar button, Tools menu, right-click on signal, or command palette → "decoder"). A selection-scoped entry point also exists in the signal tree — "Apply Decoder to Selection…" on a multi-selected row's context menu, verified in §4A.
2. Open the decoder picker. Verify the picker is **grouped into collapsible category sections** (one `ExpansionTile` per populated `DecoderCategory`). On an open-core build three sections appear: **Serial Bus (4)** = SPI, I²C, UART, SPI Flash; **AMBA (4)** = AXI4-Lite, APB, AHB-Lite, Wishbone; **Instruction Trace (1)** = RISC-V. Other category sections (High-Speed Serial, Test & Management, Ethernet, User Plugins, Custom) are absent because no decoders register in those categories on an open-core build.
3. Verify the section order top-to-bottom is **Serial Bus → AMBA → Instruction Trace**, locale-independent. Switch the app locale through en / zh-CN / ja / ko in turn — order must not change between locales, only the localized label text.
4. Verify the section header is `<Localized Name> (<count>)` via the `pickerCategoryHeader` ARB format.
5. Verify all sections start expanded — every decoder is visible. Collapse and re-expand one section to verify the disclosure arrow toggles correctly.
6. None of the Pro decoders should appear in an open-core build (no AXI4 full, USB, PCIe TLP, etc.).
7. Select SPI. Verify signal binding fields appear for SCLK (required), MOSI (required), MISO (optional), CS (optional).
8. Try to apply without binding required signals — verify it's blocked with a clear message.
9. Bind required signals → Apply. Decoder should activate.

#### 5.1.3 Reconfiguration / instance numbering

1. Add SPI decoder, then add another SPI decoder. Verify they're labeled distinctly (e.g., "SPI #1", "SPI #2").
2. Remove SPI #1. Add another SPI. Verify the new one is "SPI #3" (numbers don't reuse).
3. Update the configuration of an existing decoder — verify the transactions re-decode with new parameters.

#### 5.1.3.1 Parameter-label localization

Decoder parameter labels, descriptions, and enum-value labels are localized through an ARB-key indirection (mirroring the Stage widget `ConfigLabelResolver`): each `DecoderParameter` may carry a `labelKey` / `descriptionKey` / `enumLabelKeys`, resolved in the config dialog via `decoderConfigLabelResolverFactoryProvider`. When a key is absent the dialog falls back to the raw `displayName` / `description` / `enumLabels`, so user-contributed plugin decoders are unaffected.

1. Open the config dialog for **SPI** in each of en / zh-CN / ja / ko. Verify the parameter labels (CPOL, CPHA, Bit Order, Word Size, CS Active Level), their help text, and the enum dropdown values ("0 (Idle Low)", "MSB First", "Active Low", …) render localized — not raw ARB keys like `spiParamCpol`. Repeat for RISC-V, I²C, AHB-Lite, Wishbone, SPI-Flash (the six converted decoders).
2. Acronyms (SPI, CPOL, CPHA, I²C, AHB, MSB/LSB, RISC-V, XLEN) stay untranslated in CJK locales.

#### 5.1.4 Automation Assessment

| Test | Coverage |
|---|---|
| Decoder list inventory (open-core five only) | **WIDGET** (`test/features/decoders/widgets/decoder_picker_dialog_open_core_set_test.dart` — "full-set enumeration") |
| Decoder parameter-label resolver (known key → localized string; unknown key → identity) | **WIDGET** (`test/features/decoders/providers/decoder_config_label_resolver_provider_test.dart` — locale sweep en/zh/ja/ko) |
| `DecoderParameter` labelKey / descriptionKey / enumLabelKeys (equality, copyWith) | **UNIT** (`test/domain/models/decoder_parameter_test.dart`) |
| Picker section ordering matches `DecoderCategory.values` regardless of locale | **WIDGET** (`decoder_picker_dialog_open_core_set_test.dart` — "section ordering across locales" en/zh/ja/ko) |
| Each open-core decoder lands in the expected category | **WIDGET** (`decoder_picker_dialog_open_core_set_test.dart` — "category assignment") |
| Picker omits empty categories | **WIDGET** (`decoder_picker_dialog_test.dart` — "omits empty categories") |
| `pickerCategoryHeader` count rendering | **WIDGET** (`decoder_picker_dialog_test.dart` — "renders the localized category label in section header") |
| Required-signal validation blocks apply | **WIDGET** (`decoder_config_dialog_test.dart`) |
| Instance numbering and remove/re-add | **WIDGET** (`active_decoders_provider_test.dart` — "increments instanceNumber per decoder type" + "instanceNumber is not reused after removeDecoder" + "remove + re-add decoder → same transactions on second add") |

---

### 5.2 SPI decoder

#### 5.2.1 What it does

SPI is a 4-wire synchronous serial protocol used for chip-to-chip communication on a board (flash, sensors, ADCs, displays). The decoder takes raw clock/data/chip-select waveforms and reconstructs the bytes that were transferred — so instead of staring at a sea of clock edges, you see "0xA5 → 0x42 → 0xFF" on a transaction lane.

CPOL and CPHA are the two clock-mode parameters: CPOL says whether idle clock is low (0) or high (1); CPHA says whether data is sampled on the leading or trailing edge. Together they form four modes (0/0, 0/1, 1/0, 1/1) — different SPI peripherals require different modes, and getting the mode wrong is a common debug scenario.

#### 5.2.2 Setup

Six committed fixtures under `protocol/spi/`:

- `spi_basic.vcd` — two simple Mode 0 transactions (legacy fixture kept for the hardcoded unit-test arrays in `spi_decoder_test.dart`). Companion `spi_basic.expected_transactions.json`.
- `spi_mode0.vcd` — CPOL=0 CPHA=0, idle-low + sample-on-rising. Two transactions (one 1-byte, one 2-byte).
- `spi_mode1.vcd` — CPOL=0 CPHA=1, idle-low + sample-on-falling. Same two-transaction shape.
- `spi_mode2.vcd` — CPOL=1 CPHA=0, idle-high + sample-on-falling.
- `spi_mode3.vcd` — CPOL=1 CPHA=1, idle-high + sample-on-rising.
- `spi_glitch.vcd` — Mode 0 timing with one MOSI transition exactly on a sample edge; the decoder must flag the second transaction as `isError: true` with `errorMessage: "MOSI changes at sample edge t=<tick>"`.

Each fixture has a companion `<name>.expected_transactions.json` produced by `test/tool/generate_spi_fixtures_test.dart` (which runs the actual `SpiDecoder` against the handcrafted timeline, so the JSON is always consistent with the implementation).

Regenerate after any decoder change with: `flutter test test/tool/generate_spi_fixtures_test.dart`

#### 5.2.3 Steps

1. Load `protocol/spi/generated/spi_basic.vcd`. Capture diagnostics report → `spi_baseline_report.txt`.
2. Bind SCLK / MOSI / MISO / CS. Apply the SPI decoder with default config (CPOL=0, CPHA=0, MSB-first, 8-bit word, CS active-low).
3. Verify decoded transaction bytes match the values in `spi_basic.expected_transactions.json` (label "SPI 0xA5" then "SPI 2 words" with MOSI = "0xDE 0xAD", MISO = "0xBE 0xEF").
4. Test all four CPOL/CPHA mode combinations — one fixture per mode, decoder configured to match:
   - Load `spi_mode0.vcd`; configure decoder for Mode 0 (CPOL=0, CPHA=0); verify 2 transactions matching `spi_mode0.expected_transactions.json`.
   - Repeat with `spi_mode1.vcd` / Mode 1, `spi_mode2.vcd` / Mode 2, `spi_mode3.vcd` / Mode 3.
   - As a negative check, load `spi_mode0.vcd` and configure for Mode 2 — the decoded bytes should differ from the Mode 0 ground truth, demonstrating mode selection has an effect.
5. Test MSB-first vs LSB-first bit order on `spi_mode0.vcd` — verify swapped output when toggled.
6. Test with CS framing and without CS — both should work (the legacy `spi_basic.vcd` uses CS framing).
7. Load `spi_glitch.vcd` and apply the SPI decoder with Mode 0. Verify the second transaction is flagged as `isError: true` with `errorMessage` containing "MOSI changes at sample edge". The label should be "SPI 0xD3" (note: the byte value differs from intended 0xC3 because the glitch flipped a bit during sampling).

#### 5.2.4 Diagnostics-assisted verification

- File Info: confirm SPI test VCD has the expected signal count.
- Render tab: with the decoder active, "transaction paint" time should be non-zero in the breakdown.
- Signal Health: SCLK should be detected as a clock candidate.

#### 5.2.5 Edge cases

- Configure SPI with wrong signal bindings (e.g., CS bound to SCLK) — must not crash.
- Apply SPI decoder to a non-SPI VCD — should produce garbage or no transactions, never crash.

#### 5.2.6 Automation Assessment

| Test | Coverage | Rationale |
|---|---|---|
| Known-answer SPI byte decode | **WIDGET** (`test/services/decoders/spi_decoder_test.dart` — fixture round-trip) | Highest-value end-to-end test: load fixture → assert decoded bytes match expected list. |
| All four CPOL/CPHA modes | **WIDGET** (`spi_decoder_test.dart` — parameterized over modes) | Easy to parameterize across modes. |
| MSB/LSB bit order | **WIDGET** (`spi_decoder_test.dart`) | Easy to assert. |
| Glitch error detection | **WIDGET** (`spi_decoder_test.dart`) | Known-answer error fixture. |
| Wrong-bindings doesn't crash | **WIDGET** (`spi_decoder_test.dart`) | Robustness regression catch. |
| Activation from picker → real FFI parse → 2 transactions in table | **INTEGRATION_TEST** (`integration_test/decoders/spi_integration_test.dart`) |  |

#### 5.2.7 Captured fixture — nandland SPI master mode-3 loopback

Real-world SPI traces live under `test/fixtures/protocol/spi/captured/`
(mirrored to `verification/fixtures/protocol/spi/captured/`). The
auto-discovery sweep `test/services/decoders/spi_captured_fixtures_test.dart`
runs `SpiDecoder` against every triplet and snapshot-matches.

Current pilot capture:

- `nandland_spi_master_mode3_loopback.fst` — MIT-licensed
  nandland/spi-master `SPI_Master_With_Single_CS` in mode-3 self-
  loopback (MOSI tied to MISO). Yields 1 decoded transaction with
  matching TX/RX bytes — the simplest possible real-world SPI capture
  that still validates the CPOL/CPHA mode-3 sample-edge convention.
  See [`PROVENANCE.md`](../test/fixtures/protocol/spi/captured/PROVENANCE.md).

Manual sign-off: open the .fst in WaveCrux, apply the SPI decoder via
the `.fixture.json` bindings (CPOL=1 CPHA=1 mode-3 MSB-first 8-bit),
confirm the single transaction renders. Then run the sweep test (<1 s).

Automation Assessment:

| What | Automation |
|------|------------|
| Snapshot regression | **WIDGET** (`spi_captured_fixtures_test.dart`) |
| End-to-end activation | **INTEGRATION_TEST** (`integration_test/decoders/spi_captured_integration_test.dart`) |

---

### 5.3 I²C decoder

#### 5.3.1 What it does

I²C is a 2-wire bidirectional bus. SDA carries data; SCL carries the clock. A "START" condition (SDA falling while SCL is high) opens a transaction; the master then sends a 7-bit address and a R/W bit. The addressed slave acknowledges with ACK (pulling SDA low for one clock); if no slave responds, you get NACK. The master then reads or writes data bytes, each acknowledged. A "STOP" condition (SDA rising while SCL is high) ends the transaction. A "repeated START" lets you change direction (write-then-read) without releasing the bus.

#### 5.3.2 Setup

Two committed fixtures under `protocol/i2c/`:

- `i2c_basic.vcd` — legacy two-transaction fixture (write `0x55` to `0x48` ACK; address-NACK to `0x20`). Companion `i2c_basic.expected_transactions.json`. Used by the existing `i2c_decoder_test.dart` hardcoded arrays.
- `i2c_full.vcd` — richer fixture covering the four scenarios the verification guide actually requires. Companion `i2c_full.expected_transactions.json` produced by `test/tool/generate_i2c_fixtures_test.dart` running the actual `I2cDecoder`:

| # | Type | Address | Data | Status |
|---|---|---|---|---|
| 1 | Write | 0x50 | 0x42 | ACK (normal) |
| 2 | Read | 0x50 | 0xBE | NACK on last byte (normal for reads — `isError: false`) |
| 3 | Write | 0x55 | — | NACK on address (error — `isError: true`, `errorMessage: "Address phase NACK"`) |
| 4 | Write→Read | 0x50 | 0x10 then 0xDE | Repeated START — appears as TWO transactions in the table (write segment + read segment), chained because the read's `startTime` equals the write's `endTime`. |

Regenerate after any decoder change with: `flutter test test/tool/generate_i2c_fixtures_test.dart`

#### 5.3.3 Steps

1. Load `protocol/i2c/generated/i2c_full.vcd`. Bind SCL and SDA. Apply the I²C decoder (default `address_bits=7`).
2. Verify 5 transactions appear in the table (the repeated-START pair counts as two rows).
3. Verify each transaction's address, data, and status match the table above.
4. Verify transaction 3 is styled as an error (red border / hatching) with errorMessage "Address phase NACK".
5. Verify transactions 4 and 5 are the repeated-START chain — same address 0x50, write then read, with the read's `startTime` equal to the write's `endTime`. No intervening transaction.
6. Tap a transaction block on the canvas — cursor should jump to the transaction start time.
7. Click a row in the transaction table — cursor should jump and the transaction should highlight on canvas.

#### 5.3.4 Edge cases

- Stress test with many back-to-back transactions.
- 10-bit addressing (if supported).
- Bus arbitration scenarios.

#### 5.3.5 Captured fixture — Forencich i2c_master + i2c_slave

In addition to the hand-emitted `generated/` fixtures, a real
RTL-driven SDA/SCL trace sits in
`verification/fixtures/protocol/i2c/captured/` (mirrored to
`test/fixtures/protocol/i2c/captured/`). The capture exercises the
decoder against actual i2c_master+i2c_slave bus traffic on an
open-drain bus rather than a synthetic edge-aligned event stream.

The auto-discovery sweep test
`test/services/decoders/i2c_captured_fixtures_test.dart` walks every
captured fixture, runs `I2cDecoder` against the trace via the
WellenProvider FFI backend, and snapshot-matches the JSON. Adding a
new captured fixture is purely additive — drop the triplet in and run
`REGENERATE=1 flutter test test/services/decoders/i2c_captured_fixtures_test.dart`.

Pipeline note: no cocotb, no Python. Forencich's `verilog-i2c` (MIT)
ships its testbench stimulus in MyHDL (deprecated), so we vendor only
the synthesizable RTL (`i2c_master.v` + `i2c_slave.v`) and supply our
own pure-Verilog testbench that wires both onto a shared open-drain
SDA/SCL bus with explicit `pullup()` resolution. Toolchain matches
the picorv32 / apb captures: icarus-verilog only. Helpers live under
[`test/fixtures/protocol/i2c/captured/helpers/forencich/`](../test/fixtures/protocol/i2c/captured/helpers/forencich/).

Current pilot capture:

- `i2c_forencich_master_slave.fst` — Two back-to-back writes from the
  master to slave address 0x50: multi-byte 0xAB/0xCD then single-byte
  0x42, every byte ACK'd. Vendored from `alexforencich/verilog-i2c`
  commit `a65be40`, MIT. ~50 µs of bus traffic, FST ~6 kB. See
  [`PROVENANCE.md`](../test/fixtures/protocol/i2c/captured/PROVENANCE.md)
  for hand-verified anchors. A read-side capture is intentionally
  deferred — the slave's strict AXIS TX handshake is easy to race
  against from a synchronous tb, and the write-only path already
  covers START / addr+W / per-byte ACK / multi-byte data / STOP /
  repeated transaction.

Manual sign-off:

1. Open `i2c_forencich_master_slave.fst` in WaveCrux. Apply the I²C
   decoder with the bindings from
   `i2c_forencich_master_slave.fixture.json` (`sda → tb_i2c_master_slave.sda`,
   `scl → tb_i2c_master_slave.scl`). Confirm the two write transactions
   appear in the table — `I²C 0x50 W 2 bytes` followed by
   `I²C 0x50 W 0x42`.
2. Run `flutter test test/services/decoders/i2c_captured_fixtures_test.dart`
   and confirm it passes against the committed snapshot (2
   transactions; <1 s on a modern machine).

Automation Assessment:

| What | Automation |
|------|------------|
| Snapshot regression vs `i2c_forencich_master_slave.expected_transactions.json` | **WIDGET** (`i2c_captured_fixtures_test.dart` — fixture auto-discovery sweep + snapshot diff) |
| Toolchain reproducibility (iverilog + vendored i2c_master.v / i2c_slave.v + in-tree tb) | **MANUAL** — covered by `helpers/forencich/README.md` + `helpers/forencich/Makefile` |
| Hand-verified anchors against the testbench program | **MANUAL** — anchors documented in `PROVENANCE.md` |

#### 5.3.6 Automation Assessment

| Test | Coverage |
|---|---|
| Known-answer transaction list | **WIDGET** (`test/services/decoders/i2c_decoder_test.dart`) |
| NACK error styling | **WIDGET** (`i2c_decoder_test.dart`) |
| Repeated START detection | **WIDGET** (`i2c_decoder_test.dart`) |
| Captured-fixture snapshot regression (Forencich master+slave write transactions) | **WIDGET** (`i2c_captured_fixtures_test.dart` — fixture auto-discovery sweep + snapshot diff) |
| Tap-to-jump on canvas blocks | **INTEGRATION_TEST — pending** (gesture-arena interaction; queued in `integration_test/PENDING.md`) |
| Row click → cursor jumps + on-canvas highlight | **WIDGET** (`test/features/decoders/widgets/transaction_table_panel_test.dart` — "tapping a row marks transaction as selected" + "tapping a row also places primary cursor at transaction startTime") |
| Activation from picker → real FFI parse → 2 transactions in table | **INTEGRATION_TEST** (`integration_test/decoders/i2c_integration_test.dart`) |

---

### 5.4 UART decoder

#### 5.4.1 What it does

UART is asynchronous serial — one wire each direction, no shared clock. Each byte is framed by a start bit (low), 5–9 data bits, an optional parity bit, and 1–2 stop bits. The receiver knows the agreed baud rate and samples in the middle of each bit period. "Baud" = bits per second; common values are 9600, 115200, 1 Mbaud. A parity error means the parity bit didn't match the data; a framing error means the stop bit wasn't where expected (often caused by baud-rate mismatch).

#### 5.4.2 Setup

Two committed fixtures under `protocol/uart/generated/`:

- `uart_basic.vcd` — three transactions at 1 Mbaud (`Hi` ASCII = `0x48 0x69` on TX, single byte `U=0x55` with a **framing error**, and `OK` = `0x4F 0x4B` on RX). Parity = none. Companion `uart_basic.expected_transactions.json`.
- `uart_parity.vcd` — two TX-channel transactions at 1 Mbaud with even parity. Byte 'A' (0x41) has correct parity (passes). Byte 'B' (0x42) has its parity bit deliberately flipped — the decoder flags it as `isError: true` with `errorMessage: "Parity error"`. Generated by `test/tool/generate_uart_fixtures_test.dart`.

Three real-world captured fixtures under `protocol/uart/captured/` (MIT-licensed, from `ben-marshall/uart` at commit `5fd2db8`; see `captured/PROVENANCE.md` for full attribution + hand-verified anchors):

- `ben_marshall_tx_9600bps.fst` — standalone TX testbench, 20-byte burst at 9600 bps over a 50 MHz clock; exercises grouped back-to-back framing at the slowest commonly-deployed UART rate. Companion `.fixture.json` + `.expected_transactions.json`.
- `ben_marshall_rx_115200bps.fst` — standalone RX testbench, 10 bytes at 115200 bps. Self-checking: the testbench prints `[PASS]` per byte, providing independent ground truth for the snapshot.
- `ben_marshall_sys_loopback_11520bps.fst` — full system loopback `tb.uart_rxd → impl_top → tb.i_dut.uart_txd` at the off-standard 11520 bps rate (1/10 of 115200). Dual-channel decode, 15 RX bytes / 14 TX bytes (the 15th RX byte arrives too late to be echoed before `$finish`).

> **Important — timescale auto-detection.** The UART decoder must read the timescale from the VCD file's `WaveformDataSource.timescale` property automatically. It must NOT require the user to manually enter "ns per tick". A historical bug had the user entering this manually, causing 1000× wrong bit-period calculations on `1ps` timescale files. Verify that loading `uart_basic.vcd` with no manual timescale entry produces correct decoding.

Regenerate after any decoder change with: `flutter test test/tool/generate_uart_fixtures_test.dart`

#### 5.4.3 Steps

1. Load `protocol/uart/generated/uart_basic.vcd`. Bind TX (RX is optional). Apply the UART decoder with `baud_rate=1000000`, `parity=none`, `data_bits=8`, `stop_bits=1`.
2. Verify three transactions match `uart_basic.expected_transactions.json` — "UART TX: Hi", "UART TX: U" (flagged with errorMessage "Framing error: stop bit low"), "UART RX: OK".
3. Verify the framing-error frame is styled as an error.
4. Load `protocol/uart/generated/uart_parity.vcd`. Reconfigure the decoder with `parity=even` (other parameters unchanged). Verify two transactions: "UART TX: A" (clean) and "UART TX: B" (`isError: true`, errorMessage "Parity error").
5. Verify byte grouping (if multi-byte transaction display is supported) — `uart_basic.vcd` groups `H`+`i` into one transaction.
6. Open the diagnostics panel → Signal Health: the TX/RX line should NOT be detected as a clock (it's data).
7. **Timescale regression check:** load a `1ps`-timescale UART VCD without changing any decoder parameters. Verify decoding still works (timescale auto-read).

#### 5.4.3.1 Bit timing — baud, clocks-per-bit, auto

Steps 1–7 all state the timing as a baud rate, which is the right unit for a
captured trace. It is the wrong unit for a simulation, and that is what P46 was.

**The failure to understand before verifying.** A UART in an HDL testbench is
written against a clock and a `CLKS_PER_BIT` constant; nobody picks a baud.
Scenario 04's design was `always #5 clk` at a 1 ns timescale with
`CLKS_PER_BIT = 8` — 80 ns per bit, 12.5 Mbaud. The decoder defaulted to 9600,
computed a 104,166-tick bit period against an 80-tick reality, and produced
**no transactions at all**: no error, no warning, no hint which of eight
settings was wrong.

> **A wrong bit period does not generally produce silence.** It produces
> confident garbage. 9600 was wrong by four orders of magnitude, which is why
> that trace decoded to nothing; halving the clock in the unit tests yields a
> *different byte*, not an empty result. When verifying, treat plausible-looking
> wrong data as the expected symptom of a timing mismatch — not an absence of
> output.

8. Reload `uart_basic.vcd`. Set **Bit Timing → Clocks per bit**, bind the
   testbench clock to the new optional `clk` signal, and set **Clocks per Bit**
   to the design's divisor. Verify the same three transactions decode as in
   step 2 — clocks-per-bit is a restatement of the same timing, not a second
   decode path.
9. Halve the clock rate (or double Clocks per Bit) and re-run. The decode
   changes — that is the measurement reaching the bit period. If the output is
   unchanged, the clock is being ignored.
10. Unbind `clk` while leaving the mode on Clocks per bit. Verify **nothing
    decodes** rather than something plausible: the mode asks for a clock, and
    without one there is no honest period to invent.
11. Set **Bit Timing → Auto-detect from the line** with no clock bound. Verify
    the decode matches step 2. Auto takes the GCD of the inter-edge gaps —
    every gap on a UART line is a whole number of bit times — and falls back to
    the shortest gap when the GCD collapses under jitter. It is a heuristic,
    which is why it is the third mode and not the default; a captured trace
    with real jitter is where it is most likely to be wrong.
12. **Backward-compatibility check.** Open a `.wavecrux` session saved before
    this feature, or any decoder config with no `timing_mode` set. It must
    decode exactly as it did — baud is still the default and an unrecognized
    mode falls back to it.

#### 5.4.4 Edge cases

- Different baud rates: 9600, 115200, 1 M.
- Parity modes: none, even, odd.
- Stop bits: 1 vs 2.
- Receiver buffer overflow (very fast back-to-back).
- **`bit_order` parameter:** verify both `lsb` (default — LSB-first transmission) and `msb` (MSB-first) decode bytes correctly when the testbench uses the matching convention.
- **`group_gap_bits` parameter (default 10):** verify the decoder groups bytes into a single transaction when the inter-byte idle time is shorter than `group_gap_bits` bit periods, and emits a new transaction when the gap exceeds that threshold.

#### 5.4.5 Automation Assessment

| Test | Coverage |
|---|---|
| Known-answer byte decode | **WIDGET** (`test/services/decoders/uart_decoder_test.dart`) |
| Parity error detection | **WIDGET** (`uart_decoder_test.dart`) |
| Framing error detection | **WIDGET** (`uart_decoder_test.dart`) |
| Auto-timescale regression | **WIDGET** (`uart_decoder_test.dart` — auto-timescale-derivation case is the documented regression catch) |
| Activation from picker → real FFI parse → 3 transactions in table | **INTEGRATION_TEST** (`integration_test/decoders/uart_integration_test.dart`) |
| Captured-fixture sweep (3 ben-marshall FSTs at 9600 / 115200 / 11520 bps) — every `.fst` in `protocol/uart/captured/` is auto-discovered, decoded, and snapshot-matched | **WIDGET** (`test/services/decoders/uart_captured_fixtures_test.dart`; regenerate snapshots with `REGENERATE=1 flutter test test/services/decoders/uart_captured_fixtures_test.dart`) |
| Captured-fixture end-to-end activation (`ben_marshall_tx_9600bps.fst` → 1 grouped 20-byte transaction in the table) | **INTEGRATION_TEST** (`integration_test/decoders/uart_captured_integration_test.dart`) |

---

### 5.5 AXI4-Lite decoder

#### 5.5.1 What it does

AXI4-Lite is the simplest variant of ARM's AXI4 bus — used for register access between CPU and peripherals on an SoC. It has five channels: write address (AW), write data (W), write response (B), read address (AR), and read data (R). Each channel uses a VALID/READY handshake — both sides must assert their flag in the same cycle for data to transfer. Responses include OKAY, EXOKAY, SLVERR (slave error), and DECERR (decode error).

#### 5.5.2 Setup

`protocol/axi4lite/generated/axi4lite_basic.vcd` with read and write transactions including SLVERR/DECERR error responses and back-to-back transactions. Companion JSON file records expected output.

#### 5.5.3 Steps

1. Load `protocol/axi4lite/generated/axi4lite_basic.vcd`. Bind the 18 required AXI signals (ACLK, ARESETN, AWVALID, AWREADY, AWADDR, WVALID, WREADY, WDATA, BVALID, BREADY, BRESP, ARVALID, ARREADY, ARADDR, RVALID, RREADY, RDATA, RRESP). Optional signals (AWPROT, ARPROT, WSTRB) can be bound additionally if present in the fixture.
2. Apply the AXI4-Lite decoder.
3. Verify read transactions show address and returned data.
4. Verify write transactions show address, data, and response.
5. Verify SLVERR/DECERR transactions are flagged as errors.
6. Verify back-to-back transactions are decoded individually, not merged.

#### 5.5.4 Diagnostics-assisted verification

- Render tab: with 15+ signals plus a transaction lane, "Visible signal rows" should be ~16+.

#### 5.5.5 Automation Assessment

| Test | Coverage |
|---|---|
| Known-answer read/write decode | **WIDGET** (`test/services/decoders/axi4lite_decoder_test.dart`) |
| Error response (SLVERR/DECERR) flagging | **WIDGET** (`axi4lite_decoder_test.dart`) |
| Back-to-back transaction separation | **WIDGET** (`axi4lite_decoder_test.dart`) |
| Activation from picker → real FFI parse → 4 transactions in table | **INTEGRATION_TEST** (`integration_test/decoders/axi4_lite_integration_test.dart`) |

#### 5.5.6 Captured fixtures

Real-world AXI4-Lite traces acquired from public open-source projects
exercise the decoder against bus traffic produced by upstream IP under
permissive licenses. Each captured fixture lives under
`test/fixtures/protocol/axi4lite/captured/` (mirrored to
`verification/fixtures/protocol/axi4lite/captured/`) as a triplet:
`<name>.fst` + `<name>.fixture.json` (decoder config: signal bindings +
parameters) + `<name>.expected_transactions.json` (regression snapshot).

The auto-discovery sweep test
`test/services/decoders/axi4lite_captured_fixtures_test.dart` walks every
captured fixture, runs the open-core `Axi4LiteDecoder` against the trace
via the WellenProvider FFI backend, and snapshot-matches the JSON.
Adding a new fixture is purely additive — drop the triplet in and run
`REGENERATE=1 flutter test test/services/decoders/axi4lite_captured_fixtures_test.dart`.

Toolchain prerequisites (Python 3.13 venv + cocotb 2.0.1 + cocotbext-axi +
icarus-verilog) and the per-capture workflow are documented in
[`test/fixtures/protocol/axi4lite/captured/helpers/cocotb_setup.md`](../test/fixtures/protocol/axi4lite/captured/helpers/cocotb_setup.md).
Source projects that drive `rst` active-high (e.g. `alexforencich/verilog-axi`)
get a small `iverilog_dump.v` patch that exposes `aresetn = !axil_ram.rst`
in the FST dump scope so the decoder's active-low reset binding works
without a DUT-side change — see
[`helpers/forencich_axil_ram_aresetn_dump.patch`](../test/fixtures/protocol/axi4lite/captured/helpers/forencich_axil_ram_aresetn_dump.patch).

This pipeline mirrors the closed-source Pro overlay's AXI4 Full
captured-fixture pipeline (`tb/axi_ram/`, `tb/axi_register/`), reusing
the same toolchain and `iverilog_dump.v` patch technique. Only the
testbench target and the binding shape (no burst signals) differ.

Current pilot capture:

- `forencich_axil_ram.fst` — 9-scenario AXI4-Lite RAM exerciser
  (4 writes, 4 reads, 1 stress) from `alexforencich/verilog-axi` commit
  `516bd5d`, MIT-licensed. Yields 3712 decoded transactions covering
  the cross-product of write/read × idle-inserter × backpressure-inserter
  × aligned vs unaligned addresses, plus a 256-outstanding stress test.
  Every transaction is single-beat (no bursts in the lite protocol).
  See [`PROVENANCE.md`](../test/fixtures/protocol/axi4lite/captured/PROVENANCE.md)
  for hand-verified anchors.

Manual sign-off:

1. Open `forencich_axil_ram.fst` in WaveCrux. Apply the AXI4-Lite decoder
   with the bindings from `forencich_axil_ram.fixture.json`. Confirm the
   first transaction (`W 0x0FFC = 0xAAAAAAAA [OKAY]` at t=70 ns) and one
   of the late stress-test reads (`R 0x3EF0 = 0x1A191918 [OKAY]` at
   t≈71050 ns) render correctly in the transaction table.
2. Run `flutter test test/services/decoders/axi4lite_captured_fixtures_test.dart`
   and confirm it passes against the committed snapshot (≈3712
   transaction snapshot diff; <2 s on a modern machine).

Automation Assessment:

| What | Automation |
|------|------------|
| Snapshot regression vs `forencich_axil_ram.expected_transactions.json` | **WIDGET** (`axi4lite_captured_fixtures_test.dart` — fixture auto-discovery sweep + snapshot diff) |
| Toolchain reproducibility (cocotb venv + iverilog_dump.v patch + iverilog) | **MANUAL** — covered by `helpers/cocotb_setup.md` + `helpers/forencich_axil_ram_aresetn_dump.patch` |
| Hand-verified anchors against upstream cocotb log | **MANUAL** — anchors documented in `PROVENANCE.md` |

---

### 5.6 APB decoder

#### 5.6.1 What it does

APB (AMBA Peripheral Bus) is the simpler companion to AXI on ARM-based SoCs. It uses a 3-state state machine (IDLE → SETUP → ACCESS) and is designed for low-power, low-bandwidth peripheral register access. APB completes the free AMBA stack alongside AXI4-Lite — engineers get full register-access protocol coverage in the open core tier.

The required signals are PCLK, PRESETn, PSEL, PENABLE, PWRITE, PADDR, PWDATA, PRDATA. Optional signals include PREADY (wait states), PSLVERR (error response), PPROT (protection attributes), and PSTRB (byte strobes).

#### 5.6.2 Setup

`protocol/apb/generated/apb_basic.vcd` exercises the IDLE→SETUP→ACCESS state machine with write, read, write-with-wait-state, and read-with-PSLVERR. Companion JSON pins down the expected output. (Additional fixtures `apb_full.vcd`, `apb_violations.vcd`, `apb_stress.vcd` are referenced as future regenerable artifacts; the basic fixture is sufficient for the core verification path.)

#### 5.6.3 Steps — basic setup

1. Load `protocol/apb/generated/apb_basic.vcd`. Bind required signals. Apply APB decoder.
2. Verify the expected number of transactions appear (4 in the basic fixture: a write, a read, a write with wait state, and a read returning PSLVERR).
3. Verify each transaction's address, data, and direction (read/write) match `apb_basic.expected_transactions.json`.
4. Verify the IDLE→SETUP→ACCESS state machine is correctly identified — no spurious "incomplete transaction" warnings.

#### 5.6.4 Steps — optional signals

1. Bind PREADY only. Verify wait states are decoded as a single transaction (not split into two).
2. Bind PSLVERR. Verify the read-with-error transaction is flagged.
3. Bind PPROT and PSTRB if testbench drives them — values appear in the transaction details.

#### 5.6.5 Steps — multi-instance and reconfiguration

1. Add APB #1 with the required signal set. Add APB #2 with the same bindings. Verify both work independently.
2. Reconfigure APB #1 (e.g., change PADDR width) — verify transactions re-decode.

#### 5.6.6 Steps — protocol violation detection

A future `apb_violations.vcd` (regeneratable from the testbench) covers PENABLE without PSEL, PSEL/PENABLE deasserted during ACCESS, PADDR/PWRITE bus instability, and PSLVERR. Once available:

1. Load the violation fixture. Apply APB decoder.
2. Verify each violation is flagged with a clear error indicator.
3. Verify the transaction table shows the violation reason in a human-readable form.

#### 5.6.7 Stress test

A future `apb_stress.vcd` exercises a large transaction count for performance:

1. Load the stress fixture. Apply APB decoder. Note transaction count.
2. Check Render tab — frame time should remain reasonable even with many transaction blocks visible.
3. Scroll through the transaction table — should remain responsive.

#### 5.6.8 Automation Assessment

| Test | Coverage |
|---|---|
| Known-answer basic transactions | **WIDGET** (`test/services/decoders/apb_decoder_test.dart`) |
| Optional signal handling | **WIDGET** (`apb_decoder_test.dart`) |
| Protocol violation detection | **WIDGET** (`apb_decoder_test.dart`) |
| Multi-instance | **WIDGET** (`test/features/decoders/providers/active_decoders_provider_test.dart` — provider-level multi-instance state model; APB-specific decode covered above) + **INTEGRATION_TEST** (`integration_test/decoders/apb_integration_test.dart` — "APB #1 + APB #2" picker-activation scenario: two decoder-picker activations of APB assert the two-instance `instanceNumber` invariant (1, then 2), distinct `ActiveDecoder.id`s, both instances independently decoding the same 4 transactions, and 8 combined rows in the transaction table) |
| Stress (large transaction count) | **HYBRID** — correctness in `apb_decoder_test.dart`; visual perf at scale remains MANUAL |
| Activation from picker → real FFI parse → 4 transactions in table | **INTEGRATION_TEST** (`integration_test/decoders/apb_integration_test.dart`) |

#### 5.6.9 Captured fixtures

Real-world APB traces acquired from public open-source projects exercise
the decoder against bus traffic produced by upstream IP under permissive
licenses. Each captured fixture lives under
`test/fixtures/protocol/apb/captured/` (mirrored to
`verification/fixtures/protocol/apb/captured/`) as a triplet:
`<name>.fst` + `<name>.fixture.json` (decoder config: signal bindings +
parameters) + `<name>.expected_transactions.json` (regression snapshot).

The auto-discovery sweep test
`test/services/decoders/apb_captured_fixtures_test.dart` walks every
captured fixture, runs the open-core `ApbDecoder` against the trace via
the WellenProvider FFI backend, and snapshot-matches the JSON. Adding a
new fixture is purely additive — drop the triplet in and run
`REGENERATE=1 flutter test test/services/decoders/apb_captured_fixtures_test.dart`.

Pipeline note: APB-side traces have no cocotb dependency. ZipCPU/wb2axip
ships only formal SymbiYosys flows for its APB cores, so we vendor the
relevant RTL modules verbatim (Apache-2.0 headers preserved) and drive
them from a small pure-Verilog testbench under
[`test/fixtures/protocol/apb/captured/helpers/apb/`](../test/fixtures/protocol/apb/captured/helpers/apb/).
Toolchain is icarus-verilog + GTKWave only — no Python venv. This mirrors
the no-cocotb sub-pipeline used for MDIO in the Pro repo.

Current pilot capture:

- `apb_axil2apb.fst` — Ten APB transactions produced by routing an
  AXI-Lite stimulus stream through Gisselquist Technology's `axil2apb`
  bridge into his `apbslave` peripheral. Vendored from
  `ZipCPU/wb2axip` commit `df8e7649`, Apache-2.0. Covers four
  full-width writes, four readbacks, one partial-strobe write
  (`PWSTRB=0x3` updating only the lower 16 bits of `0x100`), and one
  final readback proving byte-merge semantics through the bridge.
  Every transaction is two-cycle (always-ready slave, PSLVERR tied
  low). See
  [`PROVENANCE.md`](../test/fixtures/protocol/apb/captured/PROVENANCE.md)
  for hand-verified anchors.

Manual sign-off:

1. Open `apb_axil2apb.fst` in WaveCrux. Apply the APB decoder with the
   bindings from `apb_axil2apb.fixture.json`. Confirm the first write
   (`W 0x100 = 0xDEADBEEF [OKAY]` at t=85 ns), its later readback (`R
   0x100 → 0xDEADBEEF` at t=325 ns), and the byte-strobe round-trip
   (`R 0x100 → 0xDEADC0DE` at t=625 ns) render correctly in the
   transaction table.
2. Run `flutter test test/services/decoders/apb_captured_fixtures_test.dart`
   and confirm it passes against the committed snapshot (10
   transactions; <1 s on a modern machine).

Automation Assessment:

| What | Automation |
|------|------------|
| Snapshot regression vs `apb_axil2apb.expected_transactions.json` | **WIDGET** (`apb_captured_fixtures_test.dart` — fixture auto-discovery sweep + snapshot diff) |
| Toolchain reproducibility (iverilog + vendored RTL) | **MANUAL** — covered by `helpers/apb/README.md` + `helpers/apb/Makefile` |
| Hand-verified anchors against testbench stimulus | **MANUAL** — anchors documented in `PROVENANCE.md` |

---

### 5.7 Wishbone decoder

#### 5.7.1 What it does

Wishbone is the OpenCores-maintained bus interface used throughout the open-source HDL ecosystem (LiteX, picorv32, NEORV32, mor1kx, and a long tail of community soft cores). It is single-master / single-slave at the wire level (multi-master fabrics arbitrate externally), memory-mapped, and ships in two specification revisions that share the same wire set:

- **B3 Classic standard cycle** (`cyc` envelopes a `stb` pulse held until the slave returns one of `ack`/`err`/`rty`).
- **B3 registered-feedback bursts** (§4 of wbspec_b3) — `cti` selects the burst type (`000` Classic, `001` constant-address, `010` incrementing, `111` end-of-burst) and `bte` selects the wrap modulus for incrementing bursts (`00` linear, `01` 4-beat wrap, `10` 8-beat wrap, `11` 16-beat wrap).
- **B4 Pipelined** — adds `stall` for slave-driven flow control. `stb` pulses once per requested transaction (held while `stall=1`); `ack`/`err`/`rty` are decoupled from `stb` and may arrive multiple cycles later. The decoder tracks an outstanding-request FIFO and emits one transaction per request matched with its termination.

The decoder ships in **Open Core** under the existing **AMBA** category (Wishbone is not part of ARM AMBA but it is the same shape — single-master memory-mapped bus — and the alternative would be a thinly populated standalone category). The display name in the picker is `Wishbone`.

Required signal bindings: `clk`, `rst` (active-high per spec — bind an inverted net for active-low designs), `cyc`, `stb`, `we`, `adr`, `dat_o`, `dat_i`, `ack`. Optional bindings: `sel`, `err`, `rty`, `lock`, `cti` (binding enables burst decode), `bte` (binding enables wrap-burst decode), `stall` (required at decode time when revision = B4), `tga`, `tgd_o`, `tgd_i`, `tgc` (user-defined tags, passed through to the transaction record without semantic interpretation).

Per-instance configuration: `revision` (`b3` or `b4`), `addr_width` (1..64), `data_width` (8/16/32/64), `granularity` (8/16/32/64), `endianness` (`little`/`big`), `check_alignment` (boolean — gate the misalignment violation).

#### 5.7.2 Setup

Seven committed fixtures under `verification/fixtures/protocol/wishbone/` (mirrored to `test/fixtures/protocol/wishbone/`):

| Fixture | What it exercises |
|---|---|
| `wishbone_b3_classic_basic.vcd` | Single read/write/err/rty handshakes (4 transactions). |
| `wishbone_b3_burst_incr.vcd` | Linear (BTE=00) incrementing burst, 4 beats + parent record. |
| `wishbone_b3_burst_wrap.vcd` | 4-beat-wrap (BTE=01) burst with wrap arithmetic + constant-address (CTI=001) burst. |
| `wishbone_b3_classic_violations.vcd` | All 9 B3-mode protocol-violation classes. |
| `wishbone_b4_pipelined_basic.vcd` | Pipelined read + write, no stall, no overlap. |
| `wishbone_b4_pipelined_stall.vcd` | Pipelined back-to-back with stalls and outstanding-count tracking (3 in-flight). |
| `wishbone_b4_pipelined_violations.vcd` | B4-specific violations (signal-change-while-stalled, mutex termination, CYC drop with outstanding). |

Each fixture has a paired `.expected_transactions.json`. Regenerate via `dart run tool/generate_wishbone_fixtures.dart` (see `verification/fixtures/helpers/README.md`).

#### 5.7.3 Steps — B3 Classic basic

1. Load `protocol/wishbone/generated/wishbone_b3_classic_basic.vcd`. Open the decoder picker — verify the `Wishbone` entry appears under **AMBA** alongside AXI4-Lite and APB, with no PRO/ENT badge (Open Core).
2. Apply the Wishbone decoder. Bind all 9 required signals (`clk → tb.CLK`, `rst → tb.RST`, …). Bind `err`, `rty`, `sel` from the optional set.
3. Defaults: `revision=b3`, `addr_width=32`, `data_width=32`, `granularity=8`, `endianness=little`, `check_alignment=true`.
4. Verify exactly **4 transactions** appear and match `wishbone_b3_classic_basic.expected_transactions.json`:
   - `W 0x00000100 = 0xDEADBEEF` (ack, OKAY)
   - `R 0x00000100 → 0x12345678` (ack, OKAY)
   - `R 0x00000200 → 0xBADBADBA [ERR]` (err, isError=true)
   - `W 0x00000300 = 0xCAFEBABE [RTY]` (rty, isError=true)
5. Verify the two terminated-with-error transactions render with the error styling (red border / hatching).

#### 5.7.4 Steps — registered-feedback bursts (CTI / BTE)

1. Load `wishbone_b3_burst_incr.vcd`. Bind `cti` and `bte` in addition to the basic set.
2. Verify **5 transactions**: 4 child beats (each with `fields["cycle"] = "Burst-Incr"` or `"Burst-EOB"` for the last) plus 1 parent record `Burst-Incr 4× W 0x100..0x10C` (`fields["type"] = "Burst"`).
3. Verify the per-beat addresses increment by 4 (data_width=32 → stride=4): `0x100 → 0x104 → 0x108 → 0x10C`.
4. Load `wishbone_b3_burst_wrap.vcd`. Verify two bursts are decoded:
   - 4-beat-wrap incrementing burst (BTE=01) starting at `0x108`. Address sequence wraps within the 16-byte window: `0x108 → 0x10C → 0x100 → 0x104`. Parent label `Burst-Incr/Wrap-4 4× R 0x108..0x104`.
   - Constant-address burst (CTI=001) at `0x200`, three beats with the same address. Parent label `Burst-Const 3× R 0x200`.

#### 5.7.5 Steps — B4 Pipelined and stalls

1. Load `wishbone_b4_pipelined_basic.vcd`. Re-configure the decoder: set `revision=b4`. Bind the basic set plus `stall`.
2. Verify **2 transactions**: a pipelined write (`W 0x00000100 = 0xCAFEBABE [Pipelined]`) with `latency=10` and a pipelined read (`R 0x00000200 → 0xFEEDBEEF [Pipelined]`) with `latency=20`. The latency field is in clock cycles between request issue and termination.
3. Load `wishbone_b4_pipelined_stall.vcd`. Verify **3 transactions** matched in FIFO order: `R 0x100`, `R 0x104`, `R 0x108` — each with its own request-issue startTime and termination endTime.
4. **B4 without stall (graceful degradation)**: in any B4-mode trace, leave `stall` UNBOUND. Verify the decoder emits a single warning transaction at the first edge ("Wishbone B4 selected but `stall` signal not bound — bind it for accurate pipelined decode. Falling back to classic decode.") and then proceeds with classic-mode decode.

#### 5.7.6 Steps — protocol violation detection

Load `wishbone_b3_classic_violations.vcd`. Verify the following violation classes are flagged with `isError = true` and human-readable `errorMessage` text containing the indicated fragment:

| # | Violation | Message fragment |
|---|---|---|
| 1 | Multiple terminations simultaneously (ACK + ERR) | `Multiple terminations` |
| 2 | Termination asserted while CYC deasserted | `Termination (ACK/ERR/RTY) asserted while CYC` |
| 3 | STB asserted while CYC deasserted | `STB asserted while CYC` |
| 4 | WE changed mid-cycle without CYC dropping | `WE changed mid-cycle` |
| 6 | Constant-address burst with ADR change | `Constant-address burst (CTI=001) but ADR changed` |
| 7 | Incrementing burst with WE / SEL change or non-monotonic ADR | `Incrementing burst (CTI=010)` |
| 8 | Reserved CTI value (`011`/`100`/`101`/`110`) | `Reserved CTI value` |
| 9 | BTE non-zero with CTI=000 / 001 | `BTE` |
| 10 | Address misaligned to (data_width / granularity) | `Misaligned address` |

Then load `wishbone_b4_pipelined_violations.vcd`. Verify violation 5 (B4-only) is flagged: `Signal(s) ADR changed while STB asserted and STALL high`. Also verify the mutex-termination violation (1) and the spec-only "CYC dropped with outstanding pipelined request" cascade fire as expected.

#### 5.7.7 Steps — multi-instance and reconfiguration round-trip

1. Add Wishbone #1 with `revision=b3`. Add Wishbone #2 with `revision=b4` and a different `data_width=64`. Verify both decoders coexist on the transaction lane and produce independent transaction streams.
2. Save the session (`File → Save Session`). Reload from the `.wavecrux` file. Verify both decoder instances restore with their per-instance bindings AND parameter values intact (revision, addr_width, data_width, granularity, endianness, check_alignment).
3. Reconfigure Wishbone #1 (toggle `check_alignment=false`). Reload the violations fixture and verify the misalignment violation no longer fires while the other 8 violation classes still do.

#### 5.7.8 Edge cases

1. **CTI/BTE unbound**: bind a B3 burst trace with neither `cti` nor `bte` bound. Every cycle decodes as `Classic` — burst structure is invisible without CTI. No violations.
2. **Tag signals bound (TGA / TGD / TGC)**: bind any combination of the four tag signals. Verify their values appear in the transaction `fields` map (e.g. `fields["tga"] = "0x..."`) without affecting decode logic.
3. **Reset behavior**: assert `rst` mid-burst. Verify any in-flight burst parent is emitted at reset time and a clean restart begins on the next CYC edge.
4. **Empty trace**: load a VCD with no clock activity in the trace window. Verify the decoder returns an empty transaction list (no spurious violations).

#### 5.7.9 Automation Assessment

| Test | Coverage |
|---|---|
| Definition (id, displayName, category, tier, signal/parameter sets) | **WIDGET** (`test/services/decoders/wishbone_decoder_test.dart` — "definition" group) |
| B3 Classic basic R/W/ERR/RTY | **WIDGET** (`wishbone_decoder_test.dart` — "B3 Classic" group) |
| B3 protocol violations (each of the 9 classes) | **WIDGET** (`wishbone_decoder_test.dart` — "B3 violations" group + fixture round-trip) |
| B3 registered-feedback bursts (CTI/BTE matrix) | **WIDGET** (fixture round-trip — `wishbone_b3_burst_incr` and `wishbone_b3_burst_wrap`) |
| Address-misalignment + `check_alignment` toggle | **WIDGET** (`wishbone_decoder_test.dart`) |
| B4 Pipelined basic + latency capture | **WIDGET** (`wishbone_decoder_test.dart` — "B4 Pipelined" group) |
| B4 stall flow control + outstanding FIFO ordering | **WIDGET** (fixture round-trip — `wishbone_b4_pipelined_stall`) |
| B4 stall-unbound graceful degradation | **WIDGET** (`wishbone_decoder_test.dart` — "B4 Pipelined" group) |
| B4 signal-change-while-stalled violation | **WIDGET** (`wishbone_decoder_test.dart` + fixture round-trip) |
| Multi-width formatting (8/16/32/64-bit data, 1..64-bit addr) | **WIDGET** (`wishbone_decoder_test.dart` — "multi-width formatting" group) |
| Multi-instance independence | **WIDGET** (`test/features/decoders/providers/active_decoders_provider_test.dart` — provider-level multi-instance state model; Wishbone-specific decode covered above) |
| Picker presence under AMBA category | **WIDGET** (`test/features/decoders/widgets/decoder_picker_dialog_open_core_set_test.dart`) |
| Visual rendering of bursts and violations on the canvas | **MANUAL** — render perception is unautomated |
| Real-world LiteX / picorv32 trace cross-check | **WIDGET** (`wishbone_captured_fixtures_test.dart` — `wishbone_picorv32_wb_ez.fst` captures live RV32I ifetch + load/store traffic from `picorv32_wb`; LiteX-specific capture remains a future enhancement) |
| Activation from picker → real FFI parse → 4 transactions in table | **INTEGRATION_TEST** (`integration_test/decoders/wishbone_integration_test.dart`) |

#### 5.7.10 Captured fixtures

Real-world Wishbone traces acquired from public open-source projects
exercise the decoder against bus traffic produced by upstream IP under
permissive licenses. Each captured fixture lives under
`test/fixtures/protocol/wishbone/captured/` (mirrored to
`verification/fixtures/protocol/wishbone/captured/`) as a triplet:
`<name>.fst` + `<name>.fixture.json` (decoder config: signal bindings +
parameters) + `<name>.expected_transactions.json` (regression snapshot).

The auto-discovery sweep test
`test/services/decoders/wishbone_captured_fixtures_test.dart` walks
every captured fixture, runs the open-core `WishboneDecoder` against
the trace via the WellenProvider FFI backend, and snapshot-matches the
JSON. Adding a new fixture is purely additive — drop the triplet in
and run
`REGENERATE=1 flutter test test/services/decoders/wishbone_captured_fixtures_test.dart`.

Pipeline note: no cocotb dependency. YosysHQ's `picorv32` ships its
own Icarus testbench but the upstream WB flow needs a RISC-V GNU
toolchain to build the firmware hex. We sidestep that by vendoring
`picorv32.v` (ISC) and driving its `picorv32_wb` variant from a small
in-tree testbench whose memory is preloaded with the same
six-instruction loop the upstream `testbench_ez.v` uses (public
domain). Toolchain is icarus-verilog only — no Python, no RISC-V
GCC. Helpers live under
[`test/fixtures/protocol/wishbone/captured/helpers/picorv32/`](../test/fixtures/protocol/wishbone/captured/helpers/picorv32/).

Current pilot capture:

- `wishbone_picorv32_wb_ez.fst` — Ten Wishbone B3 Classic transactions
  produced by letting `picorv32_wb` execute a tight counter loop:
  sequential instruction fetches plus the `lw`/`sw` of a counter at
  `0x3FC`. Vendored from `YosysHQ/picorv32` commit `87c89ac`, ISC.
  Mixes ifetch reads (`sel=0x0`), data-load reads, and full-word
  data stores (`sel=0xF`) — the kind of composite RISC-V-on-WB
  traffic that the synthetic generated/ fixtures don't cover.
  Single-cycle ack on every transfer; no errors or retries. See
  [`PROVENANCE.md`](../test/fixtures/protocol/wishbone/captured/PROVENANCE.md)
  for hand-verified anchors.

Manual sign-off:

1. Open `wishbone_picorv32_wb_ez.fst` in WaveCrux. Apply the
   Wishbone decoder with the bindings from
   `wishbone_picorv32_wb_ez.fixture.json`. Confirm the first ifetch
   (`R 0x00000000 → 0x3FC00093` at t=80 ns, the `li x1, 1020`
   instruction), the counter init (`W 0x000003FC = 0x00000000` at
   t=250 ns), and the first incremented store (`W 0x000003FC =
   0x00000001` at t=530 ns) render correctly in the transaction
   table.
2. Run `flutter test test/services/decoders/wishbone_captured_fixtures_test.dart`
   and confirm it passes against the committed snapshot (10
   transactions; <1 s on a modern machine).

Automation Assessment:

| What | Automation |
|------|------------|
| Snapshot regression vs `wishbone_picorv32_wb_ez.expected_transactions.json` | **WIDGET** (`wishbone_captured_fixtures_test.dart` — fixture auto-discovery sweep + snapshot diff) |
| Toolchain reproducibility (iverilog + vendored picorv32.v + in-tree tb) | **MANUAL** — covered by `helpers/picorv32/README.md` + `helpers/picorv32/Makefile` |
| Hand-verified anchors against RV32I encoding | **MANUAL** — anchors documented in `PROVENANCE.md` |

---

### 5.8 AHB-Lite decoder

#### 5.8.1 What it does

AHB-Lite is the single-master simplification of the ARM AMBA AHB bus, introduced in AMBA 3 (Arm IHI 0033). It keeps the two-phase pipelined transfer model — one-cycle address phase, one-or-more-cycle data phase, controlled by `HREADY` from the slave — but drops bus arbitration and the four-state response of full AHB; `HRESP` becomes a single bit (OKAY / ERROR). It is the workhorse interconnect inside the Cortex-M family and is the AMBA member that sits between APB (low-bandwidth peripherals) and AXI4 full (high-bandwidth, out-of-order) on the speed/complexity axis.

The decoder ships in **Open Core** under the existing **AMBA** category. The display name in the picker is `AHB-Lite`. Coverage at launch:

- All `HBURST` variants: SINGLE, INCR (undefined-length), INCR4 / INCR8 / INCR16 (fixed-length incrementing), WRAP4 / WRAP8 / WRAP16 (wrapping with the spec-defined `beats × stride` modulus).
- All `HSIZE` encodings up to 1024-bit (`HSIZE = 0` byte through `HSIZE = 7` 32-word).
- Full `HTRANS` state machine (IDLE / BUSY / NONSEQ / SEQ).
- HREADY-driven wait states (data-phase extension; the wait-state count is recorded on each beat).
- Two-cycle ERROR response handshake (HREADY=0,HRESP=1 → HREADY=1,HRESP=1 — IHI 0033 §3.8.2).
- Optional `HMASTLOCK` (locked transfers / atomic primitives) — surfaced on each beat and on burst-parent records.
- Optional `HPROT` (protection control) — decoded into the four named flags (data/instr, privileged, bufferable, cacheable) and surfaced informationally on each beat.
- Bursts emitted as a parent transaction spanning the full burst plus one child beat per transfer; the `burst_id` field links them, matching the AXI4 / Wishbone model.

Required signal bindings: `hclk`, `hresetn` (active-low; bind an inverted net for active-high reset designs), `haddr`, `htrans`, `hwrite`, `hsize`, `hburst`, `hwdata`, `hrdata`, `hready`, `hresp`. Optional bindings: `hprot`, `hmastlock`.

Per-instance configuration: `addr_width` (1..64, default 32), `data_width` (8/16/32/64/128/256/512/1024, default 32 — caps the legal HSIZE), `check_alignment` (boolean, default true — gate the misalignment violation), `wait_state_threshold` (integer, default 256 — soft warning threshold for stalled HREADY).

The decoder uses a single-edge pipeline model: at each rising HCLK edge, an in-flight transfer (if any) is completed by sampling that edge's HREADY/HRESP/HWDATA/HRDATA, and the same edge's address-phase signals (when HTRANS is NONSEQ or SEQ) are latched as the new in-flight transfer. This collapses the strict two-edge AHB pipeline by one cycle but preserves correctness of every transaction's address, data, response, and burst grouping. The trade-off is documented inline in `lib/services/decoders/ahb_lite_decoder.dart` and means one spec-derived violation (the master-must-hold-address-phase-stable-during-wait-state rule, IHI 0033 §3.4) is not detected here — the simulator's own assertion checks remain the authoritative source for that class of bug.

#### 5.8.2 Setup

Eight committed fixtures under `verification/fixtures/protocol/ahb_lite/` (mirrored to `test/fixtures/protocol/ahb_lite/`):

| Fixture | What it exercises |
|---|---|
| `ahb_lite_single_basic.vcd` | One SINGLE read followed by one SINGLE write, both OKAY (2 transactions). |
| `ahb_lite_incr_burst.vcd` | INCR4 read burst — 4 child beats + 1 parent record. |
| `ahb_lite_wrap_burst.vcd` | WRAP4 read burst starting at 0x108, wraps inside the 16-byte window: 0x108 → 0x10C → 0x100 → 0x104. |
| `ahb_lite_incr_undefined.vcd` | INCR (undefined-length) read with mid-burst BUSY insertion; burst ended by HTRANS=IDLE. |
| `ahb_lite_wait_states.vcd` | SINGLE read with two HREADY=0 wait states; `wait_states` field recorded on the beat. |
| `ahb_lite_error_response.vcd` | SINGLE write completed with the proper two-cycle ERROR handshake. |
| `ahb_lite_locked_transfer.vcd` | HMASTLOCK-protected read followed by HMASTLOCK-protected write (read-modify-write); HPROT bound to a representative privileged-data value. |
| `ahb_lite_violations.vcd` | Exercises the seven detectable protocol-violation classes (1–7). |

Each fixture has a paired `.expected_transactions.json`. Regenerate via `dart run tool/generate_ahb_lite_fixtures.dart` (see `verification/fixtures/helpers/README.md`).

#### 5.8.3 Steps — SINGLE basic

1. Load `protocol/ahb_lite/generated/ahb_lite_single_basic.vcd`. Open the decoder picker — verify the `AHB-Lite` entry appears under **AMBA** alongside AXI4-Lite, APB, and Wishbone, with no PRO/ENT badge (Open Core).
2. Apply the AHB-Lite decoder. Bind all 11 required signals (`hclk → tb.HCLK`, `hresetn → tb.HRESETN`, …). Leave the two optional bindings (`hprot`, `hmastlock`) unbound.
3. Defaults: `addr_width=32`, `data_width=32`, `check_alignment=true`, `wait_state_threshold=256`.
4. Verify exactly **2 transactions** appear and match `ahb_lite_single_basic.expected_transactions.json`:
   - `R 0x00000100 → 0x12345678` (OKAY)
   - `W 0x00000200 = 0xDEADBEEF` (OKAY)
5. Verify the `hprot_*` and `locked` field-sub-keys are ABSENT from each transaction's fields panel (because the optional signals are unbound).

#### 5.8.4 Steps — bursts (INCR4 / INCR / WRAP4)

1. Load `ahb_lite_incr_burst.vcd`. Verify **5 transactions**: 4 child beats (each with `fields["beat_index"]` 1..4 and `fields["burst"] = "INCR4"`) plus 1 parent record `INCR4 4× R 0x100..0x10C` with `fields["type"] = "Burst"` and `fields["beats"] = "4"`. The per-beat addresses are `0x100 → 0x104 → 0x108 → 0x10C` (stride 4 from HSIZE=word).
2. Load `ahb_lite_wrap_burst.vcd`. Verify the WRAP4 burst's beats wrap inside the 16-byte window: `0x108 → 0x10C → 0x100 → 0x104` with parent label `WRAP4 4× R 0x108..0x104`. Note: the start address (`0x108`) is mid-window — this is valid, the spec only requires HSIZE-alignment of the start.
3. Load `ahb_lite_incr_undefined.vcd`. Verify **3 child beats** (at 0x200, 0x204, 0x208) plus 1 parent record `INCR 3× R 0x200..0x208`. The mid-burst BUSY at cycle 2 does not produce an extra beat — it pauses the burst, and the subsequent SEQ resumes.

#### 5.8.5 Steps — wait states and ERROR handshake

1. Load `ahb_lite_wait_states.vcd`. Verify **1 beat** (`R 0x00000100 → 0xCAFE0001`) with `fields["wait_states"] = "2"`. The transaction's startTime/endTime span the full address-phase + extended-data-phase duration.
2. Load `ahb_lite_error_response.vcd`. Verify **1 beat** (`W 0x00000300 = 0xBADF00D1 [ERROR]`) with `isError = true`, `fields["response"] = "ERROR"`, and `errorMessage = "Response = ERROR"` — the two-cycle handshake is satisfied so the decoder does NOT additionally emit the violation-7 message.

#### 5.8.6 Steps — locked transfer (HMASTLOCK / HPROT)

1. Load `ahb_lite_locked_transfer.vcd`. Re-configure the decoder: bind `hprot → tb.HPROT` and `hmastlock → tb.HMASTLOCK` from the optional set.
2. Verify **2 transactions** (a locked read + a locked write to 0x400). Both beats carry:
   - `fields["locked"] = "1"`
   - `fields["hprot"] = "0x3"`
   - `fields["hprot_data_or_instr"] = "data"`
   - `fields["hprot_privileged"] = "1"`
   - `fields["hprot_bufferable"] = "0"`
   - `fields["hprot_cacheable"] = "0"`
3. Optional: re-load with the optional signals UNBOUND. Verify the `locked` and `hprot*` keys are absent — graceful degradation matches the Wishbone CTI/BTE precedent.

#### 5.8.7 Steps — protocol violation detection

Load `ahb_lite_violations.vcd`. Verify each violation class is flagged with `isError = true` and a human-readable `errorMessage` containing the indicated fragment:

| # | Violation | Message fragment |
|---|---|---|
| 1 | HTRANS=BUSY without an active multi-beat burst | `HTRANS=BUSY` |
| 2 | HTRANS=SEQ without preceding NONSEQ | `without a preceding NONSEQ` |
| 3 | HBURST changed mid-burst | `HBURST changed mid-burst` |
| 4 | HADDR does not match expected next beat (INCR / WRAP arithmetic) | `does not match expected next beat` |
| 5 | HSIZE wider than `data_width` | `HSIZE encodes a 64-bit` |
| 6 | HADDR misaligned to (1 << HSIZE) | `Misaligned HADDR` |
| 7 | HRESP=ERROR with HREADY=1 on the very first cycle of the data phase (no preceding two-cycle handshake) | `without two-cycle handshake` |

Violation 8 (HREADY held low > `wait_state_threshold` consecutive cycles, surfaced as a soft warning with `errorMessage` prefix `warn:`) is not exercised by a fixture — set the parameter to a small value (e.g. `wait_state_threshold=1`) on the wait-state fixture to trigger it during ad-hoc verification.

#### 5.8.8 Steps — multi-instance and per-instance configuration round-trip

1. Add AHB-Lite #1 with `data_width=32`. Add AHB-Lite #2 with `data_width=64` and `check_alignment=false`. Verify both decoders coexist on the transaction lane and produce independent transaction streams.
2. Save the session (`File → Save Session`). Reload from the `.wavecrux` file. Verify both decoder instances restore with their per-instance bindings AND parameter values intact (`addr_width`, `data_width`, `check_alignment`, `wait_state_threshold`).
3. Reconfigure AHB-Lite #1: toggle `check_alignment = false`. Reload `ahb_lite_violations.vcd` and verify the misalignment violation (violation 6) no longer fires while the other six violation classes still do.

#### 5.8.9 Edge cases

1. **Optional signals unbound**: in any fixture, leave `hprot` and `hmastlock` unbound. Verify the corresponding `fields` keys are absent on every transaction (no spurious zeros, no error transactions).
2. **Reset mid-burst**: assert `hresetn = 0` mid-burst. Verify any in-flight burst-parent record is emitted at the reset edge with the beats accumulated so far; subsequent transfers after `hresetn` rises decode normally.
3. **Empty trace**: load a VCD with no clock activity in the trace window. Verify the decoder returns an empty transaction list (no spurious violations).
4. **Address-phase-stability-across-wait-states (intentional gap)**: the spec rule that the master must hold HADDR/HTRANS/HSIZE/HBURST/HPROT/HMASTLOCK stable while HREADY=0 (IHI 0033 §3.4) is **not** detected by this decoder — see the rationale in the file-level docstring. Manual inspection of the waveform is required for this class of bug.

#### 5.8.10 Captured fixture — shalan MS_DMAC_AHBL

In addition to the synthetic `generated/` corpus, a real RTL-driven
AHB-Lite trace sits in
`verification/fixtures/protocol/ahb_lite/captured/` (mirrored to
`test/fixtures/protocol/ahb_lite/captured/`). The capture exercises
the decoder against actual `MS_DMAC_AHBL`-produced bus traffic
rather than a hand-emitted edge sequence.

The auto-discovery sweep test
`test/services/decoders/ahb_lite_captured_fixtures_test.dart` walks
every captured fixture, runs `AhbLiteDecoder` against the trace via
the WellenProvider FFI backend, and snapshot-matches the JSON.
Adding a new captured fixture is purely additive — drop the triplet
in and run
`REGENERATE=1 flutter test test/services/decoders/ahb_lite_captured_fixtures_test.dart`.

Source choice: OpenTitan's `hw/ip/...` would have been the obvious
first pick, but OpenTitan's verification flow is UVM-based (Synopsys
VCS), which iverilog/verilator don't support. Mohamed Shalan's
`MS_DMAC_AHBL` (Apache-2.0) is a clean educational/ASIC-grade DMA
controller with both slave and master AHB-Lite ports — a single
module produces meaningful bus traffic without external glue.
Helpers live under
[`test/fixtures/protocol/ahb_lite/captured/helpers/shalan/`](../test/fixtures/protocol/ahb_lite/captured/helpers/shalan/).

Current pilot capture:

- `ahb_lite_shalan_dmac.fst` — 10 SINGLE-beat transactions covering
  5 word-stride read+write pairs. A pure-Verilog testbench drives
  the DMAC's slave port through four register writes
  (SADDR/DADDR/SIZE/CTRL) followed by a software trigger; the DMAC
  then marches through 5 word reads from `0x4000_0000…0x4000_0010`
  and 5 word writes to `0x5000_0000…0x5000_0010` on its master
  port. HBURST and HRESP are tied to constants (SINGLE / OKAY)
  since the DMAC implements neither — the synthetic `generated/`
  corpus already covers bursts and error responses. Vendored from
  `shalan/MS_DMAC_AHBL` commit `d2ea9e3`, Apache-2.0. See
  [`PROVENANCE.md`](../test/fixtures/protocol/ahb_lite/captured/PROVENANCE.md)
  for hand-verified anchors.

Manual sign-off:

1. Open `ahb_lite_shalan_dmac.fst` in WaveCrux. Apply the AHB-Lite
   decoder with the bindings from
   `ahb_lite_shalan_dmac.fixture.json` (all `M_H*` master-port
   signals plus `M_HBURST` / `M_HRESP` tied wires). Confirm the
   transaction table shows 10 alternating R/W transactions stepping
   through `0x4000_0000` (read source) and `0x5000_0000` (write
   destination) at word stride.
2. Run `flutter test test/services/decoders/ahb_lite_captured_fixtures_test.dart`
   and confirm it passes against the committed snapshot (10
   transactions; <1 s on a modern machine).

Automation Assessment:

| What | Automation |
|------|------------|
| Snapshot regression vs `ahb_lite_shalan_dmac.expected_transactions.json` | **WIDGET** (`ahb_lite_captured_fixtures_test.dart` — fixture auto-discovery sweep + snapshot diff) |
| Toolchain reproducibility (iverilog + vendored MS_DMAC_AHBL + in-tree tb) | **MANUAL** — covered by `helpers/shalan/README.md` + `helpers/shalan/Makefile` |
| Hand-verified anchors against the testbench program | **MANUAL** — anchors documented in `PROVENANCE.md` |

#### 5.8.11 Automation Assessment

| Test | Coverage |
|---|---|
| Definition (id, displayName, category, tier, signal/parameter sets) | **WIDGET** (`test/services/decoders/ahb_lite_decoder_test.dart` — "definition" group) |
| SINGLE basic R/W round-trip vs. fixture JSON | **WIDGET** (`ahb_lite_decoder_test.dart` — "SINGLE basic fixture" group) |
| INCR4 burst — 4 beats + parent record | **WIDGET** (fixture round-trip — `ahb_lite_incr_burst`) |
| WRAP4 burst — wrap arithmetic inside 16-byte window | **WIDGET** (fixture round-trip — `ahb_lite_wrap_burst`) |
| INCR (undefined-length) burst with BUSY insertion | **WIDGET** (fixture round-trip — `ahb_lite_incr_undefined`) |
| Wait-state accounting on the SINGLE beat | **WIDGET** (fixture round-trip — `ahb_lite_wait_states`) |
| Two-cycle ERROR response (no spurious violation 7) | **WIDGET** (fixture round-trip — `ahb_lite_error_response`) |
| HPROT decode + HMASTLOCK propagation into fields | **WIDGET** (fixture round-trip — `ahb_lite_locked_transfer`) |
| Protocol violations 1..7 each exercised by at least one fixture | **WIDGET** (`ahb_lite_decoder_test.dart` — "protocol violations fixture" group) |
| `check_alignment` parameter toggles violation 6 | **WIDGET** (`ahb_lite_decoder_test.dart` — "check_alignment parameter" group) |
| `data_width` parameter unlocks 64-bit HSIZE | **WIDGET** (`ahb_lite_decoder_test.dart` — "data_width parameter" group) |
| Optional bindings (hprot / hmastlock) absent vs. present | **WIDGET** (`ahb_lite_decoder_test.dart` — "optional bindings" group) |
| Reset mid-burst flushes burst-parent record | **WIDGET** (`ahb_lite_decoder_test.dart` — "reset" group) |
| Multi-instance independence | **WIDGET** (`ahb_lite_decoder_test.dart` — "multi-instance independence" group; provider-level state model covered in `test/features/decoders/providers/active_decoders_provider_test.dart`) |
| Per-instance configuration round-trip through session save/load | **UNIT** (`test/services/session/session_decoder_round_trip_test.dart` — "two AHB-Lite instances round-trip distinct mixed-type per-instance configuration" saves two AHB-Lite instances with different `addr_width`/`data_width`/`check_alignment`/`wait_state_threshold` through `SessionService.saveSession`/`loadSession`, asserting integer params survive without an int→double coercion and the two instances stay independent). Full in-app session-save/load loop still exercised manually in §5.8.8. |
| Picker presence under AMBA category (CJK locale sweep) | **WIDGET** (`test/features/decoders/widgets/decoder_picker_dialog_open_core_set_test.dart`) |
| Visual rendering of bursts and violations on the canvas | **MANUAL** — render perception is unautomated |
| Wait-state warning (violation 8) at `wait_state_threshold` | **MANUAL** — exercise by lowering the threshold parameter on `ahb_lite_wait_states.vcd` |
| Address-phase stability during wait state (IHI 0033 §3.4) | **MANUAL** — intentional decoder gap; rely on simulator assertions |
| Captured-fixture snapshot regression (shalan MS_DMAC_AHBL master traffic) | **WIDGET** (`ahb_lite_captured_fixtures_test.dart` — fixture auto-discovery sweep + snapshot diff; see §5.8.10) |
| Activation from picker → real FFI parse → 2 transactions in table | **INTEGRATION_TEST** (`integration_test/decoders/ahb_lite_integration_test.dart`) |

---

### 5.9 RISC-V instruction-trace decoder

#### 5.9.1 What it does

The RISC-V decoder turns an instruction-fetch trace into human-readable disassembly: at every rising fetch-clock edge it samples the bound `instruction` word, optionally reads a `pc` signal alongside, and emits one transaction per instruction with the mnemonic, ABI register names, and signed/unsigned/hex immediates rendered the way an HDL engineer expects.

It is the first **instruction-trace** decoder in WaveCrux (a new `DecoderCategory.instructionTrace`, distinct from the bus categories), and it ships in **Open Core**. Coverage at launch:

- **RV32I** and **RV64I** baseline integer ISAs.
- Standard extensions **M** (mul/div), **A** (atomics — representative subset), **F** (single-precision FP — representative subset), **D** (double-precision FP, RV64 only — matches JKU's bundle), **C** (compressed, "lower" variant in the low 16 bits of a 32-bit signal).
- Vendor extensions and the V (vector) extension are **explicitly Pro tier** and out of scope for this phase.

The decoder uses a TOML-driven schema designed by JKU (the same schema Surfer's `instruction-decoder` crate consumes), so a `.toml` file authored for either tool drops into the other unmodified. The bundled assets in `wavecrux/assets/decoders/isa/riscv/` are hand-authored against that schema for launch coverage; see `assets/decoders/isa/riscv/NOTICE.md` and the project `NOTICES` for attribution.

Required signal bindings: `clk` (1-bit), `instruction` (32-bit). Optional: `valid` (gates fetch — when unbound, every rising edge is treated as a valid fetch), `pc` (XLEN-bit program counter; rendered alongside the disassembly when bound).

Per-instance configuration: `xlen` (32 or 64), and boolean toggles for each extension (`ext_m`, `ext_a`, `ext_f`, `ext_d`, `ext_c`). Toggling an extension off makes the corresponding instructions decode as `UNKNOWN INSN (0x…)`.

#### 5.9.2 Setup

Four committed fixtures under `verification/fixtures/protocol/riscv/` (mirrored to `test/fixtures/protocol/riscv/`):

| Fixture | What it exercises |
|---|---|
| `riscv_rv32i_basic.vcd` | One instruction per RV32I format: R, I-ALU, S, I-Load, U, system. |
| `riscv_rv32im_arith.vcd` | M-extension: `mul`, `div`, `divu`, `rem`. Tests gating: with `ext_m=false` they go UNKNOWN. |
| `riscv_rv64i_basic.vcd` | RV64-only: `ld`, `sd`, `addw`, plus the redefined 6-bit-shamt `slli`. |
| `riscv_pc_present.vcd` | Three instructions with PC bound. Verifies PC labeling and field. |

Each fixture has a paired `.expected_transactions.json`. Regenerate via `dart run tool/generate_riscv_fixtures.dart` (see `verification/fixtures/helpers/README.md`).

#### 5.9.3 Steps — RV32I baseline

1. Load `protocol/riscv/generated/riscv_rv32i_basic.vcd`. Open the decoder picker — verify a new **Instruction Trace** category appears with the RISC-V entry.
2. Apply the RISC-V decoder. Bind `clk → tb.clk`, `instruction → tb.instruction`. Leave `valid` and `pc` unbound. Defaults: `xlen=32`, `ext_m=true`, `ext_c=true`, others off.
3. Verify exactly **6** transactions appear, one per cycle (t = 5, 15, 25, 35, 45, 55 ns).
4. Verify each transaction's `label` matches the corresponding entry in `riscv_rv32i_basic.expected_transactions.json`. Specifically:
   - `add a0, a1, a2`
   - `addi t0, t1, 10`
   - `sw t1, 8(sp)`
   - `lw a0, 12(sp)`
   - `lui a0, 0x12345`
   - `ecall`
5. Verify each transaction's `fields` carry the mnemonic, the disassembly text, the raw 32-bit hex, and the contributing `isa` (e.g. `RV32I`).

#### 5.9.4 Steps — extension gating

1. Load `protocol/riscv/generated/riscv_rv32im_arith.vcd`. Apply RISC-V decoder. Bindings: `clk` and `instruction`. Toggle **off** `ext_m`.
2. Verify all 4 transactions decode as **`UNKNOWN INSN (0x…)`** with `isError = true`.
3. Re-configure with `ext_m=true`. Verify the 4 transactions now decode to `mul a0, a1, a2`, `div a0, a1, a2`, `divu a0, a1, a2`, `rem a0, a1, a2`.

#### 5.9.5 Steps — XLEN selection (RV64)

1. Load `protocol/riscv/generated/riscv_rv64i_basic.vcd`. Apply RISC-V decoder. Set `xlen=64`. Bindings: `clk` and `instruction`.
2. Verify the 4 transactions decode to `ld a0, 16(sp)`, `sd t1, 24(sp)`, `addw a0, a1, a2`, `slli t0, t1, 32`.
3. Reconfigure with `xlen=32`. The first three decode as **UNKNOWN** (their opcodes are RV64-only). The last one (`slli` with shamt=32) also goes UNKNOWN — RV32I's slli mask requires bit 25 = 0, but `shamt=32` sets bit 25.

#### 5.9.6 Steps — PC binding and `valid` gating

1. Load `protocol/riscv/generated/riscv_pc_present.vcd`. Apply RISC-V decoder. Bind `clk`, `instruction`, **and** `pc → tb.pc`.
2. Verify each transaction's `label` is prefixed `[0x80000000]`, `[0x80000004]`, `[0x80000008]` (XLEN=32 → 8-nibble PC formatting).
3. Verify each `fields["pc"]` matches.
4. **`valid` gating** (no fixture; manual): in any RV32I trace, also bind `valid` to a signal that is high in cycles 0, 2, 4 and low in 1, 3. Verify only the high-valid cycles emit transactions; low-valid cycles are silently skipped.

#### 5.9.7 Steps — error surface

1. Place an x/z value on `instruction` at a cycle where `valid` is high. Verify the decoder skips that cycle (no transaction at all — not an error transaction; per CLAUDE.md the user shouldn't be misled into thinking an unknown bit pattern is a real instruction).
2. Place a known-bad encoding (e.g. all zeros: `0x00000000`) at a cycle. Verify the decoder emits an `UNKNOWN INSN (0x00000000)` error transaction — `isError = true`, `errorMessage` non-null.

#### 5.9.8 Steps — Surfer cross-tool compatibility

The TOML schema is shared with JKU's `instruction-decoder` (used by Surfer). To verify:

1. Take any `.toml` file from <https://github.com/ics-jku/instruction-decoder/tree/master/toml> (e.g. their `RV32I.toml`) and place it next to or replace the bundled `assets/decoders/isa/riscv/RV32I.toml`.
2. Re-run the test suite. The decoder must produce equivalent disassembly for known-answer instructions. Any divergence is a code-review-blocking bug.

The corpus is **discovered** from the asset manifest, so a file dropped into `assets/decoders/isa/riscv/` is picked up with no code change — but note that a *new* set name only reaches the `riscv` decoder if `RiscvDecoder._resolveInstructionSets` names it, since the RISC-V extension toggles map onto specific set names. A dropped-in file is always visible to the shared disassembler behind the RISC-V value-column translator. Discovered sets load in the canonical order defined by `compareIsaSetNames` (narrower base width first, then lexicographic), which is what makes RV64I's redefined `slli`/`srli`/`srai` win over RV32I's under "last match wins".

(Schema fidelity is also covered by the unit tests' "parses without error" group over every bundled file.)

#### 5.9.9 Captured fixture — picorv32_wb instruction-fetch trace

In addition to the four hand-emitted `generated/` fixtures, a real
RTL-driven ifetch trace sits in
`verification/fixtures/protocol/riscv/captured/` (mirrored to
`test/fixtures/protocol/riscv/`). The capture exercises the decoder
against actual `picorv32_wb`-produced bus traffic rather than a
synthetic clock-aligned instruction stream.

The auto-discovery sweep test
`test/services/decoders/riscv_captured_fixtures_test.dart` walks every
captured fixture, runs `RiscvDecoder` against the trace via the
WellenProvider FFI backend, and snapshot-matches the JSON. Adding a
new captured fixture is purely additive — drop the triplet in and run
`REGENERATE=1 flutter test test/services/decoders/riscv_captured_fixtures_test.dart`.

Pipeline note: no cocotb dependency, no RISC-V GNU toolchain. We
vendor `picorv32.v` (ISC) and drive its `picorv32_wb` variant from a
small in-tree testbench whose WB slave memory is preloaded with the
same six-instruction loop the upstream `testbench_ez.v` uses (public
domain). The testbench additionally connects `picorv32_wb`'s
`mem_instr` port (otherwise tied off) and exposes a derived
`ifetch_valid = wb_ack & mem_instr` strobe so the RISC-V decoder's
`valid` binding selects only completed instruction fetches and skips
data load/store reads that share `wb_ack`. Helpers live under
[`test/fixtures/protocol/riscv/captured/helpers/picorv32/`](../test/fixtures/protocol/riscv/captured/helpers/picorv32/).

The Ibex capture uses a second pipeline — Verilator rather than
iverilog, `ibex_top` fetched at a pinned commit rather than vendored,
and a post-run trim step — but keeps the same two constraints: no
cocotb, and no RISC-V GNU toolchain (the program is hand-encoded by
`helpers/ibex/assemble.py`).

Current captures:

- `riscv_ibex_rvfi_trap.fst` — 26 retirements off lowRISC's Ibex
  (Apache-2.0, commit `3250d994`) captured through the RISC-V Formal
  Interface with Verilator 5.050 and `+define+RVFI`. Arithmetic,
  word/byte/halfword load-store pairs, a taken forward `beq`, a
  three-iteration backward `bne` loop, and an `ecall` into the reset
  `mtvec` vector. Ibex is fetched at a pinned commit rather than
  vendored — `ibex_top` is ~30 RTL files plus lowRISC's prim libraries.
  1841 bytes committed, trimmed from a 42530-byte full-hierarchy dump
  because Verilator ignores `$dumpvars` scope arguments. Its two `csrrs`
  and its `wfi` decode as `UNKNOWN INSN`, correctly: there is no Zicsr
  TOML in `assets/decoders/isa/riscv/`. Exercised in depth by §10B.1.10,
  which is also where the two upstream Ibex RVFI deviations this capture
  found are written up. Helpers under
  [`.../captured/helpers/ibex/`](../test/fixtures/protocol/riscv/captured/helpers/ibex/).
- `riscv_picorv32_wb_ez.fst` — Seven RV32I ifetch completions covering
  one full pass through the upstream loop body plus the wrap-around
  fetch after the `jal`. Mnemonics include `addi` (the `li`
  pseudo-form), `sw`, `lw`, and `jal`. Vendored from `YosysHQ/picorv32`
  commit `87c89ac`, ISC. The `jal`'s formatted immediate field shows
  `-2561` rather than the architectural `-12` — this is the documented
  JKU/Surfer schema behavior (§5.9.11); the PC chain is correct (next
  ifetch at PC=0x08). See
  [`PROVENANCE.md`](../test/fixtures/protocol/riscv/captured/PROVENANCE.md)
  for hand-verified anchors.

Manual sign-off:

1. Open `riscv_picorv32_wb_ez.fst` in WaveCrux. Apply the RISC-V
   decoder with the bindings from `riscv_picorv32_wb_ez.fixture.json`
   (`clk → tb_picorv32_riscv_ez.wb_clk`, `instruction →
   tb_picorv32_riscv_ez.wb_dat_s2m`, `pc → tb_picorv32_riscv_ez.wb_adr`,
   `valid → tb_picorv32_riscv_ez.ifetch_valid`). Confirm the first
   ifetch (`[0x00000000] addi ra, zero, 1020` at t=80 ns), the
   backward branch (`[0x00000014] jal zero, …` at t=480 ns), and the
   loop wrap-around (`[0x00000008] lw sp, 0(ra)` at t=590 ns) render
   in the transaction table.
2. Run `flutter test test/services/decoders/riscv_captured_fixtures_test.dart`
   and confirm it passes against the committed snapshot (7
   transactions; <1 s on a modern machine).

Automation Assessment:

| What | Automation |
|------|------------|
| Snapshot regression vs `riscv_picorv32_wb_ez.expected_transactions.json` | **WIDGET** (`riscv_captured_fixtures_test.dart` — fixture auto-discovery sweep + snapshot diff) |
| Toolchain reproducibility (iverilog + vendored picorv32.v + in-tree tb) | **MANUAL** — covered by `helpers/picorv32/README.md` + `helpers/picorv32/Makefile` |
| Hand-verified anchors against RV32I encoding | **MANUAL** — anchors documented in `PROVENANCE.md` |

#### 5.9.10 Authentic VCD via Verilator (manual, optional)

The committed fixtures are produced from a deterministic Dart emitter so that the decoder's correctness can be verified without an external simulator. For occasions when an authentic instruction trace is desired — to cross-check the hand-encoded fixtures against output from a real RISC-V simulation, or to produce traces too large for the hand-emitter to comfortably express — the following manual recipe is supported. **This is not a required verification step**; it is here for engineers who want to produce richer traces on their own time.

**Prerequisites:**

- **Verilator** ≥ 5.0
- **GNU RISC-V toolchain** (`riscv64-unknown-elf-gcc`, `riscv64-unknown-elf-as`, `riscv64-unknown-elf-objcopy`)
- A small RISC-V soft core. Recommended: `picorv32` (BSD-licensed, 32-bit) for RV32I traces, or `vroom`/`cva6` for RV64I.

**Recipe:**

1. Clone a RISC-V soft core, e.g. `git clone https://github.com/YosysHQ/picorv32`.
2. Author a tiny program (`prog.s`) that issues the instruction sequences you want to verify. Example:
   ```asm
       .section .text
       .globl _start
   _start:
       addi t0, t1, 10
       add  a0, a1, a2
       sw   t1, 8(sp)
       lui  a0, 0x12345
       ecall
   ```
3. Assemble and link to a flat hex/bin: `riscv64-unknown-elf-as -march=rv32i prog.s -o prog.o && riscv64-unknown-elf-objcopy -O binary prog.o prog.bin`.
4. Modify the picorv32 testbench's `$dumpvars` block to dump the fetch clock and instruction-bus signals (`clk`, `mem_rdata` filtered to fetch cycles, and `mem_valid && mem_instr` for the `valid` strobe; pair with `mem_la_addr` for PC).
5. Build and run with VCD output: `verilator --trace --cc picorv32.v --exe testbench.cpp && make -C obj_dir && ./obj_dir/Vpicorv32 +mem=prog.bin && ls *.vcd`.
6. Open the resulting VCD in WaveCrux. Apply the RISC-V decoder. Bind the fetch-clock and instruction signals from the picorv32 hierarchy.
7. Compare the decoded mnemonics against the source `prog.s`. Any divergence is a fixture or decoder bug — file an issue with the `.s`, the `.vcd`, and the WaveCrux disassembly output.

**What this catches that the hand-emitter doesn't:**

- Real fetch-clock timing (multi-cycle waits for memory, fetch stalls).
- Realistic PC progression including branch taken/not-taken.
- The decoder's `valid` gating against actual `mem_instr` cycles.
- Edge cases (e.g. PC alignment, fetch-bus width transitions) that hand-encoded fixtures might miss.

**Output disposition:** authentic-trace VCDs produced this way are NOT committed to `verification/fixtures/`. Keep them in a personal `~/wavecrux-traces/` or similar; reference the source `.s` and Verilator config in any bug report so the trace is reproducible.

#### 5.9.11 Future gaps (intentional, out of scope)

- **V (vector) extension** — tier-gated to Pro.
- **Vendor-specific extensions** (SiFive `Xsfvfwmaccqqq`, T-Head `XTheadCmo`, Andes, etc.) — Pro tier.
- **Bitmanip (B), crypto (Zk*) and other Z-extensions** — deferred. The schema is fully expressive enough; users may drop in JKU's upstream `RV32_Zb*.toml` etc. via a future user-TOML directory feature.
- **Pseudoinstruction recognition** (`mv`, `nop`, `li`) — the schema does not support pseudoinstruction display; mnemonics shown reflect the actual encoded instruction (`addi rd, rs, 0` rather than `mv rd, rs`). Matches Surfer behavior.
- **Architectural register-name display** (`x0`–`x31`) — bundled TOMLs use ABI names only (`zero`, `ra`, `a0`, …). A future toggle could swap mappings at load time; not in scope for launch.
- ~~**Architectural branch/jump offset rendering**~~ — **this entry was wrong and is retired.** It claimed the JKU schema reassembles immediates by concatenating slices in instruction-word order, producing a bit-shuffled value for B-type and J-type, and that Surfer behaves the same way. Neither half was true. The schema's slice `top`/`bot` are positions in the decoded part's *value*, not the instruction word — WaveCrux's loader was reading them as word indices. Branch and jump offsets now render as architectural byte offsets across their full signed ranges, as do every compressed branch (`c.j`, `c.beqz`, `c.bnez`) and the stack-pointer-relative offsets (`c.swsp`, `c.ldsp`, `c.sdsp`). Swept against spec-derived encoders in `test/services/decoders/isa/riscv_immediate_encoding_test.dart`; the cross-tool claim itself is now pinned by the "Cross-tool compatibility with the JKU loader" group in `instruction_disassembler_test.dart`.

#### 5.9.12 Automation Assessment

| Test | Coverage |
|---|---|
| TOML schema parser (round-trip + error paths) | **WIDGET** (`test/services/decoders/isa/instruction_set_toml_loader_test.dart`) |
| All 10 bundled TOMLs parse cleanly | **WIDGET** (`instruction_set_toml_loader_test.dart` — "Bundled RISC-V TOMLs" group) |
| Asset discovery over `AssetManifest` (bare + `packages/wavecrux/` prefixes, nested/non-TOML rejection, per-file failure isolation, `architecture` parameter) | **WIDGET** (`test/services/decoders/isa/isa_decoder_assets_test.dart`) |
| Deterministic set load order — RV32I before RV64I, manifest-order-independent, and RV32I/RV64I shifts proven to be the only cross-set ambiguity | **WIDGET** (`test/services/decoders/isa/isa_set_load_order_test.dart`) |
| Disassembler — RV32I per-format coverage | **WIDGET** (`test/services/decoders/isa/instruction_disassembler_test.dart`) |
| Disassembler — RV32M, RV64I composition | **WIDGET** (`instruction_disassembler_test.dart`) |
| Sign-extension of signed immediates | **WIDGET** (`instruction_disassembler_test.dart`) |
| Multi-segment immediates — B/J/CB/CJ/CSS offsets swept against spec-derived encoders over their full signed ranges, incl. the `0xfe029ce3 → -8` and `0xff5ff06f → -12` anchors | **WIDGET** (`test/services/decoders/isa/riscv_immediate_encoding_test.dart`) |
| Every bundled type's slice widths tile `width` exactly | **WIDGET** (`riscv_immediate_encoding_test.dart` — "Corpus structure") |
| Cross-tool schema compatibility — a corpus written in upstream JKU conventions decodes registers, sign-extended immediates and B-type offsets correctly | **WIDGET** (`instruction_disassembler_test.dart` — "Cross-tool compatibility with the JKU loader"); still **MANUAL** for a full upstream file, see §5.9.8 |
| `unsigned = true` flips VInt rendering | **WIDGET** (`instruction_disassembler_test.dart`) |
| Bit-width filtering (16-bit query against 32-bit ISet returns null) | **WIDGET** (`instruction_disassembler_test.dart`) |
| RiscvDecoder — fixture-driven RV32I integration | **WIDGET** (`test/services/decoders/isa/riscv_decoder_test.dart`) |
| Extension gating (M extension on/off) | **WIDGET** (`riscv_decoder_test.dart`) |
| XLEN switch (32 vs 64) | **WIDGET** (`riscv_decoder_test.dart`) |
| PC binding and label format | **WIDGET** (`riscv_decoder_test.dart`) |
| `valid` signal gating | **WIDGET** (`riscv_decoder_test.dart`) |
| x/z silent-skip path | **WIDGET** (`riscv_decoder_test.dart`) |
| Unknown-instruction error transaction | **WIDGET** (`riscv_decoder_test.dart`) |
| Surfer cross-tool TOML compatibility | **MANUAL** — drop in a JKU file, re-run tests; see §5.9.8 |
| Captured-fixture snapshot regression (picorv32_wb ifetch) | **WIDGET** (`riscv_captured_fixtures_test.dart` — fixture auto-discovery sweep + snapshot diff) |
| Verilator-generated authentic-trace cross-check | **MANUAL** — recipe in §5.9.10 |
| Decoder picker — "Instruction Trace" category appears | **WIDGET** — pending; existing `decoder_picker_dialog_test.dart` covers categories generically; add an explicit assertion when this section is verified end-to-end |
| Activation from picker → real FFI parse → 6 instructions in table | **INTEGRATION_TEST** (`integration_test/decoders/riscv_integration_test.dart`) |

---

### 5.10 SPI flash command decoder (stacked on SPI)

#### 5.10.1 What it does

The SPI flash decoder is a **stacked decoder** — it consumes the output of an already-running SPI decoder instance rather than binding raw signals directly. Each SPI transaction (one chip-select assertion) is interpreted as a standard JEDEC SPI flash command: RDID, READ, FAST_READ, PP, SE, CE, WREN, WRDI, RDSR, WRSR, RES, and vendor-specific extensions registered under the `vendor_preset` parameter.

The stacked decoder also enforces the Write Enable Latch (WEL) state machine: any erase or program command issued without a preceding WREN raises a `write_without_wel` error transaction. A double-WREN in a row raises `double_wren`.

**Stacking infrastructure** (`StackedDecoder` + `DecoderRegistry.listStackedDecoders(String parentId)`): `SpiFlashDecoder` extends `StackedDecoder` and declares `parentDecoderId: 'spi'`. The two-pass `decodeAll()` in `ActiveDecodersNotifier` runs all base decoders first, collects their output, then runs stacked decoders with the parent output as input.

**Picker UI affordances** (`DecoderPickerDialog`):

1. **Parent-decoder gating**: stacked decoders do NOT appear in the picker until at least one instance of the parent decoder is active in the current tab. When no parent is active, the picker omits the "Stacked Decoders" section entirely. (Visible to the user only when their existing decoder setup brings a stacked option into scope — avoiding clutter and a "why doesn't this work?" misstep.)
2. **Dedicated section**: stacked decoders render in a separate "Stacked Decoders" `ExpansionTile` at the bottom of the picker, with the `Icons.layers_outlined` leading icon and the `pickerCategoryHeader` count format (e.g. "Stacked Decoders (1)"). Stacked decoders are filtered out of their nominal `DecoderCategory` section (so SPI Flash, which has `category: DecoderCategory.serial`, no longer appears under Serial Bus once the picker is opened with at least one active SPI decoder — it appears only in Stacked Decoders).
3. **"Stacks on <Parent>" badge**: each stacked decoder's tile renders an inline badge next to the name (e.g. "Stacks on SPI"). The badge uses the theme's `secondaryContainer` colour so it visually contrasts with the `WaveCruxFeatureTierBadge` (which uses the brand colour) — both can sit on the same row without clash.

This is the first use of the stacking infrastructure; the pattern will be reused by future stacked decoders (I²C register maps, CAN application-layer framing, etc.).

#### 5.10.2 Setup

Seven committed fixtures under `verification/fixtures/protocol/spi_flash/` (mirrored to `test/fixtures/protocol/spi_flash/`):

| Fixture | Command / Scenario |
|---|---|
| `spi_flash_rdid.vcd` | RDID — reads Winbond W25Q128 JEDEC ID (0xEF-0x40-0x18) |
| `spi_flash_wren_pp.vcd` | WREN then Page Program at 0x012000 with data 0xAA 0xBB |
| `spi_flash_read.vcd` | READ at 0x001000, returns 0x55 0xAA |
| `spi_flash_wren_se.vcd` | WREN then Sector Erase at 0x010000 |
| `spi_flash_wel_violation.vcd` | PP without prior WREN → `write_without_wel` error |
| `spi_flash_rdsr.vcd` | RDSR — status register 0x02 (WEL bit set) |
| `spi_flash_fast_read.vcd` | FAST_READ at 0x002000, 1 dummy byte, returns 0xAB |

Each fixture has a paired `.expected_transactions.json`. Regenerate via:
```
dart run tool/generate_spi_flash_fixtures.dart
```
(see `verification/fixtures/helpers/README.md`).

Prerequisite: an SPI decoder must already be applied to the waveform. The SPI flash decoder appears in the picker only when at least one SPI decoder instance is active (parent-gating, see §5.10.1).

#### 5.10.3 Steps — RDID

1. Load `protocol/spi_flash/generated/spi_flash_rdid.vcd`.
2. Open the decoder picker. Verify the picker has no "Stacked Decoders" section at this point (parent-gating: no SPI is active yet).
3. Apply the SPI decoder. Bind `sclk`, `mosi`, `miso`, `cs`. Leave parameters at defaults (CPOL=0, CPHA=0, MSB, 8-bit).
4. Open the decoder picker again. Verify:
   - A **Stacked Decoders** section appears at the bottom of the picker with header "Stacked Decoders (1)" and a layers icon.
   - The single entry is **SPI Flash** with a "Stacks on SPI" badge next to its name.
   - SPI Flash no longer appears under the "Serial Bus" section (it has been moved into Stacked Decoders).
5. Apply the SPI Flash decoder.
6. Verify one decoded transaction appears:
   - Label: **RDID**
   - Field `jedec_id`: **0xEF-0x40-0x18**
   - No error.
7. Click the transaction block → cursor jumps to t=10.

#### 5.10.4 Steps — Write Enable + Page Program

1. Load `protocol/spi_flash/generated/spi_flash_wren_pp.vcd`. Apply SPI decoder and SPI Flash decoder (both).
2. Verify two decoded transactions:
   - **WREN** (t=10..180): no fields beyond `opcode`. No error.
   - **PP** (t=280..1250): `address = 0x012000`, `data = 0xAA 0xBB`. No error.
3. Remove the flash decoder, then remove the WREN SPI transaction (simulate WEL not set) by disabling the first CS. Re-apply the flash decoder.
4. Verify the PP transaction now carries a `write_without_wel` error.

#### 5.10.5 Steps — READ and FAST_READ

1. Load `protocol/spi_flash/generated/spi_flash_read.vcd`. Apply SPI + SPI Flash decoders.
2. Verify: label **READ**, `address = 0x001000`, `data = 0x55 0xAA`.

3. Load `protocol/spi_flash/generated/spi_flash_fast_read.vcd`. Apply SPI + SPI Flash decoders.
4. Verify: label **FAST_READ**, `address = 0x002000`, `data = 0xAB`.
   (One dummy byte is consumed and not shown in `data`.)

#### 5.10.6 Steps — WEL violation

1. Load `protocol/spi_flash/generated/spi_flash_wel_violation.vcd`. Apply SPI + SPI Flash decoders.
2. Verify: one error transaction with label **PP**, `errorMessage = write_without_wel`.
3. Verify the transaction block in the waveform lane has a red border / error styling.

#### 5.10.7 Steps — RDSR

1. Load `protocol/spi_flash/generated/spi_flash_rdsr.vcd`. Apply SPI + SPI Flash decoders.
2. Verify: label **RDSR**, field `status = 0x02`.

#### 5.10.8 Tier gate

SPI Flash is **Open Core** — no PRO badge in the picker. Verify during beta that no FeatureTierBadge chip appears next to the decoder entry.

#### 5.10.9 Edge cases

- **Stacked decoder before parent decoder is applied**: with no SPI decoder active, the "Stacked Decoders" picker section is hidden entirely — the SPI Flash entry is not reachable. Activating an SPI decoder and re-opening the picker reveals the section. (Implemented by `DecoderPickerDialog`: it reads the tab's `activeDecodersProvider` at open time and filters stacked decoders whose `parentDecoderId` isn't in the active-id set.)
- **Vendor preset**: switch from `generic` to `winbond`. Commands specific to Winbond (e.g., RDSR2 at 0x35, BE32K at 0x28) should decode with their vendor labels rather than as UNKNOWN.
- **32-bit address mode**: set `address_width = 32`. A command with 4-byte address (0xXX 0xAA 0xBB 0xCC 0xDD) should decode address as `0xAABBCCDD`.
- **Incomplete frame**: a CS transaction with only the opcode byte and no address/data bytes for a READ → `incomplete_frame` error.
- **Double WREN**: two consecutive WREN commands → second WREN raises `double_wren`.

#### 5.10.10 Automation Assessment

| Check | Assessment |
|---|---|
| RDID jedec_id field | **TEST** (`spi_flash_decoder_test.dart` — fixture round-trip `spi_flash_rdid`) |
| WREN + PP WEL state machine | **TEST** (`spi_flash_decoder_test.dart` — fixture `spi_flash_wren_pp`) |
| PP without WEL → `write_without_wel` | **TEST** (`spi_flash_decoder_test.dart` — fixture `spi_flash_wel_violation`) |
| READ / FAST_READ address + data fields | **TEST** (`spi_flash_decoder_test.dart` — fixtures `spi_flash_read`, `spi_flash_fast_read`) |
| SE with WEL | **TEST** (`spi_flash_decoder_test.dart` — fixture `spi_flash_wren_se`) |
| RDSR status field | **TEST** (`spi_flash_decoder_test.dart` — fixture `spi_flash_rdsr`) |
| Vendor preset (Winbond) | **TEST** (`spi_flash_decoder_test.dart` — "Winbond vendor preset" unit tests) |
| Incomplete frame error | **TEST** (`spi_flash_decoder_test.dart` — "incomplete_frame" unit test) |
| Stacking infrastructure — `parentDecoderId` field | **TEST** (`spi_flash_decoder_test.dart` — "definition parentDecoderId is spi") |
| Picker parent-gating (no SPI → no Stacked section) | **WIDGET** (`test/features/decoders/widgets/decoder_picker_dialog_stacked_test.dart`) |
| Picker shows Stacked section when SPI is active | **WIDGET** (`decoder_picker_dialog_stacked_test.dart`) |
| Picker tile renders "Stacks on SPI" badge | **WIDGET** (`decoder_picker_dialog_stacked_test.dart`) |
| Picker gated until parent SPI active | **MANUAL** — verify stacked-decoder entry absent before SPI applied |
| Tier badge absent (Open Core) | **WIDGET** (`test/features/decoders/widgets/decoder_picker_dialog_stacked_test.dart` — "no PRO/ENT FeatureTierBadge renders on Open Core picker rows" activates SPI, expands the picker, and asserts `find.byType(WaveCruxFeatureTierBadge)` is `findsNothing` for the Open Core parent + stacked SPI Flash rows) |
| Activation from picker (SPI stacked on SPI) → real FFI parse → 2 transactions in table | **INTEGRATION_TEST** (`integration_test/decoders/spi_flash_integration_test.dart`) |

#### 5.10.11 Captured fixture — picorv32 spiflash single-wire

Real-world SPI Flash traces live under
`test/fixtures/protocol/spi_flash/captured/` (mirrored to
`verification/fixtures/protocol/spi_flash/captured/`). The
auto-discovery sweep
`test/services/decoders/spi_flash_captured_fixtures_test.dart` runs
`SpiFlashDecoder` against every triplet and snapshot-matches.

Current pilot capture:

- `picorv32_spiflash_single_wire.fst` — ISC-licensed YosysHQ/picorv32
  `spiflash` model exercising single-wire (SPI mode) operations: RDID,
  READ, and FAST_READ. Yields 3 decoded transactions exercising the
  full RDID / READ / FAST_READ command-set the SPI Flash decoder
  natively recognizes (SE / PP / WREN paths are covered by synthetic
  unit fixtures). See [`PROVENANCE.md`](../test/fixtures/protocol/spi_flash/captured/PROVENANCE.md).

Manual sign-off: open the .fst in WaveCrux, first apply the SPI decoder
(parent), then the SPI Flash decoder (stacked); confirm all three
transactions render. Then run the sweep test (<1 s).

Automation Assessment:

| What | Automation |
|------|------------|
| Snapshot regression | **WIDGET** (`spi_flash_captured_fixtures_test.dart`) |
| End-to-end activation | **INTEGRATION_TEST** (`integration_test/decoders/spi_flash_captured_integration_test.dart`) |

---

### 5.11 Transaction overlay rendering

#### 5.11.1 What it does

Decoded transactions appear as colored blocks on a dedicated lane in the waveform canvas. Each block has a label (the decoded value), and error transactions have a red border or hatching. Tapping a block jumps the cursor to the transaction's start time. Labels truncate gracefully when blocks are narrow at high zoom-out.

#### 5.11.2 Steps

1. With any decoder active, verify colored blocks appear on the transaction lane.
2. Verify error transactions have red border/hatching distinct from normal transactions.
3. Verify label text shows inside blocks and truncates with ellipsis when blocks are narrow.
4. Tap a transaction block — cursor jumps to start time, viewport pans to bring it into view.
5. Use the Render tab to verify "transaction paint" appears in the paint-time breakdown.

#### 5.11.3 Zoom-out density bars and window culling

At full zoom-out a long decode puts far more transactions on the lane than
there are pixels to draw them in. The painter locates the visible slice by
binary search over the time-ordered transaction list, and coalesces every
transaction narrower than one pixel column into a single vertical density bar
for that column, so the number of draw operations is bounded by the lane width
rather than by the transaction count.

1. Load a fixture that decodes to a large transaction count (e.g. a captured
   Ethernet or RISC-V trace), activate its decoder, and press **Zoom Fit**.
2. Verify the lane shows a dense field of thin vertical bars rather than
   dropping to a blank or partially-drawn lane, and that panning/zooming stays
   fluid (Render tab: "transaction paint" must not dominate frame time).
3. Verify a density bar covering an error transaction is drawn in the error
   color — a sub-pixel protocol violation must stay visible when zoomed out.
4. Zoom in until individual blocks resolve; verify bars give way to labelled
   rounded-rect blocks with no gap or double-draw at the transition.
5. Pan so a long transaction starts left of the viewport; verify it is still
   drawn (the window includes transactions straddling the left edge, not only
   those starting inside it).

#### 5.11.4 Multi-decoder rendering

1. Add SPI decoder. Add I²C decoder simultaneously.
2. Verify both transaction lanes render side by side without visual collision.
3. Verify each lane is clearly labeled with its decoder name.

#### 5.11.5 Automation Assessment

| Test | Coverage |
|---|---|
| Block presence/count for known fixture | **WIDGET** (`test/features/viewer/widgets/waveform_canvas_transaction_test.dart`) |
| Visible-window culling: transactions before/after the window produce no blocks; a left-straddling transaction still does | **UNIT** (`test/features/viewer/rendering/transaction_painter_test.dart` — "visible window" group) |
| Density coalescing: 200k transactions in a 1000 px lane yield ≤ lane-width blocks, every source transaction accounted for, error/selection inherited by the bar | **UNIT** (`transaction_painter_test.dart` — "density coalescing" group) |
| Selection identity is startTime/endTime/label, not object identity | **UNIT** (`transaction_painter_test.dart` — "labels and selection" group) |
| Label paragraphs are cached and the cache stays capacity-bounded | **UNIT** (`transaction_painter_test.dart` — "label paragraph cache" group) |
| Multi-decoder lanes coexist without collision | **WIDGET** (`waveform_canvas_transaction_test.dart` — "renders multiple decoder lanes without exception") |
| Error styling | **WIDGET — pending** (canvas-side error-block painter coverage; queued — needs golden-image or color-assertion infra) |
| Tap-to-jump cursor behavior | **INTEGRATION_TEST — pending** (canvas tap → cursor + viewport pan; gesture-arena interaction; queued in `integration_test/PENDING.md`) |
| Label truncation | **MANUAL** — visual judgement |

---

### 5.12 Transaction table

#### 5.12.1 What it does

A spreadsheet-style table listing every decoded transaction across all active decoders. Sortable columns, filter-by-decoder, filter-by-text. Click row → jump cursor and highlight transaction. CSV export.

#### 5.12.2 Steps

1. With decoders active, verify the table populates with all transactions.
2. Test sorting by each column.
3. Test filtering by decoder (drop-down with numbered instance labels: "SPI #1", "I²C #2").
4. Test text filtering.
5. Click a row — cursor jumps, transaction highlights on canvas.
6. CSV export — open the exported file in a text editor, verify contents match the visible table.
7. With multiple decoders active, verify the table shows transactions from all of them.

#### 5.12.3 Automation Assessment

| Test | Coverage |
|---|---|
| Table population | **WIDGET** (`test/features/decoders/widgets/transaction_table_panel_test.dart` — "renders rows with label text") |
| Sort and filter | **WIDGET** (`transaction_table_panel_test.dart` — decoder-filter dropdown + sort tests) |
| Click-to-jump | **WIDGET** (`transaction_table_panel_test.dart` — "tapping a row marks transaction as selected" + "tapping a row also places primary cursor at transaction startTime") |
| CSV export round-trip | **WIDGET** (`transaction_table_panel_test.dart` — `buildCsvContent` group covers headers, fields, missing-field, embedded-quote escaping) |

#### 5.12.4 From the keyboard and a screen reader

**What it does.** The table is operable without a mouse, and each transaction is heard as one sentence. Before, the decoder filter was a bare click target (Tab skipped it, so there was no keyboard route to filtering, configuring or removing a decoder), the sort headers were read as "# text", and a `DataTable` put a focusable cell in every column of every row: an APB report walked eleven Tab stops per transaction, each a bare value, with empty cells silent and the arrows in read labels ("R 0x08 → 0xFF") spoken as "?".

- **Decoder filter** is a button named "Decoder filter" whose value is the current filter ("All Decoders", "APB #1"). Enter or Space opens its menu below the button with focus on the first item; Down/Up and Tab move through it; each decoder's name, **Configure {decoder}** and **Remove {decoder}** are separate, named controls; closing the menu returns focus to the button.
- **Sort headers** are buttons named for their column; the sorted column adds "sorted ascending" / "sorted descending". Enter sorts.
- **Rows are one Tab stop**, after the headers. Up / Down move between rows, Home / End go to the first / last, Page Up / Page Down move a screenful, Left / Right scroll the wide field columns sideways, and Enter or Space does what a click does (select the transaction, place the primary cursor, jump the view). While the rows have focus these keys do not pan, jump or play the waveform. The focused row has a stronger primary tint over its selected or error color. A click selects a row without taking keyboard focus; Tab back into the rows returns to the last row clicked or moved to.
- **Each row is spoken as one sentence:** "2, APB #1, 25 to 35, R 0x00000008 to 0x12345678", plus ", error: {message}" (or ", error") for a flagged transaction, plus "selected". The keyboard instructions are spoken once as focus enters the table.
- **Glyphs in decoder output are spoken as words**, in the table only: rightward arrows read "to", leftward "from", two-headed "to and from", up/down arrows and triangles "up"/"down", and box-drawing, shape and private-use glyphs are dropped. The connecting words are localized. The visible label, the canvas lane, the CSV export and the decoders' `.expected_transactions.json` snapshots are unchanged.
- Rows have no context menu, so Shift+F10 on a row does nothing.

**Steps.**

1. Load `protocol/apb/generated/apb_basic.vcd`, add the APB decoder, open the table (⌘⇧T / Ctrl+Shift+T).
2. Tab into the bottom dock: the stops inside the table are Decoder filter, search, Export CSV, the five sort headers, then one stop for the rows — never a cell. NVDA reads the row as "1, APB #1, 5 to 15, W 0x00000004 = 0xDEADBEEF, button".
3. **Down**: "2, APB #1, 25 to 35, R 0x00000008 to 0x12345678" — "to", not "question mark". **End**: row 4 adds ", error: Slave error (PSLVERR)". **Home**, **Page Down** and **Page Up** move as described. **Left** / **Right** scroll the field columns.
4. On row 2 press **Enter**: the row turns selected, the primary cursor lands at 25, the view jumps there, and focus stays on the row.
5. With the rows focused press **Left**, **Right**, **Home**, **End**, **Space**: the waveform does not pan, jump or start playback.
6. Shift+Tab to **Decoder filter** and press **Enter**: the menu opens below the button, "All Decoders, selected" is read. **Down** to "APB #1", **Enter**: the table filters and focus is back on the button, which now reads "Decoder filter, APB #1". Open it again, Tab to **Configure APB #1**, Enter: the config dialog opens; close it and focus returns. **Remove APB #1** removes the decoder.
7. Sort by Start with the keyboard (Tab to the Start header, Enter twice): the header reads "Start, button, sorted descending", and the rows' Tab stop still returns to the same transaction.

**Edge cases.**

- A label with several glyphs or a glyph at the start or end reads with single spaces, never "?" and never a doubled space.
- Clicking a column header sorts and selects no row.
- A search that matches nothing removes the rows' Tab stop; the empty-state message is not a stop.
- Pro decoders' output (Avalon-MM "R 0x… → 0x…", MDIO "R … → …", Ethernet "src→dst") reaches the same table and is spoken the same way.

**Automation Assessment.**

| Test | Coverage |
|---|---|
| Glyph-to-word conversion for every code point in the unspeakable set; directional words; unchanged text passes through; words come from every locale | **UNIT** (`test/core/utils/speakable_text_test.dart`) |
| Whole-table walk (9 stops) and keystroke transcript on the APB fixture's decoded output, rows and decoder-filter menu, pinned as `goldens/transaction_table.txt`; Enter selects row and places the cursor; no semantics label in the table carries a glyph while the arrows stay on screen | **WIDGET** (`test/accessibility/screen_reader_test.dart` — "the transaction table" group) |
| Headers then one row stop; Shift+Tab returns to the row; header names and sort state; row keys incl. Page keys with scrolling; Enter/Space activate, held Enter once; Left/Right scroll; the app keymap does not take the rows' keys; modified keys pass through; clicks on any cell activate that row without taking focus; row sentences incl. both error forms; no row label with any glyph (mutation-checked by removing the conversion); semantics focus action; focus tint; row identity kept across a re-sort | **WIDGET** (`test/features/decoders/widgets/transaction_table_body_test.dart`) |
| Decoder filter is a named button with the filter as its value; Enter and Space open the menu on its first item; filter, Configure and Remove chosen by keyboard; Escape and every item return focus to the button; menu anchored below the button; locale sweep | **WIDGET** (`test/features/decoders/widgets/transaction_table_panel_keyboard_test.dart`) |
| First menu item focused on open, focus returned on close, no-op with no menu | **WIDGET** (`test/core/utils/focus_opening_menu_test.dart`) |
| Pro decoders' rows (MDIO/Avalon/Ethernet) spoken without glyphs | **WIDGET** (Pro overlay test) |
| NVDA / VoiceOver actually speak rows, headers and the filter menu as modelled | **MANUAL** (steps 2, 3, 6) |

### 5.13 Shared decoder value helpers (extension point)

#### 5.13.1 What it does

`lib/services/decoders/decoder_value_helpers.dart` is the single canonical
implementation of the value parsing, config-parameter reading, and payload
field rendering that every protocol decoder needs — in this repo and in the
closed-source Pro decoder set, which consumes it across the repo boundary.
There is no UI surface: it exists so a parsing fix lands once instead of
being copy-pasted into ~20 decoders in two repos.

Three families:

- **Strict parsers** (`isVcdHigh`, `isVcdLow`, `parseVcdVectorInt`) — reject
  a value containing `x`/`z` by returning `null`, for decoders that must
  distinguish "unknown" from a concrete value (MDIO turnaround, PCIe header
  DWs).
- **Lenient parsers** (`parseVcdVectorIntLenient`,
  `parseVcdVectorIntLenientOrNull`, `parseVcdVectorBigLenient`,
  `vcdVectorBytesLsbFirst`, `vcdVectorWidth`) — coerce `x`/`z` to `0`, for
  streaming decoders that need a deterministic byte stream even on a capture
  with partial coverage. `vcdVectorWidth` reports the signal's observed bit
  width so a decoder inverting an active-low bus can build the right mask.
  `vcdVectorBytesLsbFirst` slices bytes straight out of the digit string,
  replacing a per-byte `BigInt` shift.
- **Field renderers** (`bytesToHex`, `bytesToHexCapped`, `joinCapped`) —
  render recovered payloads into transaction fields. The capped variants
  bound the retained string so one multi-kilobyte transaction cannot pin
  megabytes of payload text; the caller records the true size in a numeric
  field alongside. Fields that are a *data path* (anything a consumer
  hex-decodes back to bytes, e.g. the Pro Ethernet `raw_frame_hex` that feeds
  PCAP export) use the uncapped `bytesToHex`.

#### 5.13.2 Steps

No manual UI steps — this is a pure-Dart seam with no user-facing surface of
its own. Verify indirectly: every decoder section in this guide (§5.2–§5.10)
and every Pro decoder section in the Pro overlay's guide exercises
these helpers on real fixtures. If a helper regressed, decoded values in the
transaction table would be wrong across many decoders at once.

The one behavior worth eyeballing directly: open a trace with a wide bus
decoder bound (e.g. `protocol/axi4_lite/generated/` with a 1024-bit data
binding, or any Pro AXI-Stream fixture) and confirm a large payload field in
the transaction table's detail view ends with `… (+N more bytes)` rather
than rendering unbounded, while the sibling `byte_count` field still reports
the full size.

#### 5.13.3 Edge cases

- A vector shorter than the requested byte count zero-fills its high bytes.
- A vector longer than the requested byte count has its high digits dropped.
- Leading whitespace *before* the `b` prefix defeats the prefix strip — a
  long-standing quirk of the strict parsers that the lenient parsers match
  deliberately, asserted in the unit tests so the two families cannot
  silently diverge.
- A non-positive cap disables capping entirely.

#### 5.13.4 Automation Assessment

| Test | Coverage |
|---|---|
| Strict parsers (prefix strip, x/z rejection, fallbacks) | **UNIT** (`test/services/decoders/decoder_value_helpers_test.dart`) |
| `vcdVectorWidth` + active-low mask construction | **UNIT** (same file — "width drives an active-low inversion mask correctly") |
| Lenient parsers agree with strict parsers on x/z-free input | **UNIT** (same file — "parses ordinary values identically to the strict parser") |
| `vcdVectorBytesLsbFirst` equivalence to the `BigInt` shift it replaces | **UNIT** (same file — "matches the BigInt shift-and-mask it replaces") |
| Payload capping + elision suffix | **UNIT** (same file — `bytesToHexCapped` / `joinCapped` groups) |
| End-to-end decode correctness through the helpers | **UNIT** (every per-decoder test + snapshot fixture in both repos) |

---

## 6. Analysis and search features

### 6.1 Waveform diff

#### 6.1.1 What it does

Loads two VCD files side-by-side and shows where signals diverge. Engineers reach for this when "the regression passed yesterday and failed today" — instead of eyeballing two GTKWave windows, you get color-coded matching (green = identical, red = differs, gray = unmatched), XOR diff trace lanes that visualize agreement, prev/next divergence navigation, and divergence highlight bands on the time ruler. While the comparison is active the left pane swaps the signal tree for a **diff summary panel** — matched/unmatched counts plus a tap-to-jump signal list — and restores the tree when the diff is closed.

#### 6.1.2 Setup

Two VCDs, mostly identical with deliberate divergences. Generate a `diff_pass.vcd` and `diff_fail.vcd` pair from a parameterised testbench (see `helpers/README.md`) where:

- `data_bus` differs at T=100 ns and T=200 ns.
- `state` differs at T=160 ns.
- `error_flag` differs from T=160 ns onward.
- All other signals (`clk`, `reset_n`, `valid`, `ready`) are identical.

#### 6.1.3 Steps

1. Load `diff_pass.vcd`. Add all signals: clk, reset_n, data_bus, valid, ready, state, error_flag.
2. Use "Compare Waveforms" to load `diff_fail.vcd`.
3. Verify the diff toolbar appears showing "Comparing: diff_fail.vcd" and "Divergence 1 of N".
4. Verify signal matching colors (chip or icon next to each signal):

   | Signal | Expected | Reason |
   |---|---|---|
   | clk | Green | Identical |
   | reset_n | Green | Identical |
   | valid | Green | Identical |
   | ready | Green | Identical |
   | data_bus | Red | Differs at T=100 ns and T=200 ns |
   | state | Red | Differs at T=160 ns |
   | error_flag | Red | Differs from T=160 ns onward |

5. Verify XOR diff trace lanes (labeled `⊕`) appear below each red-marked signal — narrow 1-bit waveforms, high where values disagree.
6. Verify divergence highlight bands on the canvas (spanning the full lane height as semi-transparent amber bands) — at T=100 ns, T=160 ns, T=200 ns.
7. Click "Next divergence" (▶) — cursor jumps to first divergence (T=100 ns), viewport pans to center it. Click again — T=160 ns. Click again — T=200 ns. Click again — wraps around.
8. Click "Previous divergence" (◀) — backward navigation works the same.
9. Verify the diff summary panel shows correct counts. While a comparison is active the **left pane swaps the signal tree for the diff summary panel** (the same way the right pane swaps in the RTL source panel). It shows summary chips — e.g. "4 identical", "3 different", and, when present, "N only in A" / "N only in B" — above a MATCHED / UNMATCHED signal list. Tapping a *different* (red ✕) signal jumps the primary cursor to that signal's first divergence.
10. Close the diff (×) — toolbar disappears, amber bands clear, XOR lanes are removed, **the left pane restores the signal tree**, and the primary file remains loaded normally.

#### 6.1.4 Diagnostics-assisted verification

- Memory tab: loading the second file should show a noticeable but not catastrophic memory increase.
- Render tab: transaction-lane rendering should not regress; XOR lanes add a small additional paint cost.
- File Info: should describe the primary file (the secondary is referenced via the diff state, not the primary file metadata).

#### 6.1.5 Edge cases

- Compare a file against itself — should show all green, zero divergences.
- Compare files with different signal sets — unmatched signals should show as gray.
- Compare with file that has incompatible parser backend — should show a clear error snackbar (not silent failure).
- Use the comparison file picker — verify it filters by parser-aware extensions just like the primary file picker (no `.fsdb` if forceDart, etc.).
- Open a new primary file while diff is active — diff state should clear (related to the analysis-state-cleanup bug fix).
- Enter diff (or pattern search) while a protocol decoder is active — the value column must not flash a `RenderFlex` overflow. Adding the analysis overlay layer grows the value column's reserved height one frame before the canvas republishes `canvasViewportHeightProvider` (post-frame), so the body is hosted in `Expanded` + `ClipRect`/`OverflowBox` to clip that single-frame overshoot instead of throwing. Regression: `test/features/viewer/widgets/value_column_panel_test.dart` — "a stale canvasViewportHeight taller than the pane does not overflow".

#### 6.1.6 Automation Assessment

| Test | Coverage |
|---|---|
| Signal matching color logic | **WIDGET** (`test/services/diff/waveform_diff_service_test.dart` — diff classification; presentation `test/features/comparison/widgets/diff_summary_panel_test.dart`) |
| Divergence count | **WIDGET** (`test/features/comparison/widgets/diff_summary_panel_test.dart`) |
| Summary panel hosted in left pane when diff active | **WIDGET** (`test/features/viewer/screens/viewer_screen_test.dart` — "left pane swaps the signal tree for the DiffSummaryPanel when the active tab's diff is active" + "left pane hosts the signal tree, not the diff panel, by default") |
| Prev/next navigation | **WIDGET** (`test/features/comparison/providers/diff_provider_test.dart` + `test/features/comparison/widgets/diff_toolbar_test.dart`) |
| XOR lane presence | **WIDGET — pending** (canvas-side XOR lane rendering; queued in `integration_test/PENDING.md`) |
| Diff cleanup on close | **WIDGET** (`diff_provider_test.dart`) |
| Diff state cleanup on new file load | **WIDGET** (`test/features/viewer/providers/waveform_source_provider_test.dart` — "openFile clears DiffState" + "close clears DiffState") |
| Visual rendering of XOR lanes | **MANUAL** |
| Canvas amber bands at every divergence | **WIDGET — pending** (canvas divergence-band rendering; queued) |

---

### 6.2 X-Trace (X origin tracing)

#### 6.2.1 What it does

When a signal goes to X (unknown), tracing where the X came from is a common debug task. X-Trace right-clicks an X-valued signal, finds the root cause (the upstream signal whose X propagated through the design), and shows a causal chain — root signal at the top, then the siblings/descendants whose X values are correlated.

A red vertical line and diamond marker appear at the X-origin time on the waveform canvas, with a subtle red tint covering the affected lanes from that point rightward.

#### 6.2.2 Setup

`xtrace.vcd` (regeneratable from `helpers/`) containing:

- A signal `data_out` that goes X at T=200 ns due to an upstream X.
- A signal `status` that goes X at T=200 ns as a downstream consequence.
- Other signals (`addr`, `clean_sig`, `clk`, `enable`) that are not involved.

#### 6.2.3 Steps

1. Load `xtrace.vcd`. Add all signals to the canvas. Place the cursor near T=200 ns.
2. Right-click `data_out` (which has value `x` at the cursor) — "Trace X Origin".
3. Verify the X-Trace panel auto-opens.
4. Verify the causal chain shows: root = `data_out`, sibling = `status`.
5. Verify red vertical lines + diamond markers appear at T=200 ns on both `data_out` and `status` lanes.
6. Verify a subtle red tint overlay covers `data_out` and `status` from T=200 ns rightward.
7. Verify uninvolved signals (`addr`, `clean_sig`, `clk`, `enable`) have no markers and no tint.
8. Verify the cursor is positioned at T=200 ns.
9. Click a node in the X-Trace panel tree — cursor should jump to that signal's X-origin time.

#### 6.2.4 Per-tab state isolation

> Issue 21: this section originally said the X-Trace panel state should
> **clear** when opening a new file. That predates the tab-based
> UI — File → Open now always creates a new tab (it never replaces the
> current file). The expectation is therefore the opposite: each tab owns
> its own X-Trace state, so opening a new file must leave the previous
> tab's trace intact.

1. Load `xtrace.vcd` in tab A. Run "Trace X Origin" on `data_out` so the X-Trace panel is populated.
2. File → Open another VCD file → tab B opens. Verify tab B's X-Trace panel is **empty** (a fresh per-tab provider, not a stale view of tab A's trace).
3. Switch back to tab A. Verify tab A's X-Trace panel still shows the populated causal chain from step 1 — the previous-file trace was preserved, not cleared.
4. Close tab A. Per-tab state for tab A is disposed when its [`ProviderContainer`](../lib/services/tabs/tab_container_manager.dart) is torn down; tab B's empty X-Trace panel is unaffected.

> **2026-07 crux-shared round — structural scope eviction.** Container
> disposal on tab/pane close is no longer an opt-in `disposeTab` call: it is
> now driven by crux_workspace's `WorkspaceScopeReconciler` seam. Both
> `TabContainerManager` and `PaneContainerManager` implement the reconciler
> and are registered at bootstrap via `notifier.addScopeReconciler(...)`, so
> the workspace emits a live-scope snapshot after every state change and each
> manager prunes the containers (and, for panes, the render-stats collector
> and its listener) whose owning tab/pane is gone. This closes two latent
> defects that were invisible at compile time: **(1)** closed tabs' containers
> used to leak for the process lifetime, and **(2)** because `TabId`s persist
> in the workspace JSON, reloading a workspace that revived an id could hand
> the "new" tab the DEAD tab's container — cross-tab state bleed. To verify
> the second by hand: open two tabs, save the workspace, close and reload it;
> each restored tab must show its own state, never the other's. Guarded by
> `test/services/tabs/workspace_scope_reconciler_test.dart` (closed-then-revived
> id gets a FRESH container).

(For genuine within-tab cleanup — closing the loaded file via the toolbar "Close File" action or reloading the same path through the per-tab `WaveformSourceNotifier` — the X-Trace state is cleared by the per-tab provider listeners; covered by the unit-test row in §6.2.6.)

#### 6.2.5 Edge cases

- Trace X on a signal that was never X — clear "no X to trace" message.
- Trace X on a signal that has been X the entire simulation — handle gracefully.
- Cluttered design with many X signals — performance should remain reasonable.

#### 6.2.6 Automation Assessment

| Test | Coverage |
|---|---|
| Causal chain on known fixture | **WIDGET** (`test/features/viewer/widgets/x_trace_panel_test.dart` + `test/services/signal_query/x_trace_service_test.dart`) |
| Marker rendering on involved lanes (red lines + diamond markers + red tint) | **WIDGET — pending** (canvas-side X-Trace overlay rendering; queued in `integration_test/PENDING.md` — needs golden-image or render-object assertion) |
| State cleanup on new file | **WIDGET** (`test/features/viewer/providers/waveform_source_provider_test.dart` — "openFile clears XTraceState" + "close clears XTraceState") |
| Closed-then-revived tab/pane gets a fresh container (structural scope eviction) | **UNIT** (`test/services/tabs/workspace_scope_reconciler_test.dart` — both managers implement `WorkspaceScopeReconciler`; evict-on-close and resurrection-safety) |
| Click-to-jump from chain node | **WIDGET** (`x_trace_panel_test.dart`) |
| Right-click X-valued signal → "Trace X Origin" gesture dispatch | **INTEGRATION_TEST — pending** (gesture-arena interaction; queued) |

---

### 6.3 Switching activity analysis

#### 6.3.1 What it does

Counts transitions per signal over a time range, computes toggle rate, detects clocks (periodic ~50 % duty cycle signals), estimates clock frequency, and surfaces the highest-activity signals. A heatmap overlay tints the signal tree by activity level. Engineers use this to find unexpectedly busy nets, identify clocks they don't recognize, and check whether constant signals are actually constant.

#### 6.3.2 Setup

`switching_activity.vcd` (regeneratable from `helpers/`) containing:

- `clk_100mhz` — 100 MHz clock.
- `clk_50mhz` — 50 MHz clock.
- `constant_sig` — never transitions.
- Several mixed-activity signals.

#### 6.3.3 Steps

1. Load `switching_activity.vcd`. Add all 6 signals to the canvas.
2. Run "Analyze Switching Activity" from the command palette (or appropriate menu/toolbar entry).
3. Verify the activity table shows:
   - `clk_100mhz` → flagged as clock, frequency ≈ 100 MHz, high transition count.
   - `clk_50mhz` → flagged as clock, frequency ≈ 50 MHz.
   - `constant_sig` → 0 transitions.
   - Mixed signals → non-zero counts roughly matching the testbench design.
4. Verify the duty cycle for clocks is ~50 %.
5. Verify the heatmap overlay tints high-activity signals more strongly than low-activity signals.
6. Test sorting by toggle rate, by signal name, by transition count.
7. Test the time-range narrow: select a sub-range and re-analyze; counts should drop accordingly.
8. Verify the activity panel header includes a close-panel control that dismisses the activity overlay and clears the heatmap tint.
9. Test CSV export — values should match the table.

#### 6.3.4 Diagnostics-assisted cross-reference

- Signal Health tab independently detects clocks. The clocks reported by Signal Health should match those flagged in Switching Activity. **If they disagree, that's a bug.**

#### 6.3.5 Edge cases

- Analyze with no signals on the canvas — empty state, no error.
- Single-transition signal — handled correctly.
- Time range crossing the start/end of simulation — clipped correctly.

#### 6.3.6 Automation Assessment

| Test | Coverage |
|---|---|
| Transition counts on known fixture | **WIDGET** (`test/services/signal_query/switching_activity_service_test.dart`) |
| Clock detection cross-reference vs Signal Health | **WIDGET** (cross-check between `switching_activity_service_test.dart` and `test/features/diagnostics/widgets/signal_health_panel_test.dart`) |
| Duty cycle and frequency estimation accuracy | **WIDGET** (`switching_activity_service_test.dart`) |
| Heatmap tint values | **WIDGET** (`test/features/viewer/widgets/activity_heatmap_overlay_test.dart`) |
| Visual heatmap rendering | **MANUAL** |
| CSV export | **WIDGET** (`test/features/viewer/widgets/activity_report_panel_test.dart`) |

---

### 6.4 Multi-signal pattern search

#### 6.4.1 What it does

Find the moment(s) when a compound condition holds across multiple signals. Example: "find the next time `chip_select == 0 AND data_bus == 0xFF`". Two modes — a builder UI (select signal, operator, value, AND/OR/NOT) and a raw expression text field for power users. Matches are highlighted on the time ruler and waveform canvas; prev/next navigation jumps between them.

#### 6.4.2 Setup

`pattern_search.vcd` (regeneratable from `helpers/`) where the compound condition `chip_select == 0 AND data_bus == 0xFF` occurs at a known set of times.

#### 6.4.3 Steps

1. Load `pattern_search.vcd`. Add the relevant signals.
2. Open the pattern search dialog (command palette or toolbar).
3. **Builder mode:** add condition `chip_select == 0`. Add condition `data_bus == 0xFF`. Combine with AND. Search.
4. Verify match results count matches the known number of occurrences.
5. Verify match regions are highlighted on the time ruler and on the waveform canvas.
6. Use prev/next match — verify cursor jumps to each match.
7. Test with raw expression text field (advanced mode): `chip_select == 0 AND data_bus == 0xFF` (note the parser uses uppercase `AND`/`OR`/`NOT` keywords, not C-style `&&`/`||`/`!`).
8. Test a pattern with NO matches — verify clear empty-state message.
9. Test patterns involving X/Z values: `data_bus == xx` or `chip_select == x`.
   - Should accept the value gracefully.
   - Should evaluate to "0 matches found" (X/Z values never satisfy comparisons by design).
   - Should NOT show a parse error.
10. Test malformed expression (e.g., missing operator) — verify clear error message.

#### 6.4.4 State cleanup

When opening a new VCD file, the pattern search state should clear (regression area — same root cause as X-Trace state persistence).

#### 6.4.5 Diagnostics-assisted verification

- Render tab: pattern-match highlights add a small paint cost; verify it's visible in the breakdown but doesn't tank frame rate.

#### 6.4.6 Automation Assessment

| Test | Coverage |
|---|---|
| Known-answer match count | **WIDGET** (`test/services/signal_query/pattern_search_service_test.dart`) |
| Builder-mode AND/OR/NOT logic | **WIDGET** (`pattern_search_service_test.dart` + `test/features/viewer/widgets/pattern_search_dialog_test.dart`) |
| Expression-mode parser | **WIDGET** (`pattern_search_service_test.dart`) |
| X/Z value handling (no error, 0 matches) | **WIDGET** (`pattern_search_service_test.dart` — documented X/Z regression case) |
| State cleanup on new file | **WIDGET** (`test/features/viewer/providers/waveform_source_provider_test.dart` — "openFile clears PatternSearchState") |
| Prev/next match navigation | **WIDGET** (`test/features/viewer/widgets/pattern_search_toolbar_test.dart`) |
| Highlight rendering on time ruler + canvas | **WIDGET — pending** (canvas + time-ruler highlight rendering; queued in `integration_test/PENDING.md`) |

---

### 6.5 GTKWave process filter compatibility

#### 6.5.1 What it does

A "translate filter" maps signal values to human-readable labels. GTKWave's process filter version pipes signal values through an external program; the program receives values on stdin and returns translated labels on stdout. This enables backward compatibility with existing user scripts, including the SigRok protocol decoder bridge.

#### 6.5.2 Setup

A simple shell script (e.g., `fsm_filter.sh`) that maps:

- `0x00` → `"IDLE"`
- `0x01` → `"RUNNING"`
- `0x02` → `"DONE"`
- everything else → `"UNKNOWN"`

#### 6.5.3 Steps

1. Make the filter script executable: `chmod +x fsm_filter.sh`.
2. In WaveCrux, right-click a signal → set process filter → point at `fsm_filter.sh`.
3. Verify the value column for that signal now shows the translated labels (`IDLE`, `RUNNING`, `DONE`) instead of the raw hex values.
4. **Failure-mode tests:**
   - Kill the filter process externally (`pkill -f fsm_filter.sh`) — verify WaveCrux falls back to raw values without crashing.
   - Use a slow/hanging filter script — verify timeout handling kicks in.
   - Use a filter script that returns malformed output — verify graceful fallback.
5. Remove the process filter via the context menu — verify raw values return.

#### 6.5.4 Edge cases

- Process filter on a signal that already has a static translate filter — last-wins or coexists, but no crash.
- Process filter on a vector signal vs scalar — both should work.
- Filter binary that doesn't exist on disk — clear error, no crash.
- **Sandboxed macOS build:** `setProcessFilter` is blocked by the macOS App Sandbox (process filters spawn arbitrary user scripts via `Process.start`). Verify that a sandboxed build returns a clear error message rather than silently failing or crashing, and that the error guidance suggests the static translate-filter file alternative (`Assign Translate Filter…`). See the dartdoc on `process_filter_provider.dart` for the full escape-hatch matrix (run unsigned/dev build, distribute outside the App Store, or use the static-filter path).

#### 6.5.5 Automation Assessment

| Test | Coverage |
|---|---|
| Basic translation works | **WIDGET** (`test/services/translate/process_filter_service_test.dart`) |
| Process kill recovery | **WIDGET** (`process_filter_service_test.dart`) |
| Timeout / hang handling | **WIDGET** (`process_filter_service_test.dart`) |
| Missing binary error | **WIDGET** (`process_filter_service_test.dart`) |
| Real-world SigRok bridge | **MANUAL** — integration with external project |

---

### 6.6 Static translate filters and GTKWave session import

#### 6.6.1 What it does

GTKWave's static translate filters (`.txt` files mapping value → label) and `.gtkw` session save files are widely used in the GTKWave installed base. WaveCrux imports both for migration parity.

#### 6.6.2 Setup

The GTKWave fixture corpus lives under `test/fixtures/gtkw/` and follows the
same `generated/` + `captured/` split as the protocol decoders. The
verification flow consumes this tree **directly** — there is no duplicate copy
under `verification/fixtures/`.

`generated/` (synthetic, deterministic — emitted by `dart run tool/generate_gtkw_fixtures.dart`):

- `fixture.vcd` — paired waveform (5 signals under `top` / `top.cpu`).
- `simple_signals.gtkw`, `groups.gtkw`, `format_flags.gtkw`, `colors_and_markers.gtkw`, `translate_refs.gtkw` — save files exercising progressively more features.
- `sample_filter.txt` — a static translate filter referenced by `translate_refs.gtkw`.
- `<name>.expected_parse.json` / `<name>.expected_session.json` — committed golden snapshots of the parser output and the full parse→import result (the gtkw analog of a decoder's `.expected_transactions.json`).

`captured/` (real GTKWave saves from public open-source projects, each attributed in `PROVENANCE.md`):

- `sonata_ibex_pc_gpo.gtkw` (lowRISC Sonata, Apache-2.0) — FST dumpfile, `[color]`, deep `[treeopen]` hierarchy, vector bit-ranges.
- `uart_rx_tx.gtkw` (ben-marshall/uart, MIT) — three named groups over 39 signals.
- `fpxx_adder.gtkw` (tomverbeure/math, BSD-2) — separator-heavy layout, `"(null)"` dumpfile.
- `bubble_fifo.gtkw` (schoeberl/chisel-examples, BSD-2) — Chisel-generated VCD save.
- `<name>.expected_parse.json` — parse golden for each (no import golden: the referenced dumpfiles are not committed).

#### 6.6.3 Steps — translate filter

1. Load `test/fixtures/gtkw/generated/fixture.vcd`. Add a vector signal.
2. Right-click → Translate filter → point at `generated/sample_filter.txt`.
3. Verify the value column shows the label strings instead of raw hex.

#### 6.6.4 Steps — GTKWave session import (synthetic corpus)

1. With `generated/fixture.vcd` loaded, File → Import GTKWave Session → pick `generated/simple_signals.gtkw`. Verify signal list matches.
2. Repeat with `groups.gtkw` — verify named groups appear.
3. Repeat with `format_flags.gtkw` — verify per-signal format choices apply (hex/bin/dec/etc.).
4. Repeat with `colors_and_markers.gtkw` — verify per-signal colors, named markers A at 30 and B at 50 (no marker C), and the primary cursor at 40. GTKWave writes the primary marker before the named markers on the `*` line; a marker C at 50 means the import has slipped one letter.
5. Repeat with `translate_refs.gtkw` — verify all five signals import with none unmatched: the `^1`, `^>2` and `^<3` filter-reference lines must not appear as unmatched signal paths.
6. Verify the import-result dialog shows matched/unmatched signal counts.

#### 6.6.5 Steps — real-world captured saves (robustness)

Captured saves reference dumpfiles that are not committed, so every signal
imports as *unmatched* — the point of this pass is to confirm a messy,
real-world `.gtkw` (full of `[size]`, `[pos]`, `[sst_*]`, `[pattern_trace]`,
`[savefile]` directives WaveCrux does not model) imports without error.

1. With any waveform loaded, import each file under `captured/`. Verify the import-result dialog appears (no crash, no error snackbar) and lists the file's signals as unmatched.
2. For `uart_rx_tx.gtkw`, confirm the three groups (`Top Level`, `UART RX`, `UART TX`) appear in the imported (unmatched-but-structured) panel.
3. Optionally point `[dumpfile]` at a matching local VCD/FST to see signals resolve — not required for sign-off.

#### 6.6.6 Automation Assessment

| Test | Coverage |
|---|---|
| Static translate filter applies | **WIDGET** (`test/services/translate/translate_filter_service_test.dart`) |
| `.gtkw` parse + signal-list reconstruction | **AUTOMATED** (`test/services/session/gtkw_parser_test.dart` + `gtkw_import_service_test.dart`) |
| Group / format / color / marker reconstruction | **AUTOMATED** (`gtkw_import_service_test.dart`) |
| Full parse→import pipeline (synthetic) vs golden snapshots | **AUTOMATED** (`test/services/session/gtkw_golden_test.dart` against `generated/*.expected_session.json`) |
| Parser output vs golden snapshots (synthetic + captured) | **AUTOMATED** (`gtkw_golden_test.dart` against `*.expected_parse.json`) |
| Real-world captured saves parse without throwing | **AUTOMATED** (`gtkw_golden_test.dart` captured group) |
| Import orchestration → live providers (groups/markers/colors/formats land) | **AUTOMATED** (`test/features/viewer/gtkw_import_pipeline_test.dart`) |
| Import resolves against **live wellen-parsed** variables (real FFI scope-path contract), real app booted | **INTEGRATION** (`integration_test/session/gtkw_import_integration_test.dart` — nightly Linux / weekly desktop sweep) |
| Malformed / adversarial input never throws | **AUTOMATED** (`gtkw_parser_test.dart` adversarial group) |
| Import-result dialog | **AUTOMATED** (`test/features/viewer/widgets/gtkw_import_result_dialog_test.dart`) |
| Corpus discipline (layout, golden companions, captured licenses) | **AUTOMATED** (`test/static/gtkw_fixture_layout_test.dart`, `gtkw_captured_fixture_companion_test.dart`, `gtkw_captured_fixture_licenses_test.dart`) |
| File-picker dialog + FFI variable extraction | **MANUAL** — native picker / FFI not driven in tests (the picker-less orchestration glue is covered above) |

---

## 7. Cocotb log file correlation

### 7.1 What it does

Cocotb is a Python verification framework whose simulation runs produce log files with timestamps, test names, severity levels (DEBUG/INFO/WARNING/ERROR/CRITICAL), and messages. Cocotb log correlation parses such a log alongside the corresponding waveform, places log entries as time-correlated annotations on the waveform timeline, and lets the engineer click any entry to jump the cursor to that simulation time.

This eliminates the manual cross-referencing engineers do today between terminal log output and a separate waveform window.

### 7.2 Setup

- Any waveform file (e.g., `protocol/apb/generated/apb_basic.vcd`).
- `cocotb/basic_log.txt` — small file with a handful of entries spanning a few tests, mixed severities.
- `cocotb/edge_cases_log.txt` — malformed lines, multiple timescales, continuation/traceback lines, integer-only timestamps, CJK message text.
- A `cocotb_stress.log` (regenerable via Python) — 10 000+ entries across 20+ tests for stress/perf testing.

### 7.3 Steps — basic loading

1. Load the waveform file.
2. Tools → Load Cocotb Log → select `cocotb/basic_log.txt`.
3. Verify the Cocotb Log panel appears, showing timestamp, severity, logger name, message for each entry.
4. Verify colored tick marks appear on the waveform time ruler:
   - Blue for INFO.
   - Amber for WARNING.
   - Red for ERROR / CRITICAL.

### 7.4 Steps — click-to-jump

1. Click an entry in the log panel.
2. Verify the waveform cursor jumps to that simulation timestamp.
3. Verify the viewport pans if needed to bring the cursor into view.

### 7.5 Steps — filtering

1. **Test name filter:** use the test-name dropdown to narrow the view to a single test. Verify only that test's entries show.
2. **Severity filter:** toggle severity chips (DEBUG, INFO, WARNING, ERROR, CRITICAL). Verify entries narrow accordingly.
3. **Keyword search:** enter a substring. Verify only matching entries show.
4. **Combined filters:** apply test + severity + keyword. Verify the intersection.
5. Clear all filters → full list returns.

### 7.6 Steps — context menu

1. Right-click a log entry. Verify context options are present (e.g., "Jump to time", "Copy message", "Filter to this test").

### 7.7 Steps — timestamp unit conversion

The cocotb log can report timestamps in fs / ps / ns / µs / ms / s. The parser must convert all of these to the waveform's tick base.

1. Load `cocotb/edge_cases_log.txt` (it contains multi-unit timestamps) alongside a waveform with a different timescale.
2. Click an entry — verify the cursor jumps to the correct point in the waveform, accounting for unit conversion.

### 7.8 Steps — clearing

1. Tools → Clear Cocotb Log (or the equivalent).
2. Verify the panel disappears and the timeline tick marks are removed.

### 7.9 Stress test

1. Load `cocotb_stress.log` (10 000+ entries).
2. Verify the panel populates without UI freeze.
3. Filter by severity. Verify filtering remains responsive.
4. Click an entry near the end of the log. Verify the cursor still jumps correctly.
5. Pane Render Stats popover (the `i`-icon on each pane's tab bar): verify the time-ruler tick rendering doesn't drop frames significantly even with thousands of marker entries.

### 7.10 Edge cases

- Log file with no recognizable timestamps — show error, don't crash.
- Log file referencing a simulation time that's outside the waveform's range — clamp or show warning.
- Empty log file — empty state, no crash.
- Malformed log lines mixed with good ones — parser should skip bad lines, surface the rest.
- Log with non-ASCII characters in messages — render correctly.

### 7.11 Automation Assessment

| Test | Coverage |
|---|---|
| Parse known log → expected entry count | **WIDGET** (`test/services/cocotb/cocotb_log_parser_test.dart`) |
| Click-to-jump cursor positioning | **WIDGET** (`test/features/cocotb/widgets/cocotb_log_entry_row_test.dart` covers the dispatch); viewport-pan side **INTEGRATION_TEST — pending** |
| Severity filter chip behavior | **WIDGET** (`test/features/cocotb/widgets/cocotb_severity_chips_test.dart`) |
| Keyword filter | **WIDGET** (`test/features/cocotb/providers/`) |
| Combined filter intersection | **WIDGET** (`test/features/cocotb/providers/` — AND-semantics test) |
| Timestamp unit conversion (fs/ps/ns/µs/ms/s) | **WIDGET** (`cocotb_log_parser_test.dart` — all SI-unit conversions) |
| Stress (10 k entries) load and filter | **HYBRID** — parse correctness in `cocotb_log_parser_test.dart`; UI freeze under load is **MANUAL** |
| Time-ruler tick rendering | **WIDGET** (`test/features/cocotb/widgets/cocotb_timeline_overlay_test.dart`); perceptual is **MANUAL** |
| Empty log file → empty state | **WIDGET** (`test/features/cocotb/widgets/cocotb_log_panel_test.dart`) |
| Malformed lines skipped | **WIDGET** (`cocotb_log_parser_test.dart` — tolerant-of-malformed-lines case) |

---

## 8. Integration and platform features

### 8.1 Interactive/streaming VCD

#### 8.1.1 What it does

Watch waveforms update live while a simulation is running. WaveCrux reads VCD data from stdin or a named pipe; the hierarchy appears as soon as the header is parsed; value changes appear progressively as they arrive. Useful for long simulations where the engineer wants to see early behavior without waiting for the full run.

#### 8.1.2 Setup

A pure-bash VCD streaming generator (see `helpers/README.md`). Bash-only avoids the platform-specific quirks of `iverilog`'s `$dumpfile` (e.g., on macOS it appends `.vcd` to the filename, breaking `/dev/stdout`).

#### 8.1.3 Steps — pipe mode

1. In one terminal: start WaveCrux with `--pipe ~/wavecrux_pipe`.
2. In another terminal: `mkfifo ~/wavecrux_pipe; ./streaming_vcd.sh > ~/wavecrux_pipe`.
3. Verify the hierarchy appears in WaveCrux as soon as the header is parsed.
4. Verify waveform data appears progressively as value changes arrive.
5. Verify a "LIVE" badge or indicator is shown in the toolbar.
6. Verify the user can navigate already-received data (zoom, scroll, cursor) while streaming continues.
7. Click "Stop" — verify streaming stops and the user can browse all received data normally.

#### 8.1.4 Steps — stdin mode

1. `./streaming_vcd.sh | wavecrux --interactive` (or equivalent flag).
2. Same expectations as pipe mode.

#### 8.1.5 Diagnostics-assisted verification

- File Info: should update progressively. Parse time should keep incrementing. Signal count fixed after header. Transition count grows.
- Memory tab: should grow in real time as data arrives.
- Render tab: repaint should be debounced — verify it's not thrashing on every transition.

#### 8.1.6 Edge cases

- Stop the producer mid-stream — WaveCrux should detect EOF and finalize gracefully.
- Producer that emits malformed VCD partway — clear error, partial data preserved.
- Very fast producer (no sleep) — backpressure or buffering, no crash.

#### 8.1.7 Automation Assessment

| Test | Coverage |
|---|---|
| Header parses → hierarchy visible | **INTEGRATION_TEST** (`integration_test/streaming/interactive_vcd_test.dart` — feeds header through a `StreamController`, asserts `rootScopes`/variables are populated after `$enddefinitions` and the LIVE badge appears in the toolbar) |
| Transitions appear progressively | **INTEGRATION_TEST** (`integration_test/streaming/interactive_vcd_test.dart` — first half of value changes brings `currentEndTime` to ≥ 50, second half extends it to ≥ 100 with no source reload — same `WaveformDataSource` instance throughout) |
| Producer EOF handling | **INTEGRATION_TEST** (`integration_test/streaming/streaming_eof_test.dart` — closes the byte stream after partial value changes, asserts no unhandled exception, transitions to Idle, LIVE badge clears, accumulated transitions remain queryable via `valueAt`) |
| LIVE badge | **WIDGET** (`test/features/viewer/widgets/viewer_toolbar_test.dart` — "LIVE badge and stop button absent when not streaming" + "shown when StreamingViewerStarting" + "shown when StreamingViewerActive") |
| Live-feel responsiveness | **MANUAL** |

---

### 8.2 FSDB conversion path

#### 8.2.1 What it does

FSDB is Synopsys's proprietary waveform format. WaveCrux cannot read it directly (legal blocker). Instead, when the user opens a `.fsdb` file, WaveCrux invokes Synopsys's `fsdb2vcd` converter (if installed) and loads the resulting VCD. If `fsdb2vcd` is not installed, WaveCrux shows a clear dialog explaining the situation and pointing the user to where they can get the tool.

**On web** the converter cannot run at all (no local process execution in the browser), so both web open paths (file-picker and drag-drop) detect a `.fsdb` upload by name *before* attempting to parse the bytes and show the dedicated `FsdbConversionDialog.showWebUnsupported` dialog ("FSDB needs the desktop app") instead of letting the raw bytes fail with a confusing generic "unsupported format" error. The dialog steers the user to the desktop build or to pre-converting the file to VCD/FST.

#### 8.2.2 Setup

This test verifies the **error/fallback path** — most developers will not have Synopsys tools installed, and that's exactly the scenario this test covers.

#### 8.2.3 Steps

1. Attempt to open a `.fsdb` file (any file with that extension; contents don't matter for the error path).
2. Verify a clear dialog appears explaining `fsdb2vcd` is not found.
3. Verify the dialog has a link or text pointing the user to Synopsys's tools.
4. Verify the dialog can be dismissed cleanly without crashing the app.

#### 8.2.4 Automation Assessment

| Test | Coverage |
|---|---|
| Missing-fsdb2vcd dialog appears | **WIDGET** (`test/features/viewer/widgets/fsdb_conversion_dialog_test.dart`) |
| Dialog content correctness | **WIDGET** (`fsdb_conversion_dialog_test.dart`) |
| Web `.fsdb` shows the "needs the desktop app" dialog (not a generic parse error) | **WIDGET** (`fsdb_conversion_dialog_test.dart` — `showWebUnsupported` group + locale sweep). End-to-end web open-path guard is **MANUAL** until the Chrome-headless harness lands. |
| Successful conversion | **MANUAL** (requires Synopsys tools, won't be in CI) |

---

### 8.3 Remote Control API and `wavecrux-ctl`

#### 8.3.1 What it does

A WCP (Waveform Control Protocol) server inside WaveCrux that lets external tools programmatically control the viewer: load files, add/remove signals, set cursor, move viewport, set markers, query signal values. WCP is the open protocol originally authored by the Surfer project; WaveCrux implements it natively so that any WCP-compatible tool or script — including those already written for Surfer — works with WaveCrux without modification. Primary use cases: CI integration ("did this regression's waveform have signal X go to 1?"), simulator integration, VS Code extension. WaveCrux also exposes viewer-specific extension commands (`wavecrux.getValueAt`, `wavecrux.getHierarchy`, `wavecrux.getState`, `wavecrux.setActiveTab`) announced in the WCP greeting; WCP-native clients ignore them. Companion CLI: `wavecrux-ctl`.

**Protocol notes:**
- Upstream spec: the Surfer project's `surfer-wcp` crate (`surfer-wcp/src/proto.rs` in `surfer-project/surfer`, pinned at commit `4281e79afec3fed8759aa45ade689a181aaad533`); protocol version `"0"`
- Default port: 54321 (WCP spec default; configurable in Settings → Remote Control; same default in `AppSettings.remoteControlPort`, `WcpServer.defaultPort`, and the `wavecrux-ctl` client)
- Message framing: null-byte terminated JSON (`\0`)
- On connect: the server sends `{"type":"greeting","version":"0","commands":[...]}`; a client greeting is optional (permissive deviation from upstream) but its `version` is checked — a major version other than 0 draws a spec-shaped `error: "greeting"` frame
- **Two command envelopes on one port.** Spec envelope (upstream): id-less `{"type":"command","command":<name>,...params}` with top-level parameters, replies correlated by order (a per-connection serial dispatch queue guarantees in-order replies), payload-bearing responses echo the command name, others reply `{"type":"response","command":"ack"}`, errors are `{"type":"error","error":…,"arguments":[…],"message":…}`. Legacy id dialect (used by `wavecrux-ctl`; retained behind `WcpServer.idDialectEnabled`, default on): integer `id` per command, parameters nested under `data`, responses/errors echo the id. A command frame with an integer `id` selects the dialect; an id-less frame selects the spec envelope.
- Deprecated spec commands `add_variables` / `add_scope` are accepted as aliases for `add_items`; `add_items` accepts the spec parameter name `items` plus the legacy `paths` / `item_path`
- After `load`/`reload`: async `waveforms_loaded` event (carrying `source`) broadcast to all connected clients — top-level fields for spec-envelope connections, `data`-nested for legacy connections
- Items (signals, markers) identified by stable `DisplayedItemRef` integer IDs; IDs are never reused after removal
- `add_items` / `add_markers` are atomic: every entry is validated/resolved before any state changes, so a partial failure adds nothing
- `get_item_list` reflects the real displayed state: UI-added signals receive ids on first enumeration, UI-removed items are pruned; `remove_items` on a marker id removes the marker itself

#### 8.3.2 Setup

- WaveCrux running with the remote-control server enabled (Settings → Remote Control → Enable).
- `wavecrux-ctl` binary available on PATH.
- A loaded VCD (e.g., `protocol/spi/generated/spi_basic.vcd`).

#### 8.3.3 Steps

1. Verify the server start/stop control in Settings works. After start, port 54321 (or the configured port) should be visible in Settings or a status indicator.
2. From a terminal: `wavecrux-ctl add-items top.clk` (or whatever signal exists in the loaded fixture). Verify the signal appears on the canvas.
3. Test additional WCP commands:
   - `wavecrux-ctl set-cursor <timestamp>` — cursor moves in WaveCrux.
   - `wavecrux-ctl set-viewport-range <start> <end>` — canvas zooms to that time range.
   - `wavecrux-ctl zoom-to-fit` — canvas fits full waveform.
   - `wavecrux-ctl add-markers <timestamp>` — marker appears on time ruler.
   - `wavecrux-ctl remove-items <id>` — signal removed from canvas.
   - `wavecrux-ctl load <path>` — different file loads; verify `waveforms_loaded` event is received before commands against the new file proceed.
   - `wavecrux-ctl reload` — current file reloads; `waveforms_loaded` event received.
   - `wavecrux-ctl clear` — all signals removed from canvas.
4. Test WaveCrux extension commands:
   - `wavecrux-ctl get-value top.data <timestamp>` — prints signal value.
   - `wavecrux-ctl get-hierarchy` — prints the full signal hierarchy.
   - `wavecrux-ctl get-state` — prints viewer state snapshot.
   - **`wavecrux.setActiveTab` (split-pane aware):** with a split-pane workspace (one tab in each pane) and the *non-active* pane's tab targeted, send `{"command":"wavecrux.setActiveTab","data":{"tab_id":"<uuid>"}}`. Verify the tab becomes active *and* its hosting pane gains focus (pane focus indicator switches). Repeat with an explicit `pane_id` field — must succeed when the tab is hosted by that pane, must return error code 6 when it is not. Unknown `tab_id` returns error code 6; missing `tab_id` returns error code 3. Response payload: `{"tab_id":"<uuid>","pane_id":"<uuid>"}`.
5. Test an unknown command — verify clear WCP error response.
6. Test multiple simultaneous connections (two terminal windows running `wavecrux-ctl`).
7. Stop the server in Settings — verify `wavecrux-ctl` gets connection refused.
8. Verify the diagnostics report includes remote control status (running/stopped, port, connection count).

#### 8.3.4 Edge cases

- Send a malformed JSON message (truncated before null-byte) — server replies with a WCP error.
- Send a command referencing a nonexistent `DisplayedItemRef` — proper error response.
- Disconnect mid-command — server cleans up gracefully.
- Port conflict (another process on the configured port) — clear error, no crash.
- Connect a WCP-native client (e.g., a Surfer WCP script) — greeting exchange succeeds; WaveCrux extension commands are announced but the client ignores them; all standard WCP commands function correctly through the id-less spec envelope, including the deprecated `add_variables` / `add_scope` aliases.
- Send a client greeting with `version: "2"` — server replies with a spec-shaped `error: "greeting"` frame; a `0.x` version is accepted silently.
- Pipeline several id-less commands back-to-back — replies arrive strictly in request order.
- `add_items` naming one resolvable and one unknown path — error response, and *nothing* from the batch is displayed or registered.

#### 8.3.5 Automation Assessment

| Test | Coverage |
|---|---|
| Greeting handshake on connect | **WIDGET** (`test/services/remote/wcp_server_test.dart`) |
| Each WCP command's effect on viewer state | **WIDGET** (`test/services/remote/wcp_server_test.dart`); end-to-end via real socket: `set_cursor` (`wcp_set_cursor_test.dart`), `set_viewport_range` (`wcp_set_viewport_range_test.dart`), `load` (`wcp_load_test.dart`), `reload` (`wcp_reload_event_test.dart`), `add_items` (`wcp_add_signal_test.dart`), `zoom_to_fit` / `add_markers` / `remove_items` (`wcp_zoom_marker_remove_test.dart`) — all **INTEGRATION_TEST**; `clear` remains WIDGET-only. `add_items` is additionally covered end-to-end through the real `wavecrux-ctl` CLI subprocess (`wcp_add_signal_cli_subprocess_test.dart`), not just a hand-rolled socket client. |
| `waveforms_loaded` event after `load`/`reload` | **WIDGET** (`wcp_server_test.dart`) |
| `DisplayedItemRef` ID stability (no reuse after removal) | **WIDGET** (`wcp_server_test.dart`) |
| WaveCrux extension commands (`getValueAt`, `getHierarchy`, `getState`) | **WIDGET** (`wcp_server_test.dart`); `getValueAt` also end-to-end via real socket + `signal_path`→`signalRef` resolution **INTEGRATION_TEST** (`integration_test/remote_control/wcp_get_value_test.dart`) |
| `wavecrux.setActiveTab` (with and without explicit `pane_id`; activation, focus, error paths) | **WIDGET** (`test/services/remote/remote_control_notifier_test.dart` — `RemoteControlNotifier — wavecrux.setActiveTab` group) |
| Error responses for unknown/invalid commands | **WIDGET** (`wcp_server_test.dart`) |
| Multiple concurrent connections | **WIDGET** (`wcp_server_test.dart`) + **INTEGRATION_TEST** (`integration_test/remote_control/wcp_multi_connection_test.dart` — two real simultaneous TCP sockets against one app; `connectedClients` tracking, per-connection response routing/no cross-talk, broadcast fan-out to both clients, shared provider-state effects from both, and `connectedClients` dropping correctly on disconnect) |
| Server lifecycle (start/stop) | **WIDGET** (`wcp_server_test.dart` + `wcp_notifier_test.dart`) |
| Port conflict handling | **WIDGET — pending** (port-in-use error path; queued) |
| Spec envelope (id-less commands, top-level params, command-echo responses, spec error shape) | **WIDGET** (`test/services/remote/wcp_server_test.dart` — `WcpServer — spec envelope` group) + **INTEGRATION_TEST** (`integration_test/remote_control/wcp_spec_envelope_test.dart` — full spec-envelope session against a live app: greeting version check, `add_items` via `items`, in-order pipelining, marker add/remove, partial-failure atomicity) |
| Greeting version check (`0` / `0.x` accepted; other majors → `error: "greeting"`) | **WIDGET** (`wcp_server_test.dart`) + **INTEGRATION_TEST** (`wcp_spec_envelope_test.dart`) |
| In-order pipelined replies (serial dispatch queue) | **WIDGET** (`wcp_server_test.dart` — "pipelined commands reply in request order") + **INTEGRATION_TEST** (`wcp_spec_envelope_test.dart`) |
| `add_variables` / `add_scope` deprecated aliases | **WIDGET** (`wcp_server_test.dart` + `remote_control_notifier_test.dart`) |
| `add_items` / `add_markers` atomicity on partial failure | **WIDGET** (`remote_control_notifier_test.dart`) + **INTEGRATION_TEST** (`wcp_spec_envelope_test.dart`) |
| `remove_items` on a marker id removes the marker | **WIDGET** (`remote_control_notifier_test.dart`) + **INTEGRATION_TEST** (`wcp_spec_envelope_test.dart`) |
| `get_item_list` reconciliation with UI-added/-removed items | **WIDGET** (`remote_control_notifier_test.dart` — "get_item_list enumerates UI-added signals and prunes UI-removed ones") |
| id-dialect compat flag (`idDialectEnabled: false` rejects id frames) | **WIDGET** (`wcp_server_test.dart`) |
| `wavecrux-ctl` CLI parsing | **WIDGET** (`tool/wavecrux_ctl/test/`) + **INTEGRATION_TEST** (`integration_test/remote_control/wcp_add_signal_cli_subprocess_test.dart` — the CLI spawned as a real OS subprocess via `Process.run`/`dart run` against a live running app, not just in-process arg-parsing unit tests) |
| Settings → Remote Control port + status row visibility | **WIDGET** (`test/features/settings/screens/settings_screen_test.dart` — "when remote control is enabled, port + server-status rows appear") |
| Diagnostics report includes remote-control status | **WIDGET — pending** (**feature gap, not test gap**: `lib/services/diagnostics/app_diagnostics_report_service.dart` does not currently emit a Remote Control section. Closing requires (a) adding the section, then (b) extending `app_diagnostics_report_service_test.dart`. Tracked in `integration_test/PENDING.md`.) |

---

### 8.4 Flutter Web

#### 8.4.1 What it does

WaveCrux compiled to WebAssembly/JS, runnable in any modern browser. Uses the pure Dart parser fallback (no FFI). Slower than the native FFI path, but sufficient for CI integration and quick reviews on machines without a native install.

#### 8.4.2 Setup

```bash
flutter build web
cd build/web && python3 -m http.server 8080
```

Open in Chrome (and ideally Firefox + Safari).

#### 8.4.3 Steps

1. Open `localhost:8080`. Verify the welcome screen appears.
2. Test file loading via the file picker — load a small VCD. Verify the waveform renders.
3. Test drag-and-drop a VCD onto the welcome screen — verify it loads.
4. Verify features that are disabled on web show appropriate messages:
   - FSDB conversion → "Not available on web".
   - Process filters → "Not available on web".
   - Interactive VCD (stdin) → "Not available on web".
   - Remote control server → "Not available on web".
   - Auto-reload file watching → "Not available on web".
5. Verify the file size warning shows for large files.
6. Test URL-based loading: `localhost:8080/?file=<url>` — verify it fetches and loads (the served VCD must have CORS headers).
7. Verify rendering performance is acceptable with ~50 signals.
8. Open the diagnostics panel — note which tabs are functional. The Memory tab's "process RSS" relies on `dart:io` and won't work on web; verify it shows a sensible fallback or N/A.
9. Test in Firefox and Safari for browser-specific issues.

#### 8.4.4 Edge cases

- Load a file larger than browser memory limits — clear error.
- CORS-blocked URL — clear error.
- Browser zoom / DPR change — canvas re-renders correctly.

#### 8.4.5 Automation Assessment

| Test | Coverage |
|---|---|
| Disabled-feature messaging (FSDB / process filter / interactive VCD / remote API / file watcher all "Not available on web") | **WIDGET — pending** (each feature has a `kIsWeb` early-return guard in source; closing this gap requires `flutter test --platform chrome` so `kIsWeb=true` at compile time. The harness for that now exists — `tool/run_web_widget_tests.sh` + the `widget-web` CI job run `@TestOn('browser')` tests — so this is now just writing the per-feature assertions, not standing up infrastructure. Tracked in `integration_test/PENDING.md`.) |
| Web parser produces correct `valueAt()` results (cross-bridge equivalence FFI vs WASM) | **INTEGRATION_TEST** (`integration_test/web/web_cross_bridge_test.dart` — loads every `test/fixtures/{vcd,fst,ghw}` fixture through `WellenWasmProvider` in headless Chrome and asserts `valueAt()` / `changesInRange()` / `nextTransition()` / `prevTransition()` reproduce the committed `.expected.json` gold. The FFI side is frozen into those companions via `tool/generate_bridge_snapshots.dart` (WASM == gold == FFI; ARCHITECTURE §8.9 Layer 1). Replaces the retired `integration_test/web/dart_vcd_provider_test.dart`.) |
| File picker upload | **INTEGRATION_TEST** (`integration_test/web/web_file_picker_test.dart` — mocks `FilePicker.platform` with synthetic browser-API bytes and asserts the empty-canvas pipeline lands a `WellenWasmProvider` on the active tab; verifies the screen renders without `RenderFlex` overflow at 1024×768 and 1440×900. A follow-up WebDriver variant that drives the native browser file chooser is still pending.) |
| Command palette opens via Ctrl/Cmd+Shift+P | **INTEGRATION_TEST** (`integration_test/web/web_command_palette_test.dart` — opens the palette, fuzzy-filters "toggle the", presses Enter, and asserts the active color-theme preset's brightness actually flipped through the `ShortcutManagerWidget` handler). |
| URL-based loading | **DONE** (`integration_test/web/web_url_file_load_test.dart` — drives `bootstrap(args: [url])`, the same seam the desktop CLI/`?file=` route param feed, against a standalone `tool/cors_fixture_server.dart` process. Covers both the CORS-permissive success path — real fetch, real WASM parse, hierarchy + signal transitions asserted — and the CORS-blocked failure path — no source ever loads, and the localized `urlFileLoadError` SnackBar appears. The bare-root `<app>/?file=<url>` browser-address-bar deep link — where `router.dart`'s redirect must rewrite `/` → `/viewer` while **preserving** the `?file=`/`?session=` query string — is covered separately by the `rootRedirect` group in `test/core/router_test.dart`. That redirect previously dropped the query (`path == '/'` unconditionally rewrote to a bare `/viewer`); the fix + regression tests landed with this entry, so the integration test injecting at the CLI-args seam and the unit test covering the redirect together close the full path.) |
| Drag-and-drop | **INTEGRATION_TEST** (`integration_test/web/web_drag_drop_test.dart` — invokes the `WebDropZone.onFilesDropped` bridge `_WebDropZoneState._onDrop` uses with synthetic bytes; the DOM-level `dragover`/`drop` listener attached by `WebDropTarget` is covered by the unit tests on `web_drop_target_impl.dart`). |
| Cross-browser rendering | **MANUAL** (Chrome / Firefox / Safari) |
| Diagnostics Memory tab handles missing process RSS gracefully | **WIDGET** (`memory_stats_panel_test.dart` covers the missing-RSS branch) |

---

### 8.5 Contextual help links

#### 8.5.1 What it does

Minimal `?` icons or "Learn more →" links in dialogs where features aren't obvious — protocol decoder config, Stage panel empty state, translate filter picker, remote control settings, pattern search dialog, waveform diff toolbar.

#### 8.5.2 Steps

1. Visit each location with a `?` icon. Click each.
2. Verify the URL opens the matching section of the documentation (`docs.wavecrux.app/<page>#<section>`): a decoder's `?` lands on that decoder's row of Protocol decoders (a `sigrok.*` decoder on the Sigrok bridge page, any other plugin on Authoring custom decoders), the plugin panel's "Learn more" on installing plugins, the plugin safety dialog's guide link on the plugin security section, the translate filter picker on Working with signals → filters, remote control on connecting to WCP, pattern search and the diff toolbar on their Analysis sections.
3. No link may land on a "Not found" page.

#### 8.5.3 Automation Assessment

| Test | Coverage |
|---|---|
| Help icon presence | **WIDGET** (centralised in `lib/shared/widgets/help_link.dart`; per-call-site coverage is implicit via the host widgets' tests) |
| Link target correctness | **UNIT** (`test/core/help_urls_test.dart` resolves every documentation URL in `lib/core/help_urls.dart` to a `docs-site/docs` page and anchor) |
| Live URL reachability | **MANUAL** (don't depend on network in CI) |

---

### 8.6 macOS native file-picker entitlement

#### 8.6.1 What it does

On macOS, `File → Open` (and any other native open/save panel — VCD export, translate-filter picker, session save) goes through the `file_picker` plugin. As of `file_picker` 12.x the plugin performs an **unconditional entitlement check** in its native handler (`MacOSFilePickerHandler.checkEntitlement`) before showing any `NSOpenPanel`/`NSSavePanel`: it reads `com.apple.security.files.user-selected.read-only` / `…read-write` via `SecTaskCopyValueForEntitlement` and, if **neither** is present, throws `PlatformException(ENTITLEMENT_NOT_FOUND, "Either the Read-Only or Read-Write entitlement is required for this action.")`. This check runs **even when the app sandbox is disabled** (`com.apple.security.app-sandbox = false`), so the entitlement must be present regardless of sandbox state.

`macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements` both declare `com.apple.security.files.user-selected.read-write` (`read-write` satisfies both the open panel's `readOrWrite` mode and any save panel's `requireWrite` mode). This is a build-packaging regression that is **invisible from the Dart code** — it lives only in the `.entitlements` plists — so it is verified manually here as well as implicitly by every macOS desktop open-file flow.

#### 8.6.2 Steps — macOS desktop

1. Build and run the macOS desktop app (debug **and** a release/profile build — they use different `.entitlements` files).
2. `File → Open` (or the welcome-screen Open button). Verify the native macOS open panel appears — **not** an `ENTITLEMENT_NOT_FOUND` exception in the console.
3. Pick a VCD/FST file and confirm it loads.
4. Trigger a save panel (VCD export, or session save) and confirm it appears without an entitlement error.

#### 8.6.3 Automation Assessment

| Test | Coverage |
|---|---|
| Entitlement key present in both plists | **STATIC — candidate** (a trivial file-presence assertion over `macos/Runner/*.entitlements`; currently **MANUAL**) |
| Native open panel appears on macOS | **MANUAL** (OS-level native panel; not drivable in widget/integration tests) |

---

### 8.7 macOS runtime file-open (Finder / `open -a`) — including during a large restore

#### 8.7.1 What it does

Separate from `File → Open` (§8.6, the in-app native panel), macOS also opens
files handed to the *already-running* (or cold-launched) app by the OS: a
Finder double-click on a `.vcd`/`.fst`/`.ghw`/`.wavecrux`, a drag onto the Dock
icon, or `open -a "WaveCrux" trace.vcd` from a Terminal. macOS delivers these as
document Apple events, which the Flutter engine forwards to the framework as a
`file://` deep-link; the router's `fileUrlRedirect` rewrites it to
`/viewer?file=<path>` and `ViewerScreen` opens it as a new tab (or focuses the
existing tab if the file is already open).

Two failure modes are covered here (both since fixed):

1. **Open while a large workspace is restoring.** If the saved workspace holds a
   very large trace (a multi-hundred-MB / million-signal FST), cold-start
   restore takes tens of seconds. A file opened during that window used to be
   **silently dropped — and never opened even after restore finished** — because
   the runtime-open path did not wait for the cold-start reconcile and lost the
   race to it. The open is now **queued on the reconcile barrier**
   (`startupReconcileProvider`) and applied the instant restore settles.
2. **Re-opening an already-seen path.** macOS delivers a repeat open of the same
   file as the *identical* `file://` location, which go_router collapses to a
   no-op. The desktop rewrite now stamps a monotonic `req` token so the second
   `open -a` of the same path still reaches the viewer (focuses the tab, or
   reloads it if the on-disk contents changed).

#### 8.7.2 Prerequisites / infrastructure

- **A release or profile macOS build.** Use `flutter build macos --release` (or a
  profile build) and launch the built `.app` — do **not** drive this from a
  VS Code debug launch: debug builds hit the macOS 26 VS Code JIT SIGBUS
  (`docs`/memory: `macos26_debug_jit_crash`) and use different `.entitlements`.
- **A "large enough to see the restore spinner" trace.** Any FST/VCD whose parse
  keeps the restore spinner up for ≥ ~10 s works. Options, cheapest first:
  - Reuse a real gate-level dump you already have (e.g. a multi-hundred-MB `.fst`).
  - Synthesize one with the in-repo scale generator — **no HDL simulator
    required** (the file is emitted directly, deterministically):
    `dart run tool/generate_scale_fixtures.dart --out /tmp/wc --signals 5000`
    (bump `--signals` / `--transitions-per-signal` until the restore visibly
    lags; a 5000-signal file is tens of MB). These fixtures are deliberately
    uncommitted — they exceed the corpus cap — so regenerate locally.
    **No `iverilog`/`verilator` is needed for this test** — those are only
    required to regenerate protocol-decoder *captured* fixtures (see the decoder
    sections), not for the file-open flow.
- **A small second trace** to open during the restore, e.g. any
  `test/fixtures/vcd/scalar_basics.vcd`.
- **Terminal** for the `open -a` invocation, and **Finder** for the
  double-click / drag-to-Dock variants.

#### 8.7.3 Steps — open during a large restore

1. Load the large trace and quit the app so it is saved as the auto-managed
   workspace (confirm the next launch restores it).
2. Relaunch WaveCrux. While the restore spinner is still up, from Terminal run:
   `open -a "WaveCrux" /path/to/small.vcd` (Pro build: `open -a "WaveCrux Pro" …`).
3. **Expected:** `small.vcd` opens as a new tab — either immediately or the
   moment the large restore finishes settling. It is **never** lost. (Pre-fix:
   no tab, no error, ever.)
4. Repeat with a Finder double-click and a drag-onto-Dock instead of `open -a`;
   all three deliver the same document event and must behave identically.

#### 8.7.4 Steps — re-open the same path

1. With the app idle (restore done), `open -a "WaveCrux" /path/to/small.vcd`.
   Confirm it opens/focuses the tab.
2. Close that tab. Run the **exact same** `open -a …` command again.
3. **Expected:** the file re-opens (a fresh tab). (Pre-fix: the repeat open of an
   already-seen path was a go_router no-op and did nothing.)

#### 8.7.5 Edge cases

- Open **two** small files in quick succession during the restore window — both
  must end as tabs (queued in order), neither dropped.
- `open -a` a file that is **already open** in a restored tab — it must focus
  that tab (and reload if the file changed on disk), not spawn a duplicate.
- Linux/Windows use the same desktop rewrite branch; a Finder-equivalent open
  (file-manager double-click / `xdg-open` / associated-app launch) should
  exercise the same `?file=&req=` path.

#### 8.7.6 Automation Assessment

| Test | Coverage |
|---|---|
| Desktop rewrite stamps a monotonic `req` (repeat same-path open isn't a no-op) | **UNIT** (`test/core/router_test.dart` — "stamps a monotonic req token for repeat opens") |
| Runtime open mid-restore is queued on the reconcile barrier and drains after restore (not dropped, not applied early) | **WIDGET** (`test/features/viewer/screens/viewer_screen_phone_incoming_file_test.dart` — "runtime open arriving mid-restore is QUEUED…") |
| CLI/initState open already awaits the barrier (parity) | **WIDGET** (existing `_openInitialCliFiles` path) |
| Real macOS Apple-event delivery (Finder / `open -a` / Dock) during a real large-FST restore | **MANUAL** (OS-level document-event integration; not drivable in the widget harness) |

---

### 8.8 Dropping files on the desktop window (macOS, Windows, Linux)

#### 8.8.1 What it does

Dragging one or more files from Finder, Explorer or a Linux file manager and
releasing them anywhere over the WaveCrux window opens them — on the welcome
screen (empty canvas) and over an already-open waveform alike. The whole window
is the target, including the Windows/Linux title bar and menu bar. While a drag
is over the window a signal-green border and a centred card ("Drop to open")
cover it.

A drop takes exactly the File > Open route, so it behaves as picking the same
files would:

- every waveform opens in **its own new tab** (dropping a file that is already
  open opens it again, as File > Open does — unlike a Finder double-click,
  which focuses the existing tab);
- `.fsdb` gets the `fsdb2vcd` conversion offer, `.lxt`/`.lxt2` convert on open,
  `.wavecrux` restores a session, `.wavecruxpack` opens a share bundle, and a
  `.crux-project` manifest (or a design folder holding one) opens the waveform
  it names;
- a dropped **`.gtkw`** is imported into the active tab, exactly as
  File > Import GTKWave Session does after its picker. With no waveform open,
  the same import summary appears, listing every signal as not found. When a
  waveform and its `.gtkw` are dropped together, the waveform opens first and
  the session is applied to it, whichever order the file manager sent them in;
- a file that is not a waveform opens into the tab's **Failed to load waveform**
  error (and is announced to a screen reader), the same as opening it any other
  way — never a silent no-op;
- each opened file is added to Recent Files.

A drop is ignored — and no overlay appears — while a dialog, a native file
dialog, or the first-launch licence / telemetry gate is in front of the viewer.

The browser build is unchanged: it keeps the welcome screen's own drop zone
(§8.4, §16.1). Mobile is unchanged. In-app drags (tab chips, signals, the Stage
bindings pane) are Flutter gestures, not OS drags, and are unaffected.

#### 8.8.2 Setup

- A desktop build of each platform (release or profile; the Pro build ships).
- Fixtures: `verification/fixtures/vcd/scalar_basics.vcd`,
  `test/fixtures/vcd/deep_hierarchy.vcd`, a GTKWave save for `scalar_basics`
  (save one from GTKWave, or write `top.clk` / `top.rst` / `top.data` one per
  line into `scalar_basics.gtkw`), and any non-waveform file (a `.txt`).

#### 8.8.3 Steps and expected behavior

1. **Welcome screen.** Launch with no file. Drag `scalar_basics.vcd` over the
   window: the green border and "Drop to open" card appear the moment the
   pointer enters, anywhere in the window (try the toolbar, the empty canvas,
   the status bar and — Windows/Linux — the title bar). Drag back out without
   releasing: the overlay disappears and nothing opens. Drag in again and
   release: the file opens in a new tab and appears in Recent Files.
2. **Over an open waveform.** With `scalar_basics.vcd` open, drop
   `deep_hierarchy.vcd` onto the waveform canvas: it opens in a **second** tab
   and becomes active; the first tab is untouched.
3. **Several files.** Select both VCDs in the file manager and drop them in one
   gesture: each opens in its own tab.
4. **`.gtkw` with a waveform open.** With `scalar_basics.vcd` active, drop
   `scalar_basics.gtkw`: the GTKWave Import Complete dialog reports 3 signals
   imported and the signals appear in the active tab. No new tab opens.
5. **`.gtkw` with nothing open.** Close all tabs, drop the `.gtkw`: the same
   dialog reports 0 imported and lists the signals not found.
6. **Waveform + `.gtkw` together.** From the welcome screen, drop the VCD and
   its `.gtkw` in one gesture: the VCD opens, then the import dialog reports 3
   imported into it.
7. **Unsupported file.** Drop the `.txt`: a tab opens showing
   **Failed to load waveform** with the parser's reason.
8. **FSDB** (only where `fsdb2vcd` is installed): drop an `.fsdb`; the
   conversion offer appears exactly as for File > Open.
9. **Blocked while a dialog is up.** Open Settings (dialog on desktop) and drag
   a file over the window: no overlay; releasing opens nothing.
10. **In-app drags still work.** Reorder a tab chip, drag a signal in the
    signal list, and (with a Stage widget) drag a signal onto the Stage
    bindings pane: each behaves as before and no drop overlay appears.

#### 8.8.4 Diagnostics-assisted verification

- The Tab Diagnostics drawer's File Info for a dropped tab shows the dropped
  path — the drop passes paths through unchanged, it does not copy the file.
- Recent Files (welcome screen) lists each dropped file once per drop, most
  recent first.

#### 8.8.5 Edge cases

- A dropped **folder** holding one `<design>.crux-project` opens the waveform
  it names; a folder with none opens into the load error; one with several
  shows the ambiguous-manifest message (§16.1.8).
- A drop during a long cold-start restore is queued and applied once the
  restore settles, as a Finder open is (§8.7).
- Paths with spaces and non-ASCII characters open (the plugin delivers decoded
  paths on every platform).
- macOS: dropping a file from a Mail attachment or another app that supplies a
  file *promise* opens the materialized copy.
- Linux under Flatpak/portal sources: `desktop_drop` resolves the portal
  transfer key to a real path; if it cannot, the drop opens nothing (report it).

#### 8.8.6 Automation Assessment

| Test | Coverage |
|---|---|
| Drop routing: empty canvas opens, drop over a viewer opens a new tab, duplicate drop opens again, multiple files, `.gtkw` with / without an open waveform, waveform + `.gtkw` in one drop, unsupported file opens into the load error, ignored under a dialog or a modal gate, overlay shows and clears | **WIDGET** (`test/features/viewer/screens/viewer_screen_file_drop_test.dart` — real FFI parses, drop driven through the window target's seam) |
| Window target: overlay on enter/exit, delivery in open order, refuses when the viewer cannot accept, desktop-only mount, no remount of the app, plugin message → paths | **WIDGET** (`test/features/workspace/widgets/desktop_file_drop_target_test.dart`) |
| Router: attach/detach, accept checks, `.gtkw`-last open order | **UNIT** (`test/services/platform/desktop_file_drop_router_test.dart`) |
| Overlay text, pointer pass-through, locale sweep at the 800 × 500 minimum window | **WIDGET** (`test/features/workspace/widgets/file_drop_overlay_test.dart`) |
| Booted app: plugin channel messages → overlay → tab opened and saved in the workspace | **INTEGRATION_TEST** (`integration_test/workspace/empty_canvas_drag_drop_test.dart`) |
| A real OS drag from Finder / Explorer / a Linux file manager, per platform | **MANUAL** (the OS drag session cannot be driven from a test; steps 1–10 above) |

---

## 9. Mobile, tablet, and adaptive layout

> **Run on physical devices wherever possible.** Simulators and emulators miss real-world issues like gesture feel, memory pressure, and GPU performance.

### 9.1 Device classification and adaptive layout

#### 9.1.1 What it does

WaveCrux derives a `DeviceClass` from the live viewport size and adapts the layout to it. `DisplaySizeFeed` (mounted once at the app root inside `MaterialApp.builder`) pushes `MediaQuery.sizeOf` into `displaySizeProvider`; `deviceClassProvider` derives the class from that; and the per-tab `ViewerScreen` (via `CruxIdeLayout` + `_syncControllerToState`) renders the right chrome for the class:

- **Phone** (< 600 dp): single-pane scaffold, signal tree as drawer, value column inline-at-cursor; side/bottom IdeLayout panes force-hidden.
- **Tablet** (600–1200 dp): simplified multi-pane.
- **Desktop** (≥ 1200 dp): full `IdeLayout` with resizable splitters.

The class responds to width+height, not to `Platform.isIOS` / `Platform.isAndroid` — so an iPad in split-screen narrow mode correctly drops to the phone layout, and a (non-native-desktop) window resized narrow gets the right layout for its width. On a native desktop host the class is floored to desktop regardless of window size (see `deviceClassForSize`). (The earlier `AdaptiveScaffold`/`PhoneLayout`/`TabletLayout`/`DesktopLayout` widget family that once did this was superseded by the above and has since been removed.)

#### 9.1.2 Setup

- iPhone, iPad, Android phone, Android tablet — physical devices recommended.
- A medium-sized VCD file.

#### 9.1.3 Steps

1. **iPhone (portrait):** verify single-pane layout. Signal tree opens as a drawer (left status-bar chevron) **and is populated with the loaded file's signals** — you can browse the hierarchy and add signals to the canvas. (Regression: the phone drawer is hosted by the screen-level Scaffold, outside the per-tab provider scope; it must be re-bound to the active tab's container or it shows an empty tree and you cannot add any signals — even though iPad/desktop, which dock the tree inside the tab scope, work.) Value column opens as bottom sheet.
2. **iPhone (landscape):** verify the layout adapts — typically still single-pane but waveform-focused (don't accidentally switch to tablet layout just because landscape adds width).
3. **iPad (landscape):** verify simplified multi-pane.
4. **iPad split-screen narrow:** verify the layout drops to phone layout when the width crosses below 600 dp.
5. **Desktop window resized narrow** (drag window edge to phone width): verify desktop layout drops to phone layout at the breakpoint.
6. **Desktop window full size:** verify full IdeLayout with all panes.
7. **Ultrawide display (≥ 21:9).** On an ultrawide monitor or XR-glasses 32:9 mode (or by stretching the desktop window to ≥ 21:9), open a fresh workspace and confirm the signal-tree (left) and value-column (right) panes open *wider than the standard 280 / 220 dp* — ~360 / 280 at 21:9, ~420 / 320 at 32:9 — so deep hierarchical signal names and wide values stop truncating, while the canvas still keeps the bulk of the width. What the user gets: the extra horizontal room of an ultrawide / XR display is spent on readable names + values rather than an over-stretched canvas. This affects only the *default*: drag a splitter and your size is persisted and wins on the next open, at any aspect ratio. On a normal (< 21:9) screen the defaults are unchanged.

#### 9.1.4 Edge cases

- Compound device classification: phone-landscape vs tablet — verify the heuristic is right (not just "wider than 600 dp = tablet"; phones in landscape may still be < 600 dp tall and want the phone layout).
- Orientation change during use: verify state is preserved (signals on canvas remain, cursor stays at same time).
- Ultrawide pane defaults apply only when the user has not dragged a splitter; a persisted pixel width overrides them at every aspect ratio. Crossing the 21:9 / 32:9 thresholds only affects *newly seeded* (null) pane sizes.

#### 9.1.5 Automation Assessment

| Test | Coverage |
|---|---|
| Layout selection at each breakpoint | **WIDGET** (`device_class_provider_test.dart` — classification per breakpoint; `test/features/viewer/screens/viewer_screen_test.dart` — IdeLayout mounted when a tab is open + phone drawer behavior); on-device feel **INTEGRATION_TEST — pending** |
| Phone signal-tree drawer resolves the active tab scope (populated, not empty) | **WIDGET** (`test/features/viewer/screens/viewer_screen_test.dart` — "phone signal-tree drawer reads the active tab scope, not the empty root") |
| Compound classification logic | **WIDGET** (`device_class_provider_test.dart` — width+height combinations including phone-landscape) |
| Size-aware default pane widths (ultrawide **and** narrow) | **UNIT** (`pane_defaults_test.dart` — 21:9 / 32:9 thresholds, the 800 dp narrow threshold, boundary inclusivity, canvas-budget assertions, standard-aspect and degenerate fallbacks); seeding into the live IdeLayout at either extreme **MANUAL** |
| iPhone Duo pose classification (4 poses + the fold transition) | **UNIT** (`device_class_test.dart` — "iPhone Duo poses": cover portrait → phone, cover landscape → phoneLandscape, inner portrait/landscape → tablet, phone→tablet boundary crossing, no pose reaches desktop); on-hardware fold/unfold **MANUAL — pending hardware (2026-10-23)** |
| Orientation change preserves state | **WIDGET** (state is Riverpod-provider-held, so it survives the layout rebuild by construction; `device_class_provider_test.dart` covers re-classification on the resize/orientation size change); real OS rotation **INTEGRATION_TEST — pending** |
| Physical device feel | **MANUAL** |

---

### 9.2 Mobile file loading

#### 9.2.1 What it does

On mobile, the primary file path is the share sheet / document picker. Engineers receive VCD/FST files via Slack/email/AirDrop and tap the file → "Open With WaveCrux". WaveCrux registers file type associations for `.vcd`, `.fst`, `.ghw`, `.wavecrux` so it appears in the system share sheet.

#### 9.2.2 Steps — share sheet path

1. AirDrop or email a VCD to the test device.
2. Tap the file in the receiving app (Files, Mail, etc.).
3. Verify "Open With WaveCrux" appears in the share sheet.
4. Tap it. Verify WaveCrux opens with the file loaded.

#### 9.2.3 Steps — document picker path

1. Inside WaveCrux on mobile, tap "Open File".
2. Verify the system document picker appears (not a custom picker).
3. Pick a file. Verify it loads.

#### 9.2.4 Steps — repeated / same-named shares (SharedImports overwrite)

The share-sheet import copies every incoming file to
`Documents/SharedImports/<basename>`, **overwriting** a same-named earlier
import in place. HDL dumps are routinely all called `dump.vcd`, so this path
is hit constantly: the tab already open for that path must **reload** the
replaced contents rather than silently keep showing the previous parse
(regression: phone "second file won't open / signal-tree drawer shows the
earlier file's signals"). The plumbing is the `req` open-request token
(`_onIncomingFile` → router `?req=` → `ViewerScreen.openRequest`) plus the
mtime+size staleness check (`WaveformSourceNotifier.isSourceFileReplacedOnDisk`).

1. Share a VCD named `dump.vcd` (contents A) to the device → opens, signal
   tree shows A's hierarchy.
2. Share a *different* VCD also named `dump.vcd` (contents B) → the SAME tab
   reloads; signal tree (phone: the left drawer) now shows B's hierarchy.
   The status bar and the drawer agree — no stale A signals anywhere.
3. Share the *identical* `dump.vcd` (contents B) a third time → tab focuses,
   **no** reload flicker (unchanged mtime+size short-circuits).
4. Cold-launch case: force-quit mid-load on a previous run (or arm the
   restore-guard sentinel `restore_in_progress` in Application Support), so
   the next launch restores the tab chip WITHOUT loading (red recovery
   banner). Share the same file again → the tab loads (the activate() of an
   already-active tab is a no-op, so the open path itself performs the load).

#### 9.2.5 Edge cases

- Share sheet from an iCloud Drive file — should download then open.
- Very large file from share sheet — large file warning should appear before loading.
- Same-named share while the drawer is OPEN — the drawer rebinds live to the
  reloaded hierarchy (it is keyed by the active tab id + container).

#### 9.2.6 Automation Assessment

| Test | Coverage |
|---|---|
| File type association registration | **MANUAL** (OS-level integration; share-sheet "Open With WaveCrux") |
| Document picker file loading | **INTEGRATION_TEST — pending** (real OS document picker; queued in `integration_test/PENDING.md`) |
| Large file warning trigger | **WIDGET** (`test/features/viewer/widgets/large_file_warning_dialog_test.dart` — phone 100 MB / tablet 250 MB thresholds) |
| Same-path re-share reloads replaced contents (phone drawer) | **WIDGET** (`test/features/viewer/screens/viewer_screen_phone_incoming_file_test.dart` — full phone flow: incoming file after first build, drawer contents, same-path overwrite reload via `openRequest`, unloaded-active-tab load) |
| Staleness stat capture (mtime+size at parse) | **UNIT** (`test/features/viewer/providers/waveform_source_provider_open_test.dart` — `isSourceFileReplacedOnDisk` false-after-open / true-after-rewrite / false-when-missing) |
| Real OS share delivery of a same-named file (warm + cold) | **MANUAL** (needs the native `SharedImports` copy; the Dart flow below it is the WIDGET coverage above) |

---

### 9.3 Mobile memory management

#### 9.3.1 What it does

iOS and Android have tighter memory budgets than desktop. The `MobileMemoryGuardService` monitors memory via `MemoryStatsService` and unloads non-visible signal data when approaching device limits. Large file warnings (100 MB phone, 250 MB tablet) appear before loading.

#### 9.3.2 Steps

1. On phone, attempt to load a >100 MB file. Verify the warning appears with a clear "Open anyway / Cancel" choice.
2. On tablet, repeat with a >250 MB file.
3. Load a moderately large file (under the warning threshold). Open many signals. Open the diagnostics Memory tab. Verify memory grows. Scroll the canvas extensively. Verify the memory guard kicks in when approaching limits — non-visible signal data is unloaded, memory drops.
4. Verify scrolling back to a previously-unloaded region re-fetches data correctly (transparent to the user).
5. Trigger an OS memory warning (iOS Simulator → Debug → Simulate Memory Warning, or equivalent on Android). Verify WaveCrux responds — drops caches, doesn't crash.

#### 9.3.3 Diagnostics-assisted verification

- Memory tab on mobile should show: process RSS, wellen DB size, loaded signal count, with the loaded signal count dropping when the guard unloads non-visible signals.

#### 9.3.4 Automation Assessment

| Test | Coverage |
|---|---|
| Large file warning thresholds | **WIDGET** (`test/features/viewer/widgets/large_file_warning_dialog_test.dart`) |
| Memory guard unload behavior | **WIDGET** (`test/services/mobile/mobile_memory_guard_service_test.dart`) |
| OS memory warning response | **WIDGET** (`mobile_memory_guard_service_test.dart` covers the unload pathway) + **DONE** (`integration_test/mobile/os_memory_pressure_test.dart` — drives the real `WidgetsBinding.instance.handleMemoryPressure()` entry point against a booted app; asserts the loaded-but-not-visible signal is dropped, the visible one is spared, and the app keeps rendering with no exception afterward) |
| Re-fetch on scroll back | **DONE** (`integration_test/canvas/scroll_back_refetch_test.dart` — real FFI-parsed source, real `WaveformCanvas`, real drag gestures on the vertical scrollable; scrolls 300 signals so the topmost is genuinely evicted past `SignalLoadPlanner`'s retention budget, then scrolled back and re-checked for the correct value. Note: the actual scroll-driven unload/re-fetch mechanism is `_WaveformCanvasState`'s own viewport-gated `SignalLoadPlanner` pipeline — not `MobileMemoryGuardNotifier`, which only unloads signals missing from the signal group and is gated off on desktop.) |

---

### 9.4 Touch gestures and mobile UI

#### 9.4.1 What it does

Pan, pinch-to-zoom, tap-to-set-cursor, long-press for context menu, drawer swipe-from-left, bottom sheet drag — all the touch primitives a mobile waveform viewer needs. Critical that gestures don't conflict (e.g., drawer swipe shouldn't trigger when the user is panning the waveform near the left edge).

#### 9.4.2 Steps

1. Pinch-to-zoom on the waveform canvas — verify smooth zoom.
2. Two-finger pan — verify horizontal scrolling works, doesn't accidentally trigger pinch.
3. Tap to set cursor — verify cursor moves to tap location, value column updates.
4. Long-press a signal — verify context menu appears.
5. Swipe from left edge — verify drawer opens.
6. Swipe from left edge **while a pan is in progress** — verify the swipe does NOT hijack the pan. The drawer should require a clear edge swipe.
7. Drag the bottom sheet up/down — verify it expands/collapses.
8. Drag the bottom sheet **while panning the canvas** — verify gestures don't conflict.

#### 9.4.3 Automation Assessment

| Test | Coverage |
|---|---|
| Each gesture's effect | **WIDGET** (`test/features/viewer/widgets/waveform_gesture_handler_test.dart`); real touch arena **INTEGRATION_TEST — pending** |
| Gesture conflict resolution (drawer-vs-canvas, sheet-vs-canvas) | **INTEGRATION_TEST** (`integration_test/gestures/gesture_conflict_drawer_canvas_test.dart`) — asserts a canvas touch-swipe stays a pan (no cursor scrub) and does not open a drawer, and that the phone drawer opens cleanly without disturbing the cursor. The drawer half is **phone-class only** (the macOS/desktop runner classifies even a 390×844 surface as tablet, so the phone Drawer is absent there → that half runs on the iOS/Android mobile track). The left-EDGE drawer-open *gesture* winner (Scaffold edge-drag vs canvas raw-pointer Listener) remains **real-device-only** (gesture-arena), verified manually. |
| Long-press = right-click context menu (signal list / signal tree / cocotb / canvas / transaction table) | **WIDGET** (per-row `PlatformContextMenu` tests in respective panel tests); real touch arena **INTEGRATION_TEST — pending** |
| Gesture feel/responsiveness | **MANUAL** |

#### 9.4.4 App-wide two-finger trackpad scroll (macOS / iPad)

**What it does.** On a laptop **trackpad** a two-finger vertical swipe scrolls whatever list/panel is under the pointer. macOS/iPad deliver that gesture as `PointerPanZoom` events; a Flutter `Scrollable` only treats those as a scroll when `PointerDeviceKind.trackpad` is in its `dragDevices`. The app-wide `ScrollConfiguration` (`app.dart`, `kAppScrollDragDevices`) includes `trackpad` for exactly this reason. Three widgets own the trackpad gesture themselves and opt back out via `kTrackpadOwnedDragDevices`: the **waveform canvas** (`WaveformGestureHandler` maps the swipe to zoom / time-pan / lane-scroll), the **signal-list names column** and the **command palette** (both drive their controller through `TrackpadScrollListener`). The opt-out prevents the native scrollable from double-driving the offset.

**Steps** (laptop trackpad, macOS or iPad Magic Keyboard):

1. Open a file with many signals. Two-finger-scroll the **signal-tree (SST) browser** on the left — the list scrolls (previously only the scrollbar worked). Repeat for the **transaction table**, a **diagnostics panel** (e.g. Signal Health), and the **cocotb log** — each scrolls under a two-finger swipe.
2. Two-finger-scroll the **signal-list names column** (center-left) and the **waveform canvas** — both still scroll and stay vertically in sync (the canvas maps horizontal pan → time and pinch → zoom, unchanged).
3. Open the **command palette** (⌘⇧P) with more entries than fit; two-finger-scroll the results — scrolls once (no double-speed jump).
4. With a mouse (if available), confirm a click on a control does **not** turn into a drag-scroll (mouse is intentionally excluded from `dragDevices`), and the mouse wheel still scrolls.

**Edge cases.** Names column + canvas must scroll by the *same* amount (single, not double). Pinch-to-zoom on the canvas must still zoom (not scroll the lanes). A single-finger tap anywhere must still register as a tap.

##### 9.4.4.1 Automation Assessment

| Test | Coverage |
|---|---|
| `kAppScrollDragDevices` includes trackpad + touch, excludes mouse; `kTrackpadOwnedDragDevices` excludes trackpad | **UNIT** (`test/app_scroll_drag_devices_test.dart`) |
| A bare list panel (signal tree) scrolls under a synthetic trackpad pan-zoom with the app dragDevices, and does NOT with `{touch}` only | **WIDGET** (`test/features/signal_tree/widgets/signal_tree_panel_trackpad_scroll_test.dart` — positive + control) |
| Names column / command palette still scroll via `TrackpadScrollListener` (opt-out doesn't disable them) | **WIDGET** (existing `signal_list_panel_test.dart`, `command_palette_dialog_test.dart`) |
| Real trackpad feel, single-vs-double scroll amount, pinch-still-zooms, tap-still-taps | **MANUAL** |

---

### 9.5 State preservation across orientation changes

#### 9.5.1 Steps

1. Open a VCD on phone in portrait. Add several signals. Set cursor at T=500 ns.
2. Rotate to landscape. Verify: same file is loaded, same signals are on the canvas, cursor is still at T=500 ns.
3. Open the drawer. Rotate. Verify drawer state is preserved (open or closed).
4. With diff active, rotate. Verify diff state preserved.
5. With X-Trace active, rotate. Verify X-Trace state preserved.

#### 9.5.2 Automation Assessment

| Test | Coverage |
|---|---|
| State preservation across orientation | **WIDGET** (state is Riverpod-provider-held, surviving the layout rebuild by construction; `device_class_provider_test.dart` covers re-classification on the size change); real OS rotation **INTEGRATION_TEST — pending** |

---

### 9.6 iOS release build — wellen FFI symbols survive archive stripping

#### 9.6.1 What it does

On iOS the Rust waveform engine (`libwellen_ffi.a`) is statically linked into
the Runner executable, and Dart resolves the `wellen_*` C ABI at runtime via
`DynamicLibrary.process()` + `dlsym`. Two independent mechanisms must both
hold for this to work in a **release archive** (App Store / TestFlight /
exported IPA):

1. **Link time** — the `WellenFFIKeepalive` translation unit
   (`native/wellen_ffi/Sources/WellenFFIKeepalive/wellen_ffi_keepalive.c`)
   forces ld64 to retain every `wellen_*` symbol.
2. **Archive post-processing** — the Runner target sets
   `STRIP_STYLE = "non-global"` (Release + Profile) so the archive-time
   `strip` step keeps the dlsym export trie. Xcode's default for executables
   ("All Symbols") deletes it wholesale.

**Debug builds cannot catch a regression here**: their app code lives in
`Runner.debug.dylib`, which is never stripped — so waveforms open fine in
every `flutter run` build while every TestFlight build fails with
"Failed to open waveform … Failed to lookup symbol 'wellen_open'".

#### 9.6.2 Steps

1. Build the release archive the way it actually ships (`flutter build ipa`,
   or the CI/TestFlight pipeline).
2. Install on a **physical** iPhone or iPad (TestFlight or exported IPA —
   not `flutter run --release`, which skips archive post-processing).
3. Open any VCD. Verify the waveform loads (no "Failed to lookup symbol"
   error).
4. Binary-level spot check (no device needed): run
   `xcrun dyld_info -exports <archive>/Products/Applications/Runner.app/Runner | grep -c wellen_`
   — the count must equal the FFI entry-point count (31 as of this writing),
   not 0.

#### 9.6.3 Edge cases

- A new `wellen_*` FFI entry point that is missing from
  `wellen_ffi_keepalive.c` is dead-stripped at **link** time — it fails in
  debug device builds too, but only when that specific function is first
  called. Cross-check `nm -gU` symbol counts against
  `native/wellen_ffi/wellen_ffi.h` when adding entry points.
- Regenerating/upgrading the Xcode project can silently drop `STRIP_STYLE`.

#### 9.6.4 Automation Assessment

| Test | Coverage |
|---|---|
| `STRIP_STYLE = "non-global"` present on Runner Release/Profile configs | **STATIC** (`test/static/ios_runner_strip_style_test.dart`) |
| Symbols exported from a real release archive binary | **MANUAL** (needs an archive build; the `dyld_info` one-liner above) — CI-hybrid candidate if an archive step is ever added to CI |
| Waveform open on physical device from TestFlight build | **MANUAL** |

---

## 10. Stage (built-in widgets)

### 10.1 What it does

Stage is WaveCrux's signal visualization panel — a place to bind signals to visual widgets (LEDs, switches, 7-segment displays, gauges, board diagrams) so engineers can see signal state in a domain-relevant form rather than as raw waveforms. The Open Core tier ships built-in primitive widgets (LED, switch, 7-seg, gauge, level bar, state indicator, bus readout, signal graph) plus educational FPGA board widgets (Basys 3, DE10-Lite, Nexys A7, Arty A7).

> Stage Pro (curated Pro widget pack, advanced peripheral primitives, Pro board widgets) is verified separately with the Pro overlay. The Stage panel ships drag, resize, and layout editing in open-core's runtime mode — there is no separate Pro panel designer. The open-core seams used by Pro widgets are: `StageWidget.maxSize` (resize-handle ceiling) and `StageWorkspaceNotifier.addInstanceAt` (drop-position-precise widget creation). Open-core ships defaults for both; Pro widgets reuse them unchanged.

Stage is supported on **desktop and tablet only**. A phone "instrument panel" full-screen mode is not implemented.

### 10.2 Setup

`stage/stage_demo.vcd` exercises the built-in primitives (LED, switch, 7-seg, gauge, level bar, …) in one combined file.

Each educational board widget additionally ships its own compelling **out-of-box demo** fixture under `stage/boards/<board>/`, in two flavours so both auto-bind tiers can be verified against the same animation:

| Board | Per-bit fixture (exact-match tier) | Vector fixture (fan-out tier) |
|---|---|---|
| Basys 3 | `stage/boards/basys3/basys3_demo_per_bit.vcd` | `stage/boards/basys3/basys3_demo_vector.vcd` |
| Nexys A7 | `stage/boards/nexys_a7/nexys_a7_demo_per_bit.vcd` | `stage/boards/nexys_a7/nexys_a7_demo_vector.vcd` |
| DE10-Lite | `stage/boards/de10_lite/de10_lite_demo_per_bit.vcd` | `stage/boards/de10_lite/de10_lite_demo_vector.vcd` |
| Arty A7 | `stage/boards/arty_a7/arty_a7_demo_per_bit.vcd` | `stage/boards/arty_a7/arty_a7_demo_vector.vcd` |

The **per-bit** file names every LED / switch / numeric button as an individual 1-bit signal (`led0`, `sw0`, `btn0`, …) so auto-bind resolves them through the exact / per-bit tier. The **vector** file collapses each LED / switch / numeric-button row into a single packed bus (`leds`, `sws`, `btn`, `key`) so auto-bind resolves them through the vector-fan-out tier (drop one bus → bind the whole row). Both files are driven by the same exciting, comprehensive self-test, so binding either one brings the same board to life: the LED row runs a six-pattern light show (cylon knight-rider sweep → VU bar fill/drain → theater chase → switch-register mirror → expand-from-centre → sparkle), the seven-segment display shows a **coherent decoded readout** (Basys 3: a free-running hex counter; Nexys A7: live accelerometer X/Y across its 8 digits; DE10-Lite: 3-axis accelerometer X/Y/Z across its 6 digits) with **every digit exercised across its full 0–F range** (no pinned digits), the slide switches evolve as if a user were flipping them, and the push buttons fire staggered presses. Re-generate with `dart run tool/generate_board_demo_fixtures.dart`.

### 10.3 Steps — basic stage panel

1. Load `stage/stage_demo.vcd`.
2. Open the Stage panel (toolbar/menu/command palette).
3. Add an LED widget. Bind it to a 1-bit signal. Move the cursor along the timeline. Verify the LED state updates as the signal changes.
4. Add a 7-segment display widget. Bind it to a 4-bit signal. Verify segments update correctly.
5. Add a gauge widget. Bind it to an N-bit signal. Verify the gauge needle updates with signal value.
6. Save the session. Reload. Verify the Stage panel reopens with the same widget configuration.

### 10.3.1 Steps — Stage tab strip click latency

The Stage panel's tab strip switches panels on **primary-button press**, not on release. A tab also carries a double-click-to-rename gesture, and that double-tap recognizer used to hold the gesture arena for `kDoubleTapTimeout` (~300 ms) before the tab's own tap was allowed to win — so clicking a Stage tab looked frozen, and an actual double-click renamed a panel it had never switched to.

1. Create two or more Stage panels (`+` in the tab strip).
2. Click an inactive tab. The tab highlight, the underline, and the panel body switch **on the press** — before you lift the mouse button. Hold the button down to confirm: the switch has already happened.
3. Click back and forth rapidly between two tabs. Every click lands; none is swallowed as half a double-click.
4. **Double-click a background tab.** Expected: it switches to that tab **and** opens the rename dialog, pre-filled with that tab's name. Cancel — the tab stays selected.
5. Right-click (or long-press on touch) a tab: the Rename / Remove context menu still opens, and the tab under the pointer is unchanged by the right-click.
6. Keyboard / screen-reader activation of a tab still selects it (the tab keeps its `InkWell` semantics action; only the pointer path moved to press).

Pointer-down is safe here specifically because selecting a panel is idempotent and non-destructive — there is no drag-to-cancel expectation on a tab strip. Contrast with the hierarchy tree (§4A.7), where expansion deliberately stays on release.

#### Automation Assessment

| Test | Coverage | Rationale |
|---|---|---|
| Clicking an inactive tab switches panels on the **first frame**, no clock advance | **WIDGET** (`test/features/stage/widgets/stage_panel_test.dart` — "tapping an inactive tab selects its panel") | Previously required a `pump(400 ms)`; that pump is the defect. Verified to fail against the pre-fix widget. |
| The switch happens on pointer-down, before the pointer lifts | **WIDGET** (same file — "a tab selects on pointer-down, before the pointer lifts") | Uses a held `startGesture` — the only way to distinguish press from release. |
| Double-click both selects the tab and opens rename | **WIDGET** (same file — "double-tapping a tab selects it as well as renaming it") | Guards the double-click action from being lost to the fix. |
| Rename / Remove context menu unaffected | **WIDGET** (same file — existing "tab context menu …" tests) | Already covered. |
| Screen-reader activation | **MANUAL** (step 6) | Needs a real assistive-tech host. |

### 10.4 Steps — board widgets

1. Add the **Basys 3** compound widget. Verify it renders the stylized board illustration with all primitive slots (16 LEDs, 16 slide switches, 5 push buttons, 4-digit seven-segment display).
2. Load `stage/boards/basys3/basys3_demo_per_bit.vcd` and run auto-bind. Verify every LED, switch, button, and seven-segment slot resolves (per-bit / exact-match tier). Scrub the cursor and confirm the board comes alive: the LED row runs a six-pattern light show (cylon sweep → VU bar fill/drain → theater chase → switch-register mirror → expand-from-centre → sparkle); the seven-segment display shows a coherent decoded readout — for the Basys 3 a free-running hex counter (low digits blur like a real fast counter, high digits read cleanly), counting up across all four digits; the push buttons flash staggered press pulses.
3. Load `stage/boards/basys3/basys3_demo_vector.vcd` and run auto-bind. Verify the LED and switch rows fan out from the single `leds` / `sws` buses (vector-fan-out tier) and the board animates identically to the per-bit file.
4. Verify the trademark disclaimer is reachable via the info-icon tooltip on the board widget.
5. Repeat steps 1–4 for the **Nexys A7** (8-digit seven-segment showing live accelerometer X on digits 7–4 and Y on digits 3–0, each axis tilting through its range), **DE10-Lite** (`ledr`/`hex`/`key` slot names; 6 hex digits showing 3-axis accelerometer X/Y/Z), and **Arty A7** (no seven-segment; `btn`/`key` families) board widgets, using each board's `*_demo_per_bit.vcd` and `*_demo_vector.vcd`.
6. On the Arty A7, verify the RGB LED slots render as plain LEDs (Open Core fallback) and surface the "Upgrade to Pro for full peripheral rendering" hint in the bindings pane row.

### 10.5 Steps — Add-Widget picker categorization

The Stage Add-Widget picker groups every registered widget into collapsible category sections (one `ExpansionTile` per populated `StageWidgetCategory`). Empty categories are omitted; section order is fixed by enum declaration regardless of locale.

1. Open the Stage Add-Widget picker.
2. Verify section headers appear in this order: **Primitive → Peripheral → Instrument → Board → Protocol → Custom**. Switch the app locale through en / zh-CN / ja / ko in turn — order must not change between locales, only the localized label text.
3. Verify each section header is `<Localized Name> (<count>)` via the `pickerCategoryHeader` ARB format.
4. Verify the open-core widgets group as: **Primitive** = LED, Toggle Switch, Seven-Segment, Bus Readout; **Instrument** = Level Bar, State Indicator, Signal Graph; **Board** = Basys 3, DE10-Lite, Nexys A7, Arty A7. **Peripheral**, **Protocol**, and **Custom** are empty in open core (so their sections do not render).
5. All sections start expanded — every widget is visible. Collapse and re-expand a section to verify the disclosure arrow toggles correctly.
6. Tapping a widget tile inside a category still adds the widget to the active panel (binding flow unchanged).
7. Verify each widget tile's **display name** is localized. Switch the app locale through zh-CN / ja / ko and confirm the non-board widget names render in the active language: LED (acronym, unchanged), Toggle Switch, Seven-Segment Display, Level Bar, State Indicator, Signal Graph, Bus Readout, and the Tachometer reference widget. The same localized name appears in panel instance headers and the bindings pane. **Board names are exempt** — Basys 3, DE10-Lite, Nexys A7, Arty A7 stay as their English vendor product names by design (the same reasoning that keeps board silk-screen slot labels in English).

Each definition carries an optional `displayNameKey` resolved at the render sites (picker, bindings pane, instance tile) through `stageConfigLabelResolverFactoryProvider` — the same ARB-key indirection used for decoder parameter labels (§ decoder config). When a definition has no key (board widgets, user-supplied widgets) the render site falls back to the raw English `displayName`.

### 10.6 Steps — drag sources

Both the signal tree (SST) and the signal list panel are valid Draggable<String> sources for Stage slots. Verify both:

1. Drag a leaf from the signal tree onto a Stage widget slot — binding completes.
2. Drag a row from the signal list panel onto a Stage widget slot — binding also completes, with the same SignalDragChip feedback.
3. While dragging horizontally from the signal list, the row's reorder gesture must NOT engage (per the affinity-axis rule).

### 10.6.1 Steps — trackpad scroll in the bindings inspector and signal picker

The app-wide `ScrollConfiguration` (`app.dart`, `kAppScrollDragDevices`) sets scroll `dragDevices` to Flutter's default set **minus `mouse`** — i.e. it **includes `trackpad`** (plus touch/stylus/unknown). Excluding `mouse` stops a 1-px mouse drift during a click from letting a scroll view steal the tap; mouse-wheel scroll uses `PointerScrollEvent` (a separate path) and is unaffected. Because `trackpad` is now in the app-wide default, every plain list/panel/dialog — including this bindings inspector and the signal picker — scrolls under a two-finger trackpad pan-zoom for free (see §3.1.x "app-wide trackpad scroll"). The bindings inspector and pickers still carry their own local `dragDevices` re-add for defence in depth; it is now redundant but harmless.

> **History:** an earlier revision narrowed the app-wide set to `{touch}` only, which silently dropped `trackpad` and killed two-finger scrolling in every plain list on macOS/iPad (only the scrollbar and mouse wheel worked). `kAppScrollDragDevices` restored it; `kTrackpadOwnedDragDevices` is the opt-out set used by the three widgets that own their own trackpad gesture (waveform canvas, signal-list names column, command palette) so the native scrollable does not double-drive them.

1. Select a widget with a tall configuration section (e.g. the Tachometer — Signal Bindings + the RPM-range / zones config groups). On a laptop **trackpad**, two-finger-scroll the right-hand inspector pane and confirm it scrolls down to the lower config knobs (e.g. `maxRpm`). Confirm the mouse wheel scrolls it too.
2. Tap a binding row's signal field to open the **signal binding picker**. With more signals than fit, two-finger-scroll the list on a trackpad and confirm it scrolls (not just the mouse wheel).
3. Confirm a single-finger tap on a config control or a signal row still registers as a tap (re-adding trackpad must not have re-introduced mouse-drag tap-stealing — mouse is intentionally excluded from `dragDevices`).

### 10.7 Steps — device gating

1. On phone, verify there is no Stage option in the UI.
2. On tablet (or desktop window resized to tablet width), verify Stage is available, docked as a bottom panel.
3. On desktop, verify Stage works as a regular pane.

### 10.8 Edge cases

- Bind a widget to a signal that doesn't exist — the pin resolves to an **error** snapshot (`StageSignalSnapshotKind.error`), not a perpetual "loading" spinner, and the app does NOT crash. (The lazy load fails inside `StageLoadedSignals.ensureLoaded`; the failure is caught and settled as an error rather than escaping as an uncaught async error.)
- Remove a widget — Stage panel updates correctly.
- Load a session whose Stage references signals not in the current file — graceful fallback.
- A category whose widgets are all unregistered does not render an empty `ExpansionTile` in the picker.

### 10.9 Automation Assessment

| Test | Coverage |
|---|---|
| Each built-in primitive responds to cursor movement | **WIDGET** (`test/features/stage/widgets/primitives/`) |
| Each board widget renders all slots and binds correctly | **WIDGET** (`test/features/stage/widgets/boards/`) |
| Per-board demo fixtures parse and auto-bind via both tiers (per-bit exact-match + vector fan-out) | **INTEGRATION** (`test/fixtures/stage/boards/board_demo_fixtures_test.dart` — all 4 boards × per-bit + vector) |
| Trademark disclaimer surfaced via info-icon | **WIDGET** (board widget tests assert tooltip presence) |
| Add-Widget picker section ordering matches `StageWidgetCategory.values` regardless of locale | **WIDGET** (`test/features/stage/widgets/stage_widget_picker_dialog_section_ordering_test.dart` — populated-set ordering en/zh/ja/ko + full-set ordering test simulating Stage Pro shipped state) |
| Each open-core widget lands in the expected category | **WIDGET** (`test/features/stage/widgets/stage_widget_renderer_registry_test.dart`) |
| Every non-board built-in widget declares a `displayNameKey` (drift guard) and every key resolves to a localized, non-raw string | **WIDGET/UNIT** (`test/features/stage/widgets/stage_widget_display_name_localization_test.dart` — has-key guard exempting board category + resolver locale sweep en/zh_CN/ja/ko) |
| Picker omits empty categories | **WIDGET** (`stage_widget_picker_dialog_section_ordering_test.dart` — regression guard against unpopulated categories rendering) |
| Signal-drag from tree AND from signal list both work | **WIDGET** (`test/features/stage/widgets/stage_instance_tile_test.dart` + `stage_bindings_pane_test.dart` cover the binding side; `test/features/viewer/widgets/signal_list_panel_test.dart` covers the source side) |
| Bindings inspector + signal binding picker re-enable trackpad scroll (`dragDevices` includes trackpad+touch) | **WIDGET** (`stage_bindings_pane_test.dart` — "trackpad scroll" group; `signal_binding_picker_dialog_test.dart` — "re-enables trackpad two-finger scroll"). The single-finger-tap-still-taps and real trackpad-feel check stays **MANUAL**. |
| Reorder vs drag affinity-axis split | **WIDGET** (`signal_list_panel_test.dart` — axis-affinity test) |
| Binding to a missing/invalid signal settles to an error snapshot without throwing an uncaught async error | **UNIT** (`test/features/stage/providers/stage_signal_provider_test.dart` — "failed load is contained, not thrown" group; `test/domain/models/stage_signal_snapshot_test.dart` — error kind) |
| Session save/restore round-trip | **WIDGET** (`test/services/session/session_service_test.dart`) |
| Device gating (hidden on phone) | **WIDGET** (`test/features/stage/widgets/stage_panel_test.dart` + `test/shared/layouts/device_class_provider_test.dart`) |
| RGB LED Pro-upgrade hint surfaced on Arty A7 | **WIDGET** (Arty A7 widget test with the `__rgb_pro_upgrade_hint__` sentinel resolution) |
| Visual widget rendering | **MANUAL** (or golden image — golden infra not yet set up) |

### 10.10 Tachometer Rive reference widget + per-instance config

**What it does.** The open-core **Tachometer** (`StageWidgetCategory.instrument`, `requiredTier: openCore`, no PRO badge) is the canonical Rive-backed reference widget that exercises the full custom-widget runtime: the bundled `assets/stage/widgets/rive/runtime/tachometer.riv` artboard carries a state machine named `Tachometer` with three named inputs — `rpm` (Number), `redline` (Boolean), `shift` (Boolean) — matching `manifest.yaml`'s `signal_bindings` verbatim. The renderer normalizes the bound `rpm` signal from the per-instance `[minRpm, maxRpm]` range to 0.0–1.0 and drives a 1D blend state that sweeps the needle. The artboard is fully styled (dark face + bezel, tick ring, redline arc, orange needle + hub) and **all three inputs are visually wired**: `redline` fades a glow over the redline arc (state-machine Layer 2), and `shift` fires a one-shot amber rim flash on each rising edge (Layer 3). Binding a 1-bit `redline`/`shift` signal that toggles over the trace shows the glow track its level and the flash pop on its edges while the needle sweeps independently.

**Setup.** Load `stage/stage_demo.vcd`. Bind `rpm` → `level_ramp` (8-bit ramp 0–255), `redline` → `toggle_a`, `shift` → `toggle_b`. All three required pins must be bound or the renderer shows the localized "unbound" placeholder.

**Steps.**
1. Add the Tachometer, bind the three pins, scrub the cursor. With the default range (0–8000) the needle barely moves (ramp peaks at 255 ≈ 3% of 8000) — expected.
2. **Range knob (regression — config #1).** In the config pane set **Max RPM = 200**, leaving Warning/Redline at their defaults (6500 / 7500). Scrub again: the needle now sweeps the full arc. The fix is that lowering Max RPM below the default zone thresholds **keeps** Max RPM — the decorative `warningRpm` / `redlineRpm` zones clamp into `[minRpm, maxRpm]` instead of `fromMap` discarding the whole config back to 8000 (the pre-fix behavior made the range knob appear inert).
3. **Field commit on blur (regression — config #3).** Type a value into Min/Max/Warning/Redline RPM and **tab or click into another field without pressing Enter**. The value must commit (the gauge re-normalizes). Pre-fix, only Enter committed, so tab/click-away silently discarded the edit.
4. **Bindings show the signal path (regression — bindings #2).** Each bound row must display the signal's hierarchical path (e.g. `top.level_ramp`), not wellen's opaque `signalRef` handle (a bare number like `10`).

**Cross-build asset resolution.** The curated `manifest.yaml` + `tachometer.riv` are declared in open-core's `pubspec.yaml`. In the **open-core** build they resolve at the bare `assets/...` key; in the **Pro overlay** build (where `wavecrux` is a path dependency) the same bytes live under `packages/wavecrux/assets/...`. The renderer loads through `loadBundledStageAssetBytes` / `loadBundledStageAssetString`, which try the bare key then fall back to the `packages/wavecrux/` key — so the gauge renders in **both** builds. **Verify the Tachometer renders (not the "Widget failed to load" placeholder) when running the Pro app**, not just open-core.

**Edge cases.**
- Degenerate range (`minRpm >= maxRpm`) falls the *range* back to the 0–8000 default (no needle mapping exists for an inverted range); the zones then clamp into that range.
- A session bound against a signal absent from the loaded file shows the raw `signalRef` in the bindings row rather than an empty cell.

**Automation Assessment.**

| Test | Coverage |
|---|---|
| `fromMap` clamps zones into range / keeps lowered maxRpm / handles degenerate range | **UNIT** (`test/features/stage/widgets/tachometer/domain/tachometer_config_test.dart`) |
| Numeric config field commits on focus loss (tab/blur), not just Enter | **WIDGET** (`test/features/stage/widgets/stage_widget_config_editor_test.dart`) |
| Bindings row resolves opaque `signalRef` → `Variable.fullPath`, falls back to raw ref when unloaded | **WIDGET** (`test/features/stage/widgets/stage_bindings_pane_test.dart`) |
| Bundled asset resolves via bare key (open-core) and `packages/wavecrux/` fallback (Pro) | **UNIT** (`test/features/stage/runtime/bundled_stage_asset_loader_test.dart`) |
| `.riv` loads + needle sweeps with bound signal (both open-core and Pro builds) | **MANUAL** (live-scrub feel) + **INTEGRATION_TEST** — landed: `integration_test/stage/tachometer_rive_test.dart` (type routing, renderer full-Rive smoke, locale sweep of the placeholder paths, tablet/phone surface metrics) and `integration_test/stage/tachometer_golden_test.dart` (12 needle/redline golden baselines). `rive_native` is unavailable headless (`RiveNative.init` cannot resolve its FFI symbol in `flutter test`), so the former `tachometer_stage_renderer_test.dart` mount tests were permanently skipped there; that file is deleted and its coverage lives entirely in the integration target now. |

---

### 10.11 Community custom-widget live rendering (`.wcrux-widget` render bridge)

**What it does.** A *community* `.wcrux-widget` bundle is a manifest + `.riv` with **no bundled Dart**. Anyone can author one through the open-core SDK, package it, install it via **Settings → Custom Widgets** (or a watched directory), and it now **renders and animates live** when dropped on a Stage panel — the same as the curated Tachometer, but driven entirely by the generic runtime with no widget-specific code in the path. This closes the gap where a community bundle could be authored, installed, listed in the picker, and bound to signals, yet its artboard never painted.

Three pieces make it work, all open-core:

- `CommunityRiveStageRenderer` decodes the bundle's extracted `.riv` bytes (from the filesystem, via `decodeRiveFileForStageWidget` — the bytes counterpart of the curated asset loader), mounts the artboard's **default** state machine (the manifest has no state-machine-name field — the author may name it anything), and drives its inputs per frame from the manifest's `signal_bindings` + normalizer `parameters` via `GenericManifestInputMapper`.
- `CustomWidgetBundleManager` now registers, for every loaded Rive bundle, both the widget **definition** (into `StageRegistry`, so `StageInstanceTile` resolves it) and the **renderer** (into `StageWidgetRendererRegistry`) — symmetric with the Pro pack's `extraStageWidgetsProvider` path, and unregistered on bundle removal / replacement / watched-directory removal. (The existing `CustomStageWidgetRegistry` descriptor registration remains the tier-gated picker source.)
- The manifest-vs-host validator (`validateManifestAgainstHost`) fails closed: a required binding whose name the state machine does not expose surfaces the localized "Widget failed to load" placeholder instead of crashing.

**Setup.** Use the committed fixture `test/fixtures/stage/community_widget/community_gauge.wcrux-widget` (regenerate via `dart run tool/generate_community_widget_fixture.dart`). It is a community bundle (id `com.wavecrux.test.community_gauge`) that reuses the authored Tachometer artboard — whose default state machine exposes `rpm` (Number), `redline` (Boolean), `shift` (Boolean) — with manifest bindings of the same names and a linear normalizer on `rpm`. Load `stage/stage_demo.vcd` for signals.

**Steps.**
1. Settings → Custom Widgets → **Load widget bundle…** → pick `community_gauge.wcrux-widget`. It appears with no load error.
2. Open a Stage panel, add **Community Gauge** from the picker. The tile shows the localized "Bind …" placeholder (required pins unbound), **not** "Unknown widget".
3. Bind `rpm` → `level_ramp`, `redline` → `toggle_a`, `shift` → `toggle_b`. Scrub the cursor: the artboard animates live (needle sweeps as `rpm` changes) — proving default-state-machine resolution + manifest-driven input routing with no Tachometer-specific code.
4. Remove the bundle (Settings → Custom Widgets → Remove). The picker entry disappears and any live instance reverts to the "Unknown widget" tile — confirming symmetric definition + renderer unregistration.

**Survives session reload.** With a Community Gauge instance on a Stage panel, save the session (or rely on the auto-managed workspace), **fully quit and relaunch the app**, and reopen the session. The instance must come back as the live gauge — **not** a stuck "Unknown widget" tile — **without** first visiting Settings. The bundle manager is initialised eagerly at startup (alongside built-ins and the Pro pack), and the Stage tile shows a brief spinner then resolves once the async load completes (it watches the manager rather than resolving once). Regression guard: previously the manager loaded only when Settings → Custom Widgets was opened, so a restored community-widget instance showed "Unknown widget" until then.

**Open-core, reachable.** The whole capability is free open-core. The **Settings → Custom Widgets** panel (load + watched-directory management) is **ungated** — available to every tier, with **no PRO badge** on the section header — and a loaded community bundle registers at `openCore` tier, so **Community Gauge carries no PRO chip** in the picker. (Only the curated Pro *pack* content is Pro.) Verify during beta that no `FeatureTierBadge` appears on the Settings section or the community picker entry. The panel had no Settings entry point before this work — confirm it is now listed in the Settings rail (between "CXP Cross-Probe" and "Keyboard Shortcuts").

**Misnamed-input / failure path.** Author (or hand-edit) a bundle whose manifest declares a required binding the artboard's default state machine does **not** expose (e.g. rename a binding to `rpm_typo`). Dropping it surfaces the localized "Widget failed to load" placeholder with the diagnostic in the info-icon tooltip — **no crash**. An empty / malformed `.riv` surfaces the same placeholder.

**Edge cases.**
- Painter-runtime community bundles register a definition (so the tile shows the description text) but no renderer — there is no community painter runtime.
- A bundle declaring the same widget id as a curated/Pro widget: last-loaded wins for the renderer slot, mirroring registry replace semantics.
- Optional (`required: false`) bindings left unbound do not block rendering; their Rive inputs hold the artboard authoring default.

**Automation Assessment.**

| Test | Coverage |
|---|---|
| Manifest → generic input mapping (missing-required detection, normalizer resolution, default normalize, hold-stale) | **UNIT** (`test/features/stage/runtime/generic_manifest_input_mapper_test.dart`) |
| Bundle manager registers definition + renderer for a Rive bundle and clears both on removal; painter bundle registers definition only | **UNIT** (`test/features/stage/bundle/custom_widget_bundle_manager_test.dart`) |
| Empty `.riv` bytes → localized "Widget failed to load" placeholder across locales | **WIDGET** (`test/features/stage/runtime/community_rive_stage_renderer_test.dart`) |
| `StageRegistry` / `StageWidgetRendererRegistry` `unregister` | **UNIT** (`test/plugins/stage_registry_test.dart`, `test/features/stage/widgets/stage_widget_renderer_registry_test.dart`) |
| Committed community fixture bundle loads + parses | **UNIT** (`test/fixtures/stage/community_widget/community_gauge_fixture_test.dart`) |
| Custom Widgets panel reachable from the Settings rail (open-core entry point) | **WIDGET** (`test/features/settings/screens/settings_screen_test.dart` — "rail lists the platform-independent categories") |
| Community descriptor registers at `openCore` tier (no PRO badge); panel ungated (no FeatureGate) | **UNIT** (`test/features/stage/bundle/picker_integration_test.dart`) + **WIDGET** (`test/features/stage/settings/custom_widgets_panel_test.dart` — "panel is open-core") |
| Unresolved community-widget tile shows a spinner (not "Unknown widget") while the manager is loading, then re-resolves | **WIDGET** (`test/features/stage/widgets/stage_instance_tile_test.dart` — "spinner … while the custom-widget manager is still loading") + **MANUAL** (full quit/relaunch session-reload check) |
| Live artboard mounts + animates from bound signals; misnamed input → placeholder | **MANUAL** + **INTEGRATION_TEST — pending** (rive_native unavailable headless; `RiveNative.init` cannot resolve its FFI symbol in `flutter test`, so renderer-mount tests are skipped there and belong in an `integration_test/` target) |

---

## 10A. Stage Playback (animated playhead)

### 10A.1 What it does

Stage Playback adds a **play button that auto-advances the primary cursor** so
signal-bound Stage widgets animate on their own — a motor spins, a gauge sweeps,
a framebuffer/LCD/OLED updates — without the user manually scrubbing. It is an
**Open Core** capability (no tier badge, no feature gate). The playback *engine*
lives at the cursor layer (`features/cursors/providers/playback_provider.dart`)
and simply advances `cursorStateProvider.primaryCursorTime` on a `Ticker`;
everything bound to the cursor re-renders for free. Only the **transport UI**
(docked in the Stage panel) and the **Space shortcut** are gated on Stage panel
visibility.

The transport row offers: **Play/Pause**, **Stop** (returns the cursor to the
start of the range), a **Speed** selector (duration presets 5 s / 10 s / 30 s to
play the whole active range in that many wall-clock seconds — file-independent,
no timescale needed), a **Loop** selector (No loop / Loop range / Loop A–B), and
a **Follow playhead** toggle (recentres the viewport when the playhead scrolls
off-screen). Power mode (advance a fixed amount of *sim time* per wall second)
is implemented in the engine and unit-tested, but is **not** surfaced in the
transport UI in this phase — the UI exposes only the duration presets.

### 10A.2 Setup

1. Load any multi-signal trace (`stage/stage_demo.vcd` or a board demo).
2. Open the Stage panel (toolbar / View menu / command palette / `Cmd/Ctrl+Shift+G`).
3. Add a widget and bind a signal that changes over time (e.g. a Signal Graph,
   a Seven-Segment, or a board LED bound to a counter bit).

### 10A.3 Steps — play / pause / stop

1. Press **Play** (transport button, the toolbar play icon, the View-menu
   *Play / Pause Stage Playback* entry, or the **Space** key). The bound widget
   begins animating as the primary cursor sweeps left-to-right.
2. Press **Pause** — the cursor stops where it is; the widget freezes on that
   value. Press Play again — it resumes from there.
3. Press **Stop** — the cursor jumps back to the start of the active range and
   playback halts.
4. Default speed plays the whole range in ~10 s. Switch to **5 s** / **30 s** and
   confirm the sweep speeds up / slows down proportionally. The same preset
   completes in the same wall-clock time on a picosecond-scale and a
   second-scale trace (file-independent).

### 10A.4 Steps — loop and follow

1. Set **Loop → Loop range** and press Play: at the end of the range the cursor
   wraps to the start and keeps playing (the widget animates continuously).
2. Place a **secondary cursor** (delta cursor). The **Loop A–B** entry now
   appears. Select it and play: the cursor loops only between the two cursors.
   Remove the secondary cursor and re-play — it falls back to whole-range.
3. Zoom in so the range is wider than the viewport. With **Follow playhead** on,
   the viewport recentres as the playhead leaves the visible window. Turn it off
   — the viewport stays put and the playhead scrolls out of view.

### 10A.5 Steps — tier-gate / surface gating

This is an Open Core feature, so there is **no** license-tier gate. The gating
that exists is **Stage-visibility** gating of the transport and shortcut:

1. With the Stage panel **hidden**, the **Space** key does nothing (it does not
   start playback and does not type), the toolbar play button is **greyed out**,
   and the command-palette / menu *Play / Pause Stage Playback* entry is
   **disabled** (greyed in the menu, omitted from the palette).
2. Open the Stage panel — the transport appears, the Space key starts playback,
   the toolbar button enables, and the menu/palette entry enables.
3. On **phone**, Stage (and therefore playback) is not available at all.

### 10A.6 Edge cases

- **Empty Stage**: open the Stage panel with no widgets bound. The transport
  still renders, with a hint ("Bind a signal to a Stage widget to see it
  animate…") — the controls are not hidden.
- **Empty / single-tick trace**: Play is a no-op (the engine bails when the
  range is degenerate); nothing animates and the app does not crash.
- **No file**: with Stage open but no file loaded, the play action is disabled.
- **A–B with no secondary cursor**: selecting Loop A–B then playing falls back to
  whole-range looping rather than failing.
- **Re-press Play at the end** (No loop): after the cursor stops at the end,
  pressing Play restarts from the beginning of the range.

### 10A.7 Automation Assessment

| Test | Coverage |
|---|---|
| `PlaybackState` / `PlaybackSpeed` equality, copyWith, defaults | **UNIT** (`test/domain/models/playback_state_test.dart`) |
| `advanceBy` moves the cursor proportional to speed; clamps at bounds | **UNIT** (`test/features/cursors/providers/playback_provider_test.dart`) |
| Stop-at-end (No loop) pins the cursor at the end and clears `isPlaying` | **UNIT** (same) |
| Loop wrap (whole-range) and A–B loop (incl. fallback when no secondary) | **UNIT** (same) |
| Duration speed is file-independent (ps- vs second-scale range) | **UNIT** (same) |
| Power mode uses the trace timescale; falls back when none | **UNIT** (same) |
| Re-press Play at the end restarts from the range start | **UNIT** (same) |
| Viewport follow recentres only when the playhead leaves the window | **UNIT** (same — spy navigation) |
| A bound Stage signal re-samples the new cursor value under simulated advance | **UNIT** (same — proves the reactive chain, no Stage widget code change) |
| `togglePlayback` enabled only when a file is loaded AND Stage is visible | **UNIT** (`test/core/shortcuts/action_descriptors_test.dart`) |
| Space default binding present and collision-free | **UNIT** (`test/core/shortcuts/shortcut_bindings_test.dart`) |
| Transport renders, buttons call the right notifier methods, 44×44 touch targets, empty-Stage hint, locale sweep en/zh/ja/ko | **WIDGET** (`test/features/stage/widgets/stage_playback_transport_test.dart`) |
| Animated-playhead visual feel (smoothness, motor-spin perception) | **MANUAL** |

---

## 10B. RISC-V Core Designer widgets (Open Core)

### 10B.0 What this family is, and why it is free

A family of Stage widgets that turn a VCD/FST of an **RVFI-instrumented**
RISC-V core into the views a core designer actually works from — *did it
retire, with what result, is the architectural state correct*. It sits one
step past the existing RISC-V **decoder** (§5.7), which answers *what was
fetched*.

Two of the family's six widgets ship in **Open Core** by a deliberate,
recorded exception to the "curated widget content is Pro" rule. The tier line is *correctness is free, productivity is paid*: the
open-core build must answer "is my core correct?" end to end with **no
license, no crippled mode, no time limit**. When verifying this family, treat
the following as failures, not cosmetics:

- any row cap, watermark, or in-view "Pro" nag;
- a tier badge on `riscv_commit` or `pipeline` in the Add-Widget picker;
- the consistency checker being gated, degraded, or partially disabled;
- either widget presenting a reconstruction it cannot stand behind as fact.

**Fixtures.** Everything below runs against the committed generated fixtures
in `verification/fixtures/protocol/riscv/generated/` — the clean
`riscv_rvfi_retire.vcd` plus one deliberately corrupted variant per checker
rule, and the `riscv_pipeline_5stage` / `riscv_pipeline_defeat` pair.
Regenerate with `dart run tool/generate_riscv_fixtures.dart`; the generator
cross-checks every expected disassembly against the real disassembler, and
cross-checks the pipeline grid against a hand-drawn ASCII diagram, refusing to
write a wrong fixture either way.

**One piece of vocabulary here is deliberately unreachable from an open-core
build.** `RiscvIdentityWarningKind.ambiguousTag` — "the same instruction tag
was valid in two places in one cycle" — is declared alongside the other
warning kinds because the warning vocabulary belongs to the identity *model*,
which lives in open core, rather than to whichever build implements a given
source. It is the tag counterpart of `ambiguousPc`, and only the Pro `tag`
tracker can raise it: open core has no tag tracker and never reads the tag
field, so a warning about a signal this build cannot see would be a lie about
what it knows. `riscv_instruction_identity_test.dart` pins that against an
observation built specifically to provoke one (`[Coverage: UNIT]`). **If a
future open-core tracker starts emitting it, that is a tier-line question,
not a test to update.**

### 10B.1 RVFI Commit Inspector (`riscv_commit`)

#### 10B.1.1 What it does

Reconstructs the retire stream from the riscv-formal `rvfi_*` bundle and
presents five views over it — **Commits**, **Registers**, **Memory**,
**Traps**, **Checks** — plus a six-rule consistency checker whose violations
render inline and move the cursor when clicked.

#### 10B.1.2 Setup

1. Open `verification/fixtures/protocol/riscv/generated/riscv_rvfi_retire.vcd`.
2. Open the Stage panel (`Cmd/Ctrl+Shift+G`).
3. **Add Widget → Instrument → RVFI Commit Inspector.** Confirm it appears
   with **no tier badge** — it is open core.
4. Select the instance. In the bindings pane, press **Auto-bind**
   (wand icon).

#### 10B.1.3 Steps — auto-bind

1. The preview dialog opens titled **"Auto-bind RVFI channels"** — *not*
   "Auto-bind board signals". A board-flavoured title here is a defect.
2. All 21 `rvfi_*` pins are listed with a confidence chip; the fixture nests
   the bundle under `tb.core`, so they resolve as **Alias** (hierarchy-
   prefixed) rather than Exact.
3. Press **Apply all**. The header line reads **"21 of 21 RVFI channels
   bound"** and no reduced-binding banner appears.
4. Re-run Auto-bind. Already-bound pins come back as `manually bound` and are
   not overwritten.

#### 10B.1.4 Steps — the four views

Drag the cursor to the end of the trace first.

1. **Commits.** Eight rows, order 0–7, each with its PC, its disassembly
   (`addi t0, zero, 5`, `add t2, t0, t1`, `sw t2, 0(sp)`, `lw s0, 0(sp)`,
   `beq t0, t0, 16`, `ecall`), and its **real** architectural effect —
   `t0 = 0x0000_0005`, `[0x0000_1000] ← 0x0000_000c`. Register names are ABI
   mnemonics.
   - Click any row: the primary cursor jumps to that retirement's tick and
     the status bar time changes.
   - The `addi zero, zero, 0` row shows **no** register effect — `rd_addr` 0
     means "writes nothing", not "writes zero".
2. **Registers.** The reconstructed architectural file at the cursor:
   `t0 = 0x0000_0005`, `t1 = 0x0000_0007`, `t2 = 0x0000_000c`,
   `s0 = 0x0000_000c`, and **Architectural PC** above them. Every register
   the trace never wrote reads `—`, never `0x0000_0000` — hover for the
   tooltip explaining that "unknown" and "zero" are different statements.
   Scrub backwards: the file rebuilds correctly (stateless replay, backward
   seek is just another build).
3. **Memory.** Two entries — a 4-byte **write** of `0x0000_000c` to
   `0x0000_1000` and a 4-byte **read** of the same word back. Clicking either
   moves the cursor.
4. **Traps.** One entry — **Trap** at `0x8000_0028`, **privilege M**.
5. **Checks.** *"8 retirements checked, no inconsistency found."* No error
   badge on the Checks tab.

#### 10B.1.5 Steps — the consistency checker (the point of the widget)

Load each corrupted fixture in turn, auto-bind, and confirm the paired
behaviour. Each fixture retires the same legal program as the clean one and
corrupts exactly one thing the core *claims* about it, so **exactly one rule
must fire and no other**.

| Fixture | Rule that must fire | Message you should see |
|---|---|---|
| `riscv_rvfi_bad_pc_wdata.vcd` | Control-flow continuity | *"retirement #2 set rvfi_pc_wdata to 0x8000_0030, but this retirement fetched from 0x8000_000c."* |
| `riscv_rvfi_bad_x0_write.vcd` | Writes to x0 | *"rvfi_rd_addr is 0 (x0) with rvfi_rd_wdata 0x0000_002a. x0 is hardwired zero…"* |
| `riscv_rvfi_bad_rd_addr.vcd` | Destination register | *"addi encodes rd = t0 (x5), but rvfi_rd_addr reports t1 (x6)."* |
| `riscv_rvfi_bad_mem_mask.vcd` | Memory access | *"sw accesses 4 bytes, but the rvfi_mem byte masks cover 2."* |
| `riscv_rvfi_bad_order.vcd` | Retirement order | *"rvfi_order jumped from 3 to 6 — 2 retirement(s) are missing from the trace."* |
| `riscv_rvfi_bad_trap.vcd` | Trap consistency | *"rvfi_trap is set at 0x8000_0028, but rvfi_pc_wdata is 0x8000_002c — the sequential next PC, not a trap vector."* |

For each one:

1. The **Checks** tab shows an error count badge, and the summary line reads
   *"1 errors, 0 warnings over 8 retirements"*.
2. The message is **specific** — it names the actual values that disagree.
   A generic "inconsistency detected" is a defect.
3. Clicking the violation moves the primary cursor to the offending
   retirement.
4. Switch to **Commits**: the same violation is rendered **inline**, on the
   offending row, in the error colour.
5. No *other* rule fires. (The automated pairing test asserts this
   mechanically; spot-check one fixture by eye.)

**Warning vs error.** Misalignment is reported as a **Warning**, not an
error — RISC-V permits misaligned accesses and cores differ. There is no
corrupted fixture for it; exercise it by hand-binding a core whose loads are
unaligned, or trust the unit coverage.

#### 10B.1.6 Steps — the reduced binding set (degrade, do not refuse)

1. Reload the clean fixture. Bind **only** `rvfi_valid`, `rvfi_insn`,
   `rvfi_pc_rdata`, `rvfi_rd_addr`, `rvfi_rd_wdata` (clear the rest).
2. The widget **still renders**. The header shows *"5 of 21 RVFI channels
   bound"* and a banner names every missing channel by its Verilog port name
   (`rvfi_mem_addr, rvfi_mem_rmask, …`) — port names are deliberately **not**
   translated, so the banner works as a checklist against your RTL.
3. **Commits** still lists retirements with disassembly and register writes.
   Fewer rows than before: without `rvfi_order`, back-to-back retirements
   held under one `valid` pulse collapse — that is the honest consequence,
   not a bug.
4. **Registers** still reconstructs. **Memory** and **Traps** say which
   channels to bind rather than showing an empty list.
5. **Checks** says *"Not checked, because the channels they need are
   unbound: Control-flow continuity, Memory access, Retirement order, Trap
   consistency"*. **This line is the important one** — a quiet result from a
   check that never ran is the only way this widget could actively mislead
   someone.
6. Now clear `rvfi_pc_rdata` too. The widget states *"Bind rvfi_pc_rdata —
   without them no retirement can be reconstructed."* rather than rendering
   an empty panel.

#### 10B.1.7 Steps — configuration

1. Bindings pane → Configuration → **Register names** → *Numeric (x10, x2,
   x1)*. Commit effects and the register grid switch to `x5`, `x6`, … ABI is
   the default.
2. **Architectural registers** → 16 (RV32E). The register grid shows 16
   cells.
3. **Memory log depth** → 4. The Memory view keeps only the most recent four
   accesses.
4. Save the session, reload it: all three settings and all 21 bindings
   restore.

#### 10B.1.8 Edge cases

- **No file loaded** with the widget on the Stage → *"No waveform loaded"*,
  no crash.
- **Bindings to a signal that is not in the current trace** (open a
  different VCD without rebinding) → the widget reports missing required
  channels; it does not spin on a loading state and does not throw.
- **A trace with `rvfi_*` names but no retirement** (`rvfi_valid` never
  asserts) → *"No retirement observed in this trace."*
- **Signals never added to the viewer.** Bind the RVFI bundle *without*
  adding any of those signals to the waveform panel. The widget must still
  populate — Stage bindings lazily load their own signal data. An empty
  inspector here is the classic lazy-load defect (ARCHITECTURE §6.6, rule 1),
  not a bad trace.
- **Resize to the minimum (320 × 220).** The view selector scrolls
  horizontally rather than overflowing; rows ellipsize.
- **Locale sweep** en / zh-CN / zh / ja / ko: every tab label, empty state,
  banner and violation message is translated. The `rvfi_*` port names and the
  hex values are not, by design.

#### 10B.1.9 Cross-probe landing — the CXP semantic stream coordinate

**What it does.** A sibling app can point WaveCrux not just at a trace but at
one *element inside* it: SimCrux's "Debug in WaveCrux" on a **failing bounded
proof** sends `request_highlight(source=trace.vcd)` carrying a [CXP §9.9](https://edacrux.app/cxp#sec-9-9)
`coordinate` — `stream_id: riscv.formal.trace_step`, `sequence_index` = the
step `sby` reported, `sub_id` = the RVFI channel. WaveCrux opens the trace,
converts that step onto the trace's own step grid, moves the primary cursor to
it, and — because the Commit Inspector's history views are cursor-scoped — the
retirement at that step becomes the current row in all five views. A banner
above the channel count says where it landed and why.

Open core end to end. There is **no tier gate anywhere on this path**; a badge,
a nag, or a licence check appearing here is a tier-line regression — a
counterexample hand-off answers whether a core is correct, which is never gated.

**Setup.** Run a riscv-formal check in SimCrux that fails (the committed demo
fixtures replay one offline), then press **Debug in WaveCrux** on the failing
row.

**Step-by-step expected behavior**

1. The counterexample VCD opens in a new WaveCrux tab.
2. The primary cursor lands on the failing step — **not** at time zero.
3. **A Stage panel named "RVFI Commit (cross-probe)" is already there**, holding
   an RVFI Commit Inspector bound to all 21 channels, with the bottom dock open
   on it. You did not add it; the hand-off did, because a freshly opened tab has
   no Stage panel and the landing would otherwise be invisible. A tab you had
   *already* arranged is never rearranged this way — see the edge cases.
4. A **Cross-probed landing** banner appears above the "N of 21 RVFI channels
   bound" line, reading e.g.
   `insn_sub_ch0 · insn · step 7 of 20 · rvfi_order 5 · rv32i`, and — because
   the panel was auto-mounted — the line *"This Stage panel was opened by the
   incoming cross-probe and bound to the trace's RVFI channels."*
5. The Commits view shows that retirement as the current (highlighted) row,
   **scrolled into view and visible without resizing anything**. The
   counterexample's violating retirement is usually the last of several, and
   "the row exists somewhere below the fold" is not a landing — if you have to
   drag the panel bigger or scroll the log to find the instruction the jump was
   about, that is the defect this step exists to catch. Registers folds to it;
   Memory and Traps are scoped to it.
6. The panel is mounted large enough to show five or six commit rows, and the
   bottom dock is opened to at least 480 px if it was shorter — so the landed
   row has some of its own history above it for context. A dock you had already
   made **taller** keeps its height.
7. Dismissing the banner (×) hides the caption and **leaves the cursor where
   it is** — it is not an undo. The panel stays; **one** Ctrl/Cmd+Z removes the
   whole mount (panel, widget and bindings are a single undo step).
8. **Nothing is added to the waveform canvas** by the coordinate. Whatever lanes
   appear come from the sender's own `notify_selection` hint; twenty-one raw
   `rvfi_*` lanes would bury the payload rather than be it.

**Edge cases — every one of these must degrade, never fail**

- **A replayed demo fixture.** When the sender marks the coordinate
  `riscv.mode = demo`, the banner adds *"Replayed demo fixture, not a measured
  solver run."* **A landing that reports a check and a step without that line
  when the run was replayed is a defect, not a cosmetic miss** — it lets a
  screenshot of a rehearsed demo read as a measured result, which is the one
  claim this whole family refuses to make.
- **No retirement at the addressed step.** The cursor still moves there, the
  banner says *"No instruction retired at this step…"*, and **no** `rvfi_order`
  is claimed. The inspector is still mounted — the step resolved.
- **The trace was already open, and you had arranged that tab.** Cross-probe the
  same counterexample a second time (or open it by hand first, arrange it, then
  cross-probe). The cursor moves to the step and **nothing about the layout
  changes**: no new Stage panel, no dock opening, no second inspector, and the
  banner does **not** claim a panel was mounted. Rearranging a tab the user set
  up is a defect, not a convenience.
- **A trace with no RVFI bundle**, or one whose RVFI activity is not on a
  uniform lattice (an ordinary simulation dump rather than a `sby`
  counterexample): the file still opens and the signal still highlights; the
  coordinate is declined and SimCrux's toast says why. Landing at the top of
  the right trace beats refusing it.
- **A stream WaveCrux does not implement** (a future AXI / Ethernet / USB /
  video binding): identical behaviour — element honoured, reason returned, **no
  error surfaced anywhere**. Tolerating an unknown `stream_id` is required by
  [CXP §9.9.1](https://edacrux.app/cxp#sec-9-9-1), not optional politeness.
- **A different file opened in the same tab** clears the banner. A landing is a
  statement about one trace.
- **Locale sweep** en / zh-CN / zh / ja / ko across the banner. The producer's
  own tokens — the check name, the group, the ISA string — are reported
  verbatim and are deliberately not translated, like the `rvfi_*` port names.

#### 10B.1.10 The captured Ibex trace — the substrate against RTL we did not write

Every fixture in §10B.1.5 is produced by `tool/generate_riscv_fixtures.dart`.
That makes them exact regression locks and **no evidence whatsoever** that the
substrate works on a real core: we chose the signal names, the hierarchy
depth, the channel widths and the retirement timing, so of course detection
finds them.

`riscv_ibex_rvfi_trap.fst` is the counterweight — a Verilator capture of
lowRISC's Ibex (Apache-2.0, commit `3250d994`) with `+define+RVFI`, running a
hand-assembled 26-instruction RV32I program through arithmetic, word/byte/
halfword load-store pairs, a forward `beq`, a backward `bne` loop and an
`ecall` that traps. 1841 bytes committed. Rebuild recipe and the full program
listing: [`helpers/ibex/README.md`](../test/fixtures/protocol/riscv/captured/helpers/ibex/README.md).

**Setup.** Open
`verification/fixtures/protocol/riscv/captured/riscv_ibex_rvfi_trap.fst`, add
an **RVFI Commit Inspector**, press **Auto-bind**.

**Step-by-step expected behavior**

1. All **21 of 21** channels bind. Confidence is **Alias**, not Exact — the
   bundle sits at `tb_ibex_rvfi.u_ibex_top`, two scopes deep, exactly as a
   user's own Ibex simulation would present it.
2. None of Ibex's 17 `rvfi_ext_*` siblings (`rvfi_ext_mcycle`,
   `rvfi_ext_pre_mip`, …) is bound to a channel. Binding one is a defect —
   they are Ibex extensions, not RVFI.
3. **Commits** lists 26 retirements, `rvfi_order` densely 1–26, starting at
   PC `0x080` (Ibex's reset vector is `boot_addr_i + 0x80`). `0x0a0` never
   appears — the `beq` at `0x09c` is taken. `0x0c0` appears three times.
4. **Memory** shows six accesses with real byte masks: word (`0xF`) at
   `0x200`, byte (`0x1`) at `0x204`, halfword (`0x3`) at `0x208`, each with
   its read-back.
5. **Traps** shows the `ecall` at `0x0c8`, privilege M.
6. Three rows read `UNKNOWN INSN` — the two `csrrs` and the `wfi` in the trap
   handler. **This is correct**, not a decode regression:
   `assets/decoders/isa/riscv/` ships RV32I/M/A/F/C and RV64I/M/A/D/C and no
   Zicsr or privileged-system TOML. The capture records the gap.

**Checks — read this part carefully**

The Checks tab reports **19 violations**, and that is the expected result. It
is not a WaveCrux defect and it must not be suppressed. Ibex executes the
program perfectly; its RVFI *reporting* deviates from the spec in one place,
readable from the RTL without running anything:

| Rule | Count | Cause |
|---|---|---|
| Memory access (`memoryAccessUnexpected`) | 19 | `ibex_core.sv:1653` derives `rvfi_mem_rmask` from `lsu_type` alone, and for an instruction with no memory access `lsu_type` is `ibex_decoder.sv:227`'s unconditional default — the word encoding. Nothing gates it on whether a request was issued, so `rmask` is `4'b1111` on every non-store. `rvfi_mem_addr` (`:1763`, the ALU adder result) and `rvfi_mem_rdata` (`:1774`, the previous load's data) are stale alongside it, so the trace asserts a read that never happened. RVFI defines a zero mask as "no memory access". Present on 20 retirements, reported on 19 (the rule is skipped on the trapping `ecall`). |

The other five rules — **control flow**, **writes to x0**, **destination
register**, **retirement order**, **trap consistency** — are clean, which is
what makes the memory-access finding credible rather than a sign the checker
is simply noisy.

**This said 21 until 2026-08-20, and the correction is worth reading.** The
control-flow and trap rules also fired, at the `ecall`: Ibex retires it with
`rvfi_pc_wdata=0x0cc` (PC+4) rather than the trap vector, and the next
retirement fetches from `0x000`. That was recorded as a second Ibex
deviation. It is not one. RVFI defines `rvfi_intr` as marking "the first
instruction that is part of a trap handler, i.e. an instruction that has a
`rvfi_pc_rdata` that does not match the `rvfi_pc_wdata` of the previous
instruction" — the mismatch *is* the definition — and riscv-formal's own
`checks/rvfi_pc_fwd_check.sv` guards its continuity assertion with
`if (expect_pc_valid && !rvfi_intr)`. Ibex asserts `rvfi_intr` at handler
entry (`ibex_core.sv:1914`), so it conforms and our two rules were too
strict. Both now consult `rvfi_intr`; `riscv_ibex_captured_rvfi_test.dart`
locks the exemption.

Neither field is checked by Ibex's own verification: `dv/uvm` only wires them
into `core_ibex_rvfi_if`, and the Spike co-simulation compares architectural
state rather than RVFI reporting. Upstream's `doc/03_reference/rvfi.rst`
states Ibex "is not yet formally verified".

**Product consequence worth carrying forward:** against a real Ibex trace the
memory-access rule is pure noise. If the Commit Inspector ever grows per-core
quirk profiles, this fixture is the regression lock for the Ibex profile —
which is why `riscv_ibex_captured_rvfi_test.dart` pins the counts exactly
rather than asserting "more than zero".

**Limits of this capture, stated so they are not mistaken for coverage**

- **Two-state.** Verilator has no `x`/`z`, so there is no X-propagation
  anywhere, including at time zero. `hasUnknownBits` is **not** exercised;
  the test asserts its absence deliberately. A four-state capture (Icarus,
  VCS, Questa) would be the follow-up.
- **Scalar RVFI ports.** Ibex retires at most one instruction per cycle, so
  this says nothing about packed-NRET bundle detection.

#### 10B.1.11 Automation Assessment

| Test | Coverage |
|---|---|
| ABI mnemonic table — all 32 names, totality, `R<n>` fallback shape the Pro naming service delegates to | **UNIT** (`test/services/riscv/riscv_abi_register_name_test.dart`) |
| Instruction-field extraction — rd per opcode class, load/store widths, declines for compressed / FP / AMO / unallocated, mask helpers | **UNIT** (`test/services/riscv/riscv_instruction_fields_test.dart`) |
| Each of the six checker rules in isolation, on synthetic streams — including every "must not fire" case (taken branch, x0 zero-write, trapping retire, both `mem_addr` conventions, atomics) | **UNIT** (`test/services/riscv/riscv_consistency_checker_test.dart`) |
| Violation `argCount` contract; rule gating from the bound channel set; `check()` ordering | **UNIT** (same) |
| **Clean fixture fires no rule; each corrupted fixture fires its rule and no other** — the core pairing | **UNIT** (`test/services/riscv/riscv_consistency_fixtures_test.dart`) |
| Every checker rule has a corrupted fixture; test/ and verification/ fixture trees agree byte-for-byte | **UNIT** (same) |
| Widget definition — bare `riscv_commit` id, open-core tier, `instrument` category, 21 pins named as canonical RVFI ports, required set, auto-bind wiring, no cap-shaped config | **UNIT** (`test/features/stage/widgets/riscv/riscv_commit_stage_widget_test.dart`) |
| Registration in `registerBuiltinStageWidgets()` (definition + renderer) | **UNIT** (same) |
| `displayNameKey` present + resolves in all locales through `_openCoreKeyToGetter` | **UNIT** (`test/features/stage/widgets/stage_widget_display_name_localization_test.dart`) |
| All four views render real values off the committed fixture; ABI vs numeric naming; empty states; cursor-scoped history | **WIDGET** (`test/features/stage/widgets/riscv/riscv_commit_stage_renderer_test.dart`) |
| Clicking a commit row / violation moves the primary cursor to the right tick | **WIDGET** (same) |
| Violations render inline on the offending row; Checks tab error badge | **WIDGET** (same) |
| Reduced binding set degrades all four views, names the missing channels, and names the skipped checks | **WIDGET** (same) |
| 44 dp touch targets on every tappable row in every view | **WIDGET** (same) |
| Locale sweep en / zh-CN / zh / ja / ko across all five views | **WIDGET** (same) |
| **Lazy-load trap** — every bound pin is loaded before the substrate walks the source, against a source that starts fully unloaded | **WIDGET** (`test/features/stage/widgets/riscv/riscv_commit_lazy_load_test.dart`) |
| Every violation kind formats in every locale, interpolates all of its args, and is never the raw ARB key | **UNIT** (`test/features/stage/widgets/riscv/riscv_commit_messages_test.dart`) |
| Auto-bind dialog uses the widget's own title; a board widget keeps the board heading | **WIDGET** (`test/features/stage/widgets/stage_bindings_pane_test.dart`) |
| **Step grid derivation** — recovers a `sby`-shaped lattice, refuses an irregular one, refuses to manufacture one out of the trace duration alone, refuses a step past the end | **UNIT** (`test/services/remote/cxp/riscv_stream_coordinate_resolver_test.dart`) |
| `riscv.formal.trace_step` — selects the retirement at the step, falls back to the cursor when none retired there, `ch<N>` parsing, unbound channel declined | **UNIT** (same) |
| `riscv.rvfi.retire` — selects by `rvfi_order`, declines an unaddressable hart, declines a `riscv.pc` disagreement rather than selecting the wrong instruction, ignores an unparseable PC | **UNIT** (same) |
| Unknown `stream_id` is declined with a reason and never an error; the anticipated [CXP §9.9.3](https://edacrux.app/cxp#sec-9-9-3) bindings are all unimplemented | **UNIT** (same) |
| End-to-end through the inbound handler: cursor placement, landing record, advisory attributes, the lazy-load of every RVFI ref, element-honoured-with-a-reason on every decline, **and that the whole path runs unlicensed** | **UNIT** (`test/services/remote/cxp/cxp_inbound_handlers_test.dart` — stream-coordinate group) |
| The landing banner: check / "step 7 of 20" / `rvfi_order`, the **replayed-fixture provenance label**, the no-retirement line, dismiss, and a 5-locale sweep | **WIDGET** (`test/features/stage/widgets/riscv/riscv_commit_landing_banner_test.dart`) |
| **Behaviour against a real captured core trace (Ibex, Apache-2.0)** — auto-detection at a two-deep real scope, all 21 channels, `rvfi_ext_*` siblings not bound, 26-retirement reconstruction, real byte masks, the pinned 19-violation checker result with its one documented Ibex RVFI deviation, and the `rvfi_intr` handler-entry exemption | **UNIT** (`test/services/riscv/riscv_ibex_captured_rvfi_test.dart` — §10B.1.10) |
| Ibex capture decodes to its committed transaction snapshot | **WIDGET** (`test/services/decoders/riscv_captured_fixtures_test.dart` — fixture auto-discovery sweep) |
| Ibex capture reproducibility (pinned commit + Verilator + trim) | **MANUAL** — covered by `helpers/ibex/README.md` + `helpers/ibex/Makefile` |
| Add-Widget picker shows it with no tier badge; "does it *feel* like a complete free tool" | **MANUAL** |

### 10B.2 Pipeline Diagram (`pipeline`)

#### 10B.2.1 What it does

Rows are in-flight instructions, columns are clock cycles, and each cell says
which stage that instruction occupied in that cycle. The cycle window is
anchored on the cursor; clicking a cell moves the cursor to that cycle's tick;
row labels come from the existing disassembler.

**This widget is not RISC-V-specific and its id says so.** `pipeline`, not
`riscv_pipeline`: user-named stages plus `valid` / `stall` / `flush` is
generic pipeline occupancy and applies unchanged to an FFT engine, a video
pipeline, a crypto core or a packet processor. It ships the classic five-stage
in-order pipeline as its flagship preset. **If you see RISC-V vocabulary in
the widget's own pins, config labels or empty states, that is a defect** — the
ISA flavour belongs to the preset and the fixture.

#### 10B.2.2 Setup

1. Open
   `verification/fixtures/protocol/riscv/generated/riscv_pipeline_5stage.vcd`.
2. Open the Stage panel (`Cmd/Ctrl+Shift+G`).
3. **Add Widget → Instrument → Pipeline Diagram.** Confirm **no tier badge**
   — it is open core.
4. Select the instance. In the bindings pane, bind `clk`, `instruction`, and
   `stage1_*` … `stage5_*` to the identically-named signals under `tb.core`.

#### 10B.2.3 Steps — the bindings pane shows only the stages you enabled

1. On a freshly-dropped instance, the pane lists `clk`, `instruction`, and
   four pins each for **stages 1–5** — 22 pins, not 33. A pane listing eight
   stages' worth of pins on a default instance is the bug the per-pin
   visibility seam exists to prevent.
2. Configuration → **Stages** → 8. Pins for stages 6, 7 and 8 appear, and so
   do their **Stage 6/7/8 name** fields.
3. Back to 3. The stage 4–8 pins disappear from the pane. Their bindings are
   **not** discarded — set it back to 5 and they are still bound.

#### 10B.2.4 Steps — the diagram

Drag the cursor to the end of the trace first.

1. **Seven rows**, in program order, labelled with real disassembly:
   `lw t0, 0(sp)`, `add t1, t0, t0`, `addi t2, t1, 1`, `beq t2, zero, 16`,
   `addi t3, zero, 1`, `addi t4, zero, 2`, `addi t5, zero, 3`. Each carries
   its PC underneath.
2. **Thirteen columns**, numbered 0–12, with the cursor's cycle highlighted.
   The header reads *"5 stages · cycles 0 to 12 of 13"*.
3. The grid is the classic staircase, with three things visible in it:
   - **a load-use stall** — `lw t0` is in EX at cycle 2, and `add t1` holds in
     ID across cycles 2 **and** 3 while EX takes a bubble at cycle 3;
   - **a back-to-back forward** — `add t1` is in EX at cycle 4 and
     `addi t2` is in EX at cycle 5, with no stall between them;
   - **a branch flush** — `beq` resolves in EX at cycle 6, and at cycle 7 the
     two wrong-path rows (`addi t3`, `addi t4`) simply stop while `addi t5`
     (the branch target, PC `0x8000_001c`) starts in IF.
4. Each stage has its own shade, and the **legend** above the grid names them.
5. **Click any cell.** The primary cursor jumps to that cycle's rising edge
   and the status-bar time changes. Cycle 0 is tick 5, cycle 1 is tick 15, and
   so on — the widget's columns are cycles, but what it hands the rest of the
   app is a tick.
6. Scroll the grid horizontally. The **row-label column stays pinned**;
   scrolling vertically moves labels and cells together.

#### 10B.2.5 Steps — low confidence (the point of the widget)

Open
`verification/fixtures/protocol/riscv/generated/riscv_pipeline_defeat.vcd` and
bind it the same way.

This is the **same pipe running the same program with the same occupancy**.
The only difference is that the branch kill is expressed by dropping stage
`valid` instead of asserting `stageN_flush` — which is what plenty of real
cores look like from outside. The positional shift-register model predicts ID
and EX are occupied in cycle 7; the trace says they are empty.

1. A **red banner** appears above the grid: *"Not trustworthy: Positional
   (valid / stall / flush) tracking contradicted the trace in 2 cells. What
   follows is what the trace says, not a reconstructed pipeline — do not read
   it as one."*
2. The grid below it is **visibly dimmed**. It is still readable and still
   clickable, because the tracker adopts the trace where it disagrees with its
   own model — but it must not read as a finding.
3. **Compare the two grids side by side. They are identical.** That is the
   whole point: without the banner there is nothing to tell a correct diagram
   from a fabricated one. A build that draws this fixture with no banner, or
   with the same styling as the clean one, is **failing the hard requirement**,
   not being tidy.
4. Configuration → **Instruction identity** → *PC match*. The banner
   disappears and the grid un-dims: PC matching survives what defeats
   positional tracking. This is §3.2's free/paid argument made visible — the
   free tracker states what it can and cannot do, and superscalar / OoO
   tracking is genuinely harder, which is what the Pro pipeline widget sells.

#### 10B.2.6 Steps — configuration

1. **Stages** → 3. The header reads *"3 stages"*, `MEM` and `WB` disappear
   from the legend and the grid, and no cell is shaded for them.
2. **Stage 1 name** → `Fetch`. The legend and every stage-1 cell relabel; the
   cells abbreviate to four characters and the legend spells it out.
3. **Cycle window** → 4. Only four columns show, centred on the cursor's
   cycle; scrubbing scrolls the window along the trace.
4. **Instruction identity** → *PC match* / *Positional*. Note there is **no
   tag option** — tag-based tracking is Pro, and offering a choice this build
   has no tracker for would be a menu item that produces a blank panel.
5. Save the session, reload it: the stage count, the identity source, the
   window, every stage name and every binding restore.

#### 10B.2.7 Edge cases

- **No file loaded** → *"No waveform loaded"*, no crash.
- **Clock unbound** → *"Bind clk. Cycles are its rising edges — a waveform has
  no cycle domain of its own…"* rather than an empty panel. There is no
  guessed clock.
- **Clock bound to something that never toggles** → *"The bound clock never
  rises in this trace, so there are no cycles to draw."*
- **No stage `valid` pin bound** → *"Bind at least one stage valid signal. 5
  stages are configured; each needs its own valid pin."*
- **`instruction` unbound** → rows fall back to their **PC** (`0x8000_0000`),
  never to a guessed mnemonic.
- **Signals never added to the viewer.** Bind the pipeline *without* adding
  any of those signals to the waveform panel. The diagram must still populate
  — Stage bindings lazily load their own signal data. An empty grid here is
  the lazy-load defect (ARCHITECTURE §6.6 rule 1), and it is worse for this
  widget than for the Commit Inspector: an unloaded clock does not degrade the
  diagram, it deletes it.
- **Resize to the minimum (320 × 200).** The grid scrolls in both axes; the
  legend scrolls horizontally; nothing overflows.
- **Locale sweep** en / zh-CN / zh / ja / ko: the header, both banners, the
  legend heading, every empty state and every config label are translated. The
  stage names, PCs and disassembly are not, by design.

#### 10B.2.8 Automation Assessment

| Test | Coverage |
|---|---|
| Cycles are clock rising edges; the half-open `changesInRange` contract does not eat the last cycle; a clock high at `startTime` opens cycle 0; `maxCycles` truncates | **UNIT** (`test/services/riscv/riscv_pipeline_observation_service_test.dart`) |
| Per-stage sampling at the rising edge; an unbound optional pin reads false, not unknown; no clock / no stages / no edge is an empty result rather than an invented cycle count | **UNIT** (same) |
| `cycleAt` maps a tick back to its cycle, including before the first edge and past the last | **UNIT** (same) |
| **The clean and defeat fixtures draw the same grid, and only the confidence verdict separates them** — the core pairing | **UNIT** (`test/services/riscv/riscv_pipeline_fixtures_test.dart`) |
| Both trackers draw exactly the hand-authored cell grid, compared by `(cycle, stage, pc)` so the assertion is tracker-neutral | **UNIT** (same) |
| One instruction keeps one identity down its whole path | **UNIT** (same) |
| Positional reports `low` + one `occupancyMismatch` per contradicted cell on the defeat fixture; PC reports `high` on both | **UNIT** (same) |
| The two fixtures differ **only** in the flush pins; test/ and verification/ trees agree byte-for-byte | **UNIT** (same) |
| Widget definition — bare `pipeline` id, open-core tier, `instrument` category, one required clock, 4 pins × 8 stages, no `tag` param / choice / pin, no cap-shaped config | **UNIT** (`test/features/stage/widgets/pipeline/pipeline_stage_widget_test.dart`) |
| **No ISA vocabulary anywhere in the widget's own id, description, pins, params or groups** | **UNIT** (same) |
| Per-pin `visibleWhenValues` shows stage *n* only from stage count *n* up, and a never-configured instance still shows the default five stages | **UNIT** (same) |
| Config parsers clamp and fall back — including `tag` → `positional` | **UNIT** (same) |
| Registration in `registerBuiltinStageWidgets()` (definition + renderer) | **UNIT** (same) |
| `displayNameKey` present + resolves in all locales through `_openCoreKeyToGetter` | **UNIT** (`test/features/stage/widgets/stage_widget_display_name_localization_test.dart`) |
| Window anchoring, clamping at both ends, a window wider than the trace, an empty trace; cycle→tick mapping | **UNIT** (`test/features/stage/widgets/pipeline/pipeline_view_data_test.dart`) |
| Row selection and program ordering; cells past the configured stage count dropped; the instruction word sampled only at the front-stage entry cycle; a row that entered before the trace carries no disassembly and no guess | **UNIT** (same) |
| **An `occupancyMismatch` marks exactly the cell it names, and a non-mismatch warning marks none** | **UNIT** (same) |
| Grid renders real rows off the committed fixture, labelled by the disassembler; stage shading and legend | **WIDGET** (`test/features/stage/widgets/pipeline/pipeline_stage_renderer_test.dart`) |
| Clicking a cell moves the primary cursor to that cycle's **tick** | **WIDGET** (same) |
| **The defeat fixture raises the banner with its count and tracker name, and dims the grid; the clean fixture does neither** | **WIDGET** (same) |
| PC matching survives the fixture that defeats positional tracking | **WIDGET** (same) |
| Stage count, stage names and cycle window all change what is drawn | **WIDGET** (same) |
| Unbound clock / no stage valid / no instruction pin / no disassembler all state the problem instead of rendering nothing | **WIDGET** (same) |
| 44 dp touch targets on every clickable cell | **WIDGET** (same) |
| Locale sweep en / zh-CN / zh / ja / ko over the banner and the empty states | **WIDGET** (same) |
| **Lazy-load trap** — every bound pin is loaded before the substrate walks the source, against a source that starts fully unloaded | **WIDGET** (`test/features/stage/widgets/pipeline/pipeline_lazy_load_test.dart`) |
| Pinned label column vs horizontal grid scroll; readability at the 320 × 200 minimum | **MANUAL** |
| "Do the two grids look identical, and is the banner the only thing telling them apart" — the judgement the requirement is really about | **MANUAL** |
| Behaviour against a real captured core trace | **MANUAL** (still pending). The Ibex capture landed for the Commit Inspector (§10B.1.10) but does **not** serve this widget: it is trimmed to the RVFI bundle, and the pipeline widget needs per-stage valid signals that the trim drops. A second capture keeping `u_ibex_core.id_stage_i` / `if_stage_i` stage signals would close this; the recipe under `helpers/ibex/` supports it by editing `trim.py`'s whitelist. |

---

## 11. FSM state visualization

### 11.1 What it does

A finite state machine (FSM) is a common HDL design pattern — a register holding the current state, plus combinational logic deciding the next state. Engineers debug FSMs constantly: "did we transition to ERROR? When? Why?" The FSM visualization feature analyzes a state register and displays:

- The state-transition graph (nodes = states, edges = observed transitions).
- A history of state visits.
- An "active state" highlight that updates as the cursor moves.
- The ability to click a state in the graph and jump to its first occurrence in the timeline.

### 11.2 Steps

1. Load a VCD containing an FSM (state register signal). Add the state signal to the canvas.
2. Open the FSM panel (typically via right-click on the state signal → "Visualize FSM").
3. Verify the panel shows a graph of states and transitions actually observed in the simulation.
4. Move the cursor along the timeline. Verify the "active state" highlight updates in real time.
5. Click a state in the graph. Verify the cursor jumps to its first occurrence.
6. Verify state names are decoded correctly if symbolic state encoding is provided (via translate filter or stems file).

### 11.3 Edge cases

- State signal that's only ever in one state — graph shows a single node.
- State signal that goes X — visualization handles gracefully.
- Very large state machines (50+ states) — graph layout remains usable.

### 11.4 Diagnostics-assisted verification

- Render tab: FSM panel should not significantly impact frame time during cursor scrubbing.

### 11.5 Automation Assessment

| Test | Coverage |
|---|---|
| State graph derivation from known fixture | **WIDGET** (`test/services/signal_query/fsm_analysis_service_test.dart` + `fsm_layout_service_test.dart` + `test/features/viewer/widgets/fsm_bubble_painter_test.dart`) |
| Active-state highlight follows cursor | **WIDGET** (`test/features/viewer/widgets/fsm_panel_test.dart`) |
| Click-state-to-jump | **WIDGET** (`fsm_panel_test.dart`) |
| Right-click state register → "Visualize FSM" gesture dispatch | **WIDGET** (`test/features/viewer/widgets/fsm_annotate_dialog_test.dart`); end-to-end dispatch **INTEGRATION_TEST** (`integration_test/gestures/fsm_context_menu_dispatch_test.dart` — right-click the FSM signal row → "Visualize as FSM" menu item → FSM panel opens with a ≥1-node bubble diagram) |
| State cleanup on new file load | **WIDGET** (`test/features/viewer/providers/waveform_source_provider_test.dart` — "openFile clears FsmViewState" + "openFile clears FsmAnnotation map") |
| Symbolic state names from translate filter / stems file | **WIDGET** (`fsm_analysis_service_test.dart`) |
| Graph layout for large FSMs | **UNIT** (`test/services/signal_query/fsm_stress_test.dart` — layout stability at N ∈ {50, 256, 4096}: finite, in `[0,1]²`, distinct, deterministic; N=50 pins the circle by property. Promoted from MANUAL by the FSM robustness plan, Layer E.) |
| FSM model from real-parser VCDs (state/transition graph derivation, end-to-end) | **UNIT** (`test/services/signal_query/fsm_golden_test.dart` — opens VCDs through the real wellen FFI and snapshot-compares the `FsmModel` against `<machine>.expected_fsm.json`; FFI-gated, `REGENERATE=1` to refresh; FSM robustness plan, Layer A) — incl. a **real PicoRV32 `cpu_state` capture** (ISC; `test/fixtures/fsm/picorv32_state/captured/`, 7 states / 21 transitions; Layer F) |
| FSM analyzer never crashes/hangs on pathological signals | **UNIT** (`test/services/signal_query/fsm_edge_cases_test.dart` — ~24 adversarial shapes incl. all-X/Z, x/z chain break, simultaneous-tick, huge >2³² range, non-monotonic, 256-bit, 1024 states; FSM robustness plan, Layer C) |
| FSM structural invariants over random streams | **UNIT** (`test/services/signal_query/fsm_fuzz_test.dart` — 500 seeded streams vs an independent oracle: counts, ordering, x/z chain break, determinism, layout bounds; FSM robustness plan, Layer D) |
| FSM corpus is self-enforcing (layout split + golden companions) | **UNIT** (`test/static/fsm_fixture_layout_test.dart`, `test/static/fsm_fixture_companion_test.dart`) |
| User FSM annotations persist through session save/reopen | **WIDGET** (`fsm_annotation_test.dart` JSON group, `session_state_test.dart` "fsmAnnotations" group, `session_service_test.dart` "fsm annotations preserved"/"defaults to empty"/"byte-stable", `fsm_provider_test.dart` "restoreFromSession" cases); end-to-end **INTEGRATION_TEST** (Pro `integration_test/coexistence/composite_workspace_round_trip_test.dart` exercises the full save→close→reopen restore of an FSM annotation) |

### 11.6 User FSM annotations persist across session save / reopen

When a signal has no GTKWave translate filter, the user can mark it as an FSM and supply state-name labels directly (the `Annotate FSM…` dialog). These annotations are per-tab and are **persisted** in the `.wavecrux` session file (the `fsmAnnotations` map), exactly like the translate filters they substitute for. They round-trip through save → close → reopen and through the per-tab session sidecar autosave.

Steps:

1. Load a VCD with an integer-valued state register and add it to the canvas.
2. Annotate it: open the FSM annotate dialog and assign labels to a couple of state ids (e.g. `0 → IDLE`, `1 → RUN`).
3. Save the session (`File → Save Session`), then close the tab and reopen the saved `.wavecrux` file.
4. Verify the FSM annotation is restored: the same signal still shows the labels you assigned (and the FSM visualization uses them).

Edge cases:

- A session saved before this feature (no `fsmAnnotations` key) loads with an empty annotation map — no error.
- A session with no FSM annotations writes no `fsmAnnotations` key (byte-stable round-trip).
- Reopening the same waveform file (auto-reload on file change) preserves the annotations — `openFile` clears them on the fresh-file path, and the reload pipeline re-applies the snapshot.

---

## 12. RTL source annotation

### 12.1 What it does

The waveform shows you *what* happened (signal values over time). The RTL source view shows you *why* — which line of Verilog/VHDL drove each signal. RTL source annotation bridges these views: it displays your RTL source code with signal values annotated inline at the current cursor time, updating live as the cursor moves. Click a signal name in the source to add it to the waveform. Click a signal in the waveform to jump to its definition in the source.

This is inspired by Synopsys Verdi's source browser and is one of the most-requested features by engineers coming from commercial verification tools.

**Desktop only** — this feature requires significant screen real estate.

### 12.2 Setup

A VCD plus a "stems" file — a mapping from signal hierarchy paths to source file locations — plus the RTL source files themselves accessible on disk. Three ways to obtain the stems file:

- **In-app generator (no GTKWave required):** **Tools → "Generate RTL Stems…"** parses a Verilog/SystemVerilog or VHDL source tree and writes a `.stems` file directly. This is WaveCrux's replacement for GTKWave's `xml2stems` / `vermin`. See `lib/services/rtl_source/stems_generator.dart` (best-effort parser for the common synthesizable subset; constructs it cannot resolve are listed as warnings and omitted, never fatal).
- **Verilator AST import (elaboration-accurate):** **Tools → "Import Verilator AST (JSON)…"** converts a `verilator --json-only` dump (`V<top>.tree.json` + sibling `V<top>.tree.meta.json`) into a `.stems` file. Because the dump is post-elaboration, generate-for loops arrive unrolled (`gen_blink[0]`…) and the emitted paths match the waveform hierarchy exactly — accuracy the best-effort source parser cannot reach. Note that Verilator 5.x removed `--xml-only`, so GTKWave's `xml2stems` cannot consume modern Verilator output at all; this import is the working replacement. See `lib/services/rtl_source/verilator_ast_stems_importer.dart` (tolerant of schema surprises; warnings, never fatal — the JSON schema is Verilator-internal, last validated against 5.048).
- **External:** any GTKWave-compatible stems file (legacy `xml2stems` / `vermin` output) still loads. The format WaveCrux parses is documented in `lib/services/rtl_source/stems_parser.dart`.

Sample HDL designs for trying the generator live under `test/fixtures/rtl_source/`: clean-room `cpu/` (Verilog) and `vhdl/`, plus a captured real-world design `captured/picorv32/` (PicoRV32, ISC, with `PROVENANCE.md`) that exercises multi-line parameterized instantiations and a real module hierarchy. For the Verilator AST import, committed dumps (generated with Verilator 5.048) live under `test/fixtures/rtl_source/verilator_ast/` (`cpu/` and the generate-loop design `genloop/`), regenerable via `tool/generate_verilator_ast_fixtures.sh`.

### 12.3 Steps — generating stems (in-app)

1. On desktop, open **Tools → Generate RTL Stems…** (also in the command palette). It is desktop-only and does **not** require a waveform to be loaded.
2. Add HDL files with **Add Files…** or a whole tree with **Add Folder…** (e.g. point it at `test/fixtures/rtl_source/cpu/`). Verify the source list shows the files with a count.
3. Optionally type a **Top module** (leave blank to auto-detect a unique top). Click **Generate & Load**.
4. Choose where to save the `.stems` file. On success a snackbar reports the mapping count and top module (or a "generated with N warnings" notice), and the RTL panel opens automatically.
5. **Edge — ambiguous top:** select files with two independent tops and leave the field blank; verify the dialog stays open with a "could not determine a single top module … Candidates: …" message rather than guessing.
6. **Edge — no modules:** select a non-HDL file; verify a clear "no modules found" message.

### 12.3.1 Steps — importing a Verilator AST dump

Prerequisite: `verilator` on PATH (5.048 is the validated version), or use the committed dumps under `test/fixtures/rtl_source/verilator_ast/` and skip step 1.

1. Produce a dump from the sample design: `verilator --json-only -Wno-fatal --Mdir /tmp/ast --top-module top test/fixtures/rtl_source/cpu/*.v` → emits `/tmp/ast/Vtop.tree.json` + `Vtop.tree.meta.json`.
2. On desktop, open **Tools → Import Verilator AST (JSON)…** (also in the command palette). It is desktop-only and does **not** require a waveform to be loaded.
3. **Choose AST File…** and pick `Vtop.tree.json` (the sibling `.tree.meta.json` is located automatically). Click **Import & Load**.
4. Choose where to save the `.stems` file (suggested name `<top>.stems`). On success a snackbar reports "Imported N mappings from top module top" (or an "imported with N warnings" notice) and the RTL panel opens automatically. The saved `.stems` is a portable GTKWave-compatible file — the deliverable `xml2stems` used to produce.
5. **Generate-loop paths:** repeat with a dump of `test/fixtures/rtl_source/verilator_ast/genloop.v` (or use the committed `verilator_ast/genloop/` dump). Open the written `.stems` in a text editor and verify the unrolled scopes appear as `top.gen_blink[0]` … `top.gen_blink[3]`, each with `u_blink.clk` / `u_blink.led` beneath — these paths match a Verilator-simulated waveform hierarchy exactly.
6. **Edge — missing meta:** copy a `V<top>.tree.json` somewhere without its `.tree.meta.json`; verify the dialog stays open with a diagnostic naming the expected meta path, and any previously loaded stems remain untouched.
7. **Edge — ambiguous top:** import a dump containing two independent top modules; verify the dialog stays open listing the candidates, and typing one into **Top module** resolves the import (same UX as the generator).
8. **Edge — dump from another machine:** import a dump whose meta records absolute paths that don't exist locally; the mappings still load (the panel reports missing source files per §12.8 when navigation is attempted).

### 12.4 Steps — basic loading

The entry points (all desktop-only):
- **Tools → "Generate RTL Stems…"** — generate from source, then auto-load (above).
- **Tools → "Import Verilator AST (JSON)…"** — convert a Verilator `--json-only` dump, then auto-load (§12.3.1).
- **Tools → "Load RTL Stems File…"** (also in the command palette; requires a file loaded) — opens the picker; on success it reveals the panel.
- **View → "Toggle RTL Source Panel"** / **Cmd/Ctrl+Shift+R** — toggles the panel.

The RTL panel is hosted in the **right pane** (it replaces the value column). Loading/generating/toggling forces the right pane visible when revealing the panel, so it appears even if the value column was collapsed.

1. Load a VCD on desktop. Verify **View → Toggle RTL Source Panel**, **Tools → Load RTL Stems File…**, and **Tools → Generate RTL Stems…** are present.
2. Press **Cmd/Ctrl+Shift+R** (or use the menu). Verify the RTL panel appears in the right pane showing the empty-state guidance and a prominent **"Load Stems File…"** button — even if the value column was previously collapsed.
3. Load (or generate) the stems file. Verify source code displays with basic syntax highlighting (Verilog/VHDL keywords colored).
4. **Multi-tab:** open a second tab, toggle the RTL panel there, and confirm each tab keeps its own panel state (toggling in one tab never affects the other) — the per-tab scope regression the 2026-06 fix addressed.

### 12.5 Steps — signal value annotations

1. Place the cursor at a specific time.
2. For signals with stems mapping, verify their current values are annotated inline next to the relevant source lines (e.g., `wire [7:0] data_out; // = 0xFF`).
3. **Live cursor update:** slowly scrub the cursor. Annotated values in the source panel should update in real time.

### 12.6 Steps — bidirectional navigation

1. **Source → waveform:** click a signal name in the source code. If that signal isn't already in the waveform, it's added. If it's already there, it's highlighted.
2. **Waveform → source:** click a signal in the waveform that has a stems mapping. The source panel navigates to the file and line where it's defined.
3. **Signal with no stems mapping:** click such a signal in the waveform. The source panel doesn't navigate — or shows a subtle "no source mapping" message. Doesn't crash.

### 12.7 Steps — device gating

1. On phone and tablet, verify there's no menu option, button, or panel for RTL source annotation. It should be completely absent on these device classes.
2. Resize the desktop window to phone width (< 600 dp). The source annotation panel should disappear or become inaccessible.

### 12.8 Edge cases

- Stems file references source files not on disk — error or placeholder, no crash.
- Malformed stems entries — parser handles gracefully, surfaces what it can.
- Source panel opened with no stems file loaded — clear invitation to load a stems file, not an empty/broken panel.

### 12.9 Automation Assessment

| Test | Coverage |
|---|---|
| Stems file parsing | **WIDGET** (`test/services/rtl_source/` + `test/features/rtl_source/providers/`) |
| Stems generation from HDL (Verilog/SV + VHDL): hierarchy, top auto-detect, warnings, writer round-trip | **UNIT** (`stems_generator_test.dart`, `hdl_declaration_parser_test.dart`, `stems_writer_test.dart`) |
| Generate → write → load → showSignal resolves correct file:line (Verilog + VHDL) | **INTEGRATION** (`stems_generation_e2e_test.dart`, fixtures under `test/fixtures/rtl_source/`) |
| Generator on real third-party RTL: multi-line `#(...)` hierarchy, auto-top ambiguity, round-trip (PicoRV32, ISC) | **INTEGRATION** (`picorv32_captured_test.dart`, `test/fixtures/rtl_source/captured/picorv32/`) |
| Generate Stems dialog flow (add sources, generate, pop outcome, errors) + locale sweep | **WIDGET** (`generate_stems_dialog_test.dart`) |
| Verilator AST → stems conversion: elaborated hierarchy, unrolled generate scopes, var/param filtering, top resolution, schema tolerance | **UNIT** (`verilator_ast_stems_importer_test.dart`, fixtures under `test/fixtures/rtl_source/verilator_ast/`) |
| Import Verilator AST dialog flow (pick dump, import, write stems, load into RtlSourceState; ambiguous-top and missing-meta errors) + locale sweep | **WIDGET** (`import_verilator_ast_dialog_test.dart`) |
| Regenerating the committed AST dumps against a new Verilator release | **MANUAL** (`tool/generate_verilator_ast_fixtures.sh`; schema is Verilator-internal — see the fixtures README) |
| Signal value annotation at known times | **WIDGET** (`test/features/rtl_source/widgets/rtl_source_panel_test.dart`) |
| Live cursor update of annotations | **WIDGET** (`rtl_source_panel_test.dart`) |
| Source → waveform navigation | **WIDGET** (`rtl_source_panel_test.dart`) |
| Waveform → source navigation | **WIDGET** (`rtl_source_panel_test.dart`) |
| Missing source file error | **WIDGET** (`rtl_source_panel_test.dart`) |
| Device gating (hidden on phone and tablet) | **WIDGET** (`test/features/rtl_source/widgets/rtl_source_device_class_test.dart`) |
| Toggle/load route to the ACTIVE TAB (per-tab scope, not root) | **WIDGET** (`test/features/viewer/screens/viewer_screen_test.dart` — "toggleRtlSourcePanel flips the ACTIVE TAB state…") |
| Header fits the narrow right pane (no overflow), locale sweep | **WIDGET** (`rtl_source_panel_test.dart` — "narrow right pane (no overflow)") |
| Syntax highlighting fidelity | **MANUAL** (visual) |

> **2026-06-14 regression fix.** RTL annotation, the cocotb log panel, and Compare Waveforms were each wired to the **root** provider scope instead of the active tab's per-tab container (an artifact of the per-tab/per-pane workspace migration), so their toggles/loads were silent no-ops. All three now route through `_activeTabContainer`; revealing the RTL panel also forces its host (right) pane open. A codebase-wide audit found the same scope-leak class in the CXP cross-probe subsystem (outbound selection emitter + inbound highlight/marker handlers) — also fixed, via the shared `activeTabContainer(ref)` resolver. A static guardrail (`test/static/root_host_per_tab_scope_leak_test.dart`) now fails CI if any root-scoped host reads/writes a per-tab provider through a bare root `ref`, complementing the provider-body guard.

---

## 13. Performance verification

### 13.1 Targets

- **Desktop:** 60 fps with 1000+ signals.
- **Tablet:** 60 fps with 500+ signals.
- **Phone:** smooth interaction with 100+ signals.

### 13.2 Steps — desktop

1. Diagnostics → Generator: produce a synthetic VCD with 1000 signals, long duration, high complexity. Open it.
2. Add all 1000 signals to the viewer.
3. Diagnostics → Render: note current/average/worst frame time, visible signal rows, visible transitions.
4. Drag the canvas to scroll horizontally. Average frame time should hold under 16.6 ms (60 fps). Occasional worst-case spikes are acceptable.
5. **Zoom stress:** zoom out so all 1000 signals visible simultaneously — worst case for renderer. Frame times degrade somewhat but remain usable. Then zoom in to a single transition — frame times improve dramatically.
6. Repeat with 2000 signals.

### 13.3 Steps — tablet

1. Same as desktop but with 500 signals as the target. Run on physical iPad/Android tablet.

### 13.4 Steps — phone

1. 100 signals. Run on physical iPhone/Android phone.
2. Test all the major workflows (open file → add signals → cursor → zoom) and verify they remain responsive throughout.

### 13.5 Steps — regression check

1. Run the parser benchmark from Diagnostics → Benchmarks.
2. Compare parse times against the saved baseline from prior releases. Investigate any regression > 10 %.
3. Run the render benchmark. Compare frame times to baseline.

### 13.6 Memory leak check

1. Open a moderately large file. Note Memory tab values.
2. Scroll extensively for 5 minutes.
3. Note Memory tab values again. Confirm memory is stable — not growing without bound.

**Automated:** `integration_test/canvas/scroll_memory_soak_test.dart` covers
this end-to-end. It drives a sustained scroll + zoom + pan session (real-run
wall-clock ≈ 5m42s against an 800-signal, transition-dense fixture) and makes
two complementary assertions: (1) a **deterministic** bound that the source's
loaded-signal count never exceeds the `SignalLoadPlanner` eviction ceiling and
does not drift upward across iterations — the tight, non-flaky proof that the
dominant memory consumer cannot grow without bound; and (2) a **tolerant** RSS
leak canary comparing the median RSS of the last few samples to the first few
(post-warmup) via the real `MemoryStatsService`, allowing growth only up to
`max(baseline, 400 MB)` so it flags genuine unbounded growth while ignoring the
Dart heap's normal plateau and GC/fragmentation noise. Manual sign-off remains
useful for observing the Memory-tab UI values directly, but the regression is
guarded automatically.

### 13.7 Statistics strip (desktop)

Per ARCHITECTURE.md §3.1.8 and §8.8, the live-statistics strip is a desktop-only collapsible region between the IdeLayout and the status bar.

1. Toggle the strip via the disclosure triangle in the status bar. Verify it expands and collapses.
2. Verify metric values match the diagnostics Render and Memory tabs (they share the same underlying providers).
3. Verify the strip is absent on phone and tablet.
4. Verify the strip's visibility persists across session save/restore.

### 13.8 Wide-file viewport-gated loading ("Add All in Scope")

Adding hundreds–thousands of signals at once (right-click a scope → **Add All in
Scope**) used to decompress *every* added signal up front and paint them all at
the end, so the canvas looked frozen for several seconds with no feedback. The
loading path is now **viewport-gated**: only the lanes in (or near) the visible
window are decompressed, the rest stream in on scroll, lanes paint
**incrementally** as their data arrives, a determinate **progress indicator**
(with a cancel button) shows in the status bar, and an **LRU** unloads
off-screen signals so the decompressed working set — and peak memory — stays
bounded regardless of how many signals were added.

**Setup.** The committed test corpus is small; generate wide fixtures locally:

```bash
dart run tool/generate_scale_fixtures.dart            # 300/1000/2000/5000-signal VCDs → build/scale_fixtures/
dart run tool/generate_scale_fixtures.dart --signals 2000 --out /tmp/wc   # a single 2000-signal file
```

A 2000-signal file is ~67 MB / ~7 M transitions (same per-signal density as the
`forencich_axi_register.fst` reference case). These are too large to commit, so
the generator is the source of truth (deterministic for a fixed `--seed`).

**Steps.**

1. Open `scale_2000sig.vcd`. Right-click the `top` scope → **Add All in Scope**.
2. Verify signal **names** appear immediately and the first screenful of
   **waveforms** paints within a beat — not after a multi-second freeze.
3. Verify the status-bar **progress indicator** (bar + `loaded/total` count)
   appears and advances, then disappears when loading settles.
4. Verify lanes **fill in incrementally** rather than all snapping in at once.
5. **Scroll** down through all 2000 lanes. Verify scrolling stays smooth (no
   per-frame hitching) and lanes scrolled into view load on the fly.
6. Open Diagnostics → **Memory**; scroll the full height a few times. Verify
   memory stays **bounded** (LRU unloads off-screen signals) rather than
   climbing monotonically toward the full-decompress figure.

7. **No silent stretch.** On a scope that is big in *both* signal count and
   transitions per signal, choose **Add All in Scope** and watch the status
   bar from the moment the menu closes: the indicator is up throughout — an
   indeterminate bar with no count while the scope hierarchy is walked, then
   "Adding" with a count, then "Loading" — with no gap before the waveforms
   paint. This holds below 5000 signals too: small adds arm the indicator and
   hand it to the canvas's loading phase.
8. **Slow but few.** Add three or four signals with millions of transitions
   each (fewer than the 24-signal count threshold): once decompression has run
   for about 200 ms the loading indicator appears and stays until they paint.
   Adding a few light signals shows no indicator at all — no flash.

**Diagnostics-assisted.** The Pane Render Stats popover's transition/segment
counts reflect only the visible lanes; Memory grows with the visible working
set, not the full signal count.

**Million-signal adds (chunked "Adding…" phase).** For batches of ≥ 5000
variables (gate-level scopes reach 1M+), the entry-building stage itself is
now chunked and progress-indicated: the context menu closes immediately, the
same status-bar indicator runs in an **"Adding signals"** phase (tooltip
wording differs from the loading phase; the bar and counts are shared), the
entry list is applied in **one** state update at the end, and the indicator
then transitions to the loading phase for the visible screenful. Three costs
that used to freeze the UI on 1M+ adds were removed: per-entry UUID
generation (now a run-tag + counter id), the per-visible-row group-target
rescan in the signal list panel (now computed once per rebuild), and the
autosave JSON encode (sessions with ≥ 50k entries now serialize compact on a
worker isolate). Verify with Kevin Laeufer's gate-level reference FST (§13.8A):
right-click the 64k-variable scope (or the root, 1.3M) → Add All in Scope —
the menu closes at once, the "Adding" indicator advances and stays up through
the list-materialization frame, then waveforms stream in promptly under the
loading phase. The canvas **never does O(all-entries) rich-lane work**: a
compact `LaneGeometryIndex` (typed arrays + entry pointers, memoized on
structure) covers all lanes, and rich `WaveformLaneData` objects are
materialized **only for the viewport window** on each build
(`WaveformCanvas.fullMaterializeThreshold` gates this — files at or below
20k lanes keep the old materialize-everything behavior exactly). Before this,
the full lane build ran once per 12-signal load batch — a 17 s frozen frame
on web (DDC) at 1.3M entries, captured in the 2026-07-13 beta screen
recording. **Web (Chrome) must be part of this verification pass** — it is
the slowest target and where the regression was reported. Web-specific
behaviors to verify: the loading phase **visibly animates** while the
visible screenful decompresses (WASM decompresses on the main thread; the
canvas yields one real frame per load via `endOfFrame`, web only), the bar
turns **indeterminate** while the "Adding" count sits at total/total (the
heavy materialization frame — a static full bar reads as a hang), and the
Adding→Loading indicator handoff never drops the loading indicator
(`finishPhase` is phase-scoped; the two batches overlap around the
materialization frame).
Cancelling during the Adding phase applies **nothing** (all-or-nothing);
cancelling during the loading phase keeps already-loaded lanes (see below).

**Edge cases.**

- Click the progress indicator's **×** (cancel) mid-load — loading stops
  promptly; already-loaded lanes remain browsable; re-adding resumes cleanly.
- Click **×** during the **Adding** phase — the whole add is abandoned; the
  signal list is exactly as it was before the menu action.
- **Scroll while loading** — the in-flight load is superseded by the new
  viewport's load (no stacked/duplicated work, no stale paint).
- A scope with **5000+** signals (`--signals 5000`) — initial add stays bounded
  to the first screen; the app never freezes on the full set.

### 13.8A Massive-hierarchy open (gate-level netlists) + size-scaled open watchdog

Gate-level netlists produce hierarchies far beyond RTL dumps — 100k+ scopes,
1M+ variables, tens of thousands of variables in a single scope. Two behaviors
protect this path (both landed after a beta report of an 18 MB / 142k-scope /
1.3M-variable FST being rejected):

1. **Linear hierarchy build.** The FFI hierarchy walk shares one pair of
   walk-wide index buffers instead of allocating worst-case scratch buffers
   per scope (which was quadratic in design size: ~6.4 s of allocator traffic
   for a file wellen parses in <200 ms; ~0.3 s after the fix).
2. **Size-scaled open watchdog.** The open-call hang detector scales with
   file size — 30 s base + 1 s/MB, capped at 10 min (`scaledOpenTimeout`) —
   instead of a fixed 5 s, so large-but-valid files are never killed
   mid-parse while genuinely stuck opens (malformed VCDs that spin wellen)
   still recover.

**Steps.** Open a gate-level FST with ≥ 100k scopes / ≥ 1M variables (Kevin
Laeufer's `luke_wren_gatelevel_netlist_dec_2025.fst` is the reference trace, or
any synthesized netlist dump). Expect: **the moment the pick lands, a new tab
appears with a spinner and "Parsing <filename>…" in the canvas** (web: the
tab+placeholder paint once before the main-thread WASM parse blocks — the
spinner then freezes but the message stays; desktop/mobile: the spinner
animates throughout, the parse runs on the background isolate). The load then
completes in seconds (no TimeoutException), the signal tree renders with
scope-size badges, expanding the 64k-variable scope stays responsive, and
File Info reports the full scope/variable counts. The pre-fix behavior — the
welcome screen sitting untouched for the whole parse with zero feedback — is
the regression to watch for.

**Flat lazy tree (0.2.4).** The signal tree renders as a single flat
`ListView.builder` over `signalTreeRowsInOrder` with a fixed row extent —
expanding ANY scope (including the 64k-variable one) must be instant, because
only the ~30 viewport rows are ever built. The pre-0.2.4 behavior — eager
recursive child builds, one superlinear synchronous frame, minutes at 64k
rows — is the regression to watch for. Verify: expand the 64k scope (instant,
scrollbar reflects the full row count, scrolling through it stays smooth),
collapse it (instant), type a search query and confirm per-keystroke filtering
stays fluid with the big scope expanded — the filter resolves "does this scope
contain a match?" for the whole hierarchy in one bottom-up pass per keystroke,
so cost scales with scope count rather than with scope count × nesting depth. Nested indentation, expand/collapse
arrows, scope context menus (Add All in Scope), leaf gestures
(tap-add / Ctrl+click / Shift+click ranges / drag-to-Stage), and search
auto-expansion must all behave identically to the nested-tree era — the rows
are the same widgets, only their hosting changed.

**Edge case.** A deliberately malformed VCD (truncated `$var` header) must
still be rejected by the watchdog and surface the recoverable "Failed to load
waveform" error, then a valid file must open normally in the same tab.

### 13.9 Automation Assessment

| Test | Coverage |
|---|---|
| Synthetic 1000/500/100 signal load and add | **WIDGET** (`test/benchmarks/` covers parser+render numerically); perceptual 60 fps **MANUAL** |
| Size-scaled open watchdog arithmetic (base, per-MB, cap) | **UNIT** (`test/services/waveform/wellen_provider_failure_paths_test.dart` — "scaledOpenTimeout" group) |
| Hierarchy walk correctness (shared scratch buffers) | **UNIT** (existing known-answer FFI fixture tests in `test/services/waveform/` — hierarchy equality against `.expected.json`) |
| Massive-hierarchy open end-to-end (1M+ vars) | **MANUAL** (no committed fixture — a representative gate-level FST is ~18 MB; revisit if a compact netlist fixture becomes available) |
| Flat-tree row assembly: order/indent/pruning parity with `variablesInTreeOrder`, search filter, 64k flatten <500 ms | **UNIT** (`test/features/signal_tree/utils/signal_tree_rows_test.dart`) |
| Search-filter complexity: scope visits stay linear in scope count on a 200-deep chain, empty query does not traverse, a shared index is not rebuilt | **UNIT** (`test/features/signal_tree/utils/variable_tree_order_test.dart` — "ScopeMatchIndex complexity" group) |
| Flat-tree virtualization: 64k-var scope expansion builds <100 leaf widgets in one interactive frame; alias twins (shared ref / duplicated name) render without duplicate-key crashes | **WIDGET** (`test/features/signal_tree/widgets/signal_tree_panel_test.dart` — "flat lazy tree" group) |
| Frame time targets | **HYBRID** — `test/benchmarks/` captures numbers; absolute thresholds remain MANUAL (CI hardware varies) |
| Parser/render benchmark regression | **WIDGET** (`test/benchmarks/` parser benchmarks + `test/services/render_benchmark/`) |
| Viewport-gated load selects only on-screen signals (+ overscan, dedup, initial-screen estimate) | **UNIT** (`test/features/viewer/rendering/signal_load_planner_test.dart`) |
| LRU eviction keeps the decompressed set bounded, never evicts visible | **UNIT** (`test/features/viewer/rendering/signal_load_planner_test.dart`) |
| Bulk-load progress state machine (begin/advance/clamp/cancel/finish, adding/loading phases, setLoaded) | **UNIT** (`test/features/viewer/providers/signal_load_progress_provider_test.dart`) |
| Chunked bulk add: parity with sync add, single state emission, monotonic progress, all-or-nothing cancel | **UNIT** (`test/features/viewer/providers/signal_group_providers_test.dart` — "addSignalsChunked") + **WIDGET** (`test/features/signal_tree/widgets/scope_tree_node_test.dart` — "Add All in Scope" group) |
| Bulk-added entry ids unique without per-entry UUID cost | **UNIT** (`signal_group_providers_test.dart` — "bulk-added entries all get unique ids") |
| Large-session autosave: worker-isolate compact encode round-trips; normal sessions stay pretty-printed | **UNIT** (`test/services/session/session_service_test.dart` — "large-session save path") |
| Geometry-index window search (binary search, gaps, varying heights, empty/inverted windows) | **UNIT** (`test/features/viewer/rendering/lane_geometry_index_test.dart`) |
| Incremental load lands changes in materialized lanes; above-threshold adds materialize only the viewport window while the scroll extent covers all lanes | **WIDGET** (`test/features/viewer/widgets/waveform_canvas_test.dart` — "viewport-gated lane materialization" pair) |
| Load planner selects window refs from the geometry index (fallback, overscan, dedup, initial-screen estimate) | **UNIT** (`test/features/viewer/rendering/signal_load_planner_test.dart`) |
| Status-bar progress indicator + cancel button (+ locale sweep); indeterminate bar with no count before the batch is sized | **WIDGET** (`test/features/viewer/widgets/signal_load_indicator_test.dart`) |
| Add All in Scope arms the indicator before the scope walk, walks in tree order across event-loop yields, cancels during the walk with nothing added, and arms the adding phase below the chunked threshold too | **WIDGET** (`test/features/signal_tree/widgets/scope_tree_node_test.dart` — "Add All in Scope" group) |
| Canvas loading indicator: a batch under 24 signals shows it after 200 ms, a fast one never does, it takes over an Add All in Scope hold at once, and it leaves an add that is still building alone | **WIDGET** (`test/features/viewer/widgets/waveform_canvas_load_progress_test.dart`) |
| Incremental fill + scroll smoothness on 2000+ signals | **MANUAL** (load a generated scale fixture; perceptual 60 fps) |
| Memory leak detection | **INTEGRATION_TEST** (`integration_test/canvas/scroll_memory_soak_test.dart` — sustained scroll + zoom + pan soak (real run ≈ 5m42s, 800-signal transition-dense fixture) asserting a deterministic loaded-signal-count bound against the `SignalLoadPlanner` eviction ceiling plus a tolerant median-RSS growth canary via the real `MemoryStatsService`. See §13.6.) |
| Statistics strip toggle and gating | **WIDGET** (`test/features/statistics/widgets/live_statistics_strip_test.dart`) |
| Statistics strip session persistence | **WIDGET** (`test/services/session/session_service_test.dart` covers `statisticsStripVisible` round-trip) |

---

## 13A. Waveform canvas rendering goldens (ARCHITECTURE §8.9 Layer 5)

### What it does

This is the **Layer 5** rendering layer from ARCHITECTURE.md §8.9: render a known
waveform file at a fixed zoom and cursor position, rasterise the canvas, and
compare it pixel-for-pixel against a committed baseline PNG. It is the only
layer that catches *rendering* regressions the value-level tests cannot see —
wrong color for x-values, a dropped transition edge, broken bus-parallelogram
geometry, analog-trace interpolation drift, and theme-token regressions (the
canvas background, lane and x/z colors of the `oscilloscope` preset).

The test (`test/features/viewer/rendering/waveform_canvas_golden_test.dart`)
loads each fixture through the **real wellen FFI parser**, builds the canvas
lanes exactly the way `WaveformCanvas` does, renders `WaveformCanvasView` at a
`TimeMapper.fitAll` zoom, and asserts `matchesGoldenFile`. Five baselines are
committed under `test/features/viewer/rendering/goldens/`:

| Golden | Fixture | Theme | Covers |
|---|---|---|---|
| `scalar_basics_dark.png` | `scalar_basics.vcd` | `wavecrux-dark` | scalar (1-bit) traces + an 8-bit bus |
| `vector_formats_dark.png` | `vector_formats.vcd` | `wavecrux-dark` | multi-bit vector/bus parallelograms incl. x/z value periods |
| `analog_real_dark.png` | `analog_real.vcd` | `wavecrux-dark` | analog/real interpolated traces + inline cursor sample |
| `vector_formats_oscilloscope.png` | `vector_formats.vcd` | `oscilloscope` | oscilloscope signal colors + x-state hatch (xnib/znib/mixed_xz) |
| `analog_real_oscilloscope.png` | `analog_real.vcd` | `oscilloscope` | analog traces + inline cursor sample (dot + label in the signal's color) on the oscilloscope canvas |

### Setup

No special setup — the three fixtures already live under `test/fixtures/vcd/`.
The native wellen library must be built (`cd native/wellen_ffi && cargo build
--release`) because the fixtures parse through the real FFI bridge.

### Steps

1. Regenerate baselines after an *intentional* visual change:
   ```bash
   flutter test --update-goldens \
     test/features/viewer/rendering/waveform_canvas_golden_test.dart
   ```
2. Review the regenerated PNGs visually before committing — a baseline is only
   as trustworthy as the eyes that approved it.
3. Run the comparison: `flutter test
   test/features/viewer/rendering/waveform_canvas_golden_test.dart`.

### Platform sensitivity (important)

Golden PNGs are platform-specific: font hinting and shape anti-aliasing differ
per OS, so a baseline rendered on one platform will not byte-match another. The
comparison therefore runs **only on macOS** — the canonical baseline platform
for this repo — and only when the native library is present (mirroring
`fsm_golden_test.dart`'s dylib probe). On Linux/Windows and on hosts without the
native library the comparison is skipped so the suite stays green; CI's
**macOS `test` job** is the one that exercises these goldens. If the baselines
are ever regenerated on a different host, re-run `--update-goldens` on macOS
before committing.

### Edge cases

| Case | Expected |
|---|---|
| Native library not built | Test skips (no false red); regenerate on a machine with the dylib |
| Run on Linux/Windows | Comparison skipped (baselines are macOS-rendered) |
| Intentional palette/painter change | `--update-goldens`, eyeball the diff, commit the new PNGs |
| Unintended geometry/color regression | Comparison fails with a `*_testImage.png` / `*_masterImage.png` diff pair under the goldens dir |

### Automation Assessment

| Test | Coverage | Rationale |
|---|---|---|
| Scalar + 8-bit bus render (dark) | **WIDGET** (`test/features/viewer/rendering/waveform_canvas_golden_test.dart` → `scalar_basics_dark.png`) | Pixel baseline of the scalar/bus painters; macOS-gated, native-FFI-gated. |
| Multi-bit vector parallelograms incl. x/z (dark) | **WIDGET** (same → `vector_formats_dark.png`) | Bus parallelogram geometry + x/z value-period rendering. |
| Analog/real interpolated traces (dark) | **WIDGET** (same → `analog_real_dark.png`) | Analog trace interpolation + inline cursor sample. |
| Oscilloscope preset — canvas + x/z colors | **WIDGET** (same → `vector_formats_oscilloscope.png`) | Verifies the `oscilloscope` background, lane and `signal.x.fill`/`signal.x.hatch`/`signal.z.line` tokens against a baseline. Bus value labels take each signal's color. |
| Oscilloscope preset — analog + inline cursor sample | **WIDGET** (same → `analog_real_oscilloscope.png`) | Analog traces and the inline value dot + label at the primary cursor (both in the signal's color) on the preset's canvas. The cursor line and the ruler are separate layers; their token colors are covered by `test/features/viewer/widgets/canvas_theme_tokens_paint_test.dart`. |
| Cross-platform pixel identity (Linux/Windows match) | **MANUAL** | Goldens are baselined on macOS only; cross-OS byte-match is not a goal (font hinting/AA differ). |
| 1-bit scalar `x`/`z` hatch specifically | **MANUAL — pending fixture** | The three named fixtures carry x/z only as *vectors*; a 1-bit scalar x/z baseline needs a dedicated fixture (not added — would deviate from the existing-fixture scope). |

---

## 14. Edge cases and break-it tests

### 14.1 Empty VCD

A VCD with zero signals (regenerable from `helpers/`).

1. Load. File Info: signal count = 0, transition count = 0, parse time shown.
2. Decoder picker: disabled, or shows decoders but has no signals to bind.
3. Signal Health: all counts zero ("no issues found").

### 14.2 X/Z-only signals

A VCD with undriven wires, X-only signals, Z-only signals.

1. Load. Signal Health → run analysis.
2. Verify undriven wire flagged "X/Z-only".
3. Verify driven signal NOT flagged.
4. File Info: signals by type/direction reflects the undriven wire correctly.

### 14.3 Decoder on wrong signals

1. Load `protocol/uart/generated/uart_basic.vcd`. Configure SPI decoder, binding `tx` to SCLK, leaving MOSI/MISO/CS unbound.
2. Verify: no transactions or meaningless results — but no crash, exception, or hang.

### 14.4 Remove and re-add decoder

1. Load `protocol/spi/generated/spi_basic.vcd`, add SPI decoder, verify it works.
2. Remove the decoder. Verify overlay lane disappears, transaction table empties.
3. Add SPI decoder again with same bindings. Verify transactions return identically.

### 14.5 Open new file with analysis state active

1. With diff active (or X-Trace, or pattern search, or switching activity, or FSM), open a new VCD without explicitly closing the current one.
2. Verify ALL analysis states clear cleanly.

### 14.6 Malformed VCD files

Run against `test/fixtures/vcd/malformed_value_change.vcd` and any other
malformed fixtures acquired through the `test/fixtures/real_world/` provenance
process:

- Each malformed file should produce a clear error, not a crash.
- Where the parser can recover partial data, verify it does and surfaces what it has.

> The FastWaveBackend corpus previously cited here was removed 2026-07-31 —
> its files were harvested from ~40 third-party repositories with no stated
> license, which the fixture allow-list in
> `test/fixtures/real_world/README.md` does not permit. See `NOTICES` §15.
> Widening malformed-VCD coverage means acquiring new files through that
> process, with `.provenance.json` sidecars.

### 14.7 Tool-specific VCDs

Run against the vendor-specific files in `test/fixtures/real_world/` (Aldec, Cadence, Mentor, Synopsys, Verilator):

- Verify each opens without errors.
- Verify File Info reports sensible values.
- Verify direction metadata appears for files that have it (Verilator FST), absent for files that don't (most VCDs).

### 14.8 Deep hierarchy and identifier edge cases

1. Load `vcd/deep_hierarchy.vcd`. Verify the signal tree expands correctly through 10+ levels.
2. Load files with VCD identifier codes spanning the full printable ASCII range — verify all signals load with correct values (verify against the `expected.json` companions).

### 14.9 Automation Assessment

| Test | Coverage |
|---|---|
| Empty VCD (counts = 0, no crash) | **WIDGET** (`test/services/waveform/` covers parser empty-VCD case) |
| X/Z-only signals flagged in Signal Health | **WIDGET** (`test/services/diagnostics/` signal-integrity tests) |
| Decoder on wrong signals: no crash | **WIDGET** (each `test/services/decoders/*_test.dart` includes a "wrong bindings" robustness test) |
| Remove + re-add decoder → same transactions on second add | **WIDGET** (`test/features/decoders/providers/active_decoders_provider_test.dart` — "remove + re-add decoder → same transactions on second add") |
| Open new file with diff/X-Trace/pattern-search/switching-activity/FSM active → ALL clear | **WIDGET** (`test/features/viewer/providers/waveform_source_provider_test.dart` — "openFile clears X" + "close clears X" cases for all 5 features) |
| Malformed-VCD corpus | **WIDGET — pending** (the full-corpus parser-robustness test is not yet committed under `test/services/waveform/`. Closing requires (a) acquiring malformed fixtures through the `test/fixtures/real_world/` provenance process — allow-listed license plus a `.provenance.json` sidecar — and (b) writing a parameterized test that loads each file and asserts no crash. The FastWaveBackend corpus formerly named here was removed 2026-07-31 as unlicensed; see `NOTICES` §15.) |
| Vendor-specific corpus (Aldec/Cadence/Mentor/Synopsys/Verilator) | **WIDGET — pending** (same shape as above; the `real_world/` zoo already covers part of this matrix) |
| Deep hierarchy (10+ levels) expands correctly | **WIDGET** (`test/services/waveform/` parser; tree expansion `test/features/signal_tree/widgets/`) |
| Identifier edge cases (full ASCII range) | **WIDGET** (`test/services/waveform/` parser tests against `identifier_edge_cases.vcd`) |

---

## 15. Cross-feature integration

### 15.1 All Open Core decoders simultaneously

Load a VCD that exercises multiple protocols. Add SPI, I²C, UART, AXI4-Lite, APB decoders simultaneously. Verify:

- All transaction lanes render.
- The transaction table shows transactions from all decoders.
- Filter-by-decoder correctly narrows.
- Tap-to-jump works on each lane.

### 15.2 Decoder + analysis features

With a decoder active:

1. Run waveform diff against a second file — diff and decoder coexist.
2. Run X-Trace on an X-valued signal — both panels populate.
3. Run pattern search — patterns can reference signals being decoded.

### 15.3 Stage + FSM + RTL source on desktop

On desktop, open Stage panel + FSM panel + RTL source annotation panel simultaneously. Verify all three work, layout is reasonable, performance holds.

> **Layout-slot note (for the automated test).** The Stage panel and the FSM panel share the single per-pane **bottom-dock** slot via the priority chain Stage > FSM > X-Trace > … (see `ViewerScreen._buildBottomPanelContent`), so two of them cannot occupy that one slot in the same pane at the same instant. The RTL source panel lives in the **right** slot, so Stage (bottom) + RTL (right) are genuinely simultaneous. `stage_fsm_rtl_coexistence_test.dart` verifies Stage + RTL co-mounted, the FSM panel rendering in the shared dock slot, all three features concurrently active with no interference, and cursor-scrub propagation to all three.

### 15.4 Mobile with all features active

On tablet (iPad), load a file, add signals, open Stage, open FSM. Verify the layout remains usable.

### 15.5 Baseline regression

Run the parser benchmark and render benchmark against baselines from earlier releases. New optimizations should not have introduced regressions in any earlier feature.

### 15.6 Session round-trip including statistics-strip and panel state

Save a session with Stage active, FSM panel open, statistics strip expanded, multiple decoders bound, custom panel sizes. Reload. Verify all of the above are restored, and a diagnostics report taken before save matches the post-reload state's structure.

### 15.7 Automation Assessment

| Test | Coverage |
|---|---|
| Multi-decoder simultaneous correctness | **INTEGRATION_TEST** (`integration_test/coexistence/multi_decoder_coexistence_test.dart` — SPI + I²C decoders on a combined bus, per-decoder counts match the expected companions, panning preserves both. A second scenario in the same file generalizes this to **all 5 open-core decoders simultaneously** — SPI, I²C, UART, AXI4-Lite, APB — against `protocol/multi/all5_basic.vcd` (generated by `tool/generate_multi_coexistence_fixture.dart`'s `_generateAllFiveFixture`), asserting each decoder's transaction count matches its own expected companion and that panning doesn't drop/duplicate any of the 5, satisfying §15.1 above) |
| Decoder + diff coexistence | **INTEGRATION_TEST** (`integration_test/coexistence/decoder_diff_coexistence_test.dart` — SPI overlay survives entering diff mode; matched signals + divergence times + XOR traces all present) |
| Decoder + X-Trace coexistence | **INTEGRATION_TEST** (`integration_test/coexistence/decoder_xtrace_coexistence_test.dart` — X-Trace on an x signal alongside an active SPI decoder; X-Trace panel renders in the dock, SPI decode untouched) |
| Decoder + pattern search coexistence | **INTEGRATION_TEST** (`integration_test/coexistence/decoder_pattern_search_coexistence_test.dart` — `sclk == 1` pattern search produces match ranges alongside an intact SPI overlay) |
| Stage + FSM + RTL on desktop | **INTEGRATION_TEST** (`integration_test/coexistence/stage_fsm_rtl_coexistence_test.dart` — Stage (bottom dock) + RTL (right slot) render simultaneously, FSM concurrently active and its panel renders in the shared dock slot, cursor scrub updates all) |
| Tablet with Stage + FSM | **INTEGRATION_TEST** (`integration_test/coexistence/tablet_stage_fsm_test.dart` — 1024×768 tablet class, Stage docked + FSM active share the per-pane dock slot, no overflow, scrub updates both) |
| Cross-feature panel layouts | **MANUAL** (visual judgement; golden infra not yet set up) |
| Performance regression vs baseline | **WIDGET** (`test/benchmarks/` parser benchmarks); absolute thresholds **HYBRID** |
| Session round-trip with full state (Stage + FSM + statistics strip + multiple decoders + custom panel sizes) | **INTEGRATION_TEST** (`integration_test/coexistence/composite_workspace_round_trip_test.dart` — a 2-tab / 2-pane workspace round-trip). **Passing** (verified green 2026-06-11). FSM annotations now serialize and restore through the session layer — `session_providers.dart` reads `fsmAnnotationProvider` into the snapshot (`fsmAnnotations:`) and calls `restoreFromSession(...)` on reopen — so the FSM-annotation assertion survives close → re-open. The earlier "currently failing / no `fsmAnnotation` wiring" note was stale; the wiring landed and the assertion holds. **Decoders added**: the scenario now also activates an I²C decoder on tab A and a UART decoder on tab B before save, and asserts both survive the round-trip with `decoderId` / `instanceNumber` / `config.signalBindings` intact — closing the "multiple decoders bound" gap in the scenario's own description, which previously had no decoder coverage at all (`decoder_restore_on_open_test.dart` covers decoder restore standalone, against a genuine multi-bus fixture, but not inside this composite multi-tab/multi-pane scenario). |

---

## 16. Workspace and file lifecycle

> Baseline workflows that surround the waveform canvas. These are the first things a new user touches — if they're broken, nothing else matters.

### 16.1 Empty-canvas state and recent files

> **Supersession.** The Welcome screen that previously lived here is retired. Emptiness is now a *state* of the workspace, not a route: when the workspace contains zero tabs the `EmptyCanvasState` widget renders inside [`ViewerScreen`]'s body — the toolbar, menu bar, status bar, and command palette continue to render around it so Settings, the diagnostics surfaces, and the command palette remain reachable without opening a file. The active reference for new test runs is §22.9.1; this section is preserved for backwards traceability of the recent-files behaviour that survived the Welcome-screen retirement.

#### 16.1.1 What it does

The empty-canvas state is what the user sees at app launch when the workspace contains zero tabs. It surfaces an "Open File…" button, an "Open Workspace…" button (tablet + desktop only), a "Recent files" list (consuming `recentFilesNotifierProvider`), a "Recent workspaces" placeholder section, and a web drag-and-drop zone (Flutter Web only). On the desktop apps the whole window accepts dropped files instead (§8.8). On mobile, the "Open File…" button still routes through the system document picker.

#### 16.1.2 Steps

1. Launch WaveCrux with no file argument and an empty workspace. Verify the empty-canvas state renders in the body, with the toolbar / menu bar / status bar rendered around it. The Welcome screen route is gone — no separate `/welcome` URL. **(0.2.5)** Verify a muted **"Version X.Y.Z"** line renders under the header subtitle (the only always-visible version surface on web, where no native menu bar hosts About); it must show the real running version in all four locales. `[Coverage: WIDGET]` (`wavecrux_empty_canvas_test.dart` — "shows the running version").
2. Click "Open File…" → verify the platform file picker opens. Pick a VCD → verify the empty-canvas state is replaced by the viewer with the file loaded in a freshly created tab.
3. Close the tab via Cmd/Ctrl+W. Verify the empty-canvas state returns (the tab list is empty) and the just-opened file is now at the top of the recent files list.
4. Open 5+ different files in sequence. Verify the recent list bounds itself to ≤10 and shows them in most-recent-first order.
5. Click a recent file entry → verify it loads in a new tab.
6. Click a recent file entry **whose underlying file has been deleted** from disk → verify a clear error snackbar appears and the entry is either flagged stale or removed from the list.
7. Drag a `.vcd` / `.fst` / `.ghw` / `.wavecrux` file from the OS file manager onto the empty-canvas state → verify the drop overlay appears while dragging and the file loads in a new tab on release (desktop: §8.8; web: the drop zone).
8. On mobile, verify the empty-canvas state routes file-open through the system document picker (not a desktop-style modal picker).
9. From the empty-canvas state, press `Cmd+,` / `Ctrl+,` → Settings opens. Press `Cmd+Shift+P` → command palette opens. Both work without first opening a file.

#### 16.1.3 Edge cases

- Recent file list with paths containing spaces, Unicode, very long names — render correctly.
- Open the same file twice in a row — entry doesn't duplicate.
- Drag a non-waveform file onto the empty-canvas state — it opens into the tab's "Failed to load waveform" error, never a silent no-op (desktop, §8.8).
- **Issue 29 (per-tab sidecar leakage):** open the app with restored tabs from a prior session so the workspace-restore path runs `SessionNotifier.loadFromPath` against each tab's per-tab session sidecar at `{appSupportDir}/sessions/{tab-uuid}.json` (the sidecar is written through the base `crux_workspace` `WorkspaceService`, whose default extension is `.json` — **not** `.wavecrux`). Verify the Recent Files list **does not** gain a UUID-named entry per restored tab — sidecar paths are rejected by `RecentFilesNotifier.addFile` (and any previously-persisted sidecar entries are stripped on next launch by the cleanup branch in `build()`). The `RecentFilesNotifier` guard matches `…/sessions/{uuid}.<ext>` generically, so it catches the real `.json` files; a regression where the guard was pinned to `.wavecrux` silently let the `.json` sidecars leak back in. The Recent Files list must continue to show only user-opened waveform / `.wavecrux` / `.gtkw` files (see §22.9.1.1).

#### 16.1.4 Automation Assessment

| Test | Coverage |
|---|---|
| `EmptyCanvasState` renders when the workspace has zero tabs | **WIDGET** (`test/features/workspace/widgets/empty_canvas_state_test.dart`, `test/features/viewer/screens/viewer_screen_test.dart`) |
| Recent-files data path renders persisted entries | **WIDGET** (`test/features/workspace/widgets/empty_canvas_state_test.dart`) |
| Recent-files empty-state hint renders | **WIDGET** (`test/features/workspace/widgets/empty_canvas_state_test.dart`) |
| Recent-workspaces placeholder hint renders | **WIDGET** (`test/features/workspace/widgets/empty_canvas_state_test.dart`) |
| Open-File / Open-Workspace buttons fire their callbacks; no New-Tab affordance is rendered | **WIDGET** (`test/features/workspace/widgets/wavecrux_empty_canvas_test.dart`) |
| Open-Workspace hidden on phone device class | **WIDGET** (same file) |
| Touch-target compliance ≥ 44 × 44 dp on phone widths | **WIDGET** (same file — Open-File button hit area) |
| 320 × 568 dp surface has no `RenderFlex` overflow | **WIDGET** (same file) |
| Locale sweep (en / zh_CN / ja / ko) renders without exceptions | **WIDGET** (same file) |
| Drag-and-drop on empty-canvas state (desktop) | **WIDGET** + **INTEGRATION_TEST** (`test/features/viewer/screens/viewer_screen_file_drop_test.dart`; `integration_test/workspace/empty_canvas_drag_drop_test.dart` via the plugin channel). The OS drag itself is **MANUAL** — §8.8 |
| Drag-and-drop on empty-canvas state (web) | **INTEGRATION_TEST** (`integration_test/web/web_drag_drop_test.dart` — exercises the `WebDropZone.onFilesDropped` integration boundary; the underlying DOM `dragover`/`drop` listener is covered by unit tests on `web_drop_target_impl.dart`). |
| Stale recent-file entry handling | **WIDGET** (`test/features/workspace/providers/recent_files_provider_test.dart` — covers the data-layer remove path; user-facing snackbar remains **MANUAL** until the empty-canvas error-surface lands as a follow-up) |

---

### 16.1.5 Cold-start tab restoration — lazy mount + deferred load

#### 16.1.5.1 What it does

When `restoreTabsOnLaunch` is enabled, a cold start re-opens the tabs from the
last workspace. To stay within the host GPU driver's limits, restoration now
**only loads the active tab of each pane up front** and **mounts only the
active tab's content**; every other restored tab appears immediately as a tab
**chip** but loads + renders its waveform the first time you click it (then
stays loaded — switching back is instant). Each restored tab brings up its own
GPU-backed content (signal canvas, Stage/Rive board widgets); mounting them all
at once fanned out concurrent GPU surface/shader initialization that, on some
Windows + Intel integrated-GPU machines, silently terminated the process with no
Dart error and no crash dialog (`ExitProcess(0x8F)` from a DirectX driver
thread). The fix is the `LazyIndexedStack` pane host
([`lib/shared/widgets/lazy_indexed_stack.dart`]) plus deferred per-tab loading
in `_WaveCruxAppState._restoreFromWorkspace` / `_ensureTabLoaded`
([`lib/app.dart`]). The analysis is kept with the Pro overlay.

Deferring *across* tabs is not sufficient on its own: a **single** restored tab
whose Stage panel wires a **board widget** (e.g. Nexys A7) brings up a fourth
GPU-backed view — the board's bound slots rebuild into LED/segment content the
moment the restored signals settle, i.e. right as the signal-tree / canvas /
value-column restoration lands — and that count is what tips the race into the
50–100% zone. So the active tab additionally serializes the Stage board out of
that burst via `stageStartupRenderGateProvider`
([`lib/features/stage/providers/stage_startup_render_gate_provider.dart`]): the
app shell **engages** the gate at the start of a guarded restore and
**releases** it on the same content frame the restore guard stands down (§16.1.7),
after which the Stage instances build on their own frame. While engaged the
Stage instance canvas paints a lightweight placeholder spinner instead of the
board. The gate defaults to released, so normal Stage usage (opening a panel
mid-session) is unaffected.

#### 16.1.5.2 Steps

1. Open **8–10 waveform files** (mix in a couple of Stage *board* tabs — e.g.
   Nexys A7 / Basys 3 — alongside protocol/signal tabs), arrange them across
   **two split panes**, then quit so the workspace persists.
2. Relaunch (cold start). Verify the app comes up **without crashing**, all tab
   **chips** are present in both panes, and the active tab of **each** pane is
   rendered with its waveform.
3. Confirm deferred loading: a background (never-clicked) tab's waveform is not
   loaded yet — its canvas is empty/loading until you click it. (Diagnostics →
   Memory per-tab breakdown shows "—" for not-yet-loaded tabs.)
4. Click through every restored tab in turn. Each loads + renders on first
   activation (a brief load is acceptable); switching back to an
   already-visited tab is instant (kept alive). No tab loses scroll / zoom /
   cursor / signal arrangement across switches (that state lives in per-tab
   providers).
5. Verify **every panel** works on each visited tab: signal tree, value column,
   waveform canvas, transaction/Stage panels, status bar — no exceptions, no
   blank panels.

#### 16.1.5.3 Edge cases

- **Drag-reorder** restored tabs within a pane — already-mounted tabs are not
  torn down / re-mounted (no flicker), and a never-activated tab is not forced
  to mount by the reorder.
- **Single-tab / single-pane** restore behaves exactly as before (the one tab
  is the active tab → it loads + mounts immediately).
- **Single tab with a Stage board** (e.g. Nexys A7 wired on the Stage): on
  restore the Stage panel briefly shows a placeholder spinner while the
  signal-tree / canvas / value-column restoration completes, then the board
  builds on the following frame (the `stageStartupRenderGateProvider`
  serialization). On affected Windows/Intel hardware this is the case that
  previously crashed reload ~100%. Verify the tab now restores **without
  crashing** and the board renders with correct bound values once the spinner
  clears.
- A restored tab whose file was **deleted on disk** is dropped from the restore
  set (existing behaviour) and never attempts a deferred load.
- `restoreTabsOnLaunch` **disabled** → no tabs restore (empty-canvas state),
  and the deferred-load listener is never installed. This holds even when a
  file is opened on launch (below): the hydrated chips are reconciled away and
  only the opened file shows.
- **Open a file *after* restore** (File→Open, recent files, drag-drop, or a
  second `wavecrux file.vcd` launch while a workspace was restored): the new
  file loads **exactly once**, by its own open path. The deferred-load listener
  owns only the restored tabs — it must NOT also load a freshly-opened tab.
  Regression guard: before the fix the listener re-fired on the new tab's
  activation (which happens *before* the opener flips the source to loading),
  starting a **second concurrent load** on the same per-tab notifier; the two
  loads tore down each other's wellen isolate and could strand the canvas on the
  **loading spinner forever**. Verify any newly-opened file reaches its waveform
  (no permanent spinner), and restored tabs still load on first click.
- **Launch with a file while a workspace is saved** (double-click a `.vcd` in
  Finder / `wavecrux sim.vcd`): the saved tabs **restore** (deferred-loaded as
  above) **and** the opened file is added as the **active** tab —
  non-destructive "restore session + add file". The saved tabs are NOT replaced
  and do NOT appear as orphan chips. If the opened file is already one of the
  saved tabs it is **focused** (de-duplicated), not opened a second time. The
  first positional file ends active even with extra `wavecrux a.vcd b.vcd` args.
  (Internally: `_restoreFromWorkspace` runs on every cold start and `ViewerScreen`
  opens the file after the `startupReconcileProvider` barrier completes.)

#### 16.1.5.4 Automation Assessment

| Test | Coverage |
|---|---|
| `LazyIndexedStack` mounts only active + previously-activated children; keep-alive; reorder/add/remove by key | **WIDGET** (`test/shared/widgets/lazy_indexed_stack_test.dart`) |
| Stage startup render gate: engage/release/default | **UNIT** (`test/features/stage/providers/stage_startup_render_gate_provider_test.dart`) |
| Stage instance canvas defers to a placeholder while gated, builds instances when released | **WIDGET** (`test/features/stage/widgets/stage_panel_test.dart`) |
| Single-tab Stage-board restore serialized out of the burst → no render-time GPU crash on affected hardware | **MANUAL** (real GPU-driver race; not reproducible headless) |
| Cold-start restores all tab entries + active-tab pointer; live mutation round-trips | **INTEGRATION_TEST** (`integration_test/tabs/startup_restoration_test.dart`) |
| Launch with a file + saved workspace: saved tabs restored + file added active (new file), file focused not duplicated (existing file), only-the-file when `restoreTabsOnLaunch` off | **INTEGRATION_TEST** (`integration_test/workspace/cli_file_merges_workspace_test.dart`); barrier provider unit-covered by `test/core/startup_reconcile_provider_test.dart` |
| Open a file after restore loads it exactly once — the deferred-load listener does not start a second concurrent load that strands the canvas on a permanent spinner | **INTEGRATION_TEST** (`integration_test/workspace/open_after_restore_no_double_load_test.dart`) |
| 2 panes × 10 tabs (20 files): deferred load (only active tabs loaded at restore), visit-all loads on demand, all signals displayed, every panel renders without error, no crash | **INTEGRATION_TEST** (`integration_test/tabs/multi_tab_pane_stress_test.dart`) |
| Drag-reorder does not re-mount / crash semantics | **INTEGRATION_TEST** (`integration_test/tabs/tab_drag_reorder_test.dart`) + **WIDGET** (`test/features/viewer/screens/viewer_screen_test.dart` cross-pane reparent) |
| GPU-crash regression (Windows + Intel) — concurrent multi-tab GPU init | **MANUAL** (timing-/driver-specific; the 20-tab stress integration test is the proxy, plus the documented relaunch-loop repro kept with the Pro overlay) |

---

### 16.1.6 Tab-chip parity after the crux_workspace widget swap

#### 16.1.6.1 What it covers

The widget swap moved the tab strip onto the cross-suite
`crux_workspace` `ViewerTabBar`. The `crux_workspace 0.4.0` parity seams
(`contextMenuBuilder`, `tabTooltipBuilder`, `useDragHandle: false`,
`paneBorderBuilder`, `WorkspaceNotifier.reorderTabInPane`) keep every
user-visible chip behaviour identical to the pre-swap local widget. Verify
none of the following regressed.

#### 16.1.6.2 Steps

1. Open a file-backed tab. **Hover the chip label** (desktop): the tooltip
   shows the **full file path**, not just the display name.
2. **Right-click the chip** (long-press on touch). The menu order is: a
   non-interactive **monospace full-path header** (per §3.1.8.14), **Duplicate
   Tab**, **Move to New Window** (disabled, with the "multi-window stable"
   tooltip), **Reveal in Finder/Explorer/Files** (label matches the host OS),
   then — when diagnostics are enabled on tablet/desktop — **Tab Diagnostics**,
   then **Close Tab** / **Close Other Tabs** / **Close Tabs to the Right**
   (the last two gated by tab count/position).
3. **Hover the chip's × button**: the tooltip reads "Close <tab name>" (the
   name-bearing form), not a generic "Close tab".
4. **Drag a chip** anywhere on its body to reorder — there is **no separate
   drag-handle icon**; the whole chip is the drag affordance. A thin insertion
   bar appears, including a **leading slot before the first chip** so a tab can
   be dropped at the very front (reachable past the frameless left resize
   edge on Linux).
5. **Split-pane reorder (regression):** split into two panes with ≥3 tabs in
   the **second** pane. Drag a tab within the second pane to a middle position
   and confirm it lands exactly where dropped (the global tab order stays
   consistent with the visible per-pane order). Pre-0.4.0 this dropped at the
   wrong index because the pane-local index was fed to the global reorder.
6. **Active-pane border:** with a split workspace, the **focused** pane shows a
   full-strength primary border (3 dp); the unfocused pane keeps a faint
   `outlineVariant` divider (not invisible). Click into the other pane and
   confirm the accent follows focus.
   - **Un-split suppression (Issue #46):** with a **single** pane (workspace
     not split), there must be **no** active-pane border at all — the indicator
     communicates nothing when there is no second pane to disambiguate (matches
     VS Code / JetBrains). Confirm the content area has no accent ring around
     it. Split into two panes and confirm the focused pane's border appears;
     un-split and confirm it disappears again.
   - **No content squeeze on focus switch (Issue #45):** click back and forth
     between the two panes and watch the waveform canvas / signal tree. The
     content must **not** shift or "breathe" as focus moves — the border width
     is locked at 3 dp for both the active and inactive states (only the colour
     changes). The pre-fix code grew the active border from 1 dp to 3 dp,
     consuming 2 dp of content per side and visibly squeezing both panes on
     every focus switch. Because the un-split (single-pane) border is a
     transparent 3 dp band, opening a second pane must not shift content either.

#### 16.1.6.3 Automation Assessment

| Test | Coverage |
|---|---|
| `reorderTabInPane` maps pane-local → global index in a split | **UNIT** (`crux_workspace` `viewer_tab_bar_parity_seams_test.dart`) |
| `contextMenuBuilder` / `useDragHandle` / leading slot / `tabTooltipBuilder` / `closeTabTooltipFor` seam mechanics | **WIDGET** (`crux_workspace` `viewer_tab_bar_parity_seams_test.dart`) |
| `paneBorderBuilder` overrides the per-pane border (incl. the `isSplit` seam) | **WIDGET** (`crux_workspace` `pane_host_seams_test.dart`) |
| Un-split suppresses the border; split locks 3 dp on both panes & accents only the active one (Issues #45/#46) | **WIDGET** (`test/features/panes/widgets/wavecrux_pane_host_test.dart` — "un-split: the pane border is suppressed (transparent)" + "split: borders are 3 dp on both panes (no squeeze) …") |
| WaveCrux wiring: full-path header + close actions + name-bearing close tooltip + leading slot | **WIDGET** (`test/features/panes/widgets/wavecrux_pane_host_test.dart`) |
| Reveal action actually opening the OS file browser | **MANUAL** (the in-app handler is a no-op stub; production reveal is OS-level) |

---

### 16.1.7 Session recovery — crash-loop breaker, `--reset` / `--no-restore`, and the recovery banner

#### 16.1.7.1 What it does

A session so badly behaved that it crashes or hangs the app *while reopening a
waveform* would otherwise wedge every launch. WaveCrux now recovers three ways:

- **Automatic crash-loop breaker (all platforms).** Just before the cold-start
  restore reopens the previously-active waveform — the one launch operation that
  can crash or hang — a sentinel file (`{appSupportDir}/restore_in_progress`) is
  written, then deleted only **after the restored content has actually been
  rendered** (two frame boundaries past the data load), not merely once the file
  finished loading. This ordering is load-bearing: the Windows/Intel
  GPU-surface crash (`docs/flutter-windows-gpu-crash-issue.md`) fires on the
  raster thread while the canvas and any restored **Stage** widgets create their
  render surfaces — *after* the load future resolves. Disarming at load
  completion (the prior behaviour) cleared the sentinel before that crash could
  happen, so a reload that wedged in render escaped the breaker and crash-looped.
  If the next launch
  finds the sentinel still present (a crash, or a *hang* that the user
  force-quit — neither runs the cleanup), it **suppresses the auto-load**: the
  restored tab **chips still appear** (nothing is lost or deleted) but no
  waveform is auto-opened, and the recovery banner is shown. This is the only
  recovery path on **mobile**, where there is no command line. See
  `RestoreGuardService` ([`lib/services/session/restore_guard_service.dart`]).
- **`--reset` / `--no-restore` CLI flags (desktop).** `--no-restore` skips the
  auto-load for one launch without deleting anything (the non-destructive first
  thing to try). `--reset` clears all saved session state — `workspace.json`,
  every per-tab sidecar, and the legacy `last_session.json` — then launches
  empty. Both implemented in `parseCliArgs` ([`lib/services/cli/cli_args.dart`])
  and handled in `bootstrap()` ([`lib/app.dart`]); `--reset` runs the shared
  `resetPersistedSessionData` helper before workspace hydration. Neither touches
  settings, the keymap, or recent files.
- **The recovery banner** (`RecoveryBanner` / `RecoveryBannerHost`,
  [`lib/features/workspace/widgets/`]). A top strip shown on a recovering launch:
  - *interrupted* → "WaveCrux didn't reopen your last session because the
    previous launch didn't finish." with **Open last session** (performs the
    held-back load on demand), **Reset**, and dismiss.
  - *workspace corrupt* → shown when `workspace.json` was unreadable and was
    quarantined to `workspace.json.corrupt-<timestamp>` (the existing
    `WorkspaceService` quarantine, now surfaced via `takeRecovery()`); only
    **Reset** / dismiss (there is nothing to reopen).

The in-app reset (banner **Reset** and **Settings → File handling → Reset
workspace & sessions**, button key `settingsResetSessionButton`) funnels through
the same `runResetWorkspaceCommand`, which clears the live workspace **and** the
on-disk artifacts — identical to `--reset`.

#### 16.1.7.2 Steps

1. **`--no-restore`:** with a multi-tab workspace saved, launch
   `wavecrux --no-restore`. Verify the app comes up to the **empty canvas with
   tab chips present** but no waveform auto-opened; nothing on disk changed
   (relaunch without the flag restores normally).
2. **`--reset`:** launch `wavecrux --reset`. Verify the app comes up to a
   **clean empty workspace**, stdout prints the cleared-state confirmation, and
   `workspace.json` + the `sessions/` dir are gone from the app-support
   directory — but `app_settings`, the keymap, and recent-files history remain.
3. **Crash-loop breaker (simulate):** with a workspace saved, launch and
   **force-quit during the initial load** (kill the process before the waveform
   finishes). Relaunch normally: verify the **recovery banner** appears
   ("…previous launch didn't finish"), the tab chips are present, no waveform
   auto-opened, and **Open last session** loads the previous active waveform.
   Confirm the sentinel is cleared after this launch (a *second* normal relaunch
   auto-restores as usual).
4. **Banner Reset:** trigger the banner (step 3), tap **Reset**, confirm the
   dialog → the workspace empties and all saved session state is cleared.
5. **Settings reset:** Settings → File handling → **Reset workspace & sessions**
   → confirm → same outcome as step 4. Verify this is reachable on **mobile**
   (there is no CLI there).
6. **Workspace-corrupt banner:** hand-corrupt `workspace.json` (write
   non-JSON), relaunch. Verify the app starts empty, the banner shows the
   *corrupt* message (no **Open last session** action), and the original bytes
   are preserved at `workspace.json.corrupt-<timestamp>`.

#### 16.1.7.3 Tier-gate scenarios

Open Core feature — no tier gate. The CLI flags, crash-loop breaker, banner, and
Settings reset behave identically under `kBetaPeriod = true` and
`kBetaPeriod = false`; none consult `licenseTierProvider`.

#### 16.1.7.4 Edge cases

- **Hang vs. crash:** both leave the sentinel armed (cleanup runs only on a
  rendered frame), so both trigger the breaker next launch.
- **Render-time crash (GPU / Stage reload):** a session that loads fine but
  crashes the process *during render* — e.g. a tab with a Stage panel wiring a
  board widget (Nexys A7) that trips the concurrent-GPU-init crash on
  Windows/Intel — is caught because disarm waits for a rendered content frame,
  not just the completed load. Regression guard for the prior bug where disarm
  fired at load completion and let this class crash-loop. Verify by reloading
  such a session on affected hardware: at most **one** crash, then the next
  launch recovers via the banner (it does not crash again).
- **False trip:** force-quitting a *slow-but-fine* load shows the banner once on
  the next launch; **Open last session** (or simply relaunching again) restores
  normally — nothing was deleted.
- **`--reset` + `--no-restore` together:** `--reset` wins (state is cleared, so
  there is nothing to skip); launches empty.
- **Web:** no on-disk session — the guard, reset, and flags are all no-ops; the
  banner never shows.
- **Banner renders above the Navigator (no Overlay ancestor):** the strip is a
  sibling of the routed content in `MaterialApp.builder`, so the Navigator's
  `Overlay` is *not* an ancestor. The banner must therefore use no
  `Overlay`-dependent widgets — a `Tooltip` on the dismiss button threw
  "No Overlay widget found" the instant a recovery launch tried to render it
  (the dismiss now carries a `Semantics` label instead). Regression guard:
  `recovery_banner_test.dart` pumps the banner with no `Overlay` ancestor and
  asserts no exception. Verify the recovery banner actually appears (not a red
  error screen) on an interrupted relaunch.
- **Reset from the banner needs a Navigator context too:** for the same
  above-the-Navigator reason, the banner's **Reset** confirmation `showDialog`
  cannot use the host's own context (no `Navigator` ancestor → "Navigator
  operation requested with a context that does not include a Navigator", and the
  button silently did nothing). The host drives `runResetWorkspaceCommand` from
  `rootNavigatorKey.currentContext` instead. Verify **Reset** on the recovery
  banner opens the confirm dialog and, on confirm, empties the workspace.
  Regression guard: `recovery_banner_host_test.dart` taps Reset with the host
  mounted above a Navigator and asserts the dialog appears.
- **`--reset` with no saved state:** no-op, launches empty, no error.

#### 16.1.7.5 Automation Assessment

| Test | Coverage |
|---|---|
| `--reset` / `--no-restore` parsing + help text | **UNIT** (`test/services/cli/cli_args_test.dart`) |
| `resetPersistedSessionData` clears workspace.json + sidecars + manifest, keeps unrelated files, no-op when empty | **UNIT** (`test/services/session/session_reset_test.dart`) |
| Sentinel arm/disarm/`wasInterrupted`, survives across "launches", read-only detect | **UNIT** (`test/services/session/restore_guard_service_test.dart`) |
| Disarm waits for a rendered content frame (two frame boundaries past load), so a render-time/GPU crash still leaves the sentinel armed | **MANUAL** (timing of an app-level side effect during cold-start render; not reproducible in a headless test — the underlying crash is a real GPU-driver race) |
| `StartupRecovery.configure` + `StartupRestoreResume` one-shot resume | **UNIT** (`test/features/workspace/providers/startup_recovery_providers_test.dart`) |
| Recovery banner: per-reason message, resume-action visibility, callbacks, 44 dp touch target, locale sweep; renders with **no Overlay ancestor** (no Tooltip) | **WIDGET** (`test/features/workspace/widgets/recovery_banner_test.dart`) |
| Recovery banner **Reset** opens its confirm dialog when the host is mounted **above the Navigator** (drives the dialog via `rootNavigatorKey`) | **WIDGET** (`test/features/workspace/widgets/recovery_banner_host_test.dart`) |
| In-app reset clears live + on-disk state | **WIDGET** (`test/features/workspace/commands/reset_workspace_command_test.dart`) + Settings tile in `test/features/settings/screens/settings_screen_test.dart` |
| End-to-end: force-quit mid-load → next launch suppresses auto-load + shows banner + Open last session restores | **MANUAL** (process-kill timing; the unit-level sentinel survival test is the proxy) |
| `--reset` actually removes the on-disk files at boot | **MANUAL** (CLI + filesystem; `resetPersistedSessionData` is unit-covered) |

### 16.1.8 Opening a design manifest (`<design>.crux-project`)

#### 16.1.8.1 What it does

A design manifest is a small YAML file named `<design>.crux-project` (for example `uart_tx.crux-project`) that names a design's dump, RTL, lint project and regression config. Opening it in WaveCrux opens the waveform its `waveform:` entry names, exactly as if that dump had been opened directly. A manifest still named with the legacy bare `.crux-project` opens too, with a notice saying what to rename it to.

#### 16.1.8.2 Steps

1. Create a folder `uart_tx/` holding a copy of `verification/fixtures/vcd/scalar_basics.vcd` as `sim.vcd` and a `uart_tx.crux-project` containing `version: 1`, `artifacts:` and `  waveform: sim.vcd`.
2. **File → Open File**: the picker lists `uart_tx.crux-project` (it is not greyed out). Choose it — a tab opens on `sim.vcd`.
3. macOS: double-click `uart_tx.crux-project` in Finder — WaveCrux opens `sim.vcd` (Get Info shows the kind EDACrux Design Manifest).
4. Desktop CLI: `wavecrux uart_tx/uart_tx.crux-project` and `wavecrux uart_tx` (the folder) both open `sim.vcd`.
5. Rename the manifest to `.crux-project` and open it from the CLI: the waveform opens and a snackbar reads *"This design manifest uses the old file name .crux-project, which file pickers hide. Rename it to uart_tx.crux-project."*

#### 16.1.8.3 Edge cases

- A folder holding both `a.crux-project` and `b.crux-project`, opened as a folder: an error snackbar names both files and nothing opens.
- A manifest with no `waveform:` entry, or one naming a missing file: a snackbar says what is missing; nothing opens.
- `notes.crux-project.txt` is an ordinary file, not a manifest.

#### 16.1.8.4 Automation Assessment

| Test | Coverage |
|---|---|
| Named, legacy, case-insensitive, directory and ambiguous-directory resolution; URLs pass through | **UNIT** (`test/services/session/crux_project_resolution_test.dart`) |
| A positional `*.crux-project` becomes an initial file | **UNIT** (`test/services/cli/cli_args_test.dart`) |
| An incoming named manifest opens its waveform; the legacy notice and the ambiguous-folder error appear localized | **WIDGET** (`test/features/viewer/screens/viewer_screen_phone_incoming_file_test.dart`) |
| Picker lists `.crux-project`; Finder double-click on macOS | **MANUAL** (native dialogs and Launch Services) |

---

### 16.2 Settings screen

#### 16.2.1 What it does

The Settings screen exposes user-configurable preferences: color-theme presets (which also set light/dark brightness — there is **no** separate light/dark/system selector any more; the active preset is the single brightness lever), default display format, keyboard shortcut reference, file-handling behavior (auto-reload mode, file size warning threshold on mobile), remote-control / CXP servers, and decoder plugins. Settings persist across launches via `SharedPreferences` (or platform equivalent). The About box is **not** part of this screen — it is reached from the app menu (Help → About).

#### 16.2.2 Steps

1. Open Settings (gear icon, command palette → "Settings", or Ctrl/Cmd+,).
2. **Dual-pane layout.** The Settings body is a master-detail: a left **category rail** and a right **detail pane** that scrolls the selected category's content. Verify the rail lists, in order (per `settings_screen.dart`): **Appearance**, **Waveform Defaults**, **File Handling**, **Orientation** (mobile only), **Remote Control**, **CXP Cross-Probe**, **Decoder Plugins** (desktop only), **Keyboard Shortcuts**. There is **no About category** — the About box is reached from the app menu (Help → About). The selected rail row is highlighted (`secondaryContainer`); **Appearance** is selected by default. Clicking a rail row swaps the detail pane to that category and scrolls it to the top.
   - **Responsive collapse.** At ≥ 620 dp wide the rail and detail sit side by side (separated by a `VerticalDivider`). Below 620 dp (narrow window, phone, the dialog on a small screen) it collapses to a single column: the category list, which swaps to the selected category's content with an in-pane back button. Resize the window across the breakpoint and confirm both layouts work and no content is lost.
3. **Per-category content.** Each category's detail pane shows an icon + title header (suppressed in the narrow layout, where the back bar already names it) above one or more grouped cards. Verify:
   - Cards are the quiet `surfaceContainerLow` grouping tone (12 dp radius); rows are separated by inset hairline dividers and every row — `ListTile`/`SwitchListTile`, sliders, and segmented buttons alike — clears the card's left/right and top/bottom borders with a comfortable margin (no control hugging an edge).
   - Wide controls (auto-reload / orientation `SegmentedButton`s) stack full-width below their label; compact controls (language + display-format dropdowns, switches, port fields) sit in the trailing slot; the four sliders share one layout (label, description, slider, right-aligned value readout).
4. **Appearance.** Confirm one "Appearance" title, then language / font-size rows (there is **no** light/dark/system theme-mode selector — it was removed as redundant with the preset picker), then three labelled subsections — **Presets**, **Color overrides**, **Theme packs**. The **preset cards** are compact (sized to their content — a title row + one row of color swatches — with no large empty area below) and render on the app's value surface (`surfaceContainerHighest`, the same fill as text inputs), visually distinct from the section grouping card.
5. **Brightness is preset-driven.** Activate a light preset (e.g. WaveCrux Light) and confirm the entire app re-themes to light immediately; activate a dark preset (WaveCrux Dark, Solarized Dark, …) and confirm it re-themes to dark. The choice persists on next launch. Then press **⌘/Ctrl+Shift+K** (View → Toggle Theme): it flips between the default light and dark presets — from any dark preset it lands on WaveCrux Light and vice-versa. (There is no longer a separate light/dark/system flag; the toggle and the preset picker move the same lever.)
6. **OLED XR preset (XR / AR glasses).** The preset grid includes **OLED XR** (a dark preset). Activate it and confirm the *entire* surface — canvas background, signal lanes, **and** chrome (toolbar, panel headers, status bar, tab bar) — repaints on true black (`#000000`), with no near-black grey left on any chrome surface; the time ruler is true black too. What the user gets: on a Micro-OLED XR headset (e.g. Viture Beast / Xreal One Pro, which present as an external monitor) the black pixels switch fully off, so there is no backlight-bloom halo around bright traces and the image is easier on the eyes at the glasses' high brightness. Confirm signal state stays legible: X-state fill is bright red and bus value labels take each signal's own color. The active cursor is amber (`#FFD400`), the secondary cursor cyan (`#00E5FF`), markers green (`#34FF8A`), and the ruler's time labels near-white (`#E8E8E8`); there is no fine blue line on the canvas, which birdbath optics smear. A theme pack or a Color override recolors them. Activating it persists across launch like any other preset, and **⌘/Ctrl+Shift+K** (View → Toggle Theme) flips from it to WaveCrux Light and back. The preset is brand-neutral — nothing in the UI names or implies affiliation with any glasses maker.
7. **Boost legibility for XR / large displays.** Below the font-size slider, toggle **Boost Legibility for XR / Large Displays** on. With a waveform open, confirm every trace gets visibly thicker — scalar lines, bus-segment outlines, the analog trace, and lane dividers — and the in-canvas value/label text never renders below ~14 px (raise the font slider above that and the boost stops mattering; lower it and the floor holds). What the user gets: on XR/AR glasses and other large, far-viewed screens — where each pixel covers fewer arc-minutes — the thicker strokes and font floor keep thin 1-px traces and small labels from disappearing. Toggle it off and the canvas returns exactly to the default weights (no residual thickening). The setting persists across launch and is independent of the OLED XR preset (either can be used without the other, though they pair naturally).
8. Change default display format (e.g., binary → hexadecimal). Open a new file and add a freshly-discovered signal — verify it picks up the new default.
9. Change auto-reload mode (Off / Prompt / Auto). Modify the loaded VCD externally — verify behavior matches the chosen mode.
10. On mobile, change the file-size-warning threshold. Attempt to open a file just above and just below — verify the warning trigger respects the new value.
11. Check the Keyboard Shortcuts table renders all `ShortcutAction` values with their localized labels and current bindings, in the same `ActionCategory` grouping used by the menu bar / command palette.

#### 16.2.3 Locale sweep

Switch the app locale to zh_CN, ja, ko via system settings. Re-open Settings and verify every label is translated and there's no UI overflow.

#### 16.2.4 Edge cases

- Settings file corrupted on disk → app falls back to defaults rather than crashing; corruption logged.
- Permission denied writing settings (sandboxed install) → settings still apply for current session, prompt user about persistence loss.
- **Legacy theme-id migration.** A profile from an earlier beta persists the old preset ids `wavecrux-dark` / `wavecrux-light` (since renamed to the suite-wide `crux-dark` / `crux-light`). On first launch after the upgrade the user must keep their chosen theme — a light-theme user must NOT silently land in dark mode. This is handled on the read path (`builtinPresetById` applies crux_theme's permanent alias map), so it is transparent; there is no migration prompt. Guarded by `test/core/theme/wavecrux_color_theme_bootstrap_test.dart`. Likewise a `.wavecrux` session file carrying `"activeTheme": "wavecrux-dark"` restores to the current dark preset.
- **Theme-pack browser on web.** The Settings → Appearance "Theme packs" import/export now flows document *text* through the host (crux_theme's `ThemePackStore` seam) instead of `dart:io` file handles, so the panel renders and functions on the web build. On desktop/mobile behaviour is unchanged — Import reads the chosen file's contents; Export writes the encoded pack to the chosen path.

#### 16.2.5 Automation Assessment

| Test | Coverage |
|---|---|
| Theme change re-themes app | **WIDGET** (`test/features/settings/screens/settings_screen_test.dart` — theme segment behaviour); rebuild propagation across the app **WIDGET — pending** |
| Settings persistence across launch | **WIDGET** (`test/services/settings/`) |
| Default-format change applies to new signals | **WIDGET** (`settings_screen_test.dart` covers the setter; per-new-signal default consumption colocated with signal-add tests) |
| Locale sweep on Settings labels | **WIDGET** (`settings_screen_test.dart` includes locale sweep) |
| Corrupted-settings fallback | **WIDGET** (`test/services/settings/` — load-failure fallback) |
| Remote Control port + status row visibility when enabled | **WIDGET** (`settings_screen_test.dart` — "when remote control is enabled, port + server-status rows appear") |
| Grouped-card section layout | **WIDGET** (`settings_screen_test.dart` — "groups detail content into bordered Cards"); section-vs-data tone, row margins + visual polish remain **MANUAL** |
| Dual-pane rail + detail, category navigation | **WIDGET** (`settings_screen_test.dart` — "renders a category rail beside a detail pane (VerticalDivider)", "rail lists the platform-independent categories", "selecting … reveals …") |
| Narrow (list → detail) collapse with back affordance | **WIDGET** (`settings_screen_test.dart` — "SettingsScreen narrow layout shows the category list, then detail with a back button") |
| No About category | **WIDGET** (`settings_screen_test.dart` — "no About category") |
| Preset card sizing (compact, no empty area) | **MANUAL** (crux_theme `PresetPicker` fixed `mainAxisExtent`); preset activation covered by `crux_theme` package tests |
| OLED XR preset present + signature true-black/amber token values | **UNIT** (`crux_theme` `builtin_presets_test.dart` — preset count, key set, `oled-xr` chrome category, `chrome.scaffold.background`/`toolbar.iconActive` spot-checks; every `oled-xr` canvas value in `test/core/theme/wavecrux_canvas_preset_overlay_test.dart`); on-glasses bloom/legibility feel remains **MANUAL** |
| Legibility-boost toggle round-trips + scales canvas strokes | **WIDGET** (`settings_screen_test.dart` — "Appearance → legibility-boost toggle round-trips through the provider") + **WIDGET** (`waveform_canvas_render_object_scale_test.dart` — "lineWidthScale propagates from view to render object") + **UNIT** (`app_settings_test.dart`, `settings_service_test.dart` — default-off / copyWith / persistence); actual stroke thickness on-glasses **MANUAL** |
| Size-aware default pane widths (<800 dp → 220/160, ≥21:9 → 360/280, ≥32:9 → 420/320) | **UNIT** (`pane_defaults_test.dart` — threshold table incl. boundary + degenerate cases, plus the canvas-budget assertions that pin why the narrow arm exists); end-to-end pane seeding at either extreme **MANUAL** |

#### 16.2.6 Keyboard shortcut customization

##### What it does

Settings → Keyboard Shortcuts is an **editable** list (it replaced the former read-only table). Every `ShortcutAction` is grouped by category (File / View / Navigate / Search / Tools / Help / App) with its current platform-aware binding shown as a monospace chip. Each row offers: a **pencil** (capture a new chord), a **backspace** icon (unbind), and — once the binding differs from the default — a **reset** icon. A header row offers **Import…**, **Export…**, and **Reset all**. Customizations persist across launches (`SharedPreferences`, stored as diffs from default) and can be shared via a named `wavecrux.crux-keymap.json` file.

Bindings are stored in a **platform-neutral** form: the primary accelerator is recorded abstractly (`mod`) and materializes to Cmd on macOS/iOS and Ctrl on Windows/Linux; Option↔Alt likewise. Literal-Control bindings (e.g. Ctrl+Tab for next-tab) stay Control on every platform. This is what makes a shared keymap work across operating systems. **Scope:** single-activator parity — one modifier-combo + key per action; multi-key chords are out of scope for this release.

This is **open-core** — the feature lives in `wavecrux/` (and the `crux_keybindings` crux-shared package). There is no tier gate and no `FeatureTierBadge`. Verification stays in this open-core guide, not the Pro docs.

##### Setup

A desktop build (key capture needs a hardware keyboard). For the cross-platform check, a second machine or VM on a different OS family (e.g. one macOS + one Windows/Linux).

##### Steps — rebind, persist, and propagate

1. Open Settings → Keyboard Shortcuts. Confirm the categorized list renders with binding chips and the Import / Export / Reset all controls.
2. Press the **pencil** on an action (e.g. **Zoom In**). The chip is replaced by a highlighted "Press the new shortcut… (Esc to cancel)" field.
3. Press a new chord (e.g. **Cmd/Ctrl+J**). The field closes and the chip updates to the new chord immediately.
4. Open the **command palette** and the **menu bar**: the same action now shows the new binding inline. Press the new chord — the action fires.
5. **Quit and relaunch.** Re-open Settings → Keyboard Shortcuts and confirm the custom binding is still there (it persisted).
6. Press the **reset** icon on that row → it returns to the default chord and the reset icon disappears. Press **backspace** on a different bound row → it becomes "—" (unbound) and that action no longer fires from the keyboard (still reachable via menu/palette).

##### Steps — conflict detection

7. Rebind an action to a chord already used by another (e.g. set **Zoom In** to **Zoom Out**'s chord). The binding is still applied (a warning, not a block). Verify the conflict is surfaced **asymmetrically** so it's clear which row is the problem:
   - The row you just remapped (**Zoom In**, the customized "interloper") shows an amber **"Takes precedence over Zoom Out"** note — it is the one that fires.
   - The other row (**Zoom Out**, the default "owner") shows a red **error** note **"Won't fire — shadowed by Zoom In"** — its shortcut is now dead. The note must read with a **single** apostrophe in "Won't" — not a doubled `Won''t` (issue #42: this is a non-plural/non-select ICU message, so `flutter gen-l10n` does *not* un-escape apostrophes, and a doubled apostrophe in the ARB renders literally).
   - Documented intentional shadows (Close File / Close Tab on Cmd/Ctrl+W) do **not** warn.
7a. **Summary banner (works even when rows are off-screen).** With a conflict present, a red banner at the top of the section reads **"N shortcut conflict(s) need attention"** (singular at 1). Scroll the affected rows out of view — the banner stays visible. Resolve the conflict (reassign or unbind one side) and the banner disappears.
7b. **Precedence is deterministic and reflects intent (issue #36 bug 3).** After step 7, actually press the shared chord in the app: the **remapped** action (Zoom In) fires — **not** the action that merely held the chord by default. This is the customized-wins rule, independent of action declaration order. (Previously whichever action was declared later in the enum silently won, so a fresh remap appeared to do nothing.) The shadowed action (Zoom Out) remains reachable from the toolbar / menu bar / command palette.

##### Steps — export / import (sharing & company standard)

8. Make one or two customizations, then press **Export…** and save `wavecrux.crux-keymap.json`. Confirm the success snackbar. Open the file: it is readable JSON with a `schema`/`version` envelope and a `bindings` map keyed by action id, containing only your changes (diffs).
9. Press **Reset all** → confirm the dialog → all rows return to default.
10. Press **Import…**, choose the file from step 8. Confirm the "Imported N customized shortcuts" snackbar and that exactly those bindings are restored. Importing a file with no customizations shows the "no shortcut customizations" message; importing junk shows the failure snackbar without crashing. Importing a keymap **saved by a newer version of WaveCrux** (an envelope whose `version` exceeds this build's) shows the distinct **"…this keymap was saved by a newer version of WaveCrux"** message — not the generic "invalid file" one, and not a raw exception dump — so the user understands the file is fine and it is this build that is behind. (The `crux_keybindings` codec raises `KeymapSchemaVersionException`, a `FormatException` subclass, which the section catches ahead of the generic handler.)
11. **Company-standard flow:** hand the exported file to another user (or drop it in a shared location) and Import it on a fresh profile — the bindings reproduce exactly.

##### Steps — cross-platform round-trip

12. Export a keymap on **macOS** that uses Cmd and Option combos. Import it on **Windows/Linux**: the Cmd combos appear as Ctrl, the Option combos as Alt, and they fire correctly. Reverse the direction (author on Windows, import on macOS) and confirm Ctrl→Cmd. Confirm a literal Ctrl+Tab binding stays **Ctrl**+Tab on macOS (not Cmd+Tab).

##### Edge cases

- **New action after upgrade.** A keymap exported by an older build imports cleanly on a newer build; actions added since inherit their new defaults rather than showing as unbound (diffs-from-default schema).
- **Corrupt / unavailable storage.** A corrupt persisted value or unreadable preference store falls back to defaults rather than crashing.
- **Bare Esc** cancels capture (it does not bind Esc); to bind Esc, hold a modifier (e.g. Shift+Esc).
- **macOS Caps Lock → Control remap.** On a Mac configured with System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys to map Caps Lock to Control, capture a chord using the **remapped Caps Lock** as the Control key (e.g. Caps Lock+F). The captured chip must read **⌃F** (Control), not a bare **F** — Flutter surfaces the remapped key as a held `capsLock` logical key with `isControlPressed == false`, and the capture field treats a held Caps Lock as Control. A genuine Caps Lock *lock* (toggled on, not held) must NOT add Control: with Caps Lock turned on, capture **Ctrl+F** with the physical Control key and confirm the chip is still ⌃F (no double-modifier, no stray Control on an unmodified capture).
- **Close File has no default keyboard binding (issue #37).** Cmd/Ctrl+W is owned solely by **Close Tab**. Confirm the Close File row shows "—" (unbound) by default, that pressing Cmd/Ctrl+W closes the tab (not the file), and that Close File is still reachable from the File menu / command palette (and can be assigned a chord). There must be **no** conflict warning on a fresh profile (the former closeFile/closeTab Cmd/Ctrl+W shadow and its `kIntentionalShadows` suppression are gone).
- **Command Palette is reachable from the menu (issue #38).** The command-palette opener appears under the **Help** menu (desktop) and the mobile overflow menu, but **not** inside the command palette itself. Verify recovery: unbind Cmd/Ctrl+Shift+P in Settings → Keyboard Shortcuts, then reopen the palette from Help → Command Palette (desktop) / overflow (mobile) — it must still be reachable with no "reset all bindings" required.
- **Phone / tablet.** With no hardware keyboard, the list is informational; the phone note explains shortcuts need an external keyboard.

##### Automation Assessment

| Test | Coverage |
|---|---|
| Platform-neutral model: mod→Cmd/Ctrl, literal ctrl, Option↔Alt, cross-platform round-trip | **UNIT** (`test/core/shortcuts/key_binding_test.dart`) |
| Versioned codec: diffs, explicit unbind, unknown-action skip, malformed-binding skip | **UNIT** (`test/core/shortcuts/keymap_codec_test.dart`) |
| Persistence round-trip + corrupt-value fallback | **UNIT** (`test/core/shortcuts/shortcut_bindings_store_test.dart`) |
| Notifier persistence (rebind/unbind survive relaunch), resetAll clears, importDiffs | **UNIT** (`test/core/shortcuts/shortcut_bindings_provider_test.dart`) |
| Conflict detection incl. intentional-shadow allow-list | **UNIT** (`test/core/shortcuts/shortcut_conflicts_test.dart`) |
| Conflict **resolution**: customized binding wins over default owner; intentional shadow resolved-but-not-warned; deterministic (order-independent) precedence; summary count | **UNIT** (`test/core/shortcuts/shortcut_conflicts_test.dart` "resolveShortcutConflicts" + `crux-shared/packages/crux_keybindings/test/shortcut_conflicts_test.dart`) |
| Runtime precedence: a freshly remapped action fires on the shared chord, the default owner is shadowed (issue #36 bug 3) | **WIDGET** (`test/core/shortcuts/shortcut_manager_widget_test.dart` "conflict precedence") |
| Asymmetric conflict warning (winner "takes precedence" / shadowed "won't fire") + summary banner count (issue #36 bugs 1 & 2) | **WIDGET** (`test/features/settings/widgets/shortcuts/shortcuts_settings_section_test.dart` + `crux-shared/packages/crux_keybindings/test/widgets/key_bindings_editor_test.dart`) |
| Key capture, conflict warning, reset-all dialog, export/import wiring, locale sweep | **WIDGET** (`test/features/settings/widgets/shortcuts/*_test.dart`) |
| Newer-version keymap import shows the version-specific message, not the generic failure | **WIDGET** (`test/features/settings/widgets/shortcuts/shortcuts_settings_section_test.dart` — "importing a keymap from a newer version shows the version-specific message") + **UNIT** (`crux-shared/packages/crux_keybindings/test/keymap_codec_test.dart` — `KeymapSchemaVersionException`) |
| Caps Lock→Control remap captured as Control; held-Caps-Lock vs. lock-toggle distinction | **WIDGET** (`crux-shared/packages/crux_keybindings/test/widgets/shortcut_capture_field_test.dart`) |
| Default-collision guard (no dead shortcuts) | **UNIT** (`test/core/shortcuts/shortcut_bindings_test.dart` "no unintended collisions") |
| Cross-OS round-trip on real hardware | **MANUAL** (step 12 — needs two OS families) |

---

#### 16.2.7 Keymap presets (GTKWave compatibility)

##### What it does

Above the editable shortcut list, a **Preset** dropdown lets the user load a complete, named keymap in one action. Two presets ship:

- **WaveCrux (Default)** — the platform-aware defaults (`defaultBindings()`).
- **GTKWave** — eases migration for engineers coming from GTKWave by honoring the GTKWave accelerators that map onto an existing WaveCrux action. The delta from the WaveCrux defaults is: **Signal search → `Alt+S`** (GTKWave "Signal Search Regexp"), **Export → `Ctrl/Cmd+P`** (GTKWave "Print To File"), and the data-format keys on the selected signal — **Hex `Alt+X`, Decimal `Alt+D`, Binary `Alt+B`, Octal `Alt+O`**. Everything else is inherited from the WaveCrux defaults (the two apps already share the standard-desktop spine — Open/Save/New-Tab/Close/Quit, Zoom In/Out, Zoom Full, Jump-to-End). Markers, paging, and reload are deliberately *not* remapped (different mechanics / covered by auto-reload and the mouse-wheel setting — see §16.2.8).

Selecting a preset replaces all bindings and persists the same way an Import does (diffs from default). The user can still hand-edit individual rows afterward; once they do, the dropdown reads **Custom**. This is **open-core** — no tier gate, no `FeatureTierBadge`.

##### Steps

1. Open Settings → Keyboard Shortcuts. Confirm the **Preset** dropdown sits above the list and reads **WaveCrux (Default)** on a fresh profile.
2. Select **GTKWave**. Verify the **Signal Search** row's chip changes to `Alt+S`, **Export Waveform** to `Ctrl/Cmd+P`, and (scrolling to the format actions) **Set Format: Hexadecimal/Decimal/Binary/Octal** show `Alt+X/D/B/O`. Confirm no conflict warnings appear.
3. Press `Alt+S` over the waveform → the signal search opens. Select a bus signal, press `Alt+X` → it displays as hex.
4. **Quit and relaunch.** The dropdown still reads **GTKWave** and the bindings persist.
5. Hand-edit any one row (pencil → new chord). The dropdown flips to **Custom**. Re-select **WaveCrux (Default)** → all rows return to baseline and `currentDiffs()` is empty.

##### Edge cases

- The GTKWave preset must be **collision-free** — no two actions share a chord (guarded by a unit test). A future binding change that introduces a clash is a defect.
- "Custom" is a display-only state; it is surfaced via the dropdown `hint`, so the user can land on it (by editing) but can never *select* it.

##### Automation Assessment

| Test | Coverage |
|---|---|
| GTKWave preset binds the documented accelerators and changes ONLY those actions | **UNIT** (`test/core/shortcuts/keymap_presets_test.dart`) |
| GTKWave preset is collision-free; inherits unrelated defaults | **UNIT** (`keymap_presets_test.dart`) |
| `presetForBindings` identifies WaveCrux / GTKWave / Custom (value-aware, no `SingleActivator ==`) | **UNIT** (`keymap_presets_test.dart`) |
| `applyPreset` replaces the map and persists only the delta across relaunch | **UNIT** (`test/core/shortcuts/shortcut_bindings_provider_test.dart` applyPreset group) |
| Dropdown defaults to WaveCrux, applies GTKWave, shows Custom after a hand edit; locale sweep | **WIDGET** (`test/features/settings/widgets/shortcuts/shortcuts_settings_section_test.dart`) |

---

#### 16.2.8 Mouse-wheel direction (scroll signals vs. navigate time)

##### What it does

A **"Mouse wheel scrolls through time"** toggle in Settings → **Waveform Defaults** chooses what the mouse scroll wheel does over the waveform canvas. It exists primarily so GTKWave migrants get GTKWave's wheel reflex (plain wheel moves through time).

| Modifier | Off — *scroll signals* (default) | On — *navigate time* (GTKWave) |
|---|---|---|
| (none) | scroll the signal list vertically | **pan the time axis** |
| Shift | pan the time axis | scroll the signal list vertically |
| Ctrl/Cmd | zoom around the pointer | zoom around the pointer |

The setting is persisted (`wheelNavigatesTime`, default off) and applies to the **mouse scroll wheel only** — trackpad pinch-to-zoom and two-finger pan are unaffected. Ctrl/Cmd+wheel zoom-at-cursor is identical in both modes (and already matches GTKWave). This is **open-core** — no tier gate.

##### Setup

A desktop build with a real mouse wheel (the behavior is wheel-specific; a trackpad exercises the unaffected gesture path). Load any multi-signal VCD (e.g. `protocol/spi/generated/spi_basic.vcd`) and add enough signals that the list scrolls vertically, then zoom in so the time window is pannable.

##### Steps

1. **Default (off).** Scroll the wheel with no modifier → the **signal list scrolls vertically**; the time window does not move. Hold **Shift** and scroll → the **waveform pans** left/right. Hold **Ctrl/Cmd** and scroll → **zoom** centered on the pointer.
2. Open Settings → Waveform Defaults, turn **"Mouse wheel scrolls through time"** on.
3. **Navigate-time (on).** Scroll with no modifier → the **waveform pans** through time. Hold **Shift** and scroll → the **signal list scrolls** vertically. Hold **Ctrl/Cmd** and scroll → **zoom** (unchanged).
4. **Quit and relaunch** → the toggle state persists and the wheel behaves accordingly.

##### Edge cases

- A trackpad (two-finger scroll / pinch) behaves identically regardless of the toggle — the setting governs `PointerScrollEvent` from a mouse, not pan-zoom gestures.
- On macOS the OS may report Shift+wheel as a horizontal delta; the interceptor drives the lane-scroll callback directly so vertical scroll still works in navigate-time mode regardless of how the delta is reported.

##### Automation Assessment

| Test | Coverage |
|---|---|
| Default mode: plain wheel does not pan/zoom; Shift pans; Ctrl zooms | **WIDGET** (`test/features/viewer/widgets/waveform_scroll_modifier_interceptor_test.dart`) |
| Navigate-time mode: plain wheel pans; Shift drives the list (no pan); Ctrl still zooms | **WIDGET** (`waveform_scroll_modifier_interceptor_test.dart` — navigate-time group) |
| `wheelNavigatesTime` setting round-trips through persistence | **UNIT** (`test/services/settings/settings_service_test.dart`) |
| Setter + derived `wheelNavigatesTimeProvider` | **UNIT** (`test/features/settings/providers/settings_providers_test.dart`) |
| Perceptual feel on real mouse hardware | **MANUAL** (steps 1–3) |

---

### 16.3 Auto-reload on file change

#### 16.3.1 What it does

While a VCD is loaded, the file-watcher Riverpod provider (`lib/features/viewer/providers/file_watcher_provider.dart`) monitors the underlying file. When the simulation re-runs and overwrites the file, WaveCrux either reloads automatically (Auto mode), prompts the user (Prompt mode, default), or does nothing (Off mode). This is critical for iterative sim+debug workflows.

Web does not support file watching (no `dart:io`); the feature should silently no-op there.

#### 16.3.2 Setup

- Any small VCD on the local filesystem.
- An external command that overwrites or rewrites the same file (e.g., `iverilog` re-run, or a simple `cp newer.vcd target.vcd`).

#### 16.3.3 Steps — Prompt mode

1. Open the VCD in WaveCrux. Verify the file is loaded normally.
2. From a terminal, overwrite the same file with a different VCD (or re-run the simulation that produced it).
3. Within ~1 second, verify a non-blocking prompt appears: "File changed — Reload? / Ignore".
4. Click Reload → verify the new content loads, retaining session state where reasonable (signal selections, cursor position if still valid).
5. Repeat and click Ignore → verify the prompt dismisses and the in-memory data does not change.

#### 16.3.4 Steps — Auto mode

1. Switch auto-reload to Auto in Settings. Repeat the overwrite. Verify reload happens silently with a brief snackbar acknowledgment.

#### 16.3.5 Steps — Off mode

1. Switch to Off. Repeat the overwrite. Verify no prompt and no reload.

#### 16.3.6 Steps — File deletion

1. While a file is loaded, delete the source file from disk.
2. Verify a clear notification appears that the file is no longer available; in-memory data remains usable until you close the file.

> **Multi-tab scoping note.** The file watcher (`fileWatcherProvider`) is overridden per tab — it watches the *active tab's* loaded file. The notification listener that drives the prompt banner / Auto-reload / deletion snackbar lives in the per-tab Consumer in `ViewerScreen._buildTabContent` (gated to the active tab), NOT at the screen-level root scope. A root-scope listener never fires because the root `waveformSourceProvider` has no file. Regression check: open file A in tab 1, file B in tab 2, focus tab 2, then modify B on disk — only tab 2 (active) prompts/reloads; modifying A while tab 2 is focused does not drive a reload of B.

#### 16.3.7 Steps — Web fallback

1. Open WaveCrux in a browser. Open Settings → File Handling. Verify the auto-reload control is either hidden or shown disabled with an explanatory tooltip ("Not available on web").

#### 16.3.8 Automation Assessment

| Test | Coverage |
|---|---|
| Prompt mode triggers on file change | **WIDGET** (`test/features/viewer/providers/file_watcher_provider_test.dart`); real-FS event **INTEGRATION_TEST** (`integration_test/session/auto_reload_test.dart`) — ⚠ **currently failing on the macOS runner**: the modify→prompt-banner path does not surface within the poll window even though the watcher fires (Auto-mode reload and deletion both work via the same watcher). Tracked as a follow-up. |
| Auto mode silently reloads | **WIDGET** (`test/features/viewer/providers/file_watcher_provider_test.dart`); real-FS reload **INTEGRATION_TEST** (`integration_test/auto_reload/auto_reload_auto_mode_test.dart`) |
| Off mode is silent | **WIDGET** (`test/features/viewer/providers/file_watcher_provider_test.dart`) |
| File deletion notification | **WIDGET** (`test/features/viewer/providers/file_watcher_provider_test.dart`); real-FS deletion **INTEGRATION_TEST** (`integration_test/auto_reload/file_deletion_test.dart`) |
| Web fallback hides/disables control | **WIDGET — pending** (the file-watcher provider at `lib/features/viewer/providers/file_watcher_provider.dart` is `kIsWeb`-gated in source — behaviour disabled — but the Settings → Auto-reload UI section is not currently hidden on web. Closing requires either wrapping the section in a `kIsWeb` check or running the SettingsScreen test under `flutter test --platform chrome`. Tracked in `integration_test/PENDING.md`.) |

---

## 17. Value display formats and translate filters

### 17.1 What it does

Every signal can be rendered in any of: binary, hexadecimal, octal, unsigned decimal, signed decimal, ASCII. Format is chosen per signal via the value-column context menu or the signal-list right-click. WaveCrux respects GTKWave-compatible x/z propagation rules (hex nibble with any x bit → 'x'; whole-value for decimal; per-byte for ASCII). On top of formats, **translate filters** layer human-readable labels via `.txt` files, and **process filters** (§6.5) pipe values through external programs.

### 17.2 Setup

`vcd/vector_formats.vcd` exercises 1/4/8/16/32/64-bit signals with mixed x/z bits in partial nibbles. Companion `vector_formats.expected.json` is the ground truth.

### 17.3 Steps — format coverage

1. Load `vcd/vector_formats.vcd`. Add several vector signals to the canvas.
2. For each signal, cycle through every format via the right-click menu: **Binary / Hex / Octal / Unsigned Decimal / Signed Decimal / ASCII**.
3. Verify the value column updates immediately and the formatted output matches `vector_formats.expected.json` row-for-row.
4. Verify x/z propagation rules:
   - Hex with `xxxx_zzzz` partial nibbles → each affected nibble shows `x` or `z`, not a number.
   - Octal with x in any of the 3 bits of a digit → digit shows `x`.
   - Signed decimal with any x → entire value renders as `x` (decimal can't represent partial-x).
   - Unsigned decimal same.
   - ASCII per-byte: byte with any x → that character position shows `?` or `x` rather than a glyph.

### 17.4 Steps — signed decimal sign extension

1. Add the 8-bit `byte8` signal to the canvas. Set its format to **Signed Decimal**.
2. Navigate cursor to **50 ns** (byte8 = `0xFF` = `11111111`) → verify `-1`.
3. Navigate to **60 ns** (byte8 = `0x80` = `10000000`) → verify `-128`.
4. Navigate to **70 ns** (byte8 = `0x7F` = `01111111`) → verify `127`. The bit-width drives the two's-complement interpretation.

### 17.5 Steps — ASCII edge cases

1. Add the 8-bit `byte8` signal. Set its format to **ASCII**. Navigate cursor to **80 ns** (byte8 = `0x41` = 65) → verify `A`.
2. Navigate to **0 ns** (byte8 = `0x00`, null character) → verify empty/placeholder rendering, not a literal `\0` glyph.
3. Navigate to **90 ns** (byte8 = `0x07` = BEL, non-printable) → verify safe rendering (`.` or hex escape, no crash).
4. Add the 32-bit `long32` signal. Set its format to **ASCII**. Navigate to **100 ns** (long32 = `0x57415645`) → verify `WAVE`.

### 17.6 Steps — large widths

1. Open **Tools → Generate Test VCD…** (moved out of the legacy diagnostics dialog). Create a VCD with at least one 256-bit and one 1024-bit wide signal (any signal count/duration). Load the generated file, add the wide signals to the canvas, and verify hex/binary format still renders in reasonable time (< 0.5 s) without UI hang.
   *(Note: `vector_formats.vcd` provides signals up to 64-bit width. Wider signals require the test-VCD generator.)*

### 17.7 Steps — per-signal format persistence

1. Set a custom format on a signal. Save the session. Reload. Verify the per-signal format choice is preserved.

### 17.8 Steps — static translate filter

Re-references §6.6 (GTKWave session import). Specifically:

1. Right-click a signal → Translate filter → point at `test/fixtures/gtkw/generated/sample_filter.txt`.
2. Verify the value column shows the label strings rather than the underlying integer values.
3. Toggle the filter off → verify raw values return.

### 17.9 Edge cases

- Format change on a real-typed signal — only ASCII and signed/unsigned decimal apply meaningfully; hex/binary should either disable or show a sensible representation.
- Format change on a 1-bit scalar — all formats produce a single character output without crashing.

### 17.10 Steps — IEEE-754 floating-point (single and double precision)

1. Load `vcd/vector_formats.vcd`. Add the 32-bit `long32` signal to the canvas.
2. Right-click the signal in the value column → **Format → IEEE-754 Float (32-bit)**.
3. Navigate cursor to **110 ns** (long32 = `0x3F800000`) → verify `1.0`.
4. Navigate to **120 ns** (long32 = `0xBF800000`) → verify `-1.0`.
5. Navigate to **130 ns** (long32 = `0x7F800000`) → verify `Inf`; **140 ns** (`0xFF800000`) → verify `-Inf`; **150 ns** (`0x7FC00000`) → verify `NaN`.
6. Navigate to **230 ns** (long32 has x-bits in the high and low nibbles) → verify `NaN` or an explicit `x` indicator, not a crash.
7. Add the 64-bit `quad64` signal. Right-click → **Format → IEEE-754 Double (64-bit)**. Navigate to **160 ns** (quad64 = `0x3FF0000000000000`) → verify `1.0`.
8. Verify the format is preserved across session save/load.

### 17.11 Steps — fixed-point Q-format

1. Add the 16-bit `word16` signal to the canvas. Right-click → **Format → Fixed-Point (Q-format)**.
2. A configuration dialog opens with sliders for integer bits (m) and fractional bits (n), and a Signed toggle. The preview updates live showing the Q notation (e.g., "Q7.8").
3. Set m=7, n=8, Signed=true → OK. Navigate cursor to **170 ns** (word16 = `0x0100` = decimal 256 raw) → verify `1.0` (256 / 2⁸ = 1.0).
4. Right-click again → **Configure Q-Format…** Set m=0, n=15, Signed=true → OK. Navigate to **180 ns** (word16 = `0x4000` = decimal 16384 raw) → verify `0.5` (16384 / 2¹⁵).
5. Set Signed=false (unsigned Q) → verify the notation changes to "UQ0.15" and the full 16-bit scale shifts accordingly.
6. Open the configuration dialog again (right-click → **Configure Q-Format…**) → verify the previously saved m/n/signed values are pre-populated.
7. Verify the format and its configuration are preserved across session save/load.
8. Navigate to **240 ns** (word16 is all x-bits) → verify graceful output (not a crash).

### 17.12 Steps — signed-magnitude

1. Add the 8-bit `byte8` signal to the canvas. Right-click → **Format → Signed Magnitude**.
2. Navigate cursor to **0 ns** (byte8 = `0x00` = `00000000`) → verify `+0`.
3. Navigate to **190 ns** (byte8 = `0x01` = `00000001`) → verify `+1`.
4. Navigate to **200 ns** (byte8 = `0x81` = `10000001`) → verify `-1` (sign bit = 1, magnitude = 1).
5. Navigate to **50 ns** (byte8 = `0xFF` = `11111111`) → verify `-127`.
6. Navigate to **210 ns** (byte8 = `0x80` = `10000000`) → verify `-0` or `+0` depending on convention (no crash).
7. Navigate to **380 ns** (byte8 = `xxxx0000`, partially unknown) → verify graceful output (no crash).

### 17.13 Steps — gray code

1. Add the 4-bit `nib4` signal to the canvas. Right-click → **Format → Gray Code**.
2. Navigate cursor to **0 ns** (nib4 = `0000`) → verify decimal display `0`.
3. Navigate to each timestamp for Gray code values 1–7:
   - **250 ns** (`0001`) → `1`; **260 ns** (`0011`) → `2`; **270 ns** (`0010`) → `3`
   - **280 ns** (`0110`) → `4`; **290 ns** (`0111`) → `5`; **300 ns** (`0101`) → `6`; **310 ns** (`0100`) → `7`
4. Continue for values 8–15:
   - **320 ns** (`1100`) → `8`; **330 ns** (`1101`) → `9`; **10 ns** (`1111`) → `10`
   - **340 ns** (`1110`) → `11`; **30 ns** (`1010`) → `12`; **350 ns** (`1011`) → `13`
   - **360 ns** (`1001`) → `14`; **370 ns** (`1000`) → `15`
5. Add the 4-bit `xnib` signal (it has x-state bits by design at multiple timestamps). Set its format to **Gray Code** → verify graceful output for all x-containing values (no crash).
6. Switch to the 8-bit `byte8` signal and verify the standard 8-bit Gray encoding table holds.

### 17.14 Steps — named enum (first-class, with editor dialog)

1. Add an 8-bit vector signal. Right-click → **Format → Named Enum**.
2. An editor dialog opens with a table of (value, label) rows. Initially empty.
3. Click the `+` button → a new row appears with value `0` and an empty label field.
4. Enter value `0`, label `IDLE`. Add another row: value `1`, label `RUNNING`. Add value `2`, label `ERROR`.
5. Press **OK**. Navigate cursor to **0 ns** (byte8 = `0x00`) → verify `IDLE`; navigate to **190 ns** (byte8 = `0x01`) → verify `RUNNING`; navigate to **220 ns** (byte8 = `0x02`) → verify `ERROR`. Navigate to **10 ns** (byte8 = `0xCA`) → verify the raw hex value is shown (unmapped).
6. Right-click the signal again → **Edit Enum Labels…** → verify the dialog re-opens with the three rows pre-populated.
7. Delete one row, change a label, press OK → verify the value column reflects the updated mapping.
8. **Import from GTKWave `.txt` filter**: click **Import** in the editor dialog, select `test/fixtures/gtkw/generated/sample_filter.txt` → verify rows are populated from the file.
9. **Export**: click **Export** → specify a path → verify a `.txt` file is written with each row on a separate line in the format `<value>  <label>`.
10. At a value containing `x` or `z` → verify the value column shows a sensible fallback (the raw value or `x`), not a crash.
11. Press **Cancel** (not OK) in the editor → verify the existing mapping is unchanged.
12. Verify the enum mapping (all entries) is preserved across session save/load (`translatorConfig` round-trip).

### 17.15 Steps — format & translator config are **per-instance** (issue #39)

Display format **and** its translator config (Q-format `{m,n,signed}`, named-enum labels, custom-translator bindings) are scoped to the **specific row**, not shared across every row of the same signal — matching how `format` already behaves. Adding the same signal twice lets you view/interpret it two ways side by side.

1. Add the same vector signal to the canvas **twice** (two rows, same signal).
2. On **row A**: right-click → Format → Fixed-Point (Q-format) → Configure → m=8, n=8. On **row B**: Format → Fixed-Point → Configure → m=4, n=12.
3. Verify each row renders with **its own** scale (Q8.8 vs Q4.12) — changing one does **not** change the other. (Before #39 this was impossible: the config fanned out by signal-ref to all rows.)
4. Repeat with named-enum labels and a custom-translator binding: editing row A's config leaves row B's untouched.
5. Save the session and reload — each row restores its own config (`translatorConfig` is stored per entry).

### 17.16 Edge cases (extended formats)

- **Q-format with m+n > available bit-width** — should clamp silently, not crash.
- **Named enum with duplicate values** — last definition wins; no crash.
- **Named enum with very many entries (1000+)** — the scroll list in the editor should remain usable; OK/Cancel work.
- **IEEE-754 format on a 1-bit signal** — disable or fall back gracefully; no crash.
- **Gray code on a 64-bit wide signal** — should render the correctly decoded decimal without hang.
- **Context-menu height on a short window (issue #40)** — shrink the window to its minimum height, then right-click a value-column row. The top-level menu must fit without clipping: the 12 display formats are collapsed behind a single **"Display Format ▸"** entry (showing the current format), so the translator entries (**Custom translator…**, **Clear custom translator**), **Copy value**, and the filter actions stay reachable without resizing. Clicking **Display Format** opens a nested menu with all 12 formats; it also fits the minimum window. (`showMenu` does not scroll on desktop, so reachability depends on the list fitting.)

### 17.17 Automation Assessment

| Test | Coverage |
|---|---|
| Each format produces correct output for `vector_formats.vcd` | **WIDGET** (`test/services/value_format/value_format_service_test.dart` — parameterized over all formats and widths 1–1024) |
| x/z propagation per format | **WIDGET** (`value_format_service_test.dart`) |
| Signed decimal two's-complement | **WIDGET** (`value_format_service_test.dart`) |
| ASCII non-printable handling | **WIDGET** (`value_format_service_test.dart`) |
| IEEE-754 single/double: key values (0.0, 1.0, -1.0, Inf, -Inf, NaN) | **WIDGET** (`value_format_service_test.dart`) |
| IEEE-754: x/z input → graceful output | **WIDGET** (`value_format_service_test.dart`) |
| Fixed-point Q-format: Q7.8, UQ0.15, various m/n combos | **WIDGET** (`value_format_service_test.dart`) |
| Fixed-point: x/z input → graceful output | **WIDGET** (`value_format_service_test.dart`) |
| Signed-magnitude: ±0, ±1, ±127, 8-bit range | **WIDGET** (`value_format_service_test.dart`) |
| Gray code: 4-bit and 8-bit encode/decode table | **WIDGET** (`value_format_service_test.dart`) |
| Named enum: mapping, unmapped fallback, session round-trip | **WIDGET** (`value_format_service_test.dart`, `session_service_test.dart`) |
| NamedEnumEditorDialog: render, add/delete, OK/Cancel, locale sweep | **WIDGET** (`test/shared/widgets/named_enum_editor_dialog_test.dart`) |
| QFormatConfigDialog: render, sliders, preview, OK/Cancel, locale sweep | **WIDGET** (`test/shared/widgets/q_format_config_dialog_test.dart`) |
| `setSignalTranslatorConfigByRef` / `setSignalFormatByRef` provider mutation | **WIDGET** (`test/features/viewer/providers/signal_group_providers_test.dart`) |
| Per-instance translator config — `setSignalTranslatorConfigById` targets one row; two rows of one signal carry different configs; byRef still fans out (issue #39) | **WIDGET** (`test/features/viewer/providers/signal_group_providers_test.dart` — "setSignalTranslatorConfigById (issue #39 — per-instance)" group) |
| Large-width signals (256-bit, 1024-bit) render in reasonable time | **HYBRID** — correctness covered in unit tests; render-time perception **MANUAL** |
| Format persistence across session round-trip | **WIDGET** (`test/services/session/session_service_test.dart`) |
| Translate filter application | **WIDGET** (`test/services/translate/translate_filter_service_test.dart`) |
| Named enum import from `.txt` filter file | **MANUAL** — exercises file-picker UI flow |
| Named enum export to `.txt` file | **MANUAL** — exercises file-picker save dialog |

---

### 17.18 Value-display layout — aligned three-column lane geometry

#### 17.18.1 What it does

*Where* a value renders is separate from *what* it shows (§17.1–17.16). The viewer has three per-row columns — the **signal-names list** (left pane), the **waveform canvas** (centre), and the **value column** (right pane) — and every row (signal lane, group header, separator, comment) must sit at the exact same vertical position across all three so a value never drifts off the wave it describes. All three read row heights from a single shared lane-geometry model (`LaneGeometry`) instead of each re-deriving them, so the columns cannot diverge by construction.

§17.17.1–17.17.6 cover the **desktop / tablet** surface: the value column stays a resizable `IdeLayout` pane with no visual or interaction change — the alignment bug is simply gone. §17.17.7 covers the **phone** surface, which replaces the old modal value drawer with a non-modal inline-at-cursor overlay.

The governing rule is **store raw, render clamped**: a signal's stored lane height is preserved untouched (a desktop session can store a sub-44 dp lane), but on a touch device class it is clamped up to the 44 dp minimum *at render time only* — applied in exactly one place (the shared model) for all three columns.

#### 17.18.2 Setup

Load any multi-signal VCD (e.g. `vcd/vector_formats.vcd` or `vcd/spi_basic.vcd`). Build an arrangement that exercises every row type:
1. Add several signals.
2. Group two of them (right-click → Move to group… / create a group) and leave the group expanded.
3. Insert a **separator** and a **comment** row (signal-list context menu).
4. Resize a couple of lanes to non-default heights (drag the bottom-edge resize handle on a signal-names row), including making one lane very short.

Show the value column (status-bar right chevron, §22 / 3.1.8.6.1) so all three columns are visible side by side.

#### 17.18.3 Steps — three-column alignment across all row types

1. Visually scan down the three columns. For **each** row — signals, the group header, the separator, the comment, and the custom-height lanes — confirm the signal name (left), the waveform lane (centre), and the value (right) share the same top and bottom edge. Nothing should be a pixel high or low relative to its neighbours.
2. Pay special attention to the rows immediately **below** a group header, a separator, and a comment — these were the most visible drift sites before the shared lane geometry.
3. Confirm a **grouped** signal (a child rendered under an expanded group header) is the same height as an equivalent top-level signal — on a tablet/touch build both clamp to the 44 dp floor.
4. Scroll the panes; the three columns stay locked together vertically (scroll-offset sync is independent of this fix and unchanged).

#### 17.18.4 Steps — resize reflows all three columns live

1. Grab the bottom-edge resize handle of one signal in the **signal-names** column (the names column is the sole height *writer*) and drag to grow/shrink the lane.
2. Verify the lane in the **canvas** and the matching row in the **value column** grow/shrink in lockstep, staying aligned *during* the drag, not just after release.
3. Double-tap the signal-name area to reset the lane height → all three columns snap back together.
4. **The reset target is the user's configured default, not a fixed 30 dp.** Open Settings → Waveform Defaults and change the default lane height (say to 48 dp), return to the viewer, drag a lane to some other height, then double-tap the signal name. It must snap to **48 dp**, not 30. Before this was fixed the reset was a hardcoded `30`, so anyone who had configured a different default silently got 30 dp back on every reset — the setting appeared to work for newly-added signals and to be ignored on reset. 30 dp remains the shipped *default value* of the setting, which is why the defect was easy to miss: it is invisible until the user actually changes the setting.

| Check | Automatable? | How |
|---|---|---|
| Double-tap resets to the configured default | **WIDGET** (`signal_list_panel_test.dart` — "double-tap reset honours the configured default lane height") | Overrides `appSettingsProvider` with `defaultLaneHeight: 48` and asserts the reset lands on 48. Mutation-verified: against the old hardcoded `30` it fails with `Expected: <48> / Actual: <30.0>`. |
| Reset at the default setting still yields 30 | **WIDGET** (same file — "double-tap on signal name resets lane height") | Pre-existing test; passes either way, so it is the pair above that carries the regression. |
| Touch-floor clamp still applies to the reset value | **WIDGET** (same file — lane-height touch-minimum tests) | A configured default below the 44 dp touch floor must still render clamped on touch (store raw, render clamped). |

#### 17.18.5 Steps — value pane keeps its manual show/hide toggle

1. Toggle the value column off via the status-bar right chevron → it hides; signal-names and canvas remain aligned.
2. Toggle it back on → it reappears, still pixel-aligned. The pane is **not** forced always-on; this is unchanged from prior behaviour.

#### 17.18.5a Steps — synchronized vertical scroll reaches the last lane (no bounce-back)

**What it does.** The three synchronized vertical scroll columns — signal-names list, waveform canvas, value column — must share one scroll *top* and one `maxScrollExtent`, or the synced scroll clamps at the bottom and **bounces back**, hiding the last lane behind the scrollbar band ("a black bar at the bottom clips the last lane; scrolling reveals it but it snaps back"). Two structural divergences are corrected:

1. **Timeline-overlay strips.** The cocotb strip and the **Pro SVA assertion strip** (10 dp, *always mounted in the Pro build*) render between the time ruler and the canvas lanes — in the **center** pane only. The names list and value column previously did not reserve that height, so their viewports were taller than the canvas's → a smaller `maxScrollExtent` → the synced scroll clamped everyone ~10 dp short of the canvas's last lane (this is why every Pro waveform showed the clip). Both columns now reserve the overlay strips' *rendered* height (invisibly — the strips themselves stay over the canvas), so all three share one top and one extent.
2. **Right pane taller than center pane.** The value column's `IdeLayout` right pane spans the full viewer height while the canvas's center pane is shortened by the center↔bottom resizer (6 dp) and the bottom panel. `WaveformViewCenter` publishes the canvas viewport height (`canvasViewportHeightProvider`) and the value column sizes its scroll region to match.

Setup: in a **Pro build** (SVA strip always present) load a trace with enough lanes to overflow the window (or grow a few lanes tall via the resize handle). Show the value column. (Open-core repros need a timeline overlay active — e.g. an imported cocotb log — to surface divergence 1; divergence 2 is always present.)

1. Scroll the panes all the way to the **bottom**. Confirm the **last** signal lane is **fully visible** in all three columns — its waveform (canvas) and its value (value column) are not clipped by the bottom scrollbar band, and the row does **not** snap/bounce back upward when you reach the end.
2. Confirm the value beside the last lane stays vertically centred on that lane (no half-row drift) at the bottom of the scroll — the failure signature was the value sitting one partial-lane higher than its wave.
3. Open the **bottom panel** (transaction view / Stage — status-bar centre control) so it claims real height, shortening the canvas. Scroll to the bottom again: the value column's values still align with the canvas lanes and the last lane is still fully reachable. The blank region at the very bottom of the value column (beside the bottom panel) is expected — there is no wave there to value.
4. Resize the bottom panel taller/shorter via its splitter, and toggle it off again. Each time, the value column re-matches the canvas viewport; the last lane stays reachable with no residual drift. (With the bottom panel hidden the old gap was just the 6 dp resizer; with it shown the gap equalled the bottom-panel height — both are now corrected.)

#### 17.18.6 Edge cases

- **Raw-vs-clamped cross-platform reopen.** On desktop, resize a lane below 44 dp (e.g. ~20 dp) and save the session. Reopen on desktop → the lane is still ~20 dp (stored raw, rendered at the 16 dp desktop floor). Open the same session on a tablet/phone build → the lane renders at the 44 dp touch floor but the stored value is untouched, so reopening on desktop again restores ~20 dp.
- **200 dp cap.** Dragging a lane very tall stops at 200 dp (enforced by the height *writer*, `setLaneHeight`), and all three columns honour the cap identically.
- **Collapsed group.** Collapsing a group removes its children from all three columns simultaneously; the rows below shift up together with no drift.
- **Value column populates per tab.** With a file open, the value column shows each loaded signal's value beside its lane — at the cursor time, or at the file start when no cursor is set. Open a second tab with a different file and switch between tabs: each tab's value column shows *that* tab's values, never blank. (`signalGroupsProvider` is overridden per tab; the shared lane-geometry model must resolve the active tab's signal list, not the empty root scope, for the value column — which sources its rows from the model — to render. Regression guard for the value-column-blank bug.)

#### 17.18.7 Phone inline-at-cursor value overlay

**What it does.** On phone (and phone-landscape) there is no room for a docked value pane, and the previous design hosted the value column in a Material `endDrawer`. That drawer shipped a modal scrim that intercepted every touch outside it, so the user could not scrub, pan, or pinch the waveform while values were visible — the defining limitation. The values drawer is **removed entirely** and instead draws each visible signal's value *inline on its own lane*, pinned to the cursor's x-position, as a non-modal overlay layered over the canvas (the same `IgnorePointer` pass-through pattern as the cursor overlay). Because the label is part of the lane, it cannot misalign, and because the layer is non-modal, scrub / pan / pinch keep working while values are shown. There is **no settings toggle and no toolbar/chevron affordance** — the surface is automatic: labels appear whenever a primary cursor exists and disappear when it is cleared.

**Setup.** Run a phone build (or an iPhone simulator / a narrow phone-width window). Load a multi-signal VCD with at least one wide bus, e.g. `vcd/vector_formats.vcd` or `protocol/spi/generated/spi_basic.vcd` (the `tx_data` / vector signals give long hex values). Add several signals including the wide bus.

**Steps — labels appear at the cursor, on each lane.**
1. Tap the canvas to place the primary cursor. Verify a value label appears on **every visible signal lane**, horizontally next to the cursor line and vertically centred on that signal's lane band (it sits on the wave it describes, never a row above/below).
2. Confirm scalar signals show their bit (`0`/`1`/`x`/`z`) and bus signals show the formatted value in the signal's display format (hex/dec/…), identical to what the desktop value column would show.
3. Each label has a small built-in legibility scrim/pill behind the text so it stays readable over a busy trace. There is no transparency slider — this is automatic.

**Steps — scrub while values are shown (no freeze — the whole point).**
4. Press and drag horizontally across the canvas. The cursor follows your finger **and** every inline label live-updates to the value at the new cursor time as you drag — the app does **not** freeze or block the gesture (the old drawer scrim is gone).
5. Pinch-zoom and two-finger pan with the cursor placed: the gestures work normally and the labels track the cursor through the zoom/pan.
6. Release. The labels **persist** at the cursor so you can read them after the gesture ends (no "open/close panel" step).

**Steps — placement and edge-flip.**
7. With the cursor near the **left/centre** of the canvas, labels render to the **right** of the cursor line by default.
8. Move the cursor toward the **right edge**. Within a label-width of the edge, the labels **flip to the left** of the cursor so they stay fully on-screen (never clipped off the right edge).

**Steps — long bus values: tap-to-expand.**
9. Find a wide bus whose value is too long to fit — it renders truncated with an ellipsis (`…`).
10. **Tap the truncated label.** It expands in place to show the full value (wrapping within the available width so it stays on-screen).
11. **Tap it again** (or tap a different long label) to collapse it back to the truncated form. This tap is the *only* interactive element of the overlay — it does not interfere with scrub/pan/pinch (a drag starting on a label still scrubs; a long-press still raises the canvas context menu).

**Steps — phone has NO values drawer anymore (regression check).**
12. Confirm there is **no right-edge "value column" chevron** in the phone status bar (the left signal-tree chevron and the bottom-panel control remain).
13. Confirm there is no gesture/affordance that opens a value `endDrawer` — swiping from the right edge does **not** reveal a values panel. The only value surface on phone is the inline overlay.

**Accessibility.** With a screen reader (VoiceOver / TalkBack) focused on the canvas while a cursor is set, the inline values are announced as a **single combined cursor-readout** — the cursor time followed by each visible signal's name and full value — not as one node per lane. The full (untruncated) value is always read regardless of on-screen truncation.

**Edge cases.**
- **No cursor → no labels.** Before any cursor is placed (or after Clear Cursors), no inline labels render.
- **Scrolling the lane list.** With many signals, scrolling vertically keeps each label pinned to its lane; labels for off-screen lanes are not drawn.
- **Tablet/desktop unaffected.** On tablet/desktop the docked value pane (§17.17.1–17.17.6) is used; the inline overlay is phone/phone-landscape only.

#### 17.18.8 Automation Assessment

| Test | Coverage |
|---|---|
| `LaneGeometry` per-row height (signal clamp + fixed group/separator/comment heights) | **UNIT** (`test/services/waveform_geom/lane_geometry_test.dart`) |
| Store-raw-render-clamped: sub-min stored height not flattened; no upper bound (200 cap is the writer's) | **UNIT** (`test/services/waveform_geom/lane_geometry_test.dart`) |
| Cumulative offsets / flatten across signals, expanded + collapsed groups | **UNIT** (`test/services/waveform_geom/lane_geometry_test.dart`) |
| Shared provider returns one instance per equal `LaneMetrics`; recomputes on signal-list change | **UNIT** (`test/features/viewer/providers/lane_geometry_provider_test.dart`) |
| Lane-geometry provider resolves the **active tab's** signal list (scoped to `SignalGroupsNotifier`), so the value column renders per-tab values and is not blank under per-tab provider scopes | **UNIT** (`test/features/viewer/providers/lane_geometry_provider_test.dart` — "resolves the per-tab signal list, not the empty root scope") |
| **Alignment invariant** — signal-names list, canvas, and value column report identical row y-positions across group headers, separators, comments, custom + sub-min lane heights, **and after a resize** | **WIDGET** (`test/features/viewer/widgets/lane_alignment_test.dart` — the regression guard for the original drift bug) |
| **Scroll-extent + top invariant** — names list, canvas, and value column share one scroll top *and* one `maxScrollExtent` **with a timeline overlay active** (names/value reserve the overlay strip height; value matches the canvas viewport for the taller right pane), so the synced scroll reaches the last lane without bounce-back and values stay on their waves | **INTEGRATION_TEST** (`integration_test/canvas/value_column_scroll_alignment_test.dart` — injects a 10 dp overlay via `extraTimelineOverlaysProvider` and asserts all three tops + maxScrollExtents match) + **UNIT** (`canvasViewportHeightProvider` publish/no-op in `test/features/viewer/providers/value_column_provider_test.dart`); perceptual smoothness with the bottom panel open/resized remains **MANUAL** |
| Value column row height sourced from the model (signal clamp; group/separator/comment fixed) | **WIDGET** (`test/features/viewer/widgets/value_column_row_test.dart`) |
| Resize handle writes through `setLaneHeight` (single clamp site); handle tracks the model row boundary | **WIDGET** (`test/features/viewer/widgets/signal_list_panel_test.dart`, `test/features/viewer/providers/signal_group_providers_test.dart`) |
| Live perceptual smoothness of the drag-resize reflow | **MANUAL** — visual feel |
| Cross-platform raw-vs-clamped reopen (desktop ↔ touch) | **HYBRID** — clamp logic covered by unit tests; the save/reopen-on-other-device-class round trip is **MANUAL** |
| **Phone inline overlay** — one label per visible lane at the cursor x, pinned to the lane band; updates as the cursor moves; none when no cursor | **WIDGET** (`test/features/viewer/widgets/inline_cursor_value_overlay_test.dart`) |
| Default right placement + edge-flip to the left near the right edge | **WIDGET** (`test/features/viewer/widgets/inline_cursor_value_overlay_test.dart`) |
| Tap-to-expand a truncated long value, then collapse again | **WIDGET** (`test/features/viewer/widgets/inline_cursor_value_overlay_test.dart`) |
| Gesture-bubbling: truncated label is a translucent, tap-only (no long-press) `GestureDetector`; non-truncated wrapped in `IgnorePointer`; interactive hit surface ≥ 44×44 | **WIDGET** (`test/features/viewer/widgets/inline_cursor_value_overlay_test.dart`) |
| Scrub-through: a horizontal mouse drag with the overlay stacked above still reaches `WaveformGestureHandler` and moves the cursor | **WIDGET** (`test/features/viewer/widgets/waveform_gesture_handler_test.dart`) |
| Single combined cursor-readout semantics (cursor time + each visible signal's full value), not one node per lane | **WIDGET** (`test/features/viewer/widgets/inline_cursor_value_overlay_test.dart`) |
| Phone has no values `endDrawer` (desktop/tablet value pane unaffected) | **WIDGET** (`test/features/viewer/screens/viewer_screen_test.dart`) |
| Inline label locale sweep (en/zh_CN/ja/ko) | **WIDGET** (`test/features/viewer/widgets/inline_cursor_value_overlay_test.dart`) |
| Live perceptual smoothness of inline labels during a real finger scrub on a phone; scrim legibility over a busy trace; VoiceOver/TalkBack reading the combined readout | **MANUAL** — touch/AT feel on a real device |

---

## 18. Cursors, named markers, and the time ruler

### 18.1 What it does

The cursor is the user's "where am I" indicator on the timeline. WaveCrux supports a primary cursor (placed by tap), a secondary cursor (right-click / Shift+tap) for delta-time measurement, and named markers a–z (GTKWave-compatible) that persist across cursor moves. The time ruler renders auto-scaled tick marks and labels appropriate to the current zoom level.

### 18.2 Steps — primary and secondary cursors

1. Load `protocol/spi/generated/spi_basic.vcd`. Tap on the canvas at any point → verify the primary cursor (yellow filled triangle in the time ruler + vertical line through the canvas) places at that point.
2. Right-click at a different point → verify the secondary cursor (outlined triangle) places there. (Right-click is the only secondary-cursor activator; Shift+left-click is reserved for selection drag.)
3. Verify the status bar shows: cursor time, secondary-cursor time, delta time, and frequency (1/delta) — auto-scaled to ns/µs/ms.
4. Move the primary cursor — verify all bound widgets (value column, Stage, FSM viz) update in real time.
5. Clear secondary cursor (Esc or context menu) → verify delta and frequency segments disappear.

### 18.3 Steps — named markers (a–z)

Markers use two-key chords (GTKWave-style), advertised in the command palette as `Set Marker (M + a–z)` and `Jump to Marker (⇧M + a–z)`:

1. Place the primary cursor. Press **M**, then **a** → verify a transient "Set marker: press a–z" hint appears after `M`, and a labeled `a` marker flag (colored downward triangle + letter) appears at the cursor after `a`.
2. Move the cursor and set markers `b`, `c`, `d` the same way (M then the letter). The same chord also works from the command palette / View menu: choosing "Set Marker" arms the chord, then you press the letter.
3. **Any letter completes the chord — order does not matter.** After setting `a` and `b`, set `k` directly (M then `k`). Verify `k` is created (regression guard: there is no "markers must be sequential a, b, c" restriction; the earlier symptom was the focus bug below and/or the ~3 s chord timeout expiring while reaching for a less-familiar key).
4. **Focus independence (the core fix).** Click a toolbar button or open then dismiss a menu so focus leaves the waveform body, then press **M** then a letter → verify the chord still arms and sets the marker. Likewise open the palette with **⌘/Ctrl+⇧+P**, choose "Set Marker", then press a letter → verify it works. (Marker arming is now handled by an app-level global handler, and the bare keys by the viewer's global key handler, so neither is lost when focus sits on chrome.)
4a. **Completing key wins over a colliding navigation key.** Place a cursor, press **M**, then press **q** (which is also the Previous-Transition bare key) → verify a marker `q` is set and the cursor does **NOT** jump to the previous transition. Repeat with **w**/**a**/**s**/**d**/**e** (each a pan/zoom/transition bare key) → in armed-chord state each must set the marker and must NOT trigger its navigation. (Bare-key nav + marker chords share one global handler that checks the armed chord first; they are excluded from the focus `Shortcuts` layer so they cannot double-fire.)
5. Press **M** with **no** primary cursor placed → verify the "Place a cursor before setting a marker" hint and no marker is created. In the **menu / command palette**, "Set Marker" is **greyed out / absent** until a cursor is placed (it gates on a primary cursor).
6. Press **⇧M**, then **c** → verify the cursor jumps to marker `c` and the viewport scrolls to bring it into view. Pressing **⇧M** then a letter with no marker set → "Marker 'x' is not set" snackbar, no crash. In the **menu / command palette**, "Jump to Marker" and "Remove Marker…" are **greyed out / absent** until at least one marker is set (they gate on markers existing, NOT on a cursor).
7. Press **Esc** (or any non-letter) while the "press a–z" hint is showing → verify the chord cancels and the hint clears, with no marker change. The chord also auto-cancels after ~3 s.
8. **Remove a marker** two ways: (a) right-click a marker's flag on the time ruler → "Remove marker c" → it disappears; (b) command palette / View menu → "Remove Marker…" → a picker of the currently-set letters appears, pick one → it is deleted.
9. Verify removing one marker leaves the others untouched. Right-clicking the ruler **away** from any marker still places the secondary cursor (marker removal only triggers on a marker flag).
10. Save the session. Reload. Verify all remaining markers persist with their letters and times.

### 18.4 Steps — time ruler

1. At default zoom, verify major ticks have labeled times (e.g., "100 ns", "200 ns") and minor ticks subdivide.
2. Zoom in 10× → labels auto-rescale to ps/ns. Zoom out 10× → labels rescale to µs/ms.
3. Verify ruler ticks align with the canvas's painted transitions (no visual drift).
4. Tap the ruler at a point → primary cursor places there (same as canvas tap).
5. On touch devices, verify the cursor triangles and marker flags meet the `MobileMetrics` size requirements (§22.4).

### 18.4a Steps — the zoom limits (use a SHORT trace)

The bug this exists to catch only appears on a trace short enough that fit-all
is finer than one tick per pixel — tens of ticks, which is exactly what a
riscv-formal counterexample or any hand-written VCD fixture looks like. A long
trace hides it completely, so **do not** run this on a multi-megabyte capture.

1. Open a short trace (e.g. a `verification/fixtures/riscv_formal/…` trace, or
   any fixture whose whole extent is well under a hundred ticks).
2. **Zoom out, repeatedly, past where it stops changing.** The most zoomed-out
   state must be **fit-all** — the whole trace across the whole canvas. If you
   can reach a viewport wider than the trace (the data crushed into the left
   part of the canvas and a blank expanse to the right, which **Fit All** then
   corrects), that is the defect: the viewer knows the extent and is not
   clamping to it.
3. At that limit, the **Zoom Out** toolbar button, its View-menu row, its
   overflow entry and its command-palette entry are all **greyed out**, and the
   Cmd/Ctrl+`−` shortcut shows *"The whole trace is already visible — zoom out
   is at its limit."* rather than doing nothing. A control that responds and
   produces no visible effect is its own small defect.
4. **Fit All is never greyed**, at either limit — it is the escape hatch.
5. **The mirror case.** Zoom in repeatedly: it stops with a single simulation
   tick across the viewport, and **Zoom In** greys out the same way. Below one
   tick the trace carries no detail to reveal.
6. **Panning.** At any zoom level, pan hard right and hard left (drag, A/D,
   arrow keys, the horizontal scrollbar): the viewport cannot be scrolled clear
   of the data. The trace's end stays reachable at the right edge and its start
   at the left.
7. Repeat 2–6 with the **wheel** (Ctrl/Cmd+wheel), a **trackpad pinch** and, on
   a touch device, a **two-finger pinch**. All of them share the same clamp;
   any one of them reaching past the trace means a control is bypassing the
   mapper.
8. A session **saved before this clamp existed** may carry a zoom level wider
   than its trace. Reopening it must show the trace fitted, not the old blank
   expanse.

### 18.5 Steps — jump to next/previous transition

Transition navigation now requires a primary cursor (strict-cursor gate — it steps relative to the cursor; the old "fall back to t=0" behavior was removed):

1. Place a primary cursor and select a signal. Press Q (previous transition) → cursor jumps to the prior change of that signal.
2. Press E (next transition) → cursor jumps forward.
3. With **no cursor placed**, verify the Prev/Next-Transition **toolbar buttons are disabled** and the menu / palette entries are greyed out / absent; the Q/E keys are inert (no-op).
4. With a cursor but **no signal** selected, the existing "no signal" hint path applies.
5. **Focus independence (bare-key nav).** With a cursor placed and a signal selected, click toolbar/menu chrome so focus leaves the waveform body, then press **Q**/**E** (transition) and **W**/**A**/**S**/**D**/**Z** (zoom/pan) → each must still drive the waveform. These bare-letter keys are handled by the viewer's global key handler, not the focus `Shortcuts` layer, so they no longer go dead when focus is on chrome. (Arrow-key small-pan and Home/End remain focus-scoped by design, to avoid hijacking widget focus traversal.)

### 18.6 Edge cases

- Place secondary cursor at exactly the same time as primary — delta = 0, frequency display either hides or shows infinity safely.
- Set marker on a time outside the visible viewport — viewport pans to bring it in view? Or marker placed silently? Document the chosen behavior and verify.
- Maximum 26 named markers (a–z) — placing a 27th replaces or rejects, never crashes.
- **Cursor cannot land outside the loaded simulation range.** Pan / edge-scroll until pixel 0 of the canvas maps to a time before `t = 0`, then tap to place the primary cursor. Verify the status bar reports `T: 0` (clamped to `startTime`) rather than a negative reading. Symmetrically, pan past `endTime` and tap — the cursor pins to `endTime`. Pre-fix (Issue 30), the iPhone landscape edge-scroll surface let the cursor reach negative time (status bar showed `T: -233 ns` and every value column read `–`). Coverage: `cursor_providers_test.dart` group `CursorStateNotifier — clamps to waveform range (Issue 30)`.
- **Cursors and time ruler stay correct across window resize.** Place a primary and a secondary cursor, then resize the desktop window — drag the edge in and out, and on macOS use a slow live-resize. After the resize settles verify that: the waveform still fills the full canvas width (no data packed into a left-hand strip with empty space on the right), the horizontal scrollbar thumb still reflects the visible fraction, and both cursor lines plus their ruler triangles (yellow primary, blue outlined secondary) land at the time positions the status bar reports. Pre-fix, a dropped post-frame viewport-width update (canvas reparented during an IdeLayout pane reflow on resize, or a coalesced macOS live-resize frame) left `TimeMapper.viewportWidth` stuck at a stale value: the waveform shrank into a strip, the scrollbar thumb shrank, and the secondary cursor / blue ruler marker drew at the wrong x. The resize guard in `WaveformCanvas` now compares the layout width against the live mapper width (not just a local cache), so any divergence self-heals on the next frame. Coverage: `waveform_canvas_test.dart` "resize guard re-syncs TimeMapper after a stale/dropped update".

### 18.7 Automation Assessment

| Test | Coverage |
|---|---|
| Cursor placement and delta computation | **WIDGET** (`test/features/cursors/providers/cursor_providers_test.dart` + `test/features/viewer/widgets/cursor_overlay_test.dart`) |
| Marker placement and persistence | **WIDGET** (`cursor_providers_test.dart`) |
| Marker save/restore round-trip | **WIDGET** (`test/services/session/session_service_test.dart`) |
| Marker M / ⇧M chord state machine | **UNIT** (`test/features/cursors/marker_chord_controller_test.dart`) |
| Marker chord keys reach set/jump dispatch | **WIDGET** (`test/core/shortcuts/shortcut_wiring_test.dart`) |
| Focus-independent arm + complete (any letter, set/jump/cancel) | **UNIT** (`test/features/cursors/providers/marker_chord_providers_test.dart`) |
| Bare-letter nav + marker chords excluded from focus Shortcuts (no double-fire) + resolvable by the global handler | **UNIT** (`test/core/shortcuts/shortcut_wiring_test.dart` — global key-handled set group: each resolves via `globalKeyHandledActionFor`; bare-letter set skipped in the focus-dispatch sweep) + **WIDGET** (`shortcut_manager_widget_test.dart` — manager fixtures use non-global actions) |
| Completing key wins over a colliding bare nav key (M then q → marker, not prevTransition) | **MANUAL** (§18.3 step 4a — `_onKeyEvent` checks the armed chord before bare-key nav; covered piecewise by the coordinator + matcher unit tests) |
| Marker actions gate on cursor (set) / markers (jump, remove) | **UNIT** (`test/core/shortcuts/action_descriptors_test.dart` — "context gating") |
| Transition nav gates on a cursor (no t=0 fallback) | **WIDGET** (`test/features/viewer/widgets/viewer_toolbar_test.dart` — "transition buttons disabled with a file but no cursor") + **UNIT** (`action_descriptors_test.dart`) |
| Remove marker via time-ruler right-click | **WIDGET** (`test/features/viewer/widgets/time_ruler_widget_test.dart`) |
| Time-ruler tick auto-scale across zoom | **WIDGET** (`test/features/viewer/widgets/time_ruler_widget_test.dart` + `test/services/time_format/`) |
| Q/E next-prev transition | **UNIT** (the live `viewer_screen.dart` path calls `WaveformDataSource.nextTransition`/`prevTransition` directly — query covered by `wellen_provider_test.dart`; key binding by `test/core/shortcuts/shortcut_bindings_test.dart`) |
| Jump-to-marker shortcuts | **WIDGET** (`cursor_providers_test.dart` + shortcut binding test) |
| No two shortcuts share an activator (dead-key guard) | **UNIT** (`test/core/shortcuts/shortcut_bindings_test.dart` "no unintended collisions") |
| Every declared shortcut key dispatches an action | **WIDGET** (`test/core/shortcuts/shortcut_wiring_test.dart`) |
| Touch device cursor/marker hit area ≥ 44 dp | **WIDGET** (`time_ruler_widget_test.dart` includes touch-target compliance assertion per ARCHITECTURE.md §3.1.8.11) |
| Resize re-syncs TimeMapper width (cursor/ruler not stuck after a dropped update) | **WIDGET** (`waveform_canvas_test.dart` "resize guard re-syncs TimeMapper after a stale/dropped update"); macOS live-resize feel remains **MANUAL** |

---

## 19. Command palette

### 19.1 What it does

VS Code-style overlay (Ctrl/Cmd+Shift+P) listing every registered `ShortcutAction` searchable by name with localized labels and shortcut bindings displayed inline. Self-registers from the `ShortcutAction` enum — adding a new action automatically makes it discoverable.

### 19.2 Steps

1. Press Ctrl/Cmd+Shift+P. Verify the palette opens centered, focused on the search field.
2. Type a substring (e.g., "diff") → verify the list narrows to matching actions in real time.
3. Verify each result row shows: localized action label, action category (File/View/Navigate/Search/Tools/Help), keyboard shortcut binding (formatted per platform).
4. Use ↑/↓ to navigate the result list. Enter to execute.
5. Press Esc → palette dismisses without executing.
6. Type a query that matches no action → verify a clear "No actions found" empty state.
7. Verify the diagnostics action only appears when `diagnosticsEnabledProvider` is true (debug/profile builds, or release builds with the setting toggled on).
8. Open a file. Open the palette and type "decoder" → verify SPI/I²C/UART/AXI4-Lite/APB actions appear (Open Core build) and the Pro decoders appear with `PRO` chip labels (Pro build).

### 19.3 Locale sweep

Switch app locale to zh_CN, ja, ko. Open the palette. Verify action labels and category names all render translated, and CJK rendering is correct (no glyph boxes, no overflow).

### 19.4 Edge cases

- Mash a high-frequency action (e.g., toggle theme) repeatedly via the palette → no race conditions, no state corruption.
- Open palette with no file loaded → file-dependent actions (zoom, navigate, decoders) appear but execute as no-ops or surface a "no file loaded" notice.

### 19.5 Automation Assessment

| Test | Coverage |
|---|---|
| Palette opens on shortcut | **WIDGET** (`test/features/command_palette/widgets/command_palette_dialog_test.dart` + shortcut binding test) |
| Substring filter | **WIDGET** (`command_palette_dialog_test.dart`) |
| Keyboard navigation (↑/↓/Enter/Esc) | **WIDGET** (`command_palette_dialog_test.dart`) |
| No-results empty state | **WIDGET** (`command_palette_dialog_test.dart`) |
| Each row shows label + category + shortcut binding | **WIDGET** (`command_palette_dialog_test.dart`) |
| Locale sweep on action labels | **WIDGET** (`command_palette_dialog_test.dart` includes locale sweep) |
| Diagnostics gating on `diagnosticsEnabledProvider` | **WIDGET** (`command_palette_dialog_test.dart` — `kDebugMode`-gated visibility) |

---

## 20. Export (VCD / PNG / SVG / clipboard)

### 20.1 What it does

WaveCrux exports the visible state in four ways:

- **VCD export** — write a VCD of selected signals over a chosen time range. Useful for sharing a slimmed-down trace.
- **PNG export** — rasterize the current canvas to a PNG image at a chosen resolution. Useful for design-review slides.
- **SVG export** — vector export preserving text and shapes. Useful for documentation.
- **Clipboard** — right-click → Copy Value (current cursor value) or Copy Full Path of any signal.

### 20.2 Setup

`protocol/spi/generated/spi_basic.vcd` (or any loaded session). The export dialog is reached via Ctrl/Cmd+E or File → Export.

### 20.3 Steps — VCD export

1. Load a VCD with several signals on the canvas. Open Export → choose VCD.
2. Configure: signals = "visible only", time range = "visible viewport". (VCD export has no resolution control — the resolution selector only appears when PNG is the chosen format.)
3. Save. Open the exported file in a text editor and verify it has a valid VCD header (`$date`, `$version`, `$timescale`, `$scope`, `$enddefinitions $end`) and value-change body covering only the chosen signals and time range.
4. Re-open the exported file in WaveCrux → verify it loads cleanly and the values at any sampled cursor time match the source.
5. Export with signals = "all signals", time range = "full simulation". Verify the exported file is a faithful subset (or full copy) of the source.

### 20.4 Steps — PNG export

1. Open Export → choose PNG. Configure resolution (1×, 2×, 3× or absolute pixels).
2. Save. Open the PNG in any image viewer.
3. Verify it renders the visible canvas region at the chosen resolution: signal lanes, time ruler, cursors, decoded transactions, markers.
4. Verify text is legible at 1× and crisp at 2×/3×.

### 20.5 Steps — SVG export

1. Open Export → choose SVG. Save.
2. Open the SVG in a browser, Inkscape, or any SVG-capable viewer.
3. Verify text labels are real text (selectable, scalable) — not rasterized.
4. Verify shapes (signal lanes, transition edges, transaction blocks) are vector primitives.

### 20.6 Steps — clipboard

1. Right-click a signal in the signal list → "Copy Full Path". Paste into a text editor → verify hierarchical path string (e.g., `top.cpu.regs.r0`).
2. Right-click a signal in the value column → "Copy Value". Paste → verify the formatted value at the current cursor time.

### 20.7 Edge cases

- Export VCD with zero signals selected → graceful "select at least one signal" message.
- Export PNG of an empty canvas (no file loaded) → "no content to export" message, not a blank image.
- Export SVG with thousands of signals — file size grows; verify no crash and the file opens.

### 20.8 Automation Assessment

| Test | Coverage |
|---|---|
| VCD export round-trip (export → re-parse → values match) | **WIDGET** (`test/services/vcd_writer/vcd_writer_service_test.dart`) |
| PNG export at known canvas → checksum or pixel-count assertion | **WIDGET** (`test/services/export/image_export_service_test.dart`) |
| SVG export → text preserved | **WIDGET** (`image_export_service_test.dart`) |
| Clipboard copy of value, full path, and JSON-as-transaction | **WIDGET** (`test/features/viewer/widgets/value_column_row_test.dart` + `signal_list_panel_test.dart` + `transaction_table_panel_test.dart`) |
| Empty-state export messages | **WIDGET** (`test/features/viewer/widgets/export_dialog_test.dart`) |

---

## 21. Action discoverability — desktop menu bar and mobile overflow menu

### 21.1 What it does

Closes the discoverability gap between the toolbar and the command palette. On desktop, every `ShortcutAction` appears in a menu bar grouped by `ActionCategory` (File, View, Navigate, Search, Tools, Help) with shortcut bindings shown inline. On mobile, the same grouping appears as a categorized bottom-sheet (phone) or dropdown (tablet) reached via an overflow icon. The toolbar gains explicit next-prev transition buttons.

**Per-platform menu rendering (important).** Flutter's `PlatformMenuBar` only bridges to a native menu on **macOS**; on Windows and Linux it is a silent no-op. `DesktopMenuBar` therefore renders two ways from one menu model:

- **macOS** → native `PlatformMenuBar` (system menu bar at the top of the screen). The FIRST menu is the macOS **application menu** (renamed to "WaveCrux" by the OS) and hosts **About · Settings · Quit**, each in its own separator group.
- **Windows / Linux** → an in-window Material `MenuBar` rendered above the app body. There is no branded app menu: **Settings** and **Quit/Exit** fold into the bottom of the **File** menu and **About** lives in **Help**, matching VS Code / native desktop convention.

**Item order and separators.** Within each menu, the order of items and the placement of divider lines comes from the declarative `kMenuLayout` table (`lib/core/shortcuts/menu_layout.dart`), calibrated against VS Code (File: New · Open · Close · Save/Export · Reset · Collaboration; View: Zoom · Panels · Panes · Theme; etc.). Empty groups (e.g. the Enterprise collaboration block on an open-core build) collapse with no dangling separator.

### 21.2 Setup

Any file loaded.

### 21.3 Steps — desktop menu bar

1. **Menu bar is present on every desktop OS.** On **macOS**, the menu bar is at the top of the screen. On **Windows and Linux**, an in-window menu bar renders above the toolbar. (Regression: prior builds used `PlatformMenuBar` on all three; because it is macOS-only, Windows and Linux showed **no menus at all**. Confirm both Windows and Linux now show a working in-window menu bar.)
2. Click each menu (File, View, Navigate, Search, Tools, Help). Verify the items match the categorization in `lib/core/shortcuts/` and the order/separators in `menu_layout.dart`.
3. Verify each menu item displays its keyboard shortcut on the right side of the row.
4. Verify file-dependent items (zoom, navigate, decoders, export) are disabled when no file is loaded; enabled after open.
5. Click each menu item → verify it dispatches the same action the command palette does.
5b. **Repeated trigger does not stack duplicate modals.** Press a modal-opening shortcut twice in quick succession (or hold the chord so the OS auto-repeats it), e.g. **Tab Diagnostics (⇧⌘I)** or **Export (⌘E)**. Exactly **one** dialog/drawer must appear — not a stack you have to dismiss one-by-one. The same holds for the command palette (⇧⌘P), search (⌘F), App Diagnostics, the decoder picker, Settings, About, and the per-pane Render Stats `i`-icon. Mechanism: each exclusive modal opens through `ModalGuard.run(key, …)`, which suppresses re-entrant opens for the same key until the surface closes (the global `Shortcuts` layer sits above the `Navigator`, so it keeps re-dispatching the open action while a modal already holds focus). Re-opening after closing must still work.
5a. **Menu key-equivalents fire from the keyboard (all three desktop OSes).** With a file loaded, press the accelerators shown next to the items — e.g. **Save Session As… (⇧⌘S / Ctrl+Shift+S)**, **Export (⌘E / Ctrl+E)**, **Tab Diagnostics (⇧⌘I / Ctrl+Shift+I)** — *without* opening the menu. Each must perform its action. **macOS regression (fixed):** on macOS the native `PlatformMenuBar` registers each chord as an AppKit key-equivalent, but AppKit walks `FlutterView.performKeyEquivalent:` before the main menu. A global Flutter `Actions` catch-all used to *consume* every `ShortcutActionIntent` — even ones it had no handler for — so when focus was on chrome rather than the canvas the keystroke was swallowed with no effect and the native menu never fired. The menu *click* still worked, masking it. The catch-all is now enabled only for actions it can actually dispatch, so unhandled chords fall through to the native menu. Verify menu-bound shortcuts work by keyboard regardless of whether you've clicked into the canvas first.
5c. **Keys pressed in a dialog stay in the dialog.** Load a file and click the canvas to place a cursor. Open **Settings** (⌘, / Ctrl+,) and press **Escape**: Settings closes and the cursor is still there. Open Settings again (or the About box, or a right-click menu) and press **W**, **D**, then **M** followed by **a**: the waveform does not zoom or pan and no marker `a` is set. Close the dialog and press **W**: now it zooms. Repeat Escape inside the signal search dialog (⌘F / Ctrl+F): it closes, cursor intact. (Regression: the viewer's bare-key handler listens to the hardware keyboard below focus, so it used to run with a dialog on top — Escape in Settings cleared the cursors and bare navigation keys acted on the waveform behind the dialog. It now does nothing while the viewer's route is not the top route.)
6. **Diagnostics gating:** Diagnostics-related menu items appear only when `diagnosticsEnabledProvider` is true.
7. **Statistics-strip toggle gating:** appears only on desktop class.
8. **Settings placement (regression).** Settings/Preferences must NOT be in the Help menu. On **macOS** it is in the application menu (**WaveCrux → Settings**, above Quit). On **Windows / Linux** it is at the bottom of the **File** menu, above Exit. The Help menu contains only Report Issue and (on Windows/Linux) About.
9. **Logical separators.** Verify divider lines fall at the group boundaries (e.g. File separates the New / Open / Close / Save / Reset blocks; the macOS app menu separates About, Settings, and Quit).
10. **Native-like appearance (Windows / Linux in-window bar).** The Flutter-drawn `MenuBar` is themed (`menuBarTheme` / `menuButtonTheme` / `menuTheme` in `wavecrux_theme.dart`) to read like a native desktop menu rather than the chunky bold Material 3 default:
    - **Left-aligned.** The top-level titles (File, View, …) pack from the **left edge** (just right of the app logo — see §21.10). (Regression: prior builds shrink-wrapped the bar inside a `Column` whose default `CrossAxisAlignment.center` floated the whole strip in the **centre** of the window — the "center-justified menu" defect. Confirm the titles start at the far left.)
    - **Compact, regular weight.** Menu titles and items are ~13 px **regular** weight (not 14 px semibold). Row height is compact, so File / View / Tools fit more items before the dropdown needs to scroll.
    - **Clear hover.** Hovering a top-level title or a dropdown item paints a visible highlight; the pointer/keyboard focus highlight is obvious, not nearly-invisible.
    - **Surface matches the app.** The bar background matches the app surface; dropdown panels use the same surface + 1 px border as the rest of the app's popups.
    - **Tall menus scroll, title stays reachable.** Open a long menu (File / View / Tools) in a short window: the dropdown is scrollable (mouse wheel / two-finger trackpad scroll) and the compact rows keep the menu from overrunning the bar title. Applies identically on **Windows and Linux** (shared in-window `MenuBar` path); **macOS** is unaffected (the OS draws its menu and ignores app `ThemeData`).
    - **Alt-key mnemonics & menu mode (VS Code parity).** Windows/Linux only (the custom `MnemonicMenuBar`):
      - **Hold Alt** → an underline (drawn with a small gap below the letter) appears under one letter of each top-level title (F/V/N/S/T/H — unique per menu).
      - **Tap Alt** (press + release, no other key) → **menu mode**: the underlines *stay* and the first menu (File) takes keyboard focus with a primary-colored outline. **Left/Right** move between menus, **Down/Enter** open + navigate items, **Esc** closes the menu / exits menu mode, and **tapping Alt again** exits. Focus leaving the bar (e.g. a click elsewhere) also exits.
      - **Alt+F / Alt+V / …** (from anywhere) open that menu directly; **in menu mode, a bare letter** opens the matching menu.
      - The `&` marker lives in the localized label, so CJK locales underline the Latin key in e.g. `ファイル(F)`. No conflict with `ShortcutAction` bindings (all Ctrl/Cmd; the only Alt binding is Ctrl+Alt+G). The underline is a single deterministic latch, fixing the earlier every-other-press flicker. macOS is unaffected (native menu).

### 21.4 Steps — mobile overflow action menu

1. On phone, tap the overflow (☰ or ⋮) icon in the app bar. Verify a categorized bottom sheet opens with the same `ActionCategory` groupings.
2. Each item shows its localized label and (if applicable) keyboard shortcut.
3. Tap an item → verify dispatch and sheet dismiss.
4. On tablet, the same affordance opens as a dropdown rather than a bottom sheet — verify presentation matches the device class.
5. **With a file loaded**, verify file-dependent items (Add Protocol Decoder, zoom, export, Close File, …) are **enabled** on both phone and tablet — and grayed only when no file is open. (Regression: the overflow menu lives in the screen-level toolbar at the root scope; it must derive "is a file loaded" from the active tab's filePath, not the per-tab `waveformIsLoadedProvider` which always resolves false there. Reading the root provider greyed out every file action on iPhone/iPad while the toolbar's own Add Decoder button stayed enabled.)

### 21.5 Steps — next/prev transition toolbar buttons

1. On desktop, verify the toolbar has `skip_previous` and `skip_next` icons between the zoom group and the tools group.
2. Tooltips show "Previous Transition (Q)" and "Next Transition (E)".
3. Buttons are disabled when no file is loaded **or no primary cursor is placed** (strict-cursor gate — they now gate via the descriptor, not just `fileLoaded`). With a file + cursor they enable.
4. Click each → cursor jumps to the prior/next transition of the selected signal.

### 21.6 Locale sweep

Switch locale to zh_CN, ja, ko. Verify menu category names, action labels, and tooltip strings are all translated. The macOS native menu bar picks up the localized labels via `PlatformMenuBar`'s built-in support; the Windows/Linux in-window `MenuBar` renders the same localized strings directly.

### 21.7 Single source of truth — `descriptorFor` / `actionContextProvider`

Visibility, enablement, and tier for **all five** surfaces (toolbar, menu bar, overflow menu, command palette, **and the keyboard**) are declared once in `descriptorFor(ShortcutAction)` (`lib/core/shortcuts/action_descriptors.dart`) and gated by the shared `actionContextProvider`. The surfaces consume the derived selectors `groupedActionsFor` / `paletteActionsFor` / `isActionEnabled` only — there is no per-surface "hidden actions" set or `_isEnabled` copy. `action_surface_conformance_test.dart` asserts each *visible* surface matches the table on every platform/scenario; `shortcut_dispatch_conformance_test.dart` asserts the keyboard does too; `descriptorFor` is an exhaustive switch so a new action cannot compile without a descriptor.

**Keyboard parity (WC9-C).** The keyboard used to bypass the table entirely: `_handleShortcut` dispatched straight into the handler, and each handler re-derived its own precondition. Two of those drifted from the descriptors and were user-visible:

- **Jump to Start / Jump to End** guarded only "is the time mapper empty", while the descriptor requires **a file AND a primary cursor**. With a file loaded but no cursor set, the menu item was greyed and the palette omitted the action — yet pressing the key still panned the viewport.
- **Share Session / Join Session** opened their dialogs unconditionally, while the descriptor requires **not already in a session**. `ShareSessionDialog` only noticed the existing session *after* the dialog had been built, so the key could stack a second Share dialog on top of a live collaboration session.

`_handleShortcut` now consults `unmetActionRequirement(action, ref.read(actionContextProvider))` and refuses the action when it returns non-null — one structural guard instead of ~90 hand-written per-handler preconditions.

**Parity AND feedback (WC9-C follow-on).** A keyboard shortcut for a **disabled** action never runs its handler — same as the greyed menu item / inert toolbar button / omitted palette entry. But it is *not silent*: a greyed menu item explains itself by sitting next to its own label, while a dead key just reads as a broken keyboard. So the guard resolves the **unmet requirement** and shows its localized hint in a snackbar.

The reason comes from the descriptor table, not from the handler. `ActionDescriptor.requires` is a list of atomic `ActionRequirement` values (`fileLoaded`, `cursorPresent`, `notInSession`, `multiPane`, …); an action is enabled iff all of them hold, and `unmetActionRequirement(action, ctx)` returns the first that does not. That matters for actions with several preconditions — **Explain Selection** requires a file AND a selection AND a configured model, and each state produces its own message. Requirements are declared most-fundamental-first, so with nothing loaded the answer is "load a waveform file", not "place a cursor".

**Restored regression:** **Add Decoder** with no file loaded again tells the user to load a waveform file (now via the shared `fileLoaded` hint — "Load a waveform file to use this command." — rather than the old decoder-specific string). During WC9-C this guidance was dropped; it is back.

**Storm control:** the same hint is never re-shown while it is already on screen, so holding a disabled key down leaves exactly one snackbar up for its full duration instead of re-animating or queueing one per auto-repeat. A *different* requirement replaces the visible hint immediately.

Behaviors to confirm (all conformance-tested):
- Command palette no longer lists the `setFormat*` family, `Next/Previous Tab`, or `Jump to Tab 1–9`; it omits file-dependent actions until a file is loaded.
- **Context-state gating (new — `actionContextProvider` mirrors the active tab's cursor / markers / diff / cocotb-log / pattern-match / Stage-visible state to the root scope).** Each of these greys out (menu/overflow) or is omitted (palette) until its context exists:
  - **Set Marker, Jump to Start, Jump to End, Clear Cursors, Next/Prev Transition** → require a **primary cursor**.
  - **Jump to Marker, Remove Marker** → require **at least one marker** (NOT a cursor).
  - **Next/Previous Divergence** → require an **active diff** (a second file loaded for comparison).
  - **Next/Previous Pattern Match** → require **at least one pattern-search match**.
  - **Clear Cocotb Log** → requires a **loaded cocotb log**.
  - **Stage Undo / Stage Redo** → require the **Stage panel open**.
- Collaboration actions gate on session state (`Share/Join` only out of session; `Stop Sharing` only while hosting; `Leave Session` only as a non-host; `Export Session Recording` only with a session/recording).
- Phone hides device-gated actions in the overflow (diagnostics, cross-probe, statistics strip, RTL panel, pane ops); `Move Tab to Other Pane` is palette-only.
- Pro/ENT actions show a `WaveCruxFeatureTierBadge` in overflow + palette and a `(PRO)`/`(ENT)` text suffix in the native menu bar.

### 21.8 Edge cases

- **Keyboard vs. menu divergence (WC9-C regression watch).** Load a file, do **not** click the canvas (no primary cursor). Confirm `Home` / `End` do not pan the viewport, the View menu greys "Jump to Start"/"Jump to End", **and** the key press raises the snackbar "Place a cursor in the waveform to use this command." Now click the canvas to set a cursor: both the menu items and the keys work, with no snackbar. Repeat with a live collaboration session open: the Share-Session and Join-Session chords must not open a second dialog, and must instead say "Leave the current session to use this command."
- **Disabled-shortcut hint accuracy.** With nothing loaded, press the Add Decoder chord → "Load a waveform file to use this command." Load a file and press it again → the picker opens. With a file loaded but no signal selected, the Clear Signal Selection chord → "Select at least one signal to use this command." The hint must name the *first missing* precondition, never a later one.
- **Hint storm.** Hold a disabled chord down for several seconds. Exactly one snackbar is on screen at a time and nothing queues up behind it — when you release the key the hint disappears on its own timer rather than replaying once per auto-repeat.
- **Guard staleness watch.** The guard reads the *root-scope* `actionContextProvider`, which mirrors per-tab cursor/marker/diff/cocotb/pattern/Stage flags up from the active tab (`activeTabActionFlagsProvider`). If a future per-tab flag is added to a descriptor predicate but **not** mirrored to the root, the keyboard will go inert for a state the user can plainly see — the failure mode is "shortcut silently stops working after switching tabs". Check any newly-gated action on a *second* tab, not just the first.
- Adding a new `ShortcutAction` in code → it fails to compile until a `descriptorFor` case is added; it then also fails `menu_layout_test.dart` until it is placed in a `kMenuLayout` group, after which it appears automatically in the surfaces its descriptor lists.
- `app`-category actions (Settings, Quit) are placed by `DesktopMenuBar` per platform, not by `kMenuLayout`; `About` is placed under Help by the table but hoisted into the macOS application menu at render time.
- **macOS native-menu key-equivalents must not be swallowed by the Flutter `Shortcuts` layer.** A chord with no global handler (most actions — they are handled by `ViewerScreen`'s per-screen `Actions`) must fall through when the canvas isn't focused so the native menu fires it. The `ShortcutManagerWidget` global catch-all is enabled only for actions present in its `handlers` map; otherwise it returns "not handled" and the key propagates. Regression to watch: a future change that makes that catch-all unconditional again re-breaks every menu-bound keyboard shortcut on macOS while leaving menu clicks working.

### 21.9 Automation Assessment

| Test | Coverage |
|---|---|
| All four visible surfaces conform to `descriptorFor` (presence + enablement + tier) per platform/scenario | **WIDGET** (`test/core/shortcuts/action_surface_conformance_test.dart`) |
| **Keyboard is the fifth surface: firing the shortcut for any descriptor-disabled action invokes no handler AND surfaces that action's own unmet-requirement hint** (table-driven over every `ShortcutAction` the table disables in an impoverished `ActionContext`; asserts no pushed route, no exception, and exactly the expected localized hint) | **WIDGET** (`test/core/shortcuts/shortcut_dispatch_conformance_test.dart`). Verified non-vacuous by mutation: removing the `_handleShortcut` guard fails the sweep. |
| Requirement predicates read the context field they name; `unmetActionRequirement` agrees with `isActionEnabled` and reports the most-fundamental unmet one first | **UNIT** (`test/core/shortcuts/action_requirement_test.dart`) |
| Every requirement hint renders in en / zh_CN / ja / ko with no overflow, and no two requirements share a message | **WIDGET** (`shortcut_dispatch_conformance_test.dart` — "the hint renders in every supported locale") |
| Jump to Start / Jump to End obey file-AND-cursor (not just "mapper non-empty") | **WIDGET** (`shortcut_dispatch_conformance_test.dart` — both actions asserted present in the disabled set, then swept) |
| Share/Join Session cannot open a second dialog from the keyboard while in session | **WIDGET** (`shortcut_dispatch_conformance_test.dart` — `_notInSession` descriptor drives the sweep; the no-pushed-route assertion is what catches it) |
| Add Decoder with no file loaded does not open the picker and *does* restore the load-a-file guidance | **WIDGET** (`test/features/viewer/screens/viewer_screen_test.dart` — "addDecoder shortcut with no file loaded explains itself instead of opening the picker") |
| Held disabled shortcut does not stack duplicate hints | **WIDGET** (`viewer_screen_test.dart` — "holding a disabled shortcut does not stack duplicate hints") |
| Descriptor table totality + per-action visibility/enablement/tier | **UNIT** (`test/core/shortcuts/action_descriptors_test.dart`) |
| `actionContextProvider` derives file/diagnostics/pane/collab state | **WIDGET** (`test/core/shortcuts/action_context_provider_test.dart`) |
| Context-state gating (cursor / markers / diff / cocotb / pattern / Stage) greys out actions that would no-op | **UNIT** (`action_descriptors_test.dart` — "context gating" group) + **UNIT** (`test/features/viewer/providers/active_tab_action_flags_provider_test.dart` — root-scope mirror of the active tab's per-tab flags) |
| Menu bar item enumeration matches `ActionCategory` grouping | **WIDGET** (`test/features/menu_bar/widgets/desktop_menu_bar_test.dart`) |
| Win/Linux menu bar is left-aligned / full-width (not center-justified) | **WIDGET** (`desktop_menu_bar_test.dart` — `linux:`/`windows:` "bar is left-aligned, not centered": asserts the host `Column` uses `CrossAxisAlignment.stretch` and the rendered bar spans >90% of window width) |
| Win/Linux menu theming is native-like (regular weight, 13 px, visible hover, app-surface background) | **UNIT** (`test/core/theme/wavecrux_theme_test.dart` — menu-bar theming group asserts `menuButtonTheme` text is `w400`/13 px, hover overlay non-null when hovered + null idle, disabled foreground dimmed, `menuBarTheme` flat + surface-colored, `menuTheme` matches the popup surface). Visual feel (font rendering, hover timing, scroll smoothness) stays **MANUAL**. |
| Win/Linux top-level menus expose Alt mnemonics (unique F/V/N/S/T/H, `&`-marked, all 4 locales) | **WIDGET** (`desktop_menu_bar_test.dart` — each title is a `MnemonicLabel` with an `&`) + **UNIT** (`action_category_test.dart` — `acceleratorLabel` locale sweep: `&` present + unique mnemonics; app category has none) |
| Alt menu mode: tap-Alt latches underlines + focus; Alt+letter and bare-letter-in-mode open the menu; Esc exits | **WIDGET** (`test/features/menu_bar/widgets/mnemonic_menu_bar_test.dart` — sendKey sequences assert Alt+F opens, tap-Alt+bare-letter opens, Esc exits, bare letter is inert otherwise) + **WIDGET** (`menu_mnemonics_test.dart` — controller latch/visible logic + `MnemonicLabel` underline/plain rendering). Visual feel (underline gap, focus-outline look, real arrow traversal, multi-monitor) stays **MANUAL**. |
| Windows/Linux render an in-window Material `MenuBar` (not the macOS-only `PlatformMenuBar`); macOS renders `PlatformMenuBar` | **WIDGET** (`desktop_menu_bar_test.dart` — `linux:`/`windows:` groups assert `MenuBar` present + `PlatformMenuBar` absent and vice-versa) + **INTEGRATION** (`integration_test/menu_bar/desktop_menu_bar_test.dart` — boots the real app on the host OS and asserts the correct menu-bar widget actually renders; on Win/Linux it also opens View → taps Toggle Theme and asserts end-to-end dispatch. The macOS native `NSMenu` is out-of-view, so the integration test asserts only the bridge widget there; native menu contents/clicks stay **MANUAL**.) |
| Settings in app/File menu (not Help); macOS app menu hosts About·Settings·Quit; Win/Linux fold Settings+Quit into File and About into Help | **WIDGET** (`desktop_menu_bar_test.dart` — "macOS: Settings lives in the application menu, not Help" + "Settings + Quit fold into File, About in Help") |
| Menu order/grouping table covers exactly the menu-visible action set, with no duplicates and category-consistent placement | **UNIT** (`test/core/shortcuts/menu_layout_test.dart`) |
| File-dependent disable states (macOS + Win/Linux) | **WIDGET** (`desktop_menu_bar_test.dart`) |
| Action dispatch from menu (macOS + Win/Linux) | **WIDGET** (`desktop_menu_bar_test.dart`) |
| Global shortcut catch-all does not swallow chords it can't handle (so macOS native-menu key-equivalents fire) | **WIDGET** (`test/core/shortcuts/shortcut_manager_widget_test.dart` — "unhandled-intent fall-through": an unhandled chord propagates to an ancestor key handler; a handled chord is still consumed). End-to-end native `NSMenu` key-equivalent dispatch on macOS stays **MANUAL** (out-of-view; see §21.3 step 5a). |
| Escape, bare navigation keys and the M marker chord do nothing to the waveform while a dialog is on top; Escape in the signal search dialog only closes it | **WIDGET** (`test/accessibility/screen_reader_test.dart` — "keys pressed in a dialog stay in the dialog"; each case ends with a control press proving the keys reach the waveform once the dialog is gone). Verified non-vacuous by removing the route guard: both cases fail. Settings end-to-end stays **MANUAL** (§21.3 step 5c). |
| Repeated modal trigger opens at most one surface (no stacking) | **UNIT** (`test/core/ui/modal_guard_test.dart` — re-entrant `run` with the same key is suppressed; releases on close; re-opens afterward; per-key independence). Per-surface end-to-end stacking stays **MANUAL** (§21.3 step 5b). |
| Mobile overflow sheet/dropdown presentation per device class | **WIDGET** (`test/features/viewer/widgets/viewer_toolbar_test.dart` — "overflow menu" group) |
| Mobile overflow file-dependent gating reads the active tab's filePath (not the root-scope per-tab `waveformIsLoadedProvider`) — Add Decoder et al. enabled when a file is open | **WIDGET** (`test/core/shortcuts/action_context_provider_test.dart` — "fileLoaded follows the active tab filePath"; the overflow's enablement is held to the descriptors by `action_surface_conformance_test.dart`) |
| Next/prev transition toolbar button behavior | **WIDGET** (`test/features/viewer/widgets/viewer_toolbar_test.dart`) |
| New `ShortcutAction` automatically appears in menu / overflow / palette | **WIDGET** (`test/core/shortcuts/` enumeration tests + the menu/overflow/palette tests all derive from the enum) |
| Diagnostics + statistics-strip toggle gated correctly per device class | **WIDGET** (`desktop_menu_bar_test.dart` + `test/features/statistics/widgets/live_statistics_strip_test.dart`) |
| Locale sweep on menu labels | **WIDGET** (`desktop_menu_bar_test.dart` includes locale sweep) |

### 21.10 Custom window chrome (Windows / Linux frameless title bar)

**What it does (plain language).** On **Windows and Linux**, WaveCrux hides the OS-drawn title bar and draws its own slim VS Code-style title strip: the **app logo at the far left**, the **menus inline** next to it, a draggable empty region, and **minimize / maximize-restore / close** buttons at the right. This replaces the tall GNOME/Adwaita header bar (and the redundant Windows caption) so the chrome is one compact strip. Implemented with the `window_manager` plugin (`TitleBarStyle.hidden`) plus the in-window `WindowTitleBar` widget (`lib/features/window_chrome/`); a `VirtualWindowFrame` in the root `MaterialApp.builder` restores the drop shadow and drag-to-resize edges a frameless window loses. **macOS is intentionally excluded** — it keeps its native (hidden-text) title bar and the system menu bar at the top of the screen.

**Setup.** Launch the Windows or Linux build. No file needed.

**Steps.**
1. **No OS title bar.** There is no separate OS-drawn title bar above the app. The single slim strip at the very top is WaveCrux's own. On Linux this replaces the previously oversized GTK header bar.
2. **Logo at top-left, no app-name text.** The app logo (square icon) sits at the far left of the strip; there is no "WaveCrux" / "WaveCrux Pro" text label in the bar.
3. **Menus inline.** File / View / Navigate / Search / Tools / Help render immediately to the right of the logo (compact, left-aligned — see §21.3 step 10).
4. **Caption buttons.** Minimize, maximize/restore, and close render at the far right and behave natively: minimize hides to taskbar; maximize fills the work area and the glyph toggles to "restore"; restore returns to the previous size; close exits.
5. **Drag + double-click.** Click-drag the empty region (or the logo) to move the window. Double-click that region to toggle maximize/restore.
6. **Resize edges + shadow.** With no OS frame, the window still resizes from all edges/corners and casts a drop shadow (provided by `VirtualWindowFrame`). Verify on Linux under **both X11 and Wayland** — programmatic move/resize behavior varies by compositor.
7. **macOS unaffected.** On macOS the native title bar + top-of-screen menu remain; no in-window title bar appears.

**Edge cases.**
- Maximize → restore round-trips keep the maximize glyph in sync even when toggled via OS shortcut (Win+Up / double-click) rather than the button.
- Minimum window size (800×500) is still enforced; chrome never collapses.
- **Leading tab insertion slot vs. the left resize border (Linux).** `VirtualWindowFrame` enables drag-to-resize strips on **all** edges on Linux at an 8 dp `resizeEdgeSize`, so the left strip overlaps the app content's left edge. The tab strip's *leading* insertion slot sits at x∈[0,8] — exactly under that strip — which silently swallowed tab-drop pointer events: "drag a tab **before the first tab**" was a no-op on the Linux build only (reachable on macOS, and on Windows where only the top edges are enabled). The fix insets the tab strip's leading edge past the border on Linux (`windowChromeLeftResizeEdge`, consumed by `ViewerTabBar`). Verify on Linux: drag the second tab to the far left and drop — it lands in the first position. (Note: the inset is a constant on Linux, so a maximized window — which has no resize border — shows a harmless ~8 dp leading gap before the first tab.)
- If the logo asset can't be resolved, the bar degrades to a neutral chart glyph rather than throwing.
- **WSLg / broken-GPU fallback (Linux).** WSLg's default GPU stack (Mesa Zink-on-Dozen/D3D12 Vulkan) is frequently non-conformant and renders a **black window** that looks like "the app won't open" (taskbar entry only, `[WARN:COPY MODE]` title). The Linux runner (`linux/runner/main.cc`) detects WSL (via `/proc/sys/kernel/osrelease` containing `microsoft`/`WSL`) and, unless `LIBGL_ALWAYS_SOFTWARE` is already set, forces Mesa's software rasterizer (`LIBGL_ALWAYS_SOFTWARE=1` + `GALLIUM_DRIVER=llvmpipe`) before any GL context is created. Native Linux installs are untouched (hardware GL). To verify under WSLg: launch the build and confirm a fully-rendered window (not black) with no `libEGL`/`Zink`/`dzn` errors in stderr; a WSL user with working GPU passthrough can opt back to hardware GL by exporting `LIBGL_ALWAYS_SOFTWARE=0`. **MANUAL** (environment-specific; not unit-testable).

**Automation Assessment.**

| Test | Coverage |
|---|---|
| Win/Linux menus are hosted in a left-aligned, full-width `WindowTitleBar` with caption buttons | **WIDGET** (`test/features/menu_bar/widgets/desktop_menu_bar_test.dart` — `linux:`/`windows:` "menus are hosted in a left-aligned, full-width WindowTitleBar") |
| `WindowTitleBar` lays out logo → menus → caption buttons, logo at far left | **WIDGET** (`test/features/window_chrome/widgets/window_title_bar_test.dart`) |
| Caption buttons render (min/maximize/close) and build without a live window channel | **WIDGET** (`test/features/window_chrome/widgets/window_caption_buttons_test.dart`) |
| `useCustomWindowChrome` true on Win/Linux, false on macOS/mobile | **UNIT** (`test/features/window_chrome/window_chrome_platform_test.dart`) |
| `windowChromeLeftResizeEdge` = 8 dp on Linux, 0 elsewhere; tab strip insets the leading insertion slot past it so the first-position drop is reachable on Linux | **UNIT/WIDGET** (`window_chrome_platform_test.dart`; `viewer_tab_bar_drag_reorder_test.dart` "leading insertion slot inset … on Linux" / "flush at x=0 off …") + **INTEGRATION** (`tab_drag_reorder_test.dart` "drag second tab before first") |
| Frameless setup, real drag/resize/maximize, drop shadow, Wayland vs X11 behavior, macOS exclusion at runtime | **MANUAL** (OS-level window-manager integration; not reproducible in widget tests) |

---

## 22. Mobile UI standards (per ARCHITECTURE.md §3.1.8)

### 22.1 What it does

ARCHITECTURE.md §3.1.8 defines mandatory standards for every interactive UI element on touch device classes — sizing, hit targets, drag affordances, gesture rules, splitter behavior, typography, truncated-text reveals. Verification confirms each is honored in the shipped UI.

### 22.2 Setup

A touch device class — physical iPhone/iPad/Android, or a desktop window resized to phone/tablet width. iPad Pro in landscape (≥1200 dp width) still counts as touch host and applies the touch metrics.

### 22.3 Steps — `MobileMetrics` source-of-truth (§3.1.8.1)

1. On desktop class, measure (or inspect via Flutter Inspector) any toolbar button → ~36 dp hit zone, ~18 pt icon.
2. On phone/tablet, the same button is ~48 dp hit, ~24 dp icon. Verify the size jump is automatic with the active device class.
3. Status bar height: 24 dp desktop, 40 dp touch.
4. Panel header height: 32 dp desktop, 44 dp touch.

### 22.4 Steps — touch-target rule (§3.1.8.3)

1. On phone/tablet, every interactive element (icon button, list row, drag handle, color swatch, splitter, cursor marker) has at least a 44 × 44 dp hit area.
2. Test with a finger or pointer-event simulator: tap near the visual edge of small elements (12-dp color swatches, 16-dp marker flags) → action still fires.

### 22.5 Steps — visible drag affordances (§3.1.8.4)

1. Signal-list rows on touch show a right-edge drag-handle icon. Long-pressing the row body does NOT initiate drag (it opens the context menu instead).
2. Lane resize handle visible at the bottom edge of each lane (16 dp strip with grip).
3. Panel splitters paint a 6 dp visible bar (32 dp hit zone on touch).
4. Time-ruler cursor markers are filled triangles with a soft drop shadow on touch (vs outlined on desktop).

### 22.6 Steps — long-press = right-click rule (§3.1.8.5)

1. Long-press a signal-list row → verify the same context menu that right-click produces on desktop opens (Remove, Set Color, Set Format, Set Lane Height, Copy Path, Move to Group).
2. Long-press a signal-tree leaf → Add to Viewer, Copy Full Path.
3. Long-press a cocotb log row → Jump to Time, Copy Message, Copy Timestamp.
4. Long-press the waveform canvas → Place Primary/Secondary Cursor, Clear Cursors, Fit All.
5. Long-press a transaction-table row → Jump to Time, Copy as JSON.

### 22.7 Steps — gesture-bubbling and tooltip rules (§3.1.8.5)

1. In a row that has both an inner `onTap` (e.g., color cycling) and a `PlatformContextMenu`, long-press the row → context menu opens, then dismiss it. Verify the inner `onTap` does NOT fire after dismissal. (Regression catch for opaque-hit-test bug.)
2. In the same row, hover a child with a `Tooltip` (mouse only) → tooltip appears. Long-press the row on touch → context menu opens, NOT the tooltip. (Regression catch for tooltip-vs-context-menu race.)

### 22.8 Steps — panel chevrons in the status bar (§3.1.8.6.1)

1. On tablet/desktop, the status bar shows three chevrons:
   - **Left chevron** at far left → toggles signal tree. Renders `◀` when tree visible, `▶` when hidden.
   - **Center chevron** at geometric center → toggles bottom panel. Renders `▼` visible, `▲` hidden.
   - **Right chevron** at far right → toggles value column. Renders `▶` visible, `◀` hidden.
2. Chevron direction always points where the panel will *move* on tap.
3. Tap each chevron → corresponding panel hides/shows; chevron flips immediately.
4. On phone, chevrons are NOT rendered. Panels are accessed via the overflow menu's toggle actions instead.
5. **Forbidden patterns** (regression catches): no chevron inside a panel header, no edge-tab overlay on the canvas, no `Stack` overlay for panel toggles.

### 22.9 Steps — splitter affordance and pane min-sizes (§3.1.8.6)

> Each tab's four-region IDE layout is rendered by the **shared `crux_ide_layout` package** (`CruxIdeLayout`) — the same widget the rest of the Crux suite uses. WaveCrux keeps its per-tab model (one `CruxIdeLayout` per tab) and supplies a `_WaveCruxIdePanelLayout` adapter that folds the phone-width force-hide (`preference && !isPhone`) and the 120dp center-pane floor in, plus a `CruxIdeLayoutTheme` carrying the `MobileMetrics`-driven splitter sizes. The hand-rolled `_controllerForTab` / `_syncTabControllerToState` / `_onPaneStateChangedForTab` boilerplate is gone; all behavior below (splitter hover/resize, min sizes, phone force-hide, persistence) is unchanged by moving to the shared package.

1. Hover a splitter on desktop with a mouse → cursor changes to resize, splitter color brightens via `resizerHoverColor`.
2. Drag the splitter → adjacent panes resize smoothly.
3. Resize the right pane to its minimum — bottom panel honors its `bottomMinSize` ≥ 80 dp; cannot be re-shown at zero height.
4. Resize the window to phone width (< 600 dp) → all three side/bottom panes force-hide. The user's panel-visibility preference in `PanelLayoutState` is preserved (verify via reload to tablet width).

### 22.10 Steps — status-bar overflow policy (§3.1.8.12)

1. Resize the window to 320 dp wide (smallest valid iPhone SE scene). Verify nothing throws `RenderFlex overflowed by N pixels`.
2. The toolbar's content area scrolls horizontally; the overflow button (☰) stays pinned to the right edge.
3. The status bar's segments scroll horizontally; the stats toggle (desktop) and panel chevrons remain pinned.

### 22.11 Steps — typography scale (§3.1.8.13)

1. Body text in lists/dialogs/menus: 14 sp on touch, 11 pt on desktop.
2. Monospace text in value column / time ruler: 13 sp on touch, 11 pt on desktop. Always `WavecruxColors.monoFontFamily`.
3. Bump OS text scaling to 200 % → verify text grows but is clamped to 1.5× max (per `MediaQuery.withClampedTextScaling`). No `Row` overflows.
4. Reduce OS text scaling to 50 % → text shrinks but clamps to 0.85×, preserving layout density.

### 22.12 Steps — truncated-text reveals (§3.1.8.14)

1. Open a session with a deep hierarchy producing a long signal name (e.g., `top.cpu.regs.gpr.r12_value_extended`). The signal-list row truncates with ellipsis.
2. **Desktop:** hover the truncated name → tooltip shows the full path.
3. **Touch:** long-press the row → context menu's first item is the full path rendered in monospace; dismissing the menu does NOT fire spurious actions.
4. The "Copy Full Path" action remains available below the path header.

### 22.13 Edge cases

- Rotate the device with a context menu open → menu dismisses cleanly, doesn't strand a half-rendered overlay.
- Disable accessibility text scaling → typography reverts to defaults.
- Resize the window with a panel mid-drag → drag terminates cleanly, splitter snaps to legal position.
- **iPhone landscape (`phoneLandscape` device class) hides the inline "+ New Group" signal-list header.** Open any waveform on a phone-landscape surface (≥ 600 dp wide, < 500 dp tall) and verify the signal-list column shows no "+ New Group" affordance immediately below the toolbar — pre-fix (Issue 30), the icon button read as a stray popover floating in the tab-bar region. Group creation remains reachable on phone via the signal-row right-click / long-press context menu and the command palette. Coverage: `waveform_view_center_test.dart` group `hides "+ New Group" header on phone-landscape (Issue 30)` and the matching `shows "+ New Group" header on tablet/desktop` test.

### 22.14 Automation Assessment

| Test | Coverage |
|---|---|
| `MobileMetrics.of(context, deviceClass)` returns correct values | **WIDGET** (covered in core MobileMetrics tests under `test/core/`) |
| Touch-target compliance: every interactive widget ≥ 44 × 44 dp on touch | **WIDGET** (per-widget touch-target tests are mandatory per ARCHITECTURE.md §3.1.8.11; coverage spread across many widget tests) |
| Long-press = right-click on key rows | **WIDGET** (per-row `PlatformContextMenu` tests in respective panel tests); real touch arena **INTEGRATION_TEST — pending** |
| Inner-onTap-after-context-menu-dismissal regression | **WIDGET** (gesture-bubbling regression tests in panel tests) |
| Tooltip vs context-menu trigger-mode regression | **WIDGET** (regression test in row tests; static-analyzable invariant) |
| Panel chevron direction-flip and panel-toggle behavior | **WIDGET** (`test/features/viewer/widgets/status_bar_test.dart`) |
| Splitter `bottomMinSize` ≥ 80 dp (+ left/right ≥ 150, center ≥ 120) | **STATIC** (`test/static/viewer_screen_pane_min_sizes_test.dart` — asserts the `CruxIdeLayout` min-size literals in `viewer_screen.dart`; replaced the former `desktop_layout_min_sizes_test.dart`, which guarded the same constants on the deleted dead `DesktopLayout` — B6) |
| Phone-width force-hide of side/bottom panes | **WIDGET** (`test/features/viewer/screens/viewer_screen_test.dart` — `_syncControllerToState` behaviour) |
| Status-bar overflow at 320 dp width | **WIDGET** (per-chrome 320 × 568 dp surface assertion in `viewer_toolbar_test.dart` + `status_bar_test.dart` per ARCHITECTURE.md §3.1.8.12) |
| Text-scaling clamp at 0.85× / 1.5× | **MANUAL** — applied at the app root (`lib/app.dart` `MediaQuery.withClampedTextScaling` in `MaterialApp.builder`) + around the status bar; the former `adaptive_scaffold_test.dart` reference tested the clamp on the deleted dead `AdaptiveScaffold` (B6), so the live app-root clamp has no automated coverage today (candidate for a small app-root `textScaler` widget test) |
| Truncated-text tooltip + context-menu header | **WIDGET** (`signal_list_panel_test.dart` covers the signal-list pattern; per-call-site coverage via row tests) |

---

## 22.5 Open-core extension seams (Pro overlay integration)

Open-core ships several Riverpod-provider seams through which the closed-source Pro overlay contributes Pro-tier features without forking open-core widgets or services. The seams are *open-core* artifacts — they live in `lib/plugins/` and `lib/core/providers/`, default to no-op or empty values, and are exercised by Pro builds via `proOverrides`. Verification here covers the open-core defaults; Pro behavior is verified in the closed-source Pro overlay's own guide.

### 22.5.1 `timelineOverlayLayersProvider`, `extraTimelineOverlaysProvider`, and `TimelineOverlayLayer`

**What it does (plain language).** The thin coloured strip painted between the time ruler and the waveform canvas (cocotb log markers, Pro SVA assertion outcomes, future coverage-hit markers) is a registry of `TimelineOverlayLayer` instances. Each contributed layer has a stable id, an integer priority that controls vertical paint order, a fixed reserved height, and a `build` method that returns the widget the host mounts. The host (`WaveformViewCenter`) watches the unified `timelineOverlayLayersProvider`, which combines the open-core default (the cocotb log strip, registered through `CocotbTimelineOverlayLayer`) with whatever the Pro overlay contributes via `extraTimelineOverlaysProvider`, sorts the union by ascending priority (lowest paints closer to the time ruler, highest closer to the canvas), and stacks each layer's widget in order. Fixed-height children enter the layout-budget logic: when the bottom panel is dragged up to its limit, layers are dropped in reverse paint order — scrollbar first, then the highest-priority layer down to the lowest — so the time ruler and a usable canvas band stay visible.

**Setup.** Open-Core build with no Pro overlay; load any waveform fixture (e.g. `vcd/scalar_basics.vcd`).

**Step-by-step expected behavior.**

1. Open the file. Confirm the cocotb strip slot stays empty (no log loaded) and the waveform canvas extends from immediately below the time ruler down to the horizontal scrollbar.
2. Load `cocotb/basic_log.txt`. Confirm the cocotb strip appears at the historical 8 dp height directly below the time ruler.
3. Drag the bottom-panel splitter up until the splitter hits the canvas's 120 dp `centerMinSize`. Confirm the cocotb strip disappears (per the unified layout-budget logic in `WaveformViewCenter`) before the time ruler does — the registry-driven path preserves the previous drop-order behavior.

**Diagnostics-assisted verification.** Provider-level: `flutter test test/plugins/timeline_overlay_layers_provider_test.dart` confirms the open-core default exposes the cocotb layer, and that contributed extras are merged and sorted by ascending priority. `flutter test test/plugins/extra_timeline_overlays_provider_test.dart` confirms the extras seam itself defaults to an empty list and that `overrideWithValue` replaces it. Interface-level: `flutter test test/plugins/timeline_overlay_layer_test.dart` confirms a stub layer's `id`, `priority`, `height`, and `build` are exposed correctly. Adapter-level: `flutter test test/features/cocotb/widgets/cocotb_timeline_overlay_layer_test.dart` confirms `CocotbTimelineOverlayLayer` reports `id="cocotb"`, `priority=100`, height matching the historical strip, and that its `build` returns a `CocotbTimelineOverlay`.

**Tier-gate scenarios.** None — the seam itself is open-core. Layers contributed by Pro carry their own gating; that is verified in the Pro guide.

**Automation Assessment.**

| Test | Coverage |
|---|---|
| Open-core default returns the cocotb layer | **WIDGET** (`test/plugins/timeline_overlay_layers_provider_test.dart`) |
| Extras seam defaults to empty list | **WIDGET** (`test/plugins/extra_timeline_overlays_provider_test.dart`) |
| Cocotb adapter id/priority/height + build | **WIDGET** (`test/features/cocotb/widgets/cocotb_timeline_overlay_layer_test.dart`) |
| Combined list sorts by ascending priority | **WIDGET** (`test/plugins/timeline_overlay_layers_provider_test.dart`) |
| Layer interface — id / priority / height / build | **WIDGET** (`test/plugins/timeline_overlay_layer_test.dart`) |
| Layout budget: layers drop in reverse paint order under tight height | **MANUAL** (visual; integration coverage as part of `WaveformViewCenter` overflow tests) |
| Pro SVA overlay paints above cocotb strip | **In Pro repo's** `verification/VERIFICATION_GUIDE.md` |

### 22.5.2 `extraBottomDockTabsProvider` and `BottomDockTab`

**What it does (plain language).** The bottom dock currently shows one of: Stage panel, FSM bubble diagram, X-Trace report, switching-activity report, cocotb log panel, or the default transaction table — a priority chain inside `_buildBottomPanelContent`. `extraBottomDockTabsProvider` lets the Pro overlay (and any future open-core feature) contribute additional panels into this chain without forking the viewer. Each contributed `BottomDockTab` carries its own visibility provider, license-tier gate, ARB-driven label, icon, and panel builder. The host inserts contributed tabs between the cocotb panel (priority-wise above contributors) and the transaction table (the fallback). License-tier gating routes through `FeatureGate.isAvailable`, which short-circuits to allow during the public beta and consults `licenseTierProvider` post-beta.

**Setup.** Open-Core build with no Pro overlay; load a waveform fixture.

**Step-by-step expected behavior.**

1. Confirm the bottom panel shows the transaction table by default (toggle it visible if not).
2. Confirm none of Stage / FSM / X-Trace / Activity / cocotb take over the bottom panel.
3. Toggle Stage on — confirm the Stage panel takes over.
4. Toggle Stage off, load a cocotb log — confirm cocotb log panel takes over.
5. Confirm no errors are logged about an empty `extraBottomDockTabsProvider`. The seam is silently inert in Open-Core builds.

**Diagnostics-assisted verification.** Provider-level: `flutter test test/plugins/extra_bottom_dock_tabs_provider_test.dart` confirms the default empty list and override behavior. Model-level: `flutter test test/plugins/bottom_dock_tab_test.dart` confirms equality is by id, the default `requiredTier` is `LicenseTier.openCore`, and the model is `@immutable`.

**Tier-gate scenarios.**

- `kBetaPeriod = true` (current beta): every contributed tab activates regardless of `requiredTier` — the open-core viewer's `FeatureGate.isAvailable` short-circuits to `true`. Pro tabs render even on Open-Core builds *if* the Pro overlay is installed; the Open-Core distribution itself does not contribute Pro tabs because `proOverrides` is not loaded.
- `kBetaPeriod = false` (post-beta): a contributed tab with `requiredTier: LicenseTier.pro` is rendered only when `licenseTierProvider` resolves to `pro`, `edu` (Pro-feature-equivalent), or `enterprise`. Open-Core users see the transaction table fallback instead — the seam never falls through silently to a broken state.

**Automation Assessment.**

| Test | Coverage |
|---|---|
| Open-core default returns empty list | **WIDGET** (`test/plugins/extra_bottom_dock_tabs_provider_test.dart`) |
| Equality of `BottomDockTab` by id | **WIDGET** (`test/plugins/bottom_dock_tab_test.dart`) |
| Default `requiredTier` is `LicenseTier.openCore` | **WIDGET** (same file) |
| `_buildBottomPanelContent` priority chain end-to-end | **WIDGET — pending** (broader viewer integration covers this indirectly today) |
| Tier-gate during beta vs post-beta | **In Pro repo's** `verification/VERIFICATION_GUIDE.md` for the Pro SVA tab |

### 22.5.3 `svaPanelTogglerProvider`

**What it does (plain language).** The `ShortcutAction.toggleSvaPanel` action (Cmd/Ctrl+Shift+V) is dispatched in open-core through this provider. The open-core default is a no-op `void Function(BuildContext)` — Open-Core builds expose the action for discoverability through the menu bar, overflow menu, and command palette, but invoking it without the Pro overlay simply does nothing. The Pro overlay overrides this provider with a callback that flips the SVA panel's visibility provider so the bottom-dock priority chain picks it up via `extraBottomDockTabsProvider`. Pattern mirrors `debugAdvisorPanelOpenerProvider`.

**Setup.** Open-Core build, any waveform loaded.

**Step-by-step expected behavior.**

1. Press Cmd/Ctrl+Shift+V. Confirm nothing happens, no exception, no console error.
2. Open the command palette (Cmd/Ctrl+Shift+P), type "SystemVerilog". Confirm the action label "Toggle SystemVerilog Assertion Panel" appears.
3. Open the View menu (or mobile overflow menu). Confirm the action label appears in the View category.
4. Confirm the action's keyboard shortcut is rendered as Cmd/Ctrl+Shift+V (the original Cmd/Ctrl+Shift+A is taken by `analyzeSwitchingActivity`; the documented alternative is V for "Verification").

**Automation Assessment.**

| Test | Coverage |
|---|---|
| Default is a no-op callable | **WIDGET** (`test/core/providers/sva_panel_toggler_provider_test.dart`) |
| `overrideWithValue` replaces the default | **WIDGET** (same file) |
| `ShortcutAction.toggleSvaPanel` in enum + label resolver + binding + category | **WIDGET** (`test/core/shortcuts/shortcut_action_test.dart`, `shortcut_bindings_test.dart`, `action_category_test.dart`) |
| End-to-end Cmd/Ctrl+Shift+V dispatch on Pro builds | **In Pro repo's** `verification/VERIFICATION_GUIDE.md` |

### 22.5.4 User-contributed decoder plugin loader (`FfiDecoderLoader` + `examples/decoder-plugin-demo/`)

**What it does (plain language).** Open-core ships a `dart:ffi`-backed loader that scans the per-user plugin directory at startup, opens every `.so` / `.dylib` / `.dll` file via `DynamicLibrary.open`, validates each plugin's ABI version against the C header at [`include/wavecrux_decoder.h`](../include/wavecrux_decoder.h), reads the JSON manifest, and registers each contributed decoder into `DecoderRegistry.instance`. Plugins can be written in any language that emits a stable C ABI; the canonical reference is the 1-Wire decoder at [`examples/decoder-plugin-demo/`](../examples/decoder-plugin-demo/) (C) plus the Rust port at [`examples/decoder-plugin-demo-rust/`](../examples/decoder-plugin-demo-rust/). The loader feeds signal values into each plugin's `WcSample.bits_ptr` using the documented 4-state encoding (2 buffer bits per signal bit, low = level, high = unknown flag) and converts tick timestamps to femtoseconds via the file's `Timescale` so plugin authors get physical units. Per-plugin failure isolation is mandatory — a malformed manifest, ABI mismatch, missing symbol, or load failure must never break app startup; it surfaces as a non-`loaded` row in `Settings → Decoders → Plugins` instead.

**Setup.** Linux or macOS desktop with a C toolchain installed. From the open-core repo root:

```bash
cd examples/decoder-plugin-demo
make
```

Copy the produced `libwavecrux_onewire.so` / `.dylib` to the per-user plugin directory:

* Linux: `~/.config/wavecrux/decoders/`
* macOS: `~/Library/Application Support/wavecrux/decoders/`
* Windows: `%APPDATA%\WaveCrux\decoders\` (build via CMake — see the demonstrator README)

…or set `WAVECRUX_DECODER_PATH` to any directory containing the artifact.

**Step-by-step expected behavior.**

1. **First-launch acknowledgment.** Open WaveCrux. The first time the loader discovers any plugin, a one-time prompt appears explaining that plugins run as native code with full process privileges. Acknowledge it. The acknowledgment persists in `AppSettings.pluginSafetyAcknowledged`.
2. **Settings → Decoders → Plugins panel.** Open Settings, navigate to Decoders → Plugins. Confirm the demonstrator is listed:
    * Display name: `1-Wire (demo plugin)` — the demonstrator contributes a single decoder and does not export the optional ABI 1.1 `wavecrux_decoder_plugin_name` symbol, so the card title falls back to that one decoder's display name.
    * Decoder ID line containing: `examples.onewire`
    * Status: `loaded`
    * ABI: `1.1` (the header version the demonstrator is built against; the loader only enforces a matching MAJOR, so a plugin built against `1.0` still loads and reports `1.0`).
    * Decoder count line: `1 decoder`.

   **Plugin self-identification (ABI 1.1).** A plugin that contributes many decoders can name itself rather than borrowing its first decoder's display name. When a plugin exports the optional `wavecrux_decoder_plugin_name` / `wavecrux_decoder_plugin_description` entry points (see [`include/wavecrux_decoder.h`](../include/wavecrux_decoder.h)), the card title shows the plugin-reported name, an optional description line appears beneath it, and the decoder-count line reads e.g. `111 decoders`. The SigRok bridge (§22.5.4.1) is the reference exerciser of this path; the loader fixture `test_plugin_named` covers it in automation.
3. **Decoder appears in picker.** Open a VCD that has a `dq` signal (or use [`examples/decoder-plugin-demo/fixtures/onewire_basic.vcd`](../examples/decoder-plugin-demo/fixtures/onewire_basic.vcd)). In the decoder picker, confirm `1-Wire (demo plugin)` appears under the User-Contributed group.
4. **Round-trip.** Add the decoder, bind `dq` to the VCD's `dq` signal, apply. Confirm the transaction table shows: `RESET` at ~100 µs, `PRESENCE` at ~630 µs, `BYTE 0x33` at ~810 µs, `BYTE 0x28` at ~1.43 ms. The decoder output must match [`examples/decoder-plugin-demo/fixtures/onewire_basic.expected_transactions.json`](../examples/decoder-plugin-demo/fixtures/onewire_basic.expected_transactions.json) byte-for-byte after canonicalisation.
5. **Disable toggle.** In Settings → Decoders → Plugins, toggle the demonstrator's per-plugin disable switch. Click Reload plugins. Confirm:
    * The plugin row stays in the panel with status `disabled`.
    * The decoder no longer appears in the decoder picker.
    * Re-enabling and reloading restores both.

**Diagnostics-assisted verification.** Loader unit tests: `flutter test test/services/decoders/ffi/ffi_decoder_loader_test.dart` exercises the load / ABI-mismatch / missing-symbol / corrupt-manifest / per-plugin-failure-isolation / env-var override / duplicate-id rejection / pluginLoadingDisabled / perPluginDisabled / category-listing paths against the small `test_plugin*` C fixtures committed under `test/fixtures/decoder_plugins/`. Round-trip integration test: `flutter test test/services/decoders/ffi/onewire_demo_integration_test.dart` builds the demonstrator, loads it through `FfiDecoderLoader`, parses the fixture VCD via `DartVcdProvider`, and asserts the decoded transactions match the expected-transactions JSON byte-for-byte. Settings panel test: `flutter test test/features/settings/widgets/decoder_plugins_panel_demo_integration_test.dart` pumps the panel with a real loader and asserts the demonstrator's row renders correctly under both enabled and disabled states.

**Edge cases.**

- *Stale plugin from a previous install.* The loader ignores files whose extension is not in `{.so, .dylib, .dll}`, so a `libwavecrux_onewire.dylib.bak` file in the plugin directory is silently skipped. A malformed binary that fails `dlopen` reports `loadError` with the OS error in `errorMessage` and proceeds to the next file.
- *ABI mismatch.* A plugin built against a future ABI MAJOR fails the version check; the row reports `abiMismatch` with a clear message naming the host's MAJOR. Reload Plugins after rebuilding the plugin against the matching `wavecrux_decoder.h`.
- *Manifest missing required keys.* A plugin whose `manifest_json` is malformed JSON or whose `signals` array is missing reports `manifestInvalid`; the row's diagnostic message names the validation failure.
- *Two plugins claiming the same id.* The first `wavecrux_decoder_register` to claim a decoder id wins; subsequent claims surface `loadError` with `errorMessage` containing "already taken" so the user can rename one of the conflicting plugins.
- *Custom plugin directory via `WAVECRUX_DECODER_PATH`.* Setting the env var (colon-separated on Unix, semicolon-separated on Windows) prepends those directories to the search path. Relative paths in the env var are rejected with a logged warning so plugins cannot accidentally resolve from the current working directory.

**Tier-gate scenarios.** None — the loader, ABI, and demonstrator all live in open-core. Any decoder a user-contributed plugin registers carries `LicenseTier.openCore` by default and is unlocked on every WaveCrux build, regardless of the active license tier. The Enterprise plugin governance layer (signing, allowlists, on-prem registry) is separate and lives in the Pro overlay.

**Automation Assessment.**

| Test | Coverage |
|---|---|
| Loader scan / ABI-mismatch / missing-symbol / manifest-invalid / per-plugin-failure-isolation | **AUTOMATED** (`test/services/decoders/ffi/ffi_decoder_loader_test.dart`) |
| End-to-end round-trip against the 1-Wire demonstrator | **AUTOMATED** (`test/services/decoders/ffi/onewire_demo_integration_test.dart`) |
| Settings panel renders the demonstrator's loaded / disabled rows | **AUTOMATED** (`test/features/settings/widgets/decoder_plugins_panel_demo_integration_test.dart`) |
| Plugin-card decoder count + ABI 1.1 self-reported name / description | **AUTOMATED** (loader: `ffi_decoder_loader_test.dart` "uses the ABI 1.1 plugin name/description…" + the `test_plugin_named` fixture and the no-symbol fallback in the passthrough case; panel: `decoder_plugins_panel_test.dart` count/description render + populated-card locale sweep) |
| Decoder appears in the decoder picker after load | **MANUAL** — covered indirectly by `DecoderRegistry.listByCategory` returning the user-plugin entry, but the picker UI is not test-pumped here |
| First-launch acknowledgment dialog | **AUTOMATED** (`test/features/settings/widgets/plugin_safety_dialog_test.dart`) |
| Cross-platform `.so` / `.dylib` / `.dll` discovery | **MANUAL** — automated coverage exists for the host platform; cross-platform smoke is part of §23.1 |
| `WAVECRUX_DECODER_PATH` override + relative-path rejection | **AUTOMATED** (`test/services/decoders/ffi/plugin_directory_resolver_test.dart`) |

### 22.5.4.1 SigRok bridge plugin (separate `wavecrux-sigrok-bridge` repo, GPLv3+)

**What it does (plain language).** The SigRok bridge is the production-grade conformance test for §22.5.4: a downloadable, opt-in plugin that brings the 130+ protocol decoders maintained by the SigRok community (`libsigrokdecode` + the upstream Python decoder corpus) into WaveCrux. It is *not* a built-in WaveCrux feature and is not bundled with the WaveCrux installer. Users download a release archive from the bridge's separate GitHub repository (`wavecrux/wavecrux-sigrok-bridge`), drop the shim binary into their per-user plugin directory, and put the subprocess binary on `PATH` (or alongside the shim). On next launch every advertised SigRok decoder appears in WaveCrux's decoder picker as `sigrok.<protocol>` (e.g. `sigrok.onewire`, `sigrok.jtag`).

**Why it lives outside both WaveCrux repos.** `libsigrokdecode` is GPLv3+. WaveCrux open-core is Apache-2.0 (post-beta) and the Pro overlay is closed-source commercial; neither can link GPL code. The bridge solves this with a process boundary: the **shim** that loads into the WaveCrux process is GPLv3+ but contains no `libsigrokdecode` or `libpython` linkage; the **subprocess** that does host those libraries is a separate executable that talks to the shim via length-prefixed JSON over a pipe. The four license-isolation invariants (separate repo, process boundary, separate distribution, explicit GPL notice) are reproduced verbatim in the bridge's README and CLAUDE.md. CI gate `tool/verify_isolation.sh` mechanically rejects any build where the shim picks up a forbidden GPL dependency.

**Setup.** Desktop only (Linux, macOS, Windows). Requires Python 3.10+ and a `libsigrokdecode` runtime install on the host:

* Linux (Debian/Ubuntu): `sudo apt install libsigrokdecode4 libsigrokdecode-dev sigrok-cli`
* macOS (Homebrew): `brew install libsigrokdecode`
* Windows: the release archive bundles `libsigrokdecode`, the SigRok decoder corpus, and the official Python embeddable distribution

Then download and install the bridge:

1. Pull the latest archive from <https://github.com/wavecrux/wavecrux-sigrok-bridge/releases> matching your OS+architecture.
2. Verify the SHA256 against the `.sha256` companion file.
3. Extract the archive. Copy the shim library (`libwavecrux_sigrok_bridge_shim.{so,dylib}` / `wavecrux_sigrok_bridge_shim.dll`; named `libwavecrux_sigrok_bridge.*` in the v0.1.0 release) into the per-user plugin directory listed in §22.5.4 ("Setup"). Place `wavecrux-sigrok-bridge[.exe]` either in the same directory (sibling install — recommended) or anywhere on `PATH`. Alternatively set `WAVECRUX_SIGROK_BRIDGE` to an absolute path to the subprocess binary.
4. Restart WaveCrux.

**Step-by-step expected behavior.**

1. **First-launch acknowledgment.** The same one-time native-code-plugin prompt from §22.5.4 fires. Acknowledge it; the acknowledgment persists.
2. **Settings → Decoders → Plugins panel.** The bridge appears as one row. Because the shim exports the optional ABI 1.1 `wavecrux_decoder_plugin_name` / `wavecrux_decoder_plugin_description` entry points, the card title reads **WaveCrux SigRok Bridge** (not the alphabetically-first decoder's name, e.g. "Audio Codec '97"), the GPLv3+ notice (invariant 4) appears in the description line beneath it, and the decoder-count line reads the full advertised count (e.g. `111 decoders` against a real `libsigrokdecode`, or `5 decoders` on the mock-mode build). Status `loaded`, ABI `1.1`. On a real build the advertised ids are the upstream corpus (`sigrok.onewire_link`, `sigrok.jtag`, …); on the mock build they are the five reference decoders (`sigrok.onewire`, `sigrok.jtag`, `sigrok.pwm`, `sigrok.dmx512`, `sigrok.modbus`).
3. **Decoders appear in picker.** Open any VCD with a 1-Wire `dq` signal (the bridge repo's [`test/fixtures/onewire/onewire_basic.vcd`](https://github.com/wavecrux/wavecrux-sigrok-bridge/blob/main/test/fixtures/onewire/onewire_basic.vcd) works). In the decoder picker confirm `sigrok.onewire` appears under the User-Contributed group.
4. **End-to-end decode for the five reference decoders.** Apply each of the five reference decoders to its committed fixture VCD from the bridge repo's `test/fixtures/<decoder>/` directory:
    * `sigrok.onewire` → `onewire/onewire_basic.vcd` → expect RESET / Presence, READ ROM (0x33), ROM byte stream
    * `sigrok.jtag` → `jtag/jtag_idcode.vcd` → expect TEST-LOGIC-RESET, IR=0x09 IDCODE, DR=0x1234ABCD
    * `sigrok.pwm` → `pwm/pwm_steps.vcd` → expect duty=25.0%, then duty=75.0%
    * `sigrok.dmx512` → `dmx512/dmx_two_slots.vcd` → expect BREAK, MAB, slot 0 start code, slot 1 = 0xFF, slot 2 = 0x80
    * `sigrok.modbus` → `modbus/modbus_read_holding.vcd` → expect Read Holding Registers, fn=0x03, CRC ok
   For each, the transaction table must match the corresponding `<fixture>.expected_transactions.json` file shipped alongside the VCD, modulo libsigrokdecode's annotation-label wording differences (see "Edge cases" below).
5. **Subprocess crash recovery.** While a decode session is active, `kill -9 $(pgrep wavecrux-sigrok-bridge)`. Confirm WaveCrux does not crash; the active session reports an error transaction; the next decoder activation respawns the subprocess transparently.
6. **Disable toggle.** In Settings → Decoders → Plugins, toggle the bridge's per-plugin disable switch. Click Reload plugins. Confirm every `sigrok.*` decoder disappears from the picker; re-enabling restores the full set.

**Diagnostics-assisted verification.** The bridge repo runs its own end-to-end test suite (`crates/bridge/tests/end_to_end.rs`) on every CI push, exercising the full IPC contract against the mock backend and asserting acceptance for the five reference decoders. From WaveCrux's side, the smoke test [`test/services/decoders/ffi/sigrok_bridge_smoke_test.dart`](../test/services/decoders/ffi/sigrok_bridge_smoke_test.dart) is gated on the bridge being installed (skipped automatically when the shim is absent) and confirms WaveCrux loads the bridge without ABI errors and that the reference decoders (`sigrok.jtag` / `sigrok.pwm` / `sigrok.dmx512` / `sigrok.modbus`, plus a 1-Wire decoder — `sigrok.onewire` on the mock build or `sigrok.onewire_link` on a real `libsigrokdecode` build) appear in `DecoderRegistry.listByCategory`. It then opens a `sigrok.pwm` instance and decodes a square wave through it, which fails if the host's `create` configuration lacks `decoder_id` or the shim frees transaction strings early (bridge releases up to v0.1.1 do). The host's configuration contract itself runs on every CI push in `test/services/decoders/ffi/ffi_decoder_loader_test.dart`. The release archive's `wavecrux-sigrok-bridge --list-decoders` produces a JSON dump of every advertised decoder, useful for diagnosing "I installed it but nothing appears in WaveCrux."

**Edge cases.**

- *Subprocess missing.* The shim's plugin row reports zero advertised decoders with status `loaded` and a one-line diagnostic naming the missing binary. WaveCrux behaves as if the bridge were not installed.
- *ABI mismatch.* The shim and WaveCrux loader disagree on ABI MAJOR. The plugin row reports `abiMismatch` with the host's MAJOR named. Update the bridge to match WaveCrux.
- *libsigrokdecode missing or wrong version.* The subprocess fails its `srd_init` and exits with a non-zero status. The shim treats the subprocess as unavailable and surfaces the failure in the plugin row's diagnostic.
- *Mock-vs-real annotation labels.* When the bridge ships in mock mode (default), annotation labels are exact-match against the committed `.expected_transactions.json` companions. When the bridge ships built with `--features sigrok` against a real `libsigrokdecode`, annotation label wording may differ slightly because the upstream Python decoders own their own user-facing strings. The verification expectation is "the *kind* and *time range* of every annotation matches"; exact wording differences are acceptable.
- *Indeterminate (X/Z) sample bits.* Default policy emits a `glitch` annotation and skips the sample. The per-decoder configuration dialog exposes an `xz_policy` option that can be set to `coerce_last` to substitute the previous determinate value; useful for traces with brief X-storm regions during reset.

**Tier-gate scenarios.** None — every decoder the bridge advertises carries `LicenseTier.openCore`. The bridge is a user-contributed plugin from WaveCrux's perspective and the decoders it surfaces are unlocked on every build regardless of the active license tier. The four license-isolation invariants are independent of WaveCrux's own tier system.

**Automation Assessment.**

| Test | Coverage |
|---|---|
| Bridge IPC contract (length-prefixed JSON, request/response/event ordering) | **AUTOMATED** in the bridge repo (`crates/bridge/tests/end_to_end.rs`, runs on every CI push) |
| Mock backend acceptance for the five reference decoders | **AUTOMATED** in the bridge repo (mock-mode integration test asserts annotation set per fixture) |
| Shim has no GPL linkage / symbols (license-isolation invariant 2) | **AUTOMATED** in the bridge repo (`.github/workflows/isolation.yaml` runs `tool/verify_isolation.sh` on every push) |
| WaveCrux loads the bridge without ABI errors | **AUTOMATED** (`test/services/decoders/ffi/sigrok_bridge_smoke_test.dart`, gated on `which wavecrux-sigrok-bridge`) |
| Real libsigrokdecode-backed decode for the five references | **MANUAL** — depends on the host having `libsigrokdecode` installed; bridge CI runs the `--features sigrok` build on a libsigrokdecode-equipped Linux runner |
| Subprocess crash recovery (mid-session kill, automatic respawn on next activation) | **MANUAL** — exercised by the verification step above; an automated kill-and-respawn integration test is queued for the bridge repo |
| Cross-platform install walkthrough | **MANUAL** — covered by §23.1 per-platform smoke |

---

## 22.6 About Box

### 22.6.1 What it does

The About Box is a single dialog (open-core) that surfaces app identity and legal information every WaveCrux user can reach. On macOS it lives under **WaveCrux → About WaveCrux**; on Windows/Linux under **Help → About WaveCrux**; on mobile under **Settings → About**. It exposes three open-core extension-point providers (`applicationBuildInfoProvider`, `applicationBrandingProvider`, `applicationEditionProvider`) so the Pro overlay can override the edition label and branding without forking the dialog.

The dialog is rendered by the **shared `crux_about_dialog` package** (`CruxAboutDialog`) — the same surface the rest of the Crux suite uses. `WaveCruxAboutDialog.openAdaptive` is a thin builder that maps WaveCrux's branding / build-info / edition providers and ARB strings onto the shared widget and supplies the WaveCrux-specific pieces: the `GlowingAppIcon`, the wellen `AboutAttributionSection`, and the action buttons (Visit Website / Documentation / Report Issue / Privacy / Terms / Copy Version Info / Acknowledgments). The "Public Beta" chip and EDU badge are driven by `crux_license` providers inside the shared widget. All user-visible behavior below is unchanged by moving to the shared package.

### 22.6.2 Setup

1. Open a waveform file (any fixture will do) so the full desktop scaffold is present.
2. Confirm the build was made in the environment you want to verify (`kBetaPeriod` value; Pro vs. Open Core tier; locale).
3. For tier-gate tests, use a Pro build with a Pro license active, then repeat with an Open Core build.

### 22.6.3 Steps — opening and content

0. **Presentation by surface (0.2.5):** on desktop (native) AND on web in a
   desktop browser the About box opens as a **modal dialog**; on
   phone/tablet (native app or mobile browser) it opens as a pushed
   full-screen route. Web previously fell into the mobile slide-in — the
   shared heuristic keys on `defaultTargetPlatform`, which reports the host
   OS on web. On web, reach it via the command palette (Ctrl/Cmd+Shift+P →
   "About") or the toolbar overflow menu; there is no native menu bar.
   `[Coverage: WIDGET]` (crux-shared `crux_about_dialog_test.dart` — show()
   presentation-branch tests).
1. Open the About dialog from the platform menu bar.
2. Confirm the dialog title is **"About WaveCrux"** (English; localized on CJK locales).
3. Confirm the **app icon / GlowingAppIcon** is present and animating.
4. Confirm the **tagline** is visible (contains "waveform" in English).
5. Confirm the **version number** string is present and non-empty (e.g., `1.2.3`).
6. Confirm the **build number** and **git SHA** strings are present.
7. Confirm the **Ferrite Engineering** company name appears in the branding banner.
8. Confirm the **copyright line** appears (format: `© <year> Ferrite Engineering`).
9. Confirm the **"Public Beta"** chip is visible when `kBetaPeriod = true`; absent when `kBetaPeriod = false`.
10. Confirm the **edition chip** behavior:
    - Open Core build: no `FeatureTierBadge` chip.
    - Pro build with Pro license: a `FeatureTierBadge` or edition label identifying Pro is present.
    - EDU license: the `EditionBadge` "EDU" chip is visible.
11. Confirm the **wellen attribution** section is present and contains the text "wellen" and "BSD-3-Clause".
12. Confirm the **Build platform info** section shows OS, architecture, Flutter version, Dart version.

### 22.6.4 Steps — action buttons

1. Confirm **"Copy Version Info"** button is present and enabled once the async provider has resolved.
2. Tap/click **"Copy Version Info"** — clipboard must contain a structured plain-text paragraph with app name, version, build number, git SHA, edition, OS, Flutter/Dart versions. Paste into a text editor to verify format.
3. Confirm **"Acknowledgments"** button is present.
4. Tap/click **"Acknowledgments"** — the Acknowledgments screen opens. Confirm:
   - Screen title "Acknowledgments" is visible.
   - "wellen" entry appears.
   - "Flutter" entry appears.
   - "flutter_riverpod / riverpod" entry appears.
   - BSD 3-Clause and MIT license badges are visible.
   - Back button returns to the About dialog (or previous screen).
5. Confirm **"Visit Website"** button is present; tap opens the browser to the correct URL.
6. Confirm **"Report Issue"** button is present; tap opens the browser to the GitHub issues page.

### 22.6.5 Steps — wellen license expander

1. Locate the **"BSD-3-Clause"** expand trigger within the wellen attribution section.
2. Tap/click it. Confirm the license text expands without exception.
3. Tap/click it again. Confirm it collapses without exception.

### 22.6.6 Steps — tier-gate scenarios

**Beta period (`kBetaPeriod = true`):**
- All action buttons are accessible to all users.
- "Public Beta" chip is visible.
- Edition chip reflects the active license tier correctly.

**Post-beta (`kBetaPeriod = false`):**
- About dialog behavior is identical (the About dialog itself is not feature-gated — it is available to all tiers).
- "Public Beta" chip is absent.
- Edition chip reflects the active tier.

### 22.6.7 Steps — responsive layout and locale sweep

1. Resize the window to phone width (400 dp wide). Confirm:
   - No `RenderFlex overflowed` exception.
   - Branding banner text truncates or wraps gracefully.
2. Resize to tablet width (800 dp), then desktop (1400 dp). Confirm layout is clean at each size.
3. Switch locale to zh-CN, ja, ko. For each:
   - Reopen the About dialog.
   - Confirm no exception.
   - Confirm CJK characters render (no tofu / replacement characters).

### 22.6.8 Edge cases

- Open the dialog immediately after launch before any VCD is loaded — confirm it opens and renders without the file being loaded.
- Rapidly open and close the dialog multiple times — confirm no memory leak or duplicate animations.
- On a build where `applicationBuildInfoProvider` is still loading (artificially slow async): confirm "Copy Version Info" button is disabled until the provider resolves.

### 22.6.9 Automation Assessment

| Test | Coverage |
|---|---|
| Dialog renders without exception — en, zh, ja, ko | **WIDGET** (`test/features/about/widgets/wavecrux_about_dialog_test.dart` — locale sweeps group) |
| Dialog renders without overflow at phone (400×800), tablet (800×1024), desktop (1400×900) | **WIDGET** (`test/features/about/widgets/wavecrux_about_dialog_test.dart` — responsive surface sizes group) |
| "About WaveCrux" title is visible | **WIDGET** (same file — content group) |
| Version number from `applicationBuildInfoProvider` is visible | **WIDGET** (same file — content group) |
| Git SHA from `applicationBuildInfoProvider` is visible | **WIDGET** (same file — content group) |
| Company name from `applicationBrandingProvider` is visible | **WIDGET** (same file — content group) |
| "Public Beta" chip present/absent based on `kBetaPeriod` | **WIDGET** (same file — beta indicator group) |
| No edition chip for Open Core tier | **WIDGET** (same file — edition chip group) |
| EditionBadge "EDU" chip visible for EDU tier | **WIDGET** (same file — edition chip group) |
| "Copy Version Info" button present and enabled after async provider resolves | **WIDGET** (same file — action buttons group) |
| "Acknowledgments" button present | **WIDGET** (same file — action buttons group) |
| "Visit Website" button present | **WIDGET** (same file — action buttons group) |
| "Report Issue" button present | **WIDGET** (same file — action buttons group) |
| wellen attribution section contains "wellen" text | **WIDGET** (same file — wellen attribution group) |
| BSD-3-Clause expander taps without exception | **WIDGET** (same file — wellen attribution group) |
| Acknowledgments screen renders without exception — en, zh, ja, ko | **WIDGET** (`test/features/about/widgets/about_acknowledgments_screen_test.dart` — locale sweeps group) |
| Acknowledgments screen shows "wellen", "Flutter", "flutter_riverpod / riverpod" entries | **WIDGET** (same file — content group) |
| Acknowledgments screen shows BSD 3-Clause and MIT license badges | **WIDGET** (same file — content group) |
| Acknowledgments back button pops the route | **WIDGET** (same file — interaction group) |
| `applicationEditionProvider` returns "Open Core" by default in en | **WIDGET** (`test/core/app_info/application_edition_provider_test.dart`) |
| `applicationEditionProvider` renders without exception — en, zh, ja, ko | **WIDGET** (same file — locale sweep group) |
| `applicationBuildInfoProvider` returns stub data correctly when overridden | **WIDGET** (`test/core/app_info/application_build_info_provider_test.dart`) |
| `applicationBrandingProvider` returns default Ferrite Engineering branding | **WIDGET** (`test/core/app_info/application_branding_provider_test.dart`) |
| Platform menu bar "About WaveCrux" entry present on desktop | **MANUAL** |
| Mobile Settings → About row navigates to dialog | **MANUAL** |
| "Copy Version Info" clipboard content is correctly structured | **WIDGET** (`test/features/about/widgets/wavecrux_about_dialog_test.dart` — "tapping Copy Version Info writes the structured build info to the clipboard" mocks `SystemChannels.platform`, taps the action, and asserts the captured `Clipboard.setData` text contains the app name plus every field of the stub build info: version, build number, git SHA, OS, architecture, Flutter + Dart versions. The string *format* itself is unit-tested in the shared `crux_about_dialog` package's `aboutVersionInfoText` group.) |
| "Visit Website" and "Report Issue" open correct browser URLs | **MANUAL** |

---

## 22.7 Color Theming & Customization

> **Update.** The underlying types moved to the
> cross-suite `crux_theme` package: the in-process model is now
> `CruxColorTheme`, the Riverpod provider is `cruxColorThemeProvider`,
> and the Flutter `ThemeExtension` is `CruxThemeExtension`. WaveCrux's
> `canvas` and `chrome` token catalogs register with `ThemeRegistry`
> at boot; the canvas reaches its tokens through the
> `WaveCruxThemeAccessors` extension, and the chrome tokens reach the Material
> theme through `crux_theme`'s `applyChromeTokens`.
> The on-disk pack format changed to `.crux-theme.json` (flat
> `tokens: { category: { token.id: hex } }` map); bundled presets under
> `assets/themes/` are migrated. Pre-Session-3 imports of the old
> WaveCrux pack format are no longer supported.
>
> **Update.** Settings → Appearance now renders
> `crux_theme`'s `ThemeAppearanceSection` composer directly — the old
> bespoke preset grid + signal-palette editor + quick-override pickers
> are gone. The UI surface changes:
>
> * **Preset cards** ship from the package's `PresetCard`; tapping a
>   card writes through to `AppSettings.activeThemeName` via
>   `WaveCruxCruxColorThemeNotifier.activate`.
> * **Per-token editor** replaces the four-token "Quick canvas
>   overrides" — every canvas and chrome token is editable through
>   `TokenCategorySection` (collapsed by default). Tapping a token
>   swatch opens the package's `ColorPickerDialog` (HSV sliders + hex
>   input + RGB readout + live preview).
> * **Theme pack browser** replaces the standalone Import / Export
>   buttons with the package's `ThemePackBrowser` — adds an installed
>   pack list with per-pack Activate / Uninstall actions, plus a
>   confirmation dialog before uninstall.
> * **Signal color palette editor (retired)** — the palette is
>   list-valued and `crux_theme` only stores scalar `Color` tokens
>   today. The renderer still reads
>   `AppSettings.themeOverrides['canvas.signal.palette']`; only the
>   editor UI is gone. A future `crux_theme` release with palette
>   support will reintroduce the editor.
> * **Locale**: every preset card, token row, color picker, and
>   theme-pack-browser string flows through
>   `WaveCruxThemeAppearanceStrings`, which routes the package's
>   `ThemeAppearanceStrings` interface to WaveCrux's `L10N`.
>
> Internal details of the package surfaces (preset card layout, token
> editor row composition, color-picker behavior, pack list ordering)
> are tested in `crux_theme`'s own widget test suite — verification
> below covers only the WaveCrux-side composition and persistence.

### What it does

WaveCrux ships a named-token color system that lets engineers customize the waveform canvas and application chrome. All colors are identified by stable string token names grouped into `canvas.*` and `chrome.*` categories. Users interact with the system through three entry points hosted by `crux_theme`'s `ThemeAppearanceSection` composer in Settings → Appearance:

1. **Preset picker** — five built-in presets rendered as `PresetCard`s (`wavecrux-dark`, `wavecrux-light`, `solarized-dark`, `high-contrast-dark`, `oscilloscope`). One card is highlighted as active; tapping any other card activates it.
2. **Color overrides** — one collapsible `TokenCategorySection` per registered category (`canvas`, `chrome`). Each row shows the token's display name, current color swatch, and a reset-to-default button. Tapping the swatch opens the package's `ColorPickerDialog` (HSV sliders + hex input + RGB readout + live preview).
3. **Theme packs** — install / activate / uninstall flow for `.crux-theme.json` files (JSON with `schemaVersion`, `id`, `displayName`, `brightness`, `tokens` keys; missing tokens fall back to the active preset's registered defaults).

The active theme name is persisted in `.wavecrux` session files. When a session is loaded and the named theme is not found, WaveCrux falls back to `wavecrux-dark` and shows a non-blocking snackbar. GTKWave `.gtkw` imports apply `[bgcolor]` directives as a `canvas.background` quick override and per-signal `[color]` directives as per-signal color overrides.

### Setup

- Load any VCD or FST file so the waveform canvas is visible (tokens are live — changes re-paint immediately).
- Open Settings → Appearance.

### Step-by-step verification

#### 22.7.1 Preset activation

1. Open Settings → Appearance.
2. Click each of the five preset cards in order: `wavecrux-dark`, `wavecrux-light`, `solarized-dark`, `high-contrast-dark`, `oscilloscope`.
3. **Expected:** Canvas background color changes immediately after each selection. The previously selected card loses its "active" outline; the newly selected card gains one.
4. Close and reopen WaveCrux. **Expected:** The same preset is restored (the in-memory state from `cruxColorThemeProvider` rebuilds from `AppSettings.activeThemeName` via the `WaveCruxCruxColorThemeNotifier` write-through).

#### 22.7.2 Per-token color override

1. In Settings → Appearance, expand the **Canvas** category in the *Color overrides* section.
2. Locate `cursor.primary`. Tap the color swatch. **Expected:** `crux_theme`'s `ColorPickerDialog` opens with the current cursor color, HSV sliders, hex input, RGB readout, and live preview.
3. Pick a new color (e.g. `#00FF00`) and tap OK. **Expected:** The swatch updates. The cursor line on the canvas turns the new color immediately. The reset button next to the swatch becomes enabled.
4. Tap the reset button. **Expected:** The token returns to the active preset's default. The override is removed from `AppSettings.themeOverrides`.
5. Activate a different preset. **Expected:** Any remaining overrides apply only to tokens that differ from the new preset; tokens the new preset defines use the new preset's value.

#### 22.7.3 Import a theme pack

1. In Settings → Appearance, scroll to *Theme packs*. Click "Import theme pack…".
2. Select a `.crux-theme.json` file with known content (e.g. an exported pack from step 22.7.4 or a copy of a bundled preset from `assets/themes/`).
3. **Expected:** A success snackbar shows ("Installed theme pack '…'."). The pack appears in the *Installed packs* list with an Activate / Uninstall pair.
4. Tap Activate. **Expected:** The pack's tokens apply to the canvas immediately. `AppSettings.activeThemeName` updates to the pack id.
5. Try importing a JSON file with an unknown `brightness` value (e.g. `"brightness": "sepia"`). **Expected:** Import is rejected; an error snackbar reports the reason; the *Installed packs* list is unchanged.
6. Try importing a JSON file with an invalid hex (`"background": "ZZZZZZ"`). **Expected:** The file is silently accepted; the bad token falls back to the registered default; no crash.
7. Try importing an otherwise-valid pack and immediately tap Uninstall. **Expected:** A confirmation dialog appears; tapping Cancel leaves the pack installed; tapping Uninstall removes it from the list and removes the on-disk file under `${appSupportDir}/themes/`.

#### 22.7.4 Export the active theme

1. Activate `solarized-dark`.
2. Override `canvas.background` to `#002B36` via the per-token editor.
3. In *Theme packs*, click "Export current theme…" and save to a temp path.
4. Open the exported file in a text editor. **Expected:** The file is valid JSON with `"schemaVersion": 1`, the theme `id` and `displayName` matching the active theme, and the override value present under `tokens.canvas.background`.
5. Import the exported file back via step 22.7.3. Activate it. **Expected:** Canvas background matches the overridden value; the override persists into the imported pack as a baseline token (not as a layered override).

#### 22.7.5 Session persistence

1. Activate `oscilloscope`. Save the session.
2. Close and reopen WaveCrux with that session file.
3. **Expected:** `oscilloscope` preset is active; canvas colors match.
4. Now rename/delete the preset file (or use a session that names a non-existent preset). Reopen.
5. **Expected:** WaveCrux falls back to `wavecrux-dark` and shows a snackbar: "Theme 'X' not found — using default." No crash.

#### 22.7.6 GTKWave `.gtkw` migration

1. Import a `.gtkw` file that contains `[bgcolor] 002B36` and per-signal `[color]` directives.
2. **Expected:** The `canvas.background` quick override is set to `#002B36`. Affected signals have their `argbColor` set from the `[color]` directive. The theme preset is unchanged.
3. Import a `.gtkw` file with `[bgcolor] ZZZZZZ` (invalid hex).
4. **Expected:** The invalid value is silently ignored; `canvas.background` is not changed.

#### 22.7.7 Chrome token behavior

1. Export any theme pack that includes `chrome.scaffold.background`. Edit the exported JSON to remove the `chrome.scaffold.background` entry under `"tokens"` and re-import.
2. **Expected:** Chrome surfaces revert to Material 3 defaults derived from the app's seed color. No crash, no blank panels.
3. Add a `chrome.toolbar.background` token to the JSON under `"tokens"`. Re-import.
4. **Expected:** The toolbar background changes to the specified color.

#### 22.7.8a Preset switching repaints every surface (Session 5 fix)

This section is the safety net for the bugs the Session 5 fix closed:
the active preset must drive Material brightness (`MaterialApp.themeMode`),
must repaint chrome surfaces (scaffold, AppBar, panels) via
`applyChromeTokens`, and must repaint the canvas background plus alternating
lane backgrounds. Visual inspection is the canonical check — automated tests
cover the providers but cannot verify "is this pixel the right colour".

1. Cold-start the app with a VCD/FST file open so the canvas has visible content.
2. Open Settings → Appearance. Confirm the dialog chrome matches the active preset's brightness (a dark preset → dark dialog).
3. Tap `WaveCrux Light`. **Expected:**
   - Settings dialog background flips to light immediately (the dialog itself, not just the preset card outline).
   - Behind the dialog, the workspace AppBar, tab bar, side panels, status bar, and scaffold all flip to light.
   - The waveform canvas background turns light gray (`#F5F5F5`).
   - Lane row striping is visible against the light background.
4. Tap `Solarized Dark`. **Expected:**
   - Chrome surfaces (toolbar, status bar, panel headers) re-tint with Solarized hues (teal-blue, not default Material-3 dark). This is the chrome-tokens path — if you only see the canvas change but the chrome stays Material-3, `applyChromeTokens` is broken.
   - Canvas background turns Solarized dark blue (`#002B36`), and the time ruler sits on the Solarized panel blue (`#073642`).
   - The cursors and markers take Solarized's own accents: the primary cursor is Solarized yellow (`#B58900`), the dashed secondary cursor Solarized orange (`#CB4B16`), and a named marker's triangle and letter Solarized blue (`#268BD2`). The ruler's minor ticks are `#586E75` and its time labels `#93A1A1`; the delta readout between the cursors is in the primary yellow. Override `cursor.primary` under Color overrides → Canvas and confirm the canvas cursor line and its ruler triangle both repaint in the new color.
5. Tap `Oscilloscope`. **Expected:**
   - Chrome flips to phosphor-green-on-black.
   - Canvas background goes pure black, and so does the time ruler (`#000000`), with dark-green minor ticks (`#1A4A1A`) and phosphor-green time labels (`#00FF41`).
   - The primary cursor is phosphor green (`#00FF41`, solid line, filled ruler triangle) and the secondary a paler green (`#66FF88`, dashed line, outlined triangle); tell them apart by line style and triangle fill as much as by hue. Named markers are the paler green too. The delta readout is phosphor green.
7. Tap `High Contrast Dark`. **Expected:** the primary cursor is pure yellow (`#FFFF00`), the secondary and named markers pure cyan (`#00FFFF`), on a pure-black ruler (`#000000`) with white time labels and `#666666` minor ticks.
8. Tap `OLED XR`. **Expected:** amber primary cursor (`#FFD400`), cyan secondary (`#00E5FF`), green markers (`#34FF8A`), on a true-black ruler with `#E8E8E8` labels. No light-blue (`#29B6F6`) line anywhere on the canvas.
9. Tap `WaveCrux Dark`. **Expected:** the cursors return to the shared dark palette: yellow primary (`#FFEE58`), light-blue secondary (`#29B6F6`), pink markers (`#F48FB1`).
10. Quit the app and relaunch. **Expected:** Whichever preset you left active is restored — chrome and canvas both. (The persisted state is `AppSettings.activeThemeName` + `themeOverrides`; the WaveCrux notifier override rebuilds the in-memory `CruxColorTheme` from those keys on first read.)

#### 22.7.8b Waveform font size slider (Session 5 fix)

The Settings → Appearance "Waveform Font Size" slider previously wrote
`AppSettings.waveformFontSize` but no widget consumed it. After Session 5
it drives the canvas's value-label and group-header text styles.

1. Open Settings → Appearance with a VCD/FST file open.
2. Drag the slider to **8**. **Expected:** value labels (e.g. `00000004`, `deadbeef`) inside bus-shape diamonds render at the smallest legible size; group-header labels also shrink.
3. Drag to **24**. **Expected:** value labels grow proportionally; nothing clips or overflows the lane height (`MobileMetrics.minLaneHeight` accommodates the largest size).
4. Quit and relaunch. **Expected:** the chosen size persists (round-trips through `WaveCruxSettingsService`).

#### 22.7.8 Settings → Appearance locale sweep (Session 4)

1. With the app running, change the active locale (Settings → Application → Language) to each of `en`, `zh_CN`, `zh`, `ja`, `ko` in turn.
2. After each switch, reopen Settings → Appearance.
3. **Expected:** The section heading, "Presets", "Color overrides", "Theme packs", per-token category headers, brightness icons, preset-card tooltips, the color picker dialog (Hex / RGB / HSV / Hue / Saturation / Value labels), and the import / export buttons all render in the active locale. No raw `key.name` strings appear; no overflow / layout errors.

### Diagnostics-assisted verification

Open the diagnostics panel → Provider tab. Verify that `cruxColorThemeProvider` shows its state and that re-activating a preset or applying a per-token override causes the provider to emit a new value (state increments). The Session 4 write-through path also produces an `appSettingsProvider` state transition on every activation / token edit / token reset — both providers should update together.

### Edge cases

| Scenario | Expected behavior |
|---|---|
| JSON file is not valid JSON | Import rejected, error snackbar shown, *Installed packs* list unchanged |
| Required field (`schemaVersion`, `id`, `displayName`, `brightness`, `tokens`) missing | Import rejected with a snackbar pointing at the missing field |
| `brightness` value is not `"light"` or `"dark"` | Import rejected with a snackbar |
| `tokens.canvas.background` is `"ZZZZZZ"` (invalid hex) | Bad token silently falls back to the registered default; pack installs successfully |
| File picker cancelled during import | No change |
| File picker cancelled during export | No change |
| Session file `activeThemeName` is `null` | Treated as `'wavecrux-dark'` |
| Per-token color picker dismissed without picking | Override unchanged |
| Uninstall confirmation cancelled | Pack remains installed; no file is deleted |

### Automation assessment

| Test | Coverage | Assessment |
|---|---|---|
| `CruxColorTheme` model round-trip / fallback (package) | `crux_theme` package suite | **AUTOMATED** (upstream) |
| `ThemePackCodec` / `ThemePackService` validation (package) | `crux_theme` package suite | **AUTOMATED** (upstream) |
| `crux_theme` widgets — `PresetPicker` / `TokenEditor` / `ThemePackBrowser` / `ColorPickerDialog` | `crux_theme` package suite | **AUTOMATED** (upstream) |
| `ColorThemeSection` composes the three crux_theme surfaces | `test/features/settings/widgets/color_theme_section_test.dart` | **AUTOMATED** |
| `ColorThemeSection` renders all 5 built-in preset cards | same | **AUTOMATED** |
| Settings → Appearance locale sweep (en/zh_CN/zh/ja/ko) | same | **AUTOMATED** |
| Tapping a preset card persists `activeThemeName` to `AppSettings` (write-through) | same | **AUTOMATED** |
| Import button invokes the injected `pickPackFile` callback | same | **AUTOMATED** |
| Export button invokes the injected `pickExportLocation` callback | same | **AUTOMATED** |
| Export writes a valid `.crux-theme.json` to the picked path | same | **AUTOMATED** |
| `WaveCruxThemeAppearanceStrings` exposes every interface slot | same | **AUTOMATED** — guards against ARB drift |
| `SessionState.activeThemeName` round-trip | `test/domain/models/session_state_test.dart` | **AUTOMATED** |
| `SessionService` saves/loads `activeThemeName` | `test/services/session/session_service_test.dart` | **AUTOMATED** |
| `GtkwParser` parses `[bgcolor]` directive | `test/services/session/gtkw_parser_test.dart` | **AUTOMATED** |
| `GtkwImportService` passes `canvasBackgroundHex` through | `test/services/session/gtkw_import_service_test.dart` | **AUTOMATED** |
| Canvas renders with `oscilloscope` preset (golden) | `test/features/viewer/rendering/waveform_canvas_golden_test.dart` (`vector_formats_oscilloscope.png` + `analog_real_oscilloscope.png`) | **AUTOMATED** (macOS-gated, native-FFI-gated) — see §13A for the full Layer 5 golden suite |
| Every cursor, marker and ruler token reaches its painter: `cursor.primary`/`secondary` (canvas lines + ruler triangles), `cursor.delta` (band between the cursors), `marker.line` (line per named marker), `marker.flag`/`flagText`, `ruler.background`/`tick`/`label`/`cursorTime`; a theme change repaints the cursor layer and the ruler; unedited Crux Dark / Crux Light paint exactly the colors these elements had before the tokens were wired, and the four branded presets paint their designed palette (a marker's letter in its triangle's color) | `test/features/viewer/widgets/canvas_theme_tokens_paint_test.dart` | **AUTOMATED** — recorded canvas calls for geometry, rendered pixels for text color |
| Every built-in preset's canvas token values, and the registered defaults equal Crux Dark / Crux Light | `test/core/theme/wavecrux_canvas_preset_overlay_test.dart` | **AUTOMATED** |
| Token reset removes the override from `AppSettings.themeOverrides` | Pending — add to `color_theme_section_test.dart` | **HYBRID** |
| Theme-not-found fallback snackbar | **MANUAL** — UI interaction + visual check |
| Chrome token override visible in toolbar/status bar | **MANUAL** — visual verification |
| Override persists across app restarts | **MANUAL** |

---

## 22.8 Multi-Tab Workspace

> **Legacy behavior — superseded by §22.9 (Workspace Model & Split-Pane) and §22.10 (Diagnostics Restructuring).** All step-by-step content in this section describes the multi-tab workspace as it existed *before* the workspace model. The Welcome tab, the always-visible `+` button, the "Restore previous tabs on launch" Settings toggle, and the standalone "Diagnostics panel" route documented below have been retired or restructured. §22.9 and §22.10 are the active reference for new test runs. This section is preserved verbatim for backwards traceability of the multi-tab work — do not delete it, but do not use it as the primary verification target.

### What it does

The multi-tab workspace allows engineers to work with multiple waveform files simultaneously. Each tab is an independent workspace with its own file, cursor, zoom, signal arrangement, and Stage configuration. Tabs are rendered in a horizontal tab bar between the toolbar and the `IdeLayout` on desktop and tablet; phone shows single-file only. The architecture uses per-tab `ProviderContainer`s (parented to the root) so all tab-local state is fully isolated and inactive tabs stay alive in an `IndexedStack`.

### Platform scope

| Platform | Tab bar | Notes |
|---|---|---|
| macOS / Linux / Windows | ✓ | Full tab bar with overflow scrolling |
| iPadOS (tablet class) | ✓ | Simplified tab bar; no pop-out |
| iOS / Android phone | ✗ | Single-file, no tab bar |
| Web | ✗ | Single-file |

### Setup

Build and launch the desktop app:

```bash
flutter run -d macos   # or -d linux, -d windows
```

No special fixtures required; any VCD/FST/GHW file works. For multi-file tests, use two distinct files (e.g., `test/fixtures/vcd/scalar_basics.vcd` and `test/fixtures/vcd/vector_formats.vcd`).

### 22.8.1 Tab creation and switching

**Step-by-step:**

1. Launch the app. A single Welcome tab appears (`+` is the only tab chip visible).
2. Open a VCD file (File → Open or drag-and-drop). The tab bar shows one chip labelled with the filename.
3. Press Cmd+T (macOS) / Ctrl+T (Linux/Windows). A second Welcome tab appears and is selected.
4. Open a second VCD file. The second tab shows the new file.
5. Click the first tab. The waveform, cursor, zoom, and panel state from file 1 restore instantly.
6. Click the second tab. State from file 2 is independent — cursor position, zoom, and signals are unchanged.
7. Press Cmd+1 / Ctrl+1 — first tab activates. Press Cmd+2 / Ctrl+2 — second tab activates.
8. Press Ctrl+Tab (next tab) and Ctrl+Shift+Tab (previous tab); verify cycling behavior.

**Expected:** Each tab is fully independent. Switching tabs never reloads the file — the waveform data is preserved in the inactive tab's container.

### 22.8.2 Tab bar UI components

**Step-by-step:**

1. Open three or more files. Each gets a chip showing its basename.
2. Hover over a chip — tooltip shows the full file path.
3. A chip for a session with unsaved changes shows a small dot indicator.
4. Press × on a chip — that tab closes. If it had unsaved state, a confirmation dialog appears.
5. Closing the last non-welcome tab leaves one Welcome tab (never exits the app).
6. Right-click (or long-press on tablet) a tab chip — context menu appears: Duplicate Tab, Move to New Window (disabled), Reveal in Finder/Explorer, Close Tab, Close Other Tabs, Close Tabs to the Right.
7. Drag a chip left or right past another chip — tab order updates.

**Expected:** All affordances render without overflow. Touch targets are ≥ 44 dp on tablet.

### 22.8.3 Tab bar overflow scrolling

**Step-by-step:**

1. Open 8–10 files until the tab bar is wider than the window.
2. Left and right scroll chevrons appear at the tab bar edges.
3. Click the right chevron — tabs scroll right; right-most tabs become visible.
4. Click the left chevron — tabs scroll back left.

**Expected:** No RenderFlex overflow. Scroll arrows appear/disappear based on overflow state.

### 22.8.4 Panel context switching

**Step-by-step:**

1. Open two files. In tab 1, add 5 signals to the waveform, place the cursor at time 1 µs, and zoom in.
2. Switch to tab 2. The signal list is empty, cursor is at 0, zoom is at default.
3. In tab 2, add 3 different signals. Switch back to tab 1 — the 5 signals, cursor at 1 µs, and zoom level from step 1 are preserved.
4. Open the diagnostics panel (Tools → Diagnostics). Switch tabs — the File Info tab updates to reflect the active tab's file stats.
5. With the statistics strip visible, switch tabs — the sparklines and gauges update for the new tab's render pipeline.

**Expected:** All panels (waveform canvas, value column, signal tree, transaction table, Stage, diagnostics) reflect the active tab's state without any explicit refresh action.

### 22.8.5 CLI multi-file opening

**Step-by-step:**

```bash
wavecrux path/to/file_a.vcd path/to/file_b.fst
```

1. The app launches with two tabs — one for each file, in the order they were passed.
2. The first file is the active tab on launch.
3. Running `wavecrux file.fst --session debug.wavecrux` opens `file.fst` in a tab pre-configured with the named session.

**Expected:** Each positional argument opens as a separate tab. No argument → Welcome tab only.

### 22.8.6 Startup tab restoration

**Step-by-step:**

1. Open two files in separate tabs. Navigate, place cursors.
2. Quit the app (Cmd+Q / Ctrl+Q).
3. Relaunch the app.
4. Both tabs reopen with the correct filenames. (Per-tab cursor/zoom state is NOT restored — only the file path. Full state restoration requires a saved `.wavecrux` session.)

**Disable restoration:**

1. Settings → General → "Restore previous tabs on launch" → Off.
2. Open two files, quit, relaunch. The app starts with a single Welcome tab.

**Edge cases:**

- If a file from the last session no longer exists, the tab opens in an error state (file-not-found message). WaveCrux should not crash.
- If `last_session.json` is corrupt (truncated, invalid JSON), WaveCrux silently ignores it and starts with a Welcome tab.

### 22.8.7 Session integration (per-tab)

**Step-by-step:**

1. Open a file in tab 1. Add signals, set cursor, zoom in.
2. Press Cmd+S / Ctrl+S — save session for tab 1 to `debug.wavecrux`.
3. Open a second file in tab 2. Do NOT save.
4. Close both tabs. Reopen tab 1 from recent files.
5. "Restore session?" — select `debug.wavecrux`. Signals, cursor, and zoom restore.

**Expected:** Session save/load is per-tab. Tab 2's state (unsaved) is not affected by tab 1's session file.

### 22.8.8 Multi-window placeholder hooks

**Step-by-step:**

1. Right-click a tab chip → "Move to New Window". Verify the item is present but disabled (greyed out, tooltip: "Available when Flutter multi-window reaches stable").
2. If panel pop-out buttons exist in panel headers (Stage, transaction view, diagnostics), verify they are visible but disabled with the same tooltip.
3. `kMultiWindowAvailable` is `false` — both affordances stay disabled at all times.

**Expected:** Multi-window affordances are discoverable but non-functional. No crash or error when interacting with disabled items.

### 22.8.9 Phone behavior (no tab bar)

**Step-by-step (on iPhone / Android phone):**

1. Launch on phone. No tab bar appears.
2. Open a file — waveform view loads; no chip bar.
3. Settings → General → scroll to multi-tab entry (informational note only): "Multi-tab viewing is available on desktop and tablet."
4. Opening a second file replaces the current view (no new tab).

**Expected:** The phone layout is entirely single-file. The tab bar widget is not rendered.

### 22.8.10 Keyboard shortcuts

| Action | macOS | Linux / Windows |
|---|---|---|
| New tab | Cmd+T | Ctrl+T |
| Close tab | Cmd+W | Ctrl+W |
| Next tab | Ctrl+Tab | Ctrl+Tab |
| Previous tab | Ctrl+Shift+Tab | Ctrl+Shift+Tab |
| Jump to tab 1–9 | Cmd+1–9 | Ctrl+1–9 |

Verify each shortcut in the command palette (Cmd+Shift+P → search "tab") — they all appear with the correct labels.

### 22.8.11 Automation assessment

| Test | Coverage | Notes |
|---|---|---|
| Tab creation and closing | `[Coverage: AUTOMATED]` | `test/features/tabs/...` widget tests |
| TabListNotifier CRUD | `[Coverage: AUTOMATED]` | `test/features/tabs/providers/tab_providers_test.dart` (open/close/openSession on the derived `tabListProvider`); reorder/split/move on the notifier live in `test/features/workspace/providers/workspace_provider_test.dart` |
| Per-tab container isolation | `[Coverage: AUTOMATED]` | `test/services/tabs/tab_container_manager_test.dart` |
| TabId equality and hash | `[Coverage: AUTOMATED]` | Lives upstream at `crux-shared/packages/crux_workspace/test/tab_id_test.dart` |
| WavecruxTab model | `[Coverage: AUTOMATED]` | `test/domain/models/wavecrux_tab_test.dart` |
| LastSessionManifest JSON round-trip | `[Coverage: AUTOMATED]` | `test/domain/models/last_session_manifest_test.dart` |
| LastSessionService save/load/clear | `[Coverage: AUTOMATED]` | `test/services/session/last_session_service_test.dart` |
| Delegate noops (detach/pop-out) | `[Coverage: MANUAL]` | Implementation exists in `lib/core/windowing/`; no dedicated unit-test file is committed today. |
| Tab bar overflow scrolling | `[Coverage: WIDGET — pending]` | No committed widget test today; the tab-bar chevron overflow behavior (no chevrons at wide width, chevron advances the ScrollController, no `RenderFlex overflowed` at 320 dp) is verified manually. Tracked alongside the CHECKLIST §12.4 "Tab overflow" pending row. |
| Drag-to-reorder | `[Coverage: UNIT + INTEGRATION_TEST]` | **Notifier contract:** `test/features/workspace/providers/workspace_provider_test.dart` — pins `reorderTab` semantics on the `WorkspaceNotifier`. **Gesture path (integration):** `integration_test/tabs/tab_drag_reorder_test.dart` — three scenarios against the full bootstrapped app: first tab past second, second tab before first, middle tab to last in a three-tab bar. (No headless widget-level gesture test is committed; the integration test is the gesture-path coverage.) The 8 dp permanent hit zone on `_buildInsertionTarget` is what makes the gesture-level test reliable. |
| CLI multi-file (positional args) | `[Coverage: INTEGRATION_TEST]` | `integration_test/tabs/cli_multi_file_test.dart` — bootstraps the full app with two positional arguments, asserts `tabListProvider` exposes 2 tabs in CLI order with matching `displayName`/`filePath`, first file is the active tab, and each tab has a distinct per-tab `ProviderContainer`. |
| Startup tab restoration | `[Coverage: INTEGRATION_TEST]` | `integration_test/tabs/startup_restoration_test.dart` — writes a 2-entry `LastSessionManifest` to the real app-support directory, bootstraps with no CLI args, asserts the post-frame restoration repopulates `tabListProvider` with both file paths. Cleans up via `LastSessionService.clear` so subsequent test runs are unaffected. |
| Panel context switching across tabs | `[Coverage: MANUAL]` | UX feel, all panels |
| File-not-found on restore | `[Coverage: MANUAL]` | Requires deleted file |
| Multi-window placeholder disabled | `[Coverage: MANUAL]` | Visual affordance |
| Phone: no tab bar visible | `[Coverage: MANUAL]` | No committed widget test asserts tab-bar absence at phone width; verified visually. |

> **Supersession.** §16.1 (Welcome screen) and §22.8 (Multi-Tab Workspace) are partially superseded by the workspace model + split-pane and the diagnostics restructuring. The historical content above is preserved for traceability of the multi-tab work; §22.9 and §22.10 below define the current verification surface and are the active reference for new test runs.

---

## 22.9 Workspace Model & Split-Pane

### What it does

The workspace model replaces the per-tab `.wavecrux` session model with an app-level **workspace** concept and adds **split-pane viewing** as an independent feature within one window. The Welcome screen is retired in favor of an **empty-canvas state**; auto-save-on-quit + restore-on-launch removes "unsaved changes?" prompts on every tab close / app quit interaction. The Generator tab of the legacy diagnostics dialog moves to `Tools → Generate Test VCD…` with an explicit destination picker.

### Platform scope

| Platform | Workspace restore | Multi-tab | Split-pane | Empty-canvas |
|---|---|---|---|---|
| macOS / Linux / Windows desktop | ✓ | ✓ | ✓ | ✓ |
| iPadOS (tablet, width ≥ 1000 dp landscape) | ✓ | ✓ | ✓ | ✓ |
| iPadOS (tablet, width < 1000 dp) | ✓ | ✓ | ✗ (single-pane) | ✓ |
| iOS / Android phone | ✓ (single-tab fallback) | ✗ | ✗ | ✓ |
| Web | ✓ | ✓ | ✓ (when window ≥ 1000 dp) | ✓ |

### Setup

```bash
flutter run -d macos   # or -d linux, -d windows
```

Fixtures: any two distinct VCDs work. The migration test additionally requires writing a synthetic `last_session.json` to the app-support directory before first launch (the auto-migration path).

### 22.9.1 Empty-canvas startup

1. Launch the app on a clean install (or after "Reset Workspace"). The empty-canvas state renders: recent files list, recent workspaces list, "Open File…" / "Open Workspace…" buttons. There is no "New Tab" button — a blank tab is a dead-end, so WaveCrux exposes no new-blank-tab affordance.
2. Toolbar, status bar, menu bar, and command palette are interactive — verify by opening Settings (`Cmd+,` / `Ctrl+,`) and Diagnostics (`Tools → App Diagnostics…`).
3. Verify no Welcome tab chip exists in the tab bar, and that there is no `+` new-tab button on the tab bar.
4. **Animated header logo.** The logo above the "WaveCrux" title is the **official animated app icon** (`GlowingAppIcon`) — the same widget the About dialog uses — not the static Material `waves_outlined` glyph. Verify the icon is the real WaveCrux app icon and that its halo / ambient background glow visibly pulses (two independent breathing cycles, ~3.5 s and ~6 s). This is the animated logo that was lost when the separate welcome window was removed; restoring it is the point of this entry.
5. **Clickable docs link.** The bottom hint reads "Need help getting started? Visit docs.wavecrux.app". The **`docs.wavecrux.app` portion is a live link** — it renders underlined in the theme's primary color, and clicking it opens `https://docs.wavecrux.app` (`HelpUrls.docs`) in the system browser. The surrounding prose is not clickable. Repeat the click check in `zh_CN` / `ja` / `ko`: the localized sentence changes but the linked `docs.wavecrux.app` domain is identical and still opens the docs.

**Expected:** No "Welcome" string appears anywhere. The animated `GlowingAppIcon` heads the empty-canvas content (animating, not a static glyph); the `docs.wavecrux.app` hint at the bottom is a working link. Empty-canvas content is centered and scales correctly across phone (recent lists only), tablet, and desktop widths.

### 22.9.1.1 Recent Files — content and re-open dispatch

The Recent Files list holds files the user **intentionally opened**: waveform data files (`.vcd`, `.fst`, `.ghw`, `.fsdb`, `.lxt`, `.lxt2`), user-saved sessions (`.wavecrux`), and imported GTKWave sessions (`.gtkw`). It must **not** show internal per-tab session sidecars (`{appSupportDir}/sessions/{uuid}.json`) nor named workspaces (`.wavecrux-workspace` — those have their own Recent Workspaces list).

1. From empty canvas, File→Open a waveform file (e.g. a `.vcd`). After it loads, close the tab. **Verify it now appears at the top of Recent Files.** (Regression guard: prior to this fix, waveform opens were never recorded — only sessions were, so the list showed no waveforms.)
2. Open an `.fsdb` (with `fsdb2vcd` on `$PATH`, accept the conversion). Close the tab. **Verify Recent Files shows the original `.fsdb` path**, not the converted `.fst`. Cancel the conversion dialog on a different `.fsdb` → it must **not** be recorded.
3. Save a session via `File → Export Tab as Session…` (`.wavecrux`). **Verify it appears in Recent Files.**
4. With a waveform loaded, `File → Import GTKWave Session…` and pick a `.gtkw`. **Verify the `.gtkw` appears in Recent Files.**
5. **Re-open dispatch:** tap each kind of entry in Recent Files and verify it routes correctly — a waveform file opens in a new tab; a `.wavecrux` entry loads as a session (does **not** error with a waveform-parse failure); a `.gtkw` entry re-runs the GTKWave import against the active tab's waveform. (Regression guard: the recent-tap handler previously fed every entry to the waveform loader, so tapping a session/`.gtkw` failed.)
6. **Sidecar exclusion:** open 2–3 files, quit, relaunch so workspace-restore rehydrates each tab from its `{appSupportDir}/sessions/{uuid}.json` sidecar. **Verify no UUID-named `.json` entries appear in Recent Files** — only the real files. See the Issue 29 note in §16.1 for the underlying guard.

**Expected:** Recent Files reflects user-opened waveform/session/`.gtkw` files only; internal `.json` sidecars and `.wavecrux-workspace` files never appear; tapping any entry re-opens it through the correct loader.

### 22.9.2 File→Open creates a new tab (no replacement)

1. From empty canvas, File→Open file A. A tab opens.
2. File→Open file B. A second tab opens — file A is still in its original tab.
3. Close tab A. Tab B remains, no Welcome reappears.
4. Close tab B. Empty-canvas state returns.

**Expected:** No prompt asks "save before closing." Both files remain reachable; closing is silent.

### 22.9.3 Auto-save and restore on quit

1. Open three files in three tabs. Navigate, place cursors, change zoom.
2. Quit the app (Cmd+Q / Ctrl+Q). No "unsaved changes" prompt appears.
3. Relaunch. All three tabs reopen in original order; cursor positions and zoom are restored from the auto-saved workspace.
4. Inspect `{appSupportDir}/workspace.json` — JSON contains the three file paths, pane assignment, and active-tab pointer.

**Expected:** The workspace is captured continuously; quit is graceful and silent.

### 22.9.3a Window size / position restore on quit (Windows / Linux)

**What it does (plain language):** the top-level application window's size, on-screen position, and maximized state are saved **as you resize / move / maximize the window** (debounced, written live during the session) — and again as a best-effort capture at quit — then restored on the next launch, so WaveCrux reopens exactly where you left it (VS Code-style). The geometry is stored in the auto-managed workspace document (`workspace.json`) under `extras.windowBounds` — it is *window*-level, not per-tab, so it rides along with the same session restore the tabs use. Desktop only, and specifically the platforms that drive `window_manager`: **Windows and Linux** (macOS keeps its native title bar and is out of scope for this increment; web has no OS window).

> **Why live, not quit-only:** a quit-time-only flush is unreliable on desktop — a hard window-close, an OS kill, or stopping a `flutter run` debug session terminates the process before the async write lands (the original symptom: `workspace.json` never updated and the window reverted to default every launch). Persisting on each resize/move via a `window_manager` `WindowListener` — the same "save on change" model tabs use — is what makes restore dependable. Verify by resizing, then **killing the process hard** (e.g. stop the debugger) and relaunching: the size must still restore.

**Setup:** A Windows or Linux build. `AppSettings.restoreTabsOnLaunch` must be ON (geometry is part of session restore; with restore disabled, the quit-time flush is skipped and geometry is not persisted).

**Steps:**

1. Launch the app. Resize the window to a distinctive, non-default size and drag it to a distinctive position (e.g. upper-right quadrant). Open a file so a tab exists.
2. Quit (`Ctrl+Q`). Relaunch. **Expected:** the window reopens at the same size and position, with no visible "open small then jump" flash (geometry is applied before the first show).
3. Inspect `{appSupportDir}/workspace.json` — the top-level `extras` object contains `"windowBounds": { "width", "height", "left", "top" }`.
4. Maximize the window, quit, relaunch. **Expected:** the window reopens maximized (`extras.windowBounds.maximized` is `true`); un-maximizing returns to a sane size.

**Diagnostics-assisted verification:** with the debug console attached, confirm there is **no** `RenderFlex overflowed` from `IdeLayout` on a restored-default-or-larger window, and that the restored window respects the 800×500 minimum.

**Edge cases (must all be exercised):**

- **Off-screen / stale geometry.** Hand-edit `workspace.json` so `windowBounds.left` is a large negative value (e.g. `-4000`, simulating a monitor that was unplugged). Relaunch. **Expected:** the position is rejected by `WindowBounds.sanitizedForRestore` and the window opens centered at the saved *size* — never invisibly off-screen.
- **Degenerate size.** Set `width`/`height` below the 800×500 minimum (or to a non-finite value). **Expected:** size is floored to the minimum (or the snapshot is ignored), never a collapsed window.
- **`--reset`.** Launch with `--reset`. **Expected:** geometry restore is skipped (along with tab restore); the window opens at the default centered 1280×720.
- **First launch / no file.** Delete `workspace.json`. **Expected:** default centered 1280×720, no error.
- **Cross-machine.** Windows and WSL/Linux use *separate* app-support dirs, so geometry does not leak between them — each platform restores its own last window independently.
- **Resizing with a file open must be a non-event (regression).** Open a waveform, place a cursor, zoom in, expand a few signal groups, then drag-resize the window and maximize it. **Expected:** the console shows **no** `ProviderScope was rebuilt with a different ProviderScope ancestor` error, and the cursor / zoom / group expansion / decoders survive the resize untouched. Because the live persister writes geometry into the *workspace document*, an incremental write routed through the document-replacement path (`replaceWith`) evicted every per-tab and per-pane `ProviderContainer` on each resize — the tab's whole state, with the nested `ProviderScope` in `_PaneScopedCanvas` throwing mid-layout in debug builds and failing silently in release. Incremental workspace edits go through `crux.WorkspaceNotifier.mutate` instead. Exercise the split-pane variant too (split, then resize): both panes must keep their state.

**Tier gate:** Open Core — no `PRO`/`ENT` gating; no tier-gate scenarios apply.

| Test | Automation Assessment |
|---|---|
| `WindowBounds` JSON round-trip, sanitize/clamp (off-screen, degenerate, maximized) | **AUTOMATED — UNIT** (`test/domain/models/window_bounds_test.dart`) |
| Workspace `extras` read/write helpers + side-effect-free `peekPersistedWindowBounds` (temp-dir) | **AUTOMATED — UNIT** (`test/services/workspace/window_bounds_store_test.dart`) |
| `setWindowBounds` records into extras, persists to disk, preserves tabs/panes | **AUTOMATED — UNIT** (`test/features/workspace/providers/workspace_provider_test.dart`) |
| A resize (and add-tab / split-pane) keeps every live per-tab and per-pane `ProviderContainer` identical, while `reset()` / `replaceFromNamed` still evict them | **AUTOMATED — UNIT** (`test/features/workspace/providers/window_bounds_scope_preservation_test.dart`) |
| `readCurrentWindowBounds` fails soft (no live window channel → null); geometry persister mounts/disposes the window listener cleanly | **AUTOMATED — WIDGET** (`test/features/window_chrome/window_chrome_test.dart`) |
| Live persist on resize/move + survive a hard kill; end-to-end restore-before-show with no flash; real multi-monitor off-screen recovery; maximized round-trip on the actual OS | **MANUAL** (needs a real `window_manager` window; the resize→save→reload loop and cross-OS / cross-monitor UX feel can't run headless) |

### 22.9.3b Closing a tab while work is still in flight

**What it does (plain language).** Several WaveCrux operations keep running
after you trigger them: an X-origin trace, a pattern search, a switching-
activity analysis, a waveform diff (which opens a whole second file), and — in
the Pro build — an AI Advisor question, which can spend a minute in model
round-trips. Closing the tab that started one of these must be a non-event:
the work finishes into the void, nothing is published to a tab that no longer
exists, and nothing leaks.

Under the hood, closing a tab disposes that tab's `ProviderContainer`. Riverpod
3 disposes eagerly, so an already-running `await` inside a notifier resumes
against a dead container; any `state` write or `ref.read` after that point
throws `UnmountedRefException`. The long-running keepAlive notifiers now
re-check `ref.mounted` after each slow await and bail out instead.

**Setup.** A waveform large enough that analysis is not instantaneous (a
multi-hundred-MB FST is ideal — the race window on a small VCD can be too
short to hit by hand).

**Steps.**

1. Open the file in a tab. Start an X-origin trace on a signal that goes X.
2. Close the tab *while the trace is still running*.
3. Expect: the tab closes immediately, no error dialog or toast, no
   `UnmountedRefException` in the console (run a debug build so the console is
   visible), and the app stays responsive.
4. Repeat for: pattern search, switching-activity analysis, and — with a
   comparison file — `Compare → Open Comparison File…`, closing the tab during
   the load.
5. **Memory (diff only).** Open a diff, note process memory in App Diagnostics
   → Memory, close the tab, and re-check. Memory should drop by roughly the
   comparison file's size. The comparison source is closed when the notifier is
   disposed; before this, nothing closed it and the second file stayed resident
   for the life of the process.
6. **Pro build.** Ask the AI Advisor a question and close the tab mid-answer.
   Same expectation — no error, and the answer is simply discarded.

**Edge cases.**

- Closing the *last* tab (which returns to empty-canvas) during an analysis
  behaves the same way.
- Closing a *different* tab while this one analyzes must not disturb the
  running analysis — only the owning tab's disposal cancels the publish.

| Test | Automation Assessment |
|---|---|
| X-trace / pattern search / switching activity survive container disposal mid-await | **AUTOMATED — UNIT** (`test/features/viewer/providers/notifier_dispose_race_test.dart` — a blocking data source holds `loadSignal` open, the container is disposed mid-await, then the load is released; each method must complete without throwing) |
| Diff notifier releases the comparison source on disposal | **MANUAL** — the leak is only observable as a process-memory delta; `close()` on a native source has no assertable Dart-side effect |
| AI Advisor multi-turn loop survives tab close | **MANUAL** (Pro) — needs a real model key and a real network round-trip; see the Pro guide |
| No `UnmountedRefException` reaches the console in a real session | **MANUAL** — requires a debug build and a real large file to widen the race window |

### 22.9.4 Reset and named workspaces

1. With three tabs open, run `File → Reset Workspace`. Single confirmation dialog. After confirm, empty-canvas returns.
2. Open two new files. Run `File → Save Workspace As…` → `team-debug.wavecrux-workspace`. The workspace is saved as a named file.
3. Reset again. Run `File → Open Workspace…` → choose `team-debug.wavecrux-workspace`. The two tabs reopen.
4. Verify the recent workspaces list on the empty-canvas state shows `team-debug.wavecrux-workspace`.

**Expected:** Named workspace files are interchangeable across machines/users (paths must resolve).

### 22.9.5 Export tab as `.wavecrux`

1. Open file A in a tab. Configure signals, cursor, zoom.
2. `File → Export Tab as Session…` → save as `debug.wavecrux`.
3. From a different machine (or after closing the tab), open `debug.wavecrux` — the tab opens with the saved state in a new tab inside the current workspace.

**Expected:** `.wavecrux` is now an export format only; never the working file.

### 22.9.6 Missing file on restore

1. Open file A and file B; quit.
2. Move or delete file A.
3. Relaunch. Tab for file A drops from the workspace; tab for B opens. A non-blocking snackbar lists the dropped path. App does not crash.

**Expected:** Graceful degradation; the snackbar message is localized in all four locales.

### 22.9.7 One-shot migration from `last_session.json`

1. Write a synthetic `last_session.json` to `{appSupportDir}` containing two file paths.
2. Delete `workspace.json` if present.
3. Launch the app. The two tabs restore as expected; `last_session.json` is deleted; `workspace.json` is created.
4. Quit and relaunch — restoration now uses `workspace.json` exclusively.

**Expected:** Migration is one-shot and idempotent; subsequent launches do not look for `last_session.json`.

### 22.9.8 Split-pane creation and collapse

1. Open two files in two tabs. Run `View → Split Pane Right` (`Cmd+\`). The active tab moves to a new right pane; the active pane indicator updates.
2. Drag the second tab from the left pane to the right pane — verify the tab moves between panes.
3. File→Open file C — opens in the active (right) pane.
4. Close the last tab in the right pane. The layout auto-collapses back to single-pane; all remaining tabs in the left pane survive.
5. Run `View → Close Pane` (`Cmd/Ctrl+Shift+W`) from the View menu, the command palette, or the keyboard at any time with two panes open — tabs from the closed pane merge into the surviving pane. (Note: the original intent was a VSCode-style chord like `Cmd+K W`, but Flutter's `SingleActivator` does not support chord activators, so the action uses the single-key fallback `Cmd/Ctrl+Shift+W` — distinct from `Cmd/Ctrl+W` (closeTab) and bare `W` (waveform zoom-in).)
6. **No-empty-sibling invariant (regression check).** After step 4, quit the app *immediately* (`Cmd+Q`) — don't open new tabs first. Relaunch. The restored workspace must show exactly one pane. Pre-fix, the lifecycle flush could race the live-tab → workspace mirror and persist the just-emptied pane to `workspace.json`, surfacing on next launch as a phantom pane with no UI affordance to close it. `_flushWorkspace` now drops empty panes when at least one populated pane survives; `WaveCruxWorkspaceNotifier.build()` applies the same sanitization on load so any legacy bad state on disk self-heals.
7. **Cross-pane drag must not crash semantics (regression check).** With two panes open and a file loaded in each, drag a tab from one pane to the other while watching the debug console. The move must complete with **no** exception. Pre-fix, the per-tab waveform `RepaintBoundary` carried a pane-agnostic `GlobalKey` — the only `GlobalKey` in the tab-content subtree — so when the tab's content left the source pane's `IndexedStack` and entered the target pane's in one frame, Flutter *migrated* that live element across the two stacks and the next `flushSemantics` walked a stale parent→child geometry relationship, throwing `'package:flutter/src/rendering/object.dart': Failed assertion … 'identical(childRenderObject, parentRenderObject)'` followed by a `Null check operator used on a null value`. (Most visible on Linux, where the accessibility bridge keeps semantics active every frame.) The key is now scoped per **(host pane, tab)**, so the canvas tears down in the source pane and rebuilds fresh in the target pane with no element migration; scroll/zoom/cursor survive because they live in the per-tab `ProviderContainer`, not widget state. The same scoping also fixes a latent "Multiple widgets used the same GlobalKey" crash when a `PaneId.primary`-sentinel tab is rendered by two panes at once.

**Expected:** Pane focus indicator (border or tab-bar accent) is always visible. Drag preview shows the target pane as a drop zone. The tab moves between panes with no console exception and no loss of the waveform's scroll/zoom/cursor state. After every close/move that empties a pane, the layout collapses to a single pane both in the running session and across a quit/relaunch cycle — at no point should the user see an empty pane next to a populated one.

| Test | Coverage |
|---|---|
| Live close-last-tab auto-collapses pane (Issue 1) | **UNIT** (`test/features/tabs/providers/tab_list_notifier_test.dart`) |
| Loader strips stranded empty sibling pane from workspace.json | **UNIT** (`test/features/workspace/providers/workspace_provider_test.dart`) |
| Boot-race + flush both refuse to surface or persist an empty sibling pane | **INTEGRATION** (`integration_test/workspace/empty_pane_no_persist_test.dart`) |
| Cross-pane drag (sentinel double-render) does not crash on a shared GlobalKey | **WIDGET** (`test/features/viewer/screens/viewer_screen_test.dart` — `'dragging a tab between panes does not crash semantics (cross-pane reparent)'`; fails pre-fix on "Multiple widgets used the same GlobalKey") |
| Cross-pane move between two real panes completes cleanly (host-key resolution) | **WIDGET** (`test/features/viewer/screens/viewer_screen_test.dart` — `'moving a tab between two non-primary panes does not crash semantics'`; the framework `identical(...)` assertion itself needs the desktop binding and is **MANUAL**) |

### 22.9.9 Split-pane: device gating

1. On phone (resize the desktop window below 600 dp width to simulate), verify the `View → Split Pane Right` action is hidden / disabled and the layout is always single-pane.
2. On tablet at width < 1000 dp, verify the split action is hidden.
3. On tablet at width ≥ 1000 dp, verify split works as on desktop.

**Expected:** Device gating is enforced by `deviceClassProvider` width + height checks; no manual flag.

### 22.9.10 Tools menu: Generate Test VCD…

1. Run `Tools → Generate Test VCD…` from the menu bar, the command palette (search "Generate Test VCD"), or the keyboard shortcut `Cmd/Ctrl+Alt+G`. (The slot `Cmd/Ctrl+Shift+G` is taken by `toggleStagePanel`; `Cmd/Ctrl+Alt+G` reads as "Generate" and avoids the conflict.)
2. Dialog appears with: signal count slider, duration field, complexity selector, seed, **destination picker** (button + path display), and three action buttons: "Generate & Open in New Tab", "Generate & Reveal", "Cancel".
3. Pick a destination, click "Generate & Open in New Tab". The VCD is written; a new tab opens with the file loaded.
4. Repeat with "Generate & Reveal" — the platform file manager opens to the destination directory; no tab is opened.

**Expected:** No tab is overwritten. The Generator tab no longer appears inside the legacy diagnostics dialog (verify by opening App Diagnostics — it has only Memory and Frame Stats sections).

### 22.9.11 Statistics strip: per-pane behavior

1. On desktop, expand the statistics strip (▲ in status bar). Open one file in one pane. Watch paint-time sparkline accumulate.
2. Split pane right and open a second file in the right pane. Activate the right pane.
3. The strip's paint-time sparkline now reflects the right pane's render; the left pane's history is retained — switch focus back to the left pane to confirm the sparkline restores its previous samples.
4. The strip's memory + FPS segments are unaffected by pane focus — they remain continuous. (Note: FPS is derived from the active pane's paint snapshot, so it does swap with focus; only memory and the decompressed-signal aggregate are app-level.)

**Expected:** Per-pane segments swap; app-level segments are continuous. No data loss on pane switch. **There must be no cross-pane contamination** — pane A's sparkline contains only samples from pane A's canvas, never anything painted in pane B. Pre-fix (Issue 31), a dead root-scope `onPaint` bridge in `renderStatsCollectorProvider` could mix samples into the root notifier in test or fallback paths; the bridge has been removed so the per-pane `PaneContainerManager._attachBridge` is the only collector→notifier path in the codebase, guaranteeing isolation by construction.

### 22.9.12 Workspace mutation telemetry (open-core seam)

`WaveCruxWorkspaceNotifier` records a `TelemetryEvent` on every workspace lifecycle/mutation via the open-core `telemetryServiceProvider` extension point (default `NoopTelemetryService`; a downstream build — e.g. the Pro overlay — may install a live sink). The events:

- `workspace.restored` (on `build`, with `{tabs, panes}` counts)
- `tab.opened` (on `addTab`, with `{tabs, panes}` counts) — **added 2026-05-28**; `addTab` previously emitted nothing on open. This is the open-core half of the Pro overlay's workspace-events telemetry test.
- `pane.split` (on `splitPane`, once per actual split — a no-op second split does not re-emit)
- `pane.closed` (on `closePane`)
- `tab.dragged_to_pane` (on `moveTabToPane`)
- `workspace.reset` (on `reset`)
- `workspace.named.opened` / `workspace.named.saved` (named-workspace open/save commands)

**Expected:** events fire on the production mutation paths with the names above; no-op mutations (duplicate-id `addTab`, redundant `splitPane`) do not emit. Telemetry is tier-independent — the events fire regardless of license tier; only the installed sink differs.

| Test | Coverage |
|---|---|
| Each mutation records its event (incl. `tab.opened` + no-op suppression) | **WIDGET** (`test/services/telemetry/workspace_events_test.dart`) |

### 22.9.12 Edge cases

- **Corrupt workspace.json:** Truncate the file mid-JSON. Relaunch — empty-canvas appears; non-blocking snackbar lists the corruption; `workspace.json` is overwritten on next quit.
- **Workspace pointing at unreadable file (permissions):** Tab opens in an error placeholder; no crash.
- **Two tabs with same filename in different folders:** Display name disambiguates with the parent folder shown in parentheses.
- **Drag tab to non-pane drop zone:** Drag is canceled; tab returns to its original pane.

### 22.9.13 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| `Workspace` / `WorkspaceTab` / `WorkspacePane` model round-trip | `[Coverage: AUTOMATED]` | `test/services/workspace/wavecrux_workspace_codec_test.dart` |
| Schema versioning + unknown-version rejection | `[Coverage: AUTOMATED]` | same file |
| `WorkspaceService` save/load/atomic-write (codec layer) | `[Coverage: AUTOMATED]` | `test/services/workspace/wavecrux_workspace_codec_test.dart` |
| Migration from `last_session.json` | `[Coverage: INTEGRATION_TEST]` | `integration_test/workspace/last_session_migration_test.dart` — seeds legacy `last_session.json` via `LastSessionService.save`, clears `workspace.json`, runs `bootstrap()` (which invokes the synchronous `LastSessionMigration`), asserts the legacy file is deleted, `workspace.json` exists at `kWorkspaceSchemaVersion`, restored tabs match the seeded paths in a single-pane layout. |
| `workspaceProvider` round-trip | `[Coverage: AUTOMATED]` | `test/features/workspace/providers/workspace_provider_test.dart` |
| Empty-canvas state widget tests | `[Coverage: WIDGET]` | `test/features/workspace/widgets/wavecrux_empty_canvas_test.dart` — locale sweep, recent files, recent workspaces, three action buttons, 320 dp no-overflow, phone "Other tabs" fallback |
| Save Workspace As / Reset / Open / New workspace commands | `[Coverage: WIDGET]` | `test/features/workspace/commands/{save_workspace_as,reset_workspace,open_workspace,new_workspace}_command_test.dart` |
| File→Open always appends | `[Coverage: WIDGET — pending]` | extend `viewer_tab_bar_test.dart` |
| Generator destination picker flow | `[Coverage: WIDGET]` | `test/features/tools/widgets/generate_test_vcd_dialog_test.dart` — controls render, destination picker, Generate & Open / Reveal paths, `GenerateTestVcdDialog.show` entry-point (Tools menu + command palette), locale sweep |
| Split-pane creation/collapse | `[Coverage: WIDGET + UNIT]` | `test/features/panes/widgets/wavecrux_pane_host_test.dart` renders the single/split pane host (locale sweep, pane border); split creation + close-pane collapse are covered by `test/features/panes/providers/active_pane_id_provider_test.dart`, and drag-tab-to-pane (`moveTabToPane`) by `test/features/workspace/providers/workspace_provider_test.dart` |
| Drag-tab-to-pane | `[Coverage: UNIT]` | `test/features/workspace/providers/workspace_provider_test.dart` — `moveTabToPane` reassigns paneId after `splitPane()` |
| Statistics strip per-pane sparkline swap | `[Coverage: WIDGET]` | `test/features/statistics/widgets/live_statistics_strip_test.dart` — paint-time sparkline swaps with active pane, memory and decompressed-signal aggregate stay continuous, pane indicator hidden in single-pane mode |
| Quit→restart restores workspace (1 tab) | `[Coverage: INTEGRATION_TEST]` | `integration_test/workspace/restore_one_tab_test.dart` — boots one fixture, places cursor + zoom, flushes the workspace document AND the per-tab session sidecar through the same code path `AppLifecycleState.detached` runs, then reads both back through fresh service instances to assert tab/pane shape, cursor tick, and `ticksPerPixel` all survive. |
| Quit→restart restores workspace (multi-tab + split-pane) | `[Coverage: INTEGRATION_TEST]` | `integration_test/workspace/restore_split_pane_test.dart` — boots two fixtures, calls `WorkspaceNotifier.splitPane()` then `TabListNotifier.moveTabToPane` (matches `ViewerScreen._splitPaneRight`), flushes, asserts `workspace.json` records two panes with each tab in the correct pane, `activePaneId` follows the split focus shift, and each pane's `activeTabId` is right. |
| Quit→restart restores empty canvas | `[Coverage: INTEGRATION_TEST]` | `integration_test/workspace/restore_empty_test.dart` — boots a fixture, closes the lone tab, asserts the live tab list goes empty, `EmptyCanvasState` renders (via `Key('empty_canvas_state')`), and the flushed `workspace.json` records zero tabs in a single empty pane (the canonical `Workspace.empty()` shape). |
| Missing-file-on-restore snackbar | `[Coverage: INTEGRATION_TEST]` | `integration_test/workspace/missing_file_test.dart` — pre-seeds `workspace.json` with one existing fixture and one never-existed path under the OS temp dir, boots with no CLI args, asserts the missing tab is dropped, the survivor opens with its persisted TabId preserved, and `workspaceRestoreDroppedSingle` localized snackbar lists the missing path. No-crash check via `tester.takeException()`. |
| Named workspace save/open | `[Coverage: INTEGRATION_TEST]` | `integration_test/workspace/named_workspace_test.dart` — boots three fixtures, runs `saveWorkspaceAsForContainer` → `resetWorkspaceStateForContainer` → `openWorkspaceFromPathForContainer` against a temp `.wavecrux-workspace` path, asserts the reset transitions through `EmptyCanvasState`, and the reopen round-trips all three tabs with original ids, pane assignment, `activePaneId`, and active-tab pointer. |
| Tab export to `.wavecrux` and re-import | `[Coverage: INTEGRATION_TEST]` | `integration_test/workspace/tab_export_import_test.dart` — boots fixture A, places cursor at tick 42, runs `exportTabForContainer` to a temp `.wavecrux`, closes the tab, opens the export via the `TabListNotifier.openSession` + per-tab `SessionNotifier.loadFromPath` pair the OS file-picker entry uses, asserts the new tab carries both the file binding and the cursor placement from before export. |
| CLI append to active pane | `[Coverage: INTEGRATION_TEST]` | `integration_test/workspace/cli_append_test.dart` — pre-seeds a one-tab workspace, boots with no CLI args so `_restoreFromWorkspace` runs, then drives the same `notifier.openFile` + activate-original sequence the production CLI additional-files post-frame callback uses. Asserts the original tab survives, two appended tabs land in the workspace's active pane, focus stays on the original, and `workspace.json` mirrors all three live tabs in a single pane. |
| Reset Workspace command | `[Coverage: WIDGET]` | `test/features/workspace/commands/reset_workspace_command_test.dart` |
| Device gating for split-pane (phone / narrow tablet) | `[Coverage: MANUAL]` | No committed automated test exercises the phone / narrow-tablet split-pane device gate; verified visually. |

### 22.9.14 Session per-tab decoder persistence + extension-payload seam

#### 22.9.14.1 What it does

Session decoder persistence closes a long-standing gap: protocol decoders the user has activated in a tab survive a quit / relaunch (and a per-tab `.wavecrux` export / import). Two open-core changes back this:

1. **Decoder serialization.** `SessionState` carries a new `decoders: List<PersistedDecoder>` field. Each entry is `{decoderId, instanceNumber, config}` — the registry key, the per-type sequence number that powers the "SPI #2" label, and the binding + parameter map. `SessionService` writes the list under a `"decoders"` top-level array on the document. On restore, `ActiveDecodersNotifier.restoreDecoders` re-creates each `ActiveDecoder` in a single state replacement, then `decodeAll()` repopulates transactions against the freshly-opened waveform.
2. **Extension-payload seam** (the carrier the Pro overlay plugs SVA / Debug-Advisor / future per-feature state into). `extraSessionPayloadCodecsProvider` registers codecs under string namespaces (`"pro.sva"`, …); their captures land under the reserved top-level `extensions` map. **Preserve-unknown invariant:** an entry whose namespace has no codec on the current build round-trips untouched — that is the foundation of the cross-tier-open story (Pro session opened on Open Core viewer never corrupts the Pro payload).

A few quieter behaviors come along for the ride:
- Schema version bumped `1 → 2`; forward-compat policy is "lenient read" — a hypothetical newer document still loads, and the `extensions` map preserves any new payload the newer build wrote.
- `WaveformSourceNotifier.openFile` grew a `preserveDecoders:` parameter. `SessionNotifier._restore` and `reloadCurrentFile` pass `true`; everything else gets the unchanged `clearAll`-everything behavior. The seam exists so the active-decoders provider never observes a transient `[]` mid-restore (the "decoder flicker" bug the integration test asserts against).
- The per-tab debounced autosave (`SessionAutoSaveNotifier`) now listens to `activeDecodersProvider`, so any add / remove / config edit lands in the sidecar within the autosave interval.

#### 22.9.14.2 Setup

A debug or profile build with diagnostics on, plus the combined SPI + I²C fixture at `verification/fixtures/protocol/multi/spi_i2c_basic.vcd` (already used by §15.7 multi-decoder coexistence — no new fixtures needed).

#### 22.9.14.3 Steps — happy path (round-trip across restart)

1. Boot the app on `spi_i2c_basic.vcd`. Add an SPI decoder via the picker, auto-bind, confirm. Repeat for I²C. Verify the transaction table shows both decoders' transactions.
2. Quit the app (Cmd-Q on macOS). The per-tab sidecar at `{appSupportDir}/sessions/{tabId}.json` should already contain a `"decoders"` array (the debounced autosave flushed on lifecycle paused/detached).
3. Inspect the sidecar with `jq '.decoders' /path/to/sidecar.wavecrux`. Expect two entries with `decoderId == "spi"` / `"i2c"`, the `instanceNumber` values you saw in the tab labels, and a populated `config.bindings` map.
4. Relaunch. The workspace restore opens the tab. Expected:
   - Both decoders appear in the toolbar / status as "SPI #1" and "I²C #1" (same labels).
   - The transaction table is populated within ~1s (the open-time decodeAll pass) — no "Add Decoder" affordance is required.
   - Cursor / zoom / signal groups restore alongside, as today.

#### 22.9.14.4 Steps — Export Tab as Session + re-import

1. With a tab carrying two decoders, run File → Export Tab as Session… to a temp `.wavecrux`.
2. Open `jq '.decoders' /tmp/exported.wavecrux`. Same shape as the sidecar (the two formats share the SessionService writer).
3. Open the exported `.wavecrux` in a new tab. Decoders restore against the same fixture, transactions populate.

#### 22.9.14.5 Steps — cross-tier-open (Open Core opens a Pro-authored session)

This is the open-core half of the cross-tier-open contract; the Pro half is verified in the Pro overlay's own guide.

1. Hand-craft (or have a Pro build produce) a `.wavecrux` containing a `decoders` entry with `decoderId == "pro.usb"` (a decoder that exists in Pro but not in Open Core), alongside an open-core decoder like `"spi"`.
2. Open the file on the Open Core build. Expected:
   - The SPI decoder restores normally and decodes.
   - The `"pro.usb"` entry is skipped — no snackbar, no exception.
   - `flutter logs` / Console shows a single `debugPrint`: `"wavecrux: SessionService restore — skipped 1 persisted decoder(s) not in DecoderRegistry: pro.usb."`.
   - The `extensions` payload — even one written for `"pro.usb"` Pro state under e.g. `"pro.usb_runtime"` — is preserved-but-inert. Move the cursor (triggers autosave), inspect the sidecar: the `extensions.pro.usb_runtime` entry is still there byte-equivalent. Save round-trip never drops it.

#### 22.9.14.6 Steps — backward read of pre-decoder sessions

1. Find a `.wavecrux` from before decoder persistence (or hand-craft one with no `decoders` key and no `extensions` key). Open it.
2. Expected: loads cleanly, decoders list empty, behaves identically to a fresh session apart from whatever state it WAS persisting.
3. Mutate state (place a cursor); the autosave rewrites the file with `"version": 2`. The `"decoders"` and `"extensions"` keys are NOT emitted when their respective collections are empty — byte-stable for sessions that never gained either.

#### 22.9.14.7 Diagnostics-assisted verification

The diagnostics surfaces do not directly visualize the session document. Use the filesystem:

- `jq '.version, .decoders, .extensions' /path/to/sidecar.wavecrux` — quick view of the three decoder-persistence fields.
- `flutter logs` (or Console.app on macOS) for the unknown-decoderId skip message during cross-tier-open verification.

#### 22.9.14.8 Edge cases / break-it tests

- **Empty `decoders` array.** `[]` reads as empty list, re-saves with no key (open-core writer omits empty arrays for byte stability).
- **Malformed `decoders` entries.** A `decoders` array containing non-Map elements (`"foo"`, `42`, `null`) — non-Map entries are skipped silently; the rest of the array still parses. (Unit-tested in `session_decoder_backward_read_test.dart`.)
- **Unknown decoderId with a valid config block.** Skipped at restore time with the debug log. The persisted entry is NOT carried forward to the next save (unlike the `extensions` map, the decoders list is the canonical projection of the live `ActiveDecodersNotifier` state). This is intentional — a Pro decoder opened on Open Core stays available until the user re-saves the session; once re-saved it is gone. The user-visible affordance for "I want to keep this Pro decoder for later" is to leave the session sidecar untouched (don't trigger a save) until they reopen on a Pro build.
- **A persisted instanceNumber that collides with a freshly-added decoder.** `restoreDecoders` bumps the per-type counter past every restored entry; an add after restore picks `max(persisted) + 1`. No collision possible.
- **Future schema (`version > 2`).** Lenient read — the document loads, `extensions` rides through, on save the version is re-stamped to current. Surface the policy decision via the SessionService class doc-comment.
- **Decoder config whose signal bindings point at a signal that no longer exists in the source file** (e.g. the VCD was regenerated with a renamed signal). The decoder restores; `decodeAll`'s `loadSignal` swallows the error and the decoder gets nulls — same behavior as today when a binding is wrong. No throw.

#### 22.9.14.9 Tier-gate scenarios

N/A — decoder persistence is open-core. Pro decoders that fail to resolve on a non-Pro build trigger the silent-skip path; that is the **only** tier-gated behavior, and it lives in `ActiveDecodersNotifier.restoreDecoders` rather than at a tier-badge surface.

#### 22.9.14.10 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| `DecoderConfig.toJson` / `fromJson` round-trip | `[Coverage: AUTOMATED]` | `test/domain/models/decoder_config_test.dart` — round-trips, missing-bindings tolerance, non-string-binding drop, heterogeneous parameter types |
| `PersistedDecoder` round-trip + equality + copyWith | `[Coverage: AUTOMATED]` | `test/domain/models/persisted_decoder_test.dart` — all fields, empty-decoderId preserve for the unknown-id branch |
| `SessionState.decoders` round-trips byte-stable through `SessionService` | `[Coverage: AUTOMATED]` | `test/services/session/session_decoder_round_trip_test.dart` — two-entry round-trip, ordering preserved, empty list omits the key |
| Backward read: missing `decoders` key reads as empty | `[Coverage: AUTOMATED]` | `test/services/session/session_decoder_backward_read_test.dart` — pre-decoder documents, `decoders: null`, malformed-entry drop |
| Unknown decoderId restore: skipped silently, log line fires, kept entry preserves instanceNumber | `[Coverage: AUTOMATED]` | `test/services/session/session_decoder_unknown_id_test.dart` — three cases including all-unknown short-circuit |
| End-to-end: decoders restore on .wavecrux open with NO transient empty-list emission | `[Coverage: INTEGRATION_TEST]` | `integration_test/decoders/decoder_restore_on_open_test.dart` — boots SPI+I²C fixture, snapshots session, restores via `SessionNotifier.loadFromPath`, asserts `container.listen` never observed an empty active-decoders state |
| `extraSessionPayloadCodecsProvider` preserve-unknown round-trip | `[Coverage: AUTOMATED]` | `test/services/session/session_extensions_round_trip_test.dart` — unknown namespace survives a no-codec load + save |
| Codec capture / restore via `ProviderContainer` | `[Coverage: AUTOMATED]` | `test/services/session/session_extensions_codec_test.dart` — captures from live provider, persists, restores into target provider |
| Codec capture / restore through the **live `SessionNotifier._snapshot` / `_restore`** path (not just the `SessionExtensions` helper in isolation) | `[Coverage: AUTOMATED]` | `test/features/viewer/providers/session_providers_test.dart` — "session-extension codec wiring" group: a registered codec's payload lands in `extensions` on `saveToPath`, replays on `restoreFromState`, opt-out (null capture) omits the key, and an unknown namespace survives a `restore → snapshot` cycle (preserve-unknown enforced at the notifier layer, not only at the serializer). This is the wiring the Pro `pro.sva` codec depends on. |
| Schema-version stamp on save (`"version": 2`) + lenient read of future versions | `[Coverage: AUTOMATED]` | `test/services/session/session_service_test.dart` + `session_extensions_round_trip_test.dart` |
| Cross-tier-open behavior on the Pro side (Pro session opened on Open Core, then re-saved on Pro) | `[Coverage: MANUAL]` | covered by the Pro overlay's own guide; the open-core half is exercised by `session_decoder_unknown_id_test.dart` |
| `reloadCurrentFile` preserves decoders (auto-reload on file change) | `[Coverage: MANUAL]` | follow-up integration test; today the same `preserveDecoders: true` seam is used so the open-core path is the same — manual check: edit the open VCD on disk, accept the auto-reload, confirm decoders survive |

---

### 22.9.15 Per-tab provider scoping correctness (issue #44 regression)

### What it does

Every tab is an independent workspace backed by its own child `ProviderContainer` whose per-tab providers are overridden in `wavecruxTabOverrides` (`lib/services/tabs/wavecrux_tab_overrides.dart`). The **failure mode this section guards** is a *scope leak*: a code-generated `@riverpod` provider that reads per-tab state (`waveformSourceProvider`, `cursorStateProvider`, `signalGroupsProvider`, …) but is neither listed in `wavecruxTabOverrides` nor declares its per-tab `dependencies:`. Such a provider is silently hoisted to the **root** container, where it reads the empty root-scope versions of those providers and returns degraded output with **no exception** — the hallmark of this whole bug class.

Issue #44 was the visible instance: `stageBoundSignalProvider` was missing from the override list, so every Stage widget binding resolved against the file-less root source and rendered `–` (inactive) regardless of cursor position. A structural audit at fix time surfaced three more latent members of the same class — `fsmCurrentStateIdProvider` / `fsmRecentTransitionProvider` (FSM bubble diagram never highlighted) and a `ref.read` in `mobileMemoryGuardProvider` (memory pressure would unload the *visible* signals) — all fixed in the same change.

### Setup

```bash
flutter run -d macos   # or -d linux, -d windows
```

Use any VCD with a multi-bit signal (e.g. `test/fixtures/protocol/spi/generated/spi_flash_fast_read.vcd`).

### Step-by-step

1. **Stage binding (issue #44 proper).** Open the VCD. Open the Stage panel, drop an LED widget, and bind it to a signal (drag-and-drop from the signal list *and*, separately, the tap-to-pick dialog). Move the primary cursor across an edge of the bound signal.
   - **Expected:** the LED tracks the signal value (on/off), not a permanent `–`. The bindings pane shows the bound signal's handle.
2. **Per-tab isolation.** Open a *second* file in a new tab and bind a Stage widget there too. Switch between tabs.
   - **Expected:** each tab's Stage widgets reflect *that tab's* file and cursor — never the other tab's, never blank.
3. **FSM diagram.** In a tab with a file loaded, run FSM analysis on a state signal and open the FSM bubble diagram. Scrub the cursor.
   - **Expected:** the current state node highlights and the most-recent-transition edge is emphasized at the cursor, in the focused tab.
4. **Memory guard (mobile/tablet).** On a tablet/phone build, load enough signals to approach the large-file threshold, then trigger memory pressure (or the OS low-memory callback).
   - **Expected:** only signals *not* in the active tab's visible signal group are unloaded; signals you are actively viewing stay loaded.

### Diagnostics-assisted verification

The bug is invisible without behavior observation, but the structural guard makes it CI-catchable: `flutter test test/static/per_tab_provider_scope_leak_test.dart` enumerates every provider that reads per-tab state and fails if any is neither overridden nor `dependencies:`-scoped (excluding a small documented allowlist of intentionally root-scoped app-global services).

### Edge cases

- A provider may legitimately read per-tab state from **root** if it is an app-global service that explicitly resolves the active tab's container via `tabContainerManagerProvider`. Two such services do this: `mobileMemoryGuardProvider` (memory pressure unloads from the active tab) and `remoteControlProvider` (the WCP server routes every command/query through the active tab's container — verified by `test/services/remote/remote_control_notifier_test.dart` "per-tab command routing"). Because they read via the resolved `tabContainer`, not `ref`, the static guard does not flag them and they need no allowlist entry.
- Only `cocotbLogProvider` (the app-global shared cocotb log) remains allowlisted in the static guard, with a documented reason.

> **WCP `load` semantics:** the `load` command opens the file into the **active tab** (consistent with the pre-multi-tab single-source behavior), rather than spawning a new tab the way the File→Open UI does. If a future WCP revision should open a fresh tab instead, that is a protocol change, not a scoping fix.

### Automation Assessment

| Test | Coverage | Where |
|---|---|---|
| Whole bug class: no provider reads per-tab state without being scoped (override OR `dependencies:`) | `[Coverage: AUTOMATED]` | `test/static/per_tab_provider_scope_leak_test.dart` — source-driven static guard; auto-discovers new providers; allowlist self-checks against rename |
| Issue #44 behavioral: `stageBoundSignal` resolves the focused tab source in a real parent/child container, `noFile` at root | `[Coverage: AUTOMATED]` | `test/services/tabs/per_tab_scope_behavior_test.dart` — exercises the real `TabContainerManager` (not a flat container) |
| `stageBoundSignalProvider` / FSM providers / `timeRulerDataProvider` are in the per-tab override list | `[Coverage: AUTOMATED]` | `test/services/tabs/wavecrux_tab_overrides_test.dart` — issue #44 + FSM + timescale regression assertions (alongside the issue #17 / #20 pins) |
| Stage binding renders live value end-to-end in the running app | `[Coverage: MANUAL]` | steps 1–2 above — UX feel / drag-and-drop |
| FSM diagram highlight + memory-guard unload selection | `[Coverage: MANUAL]` | steps 3–4 above — mobile memory pressure is OS-driven |

---

### 22.9.16 Per-tab panel visibility + session persistence

### What it does

Panel visibility — signal-tree (left), value-column (right), bottom pane
(transaction table / Stage / FSM / X-Trace / switching-activity / cocotb), and
the desktop statistics strip — is **per-tab**. Each tab keeps its own panel
arrangement; toggling a chevron, the toolbar Stage/transaction button, or a
menu item affects **only the active tab**, even when two tabs are docked in the
same split pane. The state lives in `panelLayoutProvider`, overridden per-tab in
`wavecruxTabOverrides`; each tab's `IdeController` (the `panes` split geometry)
is the 1:1 mirror of its own state, so the chevron indicator and the rendered
panel can never disagree. New tabs start at the clean-slate defaults
(signal-tree + value-column shown, bottom pane closed) — a new tab does **not**
inherit another tab's open panel.

Because the per-tab session sidecar (`{appSupportDir}/sessions/{tabId}.json`)
snapshots and restores `panelLayoutProvider`, each tab's panel arrangement is
**persisted and restored across restart** — independently for every tab. (Before
this change panel state was tracked per-*pane* and the session snapshot read a
root singleton the UI never updated, so panel layout silently failed to
persist.)

> **History.** An earlier iteration tracked panel visibility per-pane (shared by
> a pane's tabs). That produced a split-brain on a newly-opened tab: the
> status-bar chevron read "open" (from the shared pane state) while the new
> tab's `IdeController` stayed closed, so the panel never rendered and the
> toolbar/chevron looked inert until you closed the panel in the first tab. The
> per-tab model removes the shared state entirely, so that desync is
> structurally impossible.

### Setup

```bash
flutter run -d macos   # or -d linux, -d windows
```

Use any VCD (e.g. `test/fixtures/protocol/spi/generated/spi_flash_fast_read.vcd`).

### Step-by-step

1. Open the VCD in tab 1. Open the bottom panel (toolbar transaction-table or
   Stage button, or the bottom-panel chevron in the status bar). Confirm the
   panel renders and the chevron points down.
2. Open a **new tab** (File→Open into a new tab — there is no `+` new-tab button).
   - **Expected:** the new tab starts with the bottom panel **closed** (its own
     clean-slate default) — it does not inherit tab 1's open panel. The chevron
     points the "open" direction and the panel area is empty/collapsed in a
     consistent way (indicator matches geometry). Opening the panel here works
     on the **first** click of the toolbar button / chevron.
3. Switch back to tab 1.
   - **Expected:** tab 1's bottom panel is still open exactly as you left it —
     tab 2's toggling never touched it.
4. Independently arrange each tab (e.g. tab 1: Stage panel + signal-tree hidden;
   tab 2: transaction table + value-column hidden). Switch between them.
   - **Expected:** every switch restores that tab's own arrangement; no panel
     "bleeds" across tabs.
5. **Split pane.** Split the view (⌘/Ctrl-split or the pane menu), put a tab in
   each pane, and give them different panel arrangements. Confirm each is
   independent.
6. **Persistence.** With both tabs arranged differently, quit the app and
   relaunch.
   - **Expected:** each tab reopens with its own panel arrangement restored
     (signal-tree / value-column / bottom-pane / statistics-strip visibility).

### Diagnostics-assisted verification

Behavioral — the indicator and rendered geometry are both on screen. The
per-tab session sidecar can be inspected under `{appSupportDir}/sessions/` — each
tab's `.wavecrux` file carries a `"panels"` object (`signalTree`, `valueColumn`,
`transactionView`, `stageView`, `statisticsStrip`).

### Edge cases

- **Same-pane independence.** Two tabs in one pane keep separate panel state —
  the defining difference from the old per-pane model.
- **Toolbar indicators while scrubbing (no crash).** The toolbar's
  transaction-table / Stage checkmarks reflect the **active tab**. Because the
  toolbar lives outside any tab's provider scope, it reads the active tab's
  state through a root-scope bridge (`activeTabPanelLayoutProvider`), NOT by
  entering the tab's container. Regression guard: open a VCD, add a Stage
  widget, open the bottom panel, and **scrub the cursor continuously** — the
  debug console must stay clean. (A prior implementation wrapped the toolbar in
  a second `UncontrolledProviderScope` over the active tab's container; that
  raced PaneHost's scope and spewed a repeated `setState()/markNeedsBuild()
  called during build` exception on every scrub frame.)
- **Phone width.** At phone widths the side/bottom panes are force-hidden
  regardless of the per-tab preference (§3.1.7); the preference is preserved and
  restores when the window grows back to tablet/desktop.
- **RTL-source & cocotb-log panels.** `rtlSourceVisible` is driven by its own
  provider and `cocotbLogPanelVisible` auto-derives from whether a cocotb log is
  loaded; neither is part of the five persisted `panels` flags, so they are
  restored by their own mechanisms, not the sidecar `panels` object.

### Automation Assessment

| Test | Coverage | Where |
|---|---|---|
| Panel visibility is per-tab — a new tab keeps its own default; its IdeController mirrors its own (closed) state, not another tab's open panel | `[Coverage: AUTOMATED]` | `test/features/viewer/screens/viewer_screen_test.dart` — "panel visibility is per-tab — a new tab keeps its own default…" |
| `panelLayoutProvider` is overridden per-tab (not isolated per-pane) | `[Coverage: AUTOMATED]` | `test/services/panes/pane_container_manager_test.dart` — "panelLayoutProvider is NOT isolated per-pane…"; the scope-leak guard `test/static/per_tab_provider_scope_leak_test.dart` confirms it is scoped per-tab |
| Session snapshot/restore round-trips panel visibility | `[Coverage: AUTOMATED]` | `test/features/viewer/providers/session_providers_test.dart` — panel-layout restore assertions |
| Toolbar's active-tab bridge mirrors the active tab's panel state and tracks only the active tab | `[Coverage: AUTOMATED]` | `test/features/viewer/providers/active_tab_panel_layout_provider_test.dart` |
| Same-pane / split-pane independence, statistics-strip per-tab, cross-restart persistence, no scrub-time exception | `[Coverage: MANUAL]` | steps 3–6 + toolbar-scrub edge case above — multi-tab UX and restart |

---

## 22.10 Diagnostics Restructuring

### What it does

The legacy single seven-tab "Diagnostics panel" dialog is split into **three surfaces** aligned with the workspace/pane/tab ownership model (see ARCHITECTURE.md §8.8). The Generator lives in the Tools menu; the remaining six tabs are redistributed:

- **Tab Diagnostics drawer** (per-tab — follows the active tab): File Info, Signal Health, Benchmark This File _(a fourth "Parser Backend" section was retired when the dual-parser model collapsed to one backend per platform.)_
- **App Diagnostics dialog** (process-wide): Memory (with per-tab breakdown), Frame Stats
- **Pane Render Stats popover** (per-pane): paint time breakdown, transitions per viewport, line segments

The legacy `DiagnosticsDialog` widget is deleted in the same change set. `diagnosticsAvailableProvider` is renamed to `diagnosticsEnabledProvider`.

### Platform scope

All three surfaces are available on tablet and desktop. Phone is unchanged (no diagnostics).

### Setup

```bash
flutter run -d macos
```

Use any two VCD fixtures so per-tab content can be observed independently.

### 22.10.1 Tab Diagnostics drawer

1. Open file A in tab 1. Right-click tab 1's chip → "Tab Diagnostics…". A side drawer slides in.
2. Verify three collapsible sections: File Info, Signal Health, Benchmark This File. _(The previously-listed "Parser Backend" section is gone.)_
3. Each section shows the data for file A (file size, format, signal counts; constant signals; benchmark options).
4. Switch to tab 2 (with a different file). The drawer content updates to reflect file B's stats.
5. Click "Copy Tab Diagnostics Report" — clipboard contains structured plain text identifying file B's tab.
6. Close tab B. The drawer closes (its target is gone).

**File Path row — truncated text reveal (Issue 23):**

7. With File Info expanded for a tab whose absolute file path overflows the drawer width, the **File Path** value is truncated with an ellipsis. Verify two reveals are available (per ARCHITECTURE.md §3.1.8.14):
   - **Desktop hover:** hover the value text — a tooltip surfaces with the full absolute path.
   - **Right-click / long-press on touch:** opens a `PlatformContextMenu`. The first entry is the non-interactive monospace full-path header; the second is **Copy File Path** (`Copy File Path` / `复制文件路径` / `ファイルパスをコピー` / `파일 경로 복사`). Choosing Copy File Path puts the full path on the system clipboard and shows the "Copied path to clipboard" snackbar.

**Expected:** The drawer never shows mixed data from two tabs. The drawer is non-modal — clicking the canvas does not dismiss it; an explicit close button or `Esc` closes it. The truncated File Path row is never a dead end; users can always read or copy the full path without leaving the app.

**Non-modal interaction (Issue 24):**

8. With the drawer open, click the tab close button (×) on any tab in the tab bar. The tab closes immediately — pre-fix the dialog's invisible modal barrier captured the click and the close button was effectively dead. Repeat with arbitrary chrome targets outside the drawer (toolbar buttons, status-bar chevrons, signal-list rows): all must remain interactive while the drawer stays open.

### 22.10.2 App Diagnostics dialog

1. Open `Tools → App Diagnostics…`. Modal dialog appears.
2. Two sections visible: Memory (overall RSS + Dart heap + total wellen DB + **per-tab breakdown table**), Frame Stats (FPS, frame budget overruns).
3. With three tabs open, the per-tab breakdown shows one row per tab, each with its wellen-DB contribution and decompressed signal count.
4. Click "Copy Full Diagnostics Report" — clipboard contains app-level metrics + the active pane's render stats + per-tab file info and signal health.

**Expected:** The dialog never references a specific tab; it is whole-app.

### 22.10.3 Pane Render Stats popover

> Issue 25: this section previously referred to a "+ button" adjacent to the
> `i`-icon and instructed the user to "split pane right and open a second
> tab in the right pane" with no setup. Both were wrong: the tab bar has no
> `+` new-tab button (File → Open creates new tabs; the tab-bar `+` was
> removed because a blank tab is a dead-end — opening a file always spawns a
> fresh tab and a blank tab exposes no in-tab way to load anything; WaveCrux
> simply omits `defaultPayloadBuilder` on its `crux.PaneHost`),
> and the split-pane (⊟) icon only appears once the active pane contains 2
> or more tabs. Updated steps below reflect the actual UI.

1. Open `protocol/spi/generated/spi_basic.vcd` in tab 1 so the canvas paints at least one frame (an empty placeholder pane still produces a non-null `PaneRenderStats` snapshot — see Issue 26 — but the popover is most informative against a real paint). The `i`-icon sits at the trailing end of the pane's tab bar. Click it: a popover appears with paint-time breakdown, transitions per viewport, line segments, and the canvas pixel dimensions.
2. To exercise the per-pane isolation under split-pane, you first need at least two tabs in the active pane (the split-pane button only appears once `panes.length == 1 && tabs.length ≥ 2`):
   - File → Open a second file → tab 2 appears in the active pane.
   - The split-pane button (⊟) is now visible in the tab bar's trailing affordance group. Click it — OR use `View → Split Pane Right` / `Cmd/Ctrl+\` (these work with one or more tabs and are the discoverable alternative paths). The active tab moves to a new right pane.
   - Each pane now shows its own `i`-icon. Open the right pane's popover — content reflects the right canvas's stats independently.
3. Switch active pane between left and right while both popovers are open — each popover continues to show its own pane's stats, not the active pane's.

**Expected:** Per-pane isolation. Two popovers can be open simultaneously without state mixing.

**Single-tap, simultaneous popovers (Issue 27):**

8. With pane A's popover open, click pane B's `i`-icon **once**. Verify B's popover appears and **A's popover remains visible** (pre-fix the `showMenu` modal route dismissed A's popover when B's opened, AND the click on B's icon was absorbed by A's modal barrier so B's popover never appeared at all — the user needed two clicks to see B).
9. Each popover now carries a dedicated close (×) button in its header (Material design size 18 icon, ≥ 32 dp touch target). Click A's `×` → A dismisses; B's popover stays open. Click B's `×` → B dismisses. Escape on a focused popover also dismisses it.

**Empty-canvas state (Issue 26):**

4. Open a file but do **not** add any signals to the canvas (so the canvas shows the "No signals" placeholder). Open the Pane Render Stats popover.
5. Verify **Canvas size** reports the actual on-screen pixel dimensions of the placeholder area (e.g. `1024×680 px`) rather than the misleading pre-fix `0×0 px`. The paint-time metrics legitimately stay at `0.0 ms` and `Visible transitions` stays at `0` (nothing is being painted), but the canvas dimensions reflect what the user actually sees.

### 22.10.4 Renamed access entry points

| Old (pre-4.10) | New (4.10+) |
|---|---|
| Toolbar "Diagnostics" button → opens 7-tab dialog | Toolbar "App Diagnostics" → opens App Diagnostics dialog (Memory + Frame Stats only) |
| Tools menu "Open Diagnostics" | Tools menu: three entries — "Tab Diagnostics", "App Diagnostics", and (for the per-pane popover, also reachable via the `i`-icon) |
| Command palette "Diagnostics: …" | Command palette: "Tab Diagnostics", "App Diagnostics", "Pane Render Stats", "Generate Test VCD…" (Tools) |
| Keyboard shortcut → 7-tab dialog | Three separate keyboard shortcuts (configurable in settings) |

### 22.10.5 Locale sweep

Switch to zh_CN, ja, ko. Verify all three surfaces render correctly with no overflow. The localized strings replace `diagnosticsDialog*` keys with new `tabDiagnostics*`, `appDiagnostics*`, and `paneRenderStats*` keys across the four ARB files.

### 22.10.6 Edge cases

- Open Tab Diagnostics drawer, then close all tabs → drawer auto-dismisses.
- Open App Diagnostics with no tabs open → Memory section shows app-level metrics only; per-tab breakdown table renders the `appDiagnosticsNoTabs` empty-state message ("No tabs are loaded." in English; localized equivalents in zh_CN/ja/ko). Issue 28: the guide previously quoted "No tabs open" verbatim; the actual ARB string is "No tabs are loaded." — verify the displayed text matches that exactly.
- Open Pane Render Stats with the canvas idle for >5 s → values stay stable; FPS reads as 0 because no frames are being painted (this is correct behavior).
- `diagnosticsEnabledProvider = false` in release build → all three entry points are hidden; verify the `i`-icon does not render on pane tab bars.

### 22.10.7 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| `TabDiagnosticsDrawer` widget tests | `[Coverage: WIDGET]` | `test/features/diagnostics/widgets/tab_diagnostics_drawer_test.dart` — three collapsible sections (File Info / Signal Health / Benchmark This File), follow-active-tab subtitle + re-keyed per-tab scope, close-on-tab-close, Copy Tab Diagnostics Report, non-modal interaction (Issue 24), locale sweep, touch target |
| `AppDiagnosticsDialog` widget tests | `[Coverage: WIDGET]` | `test/features/diagnostics/widgets/app_diagnostics_dialog_test.dart` — per-tab breakdown table, Copy Full Report, scrollable content + trackpad/mouse drag, locale sweep, gating |
| `PaneRenderStatsPopover` widget tests | `[Coverage: WIDGET]` | `test/features/diagnostics/widgets/pane_render_stats_popover_test.dart` — per-pane isolation under split-pane, two simultaneous popovers, activePaneIdProvider change does not swap content, placeholder when no frames recorded, single-tap reopen (Issue 27), locale sweep |
| `diagnosticsEnabledProvider` gating | `[Coverage: WIDGET]` | reuse existing `diagnostics_providers_test.dart` (rename in-place) |
| Legacy `DiagnosticsScreen` / `_DiagnosticsDialog` deleted (no widget references remain) | `[Coverage: STATIC]` | grep guard in `test/static/no_legacy_diagnostics_test.dart` |
| End-to-end: open + switch tabs + verify drawer follows | `[Coverage: INTEGRATION_TEST]` | `integration_test/diagnostics/tab_drawer_follow_active_test.dart` — boots two CLI fixtures, opens `TabDiagnosticsDrawer` via the production `open(context)` entry-point, switches `activeTabIdProvider`, asserts the drawer's subtitle reflects the new active tab. |
| End-to-end: split-pane → per-pane container isolation | `[Coverage: INTEGRATION_TEST]` | `integration_test/diagnostics/pane_popover_isolation_test.dart` — boots two CLI fixtures, splits right + `moveTabToPane`, asserts each pane's `paneRenderStatsProvider` (through `paneContainerManagerProvider.containerFor(id)`) holds its own state and active-pane changes / cross-pane mutations don't bleed between containers. (The popover UI display path is covered by the widget tier above; the integration tier focuses on the bootstrap + workspace + container-manager seam.) |

---

## 22.11 Web WASM Parsing — FST / GHW Support

### What it does

The `wellen` Rust library ships as a WebAssembly module so the Flutter Web
build can decode VCD, FST, and GHW with the same engine that powers the
native FFI build. The web build once handled only VCD via a pure-Dart parser
and rejected FST/GHW at the picker; all three formats now open identically
across desktop, mobile, and web.

### Platform scope

- **Web:** primary delivery surface — every browser that supports WebAssembly
  v1 (~96% of installed base). No special HTTP headers required (the wasm
  runs single-threaded, so cross-origin isolation is not needed).
- **Desktop / Mobile:** untouched — continues to use the FFI path.

### Setup

1. **Prerequisites (developer machine only):**
   ```bash
   rustup target add wasm32-unknown-unknown
   curl -sSf https://rustwasm.github.io/wasm-pack/installer/init.sh | sh
   ```
2. **Build:** `dart run tool/build_web_wasm.dart` — wraps `wasm-pack`,
   copies output into `web/wasm/`, and runs the 1.5 MB gzipped budget gate.
3. **Run:** `flutter run -d chrome --release` — the script above must have
   been run at least once so `web/wasm/wellen_wasm_bg.wasm` exists. CI
   handles this automatically via the new `wasm` job in `ci.yml`.

### 22.11.1 Happy-path open: VCD on web

- [ ] Build web release: `flutter build web --release` (after running
  `dart run tool/build_web_wasm.dart`).
- [ ] Serve `build/web/` with any static server (`python3 -m http.server`).
- [ ] Open in Chrome / Firefox / Safari / Edge.
- [ ] Drag the open-core `test/fixtures/vcd/scalar_basics.vcd` onto the
  WaveCrux drop zone or use the file picker.
- [ ] Expected: hierarchy populates, signal list populates, canvas renders
  with the same scalar transitions you see on the desktop build.
- [ ] Confirm `WellenWasmProvider` is the active backend — there is
  no the runtime provider override, so the way to verify is to look
  at the Web file picker UTIs (.vcd/.fst/.ghw accepted) and the
  diagnostics drawer's File Info / Benchmark sections having no
  parser-backend selector.

### 22.11.2 Happy-path open: FST on web (new capability)

- [ ] Drag an FST fixture (e.g. `test/fixtures/fst/scalar_basics.fst` if
  generated, or any FST from a real simulator run) onto the drop zone.
- [ ] Expected: the picker accepts the `.fst` extension. Hierarchy and
  canvas render exactly as on desktop. No VCD-only fallback message.
- [ ] Pick a signal — value column reads correct values at cursor times.

### 22.11.3 Happy-path open: GHW on web (new capability)

- [ ] Same as 22.11.2 with a `.ghw` fixture (e.g. produced by GHDL).
- [ ] Expected: open, hierarchy, value queries all work.

### 22.11.4 Cross-bridge equivalence (FFI vs WASM, VCD/FST/GHW)

This is the **Layer 1** check from ARCHITECTURE.md §8.9 (Wellen-vs-Wellen bridge
validation). It is now **automated** by
`integration_test/web/web_cross_bridge_test.dart`, which loads every fixture
under `test/fixtures/{vcd,fst,ghw}` through `WellenWasmProvider` in headless
Chrome and asserts `valueAt()` / `changesInRange()` / `nextTransition()` /
`prevTransition()` reproduce the committed `.expected.json` gold. Because FFI
cannot run in a browser, the FFI side is frozen ahead of time into those
companions — `tool/generate_bridge_snapshots.dart` records the real
`WellenProvider` (FFI) answers, and `scalar_basics` / `deep_hierarchy` remain
hand-authored Layer-2 gold (audited 0-mismatch). WASM == gold == FFI, so any
divergence pinpoints a marshalling-bridge bug. The manual steps below remain as
a spot-check for releases where the automated job did not run:

- [ ] Open the same VCD on desktop (`WellenProvider`/FFI) and web
  (`WellenWasmProvider`).
- [ ] Walk the cursor through 5–10 representative transitions.
- [ ] Verify the value column matches byte-for-byte across both runtimes.
- [ ] Repeat for one FST and one GHW fixture if available.

### 22.11.5 WebAssembly required error path (all formats)

Now **automated** by
`test/features/viewer/providers/wasm_load_failure_web_test.dart` (run via
`flutter test --platform chrome` / `tool/run_web_widget_tests.sh`): the bare
Chrome widget harness does not inject `web/index.html`'s `wellen_wasm_loader.js`,
so the module-load failure is real, and the test asserts
`WebAssemblyRequiredError` for VCD/FST/GHW plus the guidance UI. Manual
deployment-path spot-check:

- [ ] Temporarily delete `web/wasm/wellen_wasm_bg.wasm`, rebuild
  `flutter build web --release`, redeploy.
- [ ] Open any waveform on web (VCD, FST, or GHW).
- [ ] Expected: no Dart-side fallback; the open path raises
  `WebAssemblyRequiredError`. The waveform canvas centre shows the
  "WebAssembly is required" guidance UI with the message "Please use a
  current version of Chrome, Firefox, Safari, or Edge…" and **no Retry
  button** (retrying without WebAssembly cannot recover).

### 22.11.7 Bundle-size budget

- [ ] Run `flutter build web --release` after a clean
  `dart run tool/build_web_wasm.dart`.
- [ ] Verify `build/web/wasm/wellen_wasm_bg.wasm` exists.
- [ ] Verify `gzip -9c build/web/wasm/wellen_wasm_bg.wasm | wc -c` is
  comfortably under 1.5 MB. (Current build: ~160 KiB gzipped.)
- [ ] CI runs the same gate via `test/native/wellen_wasm_bundle_size_test.dart`.

### 22.11.8 FSDB on web message

- [ ] Attempt to open a `.fsdb` file on web.
- [ ] Expected: the picker rejects the extension (only vcd/fst/ghw are
  allowed). Documentation / website explains that FSDB → FST conversion
  needs the desktop build's `fsdb2vcd` integration.

### 22.11.9 Edge cases

- File > 100 MB on web → memory-budget warning dialog appears before load.
- Drag-and-drop of a non-waveform file → silently rejected with no crash.
- Repeatedly opening/closing the same file → no memory leak (verify via the
  in-app App Diagnostics dialog; WASM linear memory should not grow
  unboundedly across opens).
- Browser navigation reload → WASM module re-initializes cleanly.

### 22.11.10 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| `wellen_wasm` Rust unit tests (format detection, helpers) | `[Coverage: UNIT]` | `cargo test` in `native/wellen_wasm/` — runs in CI's `wasm` job |
| `WellenWasmProvider` stub semantics | `[Coverage: UNIT]` | `test/services/waveform/wellen_wasm_provider_stub_test.dart` |
| Bundle-size regression gate | `[Coverage: STATIC]` | `test/native/wellen_wasm_bundle_size_test.dart` |
| Web file picker accepts vcd/fst/ghw | `[Coverage: UNIT]` | `test/services/waveform/web_file_loader_test.dart` |
| End-to-end Chrome-headless open + valueAt | `[Coverage: INTEGRATION_TEST]` | `integration_test/web/web_cross_bridge_test.dart` loads every committed VCD/FST/GHW fixture through `WellenWasmProvider` and asserts the full query surface against the `.expected.json` gold. Also `integration_test/web/web_file_picker_test.dart` (single-signal smoke). |
| Cross-parser equivalence (FFI desktop vs WASM web) — Layer 1 | `[Coverage: INTEGRATION_TEST]` | `integration_test/web/web_cross_bridge_test.dart`. FFI side frozen into `.expected.json` via `tool/generate_bridge_snapshots.dart`; WASM == gold == FFI. Caught a latent `vector_formats` / `analog_real` gold error when it landed. |
| WebAssembly-required error path (all formats) | `[Coverage: WIDGET]` | `test/features/viewer/providers/wasm_load_failure_web_test.dart` via `flutter test --platform chrome` — real module-load failure (loader absent), asserts `WebAssemblyRequiredError` + guidance UI for VCD/FST/GHW |
| Bundle build correctness | `[Coverage: INTEGRATION_TEST]` | The `integration-web` CI job builds the bundle from source via `dart run tool/build_web_wasm.dart` before driving the suite; `web_file_picker_test` / `web_cross_bridge_test` then confirm `WellenWasmProvider` decodes real fixtures through it |

---

## 22.12 CXP Server + Cross-Probe Panel (Open Core)

WaveCrux speaks two distinct remote-control protocols. **WCP** (Waveform
Control Protocol, §8.3 / port 54321 by default) is the *external driver*
protocol — third-party scripts and IDEs imperatively drive the viewer.
**CXP** (Cross-Tool eXchange Protocol, this section / port 54322 by default)
is the *peer cross-probe* protocol — Crux apps (and any third-party CXP
peer) gossip selection events between each other and negotiate
highlight / open-source requests. The two coexist on different ports
with disjoint command surfaces. The CXP specification is published at
[edacrux.app/cxp](https://edacrux.app/cxp).

### Setup

* Build flavour: open-core (CXP is open-core; no Pro overlay needed).
* Platforms: desktop only — Settings → Remote Control's CXP block is
  rendered on macOS, Linux, and Windows; the lifecycle bridge that
  starts the server at boot is gated on the same hosts.
* Manifest directory: the **suite-shared** location resolved by
  `sharedCxpManifestDirectory()` (crux_cxp) — bundle-independent so every
  Crux product (and dev vs installed builds of the same product) publishes
  into and scans the SAME folder:
  * macOS: `~/Library/Application Support/crux/cxp/peers/`
  * Windows: `%APPDATA%\crux\cxp\peers\`
  * Linux: `${XDG_DATA_HOME:-~/.local/share}/crux/cxp/peers/`

  > **2026-07-18 regression fix (beta W2/S1).** The previous resolution
  > (`getApplicationSupportDirectory()/crux/cxp/peers`) was scoped to each
  > app's own container, so no product ever saw another's manifest and
  > cross-product discovery was structurally impossible. Two further
  > each-sufficient defects were fixed at the same seam: manifests are now
  > **heartbeat-refreshed every 30 s** (previously written once and
  > stale-pruned by peers after 5 minutes), and each product now runs a
  > **peer connector** that dials every discovered manifest (previously
  > nothing ever opened a CXP socket, so `connectedPeers` — which every
  > cross-probe surface gates on — stayed empty forever).

  > **2026-07-20 follow-on fix (connector → server dispatch).**
  > `WaveCruxCxpServer.start()` built its `CxpPeerConnector` without
  > `server:`, so inbound traffic arriving over a **connector-dialed**
  > link was dropped before reaching `_handleInbound`. Because the two
  > sides dial symmetrically, that is the socket every cross-product
  > request, ack, and `notify_selection` actually lands on — so
  > presence looked perfectly healthy (`connectedPeers` populated,
  > peer rows rendered) while no cross-probe action ever worked. When
  > verifying §22.12.2, **do not stop at the peer list**: always drive
  > at least one real cross-probe action end-to-end and confirm the
  > ack, since presence and traffic fail independently here.
* Default port: `54322`. Default `cxpServerEnabled = true` (so CXP is
  a discoverable peer from launch with zero configuration).
* Default `cxpEditorCommand = ''` (open-source path disabled until
  the user enters a shell command — e.g. `code -g`, `subl`,
  `nvr --remote-silent`, `emacsclient -n`).

### 22.12.1 Server lifecycle from Settings

1. Launch a fresh WaveCrux build with no prior manifests in the shared
   directory (`~/Library/Application Support/crux/cxp/peers/` on macOS).
2. Open Settings → Remote Control. Scroll past the WCP block (separated
   by a Divider) to the **CXP Cross-Probe** sub-heading.
3. Verify the **Enable CXP Server** toggle is ON by default and the
   **CXP Status** row reads `Running on port 54322`.
4. Toggle OFF. Status row flips to `Stopped`; the bound manifest file
   at `<shared dir>/wavecrux-<pid>-<startedAt>.json` is removed
   from disk.
5. Toggle back ON. Manifest reappears.
6. Change the **CXP Port** field to `54323` and press Enter. Status
   row updates to `Running on port 54323` after a brief restart; the
   manifest's `port` field reflects the new value.
7. Reset the port to `54322` (default).

**Tier gating:** N/A — CXP is open-core (it's a fundamental ecosystem
feature, like the user-contributed decoder loader; gating it would
suppress cross-product workflows).

### 22.12.2 Peer discovery (manifest watcher + connector)

1. With the CXP server running per §22.12.1, open the **Cross-Probe
   Panel** (command palette → `Show Cross-Probe Panel`).
2. The panel's Peers section shows the **discovery directory** line
   (monospace, under the "Connected Peers" heading) — verify it names the
   shared path from Setup, NOT a per-app container. This line is the
   self-debug surface for "peers aren't appearing": the directory it
   names is the one to inspect.
3. With no other Crux apps running the **Connected Peers** section
   reads `No peers connected`. WaveCrux's OWN manifest is in the scanned
   directory but must never be listed as a peer (self-filter).
4. From a terminal, simulate a peer manifest (shared dir; macOS path shown):
   ```bash
   PEERS="$HOME/Library/Application Support/crux/cxp/peers"
   mkdir -p "$PEERS"
   cat > "$PEERS/othercrux-99-12345.json" <<EOF
   {
     "identity": {
       "peer_id": "othercrux-99-12345",
       "product_name": "othercrux",
       "product_version": "0.1.0",
       "capabilities": []
     },
     "host": "127.0.0.1",
     "port": 0,
     "started_at": $(date +%s)000
   }
   EOF
   ```
5. Within ~3 seconds the panel shows an `othercrux 0.1.0` row. (The
   connector will also try dialing port 0 and fail — harmless; retried
   until the manifest goes away.)
6. Delete the manifest file: the peer row disappears within ~3 seconds.

#### 22.12.2b Real cross-product discovery (the beta W2/S1 flow)

1. Launch WaveCrux **and** a second suite product (SimCrux / NetCrux /
   LintCrux — any build at or past the 2026-07-18 fix; a pre-fix build,
   e.g. WaveCrux Pro ≤ 0.2.7, publishes into its per-app container and
   cannot be discovered) with both CXP servers enabled.
2. Within ~5 seconds each app's cross-probe surface lists the other as a
   **connected** peer (manifest discovered → symmetric connector dials →
   inbound Hello on both servers).
3. Leave both running **> 5 minutes** and re-check: the peer rows must
   persist (manifest heartbeat, 30 s cadence, defeats the 5-minute stale
   prune that previously evicted long-running peers).
4. Quit the second product: its manifest is removed and the peer row
   disappears within ~3 seconds; its outbound connection is torn down.
5. Kill the second product with `kill -9` (crash simulation, manifest
   left behind): the peer row lingers until the stale threshold
   (~5 minutes after its last heartbeat), then is pruned and its
   manifest deleted by the surviving scanner.

#### 22.12.2c Unreachable-peer indicator (one-way connectivity)

A peer whose manifest we discover but whose CXP socket we cannot open is
*one-way connectivity*: it can still show as connected if it dialed us
first, so a healthy-looking peer list hides that our own outbound path to
it is broken. The **Unreachable peers** section makes that visible. It is
a **persistent inline indicator** (not a toast) and stays out of the way
when there is nothing to report.

1. With the CXP server running per §22.12.1 and the Cross-Probe Panel
   open, confirm that with every discovered peer reachable there is **no
   "Unreachable peers" section** — the indicator is silent when empty.
2. From a terminal, write a manifest that points at a port with nothing
   listening (shared dir; macOS path shown):
   ```bash
   PEERS="$HOME/Library/Application Support/crux/cxp/peers"
   mkdir -p "$PEERS"
   cat > "$PEERS/deadcrux-1-2.json" <<EOF
   {
     "identity": {
       "peer_id": "deadcrux-1-2",
       "product_name": "deadcrux",
       "product_version": "0.1.0",
       "capabilities": []
     },
     "host": "127.0.0.1",
     "port": 65533,
     "started_at": $(date +%s)000
   }
   EOF
   ```
3. Within a few seconds an **Unreachable peers** section appears with a
   warning icon and the line **Couldn't reach deadcrux-1-2**, plus a
   `127.0.0.1:65533` host:port line beneath it. It persists (the connector
   keeps retrying with backoff) — it does not flash and vanish.
4. Delete the manifest file: within ~3 seconds discovery stale-prunes the
   peer, the connector drops it, and the row disappears.
5. **One-way case (optional, two apps):** if you can arrange a peer that
   dials WaveCrux but whose own listener WaveCrux cannot reach (e.g. a
   firewall on the peer's bound port), confirm the peer appears in BOTH
   **Connected Peers** and **Unreachable peers** — that dual listing is
   the one-way-connectivity signal this feature exists to surface.

**Tier gating:** N/A — CXP is open-core; the indicator ships to every
tier. **Beta behavior:** identical to post-beta — there is no
`kBetaPeriod` branch here (nothing tier-gated to short-circuit), so the
indicator is live from the first beta build with zero configuration.

**Automation Assessment.**

| Test | Coverage |
|---|---|
| Connector dial failure re-broadcasts on `WaveCruxCxpServer.dialFailures` and lands in `unreachablePeers`; empty once stopped | **UNIT** (`test/services/remote/cxp/wavecrux_cxp_server_test.dart` — "dial failures (unreachable peer)" group) |
| `CxpServerNotifier` pushes connector dial failures into `cxpDialFailuresProvider` | **INTEGRATION_TEST** (`test/services/remote/cxp/cxp_integration_test.dart` — "surfaces connector dial failures into cxpDialFailuresProvider") |
| Panel renders the indicator when the provider has failures and hides it when empty; en/zh_CN/ja/ko locale sweep | **WIDGET** (`test/features/remote/widgets/cross_probe_panel_test.dart` — unreachable-peer indicator + absent-when-empty + locale sweep) |
| Real two-app one-way-connectivity dual listing | **MANUAL** (step 5) |

### 22.12.3 Outbound `notify_selection` emission

Requires a CXP peer connected. Easiest: spawn `LocalCxpClient` from a
small Dart script (see `test/services/remote/cxp/cxp_integration_test.dart`
for the recipe).

1. Connect a test peer and have it `Subscribe` to `notify_selection`.
2. In WaveCrux, click on a signal in the signal list — `selectedSignalProvider`
   updates → peer receives `NotifySelection(elements: [signal:<path>])`.
3. Move the primary cursor — peer receives a debounced (~100 ms)
   broadcast carrying the previous signal selection plus
   `metadata.wavecrux.cursor_time_fs`.
4. Set a named marker (`Cursors → Set Marker A`) — peer receives
   `NotifySelection(elements: [marker:a], metadata: {cursor_time_fs: <tick>})`.

Cross-probe panel's **Recent Events** section shows each broadcast
with an `→` prefix and the selected signal in the summary line.

### 22.12.4 Inbound `request_highlight` reception

From the test peer:

1. Send `RequestHighlight(element: signal:top.cpu.clk)` (assuming
   `top.cpu.clk` exists in the loaded waveform).
2. Peer receives `RequestHighlightAck(honored: true)`.
3. WaveCrux's signal list shows `top.cpu.clk` added (if not already
   present) and the row highlighted.
4. Send `RequestHighlight(element: marker:a)` after Marker A is set
   per §22.12.3 — the primary cursor jumps to the marker's tick time
   and the ack returns `honored: true`.
5. Send `RequestHighlight(element: signal:nosuchpath)` — ack returns
   `honored: false, reason: "element not found: nosuchpath"`.

Cross-probe panel's **Recent Events** section shows each request with
an `←` prefix and the requested path in the summary line.

### 22.12.5 Inbound `request_open_source` dispatch

1. In Settings → Remote Control → CXP, set the editor command to
   `echo` (a benign shell-out that always exits 0).
2. From the test peer, send `RequestOpenSource(filePath: 'rtl/cpu.v', line: 42)`.
3. Peer receives `RequestOpenSourceAck(honored: true)`.
4. Clear the editor command (empty string). Send the same request —
   ack now returns `honored: false, reason: "no editor command configured"`.

### 22.12.6 Tier-gate scenarios

CXP is open-core, so there is no Pro/EDU/Enterprise gate. The
server-running / -stopped state is the only access gate; the cross-probe
panel surfaces an offline banner when the server is stopped.

### 22.12.7 Edge cases

| Scenario | Expected behavior |
|---|---|
| Configured port already in use | `startServer` returns the error string; status row shows `lastError`; toggle stays off |
| Peer disconnects mid-message | Presence event flushes; cross-probe panel's peer row disappears; in-flight ack is dropped silently |
| Malformed inbound envelope | Sender receives `ErrorResponse(code: malformed_envelope)`; CXP server stays up |
| Unknown element kind in `request_highlight` | Ack returns `honored: false, reason: "wavecrux does not handle <kind> elements"`. This now covers **two** cases identically: a kind WaveCrux knows but does not author (`rule`/`test`/`breakpoint`), **and** a kind this build has never heard of at all. `ElementKind` became an **open** wire type in the 2026-07 crux-shared round, so a peer built against a later protocol revision can send a kind not in this build's vocabulary; the ruling is to **ignore it gracefully** (no-op, honored=false, no throw, no crash) rather than guess it is signal-like. The name resolver likewise returns `null` for an unknown kind in both directions. |
| Editor command is just whitespace | Treated as empty; `request_open_source` replies `honored: false` |
| Empty signal path in name resolver | Returns `null`; outbound `notify_selection` is skipped |

### 22.12.8 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| `WaveCruxNameResolver` round-trip (all 4 native kinds + edge cases + unknown-open-kind graceful null) | `[Coverage: UNIT]` | `test/services/remote/cxp/wavecrux_name_resolver_test.dart` (incl. the "unknown element kinds (open wire type)" group) |
| `WaveCruxCxpServer` lifecycle + handshake + inbound dispatch + discovery | `[Coverage: UNIT]` | `test/services/remote/cxp/wavecrux_cxp_server_test.dart` (16 cases) |
| `dispatchCxpHighlight` / `dispatchCxpOpenSource` (every ElementKind branch + an unknown open-type kind ignored gracefully) | `[Coverage: UNIT]` | `test/services/remote/cxp/cxp_inbound_handlers_test.dart` (incl. "a kind this build has never heard of is ignored gracefully") |
| `CxpSelectionEmitter` (signal / cursor-debounce / marker / dispose paths) | `[Coverage: UNIT]` | `test/services/remote/cxp/cxp_selection_emitter_test.dart` (6 cases — uses a real `LocalCxpClient` peer for end-to-end wire validation) |
| End-to-end integration through the real Riverpod providers | `[Coverage: INTEGRATION_TEST]` | `test/services/remote/cxp/cxp_integration_test.dart` (5 cases — RequestHighlight changes viewer state, RequestOpenSource invokes editor runner, NotifySelection reaches subscribed peer, event log records both directions) |
| Cross-probe panel widget (empty state, offline banner, peer rows, event rows, clear, locale sweep) | `[Coverage: UNIT]` | `test/features/remote/widgets/cross_probe_panel_test.dart` (6 cases) |
| Settings → CXP block renders (toggle + port + editor command + status) | `[Coverage: UNIT]` | `test/features/settings/screens/settings_screen_test.dart` (2 new CXP-specific cases) |
| Conformance against the wire protocol | `[Coverage: UNIT]` | `crux-shared/packages/crux_cxp/test/conformance/` — `LocalCxpServer` (which WaveCruxCxpServer wraps) is exercised against the v1.0 protocol spec at the package level |
| Shared manifest directory is bundle-independent + per-platform paths + heartbeat defeats stale-prune + two in-process servers mutually discover AND connect | `[Coverage: UNIT]` | `crux-shared/packages/crux_cxp/test/conformance/peer_connectivity_test.dart` (beta W2/S1 regression suite) |
| Two `WaveCruxCxpServer`s sharing one manifest dir end up mutually CONNECTED; `discoveredPeers` excludes self | `[Coverage: UNIT]` | `test/services/remote/cxp/wavecrux_cxp_server_test.dart` ("peer connector (symmetric connect regression)" + discovery group) |
| Inbound `request_highlight` over a **connector-dialed** link reaches the peer's WaveCrux handler and its ack routes back (presence alone is not sufficient) | `[Coverage: UNIT]` | `test/services/remote/cxp/wavecrux_cxp_server_test.dart` ("peer connector" group, e2e product-traffic case) |
| Real two-app cross-product discovery, >5-minute persistence, crash-manifest prune (§22.12.2b) | `[Coverage: MANUAL]` | Needs two separately-installed suite apps; not drivable in-process |

---

## 22.13 LXT / LXT2 Legacy Format Support (Open Core)

### What it does

WaveCrux has **read** support for GTKWave's legacy `.lxt` (2003 streaming) and `.lxt2` (2005 block-indexed) capture formats. The strategy is **convert-on-open, not native parsing**: a magic-byte probe at file-open time routes legacy files through the clean-room `lxt2fst` Rust crate, which streams the source into a sibling-of-source (or app-cache fallback) `.fst`. The existing wellen pipeline then opens the resulting FST exactly like any other FST — canvas, decoders, Stage, value queries, export all work unchanged. Once converted, the file lives forever in the FST hot path and subsequent re-opens skip the converter entirely.

The architectural rationale, crate boundary, cache strategy, and rollout sequence live in `docs/ARCHITECTURE.md` §2.2.1. **No Pro overlay changes are required** — this is open-core.

### Platform scope

- **Desktop / mobile:** primary delivery surface. Conversion runs on a background isolate; cache lives at `<source>.fst` next to the legacy file, or `${appCacheDir}/legacy_conversions/<sha256-of-source-path>.fst` when the source directory is read-only.
- **Web:** the same converter is exposed via wasm-bindgen; conversion runs on the main thread, entirely in memory (no Workers: threads would need SharedArrayBuffer and cross-origin-isolation headers the web build does without). `web/wasm/lxt2fst_loader.js` fetches the converter on the first LXT/LXT2 open. There is **no web conversion cache**: every open, including a second drop of the same file, converts again.
- **CLI / drag-drop / share-sheet:** all four file-entry paths reuse the same `WaveformSourceNotifier` plumbing — none requires special-casing.

### Setup

1. **Fixtures.** Committed under `test/fixtures/legacy/`. Each fixture has a source `.vcd`, one or more `.lxt`/`.lxt2` conversions, and a `.expected.json` wellen-loaded ground truth. The verification suite shares these fixtures with the unit-test tree — copies are not duplicated. The `~50 MB` `large_sample` capture is not committed; regenerate it locally with `dart run tool/regenerate_legacy_fixtures.dart --large`, which writes to `build/legacy_perf/`.
2. **Build.** No extra steps on desktop or Android: `native/wellen_ffi` links the `lxt2fst` crate, so the `libwellen_ffi` each platform build already compiles and bundles carries the converter (confirm with `nm -gU <app>/Contents/Frameworks/libwellen_ffi.dylib | grep lxt2fst` on macOS). iOS uses the committed `WellenFFI.xcframework`; rerun `scripts/build_ios.sh` after changing the crate. The web build uses the committed `web/wasm/lxt2fst_bg.wasm`; rerun `dart run tool/build_lxt2fst_wasm.dart` after changing the crate. CI rebuilds it in the `wasm` job.
3. **Settings.** Confirm `AppSettings.suppressLegacyFormatBanner` is `false` for the first-open banner checks (Settings → Advanced → Reset Banners, or fresh user-data directory).

### 22.13.1 Happy-path open: small LXT2 file (hierarchy + values render)

- [ ] Launch a debug build with a fresh user-data directory.
- [ ] **File → Open…** → `test/fixtures/legacy/simple_counter.lxt2`.
- [ ] Expected: a brief progress dialog *may* flash (debounced — small files convert in well under 250 ms and should skip the dialog entirely).
- [ ] The signal tree populates with the `top` scope containing the 8-bit counter and toggling clock from the source VCD.
- [ ] Drag the two signals onto the canvas; the values match `test/fixtures/legacy/simple_counter.expected.json` at the cross-checked timestamps.
- [ ] The Diagnostics → File Info "Original format" row reads `LXT2 (converted to FST on <today>)` (`diagnosticsFileInfoOriginalFormatValue` ARB key).
- [ ] A sibling `simple_counter.fst` now lives next to `simple_counter.lxt2`, plus a `.lxt2cache.json` sidecar with `sourceSize` matching the `.lxt2` byte length.

### 22.13.2 Cache hit on second open is instant (no progress dialog, no converter run)

- [ ] After §22.13.1, **File → Close**.
- [ ] **File → Open…** → the same `simple_counter.lxt2`.
- [ ] Expected: no progress dialog appears at any duration. The signal tree and canvas restore essentially instantly (faster than wall-clock perception of a "loading" pause — the file is now an FST cache hit).
- [ ] The legacy banner does **not** appear on the second open (cache hit suppresses the banner regardless of `suppressLegacyFormatBanner`).
- [ ] The Diagnostics → File Info "Original format" row still reads the LXT2 origin.

### 22.13.3 App-cache fallback for read-only source directory

- [ ] Copy `simple_counter.lxt2` into a read-only directory (e.g. `chmod 555` a temp dir on Linux/macOS, or open from a read-only network share on Windows).
- [ ] **File → Open…** the copy.
- [ ] Expected: conversion succeeds. No sibling `.fst` is created next to the source (the directory is unwritable).
- [ ] Confirm the cache landed at `${appCacheDir}/legacy_conversions/<sha256>.fst` plus the matching `.lxt2cache.json` sidecar. On macOS this is under `~/Library/Caches/com.wavecrux.wavecrux/legacy_conversions/`; on Linux under `~/.cache/com.wavecrux.wavecrux/legacy_conversions/`; on Windows under `%LOCALAPPDATA%\com.wavecrux\wavecrux\legacy_conversions\`.
- [ ] Re-open the same file. Cache hit: no progress dialog, instant load, banner suppressed.

### 22.13.4 Large-file progress dialog (moving bar)

- [ ] `dart run tool/regenerate_legacy_fixtures.dart --large` (writes a true ~50 MB capture under `build/legacy_perf/large_sample.lxt2` — uncommitted).
- [ ] **File → Open…** → `build/legacy_perf/large_sample.lxt2`.
- [ ] Expected: within 250 ms a modal progress dialog appears with title "Converting legacy waveform file" (`lxt2ConversionTitle`), status text "Converting LXT2 → FST…" (`lxt2ConversionStatus`), and filename row "File: large_sample.lxt2" (`lxt2ConversionFile`).
- [ ] The determinate progress bar moves monotonically from left to right driven by the `(blocks_done, total_blocks)` callback. Update cadence is throttled to 50 ms / 1 % — the bar should not feel choppy.
- [ ] After conversion completes the dialog dismisses and the canvas renders the four cross-checked `top.bench` probe signals from the source. (The `top.bench.bulk.*` filler signals are intentionally not in the `.expected.json`.)

### 22.13.5 Cancel mid-conversion (no leftover files)

- [ ] Repeat the open from §22.13.4 against a freshly-deleted cache: `rm -f build/legacy_perf/large_sample.fst build/legacy_perf/large_sample.lxt2cache.json`.
- [ ] When the progress bar is partway across, press **Cancel** (`lxt2ConversionCancel`).
- [ ] Expected: the dialog dismisses, the converter terminates, and no `large_sample.fst` or `.lxt2cache.json` exists in `build/legacy_perf/`. The viewer returns to the empty-canvas state (or the previous tab, if any).
- [ ] A subsequent **File → Open…** of the same file starts a fresh conversion — no stale partial cache is reused.

### 22.13.6 Legacy banner: first-open visibility + Don't-show-again

- [ ] Reset `AppSettings.suppressLegacyFormatBanner = false` (Settings → Advanced, or fresh user-data dir).
- [ ] Delete the sibling cache (`rm simple_counter.fst simple_counter.lxt2cache.json` next to the fixture) so the next open is a fresh conversion, not a cache hit.
- [ ] **File → Open…** → `simple_counter.lxt2`.
- [ ] Expected: above the waveform area a non-modal `MaterialBanner` appears reading "Opened from legacy LXT2 format. Converted to FST and cached at `<absolute path>`." (`legacyFormatBannerMessage`) with two actions: "Don't show again" (`legacyFormatBannerDontShowAgain`) and "Dismiss" (`legacyFormatBannerDismiss`).
- [ ] Tap **Dismiss**. The banner closes but `suppressLegacyFormatBanner` remains `false`.
- [ ] Close the tab, delete the sibling cache again, reopen — the banner returns (first-open of a fresh conversion).
- [ ] This time tap **Don't show again**. The banner closes; `suppressLegacyFormatBanner` flips to `true`.
- [ ] Close the tab, delete the sibling cache, reopen — the banner does **not** appear despite the fresh conversion. Diagnostics → File Info "Original format" row still shows the LXT2 origin (the row is independent of the banner setting).

### 22.13.7 Diagnostics → File Info "Original format" row

- [ ] Open `simple_counter.lxt2` per §22.13.1.
- [ ] Open **Diagnostics → File Info** (per-tab drawer).
- [ ] Confirm the **Format** row reads `FST` (what wellen is actually parsing) and a row immediately below labelled **Original Format** (`diagnosticsFileInfoOriginalFormat`) reads `LXT2 (converted to FST on <today>)` — formatted by `diagnosticsFileInfoOriginalFormatValue` with the conversion date in the user's locale.
- [ ] Open a non-legacy file (e.g. any `test/fixtures/vcd/*.vcd`): the **Original Format** row is hidden entirely.
- [ ] Open a different legacy fixture (`multi_scope.lxt2`): row shows the LXT2 origin with the conversion date of that file.

### 22.13.8 Locale sweep on the dialog and banner

Verify the legacy-file UX renders cleanly across all four shipped locales. Use the locale switcher in Settings → Appearance.

For each of `en`, `zh_CN`, `ja`, `ko`:

- [ ] Delete the sibling cache to force a fresh conversion.
- [ ] **Conversion dialog:** open `build/legacy_perf/large_sample.lxt2`. While the dialog is visible, confirm: the title, status, and filename rows render the localized strings (`lxt2ConversionTitle`, `lxt2ConversionStatus`, `lxt2ConversionFile`); CJK characters render with the bundled fallback font and do not show ▯ tofu; the dialog does not overflow the modal frame at 1280×720; the Cancel button is fully readable.
- [ ] **Banner:** allow the conversion to finish. Confirm the banner reads the localized `legacyFormatBannerMessage` with both placeholder interpolations (`{format}` → `LXT2`, `{path}` → the cache absolute path); the **Don't show again** and **Dismiss** actions render localized; the banner row scrolls horizontally if the cache path is longer than the viewport (banner inherits the same `SingleChildScrollView` chrome rule as the toolbar — no `RenderFlex overflowed` exception).
- [ ] **Original Format row:** confirm `diagnosticsFileInfoOriginalFormat` and `diagnosticsFileInfoOriginalFormatValue` render the localized strings under each locale.

### 22.13.9 LXT classic — full open (hierarchy + real per-facility values render)

**Both legacy codecs now decode full per-facility values.** LXT2 (see §22.13.1) and **LXT-classic** alike convert to FST with their real transitions — scalars, bit-vectors with x/z, and reals round-trip exactly. The LXT-classic reader decodes the trailing gzip dictionary sections (NAMES, GEOMETRY, per-facility chain-head table, index), the timescale + max-time, **and** the inline *streaming* value-change records (a separate format from LXT2's block/granule codec) via `lxt_value_decode`: the `[op][facref][value]` record framing, multi-byte back-pointers, the chain-head table that resolves facility identity, the binary + 4-state operator alphabet, little-endian f64 reals, and the per-timestep time index. The decoder was reverse-engineered differentially against GTKWave's `vcd2lxt` encoder (`tool/lxt_classic_value_fuzz.py`) and is **strict** — any unvalidated structure falls back to a bounded `x`-state emission rather than a guessed value, so a converted `.lxt` is never silently wrong and always opens cleanly.

- [ ] **File → Open…** → `test/fixtures/legacy/simple_counter.lxt`.
- [ ] Expected: the open path detects the LXT magic, hands the file to `lxt2fst_convert`, and conversion succeeds — no crash, no half-state, no `Unsupported` error.
- [ ] The signal tree populates with the `top` scope containing the 8-bit `count` and the scalar `clk` from the source VCD (names + geometry are fully decoded).
- [ ] Drag `clk` and `count` onto the canvas: `clk` toggles 0/1 every 10 ns and `count` increments `0x00..0x31` over t=0..490 — identical to the `simple_counter.lxt2` waveform (both derive from the same source VCD / `simple_counter.expected.json`).
- [ ] The Diagnostics → File Info "Original format" row reads `LXT (converted to FST on <today>)` — the LXT-classic origin, distinct from the LXT2 label.
- [ ] A sibling `simple_counter.fst` + `.lxt2cache.json` sidecar appear next to the source (the sidecar suffix is the shared `Lxt2FstCache.sidecarSuffix`, used for both legacy formats), exactly like the LXT2 cache flow (§22.13.1–§22.13.3 apply to `.lxt` too).

### 22.13.10 Edge cases

- **Truncated `.lxt2`:** copy `simple_counter.lxt2` and truncate it with `dd bs=1 count=64`. Open path surfaces a clean error, no crash, no partial cache left behind.
- **Magic mismatch (renamed FST):** rename a real `.fst` to `.lxt2` and open. The magic probe falls through to wellen, which opens it as the FST it actually is. No spurious conversion attempt.
- **Cache present but `.lxt2cache.json` missing:** delete only the sidecar (`rm simple_counter.lxt2cache.json`, leave the `.fst` in place). Next open treats the cache as stale (size unknown), reconverts, and rewrites the sidecar.
- **Source touched after caching:** `touch simple_counter.lxt2` after a successful conversion. Next open detects `source_mtime > fst_mtime` and reconverts.
- **Source copied with same mtime but different size:** simulated via a regenerated fixture overwriting the original. Next open detects size mismatch via the sidecar and reconverts.
- **Web has no cache:** opening from drag-drop on web bypasses the filesystem cache entirely and nothing replaces it. Confirm a second drag-drop of the same file converts again (the progress dialog may flash for a large file) and opens identically, and that no `.fst` download or storage prompt appears.

### 22.13.11 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| `lxt2fst` Rust unit tests (LXT2 header/block-prefix parse + value-codec helpers in `value_decode.rs`; LXT-classic gzip-section enumeration, name/geometry/timescale decode + value-codec helpers in `lxt_value_decode.rs`; magic detection, error variants) | `[Coverage: UNIT]` | `cd native/lxt2fst && cargo test` — runs in CI alongside `wellen_ffi` / `wellen_wasm`. Includes `value_decode::tests::*`, `lxt_value_decode::tests::*`, `lxt::tests::*`, and the `round_trip::*_value_equivalence` + `*_structural_round_trip` tests |
| `lxt2fst` web conversion (loader shim → in-memory wasm conversion → wellen-WASM, values vs `.expected.json`; drop-zone open in the app) | `[Coverage: INTEGRATION]` | `integration_test/web/web_legacy_lxt_open_test.dart` via `tool/run_web_integration_tests.sh` (CI: `integration-web.yml`, which rebuilds the lxt2fst wasm first). `round_trip::convert_bytes_matches_path_conversion_for_every_fixture` proves the in-memory path is byte-identical to the file path |
| Bundle-size regression (gzipped ≤ 400 KiB) | `[Coverage: STATIC]` | `test/native/lxt2fst_wasm_bundle_size_test.dart` |
| `LegacyFormatDetector` magic-byte classification | `[Coverage: UNIT]` | `test/services/waveform/legacy_format_detector_test.dart` |
| `Lxt2FstCache.resolve` sibling-vs-fallback + freshness (mtime + size) | `[Coverage: UNIT]` | `test/services/waveform/lxt2fst_cache_test.dart` (covers writable sibling, read-only sibling → fallback, stale-by-mtime, stale-by-size, missing sidecar) |
| `LegacyConversionController` state machine (debounce, cancel, error, progress) | `[Coverage: UNIT]` | `test/services/waveform/legacy_conversion_controller_test.dart` |
| Bridge equivalence (legacy fixture → `lxt2fst` → wellen returns expected hierarchy + values per `.expected.json`) | `[Coverage: UNIT]` | `test/services/waveform/lxt2fst_bridge_equivalence_test.dart` — both `.lxt2` and `.lxt` paths assert full `valueAt` equivalence (bit-vectors with x/z + reals, numeric tolerance for reals) |
| `WaveformSourceNotifier` routes LXT2 through convert-on-open and records `originalFormat` | `[Coverage: UNIT]` | `test/features/viewer/providers/waveform_source_provider_lxt2_test.dart` |
| Banner appears on first open, suppressed by setting, suppressed on cache hit (incl. locale sweep) | `[Coverage: UNIT]` | `test/widgets/legacy_format_banner_test.dart` |
| Progress dialog: debounce, status text, cancel button, locale sweep | `[Coverage: UNIT]` | `test/widgets/legacy_conversion_progress_dialog_test.dart` |
| File Info "Original format" row visibility + value formatting | `[Coverage: UNIT]` | `test/features/diagnostics/widgets/file_info_panel_test.dart` (Original Format row group) |
| Round-trip value fidelity (VCD → LXT2 via `vcd2lxt2` → FST via `lxt2fst` → values match VCD) | `[Coverage: UNIT]` | `native/lxt2fst/tests/round_trip.rs` — `simple_counter`/`multi_scope`/`vector_signals` `*_value_equivalence` tests assert exact transitions (clk/count, 16/32-bit vectors, x/z, reals) via wellen. Continuously cross-checked against GTKWave's `vcd2lxt2` encoder by the differential fuzzer `tool/lxt2_value_fuzz.py` (thousands of randomized inputs; hard invariant: never a wrong value) |
| Round-trip value fidelity — LXT classic (VCD → LXT via `vcd2lxt` → FST → values match VCD) | `[Coverage: UNIT]` | `native/lxt2fst/tests/round_trip.rs` — `lxt_classic_value_equivalence_post_decoder` asserts exact `clk`/`count` transitions via wellen (same ground truth as the LXT2 path). Continuously cross-checked against GTKWave's `vcd2lxt` encoder by the differential fuzzer `tool/lxt_classic_value_fuzz.py` (thousands of randomized inputs — every width, x/z, reals, multi-facility, ≥256-byte back-pointers; hard invariant: never a wrong value) |
| End-to-end open through the UI (file picker → progress dialog → canvas renders) | `[Coverage: MANUAL]` | This guide — UI feel + cache fallback are best verified on the host platform. Hybrid candidate when integration_test gains a stable file-picker shim. |
| Cancel mid-conversion leaves no partial files | `[Coverage: UNIT]` | `legacy_conversion_controller_test.dart` (cancel path asserts the converter's `onCancel` is called and the output path is unlinked) |

---

## 22.14 Translator Registry + Structured TranslationResult (Open Core)

### What it does

The translator registry replaces the flat `ValueFormatService.format() → String` value-rendering seam with a **registry of translators** that return a structured `TranslationResult` (primary `text` + optional named `fields` + a `validity` hint + an optional `colorArgb` color hint). It is a **foundational refactor with no user-visible change**: every `DisplayFormat` renders byte-for-byte identically before and after, because the built-in translator (`builtin.valueFormat`) is a thin adapter over the unchanged `ValueFormatService`.

The value of this stage is the **extension point**, not new on-screen behavior:

- `Translator` interface + `TranslationRequest` value object in `lib/domain/interfaces/translator.dart`.
- `TranslationResult` / `TranslatedField` models + `ValueValidity` enum in `lib/domain/{models,enums}/`. Domain layer stays Flutter-free, so color is carried as `int? colorArgb` (ARGB), not `dart:ui Color`.
- `TranslatorRegistry` (mirrors `DecoderRegistry`) in `lib/plugins/translator_registry.dart`, seeded with the built-in translator, plus an `@riverpod translatorRegistryProvider` built from the built-in set **plus** an overridable `extraTranslatorsProvider`.
- All five value-render call sites (`vector_signal_painter`, `value_column_provider` ×2, `bus_readout_stage_widget`, `rtl_source_panel`) route through the registry and read `result.text`.

The structured `fields` / child-row UI and the declarative translator authoring format land in **Stage 1**; the curated Pro pack registers through `extraTranslatorsProvider` in **Stage 2**. This entry covers only the Stage-0 seam.


### Platform scope

Pure Dart — identical on desktop, mobile, and the web (WASM) build. No native code, no new assets, no new ARB strings.

### Setup

No fixtures or special build steps. The seam is exercised by every value the viewer already renders.

### 22.14.1 No-visible-change regression sweep

- [ ] Open any multi-format file (e.g. `test/fixtures/vcd/*.vcd` with a mix of buses and scalars).
- [ ] For a bus signal, cycle its display format through **every** entry of the format picker (Binary, Hex, Octal, Unsigned/Signed Decimal, ASCII, IEEE-754 single/double, Fixed-point Q, Sign-magnitude, Gray, Named-enum).
- [ ] Expected: the value-column readout, the in-lane bus label on the canvas, and (where applicable) the RTL-source hover value all render **exactly** what they rendered before the translator registry — same digits, same `X` / `Z` indeterminate markers, same enum labels. There is no new chrome, no child-row expander, no color change.
- [ ] Confirm x/z values still show `X` / `Z` (hex/oct show lowercase `x`/`z` per the existing rules); reals pass through unchanged.

### 22.14.2 Stage bus-readout parity

- [ ] Add a **Bus Readout** Stage widget bound to a vector signal.
- [ ] Scrub the cursor; the large numeric readout shows the same prefixed value (`0x…` / `0b…` / `0o…`) and the same red `X` / `Z` error styling as before the refactor.

### 22.14.3 Extension-point sanity (developer check)

- [ ] In a `ProviderContainer`, read `translatorRegistryProvider` with no overrides → `resolve()` returns the built-in translator (`builtin.valueFormat`).
- [ ] Override `extraTranslatorsProvider` with a stub translator → the registry now resolves that id, and a stub registered under `builtin.valueFormat` **wins** over the seeded built-in (last-write-wins). This is the seam Stage 2 / the Pro pack uses; verifying it here guarantees Pro translators have a way in.

### 22.14.4 Edge cases

- **Empty raw value** — passes through verbatim (no exception).
- **Real/analog values** (`3.14`, `-1.5e-3`, VCD `r`-prefixed) — `validity` is `ok`, `text` is the unchanged float rendering.
- **Narrow (1-bit) and wide (64-bit) buses** — byte-identical to the legacy formatter across all formats.
- **`fixedPointQ` / `namedEnum` config** — the per-signal `translatorConfig` map is forwarded through `TranslationRequest.config`; missing/invalid config falls back exactly as `ValueFormatService` already did.

### 22.14.5 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| `TranslationResult` / `TranslatedField` model round-trips (equality, copyWith, defaults, deep field equality) | `[Coverage: UNIT]` | `test/domain/models/translation_result_test.dart`, `test/domain/models/translated_field_test.dart` |
| `TranslationRequest` equality (incl. config map) | `[Coverage: UNIT]` | `test/domain/interfaces/translator_test.dart` |
| Built-in translator: text delegates to `ValueFormatService`; `validity` from x/z; no fields | `[Coverage: UNIT]` | `test/services/value_format/builtin_value_translator_test.dart` |
| Registry: built-in resolves; `extraTranslatorsProvider` override adds + wins; resolve fallback; unregister | `[Coverage: UNIT]` | `test/plugins/translator_registry_test.dart` |
| **Call-site parity** — every `DisplayFormat` × representative value matrix (incl. x/z, real, narrow/wide, Q-format, enum) renders `registry.translate(...).text == ValueFormatService().format(...)` byte-for-byte | `[Coverage: UNIT]` | `test/plugins/translator_registry_test.dart` (parity group) — the regression guarantee for "no visible change" |
| Migrated call-site tests stay green (painter, value column, bus readout, RTL source) | `[Coverage: UNIT]` | existing tests under `test/features/**`, unchanged behavior |
| On-screen "looks identical" sweep across formats and the Stage readout | `[Coverage: MANUAL]` | This guide §22.14.1–.2 — pixel-level human confirmation; the parity unit test is the strong automated backstop |

---

## 22.15 Declarative Struct/Bitfield Translators + Child-Row UI (Open Core)

### What it does

Stage 1 delivers the **user-extensible declarative translator tier** on top of the Stage-0 registry:

- A **bit-field/struct translator** (`builtin.bitfield`) that decomposes a bus value into named subfields. Each subfield is an MSB-indexed slice `[hiBit:loBit]` formatted with any built-in `DisplayFormat` (including a per-field enum table, or a nested struct for struct-in-struct). The value column shows a compact summary (`{valid=1, len=08, addr=81}`) and, when expanded, one **child row per subfield** aligned under the parent signal.
- A **RISC-V instruction-disassembly translator** (`builtin.riscvDisasm`) that wraps the existing open-core RISC-V disassembler and renders an instruction-bus signal inline as `addi t0, t1, 10` with mnemonic + operand fields. **Open Core, never Pro-gated** — no tier badge, no feature gate.
- A **Settings → Custom Translators** panel to author/edit/delete named bit-field translators, and a value-column context-menu **"Custom translator…"** entry to bind one (or RISC-V) to a signal. The binding is stored in the per-signal `translatorConfig` map, so it persists in the `.wavecrux` session.

Child-row geometry reuses the **shared lane-geometry source of truth** (§17.18) (`LaneGeometry.heightForEntry` + `signalChildRowCounts`): the value column renders the child rows while the canvas and signal-names list reserve the identical vertical span, so subfields never drift from their wave. The field *count* is static (declared in the config), independent of the cursor value, which is what makes geometry reservation possible.

Pure Dart — runs identically on desktop, mobile, and the web (WASM) build. No native code.


### Platform scope

All platforms incl. web. Adds ARB strings (en/zh_CN/zh/ja/ko). No new fixtures or assets — the RISC-V translator reuses the bundled `assets/decoders/isa/riscv/*.toml` corpus.

### Setup

Open any file with a wide bus signal (e.g. a 16- or 32-bit bus). For RISC-V, open a trace with a 32-bit instruction-fetch bus.

### 22.15.1 Authoring a declarative translator

- [ ] Open **Settings → Custom Translators**. The panel shows the empty state and an **Add Translator** button.
- [ ] Add a translator (e.g. name `AXI ARSIZE`). Add fields with name + high/low bit + per-field format. For a `Named enum` field, the **enum table** sub-editor opens.
- [ ] Save. The translator appears in the list with its field count.
- [ ] Edit it (pre-filled), rename it (the old name is replaced), delete it.

### 22.15.2 Binding + child-row display

- [ ] Right-click a bus signal's value-column cell → **Custom translator…** → pick the authored translator. The value column now shows the compact `{field=value, …}` summary.
- [ ] An **expand chevron** appears on the value row. Tap it: the row expands into one aligned **child row per subfield** (`name  value`). The canvas wave for the parent signal and the signal-names row stay vertically aligned with the value column — the next signal down does **not** drift.
- [ ] **Lower signals stay visible on expand (issue #43).** With at least one signal positioned **below** the expanded one, tap the chevron. The signals below must **not** disappear from the waveform canvas. The blank child-row space reserved after the expanded signal extends the canvas's scrollable content height, so the lower lanes are pushed down and remain painted (previously the canvas `SizedBox` summed only lane heights, omitting the reserved space, and clipped everything below the expanded signal). Confirm the same when the expanded signal is the **last** row and when it's the last child **inside a group** (everything after the group must not drift up), and that **transaction/decoder lanes** stack *below* the reserved space, not on top of it.
- [ ] Collapse: the chevron toggles back; child rows disappear and alignment is restored.
- [ ] Expansion survives scrolling and orientation changes (state lives in `expandedTranslatorRowsProvider`).
- [ ] Touch: the expand affordance hit target is ≥ 44 × 44 dp.
- [ ] **Persistence:** save the session, reopen it — the binding is restored (the signal still decomposes).
- [ ] **Clear reverts format too (issue #41).** Add the same bus signal to the viewer twice. On the second row, change the **Display Format** to a non-default value (e.g. **IEEE 754 Single**), *then* bind a custom translator. Right-click → **Clear custom translator**. The value reverts all the way to the default hex (matching the first row) — it must **not** keep showing a "translated-looking" value (e.g. a float) from the now-stale format. Clearing resets both the binding **and** the row's display format. The other row is unaffected.

### 22.15.3 RISC-V instruction disassembly

- [ ] Bind a 32-bit instruction-bus signal via **Custom translator… → RISC-V disassembly**.
- [ ] The value column renders the disassembled instruction inline (`addi t0, t1, 10`, `add a0, a1, a2`, a compressed `c.*`, …). Mnemonic + operands are exposed as result fields but render **inline only** — RISC-V reserves no static child rows (operand count varies per opcode), so the value row shows **no expand chevron**.
- [ ] No PRO/ENT badge anywhere — this is Open Core.

### 22.15.4 Edge cases

- **Invalid/empty config** — a translator whose field specs are all out of range falls back silently to the flat built-in format (no child rows).
- **Out-of-range field among valid ones** — that field renders `X` but still occupies a child row, so the reserved geometry stays in sync.
- **x/z propagation** — per-field x/z follows the built-in rules; overall `validity` reflects x/z; child rows show `X` colored.
- **Overlapping/duplicate bit ranges** — accepted; each field slices independently (last-writer semantics do not apply — fields are independent views).
- **RISC-V unknown instruction / x bits** — falls back to flat hex.

### 22.15.6 Contributed translator presets (extension-point seam for the Pro pack)

The bind dialog now lists **contributed translator presets** above the RISC-V
entry, drawn from the open-core `extraTranslatorPresetsProvider` seam
(`lib/plugins/extra_translator_presets_provider.dart`, default empty). This is
the discovery surface the curated **Pro** translator pack (in the Pro overlay)
registers through — the *registration* counterpart is
`extraTranslatorsProvider`. Each `TranslatorPreset` carries its own
`requiredTier`; the dialog renders a `WaveCruxFeatureTierBadge` for non-open-core
tiers and gates the tap through the same `betaPeriodProvider`-driven rule the
decoder picker uses (beta short-circuits to allow; post-beta routes an
unsatisfied tier to the upgrade dialog).

- [ ] **Open Core build:** the provider is empty, so the bind dialog shows only
  the RISC-V entry + authored bit-field translators — no preset rows, no
  badges. (Verify on the Open Core verification pass; the Pro pack's own
  presets are verified with the Pro overlay.)
- [ ] Developer check: a unit test contributes a `LicenseTier.pro` preset and
  confirms the badge renders, the beta tap binds, and the post-beta tap (gate
  flipped off) surfaces the upgrade dialog instead of binding.
- [ ] The dialog list scrolls with the mouse wheel, **two-finger trackpad**,
  and click-drag (the dialog wraps its single scroll region in a
  `ScrollConfiguration` adding mouse + trackpad to the drag devices, mirroring
  `DecoderPickerDialog` — the default `ScrollBehavior` omits them).
- [ ] **Generic child-row reservation.** The value-column expand chevron now
  reserves child rows for *any* registered `ChildRowTranslator`, not only
  `builtin.bitfield`: `signalChildRowCounts` resolves the bound translator from
  the registry and asks it for its static count. `ChildRowTranslator` extends
  `Translator` (so a registry `Translator?` promotes); translators that don't
  implement it (the flat formatter, RISC-V disassembly) reserve none and render
  inline. A unit test registers a non-bitfield `ChildRowTranslator` through
  `extraTranslatorsProvider` and asserts the rows are reserved — this is the
  seam the Pro float / pixel translators rely on to expand.
- [ ] **No dead chevron.** The value-column expand chevron is gated on the
  bound translator's *static* child-row capacity
  (`translatorChildRowCount(registry, config) > 0`), not on whether the value
  produced fields. So an inline-only translator (RISC-V disassembly, or any
  `Translator` that is not a `ChildRowTranslator`) shows **no** chevron even
  when it returns fields; bit-field / AMBA / ML-float / pixel bindings show a
  working one. Covered by `value_column_row_translator_test.dart` (inline
  translator → no affordance; `ChildRowTranslator` → affordance present).

### 22.15.5 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| `BitfieldTranslatorConfig` / `BitFieldSpec` fromMap/toMap round-trip, equality, defaults, width/validity | `[Coverage: UNIT]` | `test/domain/models/bitfield_translator_config_test.dart` |
| Contributed-presets seam: open-core default empty; override contributes presets; bind dialog renders badge + gates beta/post-beta both ways | `[Coverage: UNIT]` | `test/plugins/extra_translator_presets_provider_test.dart`, `test/features/viewer/widgets/bind_custom_translator_dialog_test.dart` |
| Generic child-row seam: `signalChildRowCounts` reserves rows for any registered `ChildRowTranslator` (not only `builtin.bitfield`) | `[Coverage: UNIT]` | `test/features/viewer/providers/translator_expansion_provider_test.dart` (fake non-bitfield translator) |
| Expand chevron gated on static child-row capacity: inline-only translator (fields but no `ChildRowTranslator`) → no chevron; `ChildRowTranslator` → chevron present | `[Coverage: UNIT]` | `test/features/viewer/widgets/value_column_row_translator_test.dart` |
| Dialog scrolls via mouse / trackpad / drag | `[Coverage: MANUAL]` | `ScrollConfiguration` mirrors the proven `DecoderPickerDialog` pattern |
| Bitfield decode: simple fields, enum subfield, nested struct, x/z per field, invalid-config fallback, out-of-range field keeps its row | `[Coverage: UNIT]` | `test/services/value_format/bitfield_translator_test.dart` |
| Web/desktop parity (pure-Dart deterministic output) | `[Coverage: UNIT]` | `test/services/value_format/bitfield_translator_test.dart` (parity test) |
| RISC-V disasm translator: RV32I/RV64I + one compressed, operand fields, unknown/x fallback | `[Coverage: UNIT]` | `test/services/value_format/riscv_disasm_translator_test.dart` |
| Expansion-state provider toggle; `signalChildRowCounts` only counts expanded bitfield bindings; geometry inflation | `[Coverage: UNIT]` | `test/features/viewer/providers/translator_expansion_provider_test.dart` |
| Child-row widget rendering + **44×44 touch-target** affordance + collapsed/expanded states + locale sweep | `[Coverage: UNIT]` | `test/features/viewer/widgets/value_column_row_translator_test.dart`, `translator_child_row_test.dart` |
| Custom-translators store (upsert/rename/remove); model round-trip | `[Coverage: UNIT]` | `test/features/settings/providers/custom_translators_provider_test.dart`, `test/domain/models/custom_translator_def_test.dart` |
| Settings panel + editor dialog (list, add, validation, locale sweep) | `[Coverage: UNIT]` | `test/features/settings/widgets/custom_translators_panel_test.dart`, `custom_translator_editor_dialog_test.dart` |
| Bind dialog returns the correct `translatorConfig` marker for RISC-V and custom translators | `[Coverage: UNIT]` | `test/features/viewer/widgets/bind_custom_translator_dialog_test.dart` |
| Clear custom translator resets binding **and** format back to default hex (issue #41); targets only the matching row; nested-in-group; no-op when absent | `[Coverage: UNIT]` | `test/features/viewer/providers/signal_group_providers_test.dart` ("clearSignalTranslatorById") |
| Reserved child-row space extends canvas content height so lower lanes aren't clipped on expand (issue #43) | `[Coverage: WIDGET]` | `test/features/viewer/widgets/waveform_canvas_test.dart` ("issue #43") |
| Registry seeds `builtin.bitfield`; resolves `builtin.riscvDisasm` once assets load | `[Coverage: UNIT]` | `test/plugins/translator_registry_test.dart` |
| On-screen child-row alignment under scroll, and the "subfields never drift from their wave" guarantee across all three columns | `[Coverage: MANUAL]` | This guide §22.15.2 — best confirmed visually; the geometry-inflation unit test is the automated backstop |
| Session persistence of a bound translator across save/reopen | `[Coverage: MANUAL → HYBRID candidate]` | `translatorConfig` round-trips through the existing session JSON; a focused session test is a good follow-up |

---

## 22.16 Beta Issue Reporter (Open Core)

### What it does

A first-party in-app bug-report button (`ShortcutAction.issueReporter`). It collects privacy-scrubbed diagnostic context, lets the user opt out of individual categories, previews the exact GitHub issue body, and opens the pre-filled GitHub new-issue page in the browser. The diagnostic body is **pre-filled into the GitHub URL** when it fits under a ~6 KB length cap (the form opens already populated); for over-sized reports (typically a long Diagnostic Log) the body is omitted from the URL and the user pastes it from the clipboard instead. The body is **always** copied to the clipboard as well, so the paste path is available regardless. On desktop it also saves a Flutter-layer screenshot to the OS temp directory and reveals it in the file manager so the user can drag it onto the issue form. Open to all tiers — no `FeatureTierBadge`, no `FeatureGate`.

### Platform scope

All platforms for the dialog and clipboard/URL flow. The **Screenshot** category is desktop-only (Linux / macOS / Windows) — the tile is hidden on iOS / Android (no drag-attach on the GitHub mobile new-issue form) and on web (no temp-dir reveal).

### Setup

1. Launch the open-core build with a waveform file loaded and at least one decoder bound (so Session State has content).
2. Optional: trigger a benign warning (e.g. attempt to open a malformed file) so the Diagnostic Log category has at least one WARNING line.

### Golden path

1. Open the reporter from **Help menu → Submit Issue**, the command palette (search "Submit Issue"), or the **About box → Report Issue** button. Confirm all three entry points open the same dialog.
2. The dialog shows: a title text field labelled **Issue Summary**; four category tiles — **App & Environment** (locked on, lock icon, switch disabled), **Session State**, **Diagnostics**, **Screenshot** (desktop only) — all defaulting on; a privacy callout; a collapsible **Preview issue body** pane; and Submit / Cancel.
3. Type a summary.
4. Expand the preview. Confirm the body is **scrollable**: a two-finger trackpad vertical drag (not just the mouse wheel) scrolls the dialog body, a Scrollbar is visible when content overflows, and the full expanded preview text is reachable. Toggle **Session State** off, then on; toggle **Diagnostics** off, then on. Confirm the preview updates **live** — the `## Session State` / `## Diagnostics` sections appear and disappear in lock-step with the toggles. The `## App & Environment` section is always present. The `## Diagnostics` section is **never blank** — it always carries the diagnostics report snapshot even on a clean session.
5. Hit **Submit**. Confirm:
   - **The dialog closes** (it must not remain open after the browser launches).
   - The browser opens the GitHub new-issue form with the **title** pre-filled and labels `bug`, `user-report`, and the platform token (`macos` / `linux` / `windows` / `web`). The target repository is the open-core source repo, `https://github.com/Ferrite-Engineering/wavecrux/issues/new`. It is a fixed slug, not keyed off `kBetaPeriod` — the tracker moved at the 1.0 launch, while the gating flag flips on its own schedule.
   - For a typical report, the **issue body is also pre-filled** in the opened GitHub form (well-formed markdown, see below) and a snackbar reads "GitHub issue opened with the diagnostic details pre-filled — drag in the screenshot if one was captured."
   - For an over-sized report (e.g. after a session that logged many errors), the body is **not** in the URL, the snackbar instead reads "GitHub issue opened — paste from the clipboard into the body, then drag in the screenshot," and pasting from the clipboard yields the full body.
   - The body (pre-filled or pasted) is well-formed markdown: `## App & Environment` with version, build SHA, platform, OS, DPI, locale, Flutter/Dart versions; `## Session State` with tab count, active file format, signal count, decoder names; `## Diagnostics` with a fenced ` ```text ` **Full Diagnostics Report** block (platform, app memory, frame stats, active-pane render stats, per-tab file info / signal health) followed by a **Session log** subsection (a fenced block of captured WARNING+/recent log lines, or "(no errors or warnings logged this session)").

### Screenshot path (desktop)

1. Leave **Screenshot** on. Confirm a thumbnail of the live app renders in the dialog.
2. Submit. Confirm a PNG is written to the OS temp directory (`wavecrux-issue-<timestamp>.png`) and the OS file manager opens with that file revealed (Finder on macOS, Explorer on Windows, the containing folder via `xdg-open` on Linux).

### Screenshot-excluded path

1. Toggle **Screenshot** off. The thumbnail disappears.
2. Submit. Confirm no PNG is written and the file manager does **not** open; the clipboard + URL flow still completes.

### Mobile path

1. On iOS / Android, open the reporter. Confirm the **Screenshot** tile is absent and no thumbnail renders. Submit still copies the body and opens the browser.

### Privacy audit

1. Inspect the pasted Session State section. Confirm it contains **no file paths** and **no decoder configuration values** — only counts, the format name, decoder display names (e.g. "AXI4-Full #1"), and (Pro overlay only) signal binding names. This is the issue reporter's privacy contract.

### Diagnostics section verification

- The **Full Diagnostics Report** block is generated by `AppDiagnosticsReportService` — the same text the App Diagnostics dialog's "Copy Full Diagnostics Report" emits (minus live frame-timing, which the reporter doesn't sample, so it shows "(no frames recorded yet)"). Cross-check the memory / per-tab numbers against the App Diagnostics dialog.
- The **Session log** subsection mirrors the in-memory ring buffer (`IssueReporterLogBuffer`, 500 entries, attached in `bootstrap()` before provider construction). The buffer is fed by `package:logging` records **and** by uncaught framework / async errors captured via `captureFlutterErrors()` (`FlutterError.onError` + `PlatformDispatcher.onError`, chained so console reporting is preserved). To verify capture, trigger a benign exception (e.g. a deliberate throw) and confirm a `SEVERE flutter:` line appears in the Session log. On a clean session with no errors logged, the subsection correctly reads "(no errors or warnings logged this session)".

### 22.16.1 Tier-gate scenarios

The Beta Issue Reporter is Open Core and open to all tiers — there is no `FeatureGate` and no tier badge.

- **`kBetaPeriod = true` (beta):** Available to every tier; no badge in the Help menu / palette; no upgrade prompt.
- **`kBetaPeriod = false` (post-beta):** Identical behavior — still available to every tier, still no badge, still no gate. The action's `ActionDescriptor.requiredTier` is `LicenseTier.openCore`, so neither the overflow/palette `WaveCruxFeatureTierBadge` nor the menu-bar `tierLabelSuffix` ever renders.

The Pro overlay's additive "Pro State" category is verified separately in the Pro overlay's guide.

### 22.16.2 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| Ring buffer overflow eviction, `recentEntries` count + `minLevel` filter, chronological ordering, logging-listener capture, `captureFlutterErrors` routing a framework error to a `SEVERE flutter:` entry | `[Coverage: UNIT]` | `test/services/issue_reporter/issue_reporter_log_buffer_test.dart` |
| Markdown body structure (`## <title>` headings, toggled-off exclusion), App/Session category builders, `buildDiagnosticsCategory` (report block + Session log + empty placeholder), fenced-block + timestamp dedup | `[Coverage: UNIT]` | `test/services/issue_reporter/issue_reporter_service_test.dart` |
| Diagnostics report snapshot generation from app/tab providers (the `## Diagnostics` report block) | `[Coverage: MANUAL]` | Built by `AppDiagnosticsReportService.generate`; the issue-reporter wiring degrades to a placeholder on provider-scope failure |
| URL label construction (`bug,user-report,<platform>` + title), clipboard content via injected writer, body pre-fill when short / dropped when over the ~6 KB cap, `bodyPrefilled` reporting | `[Coverage: UNIT]` | `test/services/issue_reporter/issue_reporter_service_test.dart` |
| Submit closes the dialog and shows the pre-filled toast; the **Issue Summary** field label renders | `[Coverage: UNIT]` | `test/features/issue_reporter/widgets/issue_reporter_dialog_test.dart` |
| Two-finger trackpad / touch drag-scroll of the dialog body (`_DragAnywhereScrollBehavior` + pinned Scrollbar) | `[Coverage: MANUAL]` | Pointer-device drag-scroll feel is not asserted headless |
| Privacy: Session State body contains no `/` path separators | `[Coverage: UNIT]` | `test/services/issue_reporter/issue_reporter_service_test.dart` |
| Dialog locale sweep (en/zh_CN/ja/ko) at phone/tablet/desktop widths; tile toggle state; live preview update; Screenshot tile hidden on mobile / present on desktop | `[Coverage: UNIT]` | `test/features/issue_reporter/widgets/issue_reporter_dialog_test.dart` |
| Action wired into descriptor / Help menu / palette with `requiredTier: openCore` (no badge), unbound (no default keystroke) | `[Coverage: UNIT]` | `test/core/shortcuts/action_surface_conformance_test.dart`, `shortcut_bindings_test.dart` |
| Browser actually opens at the GitHub URL; clipboard genuinely populated; screenshot revealed in OS file manager | `[Coverage: MANUAL]` | OS-level integration — the `url_launcher` / `Process.run` reveal cannot be asserted headless |
| Screenshot capture renders the live app (not the dialog) at 2× | `[Coverage: MANUAL → HYBRID candidate]` | Capture happens before the dialog mounts; visual confirmation is manual, a golden is a possible follow-up |

---

## 22.17 Beta build expiry (Open Core)

### What it does

A per-release **hard build-expiry** date so a stale public-beta build stops running and the user is pushed onto the current build. The expiry date is injected per release at build time via `--dart-define=BETA_EXPIRY=<yyyymmdd>` (e.g. `20260901`); absent or `0` means the build never expires. At startup and on app resume the shell reads `betaExpiryStatusProvider` (`crux_license`) and, depending on the status:

- **`expiringSoon`** (within the warning window — default 7 days, overridable via `--dart-define=BETA_EXPIRY_WARNING_DAYS=<n>`) — shows a **dismissible banner** above the viewer: "WaveCrux Beta expires in {days} days. Download the latest build." with an inline **Download** action.
- **`expired`** (on or past the date) — shows a **blocking, non-dismissable modal** over a dimmed viewer with a **Download latest build** button and a **Quit WaveCrux** button; the system back gesture is blocked. The quit action is load-bearing on Windows/Linux: those platforms draw custom window chrome, so the in-app close caption button sits behind the modal barrier and the quit button is the only visible way to exit (macOS's native traffic lights are unaffected; Alt+F4 / Cmd-Q still work everywhere).
- **`active`** / **`notApplicable`** — nothing renders.

This is distinct from `kBetaPeriod`, which governs feature *gating* (tier badges / `FeatureGate`); build expiry governs build *shelf life*. Open to all tiers — no `FeatureTierBadge`, no `FeatureGate`. The mechanism lives in `crux_license` (`beta_expiry.dart` / `beta_expiry_provider.dart`); the UI is `lib/features/beta_expiry/`.

### Platform scope

All platforms. The banner respects `SafeArea` (top) so it clears the notch on mobile; the modal is centered and width-constrained.

### Setup

Beta expiry only applies while `kBetaPeriod == true`. Build with an injected date close to "today" to exercise each path. The check reads the **device clock** — set a near-future or past `BETA_EXPIRY`, or temporarily change the OS clock, to land on a given status without rebuilding.

```bash
# Expires soon (within the 7-day window) — banner. Pick a date 1–7 days out.
flutter run -d macos --dart-define=BETA_EXPIRY=<yyyymmdd_within_7_days>

# Expired — blocking modal. Pick today or any past date.
flutter run -d macos --dart-define=BETA_EXPIRY=<yyyymmdd_today_or_past>

# Active — nothing renders. Pick a date well beyond the warning window.
flutter run -d macos --dart-define=BETA_EXPIRY=20990101

# Never expires (the shipping default for dev builds) — omit the define.
flutter run -d macos
```

### Active path

1. Launch with `BETA_EXPIRY=20990101`. Confirm **no banner and no modal** — the app opens straight to the viewer.
2. Confirm an unconfigured build (no `--dart-define`) behaves identically (never expires).

### Expiring-soon path

1. Launch with a date 1–7 days out. Confirm the **banner** appears at the top of the content area with the correct day count (plural-correct: "1 day" vs "N days") and a **Download** action.
2. Tap **Download**. Confirm the browser opens `https://wavecrux.app/download`.
3. Tap the **✕** close button. Confirm the banner dismisses and the viewer reclaims the space for the session.
4. Suspend and resume the app (or background/foreground on mobile). Confirm the banner **re-surfaces** on resume (the dismissal is per-session and the status is re-evaluated against the latest clock).
5. Confirm the day count crosses correctly: a date exactly 7 days out shows the banner; 8 days out shows nothing.

### Expired path

1. Launch with today's date or a past date. Confirm the **blocking modal** appears over a dimmed viewer: title, body, a **Download latest build** button, and a **Quit WaveCrux** button.
2. Confirm the viewer behind the scrim is **not interactable** (clicks/taps don't reach it).
3. On desktop, confirm the window cannot be dismissed past the modal; on mobile, confirm the **system back gesture** does not close it.
4. Tap **Download latest build**. Confirm the browser opens `https://wavecrux.app/download`.
5. Tap **Quit WaveCrux**. Confirm the app exits immediately. **On Windows and Linux specifically** (custom window chrome), confirm this button is present and works — without it the in-app title-bar close button is blocked behind the modal barrier and the app appears unquittable (the 2026-07-12 Windows-beta defect).
6. Confirm the exact-day boundary: a build whose `BETA_EXPIRY` equals today is expired (not merely expiring).

### `kBetaPeriod = false` no-op path

1. With `kBetaPeriod` flipped to `false` (post-beta build) **and** a past `BETA_EXPIRY` injected, confirm **nothing renders** — `kBetaExpiry` resolves to `null` when `kBetaPeriod` is false, so production builds never expire regardless of the injected date. This is the contract that lets the same expiry plumbing stay compiled-in after the beta without ever firing.

### Edge cases

- **Banner renders above the Navigator (no Overlay ancestor):** like the
  recovery banner (§16.1.7), the expiring-soon strip is a sibling of the routed
  content in `MaterialApp.builder`, so the Navigator's `Overlay` is not an
  ancestor. The banner must use no `Overlay`-dependent widgets — a `Tooltip` on
  the dismiss button threw "No Overlay widget found" the instant an
  expiring-soon launch tried to render it (now a `Semantics` label). Verify the
  banner appears (not a red error screen) when `BETA_EXPIRY` lands inside the
  warning window.

### Tier-gate scenarios

Beta build expiry is Open Core and tier-agnostic — there is no `FeatureGate` and no tier badge.

- **`kBetaPeriod = true` (beta):** Applies to every tier identically; banner/modal render purely on the date, never on tier.
- **`kBetaPeriod = false` (post-beta):** Disabled entirely (`kBetaExpiry == null`); no banner, no modal, for any tier.

### 22.17.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| `yyyymmdd` parsing (valid, `0`/absent, negative, out-of-range month/day, Feb-30 normalization, small year) | `[Coverage: UNIT]` | `crux-shared/packages/crux_license/test/beta_expiry_test.dart` |
| Status boundaries: active / expiringSoon / expired across day-before, exact-day, day-after; custom warning window; `daysUntilBetaExpiry` day math | `[Coverage: UNIT]` | `crux-shared/packages/crux_license/test/beta_expiry_test.dart` |
| `notApplicable` default in an unconfigured build; provider override drives every status / day count | `[Coverage: UNIT]` | `crux-shared/packages/crux_license/test/beta_expiry_provider_test.dart` |
| Banner locale sweep (en/zh_CN/ja/ko); day-count message; Download / Dismiss callbacks; 44×44 dismiss touch target; **renders with no Overlay ancestor (no Tooltip)** | `[Coverage: UNIT]` | `test/features/beta_expiry/widgets/beta_expiry_banner_test.dart` |
| Blocking overlay locale sweep; non-dismissable barrier; `canPop == false`; content rendered behind; Download callback; Quit callback | `[Coverage: UNIT]` | `test/features/beta_expiry/widgets/beta_expiry_blocking_overlay_test.dart` |
| Gate wiring: notApplicable/active → child only; expiringSoon → banner; expired → overlay; dismiss hides banner; download launches `…/download`; quit exits via the `betaExpiryExitApp` seam | `[Coverage: UNIT]` | `test/features/beta_expiry/widgets/beta_expiry_gate_test.dart` |
| Quit actually terminates the process past the custom window chrome (Windows/Linux) | `[Coverage: MANUAL]` | Process exit — not assertable in a widget test; per-release smoke on the expired build |
| Resume re-check actually re-reads the clock and re-surfaces a dismissed banner | `[Coverage: MANUAL → HYBRID candidate]` | Lifecycle-edge invalidation; an integration test driving `AppLifecycleState.resumed` is a possible follow-up |
| Browser actually opens at the download URL | `[Coverage: MANUAL]` | OS-level `url_launcher` — not assertable headless |
| Clock-tampering rollback (setting the clock back can no longer defer expiry) | `[Coverage: UNIT]` + `[Coverage: MANUAL]` | **Hardened** via the update manifest's `server_time` → `crux_license` `trustedBetaExpiryNow` / `observedServerTimeProvider`. Unit: `crux_license/test/beta_expiry_test.dart` (clock-set-back → expired); manual end-to-end in §22.23 (clock-back path) |

---

## 22.18 AI Waveform Assistant — open-core extension-point seams (Open Core)

### What it does

The two open-core sockets the AI Waveform Assistant plugs into. **No model, no analysis logic, no UI** lands with these seams — only the transport interface, the function-calling registry, and a no-op default. The user-visible "Explain Selection" panel, Settings → AI key config, and the Pro agentic Advisor build on them; this entry verifies the seams those build on.

- **`AiModelClient` / `aiModelClientProvider`** — abstracts "send a structured request, stream back text + tool calls" over a bring-your-own-key endpoint. The open-core default `NoopAiModelClient` reports `AiUnavailableReason.notConfigured` as a typed terminal stream event (never throws; `isConfigured == false`). WaveCrux runs no model. The Pro overlay overrides the provider with a concrete multi-provider client.
- **`AiToolRegistry` / `aiToolRegistryProvider`** (+ `extraAiToolsProvider`) — the grounded function-calling surface. Open-core registers six viewer-navigation tools, each reading the live provider graph and returning citations the viewer can jump to: `searchSignal`, `getTransitionsInWindow`, `listDecodedTransactions`, `getSelectionContext`, `jumpCursor`, `addMarker`. The Pro overlay appends analysis tools through `extraAiToolsProvider`.

The trust discipline is **ground everything, hallucinate nothing**: every substantive datum a tool returns carries a stable `(signalRef, time)` coordinate; expected failures (no waveform loaded, unknown signal, unknown tool) are returned as a typed `AiToolResult.failure`, never thrown.

### Platform scope

All platforms (pure-Dart domain + service code; no native dependency). Ships **Experimental** during the public beta — `kAiExperimental` build flag + an off-by-default Settings → AI toggle (both land with the UI prompts, not these seams).

### Setup

No fixture file is required — the seam tests use a hand-crafted in-memory known-answer source (`top.clk`, `top.data`, `top.state` with a deliberate X at tick 5). To exercise the grounded tools interactively once the UI lands, load any VCD/FST (e.g. `protocol/spi/generated/spi_basic.vcd`), add a decoder, and select a few signals.

### Seam behavior (code-level, until the UI lands)

1. **Unconfigured client.** With no override, `aiModelClientProvider` resolves to `NoopAiModelClient`; `isConfigured` is `false` and `send(...)` yields exactly one `AiClientUnavailable(notConfigured)` then completes. No exception is thrown for the missing-key case.
2. **Tool registry contents.** `aiToolRegistryProvider` exposes exactly the six viewer-navigation tools by name; `extraAiToolsProvider` tools are appended; a contributed tool whose name collides with an open-core tool trips the duplicate-name guard at registry construction.
3. **Grounded tools** (against a loaded source):
   - `searchSignal` returns matching signals with stable `signalRef` / path / width.
   - `getTransitionsInWindow` returns the real transitions inside the window; every citation resolves to an actual transition at that tick.
   - `listDecodedTransactions` returns active-decoder transactions, sorted by start time, filterable by decoder id and by overlapping window.
   - `getSelectionContext` emits a compact, **deterministic** structured summary (same selection + window → identical payload) folding in each signal's value-at-start, in-window transitions, overlapping decoded transactions, and an **X-origin trace** when a signal is X (tick 5, previous value `00`). Every citation resolves to a real coordinate.
   - `jumpCursor` moves the primary cursor and cites the resulting tick; `addMarker` places a marker (auto-picking the next free letter a–z) and cites the tick.
4. **No-waveform path.** Each data tool returns `AiToolResult.failure` (typed) when no waveform is loaded — it does not throw and does not fabricate data.

### Tier-gate scenarios

The seams themselves are **Open Core and tier-agnostic** — no `FeatureGate`, no `FeatureTierBadge`. Tier gating lives on the features that consume them (the free "Explain Selection" is `requiredTier: openCore`; the Pro "AI Advisor" is `requiredTier: pro`), verified in the Pro repo's guide when those land.

- **`kBetaPeriod = true` (beta):** seams active for every tier; the no-op client is the default until a Pro client overrides it.
- **`kBetaPeriod = false` (post-beta):** unchanged — the seams are not gated; only the consuming features gate.

### 22.18.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| `NoopAiModelClient` reports unconfigured; `send` yields one typed `notConfigured` event and completes without throwing | `[Coverage: UNIT]` | `test/services/ai/noop_ai_model_client_test.dart` |
| Message/protocol models (roles, tool spec/call, sealed `AiStreamEvent` exhaustive switch, `AiRequest` defaults) | `[Coverage: UNIT]` | `test/domain/interfaces/ai_model_client_test.dart` |
| `AiToolResult` / `AiCoordinate` shape, citation `toMap` omits nulls, ok/failure | `[Coverage: UNIT]` | `test/domain/models/ai/ai_tool_result_test.dart` |
| Registry: name ordering, lookup, duplicate-name guard, unknown-tool → typed failure | `[Coverage: UNIT]` | `test/services/ai/ai_tool_registry_test.dart` |
| Provider defaults: no-op client; six viewer-navigation tools registered; `extraAiToolsProvider` append + collision | `[Coverage: UNIT]` | `test/core/providers/ai_model_client_provider_test.dart`, `test/core/providers/ai_tool_registry_provider_test.dart` |
| Each viewer-navigation tool returns correct grounded data against a loaded source; citations resolve to real coordinates | `[Coverage: UNIT]` | `test/services/ai/tools/viewer_navigation_tools_test.dart` |
| `getSelectionContext` determinism (same inputs → identical payload) + grounded X-origin | `[Coverage: UNIT]` | `test/services/ai/tools/viewer_navigation_tools_test.dart` |
| End-to-end agentic loop and "Explain Selection" panel behavior | `[Coverage: MANUAL → pending]` | Lands with the UI prompts (Settings → AI, panels); verified then |

### 22.18.2 `aiAdvisorPanelTogglerProvider` — Pro AI Advisor panel toggle seam (Open Core)

The third open-core socket the AI Waveform Assistant plugs into: the toggle action for the **Pro agentic AI Advisor** panel. It mirrors `svaPanelTogglerProvider` (§22.5.3) exactly — open-core ships the action and a no-op toggler; the closed-source overlay supplies the body. **No model, no loop, no panel** lands in open-core with this seam.

- **`ShortcutAction.aiAdvisorTogglePanel`** — declared `requiredTier: LicenseTier.pro` (so every action surface renders the PRO badge automatically) and `isVisible: _aiAvailable` (hidden entirely unless experimental AI is enabled via `aiExperimentalEnabledProvider`). Lives in the Tools menu group alongside Explain Selection. No keyboard binding — palette / menu / overflow only.
- **`aiAdvisorPanelTogglerProvider`** — the dispatch extension point. `_handleShortcut` calls `ref.read(aiAdvisorPanelTogglerProvider)(context)`. The open-core default is a no-op; the Pro overlay overrides it with a callback that flips the Advisor panel's visibility provider, routing through `FeatureGate` (upgrade dialog post-beta). The panel mounts through the existing `extraBottomDockTabsProvider` seam (§ bottom-dock contract) — no new bottom-pane branch is forked into the viewer.

#### Tier-gate scenarios

The action is **Pro-tier** at the descriptor level (PRO badge everywhere). The seam (the toggler provider) is tier-agnostic — gating is enforced by the Pro override's `FeatureGate` check, verified in the Pro repo's guide.

- **`kBetaPeriod = true` (beta):** the action is visible (AI enabled) and badged PRO; invoking it toggles the panel (beta short-circuit) for every tier.
- **`kBetaPeriod = false` (post-beta):** the Pro override's `FeatureGate.isAvailable(LicenseTier.pro, …)` governs — unlicensed → upgrade dialog; licensed → toggles. Open-core's no-op default simply does nothing in an Open-Core build (the action stays discoverable, badged PRO).

#### 22.18.2.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| `aiAdvisorTogglePanel` descriptor: Pro tier, menu/overflow/palette surfaces, hidden unless AI enabled, placed in Tools menu | `[Coverage: UNIT]` | `test/core/shortcuts/ai_advisor_action_gating_test.dart` |
| `aiAdvisorPanelTogglerProvider` default is a no-op; overrides replace it | `[Coverage: UNIT]` | `test/core/providers/ai_advisor_panel_toggler_provider_test.dart` |
| Menu/surface conformance (the new action is wired into every declared surface) | `[Coverage: UNIT]` | `test/core/shortcuts/menu_layout_test.dart`, `action_surface_conformance_test.dart` |
| End-to-end panel toggle + FeatureGate upgrade dialog | `[Coverage: MANUAL → Pro repo]` | The Pro override + panel live in the Pro overlay; verified in its guide. |

---

## 22.19 AI Waveform Assistant — Settings → AI config + Experimental gate (Open Core)

### What it does

The open-core, bring-your-own-key configuration surface for the AI assistant, plus the two-layer Experimental gate. No model ships — this configures the client the Pro overlay provides.

- **Settings → AI Assistant section** — a provider selector (Anthropic / OpenAI / Google / Local Ollama), an optional endpoint override, and an obscured API-key field, with a "No model configured" empty state when a cloud provider has no key. The key is stored in **platform secure storage** (`AiKeyStore`), never in `shared_preferences`, never in a session file, never logged. Provider + endpoint (non-secret) persist in `AppSettings`.
- **`kAiExperimental` build flag** (`crux_license`, `--dart-define=AI_EXPERIMENTAL=true`, default `false`) — when off, no AI section and no AI surface exists at all.
- **"Enable experimental AI features" toggle** (off by default) — the user opt-in. `aiExperimentalEnabledProvider` = build flag AND toggle; every AI configuration/functional surface gates on it.
- **Experimental chip** — rendered in the section header alongside (not instead of) any tier badge.

### Platform scope

All platforms. Secure storage maps to Keychain (iOS/macOS), Keystore-backed encrypted prefs (Android), libsecret (Linux), DPAPI (Windows), WebCrypto (Web).

### Setup

The section is only offered on a build with the flag on:

```bash
flutter run -d macos --dart-define=AI_EXPERIMENTAL=true
```

A build without the define (the beta default) is the "no AI surface anywhere" baseline.

### Steps and expected behavior

1. **Flag off (default build).** Open Settings. Confirm there is **no AI Assistant section** in the category list.
2. **Flag on, toggle off.** Launch with `--dart-define=AI_EXPERIMENTAL=true`. Open Settings → AI Assistant. Confirm the **Experimental chip** in the header, the **"Enable experimental AI features"** toggle (off), and **nothing else** — no provider, endpoint, or key fields.
3. **Toggle on.** Flip the toggle. Confirm the provider selector, endpoint field, and API-key field appear, and (with no key) the **"No model configured"** empty state.
4. **Enter a key.** Type an API key. Confirm the field is obscured (toggle visibility with the eye icon), the empty state disappears, and the key is **not** echoed in logs. Reopen Settings — the key is restored from secure storage.
5. **Switch provider.** Change the provider. Confirm the key field reloads that provider's own key (keys are per-provider), and a Local (Ollama) selection does **not** demand a key (no empty state).
6. **Clear the key.** Use the clear (✕) button. Confirm the key is removed from secure storage and the empty state returns (for cloud providers).
7. **Toggle off again.** Confirm all configuration disappears and (later prompts) every AI surface is hidden.

### Edge cases

- Quitting and relaunching preserves provider/endpoint (from settings) and the key (from secure storage).
- An empty key string deletes the stored secret rather than persisting `""`.
- The key never appears in the `.wavecrux` session document or `shared_preferences`.

### Tier-gate scenarios

The configuration surface is **Open Core and tier-agnostic** — no `FeatureGate`, no `FeatureTierBadge`. The Experimental gate is orthogonal to tier:

- **`kBetaPeriod = true` (beta):** identical for every tier; the gate is the build flag + user toggle, never the tier.
- **`kBetaPeriod = false` (post-beta):** unchanged; the AI gate does not consult `kBetaPeriod`. (Graduating AI out of Experimental is a separate `kAiExperimental` default flip.)

### 22.19.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| `kAiExperimental` default false; `aiExperimentalEnabledProvider` = flag AND toggle, both ways | `[Coverage: UNIT]` | `crux-shared/.../crux_license/test/ai_experimental_test.dart` + `ai_experimental_provider_test.dart` |
| Secure-storage round-trip (write/read/delete, per-provider isolation, empty-key deletes) | `[Coverage: UNIT]` | `test/services/ai/secure_storage_ai_key_store_test.dart` (mocked `FlutterSecureStorage`) |
| Provider/endpoint persistence; API key never written to `shared_preferences` | `[Coverage: UNIT]` | `test/services/settings/settings_service_test.dart`, `test/domain/models/app_settings_test.dart` |
| Toggle gates the provider/endpoint/key configuration both ways; empty state appears/clears | `[Coverage: UNIT]` | `test/features/settings/widgets/ai_settings_section_test.dart` |
| 44dp touch targets (toggle, clear-key button); locale sweep en/zh_CN/ja/ko | `[Coverage: UNIT]` | `test/features/settings/widgets/ai_settings_section_test.dart` |
| Experimental chip renders in all locales | `[Coverage: UNIT]` | `test/shared/widgets/experimental_chip_test.dart` |
| Build-flag gating of the whole section in the live Settings screen | `[Coverage: MANUAL]` | §22.19 step 1–2 (build-define driven; not assertable without two builds) |
| Secure storage actually persists across an app restart on each OS | `[Coverage: MANUAL]` | OS Keychain/Keystore/DPAPI — not assertable headless |

---

## 22.20 AI Waveform Assistant — "Explain Selection" (Open Core, free, non-agentic)

### What it does

The free "AI-assisted" taste: select signals, run **Explain Selection**, and get a short, plain-language explanation in a bottom-pane result panel where **every cited transition / time / transaction is a clickable affordance that jumps the cursor (and selects the signal) there**. It is a SINGLE, non-agentic `AiModelClient` call — no tool loop. Grounding discipline: a citation that does not resolve to the loaded trace renders as a non-clickable "Could not locate" chip — **never a silent wrong jump**.

The action `aiExplainSelection` is `requiredTier: openCore` (no tier badge) but carries the **Experimental chip** (rendered in the result-panel header). It is gated three ways: **visible** only when experimental AI is enabled (`aiExperimentalEnabledProvider`), and **enabled** only when a model is configured (`AiModelClient.isConfigured`) **and** the active tab has a non-empty selection.

> Open Core ships the no-op `AiModelClient`, so in a stock open-core build the action stays *disabled* (no configured model). The concrete BYO-key client that makes it actually call a model is provided by the Pro overlay (or a future open-core client); the feature, its panel, and its grounding are all open-core and exercised in tests with a faked configured client.

### Platform scope

All platforms (tablet/desktop primarily; the result panel uses the standard bottom-dock host).

### Setup

Run an experimental build with a configured model, e.g. (concrete client supplied by the overlay):

```bash
flutter run -d macos --dart-define=AI_EXPERIMENTAL=true
```

Enable experimental AI in Settings → AI, configure a provider + key (§22.19), load any VCD/FST, and select one or more signals.

### Steps and expected behavior

1. **Discovery.** With experimental AI off, confirm **no** "Explain Selection" entry in the Tools menu or command palette. Turn it on: the entry appears. With no model configured or nothing selected, it is **greyed** in the menu and **absent** from the palette (the palette omits disabled actions).
2. **Run.** Select a couple of signals around an interesting transition; invoke Explain Selection (Tools menu / palette). The bottom pane shows the result panel: title + **Experimental chip** + a close button, then a short explanation while a spinner shows during the call.
3. **Citations jump.** Each citation in the explanation is a small chip (signal @ tick, or a tick). Click one: the **cursor jumps to that tick** and the cited signal becomes selected. Verify the landing tick matches the citation.
4. **Could-not-locate.** If the model cites a signal or time not in the trace, that citation renders as a muted **"Could not locate"** chip with the raw citation in its tooltip, and clicking it does nothing (no jump).
5. **Close.** The close button clears the result and returns the bottom pane to its normal content.

### Edge cases

- Empty selection → an "select one or more signals" message (the action is normally disabled, but the controller also fails soft).
- No model configured → a "configure a model in Settings → AI" message (the no-op client path).
- Model unreachable / error → a non-fatal "could not be reached" message.

### Tier-gate scenarios

`aiExplainSelection` is **Open Core** (`requiredTier: openCore`, no badge). The Experimental gate is orthogonal to tier:

- **`kBetaPeriod = true` (beta):** identical for every tier; gating is experimental-flag + user-toggle + model + selection, never tier.
- **`kBetaPeriod = false` (post-beta):** unchanged. (The Pro "AI Advisor" agentic sibling is a separate, `requiredTier: pro` action — not this one.)

### 22.20.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| Citation grammar parser (text/citation split, signalRef-or-path, bare time, malformed token) | `[Coverage: UNIT]` | `test/services/ai/explain_selection_test.dart` |
| Single non-agentic request shape (system+user, no tools, context embedded) | `[Coverage: UNIT]` | `test/services/ai/explain_selection_test.dart` |
| Grounding resolver: real (signal,time) / signalRef / bare-time resolve; unknown signal, out-of-range time, empty, no-source → unresolved | `[Coverage: UNIT]` | `test/services/ai/explain_selection_test.dart` |
| Controller: faked configured client → ready + parsed citations; empty selection; no-op client → notConfigured; close | `[Coverage: UNIT]` | `test/features/ai/providers/explain_selection_provider_test.dart` |
| Panel grounding: resolved citation jumps cursor to the exact tick + selects the signal; unresolved is inert (no jump) | `[Coverage: UNIT]` | `test/features/ai/widgets/explain_selection_result_panel_test.dart` |
| Panel locale sweep (en/zh_CN/ja/ko); 44dp close button; phase messages | `[Coverage: UNIT]` | `test/features/ai/widgets/explain_selection_result_panel_test.dart` |
| Action gating: hidden when AI off; disabled without model/selection/file; enabled + in palette with all gates | `[Coverage: UNIT]` | `test/core/shortcuts/ai_explain_selection_gating_test.dart` |
| End-to-end against a real provider endpoint (BYO key) | `[Coverage: MANUAL]` | Needs a live key + concrete client (overlay); not assertable headless |

---

## 22.21 Signal selection from the waveform + Clear selection (Open Core)

### What it does

"Signal selection" (`selectedVariablesProvider`) is the set of signals the user
has marked as interesting. It drives downstream features (AI "Explain
Selection" context, the status-bar selected-signal value readout). Before this
change it could only be set by Ctrl/Cmd-clicking a leaf in the **Signal Tree**,
was highlighted only in the tree, and had no way to be cleared wholesale. This
feature adds three things:

1. **Select from the waveform value column.** Ctrl/Cmd-clicking a
   `ValueColumnRow` toggles that signal's selection (the same modifier branch
   the Signal Tree leaf uses). A plain click still cycles/copies the value. On
   touch, the row's long-press context menu gains a **"Select Signal"** item
   (no modifier key on touch).
2. **Selection highlight in the value column.** A selected value row is tinted
   with the theme `primary` colour at low opacity — consistent with how the
   Signal Tree leaf highlights a selected signal.
3. **Clear the whole selection.** A new open-core action
   `clearSignalSelection` (Navigate category; menu / overflow / command palette;
   enabled only while a selection exists) clears the selection. **Escape** also
   clears the selection (the viewer's global Escape handler clears the signal
   selection alongside the cursors). A small **✕** button next to the
   selected-signal indicator in the status bar clears the selection on click.

### Platform scope

All platforms. The Ctrl/Cmd-click path is desktop/keyboard; the "Select Signal"
context-menu item is the touch equivalent. The status-bar ✕ and the value-column
highlight render on tablet/desktop (the value column and its status-bar segments
are hidden on phone).

### Setup

Load any VCD/FST, add a few signals to the waveform so the value column is
populated.

### Steps and expected behavior

1. **Select from the value column (desktop).** Ctrl/Cmd-click a signal's value
   cell. The row tints (primary, low opacity) and the same signal highlights in
   the Signal Tree. The status bar shows the selected signal's value and a ✕
   button appears next to it.
2. **Plain click unaffected.** A plain (no-modifier) click on a value cell still
   performs its existing action (copy value / cycle) and does **not** change the
   selection.
3. **Select on touch.** Long-press a value row → context menu → **Select
   Signal**. The row tints and the selection updates. Long-press again → Select
   Signal toggles it back off.
4. **Clear via Escape.** With one or more signals selected, press **Escape**.
   The selection empties (the row tint clears, the status-bar ✕ disappears).
   Cursors are also cleared by the same Escape press (pre-existing behavior).
5. **Clear via the action.** Open the command palette / Navigate menu →
   **Clear Signal Selection**. With a selection present the action is enabled
   and clears it; with nothing selected the action is greyed (menu) / absent
   (palette).
6. **Clear via the status-bar ✕.** Click the ✕ next to the selected-signal
   indicator. The selection empties and the ✕ disappears.

### Diagnostics-assisted verification

None specific. The selected set is observable indirectly via the status-bar
selected-signal readout and the value-column / Signal-Tree highlight.

### Edge cases

- Selecting a signal that has no value at the current cursor → the row still
  tints and the status-bar ✕ still appears (the ✕ is gated on selection
  non-empty, independent of whether the selected signal has a value to show).
- Multi-select: Ctrl/Cmd-click several rows (and tree leaves); Escape / the
  action / the ✕ each clear the **entire** set in one action.
- Phone: there is no value column and no status-bar selected-signal segment, so
  the value-column highlight and the ✕ do not render; selection is still
  driven from the Signal Tree and cleared via Escape / the action.

### Tier-gate scenarios

This is **Open Core** — `clearSignalSelection` is `requiredTier: openCore`, no
tier badge, no `FeatureGate`. Behavior is identical under `kBetaPeriod = true`
and `kBetaPeriod = false`. (The Pro AI Assistant *consumes* the selection but
does not gate the selection mechanism itself.)

### 22.21.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| Ctrl/Cmd-click on a value cell toggles the signal selection | `[Coverage: WIDGET]` | `test/features/viewer/widgets/value_column_row_test.dart` |
| Plain tap on a value cell does **not** change the selection | `[Coverage: WIDGET]` | `test/features/viewer/widgets/value_column_row_test.dart` |
| Selected value row paints the primary tint; unselected does not | `[Coverage: WIDGET]` | `test/features/viewer/widgets/value_column_row_test.dart` |
| Touch context-menu "Select Signal" item toggles the selection | `[Coverage: WIDGET]` | `test/features/viewer/widgets/value_column_row_test.dart` |
| Status-bar ✕ shows only when a selection exists (and is hidden on phone), and clears the selection on tap | `[Coverage: WIDGET]` | `test/features/viewer/widgets/status_bar_test.dart` |
| `clearSignalSelection` action wired into the descriptor / menu layout / command palette, enabled only with a selection | `[Coverage: WIDGET]` | `test/core/shortcuts/action_surface_conformance_test.dart`, `test/core/shortcuts/menu_layout_test.dart` |
| `SelectedVariablesNotifier.clear()` empties the selection (the call Escape, the action, and the ✕ all make) | `[Coverage: WIDGET]` | `test/features/signal_tree/providers/signal_tree_providers_test.dart` |
| Escape clears selection + cursors together (global key handler) | `[Coverage: MANUAL]` | Private viewer-screen `_onKeyEvent`; the `clear()` contract is unit-tested, the keystroke wiring is verified manually |

---

## 22.22 Session restore parity — active panel, pane sizes, signal-tree state (Open Core)

### What it does

The per-tab session sidecar (`{appSupport}/sessions/{tabId}.wavecrux`, 2 s
debounced auto-save) is the mechanism behind "quit and relaunch lands you where
you left off" (the VS Code model). This change closes three gaps in what the
sidecar captured:

1. **Active bottom-dock panel.** The bottom pane's *content* is chosen by the
   viewer's priority chain over per-feature visibility flags. Previously only
   `transactionView` (is the pane docked) persisted, so a relaunch always fell
   back to the Transaction table even if the user had the cocotb-log / RTL /
   (Pro) AI / SVA panel open. The cocotb-log and RTL-source visibility flags now
   persist, and their underlying file paths (cocotb log, RTL stems) are
   re-loaded fail-soft on restore. (The Pro AI-Advisor / SVA selections persist
   via their Pro session-extension codecs — see the Pro verification guide.)
2. **Pane sizes.** Left / right / bottom pane sizes are persisted (previously
   hard-coded 280 / 220 / 200 and reset every launch). Drag-to-resize writes the
   size into `PanelLayoutState`; the shared `CruxIdeLayout` reconciles a restored
   size onto its live controller (crux_ide_layout `didUpdateWidget`).
3. **Signal-tree browser state.** Expand/collapse set, search-box text,
   multi-selection, and vertical scroll position all persist and restore.

### Platform scope

Desktop / tablet (the side and bottom panes and the signal-tree browser are
hidden on phone; the underlying state still persists and re-applies when the
window grows back to tablet/desktop).

### Setup

Load any VCD/FST with a hierarchy of scopes. Add a few signals.

### Steps and expected behavior

1. **Active panel.** Open the cocotb-log panel (load a cocotb log) or, on a Pro
   build, the AI Advisor. Resize the left (signal-tree) pane noticeably wider and
   the bottom pane taller. Expand several scopes in the signal tree, type a query
   in its search box, scroll the tree partway down. **Quit the app** (Cmd/Ctrl+Q
   on desktop) and **relaunch**.
2. **Expected on relaunch:** the same bottom panel is active (cocotb log shows
   its reloaded content; AI Advisor shows its restored transcript). The left and
   bottom panes are the sizes you dragged them to, not the defaults. The signal
   tree shows the same expanded scopes, the same search text (filtered view), and
   the same scroll position.
3. **Fail-soft.** Delete/move the cocotb log file, then relaunch a session that
   referenced it: the cocotb panel re-docks but shows its normal empty state — no
   error dialog. Same for a moved RTL stems file.
4. **Pane size during a session (no restart).** Drag a splitter; the new size
   sticks for the rest of the session and is what gets persisted.

### Diagnostics-assisted verification

Inspect the on-disk sidecar (`{appSupport}/sessions/{tabId}.wavecrux`): the
`panels` object carries `cocotbLogPanel` / `rtlSource` (+ `cocotbLogPath` /
`rtlStemsPath` when set) and a `sizes` object; a top-level `signalTreeState`
object carries `expanded` / `search` / `selected` / `scroll`. All are omitted
when at their defaults, so a never-customized session stays byte-stable.

### Edge cases

- A stale expanded-scope path or selected signal-ref (the reopened waveform no
  longer has it) is harmless — it simply never matches a rendered row.
- A restored non-empty search query drives the panel's search-expansion, which
  intentionally overrides the restored expansion set (faithful to "a search was
  active when saved").
- `null` pane sizes (never resized) fall back to the layout defaults.

### Tier-gate scenarios

This is **Open Core** — no tier badge, no `FeatureGate`. Behavior is identical
under `kBetaPeriod = true` and `kBetaPeriod = false`. (The Pro AI / SVA panel
*selections* restore via Pro codecs, covered in the Pro guide; the open-core
priority-chain mechanism that surfaces them is tier-agnostic.)

### 22.22.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| `SessionState` v3 fields round-trip (copyWith / equality / hashCode) | `[Coverage: WIDGET]` | `test/domain/models/session_state_test.dart` "v3 fields" group |
| v3 JSON serialization round-trip (panels content, pane sizes, signal-tree state) + lenient decode of a v1/v2 doc | `[Coverage: WIDGET]` | `test/services/session/session_service_test.dart` "v3 session-restore state" group |
| snapshot → restore through `SessionNotifier` restores panel flags, pane sizes, expanded scopes, search, selection, scroll | `[Coverage: WIDGET]` | `test/features/viewer/providers/session_providers_test.dart` round-trip group |
| `PanelLayoutNotifier` pane-size setters | `[Coverage: WIDGET]` | `test/features/viewer/providers/panel_layout_provider_test.dart` |
| `ExpandedScopesNotifier.applyExpanded` / `SelectedVariablesNotifier.applySelection` / `SignalTreeScrollNotifier` | `[Coverage: WIDGET]` | `test/features/signal_tree/providers/signal_tree_providers_test.dart` |
| Signal-tree panel seeds its scroll controller + search box from the restored providers and writes scroll back | `[Coverage: WIDGET]` | `test/features/signal_tree/widgets/signal_tree_panel_test.dart` "session-restore seeding" group |
| `CruxIdeLayout` reconciles a host-driven pane-size delta onto the live controller without echoing the sink | `[Coverage: WIDGET]` | `crux-shared/packages/crux_ide_layout/test/crux_ide_layout_test.dart` |
| Full quit → relaunch end-to-end (panel + sizes + tree state actually restored in the running app) | `[Coverage: MANUAL]` | The sidecar round-trip is unit-tested; the lifecycle-flush-then-cold-boot restore is verified manually (steps 1–2 above) |

---

## 22.23 Update mechanism (Open Core)

### What it does

A minimal, **notify-and-deep-link** update mechanism. On launch and every 24 h the app fetches a version manifest (`https://updates.wavecrux.app/manifest.json`), compares `latest.version` against the running build, and — when a newer **and** still-supported release exists — shows a non-intrusive banner above the viewer: "WaveCrux X.Y.Z is available." with **[View Changes] [Update Now] [Dismiss]**. "Update Now" deep-links (via `url_launcher`) to the platform download page on desktop/web and the App Store / Play Store on mobile; there is **no** in-place download / checksum / relaunch this phase. A manual **Check for Updates** entry point lives in the Help menu / overflow / command palette and in the About box. The automatic (launch + periodic) checks are governed by a **Settings → General → "Automatically check for updates"** toggle (default on); the manual check always runs. Every check transmits only the app version + OS (via the `User-Agent`). **On iOS and Android the update check is disabled entirely** (the store handles updates, and mobile carries no beta expiry) — the mobile build wires a no-op service, performs no manifest fetch, and shows no banner, so the mobile binary makes no update-related network request. The behaviors below apply to desktop and web.

Three behaviors deserve attention:

- **`mandatory`** manifests render a **non-dismissible** banner (no Dismiss; only View Changes / Update Now). A build below `min_supported_version` is *forced* mandatory even when the manifest's own flag is false — being below the floor never *suppresses* the notification, it strengthens it.
- The manifest's authoritative **`server_time`** is recorded (persisted, monotonic) on every successful fetch and feeds `crux_license`'s beta-expiry clock — the §10.8 clock-tampering hardening (see §22.17 and the clock-back path below).
- The check **never throws** — a network or malformed-manifest failure resolves to a typed error state (no banner; the manual check shows a non-fatal toast).

Open to all tiers — the `checkForUpdates` action is `requiredTier: openCore`, so **no tier badge** and no `FeatureGate`. The mechanism lives in `lib/features/update/` + `lib/services/update/` (model in `lib/domain/models/update_manifest.dart`, semver from `crux_updates`); the banner mounts in `app.dart`'s `MaterialApp.builder`, nested inside `BetaExpiryGate`.

### Platform scope

Desktop and web only. On iOS and Android the update check is disabled (the store handles updates), so no manifest fetch occurs and no banner appears — the mobile build makes no update-related network request. On desktop/web, "Update Now" → download page. The banner respects `SafeArea` (top) and renders above the Navigator (a sibling in `MaterialApp.builder`, like the beta-expiry banner — no `Overlay`-dependent widgets).

### Setup

The production endpoint/CDN is a separate website task and need not exist for this pass. Serve one of the committed fixtures in `verification/fixtures/update/` (see its `README.md`) and route the manifest host at it, or run a debug build that points `HttpUpdateCheckService(manifestUri:)` at a local file/server:

- `manifest_update_available.json` — version `99.0.0`, non-mandatory → banner appears.
- `manifest_mandatory.json` — version `99.0.1`, `mandatory: true` → non-dismissible banner.
- `manifest_up_to_date.json` — version `0.0.1` → app is current (no banner).
- `manifest_malformed.json` — invalid JSON → soft-fail (no crash, no banner).

The `99.x` versions sort above any real build version and `0.0.1` below it, so the outcomes are deterministic regardless of the build's version string.

### Golden path (update available)

1. Serve `manifest_update_available.json`. Launch (or trigger a check). Confirm the **banner** appears above the viewer: "WaveCrux 99.0.0 is available." with View Changes / Update Now / Dismiss.
2. Tap **View Changes**. Confirm the browser opens `https://wavecrux.com/releases/99.0.0` (the manifest's `changelog_url`).
3. Tap **Update Now**. Confirm the browser opens the platform target — desktop/web: `https://wavecrux.app/download`. (Mobile builds no longer perform the update check, so this banner does not appear on iOS/Android — run this path on desktop or web.)

### Dismiss path

1. With the banner shown, tap **Dismiss**. Confirm it hides and the viewer reclaims the space.
2. Confirm it stays hidden for the session for that version, and re-appears only when a *newer* version is offered (serve a higher version to confirm).

### Mandatory path

1. Serve `manifest_mandatory.json`. Confirm the banner appears with **only** View Changes / Update Now — **no Dismiss affordance** (it cannot be dismissed).
2. Confirm View Changes / Update Now behave as in the golden path.

### Manual "Check for Updates" — update exists

1. Serve `manifest_update_available.json`. Open **Help → Check for Updates** (or the command palette, or the About box's **Check for Updates** button).
2. Confirm the banner appears (the manual check surfaces an available update through the same banner; no separate toast).

### Manual "Check for Updates" — already current

1. Serve `manifest_up_to_date.json`. Trigger the manual check from any of the three surfaces.
2. Confirm **no banner**, and a brief confirmation toast: "You're on the latest version (X.Y.Z)" naming the running version.

### Auto-check toggle on/off

1. In **Settings → General**, confirm the **"Automatically check for updates"** toggle (default **on**) with its description.
2. Turn it **off**. Relaunch with `manifest_update_available.json` served. Confirm **no banner appears on launch** and no periodic check fires (the auto path is suppressed).
3. With the toggle still off, run **Help → Check for Updates** manually. Confirm the banner still appears — the manual check always runs regardless of the toggle.
4. Turn it back **on**; confirm the launch check resumes on the next start.

### Malformed-manifest soft-fail

1. Serve `manifest_malformed.json`. Trigger a check (launch or manual).
2. Confirm **no crash and no banner**. A manual check shows the non-fatal "Couldn't check for updates" toast; an automatic check fails silently.

### Server-time clock-back hardening (§10.8 / §10.9)

This is the cross-feature payoff: the update manifest's `server_time` hardens the beta-expiry clock against rollback.

1. Build a beta (`kBetaPeriod == true`) with `--dart-define=BETA_EXPIRY=<a past or near date>` so the build is at/near expiry by the true date.
2. Serve a manifest whose `server_time` is at or past the expiry date and let one successful check run (launch or manual) so the value is observed and persisted.
3. Set the **device clock back** well before the expiry date and **resume** the app (or relaunch offline).
4. Confirm the beta-expiry status **still triggers** (expiring-soon banner or expired modal per §22.17) — the trusted reckoning uses the *later* of the device clock and the last observed `server_time`, so rolling the clock back can no longer defer expiry below the last server time seen.
5. Control: on a **fresh** install that has never reached the endpoint (no observed server time), confirm expiry falls back to the device clock exactly as before (pre-hardening behavior preserved).

### Edge cases

- **Banner vs. beta-expiry precedence:** when a build is *expired* (§22.17), the blocking modal covers the update banner — `UpdateBanner` is nested inside `BetaExpiryGate`, so the expired modal wins. Verify both can be active without a render error.
- **Web never shows the banner (0.2.4):** the web app self-updates on deploy, so the "download the new version" banner is suppressed on web even when the manifest offers a newer version (it used to appear transiently around releases, between the manifest bump and the web deploy / 60 s edge cache). The update *check* still runs on web — it observes `server_time` for the clock-back hardening above. Verify on app.wavecrux.app right after a manifest bump (or with a locally served newer manifest): no banner; and confirm a desktop build against the same manifest DOES show it. `[Coverage: WIDGET]` (`update_banner_test.dart` — "web never shows the banner").
- **Below `min_supported_version`:** serve a manifest with a `min_supported_version` above the running build — confirm the update is offered **as mandatory** (non-dismissible), not suppressed.
- **No changelog URL:** a manifest entry without `changelog_url` hides the **View Changes** button (Update Now / Dismiss remain).

### Tier-gate scenarios

The update mechanism is Open Core. The `checkForUpdates` action declares `requiredTier: openCore`, so the `FeatureGate` is a **no-op in both beta and post-beta** — stated explicitly here so this row is not mistaken for missing tier coverage:

- **`kBetaPeriod = true` (beta):** Banner, toggle, and the Check-for-Updates action all function for every tier; no badge renders (openCore).
- **`kBetaPeriod = false` (post-beta):** Identical — the action stays openCore (no badge), the gate admits it for every tier, and nothing about the update mechanism changes at the beta→production flip. (Note the *beta-expiry* mechanism it hardens *does* go dormant post-beta per §22.17, but the update mechanism itself is tier- and beta-agnostic.)

### 22.23.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| Semver parse + ordering (equal/older/newer/pre-release precedence/build-metadata/malformed) | `[Coverage: UNIT]` | `crux-shared/packages/crux_updates/test/src/models/semantic_version_test.dart` |
| Manifest parse incl. `server_time`; soft-fail on malformed/missing/type-mismatched fields; `isNewerThan` / `meetsMinSupported` boundaries; equality/copyWith | `[Coverage: UNIT]` | `crux-shared/packages/crux_updates/test/src/models/update_manifest_test.dart` |
| `HttpUpdateCheckService`: returns an update only when newer; below-floor → forced mandatory; typed-failure (non-200 / network / malformed) never leaks raw; minimal `User-Agent`; `server_time` observed on available **and** current, skipped when absent | `[Coverage: UNIT]` | `crux-shared/packages/crux_updates/test/src/services/http_update_check_service_test.dart` |
| Notifier state machine: launch check, periodic (gated path), toggle-off suppresses auto-check, `checkNow` always runs, typed-error state never throws | `[Coverage: UNIT]` | `crux-shared/packages/crux_updates/test/src/providers/update_status_provider_test.dart` |
| Service-provider Noop-until-build-info then live Http default | `[Coverage: UNIT]` | `crux-shared/packages/crux_updates/test/src/providers/update_check_service_provider_test.dart` |
| Banner widget: LTR/RTL × text-scale sweep; product strings rendered unchanged; 44 dp dismiss and action targets; mandatory hides Dismiss; View Changes hidden without changelog; callbacks fire | `[Coverage: UNIT]` | `crux-shared/packages/crux_updates/test/src/widgets/update_available_banner_test.dart` |
| Banner gate: available → banner; current/checking/error → none; dismiss hides; mandatory non-dismissible; View Changes / Update Now launch correct URLs; per-platform Update Now target (`updateTargetFor`) | `[Coverage: UNIT]` | `crux-shared/packages/crux_updates/test/src/widgets/update_banner_test.dart`; WaveCrux's targets in `test/core/updates/wavecrux_update_config_test.dart` |
| Manual check helper: available → banner (no toast); current → version toast; error → non-fatal toast | `[Coverage: UNIT]` | `crux-shared/packages/crux_updates/test/src/update_check_action_test.dart` |
| Action descriptor: `checkForUpdates` openCore (no badge), on menu/overflow/palette; About-box button present + invokes `checkNow()` | `[Coverage: UNIT]` | `test/core/shortcuts/action_descriptors_test.dart`, `test/features/about/widgets/wavecrux_about_dialog_test.dart` |
| Auto-check setting round-trip (persist) + Settings → General toggle flips the provider | `[Coverage: UNIT]` | `test/services/settings/settings_service_test.dart`, `test/features/settings/screens/settings_screen_test.dart` |
| Observed-server-time store: monotonic record, persist, reload on launch; root override flows store → `crux_license` `observedServerTimeProvider` | `[Coverage: UNIT]` | `test/features/update/providers/observed_server_time_provider_test.dart` |
| `trustedBetaExpiryNow` rollback math; clock-set-back → expired via `server_time`; no-server-time fallback; consistent | `[Coverage: UNIT]` | `crux-shared/packages/crux_license/test/beta_expiry_test.dart` |
| Banner / View Changes / Update Now actually open the browser at the right URL | `[Coverage: MANUAL]` | OS-level `url_launcher` — not assertable headless (§22.23 golden/mandatory paths) |
| End-to-end against a live manifest endpoint (real fetch, version distribution / DAU server log) | `[Coverage: MANUAL]` | Depends on the website/CDN endpoint; fixture-served locally otherwise (§22.23 setup) |
| Clock-back hardening across a real resume / offline relaunch | `[Coverage: MANUAL → HYBRID candidate]` | Logic is unit-tested; the lifecycle-edge + persisted-reload path is the manual control (§22.23 clock-back path) |

---

## 22.24 Bundled sample waveform (Open Core, 0.2.0)

### What it does

The Welcome screen offers **[Open Sample Waveform]** next to **[Open File…]**. Tapping it opens a waveform bundled with the app — no user-supplied file needed. The sample is `assets/samples/all5_basic.vcd`, a verbatim copy of `verification/fixtures/protocol/multi/all5_basic.vcd`: ~5 KB carrying SPI, I²C, UART, AXI4-Lite, and APB traffic simultaneously, so one tap shows real transitions *and* five decodable protocols rather than a couple of clock lines. It is a `generated/` fixture, so shipping it in the app bundle carries no third-party license obligation.

**Why it exists.** Before 0.2.0 a first-run user faced an empty canvas whose only action opened a file picker. On mobile that is not merely inconvenient but impossible — an iPhone cannot produce a VCD locally. App Store review rejected 0.1.0 (2) under **Guideline 2.1 ("provide demo files")** and, relatedly, **Guideline 2.2** (the app appeared to have no working features), because the reviewer had nothing to open. The button makes the app demonstrate itself on every platform.

Open to all tiers — no badge, no `FeatureGate`.

### Platform scope

All platforms. Desktop/mobile materialize the asset to a real file (the wellen FFI engine reads from a background isolate and cannot read an asset-bundle key); web routes the bytes through the same path the drop-zone uses.

### Setup

None — the sample ships in the build.

### Step-by-step expected behavior

1. Launch a build with **no** recent files (fresh install, or clear Recent Files).
2. The Welcome screen shows the app icon, subtitle, **[Open File…]**, **[Open Sample Waveform]**, and the two empty recent lists. Confirm the sample button is present on **phone**, tablet, and desktop — phone is the case that matters, since it drops [Open Workspace…].
3. Tap **[Open Sample Waveform]**. A new tab opens named **WaveCrux Sample.vcd**.
4. Confirm the hierarchy browser lists five scopes: `spi_tb`, `i2c_tb`, `uart_tb`, `axi4lite_tb`, `apb_tb`.
5. Add signals from any scope and confirm transitions render.
6. Attach a decoder (e.g. SPI on `spi_tb`) and confirm decoded transactions overlay the waveform. This is the "it visibly works" demonstration a reviewer or evaluating engineer sees.
7. Tap it a second time — a second tab opens (File→Open semantics: always a new tab, never a replace).

### Edge cases

- **Repeat taps / corrupted copy:** the sample is rewritten on every invocation rather than reused when present, so a copy truncated by an interrupted earlier write repairs itself instead of failing to parse forever. Verify by truncating the materialized file on disk and tapping again.
- **Asset drift:** the shipped asset must stay byte-identical to its verification fixture. Enforced by test, not by eye.
- **Sandboxed storage:** the sample is written under the app-support directory (not temp), so iOS purging caches mid-session cannot break an auto-reload or a session restore pointing at it. Falls back to the system temp directory when the platform channel is unavailable.

### Tier-gate scenarios

Open Core in both regimes — stated explicitly so this row is not mistaken for missing tier coverage:

- **`kBetaPeriod = true` (beta):** button present and functional for every tier; no badge.
- **`kBetaPeriod = false` (post-beta):** identical. Nothing about the sample is tier- or beta-dependent.

### 22.24.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| Asset loads from the bundle; materializes to a real re-readable file; correct file name | `[Coverage: UNIT]` | `test/services/samples/sample_waveform_service_test.dart` |
| Rewrite-on-every-call (truncated copy self-repairs) | `[Coverage: UNIT]` | same file |
| Shipped asset is byte-identical to the verification fixture, is a parseable VCD carrying all five scopes, and stays under the size budget | `[Coverage: UNIT]` | same file — this is the drift guard |
| Button renders on phone / phone-landscape / tablet / desktop; fires its callback; absent when no callback supplied; locale sweep (en/zh_CN/ja/ko) | `[Coverage: WIDGET]` | `test/features/workspace/widgets/wavecrux_empty_canvas_test.dart` |
| End-to-end: tap → tab opens → five scopes present → decoder overlays transactions | `[Coverage: MANUAL → INTEGRATION candidate]` | Needs the real FFI engine; strong integration-test candidate (steps 3–6 above) |
| Web byte-path variant (no filesystem) | `[Coverage: MANUAL]` | Browser-only path; verify on app.wavecrux.app |

---

## 22.25 App-store distribution surface (mobile store builds, 0.2.0)

### What it does

iOS and Android ship through consumer app stores whose review rules differ from side-loaded desktop distribution. Four surfaces therefore differ on a **mobile host** (`isMobileHostPlatform` — iOS/Android, not a mobile *browser*), while desktop and web are unchanged:

1. **PRO/ENT actions are hidden, not badged.** Open Core ships the full `ShortcutAction` enum including Pro/Enterprise actions, but its handlers for them are empty closures ("Open Core builds silently absorb these actions"). On desktop that is a deliberate upsell with a working upgrade path. On an app store it is a feature that visibly does nothing — Apple rejected 0.1.0 (2) under **Guideline 2.2** ("complete, remove, or fully configure any partially implemented features") after tapping badged rows like *Share Session* and *Convert PCAP to VCD* and getting no response. The rule is applied once, in `isActionVisibleIn`, keyed off `ActionContext.tierGatedActionsAvailable` (fed by `tierGatedActionsAvailableProvider`), so a *future* PRO/ENT action inherits it from `requiredTier` alone.
2. **The "Public Beta" chip is suppressed** in the About screen. App stores forbid distributing pre-release software, and the mobile builds carry no beta expiry either (see `scripts/release_ios.sh`), so on these hosts there is genuinely no beta for the chip to describe; the desktop build is a real public beta and keeps it. Implemented as a `betaPeriodProvider.overrideWithValue(false)` in `bootstrap`'s root container, guarded by `isMobileHostPlatform`. This flips only provider-reading UI — `FeatureGate.isAvailable` reads the compile-time `kBetaPeriod` constant, so tier gating is unchanged, and the picker dialogs that do read the provider gate nothing in an Open Core build (which registers no PRO/ENT decoders, Stage widgets, or translator presets).
3. **The RGB LED binding hint drops its upsell.** Desktop reads *"RGB LED position — Open Core renders one channel only. Upgrade to Pro for full RGB rendering."*; mobile reads *"RGB LED position — renders a single color channel."* The first describes a shipped feature as partial (**2.2**) and is an external purchase call-to-action inside the app (**3.1.1**). Behavior is identical; only the framing differs.
4. **The Settings → AI Assistant section is removed** from store builds via `--dart-define=AI_EXPERIMENTAL=false` in `scripts/release_ios.sh` and `scripts/release_android.sh`. `kAiExperimental` defaults to `true`, so 0.1.0 (2) shipped a section labelled *"Experimental"* whose own description said the assistant *"may change or be removed"* — a self-declared unfinished feature. Desktop keeps the flag on and the BYO-key assistant available.

Note also what is **not** changed, deliberately: the in-app update banner needs no mobile guard (`updateCheckServiceProvider` already returns a `NoopUpdateCheckService` on iOS/Android, so the status never reaches `available`), and the Issue Reporter's destination is the same on mobile as on desktop — the fixed open-core slug `Ferrite-Engineering/wavecrux`, which it moved to at the 1.0 launch.

### Platform scope

iOS and Android only. Every behavior above is unchanged on macOS, Windows, Linux, and web.

### Setup

Two builds are needed to verify the delta: a desktop build and a mobile store build (`./scripts/release_ios.sh` / `release_android.sh`, or a debug run on a simulator/device — the platform predicate is runtime, not build-flag, for items 1–3; item 4 is build-flag and requires the release script or an explicit `--dart-define=AI_EXPERIMENTAL=false`).

### Step-by-step expected behavior

**On iOS/Android:**

1. Open the overflow menu (phone bottom sheet and tablet popup). Confirm **no** row carries a PRO or ENT badge, and specifically that *Debug Advisor*, *SVA panel* (toggle/load/clear), *AI Waveform Assistant*, *Convert PCAP to VCD*, *Share/Join/Stop/Leave Session*, *Export Session Recording*, and the Presenter Mode entries are **absent** — not greyed, absent.
2. Open the command palette and type fragments of those names. Confirm no matches.
3. Confirm the Open Core rows are all still present — the sheet must not have been emptied.
4. Open About. Confirm **no "Public Beta" chip**. The version line reads 0.2.0.
5. Open Settings. Confirm there is **no AI Assistant category** (store build only).
6. On a tablet, add the Arty A7 board Stage widget and open its bindings pane. Confirm an RGB LED slot reads *"renders a single color channel"* with **no** mention of Pro or upgrading.

**On desktop (the control):**

7. Repeat 1–2 and confirm PRO/ENT rows **are** listed with their badges.
8. Repeat 4 and confirm the "Public Beta" chip **is** present (while `kBetaPeriod` is true).
9. Repeat 6 and confirm the desktop wording with the Pro upgrade hint.

### Edge cases

- **Mobile browser is not a mobile host.** A phone browsing app.wavecrux.app is web: `isMobileHostPlatform` is false, so it keeps desktop behavior. Verify the chip and PRO/ENT rows still appear there.
- **Suppression must be conditional, not permanent.** If a Pro mobile build ever ships, the Pro overlay overrides `tierGatedActionsAvailableProvider` to `true` — its `proOverrides` replace the no-op opener providers with real ones. Hardcoding the platform test at the call site would silently strip working features out of that build. Covered by test.
- **iPad Stage Manager / split-screen** does not change host platform — a narrow iPad window is still iOS and still suppresses.

### Tier-gate scenarios

- **`kBetaPeriod = true` (beta):** `FeatureGate` short-circuits open for every tier, so on **desktop** a user can actually *use* PRO/ENT features and the badges advertise the future model. On **mobile** the actions are hidden regardless — the suppression keys off whether the build *implements* them (`tierGatedActionsAvailableProvider`), not off the beta gate, so beta state does not resurrect dead rows.
- **`kBetaPeriod = false` (post-beta):** desktop Open Core badges the actions and `FeatureGate` denies activation, showing the upgrade dialog. Mobile is unchanged — still hidden, so no upgrade dialog and no external purchase CTA can appear on a store build (which also keeps Guideline 3.1.1 satisfied by construction). The "Public Beta" chip disappears everywhere at the flip; the mobile suppression becomes redundant but stays correct.

### 22.25.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| Every PRO/ENT action hidden from every surface when the build cannot execute them; Open Core actions unaffected; palette and overflow selectors both filtered | `[Coverage: UNIT]` | `test/core/shortcuts/tier_gated_action_mobile_suppression_test.dart` |
| `tierGatedActionsAvailableProvider` default: false on iOS/Android, true on desktop, and overridable so Pro mobile can opt back in | `[Coverage: UNIT]` | same file |
| Phone overflow sheet lists no PRO/ENT rows and still lists every Open Core row — the exact surface and device class of the rejection | `[Coverage: WIDGET]` | `test/features/viewer/widgets/viewer_toolbar_test.dart` — "Open Core on a phone lists no PRO/ENT rows" |
| `isMobileHostPlatform` / `isDesktopPlatform` truth table and disjointness across all `TargetPlatform` values | `[Coverage: UNIT]` | `test/core/platform_utils_test.dart` |
| Beta chip renders under `kBetaPeriod` and disappears when `betaPeriodProvider` is false (the mechanism `bootstrap` uses on mobile) | `[Coverage: WIDGET]` | `test/features/about/widgets/wavecrux_about_dialog_test.dart` |
| The chip is actually absent on a real iOS/Android build | `[Coverage: MANUAL]` | `bootstrap`'s host branch — §22.25 steps 4 and 8 are the control pair |
| RGB LED binding description: desktop upsell wording vs mobile neutral note | `[Coverage: WIDGET]` | `test/features/stage/widgets/boards/arty_a7_stage_widget_test.dart`, and Pro's `zybo_z7_stage_widget_test.dart` |
| Settings has no AI category under `AI_EXPERIMENTAL=false` | `[Coverage: UNIT]` | `test/features/settings/screens/settings_screen_test.dart` (build-flag path via `aiExperimentalBuildFlagProvider`) |
| Release scripts actually pass `--dart-define=AI_EXPERIMENTAL=false` | `[Coverage: MANUAL]` | Verify in the built IPA/AAB (Settings shows no AI category); the scripts are not executed in CI |
| The delta as a whole on real hardware (steps 1–9 above, both a mobile store build and a desktop control) | `[Coverage: MANUAL]` | The pre-submission gate — run this before every store upload |

---

## 22.26 Shipped `examples/` sessions (Open Core, 0.2.0)

### What it does

`examples/` at the repository root holds two ready-to-open `.wavecrux` sessions, each with its trace committed beside it and named relatively, plus an `examples/README.md` and a "Try it" section on the repo's front-page `README.md`. A person cloning the repo — or unpacking a source tarball — has something to open without knowing anything about `test/fixtures/`.

- **`examples/five-buses/`** — `five-buses.wavecrux` over `five-buses.vcd` (a byte-identical copy of `verification/fixtures/protocol/multi/all5_basic.vcd`). Signals grouped per bus, formats set, and **five decoder instances baked into the session** (SPI, I²C, UART at 1 Mbaud, AXI4-Lite, APB) so the transaction table is populated on open.
- **`examples/pipeline-diagram/`** — `pipeline-diagram.wavecrux` over `pipeline-diagram.vcd` (a copy of `test/fixtures/protocol/riscv/generated/riscv_pipeline_5stage.vcd`), with a **Stage** panel mounting the open-core `pipeline` widget across all five stages.

**Why it exists.** WaveCrux had no equivalent of SimCrux's and LintCrux's `examples/`. The bundled sample waveform (§22.24) covers first-run *in the app*; this covers first-run *in the repository*, and unlike the sample it demonstrates a **pre-arranged session** — groups, formats, decoders and a Stage panel — rather than a raw trace.

Open to all tiers. Both examples deliberately use only open-core decoders and the open-core `pipeline` widget; a Pro widget id here would mount an empty tile in an open-core build.

### Platform scope

Desktop primarily (the File → Open File picker path). Mobile can open either session through the share sheet / document picker if the trace is alongside.

### Setup

None. No simulator, cross-compiler, decoder plugin or network access.

### Step-by-step expected behavior

1. **File → Open File** (`Cmd/Ctrl+O`). Confirm the picker's allowed extensions include `wavecrux` — there is no separate "open session" menu item, and the post-pick dispatch routes `.wavecrux` to the session loader.
2. Pick `examples/five-buses/five-buses.wavecrux`. A tab opens and the trace `five-buses.vcd` next to it loads — verify this from a working directory *other* than the repo root, since the relative-path resolution is against the session file's own directory, not the process CWD.
3. Confirm five signal **groups** — SPI, I2C, UART, AXI4-Lite, APB — with APB **collapsed** and the other four expanded.
4. Confirm the **transaction table** in the bottom panel is already populated with five decoders' output, with no manual binding step.
5. Click a transaction row; the cursor jumps to it and the canvas scrolls.
6. Open `examples/pipeline-diagram/pipeline-diagram.wavecrux`. Confirm the **Stage** panel is visible with one Pipeline Diagram tile labelled "Pipeline Diagram", five columns named IF/ID/EX/MEM/WB.
7. Click a cell in the grid; the cursor moves to that cycle and the raw `stage*_valid` / `stage*_stall` / `stage*_flush` lanes on the left show the bits it came from.
8. Confirm the stall and the flush in the trace are visible as a shape in the grid.

### Edge cases

- **Silent degradation is the whole risk.** A `.wavecrux` stores Stage and decoder bindings as backend-local `signalRef`s and restore does **not** re-resolve them; the top-level signal list *is* re-resolved by path, and `SignalGroupsNotifier.reresolveSignalRefs` **drops entries whose path matches nothing without an error**. Either failure opens to a window that is merely emptier than intended. Enforced by test, not by eye.
- **Trace drift.** Both `.vcd` copies must stay byte-identical to their upstream fixtures; regenerating a fixture without refreshing the example silently changes what the example shows.
- **Undocumented example.** A session added to `examples/` without a README entry or a guard entry fails the guard.

### Tier-gate scenarios

Open Core in both regimes:

- **`kBetaPeriod = true` (beta):** both sessions open fully; no badge, no gate.
- **`kBetaPeriod = false` (post-beta):** identical. Nothing in either example is tier- or beta-dependent — that is the point of restricting them to open-core decoders and the open-core `pipeline` widget.

### 22.26.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| Both sessions load through the real `SessionService.loadSession` | `[Coverage: UNIT]` | `test/examples/examples_test.dart` |
| `sourceFilePath` is relative, single-segment, and the named trace is committed beside the session | `[Coverage: UNIT]` | same file — the portability guard |
| Every signal entry's `path` resolves against the committed trace **and** its baked `ref` equals the ref that trace actually produces | `[Coverage: UNIT]` | same file — the silent-drop guard; the strongest assertion here |
| Every Stage instance mounts a widget registered in an **open-core** `StageRegistry`, every pin name is declared by that widget, every bound ref resolves | `[Coverage: UNIT]` | same file |
| Every decoder id is registered open-core, every pin name is declared by the definition, every bound ref resolves | `[Coverage: UNIT]` | same file |
| All five decoders **actually decode**, through the registry factories with `decodeAll`-shaped callbacks, matching `all5_basic.<id>.expected_transactions.json` counts and labels | `[Coverage: UNIT]` | same file — "it works", not "it exists" |
| Both `.vcd` copies are byte-identical to their upstream fixtures | `[Coverage: UNIT]` | same file — the drift guard |
| Every `.wavecrux` under `examples/` is covered by the guard, and every example directory is named in `examples/README.md` | `[Coverage: UNIT]` | same file |
| The visual result on a real build — groups collapsed/expanded, table populated on open, Stage tile rendering, click-a-cell seek (steps 2–8 above) | `[Coverage: MANUAL → INTEGRATION candidate]` | Needs the real FFI engine and a rendered Stage panel |

---

## 22.27 Digital bus rendered as an analog trace (Open Core)

**What it does.** Draws a digital bus as a curve instead of a hex/binary lane —
GTKWave's `Data Format → Analog`. The feature exists because a fixed-point or
ML-float datapath is unreadable as hex: an engineer evaluating WaveCrux against
GTKWave on a DSP block hits this in the first session, which makes it a
migration blocker rather than a nicety.

**The one design rule to keep in mind while verifying.** The analog toggle is
**orthogonal to the display format**, not a value of it. The format answers
*"what number are these bits"* (hex, Q4.12, IEEE 754, a Pro bf16 translator);
the toggle answers *"draw that number how"*. So the same bits legitimately plot
a different curve under Q4.12 than under hex — that is correct behaviour, not a
bug, and it is the fastest way to confirm the two axes are really independent.

### Setup

```bash
dart run tool/generate_analog_fixtures.dart   # if the corpus is missing
```

Open `verification/fixtures/analog/mixed_analog_digital.vcd`. It carries real
signals, buses meant to be plotted, and buses meant to stay digital on one
timeline — see `verification/fixtures/analog/README.md` for the per-signal
table and the expected value ranges.

### Steps

1. Add `top.dsp.sample_q`, `top.dsp.count_u`, `top.vref` and `top.clk`.
2. `top.vref` renders as a curve immediately — it is a `real`, always was
   analog, and nothing about this feature changed it. `top.clk` renders as a
   normal scalar lane.
3. Right-click `top.dsp.sample_q` → **Render as analog**. The lane becomes a
   curve. As it stands (hex), it is a sawtooth of raw integers.

   **The toggle is on two menus, deliberately.** The signal-name row in the
   left panel (right-click, or long-press the colour dot on touch) and the
   value cell in the right-hand Values pane both carry it. The format menu
   lives only in the Values pane, but GTKWave puts Data Format on the signal
   *name*, so that is where a migrating user right-clicks first. Check both
   during verification — a build where only one has it is half-broken for the
   audience this feature exists for.
4. Right-click it again → **Display Format → Fixed-point Q** and configure
   **Q4.12 signed**. The curve becomes a clean sine spanning **−3.5 … +3.5**.
   *This is the whole feature in one step:* the toggle did not change, the
   number did.
5. Right-click the same row → the menu item now reads **Render as digital**.
   Choosing it returns the lane to a bus, with the Q4.12 format still set —
   confirming the two settings are stored and applied independently.
6. Turn analog on for `top.dsp.bus_xz`. The trace has two **gaps**, one over
   its `x` window and one over its `z` window. Confirm the curve *breaks*
   rather than dropping to the zero line — a gap drawn as 0 would be
   indistinguishable from a real zero sample and is the most damaging way this
   feature can be wrong.
7. Leave `top.dsp.count_u` alone. It must still be a hex bus. A build where
   turning one lane analog converted others has a lane-identity bug.
8. Save the session, reopen it: the analog rows come back analog, the digital
   rows digital.

### `.gtkw` import

Open `test/fixtures/gtkw/generated/analog_flags.gtkw` against its paired
`fixture.vcd`. Traces flagged `TR_ANALOG_STEP` / `TR_ANALOG_INTERPOLATED`
import already switched to analog; the unflagged trace does not.

> **While you are here:** this release also corrected the `.gtkw` display-format
> decode. The `@` word is a bit set (`1 << bit` over `enum TraceEntFlagBits` in
> GTKWave's `src/analyzer.h`), not an enumeration of low-byte values, and the
> previous table read `@22` as octal and `@28` as binary's opposite. If you have
> an old `.gtkw` handy, spot-check that a hex-formatted bus now imports as hex.

### Coverage

| Claim | Coverage | Where |
|---|---|---|
| Every built-in format's numeric reading, including the hex `"1e5"` trap and the Gray decode | `[Coverage: UNIT]` | `test/services/value_format/numeric_value_test.dart` |
| A Pro/declarative translator reaches the renderer through `Translator.translate` only, and a throwing or non-numeric one degrades rather than crashing | `[Coverage: UNIT]` | `test/services/value_format/analog_value_extractor_test.dart` |
| The painter plots magnitudes, x/z become gaps not zeros, and real signals keep the historical extractor | `[Coverage: UNIT]` | `test/features/viewer/rendering/analog_digital_lane_test.dart` |
| The whole chain over a file carrying analog **and** digital signals at once, through the real FFI parser | `[Coverage: UNIT]` | `test/services/waveform/analog_fixture_golden_test.dart` |
| The menu item appears, applies, reverses, and is localized in all four locales | `[Coverage: WIDGET]` | `test/features/viewer/widgets/value_column_row_test.dart` |
| `renderAsAnalog` round-trips in `.wavecrux`, is omitted when false, and a pre-feature session loads as digital | `[Coverage: UNIT]` | `test/services/session/session_service_test.dart` |
| GTKWave analog + radix flag decode | `[Coverage: UNIT]` | `test/services/session/gtkw_parser_test.dart` |
| The rendered result on a real build — curve shape, gap appearance, mixed lanes side by side (steps 2–8 above) | `[Coverage: MANUAL]` | Needs the real FFI engine and a rendered canvas |

---

---

## 22.28 Waveform annotations (Open Core)

**What it does.** Balloons, arrows and time bands drawn on the waveform and
anchored to `(tick, signal path)` rather than to pixels, so they stay glued to
the edge they mark through pan, zoom and scroll. Each note records a **witness**
— what the signal was doing when it was written — and reports itself as
*drifted* when that no longer holds. That is the whole differentiator over
annotating a screenshot: re-simulate, reopen, and the claims that no longer hold
flag themselves.

**Fixture.** `examples/annotations/annotations-demo.wavecrux` — open the
`.wavecrux`, not the `.vcd`. Copy the directory somewhere scratch before editing
the trace; a guard asserts the committed example opens **not** drifted.

### Finding the feature at all

**Do this pass on a fresh profile, before the authoring pass.** Every route
below has to work for somebody who has never made an annotation, because the
gesture is not guessable and 5.9.1 shipped with its only explanation
unreachable.

0a. With a waveform open and **no annotations**, run **View ▸ Annotations
    Panel**. The panel opens *empty* and says *"No annotations yet.
    Option-click a signal lane to add one."* That sentence is the feature's
    discovery surface. Until 2026-08-13 the panel appeared only once the tab
    already had a note, so the sentence rendered only for people who no longer
    needed it.

0b. **Right-click the canvas.** *Add annotation here*, *Annotate Range Between
    Cursors* and *Annotate Range on This Lane* are all there. Right-click is
    the discoverable route; Option-click is the fast one.

0c. **Edit ▸ Add Annotation at Cursor** (⇧A). Click a signal **in the signal
    list** so its row is selected, place the primary cursor, then press ⇧A: a
    note appears on that lane at the cursor with its editor open. With zero or
    several signals selected, or no cursor, it is greyed — and invoking it from
    the palette says which of the two is missing rather than doing nothing.
    (This is WaveCrux's first Edit-menu action; the menu did not exist before.)

    **Do this with a real selection, not a fixture.** Both this action and the
    band confine control below resolve "the selected lane" from a set keyed by
    `Variable.fullPath`; comparing it against `signalRef` silently never
    matches, and the symptom is "select exactly one signal" for a user who has.
    Both shipped that way once. See `singleSelectedRowId`.

### Authoring

1. **Option/Alt-click a signal lane.** A balloon appears with a focused text
   field. Type and press **Enter** — Shift+Enter inserts a line break instead.
   The note **stays expanded** afterwards. Do this again on a note that was
   collapsed (fold one first, or use the fixture's authored-collapsed note):
   committing text must un-fold it. It did not until 2026-08-14, so typing a
   sentence and pressing Enter put the words in the panel while the canvas
   snapped back to a dot — which reads as the text having been thrown away.
1b. **Fold it back with the balloon's ⌄.** Tapping a dot has always expanded a
   note; nothing on the canvas folded one, so `collapsed` had exactly one
   writer in the whole app — the walkthrough. The panel's ⋮ offers the same.
1c. **Edit a note whose signal is hidden**, from the panel's "Not displayed"
   group: the signal is put back on the canvas and the editor opens. Edit one
   under **"Not in this file"**: a message says there is no lane to edit it on.
   Both used to set the editing state and produce nothing visible, which is
   indistinguishable from a dead menu item — and the panel is exactly where
   those notes are listed, so it is where somebody will try.
2. Alt-click **between lanes** or on a group header: nothing is created and a
   message says why. Silence here is a bug — a click that lands nowhere looks
   identical to one that worked.
3. Click a lane a few pixels **before a transition**: the anchor snaps onto the
   edge. Hold the modifier to place freely. Snapping is not cosmetic — an
   unsnapped anchor captures the witness on the wrong side of the edge, so the
   note records the value from *before* the event it describes.
4. Touch/long-press the canvas → **Add Annotation Here** in the context menu.

### Manipulating

5. **Drag a balloon.** The note moves; the **anchor does not**, and the leader
   line stretches to follow. The **primary cursor must not move**, either during
   the drag or when the pointer is released.
6. Drag several different notes, including the earliest-authored one. Every
   balloon must stay grabbable regardless of how many others are on screen or
   where they have been moved to.
7. Click a collapsed numbered dot: it expands. Click the **×**: the note is
   deleted and a snackbar offers **Undo**.
8. Pan, zoom and place cursors in the gaps between balloons — unchanged
   behaviour.

### Drift — the one that matters

9. Note the balloon on `top.bus` renders normally.
10. Edit the copied trace: change `b10100011 $` under `#400` to `b00000000 $`.
11. Let the file watcher auto-reload (or reopen). That note must now render
    **drifted**: dashed leader, amber, italic. Nothing else changes and nothing
    is deleted — annotations survive a reload of the same file on purpose,
    because that is exactly when the witness has something to say.
12. Change the value back: it returns to normal.
13. Switch the `bus` row from hex to decimal. It must **not** drift — the
    witness stores canonical bits, so a display preference cannot masquerade as
    a design change.

### The panel

14. Open the **Annotations** tab in the bottom dock. Every annotation is listed,
    numbered in time order — the badge matches the canvas dot, so gaps in the
    visible numbering are correct.
15. **Not displayed (n)** groups notes whose signal is hidden; **Show signal**
    puts the lane back and the note becomes drawable. **Not in this file (n)**
    groups notes whose signal is absent. Neither is ever silently dropped —
    that is the panel's reason to exist, since the canvas draws nothing for
    them by design.
16. Filter text matches body, author and signal path. **Drifted only** narrows
    to the notes needing a re-check. A filter that excludes everything says so.
17. Click a row: the view centres that tick at the current zoom. Double-click
    opens its editor.

### Persistence and export

18. Save the session, quit, reopen: annotations return with their positions,
    collapse state and witness intact.
19. Open a pre-5.9 session: loads clean with no annotations and re-saves
    byte-stable.
20. **Export → PNG**: annotations appear in the image. Untick **Include
    annotations** and they do not — and the canvas is left showing them again
    afterwards, including when the export fails or is cancelled.
21. With PNG selected, **Time range** and **Signals** are disabled with an
    explanation. A PNG is a capture of the visible viewport, so it cannot
    honour them; they were previously offered and silently ignored.
22. **View ▸ Show Annotations** (⌘/Ctrl+⇧N) hides every note; the canvas is
    bare and the panel still lists them. Toggle it back. Save, reopen: the
    state persists, and every note is still there.

    *Until 2026-08-13 this step named a control that did not exist.* The
    visibility state shipped in 5.9.1 with persistence and export integration
    and **no writer** — the export dialog honoured a flag the user had no way
    to set. If this step ever becomes unreachable again, that is the same
    defect returning.

### The panel's row actions

23. Every row has a **⋮**. It opens **immediately** — if it takes a visible
    beat, the button has been nested back inside the row's double-tap target
    and every press is waiting out the double-tap timeout.
24. **Delete** removes the note with an undo toast. Do this on a note in the
    **"Not displayed"** group: that is the case the action exists for, because
    an orphan draws no balloon and therefore has no ✕ anywhere else.
25. **Collapse on canvas** folds an expanded balloon to its numbered dot;
    **Expand on canvas** brings it back. Before this, `collapsed` could only be
    set by the *walkthrough* folding the note it had just left — you could
    expand a dot by tapping it and never fold a balloon back.
26. **Set anchor time…** takes a tick, shows the current position formatted
    beneath the field, and moves the note there — jumping the viewport to it.
    An out-of-range number **clamps** rather than being refused.
27. **The moved note must NOT go drifted.** Same rule as the ⌥-arrow nudge: the
    witness is re-captured, or the badge would come to mean "somebody adjusted
    this" rather than "the design changed".
28. On an **adopted** note (§22.33) the menu offers *Duplicate as mine* and no
    *Edit text* — but it does offer **Delete**. Read-only attribution is about
    not rewriting somebody's words, not about being unable to remove them.

### The drift legend

29. The **Drifted only** chip carries an amber swatch, and hovering it explains
    what amber means. Without that, amber is the only colour variation a
    single user ever sees and nothing in the app says why — on a feature whose
    entire differentiator over a screenshot is that stale claims flag
    themselves.
30. Export the same drifted note to **SVG** and compare: the document's amber
    is the *same* amber. Both read `kAnnotationDriftedColor`; three surfaces
    disagreeing about which notes still hold would be worse than none of them
    saying so.

### 22.28.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| Model round-trip: every shape, both anchor kinds, tolerant decode, text cap | `[Coverage: UNIT]` | `test/domain/models/annotation_test.dart` |
| `.wavecrux` v4: additive bump, empty-list omission, one bad entry does not cost the rest, preserve-unknown intact | `[Coverage: UNIT]` | `test/services/session/session_annotations_round_trip_test.dart` |
| Snapshot/restore through the live provider graph | `[Coverage: UNIT]` | `test/features/annotations/annotation_session_wiring_test.dart` — a codec test cannot catch a missing wire |
| Witness capture, the four-state decision table, and drift after a re-run | `[Coverage: UNIT]` | `test/services/annotations/annotation_witness_service_test.dart` |
| Drift is independent of display format, and `b0` compares equal to `00000000` | `[Coverage: UNIT]` | same file — a badge that fires on a radix change is one users learn to ignore |
| Drift recomputes when sample data finishes loading after an in-place reload | `[Coverage: UNIT]` | `test/features/annotations/annotation_drift_on_reload_test.dart` |
| Annotations survive a reload of the same file; a different file clears them | `[Coverage: UNIT]` | `test/features/annotations/annotation_reload_test.dart` |
| Anchor resolution, edge snapping, and that the radius is pixels not ticks | `[Coverage: UNIT]` | `test/services/annotations/annotation_anchor_resolver_test.dart` |
| All three creation paths capture a witness; abandoned empty callouts are discarded | `[Coverage: UNIT]` | `test/features/annotations/annotation_authoring_test.dart` |
| Dragging moves the label and provably not the anchor; a whole drag is one undo step | `[Coverage: UNIT]` | `test/features/annotations/annotation_interaction_test.dart` |
| The ancestor gesture handler still sees the pointer claim held on the up event | `[Coverage: UNIT]` | same file — models production; this is what stopped the cursor jumping to the release point |
| Enter commits rather than inserting a newline | `[Coverage: UNIT]` | same file |
| Panel lists orphaned and unresolved notes, filters, and numbers from the full ordering | `[Coverage: UNIT]` | `test/features/annotations/annotations_panel_test.dart` |
| Visibility persists through the session and defaults to shown | `[Coverage: UNIT]` | `test/features/annotations/annotation_export_visibility_test.dart` |
| The visibility toggle has a writer at all, and is independent of the panel | `[Coverage: UNIT]` | `test/features/annotations/annotation_panel_visibility_test.dart` — it shipped in 5.9.1 with no control; this pins that it has one |
| The panel opens with **zero** annotations, keeping its empty state reachable | `[Coverage: UNIT]` | `test/features/viewer/widgets/bottom_dock_test.dart` — verified red against the `isNotEmpty`-only rule before it was made green |
| Closing the panel does not delete the notes, and stays closed as notes are added | `[Coverage: UNIT]` | same file — every other closable dock panel clears what it displays; this one must not |
| The three new actions are in the menus, and only the panel toggle is palette-only | `[Coverage: UNIT]` | `test/core/shortcuts/` conformance — the Edit-menu assertion flipped deliberately |
| **The selected lane resolves by `fullPath`, and a `signalRef` never resolves** | `[Coverage: UNIT]` | `test/services/waveform_geom/single_selected_row_id_test.dart` — the fixture's `signalRef` and `fullPath` are deliberately unlike, because one where they coincided would pass against the bug |
| The band confine control appears for a real selection | `[Coverage: UNIT]` | `test/features/annotations/annotation_band_interaction_test.dart` — its seed said `ref_data` until 2026-08-13, so the test and the code agreed with each other and both disagreed with the app |
| A row can be deleted from the panel, including an **orphan** with no balloon | `[Coverage: UNIT]` | `test/features/annotations/annotations_panel_test.dart` |
| A row collapses and expands the note on canvas | `[Coverage: UNIT]` | same file — until now only the walkthrough could ever set `collapsed: true` |
| An adopted note's menu offers duplicate, not edit, and still offers delete | `[Coverage: UNIT]` | same file |
| The ⋮ opens on `pumpAndSettle` alone | `[Coverage: UNIT]` | same file — the absence of a 300 ms pump *is* the assertion that the button is no longer inside the row's double-tap target |
| `setAnchorTime` moves to an exact tick, clamps out-of-range, translates a band, and **re-captures the witness** | `[Coverage: UNIT]` | `test/features/annotations/annotation_shapes_test.dart` — the same trap the nudge documents |
| Canvas, panel and SVG share one drift colour | `[Coverage: UNIT]` | `core/theme/annotation_colors.dart` is the single definition; `test/services/export/` pins the emitted value |
| Whether the amber legend is noticed where it sits | `[Coverage: MANUAL]` | Step 29 — a tooltip on a filter chip is a judgement about where a reader looks |
| The shipped example opens **not** drifted, re-derived against its committed trace | `[Coverage: UNIT]` | `test/examples/annotations_demo_session_test.dart` — reading the witness back out of its own JSON cannot catch a wrong value |
| Every balloon grabbable on a real canvas regardless of count and position | `[Coverage: MANUAL]` | The widget harness has no `Listener` ancestor, no `Scrollable` and therefore no gesture arena; it did not reproduce this class of bug and should not be trusted to |
| Annotations present in an exported PNG at each pixel ratio | `[Coverage: MANUAL → INTEGRATION candidate]` | Needs a real `RepaintBoundary` capture |
| Panel row tap centres the view | `[Coverage: MANUAL]` | The unit test is present but **skipped**: the tap does not reach the row's `InkWell` in the harness though it works in the app |

---

## 22.29 The `.wavecruxpack` share bundle (Open Core)

**What it does.** `File ▸ Share Annotated Waveform…` writes one self-contained
file: the annotated view, the waveform excerpt those notes actually refer to, a
preview image, and a README naming the download page. Opening one restores the
whole annotated view on a machine that has never seen the original dump.

**Why it exists.** A bare `.wavecrux` references a dump the recipient does not
have, so it opens to nothing. The pack is the first WaveCrux artifact that is
self-contained and small — the property that lets it travel. The **PNG** is
what circulates and needs no install; the **pack** is what makes the recipient
install WaveCrux to step through the notes.

**Setup.** Open `examples/annotations/annotations-demo.wavecrux` (the §22.28
fixture, copied somewhere scratch) so there are annotations to share.

### Sharing

1. **File ▸ Share Annotated Waveform…**. It is in the File menu's Export group
   and in the command palette; it is deliberately **not** on the toolbar and
   has **no keyboard binding** — the one action that sends design data off the
   machine should not be reachable by a mis-hit chord.
2. The **disclosure dialog** appears *before* the save dialog. Read it, because
   it is the feature:
   - **Time range** — the annotated span with ~20% context either side, and the
     text says so. With no annotations at all it falls back to the visible
     range and says *that* instead.
   - **Signals** — every signal **path**, listed, scrollable. Not a count. If
     this ever degrades to "12 signals", the disclosure has stopped disclosing.
   - **Names embedded in the annotations** — the distinct authors, with a
     **Strip author names** checkbox. With unattributed notes the checkbox is
     absent rather than inert.
   - **Size** — roughly what the bundle will be, before compression.
3. **Cancel.** Nothing is written and no save dialog appears.
4. Re-open it, tick **Strip author names**, confirm, and save as
   `review.wavecruxpack`.

### Opening — the loop that matters

5. **Move the pack to a machine (or a user account) that does not have the
   original dump**, or rename the original `.vcd` so it cannot resolve. This is
   the step that makes the test real: a pack whose session still names the
   sender's absolute path opens *perfectly* on the sender's machine and opens
   to nothing everywhere else.
6. **File ▸ Open…** and pick the `.wavecruxpack`. The annotated view comes back
   — the same signals, the same zoom, the same notes on the same edges — with
   the waveform coming out of the bundle.
7. The annotations carry **no author name** (step 4 stripped them) but all of
   their text.
8. Open the pack a second time. The previous extraction is **replaced**, not
   merged — a stale bundled dump would be a session silently one run out of
   date.
9. Rename the pack to `review.zip` and unzip it by hand. Four entries:
   `session.wavecrux`, `waveform.vcd`, `preview.png`, `README.txt`. The README
   is plain English (deliberately not localized — it travels to a machine whose
   locale we do not know) and names `wavecrux.app/open`.

### The guards

10. Show a very large signal set over a long span and invoke the share. Above
    the email-attachment threshold the dialog **warns** and still lets you
    proceed; past the hard ceiling it **refuses** with an explanation and never
    opens the save dialog. Nothing multi-gigabyte is ever produced silently.
11. Rename any text file to `.wavecruxpack` and open it: *"That file is not a
    WaveCrux pack"* — not a generic failure and not a complaint about a missing
    session.
12. Open a `.zip` that is a real archive but carries no `session.wavecrux`
    (rename any zip): *"This pack has no session inside it"*. The two cases are
    distinguished on purpose; they send a user looking in different places.

### File association

13. On macOS, a `.wavecruxpack` shows the WaveCrux document type in Finder's
    *Open With*. **Note the honest limit:** the type is *registered* (Info.plist
    `CFBundleDocumentTypes` + an exported `com.wavecrux.pack` UTI conforming to
    `public.zip-archive`), and delivery reaches the app the same way `.wavecrux`
    does today — via the CLI/deep-link path — so a cold Finder double-click has
    exactly the same status as it does for a session file, no better. Opening
    from **File ▸ Open…**, from Recent Files, or from `wavecrux
    review.wavecruxpack` on the command line is the tested path.

### 22.29.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| Write a pack, extract it elsewhere, load the session, and find the bundled dump | `[Coverage: UNIT]` | `test/services/pack/wavecrux_pack_round_trip_test.dart` — extraction happens in a directory the session has never seen, which is the only way this assertion means anything |
| Author names stripped without losing the annotations | `[Coverage: UNIT]` | same file, and again at the flow level in `test/features/pack/pack_share_flow_test.dart` |
| A pack with no preview still opens | `[Coverage: UNIT]` | same file — a failed capture must not cost the bundle |
| Reopening replaces the previous extraction rather than merging | `[Coverage: UNIT]` | same file — the stale-dump failure is silent and looks like a wrong waveform |
| A newer schema version degrades per the existing lenient policy | `[Coverage: UNIT]` | same file — unknown top-level keys dropped, `extensions` preserved |
| Not-an-archive, missing file, no-session, traversal, absolute path, oversized expansion | `[Coverage: UNIT]` | same file — each maps to its own failure kind, because one generic error would send users to the wrong place |
| Span = annotated window padded 20%, clamped to the trace; viewport fallback | `[Coverage: UNIT]` | `test/services/pack/pack_disclosure_test.dart` |
| A single note pads from the viewport rather than exporting one tick | `[Coverage: UNIT]` | same file |
| Size estimate scales with changes, signals and bus width; the warn threshold sits below the refuse threshold | `[Coverage: UNIT]` | same file — an unreachable warning is a size guard with no gradient |
| The disclosure lists signal **paths**, names the authors, warns on size, and refuses past the ceiling | `[Coverage: UNIT]` | `test/features/pack/pack_share_flow_test.dart` |
| The bundled session's `sourceFilePath` is the relative bundled dump and never an absolute sender path | `[Coverage: UNIT]` | same file — verified red against the un-rewritten code before it was made green |
| `pack.exported` recorded once, with no properties | `[Coverage: UNIT]` | same file |
| A bare positional `.wavecruxpack` routes to the session path, not the waveform parser | `[Coverage: UNIT]` | `test/services/cli/cli_args_test.dart` |
| The preview PNG actually contains the annotated render | `[Coverage: MANUAL]` | Needs a real `RepaintBoundary` capture — the same gap §22.28 names for annotated PNG export |
| Opening a pack on a machine without the original dump | `[Coverage: MANUAL]` | The unit round-trip extracts to an unrelated directory, which models it; it cannot model a second machine's filesystem, its permissions, or a quarantine flag |
| Finder / Explorer association and the *Open With* entry | `[Coverage: MANUAL]` | Declared in platform manifests; no harness observes the OS launch services database |
| `pack.opened` reaching the ingestion Worker | `[Coverage: MANUAL]` | The catalog conformance test pins the name and shape; delivery is verified with the rest of telemetry |

---

## 22.30 Arrow and band authoring (Open Core)

**What it does.** 5.9.1 built all three annotation shapes in the model but the
authoring gestures only produced callouts. Arrows are now drawn, bands are
resized and re-scoped in place, and a selected annotation's anchor moves by
keyboard.

**Setup.** The §22.28 fixture, `examples/annotations/annotations-demo.wavecrux`,
copied somewhere scratch.

### Arrows

1. **Alt/Option-click** a lane: a callout, as before.
2. **Alt/Option-*drag*** on a lane: an arrow. The anchor is where the press
   landed and the head follows the pointer — same modifier, same anchor, and
   the shape falls out of whether you moved. No mode switch, no toolbar.
3. Release after moving only a pixel or two: **nothing is created**. A
   zero-length arrow is indistinguishable from the dot already drawn at its
   anchor, so it would be litter the user cannot see well enough to delete.
4. Draw a real arrow, then press **⌘Z once**. The whole thing goes — the create
   and the drag are one undo step, not two.
5. An arrow opens no text editor and survives the empty-note sweep that
   discards an abandoned callout. An arrow with no words is the shape working.

### Bands

6. **Shift+drag a time range on the canvas** — the grey selection zone, the
   same one zoom-to-selection uses — then **Edit ▸ Annotate Selected Range**. A
   full-height band appears over exactly that zone with the measured delta
   pre-filled, and its editor opens.

   *This is the route to check.* Until 2026-08-13 a band could only be made
   from the canvas **long-press** menu, which nobody performs with a mouse —
   and right-click cannot host that menu because right-click is already
   secondary-cursor placement. So the region gesture the app already had and
   the band that describes a region were not connected to each other.
7. With no drag selection, the same action falls back to **both cursors**, and
   with neither it says which is missing rather than doing nothing. A backwards
   drag (right to left) normalises rather than producing an inverted band.
8. **Confining a band to one lane stays a canvas gesture**: long-press a lane ▸
   *Annotate Range on This Lane*, or use the band's own **⌄** toggle with
   exactly one signal selected in the signal list. "Which lane" is a question
   only a pointer position or a selection answers, so it has no menu form.
8b. **A band carries its panel number as a badge**, at its top-left. Make two
    overlapping bands and check you can tell which row is which: before
    2026-08-14 a band had no badge and its label may be empty, so two of them
    were indistinguishable.
8c. **Edit a band's text.** Its label is an editable field like a balloon's —
    including the measured delta pre-filled at creation, which exists to be
    replaced with what the measurement *means*. Bands never received the
    editing flag until 2026-08-14, so that had never once worked.
9. **Drag either edge.** Only that edge moves; the opposite one stays put —
   and it lands **where the pointer did**. Drag slowly, in many small movements
   rather than one flick: until 2026-08-13 the edge computed its new tick from
   the *already-moved* anchor while the travel kept accumulating, so it
   accelerated away under the pointer and 48 px of drag landed 390 ticks out.
   A single-move `tester.dragFrom` could not see it; a real hand always could.
10. While an edge is held, the band shows its **span, live**, in the file's
    timescale. That number is why somebody drew the band; reading it off the
    ruler mid-drag is not something anyone manages.
11. Drag one edge **past** the other. The band inverts and keeps following your
    pointer — the handle you are holding must not jump to the other side.
12. Release, then **⌘Z once**: the whole drag reverts, not the last pixel.
13. Select exactly one signal in the signal list, then press the band's
    **⌄ toggle**: the band confines itself to that lane. Press **⌃** on a lane
    band: it goes back to full height. Its **start and end never move** —
    scope is presentation, not identity.
14. With zero or several signals selected, a full-height band offers **no**
    confine control. "The selected lane" has no answer then, and choosing one
    would attach the band to a signal nobody named.

### Keyboard nudge

15. Click any annotation: it gets a **ring** (on the dot) or a **thicker
    border** (on a balloon). That is the selection the keyboard acts on. A note
    can be both selected and drifted, and the two stay separately legible.
16. **⌥←/⌥→** move the anchor one tick. **⌥⇧←/⌥⇧→** jump to the adjacent
    transition on that signal.
15. **The nudged note must NOT go drifted.** The witness is re-captured as the
    anchor moves. Without that, adjusting a note would flag it — and the drift
    badge would come to mean "somebody touched this" rather than "the design
    changed", which is the whole feature.
16. Nudge a note past the last transition on its signal with ⌥⇧→: it **holds
    position** and the viewport does not pan. Falling through to the arrow-key
    pan would look like the waveform jumped sideways for no reason.
17. Nudge a **band**: it translates, keeping its width. A band's anchor is the
    window; the edges are what you drag.
18. With no annotation selected, bare ←/→ still pan as always. The nudge
    bindings require Alt, which the pan activators require to be up.

### 22.30.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| An arrow is created through the same anchor path as a callout, witness included | `[Coverage: UNIT]` | `test/features/annotations/annotation_shapes_test.dart` |
| An empty arrow survives the discard-if-empty sweep that removes an empty callout | `[Coverage: UNIT]` | same file |
| Create + drag is one undo step; an abandoned draw leaves the undo stack untouched | `[Coverage: UNIT]` | same file — the abandoned case removes *inside* the open transaction, so no ⌘Z resurrects it |
| Band defaults to full height; can be confined at creation | `[Coverage: UNIT]` | same file |
| Each edge moves independently; inversion does not swap the handles | `[Coverage: UNIT]` | same file |
| **A many-move drag lands where the pointer did** | `[Coverage: UNIT]` | `annotation_band_interaction_test.dart` — the origin tick is snapshotted at gesture start; the pre-existing multi-move test asserted only that the edge *moved*, which the compounding bug satisfied |
| A band spans the Shift-drag selection, normalises a backwards one, and falls back to the cursors | `[Coverage: UNIT]` | `annotation_shapes_test.dart` |
| A band carries its panel number, and its text is editable | `[Coverage: UNIT]` | `annotation_band_interaction_test.dart` — the editing flag was never passed to bands, so this is behaviour that had never worked rather than a regression |
| Committing text un-collapses the note | `[Coverage: UNIT]` | `annotation_panel_canvas_wiring_test.dart` |
| The balloon folds itself back from the canvas | `[Coverage: UNIT]` | same file — `collapsed: true` previously had one writer, the walkthrough |
| Editing an orphan shows its signal first; editing a not-in-file note explains rather than doing nothing | `[Coverage: UNIT]` | `annotations_panel_test.dart` |
| Scope toggles both ways without moving the span | `[Coverage: UNIT]` | same file |
| Nudge moves one tick, steps to the adjacent edge, and holds when there is none | `[Coverage: UNIT]` | same file |
| **A nudged note reports resolved, not drifted** | `[Coverage: UNIT]` | same file — the witness re-capture, and the reason the nudge lives on the authoring notifier rather than on the plain one |
| A band nudge translates and keeps its width | `[Coverage: UNIT]` | same file |
| Edge handles drive the right end, one undo step, and select the band | `[Coverage: UNIT]` | `test/features/annotations/annotation_band_interaction_test.dart` |
| The span readout appears only while an edge is held | `[Coverage: UNIT]` | same file |
| The toggle confines and un-confines, and is absent without a single selected lane | `[Coverage: UNIT]` | same file |
| Alt-drag on a real canvas produces an arrow rather than moving the cursor | `[Coverage: MANUAL]` | The harness has no `Listener` ancestor and no gesture arena — the same gap §22.28 names. The arena is exactly what decides between the cursor drag and the annotate drag |
| ⌥/⌥⇧ + arrow reaching the viewer's global key handler | `[Coverage: MANUAL]` | Handled on `HardwareKeyboard`, outside the focus chain; no widget test drives real modifier state through it |
| A band edge is grabbable at a realistic zoom and band width | `[Coverage: MANUAL]` | The handle is 10 px inside the band's own bounds; whether that is enough is a pointing-device question |

---

## 22.31 Annotations in SVG export (Open Core)

**What it does.** Annotations now appear in exported SVG, and the export
dialog's **Time range** and **Signals** selectors are finally obeyed by that
format.

**Why SVG needs its own work.** PNG gets the overlay for free — it is a
`RepaintBoundary` capture and the annotations are widgets inside it. SVG is
hand-emitted from signal data, so every balloon, leader, arrowhead and band has
to be written out explicitly.

**The honesty fix this completes.** §22.28 step 21 disabled Time range and
Signals for PNG, because a screen capture cannot honour them. It left SVG's fix
to here — and SVG *can* honour them, because `exportSvg` takes its signal group
and time mapper as parameters. Until now it ignored both and read the live
providers, so "Full simulation + All signals + SVG" silently produced the
current viewport.

### The selectors

1. Zoom into a slice of a trace and hide most signals. **Export → SVG →
   Visible + Visible Signals Only.** Open the file: it shows the slice and the
   displayed lanes, as before.
2. Repeat with **Full Simulation + All Loaded Signals**. The document now
   covers the whole trace and every loaded signal — more content than is on
   screen, which is the thing no other export path can do. Its **height** grows
   with the lane count; the width is fixed, and that is fine because a vector
   reader zooms.
3. Confirm the same two selectors still produce matching content for VCD, so
   one control does not mean two things depending on format.

### The annotations

4. Annotate a waveform with a callout, an arrow and a band, then export SVG and
   open it **in a browser**. All three are drawn: balloon with its numbered
   dot, arrowhead pointing back at its anchor, shaded band with its label.
5. A **collapsed** note exports as a numbered dot, not a balloon.
6. A **drifted** note exports with a dashed leader and the same amber the
   canvas uses. Screen and document must agree about which claims no longer
   hold.
7. **Orphaned and unresolved notes draw nothing**, exactly as on canvas. A
   static document has no panel to route them to.
8. Untick **Include annotations**: the waveform exports and the notes do not.
   Toggling annotation visibility off in the session does the same — what you
   exported is what you were looking at.

### Escaping — the failure that is total and silent

9. Write an annotation whose body contains `a < b && c > "d"` and export SVG.
   **Open it in a browser.** It must render. One unescaped `<` produces a
   document that displays nothing at all, and a shared SVG is opened in a
   browser more often than anywhere else.
10. Write a note longer than the balloon: it **wraps** across up to four lines
    and ends in an ellipsis. It must not be cut to ten characters — that is the
    signal-label rule, and a body is prose the user expects to read back.

### 22.31.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| Each shape emits its own SVG structure (balloon, arrowhead path, band rect, numbered dot) | `[Coverage: UNIT]` | `test/services/export/svg_annotations_test.dart` |
| Drifted styling: dashed leader and the canvas's amber | `[Coverage: UNIT]` | same file — the two surfaces must not disagree about drift |
| Orphaned / unresolved draw nothing; a note on an absent row is skipped | `[Coverage: UNIT]` | same file |
| All five XML metacharacters escaped in bodies and band labels | `[Coverage: UNIT]` | same file |
| A body containing `</svg><script>` leaves exactly one closing tag | `[Coverage: UNIT]` | same file — the hostile case, and the one that fails silently |
| A long body wraps rather than being truncated to the label width | `[Coverage: UNIT]` | same file |
| "Full Simulation" hands the emitter the whole trace, not the viewport | `[Coverage: UNIT]` | `test/features/viewer/providers/svg_export_selectors_test.dart` |
| "All Loaded Signals" hands it more lanes than are displayed | `[Coverage: UNIT]` | same file |
| Document height grows with the lane count and keeps a floor | `[Coverage: UNIT]` | same file |
| The checkbox and the session visibility toggle both gate annotations | `[Coverage: UNIT]` | same file |
| The exported SVG renders correctly in a browser | `[Coverage: MANUAL]` | No harness parses the output as XML or paints it; the escaping tests assert the bytes, not a renderer's verdict |
| Wrapped text stays inside its balloon at real font metrics | `[Coverage: MANUAL]` | The wrap is computed from a character budget, since SVG has no text flow — whether it fits is a font question |

---

## 22.32 Walkthrough mode (Open Core)

**What it does.** Steps through a tab's annotations in time order — centring
each one, expanding it, folding the one before — by key, by menu, or
automatically on a timer.

**Why it matters.** This is what turns an annotated waveform from a picture
into a **document somebody else can drive**. The author's notes arrive in the
order the events happened, one at a time, without the reader having to know
where to look. It is also, almost verbatim, the interaction an EDU pack wants
for a guided lab.

**Setup.** `examples/annotations/annotations-demo.wavecrux`, copied somewhere
scratch. Add a couple more notes so there are at least three.

### Stepping

1. Press **`]`**. The first annotation in time order is centred and expanded.
   Press it again: the second, and the first folds back to its dot.
2. Press **`[`** with no tour running: it opens at the **last** note. Either
   bracket starts the tour from the end it points away from.
3. Keep pressing `]` past the last note. It **wraps to the first and says so**
   — a brief notice, not silence. Silence here is the defect: a reader who
   lands back on note 1 with no signal reads it as the key having done nothing
   and presses it again.
4. `[` past the first wraps to the last, with the matching notice.
5. Zoom in before stepping. Each landing **centres the tick and keeps the
   zoom** — the same recipe the panel's row tap uses.
6. Put the annotated signal off the bottom of the viewport, then step to a note
   on it. The lane **scrolls into view**.
7. Step, then press **⌥→**. The nudge moves the note the tour is on — the
   walkthrough, the panel and the keyboard all agree about which note is "the"
   one right now.

### The undo stack — the quiet one

8. Author a note, then step through the whole tour a few times, then press
   **⌘Z once**. It must undo **your last real edit**, not a fold from the tour.
   Reading is not editing; a tour that recorded every expand/collapse would put
   twenty entries between the reader and the author's work.

### Automatic playback

9. Open the **Annotations** panel. Press **▶**. It steps **immediately**, then
   on the dwell — a transport that does nothing for four seconds reads as
   broken.
10. Change the dwell dropdown mid-playback: the new interval takes effect
    **now**, not after the current one elapses.
11. **⏸** stops the timer and keeps the position; **⏹** stops and forgets it,
    and the stop button disappears when there is nothing to stop.
12. The three walkthrough commands are in the **Navigate** menu and the command
    palette, and are **absent entirely** when the tab has no annotations — the
    same structural hide `stopStreaming` uses, rather than three permanently
    greyed rows in every session that never annotates.
13. Rebind `]` in Settings ▸ Keyboard: the new chord steps and the old one does
    not. They are ordinary ShortcutActions, unlike the ⌥-arrow anchor nudge
    (§22.30), which is deliberately canvas-local.

### In a collaborative session

14. Join a session as a follower, then step the walkthrough. The local view
    **detaches from follow** rather than being dragged back by the presenter —
    driving the tour is reading at your own pace, and a viewport that snapped
    away from the note you just stepped to would make the feature unusable
    mid-session.

### 22.32.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| Steps in **time** order, not insertion order | `[Coverage: UNIT]` | `test/features/annotations/annotation_walkthrough_test.dart` — seeded deliberately out of order |
| The first backward step opens at the end | `[Coverage: UNIT]` | same file |
| Wrapping both directions sets the flag the UI announces from | `[Coverage: UNIT]` | same file — the flag lives in state because the notifier has no `BuildContext` |
| An ordinary step does not flag a wrap | `[Coverage: UNIT]` | same file — otherwise the notice fires every step and is ignored |
| Expand/collapse handoff between consecutive notes | `[Coverage: UNIT]` | same file |
| **A whole tour leaves the undo stack where it was** | `[Coverage: UNIT]` | same file — the folds run inside a transaction that is then cancelled |
| Centring keeps the zoom; the row is scrolled; the note is selected | `[Coverage: UNIT]` | same file |
| Playback steps immediately, honours the dwell, and pauses / stops / toggles | `[Coverage: UNIT]` | same file, under `fakeAsync` |
| A changed dwell restarts the ticker rather than waiting out the old one | `[Coverage: UNIT]` | same file |
| The actions are hidden without annotations and appear with them | `[Coverage: UNIT]` | `test/core/shortcuts/` conformance — descriptor visibility, not the panel |
| `]` / `[` actually reaching the handler through the focus chain | `[Coverage: MANUAL]` | These are focus-`Shortcuts` bindings; no widget test drives real key events through the viewer's whole tree |
| Follow-detach during a live collaborative session | `[Coverage: MANUAL]` | Needs two clients; the unit test asserts the call, not the session behaviour |
| Whether the dwell defaults feel right on real notes | `[Coverage: MANUAL]` | A judgement about reading speed, which is why it is configurable |

---

## 22.33 Session annotation layers and adoption (Open Core)

**What it does.** When a collaborative session ends, the notes it produced are
offered for adoption. Kept ones land as a **named, disposable layer** —
*"Annotations · 2026-08-13 · 3 participants"* — that toggles and deletes as a
unit, with each note's session colour frozen into the document.

**Why a layer and not loose notes.** Twelve notes by three people dropped into
somebody's document are twelve notes they will never confidently delete, because
they cannot tell which came from where. Naming the group is what makes *Keep
all* a safe answer a week later.

**Why the colour is frozen.** In a session a note's colour comes from its
author's palette **slot** — a per-session 0–7 index. Carrying the index into the
document would make last week's notes silently recolour and misattribute
themselves the moment a new session handed slot 3 to somebody else. The index is
turned into an RGB value exactly once, at adoption, and never persisted.

**Setup.** Two clients on the same waveform, as in the Pro overlay's collaboration guide. Write notes as both
participants, then end the session.

### The prompt

1. End the session. A **strip appears above the canvas**, not a dialog: *"N
   annotations were made in this session by M people. Keep them?"* with **Keep
   all**, **Keep only mine**, **Discard**, **Don't ask again** and a **✕**. It
   is non-modal on purpose — a dialog thrown up the instant a meeting ends lands
   on somebody already reaching for the next thing.
2. **Keep all.** Every note stays, grouped under one layer named for the date
   and the participant count.
3. Repeat with **Keep only mine**: the others go, and yours are *still* a layer
   — they were written in that meeting whoever wrote them.
4. With a session where every note is yours, **Keep only mine is absent**, not
   greyed. It would be *Keep all* pressed twice.
5. **Discard**: nothing is kept, and no layer is registered.
6. **✕ keeps everything.** This is the one behaviour in the section worth
   checking deliberately, because it looks like a cancel. Silently discarding
   destroys the meeting's output; silently keeping merely surprises somebody;
   so a closed prompt takes the branch that does not lose work irreversibly. A
   kept layer deletes with one control. A discarded one is gone.
7. **Don't ask again** keeps this session's notes *and* sets the preference.
   End another session: the notes are adopted with no prompt at all. The
   preference can only ever mean **keep** — a box ticked once, weeks ago, must
   not silently throw away a meeting.
8. A session that produced **no** notes shows no strip.

### The layer in the panel

9. Open the **Annotations** panel. Your own notes are listed first, ungrouped;
   the adopted ones sit under the layer's name.
10. Press the layer's **eye**: its notes vanish from the canvas and the
    walkthrough steps past them — but the panel **still lists them**. A layer
    you cannot see and cannot find again is a layer you have lost.
11. Press it again: they come back.
12. Press the layer's **trash**: the group and its notes go together, with an
    undo toast. **⌘Z once** brings back every note, not the last one.
13. Delete every note in a layer individually. The heading disappears with the
    last one rather than lingering over nothing.

### Attribution is read-only

14. Double-click one of *your* notes in the panel: the inline editor opens.
15. Double-click an **adopted** one: it does not. There is a small lock beside
    the author and a **Duplicate as mine** action instead, so the missing
    editor has a visible reason rather than reading as a bug.
16. Press **Duplicate as mine**. A *new* note appears with the same text, your
    name, no layer and no frozen colour. That is the honest way to build on
    somebody's point — a new note with a new author, never an edit under the
    original name.
17. Delete an adopted note outright: allowed. Hiding and deleting are not the
    same as putting words in somebody's mouth.

### It survives the file

18. Save, close and reopen the `.wavecrux`. The layer, its name, its visibility
    and every frozen colour come back.
19. Open the same document in a build that predates layers (or hand-edit the
    `annotationLayers` key out): the notes are still there, as an **unnamed
    group**. Never lost.

### The colour freeze — the one that fails a week later

20. Adopt a layer, noting the colour of a colleague's note. Start a **second**
    session in which the palette slots land differently, and adopt from that
    too. **The first layer's colours must not have moved.** If they have, last
    week's notes are now attributed to this week's people, and nothing on
    screen says so.

### 22.33.1 Automation Assessment

| Test | Coverage | Notes |
|---|---|---|
| Adoption stores the **resolved** colour, never the palette slot | `[Coverage: UNIT]` | `test/features/annotations/annotation_layers_test.dart` — the feature's central rule |
| A second session reassigning a slot does not move the first layer's colours | `[Coverage: UNIT]` | same file — the failure is silent and arrives a week later |
| An author the roster no longer knows adopts unattributed rather than in a borrowed colour | `[Coverage: UNIT]` | same file |
| Keep all / Keep only mine / Discard, and **dismiss keeps everything** | `[Coverage: UNIT]` | same file, and at the widget level in `annotation_adoption_prompt_test.dart` |
| "Keep only mine" is absent when every note is already yours | `[Coverage: UNIT]` | `annotation_adoption_prompt_test.dart` |
| "Don't ask again" keeps and persists, and the prompt then never appears | `[Coverage: UNIT]` | same file |
| Adoption is one undo step; your own note is not duplicated by it | `[Coverage: UNIT]` | `annotation_layers_test.dart` |
| A layer hides from the canvas without leaving the panel; deletes as a unit; an empty layer shows no heading | `[Coverage: UNIT]` | same file + `annotations_panel_test.dart` |
| An adopted note offers **Duplicate as mine** instead of editing; the copy carries your name, no layer and no frozen colour | `[Coverage: UNIT]` | `annotations_panel_test.dart` |
| The registry round-trips, emits no key when empty, tolerates a malformed entry, and does not move the schema version | `[Coverage: UNIT]` | `test/services/session/session_annotations_round_trip_test.dart` |
| A v4 document with `layerId`s and no registry loads as an unnamed group | `[Coverage: UNIT]` | same file — the cross-version case, both directions |
| A session ending offers its notes, resolving "mine" by participant id and the slot from the roster | `[Coverage: UNIT]` | `test/services/collaboration/collab_viewer_bridge_test.dart` — the roster is gone the moment the session is |
| Two real clients, two palettes, and colours that still look right next week | `[Coverage: MANUAL]` | Steps 20 above; no harness runs two sessions against two real palettes |
| Whether the strip is noticed at all when a meeting ends | `[Coverage: MANUAL]` | A non-modal prompt trades interruption for the risk of being missed; that trade is a judgement about attention, not a test |

---

## 23. Sign-off checklist

Use this as the gate before any release ships. Tick each box; record the build/version, the platform tested, and the date.

### 23.1 Per-platform smoke

- [ ] Linux desktop — full feature pass
- [ ] macOS desktop — full feature pass
- [ ] Windows desktop — full feature pass
- [ ] Web — file loading, disabled-feature messaging, basic rendering
- [ ] iPad — adaptive layout, file loading via share sheet, Stage, FSM
- [ ] iPhone — adaptive layout, gestures, memory management
- [ ] Android tablet — same as iPad
- [ ] Android phone — same as iPhone

### 23.2 Per-feature

- [ ] Diagnostics surfaces — Tab Diagnostics drawer (3 sections), App Diagnostics dialog, Pane Render Stats popover, Copy Report
- [ ] Signal search — direction filtering, prefix syntax, type filtering
- [ ] SPI decoder — known-answer, all four CPOL/CPHA modes
- [ ] I²C decoder — known-answer, NACK error, repeated START
- [ ] UART decoder — known-answer, parity error, framing error, auto-timescale
- [ ] AXI4-Lite decoder — known-answer reads/writes, error responses
- [ ] APB decoder — known-answer, optional signals, violations, multi-instance
- [ ] Transaction overlay — colors, error styling, tap-to-jump, multi-decoder
- [ ] Transaction table — sort, filter, click-to-jump, CSV export
- [ ] Waveform diff — match colors, XOR lanes, navigation, cleanup
- [ ] X-Trace — causal chain, markers, state cleanup
- [ ] Switching activity — counts, clock detection, heatmap
- [ ] Pattern search — builder, expression mode, X/Z handling
- [ ] Process filter — translation, kill recovery, timeout
- [ ] GTKWave session import — signals, groups, formats, colors, markers, translate refs
- [ ] Cocotb log — load, click-to-jump, filtering, stress
- [ ] Streaming VCD — pipe mode, stdin mode, EOF handling
- [ ] FSDB error path
- [ ] Remote control API — all commands, multi-connection, lifecycle
- [ ] Flutter Web — disabled features messaged correctly
- [ ] Help links — all wired
- [ ] Stage — built-in primitives + 4 board widgets, signal-drag from both sources, save/restore, device gating
- [ ] RVFI Commit Inspector (open core, §10B.1) — auto-bind all 21 `rvfi_*` pins, four views off `riscv_rvfi_retire.vcd`, all six checker rules fired by their corrupted fixtures, clickable violations, reduced-binding-set degradation **and** the "not checked" line, no cap / badge / nag
- [ ] Pipeline Diagram (open core, §10B.2) — the staircase off `riscv_pipeline_5stage.vcd` with its load-use stall, back-to-back forward and branch flush; cell click → cursor tick; only the enabled stages' pins listed; **and the paired `riscv_pipeline_defeat.vcd` drawing the identical grid behind a low-confidence banner and a dimmed panel**, which is the whole requirement
- [ ] FSM — graph, active-state highlight, click-to-jump
- [ ] RTL source annotation — annotations, navigation, device gating
- [ ] Live statistics strip — toggle, gating (desktop only), session persistence

### 23.2.b Workspace, formats, navigation, discoverability (§16–22)

- [ ] Welcome screen — recent files, drag-drop, stale-entry handling
- [ ] Settings screen — all sections, theme switch, persistence, locale sweep
- [ ] Auto-reload on file change — Prompt, Auto, Off modes; deletion notification
- [ ] Display formats — every format (binary/hex/oct/dec-signed/dec-unsigned/ASCII) on `vcd/vector_formats.vcd`; x/z propagation; signed two's-complement; per-signal persistence
- [ ] Cursors — primary, secondary, delta, frequency
- [ ] Named markers a–z — placement, jump, save/restore
- [ ] Time ruler — auto-scaled tick generation across zoom levels
- [ ] Q/E next-prev transition keyboard navigation
- [ ] Command palette — open, fuzzy filter, keyboard navigation, locale sweep, diagnostics gating
- [ ] Export VCD — round-trip (export → re-parse → values match)
- [ ] Export PNG — at 1×/2×/3× resolution
- [ ] Export SVG — text remains real text
- [ ] Clipboard — Copy Value, Copy Full Path, Copy as JSON
- [ ] Desktop menu bar — all `ActionCategory` groups, file-dependent disable, locale sweep
- [ ] Mobile overflow action menu — bottom sheet (phone) / dropdown (tablet)
- [ ] Toolbar next/prev transition buttons
- [ ] `MobileMetrics` size compliance on touch
- [ ] Touch-target ≥ 44 × 44 dp regression sweep
- [ ] Long-press = right-click rule on every key row
- [ ] Inner-onTap-after-context-menu-dismissal regression check
- [ ] Tooltip vs context-menu trigger-mode regression check
- [ ] Status-bar panel chevrons — direction-flip, gating on phone
- [ ] Splitter affordance + bottomMinSize + force-hide at phone widths
- [ ] Status-bar overflow at 320 dp width
- [ ] Text-scaling clamp at 0.85×/1.5×
- [ ] Truncated-text tooltip + context-menu header

### 23.3 Edge cases

- [ ] Empty VCD
- [ ] X/Z-only signals
- [ ] Decoder on wrong signals (no crash)
- [ ] Remove and re-add decoder
- [ ] Open new file with analysis state active (state cleanup)
- [ ] Malformed VCD corpus
- [ ] Vendor-specific VCDs
- [ ] Deep hierarchy + identifier edge cases

### 23.4 Performance

- [ ] Desktop 1000 signals at 60 fps
- [ ] Tablet 500 signals at 60 fps
- [ ] Phone 100 signals smooth
- [ ] Parser benchmark within 10 % of baseline
- [ ] Render benchmark within 10 % of baseline
- [ ] Memory stable over 5-minute scroll session (regression auto-guarded by `integration_test/canvas/scroll_memory_soak_test.dart`; manual pass still confirms the Memory-tab UI values — see §13.6)

### 23.5 Cross-feature

- [ ] All Open Core decoders simultaneously
- [ ] Decoder + diff
- [ ] Decoder + X-Trace
- [ ] Decoder + pattern search
- [ ] Stage + FSM + RTL on desktop
- [ ] Baseline regression check
- [ ] Session round-trip including statistics strip and panel state

### 23.6 Final report

- [ ] Diagnostics report captured for each major fixture, archived under release version

---

## 24. Automation roadmap summary

Use this when planning integration test work — focus on the **High Priority** items first.

### 24.1 High priority — core regression catches

1. **Known-answer decoder fixture tests** (SPI, I²C, UART, AXI4-Lite, APB) — load fixture, apply decoder, assert decoded transactions match the `.expected_transactions.json` companion. End-to-end through the FFI boundary.
2. **UART auto-timescale regression** — load `1ps`-timescale UART VCD with no manual config, assert correct decoding.
3. **Open file → signal tree populates → add signal → waveform renders → cursor reads correct value** — the full pipeline that crosses FFI/Dart-fallback, providers, and CustomPainter.
4. **Session save/restore round-trip** — save with N signals + cursor + zoom + Stage + statistics-strip + per-signal display formats + named markers + panel sizes; reload; assert all state restored.
5. **Analysis state cleanup on new file load** — known regression area covering diff, X-Trace, pattern search, switching activity, FSM.
6. **Adaptive layout selection at each breakpoint** — phone/tablet/desktop boundary correctness.
7. **Direction filter chips with FST fixture having direction metadata** — known-answer.
8. **Cocotb log timestamp unit conversion (fs/ps/ns/µs/ms/s)** — easy to regress, hard to manually verify.
9. **Stage signal-drag from both tree and signal-list panel** — the two-source design is easy to regress to "only one works".
10. **GTKWave `.gtkw` import end-to-end** — signal list, groups, formats, colors, markers, translate-filter refs.
11. **VCD export round-trip** (export → re-parse → values match) — high-leverage regression catch for the value-encoding pipeline.
12. **Display-format coverage on `vcd/vector_formats.vcd`** — every format × x/z propagation rule, parameterized.
13. **Touch-target ≥ 44 × 44 dp regression sweep** — broad sweep across every interactive widget. Catches accidental hardcoded sizes.
14. **Long-press = right-click context-menu rule** — verify on signal-list, signal-tree, cocotb-log, transaction-table, canvas.
15. **Inner-onTap-after-context-menu-dismissal** and **Tooltip-trigger-mode regressions** — both are known regression areas with specific gesture-arena pitfalls.
16. **Status-bar overflow at 320 dp width** — every chrome `Row` survives without `RenderFlex overflowed` exceptions.
17. **Auto-reload (Prompt/Auto/Off) on file modification** — straightforward to mock with a temp file.

### 24.2 Medium priority — common workflows

- All decoder error-condition fixtures (parity, framing, NACK, SLVERR, protocol violation).
- Transaction table sort/filter/CSV export.
- Pattern search with X/Z values (no error, 0 matches).
- Remote control API command effects on viewer state.
- Diff cleanup on close.
- Multi-decoder simultaneous operation.
- Memory guard unload/reload cycle on mobile.
- Statistics strip session persistence + device-class gating.

### 24.3 Low priority or remain manual

- Visual rendering (XOR lanes, heatmap colors, transaction block labels) — golden image tests if regression-prone, otherwise manual.
- Touch gesture feel and responsiveness on physical devices.
- Cross-browser web rendering.
- Synopsys `fsdb2vcd` happy path (won't be in CI).
- SigRok bridge integration (depends on external project).

### 24.4 Hybrid candidates

- Memory tab values increase/decrease with file load.
- Frame time targets — automate the measurement, set thresholds with CI-hardware tolerance.
- Parser benchmark vs. baseline — assert within ±10 %, not absolute number.

### 24.5 Recommended initial integration test suite

1. Open VCD via test harness; verify signal tree population.
2. Add signals; verify waveform rendering against a golden screenshot.
3. Cursor navigation and value readout at known timestamps.
4. Zoom in/out and verify time axis scaling.
5. Session save/restore round-trip.
6. Protocol decoder end-to-end with `protocol/spi/generated/spi_basic.vcd` fixture.
7. Waveform diff with known divergence fixture pair.
8. Search for a signal by name and add it.
9. Keyboard shortcut navigation (next edge, previous edge).
10. Large file load — verify no timeout or crash.
11. APB decoder end-to-end with `protocol/apb/generated/apb_basic.vcd`.
12. Cocotb log correlation with `cocotb/basic_log.txt`.

CI strategy: run the integration suite on Linux desktop only (fastest, most stable target), only on merges to main (not every PR push). Mobile and cross-browser remain manual.

---

## Document history

- **v1.0** (2026-05-03): consolidated from per-phase verification guides + master verification document. First canonical pre-release reference for the open-core viewer.
- **v1.1** (2026-06-11): added §22.17 Beta build expiry — per-release `--dart-define=BETA_EXPIRY` hard expiry with the active / expiring-soon banner / expired blocking-modal paths, the `kBetaPeriod = false` no-op path, and the §22.17.1 Automation Assessment; matching §12.13 checklist group.
- **v1.3** (2026-07-12): §22.17 expired modal gained a **Quit WaveCrux** action (`betaExpiryExitApp` seam) — fixes the Windows/Linux custom-chrome defect where the modal barrier blocked the in-app title-bar close button, leaving the expired app with no visible way to exit; new `betaExpiryExpiredQuit` ARB key across en/zh_CN/zh/ja/ko; expired-path step 5 + Automation Assessment rows updated; matching §12.13 checklist bullet.
- **v1.2** (2026-06-19): added §22.23 Update mechanism (§10.9) — manifest fetch + notification banner (golden / dismiss / mandatory paths), manual Check-for-Updates (Help / palette / About), Settings → General auto-check toggle, malformed-manifest soft-fail, and the server-time clock-back hardening of §10.8 (also flipped the §22.17.1 clock-tampering row from "deferred" to "hardened"); committed `verification/fixtures/update/` manifest fixtures; §22.23.1 Automation Assessment; matching §12.19 checklist group.
