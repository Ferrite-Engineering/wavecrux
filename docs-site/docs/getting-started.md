# Installation & first launch

WaveCrux runs natively on desktop and mobile and in the browser, all driven by the same Rust parsing engine. There is no account to create, no license key to enter, and nothing to activate before you open your first waveform. This page covers how to get the app on each platform and how to load a trace once it is running.

## Platforms { #platforms }

The same `wellen` Rust engine parses on every platform — native FFI on desktop and mobile, WebAssembly on the web — so VCD, FST and GHW open the same way everywhere. A trace that opens on your laptop opens identically on your phone or in a browser tab.

| Platform | Versions | How you get it |
|---|---|---|
| Linux | x86_64 | Native binary from the [downloads page](https://wavecrux.app/download). No webview wrapper. |
| macOS | Universal, 12.0+ (Intel + Apple Silicon) | Native binary from the [downloads page](https://wavecrux.app/download). |
| Windows | 10 / 11, x86_64 | Native binary from the [downloads page](https://wavecrux.app/download). |
| iOS / iPadOS | 16+ | Native app from the App Store. |
| Android | 7.0+ (API 24+) | Native app from the Play Store. |
| Web | Any WebAssembly-capable browser | Open [app.wavecrux.app](https://app.wavecrux.app) — nothing to install. |

Desktop and mobile builds are native binaries, not webview wrappers. Installers for every desktop platform live on the [download page](https://wavecrux.app/download), and a SHA-256 checksum is published alongside each one so you can verify what you downloaded before you run it.

!!! note "No activation step"

    You do not need an account or a license key to begin, on any build: the free Open Core viewer opens waveforms with no key, no account and no network call. Only the Pro and Enterprise features ask for a key. See [Tiers & licensing](licensing.md) for how tiers and license keys work.

!!! warning "Web requires WebAssembly"

    The browser build compiles the same Rust engine to WebAssembly, with full VCD, FST, and GHW parity — it is not a stripped-down demo. If the WebAssembly module fails to load, the canvas shows a "WebAssembly is required" message; there is no fallback parser.

## First launch { #first-launch }

On first launch, with nothing open, the canvas shows an empty-canvas state listing your **Recent files** and **Recent workspaces** alongside **Open File…**, **Open Sample Waveform**, and **Open Workspace…** buttons. You do not need a file loaded to explore the app: the toolbar, status bar, menu bar, command palette, and Settings are all reachable from the empty canvas.

WaveCrux is localized in English, Simplified Chinese, Japanese, and Korean. The **Language** picker lives in **Settings → Appearance**.

## Open your first waveform { #open-first-waveform }

1. Choose **File → Open File**, or press ++cmd+o++ / ++ctrl+o++. On macOS, Windows and Linux you can instead drag the trace from your file manager onto the WaveCrux window — see [Dropping files onto the window](files-and-sessions.md#drop).
2. Select a trace. The format is auto-detected on open — you do not pick a format.
3. The viewer parses the file and shows the signal hierarchy. From there, add signals to the canvas and start navigating.

Supported inputs:

| Format | How it loads |
|---|---|
| VCD, FST, GHW | Parsed natively, on every platform. |
| Legacy GTKWave LXT / LXT2 | Converts to FST on open, on every platform. Desktop and mobile cache the result as a sibling `.fst`; the browser converts again on every open. |
| Synopsys FSDB | Desktop only. Converts on open with your own `fsdb2vcd` (and `vcd2fst`, when it is also on `$PATH`) — available only when that user-supplied tool is on `$PATH`. |

The full format coverage — including auto-reload behavior, session import, and export — is documented on [Files & sessions](files-and-sessions.md).

!!! tip "No install required"

    To try WaveCrux without downloading anything, open [app.wavecrux.app](https://app.wavecrux.app) in your browser. The web build runs the same Rust engine as the desktop app, so it opens the same VCD, FST, GHW, LXT and LXT2 files.

## On mobile { #on-mobile }

On iOS, iPadOS, and Android the usual way to open a trace is **Open with WaveCrux** — from Files, Mail, a chat app, a cloud drive, or AirDrop. The system file picker, with iCloud Drive, Google Drive and other document providers, is the other path. File-type associations are registered for `.vcd`, `.fst`, `.ghw`, `.lxt`, `.lxt2` and `.wavecrux` (and, on Android, `.wavecruxpack`), so those files offer WaveCrux directly. A received file is copied into the app's own storage before it opens.

Mobile devices have tighter memory budgets than desktops. A large-file warning appears before loading above a threshold — 100 MB on phones and 250 MB on tablets — and a memory guard watches the app's memory use and the system's memory-pressure callbacks, unloading signal data that is loaded but not shown in the signal list to keep the app within the device budget.

## Usage statistics and privacy { #telemetry }

WaveCrux can send anonymous usage and error counts — which features get used, and how often the app hits an error it did not handle — never your files, your designs, file paths, or anything that identifies you. An error is counted by its kind alone (for example, a state error in the widgets library), never with its message or stack trace. The exact field list, and the list of things that are never collected, is published at [edacrux.app/telemetry](https://edacrux.app/telemetry).

- **You choose on first launch.** A one-time **Help make WaveCrux better** dialog explains what is collected and holds a **Send anonymous usage statistics** switch; **Continue** records your choice. The switch starts **on**, except where your device's region is in the EEA, the UK, Switzerland or South Korea, where it starts **off**. Nothing is sent before you have answered — if you quit without choosing, you are asked again on the next launch.
- **Change it any time** in **Settings → Privacy → Send anonymous usage statistics**.
- **Your organization may decide for you.** The `telemetry` key in an organization's [policy file](https://edacrux.app/policy-reference) can turn usage statistics off, or on, for every seat; where it decides, WaveCrux shows neither the dialog nor the Privacy section. In the regions above, an organization's "on" still leaves the choice to each person.

## Reporting issues { #reporting-issues }

The fastest way to get something fixed is the built-in issue reporter, which is open to every tier — there is no badge on it and no license check in front of it. Open it from **Help → Submit Issue…**, the command palette, or the **Report Issue** button in the About box.

1. Give the issue a short summary describing what went wrong.
2. Choose what to attach. WaveCrux assembles the diagnostic context for you — **App & Environment** (version and build, platform and OS, screen DPI, locale); **Session State** (counts and format names only — open tabs, file formats, signal counts, active decoders); a [diagnostics snapshot and recent log](interface.md#logs); and, on desktop, an optional **Screenshot** of the app window, saved to a file so you can attach it. Each category is a toggle, and a live preview shows exactly what will be sent, so nothing leaves your machine that you have not seen. File paths and file contents are deliberately left out. The log is always captured in full regardless of your [log-verbosity setting](interface.md#log-verbosity), so you never have to change a setting before reproducing a problem.
3. Submit. WaveCrux copies the report to your clipboard and opens a new issue on the public GitHub tracker — with the body pre-filled when the report is short enough to fit in the link; otherwise paste it from the clipboard. Drag in the saved screenshot if you captured one, then post.

!!! tip "Just the numbers"

    For a performance problem rather than a bug, the App Diagnostics dialog (++cmd+shift+m++ / ++ctrl+shift+m++) has a **Copy Full Diagnostics Report** button that puts a complete memory and frame-stats snapshot on your clipboard to attach as well — see [the interface tour](interface.md#diagnostics).

!!! note "Next steps"

    With a trace open, take the tour of [the interface](interface.md), learn the details of [files & sessions](files-and-sessions.md), and then move on to [navigating & measuring](navigating-waveforms.md) to start reading waveforms in earnest.
