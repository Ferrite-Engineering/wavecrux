# WaveCrux Web Performance Notes

How the Flutter Web build (app.wavecrux.app) parses and renders waveforms, and
where its limits come from. The limits below are constants in the code; the
source is named next to each.

## Renderer

The web build uses CanvasKit, which is Flutter's default renderer for
`flutter build web`. The HTML renderer no longer exists, and the old
`--web-renderer canvaskit` flag was removed from Flutter — passing it fails
the build (see the `Makefile` comment). Build without it:

```bash
flutter build web --release
# or: make web-release
```

CanvasKit ships its own `canvaskit.wasm`, fetched on first load and cached by
the browser afterwards.

## Engine: wellen compiled to WebAssembly

The web build parses with the same `wellen` Rust crate as desktop and mobile.
`native/wellen_wasm/` wraps it with wasm-bindgen; both `native/wellen_wasm` and
`native/wellen_ffi` pin `wellen = "0.24"`, so web and native parse identically.
There is no pure-Dart parser.

```
WaveformSourceNotifier.openFromBytes      lib/features/viewer/providers/waveform_source_provider.dart
  └── WellenWasmProvider                  lib/services/waveform/wellen_wasm_provider_web.dart
        └── globalThis.waveCruxWellen     web/wasm/wellen_wasm_loader.js (loaded from web/index.html)
              └── WellenWasm              native/wellen_wasm/src/lib.rs → web/wasm/wellen_wasm_bg.wasm
```

- **Loading.** The loader script loads with the page, but the `.wasm` is not
  instantiated until the first file open
  (`WellenWasmProvider.ensureInitialized`). The loader's ABI version must then
  match `expectedAbiVersion`. If the module is missing, fails to instantiate,
  or reports the wrong ABI, the open raises `WebAssemblyRequiredError` and the
  canvas centre shows "WebAssembly is required". There is no fallback.
- **Headers.** The module is single-threaded, so it needs no
  `Cross-Origin-Opener-Policy` / `Cross-Origin-Embedder-Policy` headers and
  runs from any static host.
- **Bundle budget.** The gzipped `web/wasm/wellen_wasm_bg.wasm` must stay
  under 1.5 MiB — enforced by `tool/build_web_wasm.dart` and
  `test/native/wellen_wasm_bundle_size_test.dart`.

## Formats on web

| Format | Web | How |
|---|---|---|
| VCD, FST, GHW | Yes | wellen-WASM. wellen detects the format from the file contents; the extension only sets the format label reported in File Info. |
| `.wavecruxpack` | Yes | Unpacked in memory; the bundled session is restored against the bundled dump. |
| LXT, LXT2 | Yes | Converted to FST in memory by the `lxt2fst` WASM converter (`lib/services/waveform/lxt2fst_converter_web.dart`), then parsed by wellen-WASM like any FST. `web/wasm/lxt2fst_loader.js` (loaded by `web/index.html`) fetches the converter only on the first LXT/LXT2 open, so other visitors never download it. No conversion cache: reopening converts again. Covered end to end by `integration_test/web/web_legacy_lxt_open_test.dart`. |
| FSDB | No | Conversion needs a local `fsdb2vcd`. A picked or dropped `.fsdb` is caught by name and shows "FSDB needs the desktop app". |
| `.wavecrux` session files | No | The web picker does not offer them; there is no filesystem to resolve the session's source path. |

## Performance characteristics

- **Parsing blocks the main thread.** Flutter Web has no background isolate,
  and the WASM module has no worker threads. The open path waits for one
  frame (`WidgetsBinding.instance.endOfFrame`) so the "Parsing…" placeholder
  paints, then parses synchronously. The UI is unresponsive until parsing
  finishes. On desktop, wellen's VCD parser uses several threads; on web it
  uses one.
- **The whole file is in memory, more than once.** Browsers hand the app file
  contents, not paths, so the picker, drag-and-drop and `?file=` fetch all read
  the full file into a `Uint8List`. That buffer is then copied into WASM linear
  memory. wasm32 caps linear memory at 4 GiB.
- **The hierarchy is built eagerly.** On open, `WellenWasmProvider` walks
  every scope and variable, making a separate JS↔WASM call for each property.
  Open time therefore grows with the variable count, even when few signals are
  displayed.
- **Signal data loads lazily, then crosses the bridge once.** `loadSignal`
  loads the signal inside WASM, then copies its whole change list to Dart
  (`CompactChanges`) in a single call. Values arrive as strings. After that,
  `valueAt`, `changesInRange` and `nextTransition` / `prevTransition` are
  binary searches on the Dart copy, so drawing never calls into WASM.
- **Transition totals are lazy.** File-wide transition counts are summed from
  the signals already loaded rather than computed at open, which removed about
  400 ms from opening a 1,500-signal file.
- **Time precision.** Times and counts cross the bridge as JS Numbers (`f64`),
  so tick values above 2^53 lose precision.

## Limits

| Limit | Value | Source |
|---|---|---|
| Large-file warning | Files over 100 MB show a "Large File" confirmation before loading. This covers the picker, drag-and-drop, `?file=` URLs, and the waveform inside a `.wavecruxpack`. | `WebFileLoader.fileSizeWarningThresholdBytes` |
| Slow-parse nudge (editor-host webview only) | A parse taking 3 s or more offers the desktop app | `kEditorHostSlowParseThreshold` |
| WASM bundle, gzipped | 1.5 MiB (`wellen_wasm`), 400 KiB (`lxt2fst`) | `tool/build_web_wasm.dart`, `tool/build_lxt2fst_wasm.dart` |

## Not available on web

- **Auto-reload on file change.** There is no file path to watch;
  `crux_file_watcher` is a no-op on web.
- **FSDB conversion** and **process filters**. Neither can start a local
  process; process filters are a no-op on web.
- **Interactive (streaming) VCD** from stdin or a named pipe. It throws
  `UnsupportedError`.
- **User ISA table directories.** The Settings panel is hidden, and only the
  bundled tables load.
- **Native decoder plugins.** The startup plugin scan returns nothing on web.
- **Drag-and-drop after a file is open.** The drop target exists only while
  the empty canvas is showing (no tabs open). To add another file after that,
  use the Open File action.

## CI/CD URL Loading

A CI test report can link to a WaveCrux instance that loads a waveform
automatically:

```
https://app.wavecrux.app/?file=https://ci.example.com/artifacts/dump.vcd
```

**CORS requirement:** the server hosting the waveform must send

```
Access-Control-Allow-Origin: *
```

(or the WaveCrux origin). Without it the browser blocks the fetch, and
WaveCrux shows a load-error snackbar.

How it works: `rootRedirect` in `lib/core/router.dart` rewrites `/?file=` to
`/viewer?file=`. `ViewerScreen` passes the value to `_openPath` in
`lib/features/viewer/screens/viewer_screen_file_io.dart`. On web, an
`http(s)://` value goes to `_openFromUrl`, which fetches it with
`UrlFileLoader` (`http.Client.get`, the browser Fetch API). Any HTTP status
other than 200 is an error. The same 100 MB warning applies, and the bytes
then open through `openFromBytes` in a new tab. The flow, including a
CORS-blocked URL, is covered by `integration_test/web/web_url_file_load_test.dart`.

## Build and test commands

```bash
# Development (debug)
flutter run -d chrome

# Production build — output in build/web/
make web-release

# Profile build (DevTools performance profiling)
make web-profile

# Rebuild the WASM bundles after changing native/wellen_wasm or native/lxt2fst
# (needs `rustup target add wasm32-unknown-unknown` and wasm-pack). The built
# bundles are committed under web/wasm/, so this step is not needed otherwise.
dart run tool/build_web_wasm.dart
dart run tool/build_lxt2fst_wasm.dart

# Web-only widget tests (@TestOn('browser'), kIsWeb == true)
tool/run_web_widget_tests.sh

# Web integration tests (flutter drive + chromedriver, headless Chrome)
tool/run_web_integration_tests.sh
```
