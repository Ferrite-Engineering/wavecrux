# WaveCrux

A modern, high-performance, multi-platform waveform viewer built with Flutter and Rust.
Domain: wavecrux.app

Architecture & engineering manual: `docs/ARCHITECTURE.md`. User documentation: `docs-site/docs/` (published at `https://docs.wavecrux.app`).

**IMPORTANT:** Neither is auto-loaded into context (no `@` prefix). Don't bulk-read them; locate the right anchor with `grep` first, then read the specific section.

## Tech Stack

- **Framework:** Flutter (Dart)
- **State Management:** Riverpod with code generation (`@riverpod` annotations via `riverpod_generator`)
- **Routing:** go_router
- **Waveform Engine (desktop/mobile):** wellen (Rust) via dart:ffi — VCD, FST, GHW parsing with multi-threaded VCD and compressed signal storage (both from wellen's defaults; `native/wellen_ffi` configures nothing extra). Legacy GTKWave LXT / LXT2 are converted to FST on open by the `native/lxt2fst` crate; FSDB is converted via an external `fsdb2vcd`.
- **Waveform Engine (web):** wellen (Rust) compiled to WebAssembly via wasm-bindgen, called from Dart via `dart:js_interop`. Single-threaded, otherwise identical to the FFI build. No Dart-side fallback — a WASM load failure surfaces a "WebAssembly is required" error in the canvas centre. Details: [`docs/web_performance.md`](docs/web_performance.md).
- **Domain Models:** Plain immutable Dart classes with copyWith/equality (no freezed — models are not serialized to a database)
- **Panel Layout:** `CruxIdeLayout` (crux-shared `crux_ide_layout`, built on the `panes` package) for the resizable left / centre / right / bottom regions; the docks inside them come from `crux_dock`, and tabs / split panes from `crux_workspace`. Panel sizes and visibility persist per tab in the session JSON.
- **Session Persistence:** JSON files (.wavecrux session format); `.wavecruxpack` share bundles (session + trace slice); GTKWave `.gtkw` import supported
- **Plugin System:** Dart-based protocol decoders, plus native decoder plugins loaded at startup through a C ABI (`include/wavecrux_decoder.h`, loader in `lib/services/decoders/ffi/`, desktop only); Rive-backed custom animated widgets for WaveCrux Stage (open-core SDK — manifest, normalization framework, `.wcrux-widget` bundle loader, hot-reload, Tachometer reference widget all live here)
- **Rendering:** Custom `RenderObject` / `CustomPainter` for waveform canvas

## Platform Targets

| Platform | Device Class | Notes |
|----------|-------------|-------|
| **Linux** | Desktop | Primary target. Most HDL engineers work on Linux. |
| **macOS** | Desktop | Strong FPGA/ASIC user base. |
| **Windows** | Desktop | Xilinx/Intel FPGA users. |
| **Web** | Desktop/Tablet | wellen compiled to WebAssembly (no FFI, no Dart parser). Single-threaded, parses on the main thread. `?file=<url>` loading for CI/CD links. See `docs/web_performance.md`. |
| **iPadOS** | Tablet | Review simulation results during design reviews. Multi-pane layout. Stage panel supported. |
| **iPad (portrait)** | Phone→Tablet | May collapse to phone layout in narrow portrait orientation. |
| **iOS (iPhone)** | Phone | Quick waveform checks after CI notifications. Full-screen canvas with drawer/sheet navigation. |
| **iOS (iPhone Duo)** | Phone ⇄ Tablet | Foldable. Cover display 466×678 dp → phone; inner display 669×951 dp → tablet. The class changes *while the user holds the device*: side docks force-hide on fold and restore on unfold, preferences preserved. Inner portrait is the narrowest tablet-class viewport we ship to — it takes the `<800 dp` pane defaults. |
| **Android tablet** | Tablet | Same as iPadOS — multi-pane layout. |
| **Android phone** | Phone | Same as iPhone — full-screen canvas with drawer/sheet navigation. |

### Device Class Breakpoints

| Device Class | Breakpoint | Layout |
|---|---|---|
| Phone | Width < 600 dp | Single-pane, drawers/sheets for secondary panels |
| Phone (landscape) | Width ≥ 600 dp, height < 500 dp | Waveform-focused: full-width canvas, overlay panels, condensed/auto-hide chrome |
| Tablet | 600 dp ≤ width < 1200 dp, height ≥ 500 dp | Simplified multi-pane, narrower proportions |
| Desktop | Width ≥ 1200 dp | Full `IdeLayout` with resizable splitters |

`deviceClassProvider` (Riverpod) uses a compound classification based on both width and height. A phone in landscape crosses the 600 dp width threshold but has only ~380 dp of vertical space — too short for persistent side panels. The secondary height check (height < 500 dp) keeps it in a waveform-focused layout with overlay panels. Layout widgets watch this provider — **not** `Platform.isIOS` / `Platform.isAndroid` — so that tablets in split-screen or phones rotating get the correct layout. Re-evaluates on resize and orientation change.

**Native-desktop-host exception.** On a native desktop OS (macOS / Windows / Linux), `deviceClassProvider` is floored to `DeviceClass.desktop` regardless of window size — a small desktop window keeps the full IDE layout and simply shrinks to the OS-enforced minimum (800×500), it never reflows to tablet/phone chrome. A small desktop window is still a desktop: mouse, keyboard, multi-pane IDE expected. This is the one place the layout consults the host platform, via `isDesktopHostPlatform` (`defaultTargetPlatform`) inside `deviceClassForSize` — the single classifier behind `deviceClassProvider` (fed by `DisplaySizeFeed`), which `ViewerScreen` watches. **Web and mobile keep the size-driven classification** (a narrow browser tab, or a phone/tablet in split-screen, genuinely needs the adaptive layout). The desktop pane minimums (~420 dp combined) fit well inside the 800 dp window minimum, so flooring never overflows.

## Build & Run Commands

```bash
# Code generation (Riverpod)
dart run build_runner build --delete-conflicting-outputs

# Run app (desktop)
flutter run -d linux    # or -d macos, -d windows

# Run app (mobile)
flutter run -d ios      # iOS simulator or connected device
flutter run -d android  # Android emulator or connected device

# Run all tests
flutter test

# Run single test file
flutter test test/path/to/test_file.dart

# Lint (zero warnings policy — CI fails on infos too)
flutter analyze --fatal-infos --fatal-warnings

# Generate localization files (flutter gen-l10n)
# Note: runs automatically during `flutter build` / `flutter run` (generate: true in pubspec.yaml)
flutter gen-l10n

# Rust wellen_ffi library. Needs a Rust toolchain (rustup) on PATH.
#   Desktop: nothing to run — linux/ and windows/ CMakeLists.txt and a macOS
#            Xcode build phase run `cargo build --release` in native/wellen_ffi.
#   Android: nothing to run — the Gradle preBuild hook runs scripts/build_android.sh
#            (needs the Android NDK).
#   iOS:     rebuild the committed native/wellen_ffi/WellenFFI.xcframework after
#            any Rust change (needs Xcode):
./scripts/build_ios.sh

# Regenerate the Dart FFI bindings after changing a C header (needs LLVM/libclang)
dart run ffigen --config ffigen.yaml           # native/wellen_ffi/wellen_ffi.h
dart run ffigen --config ffigen_decoder.yaml   # include/wavecrux_decoder.h

# Run Rust tests
cd native/wellen_ffi && cargo test
```

## Coding Conventions

### IMPORTANT: Cross-suite filename convention — no dotfile names for user files

WaveCrux has no per-project config file today (workspaces export as
`team-debug.wavecrux-workspace`; session shares export as `mysim.wavecrux` —
both named files with the product's extension). That pattern is locked in
across the suite by
[crux-shared/docs/adr/0001-project-config-filename-convention.md](crux-shared/docs/adr/0001-project-config-filename-convention.md):
when introducing any new per-project, per-user, or per-suite config file,
use a named-file pattern, NOT a dotfile name like `.wavecrux-config`. See
the ADR for the failure mode that motivated it (macOS Finder and most
native file pickers hide dotfiles, so users could not find another suite
product's pre-ADR dotfile config). Pure tooling caches that the user never opens
may still use a dotfile name; consult the ADR before adding one.

### IMPORTANT: No Hardcoded Strings

Every user-facing string MUST come from `L10N` (ARB files). No string literals displayed to users anywhere in widget, screen, or service code. The only exception is test code. WaveCrux ships with English, Simplified Chinese, Japanese, and Korean — all strings go through the localization system.

### IMPORTANT: Tests Required for All New Code

Every new or modified Dart file in `lib/` MUST have a corresponding test file in `test/` mirroring the same directory structure. When generating production code, YOU MUST also generate the tests in the same response. Do not wait to be asked — tests are not optional.

- **Domain models:** Unit tests for equality, copyWith, and any computed properties.
- **Services** (parser, value formatter, signal query, waveform builder, session, protocol decoders): Unit tests covering happy path, edge cases, and error handling.
- **Providers:** Unit tests using `ProviderContainer`. Verify state transitions and async behavior.
- **Widgets:** Widget tests for key interactions and layout. Screens and interactive widgets must include a **locale sweep** that renders in `en`, `zh_CN`, `ja`, and `ko` and asserts no exceptions (catches RenderFlex overflow, CJK rendering issues). Use `expect(tester.takeException(), isNull)` after pumping.
- Use `mocktail` for mocking, not `mockito`.
- Test file naming: `test/<lib path mirrored>/<name>_test.dart`
- **Waveform parser validation:** Every waveform query must be tested against hand-crafted known-answer fixture files (see ARCHITECTURE.md §8.9). Cross-validate `WellenProvider` (FFI) and `WellenWasmProvider` (WASM) — both wrap the same wellen crate and must return identical results for every fixture, validating the two marshalling bridges. Use GTKWave as the reference implementation for value correctness.

### IMPORTANT: Protocol Decoder Fixture Layout — `generated/` + `captured/`

Every per-decoder fixture directory under `test/fixtures/protocol/<decoder>/` and `verification/fixtures/protocol/<decoder>/` is split into two sibling tiers:

- **`generated/`** — deterministic VCDs and JSON snapshots emitted by `tool/generate_*.dart`. Re-runnable in seconds. 100% reproducible. The unit-test backbone — `flutter test test/services/decoders/<decoder>_decoder_test.dart` runs against the snapshots in this directory.
- **`captured/`** — traces acquired from public open-source projects (verilog-ethernet, verilog-axi, picorv32, OpenTitan, cocotbext-axi, Corundum, etc.), as direct VCD/FST downloads or as locally rebuilt artifacts from upstream testbenches via `iverilog` / `verilator`. Exercises the decoder against real-world bus traffic.

Rules:

1. **No fixture files at the `<decoder>/` level.** Every `.vcd` / `.fst` / `.vcd.zst` / `.expected_transactions.json` must live in either `generated/` or `captured/`. The `multi/` coexistence harness directory under `verification/fixtures/protocol/` is exempt — it composes from per-decoder sources rather than holding its own corpus.
2. **Every fixture has a sibling `.expected_transactions.json` snapshot.** Enforced by `test/static/captured_fixture_companion_test.dart` for captured, and by the existing per-decoder tests for generated.
3. **Captured fixtures require per-directory `PROVENANCE.md` entries.** Source project, commit SHA, license, capture method, and hand-verified anchor transactions. License allow-list: MIT, BSD-2, BSD-3, Apache-2.0, ISC, CC0, public-domain. GPL/AGPL/proprietary captures are blocked by `test/static/captured_fixture_licenses_test.dart`.
4. **Generators write into `<decoder>/generated/`.** Any new `tool/generate_<x>_fixtures.dart` must follow this output path — never the unqualified `<decoder>/` directory.
5. **Total committed fixture corpus targets ≤100 MB.** Prefer FST over VCD where possible (wellen reads FST natively). Compress raw VCDs as `.vcd.zst` when FST isn't viable. Cap any single fixture at ~5 MB raw-equivalent.

The full provenance/automation rationale lives in `verification/fixtures/helpers/README.md`. Captured fixtures are added one decoder at a time through the same workflow: acquire, trim, snapshot, document.

### IMPORTANT: Integration-Test Timing — never `pumpAndSettle(Duration)`

Integration tests (`integration_test/**`) run under `LiveTestWidgetsFlutterBinding`, where the `duration` argument to `pump` / `pumpAndSettle` is the **per-pump real-time interval, NOT a timeout**. `pumpAndSettle(const Duration(seconds: 10))` schedules a real 10-second `Timer` and blocks the full ten seconds even when the UI settled instantly — multiplied across the suite that is minutes of wasted CI wall-clock. Stripping it to a bare `pumpAndSettle()` is also wrong when waiting on the background-isolate FFI parse or the decoder decode pass: that work schedules no Flutter frames until it completes, so a bare `pumpAndSettle()` returns early and races the load.

Always use a **bounded condition-poll** that returns the instant the real ready-state is observable: the `pumpUntil` / `pumpUntilWaveformReady` helpers in [`integration_test/helpers/app_driver.dart`](integration_test/helpers/app_driver.dart) (the file's doc-comments explain the binding semantics in full), or an inline `for (…) { await tester.pump(interval); if (ready) break; }`. A bare `pumpAndSettle()` is fine only for a pure UI-animation settle that schedules its own frames (e.g. after a resize or dialog open). The convention is enforced by [`test/static/no_pumpandsettle_duration_in_integration_tests_test.dart`](test/static/no_pumpandsettle_duration_in_integration_tests_test.dart), which fails CI if a `pumpAndSettle(Duration…)` call reappears under `integration_test/`.

### IMPORTANT: Widget Architecture

- **One widget per file.** Each public widget class gets its own `.dart` file named in `snake_case` (e.g., `waveform_canvas.dart` → `WaveformCanvas`). Private helper widgets within the same file are acceptable.
- **Keep widgets small.** If `build()` exceeds ~50 lines or has 3+ nesting levels, extract child sections into their own widget files.
- **Build for reuse.** Leaf widgets should be "dumb" — accept data and callbacks via constructor, don't reach into providers directly. Place shared widgets in `lib/shared/widgets/`.
- **Stateless over stateful.** Use `ConsumerWidget` with Riverpod. Only use `StatefulWidget` for local mutable state (animations, form controllers, focus nodes, canvas gesture handlers).
- **Composition over configuration.** Prefer distinct widget variants over a single widget with many boolean flags.
- **Panel widgets must be layout-agnostic.** Panel content widgets (signal tree, value column, transaction table, Stage) must not assume they are hosted in `IdeLayout`. They receive constraints from their parent and adapt. `ViewerScreen` decides *where* to place them (an `IdeLayout`/`CruxIdeLayout` pane on tablet/desktop, or the phone signal-tree `Scaffold.drawer` at phone width, with side/bottom panes force-hidden); the panel widget itself just renders its content within whatever space it's given.
- **Touch targets and mobile sizing — see `MobileMetrics`.** All interactive sizing (touch targets, icon sizes, toolbar heights, splitter widths, lane resize handles, cursor markers, drag handles) lives in `lib/core/mobile_metrics.dart`. Read from `MobileMetrics.of(context, deviceClass)` instead of declaring local pixel constants. Full spec: ARCHITECTURE.md §3.1.8.
- **Context menus vs. long-press.** Right-click context menus (signal format, copy value) must have a long-press equivalent on mobile via `PlatformContextMenu`. Drag-to-reorder uses an explicit drag handle only — long-pressing the row body never initiates drag. See ARCHITECTURE.md §3.1.8.5.
- **Orientation-change resilience.** Widgets must survive orientation changes without losing state. All meaningful state lives in Riverpod providers (which survive widget rebuilds), not in local `State` fields. Scroll positions, cursor state, zoom level, and panel contents must be preserved across orientation transitions. `ViewerScreen` re-syncs its pane visibility on an orientation/size change (via `deviceClassProvider`, re-fed by `DisplaySizeFeed`) — panel widgets must not assume a fixed parent layout across their lifetime.

### IMPORTANT: Mobile UI Standards

WaveCrux runs on a single codebase across desktop, tablet, and phone. Default Flutter widget sizing is desktop-first and produces unusable interactions on touch — invisible drag handles, buttons too small to hit reliably, cursor markers buried under a fingertip. ARCHITECTURE.md §3.1.8 is the authoritative spec; the rules below summarize the parts every contributor must follow.

- **Read sizes and font sizes from `MobileMetrics`.** Do not hardcode pixel sizes or font sizes for interactive elements or text in `lib/features/**`. Call `MobileMetrics.of(context, deviceClass)` and use the returned values, including the typography tokens (`bodyText`, `labelText`, `monoText`, `statusBarText`). Per-widget overrides require a comment explaining why.
- **Apply mobile metrics to all touch device classes uniformly.** Phone, phone-landscape, and tablet all get the same enlarged sizes. Tablet does **not** stay at desktop sizing — engineers using a tablet are using touch input.
- **Apply mobile metrics on iOS/iPadOS/Android even when the screen is desktop class.** iPad Pro 12.9" landscape is `DeviceClass.desktop` but has no mouse and no right-click. The host platform check (`Theme.of(context).platform`) decides, not just device class.
- **Wrap chrome in `SafeArea`.** Every layout (phone, tablet, desktop) wraps its content in `SafeArea`. Never call `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)` to hide the system bars — it breaks iPad Stage Manager and split-screen.
- **44 × 44 dp minimum hit area on touch.** Even when the visual element is smaller (a 16 dp swatch, a 1 dp splitter line), the surrounding `GestureDetector`/`InkWell` must be ≥ 44 dp.
- **Visible affordances for every draggable surface on touch.** Drag handles render as actual icons. Lane resize strips paint a two-line grip. Splitters are 6 dp visible (never thinner) with a 32 dp hit zone on touch / 12 dp on desktop, and **must** wire `resizerHoverColor`/`resizerFocusedColor` to the theme's primary so the bar lights up under a hovering pointer. Cursor triangles are filled, not outlined, on touch.
- **Long-press = right-click everywhere.** Wrap rows that have a desktop right-click menu with `PlatformContextMenu`. Drag-to-reorder must use an explicit handle.
- **Don't claim gestures you don't handle.** Inner `GestureDetector`s handling only `onTap` (color cycle, double-tap reset) must NOT use `HitTestBehavior.opaque` — opaque hit-testing claims long-press too and prevents the outer `PlatformContextMenu` from firing, then the inner `onTap` runs *after* dialog dismissal and clobbers the user's choice. This is the gesture-bubbling rule (ARCHITECTURE.md §3.1.8.5).
- **Tooltips inside a row use `triggerMode: TooltipTriggerMode.manual`.** Default `Tooltip` registers a `LongPressGestureRecognizer` that beats the outer `PlatformContextMenu` in the arena, hiding the context menu on touch. Hover tooltips on desktop still work; touch users see the equivalent content via context-menu items.
- **Phone widths force-hide all side and bottom docks.** At `DeviceClass.phone` / `phoneLandscape`, the side panes' min sizes (150 dp each) plus the 120 dp centre floor exceed the available width. `ViewerScreen`'s per-tab `Consumer` watches both `panelLayoutProvider` and `deviceClassProvider` and passes `isPhone` into the `CruxIdeLayout` adapter, which computes *effective* visibility without touching `PanelLayoutState`. The user's per-panel preference is preserved and restores when the window grows back to tablet/desktop. Per ARCHITECTURE.md §3.1.8.6.
- **Panel collapse lives on the docks, not in the status bar.** On tablet and desktop each dock's strip collapses it, a collapsed region leaves a slim restore bar along its edge (`WaveCruxDockRestoreBars`), and panels are also revealed from the View menu, command palette, or toolbar. The status bar carries panel chevrons **on phone only**, where they are the phone's only panel access: the left chevron opens the signal-tree drawer and the centre chevron opens the bottom-dock sheet. There is no right chevron on any device class — on phone, values render inline at the cursor (`InlineCursorValueOverlay`). Splitters between panels must remain reachable; once a panel is shown it must stay drag-resizable, and the bottom panel honors its `bottomMinSize` ≥ 80 dp so it cannot be re-shown at zero height.
- **Chrome rows are horizontally scrollable.** The shared toolbar and status bar (`crux_toolbar`, `crux_status_bar`) wrap their primary content in `SingleChildScrollView(scrollDirection: Axis.horizontal)` so they don't overflow on narrow windows (iPad split-screen, small phones); panel header `Row`s must do the same. The toolbar's overflow menu sits outside the scroll view, pinned right.
- **Truncated text always has a reveal.** Any `Text(overflow: TextOverflow.ellipsis)` is wrapped in `Tooltip(message: fullText, triggerMode: TooltipTriggerMode.manual)` for desktop hover, **and** the row's context menu's first item is a non-interactive monospace header showing the full content (per ARCHITECTURE.md §3.1.8.14). Snackbar-based "Show Full…" actions are not used.
- **Text scaling clamped to [0.85, 1.5].** The app root (`app.dart`, inside `MaterialApp.builder`) wraps the app in `MediaQuery.withClampedTextScaling` so OS-level accessibility scaling can't blow up the layout.
- **Touch-target compliance test.** Any new interactive widget that renders on phone or tablet must include a widget test asserting `tester.getSize(find.byKey(...))` for the hit-test surface is ≥ 44 × 44 dp.

### IMPORTANT: Screen-reader and keyboard accessibility

An external NVDA pass (2026-09-14) found WaveCrux unusable by ear in ways every automated guard passed: silence at launch, bare "text" Tab stops, a search dialog of unlabelled check boxes, Space not activating buttons, a failed load announced as nothing. These rules are the definition of done for any UI change here.

- **A new or changed surface gets a focus walk.** Follow `test/accessibility/screen_reader_test.dart`: `expectFocusAnnounced` where focus must land, `walkFocus` + `expectCleanFocusWalk`, and for a primary surface a transcript golden under `test/accessibility/goldens/` that you read before committing (`flutter test --update-goldens test/accessibility`). A golden diff is a change in what a blind user hears — review it like a UI diff.
- **Focus always lands somewhere named.** The viewer is under a `CruxFocusRegionScope`: top-level chrome goes in a `CruxFocusRegion`, the start screen and the waveform pane are the primary regions. Never add an unnamed `Focus(autofocus: true)` holder around a large subtree — it absorbs every label below it.
- **One name per control, one node per row.** A label or a tooltip, not both. A list row is one named node (`semanticLabel`, `excludeFromSemantics` on the row gesture, `ExcludeSemantics` on text the label already says).
- **Errors and completions are announced** with `announceCrux` — a snackbar or a red pane is silent on desktop.
- **Space and Enter belong to the focused control.** A bare-key binding must not consume them when the focused widget accepts `ActivateIntent` (see `shortcut_manager_widget.dart`).
- **A lazy list is one focus node, not one per row.** A row scrolled out of a `ListView.builder` is disposed and takes a per-row focus node with it. Hold the current row in state and let the row report focus through its own `Semantics(focused:)`, as `lib/features/signal_tree/widgets/signal_tree_row_list.dart` does for the signal tree.
- **A `HardwareKeyboard` handler runs under dialogs.** It sits below focus, so it must return early while its screen's route is not current (`ModalRoute.of(context)?.isCurrent`), or Escape and bare keys pressed in a dialog act on the screen behind it.
- **No arrows or box glyphs in ARB strings** — `test/static/speakable_strings_test.dart` enforces it. Write menu paths as `Settings > AI`.

### Dart Style

- Follow Effective Dart guidelines
- Files: `snake_case.dart`
- Classes: `PascalCase`
- Variables/functions/params: `camelCase`
- Constants: `camelCase` (not SCREAMING_SNAKE)
- Providers: `camelCase` ending in `Provider` (e.g., `signalListProvider`)
- No `!` operator unless non-null contract is provably guaranteed and documented with a comment
- Use `very_good_analysis` lint rules

### Riverpod

- Riverpod 3 (`flutter_riverpod` + `riverpod_generator`). Use the `@riverpod` annotation (code generation) for new providers; hand-written providers remain only where a seam needs one (e.g. the `lib/plugins/extra_*_provider.dart` extension points)
- Providers live in `providers/` within each feature module
- Providers should be thin — delegate logic to services or the wellen FFI layer
- Generated `Notifier` / `AsyncNotifier` classes for mutable state (cursor position, zoom level, selected signals). There is no `StateNotifier` / `StateNotifierProvider` in `lib/`; don't introduce the legacy API
- Async loads expose `AsyncValue` — e.g. `waveformSourceProvider` is a keep-alive notifier whose state is `AsyncValue<WaveformDataSource?>`
- Never use `ref.read` in a widget's `build` method — use `ref.watch`

### Localization

- 4 locales for first release: English (`en`), Simplified Chinese (`zh-CN`), Japanese (`ja`), Korean (`ko`). Internationalized from day one using Flutter's standard `flutter gen-l10n` system.
- ARB files live in `lib/l10n/`
- `app_en.arb` is the primary source of truth. CJK ARB files (`app_zh_CN.arb`, `app_ja.arb`, `app_ko.arb`) must be updated with the localized language text in every commit that adds or modifies strings.
- `app_zh.arb` mirrors `app_zh_CN.arb` (same translations, `@@locale` set to `zh`) so users on a bare `zh` locale (no country code) get Simplified Chinese rather than falling back to English. Keep the two files in sync — every edit to `app_zh_CN.arb` must also be applied to `app_zh.arb`.
- Generated code (the `output-dir` in `l10n.yaml`, imported as `package:wavecrux/l10n/generated/l10n.dart`, class `L10N`) is not committed — it is produced at build time via `flutter gen-l10n`.
- All user-facing strings go through `L10N`. This enables community-contributed translations post-launch with zero code changes.
- All description metadata in the ARB files remain in English.  Only the UI visible text is localized.
- **Translation house style and glossary:** [`.claude/instructions.md`](.claude/instructions.md) is the canonical house style for CJK translations (core principles, mandatory glossary, ICU plural rules including the `=1` case requirement, button-label length targets, per-language rules). [`assets/l10n/glossary.json`](assets/l10n/glossary.json) is the machine-readable version of the glossary + acronym never-translate list + pluralization templates. Read both before adding or modifying any CJK string, and when DeepSeek/Claude/another translator audits the ARB files, point them at these two files first.

#### IMPORTANT: ARB File Rules

- **Every message MUST have a corresponding `@` metadata entry** to avoid analyzer warnings. Include at minimum a `description` field. Example:
  ```json
  {
    "signalTreeTitle": "Signals",
    "@signalTreeTitle": {
      "description": "Title for the signal hierarchy browser panel"
    },
    "valueAtTime": "Value at {time}",
    "@valueAtTime": {
      "description": "Label showing the signal value at a specific time",
      "placeholders": {
        "time": { "type": "String" }
      }
    }
  }
  ```

## Project Structure

```
lib/
├── core/               # Shared utilities, constants, extensions, theme, keyboard shortcuts
├── l10n/               # Localization: ARB source files (generated code via flutter gen-l10n, not committed)
├── domain/             # Pure Dart: models, enums, interfaces — ZERO Flutter imports
│   ├── models/         # Scope, Variable, SignalGroup, SessionState, etc.
│   ├── enums/          # DisplayFormat, VarType, ScopeType, etc.
│   └── interfaces/     # WaveformDataSource, ProtocolDecoder, StageWidget interfaces
├── native/             # Dart FFI bindings: wellen_ffi_bindings.dart (ffigen) and
│   └── bindings/       # lxt2fst_bindings.dart (hand-written). The Rust crates live at
│                       # repo-root native/ (wellen_ffi, wellen_wasm, lxt2fst), not under lib/.
├── services/           # Non-UI services — business logic lives here
│   ├── ai/             # AI extension-point plumbing (tool registry, explain-selection, no-op
│   │                   # model client, secure key storage) — advisor implementation is Pro
│   ├── annotations/    # Annotation anchor resolution + drift witness
│   ├── auto_bind/      # Automatic decoder/Stage-widget binding text helpers
│   ├── cli/            # Command-line argument parsing
│   ├── cocotb/         # Cocotb log parsing + correlation
│   ├── collaboration/  # Collaboration extension points (no-op service, content hash) — Pro implements
│   ├── debug_advisor/  # Debug Advisor extension point — Pro implements the rule engine
│   ├── decoders/       # Protocol decoders (SPI, I2C, UART, APB, AHB-Lite, AXI4-Lite, Wishbone,
│   │                   # SPI flash), ISA/RISC-V instruction trace, C-ABI FFI plugin loader (ffi/)
│   ├── dev_tools/      # Developer/debug-only tooling (VCD generator service)
│   ├── diagnostics/    # App/tab diagnostics report services + FileStatsService, MemoryStatsService, etc.
│   ├── diff/           # Waveform comparison/diff engine
│   ├── export/         # Image/screenshot export service
│   ├── host_bridge/    # Editor-host (VS Code webview) bridge: cross-probe, telemetry relay
│   ├── logging/        # package:logging console sink + verbosity level
│   ├── mobile/         # MobileMemoryGuardService, file size warning, memory pressure handling
│   ├── pack/           # .wavecruxpack share-bundle reader/writer
│   ├── panes/          # PaneContainerManager — per-pane ProviderContainer lifecycle
│   ├── platform/       # Platform services: incoming file handling, orientation lock,
│   │                   # security-scoped bookmarks, web drag-drop
│   ├── policy/         # Organization policy-file consumers (decoder settings, session
│   │                   # templates, signal groups, themes)
│   ├── remote/         # WCP server (wcp_server.dart) + CXP (cxp/) + remote-control state
│   ├── riscv/          # RVFI detection, retire stream, architectural-state tracking
│   ├── rtl_source/     # RTL source loader, HDL parser, syntax highlighter, Verilator STEMS import
│   ├── samples/        # Bundled sample-waveform loader (empty canvas "Open Sample Waveform")
│   ├── session/        # Session save/load (.wavecrux JSON format), .gtkw import, <design>.crux-project resolution
│   ├── settings/       # App preferences persistence
│   ├── signal_query/   # Search, filter, group, analyze signals
│   ├── stage/          # Stage widget board auto-bind + stage slot family (binding logic)
│   ├── tabs/           # TabContainerManager — per-tab ProviderContainer lifecycle
│   ├── telemetry/      # Telemetry event catalog + platform tag (pipeline: crux-shared crux_telemetry)
│   ├── time_format/    # Human-readable time display with auto-scaling
│   ├── translate/      # GTKWave-compatible translate filter file reader
│   ├── value_format/   # Hex, dec, bin, oct, ASCII, signed, enum formatting
│   ├── vcd_writer/     # VCD export (filtered signal/time-range subset)
│   ├── waveform/       # WellenProvider (FFI) / WellenWasmProvider (WASM), lxt2fst + FSDB
│   │                   # conversion, streaming VCD, web/URL file loaders
│   ├── waveform_geom/  # WaveformBuilder, TimeMapper, TimeRuler — rendering geometry
│   └── workspace/      # Workspace codec, last-session migration, window bounds store
├── features/           # Feature modules
│   ├── about/          # About box
│   ├── ai/             # AI advisor extension-point UI
│   ├── annotations/    # Waveform annotations: canvas overlay, Annotations panel, providers
│   ├── beta_expiry/    # Beta build expiry banner/gate
│   ├── cocotb/         # Cocotb log panel
│   ├── collaboration/  # Collaboration extension-point UI
│   ├── command_palette/ # VS Code-style command palette (Ctrl+Shift+P fuzzy action search)
│   ├── comparison/     # Waveform diff/comparison view
│   ├── cursors/        # Cursor, marker, and measurement management
│   ├── decoders/       # Protocol decoder UI (transaction overlay, decoder config)
│   ├── diagnostics/    # Tab Diagnostics drawer (File Info / Signal Health / Benchmark This File) + App Diagnostics dialog (Memory + Frame Stats) + Pane Render Stats popover
│   ├── issue_reporter/ # Issue reporter provider overrides (dialog + log buffer: crux-shared crux_issue_reporter)
│   ├── menu_bar/       # Desktop menu bar (CruxDesktopMenuBar binding)
│   ├── pack/           # Share Annotated Waveform (.wavecruxpack) disclosure dialog + providers
│   ├── panes/          # WaveCruxPaneHost adapter over crux_workspace's PaneHost
│   ├── remote/         # CXP remote-control UI
│   ├── rtl_source/     # RTL source annotation view (desktop only)
│   ├── search/         # Signal search dialog
│   ├── settings/       # App preferences (theme, shortcuts, default formats, extensions)
│   ├── signal_tree/    # Signal hierarchy browser (SST panel)
│   ├── stage/          # WaveCrux Stage: animated signal visualization panels
│   │   ├── bundle/  providers/  runtime/  sdk/  settings/  widgets/
│   ├── statistics/     # Live statistics strip (desktop only — ambient performance monitoring above the status bar)
│   ├── tabs/           # ViewerTabBar chip menu, drag/reorder, tab lifecycle UI
│   ├── telemetry/      # crux_telemetry provider overrides
│   ├── tools/          # Misc toolbar tool actions
│   ├── update/         # Update-check provider overrides (service: crux-shared crux_updates)
│   ├── viewer/         # Main waveform viewer (canvas, signal list, value column)
│   │   ├── providers/
│   │   ├── screens/
│   │   └── widgets/
│   └── workspace/      # Workspace = the open-tab set; empty-canvas state, recent files/workspaces
├── shared/             # Shared widgets and responsive layouts
│   ├── widgets/
│   ├── platform/       # Reveal-in-file-manager helper (io + stub)
│   └── layouts/        # device class provider + host-aware classifier (deviceClassForSize), size-aware pane defaults (DisplaySizeFeed lives in shared/widgets/)
├── widgets/            # Legacy-format conversion progress dialog + banner
└── plugins/            # Plugin registries and extension seams
    ├── decoder_registry.dart
    ├── stage_registry.dart
    ├── translator_registry.dart
    └── extra_*_provider.dart   # overlay seams (decoders, Stage widgets, dock tabs, timeline overlays, …)
```

Window chrome, the menu bar renderers, dock/workspace/toolbar/status-bar chrome, the issue reporter, update check, and telemetry pipeline are shared suite packages under the `crux-shared` submodule (`crux_window_chrome`, `crux_menu_bar`, `crux_dock`, `crux_workspace`, `crux_toolbar`, `crux_status_bar`, `crux_issue_reporter`, `crux_updates`, `crux_telemetry`, …).

## Key Architecture Rules

- **Domain layer has zero Flutter imports.** Pure Dart only. No third-party deps. Models, enums, and interfaces live here.
- **Features depend on domain interfaces**, not service implementations. The `WaveformDataSource` interface abstracts whether data comes from wellen via FFI (`WellenProvider`) or wellen via WebAssembly (`WellenWasmProvider`). There is no Dart parser; `test/static/no_dart_vcd_parser_test.dart` keeps it that way.
- **Desktop-first, responsive everywhere.** The primary layout is a multi-pane desktop view built with `CruxIdeLayout` (crux-shared `crux_ide_layout`, on the `panes` package). Tablet uses a simplified multi-pane layout. Phone uses a single-pane scaffold with a signal-tree drawer (side/bottom panes force-hidden). `ViewerScreen` adapts its layout based on `deviceClassProvider`. Panel state (sizes, visibility) is saved/restored as part of the session file.
- **Layout decisions use screen width and height, not platform — with one exception.** `deviceClassProvider` derives `DeviceClass` from `MediaQuery` dimensions, not `Platform.isIOS`/`Platform.isAndroid`. A compound classification applies: primary width breakpoints select phone/tablet/desktop, then a secondary height check catches phone-landscape (width ≥ 600 dp but height < 500 dp → keep overlay-panel layout despite tablet-class width). This ensures correct layout for web browsers at any size and phones rotating between portrait and landscape. **The exception:** on a native desktop host (macOS/Windows/Linux) the class is floored to `desktop` regardless of size, so a small desktop window keeps the IDE layout and just shrinks to the OS minimum rather than reflowing to tablet/phone — see the "Native-desktop-host exception" under Device Class Breakpoints. The shared host-aware classifier is `deviceClassForSize`, behind `deviceClassProvider`; web and mobile fall through to the size-only path.
- **All engine/data layer code is platform-agnostic.** Services, providers, domain models, protocol decoders, and the wellen FFI layer work identically on phone, tablet, desktop, and web. Only the layout scaffold and panel hosting differ between device classes.
- **Feature surface is controlled by device class, not feature flags.** Features excluded from phone or tablet (Stage on phone, RTL source annotation, diagnostics, live statistics strip) are gated by `deviceClassProvider` checks in the UI layer, not compile-time flags. The underlying logic is always available.
- **Mobile file loading uses share sheet / document picker as primary path.** On mobile, users receive files via Slack/email/AirDrop and tap to open. File type associations (`.vcd`, `.fst`, `.ghw`, `.lxt`, `.lxt2`, `.wavecrux`; Android also `.wavecruxpack`) are registered in `ios/Runner/Info.plist` and `AndroidManifest.xml` so "Open With WaveCrux" appears in the system share sheet. The filesystem picker is a secondary path on mobile.
- **Mobile memory management is explicit.** iOS and Android have tighter memory budgets. The `MobileMemoryGuardService` monitors memory via `MemoryStatsService` and unloads non-visible signal data when approaching device limits. Large file warnings (100 MB phone, 250 MB tablet) are shown before loading. OS memory-pressure callbacks (iOS `didReceiveMemoryWarning`, Android `onTrimMemory`) reach Dart through Flutter as `didHaveMemoryPressure`, which triggers graceful unloading — there is no app-specific native code for it.
- **Rust FFI runs on a background isolate.** All wellen calls happen off the UI thread. The `WellenProvider` service manages the isolate lifecycle and exposes async query methods to Dart.
- **Wellen-WASM is the web parser.** On Flutter Web (where dart:ffi is unavailable), the `WellenWasmProvider` service uses the wellen crate compiled to WebAssembly. Both providers implement the same `WaveformDataSource` interface — the UI doesn't know or care which backend is active. If the WASM module fails to load, the open path raises `WebAssemblyRequiredError` and the canvas centre shows a "WebAssembly is required" guidance UI; there is no Dart-side fallback.
- **Signal data is lazily loaded.** Following wellen's architecture, signal value data is only decompressed when a signal is added to the viewer. The hierarchy (scopes and variable names) loads immediately; value data loads on demand.
- **Time-driven update bus.** When the cursor moves, `cursorStateProvider` (in `lib/features/cursors/providers/`) publishes the new cursor state, and derived providers such as `signalValueAtCursorProvider` follow it. All visible panels (waveform, value column, Stage widgets, source annotation) react via `ref.watch`. No manual notification wiring.
- **Plugin interfaces are defined in domain.** `ProtocolDecoder` and `StageWidget` interfaces live in `lib/domain/interfaces/`. Implementations (built-in or user-supplied) register via `DecoderRegistry` / `StageRegistry` in `lib/plugins/`.
- **GTKWave compatibility is a first-class concern:**
  - WaveCrux reads GTKWave's `.txt` translate filter file format. Users' existing filter libraries work without modification.
  - WaveCrux imports GTKWave `.gtkw` session files (signal lists, groups, colors, display formats, zoom, markers). This is a key migration enabler.
  - FSDB files are supported via conversion only: if Synopsys `fsdb2vcd` is in `$PATH`, WaveCrux offers to convert FSDB → VCD on open, then VCD → FST when GTKWave's `vcd2fst` is also available (otherwise the VCD is opened). No native FSDB reader (format is proprietary Synopsys IP). Desktop only; the web build explains that FSDB needs the desktop app.
- **Session files are human-readable JSON.** The `.wavecrux` session format stores signal groups, display formats, cursor positions, markers, zoom level, panel layout, and Stage panel configurations. It is not a binary format.
- **Diagnostics surfaces and live statistics strip.** WaveCrux separates introspection into three surfaces plus the statistics strip. The **Tab Diagnostics drawer** (per-tab, follows the active tab) hosts File Info, Signal Health, and Benchmark This File. The **App Diagnostics dialog** (process-wide modal) hosts Memory (overall + per-tab breakdown) and Frame Stats and exports "Copy Full Diagnostics Report". The **Pane Render Stats popover** (per-pane) is anchored to each pane's tab bar and shows paint pipeline metrics. All three surfaces live in `lib/features/diagnostics/` and are available on tablet and desktop (their action descriptors hide them on phone). The single `diagnosticsEnabledProvider` gate controls all of them; it currently returns `true` in every build mode, so it is a seam rather than a user setting. The **live statistics strip** is an ambient real-time performance monitor between the `CruxIdeLayout` region and the status bar, showing a paint-time sparkline, FPS, memory usage, and decompressed signal count. It lives in `lib/features/statistics/` (chrome from crux-shared `crux_stats_strip`) and is **desktop only** — `ViewerScreen` mounts it only when `deviceClassProvider == DeviceClass.desktop`. It is always mounted there, collapsed to a 24 px disclosure row that owns its own expand/collapse control and expanding to show the 96 px strip. Strip expansion is tracked by `statisticsStripVisible` in `PanelLayoutState` and persisted per tab in the session. The strip reads existing providers (`memoryStatsProvider`, `paneRenderStatsProvider`, and the shared `cruxMemoryStatsProvider` / `cruxFrameStatsProvider`) — no new data collection. The naming distinction is intentional: "diagnostics" = active troubleshooting actions; "statistics" = passive ambient monitoring.
- **Auto-reload on file change.** WaveCrux watches the loaded waveform file for changes and offers to reload. Essential for iterative sim+debug workflows.
- **Three-tier action discovery.** Every user-facing action is reachable through at least two tiers: (1) **toolbar icons** for one-click access to frequent actions (all device classes), (2) **menu bar** (desktop: `CruxDesktopMenuBar` — native `PlatformMenuBar` on macOS, an in-window menu bar on Windows/Linux) or the toolbar's **overflow menu** (categorized bottom sheet on phone, popup elsewhere; shown once the strip is too narrow for its buttons, which on a phone is always) for browsable categorized access, (3) **command palette** (Ctrl+Shift+P) for search-by-name access. The `ShortcutAction` enum is the single source of truth for *what actions exist*; **`descriptorFor(ShortcutAction)` in `lib/core/shortcuts/action_descriptors.dart` is the single source of truth for *where each action appears and when it is visible/enabled*** (see the "Action surface single source of truth" subsection in ARCHITECTURE.md §3.1.6). Keyboard shortcuts are displayed inline in the menu bar and command palette, teaching users shortcuts over time.

  ### IMPORTANT: Wire every new action into the action descriptor

  Adding or changing a user-facing action means editing the `descriptorFor` table — **never** re-introduce a per-surface "hidden actions" set (the old `kMenuHiddenActions` / `_kPaletteHidden`) or a per-surface `_isEnabled` / `_filteredActions` copy; those are exactly what drifted apart and were deleted. The four surfaces (`DesktopMenuBar`, `CommandPaletteDialog`, and `ViewerToolbar`'s buttons and its trailing overflow menu) consume the table via the derived selectors `groupedActionsFor` / `paletteActionsFor` / `isActionVisibleIn` / `isActionEnabled` only. Four guardrails enforce this: (1) `descriptorFor` is an **exhaustive `switch`** — a new `ShortcutAction` value fails to compile until a case is added; (2) `test/core/shortcuts/action_surface_conformance_test.dart` fails if any surface diverges from the table; (3) gating inputs are added as fields on `ActionContext` (built by `actionContextProvider`), not read ad-hoc inside a surface; (4) `test/static/action_reachability_guard_test.dart` fails if a surface's widget stops being loaded from `lib/main.dart` or constructed, or if any other file reads a surface — a surface declared by ninety-odd actions was once rendered by a widget mounted nowhere. Toolbar placement stays opt-in: set `surfaces: {…, ActionSurface.toolbar}` in the descriptor *and* tag the `ViewerToolbar` button with `action:` so the conformance test can find it.

## Verification Documentation

Every release of WaveCrux is gated by a manual end-user verification pass against the documents in [`verification/`](verification/):

- **[`verification/VERIFICATION_GUIDE.md`](verification/VERIFICATION_GUIDE.md)** — detailed pre-release verification reference (step-by-step instructions, fixture inventory, diagnostics-assisted checks, edge cases, automation assessment per test).
- **[`verification/VERIFICATION_CHECKLIST.md`](verification/VERIFICATION_CHECKLIST.md)** — quick sign-off bullet list for each release.
- **[`verification/fixtures/`](verification/fixtures/)** — committed VCDs, GTKW files, cocotb logs, Stage demos, and `.expected.json` / `.expected_transactions.json` companions used by both manual and automated verification.

### IMPORTANT: New features must update the verification documents in the same change

When you implement a new user-facing feature, change behavior visible to end users, or fix a bug whose regression is non-obvious from code alone, the same change set MUST:

1. Add or update the relevant **Section** in `verification/VERIFICATION_GUIDE.md` covering: what it does (in plain language an HDL engineer would recognize), setup, step-by-step expected behavior, diagnostics-assisted verification, edge cases, and an Automation Assessment table.
2. Add or update the corresponding **bullet** in `verification/VERIFICATION_CHECKLIST.md` so the next pre-release sign-off catches the new surface.
3. If the feature needs a new fixture, commit it under `verification/fixtures/<category>/` alongside any `.expected.json` companion. Existing test-suite fixtures under `test/fixtures/` may be copied or referenced — duplicates are acceptable to keep the verification tree self-contained.
4. Each verification entry should be **automation-aware**: the Automation Assessment column flags whether the test is a strong integration-test candidate, a hybrid (numeric thresholds with CI tolerance), or remains manual (UX feel, cross-browser, OS-level integration). One of the goals of the verification documents is to drive the integration-test backlog.

A feature that ships without a verification entry is a code-review-blocking defect — it means we cannot include the feature in the next release sign-off without re-deriving the test plan from scratch.

If a feature is Pro/Enterprise rather than Open Core, its verification entry lives with the closed-source Pro overlay, not here.

## User documentation lives in `docs-site/`

`docs-site/docs/` (MkDocs Material) is the source of truth for user
documentation, published at `https://docs.wavecrux.app`. A change to
user-visible behaviour — a label, shortcut, flag, config key, file
format, tier or platform availability — updates the affected page in the
same change. Build with `mkdocs build --strict` from `docs-site/` (pinned
versions in `.github/workflows/docs.yml`); CI fails a broken link or
anchor. Keep page file names stable: in-app help links point at them.

## FFI / WASM Architecture

```
┌─────────────────────────────────────────────────────┐
│  Flutter UI (main isolate / JS event loop)          │
│  All widgets, providers, rendering                  │
├─────────────────────────────────────────────────────┤
│  WaveformDataSource interface                       │
│  ├── WellenProvider     (desktop/mobile, FFI)        │
│  │   └── Communicates with background isolate       │
│  ├── WellenWasmProvider (web, WASM)                  │
│  │   └── dart:js_interop → globalThis.waveCruxWellen │
│  (No web Dart fallback; a WASM load failure          │
│   surfaces WebAssemblyRequiredError.)                │
├─────────────────────────────────────────────────────┤
│  Background Isolate (desktop/mobile only)           │
│  └── dart:ffi calls into native library             │
├─────────────────────────────────────────────────────┤
│  Rust shared library (.so / .dylib / .dll) — FFI     │
│  (iOS: static lib in WellenFFI.xcframework)          │
│  └── wellen_ffi crate                                │
│      ├── wellen (VCD + FST + GHW)                    │
│      ├── Multi-threaded VCD parsing (rayon)          │
│      ├── LZ4-compressed signal storage               │
│      └── lxt2fst crate, linked in — LXT/LXT2 → FST   │
├─────────────────────────────────────────────────────┤
│  WebAssembly module (web/wasm/wellen_wasm_bg.wasm)  │
│  └── wellen_wasm crate (wasm-bindgen)                │
│      ├── wellen (VCD + FST + GHW)                    │
│      └── Single-threaded — no COOP/COEP needed       │
│  (web/wasm/lxt2fst_bg.wasm — lxt2fst, lazy-loaded)   │
└─────────────────────────────────────────────────────┘
```

### Building the web WASM bridge

```bash
dart run tool/build_web_wasm.dart      # wellen_wasm: rebuilds + copies into web/wasm/
dart run tool/build_lxt2fst_wasm.dart  # lxt2fst: same pipeline
```

The built bundles are committed under `web/wasm/`, so a plain
`flutter build web` needs no Rust toolchain. CI rebuilds both from source in its
`wasm` job and the `build-web` job builds against those artifacts. Gzipped
budgets — 1.5 MiB for `web/wasm/wellen_wasm_bg.wasm`, 400 KiB for
`web/wasm/lxt2fst_bg.wasm` — are enforced by
`test/native/wellen_wasm_bundle_size_test.dart` and
`test/native/lxt2fst_wasm_bundle_size_test.dart`.

## Git Conventions

- Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`
- Branch naming: `feature/xxx`, `fix/xxx`
- `main` is always deployable

## Changes land through pull requests

Until the 1.0 code freeze, maintainers commit directly to `main`. From the
code freeze on, every change — by anyone — lands through a pull request
whose description documents the issue or feature, the fix or
implementation, how it was verified (tests added, CI gates passed), and
the user documentation updated in the same PR. Contributors sign a CLA
before a first merge, as described in `CONTRIBUTING.md`.

## Licensing

WaveCrux open core — this repository — is licensed under the Apache License 2.0
([`LICENSE`](LICENSE); `license: Apache-2.0` in `pubspec.yaml`). Hand-written
Dart sources carry an `SPDX-License-Identifier: Apache-2.0` header — add one to
every new file. Third-party
attributions are in [`NOTICES`](NOTICES), and use of the WaveCrux name and
marks is covered by [`TRADEMARK.md`](TRADEMARK.md). Pro and Enterprise
features are built in a separate, closed-source overlay that consumes this
repository as a dependency; nothing in this tree depends on it.

**Stage.** The Stage widget **capability** is free in open core — anyone can
author and run custom Rive-backed widgets through the open-core SDK
(`lib/features/stage/sdk/`, `lib/features/stage/runtime/`,
`lib/features/stage/bundle/`, `lib/features/stage/settings/`) plus the
Tachometer reference widget. Pro adds curated widget *content*. The
free/premium boundary is at that content level, not the capability — the same
pattern as user-contributed protocol decoders.

## Suite UI consistency (MANDATORY for any UI change)

The four Crux apps (WaveCrux, NetCrux, LintCrux, SimCrux) are built as if they
were ONE app. Before touching any UI surface:

1. **Mirror-check:** a change to a shared surface (menus, toolbar, status bar,
   docks/panels, welcome screen, window chrome, Settings, dialogs, shortcuts,
   shared l10n keys) must be applied to the OTHER THREE apps in the same
   session — or explicitly flagged as pending in your final report. Never
   diverge silently. The sibling apps live at
   sibling checkouts of `wavecrux`, `netcrux`, `lintcrux` and `simcrux`.
2. **New surface:** adding a dialog / panel / dock tab / settings category /
   banner here requires answering "do the other three apps need this?" — and
   generic chrome starts life in crux-shared (`crux_dock`, `crux_workspace`,
   `crux_settings_ui`, `crux_cxp_ui`, ...), never as an app-local copy.
3. **Canon details:** WaveCrux is the canonical app when the four differ.
   Workflow dialogs are `barrierDismissible: false`; settings categories use
   the same order and icons in all four apps; l10n keys for shared strings use
   WaveCrux-style names in all four apps; the Language picker requires
   `MaterialApp.locale` wiring.
4. **Verify like CI:** `flutter analyze --fatal-infos --fatal-warnings` (the
   crux-shared Consumer CI fails on infos; plain `dart analyze` won't) + the
   full test suite for every repo you touched.
5. **User docs:** if you changed a user-visible usage model (panel
   behavior, shortcut, settings layout, menu location, dialog flow), update
   the affected `docs-site/docs/` page in the same change — grep it for the
   OLD wording — and check the other three products' user docs when the
   change was suite-wide.
