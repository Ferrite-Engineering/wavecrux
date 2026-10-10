# WaveCrux — Architecture & Engineering Manual

> A modern, high-performance, multi-platform waveform viewer built with Flutter and Rust.
>
> **Domain:** wavecrux.app

**Status:** Open-core engineering manual. Architectural and convention reference for contributors and maintainers.
**Last Updated:** See git log for the latest revision.

---

## How this document is organized

This is the engineering reference for the open-core wavecrux project: tech stack, target platforms, mobile UI standards, architectural rules, coding conventions, design system, the extension-point seams that the closed-source Pro overlay plugs into, and the project glossary.

Section numbers are stable because source comments cite them (`// Per ARCHITECTURE.md §3.1.8.X`). The numbering has gaps, and sections are never renumbered to close them, so an existing citation keeps pointing at the same section.

---

## 2. Tech Stack

### 2.1 Core Framework

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **UI Framework** | Flutter | Single codebase for Linux, macOS, Windows, iOS, Android, Web. A custom `RenderObject` for high-performance waveform rendering (§2.3). Material 3 for polished, native-feeling UI. |
| **Language** | Dart + Rust | Dart for UI and application logic. Rust for performance-critical parsing and signal storage via wellen. |
| **State Management** | Riverpod (with code generation) | Reactive model ideal for time-driven updates (cursor moves → all panels update). No BuildContext dependency — critical for background isolate communication. |
| **Routing** | go_router | Declarative routing for multi-pane desktop layouts and deep-link support. |

### 2.2 Waveform Engine

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **Parser (desktop / mobile)** | wellen (Rust) via dart:ffi (`WellenProvider`) | Multi-threaded VCD parsing, FST and GHW support, lazy signal loading, LZ4-compressed storage. The same engine Surfer uses — proven at multi-GB scale. |
| **Parser (web)** | wellen (Rust) via WebAssembly (`WellenWasmProvider`) | The same `wellen` crate, compiled to wasm32 via wasm-bindgen (`native/wellen_wasm/`), called from Dart via `dart:js_interop`. Single-threaded but otherwise identical to the FFI build — gives the web target full VCD/FST/GHW parity with desktop/mobile. If the WASM module fails to load, `WaveformSourceNotifier` raises `WebAssemblyRequiredError` and the canvas centre shows a "WebAssembly is required" guidance UI; there is no Dart-side fallback parser. |
| **Streaming VCD (desktop)** | Pure-Dart incremental parser (`StreamingVcdService`) | The one non-wellen `WaveformDataSource`: `--interactive` / `--stdin` / `--pipe <path>` feed a live VCD byte stream whose hierarchy appears after `$enddefinitions` and whose value changes accumulate as the simulation runs (`lib/services/waveform/streaming_vcd_service.dart`, bound per tab by `streamingSourceProvider`). Not a fallback for wellen — it exists because wellen parses complete files. |
| **FSDB (desktop)** | External-tool conversion (`FsdbConversionService`) | FSDB is proprietary; WaveCrux does not read it. When the user opens an `.fsdb` on desktop, the service looks for `fsdb2vcd` (Synopsys) and `vcd2fst` (GTKWave) on `PATH`, converts to FST, and caches the result next to the source. Rejected on web. |
| **Legacy LXT/LXT2 read path** | clean-room `lxt2fst` crate (Rust) — convert-on-open to FST | `.lxt` (2003 streaming) and `.lxt2` (2005 block-indexed) captures are converted to an FST by the `lxt2fst` crate at file-open time and then handed to wellen exactly like any other FST — see §2.2.1. The crate is GPLv2-clean (GTKWave's reader source was not consulted); reader and writer modules are kept separate so the reader portion can graduate into a wellen contribution without re-architecture. Linked into `native/wellen_ffi` for FFI — no separate native artefact — and built with `dart run tool/build_lxt2fst_wasm.dart` for web; gzipped WASM budget: 400 KiB. |
| **FFI Bridge** | Custom Rust crate (`wellen_ffi`) | C-ABI wrapper around wellen (`native/wellen_ffi/src/lib.rs`, header `native/wellen_ffi/wellen_ffi.h`) exposing lifecycle, hierarchy queries, signal loading, value queries, and the diagnostics counters of §8.8. Entry points that can panic run inside `catch_unwind` (§8.5). |
| **WASM Bridge** | Custom Rust crate (`wellen_wasm`) | wasm-bindgen wrapper around wellen. Method-for-method parallel to `wellen_ffi` so the Dart-side `WellenWasmProvider` matches `WellenProvider` (FFI) semantics exactly. Built via `dart run tool/build_web_wasm.dart`; output committed under `web/wasm/`. Gzipped budget: 1.5 MiB, enforced by `test/native/wellen_wasm_bundle_size_test.dart`. |
| **Dart Bindings** | ffigen (FFI) / `dart:js_interop` (WASM) | FFI bindings generated from `wellen_ffi.h` into `lib/native/bindings/` (`ffigen.yaml`); WASM bindings hand-rolled as `extension type`s on the wasm-bindgen output. |

#### 2.2.1 Convert-on-open for LXT / LXT2

GTKWave's legacy LXT (2003 streaming) and LXT2 (2005 block-indexed) formats predate FST and are read-only archive territory — engineers carry `.lxt2` files from older projects but new captures are produced as VCD or FST. Rather than maintain a streaming reader for two frozen formats inside the hot path, WaveCrux **converts on open**: a magic-byte probe at file-open time routes `.lxt` / `.lxt2` through a small dedicated Rust crate that emits an FST, then the existing wellen pipeline takes over and the rest of the application (canvas, decoders, Stage, export) sees a plain FST. Once converted, the file lives forever in the FST hot path with all its streaming and lazy-load benefits.

**Crate boundary — `native/lxt2fst/`.** The clean-room crate (Apache-2.0, no GPL ancestry) splits **reader** and **writer** into separate modules so the reader portion can graduate into a wellen contribution and routing can switch to native, with the writer scaffolding remaining only as long as needed:

* `src/lxt2.rs` — LXT2 reader (block-indexed): magic + version + numfacs + name-section prefix-decompression + 16-byte/facility geometry + block-prefix walking + per-block time-table reconstruction, plus **full value decode** via `src/value_decode.rs`.
* `src/value_decode.rs` — the LXT2 per-facility value-change decoder: multi-granule block framing, the operator alphabet (set-0/1, complement, shifts, ±1..4 deltas, all-x/all-z, MVL string literals), the footer bitmask dictionary, the Verilog x/z left-extension rule, and real (`f64`) facilities. Clean-room: reverse-engineered and **differentially fuzz-validated against GTKWave's own `vcd2lxt2` encoder** (`tool/lxt2_value_fuzz.py`) — `lxt2_read.c` (GPLv2) is never consulted. Strict-by-design: a block whose structure does not validate is not emitted with guessed values; the converter falls back to a safe initial-value record, so a converted trace is never silently wrong. Scalars, bit-vectors with x/z, reals, and multi-granule/multi-block files round-trip to FST exactly.
* `src/lxt.rs` — LXT-classic reader (2003 streaming): magic + trailing gzip dictionary-section enumeration (NAMES, GEOMETRY, chain-head table, index) + timescale exponent + max-time. NAMES and GEOMETRY share the LXT2 wire layout, so this module reuses `lxt2::{parse_names, parse_geometry, Geometry, build_hierarchy, inflate_gzip_at}`. It emits the full hierarchy and the real per-facility transitions decoded by `src/lxt_value_decode.rs` (falling back to a bounded `x`-state time table only where the stream does not validate, so `.lxt` files always open cleanly — no wellen panic).
* `src/lxt_value_decode.rs` — the LXT-classic *streaming* value-change decoder (a separate format from LXT2's block/granule codec): the inline `[op][facref][value]` record framing, the multi-byte back-pointer (`1 + (op>>4)` big-endian facref bytes), the per-facility chain-head table that resolves facility identity (the stream is in VCD-declaration order, the name index alphabetical), the operator alphabet (binary + 2-bit-per-symbol 4-state literals; all-0/1/z/x), little-endian f64 reals, and the per-timestep time index. Clean-room: reverse-engineered and **differentially fuzz-validated against GTKWave's own `vcd2lxt` encoder** (`tool/lxt_classic_value_fuzz.py`) — `lxt_read.c` (GPLv2) is never consulted. Strict, like the LXT2 path: an unvalidated structure falls back to a safe `x`-state emission rather than a guessed value, so a converted `.lxt` is never silently wrong. Scalars, bit-vectors with x/z, reals, and many-facility / wide-back-pointer files round-trip to FST exactly.
* `src/fst_writer.rs` — façade over the BSD-3 `fst-writer` crate (sibling of the `fst-reader` wellen uses internally), serializing either to a file (FFI) or to an in-memory buffer (web). The single dependency stays on one well-tested non-GPL FST stack instead of fragmenting onto a fresh in-tree writer.
* `src/progress.rs` — throttled `(done, total)` callback: at most one report per 1 % step, and additionally per 50 ms on native builds (the timer is compiled out on wasm32). LXT2 reports `(blocks_done, total_blocks)` straight from the block-index header; LXT classic reports only a start and an end event. Both reach the Dart caller through a single C-ABI / wasm-bindgen surface (`lxt2fst_convert`, `lxt2fstConvert`).

**Dart-side integration — `lib/services/waveform/`.** The Dart layer mirrors the wellen FFI / WASM split:

* `legacy_format_detector.dart` — `LegacyFormatDetector.detectFile` / `detectBytes` reads the first 2 bytes and classifies LXT vs LXT2 vs not-legacy. Runs before the wellen open path is invoked.
* `lxt2fst_converter.dart` — conditional re-export shim. On `dart:io` hosts resolves to `lxt2fst_converter_io.dart` (FFI + background isolate, bindings in `lib/native/bindings/lxt2fst_bindings.dart`); on `dart:js_interop` resolves to `lxt2fst_converter_web.dart` (main-thread wasm-bindgen call); on neither resolves to a stub whose methods throw `UnsupportedError`. Public API: `Stream<ConversionProgress> convertPath({inPath, outPath})` on `dart:io` hosts — cancelling the subscription cancels the conversion — and `Future<Uint8List> convertBytes(bytes, {onProgress})` on web; each throws `UnsupportedError` on the other host. Shared types live in `lxt2fst_conversion_types.dart`; the Riverpod wiring in `lxt2fst_providers.dart`.
* `lxt2fst_cache.dart` — `Lxt2FstCache.resolve(sourcePath)` returns an `Lxt2CacheDecision` with the FST path, whether it is a cache hit, and whether it is the sibling-of-source or app-cache location. **Strategy:** a sibling `<basename-without-extension>.fst` next to the source first when the source directory is writable (`foo.lxt2` → `foo.fst`); fall back to `${appCacheDir}/legacy_conversions/<hash-of-source-path>.fst` (a 16-hex-digit double FNV-1a hash) when it is not (sandboxed cloud mount, read-only share, removable media). **Freshness:** a cached FST is fresh iff its mtime ≥ source mtime *and* a sidecar `.lxt2cache.json` records a matching source size — a copy with preserved mtime would otherwise look fresh. Size + mtime is a strong enough fingerprint for an archive workflow; whole-file hashing was rejected as overkill. Note the consequence of the sibling name: an unrelated `foo.fst` that already sits next to `foo.lxt2` has no sidecar, so it reads as stale and is overwritten.
* `legacy_conversion_controller.dart` — Riverpod controller (`LegacyConversionController`, `LegacyConversionEventSink`) that drives the user-visible progress dialog (`lib/widgets/legacy_conversion_progress_dialog.dart`) and emits the "successfully converted" event the banner listens for. The dialog's Cancel runs the controller's cancel hook, which cancels the conversion subscription; the open then fails with `LegacyConversionCancelledException`. The dialog is debounced by a `showAfter` delay (default 250 ms) so fast conversions never flash a dialog at the user.

**Execution model.** On desktop/mobile the converter runs on a one-shot background isolate spawned by `lxt2fst_converter_io.dart`, parallel to the wellen isolate model — the UI thread never blocks on the conversion and progress events flow back through a `SendPort`. There is no separate converter library: the Rust `wellen_ffi` crate links `lxt2fst`, so the `libwellen_ffi` every platform already builds, bundles and signs also exports the `lxt2fst_*` C ABI (on iOS, the static archive in `native/wellen_ffi/WellenFFI.xcframework`, with the symbols kept alive for `dlsym` by `native/wellen_ffi/Sources/WellenFFIKeepalive/wellen_ffi_keepalive.c`). Both the wellen provider and the converter open it through one resolver, `lib/native/wellen_ffi_library_io.dart` — bare name from the app bundle, `native/wellen_ffi/target/{release,debug}/` under `flutter test`, the process image on iOS. `test/static/wellen_ffi_bundles_lxt2fst_test.dart` guards the link, the keepalive list, the committed xcframework and each platform's rebuild inputs. On web the converter runs on the main thread, entirely in memory, and has no conversion cache — every open converts again (`WaveformSourceNotifier.openFromBytes`). `web/wasm/lxt2fst_loader.js`, loaded by `web/index.html`, publishes `globalThis.waveCruxLxt2Fst` and imports the wasm module only on the first LXT/LXT2 open; the in-memory FST output relies on a vendored fst-writer (`native/vendor/fst-writer/`) whose one addition is a constructor over any `Write + Seek` sink, since the published crate can only write to a file path.

**Banner UX.** On a successful first-open of a converted file, `LegacyFormatBanner` (`lib/widgets/legacy_format_banner.dart`, mounted in `viewer_screen.dart` above the waveform area) renders a non-modal `MaterialBanner` reading "Opened from legacy LXT/LXT2 format. Converted to FST and cached at `<path>`." A "Don't show again" action sets `AppSettings.suppressLegacyFormatBanner = true`; subsequent legacy opens skip the banner regardless of cache state. A cache hit always suppresses the banner — the user already knows about the converted `.fst` sitting next to the source. The Diagnostics → File Info panel surfaces an "Original format" row whenever `WaveformSourceNotifier.originalFormat?.isLegacy` is true, so a power user opening an `.fst` cached next to a `.lxt2` can see *why* it exists.

**`WaveformFormat` enum.** Open-core (`lib/domain/enums/waveform_format.dart`): `vcd`, `fst`, `ghw`, `lxt`, `lxt2`, `unknown`. The file picker accepts `.lxt` and `.lxt2` on desktop, mobile, and web. The CLI `wavecrux <file.lxt2>`, the web drop zone and a file dropped on the desktop window reuse the same `WaveformSourceNotifier` plumbing, so no surface needs special-casing. (The desktop window drop — `DesktopFileDropTarget` in `MaterialApp.builder`, backed by `desktop_drop` — hands its paths through `DesktopFileDropRouter` to `ViewerScreen`, which runs them through the File > Open dispatch.)

### 2.3 Rendering

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **Waveform Canvas** | Custom `RenderObject` | Bypasses the widget tree for the hot rendering path. Direct painting to canvas with GPU-accelerated compositing. |
| **Signal Value Column** | Standard Flutter widgets | Modest update frequency — standard widget tree is fine. |
| **Stage Animations** | Rive (sole supported runtime) | Vector animation format with state-machine inputs and signal binding points. The Stage widget SDK exposes a library-agnostic `StageWidgetAnimationController` interface so a future addition (e.g. Lottie) would be a one-implementation change. Lottie was evaluated and not chosen — Rive's state-machine inputs map more naturally to signal bindings, and the runtime integrates more cleanly with Flutter. |

### 2.4 Panel Layout

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **Region layout** | `CruxIdeLayout` (`crux_ide_layout`, wrapping the `panes` package's `IdeLayout`) | The suite's shared four-region shell (left / center / right over center / bottom) with resizable splitters, per-region minimum sizes, and window-fit clamping. It owns the `IdeController` and `PaneTheme`; the product supplies the region builders and a `PanelLayoutState` adapter. |
| **Dockable Panels** | `CruxDock` (`crux_dock`) | Each side and bottom region is a VS Code-style tab strip of `CruxDockEntry`s — pinned, dynamic (one per Stage panel), or on-demand (present while an analysis is active). Collapse lives on each dock's strip; a collapsed region leaves a slim restore bar. |
| **Layout Persistence** | Per-tab `PanelLayoutState` | Region visibility, sizes, active dock tabs, and dock placements are fields of the per-tab `PanelLayoutState`, captured into the tab's `.wavecrux` session sidecar by `SessionService` — not via the `panes` `save()` / `load()` API. |

### 2.5 Infrastructure

| Component | Choice | Rationale |
|-----------|--------|-----------|
| **CI/CD** | GitHub Actions (`.github/workflows/`) | Automated testing, linting, cross-platform builds, Rust native library compilation, WASM bundle-size gates. |
| **Crash / bug reporting** | No crash-reporting SDK | Bug reports go through the in-app issue reporter (`crux_issue_reporter`, §10), which pre-fills a GitHub issue with a privacy-scrubbed diagnostics report. Anonymous usage statistics are a separate pipeline (`crux_telemetry`, §10). |
| **Distribution** | Desktop builds, App Store / Google Play, static web build | Mobile store builds are cut by `scripts/release_ios.sh` / `scripts/release_android.sh`; the web build is deployed by `scripts/deploy_web.sh`. In-app update checks come from `crux_updates`. |
| **Cross-suite shared infrastructure** | [`crux-shared`](https://github.com/Ferrite-Engineering/crux-shared) (Apache 2.0, Melos workspace) | Held as a Git submodule at `./crux-shared/` and consumed through `path:` dependencies — every `crux_*` package in `pubspec.yaml` comes from it. The largest are `crux_workspace` (the generic `Workspace<P>` domain, persistence, per-tab / per-pane container managers, multi-window scaffolding, and the `PaneHost<P>` / `ViewerTabBar<P>` / `EmptyCanvasState` widgets — WaveCrux is its reference adopter), `crux_ide_layout` + `crux_dock` (§2.4), `crux_license`, `crux_telemetry`, `crux_issue_reporter`, `crux_cxp`, `crux_theme`, `crux_settings`, and `crux_shortcut_action` / `crux_command_palette` / `crux_menu_bar`. |


---

## 3. Target Platforms

| Platform | Notes |
|----------|-------|
| **Linux** | x86_64. Most HDL engineers work on Linux. |
| **macOS** | Universal binary (Intel + Apple Silicon); the wellen library is built universal by `scripts/build_wellen_universal.sh`. |
| **Windows** | x86_64. |
| **Web** | wellen compiled to WASM (§2.2). Lets a CI report link straight to a waveform. |
| **iOS / iPadOS** | Review waveforms on a tablet during design reviews. Store builds via `scripts/release_ios.sh`. |
| **Android** | Quick waveform checks after a CI notification. Store builds via `scripts/release_android.sh`. |

**Desktop file association.** macOS registers the document types in
`macos/Runner/Info.plist` (the Pro overlay carries its own copy of the same
list); Linux writes a `.desktop` entry whose `MimeType=` list comes from
`lib/core/platform/linux_desktop_identity.dart`. WaveCrux answers for its own
formats, but the suite manifest `<design>.crux-project` is registered
`LSHandlerRank: Alternate` in all four products — none of them owns it — so a
double-clicked manifest opens whichever product the user has chosen, and
**Get Info → Open with → Change All** is how they choose. On the same
reasoning, only the session and the pack are declared under
`UTExportedTypeDeclarations`: VCD, FST, GHW, the GTKWave save file and the
LXT/LXT2 dumps are other projects' formats, so WaveCrux imports them.

### 3.1 Mobile Strategy

Mobile support targets engineers reviewing and investigating simulation results — not authoring debug sessions from scratch. The primary mobile use cases are: opening a `.wavecrux` session file received from a colleague, exploring waveforms during a design review meeting (tablet), and quick signal checks after a CI notification (phone). Interactive streaming VCD (`--stdin` / `--pipe`) is desktop-only because it is reachable only from the command line. The WCP remote-control server is **not** desktop-only: its settings section is offered on mobile too, and the lifecycle bridge starts it on every host except web.

#### 3.1.1 Device Classification

WaveCrux defines four device classes (`DeviceClass`, `lib/domain/enums/device_class.dart`), used to select layout and feature surface:

| Device Class | Breakpoint | Layout Strategy |
|---|---|---|
| **Phone** | Width < 600 dp | Full-width canvas; side and bottom regions force-hidden and reached through a drawer and a bottom sheet |
| **Phone landscape** | Width ≥ 600 dp and height < 500 dp | Same as phone — tablet-class width, but too short for persistent side panels |
| **Tablet** | 600 dp ≤ width < 1200 dp and height ≥ 500 dp | Multi-pane `CruxIdeLayout` (narrower pane defaults below 800 dp — §3.1.7) |
| **Desktop** | Width ≥ 1200 dp and height ≥ 500 dp | Multi-pane `CruxIdeLayout` with resizable splitters |

`DisplaySizeFeed`, mounted once inside `MaterialApp.builder`, pushes `MediaQuery.sizeOf` into `displaySizeProvider`; `deviceClassProvider` classifies that size through the shared `deviceClassForSize` function (`lib/shared/layouts/device_class_provider.dart`). Layout widgets watch `deviceClassProvider`, so the classification is re-evaluated on window resize, orientation change, and split-screen entry/exit. See §3.1.7 for why height matters.

**Native-desktop-host floor.** On a native desktop OS (macOS / Windows / Linux) the class is floored to **Desktop** regardless of window size: a small desktop window keeps the full IDE layout and shrinks only to the OS-enforced window minimum (800×500), it never reflows to the Tablet/Phone presentation. The size breakpoints above therefore govern **web and mobile** only; on desktop the host wins. This is the single place the layout consults the host platform — via `isDesktopHostPlatform` (`defaultTargetPlatform`) inside `deviceClassForSize`. The desktop pane minimums (150 + 150 dp sides + 120 dp centre) fit inside the 800 dp window minimum, so the floor never produces overflow. `deviceClassForSize` defaults to Desktop before the first size is known; a reader outside the widget tree that cannot afford that default (telemetry's `form_factor`) uses `resolvedDeviceClassForSize`, which returns `null` instead.

#### 3.1.2 Phone Layout

On phone (and phone landscape), the waveform canvas occupies the full screen width — it needs every pixel. `CruxIdeLayout` is still the layout, but its side and bottom regions are force-hidden (§3.1.8.6), and the panels are reached as follows:

- **Signal tree browser** → `Scaffold.drawer`, opened by the status bar's left chevron
- **Value column** → `InlineCursorValueOverlay`, values drawn on the canvas lanes at the cursor (no modal drawer)
- **Bottom dock** (transaction table, Stage panels, analyses) → `WaveCruxBottomDockSheet` in a modal bottom sheet, opened by the status bar's centre chevron
- **Command palette** → the same dialog as on desktop
- **Settings** → standard full-screen route

#### 3.1.3 Tablet Layout

On tablet, WaveCrux shows the desktop multi-pane layout — signal tree on the left, waveform canvas centre, value column on the right, bottom dock below — with the size-aware pane defaults of §3.1.7 (narrower below 800 dp). There is no tablet-specific drawer: a tablet in portrait keeps its side panes.

#### 3.1.4 File Loading on Mobile

On mobile, the primary file loading path is the system document picker and "Open with", not filesystem browsing:

- **"Open with" / AirDrop** — a file received through email, chat, or AirDrop opens in WaveCrux; on Android this is the `ACTION_VIEW` intent (there is no `ACTION_SEND` share-target filter). Incoming files are copied into app storage (`IncomingFileService`).
- **Cloud storage** — iCloud Drive, Google Drive, and other document providers are accessible through the system file picker
- **File association** — iOS registers `.vcd`, `.fst`, `.ghw`, `.lxt`, `.lxt2`, `.wavecrux` (`ios/Runner/Info.plist`); Android registers the same plus `.wavecruxpack` (`android/app/src/main/AndroidManifest.xml`)
- **Recent files** — kept as local paths to the copied files and shown on the empty-canvas state alongside the rest of the workspace empty-state UI
- **Workspace restoration on phone:** the auto-saved workspace is honored on phone, but the layout is forced single-tab. If the workspace at quit had N > 1 tabs, the most recent active tab is restored and the rest are listed under "Other tabs from your last session" on the empty-canvas state for one-tap opening (`lib/features/workspace/workspace_restore_strategy.dart`). Tab bars are not rendered on phone.

#### 3.1.5 Memory Management on Mobile

iOS and Android have significantly tighter memory budgets than desktop workstations. Two mechanisms handle this, both keyed on device class (phone, phone landscape, tablet) — so an iPad large enough to classify as Desktop gets neither:

- **File size warning** — `MobileMemoryGuardService.shouldWarnBeforeLoad` compares the file against fixed limits (100 MB on phone, 250 MB on tablet) before opening, and `LargeFileWarningDialog` offers "Load Anyway".
- **Memory guard** — `MobileMemoryGuardNotifier` (`lib/features/viewer/providers/mobile_memory_guard_provider.dart`) polls process RSS every 5 s against warning / critical thresholds (300 / 500 MB phone, 600 / 1000 MB tablet). At warning or above it unloads signals that are loaded but not in the signal list, least-recently-added first. It is also a `WidgetsBindingObserver`: Flutter's `didHaveMemoryPressure` (which surfaces iOS `didReceiveMemoryWarning` and Android `onTrimMemory`) triggers an immediate critical-severity pass. Either path shows a snackbar naming what was released. The thresholds and unload policy live in the stateless `MobileMemoryGuardService`.

#### 3.1.6 Mobile Feature Matrix

On a mobile host, Open Core builds hide every Pro- and Enterprise-tier action from every surface (`tierGatedActionsAvailableProvider`); the matrix below records where each capability is offered.

| Feature | Phone | Tablet | Desktop |
|---|---|---|---|
| File loading (VCD/FST/GHW via wellen FFI) | ✓ | ✓ | ✓ |
| Workspace (auto-saved, restored on launch) | ✓ (single-tab) | ✓ | ✓ |
| Multi-tab workspace | — | ✓ | ✓ |
| Split-pane viewing | — | ✓ (width ≥ 1000 dp) | ✓ |
| Empty-canvas startup state | ✓ | ✓ | ✓ |
| Export tab as `.wavecrux` session | ✓ | ✓ | ✓ |
| Named workspace save/load (`.wavecrux-workspace`) | ✓ (menu / palette only) | ✓ | ✓ |
| GTKWave `.gtkw` session import | ✓ | ✓ | ✓ |
| Waveform viewing + navigation | ✓ (full screen) | ✓ (multi-pane) | ✓ (multi-pane) |
| Touch gestures (pinch zoom, drag pan) | ✓ | ✓ | — (mouse/kbd) |
| Signal tree browser | ✓ (drawer) | ✓ (side dock) | ✓ (side dock) |
| Value column | ✓ (inline at cursor) | ✓ (side dock) | ✓ (side dock) |
| All display formats + translate filters | ✓ | ✓ | ✓ |
| Built-in decoders (SPI, I2C, UART, AXI4-Lite, APB, AHB-Lite, Wishbone, SPI Flash, RISC-V instruction trace) | ✓ | ✓ | ✓ |
| User decoder plugins (FFI) | — | — | ✓ |
| Transaction table + bottom dock (Stage panels, analyses) | ✓ (bottom sheet) | ✓ (bottom dock) | ✓ (bottom dock) |
| Cursors + markers | ✓ | ✓ | ✓ |
| Signal search + command palette | ✓ | ✓ | ✓ |
| Desktop menu bar | — | — | ✓ (native desktop hosts) |
| Toolbar overflow menu | ✓ (bottom sheet) | ✓ (popup) | ✓ (popup) |
| Export (VCD/PNG/SVG/clipboard) | ✓ | ✓ | ✓ |
| Waveform diff / comparison | ✓ | ✓ | ✓ |
| X-trace (unknown origin finder) | ✓ | ✓ | ✓ |
| Switching activity analysis | ✓ | ✓ | ✓ |
| FSM state visualization | ✓ | ✓ | ✓ |
| Multi-signal pattern search | ✓ | ✓ | ✓ |
| Cocotb log file correlation | ✓ | ✓ | ✓ |
| Stage panel (built-in widgets) | ✓ (bottom sheet) | ✓ | ✓ |
| Stage playback transport | — | ✓ | ✓ |
| Cross-probe (CXP) panel | — | ✓ | ✓ |
| RTL source panel / stems generation | — | — | ✓ (in-app panel) — also the VSCode extension, on every desktop VSCode runs on |
| Interactive VCD (stdin/pipe) | — | — | ✓ |
| Remote control API (WCP server) | ✓ | ✓ | ✓ (not on web) |
| Tab Diagnostics drawer (per-tab) | — | ✓ | ✓ |
| App Diagnostics dialog (process-wide) | — | ✓ | ✓ |
| Pane Render Stats popover (per-pane) | — | ✓ | ✓ |
| `Tools → Generate Test VCD…` | ✓ | ✓ | ✓ |
| Live statistics strip | — | — | ✓ |
| Pro- / Enterprise-tier actions (supplied by the Pro overlay) | hidden in Open Core on mobile hosts | hidden in Open Core on mobile hosts | ✓ (badged) |

**Rationale for key exclusions:**

- **Tier-gated actions on mobile (hidden):** Open Core ships the full `ShortcutAction` enum, including the Pro and Enterprise actions, but its handlers for them are no-ops. On desktop the badged item has a working upgrade path behind it; on a mobile store build an enabled item that does nothing reads as an unfinished feature, so `tierGatedActionsAvailableProvider` hides those actions from every surface on mobile hosts. An overlay that implements them overrides the provider to `true`.
- **RTL source annotation (the in-app panel is desktop only; the VSCode extension is not):** The *in-app* RTL Source panel is desktop-only because it opens a second source-sized pane beside the waveform, and that needs screen real estate a phone or tablet does not have. That rationale is about the panel, not about the capability — and it stops applying the moment the source view is not ours to place. Inside VSCode the editor **is** the source view, already open, already scrolled to the line the engineer is reading, so the WaveCrux extension annotates it directly: signal values render as inline decorations in the user's own Verilog/VHDL, following the waveform cursor (`edacrux.rtlAnnotation.enabled`, off until opted into; command **Toggle RTL Value Annotation**). The extension lives in the separate `crux-vscode` repository (`crux-vscode/packages/host-core/src/annotate/`); The app's own half of it is `lib/services/host_bridge/host_annotation_value_service.dart`, which answers the extension's standing value query at the cursor.
- **Interactive VCD (desktop only):** Streaming mode is entered only through the `--stdin` / `--interactive` / `--pipe` command-line flags, which a mobile launch cannot pass.
- **Diagnostics surfaces (tablet+ only):** Development/debug diagnostics are not useful on phone. On tablet they serve engineers profiling mobile performance. See §8.8.
- **Live statistics strip (desktop only):** The statistics strip provides ambient performance monitoring (FPS, memory, paint time) during active debugging sessions — a workstation activity, and its expanded height would consume scarce vertical space on smaller screens. The underlying providers and services exist on all platforms (they power the three diagnostics surfaces); only the strip UI is desktop-gated.
- **Desktop menu bar / toolbar overflow:** `CruxDesktopMenuBar` (`crux_menu_bar`) is chosen by host OS, not device class: macOS gets the system `PlatformMenuBar`, Windows and Linux an in-window menu bar, web and mobile none. The toolbar (`CruxToolbar`) shows an overflow button on every device class whenever its strip overflows; phone presents the overflow as a bottom sheet, other classes as a popup menu. Both are views into the same `ShortcutAction` registry, and the command palette remains the universal discovery tool on all device classes.

##### Action surface single source of truth

The four action-discovery surfaces — toolbar, desktop menu bar, toolbar overflow menu, command palette — do **not** each decide what to show or when to enable it. A single declarative table, `descriptorFor(ShortcutAction)` in `lib/core/shortcuts/action_descriptors.dart`, maps every action to an `ActionDescriptor` (`lib/core/shortcuts/action_descriptor.dart`) declaring: which `ActionSurface`s it appears in, its required `LicenseTier`, a structural `isVisible(ActionContext)` predicate (device-class / availability gating that hides it everywhere), and a `requires` list of atomic `ActionRequirement`s (transient gating — file loaded, diagnostics on, pane count, collaboration session state). `isEnabled(ActionContext)` is derived — every requirement satisfied — and `unmetRequirement(ActionContext)` returns the first one that is not, which is how a refused *keyboard* shortcut (the fifth surface) explains itself: the viewer maps the unmet requirement to a localized hint (`ActionRequirementHint.hint`) and shows it in a snackbar, since a key press has no greyed label to speak for it. The shared `actionContextProvider` builds one `ActionContext` from app state and every surface reads it.

Presentation policy: `isActionVisibleIn(action, s, ctx)` is true iff `surfaces.contains(s) && isVisible(ctx)` **and** the action's tier is usable in this build — when `ActionContext.tierGatedActionsAvailable` is false (Open Core on a mobile host, §3.1.6) every action whose `requiredTier` is not `openCore` is hidden. Menu / overflow render visible actions and grey out the disabled ones; the command palette omits disabled actions (it has no greyed state); the toolbar (a curated opt-in subset, tagged by `ValueKey(action)`) renders its buttons and enables them per `isEnabled` — it does not consult `isVisible`, so a toolbar button's device gating is the toolbar's own responsibility. The surfaces call the derived selectors `groupedActionsFor` / `paletteActionsFor` / `isActionVisibleIn` / `isActionEnabled`, and the keyboard guard calls `unmetActionRequirement`. Tier is shown as a `WaveCruxFeatureTierBadge` in the command palette and as a localized text suffix (`tierLabelSuffix`) in the menu bar and the toolbar overflow menu.

`descriptorFor` is an **exhaustive `switch`** (like `ShortcutAction.category` / `.label`): adding a `ShortcutAction` fails to compile until a descriptor case exists, and `test/core/shortcuts/action_surface_conformance_test.dart` checks the surfaces against the table. Never re-introduce a per-surface "hidden actions" set or `_isEnabled` copy. `ActionRequirement` is likewise exhaustive in two places — its predicate switch and its L10N hint switch — so a new requirement cannot ship without both a definition and a user-facing message.

#### 3.1.7 Device Orientation

Waveforms are inherently horizontal — time flows left to right, and more horizontal pixels means more visible transitions and better time resolution. Orientation is a first-class layout concern on mobile, not an afterthought.

**Orientation × device class interaction:**

A phone in portrait provides ~380 dp of waveform width. In landscape, the same phone provides ~800 dp+ — more than doubling the useful time axis. A phone in landscape crosses the 600 dp tablet width threshold, but its ~380 dp of height is too short for side panels (signal tree, value column) to be usable as persistent panes, so classification uses both width *and* height and yields `phoneLandscape`.

**Layout rules by orientation:**

| Device | Orientation | Width (approx) | Height (approx) | Layout Behavior |
|---|---|---|---|---|
| **Phone** | Portrait | ~380 dp | ~800 dp | `phone`: full-width waveform, drawer + bottom sheet for panels |
| **Phone** | Landscape | ~800 dp | ~380 dp | `phoneLandscape`: full-width canvas maximizing the time axis. Panels stay in the drawer / bottom sheet despite tablet-class width. |
| **Tablet** | Landscape | ~1100 dp | ~800 dp | Multi-pane: signal tree + waveform + value column side by side. Preferred orientation for waveform debugging. |
| **Tablet** | Portrait | ~800 dp | ~1100 dp | Multi-pane; below 800 dp wide it takes the narrow pane defaults (220/160). Adequate but not ideal for waveform work. |
| **Foldable, closed** | Portrait | ~466 dp | ~678 dp | Phone layout. The iPhone Duo's cover display. |
| **Foldable, open** | Portrait | ~669 dp | ~951 dp | Multi-pane, but the narrowest tablet-class viewport we ship to: at the standard 280/220 pane defaults the canvas would get ~157 dp, *less* than the closed-device phone layout gives it. Takes the `< 800 dp` narrow pane defaults (220/160) instead. |
| **Foldable, open** | Landscape | ~951 dp | ~669 dp | Multi-pane at standard proportions. The best pose for waveform work on the device. |

**Implementation approach:**

- `DeviceClass.fromSize` applies a secondary height check after the primary width test (reached through `deviceClassForSize` on web and mobile hosts):
  - If width ≥ 600 dp but height < 500 dp → `phoneLandscape` (full-width waveform, drawer / sheet panels) even though width qualifies as tablet
  - If width ≥ 600 dp and height ≥ 500 dp → `tablet` or `desktop` multi-pane layout as normal
- **Size-aware side-pane defaults (`paneDefaultsForViewport`).** The side docks are absolute-width and the canvas absorbs what is left, so the canvas is whatever the panes leave. Defaults widen above 21:9 / 32:9 (ultrawide monitors, XR glasses) where names and values truncate with room to spare, and narrow below 800 dp (foldable inner display in portrait, small tablet in portrait, narrow browser tab) where a fixed 500 dp of panes starves the canvas. Only *un-dragged* defaults are affected — a user-dragged width persists in `PanelLayoutState` and always wins — and pane **visibility** is never touched by viewport size, because that is per-tab user state, not a layout decision.
- **Foldables are a live device-class change, not a resize.** On the iPhone Duo the class crosses `phone` ⇄ `tablet` while the user holds the device. This falls out of the size-driven classifier for free and needs no fold-specific code path: `_WaveCruxIdePanelLayout` reads `leftVisible => !isPhone && _state.signalTreeVisible`, so folding force-hides the docks while *preserving* the user's visibility preference, and unfolding restores exactly what they had. WaveCrux consumes no `MediaQuery.displayFeatures` — hinge/crease geometry is not read, and the waveform canvas does not route content around a crease.
- **Landscape encouragement on phone:** When the user opens a waveform file in phone-portrait, a non-blocking snackbar suggests "Rotate to landscape for a wider view" — once per session (`landscapeHintProvider`). Rotation is never forced.
- **Orientation lock setting:** The settings screen includes an orientation preference: Auto (system default), Landscape Lock, Portrait Lock, or Sensor (follow device), stored in `AppSettings` and applied by `orientationLockSyncProvider`. Useful for engineers who want to lock landscape during a review session without the display flipping when they tilt the device. On desktop, this setting is hidden.
- **State survives rotation:** `ViewerScreen` does not lose scroll position, cursor state, or panel contents on rotation because all of that state lives in Riverpod providers, not in the widget lifecycle. Chrome is not condensed or auto-hidden in phone landscape, and layout changes are not animated.

#### 3.1.8 Mobile UI Standards

This section defines the binding interaction and sizing standards for every WaveCrux UI element on phone and tablet device classes. These rules exist because the desktop-first widget set produces unusable interactions when ported to touch input — buttons too small to hit reliably, drag handles invisible to a finger, system status bars overlapping the toolbar. The standards apply uniformly across **all touch device classes** (`phone`, `phoneLandscape`, `tablet`) and to any device class running on a mobile host platform (iOS, iPadOS, Android), even when the screen size classifies as `desktop` (e.g. iPad Pro 12.9" in landscape).

**Status:** normative for new and modified widgets. Existing code does not fully conform — `lib/features/` still carries literal `fontSize:` values and a few hand-sized hit areas — so treat a violation in code you touch as something to fix, not as precedent.

##### 3.1.8.1 Single Source of Truth: `MobileMetrics`

All sizing, spacing, and hit-target constants are defined in `lib/core/mobile_metrics.dart`. Widgets read values from `MobileMetrics` rather than declaring local constants. The `MobileMetrics.of(context, deviceClass)` factory returns the touch set when the device class is not `desktop` **or** the host is iOS / Android, and the desktop set only for the `desktop` class on a desktop host.

| Metric | Phone / Tablet | Desktop |
|---|---|---|
| `touchTarget` (minimum hit area) | 44 dp | 28 dp |
| `iconSize` (default Material/SF icon) | 24 dp | 18 dp |
| `toolbarButton` (square hit zone) | 48 dp | 36 dp |
| `toolbarHeight` | 48 dp | 40 dp |
| `statusBarHeight` | 40 dp | 24 dp |
| `panelHeaderHeight` | 44 dp | 32 dp |
| `splitterHitWidth` (panel resize hit zone) | 32 dp | 12 dp |
| `splitterVisualWidth` (drawn line) | 6 dp | 6 dp |
| `laneResizeHandle` (vertical resize on signal lanes) | 16 dp + visible grip | 4 dp |
| `cursorMarkerSize` (time-ruler triangle) | 18 dp | 10 dp |
| `namedMarkerFlag` (a–z marker) | 16 dp | 8 dp |
| `dragHandleHitArea` (signal-list reorder grip) | 44 dp | 24 dp |
| `colorSwatch` (visual indicator) | 16 dp | 12 dp |
| `minLaneHeight` (render floor for a signal lane) | 44 dp | 16 dp |

**Typography tokens** (§3.1.8.13). All text in chrome and panels reads sizes from these tokens — never hardcodes a font size.

| Token | Phone/Tablet | Desktop |
|---|---|---|
| `bodyText` (default text in lists, dialogs, menus) | 14 sp | 11 pt |
| `labelText` (column headers, axis labels, panel titles) | 12 sp | 10 pt |
| `monoText` (signal values, time-ruler labels, hex/dec) | 13 sp | 11 pt |
| `statusBarText` (cursor times, file name, zoom percent) | 13 sp | 11 pt |

The desktop column is the historical baseline. The phone/tablet column is the binding requirement.

##### 3.1.8.2 Safe Area

`ViewerScreen` wraps its chrome + body tree in a `SafeArea` whose `top`/`bottom`/`left`/`right` insets respect the platform's reported padding. This is mandatory regardless of device class, because:

- iPad Pro at desktop class (≥1200 dp) still has the iOS status bar overlay (clock, wifi, battery) at the top. Without `SafeArea`, our toolbar renders under those icons and its hit area is partially blocked.
- iPhone notches, Dynamic Island, and Android cutouts intersect the top of any landscape layout.
- The home indicator on iPhone/iPad consumes the bottom 34 pt and must not cover the status bar segments.

We do **not** call `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)` to hide the system bars. iPadOS Stage Manager and split-screen modes require the system status bar to remain visible, and forcing immersive mode breaks multitasking.

##### 3.1.8.3 Touch Target Rule

Every interactive element on phone or tablet has a minimum **44 × 44 dp** hit area — the iOS Human Interface Guidelines floor (Material Design recommends 48 dp).

When the visual element is smaller than 44 dp (e.g. a 24 dp icon, a 16 dp color swatch, a 1 dp splitter line), the surrounding `GestureDetector` / `InkWell` must be sized to 44 dp. Use `SizedBox(width: 44, height: 44, child: ...)` or wrap in a `Padding` that brings the hit area to 44 dp.

##### 3.1.8.4 Visible Affordances

Anything draggable on phone or tablet must show a **visible drag affordance**. This includes:

- **Signal-list lane reorder:** a drag-handle icon (`MobileMetrics.iconSize`) at the left edge of each row inside a `dragHandleHitArea` (44 dp on touch) hit box; the row's right edge carries the remove ✕.
- **Lane vertical resize:** a 16 dp horizontal strip at the bottom of each lane with a two-line center grip that brightens while dragging.
- **Panel resize splitters:** a 6 dp visible bar (`splitterVisualWidth`) inside a 32 dp touch / 12 dp desktop hit zone (`splitterHitWidth`) — see §3.1.8.6.
- **Time-ruler cursor markers:** the 18 dp downward triangle is fully painted (not outlined) on touch device classes.

An interaction with no visible affordance is invisible to a touch user — they have no hover or right-click feedback to discover it.

##### 3.1.8.5 Long-Press = Right-Click (Universal)

On all touch device classes, long-press fires the same context menu that right-click fires on desktop. Drag-to-reorder uses the **explicit drag handle** only — long-pressing the row body never initiates drag, so the row body is always free to fire the long-press context menu.

This rule applies to:
- Signal-list rows (full-path header, Change Color…, Render as Analog / Digital, Move to Group, Copy Value, Copy Full Path, translate / process filter items, Trace X, FSM visualize / annotate; removal is the row's ✕ button and display format lives in the value-column row menu)
- Signal-tree leaves (Add to Viewer, Add Selected, Apply Decoder to Selection, Copy Signal Path)
- Signal-tree scopes (Add All in Scope)
- Cocotb log rows (Jump to Time, Copy Message, Copy Timestamp)
- Waveform canvas (Place Primary Cursor Here, Place Secondary Cursor Here, Clear Cursors, Fit All, Add Annotation, Annotate Range, Annotate Range on Lane)

Transaction table rows have no context menu; a tap jumps to the transaction. `PlatformContextMenu` (`lib/shared/widgets/platform_context_menu.dart`) wraps a row so long-press and right-click open the same menu; it is used by the signal-list rows, value-column rows, the file-info panel, and decoder list entries. The signal tree, cocotb rows, and the canvas wire their own long-press / secondary-tap handlers to the same effect.

**Gesture bubbling rule.** Inner `GestureDetector`s that handle only a subset of gestures (e.g. an `onTap` for color cycling) must NOT use `HitTestBehavior.opaque`. Opaque hit-testing claims the entire gesture arena and prevents long-press from bubbling to the outer `PlatformContextMenu`, producing the failure mode where a context menu opens but the inner `onTap` also fires after dismissal — overwriting whatever the user just chose. Use `HitTestBehavior.translucent` (or omit `behavior`, which defaults to deferToChild + translucent fallback) so unhandled gestures bubble.

**Tooltip rule on touch.** Flutter's `Tooltip` widget registers a `LongPressGestureRecognizer` on touch (default `triggerMode: TooltipTriggerMode.longPress`). Inside a row wrapped in `PlatformContextMenu`, the Tooltip's deeper recognizer wins the gesture arena, the user sees the tooltip but never reaches the context menu, and any inner `onTap` may then fire spuriously — the *same* defect class as the opaque-hit-test trap above. Therefore: every `Tooltip` rendered inside a `PlatformContextMenu`-wrapped row must set `triggerMode: TooltipTriggerMode.manual`. Hover (mouse) tooltips still work; touch users get the equivalent reveal via the row's own context menu — typically a path/name header at the top of the menu (§3.1.8.14) and item-specific actions like "Change Color…". Code review rejects new in-row Tooltips that use the default trigger mode.

##### 3.1.8.6 Panel Visibility & Resize Affordances

Tablet and desktop multi-pane layouts show three dock regions around the canvas — left (Signals, plus Diff while a waveform diff is active), right (Values, plus RTL Source and Cross-Probe on demand), and bottom (Transactions pinned, one tab per Stage panel, and on-demand analysis tabs such as FSM, X-Trace, switching activity, Explain Selection, and cocotb). On all device classes that show more than one pane:

- **Splitters** between regions honor `splitterHitWidth` (32 dp on touch, 12 dp on desktop) and `splitterVisualWidth` (6 dp on both). The visible 6 dp bar provides the "I can grab this" affordance — narrower lines (e.g. 1 dp) are *not* discoverable; 4 dp was usable on touch but ambiguous with mouse. The splitter paints with **`resizerColor: colorScheme.outlineVariant`** at rest and **`resizerHoverColor` / `resizerFocusedColor: colorScheme.primary`** on hover and during a grab — without the hover color, mouse users can't tell a passive divider from a resizable one. `ViewerScreen` passes these through `CruxIdeLayoutTheme`, which builds the `PaneTheme` wrapping the `panes` `IdeLayout`.
- **Collapse lives on each dock's strip; reveal lives in the View menu, palette, toolbar, and the restore bars.** A collapsed region leaves a slim restore bar along its window edge (`WaveCruxDockRestoreBars`) showing the region's tab icons; clicking one reopens the region on that tab. The restore bars reuse the docks' own entry assemblers, so a bar never disagrees with its dock.
- **Splitters remain reachable when a region is shown.** Nothing — no overlay, no scrollbar — may sit on top of a splitter's hit zone. Once a region is opened it must always be drag-resizable. The bottom region honors `bottomMinSize` (80 dp) so it cannot be re-shown at zero height.
- **Force-hide side and bottom regions at phone widths.** The region minimums (150 dp left + 150 dp right + 120 dp centre) cannot fit a phone-width window. At `DeviceClass.phone` or `DeviceClass.phoneLandscape`, the `_WaveCruxIdePanelLayout` adapter (`lib/features/viewer/screens/viewer_screen_widgets.dart`) reports each region as hidden (`leftVisible => !isPhone && _state.signalTreeVisible`, and likewise for right and bottom) while leaving the user's preference in `PanelLayoutState` untouched, so the previous arrangement restores when the window grows back to tablet/desktop. `ViewerScreen` rebuilds the adapter from `deviceClassProvider`, and `CruxIdeLayout` pushes only visibility deltas onto its `IdeController`. `CruxIdeLayout` also clamps pixel-sized regions to the space it is given, so a narrow iPad split-screen or a resized window shrinks the regions instead of overflowing.

  **Phone panel hosting.** While the regions are force-hidden, the panels stay reachable without taking horizontal space from the canvas: `ViewerScreen` hosts the **signal tree** in the screen-level `Scaffold.drawer` (built outside the per-tab `CruxIdeLayout`, re-bound to the active tab's container), the **value column** is drawn inline at the cursor (`InlineCursorValueOverlay`) rather than in a modal drawer, and the **bottom dock** — transactions, Stage panels, analyses — opens as a modal bottom sheet (`WaveCruxBottomDockSheet`) that uses the same entry list as the desktop dock. The overflow menu's `Toggle Signal Tree` / `Toggle Value Column` / `Toggle Transaction Table` actions only flip `PanelLayoutState`, which the force-hide masks on phone; the status-bar chevrons (§3.1.8.6.1) are the phone's panel access.

##### 3.1.8.6.1 Phone Panel Chevrons in the Status Bar

On phone and phone landscape only, the status bar carries the panel entry points. Tablet and desktop render no chevrons: there, collapse is on each dock's strip and reveal is in the View menu, palette, toolbar, and restore bars (§3.1.8.6).

**Layout** (phone, left to right):

```
[▶tree]    [file | cursor | …]      [▲bottom]      [load indicator | overlay slot]
   ↑       └ scrolls if narrow ┘        ↑
 leading                           geometric
                                     center
```

- **Left chevron** (signal tree): the status bar's leading slot. Opens the phone `Scaffold.drawer`. Renders `Icons.chevron_left` when the tree is effectively visible and `Icons.chevron_right` when hidden — on phone the region is always force-hidden, so it points right.
- **Center chevron** (bottom dock): the geometric center of the status bar. Opens `WaveCruxBottomDockSheet` through the `onShowBottomPanelSheet` callback. Renders `Icons.keyboard_arrow_down` / `Icons.keyboard_arrow_up` by the same rule.
- **No right chevron** on any device class: phone has no value-column pane (values render inline at the cursor).

Direction-flip is the binding rule: the chevron points in the direction the panel will *move* on tap, computed from *effective* visibility (the force-hide included), not the raw `PanelLayoutState` flag.

**Implementation pattern**:
- `_PanelChevronButton` widgets passed to `CruxStatusBar`'s `leading` and `center` slots from `StatusBar` (`lib/features/viewer/widgets/status_bar.dart`), gated on `isPhone`.
- Each chevron's hit area is `MobileMetrics.touchTarget` (44 dp on touch).
- The trailing slot holds the signal-load indicator and the `statusBarTrailingWidgetsProvider` overlay seam (§10).

**Forbidden patterns** (regression guards):
- No `Stack` overlays on the `CruxIdeLayout` for panel toggles.
- No "edge tabs" along canvas edges (the old `PanelEdgeTab` widget is gone; restore bars are part of the dock system, not canvas overlays).

##### 3.1.8.7 Status Bar

The status bar (`CruxStatusBar`, from `crux_status_bar`) height is `MobileMetrics.statusBarHeight` (40 dp on phone/tablet, 24 dp on desktop). Phone shows a condensed segment set; tablet shows the same full segment set as desktop, just at the larger height. The live statistics strip's disclosure lives on the strip itself (§8.8), not in the status bar.

##### 3.1.8.8 Lane Vertical Resize on Touch

The signal-list resize handle at the bottom edge of each lane is 16 dp tall on touch device classes (vs 4 dp on desktop). It paints a **two-line horizontal grip** centered in the strip, in `theme.colorScheme.outlineVariant`, switching to `theme.colorScheme.primary` while a drag is in progress. The grip is drawn over the bottom of the lane rather than added below it; instead, every lane renders at least `MobileMetrics.minLaneHeight` tall (44 dp on touch, 16 dp on desktop) so the row content and the grip cannot collide. `SignalGroupsNotifier.setLaneHeight` clamps to the same floor. Besides drag-resize, double-tapping a row's signal name resets its lane to the default height from Settings.

##### 3.1.8.9 Cursor & Marker Sizing

The time-ruler cursor triangles and named-marker flags (a–z) scale with `MobileMetrics`:

- Primary cursor triangle: 18 dp wide on touch, 10 dp on desktop (`cursorMarkerSize`).
- Secondary cursor triangle: same dimensions, outlined instead of filled.
- Named marker flags: 16 dp wide on touch, 8 dp on desktop (`namedMarkerFlag`), with the letter label below.

On touch, the cursor hit area extends 22 dp on each side of the painted triangle (giving a 44 dp horizontal hit zone) so a finger can grab and drag a cursor reliably. Named markers are not draggable; their hit test serves right-click removal. The cursor *line* itself (the vertical 1 dp line cutting through the canvas) is **not** independently draggable on any device class — placement and movement happen via the time ruler triangle or by tapping in the canvas.

##### 3.1.8.10 Toolbar Icon Sizes

`ViewerToolbar` renders through the shared `CruxToolbar`, whose `CruxToolbarMetrics` carry the same values as `MobileMetrics.toolbarButton` / `iconSize`: 48 dp hit and 24 dp icon on touch, 36 dp hit and 18 dp icon on desktop.

##### 3.1.8.11 Maintenance Rule

When adding a new interactive widget, the author must:

1. Read sizes and font sizes from `MobileMetrics`, not hardcode pixel values.
2. Wrap any draggable surface in a visible affordance per §3.1.8.4.
3. Wrap any row that has a desktop right-click menu with `PlatformContextMenu` per §3.1.8.5.
4. Avoid `HitTestBehavior.opaque` on inner `GestureDetector`s that handle only some gestures — let unhandled gestures bubble to the outer `PlatformContextMenu` (§3.1.8.5).
5. If the widget appears on phone or tablet, include a touch-target compliance test that asserts the rendered hit rect is ≥ 44 × 44 dp.
6. Let any `Row`-based chrome scroll horizontally per §3.1.8.12, with always-visible affordances outside the scroll.
7. Wrap any `Text` with `TextOverflow.ellipsis` in a `Tooltip` and/or expose the full content via a context-menu item per §3.1.8.14.

The constants in `MobileMetrics` are the binding contract; per-widget overrides are not permitted without an explicit comment justifying the deviation (e.g. "list density mode allows 32 dp rows for power users — opted in via setting").

##### 3.1.8.12 Window Resize & Overflow Policy

WaveCrux must render correctly at any window size from 320 dp wide (smallest valid iPad / iPhone scene) up to ultra-wide desktop monitors. We do **not** restrict iPad multitasking via `UIRequiresFullScreen` or `UISupportsResizableWindow=NO` — those keys break Stage Manager and split-screen, which our target users (HDL engineers reviewing waveforms next to chat / docs) actively use.

The toolbar's intrinsic width with all of its buttons and dividers exceeds the canvas width on small windows. Without intervention, Flutter throws `RenderFlex overflowed by N pixels`.

**Standard:** All chrome (toolbar, status bar, dock headers) lets its primary content scroll horizontally when the available width is smaller than its intrinsic width. The toolbar keeps its overflow button (`Icons.more_vert`) *outside* the scrolling strip, at the right edge behind a fade, and shows it only while the strip actually overflows.

This rule applies to every `Row`-based chrome surface. List rows (signal list, value column, transaction table) are *not* covered — they have their own ellipsis / wrap behavior (§3.1.8.14).

**Verification:** every chrome widget test should include a "renders without overflow at 320 × 568 dp surface" case (smallest iPhone 5 / SE scene).

##### 3.1.8.13 Typography Scale

Body text on a desktop is read from ~70 cm on a 27" monitor; on a phone or tablet it's read from ~30 cm in the hand. The same 11 pt font that's comfortable on desktop is squinty on touch. The same applies to any text rendered into chrome: status bar values, panel headers, signal list rows.

**Standard:** every font size in `lib/features/**` reads from `MobileMetrics`'s typography tokens — see the table in §3.1.8.1. The four tokens cover all text in the app:

- `bodyText` — default text in lists, dialogs, menu items, snackbars.
- `labelText` — column headers, axis labels, panel titles, tooltips.
- `monoText` — signal values, time-ruler labels, hex/dec/bin readouts. Always paired with `WavecruxColors.monoFontFamily`.
- `statusBarText` — cursor times, file name, zoom percent. Slightly tighter than body text but never below `monoText`.

**Text scaling clamp.** Operating-system text scaling (Settings → Display → Text Size on iOS, Android, macOS) is honored but bounded. The app root (`app.dart`, inside `MaterialApp.builder`) wraps the app in `MediaQuery.withClampedTextScaling(minScaleFactor: 0.85, maxScaleFactor: 1.5)` so a user who maxes out their accessibility scaling can't push 14 sp body text up to 28 sp and break every `Row` in the app. The 0.85 floor preserves layout density for users who shrink scaling.

**Forbidden in new code:** hardcoded `fontSize: 11` (or any literal number) in any file under `lib/features/**`. The only exceptions are `lib/core/theme/` and the typography token definitions themselves. No static guard enforces this yet, and existing feature code still carries literal font sizes (§3.1.8 status).

##### 3.1.8.14 Truncated Text

Any `Text` widget that uses `overflow: TextOverflow.ellipsis` or `TextOverflow.fade` must give the user some way to see the full content. Two patterns are acceptable:

1. **Hover tooltip (desktop only)** — wrap the `Text` in `Tooltip(message: fullText, triggerMode: TooltipTriggerMode.manual, child: Text(...))`. The manual trigger mode disables the default long-press recognizer (per §3.1.8.5) but hover still works on mouse, so desktop users see the full content on hover.
2. **Context-menu path header** — for rows that already have a `PlatformContextMenu`, the **first item of the menu is a non-interactive header showing the full content** (monospace, slightly dimmed `onSurfaceVariant`, separated by a `PopupMenuDivider` from the action items below). This is always visible the moment the menu opens — no extra action required, no extra screen tap, no buried list item the user has to scan for. The "Copy Full Text" action remains lower in the menu for explicit clipboard use.

The signal list combines both: the row name has `Tooltip(message: fullPath, triggerMode: manual)` for desktop hover, *and* the long-press menu's first item is the full path itself, rendered in monospace with the existing "Copy Full Path" action immediately below.

**Forbidden:** rendering `TextOverflow.ellipsis` without one of the above reveals. A truncated name with no way to see the full version is a UX defect. Do not add a separate "Show Full {Field}…" action that opens a snackbar — the menu-header pattern surfaces the content one step earlier and removes a guess about which menu item reveals the data.


---

## 5. Localization

### 5.1 Strategy

WaveCrux is fully internationalized. Every user-facing string goes through Flutter's standard `flutter gen-l10n` localization system; the generated class is `L10N` (`l10n.yaml`: `output-class: L10N`, output under `lib/l10n/generated/`).

**Shipped locales:**
- **English (`en`)** — primary, maintained by the project
- **Simplified Chinese (`zh-CN`)**
- **Japanese (`ja`)**
- **Korean (`ko`)**

CJK (Chinese, Japanese, Korean) localization is a baseline requirement because a large share of hardware engineers outside the US and Europe work in these languages.

The UI language is a user setting (`CoreSettings.locale`, default `en`) rather than the device locale: `WaveCruxApp` maps the stored tag onto a `Locale` in `_toLocale` (`lib/app.dart`), and the picker offers the fixed `kCruxSupportedLocales` list from `crux_settings_ui`. Adding a community translation therefore takes the new ARB file **plus** an entry in that mapping and in the picker list.

### 5.2 ARB File Rules

- ARB files live in `lib/l10n/` (no `arb/` subdirectory). Generated Dart code (`lib/l10n/generated/`) is gitignored and not committed.
- `app_en.arb` is the template and the primary source of truth. `app_zh_CN.arb`, `app_ja.arb`, and `app_ko.arb` are the maintained translations.
- `app_zh.arb` mirrors `app_zh_CN.arb` (identical translations, `@@locale` set to `zh`): `gen-l10n` requires a language-only fallback file for a country-specific locale, and the mirror keeps a bare `zh` resolving to Chinese rather than English. Every edit to `app_zh_CN.arb` must be applied to `app_zh.arb` in the same commit.
- Each ARB file MUST include `"@@locale": "<locale_code>"` as its first entry (e.g., `"@@locale": "en"`). This is required by `flutter gen-l10n`.
- Every message in `app_en.arb` MUST have a corresponding `@` metadata entry with at minimum a `description` field. (The translated files carry metadata for most but not all keys; the template's metadata is the one `gen-l10n` reads.)
- `description` field remains in English.
- Placeholder names are `camelCase` and must include `type` in the metadata.
- Do NOT use ICU message syntax unless actual pluralization or gender selection is needed — keep messages simple.


---

## 6. Architecture

### 6.1 Layer Responsibilities

- **Domain layer** (`lib/domain/`) — Plain Dart models, enums, and interfaces; the source of truth for data shapes, unit-testable without a widget tree. It imports nothing app-level (§6.2.4). Its package imports are limited to leaf value-type packages — `meta`, `uuid`, and the suite's `crux_license` / `crux_settings` / `crux_workspace` — plus one `package:flutter/foundation.dart` import (`active_decoder.dart`).
- **Services layer** (`lib/services/`) — Business logic. Waveform data access (wellen FFI on desktop/mobile, wellen WASM on web, the streaming VCD parser), value formatting, signal querying, session management, protocol decoders. Services depend on domain interfaces and are testable with mocks.
- **Feature modules** (`lib/features/`) — Each feature owns its Riverpod providers, screens, and widgets. Providers depend on services.
- **Native code** — the Rust crates live in `native/` (`wellen_ffi`, `wellen_wasm`, `lxt2fst`, and the `torture_gen` large-file generator used by the perf benchmarks); their ffigen / hand-written Dart bindings live in `lib/native/bindings/`. The wellen bindings are consumed only by the `WaveformDataSource` implementations in `lib/services/waveform/`; the `lxt2fst` bindings by its converter (§2.2.1).
- **Core** (`lib/core/`) — Theme, constants, keyboard shortcut definitions and action descriptors, utility extensions. May use `domain/` and `shared/`; does not import `features/` or `services/`, with two sanctioned exceptions enforced by the layering guard: the `core/providers/` extension-point registry (§6.2.2) and the named core composition roots in the orchestration tier (§6.2.1).
- **Shared** (`lib/shared/`) — Reusable layout helpers (`layouts/`, e.g. `deviceClassProvider`, `paneDefaultsForViewport`), platform shims, and leaf widgets. Held to the same no-`features/` rule as services.
- **Plugins** (`lib/plugins/`) — Registries and overlay injection points: protocol decoders, Stage widgets, value translators and presets, timeline overlays, bottom-dock tabs, transaction-table exporters, localization delegates, eager-startup providers.
- **`lib/widgets/`** — the two legacy-format widgets (`legacy_format_banner.dart`, `legacy_conversion_progress_dialog.dart`). Not covered by any layering rule today.

### 6.2 Dependency Flow

The baseline flow (enforced by `test/static/import_layering_test.dart` —
see the amendments below for the sanctioned exceptions):

```
features/ → services/ → domain/ (via interfaces)
services/ → domain/ (implements interfaces, uses models)
services/, plugins/, shared/ → never features/ (except the orchestration tier)
core/ → never features/ or services/ (except the orchestration tier and core/providers/)
domain/ → nothing app-level
```

The test does not regulate `services/ → services/`, `plugins/ → services/`
(the translator registry builds on the ISA decoder services), or anything
imported *from* `features/` downward.

**§6.2.1 The orchestration tier.** The layer
diagram has no home for *composition* code — files whose entire job is to
wire features together. Rather than a directory move, these are blessed in
place as a named tier: the explicit, per-file allowlist
(`_orchestrationTier`) in `test/static/import_layering_test.dart`, each
entry carrying a one-line justification. Members may import from
`features/`; nothing else in `services/`, `core/`, `plugins/`, or `shared/` may. The tier today:

- *Per-tab / per-pane container composition* — `services/tabs/wavecrux_tab_overrides.dart`
  (THE per-tab override registry), `tab_container_manager`,
  `active_tab_container`, `services/panes/pane_container_manager.dart`.
- *Wire-protocol → provider translators* — `services/remote/remote_control_notifier.dart`
  (WCP), `services/remote/cxp/{cxp_inbound_handlers,cxp_selection_emitter,cxp_workspace_link}.dart`
  (CXP), `services/host_bridge/{editor_host_bridge,host_annotation_value_service}.dart`
  (the editor-extension host), `services/collaboration/collab_viewer_bridge.dart`,
  `services/ai/tools/viewer_navigation_tools.dart`.
- *State-snapshot reporters* — `services/diagnostics/{app,tab}_diagnostics_report_service.dart`.
- *Session/workspace plumbing* — `services/session/session_reset.dart`,
  `services/workspace/last_session_migration.dart`,
  `services/decoders/ffi/ffi_decoder_loader_provider.dart`.
- *Core composition roots* — `core/router.dart` (mounts screens),
  `core/shortcuts/action_context_provider.dart` (the §3.1.6 action-gating
  seam), `core/theme/wavecrux_color_theme_bootstrap.dart`.
- *Plugin registries* — `plugins/{extra_stage_widgets,custom_stage_widget_registry,timeline_overlay_layers}_provider.dart`
  (they bind built-in implementations that live in `features/`).

The app-level entry points `lib/app.dart` / `lib/main.dart` are the
bootstrap composition root and sit outside the regulated tiers entirely.
Joining the tier is a deliberate act: add the file to the allowlist *with a
justification*, and expect the addition to be challenged in review — most
"I need a feature provider from a service" cases actually want a
domain/service seam instead.

**§6.2.2 Extension-point registry carve-out.** `core/providers/` may import
from `services/` — its files declare the cross-repo extension points
(`collaborationServiceProvider`, `debugAdvisorServiceProvider`, the AI
seams, the panel openers / togglers, …) and bind their open-core default
implementations (no-op services, registry types). Everything else under
`core/` stays free of `services/` and `features/`. (Suite-wide seams such
as `telemetryServiceProvider` are declared in their `crux-shared` package,
not here.)

**§6.2.3 Lateral feature imports.** Features freely import *sibling
features'* providers, commands, constants, and feature-root files — that is
the sanctioned state-seam / time-bus pattern, and it is by far the most
common cross-feature edge. What they may **not** import is a sibling's
`widgets/` or `screens/`: composing another feature's UI couples widget
trees across module boundaries. Two exceptions:

- `features/viewer/` is the **sanctioned feature shell** — the viewer
  screen hosts every panel, dialog, menu surface, and toolbar, so its
  sibling-UI imports are its composition job.
- A small explicit allowlist (`_lateralUiAllowlist` in the static test) for
  genuine cross-feature surfaces: the signal tree opening the decoder
  picker, the pane host mounting the diagnostics popover/drawer, and
  diagnostics reading the viewer's render-stats collector.

**§6.2.4 Domain purity is absolute.** `domain/` imports nothing from
`features/`, `services/`, `core/`, `plugins/`, or `shared/` —
no exceptions, no allowlist. Pure value types belong *in* `domain/`: a
pure-Dart type that gains a domain consumer moves into `domain/` rather than
the rule gaining an exception.

All four rules — plus stale-allowlist detection, so an entry that stops
being needed fails the suite until removed — are enforced by
`test/static/import_layering_test.dart`.

### 6.3 Key Interface: WaveformDataSource

The central abstraction that decouples the UI from the parsing backend:

```dart
abstract class WaveformDataSource {
  Future<void> openFile(String path);
  void close();

  // Hierarchy
  List<Scope> get rootScopes;
  List<Variable> findVariables(SignalFilter filter);

  // Signal data (lazy loading)
  Future<void> loadSignal(String signalRef);
  bool isSignalLoaded(String signalRef);
  Future<void> unloadSignal(String signalRef) async {} // default no-op

  // Queries
  String? valueAt(String signalRef, int time);
  List<SignalChange> changesInRange(String signalRef, int start, int end);
  SignalChange? nextTransition(String signalRef, int afterTime);
  SignalChange? prevTransition(String signalRef, int beforeTime);

  // Metadata
  int get startTime;
  int get endTime;
  Timescale? get timescale;
  String? get date;
  String? get version;
}
```

Three implementations:
1. `WellenProvider` — wraps wellen via FFI; the wellen handle lives on a long-lived worker isolate managed by `WellenIsolateOrchestrator` (desktop/mobile)
2. `WellenWasmProvider` — wraps wellen via WebAssembly through `dart:js_interop` (web — the only file path there; `WaveformSourceNotifier` raises `WebAssemblyRequiredError` if the WASM module fails to load)
3. `StreamingVcdService` — incremental pure-Dart VCD parser for `--stdin` / `--pipe` streaming mode (desktop; see §2.2)

`SignalChange` (`lib/domain/models/signal_change.dart`) is a plain `(time, value)` value class.

### 6.4 Riverpod Provider Hierarchy

WaveCrux uses a three-kind container hierarchy: a root container for app-global state, one container per open tab for all file-specific state, and one container per pane for render statistics. Per-tab containers are what make multi-tab and split-pane work — a tab's container can be hosted by either pane without being rebuilt.

**Workspace = the open-tab set.** A workspace (`Workspace` model + `workspaceProvider` in the root scope) is the persisted session concept. It holds the ordered list of `WorkspaceTab`s, the panes layout (one or two panes), and the active pane / active tab pointers. It is auto-saved to `{appSupportDir}/workspace.json` — debounced on tab/pane mutations, and flushed when the app lifecycle reaches paused or detached; "Save Workspace As…" produces a named `.wavecrux-workspace` file for explicit sharing. A single-tab `.wavecrux` session remains the export format for sharing one debug session.

`bootstrap()` builds the root `ProviderContainer` directly (with the open-core overrides followed by any overlay `extraOverrides`) and mounts it with `UncontrolledProviderScope` (§10).

**Root scope (app lifetime — global state):**
```
Root ProviderContainer
├── appSettingsProvider
├── licenseTierProvider
├── cruxColorThemeProvider
├── deviceClassProvider
├── workspaceProvider           ← Workspace state (tabs + panes + active selection)
├── tabListProvider             ← derived from workspaceProvider (live WavecruxTab view)
├── activeTabIdProvider         ← derived from workspaceProvider
├── activePaneIdProvider        ← which pane has focus
└── selectedSignalProvider      ← the WCP server's focus_item target (app-global)
```

**Per-tab scope (one ProviderContainer per open tab, parented to root):**
```
UncontrolledProviderScope(container: ProviderContainer(parent: rootContainer))
├── tabIdProvider              ← overridden with this tab's UUID
├── waveformSourceProvider     ← WaveformDataSource for this tab's file
├── hierarchyProvider          ← scopes and variable list for this file
├── signalGroupsProvider       ← user-defined signal arrangement
├── selectedVariablesProvider  ← signals selected in this tab
├── cursorStateProvider        ← primary + secondary cursor positions (single CursorState)
├── timeMapperProvider         ← zoom/pan state → TimeMapper
├── markerStateProvider        ← named markers a-z
├── activeDecodersProvider     ← protocol decoder bindings
├── panelLayoutProvider        ← this tab's dock visibility, sizes, active dock tabs
├── stageWorkspaceProvider     ← this tab's Stage panels and instances
├── sessionProvider / sessionAutoSaveProvider ← per-tab session sidecar
└── … every other file-specific provider
```

The authoritative list is `wavecruxTabOverrides` in `lib/services/tabs/wavecrux_tab_overrides.dart`; an overlay appends its own per-tab providers through `bootstrap(extraTabOverrides:)`. A file-specific provider missing from that list silently resolves against the empty root scope — the per-tab scope-leak defect class that list exists to prevent.

Heavyweight per-tab state (the providers above) persists in a per-tab session sidecar at `{appSupportDir}/sessions/{tabId}.wavecrux`, written continuously (debounced) by `sessionAutoSaveProvider`. The workspace document carries only the framework-visible summary needed to re-bind the file after restart: `WaveCruxTabPayload` (`filePath`, `sessionFilePath`, `sessionExportPath` — the last "Export Tab as Session…" destination — and `isDetached`).

**Per-pane scope (one ProviderContainer per pane, parented to root):**
```
UncontrolledProviderScope(container: ProviderContainer(parent: rootContainer))
├── paneIdProvider               ← overridden with this pane's UUID
├── paneRenderStatsProvider      ← canvas paint pipeline metrics for this pane's active canvas
└── renderStatsCollectorProvider ← the collector this pane's canvas paints into
```

**Key rules:**
- Widgets inside a tab's subtree watch the same provider names as always; the nearest `UncontrolledProviderScope` ancestor resolves them to the correct tab's container.
- Tab containers are created, cached, and disposed by `TabContainerManager` (a thin WaveCrux wrapper over `crux_workspace`'s manager); inactive tabs keep their containers, and each pane mounts tab content through a `LazyIndexedStack`, so switching tabs never re-loads the file or loses state.
- Global providers (`appSettingsProvider`, `licenseTierProvider`, `workspaceProvider`, etc.) are visible from within any tab or pane container via Riverpod's parent container lookup.
- With split-pane, the same tab is hosted by exactly one pane at a time; moving a tab to the other pane is a metadata-only update on `workspaceProvider` (the tab's `ProviderContainer` does not change).
- Render stats are **per-pane**, not per-tab: the canvas being painted belongs to a pane, and with two visible panes there are two simultaneous render-stats streams. Other diagnostic data (file info, signal health, memory) is per-tab — see §8.8.
- **Multi-window is a seam, not a feature.** `crux_workspace` defines `TabDetachingDelegate` / `PanelPopOutDelegate` with `Noop*` defaults and `kMultiWindowAvailable = false` (the flag re-exported through `lib/core/constants.dart`); the "Move to New Window" tab menu item renders disabled while the flag is false. No concrete multi-window delegate exists in this repository or in the overlay. The design intent is that, once Flutter multi-window is stable, a tab's `ProviderContainer` moves to the new window's widget tree unchanged (single shared Dart isolate). Split-pane and multi-window are independent axes.

**Empty-canvas state:** when the tab list is empty, `ViewerScreen` renders `WaveCruxEmptyCanvas` (which composes `crux_workspace`'s `EmptyCanvasState`) instead of any tab content. Toolbar, status bar, menu bar, and command palette remain interactive so users can open files, change settings, and access diagnostics without first creating a tab. There is no "Welcome tab" — emptiness is a state of the workspace, not a tab kind.

**The viewport's three bounds (`TimeMapper`, `lib/services/waveform_geom/time_mapper.dart`).** Zoom and pan are clamped to the trace's own extent, in every direction, and the bounds are properties of the mapper rather than of any one control — so the wheel, the pinch, the trackpad, the keyboard, the toolbar, the scrollbar and the remote-control API all obey them without each re-deriving them.

* **Zoom out stops at fit-all.** `maxTicksPerPixel` is `range / viewportWidth` — with no one-tick-per-pixel floor, which would otherwise become the bound on any trace shorter than the viewport is wide and let the data crush into a corner of the canvas.
* **Zoom in stops at one tick across the viewport** (`minTicksPerPixel`, `minVisibleTicks = 1`). One tick is the timescale's resolution; below it the trace carries nothing to reveal. The floor yields to `maxTicksPerPixel` on a trace only a tick long, so such a trace stays fittable and `clamp`'s `min <= max` precondition holds.
* **Pan stops at the data.** `clamped()` holds `panOffsetTicks` in `[startTime, endTime − viewport]`, collapsing to `startTime` at fit-all. The `TimeMapperNotifier` mutators apply it — including `zoomToRange`, which is the one a *peer* drives (a collaboration follower applying a presenter's viewport, the shared-pointer overlay re-centring) and can therefore be handed a range the local trace does not have. The fit-all paths build `TimeMapper.fitAll`, which is in bounds by construction.

`TimeMapper.canZoomIn` / `canZoomOut` publish the first two so the action surfaces can grey out instead of absorbing a press: they ride the per-tab → root mirror in `activeTabActionFlagsProvider`, become `ActionRequirement.canZoomIn` / `canZoomOut` on the `zoomIn` / `zoomOut` descriptors, and the keyboard guard turns the unmet one into a localized hint. Fit All is deliberately **not** gated — it is the escape hatch. The bare-key WASD variants (`waveformZoomIn` / `waveformZoomOut`) stay ungated: they are hidden from every surface, have no enabled state to show, and the mapper's clamp already makes them inert at the limits.

### 6.5 Panel Layout Architecture

The screen is a fixed chrome shell around a pane host; every tab carries its own dockable IDE layout:

```
┌──────────────────────────────────────────────────────────────┐
│  Menu Bar (macOS: system menu bar; Windows/Linux: in-window) │  ← wraps every route from MaterialApp.builder
├──────────────────────────────────────────────────────────────┤
│  Toolbar (frequent actions + overflow when it does not fit)  │  ← one per screen, outside any tab scope
├──────────────────────────────────────────────────────────────┤
│  Tab Bar [file_a.fst ×] [file_b.vcd ×]   (hidden on phone)   │  ← WaveCruxPaneHost (one or two panes)
├──────────────────────────────────────────────────────────────┤
│  Banners (legacy-format, capability nudge, annotation adopt) │  ← per tab from here down
├────────────┬─────────────────────────────────┬───────────────┤
│ Left dock  │  Signal list │ Time Ruler       │  Right dock   │
│  Signals   │              ├──────────────────┤   Values      │
│  (Diff)    │              │ Waveform Canvas  │   (RTL Source)│
│            │              │                  │   (Cross-Probe│
│            ├──────────────┴──────────────────┴───────────────┤
│            │  Bottom dock: Transactions │ Stage ×N │ FSM │ … │
├────────────┴─────────────────────────────────────────────────┤
│  Live Statistics Strip (desktop only)                        │
├──────────────────────────────────────────────────────────────┤
│  Status Bar (file name, cursor, range, zoom)                 │
└──────────────────────────────────────────────────────────────┘
```

Each tab's content is a `CruxIdeLayout` (§2.4) whose centre region is `WaveformViewCenter` (signal list, time ruler, canvas, horizontal scrollbar) and whose left, right, and bottom regions are `CruxDock` tab strips assembled by `WaveCruxLeftDock`, `WaveCruxRightDock`, and `WaveCruxBottomDock` (`lib/features/viewer/widgets/side_docks.dart`, `bottom_dock.dart`). Entries are pinned (Signals, Values, Transactions), dynamic (one tab per Stage panel), or on-demand (present while the analysis or feature is active; closing the tab deactivates it). The movable on-demand entries (the analyses, cocotb, and Cross-Probe) can be dragged between the bottom and right docks; the placement persists in `PanelLayoutState.dockPlacements`. Panel state is per tab and persists through the tab's session sidecar (§6.4). Adding a panel means adding a `CruxDockEntry` to the relevant entry assembler; an overlay adds bottom-dock tabs through `extraBottomDockTabsProvider` (§10).

#### PaneHost (split-pane viewing)

`WaveCruxPaneHost` (`lib/features/panes/widgets/wavecrux_pane_host.dart`) is the screen body below the toolbar and hosts **one or two panes** side by side. Each pane has its own `ViewerTabBar` (filtered to that pane's tabs via `WorkspaceTab.paneId`), its own lazily-mounting stack of tab content subtrees, and its own per-pane `ProviderContainer` (see §6.4) that publishes `paneRenderStatsProvider`. The adapter wraps `crux_workspace`'s generic `PaneHost<P>` / `ViewerTabBar<P>` and wires the WaveCrux-specific behaviour through the package's additive seams: `stackBuilder` → `LazyIndexedStack` (one-at-a-time GPU-surface init, avoiding a Windows/Intel driver crash), `splitLayoutBuilder` → a drag-resizable splitter, `paneTrailingActionsBuilder` → the Pane Render Stats `i`-icon + split-pane button, and `tabContainerFor` / `paneContainerFor` → WaveCrux's container managers. `contextMenuBuilder` composes the tab chip menu (monospace full-path header per §3.1.8.14, Duplicate, Move to New Window — disabled, §6.4 — platform-specific Reveal, Tab Diagnostics, then the close block); `tabTooltipBuilder` surfaces the full file path on hover; `useDragHandle: false` selects the browser-style whole-chip drag with a keyed leading insertion drop slot; `paneBorderBuilder` draws the split-pane active-pane border (primary at 3 dp on the active pane, `outlineVariant` at half alpha on the other, transparent when not split); and the per-pane reorder routes through `WorkspaceNotifier.reorderTabInPane` so a drop in the second pane of a split lands at the correct global index. WaveCrux passes no new-tab builder, so tab bars have no `[+]` button (a blank tab is a dead end).

```
┌───────────────────────────── WaveCruxPaneHost ──────────────────────────────┐
│ ┌──────────── pane "L" ────────────┐ ┌──────────── pane "R" ────────────┐   │
│ │ [tab a × ] [tab b × ]            │ │ [tab c × ]                        │   │
│ ├──────────────────────────────────┤ ├───────────────────────────────────┤   │
│ │ tab a content: docks + canvas +  │ │ tab c content: docks + canvas +   │   │
│ │ strip + status bar               │ │ strip + status bar                │   │
│ └──────────────────────────────────┘ └───────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────┘
        ↑ active pane shown with a primary-colour border
```

Properties of the split-pane layout:

- **Pane count:** 1 (single) or 2 (split). Three side-by-side waveform views add little and make resizing cramped.
- **Active pane:** `activePaneIdProvider` tracks focus. File→Open, command palette actions, WCP commands, and keyboard shortcuts target the active pane's active tab.
- **Tab placement:** each `WorkspaceTab` belongs to exactly one pane via `paneId`. Tabs move between panes by dragging a tab chip onto the other pane or via the "Move Tab to Other Pane" command (View menu / palette; no default shortcut).
- **Split / unsplit commands:** "Split Pane Right" (`Cmd/Ctrl+\`) creates a second pane and moves the active tab into it; "Close Pane" (`Cmd/Ctrl+Shift+W`) closes the active pane and merges its tabs into the surviving pane. Closing the last tab of either pane, when two exist, removes that pane.
- **Device gating:** split-pane is rendered on `DeviceClass.desktop` unconditionally and on `DeviceClass.tablet` when width ≥ 1000 dp (`kPaneHostMinSplitWidthDp`). Phone and phone-landscape always render single-pane. The split actions themselves are gated only to tablet-or-desktop, so on a narrower tablet "Split Pane Right" creates a pane that is not rendered until the window is wide enough.
- **Multi-window independence:** the pane host lives inside one `FlutterView`. Split-pane is widget-tree composition; multi-window (§6.4) would be a separate `FlutterView`.

#### 6.5.1 Adaptive Layout

`ViewerScreen` renders the same tab content on every device class and adapts it through `deviceClassProvider`: at phone widths it force-hides the `CruxIdeLayout` side and bottom regions, hosts the signal tree in a `Scaffold.drawer`, draws values inline at the cursor, and opens the bottom dock as a modal sheet (§3.1.8.6).

**Phone layout (`phone` / `phoneLandscape`):**
```
┌──────────────────────────┐
│  Toolbar (+ overflow)    │
├──────────────────────────┤
│  Signal list │ Ruler     │
│              ├───────────┤
│              │ Canvas    │
│              │ (values   │
│              │  inline)  │
├──────────────────────────┤
│  Status Bar [▶]  [▲]     │
└──────────────────────────┘
  ↙ [▶] drawer   ↘ [▲] bottom sheet
Signal Tree      Bottom dock (Transactions,
                 Stage, analyses)
```

**Tablet layout:** identical to the desktop layout above (tab bar included, live statistics strip excluded), with the narrow pane defaults below 800 dp wide.

The individual panel widgets (signal tree, value column, transaction table, Stage) are shared across all layouts — only the host changes. Panel widgets must not assume a specific parent layout; they receive their constraints from the layout and adapt accordingly.

### 6.6 RISC-V Trace Substrate (`lib/services/riscv/`)

Open core, pure Dart, zero Flutter imports. The substrate turns a VCD/FST of an **RVFI-instrumented** RISC-V core into the derived state the RISC-V Core Designer widget family renders. It answers *did an instruction retire, with what architectural effect, and where did it sit in the pipe* — questions the existing RISC-V **decoder** (`lib/services/decoders/isa/`, "what was fetched") cannot. The two are layered, not overlapping: the substrate **reuses `InstructionDisassembler` rather than reimplementing decode**, and `services → services` is a sanctioned dependency (§6.2).

Two open-core Stage widgets render it — the Commit Inspector (`riscv_commit`, §6.6.1) and the Pipeline Diagram (`pipeline`, §6.6.2); the Pro overlay builds further widgets on the same substrate.

| File | Role |
|---|---|
| `rvfi_channel.dart` | The 21 riscv-formal `rvfi_*` channels as an enum, with `isRequired` (valid / insn / pc_rdata) and `isReducedSetMember` (adds rd_addr / rd_wdata). `kRiscvInstructionBitWidth = 32`. |
| `rvfi_binding_set.dart` | `RvfiBindingSet` (channel × retirement-channel-index → signal ref) plus `RvfiCompletenessReport` — what was found, what is missing, whether the reduced set applies, how many retirement channels, whether a packed superscalar vector is suspected. |
| `rvfi_detection_service.dart` | Recognizes the bundle by name pattern: hierarchy-prefixed, flattened-prefix (`core0_rvfi_valid`), `_i`/`_o` suffixed, and multi-channel (`rvfi_valid[1]`). Implements `StageAutoBindService`. |
| `riscv_trace_values.dart` | 4-state bit-string decode (`riscvBitState`, `riscvDecodeUint`) — the same shape the overlay's register-snapshot service uses, so the two agree on what an `x` means. |
| `riscv_retired_instruction.dart` | `RiscvRetiredInstruction` + `RiscvMemoryEffect`. Every decoded field is nullable, because a partially-instrumented core is a supported case; only `time`, `channelIndex` and `hasUnknownBits` are always present. |
| `riscv_retire_stream_service.dart` | Walks the trace into an ordered retire stream. Disassembler injected, never constructed. |
| `riscv_arch_state.dart` / `riscv_arch_state_service.dart` | Folds the stream to the cursor into a register snapshot + PC + last-N memory effects. |
| `riscv_instruction_identity.dart` | `RiscvIdentitySource` (`tag` / `pc` / `positional`), the two open-core trackers, and `RiscvIdentityTrackerRegistry`. Also the shared warning vocabulary `RiscvIdentityWarningKind` — `occupancyMismatch` / `ambiguousPc` / `ambiguousTag` / `contradictoryControl` / `unexplainedDrop`. **`ambiguousTag` is never raised by an open-core tracker**: it is the tag counterpart of `ambiguousPc` and belongs to a `tag` source, but the vocabulary lives with the identity model rather than with whichever build implements a given source (an open-core test pins that open core never emits it). |
| `riscv_pipeline_observation_service.dart` | `RiscvPipelineStageBinding` + `RiscvPipelineObservationService` — derives the cycle domain from a bound clock's rising edges and samples per-stage `valid` / `pc` / `stall` / `flush` into a `RiscvPipelineObservationResult` (the `RiscvPipelineObservation` model itself is declared in `riscv_instruction_identity.dart`). **Architecture-neutral**; it lives here because the observation model does, not because it is ISA-coupled. Carries a `tagRef` it never populates, so an overlay tag tracker can reuse it rather than fork it. |
| `riscv_abi_register_name.dart` | `riscvAbiRegisterName(int)` / `riscvNumericRegisterName(int)` — the RISC-V ABI mnemonic table. Open core **owns** it; the overlay's register-naming code delegates here rather than keeping a second copy. |
| `riscv_instruction_fields.dart` | `riscvDecodedIntegerRd` / `riscvDecodedAccess` + mask helpers — the two structured facts the checker compares against RVFI. **Not a decoder**; returns `null` ("declines to judge") for compressed, floating-point, atomic and unallocated encodings. |
| `riscv_consistency_checker.dart` | The six checker rules, each a separate top-level function, plus `RiscvConsistencyCheckOptions.forBindings` which computes *which rules the bound channel set can support*. |

Four rules this substrate is built around, each of which has burned someone:

1. **Every bound pin must be watched through `stageBoundSignalProvider` before the substrate walks the source.** `WaveformDataSource.valueAt` returns `null` both for "not loaded" and for "no value yet" — the two are indistinguishable. With ~20 RVFI channels, forgetting the lazy-load watch produces a silently empty widget on a perfectly good trace. `RvfiBindingSet.allRefs` is the list to watch.
2. **There is no cycle domain.** `startTime` / `endTime` / `placePrimary` are simulation *ticks*. "Cycle" is derived by the consumer from a bound clock's rising edges; nothing in `services/riscv/` invents one.
3. **Retirement is located by `rvfi_valid` rising edges *and* by `rvfi_order` changes while valid is held high.** A core retiring on consecutive cycles holds `rvfi_valid` high across them; an edge-only reader silently collapses the run. The committed `riscv_rvfi_retire` fixture exercises exactly that.
4. **Replay is stateless — a backward seek rebuilds.** `RiscvArchStateService.build` clamps to `[startTime, min(cursor, endTime)]`, rebuilds the stream from the start, and folds with a hard break past the cursor. The cursor is a scrub bar, and an incremental cache is only correct forwards.

**Honesty over plausibility.** Three places deliberately report a limitation rather than guessing: a packed superscalar `rvfi_valid` vector is *suspected* rather than sliced — the wide signal is bound as channel 0 and `RvfiCompletenessReport.packedVectorSuspected` is set (no UI surfaces that flag yet); positional identity tracking self-checks its shift-register model against the observed per-stage `valid` bits every cycle and reports `RiscvIdentityConfidence.low` with per-cell warnings on any disagreement; and `RiscvIdentityTrackerRegistry` has **no `tag` tracker in open core** — `create(RiscvIdentitySource.tag)` returns `null` so a consumer says "not available" instead of drawing a plausible lie. A tag-based tracker (the overlay ships one) installs itself through `RiscvIdentityTrackerRegistry.register`.

Fixtures come from `tool/generate_riscv_fixtures.dart`, which emits both the four fetch traces and the RVFI retire trace plus its `.expected_retire_stream.json` into `test/fixtures/protocol/riscv/generated/` and the mirrored `verification/` tree. Before writing the RVFI and pipeline traces, the generator cross-checks their programs' expected disassembly against the real `InstructionDisassembler`, so a hand-encoding typo fails the generator rather than baking a wrong fixture. (The four fetch traces are written before that check runs and are not covered by it.)

It also emits **one deliberately corrupted RVFI variant per checker rule** (`riscv_rvfi_bad_pc_wdata`, `…_bad_x0_write`, `…_bad_rd_addr`, `…_bad_mem_mask`, `…_bad_order`, `…_bad_trap`), each with a hand-written `.expected_violations.json`. **That pairing is the checker's real test surface:** a checker with a broken rule and a checker with no rules produce the same output — "no violations" — and only a fixture that *must* fire tells them apart. Each variant retires the same ISA-legal program as the clean fixture and corrupts one thing the core *claims* about it, so `test/services/riscv/riscv_consistency_fixtures_test.dart` can assert both that the target rule fires and that **no other rule does**. The expectations are authored, never captured from the checker — capturing would make the test pass whatever the checker happens to do today.

### 6.6.1 RVFI Commit Inspector (`lib/features/stage/widgets/riscv/`)

The open-core Stage widget over the substrate: widget id `riscv_commit`, category `instrument`, tier `openCore`. Registered in `registerBuiltinStageWidgets()` like any other built-in.

| File | Role |
|---|---|
| `riscv_commit_stage_widget.dart` | The definition: 21 pins named exactly as the riscv-formal ports (three required), `autoBindService` → `RvfiDetectionService`, `autoBindTitleKey`, and three display config params. |
| `riscv_commit_stage_renderer.dart` | The `ConsumerStatefulWidget`: the lazy-load watch, the memoized whole-trace analysis, the per-build fold to the cursor, the view selector. |
| `riscv_commit_view_data.dart` | `RiscvCommitViewData` — the immutable bundle the five views read. |
| `riscv_commit_views.dart` | The five view bodies (commits / registers / memory / traps / checks) and the 44 dp touch-target constant. |
| `riscv_commit_messages.dart` | The one place the pure-Dart checker's `(kind, args)` becomes a localized sentence. Keeps the checker Flutter-free and the ARB rule-free. |

Three things about it that are load-bearing rather than incidental:

- **Whole-trace analysis, cursor-scoped state.** The retire stream and the checker run over the entire trace and are memoized against `(source, bindings, disassembler)`, so scrubbing does not re-walk it. The architectural state is a fold to the cursor, recomputed every build under the stateless-rebuild contract (rule 4 above). Violations therefore exist *ahead* of the cursor and stay clickable — "jump to the retirement that broke" is the workflow the checker exists for.
- **A rule that could not run is reported, never counted as passing.** `RiscvConsistencyCheckOptions.forBindings` derives the runnable rule set from the bound channels, and the Checks view names the skipped rules. A quiet result from a check that never executed is the only way this widget could actively mislead someone.
- **Not crippled, and no upsell.** This widget and its checker are open core by deliberate decision: correctness is free, productivity is paid. The open-core build must answer *is my core correct?* end to end — every retired instruction, the reconstructed architectural state, and the invariant violations — with no license and no crippled mode; microarchitectural performance analysis is what an overlay adds. There is no row cap, no watermark and no in-view upgrade prompt, and there must not be one added.

**A known bound on decode fidelity.** The renderer watches the shared process-wide `riscvDisassemblerProvider`, which composes the whole TOML corpus — bundled sets plus any user-supplied tables (§6.7) — without filtering by XLEN — deliberately, because open core has exactly two `IsaDecoderAssets.loadFromBundle()` call sites and adding a third for this widget is not worth it. `test/services/decoders/isa/isa_set_load_order_test.dart` proves mechanically that the RV32I/RV64I shift-immediates are the **only** cross-set encoding ambiguity in the corpus, so the entire observable effect is that a legal RV32 `slli`/`srli`/`srai` is attributed to `RV64I` (identical text, different set name) and an *illegal* RV32 shift with `insn[25]` set decodes rather than failing to match. If that bound ever stops holding (a user table can break it), compose per-XLEN sets the way `RiscvDecoder.resolveInstructionSets()` does and inject the result.

### 6.6.2 Pipeline Diagram (`lib/features/stage/widgets/pipeline/`)

The second open-core Stage widget of the family, and the one that is **not RISC-V-specific at all**: widget id `pipeline` (bare, deliberately *not* `riscv_pipeline`), category `instrument`, tier `openCore`. Rows are in-flight instructions, columns are clock cycles, cells are shaded by stage, and clicking a cell moves the primary cursor to that cycle's tick. User-named stages plus per-stage `valid` / `stall` / `flush` is generic pipeline occupancy — it applies unchanged to an FFT engine, a video pipeline, a crypto core, a systolic array or a packet processor — so the id was chosen before it hardened into shipped `.wavecrux` sessions and every ARB file, where a rename becomes a migration. It ships the classic five-stage in-order pipeline (`IF` / `ID` / `EX` / `MEM` / `WB`) as its **flagship preset**, which is what an RVFI-instrumented teaching core looks like; the RISC-V flavour lives in that preset and in the bundled fixture, never in the widget's own ids, pins or strings. `pipeline_stage_widget_test.dart` asserts that mechanically.

| File | Role |
|---|---|
| `pipeline_stage_widget.dart` | The definition: one required `clk` pin, an optional `instruction` pin, four pins per stage for eight stages, three view params plus eight stage-name params, and the `parsePipeline*` config readers. |
| `pipeline_stage_renderer.dart` | The `ConsumerStatefulWidget`: the lazy-load watch, the memoized whole-trace observation + tracking, the per-build window, the confidence banner and the cell→cursor seek. |
| `pipeline_view_data.dart` | `PipelineViewData` / `PipelineRow` / `PipelineCell` and `buildPipelineViewData` — windowing, row ordering, row labelling and per-cell mismatch marking. Pure Dart. |
| `pipeline_grid.dart` | The grid itself: pinned label column, horizontally scrolling cycle columns, the theme-derived per-stage colour ramp, the legend and the 44 dp cell constant. |

Four things that are load-bearing rather than incidental:

- **Thirty-four declared pins, and never thirty-four listed pins.** Every per-stage pin carries a `SignalBinding.visibleWhenValues` predicate keyed off the `stageCount` config param, so the bindings pane shows only the stages the user enabled. That seam exists for this widget. For the stages inside the default pipeline (1–5) the predicates admit `null` as well as the numeric counts at or above the stage index, because the pane tests the instance's **raw** configuration map and a freshly-dropped instance has an empty one — declared defaults are applied on read, not on creation. Without the `null`, a new instance would show a clock pin and nothing else.
- **There is no cycle domain.** `startTime` / `endTime` / `placePrimary` are simulation ticks. Cycles are indices into the rising edges of the bound clock, computed by `RiscvPipelineObservationService`, and every seek converts back through `cycleTicks`. The cycle index is internal; the tick is what the rest of the app shares.
- **Low confidence is stated, not implied.** This is the widget's hard requirement: a pipeline diagram that silently mis-attributes is worse than no diagram. When the tracker returns `RiscvIdentityConfidence.low` the renderer shows a banner naming the tracker and the number of contradicted cells, marks drawn cells the tracker disowns (a cell the model expected but the trace shows empty is not drawn, so it appears only in the banner count), and dims the grid so it cannot be screenshotted as a finding without the caveat. The grid is still drawn, because the tracker adopts the trace where it disagrees with its own model and a readable-but-flagged grid beats a blank panel.
- **`tag` is not selectable.** The config offers `positional` and `pc` only, `parsePipelineIdentitySource` folds an unrecognised value (including a `tag` written by an overlay build's session) back to `positional`, and the renderer states "no tracker for this source" rather than rendering an empty diagram if one ever reached it. A tag tracker installs through `RiscvIdentityTrackerRegistry.register`.

**Fixtures.** `tool/generate_riscv_fixtures.dart` emits `riscv_pipeline_5stage` and `riscv_pipeline_defeat` — the *same* seven-instruction RV32I program through the same five-stage pipe, with a load-use stall, an EX→EX back-to-back forward and a taken-branch flush. They differ only in how the kill is expressed: the first drives the `stageN_flush` pins, the second drops `valid` and leaves them low. Positional tracking models the first exactly (`high`) and cannot model the second (`low`, with one `occupancyMismatch` per contradicted cell), while PC matching survives both. **That pair is the widget's real test surface** — the two produce an identical grid, so only the confidence verdict distinguishes a finding from a fabrication. The `.expected_pipeline.json` is written from a hand-drawn ASCII pipeline diagram that the generator cross-checks against the occupancy table it renders the VCD from, so nothing in the expectation is captured from the tracker.

### 6.6.3 CXP semantic stream coordinate — the consumer seam

A plain CXP cross-probe gets a peer to the right *file*; the [CXP §9.9](https://edacrux.app/cxp#sec-9-9) **semantic stream coordinate** gets it to the right *element inside the file* — "open this counterexample **at step 7**". (Section numbers here refer to the CXP specification, published at [edacrux.app/cxp](https://edacrux.app/cxp); `crux_cxp` implements it.) SimCrux produces the coordinate; WaveCrux, which holds the decoded trace, consumes it. Open core end to end, with no tier gate anywhere on the path — a counterexample hand-off answers whether a core is correct, which is never gated — and `cxp_inbound_handlers_test.dart`'s stream-coordinate group asserts that by running the whole hand-off on an unlicensed container.

| File | Role |
|---|---|
| `lib/services/remote/cxp/riscv_stream_coordinate_resolver.dart` | `RiscvTraceStepGrid` (the step lattice), `RiscvCoordinateResolution` (landed-on-a-retirement / landed-on-a-step / declined), `RiscvStreamCoordinateResolver` (the two bindings), and `RiscvCoordinateAttributes` (the advisory keys). Pure Dart. |
| `lib/services/remote/cxp/cxp_inbound_handlers.dart` | `_applyStreamCoordinate` / `_resolveStreamCoordinate` — the element is honoured first, then the coordinate is resolved against the trace it just opened. |
| `lib/features/stage/providers/riscv_commit_landing_provider.dart` | `RiscvCommitLanding` + the per-tab notifier the banner reads. |
| `lib/features/stage/providers/riscv_commit_auto_stage.dart` | `mountRiscvCommitInspector` — adds the Stage panel + bound Commit Inspector a freshly-opened tab has no other way to get. Lives in the feature layer, not under `services/`: it composes two feature notifiers, and the import-layering guard is right to insist. |
| `RiscvCommitLandingBanner` (in `riscv_commit_views.dart`) | The caption, the provenance surface, and the account of who mounted the panel. |

**Two streams, and deliberate tolerance for every other one.** `riscv.formal.trace_step` is what actually arrives: a bounded model checker reports the step its assertion fired at and *cannot* report `rvfi_order`, because how many instructions a core retires in seven cycles is a property of the core under proof. **Whoever holds the decoded stream owns the index conversion**, so the conversion lives here. `riscv.rvfi.retire` — the spec's normative binding, indexed by `rvfi_order` — is accepted too. Anything else (`axi.transaction`, `ethernet.frame`, …) is ignored with a reason and **never** treated as a protocol error; [CXP §9.9.1](https://edacrux.app/cxp#sec-9-9-1) requires exactly that, and it is the forward-compatibility path the generic coordinate was designed for.

**How the step grid is established, and what happens when it cannot be.** There is no step domain in a waveform. `RiscvTraceStepGrid.derive` recovers one by measuring: it collects every tick at which any **bound RVFI signal** changes (plus `startTime` and `endTime`), takes the pitch to be the smallest positive gap between consecutive distinct ticks, and then **verifies that every collected tick lies on `startTime + k·pitch`**. Only the RVFI channels are measured — a counterexample dumped with a clock carries half-step transitions that have nothing to do with the proof — and the origin is `startTime` because step 0 *is* the trace's initial state by the binding's own definition. A trace that fails the lattice check (an ordinary simulation dump), or that binds no RVFI at all, yields **null**, and the handler declines the coordinate while still honouring the element and saying so in the ack's `reason`. The residual bound is stated in the class doc rather than hidden: a trace whose RVFI channels only change on every *other* step leaves no evidence of the finer lattice, and no receiver could recover it from the file alone.

**The cursor is the selection.** The Commit Inspector's history views show the retirements at or before the primary cursor and mark the last of them as current, so placing the cursor exactly on a retirement's tick selects that retirement, folds the register file to it, and scopes the memory and trap logs to it. One move, four consistent cursor-scoped views (the Checks view stays whole-trace) — which is why the consumer does not carry a second selection concept. When the addressed step exists but nothing retired there, [CXP §9.9.2](https://edacrux.app/cxp#sec-9-9-2)'s prescribed fallback applies: the cursor moves, nothing is selected, and the ack and the banner both say so.

**The lazy-load trap bites here too, and harder.** Resolving a retirement means the substrate walks the source, and a cross-probe is the worst case for it — the trace was opened a moment ago by the hand-off itself and nothing is in the viewer, so every ref the detected bundle names is loaded *before* the walk. The retire stream is built with a **null disassembler** on purpose: nothing the resolver reads comes from disassembly, and composing one costs an async asset load.

**`riscv.pc` disproves, never resolves.** [CXP §9.9](https://edacrux.app/cxp#sec-9-9) rule 2 forbids needing an attribute to *find* an element. The PC attribute is used only to reject: a retirement at the requested `rvfi_order` whose PC disagrees with the sender's means this is not the trace the coordinate was measured in, and declining beats selecting the wrong instruction.

**The banner carries the provenance obligation.** It is the only surface in WaveCrux that repeats a peer's claims about a proof — check, group, "step 7 of 20", ISA — so `riscv.mode == "demo"` is rendered as an explicit *replayed demo fixture, not a measured solver run* line. Suppressing that label would let a screenshot of a replayed demo read as a measured result. The landing is per-tab and self-clears when the tab's waveform changes, because a landing is a statement about one trace.

**The landing has to be *visible*, and on a fresh tab it is not.** A tab the hand-off opened a moment ago has no Stage panel — so no Commit Inspector, and therefore no banner, because the banner lives inside the widget; moving the cursor alone would land it on an empty canvas. `mountRiscvCommitInspector` closes that: when a coordinate **resolves against an RVFI stream**, it adds a Stage panel holding one `RiscvCommitStageWidget`, binds it through `RvfiDetectionService` (the same `StageAutoBindService` the manual Auto-bind affordance uses — there is no second binding path), and reveals the panel's bottom-dock tab. Adding the panel, the instance, and its bindings is one `StageWorkspaceNotifier` transaction, so one Ctrl/Cmd+Z removes them; the dock reveal and resize happen on `PanelLayoutNotifier` afterwards and are not part of that undo step.

Three conditions, all load-bearing:

* **Only on a resolved coordinate.** The mount is reached only past every decline — unknown `stream_id`, no RVFI bundle, no step grid, step past the end — including when the step resolves but nothing retired there. A non-RVFI trace's layout is never touched.
* **Only into a tab the cross-probe opened.** `_ElementOutcome.openedTab` is threaded out of every path that can open one. On the signal-like element path, activating a tab that already held the file reports **false**, because the user arranged that tab — it gets its cursor moved and nothing else; both directions are asserted in `riscv_counterexample_handoff_test.dart` (with a `signal` element). A `source` element — the SimCrux counterexample hand-off — always opens a new tab and reports **true**, so re-sending an already-open trace yields a second tab with its own inspector.
* **Only once per tab.** A repeat cross-probe onto a tab that already holds an inspector re-captions the existing one rather than stacking a second.

And the banner says so: `RiscvCommitLanding.autoMounted` renders a line stating that the panel was opened by the incoming cross-probe and bound to the trace's RVFI channels. A panel that appears unbidden with no explanation is worse than no panel.

**"Mounted" is still not "visible", and the second half is the scroll.** At the widget's declared `defaultSize` (560 × 380) in a bottom dock at its default 200 px, the panel shows the banner and about two commit rows, so a violating retirement late in the log would land below the fold. Two mechanisms handle that, and only one of them is load-bearing:

* **`RiscvCommitLogView` scrolls the landed retirement into view** when a landing is recorded, keyed on `RiscvCommitLanding.token` so a repeat cross-probe re-reveals and ordinary cursor scrubbing does not. The landed row is the *last* row of `retiredSoFar` by construction, so the target is the scroll extent's end — exact for rows of unequal height, and a no-op when the log fits its viewport or the landing is on the first retirement. This is the half that matters: a panel may legitimately be small (the user's layout, a phone, a session file), and the row has to come to them.
* **`kRiscvCrossProbeMountSize` (720 × 420) and `kRiscvCrossProbeDockHeight` (480)** size the panel for five or six rows of context instead of two. The dock grows through `PanelLayoutNotifier.growBottomPaneTo`, which is raise-only — sizing the instance alone would not help, because the Stage canvas is an unconstrained `InteractiveViewer` that *pans* an oversized instance rather than scrolling it.

The end-to-end test pumps the inspector at the mounted instance's own rect rather than a full-screen `Scaffold` body, and asserts the landed row's painted rectangle lies inside the commits list's painted rectangle — asserting only that the right row is tinted would pass while the row is scrolled out of sight.

**No raw `rvfi_*` lanes are added to the canvas.** The Commit Inspector *is* the payload — it renders the disassembly, the operand values, the architectural effect and the checker verdict — while twenty-one raw hex lanes would bury it and would be an unrequested rearrangement of a surface the user owns. The canvas remains the *sender's* channel: SimCrux's `notify_selection` carries `simcrux.suggested_signals`, and `_applySuggestedSignals` places whatever it names.

### 6.7 Instruction-Decoder Namespace (`lib/services/decoders/isa/`)

Everything here except `riscv_decoder.dart` is **ISA-neutral**. The data model is a port of JKU's [`instruction-decoder`](https://github.com/ics-jku/instruction-decoder) crate, whose TOML schema is a generic formats / parts / mappings encoding description with nothing architecture-specific in it, and the disassembler takes a bare `List<InstructionSet>`. All the RISC-V-ness lives in the TOML corpus under `assets/decoders/isa/riscv/` and in `riscv_decoder.dart`. Table authoring is documented in [`docs/ISA_TABLE_AUTHORING.md`](ISA_TABLE_AUTHORING.md).

| File | Role | ISA-specific? |
|---|---|---|
| `instruction_set.dart` | `InstructionSet` / `InstructionFormat` / `InstructionDef` / `PartDecoder` / `Mapping` — the JKU runtime model. | No |
| `instruction_set_toml_loader.dart` | `parseInstructionSetToml` + `InstructionSetTomlException`. One TOML document → one `InstructionSet`. | No |
| `instruction_disassembler.dart` | `InstructionDisassembler` — matches an instruction word across the loaded sets and renders it via the format's `repr` template. | No |
| `isa_decoder_assets.dart` | `IsaDecoderAssets` — discovers and caches `assets/decoders/isa/<architecture>/*.toml` at startup, overlays user tables, and records `IsaTableLoadIssue`s. | No |
| `user_isa_tables.dart` (+ `_io` / `_stub`) | `loadUserIsaTables` — scans `WAVECRUX_ISA_PATH` and the user-configured table directories for `*.toml`; the web stub returns nothing. | No |
| `isa_trace_decoder.dart` | `IsaTraceDecoder` — the architecture-neutral instruction-fetch trace walk (fetch clock, optional valid strobe, instruction / PC words, transaction formatting); a subclass only chooses which tables to consult. Also the `isaDisassemblyRenderer` hook an overlay can set to post-process disassembly (e.g. alias rendering). | No |
| `riscv_decoder.dart` | `RiscvDecoder extends IsaTraceDecoder` — decoder id `riscv`, XLEN/extension parameters, and the mapping from those parameters onto the RISC-V TOML corpus. | **Yes** |

**Discovery, not a filename list.** `IsaDecoderAssets.loadFromBundle({architecture = kDefaultIsaArchitecture, userTableDirectories})` reads `AssetManifest` and loads every direct-child `.toml` under the architecture's directory, resolving it at either the bare `assets/…` key (wavecrux as the running app) or the `packages/wavecrux/assets/…` key (wavecrux as a path dependency). Per-file failures are isolated so one malformed TOML degrades coverage instead of breaking startup, and each failure is **recorded** as an `IsaTableLoadIssue` naming the file and the parser's message, which the Settings ISA tables panel shows. A key is only ever `loadString`ed after the manifest confirms it exists — a failed `rootBundle.loadString` raises an *uncaught async* asset error that flakily reds whichever integration test it lands in.

**User tables.** After the bundled sets, `loadFromBundle` overlays every table found by `loadUserIsaTables` — directories from the `WAVECRUX_ISA_PATH` environment variable (path-list separated) first, then the directories configured in Settings (`peekIsaTableDirectories`); relative paths are ignored with a log line. A user table wins a name collision with a bundled set and is appended after every bundled one, so under last-match-wins a table describing a custom instruction overrides the base encoding it overlaps — usually the reason the table exists. `userSuppliedSets` records which sets came from disk.

**Load order is semantics.** `InstructionDisassembler` resolves an encoding matched by more than one set with "last match wins", so a set loaded later overrides an earlier one — that is how `RV64I.toml`'s 6-bit-shamt `slli`/`srli`/`srai` override `RV32I.toml`'s 5-bit form. `AssetManifest` guarantees no order, so discovery imposes one on the bundled sets: `compareIsaSetNames` sorts ascending by the first digit run in the asset name (the register width the set is named for, so a narrower base set always loads before its wider sibling) and breaks ties lexicographically, giving a total order independent of manifest iteration. User tables follow in directory / filename order. `test/services/decoders/isa/isa_set_load_order_test.dart` proves mechanically — by intersecting every cross-set `(mask, match)` pair — that the RV32I/RV64I shift-immediates are the *only* cross-set encoding ambiguities in the bundled corpus, so the ordering of every other bundled pair cannot affect output; a new ambiguity in the corpus fails that guard instead of being decided silently by the sort.

Open core calls `loadFromBundle` in exactly two places: `app.dart` (registers the `riscv` decoder factory) and `plugins/translator_registry.dart` (builds the shared disassembler behind `RiscvDisasmTranslator`); both pass the same user table directories, so the decoder and the translator cannot disagree. `RiscvDecoder` composes the canonical RISC-V sets by **explicit set name** for the configured XLEN and extensions, then appends every other available set (the user tables) in canonical order, so composition is deterministic rather than decided by discovery.

**RISC-V is the only architecture open core bundles.** The `architecture` parameter and the `IsaTraceDecoder` split keep the namespace from being welded to one ISA: an overlay can ship curated tables for another architecture under its own asset directory and register an `IsaTraceDecoder` subclass for it, and users can extend the RISC-V decoder with their own tables.

---

## 8. Coding Standards & Conventions

### 8.1 Dart / Flutter

- **Effective Dart** — Follow the official Effective Dart guidelines as the baseline.
- **Linting** — `very_good_analysis` (`analysis_options.yaml`). Zero lint warnings policy — CI treats warnings as errors.
- **Null safety** — Fully sound null safety. Avoid the `!` operator unless the non-null contract is provably guaranteed, and say why in a comment.
- **Immutability** — Domain models should be immutable plain Dart classes with `const` constructors, manual `copyWith`, `==`, and `hashCode`. No freezed.
- **No hardcoded strings** — Every user-facing string must come from the localization system (ARB files via the generated `L10N` class, §5). No string literals in widget code, screen code, or service code that will be displayed to the user. The only exception is test code.
- **Naming conventions:**
  - Files: `snake_case.dart`
  - Classes: `PascalCase`
  - Variables, functions, parameters: `camelCase`
  - Constants: `camelCase` (Dart convention, not `SCREAMING_SNAKE`)
  - Providers: `camelCase` ending in `Provider` (e.g., `signalGroupsProvider`)
  - Private members: `_prefixed`

### 8.2 Widget Architecture

- **One widget per file.** Each public widget class lives in its own `.dart` file, named in `snake_case`.
- **Keep widgets small.** If `build()` exceeds ~50 lines or has 3+ nesting levels, extract child sections into their own widget files.
- **Favor composition over configuration.** Distinct widget variants over boolean flags.
- **Build for reuse.** Leaf widgets accept data via constructor. Place shared widgets in `lib/shared/widgets/`.
- **Stateless over stateful.** Prefer `ConsumerWidget` with Riverpod. Only use `StatefulWidget` for local mutable state (canvas gesture handlers, animations, form controllers, focus nodes).
- **Custom painting only where the widget tree cannot do the job.** The waveform canvas is a custom `RenderObject` (`WaveformCanvasRenderObject`, `lib/features/viewer/rendering/`); `CustomPainter` is used for genuinely graphical overlays and gauges (time ruler, cursor / marker / annotation overlays, the FSM bubble diagram, sparklines, Stage primitives and board widgets). Don't reach for either for standard UI.

### 8.3 Riverpod Conventions

The project is on Riverpod 3 (`flutter_riverpod`, `riverpod_annotation` + `riverpod_generator`).

- Prefer the `@riverpod` / `@Riverpod(...)` annotation (code generation) for new providers. Hand-written `Provider` / `NotifierProvider` declarations are used for cross-repo extension points (`lib/core/providers/`, `lib/plugins/`) and a few composition roots, where a plain, overridable declaration is the point.
- Feature providers live in the feature's `providers/` directory; extension points in `lib/core/providers/` or `lib/plugins/`; layout helpers in `lib/shared/layouts/`.
- Providers should be thin — delegate logic to services.
- `Notifier` / `AsyncNotifier` classes (`@riverpod class …`) for mutable state; long-lived async state such as the loaded waveform is a keep-alive notifier whose state is an `AsyncValue`. `StateNotifier` is not used.
- Use `ref.watch` for values a widget renders from; `ref.read` belongs in callbacks and one-shot lookups.
- A file-specific provider must be registered in `wavecruxTabOverrides` (§6.4), or it resolves against the empty root scope.

### 8.4 Testing Strategy

**Tests are expected with every change.** New or modified production code in `lib/` should come with a corresponding test.

#### Test File Structure

Test files mirror the `lib/` directory structure:

```
lib/domain/models/scope.dart                     → test/domain/models/scope_test.dart
lib/services/value_format/value_format_service.dart → test/services/value_format/value_format_service_test.dart
lib/services/decoders/spi_decoder.dart           → test/services/decoders/spi_decoder_test.dart
lib/features/viewer/widgets/waveform_canvas.dart → test/features/viewer/widgets/waveform_canvas_test.dart
```

Cross-cutting structural guards live in `test/static/` (import layering, locale sweeps, decoder fixture coverage, documented paths in this file, and others).

#### Coverage

`tool/coverage.sh` and the `coverage.yml` workflow measure line coverage against a single repo-wide floor. Aim higher for domain models and services than for widgets; every built-in protocol decoder must have fixture-driven tests (`test/static/all_decoders_have_fixtures_test.dart`).

#### Testing Conventions

- Use `mocktail` for mocking (not `mockito`).
- Domain model tests: verify equality, `copyWith`, computed properties, edge cases.
- Service tests: test with realistic signal data. For protocol decoders, use the fixture VCD / FST files under `test/fixtures/protocol/` (§8.9).
- Provider tests: create a `ProviderContainer` with overridden dependencies, verify state transitions.
- Widget tests: screens and interactive widgets include a locale sweep that renders in `en` and at least one CJK locale and asserts no exceptions (`expect(tester.takeException(), isNull)`). `test/static/locale_sweep_guard_test.dart` fails a widget test that pumps localized UI without touching a CJK locale, unless it carries a `LOCALE_SWEEP_EXEMPT: <reason>` comment.
- Every test file must be self-contained — no shared mutable state between tests.
- **FFI / WASM bridge equivalence:** see §8.9, Layer 1.
- **Benchmarks:** engine throughput (`test/perf/engine_bench.dart`, over large files from `native/torture_gen`) and the render benchmark (`test/benchmarks/waveform_paint_benchmark.dart`) run in the `perf.yml` workflow — weekly and on demand — gated against a baseline by `tool/perf/check_baseline.dart`; they do not run on every push.

### 8.5 Rust Conventions

- Follow standard Rust formatting (`rustfmt`); CI runs `cargo fmt --check` for `wellen_ffi` and `lxt2fst`
- Clippy with `-D warnings` (CI-gated for `wellen_ffi` and `lxt2fst`)
- The FFI surface is `extern "C"` functions only — no Rust types leak across the boundary
- All strings crossing FFI use null-terminated C strings (`CStr` / `CString`)
- Signal data crossing FFI uses flat buffers (timestamp arrays, value byte arrays) — no complex structs
- Panic safety: every FFI entry point that can panic runs inside `catch_unwind` (`ffi_guard!` in `wellen_ffi`) and returns an error value; the remaining entry points are null-checked field reads that cannot panic. Keep it that way when adding one.

### 8.6 Git Conventions

- **Branches and pull requests:** contributors fork, branch off `main`, and open a pull request against `main` — see `CONTRIBUTING.md`, which also describes the required DCO sign-off (`git commit -s`) and the local quality gates.
- **Commit messages:** Follow Conventional Commits, in both the commit subject and the PR title.
  - `feat: add SPI protocol decoder`
  - `fix: correct hex formatting for 9-state values`
  - `refactor: extract waveform canvas into RenderObject`
  - `docs: document the dock layout`
  - `test: add fixture VCDs for AXI decoder`
  - `chore: upgrade wellen`

### 8.7 Documentation

- Public API for each module documented with `///` doc comments.
- Repository documentation: this file, `CONTRIBUTING.md` (contribution workflow and the decoder-plugin ABI), `docs/ISA_TABLE_AUTHORING.md`, `docs/web_performance.md`, the plugin ABI header `include/wavecrux_decoder.h` with its reference plugins under `examples/`, and the manual verification guides under `verification/`.
- Decisions that span more than one Crux product are recorded as ADRs in `crux-shared/docs/adr/`; WaveCrux-only decisions are recorded here.
- Keep this document current: when the code changes a fact written here, change the text in the same commit. `test/static/doc_truth_test.dart` checks the mechanically checkable part (paths and some derived quantities).

### 8.8 Diagnostics Surfaces & Live Statistics Strip

WaveCrux separates introspection into surfaces aligned with the workspace / pane / tab ownership model from §6.4: a standalone tool, a per-tab drawer, a process-wide dialog, a per-pane popover, and the desktop statistics strip.

**The surfaces:**

1. **Tools menu actions** (standalone tools — no current state required):
   - `Tools → Generate Test VCD…` (`GenerateTestVcdDialog`, backed by `VcdGeneratorService`) — pick a destination, then choose "Generate & Open in new tab", "Generate & Reveal", or Close.

2. **Tab Diagnostics drawer** (per-tab — follows the active tab):
   - Non-modal side drawer (`TabDiagnosticsDrawer`); opened from the tab context menu, the Tools menu, a keyboard shortcut, or the command palette.
   - Three collapsible sections: **File Info**, **Signal Health** (on-demand `SignalIntegrityService` analysis), **Benchmark This File** (`ParserBenchmarkRunner` — re-opens the active tab's file with a fresh `WellenProvider` and records timing).
   - Follows the active tab: switching tabs re-renders the sections against the new tab's providers; the drawer dismisses itself when no tabs remain.
   - "Copy Tab Diagnostics Report" exports just this tab's data as structured plain text.

3. **App Diagnostics dialog** (process-wide):
   - Modal dialog (`AppDiagnosticsDialog`) opened via `Tools → App Diagnostics…`, a keyboard shortcut, the palette, or the debug-build toolbar button.
   - Sections: **Memory** (process RSS and the summed wellen signal-database size), **Per-tab breakdown**, **Frame Stats** (FPS, frame-budget overruns, last frame — measured by the dialog's own frame-timings callback), and **Logs**.
   - "Copy Full Diagnostics Report" aggregates the active pane's render stats, every loaded tab's file info and signal health, and the app-level memory/frame stats (`AppDiagnosticsReportService`).
   - The Tools menu's "Copy Diagnostics Report" action copies the same report through the same helper (`lib/features/diagnostics/copy_app_diagnostics_report.dart`), without the frame stats only the open dialog samples.

4. **Pane Render Stats popover** (per-pane — one per visible canvas):
   - Small popover (`PaneRenderStatsPopover`) anchored to an `i`-icon in each pane's tab bar; also reachable from the command palette.
   - Contents: total paint time and its breakdown (layout, scalar, vector, analog, cursor, transaction), transitions, line segments, and canvas size.
   - Subscribes to the hosting pane's `paneRenderStatsProvider` (see §6.4). With split-pane there are two icons and two popovers.

The drawer, dialog, and popover are tablet + desktop only (§3.1.6).

#### Access Model

```dart
final showDiagnostics = ref.watch(diagnosticsEnabledProvider);
```

`diagnosticsEnabledProvider` (`lib/features/diagnostics/providers/diagnostics_providers.dart`) is the single gate the diagnostics entry points consult (as `ActionRequirement.diagnosticsEnabled`). It returns `true` in every build — debug, profile, and release — because the surfaces are part of the open-core feature set. `AppSettings` still carries a `diagnosticsEnabled` field, but nothing reads it and no UI sets it.

The statistics strip is additionally gated behind `deviceClassProvider == DeviceClass.desktop`: on phone and tablet neither the strip nor its disclosure exists. On desktop the strip (`LiveStatisticsStrip`, a WaveCrux wrapper around `crux_stats_strip`'s `CruxStatsStrip`) is always mounted — one per pane, fed that pane's id — and carries its own disclosure row, which collapses it to 24 px rather than removing it, so the feature stays discoverable. Disclosure state (`statisticsStripVisible`) is part of the per-tab `PanelLayoutState`, persisted in the tab's session sidecar, and reachable from `ShortcutAction.toggleStatisticsStrip`; the strip drives it through `CruxStatsStrip.expanded` / `onToggle` instead of the shared `cruxStatsStripExpandedProvider`, which has nowhere to persist it.

**Shared collectors for the shared readings.** Process memory, FPS, and dropped frames come from `crux_stats_strip`'s own collectors, so the Crux products measure and report them identically. `cruxFrameStatsProvider` measures real `SchedulerBinding` frame timings — not the rate the canvas *could* paint at — and carries a 60-frame sparkline; `cruxMemoryStatsProvider` carries a 60-sample RSS history.

The shared RSS collector only samples while something declares it is being watched, and it takes that cue from `cruxStatsStripExpandedProvider` — which WaveCrux does not use, since its disclosure state is per tab and persisted. The strip therefore holds a `cruxMemoryPollRequestProvider` tag for exactly as long as its expanded subtree is mounted (`_MemoryPollDemand`), which is the mechanism that provider exists for. Without it the Memory segment would show one stale reading under a flat sparkline forever.

Collapsed, the strip returns before watching `memoryStatsProvider` or `paneRenderStatsProvider`. Those are live subscriptions — a memory poll timer and a per-frame render feed — and the strip is mounted for the whole session, so a collapsed strip that watched them would pay for readings nobody has opened.

#### Live Statistics Strip Ownership

The statistics strip surfaces a curated subset of the same data the diagnostics surfaces present. Each strip segment has a natural owner:

| Strip metric | Owner | Behavior |
|---|---|---|
| Memory RSS + sparkline | App-level, **shared collector** (`cruxMemoryStatsProvider`) | Root scope; continuous across tab and pane changes |
| FPS / Dropped + sparkline | App-level, **shared collector** (`cruxFrameStatsProvider`) | Same — continuous |
| wellen DB total / decompressed signals | Per-tab, WaveCrux's own `memoryStatsProvider` | Each tab polls its own loaded source |
| Paint time + sparkline | Per-pane | Each pane's strip reads that pane's `paneRenderStatsProvider`; each pane retains its own 30-sample buffer in its `ProviderContainer` |
| Render time | Per-pane | Same as paint time |

#### Surface-to-data routing

| Data source | Tab Drawer | App Dialog | Render Popover | Strip |
|---|---|---|---|---|
| `fileStatsProvider` (per-tab) | ✓ | per-tab breakdown row | — | — |
| `signalIntegrityProvider` (per-tab) | ✓ (Signal Health) | in the full report | — | — |
| `devToolsProvider` benchmark result | ✓ (Benchmark This File) | — | — | — |
| `memoryStatsProvider` (per-tab) | — | ✓ (summed + breakdown) | — | ✓ (active tab) |
| `cruxMemoryStatsProvider` / `cruxFrameStatsProvider` (app) | — | — (own frame callback) | — | ✓ |
| `paneRenderStatsProvider` (per-pane) | — | ✓ for active pane (Copy Full Report) | ✓ | ✓ (that pane) |

Note that `devToolsProvider` is not in `wavecruxTabOverrides`, so its benchmark result resolves at root scope and is shared across tabs.

#### FFI Diagnostics Counters

`wellen_ffi` exposes four counters for diagnostics (mirrored by `wellen_wasm`):

```c
/// Return format identifier: 1 = VCD, 2 = FST, 3 = GHW, 0 = unknown.
int32_t wellen_file_format(const WellenHandle* handle);

/// Total transitions across the signals loaded so far.
uint64_t wellen_total_transition_count(const WellenHandle* handle);

/// Transition count for a single signal. Returns 0 if not loaded.
uint64_t wellen_signal_transition_count(const WellenHandle* handle, uint32_t signal_ref);

/// Approximate memory in bytes used by the signal database.
uint64_t wellen_memory_usage_bytes(const WellenHandle* handle);
```

#### Architecture

All diagnostics and statistics features follow the standard WaveCrux layering:

```
Domain models (FileStats, MemoryStats, RenderPipelineStats, SignalIntegrityReport, …)
  ↓
Services (FileStatsService, MemoryStatsService, SignalIntegrityService, …)
  ↓
Providers (fileStatsProvider, memoryStatsProvider, signalIntegrityProvider, paneRenderStatsProvider, …)
  ↓
UI ─┬── TabDiagnosticsDrawer (per-tab — tablet + desktop)
    ├── AppDiagnosticsDialog (process-wide — tablet + desktop)
    ├── PaneRenderStatsPopover (per-pane — tablet + desktop)
    ├── GenerateTestVcdDialog (Tools menu)
    └── LiveStatisticsStrip (one per pane, above the status bar — desktop only)
```

The `RenderStatsCollector` is a special case — it lives in the viewer feature module because it hooks into `WaveformCanvasRenderObject.paint()`. Each pane owns a dedicated collector instance (`renderStatsCollectorProvider`, §6.4) and publishes into its own `paneRenderStatsProvider`. The Pane Render Stats popover and the per-pane segments of the strip both consume that provider.

Signal integrity analysis (`SignalIntegrityService`: constant, undriven, glitch, and clock checks) runs on demand from the Signal Health section against the tab's own `WaveformDataSource`, loading every variable through it. There is no separate instance and no dedicated isolate; on desktop/mobile the wellen work itself runs on the provider's worker isolate.

The `LiveStatisticsStrip` adds no data collection of its own — it consumes the shared collectors, the per-tab `memoryStatsProvider`, and its pane's `paneRenderStatsProvider`. The only strip-specific state is sparkline history: 60 samples in the shared collectors, 30 in each pane's render-stats buffer.

### 8.9 Test Fixture & Validation Strategy

Waveform viewer correctness is verifiable only against real waveform files. A viewer that renders the wrong value at the wrong time is worse than useless — engineers will make design decisions based on incorrect data. WaveCrux uses several independent checks on correctness.

#### Test Fixture Sources

| Source | Formats | What It Provides |
|--------|---------|------------------|
| **Hand-crafted known-answer fixtures** | VCD (+ FST mirrors) | Small files under `test/fixtures/vcd/` with `.expected.json` companions. |
| **Generated protocol fixtures** | VCD | `tool/generate_*_fixtures.dart` scripts emit protocol traces and their `.expected_transactions.json` into `test/fixtures/protocol/<protocol>/generated/` (and the mirrored `verification/fixtures/` tree). |
| **Captured protocol fixtures** | FST | `test/fixtures/protocol/<protocol>/captured/` — simulations of third-party RTL, with the testbench sources under `captured/helpers/` and a `PROVENANCE.md`. |
| **Real-world traces** | VCD, FST, GHW | `test/fixtures/real_world/` — outputs of open-source projects and simulators (cocotb, GHDL, Icarus/PicoRV32, Verilator, Yosys), each with a `.provenance.json` and listed in `real_world/README.md`. Add files only through that provenance process; unlicensed harvested corpora are not accepted (see `NOTICES`). |
| **GHDL-generated GHW** | GHW | `tool/ghw_fixtures/regen.sh` simulates `wavecrux_vhdl_types_tb.vhd` to produce the GHW fixtures. |
| **Synthetic generator** | VCD | `VcdGeneratorService` (also behind `Tools → Generate Test VCD…`): deterministic, seed-based generation. |
| **Large-file generator** | VCD, FST | `native/torture_gen` (Rust) produces multi-GB files for the perf benchmarks; they are never committed. |

#### Known-Answer Fixture Files

`test/fixtures/vcd/` holds hand-crafted VCD files with companion `.expected.json` files that document what queries should return; `test/fixtures/fst/` holds their FST mirrors.

| Fixture File | What It Tests |
|---|---|
| `scalar_basics.vcd` | 1-bit signals and a small bus; transitions at various times |
| `vector_formats.vcd` | Multi-bit buses across widths; hex/dec/bin/oct formatting |
| `analog_real.vcd` | Real-valued signals (`$var real`): negative, zero, very small and very large magnitudes |
| `deep_hierarchy.vcd` | Nested scopes (module and task) and duplicate names at different levels |
| `direction_test.vcd` | Port-direction metadata |
| `malformed_value_change.vcd` | A malformed value-change record the parser must tolerate |

Other fixture families live beside them: `analog/`, `cocotb/`, `decoder_plugins/`, `fsm/`, `ghw/`, `gtkw/` (GTKWave save files and a translate-filter file), `legacy/` (LXT / LXT2), `riscv_formal/`, `rtl_source/`, `stage/`, and `themes/`.

#### Validation Layers

**Layer 1 — FFI-vs-WASM bridge validation.** Both `WellenProvider` (FFI) and `WellenWasmProvider` (WASM) wrap the *same* `wellen` crate, so any divergence between them is a marshalling bug, not a parser bug. FFI cannot run in a browser, so the FFI answers are frozen ahead of time: `tool/generate_bridge_snapshots.dart` records the real FFI provider's answers into the committed `.expected.json` companions, and `integration_test/web/web_cross_bridge_test.dart` replays every signal's `valueAt` / `changesInRange` / `nextTransition` / `prevTransition` probe set through WASM in headless Chrome and diffs it against that gold, over the VCD fixtures, their FST mirrors, and the GHW fixture. `test/services/waveform/fst_vcd_equivalence_test.dart` separately proves (via FFI) that each FST mirror reads identically to its VCD source. The web workflow runs on pull requests and on demand; regenerating the snapshots is a manual step.

**Layer 2 — Known-answer tests.** Of the `.expected.json` companions, `scalar_basics` and `deep_hierarchy` are hand-authored ground truth; the others are the FFI snapshots of Layer 1. See `integration_test/PENDING.md` for what is still outstanding.

**Layer 3 — GTKWave reference comparison.** `tool/gtkwave_reference_compare.sh` uses GTKWave's `fst2vcd` to re-read each committed FST mirror and diffs the signal declarations (name + width) against the hand-crafted VCD, reporting value-change counts for information only. It runs as a non-blocking CI job on Linux, where GTKWave is installed.

**Layer 4 — Round-trip tests.** The VCD writer is validated by parse → export → re-parse on a known fixture (`test/services/vcd_writer/vcd_writer_service_test.dart`); the synthetic generator's output is checked for deterministic content.

**Layer 5 — Rendering golden tests.** Baselines live next to their tests (`test/features/viewer/rendering/goldens/`, `integration_test/stage/goldens/`); the `rebaseline-goldens.yml` workflow regenerates them when a visual change is intentional. Golden tests catch rendering bugs that value-level tests can't detect: wrong colour for x-values, missing transition edges, bus geometry, ruler tick alignment.

**Layer 6 — Protocol decoder fixture tests.** Each decoder is tested against its generated and captured fixtures, verifying start/end times, decoded field values, and error detection. `test/static/all_decoders_have_fixtures_test.dart` fails if a built-in decoder has no fixture.

**Layer 7 — Large-file performance benchmarks.** `perf.yml` builds `native/torture_gen`, generates large VCD/FST files, runs `test/perf/engine_bench.dart`, and compares the results with a stored baseline (`tool/perf/check_baseline.dart`). Weekly and on demand, never per push.

#### Fixture File Organization

```
test/fixtures/
├── vcd/            # Hand-crafted known-answer VCDs + .expected.json
├── fst/            # FST mirrors of the vcd/ fixtures (tool/generate_fst_mirrors.sh)
├── ghw/            # GHDL-generated GHW + .expected.json + .provenance.json
├── gtkw/           # GTKWave save files and translate filters (generated/, captured/)
├── legacy/         # LXT / LXT2 inputs for the convert-on-open path
├── protocol/       # apb, ahb_lite, axi4lite, i2c, riscv, spi, spi_flash, uart, wishbone
│   └── <protocol>/
│       ├── generated/   # tool/generate_*_fixtures.dart output + .expected_transactions.json
│       └── captured/    # simulated third-party RTL + helpers/ testbenches + PROVENANCE.md
├── real_world/     # attributed open-source traces, one .provenance.json each + README.md
└── analog/ cocotb/ decoder_plugins/ fsm/ riscv_formal/ rtl_source/ stage/ themes/
```

#### Generating FST and GHW Fixtures

FST and GHW are binary formats that cannot be hand-crafted:

- **FST from VCD:** `tool/generate_fst_mirrors.sh` converts the known-answer VCDs with GTKWave's `vcd2fst`. Run it when a VCD fixture changes.
- **GHW from VHDL:** `tool/ghw_fixtures/regen.sh` runs GHDL on a small VHDL testbench designed to produce known signal patterns.
- **Binary fixtures are committed.** Fixture files are small (KB to low MB), so CI runners need no simulators to run the tests; only the Layer 3 job installs GTKWave.

---

## 9. Design System

### 9.1 Design Principles

1. **Data density** — Engineers need to see many signals simultaneously. Maximize information density without clutter.
2. **Keyboard-first** — Every action reachable by keyboard. Mouse is for spatial operations (zoom, pan, select region).
3. **Dark mode default** — Engineers stare at waveforms for hours. The default theme is `crux-dark`; light and other presets are available.
4. **Consistent with engineering tools** — Color conventions from oscilloscopes and logic analyzers (green for data, yellow for clock, red for error/x). Don't reinvent conventions engineers already know.
5. **Responsive but desktop-first** — The primary layout is a multi-pane desktop view. Phone is a full-width canvas with drawer / sheet access to the panels (§3.1.2).

### 9.2 Design Tokens

- **Color palette:** Dark background (near-black), muted panel borders, high-contrast signal colors. Signal color defaults (`WavecruxColors`): green, cyan, yellow, magenta, orange, white. x-values in red hatching. z-values as a centered dashed line on 1-bit signals and a dashed outline plus midline on buses. Colors resolve through the named-token theme engine (`crux_theme`, §10).
- **Typography:** Monospace for signal values, names, and time displays — `WavecruxColors.monoFontFamily` (`JetBrainsMono`, falling back to `FiraCode`, `Courier New`, `monospace`). No font files are bundled, so the fallback applies unless the font is installed. System sans-serif for UI labels.
- **Spacing:** 4dp grid for dense panels. 8dp grid for settings/dialogs.
- **Elevation:** Minimal. Panel boundaries via subtle borders, not shadows.
- **Motion:** Minimal — smooth zoom transitions and cursor movement. No decorative animation.

---

## 10. Extension Points (Overlay Seams)

This open-core repo is also consumed by a closed-source Pro overlay that adds Pro and Enterprise features by overriding Riverpod providers and registering into open-core registries, not by forking code:

- `wavecrux` (this repo, Apache-2.0) ships the complete, standalone, fully functional waveform viewer: all core viewer features, built-in protocol decoders, built-in Stage widgets, debug tools.
- The Pro overlay consumes this repo as a Git submodule with a `path:` pubspec dependency and calls the same `bootstrap()` entry point with its own overrides (see *Override pattern* below).

Nothing in this repository depends on the overlay. The seams below exist so an overlay can plug in; each has an open-core default.

**Open-core extension-point interfaces:**

- `StageRegistry` (`lib/plugins/stage_registry.dart`) — Stage widget registration. `registerBuiltinStageWidgets()` registers the built-in primitives, the educational FPGA board widgets, the RISC-V Commit Inspector and Pipeline Diagram (§6.6), **and the Tachometer Rive reference widget** (the canonical worked example for the custom-widget SDK — see `lib/features/stage/widgets/tachometer/`). An overlay adds widgets through `extraStageWidgetsProvider`.
- **Stage widget SDK** (`lib/features/stage/sdk/`, `lib/features/stage/runtime/`, `lib/features/stage/bundle/`, `lib/features/stage/settings/`) — the open-core *capability* for authoring, packaging, installing, hot-reloading, and animating custom Stage widgets. Covers: manifest format (`stage_widget_manifest.dart`, YAML parser, validation errors, localized strings), normalization framework (`value_normalizer.dart`, normalizer chain, bit-field / boolean / enum / linear normalizers, raw signal sample, normalized value types), Rive-backed runtime (`RiveBackedAnimationController`, `RiveRuntimeStateMachineHost`, `community_rive_stage_renderer.dart` — which renders every installed Rive bundle — and `bundled_stage_asset_loader.dart`), the `.wcrux-widget` bundle reader / store / manager / provider (plus the writer the repository's tools use to author bundles; the app only reads them), and the Settings → Custom Widgets panel (`custom_widgets_panel.dart`). The capability to extend the system is free; curated widget *content* is what an overlay adds — the same pattern as protocol decoders.
- `StageWidget.maxSize` — optional getter on the `StageWidget` interface (`(double, double)?`, default `null` = unbounded). Declared for widgets to state an upper bound; the resize handles currently clamp only to `minSize` and do not read it.
- `StageWidgetSlot.pinBindings` — optional `Map<String, String>?` on `StageWidgetSlot`. When non-null, the slot represents a multi-pin peripheral whose child widget needs more than one signal binding to render (for example a display slot on a board that needs clock, data and sync pins). Keys are the child widget's pin names; values are sibling slot names whose `parentInstance.signalBindings[<sibling>]` entry holds the signal binding for that pin. The board scaffold reads each pin's binding from the named sibling slot and populates the child instance's `signalBindings` accordingly. Default `null` preserves the single-pin behavior (`slot.name` → primary pin via `childInputPinName`). Drag-to-bind on a multi-pin slot is disabled — users bind each pin via its sibling chip slot, which remains a standard single-pin slot with its own drop target.
- `StageWidget.requiredTier` — license tier required to instantiate the widget (defaults to `LicenseTier.openCore`). The picker dialog renders a `WaveCruxFeatureTierBadge` per row and gates activation on `betaPeriodProvider || currentTier.featureEquivalent >= requiredTier` — the same comparison `FeatureGate.isAvailable` makes, computed at the call site so a test can flip the beta flag through the provider.
- `StageWidget.configParams` + `StageWidget.configGroups` + `StageInstance.configuration` — schema-driven per-instance widget configuration. A widget declares a `List<ConfigParam>` (and optional `List<ConfigParamGroup>` for sectioning) describing its configurable knobs (numeric / bool / text / enum); the Stage bindings pane renders a generic editor that two-way binds the schema against the instance's `configuration` map (a `Map<String, Object?>` of scalar values, JSON-natural and forward-compatible). Default empty schemas mean built-in primitives are unaffected; a widget with a schema converts the map to a typed config inside the widget (e.g. `TachometerConfig.fromMap` / `toMap`). Widgets that need bespoke editing UI (palette tables, layout grids) supply a custom editor widget through their renderer instead and leave `configParams` empty.
- `SignalBinding.visibleWhenKey` / `visibleWhenValue` / `visibleWhenValues` + `SignalBinding.isVisibleIn` — **per-pin** conditional visibility, mirroring the `ConfigParam.visibleWhen*` / `isVisibleIn` contract exactly (discrete equality or set membership against the instance's `configuration` map; no comparisons, no cross-field logic). The Stage bindings pane filters its pin enumeration through it. A binding with no predicate is always visible, so every pre-existing widget enumerates exactly as it did — the additive guarantee is asserted directly in `test/features/stage/widgets/stage_bindings_pane_test.dart`. Exists because a widget whose pin count is itself configurable (the Pipeline Diagram's 2–8 stages × valid/pc/stall/flush) would otherwise show every pin permanently.
- `StageAutoBindService` + `StageWidget.supportsAutoBind` / `StageWidget.autoBindService` — the generic auto-bind seam (`lib/domain/interfaces/stage_auto_bind_service.dart`). Resolution lives in `stageAutoBindServiceFor` (`lib/services/stage/stage_auto_bind_resolver.dart`): an explicitly declared `autoBindService` wins; otherwise a `CompoundStageWidget` falls back to the shared `BoardAutoBindService`, so boards need **no** per-widget declaration. Two open-core implementations ship: `BoardAutoBindService` (whose `autoBind` is a thin adapter over `computeBindings`) and `RvfiDetectionService`. `BoardAutoBindPreviewDialog` renders any implementation's `BoardAutoBindCandidate` set and takes an optional `title` for non-board subjects.
- `RiscvIdentityTrackerRegistry` (`lib/services/riscv/riscv_instruction_identity.dart`) — pipeline instruction-identity tracking keyed by `RiscvIdentitySource`. Open core registers `pc` and `positional`; `tag` is **deliberately absent** (`create` returns `null`, `supports` returns `false`). An overlay installs a tag tracker with `RiscvIdentityTrackerRegistry.register(RiscvIdentitySource.tag, …)` — a plain static seam, called before `bootstrap()`. See §6.6.
- `DecoderRegistry` (`lib/plugins/decoder_registry.dart`) — protocol decoder registration. Open core registers SPI, I2C, UART, AXI4-Lite, APB, AHB-Lite, Wishbone, SPI Flash, and the RISC-V instruction-trace decoder (§6.7) in `bootstrap()`; an overlay adds decoders through `extraDecodersProvider`, and further `IsaTraceDecoder` subclasses directly.
- `isaDisassemblyRenderer` (`lib/services/decoders/isa/isa_trace_decoder.dart`) — a static hook an overlay sets before `bootstrap()` to post-process decoded instructions (e.g. alias rendering); open core leaves it `null` and renders exactly what the tables say (§6.7).
- **User-contributed decoder plugin loader** (`FfiDecoderLoader`) — desktop `dart:ffi` loader that scans decoder-plugin directories at startup — `WAVECRUX_DECODER_PATH` first, then the user-configured directories, then the per-user default under the app-support directory (`PluginDirectoryResolver`). Nothing is loaded until the user has acknowledged the plugin safety notice in Settings, and an organization policy file can restrict loading to an allowlist. Each library's ABI major version is checked against the C header at [`include/wavecrux_decoder.h`](../include/wavecrux_decoder.h), its JSON manifest is read, and each contributed decoder is registered into `DecoderRegistry.instance` alongside the built-ins. Per-plugin failure isolation is mandatory — a malformed manifest, ABI mismatch, missing symbol, or load failure must never break app startup. The loader feeds signal values into each plugin's `WcSample.bits_ptr` using the documented 4-state encoding (2 buffer bits per signal bit, low = level, high = unknown flag) and converts tick timestamps to femtoseconds via the file's `Timescale` so plugin authors get physical units. The reference demonstrator at [`examples/decoder-plugin-demo/`](../examples/decoder-plugin-demo/) (1-Wire bus) plus its Rust port at [`examples/decoder-plugin-demo-rust/`](../examples/decoder-plugin-demo-rust/) are the canonical templates plugin authors clone and adapt; round-trip integration test at `test/services/decoders/ffi/onewire_demo_integration_test.dart`. The authoring guide is in `CONTRIBUTING.md`. The loader and ABI are open core because a decoder plugin is the extension capability itself; curated decoder content is what an overlay adds.
- `LicenseTier` / `LicenseTierFeatures`, `kBetaPeriod` / `betaPeriodProvider`, `FeatureGate`, `licenseTierProvider`, `LicenseValidator` / `NoopLicenseValidator`, `LicenseBadgeStrings` / `LicenseBadgeStringsEn`, `FeatureTierBadge`, `EditionBadge` — license-tier gating primitives shipped by the cross-suite `package:crux_license/crux_license.dart` package (in [`crux-shared`](https://github.com/Ferrite-Engineering/crux-shared)). Open-core defaults: tier resolves to `LicenseTier.openCore`; `FeatureGate.isAvailable(required, current)` short-circuits to allow while `kBetaPeriod` is `true` and otherwise compares `current.featureEquivalent` against the required tier; badges render nothing for the open-core tier. WaveCrux ships a `WaveCruxLicenseBadgeStrings` adapter (`lib/core/license/wavecrux_license_badge_strings.dart`) bridging the package widgets to `L10N`, plus thin `WaveCruxFeatureTierBadge` / `WaveCruxEditionBadge` wrappers (`lib/shared/widgets/`) that construct the adapter from `BuildContext`. An overlay overrides `licenseTierProvider` with a value derived from a validated license, and `licenseResolvedProvider` (`lib/core/license/license_resolved_provider.dart`) with the future that completes once that tier is known. One-shot bootstrap steps that act on the tier, such as seeding the organization session template into a new tab, await it (bounded) so a cold start does not act on the Open Core tier every launch reads until the keychain answers; open core's constant tier resolves at once.
- **A restored item is gated where it runs** (`tierUnlockedProvider`, `lib/core/license/tier_unlocked_provider.dart`). The pickers gate *adding* a decoder, a Stage widget or a translator preset, but a session restore puts back whatever it saved, and an overlay registers its items at every tier, so a session saved during the beta (or edited by hand) names items the seat's tier may not include. Each consumer that would run such an item therefore asks the tier itself, live: `ActiveDecodersNotifier.decodeAll` runs a decoder only when its `DecoderDefinition.requiredTier` is met and re-runs the set when the licence changes; `StageInstanceTile` draws a locked body in place of the renderer (the custom registry's tier wins, as in the picker); `translatorRegistryProvider` registers a `TierGatedTranslator` only where its tier is met and otherwise records it with `TranslatorRegistry.withhold`, so the value column can show a lock beside the built-in fallback value. A withheld item stays in the session model, so the next save writes it back and an upgrade brings it back without a restart, and its surface says the upgrade dialog's own sentence through `WaveCruxWithheldNotice` (`lib/shared/widgets/wavecrux_withheld_notice.dart`).
- `TelemetryService` — anonymous usage statistics. The whole pipeline lives in the shared `crux_telemetry` package (`crux-shared/packages/crux_telemetry/`), and every implementation ships there in open core: `NoopTelemetryService`, `PendingTelemetryService` (buffers launch events while the stored consent is still loading), and `LiveTelemetryService` (append-only JSON-Lines queue + coalesced, batched HTTP POST to the ingestion endpoint). `telemetryServiceProvider` picks one from a gate that is closed for the whole beta (`kBetaPeriod`), then honours an organization telemetry policy (`deny` / `allow`) if one is present, and otherwise transmits only when the stored consent is `enabled` — an unanswered (`unset`) consent never transmits outside the developer flag. After the beta a first-launch disclosure asks for consent; its toggle is pre-set on, except in the EEA, the UK, Switzerland, and South Korea, where it is pre-set off (`telemetry_region.dart`). Inside an editor host the whole service is swapped for `HostRelayTelemetryService` (`lib/services/host_bridge/host_relay_telemetry_service.dart`). What stays in this repo is the event catalog (`lib/services/telemetry/telemetry_event_catalog.dart`), the instrumentation call sites, the `DeviceClass` → `form_factor` derivation (`lib/services/telemetry/telemetry_platform.dart`), the ARB strings, and the binding adapters under `lib/core/telemetry/` + `lib/features/telemetry/`.
- `CollaborationService` / `collaborationServiceProvider` (`lib/core/providers/collaboration_service_provider.dart`) — live shared sessions (an Enterprise feature of the overlay). Open core owns the interface (`lib/domain/interfaces/collaboration_service.dart`), the viewer-side bridge that mirrors cursor / viewport / marker state into and out of a session (`lib/services/collaboration/collab_viewer_bridge.dart`, started at boot), the session-state providers under `lib/features/collaboration/`, and the command-handler seam `collaborationCommandHandlerProvider`; the bound service defaults to `NoopCollaborationService`, which makes no network calls.
- `applicationEditionProvider(l10n)` (`lib/core/app_info/application_edition_provider.dart`) — family provider keyed by `L10N` returning the edition label. It derives the label from `licenseTierProvider` (`l10n.aboutEditionOpenCore` for open core; the proper nouns "EDU", "Pro", "Enterprise" otherwise), so an overlay that overrides the tier needs no override here.
- `applicationBuildInfoProvider` (`lib/core/app_info/application_build_info_provider.dart`) — async provider returning `ApplicationBuildInfo` (version string, build number, short git SHA, OS name, architecture, Flutter SDK version, Dart SDK version). Reads `PackageInfo.fromPlatform()` and falls back to the constants in `lib/core/app_info/build_info_fallback.dart` (`kBuildVersion`, `kBuildNumber`, `kBuildGitSha`, …). The About dialog awaits it before opening.
- `applicationBrandingProvider` (`lib/core/app_info/application_branding_provider.dart`) — synchronous provider returning `ApplicationBranding` (company name, logo asset path, square logo asset path, copyright year, website URL). Default value is the Ferrite Engineering branding committed under `assets/branding/`. Overridable for white-label deployments or tests.
- `TabDetachingDelegate` / `PanelPopOutDelegate` — the multi-window seam, defined in `crux_workspace` with `Noop*` defaults. See §6.4: it is unimplemented, and the "Move to New Window" affordance is disabled by `kMultiWindowAvailable = false`.
- `cruxColorThemeProvider` (from `package:crux_theme`) — the active `CruxColorTheme`. WaveCrux overrides this provider in `bootstrap()` via `wavecruxCruxColorThemeOverride` (defined in `lib/core/theme/wavecrux_color_theme_bootstrap.dart`) with a `CruxColorThemeNotifier` subclass that derives state from `appSettingsProvider` — preset lookup by `activeThemeName`, with `themeOverrides` layered on via `CruxColorTheme.mergeTokens`. Persistence lives in `AppSettings`. The notifier additionally overrides `activate(theme)` and `applyOverrides(map)` so the crux_theme widgets' preset-switch, token-edit, and token-reset flows write through to `AppSettings.activeThemeName` and `AppSettings.themeOverrides` (overrides derived as the diff between the active theme's tokens and the matching built-in preset's defaults). An overlay can layer additional overrides on top (later overrides win). At boot `registerWaveCruxThemeTokens()` (in `lib/core/theme/wavecrux_theme_tokens.dart`) registers WaveCrux's `canvas` token category plus its preset overlay, and calls `crux_theme`'s `registerCruxThemeChromeTokens()` for the suite-wide `chrome` category; the canvas reaches its resolved colors through the `WaveCruxThemeAccessors` extension on `CruxColorTheme` (e.g. `theme.canvasBackground`), and `app.dart` folds the chrome tokens into the Material theme with `crux_theme`'s `applyChromeTokens`.
- `pcapToVcdDialogOpenerProvider` (`lib/core/providers/pcap_to_vcd_dialog_opener_provider.dart`) — seam for mounting the Convert PCAP to VCD dialog (an Enterprise-tier action). The default opener is a no-op so `ShortcutAction.convertPcapToVcd` stays discoverable, badged, on desktop surfaces; an overlay overrides it with a callback that checks the tier and mounts the dialog.
- **Issue reporter** — the reporter (diagnostic-log ring buffer, category collection, screenshot capture, markdown report builder, and the pre-filled GitHub new-issue dialog `CruxIssueReporterDialog`) ships as the cross-suite `package:crux_issue_reporter/crux_issue_reporter.dart` package. WaveCrux binds it in `bootstrap()` through `wavecruxIssueReporterOverrides` (`lib/features/issue_reporter/wavecrux_issue_reporter_overrides.dart`): the `CruxIssueReporterConfig` (repository slug `Ferrite-Engineering/wavecrux`), the build info mapped onto `crux_app_info`'s `ApplicationBuildInfo` (adapter in `lib/core/app_info/crux_app_info_adapter.dart`), the structured diagnostics report (`cruxIssueDiagnosticsReportProvider`, reusing `AppDiagnosticsReportService`), and the privacy-scrubbed session snapshot (`cruxIssueSessionContextProvider`, built by `lib/features/issue_reporter/providers/wavecrux_issue_session_context.dart`). The localized dialog chrome comes from a `WavecruxIssueReporterStrings` adapter (`lib/core/issue_reporter/wavecrux_issue_reporter_strings.dart`) bound from `MaterialApp.builder`. `cruxIssueReporterDataProviderProvider` is the seam through which an overlay contributes an extra privacy-scrubbed report category; its open-core default (`NoopCruxIssueReporterDataProvider`) returns `[]`. The reporter is open to all tiers — `ShortcutAction.issueReporter` carries the default `requiredTier: LicenseTier.openCore` (no badge, no gate). Companions from the package: `cruxAppScreenshotBoundaryKeyProvider` (the `GlobalKey` on the root `RepaintBoundary` for Flutter-layer screenshot capture) and `CruxIssueReporterLogBuffer` (a 500-entry ring buffer attached to `package:logging` in `bootstrap()` before any provider is constructed).
- **CXP server + name resolver** (`WaveCruxCxpServer`, `WaveCruxNameResolver`, `cxpServerProvider`, `cxpPeersProvider`, `cxpEventLogProvider`, `cxpSelectionEmitterProvider`, `cxpLifecycleBridgeProvider`) — **open core, not an overlay feature.** CXP (Cross-Tool eXchange Protocol) is the peer cross-probe protocol that lets WaveCrux gossip selection events with other Crux-compatible tools and accept inbound `request_highlight` / `request_open_source` from them. The server, name resolver, lifecycle providers, selection emitter, and cross-probe panel all live here. Distinct from WCP (the external driver protocol): the two coexist on different ports (CXP defaults to 54322; WCP to 54321) with disjoint command surfaces. Inbound `request_highlight` reuses the same internal provider calls WCP's `add_items` / `set_cursor` / `focus_item` reach for (`signalGroupsProvider.addSignals`, `cursorStateProvider.placePrimary`, `selectedSignalProvider.select`) — one implementation, two front doors. `request_highlight` also carries the optional [CXP §9.9](https://edacrux.app/cxp#sec-9-9) **semantic stream coordinate** (`RequestHighlight.coordinate`), which `onHighlight` passes through to `dispatchCxpHighlight`: the element says what to open, the coordinate says where to land inside it. Also open core, also ungated — see §6.6.3.
- **Session per-tab extension payload** (`extraSessionPayloadCodecsProvider`, `SessionExtensionCodec`, `SessionExtensions`) — `lib/services/session/session_extension_codec.dart`. The seam for overlay per-tab state that needs to ride the `.wavecrux` session document. The registry maps a string namespace (e.g. `"pro.sva"`) to a codec with a `capture(Ref)` / `restore(Ref, payload)` pair. `SessionService` writes every registered codec's captured payload under a reserved top-level `extensions: Map<String, Object?>` field of the document (current document version: `_kCurrentVersion = 4`). **Preserve-unknown invariant:** namespaces present in a loaded document that have no codec registered on the current build round-trip through `SessionState.extensions` verbatim — the receiving build never reaches into the payload, but re-emits it on the next save. This is what lets an older build, or the open-core viewer, open a session written by a newer or overlay build without corrupting the overlay's payload. **Forward-compat policy:** newer schema versions (`version > _kCurrentVersion`) are read silently rather than surfacing a read-only banner — the codec seam exists precisely so a per-feature payload added in a future release does not need a UX surface to survive a round-trip.
- `AiModelClient` / `aiModelClientProvider` — bring-your-own-key model client for the AI Waveform Assistant. Interface + provider-neutral message models (`AiMessage`, `AiToolSpec`, `AiToolCall`, `AiRequest`, sealed `AiStreamEvent`) in `lib/domain/interfaces/ai_model_client.dart`; default `NoopAiModelClient` (`lib/services/ai/`) reports `AiUnavailableReason.notConfigured` as a typed terminal stream event — it never throws and `isConfigured` is `false`. WaveCrux runs no model; the user brings their own key. Open core ships this seam, the key store seam `aiKeyStoreProvider`, and the Settings → AI key-config UI written against it; it contains no concrete model client, which is supplied by overriding the provider. AI surfaces appear only when both switches are on: the `kAiExperimental` build flag (from `crux_license`; defaults to `true`, overridable with `--dart-define=AI_EXPERIMENTAL=false`) and the off-by-default user toggle in Settings → AI (`aiExperimentalEnabledProvider`).
- `AiToolRegistry` / `aiToolRegistryProvider` (+ `extraAiToolsProvider`, both in `lib/core/providers/ai_tool_registry_provider.dart`) — the function-calling surface presented to an `AiModelClient`. `lib/services/ai/ai_tool_registry.dart` keys `AiTool`s (a model-facing `AiToolSpec` paired with an async `(Ref, args) → AiToolResult` handler) by unique name; the provider composes the open-core viewer-navigation tools (`lib/services/ai/tools/viewer_navigation_tools.dart`: `searchSignal`, `getTransitionsInWindow`, `listDecodedTransactions`, `getSelectionContext`, `jumpCursor`, `addMarker`) with everything contributed through `extraAiToolsProvider`. Every tool is **grounded** — it reads the live waveform / cursor / decoder / selection providers and returns an `AiToolResult` whose `citations` are `AiCoordinate`s (`signalRef`, `signalPath`, `time`) the viewer can jump to; expected failures (no waveform, unknown signal, unknown tool) are returned as `AiToolResult.failure`, never thrown. `getSelectionContext` is the compact, deterministic structured-context extractor behind the "Explain Selection" action (`ShortcutAction.aiExplainSelection`), which is enabled only when a model is configured — so it stays disabled in a build with only the no-op client.
- `aiAdvisorPanelTogglerProvider` (`lib/core/providers/ai_advisor_panel_toggler_provider.dart`) — seam through which a Pro-tier AI assistant panel is toggled. Mirrors `svaPanelTogglerProvider`: `ShortcutAction.aiAdvisorTogglePanel` (declared `requiredTier: LicenseTier.pro`, `isVisible` gated on the AI switches above, in the Tools menu group) dispatches through `ref.read(aiAdvisorPanelTogglerProvider)(context)`; the open-core default is a no-op. An overlay mounts the panel itself through `extraBottomDockTabsProvider`.

**Other overlay seams**, each with a no-op or empty default:

| Seam | Where | Purpose |
|---|---|---|
| `extraOverrides` / `extraTabOverrides` | `bootstrap()` in `lib/app.dart` | Root-scope and per-tab provider overrides |
| `extraDecodersProvider`, `extraStageWidgetsProvider`, `customStageWidgetRegistryProvider` | `lib/plugins/` | Decoders and Stage widgets |
| `extraTranslatorsProvider`, `extraTranslatorPresetsProvider` | `lib/plugins/` | Value translators and translate-filter presets |
| `extraTimelineOverlaysProvider` | `lib/plugins/` | Canvas timeline overlay layers |
| `extraBottomDockTabsProvider` | `lib/plugins/` | Bottom-dock tabs (§6.5) |
| `transactionTableExportersProvider` | `lib/plugins/` | Transaction-table export formats |
| `extraLocalizationsDelegatesProvider` | `lib/plugins/` | Additional localization delegates |
| `eagerStartupProvidersProvider` | `lib/plugins/` | Side-effecting providers realized at startup |
| `extraSettingsCategoriesProvider` | `lib/features/settings/providers/` | Settings categories |
| `statusBarTrailingWidgetsProvider` | `lib/core/providers/` | Status-bar trailing chrome |
| `debugAdvisorServiceProvider`, `debugAdvisorPanelOpenerProvider` | `lib/core/providers/` | Debug-advisor service and panel |
| `svaResultsLoaderProvider`, `svaPanelTogglerProvider` | `lib/core/providers/` | Assertion-results loading and panel |
| `tierGatedActionsAvailableProvider` | `lib/core/providers/` | Whether tier-gated actions are executable on this host (§3.1.6) |
| `stageConfigLabelResolverFactoryProvider` | `lib/features/stage/providers/` | Localized labels for overlay widgets' config params |

Shared-package seams (`telemetryPolicyProvider`, `updatePolicyProvider`, `cruxSecretStoreProvider`, the `crux_workspace` delegate providers) are documented in their `crux-shared` packages.

**Override pattern (open-core entry point):**

```dart
// lib/app.dart
Future<void> bootstrap({
  List<String> args = const [],
  List<Override> extraOverrides = const [],
  List<Override> extraTabOverrides = const [],
}) async {
  // ... CLI parsing, decoder / Stage / ISA registration ...
  final rootContainer = ProviderContainer(
    overrides: [
      // open-core initial-file / session / streaming / theme / reporter overrides ...
      ...extraOverrides, // an overlay's root overrides come last and win
    ],
  );
  // extraTabOverrides are appended to every per-tab container by TabContainerManager.
  runApp(
    UncontrolledProviderScope(
      container: rootContainer,
      child: const WaveCruxApp(),
    ),
  );
}
```

An overlay's `lib/main.dart` installs any static registrations (e.g. `RiscvIdentityTrackerRegistry.register`, `isaDisassemblyRenderer`) and then calls `runWaveCrux(args: args, extraOverrides: …, extraTabOverrides: …, linuxDesktopApp: …)`, which runs `bootstrap` and exits the process after a headless invocation such as `--help` (a desktop runner would otherwise keep its window and event loop alive). Conflict semantics: open-core overrides come first; overlay overrides come last; later overrides win.

**Rule: open-core extension point first.** If an overlay feature needs to plug in somewhere that open core does not yet have a hook, the *first* change is to this repo to add the extension-point interface, registry, and default implementation. Only after that lands does the overlay implementation go in. Forking open-core widgets or services into the overlay to "patch them" is not allowed — it breaks the open-core / overlay contract and leads to divergence.

The user-facing account of tiers and licensing is at `https://edacrux.app/licensing`, and of usage statistics at `https://edacrux.app/telemetry`.

---

## 12. Glossary

| Term | Definition |
|------|------------|
| **VCD** | Value Change Dump — IEEE Std 1800-2023 standard format for recording signal value changes from simulation. ASCII-based, universally supported, but large and slow. |
| **FST** | Fast Signal Trace — binary format created by GTKWave for fast random access and compact storage. Used by Icarus Verilog and Verilator. |
| **GHW** | GHDL Waveform — nine-state waveform format native to the GHDL VHDL simulator. |
| **LXT** | The original 2003 streaming compressed waveform format authored by Tony Bybell (also the original author of GTKWave). Predates FST. Read-only in WaveCrux via the convert-on-open path (§2.2.1). The clean-room `lxt2fst` crate decodes both the LXT structure (names, geometry, timescale) and its *streaming* value-change codec (`src/lxt_value_decode.rs`), so `.lxt` files convert to FST with their real per-facility transitions — to the same bar as its sibling **LXT2**. The codec was reverse-engineered differentially against GTKWave's `vcd2lxt` encoder (`lxt_read.c` GPLv2 never consulted) and is strict (an unvalidated stream falls back to `x`-state rather than guessing). LXT-classic captures are rarer than LXT2 in the field, but both legacy readers now decode values. |
| **LXT2** | The 2005 block-indexed evolution of LXT (also by Tony Bybell) — per-block compression and a block-index header that gives `(blocks_done, total_blocks)` progress essentially for free. The dominant pre-FST GTKWave capture format. Read-only in WaveCrux via the convert-on-open path (§2.2.1) implemented in the `lxt2fst` crate. |
| **lxt2fst** | Clean-room Rust crate at `native/lxt2fst/` that converts `.lxt` and `.lxt2` captures to FST at file-open time . Apache-2.0, no GPL ancestry: GTKWave's `lxt_read.c` / `lxt2_read.c` were not consulted. Reader and writer modules are deliberately separable so the LXT2 reader can graduate into a wellen contribution and routing can switch to native, in which case the writer scaffolding is retired. C-ABI surface (`lxt2fst_convert`, `lxt2fst_detect_format`, `lxt2fst_last_error_message`, `lxt2fst_abi_version`) for desktop/mobile, exported from the `wellen_ffi` library that links the crate; wasm-bindgen surface (`lxt2fstConvert`, `lxt2fstDetectFormat`, `lxt2fstAbiVersion`) for web. WASM bundle gated at ≤ 400 KiB gzipped by `test/native/lxt2fst_wasm_bundle_size_test.dart`. |
| **convert-on-open** | The strategy for legacy formats: at file-open time, magic-byte detection routes `.lxt` / `.lxt2` through the `lxt2fst` crate into a sibling-of-source (or app-cache fallback) `.fst`, which is then loaded by wellen exactly like any other FST. Conversion runs once and the result is reused on subsequent opens via the `Lxt2FstCache` mtime+size freshness check. The rest of the application (canvas, decoders, Stage, export, value queries) sees only FST and the legacy formats stay confined to a small, frozen, replaceable seam. Distinct from in-pipeline parsing — wellen never sees the legacy bytes. |
| **FSDB** | Fast Signal Database — Synopsys proprietary binary format. WaveCrux cannot read it natively; on desktop, `FsdbConversionService` converts an opened `.fsdb` through the user's own `fsdb2vcd` and `vcd2fst` tools and caches the FST next to it (§2.2). |
| **wellen** | Rust crate providing a unified interface for reading VCD, FST, and GHW files. Created by Kevin Laeufer. Used by the Surfer waveform viewer. |
| **WellenWasmProvider** | `WaveformDataSource` implementation backing the Flutter Web build. Wraps the `wellen` crate compiled to WebAssembly via `dart:js_interop`. Method-for-method parallel to `WellenProvider` (FFI). Lives in `lib/services/waveform/wellen_wasm_provider_web.dart`; the conditional-export shim at `wellen_wasm_provider.dart` re-exports it on web and a stub that throws `UnsupportedError` on other hosts. |
| **wasm-bindgen** | Rust + JS toolchain that generates the JS glue and `.d.ts` types around a wasm32 `cdylib` so a Rust struct (here, `WellenWasm` in `native/wellen_wasm/`) becomes a callable JS class. WaveCrux pins the version transitively through wasm-pack. |
| **wasm-pack** | Build orchestrator that drives `cargo build --target wasm32-unknown-unknown` plus wasm-bindgen post-processing. Invoked from `tool/build_web_wasm.dart` (wellen) and `tool/build_lxt2fst_wasm.dart` (legacy converter); CI rebuilds both and gates their gzipped bundle sizes. |
| **Timescale** | The time unit and magnitude that defines one tick of simulation time (e.g., 1 ns, 10 ps). |
| **Identifier Code** | Short ASCII string used in VCD files to reference a signal in value change lines. |
| **Translate Filter** | A GTKWave feature that maps raw signal values to human-readable labels via external text files or programs. |
| **SST** | Signal Search Tree — the hierarchical signal browser panel (GTKWave terminology). |
| **WCP** | Waveform Control Protocol — an open JSON-based remote control protocol for waveform viewers, originally authored by the Surfer project. The upstream specification is the `surfer-wcp` crate (`surfer-wcp/src/proto.rs`) in the `surfer-project/surfer` repository, pinned at commit `4281e79afec3fed8759aa45ade689a181aaad533`; protocol version `"0"`. WaveCrux implements the spec envelope natively (default port 54321 — the WCP spec default, matching `AppSettings.remoteControlPort`, `WcpServer.defaultPort`, and the `wavecrux_ctl` client; null-byte message framing; version-checked greeting handshake; id-less commands with top-level parameters; in-order replies via a per-connection serial dispatch queue; command-echo responses; `DisplayedItemRef` stable IDs; async `waveforms_loaded` events) so that any WCP-compatible tool or script works with WaveCrux unchanged, including the deprecated spec commands `add_variables` / `add_scope` (dispatched as `add_items`). WaveCrux's original id-framed envelope (integer `id` per command, parameters nested under `data`, id-echo responses) is retained as a compat dialect behind `WcpServer.idDialectEnabled` (default on) — `wavecrux_ctl` uses it; a command frame carrying an integer `id` selects the dialect, an id-less frame selects the spec envelope. WaveCrux also exposes viewer-specific extension commands (`wavecrux.getValueAt`, `wavecrux.getHierarchy`, `wavecrux.getState`, `wavecrux.setActiveTab`) announced in the greeting; WCP-native clients ignore them. `wavecrux.setActiveTab` accepts a required `tab_id` and an optional `pane_id`, letting external tools target a specific tab (and assert its hosting pane) under the split-pane workspace model. The server's lifecycle is owned by `wcpLifecycleBridgeProvider` (`services/remote/remote_control_notifier.dart`), the WCP counterpart to `cxpLifecycleBridgeProvider`: it mirrors `AppSettings.remoteControlEnabled` / `remoteControlPort` into start / stop / rebind, so a launch with remote control already enabled comes up listening and a port edit rebinds the live server. `_WaveCruxAppState.initState` (`lib/app.dart`) reads it once on every non-web platform, mobile included. The settings-screen switch only writes the setting — it must never call `startServer` itself, or it races the bridge for the port. |
| **Stage** | WaveCrux's animated signal visualization system where physical-world widgets are bound to signals. |
| **Stage widget SDK** | Open-core capability (`lib/features/stage/sdk/`, `runtime/`, `bundle/`, `settings/`) for authoring, packaging, installing, hot-reloading, and animating custom Rive-backed Stage widgets. Free for anyone to use — mirrors the protocol-decoder plugin pattern. The Tachometer reference widget under `lib/features/stage/widgets/tachometer/` is the canonical worked example. Curated widget content is what an overlay adds. |
| **Tachometer** | The open-core Rive reference widget that demonstrates the full Stage widget SDK pipeline (manifest → normalizer chain → Rive state-machine inputs → rendered gauge). `requiredTier: LicenseTier.openCore`. Its artboard is `assets/stage/widgets/rive/runtime/tachometer.riv`. The renderer's widget tests are skipped under headless `flutter test` because the `rive_native` library cannot load there; the rendered widget is covered by the tests and goldens under `integration_test/stage/`. |
| **`.wcrux-widget`** | Zip-style bundle format for distributing custom Stage widgets. Contains `manifest.yaml` (signal bindings, normalizer chain, runtime asset path) plus the `.riv` runtime asset and any auxiliary files. The open-core `WidgetBundleReader` / `WidgetBundleWriter` round-trip the format; `CustomWidgetBundleManager` watches directories and hot-reloads on file change. |
| **Scope** | A hierarchical container for signals in a VCD file (module, task, function, begin, fork). |
| **Protocol Decoder** | A plugin that interprets raw bus signals as higher-level transactions (e.g., SPI frame, I2C transfer, AXI burst). |
| **X-Trace** | Debug technique of walking backward through signal transitions to find where an unknown (X) value originated. |
| **`.gtkw`** | GTKWave's save file format. Line-oriented ASCII text containing signal lists, display flags, groups, colors, zoom factor, and markers. WaveCrux imports this format for GTKWave migration. |
| **`panes`** | Flutter package providing IDE-like resizable panel layouts (`IdeLayout`) with programmatic control and keyboard-accessible resizers. WaveCrux uses it only indirectly, through `CruxIdeLayout` in `crux_ide_layout` (§2.4). |
| **Command Palette** | A VS Code-style overlay (Ctrl+Shift+P; Cmd+Shift+P on macOS) for searching and executing actions by name. It lists every `ShortcutAction` that is visible and enabled for the palette surface (§3.1.6), with its keyboard shortcut. |
| **CJK** | Chinese, Japanese, Korean — the three East Asian language families requiring special rendering support (line breaking, font fallback, vertical text). WaveCrux ships with zh-CN, ja, and ko translations at first release. |
| **Diagnostics Report** | Structured plain-text snapshot of diagnostics data. Two variants: a **Tab Diagnostics Report** (one tab's file stats, signal health, and "Benchmark This File" result) and a **Full Diagnostics Report** (app-level memory + frame stats + per-tab breakdown + active pane render stats). Both are designed for clipboard copy and GitHub issue pasting. |
| **Tab Diagnostics** | Per-tab non-modal drawer following the active tab and exposing File Info, Signal Health, and Benchmark This File. See §8.8. |
| **App Diagnostics** | Process-wide modal dialog showing Memory, a per-tab breakdown, Frame Stats, and Logs. Hosts "Copy Full Diagnostics Report". See §8.8. |
| **Pane Render Stats** | Per-pane popover anchored to an `i`-icon in each pane's tab bar. Shows total paint time and its breakdown, transitions, line segments, and canvas size. With split-pane there is one popover per pane. See §8.8. |
| **Statistics Strip** | Collapsible real-time performance monitoring region between the `CruxIdeLayout` and the status bar, one per pane. Shows curated metrics (paint time sparkline, FPS, memory, decompressed signals) from existing providers. Desktop only. Toggled via the disclosure on the strip itself, as in every other product in the suite. Distinct from the diagnostics surfaces: "statistics" = passive ambient monitoring; "diagnostics" = active troubleshooting actions. |
| **LiveStatisticsStrip** | `ConsumerWidget` that supplies WaveCrux's readings to the shared `CruxStatsStrip` (`crux_stats_strip`, itself the extraction of this strip). Consumes `cruxMemoryStatsProvider`, `cruxFrameStatsProvider`, the per-tab `memoryStatsProvider`, and its pane's `paneRenderStatsProvider`. Gated behind `deviceClassProvider == DeviceClass.desktop`. Expansion controlled by `statisticsStripVisible` in `PanelLayoutState`. |
| **Desktop Menu Bar** | `CruxDesktopMenuBar` (`crux_menu_bar`) providing categorized access to user-facing `ShortcutAction` values: the system `PlatformMenuBar` on macOS, an in-window menu bar on Windows and Linux, none on web or mobile. The browsable middle tier between toolbar icons and the command palette. See §3.1.6. |
| **Action Category** | Enum (from `crux_shortcut_action`, re-exported by `lib/core/shortcuts/action_category.dart`) grouping `ShortcutAction` values into browsable categories: app, file, edit, view, navigate, search, tools, help. Shared by the desktop menu bar, the toolbar overflow menu, and the command palette. |
| **Toolbar Overflow Menu** | `CruxToolbarOverflowMenu` — the toolbar's overflow button, shown on every device class whenever the toolbar strip does not fit: a bottom sheet on phone, a popup menu elsewhere. Items come from the same `ShortcutAction` registry as the menu bar. See §3.1.6. |
| **Signal Integrity Check** | Automated analysis of loaded waveform data for common simulation problems: constant signals, undriven (X/Z-only) signals, glitches, clock detection. |
| **RenderStatsCollector** | Instrumentation class embedded in `WaveformCanvasRenderObject.paint()` that counts visible signals, transitions, line segments, and times each paint phase per frame. |
| **Device Class** | Classification of the current display into `phone` (< 600 dp wide), `phoneLandscape` (≥ 600 dp wide but < 500 dp tall), `tablet` (600–1200 dp), or `desktop` (≥ 1200 dp), from width *and* height via `deviceClassProvider`. On a native desktop host the class is always `desktop` regardless of window size (§3.1.1). Determines layout strategy and feature surface (Stage playback, diagnostics, statistics strip). |
| **DisplaySizeFeed** | Widget mounted once at the app root (inside `MaterialApp.builder`) that pushes `MediaQuery.sizeOf` into `displaySizeProvider` on every size change, so `deviceClassProvider` always has an accurate size to classify. `ViewerScreen` consumes the resulting class to adapt the layout (§3.1.2, §3.1.8.6). |
| **MobileMemoryGuardService** | Stateless service holding the mobile memory thresholds and unload policy — file-size warning limits and RSS warning / critical levels per device class. `MobileMemoryGuardNotifier` does the work: it polls RSS, unloads idle signals under pressure, and handles Flutter's `didHaveMemoryPressure` callback (§3.1.5). |
| **License tier** | `LicenseTier` (from `crux_license`): `openCore`, `edu`, `pro`, `enterprise`. This repository is the open-core build; the other tiers are unlocked in the overlay build by a validated license. `edu` is feature-equivalent to `pro` (see `featureEquivalent`). |
| **License Key / Licence File** | The two credential formats `crux_license` verifies locally against an embedded public key, with no network call: a key `key/<base64(JSON)>.<base64(Ed25519 signature)>` that carries a policy id resolved through a table compiled into the app (no tier, entitlements, email or seat count), and a `-----BEGIN LICENSE FILE-----` file that embeds the whole licence object and so resolves with no table and works offline. |
| **Feature-Tier Badge** | Small colored chip ("PRO" or "ENT") displayed next to **features** that require a paid license — it says *"this feature requires PRO"*. Open Core features have no badge, and EDU is not a feature-required tier (it collapses to `SizedBox.shrink()`). It takes its tier as a constructor argument, because the tier is a property of the feature, not of the user. Canonical home: `package:crux_license/crux_license.dart` `FeatureTierBadge`. WaveCrux uses the `WaveCruxFeatureTierBadge` wrapper in `lib/shared/widgets/wavecrux_feature_tier_badge.dart`, which supplies a `WaveCruxLicenseBadgeStrings` adapter built from `L10N.of(context)`. |
| **Edition Badge** | Small colored chip ("EDU", "PRO" or "ENT") stating the edition the user is **running** — it says *"you are running PRO"* — on user-status surfaces such as the About dialog and the window status bar. Renders **nothing** at Open Core, which is what makes it safe to mount unconditionally in shared chrome. Distinct from the feature-tier badge: that one labels a feature by the tier it needs, this one labels the licence in force. It reads `licenseTierProvider` itself rather than taking a tier, because a statement about what the user owns has exactly one correct source. EDU keeps its own colour: it carries non-commercial terms and an annual renewal, and that is worth a visual difference. Canonical home: `package:crux_license/crux_license.dart` `EditionBadge`. WaveCrux uses the `WaveCruxEditionBadge` wrapper in `lib/shared/widgets/wavecrux_edition_badge.dart`. |
| **Feature Gate** | Runtime check that determines whether a gated feature is accessible: `FeatureGate.isAvailable(required, current)`. During the beta (`kBetaPeriod`), all gates are open. Otherwise it compares `current.featureEquivalent.index >= required.index`, so EDU satisfies any Pro-tier gate. Canonical home: `package:crux_license/crux_license.dart` `FeatureGate`. |
| **`kBetaPeriod`** | Build-time `const bool` (`bool.fromEnvironment('BETA_PERIOD', defaultValue: true)`) indicating the public-beta period, during which `FeatureGate.isAvailable` short-circuits to `true` regardless of tier and telemetry is inert. Lives in `package:crux_license/crux_license.dart` and is consumed across every Crux product; `betaPeriodProvider` exposes it as a Riverpod provider so tests can flip it without a rebuild. A build can override it with `--dart-define=BETA_PERIOD=false`. |
| **`LicenseBadgeStrings`** | Abstract caller-supplied strings interface from `package:crux_license/crux_license.dart` consumed by the package's `FeatureTierBadge` and `EditionBadge` widgets. Products ship a subclass backed by their `AppLocalizations`. `LicenseBadgeStringsEn` provides English defaults for prototypes/tests. |
| **`WaveCruxLicenseBadgeStrings`** | WaveCrux's adapter (`lib/core/license/wavecrux_license_badge_strings.dart`) that satisfies the package's `LicenseBadgeStrings` interface from the wavecrux `L10N` ARB output, using the `tierBadgePro` / `tierBadgeProSemantic` / `tierBadgeEnterprise` / `tierBadgeEnterpriseSemantic` / `tierBadgeEdu` / `tierBadgeEduSemantic` keys in every ARB file. |
| **`WaveCruxFeatureTierBadge` / `WaveCruxEditionBadge`** | Thin Stateless wrappers in `lib/shared/widgets/` that delegate to the cross-suite `FeatureTierBadge` / `EditionBadge` widgets, supplying a `WaveCruxLicenseBadgeStrings` adapter built from `L10N.of(context)` so call sites never have to construct the adapter themselves. |
| **`featureEquivalent`** | Extension getter on `LicenseTier` (from `package:crux_license/crux_license.dart`) that maps a tier to the Pro/Enterprise tier whose feature set it unlocks. EDU returns Pro because EDU users have full Pro feature access; the EDU distinction is in licensing terms, not feature access. Other tiers map to themselves. Used by `FeatureGate.isAvailable`. |
| **Collaborative Viewing** | Live shared waveform session with synchronized cursors — an Enterprise feature of the overlay. Open core owns the `CollaborationService` seam, the viewer-side bridge, and the session-state providers (§10); the bound service defaults to a no-op. |
| **Version Manifest** | JSON update manifest at `https://updates.wavecrux.app/manifest.json` (`lib/core/updates/wavecrux_update_config.dart`) read by `crux_updates` for the in-app update check; its `server_time` also anchors the beta-expiry clock against device-clock rollback. An organization policy file can point the check at an internal server. |
| **Keygen** | Third-party licensing service whose key and licence-file formats `crux_license` implements (`keygen_client`, `keygen_issuer`). |
| **TelemetryService** | Extension point interface for anonymous usage statistics, from `crux_telemetry`. `NoopTelemetryService` does nothing; `PendingTelemetryService` buffers while the stored consent loads; `LiveTelemetryService` queues, coalesces, batches, and transmits events. All are open-core; the active one is chosen by `telemetryServiceProvider` from the beta gate, any organization policy, and the stored consent (§10). WaveCrux supplies the config, storage, strings, `form_factor` and locale seams, and owns the event catalog. |
| **Telemetry Event** | Lightweight data class representing a single feature-usage signal (e.g., `decoder.opened`). Contains event name, timestamp, and optional properties. Never contains file names, signal names, or PII. |
| **TabId** | UUID wrapper from [`crux_workspace`](https://github.com/Ferrite-Engineering/crux-shared) (re-exported through `lib/domain/models/tab_id.dart` for compat) that uniquely identifies a WaveCrux tab. Keys the tab's `ProviderContainer`, serves as the drag-reorder handle, and persists in the workspace. Equality and hash are value-based. |
| **PaneId** | UUID wrapper from [`crux_workspace`](https://github.com/Ferrite-Engineering/crux-shared) (re-exported through `lib/domain/models/pane_id.dart`) uniquely identifying a pane. Each `WorkspaceTab` belongs to exactly one pane via `paneId`. `PaneId.primary` is a fixed sentinel that is never persisted; a fresh workspace's pane gets a generated id. |
| **WavecruxTab** | Live per-tab view model derived from the workspace by `tabListProvider`: `id` (TabId), `displayName`, `filePath`, `sessionFilePath`, `isDetached`, `paneId`. Immutable with `copyWith`. Emptiness is a workspace state, not a tab kind. `WorkspaceTab<WaveCruxTabPayload>` is the persisted form stored in `workspace.json`. |
| **Workspace** | WaveCrux-flavored typedef `Workspace = crux.Workspace<WaveCruxTabPayload>` from the [`crux_workspace`](https://github.com/Ferrite-Engineering/crux-shared) package: ordered list of `WorkspaceTab`s, list of `WorkspacePane`s (one or two), `activePaneId`, schema `version`, and a free-form `extras` map for per-product top-level flags. Persisted to `{appSupportDir}/workspace.json` automatically; named workspaces export as `.wavecrux-workspace`. Replaces the per-tab `.wavecrux` working-file model — `.wavecrux` is now an export format only. |
| **WorkspaceTab** | WaveCrux-flavored typedef `WorkspaceTab = crux.WorkspaceTab<WaveCruxTabPayload>` from [`crux_workspace`](https://github.com/Ferrite-Engineering/crux-shared). Framework fields: `id` (TabId), `displayName`, `paneId`, plus a typed `payload`. Convenience getters `tab.filePath` / `tab.sessionFilePath` / `tab.sessionExportPath` / `tab.isDetached` / `tab.isPlaceholder` (via the `WaveCruxWorkspaceTabAccessors` extension in `lib/domain/models/workspace.dart`) read from the payload. New construction uses `buildWorkspaceTab(...)` for ergonomics. |
| **WaveCruxTabPayload** | Per-tab payload type WaveCrux supplies to `WorkspaceTab<P>`: `filePath`, `sessionFilePath`, `sessionExportPath`, `isDetached` — the slice of per-tab state that lives directly in `workspace.json`. Heavyweight per-tab state (cursors, signal groups, markers, decoder config, Stage config, panel layout) stays in its per-tab Riverpod providers and persists in the per-tab session sidecar; the payload is the framework-visible summary needed to re-bind the file on restore. Defined in `lib/domain/models/wavecrux_tab_payload.dart`. |
| **WaveCruxWorkspaceCodec** | WaveCrux-specific implementation of [`crux_workspace`](https://github.com/Ferrite-Engineering/crux-shared)'s `WorkspaceCodec<P>` interface. Defined in `lib/services/workspace/wavecrux_workspace_codec.dart`. Round-trips `WaveCruxTabPayload` through the workspace document; tolerates wrong-typed values and missing optional fields, silently ignores unknown keys for forward compatibility, and falls back to `Workspace.empty()` inside the package service on schema-version mismatches. |
| **WorkspacePane** | Workspace-level pane descriptor `crux.WorkspacePane` from [`crux_workspace`](https://github.com/Ferrite-Engineering/crux-shared) (re-exported through `lib/domain/models/workspace.dart`): `id` (PaneId), `activeTabId?`. The workspace currently allows one or two panes. |
| **WorkspaceService** | WaveCrux-flavored typedef `WorkspaceService = crux.WorkspaceService<WaveCruxTabPayload>` from [`crux_workspace`](https://github.com/Ferrite-Engineering/crux-shared). Provides atomic-write persistence (`load()` / `save(ws)` / `saveToPath(path, ws)` / `loadFromPath(path)` / `clear()`), per-tab sidecar resolution (`sidecarPathFor(tabId, extension: '.wavecrux')` / `deleteSidecar`), and a `codec` getter exposing the active `WaveCruxWorkspaceCodec`. Failure modes (missing file, corrupt JSON, schema-version mismatch, invariant violation) silently fall back to `Workspace.empty()` so the app never crashes on a malformed document. Debounced auto-save lives in `WorkspaceNotifier`, and `LastSessionMigration` (`lib/services/workspace/last_session_migration.dart`) imports a legacy `last_session.json` on first launch. |
| **`.wavecrux-workspace`** | Named workspace file produced by "Save Workspace As…". Captures the complete multi-tab + multi-pane arrangement for sharing or version control. Distinct from the auto-managed `workspace.json` (which lives in app support dir and is implicit). |
| **`.wavecrux`** | Single-tab session export format. Used by "Export Tab as Session…" to share one debug session with a colleague. It was once the working session file; now it is an export format only. |
| **Empty-canvas state** | The app's state when no tabs are open. Rendered by `WaveCruxEmptyCanvas` (`lib/features/workspace/widgets/wavecrux_empty_canvas.dart`), which composes WaveCrux content (recent files, recent workspaces, other tabs from the last session on phone, the web drop-zone, and "Open File…" / "Open Sample" / "Open Workspace…" buttons — there is intentionally no "New Tab" button, since a blank tab is a dead-end) into the package `crux.EmptyCanvasState` shell (`useCard: false`). Toolbar, status bar, menu bar, command palette, and Settings are all reachable from this state. |
| **PaneHost** | The package `crux.PaneHost<WaveCruxTabPayload>`, consumed via the `WaveCruxPaneHost` adapter as the screen body below the toolbar; hosts one or two panes side by side. Each pane has its own `ViewerTabBar`, lazily-mounting stack (`LazyIndexedStack`), and per-pane `ProviderContainer`. Split-pane is widget-tree composition inside one `FlutterView`; it is independent of multi-window. See §6.5. |
| **Per-tab ProviderScope** | Each open tab hosts its own `ProviderContainer` parented to the root container, with the overrides from `wavecruxTabOverrides` (plus any overlay `extraTabOverrides`), wrapped in `UncontrolledProviderScope`. Tab-local providers (waveform source, cursor, zoom, signal groups, panel layout, Stage config) resolve from the tab container; global providers (settings, license, theme, device class, workspace) resolve from the root via Riverpod's parent lookup. Containers are owned by `TabContainerManager` and survive tab switches, so state is preserved without re-loading files. See §6.4. |
| **Per-pane ProviderScope** | Each pane hosts its own `ProviderContainer` carrying `paneIdProvider`, `paneRenderStatsProvider`, and `renderStatsCollectorProvider`. With split-pane there are two such containers, both parented to the root. |
| **TabContainerManager** | Creates, caches, and disposes per-tab `ProviderContainer`s. WaveCrux's `TabContainerManager` (`lib/services/tabs/tab_container_manager.dart`) is a thin wrapper that delegates to `crux_workspace`'s manager, supplying `wavecruxTabOverrides` plus any `extraTabOverrides` and arming the per-tab session autosave; `PaneContainerManager` (`lib/services/panes/pane_container_manager.dart`) does the same for per-pane containers. |
| **kMultiWindowAvailable** | Compile-time `const bool` in `crux_workspace` (currently `false`; re-exported from `lib/core/constants.dart`) that gates multi-window affordances: the "Move to New Window" tab context menu item renders disabled while it is false. No multi-window delegate implementation exists yet (§6.4). Independent of split-pane. |
| **TabDetachingDelegate** | Abstract class in `crux_workspace` defining `detachTab(TabId, ProviderContainer)` and `reattachTab(TabId)`, with `NoopTabDetachingDelegate` as the default. Intended to move a tab's container into a new `FlutterView` once Flutter multi-window is stable; not implemented. |
| **PanelPopOutDelegate** | Parallel abstract class in `crux_workspace` for detaching individual panels into secondary windows (`popOutPanel(panelId, ProviderContainer)`), with `NoopPanelPopOutDelegate` as the default. Not implemented. |
| **`crux-shared`** | Cross-suite shared infrastructure Melos workspace at [`Ferrite-Engineering/crux-shared`](https://github.com/Ferrite-Engineering/crux-shared). Apache 2.0. Holds the Dart packages the Crux products share — every `crux_*` dependency in `pubspec.yaml` comes from it. Held as a Git submodule at this repo's `./crux-shared/`; consumed via `path:` deps in `pubspec.yaml`. |
| **`crux_file_watcher`** | Cross-suite package in [`crux-shared`](https://github.com/Ferrite-Engineering/crux-shared) hosting the `FileWatcherService`, `FileWatchEvent` enum, and `WatchFactory` typedef. The consumer (`file_watcher_provider.dart`) imports via `package:crux_file_watcher/crux_file_watcher.dart`. |
| **`crux_license`** | Cross-suite Flutter package in [`crux-shared`](https://github.com/Ferrite-Engineering/crux-shared) carrying the suite-wide license vocabulary: `LicenseTier` + `LicenseTierFeatures` extension (`openCore` / `edu` / `pro` / `enterprise` with the EDU-as-Pro-feature-equivalent mapping), `kBetaPeriod` + `betaPeriodProvider`, `kAiExperimental` + `aiExperimentalEnabledProvider`, `FeatureGate.isAvailable`, `licenseTierProvider` (manual `Provider<LicenseTier>`), `LicenseValidator` interface + `NoopLicenseValidator` default, `LicenseBadgeStrings` interface, the `FeatureTierBadge` + `EditionBadge` widgets, and the licence-credential parsing and verification. WaveCrux has no in-tree license primitives; the `WaveCruxLicenseBadgeStrings` adapter (`lib/core/license/wavecrux_license_badge_strings.dart`) bridges the package widgets to WaveCrux's ARB-generated `L10N`. |
| **`crux_cxp`** | Cross-suite pure-Dart package in [`crux-shared`](https://github.com/Ferrite-Engineering/crux-shared) carrying the CXP (Cross-Tool eXchange Protocol) bindings every Crux product imports — protocol version `1.2` (`cxpProtocolVersion`): `ElementId`, `NameResolver`, `PeerIdentity`, `CxpEnvelope`, the message bodies (hello / hello-ack / goodbye, error, `notify_selection`, `request_highlight` / `request_open_artifact` / `request_open_source` and their acks, subscribe / unsubscribe), `CxpServer` / `LocalCxpServer` / `NoopCxpServer`, `CxpClient` / `LocalCxpClient`, `CxpDiscovery` / `CxpManifestWriter`, `cxpProcessAuthToken` (the per-process token a manifest publishes and a server requires of every dialler) and `CxpPathContainment` (the receiver-side rule for a peer-supplied path). WaveCrux's open-core `WaveCruxCxpServer` and `WaveCruxNameResolver` build on it. |
| **`crux_workspace`** | Cross-suite Flutter package in [`crux-shared`](https://github.com/Ferrite-Engineering/crux-shared) that owns the workspace + multi-tab + split-pane infrastructure. Provides generic `Workspace<P>` / `WorkspaceTab<P>` / `WorkspacePane` / `TabId` / `PaneId` value types, the `WorkspaceCodec<P>` interface for per-product payload serialization, `WorkspaceService<P>` with atomic-write persistence, `WorkspaceNotifier<P>` AsyncNotifier base, `WorkspaceLifecycleObserver`, `TabContainerManager` / `PaneContainerManager` for per-tab / per-pane `ProviderContainer` lifecycle, multi-window scaffolding (`kMultiWindowAvailable`, `TabDetachingDelegate`, `PanelPopOutDelegate`, `Noop*` defaults), and the consumer-facing widgets `PaneHost<P>` / `ViewerTabBar<P>` / `EmptyCanvasState`. WaveCrux is its reference adopter: the foundation types are bound to `WaveCruxTabPayload` throughout. |
| **`crux_theme`** | Cross-suite Flutter package in [`crux-shared`](https://github.com/Ferrite-Engineering/crux-shared) holding the named-token color theming engine: `CruxColorTheme` (immutable theme model), `ThemeRegistry` (token-category registration, preset overlays, fallback resolution), `ThemePack` + `ThemePackCodec` + `ThemePackService` (`.crux-theme.json` persistence), `CruxColorThemeNotifier` + `cruxColorThemeProvider` (Riverpod state), `CruxThemeExtension` (Flutter `ThemeExtension` integration), the six built-in presets via `builtinPresets()` (`crux-dark`, `crux-light`, `solarized-dark`, `high-contrast-dark`, `oscilloscope`, `oled-xr`; suite-wide `chrome` tokens only), and the Settings → Appearance widget set (`PresetPicker` / `TokenEditor` / `ColorPickerDialog` / `ThemeAppearanceSection` composer). WaveCrux registers its `canvas` token category and preset overlay at boot via `registerWaveCruxThemeTokens()`, exposes canvas accessors through `WaveCruxThemeAccessors`, applies chrome tokens with `applyChromeTokens`, and derives `cruxColorThemeProvider` state from `appSettingsProvider`. |
| **`CruxColorTheme`** | Immutable named-token color theme model from `package:crux_theme`. Stores a flat `Map<String, Map<String, Color>>` of `category → token → Color` plus an `id`, `displayName`, and `Brightness`. Consumers reach WaveCrux's specific tokens via the field-style getters on the `WaveCruxThemeAccessors` extension (`theme.canvasBackground`, `theme.canvasCursorPrimary`, …), which resolve through `ThemeRegistry` so tokens absent from the active theme fall back to the registered brightness-appropriate default. |
| **`CruxThemeExtension`** | Flutter `ThemeExtension<CruxThemeExtension>` from `package:crux_theme` that wraps the active `CruxColorTheme` so widgets can read named tokens through `Theme.of(context).extension<CruxThemeExtension>()!`. WaveCrux does not read chrome tokens from it directly: `app.dart` passes each built theme through `applyChromeTokens`, which folds the optional Material 3 overrides into the `ColorScheme` / `AppBarTheme` and leaves any token the active theme omits (a transparent sentinel) at its Material default. |
| **`WaveCruxThemeAccessors`** | Extension on `CruxColorTheme` (in `lib/core/theme/wavecrux_theme_accessors.dart`) that exposes every WaveCrux canvas token under field-style names (`theme.canvasBackground`, `theme.canvasCursorPrimary`, …) returning `Color`. Every registered canvas token has a reader: the lane render object reads the background, lane, group-header, X/Z, `ruler.tickMajor` (group-header and comment text) and selection tokens; `CursorOverlay` reads `cursor.*` and `marker.line`; `TimeRulerWidget` reads `ruler.background`/`tick`/`label`/`cursorTime`, `marker.flag`/`flagText` and the cursor colors. The ruler's own major ticks keep `WavecruxColorExtension.timeRulerMajorTick`, because `ruler.tickMajor` already colors the group-header text in a different shade. `cursor.delta` and `marker.line` default to fully transparent, which draws nothing. Traces and bus value labels take each signal's own color, so there is no token for them. `test/core/theme/wavecrux_canvas_preset_overlay_test.dart` pins every preset value and `test/features/viewer/widgets/canvas_theme_tokens_paint_test.dart` asserts each token reaches its painter. |
| **`WaveCruxThemeAppearanceStrings`** | Adapter (in `lib/core/theme/wavecrux_theme_appearance_strings.dart`) that satisfies `package:crux_theme`'s abstract `ThemeAppearanceStrings` interface from WaveCrux's ARB-generated `L10N`. Every getter routes to a `L10N.appearance*` key. Wired by [`ColorThemeSection`](../lib/features/settings/widgets/color_theme_section.dart), which composes the package's `PresetPicker` + `TokenCategorySection` + `ThemePackBrowser` **directly** (rather than the bundled `ThemeAppearanceSection` composer) under WaveCrux subsection labels so it nests inside the Settings → Appearance category without a duplicate heading; the sub-widgets render in the active locale. |
| **CXP** | **Cross-Tool eXchange Protocol** — the peer cross-probe protocol that lets Crux apps gossip selection events, request highlights, and reconcile element identity across products. Distinct from `WCP`: WCP is the external driver protocol (imperative, viewer-bound, third-party tools driving one viewer); CXP is the peer cross-probe protocol (bidirectional, symmetric, Crux apps and third-party peers gossiping). The two are orthogonal and coexist on distinct ports with disjoint command surfaces. The CXP specification is published at `https://edacrux.app/cxp`. |
| **CxpServer** | Abstract server interface defined in `package:crux_cxp` with `start()` / `stop()` / `broadcast()` / `sendTo()` / `inbound` stream / `presence` stream. `LocalCxpServer` is the concrete TCP/JSON-line implementation bound to localhost (default port 54322 in WaveCrux); `NoopCxpServer` is the default for products that haven't opted into CXP. `WaveCruxCxpServer` wraps `LocalCxpServer`, registers `WaveCruxNameResolver`, and runs the manifest writer, discovery, and a `CxpPeerConnector`; outbound `notify_selection` events come from the separate `CxpSelectionEmitter` provider. |
| **CxpClient** | Symmetric client interface — `connect()` / `disconnect()` / `send()` / `inbound` stream / `events` stream — with concrete `LocalCxpClient` matching `LocalCxpServer`'s wire format. Used by reference tests; product-side integrations don't typically need it because each Crux app runs a server that other apps' clients connect to. |
| **ElementId** | Opaque, comparable identifier for a cross-tool referenceable design element (`ElementKind.signal`, `scope`, `instance`, `net`, `port`, `marker`, `rule`, `test`, `breakpoint`, `source`). The on-the-wire form Crux peers exchange — value-based equality on `kind` + canonical `path`. Defined in `package:crux_cxp`. |
| **NameResolver** | Abstract seam in `package:crux_cxp` that each Crux product implements to translate its native references into and out of canonical `ElementId` form. WaveCrux's resolver maps hierarchical signal paths (`top.cpu.alu.sum[31:0]`) and named markers; future Crux products map their own domains (elaborated names, rule sites, breakpoints, tests). `NoopNameResolver` and `IdentityNameResolver` ship for testing and proof-of-concept use. |
| **CxpDiscovery** | Manifest-file peer discovery service in `package:crux_cxp`. Each running CxpServer writes `<peer_id>.json` via `CxpManifestWriter` into one suite-shared directory resolved by `sharedCxpManifestDirectory()` — `~/Library/Application Support/crux/cxp/peers` on macOS, `%APPDATA%\crux\cxp\peers` on Windows, `${XDG_DATA_HOME:-~/.local/share}/crux/cxp/peers` on Linux — so every product scans the same place. Peers watch the directory and emit `CxpDiscoveryEvent`s as manifests appear and disappear; stale-pruning (default 5-minute threshold) removes dead-peer manifests. |
| **WaveCruxCxpServer** | WaveCrux's open-core wrapper around `LocalCxpServer`. Owns the CXP server lifecycle, registers `WaveCruxNameResolver`, writes its peer manifest `wavecrux-<pid>-<startedAtMillis>.json` into the shared manifest directory (see CxpDiscovery), and runs discovery so the cross-probe panel sees sibling Crux apps appear and disappear. Capabilities advertise `wavecrux.signal_value` + `wavecrux.cursor_time_fs`. Defined in `lib/services/remote/cxp/wavecrux_cxp_server.dart`. |
| **WaveCruxNameResolver** | Concrete `NameResolver` for WaveCrux's native element references. Round-trips four element kinds: hierarchical signal paths (slice-preserving, escape-prefix-preserving), scope paths, named markers (`a`–`z`), and `file:line[:column]` source citations. Returns `null` for `rule`/`test`/`breakpoint` kinds (those belong to peer products); accepts `instance`/`net`/`port` inbound and treats them as signal-like paths so peer-supplied references still have a chance of resolving in the current waveform. Defined in `lib/services/remote/cxp/wavecrux_name_resolver.dart`. |
| **Cross-probe panel** | Dock tab (right dock by default, movable to the bottom dock) that lists currently-connected CXP peers, the most recent ~50 cross-probe events (newest first, with direction arrows), and a "send selection to peer" button per peer. Opened via `ShortcutAction.openCrossProbePanel` (View category; "Show Cross-Probe Panel" in the palette; also a toolbar button). Available on tablet + desktop; hidden on phone. Defined in `lib/features/remote/widgets/cross_probe_panel.dart`, wrapping `crux_cxp_ui`'s `CrossProbePanel`. |
| **pcapToVcdDialogOpenerProvider** | Open-core seam (`lib/core/providers/pcap_to_vcd_dialog_opener_provider.dart`) for mounting the Convert PCAP to VCD dialog; the default opener is a no-op. See §10. |

---

## Revision History

This file's history is in `git log -- docs/ARCHITECTURE.md`. The product roadmap is not part of this repository.
