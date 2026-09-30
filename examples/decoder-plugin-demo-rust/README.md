# 1-Wire Decoder — Rust Port

This is the companion Rust port of the C demonstrator at
[`../decoder-plugin-demo/`](../decoder-plugin-demo/). Same protocol,
same on-disk artifact, same WaveCrux behavior — written in idiomatic
Rust against the same C ABI.

Pick whichever language you prefer for your own decoder plugin. The
WaveCrux loader treats the produced `.so` / `.dylib` / `.dll` files
interchangeably: it looks for the two required `extern "C"`
entry points, validates the ABI version, and wires the decoder into
the `DecoderRegistry` exactly as it would for the C build.

## Why a Rust port

Rust gives you memory-safe per-instance state, ergonomic enum-based
transaction kinds, and `Box<dyn>`-style ownership without any of the
C boilerplate. The runtime cost is identical (no allocation in the
hot path, only at handle construction / destruction), so this port
is a useful reference for plugin authors who want to write their
decoder in Rust without learning the open-core wavecrux toolchain.

## Build

```bash
cd wavecrux/examples/decoder-plugin-demo-rust
cargo build --release
```

The artifact lands at `target/release/`:

| Platform | Filename |
|---|---|
| Linux | `libwavecrux_onewire.so` |
| macOS | `libwavecrux_onewire.dylib` |
| Windows (MSVC / MinGW) | `wavecrux_onewire.dll` |

The `Cargo.toml`'s `crate-type = ["cdylib"]` is what produces a
C-compatible shared library rather than a `.rlib`.

## Install and verify

After building, copy the artifact into WaveCrux's plugin directory:

```bash
# macOS
cp target/release/libwavecrux_onewire.dylib \
   ~/Library/Application\ Support/wavecrux/decoders/

# Linux
cp target/release/libwavecrux_onewire.so \
   ~/.config/wavecrux/decoders/
```

…and follow steps 3–6 of [`../decoder-plugin-demo/README.md`](../decoder-plugin-demo/README.md)
(plugin safety prompt → reload → use the decoder).

The Rust port and the C port produce **byte-identical decoder
output** against the canonical fixture
`examples/decoder-plugin-demo/fixtures/onewire_basic.vcd`. They are
genuinely interchangeable.

## Cross-compiling

`cargo` natively supports cross-compilation — see the
[Rust cross-compilation docs](https://rust-lang.github.io/rustup/cross-compilation.html).
Common targets:

```bash
# Linux x86_64 → Windows
rustup target add x86_64-pc-windows-gnu
cargo build --release --target x86_64-pc-windows-gnu

# macOS aarch64 → macOS x86_64
rustup target add x86_64-apple-darwin
cargo build --release --target x86_64-apple-darwin
```

## Authoring tips for the Rust path

- The `extern "C"` entry points must use `#[no_mangle]` so the
  loader can find them by symbol name.
- The plugin's `WcDecoderHandle` is a `*mut c_void` from the loader's
  perspective; in Rust the natural representation is
  `Box::into_raw(Box::new(state)) as WcDecoderHandle`. `ow_destroy`
  reverses that with `Box::from_raw`.
- Static manifest / id / label strings must be NUL-terminated. Use
  `b"…\0"` byte-string literals and cast to `*const c_char` at the
  FFI boundary — these have `'static` lifetime, which exactly
  matches the loader's "borrowed for the lifetime of the shared
  library" rule.
- Per-call strings (transaction `label` and `fields_json`) need
  per-instance backing storage that lives until the next `feed` /
  `flush` call. `OneWireState` allocates a small ring of fixed-size
  byte buffers and writes NUL-terminated copies into them — no
  dynamic allocation in the hot path.
