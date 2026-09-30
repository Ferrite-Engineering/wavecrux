# lxt2fst — clean-room LXT/LXT2 → FST converter

`lxt2fst` is the convert-on-open path for GTKWave's legacy
`.lxt` (2003 streaming) and `.lxt2` (2005 block-indexed) waveform formats.
Files matching the LXT or LXT2 magic byte are converted by this crate
into an FST — a cached sibling `.fst` on desktop and mobile, an in-memory
buffer on the web — then opened by the existing wellen pipeline like any
other FST. The rest of WaveCrux sees a plain FST and the entire
query / decoder / Stage / export surface works unchanged.

The convert-on-open architecture and the sibling-cache strategy are described
in `docs/ARCHITECTURE.md` §2.2.1.

## Clean-room rule

GTKWave's `lxt_read.c` / `lxt2_read.c` are GPLv2. They were NOT consulted
during the implementation of this crate — neither as source, nor as a
source of constants. The wire-format constants used here (magic bytes,
header field layout, block-prefix layout, name-prefix-compression scheme,
geometry-record shape) were established empirically from the small
fixtures committed under `wavecrux/test/fixtures/legacy/`, combined with
the publicly-documented format outline. The formats are frozen; no
upstream version tracking is needed.

## Build

### Desktop / mobile (FFI)

This crate is not built or bundled on its own. `native/wellen_ffi` links it
as a Rust dependency, so the one native library every platform already
ships — `libwellen_ffi.{dylib,so}` / `wellen_ffi.dll`, and the static
archive in `WellenFFI.xcframework` on iOS — exports the `lxt2fst_*` C ABI
next to `wellen_*`. Dart opens that library for both
(`lib/native/wellen_ffi_library_io.dart`). Building wellen_ffi builds this
crate:

```bash
cd native/wellen_ffi
cargo build --release
```

Every platform build treats this crate's sources as rebuild inputs (the
Linux/Windows CMake, the macOS Runner phase, Android's Gradle task). iOS is
the exception: Xcode never runs cargo, so rerun `scripts/build_ios.sh` and
commit the xcframework after changing the crate. New C-ABI functions also
need a line in `native/wellen_ffi/Sources/WellenFFIKeepalive/wellen_ffi_keepalive.c`
or iOS strips them; `test/static/wellen_ffi_bundles_lxt2fst_test.dart`
enforces both. The C-ABI header is hand-maintained at `include/lxt2fst.h`.

This crate's own `[profile.release]` (size-optimised, `panic = "abort"`)
applies only to the web build; linked into wellen_ffi, wellen_ffi's profile
governs, and it unwinds, so the `ffi_guard!` panic net works.

### Prerequisites

```bash
# WASM toolchain (web build only)
rustup target add wasm32-unknown-unknown
curl -sSf https://rustwasm.github.io/wasm-pack/installer/init.sh | sh
```

The desktop FFI build needs only a working `cargo` (any stable
toolchain ≥ 1.74). The crate has no system-library dependencies — `flate2`
is pulled in with `default-features = ["rust_backend"]` so no `zlib`
headers are required.

### Web (WASM)

```bash
dart run tool/build_lxt2fst_wasm.dart
```

Compiles the crate to WebAssembly via `wasm-pack`, copies the artefact
into `web/wasm/lxt2fst_bg.wasm`, and verifies the gzipped bundle stays
inside the 400 KiB budget enforced by
`test/native/lxt2fst_wasm_bundle_size_test.dart`.

On the web the conversion runs entirely in memory (`convert_bytes`;
wasm32 has no filesystem). The hand-written `web/wasm/lxt2fst_loader.js`,
loaded by `web/index.html`, imports the module lazily on the first
LXT/LXT2 open and publishes it as `globalThis.waveCruxLxt2Fst` for
`lib/services/waveform/lxt2fst_converter_web.dart`. Nothing is cached: a
second open converts again.

Direct invocation:

```bash
wasm-pack build native/lxt2fst --target web --release
```

The release profile mirrors `wellen_wasm` — `opt-level = "z"`, full LTO,
single codegen unit, `panic = "abort"`. `wasm-opt` post-processing is
disabled because the wasm-pack 0.13 bundled `wasm-opt` lags the bulk-
memory ops modern rustc emits.

## Dependency choices

The writer side had two candidates: the `fst-native` family (now
`fst-reader` / `fst-writer`, already transitive via wellen), or a thin
in-crate FST writer if that dependency surface proved too large to pull in
standalone.

We picked **`fst-writer`** (the BSD-3 sibling crate to the `fst-reader`
that wellen uses internally). Rationale:

* `fst-writer` and `fst-reader` are by the same author as wellen, all
  intentionally non-GPL, so the convert-on-open path stays on one
  well-tested FST stack instead of fragmenting onto a fresh writer.
* The FST block layout (geometry, block index, value-change blocks with
  their own LZ4 framing) is non-trivial. Reimplementing it solely to avoid
  a small dependency would be a poor effort tradeoff — particularly in
  comparison to the LXT/LXT2 reader, which has no upstream non-GPL writer
  we can reuse and so genuinely needs new code.
* Bundle-size budget (400 KiB gzipped wasm) was verified against
  `fst-writer` under the same wasm-pack release profile we ship for
  `wellen_wasm`; the budget holds with headroom (see the regression test).

The wrapper lives in `src/fst_writer.rs`. If `fst-writer` ever drifts or
the wasm bundle blows the 400 KiB budget under a future upgrade, only
that file changes — the rest of the crate is API-stable behind the
façade.

**Vendored patch.** fst-writer 0.3.1 (the latest release) can only create
a writer on a file path, which the web build does not have. The crate is
therefore vendored at `native/vendor/fst-writer/` with one addition — a
public `FstHeaderWriter::new` over any `Write + Seek` sink — and applied
through `[patch.crates-io]` in both this manifest and wellen_ffi's (a
patch only takes effect at the root of a build). Provenance and the exact
change are in `native/vendor/fst-writer/Cargo.toml`; drop the directory and
both patch entries once an fst-writer release has a non-file constructor.

## Cargo layout

```
native/lxt2fst/
├── Cargo.toml                # deps: flate2 (rust_backend), fst-writer (patched → ../vendor/fst-writer); wasm-bindgen on wasm32
├── .cargo/config.toml        # cross-compile config (mirrors wellen_ffi)
├── include/
│   └── lxt2fst.h             # hand-maintained C-ABI header (ffigen input)
├── src/
│   ├── lib.rs                # FFI surface, error type, magic detection
│   ├── error.rs              # ConvertError + C-ABI return codes
│   ├── progress.rs           # 50 ms / 1 % throttled reporter
│   ├── lxt2.rs               # LXT2 reader (block-indexed)
│   ├── lxt.rs                # LXT classic reader (structure + convert)
│   ├── lxt_value_decode.rs   # LXT classic streaming value-change decoder
│   ├── fst_writer.rs         # façade over the fst-writer crate
│   └── wasm.rs               # wasm-bindgen surface (web only)
├── tests/                    # round-trip integration tests
└── README.md                 # this file
```

## Status

**LXT2 — full value decode (shipped).** The block/granule value-change
codec is reverse-engineered and decoded, so `.lxt2` files convert to FST
with their real per-facility transitions — scalars, bit-vectors (including
`x`/`z` states), reals, multi-granule blocks, and multi-block files all
round-trip to FST exactly.

* **Structural parser:** magic + version + numfacs + name-section
  prefix-decompression + 16-byte/facility geometry + block-prefix walking
  + per-block time-table reconstruction.
* **Value-change decoder (`src/value_decode.rs`):** multi-granule block
  framing, the per-facility operator alphabet (set-0/1, complement,
  shifts, ±1..4 deltas, all-x/all-z, MVL string literals), the footer
  bitmask dictionary, the Verilog x/z left-extension fill rule, and real
  (f64) facilities. **Differentially fuzz-validated** against GTKWave's
  own `vcd2lxt2` encoder by `tool/lxt2_value_fuzz.py` (thousands of
  randomized inputs — every width, x/z, reals, multi-facility,
  multi-granule — with the hard invariant that the decoder never emits a
  wrong value). The decoder is **strict**: a block whose structure does
  not validate is not emitted with guessed values; the converter falls
  back to a safe initial-value record for the affected facilities, so a
  converted trace is never silently wrong.
* **FST writer façade:** hierarchy emission (dotted-path → `$scope` /
  `$upscope`), bit-vector value changes, and real (`f64`) value changes
  written as native little-endian 8-byte payloads.
* **C-ABI surface:** `lxt2fst_convert`, `lxt2fst_detect_format`,
  `lxt2fst_last_error_message`, `lxt2fst_abi_version`. Panic-safe at the
  boundary; structured `ConvertError` enum with stable discriminants.
* **WASM surface:** `lxt2fstConvert` / `lxt2fstDetectFormat` /
  `lxt2fstAbiVersion`. Bundle size gated at ≤ 400 KiB gzipped. The
  committed `web/wasm/lxt2fst_bg.wasm` is rebuilt with `dart run
  tool/build_lxt2fst_wasm.dart` (needs `wasm-pack`) after any change to
  this crate or the vendored fst-writer.
* **Progress reporting:** `(blocks_done, total_blocks)` for LXT2;
  `(sections_done, total_sections)` for LXT classic. Throttled to 50 ms
  OR 1 %, whichever first.

**LXT-classic — full value decode (shipped).** The *streaming*
value-change codec — a **separate** format from LXT2's block/granule codec
— is reverse-engineered and decoded, so `.lxt` files convert to FST with
their real per-facility transitions, to the same bar as LXT2.

* **Structural LXT-classic parser:** magic + trailing gzip-section
  enumeration (NAMES + GEOMETRY + chain-head table + index) + name-section
  prefix-decompression (shared scheme with LXT2) + 16-byte/facility
  geometry (shared layout with LXT2) + timescale exponent + max-time from
  the index section.
* **Value-change decoder (`src/lxt_value_decode.rs`):** the inline
  `[op][facref][value]` record framing, the multi-byte back-pointer
  (`1 + (op>>4)` big-endian facref bytes), the per-facility chain-head
  table (which resolves facility identity — the stream is in
  VCD-declaration order, the name index alphabetical), the operator
  alphabet (binary + 2-bit-per-symbol 4-state literals; all-0/1/z/x),
  little-endian f64 reals, and the per-timestep time index.
  **Differentially fuzz-validated** against GTKWave's own `vcd2lxt` encoder
  by `tool/lxt_classic_value_fuzz.py` (thousands of randomized inputs —
  every width, x/z, reals, multi-facility, ≥256-byte back-pointers — with
  the hard invariant that the decoder never emits a wrong value). Like the
  LXT2 path it is **strict**: any structural surprise falls back to a safe
  `x`-state emission rather than a guessed value, so a converted `.lxt` is
  never silently wrong. In practice LXT2 is the dominant legacy format, but
  both legacy readers now decode values to the same standard.

## Tests

```bash
# Rust unit + integration tests (incl. value-equivalence round-trips)
cd native/lxt2fst
cargo test

# Differential value-codec fuzz vs GTKWave's vcd2lxt2 / vcd2lxt encoders
# (dev-machine only; needs vcd2lxt2 + vcd2lxt on PATH — `brew install gtkwave`)
python3 tool/lxt2_value_fuzz.py --trials 20000          # LXT2 block/granule codec
python3 tool/lxt_classic_value_fuzz.py --trials 20000   # LXT-classic streaming codec

# WASM tests (requires wasm-pack + Chrome)
wasm-pack test --chrome --headless native/lxt2fst

# Dart bundle-size regression (after building the wasm)
flutter test test/native/lxt2fst_wasm_bundle_size_test.dart
```

`cargo test` validates the structural reader against every legacy
fixture and round-trips a tiny FST through fst-writer ↔ wellen. The
WASM test suite re-runs the same logic under `wasm32-unknown-unknown`
to catch wasm-only regressions (libc gaps, allocator differences).

## License

Apache-2.0, same as the rest of the WaveCrux open-core repo. The
`fst-writer` and `flate2` dependencies are BSD-3-Clause and
MIT-or-Apache-2.0 respectively; both are listed in the project root
`NOTICES`, which also records the vendored fst-writer modification.
