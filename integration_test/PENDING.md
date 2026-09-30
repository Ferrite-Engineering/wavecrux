# Open Core — Pending Integration Tests

This file is the queue of verification items that should ultimately be exercised by Flutter `integration_test/` tests against a fully-running app on a real device or simulator (option A in the test taxonomy). Each entry corresponds to a `[Coverage: INTEGRATION_TEST — pending]` marker in `verification/VERIFICATION_GUIDE.md` or `verification/VERIFICATION_CHECKLIST.md`.

The taxonomy is documented in `verification/VERIFICATION_GUIDE.md` §1.4. Until each item below is implemented as a real `integration_test/*.dart` file, it must still be exercised manually before sign-off.

## Why option A and not a widget test (option B)

A verification item belongs in this queue (option A) rather than in a widget-test file (option B) when at least one of the following is true:

- It exercises a real platform integration point that a widget test cannot mock convincingly (system file picker, system share sheet, secure storage, platform-channel notifications, OS-level memory pressure callbacks, file association handling, system menu bar interaction).
- It depends on a real waveform file being parsed end-to-end through the real `WellenProvider` FFI path, where mocking the `WaveformDataSource` would defeat the purpose.
- It exercises a touch gesture sequence whose behavior depends on real `GestureArena` resolution at real coordinates (pinch-zoom, two-finger pan, long-press → context menu) where Flutter's `WidgetTester` gesture simulation is not faithful enough.
- It exercises window-resize, orientation-change, or split-screen behavior that Flutter `WidgetTester` cannot reproduce.
- It is a per-platform smoke test where the act of launching the app on the platform is part of the test.

## Pending items

### Decoder integration (open-core decoders × real FFI parse + canvas rendering)

Each open-core decoder has full unit-test coverage (`test/services/decoders/<decoder>_test.dart`) of its decode logic against a fixture VCD. What's not covered: the full pipeline from picker → activation → real `WellenProvider` parse → transactions visible in the transaction-table panel and as overlays on the canvas.

- ~~SPI — picker → apply → real FFI parse of `protocol/spi/generated/spi_basic.vcd` → transactions render in the transaction-table panel and as overlay blocks on the canvas~~ — **DONE** (`integration_test/decoders/spi_integration_test.dart` — real FFI parse via `loadFixtureVcd`, picker activation via `activateDecoder`, 2 transaction rows asserted).
- ~~I²C — same pattern~~ — **DONE** (`integration_test/decoders/i2c_integration_test.dart` — same picker → real FFI parse → transaction-table pattern, 2 rows). The tap-to-jump-on-canvas-blocks gesture-arena interaction it also names is not decoder-specific — that behavior is tracked generically by the still-open "Tap transaction block → cursor jumps + viewport pans" bullet under Transaction overlay & table below.
- ~~UART — same pattern~~ — **DONE** (`integration_test/decoders/uart_integration_test.dart` — custom activation flow that sets `baud_rate = 1000000` in the config dialog before auto-bind, since the fixture's 1 Mbaud timing needs it; 3 transaction rows asserted).
- ~~AXI4-Lite — same pattern~~ — **DONE** (`integration_test/decoders/axi4_lite_integration_test.dart` — 4 transaction rows asserted).
- ~~APB — same pattern~~ — **DONE**, including the multi-instance half (`integration_test/decoders/apb_integration_test.dart` — single-instance case asserts 4 transaction rows; the "APB #1 + APB #2" case drives the decoder picker twice and asserts the two-instance `instanceNumber` invariant (1, then 2), distinct `ActiveDecoder.id`s, both instances independently decoding the fixture's 4 transactions, and 8 combined rows in the transaction table).

### Transaction overlay & table

- ~~Tap transaction block → cursor jumps + viewport pans (gesture-arena interaction)~~ — **DONE** (`integration_test/canvas/transaction_tap_test.dart` — taps a transaction overlay block on canvas and asserts cursor jumps to that time + viewport pans to keep the block visible).
- ~~Right-click X-valued signal → "Trace X Origin" context menu dispatch (gesture-arena + popup-menu interaction)~~ — **DONE** (`integration_test/canvas/x_trace_gesture_test.dart` — right-click (or long-press on touch) on an X-valued signal fires the context menu and asserts "Trace X Origin" entry is present and clickable).

### Streaming / interactive VCD

- ~~`--pipe <fifo>` mode: real FIFO + progressive parse + UI hierarchy population~~ — **DONE** (`integration_test/streaming/interactive_vcd_test.dart` — drives the same `_start(Stream<List<int>>)` code path that `startFromPipe` and `startFromStdin` delegate to, via the `@visibleForTesting startFromStream` seam on `StreamingSourceNotifier`. Verifies header parse → hierarchy population, first/second-half progressive `currentEndTime` extension with no source reload, LIVE badge visibility, and EOF → Idle transition).
- ~~Stdin mode: same behavior~~ — **DONE** (covered by the same `interactive_vcd_test.dart` via the shared `_start` path).
- [ ] Stop button finalizes and lets user browse received data — manual user-action verification path; the underlying `stop()` → Idle transition + post-stop browsability is covered by `streaming_source_provider_test.dart` and the EOF integration test.
- ~~Producer EOF → graceful finalize~~ — **DONE** (`integration_test/streaming/streaming_eof_test.dart` — partial value changes + close, asserts no crash, partial transitions preserved, LIVE badge clears, state returns to Idle).
- [ ] Producer emits malformed VCD partway → clear error, partial data preserved (covered by manual verification; the unit-test suite's parser-resilience tests document expected behavior).

### Remote Control API (real socket)

- ~~`wavecrux-ctl add-signal` end-to-end via real TCP socket → canvas updates~~ — **DONE** (`integration_test/remote_control/wcp_add_signal_cli_subprocess_test.dart` — spawns the real `tool/wavecrux_ctl` CLI as an OS subprocess via `Process.run` (`dart run bin/wavecrux_ctl.dart`) for both `load` and `add`, asserting exit code 0 + stdout, and that the signal lands in `signalGroupsProvider` — the canvas lane source. Complements the socket-level `wcp_add_signal_test.dart`, which drives the WCP protocol directly rather than through the CLI process).
- ~~All RPC commands (set cursor / set zoom / set marker / query value / remove signal / load file) end-to-end~~ — **DONE**. `set_cursor` (`wcp_set_cursor_test.dart`), `getValueAt`/`load` (`wcp_get_value_test.dart`/`wcp_load_test.dart`), and `set_viewport_range` (`wcp_set_viewport_range_test.dart`) were already covered. `zoom_to_fit`, `add_markers`, and `remove_items` — the three genuinely missing commands — are now covered by `integration_test/remote_control/wcp_zoom_marker_remove_test.dart` (one real-socket test exercising all three, asserting both response frames and the resulting `timeMapperProvider` / `markerStateProvider` / `signalGroupsProvider` state).
- ~~Multi-connection scenario over real sockets~~ — **DONE** (`integration_test/remote_control/wcp_multi_connection_test.dart` — opens two simultaneous real TCP client sockets against one running app instance and asserts `connectedClients` tracks both, each client's command responses are routed back to that connection only (no cross-talk), a server-broadcast event triggered by one client reaches both, both clients' commands land in the shared active-tab provider state, and `connectedClients` drops correctly as each socket disconnects).

### Flutter Web

> **CI:** the `integration_test/web/*` suite runs nightly in GitHub Actions via
> `.github/workflows/integration-web.yml` (headless Chrome + chromedriver,
> `flutter drive`, 05:30 UTC), and locally via `tool/run_web_integration_tests.sh`.
> That workflow now builds the `wellen_wasm` bundle from source first
> (`tool/build_web_wasm.dart`) so the suite runs against the crate at HEAD, and
> carries a second job (`widget-web`) that runs the `@TestOn('browser')` widget
> tests via `flutter test --platform chrome` (`tool/run_web_widget_tests.sh`) so
> `kIsWeb == true` branches are exercised in-process. Before this, the web tests
> existed but never executed anywhere (the desktop runner uses `flutter test`,
> which skips them via `!kIsWeb`) — which is how the web file-open hang shipped
> unnoticed.

- ~~File picker upload (real browser file API)~~ — **DONE** for the post-dialog pipeline
  (`integration_test/web/web_file_picker_test.dart` overrides `webFileLoaderProvider` with a
  `WebFileLoader` stub returning synthetic browser-API bytes and asserts the welcome screen
  routes them through `openFromBytes` to a `WellenWasmProvider`). A follow-up WebDriver variant that drives
  the native browser file chooser remains pending.
- ~~Drag-and-drop onto welcome screen (real DOM drag/drop)~~ — **DONE** for the post-drop
  pipeline (`integration_test/web/web_drag_drop_test.dart` invokes `WebDropZone.onFilesDropped`
  with synthetic bytes — the same bridge `_WebDropZoneState._onDrop` uses after
  `WebDropTarget.files` emits). The DOM-level `dragover`/`drop` listener attached by
  `WebDropTarget` is covered by the existing unit tests on `web_drop_target_impl.dart`.
- ~~**Cross-bridge equivalence (FFI vs WASM)**~~ — **DONE**
  (`integration_test/web/web_cross_bridge_test.dart`). Loads every fixture under
  `test/fixtures/{vcd,fst,ghw}` through `WellenWasmProvider` (WASM) in headless Chrome
  and asserts `valueAt()` / `changesInRange()` / `nextTransition()` / `prevTransition()`
  reproduce the committed `.expected.json` gold. FFI cannot run in a browser, so the FFI
  side is frozen ahead of time into those companions — `tool/generate_bridge_snapshots.dart`
  records the real `WellenProvider` (FFI) answers; `scalar_basics` / `deep_hierarchy` stay
  hand-authored Layer-2 gold (audited 0-mismatch). WASM == gold == FFI closes the loop, so
  any divergence pinpoints a marshalling-bridge bug. Fixtures are base64-embedded via
  `tool/generate_web_fixture_bundle.dart` (no `dart:io` in-browser). This sweep caught a
  latent gold error (`vector_formats` `valueAt(byte8,100)`) and a real-number formatting
  drift (`analog_real`), both now fixed. The earlier `web_file_picker_test` single-signal
  guard remains as a smoke check.
- ~~**WebAssembly required error path**~~ — **DONE**
  (`test/features/viewer/providers/wasm_load_failure_web_test.dart`, run via
  `flutter test --platform chrome` / `tool/run_web_widget_tests.sh`). The bare Chrome
  widget harness does not inject `web/index.html`'s `wellen_wasm_loader.js`, so
  `WellenWasmProvider.ensureInitialized()` genuinely fails — a real module-load failure,
  not a mock. Asserts the open path raises `WebAssemblyRequiredError` for VCD, FST, and GHW,
  and that `WaveformViewCenter` renders the "WebAssembly is required" guidance UI (warning
  icon + title + message, no generic-error chrome). Replaces the retired Dart-VCD-fallback
  test (`integration_test/web/dart_vcd_provider_test.dart`), since deleted.
- ~~Command palette opens in Chrome via Ctrl/Cmd+Shift+P~~ — **DONE**
  (`integration_test/web/web_command_palette_test.dart` mounts the dialog, fuzzy-filters
  "toggle the", presses Enter, and asserts the theme actually flipped — proving the dispatch
  chain reached the `ShortcutManagerWidget` handler in `app.dart`).
- ~~URL `?file=<url>` loads with CORS~~ — **DONE** (`integration_test/web/web_url_file_load_test.dart` — drives a real fetch via `bootstrap(args: [url])` against a standalone `tool/cors_fixture_server.dart` process serving both a CORS-permissive and a CORS-blocked route; wired into `tool/run_web_integration_tests.sh` alongside chromedriver, so `.github/workflows/integration-web.yml` needs no changes).

### Mobile / tablet / adaptive layout

The `integration_test/mobile/` suite covers the foundational mobile-layout and
gesture surface. The remaining items below are deeper integration scenarios
that suite does not yet attempt.

- ~~iPhone simulator: real layout selection across portrait/landscape orientations~~ — **DONE** (`integration_test/mobile/layout_phone_test.dart`, `layout_phone_landscape_test.dart`).
- ~~iPad simulator: tablet multi-pane in landscape, drawer in portrait~~ — **DONE** (`integration_test/mobile/layout_tablet_test.dart`).
- [ ] iPad split-screen narrow: drops to phone layout (real Stage Manager scenario) — manual until Flutter test harness supports Stage Manager.
- ~~Share sheet "Open With WaveCrux" works for `.vcd` / `.fst` / `.ghw` / `.wavecrux`~~ — **DONE for the channel path** (`integration_test/mobile/share_sheet_test.dart` mocks `com.wavecrux/incoming_file`); driving the real OS share sheet remains manual.
- [ ] Document picker on mobile loads files (real OS picker) — manual until the OS file picker supports test automation.
- ~~Re-fetch on scroll-back is transparent (real lazy-reload during scroll)~~ — **DONE** (`integration_test/canvas/scroll_back_refetch_test.dart`). The feature had already shipped. It's also mislabeled in this bullet's original framing — the real mechanism is `_WaveformCanvasState`'s viewport-gated `SignalLoadPlanner` pipeline (load-ahead + LRU eviction keyed off vertical scroll position), not `MobileMemoryGuardNotifier` (which unloads signals missing from the signal group, gated off on desktop, and has no notion of scroll position). The test drives 300 real signals through real drag gestures on the canvas's vertical scrollable, confirms the topmost signal is genuinely evicted once the traversal crosses `SignalLoadPlanner`'s retention budget, then scrolls back and asserts it re-fetches with the correct value.
- ~~OS memory warning → drops caches, no crash (real `didReceiveMemoryWarning` / `onTrimMemory`)~~ — **DONE** (`integration_test/mobile/os_memory_pressure_test.dart`). Drives the real `WidgetsBinding.instance.handleMemoryPressure()` entry point against a booted app with a loaded-but-not-visible signal, and asserts `MobileMemoryGuardNotifier` drops it while sparing the visible one, with no crash and a further frame still rendering. Needs `debugDefaultTargetPlatformOverride` + a forced phone-width `tester.view.physicalSize`, since the guard only activates off `DeviceClass.desktop` and a native desktop host otherwise floors every window size to desktop.
- ~~Pinch zoom, two-finger pan, tap cursor, long-press menu (real touch arena)~~ — **DONE** (`integration_test/mobile/gesture_pinch_zoom_test.dart`, `gesture_two_finger_pan_test.dart`, `gesture_long_press_context_menu_test.dart`).
- ~~Drawer swipe vs canvas pan don't conflict (real gesture arena)~~ — **DONE** (`integration_test/gestures/gesture_conflict_drawer_canvas_test.dart` — a horizontal swipe on the canvas resolves to a pan with no cursor scrub, while the same gesture from the phone drawer's edge opens the drawer; both arms run in one real gesture arena).
- [ ] Bottom sheet drag vs canvas pan don't conflict (real gesture arena).
- ~~Orientation change preserves all state (real OS rotation event)~~ — **DONE** (`integration_test/mobile/orientation_change_test.dart` exercises the surface-swap path that the OS rotation event triggers).
- [ ] Splitter visual on real touch — visible widening on grab — manual UX check.
- ~~Long-press = right-click on signal-list … (real touch arena)~~ — **DONE for signal-list rows** (`integration_test/mobile/gesture_long_press_context_menu_test.dart`); signal-tree / cocotb / canvas / transaction-table rows are not yet covered.

### Workspace and file lifecycle

- ~~Drag-drop onto the startup screen (real desktop drag-drop)~~ — **DONE** (`integration_test/workspace/empty_canvas_drag_drop_test.dart`). The original wording said "Welcome screen", a surface that no longer exists — the startup surface is the empty-canvas state of the workspace shell (`lib/features/workspace/`), and that is what the test drops onto. The test feeds the `desktop_drop` plugin's Dart side the messages its native runner sends (`entered`, then `performOperation`), so the window drop target, the overlay, the drop router and the File > Open dispatch all run as shipped. The OS drag session itself — Finder, Explorer or a Linux file manager handing paths to the runner — cannot be driven from a test and stays manual (`verification/VERIFICATION_GUIDE.md` §8.8).
- ~~File deletion notification with real-FS deletion event~~ — **DONE** (`integration_test/auto_reload/file_deletion_test.dart` — loads a waveform file, deletes it from the filesystem with `File.deleteSync()`, and asserts the app detects the deletion and surfaces a "file was deleted" notification).

### Action discoverability — desktop menu bar (per-platform smoke)

- ~~Desktop menu bar actually renders on the host OS (the act of launching is the test): macOS → native `PlatformMenuBar`; Windows/Linux → in-window Material `MenuBar`, with View → Toggle Theme tapped through to assert end-to-end dispatch~~ — **DONE** (`integration_test/menu_bar/desktop_menu_bar_test.dart`). Guards the regression where `PlatformMenuBar` (macOS-only in Flutter) rendered *no menu at all* on Windows/Linux. The macOS native `NSMenu` is out-of-view AppKit, so its contents/clicks remain **MANUAL** — the integration test asserts only that the bridge widget is present there.

### FSM visualization

- ~~Right-click + long-press dispatch from state register → "Visualize FSM" (gesture-arena)~~ — **DONE** (`integration_test/gestures/fsm_context_menu_dispatch_test.dart` — right-click (or long-press on touch) on a state register fires the context menu and asserts "Visualize FSM" is dispatched correctly).

### Performance

- ~~5-minute scroll session: memory stable, not growing without bound (long-running scenario; not feasible in widget-test)~~ — **DONE** (`integration_test/canvas/scroll_memory_soak_test.dart` — drives a sustained scroll + zoom + pan session (`_soakIterations` full cycles, hundreds of load/evict/cache-rebuild refreshes; real run wall-clock ≈ 5m42s against an 800-signal / transition-dense fixture) and asserts memory stays bounded via two complementary checks: a DETERMINISTIC bound that the source's loaded-signal count never exceeds the `SignalLoadPlanner` eviction ceiling and does not drift upward across iterations (the tight, non-flaky proof), plus a TOLERANT RSS growth canary — median tail vs. median baseline, allowed to grow only up to `max(baseline, 400 MB)` — that catches genuine unbounded growth while ignoring GC/heap-plateau noise. Uses the real `MemoryStatsService` RSS substrate; the RSS canary self-skips where `ProcessInfo` reports 0).

### Cross-feature integration (composite scenarios)

- ~~All 5 Open Core decoders simultaneously~~ — **DONE** (`integration_test/coexistence/multi_decoder_coexistence_test.dart` — second scenario generalizes the SPI+I²C case to all 5 open-core decoders (SPI, I²C, UART, AXI4-Lite, APB) against `protocol/multi/all5_basic.vcd`, generated by `tool/generate_multi_coexistence_fixture.dart`'s new `_generateAllFiveFixture`; asserts each decoder's transaction count matches its own expected companion and that panning doesn't drop/duplicate any of the 5).
- ~~Decoder + diff~~ — **DONE** (`integration_test/coexistence/decoder_diff_coexistence_test.dart` — activates a decoder, enters diff mode against a second waveform with the same decoder, and asserts both the decode overlay and diff highlights render without interference).
- ~~Decoder + X-Trace~~ — **DONE** (`integration_test/coexistence/decoder_xtrace_coexistence_test.dart` — activates a decoder and concurrently uses X-Trace on a related signal, asserting both overlays render and the transaction count is unchanged).
- ~~Decoder + pattern search~~ — **DONE** (`integration_test/coexistence/decoder_pattern_search_coexistence_test.dart` — activates a decoder and performs a pattern search on a related signal, asserting both overlays coexist without cross-interference).
- ~~Stage + FSM + RTL on desktop~~ — **DONE** (`integration_test/coexistence/stage_fsm_rtl_coexistence_test.dart` — loads a Stage widget alongside FSM visualization and RTL waveform on desktop, asserting all three render together).
- ~~Tablet with Stage + FSM~~ — **DONE** (`integration_test/coexistence/tablet_stage_fsm_test.dart` — same as above but on a simulated tablet layout with constrained width).
- ~~Session round-trip with Stage active, FSM open, statistics strip expanded, multiple decoders bound, custom panel sizes~~ — **DONE** (`integration_test/coexistence/composite_workspace_round_trip_test.dart` — the composite 2-tab/2-pane scenario now also activates a decoder on each tab (I²C on tab A, UART on tab B) before save and asserts both survive the save → close → reopen round-trip with `decoderId`, `instanceNumber`, and `config.signalBindings` all intact, alongside the already-covered Stage / FSM / statistics-strip / signals / cursors / custom panel sizes).

## Companion: widget-test gaps

The verification documents also flag `[Coverage: WIDGET — pending]` items — gaps that *can* be closed with a widget test (option B, full ProviderScope, no real device needed) but are not yet implemented:

- ~~Decoder picker section ordering test asserting top-to-bottom order across all populated `DecoderCategory` values under each of en/zh-CN/ja/ko~~ — **DONE** (`test/features/decoders/widgets/decoder_picker_dialog_open_core_set_test.dart` — Serial Bus above AMBA verified across en/zh/ja/ko via y-coordinate)
- ~~Open-core enumeration test (with all 5 open-core decoders registered, assert picker shows exactly that set)~~ — **DONE** (`decoder_picker_dialog_open_core_set_test.dart` — full-set enumeration with no `TierBadge` regression guard)
- ~~Per-category assignment test: SPI/I²C/UART → Serial Bus; AXI4-Lite/APB → AMBA~~ — **DONE** (`decoder_picker_dialog_open_core_set_test.dart` — category assignment via `find.descendant` against ExpansionTile keys, plus regression guard against the 5 unpopulated categories)
- Collapse/expand toggle behavior on `ExpansionTile` headers
- Decoder reconfigure → re-decode test
- Multi-decoder canvas layout test (multiple decoders active, no lane collision)
- Row click → cursor jump + on-canvas highlight (transaction table → canvas cross-feature)
- XOR `⊕` lane rendering on red signals
- Time-ruler amber bands at every divergence (diff overlay)
- X-Trace red lines + diamond markers + red tint on canvas (overlay rendering)
- Pattern search match highlights on time ruler + canvas
- ~~Stage widget picker section-ordering test (analogous to decoder picker gap)~~ — **DONE** (`test/features/stage/widgets/stage_widget_picker_dialog_section_ordering_test.dart` — open-core populated-set ordering across en/zh/ja/ko + full-set ordering simulating Stage Pro shipped state + regression guard against unpopulated categories rendering)
- Status-bar LIVE-badge widget test (streaming VCD)
- Diagnostics report remote-control-status field test — **NOT a test gap; it's a feature gap.** `AppDiagnosticsReportService` emits no Remote Control section. The verification item assumes the feature exists. Closing the gap requires adding a Remote Control section to the report (querying `remoteControlNotifierProvider` for server-running/port/connection-count) and *then* extending `test/services/diagnostics/app_diagnostics_report_service_test.dart`. Re-classify if the Remote Control section is added.
- `kIsWeb` gating tests for FSDB / process filters / interactive VCD / remote API / file watcher disabled-on-web — **CI infrastructure item, not a missing-test gap.** Each feature already has a `kIsWeb` early-return guard in source. Closing this gap means running per-feature widget tests under `flutter test --platform chrome` so `kIsWeb` is `true` at compile time. The standard `flutter test` runs with `kIsWeb=false` and only exercises the desktop branch. Add a per-PR or per-release Chrome test runner job to CI to close the gap.
- Auto-reload Settings section visibility on web — the `FileWatcherService` is gated (`if (kIsWeb) return;`) so the *behavior* is disabled, but the Settings → Auto-reload UI section still renders on web. Either wrap the section in a `kIsWeb` check (production-code change) or assert the current rendering under the Chrome runner.
- Auto-reload-disabled-on-web test
- IdeLayout splitter `bottomMinSize` ≥ 80 dp invariant
- ~~Composite "open new file with all features active → all clear" regression test~~ — **DONE** (`test/features/viewer/providers/waveform_source_provider_test.dart` — explicit `openFile clears X` and `close clears X` cases for all 5 features (XTraceState, DiffState, PatternSearchState, SwitchingActivityState, FsmViewState + FsmAnnotation map). Each test forces the provider into a non-default state via a testable subclass, calls openFile/close, then asserts state has reset to default. Catches the regression where someone removes a `ref.read(xNotifier).clearX()` call from `openFile`/`openFromBytes`/`attachStreamingSource`.)
- "Remove + re-add decoder → same transactions on second add" provider invariance test
- EDU licence-description site-wiring test (the ARB string lands with the wiring)

## Conventions

When implementing one of these tests:

1. Land the test under `integration_test/<area>/<feature>_integration_test.dart`.
2. Update the corresponding verification entry from `[Coverage: INTEGRATION_TEST — pending]` to `[Coverage: INTEGRATION_TEST]` and add the file path.
3. Remove the entry from this PENDING list in the same commit.
4. If the test reveals a platform-specific quirk (e.g. macOS file picker UTI handling), capture that in the verification guide as an edge case alongside the marker change.
