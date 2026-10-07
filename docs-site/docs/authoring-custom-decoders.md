# Authoring custom decoders

WaveCrux's built-in decoders are not a closed set. You can write your own protocol decoder in any language that produces a native shared library, drop it into a directory, and it appears in the decoder picker alongside the built-in decoders — and runs at native speed. This page is the full contract: the C ABI, the two-call register pattern, the four lifecycle callbacks, how signal values reach your code, how timestamps work, who owns which strings, and where to install the finished plugin. It also covers the other way to teach WaveCrux something new without writing code: [ISA encoding tables](#isa-tables) for instruction-trace decoding.

!!! tip "Free & Open Core"

    The decoder plugin interface is part of Open Core — free, on every tier, no license key required. The C ABI header (`include/wavecrux_decoder.h`) and two complete reference implementations (one in C, one in Rust, under `examples/`) ship in the open-core source, so you start from working code. Only the *curated Pro decoder pack* (AXI4 full, USB 2.0, PCIe TLP, Ethernet, JTAG, …) is paid; the *capability* to author your own is not.

## How plugin decoders work { #how-it-works }

A plugin decoder is a native shared library — a `.so` (Linux), `.dylib` (macOS), or `.dll` (Windows) — that exports a small set of C functions. At startup (and on demand via **Reload plugins**), WaveCrux scans its plugin directories, opens each library, checks its ABI version, and asks it to register the decoders it contributes. Registered decoders then behave like built-ins: they appear in the decoder picker (under **User Plugins** unless the manifest names another category), take signal bindings, and emit transactions overlaid on the waveform.

Loading is **desktop-only** — Linux, macOS, and Windows. iOS, Android, and the web build do not load native plugins, and the Decoder Plugins settings are not shown there.

## Plugin security { #security }

!!! warning "Plugins run native code"

    A decoder plugin is unsandboxed native code running with your full process privileges — it can read any file you can read, open network connections, and call any operating-system API. Before WaveCrux scans for plugins it shows a one-time safety acknowledgment, **Plugins run as native code**, that you must accept (**I understand, continue**) or decline (**Disable plugin loading**). Only install plugins you trust or built yourself. A master switch and per-plugin **Enabled** toggles live in **Settings → Extensions → Decoder Plugins**.

Every plugin is loaded in isolation: a library that fails to open, declares the wrong ABI, is missing a required symbol, ships a malformed manifest, or registers a duplicate decoder id is logged with a specific diagnostic and *skipped*. One bad plugin never blocks startup or disturbs the others.

On a managed install, an organization can go further and allow only approved plugins by content hash; any other plugin shows **Not approved** and cannot be enabled from Settings. See [Administration](administration.md#plugins).

## The two entry points { #entry-points }

Every plugin exports two C functions:

```c
uint32_t wavecrux_decoder_abi_version(void);
int32_t  wavecrux_decoder_register(WcDecoderDef* out_defs,
                                   size_t* inout_count);
```

`wavecrux_decoder_abi_version()` returns the macro `WAVECRUX_DECODER_ABI_VERSION` from `wavecrux_decoder.h`, encoded as `(major << 16) | minor`. The current ABI is **1.1**. The loader rejects any plugin whose **major** version differs from the host's; **minor** is backward-compatible, so a 1.0 plugin runs fine in a 1.1 host and trailing struct fields the plugin doesn't set default to zero.

`wavecrux_decoder_register()` uses a **two-call pattern** so the host can size its buffer:

1. **First call — count.**

    The host calls with `out_defs == NULL` and `*inout_count == 0`. Write the number of decoders you contribute into `*inout_count` and return `WC_DECODER_NEED_MORE_SLOTS` (or `WC_DECODER_OK`).

2. **Second call — fill.**

    The host calls again with a buffer large enough for that many `WcDecoderDef` entries. Populate the array, set `*inout_count` to the number actually written, and return `WC_DECODER_OK`. Return `WC_DECODER_ERR` on an internal failure and the plugin is skipped.

Each `WcDecoderDef` carries the decoder's `id` (by convention lowercase and namespaced, e.g. `examples.onewire`), `display_name`, a JSON `manifest_json`, and the four lifecycle function pointers below. Optional ABI 1.1 symbols (`wavecrux_decoder_plugin_name`, `wavecrux_decoder_plugin_description`) let a plugin that contributes several decoders present one name and description in the Settings panel.

### The manifest { #manifest-json }

`manifest_json` is a JSON object:

| Key | Meaning |
|---|---|
| `signals` | Array of required bindings: `{ "name", "bit_width"?, "description"? }`. |
| `optional_signals` | Array of optional bindings, same shape. |
| `parameters` | Array of `{ "name", "kind", "default"?, "description"?, "display_name"?, "enum_values"?, "enum_labels"? }`, where `kind` is `bool`, `int`, `enum` or `string`. `enum_labels` is an object keyed by value, `{ "tx": "Downstream", "rx": "Upstream" }`, or an array with one label per `enum_values` entry, in the same order. |
| `description` | Optional text shown in the picker. |
| `category` | Optional picker category; anything unrecognized falls back to **User Plugins**. |

## The four lifecycle callbacks { #lifecycle }

Each registered decoder exposes four callbacks the host drives in order:

| Callback | When | Purpose |
|---|---|---|
| `create(config_json)` | Once, when the decoder instance is created. | Allocate per-instance state; return `NULL` on failure. |
| `feed(handle, sample, out_tx, &count)` | Once per sample the host feeds. | Decode incrementally; emit zero or more transactions per call. |
| `flush(handle, out_tx, &count)` | Exactly once at end-of-stream. | Emit any transaction still pending. |
| `destroy(handle)` | Exactly once, at the end. | Free per-instance state. |

`feed` and `flush` write through a host-provided array of `*inout_count` transactions; to emit more than fit, return `WC_DECODER_NEED_MORE_SLOTS` and the host retries with a larger buffer. Any other non-zero return is fatal for that instance.

The host serializes the instance configuration as `{"decoder_id": "…", "signal_bindings": {…}, "parameters": {…}, "options": {…}}` and passes it to `create` as a UTF-8 NUL-terminated JSON string. `decoder_id` is the `id` of the decoder being created, so a plugin that registers several decoders through one `create` can tell them apart; `options` carries the same values as `parameters`. Most decoders read only the parameters — the host has already used your manifest to pack the bound signals into each sample in declaration order, so you read values by position, not by name.

!!! note "Threading"

    The host serializes all calls on a single handle, so an instance never sees concurrent `feed`/`flush` calls. Different handles may run on different threads, though — do not share mutable state across instances without your own synchronization.

## Reading signal values { #reading-signals }

Each `feed` call receives a `WcSample` whose `bits_ptr` packs every bound signal's value at that timestamp. The encoding is **two buffer bits per signal bit**, LSB-first:

| Buffer bit | Meaning |
|---|---|
| Even (offset 0, 2, 4 …) | Level — `0` or `1`. |
| Odd (offset 1, 3, 5 …) | Unknown flag — set if the source sample was `X` or `Z`. |

For a 1-bit signal, `bits_ptr[0] & 1` is the level and `(bits_ptr[0] >> 1) & 1` is the unknown flag. For a multi-bit binding, signal bit *i* lives at buffer-bit `2*i` (level) / `2*i + 1` (unknown). When several bindings are declared, the declaration order sets the packing order — required signals first, then optional ones: the first binding's bits start at offset 0, the next at `2 × binding[0].bit_width`, and so on. Mask the unused high bits of the final byte.

!!! note "Always check the unknown flag"

    Real captures contain `X` and `Z`. A decoder that reads only the level bit will happily decode garbage out of an undriven bus. Check the unknown flag and treat unknown samples as a hold or a protocol error, the way real hardware would.

## Timestamps are femtoseconds { #timestamps }

Every timestamp the host passes you — and every timestamp you put on an emitted transaction — is in **femtoseconds**, not ticks and not the file's native timescale. The host derives the conversion from the file's timescale before calling you, so your decoder logic is timescale-independent.

When you port timing thresholds from a datasheet, convert up front: multiply nanoseconds by 1,000,000 and microseconds by 1,000,000,000 to reach femtoseconds. A transaction whose timestamps look off by orders of magnitude is almost always a missing unit conversion here.

WaveCrux 1.0.0 converted the timestamps it passed in but not the ones it got back, so on any file whose timescale is coarser than 1 fs it drew a plugin's transactions too late by the fs-per-tick factor (1,000× for a 1 ps file), usually past the end of the trace. WaveCrux 1.0.1 converts both ways. A plugin that divided its own output to work around 1.0.0 should stop doing so on 1.0.1.

## Who owns which strings { #strings }

The ABI splits string ownership into two simple rules:

- **Definition strings are borrowed for the library's lifetime.** The `id`, `display_name`, and `manifest_json` you put on a `WcDecoderDef` are held by the host for as long as the plugin is loaded (until shutdown or **Reload plugins**). Static string literals in `.rodata` satisfy this trivially.
- **Per-transaction strings are owned until the next call.** The `label` and `fields_json` on each emitted `WcTransaction` must stay valid until the *next* call on the same handle. A small ring of per-instance scratch buffers satisfies this with no dynamic allocation — the reference decoders do exactly that.

Set `is_error` on a `WcTransaction` to flag it as a protocol violation.

## Building and installing { #install }

Build the reference C decoder with `make` (Linux/macOS) or CMake (all three platforms). Then place the resulting library in a plugin directory. WaveCrux searches, in order:

1. Every absolute path in the `WAVECRUX_DECODER_PATH` environment variable (colon-separated on Unix, semicolon-separated on Windows; relative entries are ignored).
2. Directories you add with **Add directory…** in **Settings → Extensions → Decoder Plugins**.
3. The platform-default plugin directory, `wavecrux/decoders` (`WaveCrux\decoders` on Windows) inside WaveCrux's application-support folder. **Open plugin directory** in the same panel reveals it.

Then:

1. **Acknowledge the safety prompt.**

    The first time, accept the one-time native-code acknowledgment.

2. **Load it.**

    Restart WaveCrux, or click **Reload plugins** in **Settings → Extensions → Decoder Plugins** to re-scan without restarting.

3. **Confirm it loaded.**

    **Discovered plugins** lists the library with status **Loaded**, its ABI version, and the decoders it contributed. Any failure shows a specific status and message instead.

4. **Use it.**

    Open a capture, pick your decoder in the decoder picker (++cmd+shift+d++ / ++ctrl+shift+d++), bind its signals, and add it.

## The C and Rust references { #references }

The open-core source ships two complete, working demonstrators under `examples/` that both implement the same passive 1-Wire (Maxim/Dallas) bus decoder — chosen because it rides a single `dq` line, has cleanly bounded RESET / PRESENCE / BYTE transactions, and isn't already a built-in. Copy one, swap in your own protocol logic and manifest id, and you have a finished plugin.

- **C reference** (`examples/decoder-plugin-demo`) — a single `onewire_decoder.c` with a Makefile and CMake build, a reference VCD fixture, and the expected-transactions JSON. The shortest path to a working `.so`/`.dylib`/`.dll`.
- **Rust reference** (`examples/decoder-plugin-demo-rust`) — an idiomatic `cdylib` port across the identical C ABI boundary. Memory-safe state, enum-typed transactions, no manual string-lifetime bookkeeping.

Both include their own walkthrough README, and the open-core test suite builds the C reference and round-trips the 1-Wire fixture through the real loader whenever a C toolchain is available — so the reference is not just illustrative.

!!! note "Pull the header matching your build"

    Build against the `wavecrux_decoder.h` from the open-core source at the same version as the WaveCrux build you'll run. An ABI-major mismatch is the most common first-time load failure, and it almost always means the header and the app drifted apart.

## Troubleshooting { #troubleshooting }

When a plugin won't load or behaves oddly, the Decoder Plugins panel and the [logs](interface.md#logs) name the cause. The common ones:

| Symptom | Cause |
|---|---|
| **ABI version mismatch** | The plugin's major ABI differs from the host. Rebuild against the matching header. |
| **Missing entry point** | `wavecrux_decoder_abi_version` or `wavecrux_decoder_register` isn't exported. |
| **Invalid manifest** | The `manifest_json` isn't a valid JSON object, or an entry is malformed (missing `name`, non-integer `bit_width`, unknown parameter `kind`). |
| **Load failed** | The library could not be opened, or registration failed; the message says which. |
| **Disabled** / **Not approved** | You switched it off, or the organization's policy does not list its hash. |
| No decoders from the plugin | `register` left `*inout_count` at 0. Set it to your decoder count on the first call. |
| `create` returns NULL | Per-instance allocation or configuration parsing failed. |
| Timestamps look wildly off | A missing femtosecond conversion — see [Timestamps](#timestamps). |

## ISA encoding tables { #isa-tables }

Instruction-trace decoding does not need a plugin at all. The **RISC-V Instruction Trace** decoder and the RISC-V [instruction translator](translators.md#riscv) read **TOML encoding tables** — the bundled RISC-V sets plus any you add — so describing an instruction set is authoring a table, not writing code. The intended uses are extending a RISC-V core (custom instructions in the `custom-0`…`custom-3` opcode space, for example) and replacing a bundled set.

- **Where they load from.** **Settings → Extensions → ISA encoding tables → Add directory…** (below Decoder Plugins), plus any directories named in the `WAVECRUX_ISA_PATH` environment variable. Every `*.toml` directly inside a directory is loaded; subdirectories and symbolic links are not followed, and paths must be absolute. Desktop builds only — the browser and mobile builds use the bundled tables.
- **When they take effect.** Tables are composed **at launch**, so restart WaveCrux after adding a directory. The panel reports straight away how many tables parsed and lists any that failed, with the offending key.
- **How collisions resolve.** A table is keyed by its **file name**: a file named `RV32I.toml` replaces the bundled RV32I on purpose. A table with a new name is composed after the bundled sets, and when an encoding matches more than one set the last match wins — so your custom instruction takes precedence over an overlapping base encoding.
- **What the decoder consults.** Only tables with `width = 32`; 16-bit compressed encodings go in the low half of a 32-bit word.

The schema is the JKU `instruction-decoder` format, with stricter checks: a known radix, mapping types that exist, and field slices that account for every bit of the word. The single most common mistake is reading `top` / `bot` as positions in the instruction word — they are positions in the decoded part's *value*, and slices tile the word most-significant-bit first in declaration order. The complete format reference, with a minimal worked table, is `docs/ISA_TABLE_AUTHORING.md` in the open-core source.

!!! note "Related"

    For the built-in and Pro decoder catalogs and how decoding works at the UI level, see [Protocol decoders](protocol-decoders.md). For 130+ community decoders without writing any code, see the [Sigrok bridge](sigrok-bridge.md). To drive a custom Stage widget from your signals, see [Authoring Rive widgets](authoring-rive-widgets.md).
