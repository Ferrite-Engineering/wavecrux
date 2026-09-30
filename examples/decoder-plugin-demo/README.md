# 1-Wire Decoder — WaveCrux Plugin Demonstrator

This is the canonical reference for authoring a user-contributed
protocol decoder plugin against the WaveCrux decoder C ABI. It
implements a passive observer for the Maxim/Dallas 1-Wire bus and
emits `RESET`, `PRESENCE`, and `BYTE` transactions as you scrub the
waveform timeline.

Clone or copy this directory, change the protocol logic to fit your
own bus, rename the manifest's decoder id, and you have a complete
WaveCrux plugin.

> Looking for the ABI reference? See
> [`include/wavecrux_decoder.h`](../../include/wavecrux_decoder.h) at
> the open-core repo root.

---

## Why 1-Wire

1. **Single signal.** The whole protocol rides on one `dq` line, so
   the manifest declares exactly one binding and the demonstrator
   doesn't get bogged down in multi-pin wiring.
2. **Bounded transactions.** Each RESET / PRESENCE / BYTE has a clean
   start and end. There's no streaming-frame ambiguity.
3. **Well documented.** The Maxim DS18B20 datasheet and the "1-Wire
   Communication Through Software" application note describe every
   timing window we use.
4. **Not in WaveCrux's built-in set.** Building an 11th decoder atop
   a known protocol skips the "what would I even decode?" decision
   and lets the demonstrator be useful in real designs (DS18B20
   thermometers, DS2401 silicon serial numbers, iButtons).

---

## What the decoder does

| Event | Detection | Emitted transaction |
|---|---|---|
| RESET pulse | DQ low for ≥ 400 µs | `RESET` |
| PRESENCE pulse | DQ low for 30–240 µs immediately after a RESET release | `PRESENCE` |
| Bit slot (1) | DQ low for < 15 µs | accumulated into `BYTE` |
| Bit slot (0) | DQ low for ≥ 30 µs and < 240 µs (outside a presence-pulse window) | accumulated into `BYTE` |
| Byte boundary | every 8 bit slots after a RESET | `BYTE 0xXX` |

The decoder does **not** interpret the byte stream — it does not know
that `0x33` is the READ_ROM command, or that a particular byte is a
CRC8. Higher-level interpretation is left to upstream tooling.

This is a deliberate scope limit: the demonstrator should show how
the C ABI works, not how to write a complete 1-Wire transaction
analyser.

---

## End-to-end walkthrough

The path from "git clone" to "1-Wire decoder appears in WaveCrux" is
six steps. Estimated time: 5–10 minutes if you already have a C
compiler installed.

### 1. Build the plugin

#### Linux / macOS

```bash
cd wavecrux/examples/decoder-plugin-demo
make
```

This produces `libwavecrux_onewire.so` (Linux) or
`libwavecrux_onewire.dylib` (macOS) next to the source.

#### Cross-platform with CMake

```bash
cd wavecrux/examples/decoder-plugin-demo
cmake -S . -B build
cmake --build build
```

The artifact lands in `build/`.

#### Windows (MSVC)

From a "Developer PowerShell for VS":

```powershell
cd wavecrux\examples\decoder-plugin-demo
cmake -S . -B build
cmake --build build --config Release
```

The artifact is `build\Release\wavecrux_onewire.dll`. CMake produces
the canonical Windows naming (no `lib` prefix); the WaveCrux loader
scans for both `wavecrux_onewire.dll` and `libwavecrux_onewire.dll`,
so either name works.

#### Windows (MinGW)

```cmd
cd wavecrux\examples\decoder-plugin-demo
cmake -S . -B build -G "MinGW Makefiles"
cmake --build build
```

The artifact is `build\libwavecrux_onewire.dll`.

### 2. Drop the plugin into WaveCrux's plugin directory

The default per-user plugin directory is platform-specific:

| Platform | Default path |
|---|---|
| Linux | `~/.config/wavecrux/decoders/` |
| macOS | `~/Library/Application Support/wavecrux/decoders/` |
| Windows | `%APPDATA%\WaveCrux\decoders\` |

Create the directory if it doesn't exist, then copy the artifact:

```bash
# Linux / macOS — using the Makefile target:
make install

# …or by hand:
mkdir -p ~/Library/Application\ Support/wavecrux/decoders
cp libwavecrux_onewire.dylib ~/Library/Application\ Support/wavecrux/decoders/
```

Alternatively, point WaveCrux at any directory you like via
`Settings → Decoders → Plugin Directories`, or via the
`WAVECRUX_DECODER_PATH` environment variable (colon-separated on
Unix, semicolon-separated on Windows).

### 3. Acknowledge the plugin safety prompt

The first time WaveCrux discovers any plugin, you'll see a one-time
prompt explaining that plugins run as native code with full process
privileges. Acknowledge it to enable plugin loading.

This step exists because dropping a `.so` into a directory is exactly
the scenario your IT and security teams want to know about. The
acknowledgment is per-user, persistent, and bypassed for builds that
have Enterprise plugin governance enabled.

### 4. Restart WaveCrux (or click "Reload plugins")

WaveCrux scans the plugin directory at startup. After the first
launch, you can re-scan without restarting via
`Settings → Decoders → Plugins → Reload plugins`.

### 5. Verify the plugin loaded

Open `Settings → Decoders → Plugins`. You should see:

```
libwavecrux_onewire.dylib    (or .so / .dll)
  ID: examples.onewire
  Status: loaded
  Decoders: 1-Wire (demo plugin)
  ABI: 1.0
```

If the status is `abiMismatch`, `missingSymbol`, `manifestInvalid`,
or `loadError`, the panel shows the diagnostic message — fix the
issue and click "Reload plugins".

### 6. Use the decoder

Open a VCD with a 1-Wire `dq` signal — `fixtures/onewire_basic.vcd`
in this directory is a hand-crafted reference fixture you can use to
prove the plugin is working. In the WaveCrux decoder picker, choose
`1-Wire (demo plugin)`. Bind the manifest's `dq` pin to the signal
in your VCD that carries DQ. Apply.

You should see RESET / PRESENCE / BYTE transactions overlaid on the
waveform. The fixture's expected output is committed at
`fixtures/onewire_basic.expected_transactions.json` — comparing
WaveCrux's decoded output to that file is exactly the round-trip
the integration test in
`test/services/decoders/ffi/onewire_demo_integration_test.dart`
performs.

---

## Reference: the C ABI in 5 minutes

Every plugin exports two C functions:

```c
uint32_t wavecrux_decoder_abi_version(void);
int32_t  wavecrux_decoder_register(WcDecoderDef* out_defs,
                                   size_t* inout_count);
```

`wavecrux_decoder_abi_version()` returns the macro
`WAVECRUX_DECODER_ABI_VERSION` from `wavecrux_decoder.h`. The loader
rejects plugins whose major version doesn't match the host's.

`wavecrux_decoder_register()` is called twice: first with
`out_defs == NULL` and `*inout_count == 0` (return
`WC_DECODER_NEED_MORE_SLOTS` and write your decoder count to
`*inout_count`), then with a buffer big enough to hold every decoder
the plugin contributes. Populate the array, set `*inout_count` to
the number actually written, return `WC_DECODER_OK`.

Each decoder exposes four lifecycle callbacks:

| Callback | When called | Purpose |
|---|---|---|
| `create(config_json)` | Once per decoder instance, when the user activates the decoder. | Allocate per-instance state. Return `NULL` on failure. |
| `feed(handle, sample, out_tx, &count)` | Once per signal-change timestamp in the requested time range. | Decode incrementally. Emit zero or more transactions per call via `out_tx`. |
| `flush(handle, out_tx, &count)` | Exactly once at end-of-stream. | Emit any pending transactions. |
| `destroy(handle)` | Exactly once after flush. | Free per-instance state. |

The host serializes the decoder configuration as
`{"decoder_id": "...", "signal_bindings": {...}, "parameters": {...}, "options": {...}}`
and passes it as a UTF-8 NUL-terminated JSON string to `create`.
`decoder_id` is the id of the decoder being instantiated, so a plugin
that registers several decoders behind one `create` can tell them
apart; `options` carries the same values as `parameters`. Most plugins
ignore this — the binding-name → signal-path mapping is the host's concern,
and the loader has already used the manifest to wire signal values
into `WcSample.bits_ptr` in declaration order.

### Reading signal values

`WcSample.bits_ptr` packs every bound signal's current value at the
sample timestamp. The encoding is **two buffer bits per signal bit**:

| Buffer bit | Meaning |
|---|---|
| Even bit (offset 0, 2, 4 …) | Level: `0` or `1` |
| Odd bit (offset 1, 3, 5 …) | Unknown flag: set if the source value was X or Z |

For a 1-bit `dq` signal, `bits_ptr[0] & 1` is the level and
`(bits_ptr[0] >> 1) & 1` is the unknown flag — exactly what the
demonstrator's `extract_level` helper reads.

For a multi-bit binding, signal bit *i* lives at buffer-bit position
`2*i` (level) / `2*i + 1` (unknown). For multiple bindings, the
declaration order in the manifest determines packing order: the
first binding's bits start at offset 0, the next at offset
`2 * binding[0].bit_width`, and so on.

### Owning your strings

Every `const char*` you put on `WcDecoderDef` (id, display_name,
manifest_json) is **borrowed by the loader for the lifetime of the
plugin's shared library**. Static string literals in `.rodata`
satisfy this trivially (the demonstrator uses static strings for the
manifest and for the literal labels `"RESET"` / `"PRESENCE"`).

Per-call strings (the `label` and `fields_json` on each emitted
`WcTransaction`) follow a different rule: the plugin owns them until
the *next* call on the same handle. The demonstrator uses a small
ring of per-instance scratch buffers (`label_buf` and `fields_buf`
on `OneWireState`) to satisfy this without dynamic allocation.

### Threading

The loader serializes calls per handle. Different handles may run on
different threads, so do not share mutable state across instances
without your own synchronisation.

---

## Customising for your protocol

The most common path is:

1. **Edit the manifest.** Change `signals`, add `parameters`, change
   the decoder `id` and `display_name`. The id should be lowercase
   dot-separated and namespaced under your project — e.g.,
   `mycorp.lin` for a LIN bus decoder.
2. **Replace the timing thresholds.** The `*_FS` macros at the top of
   `onewire_decoder.c` are the only protocol-specific constants.
3. **Rewrite `ow_feed`.** The structure (track previous level,
   detect edges, classify pulse durations) generalises to most
   half-duplex single-wire and clocked-bus protocols.
4. **Update the transaction labels and fields-JSON.** The
   `format_simple` / `format_byte` helpers show the pattern.

When you're ready to publish, change the library name in `Makefile`
and `CMakeLists.txt`, and update this README to match.

---

## Troubleshooting

**"plugin reports ABI major X; host requires Y"**
You're built against an older or newer header than the WaveCrux
build you're running. Pull the matching `wavecrux_decoder.h` from
the open-core repo at the same commit as your WaveCrux build and
rebuild.

**"plugin returned zero decoders from register"**
Your `wavecrux_decoder_register` set `*inout_count = 0`. Set it to
the number of decoders you contribute (1 for this demonstrator).

**"manifest top-level value must be a JSON object"**
Your `manifest_json` is malformed. Validate it with `jq` or any JSON
linter. The most common mistake is a trailing comma or unescaped
quote.

**Status `loaded` but the decoder doesn't appear in the picker**
Check `Settings → Decoders → Plugins → Decoders:` — if it lists your
plugin's id, the picker should also list the decoder under
"User-Contributed". If the picker is filtered by tier or category,
confirm your manifest's `category` field is a valid value (see
`include/wavecrux_decoder.h` for the enum).

**Library loads but `create` returns NULL**
Check that your plugin can allocate enough memory. The demonstrator
allocates ~3 KB per instance.

**Decoder produces transactions but the timestamps look wrong**
Remember timestamps are in **femtoseconds** — multiply by
`1_000_000_000` to convert nanoseconds to fs, by `1_000_000_000_000`
to convert microseconds to fs. The `US_TO_FS` macro in the
demonstrator shows the conversion.

---

## See also

- [`include/wavecrux_decoder.h`](../../include/wavecrux_decoder.h)
  — full ABI reference.
- [`CONTRIBUTING.md`](../../CONTRIBUTING.md) — "Contributing a
  decoder plugin" section, including the ABI versioning policy.
- [`fixtures/onewire_basic.vcd`](fixtures/onewire_basic.vcd) — the
  reference fixture this README sends you to in step 6.
- [`fixtures/onewire_basic.expected_transactions.json`](fixtures/onewire_basic.expected_transactions.json)
  — the canonical decoder output. Compare against your build to
  verify correctness.
- [`tool/generate_onewire_fixture.dart`](../../tool/generate_onewire_fixture.dart)
  — regenerates both fixture files from a single source-of-truth
  Dart program.
- [`examples/decoder-plugin-demo-rust/`](../decoder-plugin-demo-rust/)
  — companion Rust port of this demonstrator. Same C ABI, idiomatic
  Rust authoring.
