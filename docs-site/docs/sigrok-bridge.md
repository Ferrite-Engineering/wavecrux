# Sigrok bridge

The Sigrok bridge is an optional, separately downloaded add-on that brings the 130+ community-maintained `libsigrokdecode` protocol decoders into WaveCrux. Once installed, those decoders appear in the decoder picker as `sigrok.*` entries, loaded through the same [decoder plugin](authoring-custom-decoders.md) interface as any other plugin.

!!! warning "What this is — and is not"

    The bridge brings the libsigrokdecode protocol **decoders** into WaveCrux. It is **not** a live hardware-capture tool — WaveCrux does not acquire signals from a logic analyzer. You decode signals that are **already loaded** from a VCD, FST, or GHW file. To capture from hardware, use a separate tool such as [PulseView](https://sigrok.org/wiki/PulseView) or `sigrok-cli`, save the result as VCD, then open it in WaveCrux and apply a sigrok decoder to it.

!!! warning "Bridge version"

    Decoding needs a bridge release newer than v0.1.1. Releases v0.1.0 and v0.1.1 load and list their `sigrok.*` decoders, but they release each decoded transaction's text before WaveCrux reads it, so a decode produces no usable transactions.

## How it works and why it's separate { #how-it-works }

libsigrokdecode is licensed under the GPL, which is not license-compatible with the WaveCrux core. The bridge is therefore **process-isolated and distributed separately**, and no GPL code is linked into WaveCrux itself.

The bridge is two pieces:

- A small **shim plugin** that WaveCrux loads in-process.
- A separate **subprocess** that hosts libsigrokdecode and Python, and talks to the shim over a pipe.

The bridge's GPLv3+ notice is shown on its card in **Settings → Extensions → Decoder Plugins**. Because the bridge is GPLv3+, its complete source is published in the [same repository](https://github.com/Ferrite-Engineering/wavecrux-sigrok-bridge) as the release archives — the source always travels with the binary.

!!! note "Desktop only"

    The Sigrok bridge runs on the desktop builds — Linux, macOS, and Windows. It is not available on the web app or on mobile, which do not load native plugins.

## Requirements { #requirements }

The bridge needs **Python 3.10 or newer** and a **libsigrokdecode runtime**. How you provide those depends on your platform.

**Linux (Debian/Ubuntu)**

```bash
sudo apt install libsigrokdecode4 libsigrokdecode-dev sigrok-cli
```

**Linux (Fedora)**

```bash
sudo dnf install libsigrokdecode libsigrokdecode-devel
```

**macOS (Homebrew)**

```bash
brew install libsigrokdecode
```

**Windows**

No separate system install is required, but the Windows release archive ships a built-in **mock backend** covering only the five reference decoders (1-Wire, JTAG, PWM, DMX512, Modbus) — there is no `apt`/Homebrew source for libsigrokdecode on Windows yet. To get the full 130+ decoder corpus on Windows today, build the bridge from source against a manually installed libsigrokdecode — see `HOW_TO_BUILD.md` in the bridge repository. Linux and macOS archives ship the real libsigrokdecode backend (install the runtime above) and expose the full corpus.

## Install { #install }

1. Download the release for your OS and architecture from the [`wavecrux-sigrok-bridge` releases page](https://github.com/Ferrite-Engineering/wavecrux-sigrok-bridge/releases) — Linux x86_64, macOS arm64 or x86_64, or Windows x86_64.
2. Verify the download's SHA-256 against the published `.sha256` file.
3. Extract the archive.
4. Copy the shim library into a decoder plugin directory — the platform default, which **Open plugin directory** in **Settings → Extensions → Decoder Plugins** reveals, or any directory you add there (see [Building and installing](authoring-custom-decoders.md#install)). The shim file is `libwavecrux_sigrok_bridge_shim.so` on Linux, `libwavecrux_sigrok_bridge_shim.dylib` on macOS, and `wavecrux_sigrok_bridge_shim.dll` on Windows. WaveCrux discovers plugins by directory, not by file name.
5. Place the bridge subprocess executable (`wavecrux-sigrok-bridge`, or `wavecrux-sigrok-bridge.exe` on Windows) where the shim can find it — next to the shim (recommended), anywhere on your `PATH`, or at an absolute path named by the `WAVECRUX_SIGROK_BRIDGE` environment variable (checked first).
6. Restart WaveCrux, or click **Reload plugins**.

!!! note "macOS — first launch"

    The macOS bridge binaries are ad-hoc signed but not Apple-notarized, so Gatekeeper quarantines them on download. After extracting, clear the quarantine flag once — `xattr -dr com.apple.quarantine <extracted-folder>` — or right-click each binary and choose *Open* the first time.

## Verify it loaded { #verify }

After you restart, open **Settings → Extensions → Decoder Plugins** (accepting the one-time native-code acknowledgment if you have not already). The bridge is listed as **WaveCrux SigRok Bridge** with:

- status **Loaded**,
- its ABI version, and
- its GPLv3+ notice.

The decoder picker now includes the `sigrok.*` decoders. The bridge's **Enabled** toggle in the same panel switches all `sigrok.*` decoders off at once without uninstalling the bridge.

## Decode a signal with sigrok { #decode }

Using a sigrok decoder is identical to using a [native WaveCrux decoder](protocol-decoders.md):

1. Open a VCD, FST, or GHW file.
2. Open the decoder picker.
3. Choose a `sigrok.*` decoder — for example `sigrok.jtag`.
4. Bind its required signals to signals in your waveform, and set any of the decoder's options in the same dialog.

The decoded annotations appear in the transaction lane and table like a native decoder's. The option values you set are passed to libsigrokdecode as that decoder's options. When a bound sample is `X` or `Z`, the bridge emits a glitch annotation and skips that sample.

## Available decoders { #decoders }

On Linux and macOS the bridge advertises the full set of 130+ libsigrokdecode decoders. (On Windows, the release archive's mock backend exposes only the five reference decoders below — see [Requirements](#requirements).) The reference decoders validated at release are:

- 1-Wire (`sigrok.onewire` from the mock backend; `sigrok.onewire_link` and `sigrok.onewire_network` from libsigrokdecode)
- JTAG
- PWM
- DMX512
- Modbus

To list every advertised decoder, run the subprocess directly:

```bash
wavecrux-sigrok-bridge --list-decoders
```

## Troubleshooting { #troubleshooting }

If no sigrok decoders appear in the picker:

1. Run `wavecrux-sigrok-bridge --list-decoders` to confirm the subprocess works on its own.
2. Make sure the executable is next to the shim, on your `PATH`, or named by the `WAVECRUX_SIGROK_BRIDGE` environment variable.
3. Confirm **Settings → Extensions → Decoder Plugins** shows the bridge as **Loaded**, and that plugin loading and the bridge's **Enabled** toggle are on.

!!! tip "See also"

    For how decoders bind and render in WaveCrux, and the full native decoder catalog, see [Protocol decoders](protocol-decoders.md). For the plugin interface the bridge is built on, see [Authoring custom decoders](authoring-custom-decoders.md).
