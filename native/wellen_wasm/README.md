# wellen_wasm — WebAssembly bridge to the wellen waveform parser

This crate compiles the [`wellen`](https://crates.io/crates/wellen) Rust
library to WebAssembly so the WaveCrux Flutter Web build can decode VCD, FST,
and GHW files using the same parser that powers the native FFI build.

It is the web sibling of `native/wellen_ffi`, which exposes the same engine
via a C ABI for desktop and mobile builds. Both crates pin the same `wellen`
version so every platform parses identically.

It runs single-threaded so the web build needs no cross-origin-isolation
headers; see [Deployment](#deployment).

## Architecture

```
Flutter Web app
  └── Dart WellenWasmProvider (lib/services/waveform/wellen_wasm_provider_web.dart)
        └── globalThis.waveCruxWellen (web/wasm/wellen_wasm_loader.js)
              └── wasm-bindgen WellenWasm class (this crate)
                    └── wellen Rust library (vendored from crates.io)
```

The Dart side never imports the wasm-bindgen ES module directly. Instead, a
small JS loader (`web/wasm/wellen_wasm_loader.js`) does the dynamic import and
republishes the API on `globalThis.waveCruxWellen`, which Dart's
`dart:js_interop` can address.

## Surface

The `WellenWasm` class mirrors `wellen_ffi.h` method-for-method. Every method
that the FFI bridge exposes has an equivalent here, with these conventions:

- Time values (ticks, transition counts, byte sizes) are `f64` (JS Number).
  Simulation times fit comfortably within 53 bits of precision; using
  `JSBigInt` would force every Dart caller through a String round-trip and is
  not worth the trouble for the gains in precision.
- Indices (signal refs, scope/variable indices, scope/variable type
  identifiers) are `u32` (JS Number).
- Strings are `String` (JS String). Empty string is used in place of
  null when the underlying field is absent.
- Hierarchy traversal returns `Vec<u32>` which `wasm-bindgen` materializes as
  `Uint32Array` on the JS side.
- `signalChanges()` returns `{ times: Float64Array, values: string[] }`.
- `timescale()` returns `{ factor: number, unitExp: number }` or `null`.
- `nextTransition()` / `prevTransition()` return `{ time, value }` or `null`.

Bumping the ABI requires bumping `abiVersion()` and `expectedAbiVersion` on
the Dart side together — the Dart wrapper rejects mismatched modules at load
time.

## Build

Prerequisites:

```bash
rustup target add wasm32-unknown-unknown
curl -sSf https://rustwasm.github.io/wasm-pack/installer/init.sh | sh
```

Build (preferred — invokes wasm-pack, copies artefacts into `web/wasm/`,
runs the gzipped-bundle gate):

```bash
dart run tool/build_web_wasm.dart
```

Direct invocation (for when you want to inspect the `pkg/` output without
copying it):

```bash
wasm-pack build native/wellen_wasm --target web --release
```

The `release` profile turns on `opt-level = "z"`, full LTO, single codegen
unit, and `panic = "abort"`. `wasm-opt` post-processing is disabled because
the version bundled with wasm-pack 0.13 lags the bulk-memory ops modern
rustc emits — see the comment in `Cargo.toml` for details.

## Bundle size

The gzipped `wellen_wasm_bg.wasm` budget is **1.5 MiB**. The current build
weighs in around 160 KiB gzipped, leaving plenty of headroom for wellen
upstream changes. The `tool/build_web_wasm.dart` script verifies this on
every build, and `test/native/wellen_wasm_bundle_size_test.dart` makes the
gate part of `flutter test` so a regression surfaces on the same PR that
causes it.

## Tests

Pure-logic unit tests (format detection, helpers) run as native Rust tests:

```bash
cd native/wellen_wasm
cargo test
```

End-to-end JS interop tests live on the Dart side as Chrome-headless
integration tests (see `lib/services/waveform/wellen_wasm_provider_web.dart`
and `integration_test/web/`).

## Deployment

The web build ships the wasm artefact as a single deferred asset under
`web/wasm/wellen_wasm_bg.wasm`. **No special HTTP headers are required**:
the bundle runs in single-threaded mode, so cross-origin isolation
(`Cross-Origin-Opener-Policy` + `Cross-Origin-Embedder-Policy`) is
intentionally unnecessary. This keeps the deployment story aligned with
"drop the build into any static host" — Pages, Netlify, S3, an `nginx`
config, all work without further setup.

If/when multi-threaded WASM becomes worth the deployment-header tax, that
will be a separate phase.

## License

This crate is part of the WaveCrux open-core repo and ships under the same
license as the rest of the source. The `wellen` dependency is BSD-3-Clause,
attributed in the project root `NOTICES`.
