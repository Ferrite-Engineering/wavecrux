# Welcome to WaveCrux

WaveCrux is a modern waveform viewer for hardware engineers — VCD, FST, and GHW on desktop, mobile, and the web, all driven by the same Rust parsing engine. This guide is written for people who already read waveforms for a living: it is precise about what each feature does, the file formats and protocols involved, and the keyboard you will actually use.

!!! tip "New here?"

    Start with [Installation & first launch](getting-started.md), then take the [interface tour](interface.md). If you are migrating from GTKWave, jump straight to [Files & sessions](files-and-sessions.md) — your `.gtkw` session files import directly. Prefer to learn by doing? The [Cookbook](cookbook.md) walks through complete workflows step by step.

## One app, four tiers { #tiers }

WaveCrux ships as a single application. The free **Open Core** viewer is fully featured on its own; **Pro** and **Enterprise** add capability on top without changing anything you already use, and **Education** grants the Pro feature set free to verified students and educators. This documentation set covers all four. Wherever a feature requires a paid tier, you will see a badge next to its name:

- **Open Core** — no badge. Free and open. No account, no license key, no time limit.
- <span class="tier tier-pro">Pro</span> Advanced protocol decoders, the curated Stage widget pack and Pro boards, the Debug Advisor, SystemVerilog assertion visualization, the Pro translator pack, and the AI Waveform Assistant.
- <span class="tier tier-enterprise">Enterprise</span> Hosting collaborative viewing sessions (from 1.1, joining one is free in every edition), plus organization-wide settings from a policy file, an audit log, and the Ethernet RGMII decoder and PCAP-to-VCD conversion.
- <span class="tier tier-edu">EDU</span> Every Pro feature, free for verified students and faculty, non-commercial.

!!! info "What the badges mean"

    Open Core is free: no account, no key and no time limit. Pro and Enterprise features need a license key, and the badges throughout the app and these docs tell you which is which. See [Tiers & licensing](licensing.md) for the full picture, including the Education tier and how the license key system works.

## How this guide is organized { #map }

- [Installation & first launch](getting-started.md) — Download for macOS, Linux, and Windows; the web app; iOS and Android. Open your first waveform.
- [The interface](interface.md) — The toolbar, docks, canvas, value column, status bar, command palette, tabs, split panes, diagnostics and logs.
- [Appearance & themes](appearance-and-themes.md) — Built-in light and dark themes, the brightness toggle, per-token color tweaks, and the `.crux-theme.json` pack format.
- [Files & sessions](files-and-sessions.md) — Supported formats, opening files, auto-reload, GTKWave import, workspaces, recovery, and export.
- [Navigating & measuring](navigating-waveforms.md) — Zoom and pan, cursors and delta measurement, 26 named markers, and the full keyboard reference.
- [Keyboard & mouse reference](keyboard-mouse.md) — Every mouse, trackpad, and touch gesture on the canvas and signal tree — cursors, pan and zoom, time-range and signal selection.
- [Working with signals](working-with-signals.md) — The hierarchy browser, search, grouping, colors, all 12 value-display formats, analog rendering, and GTKWave translate filters.
- [Translators](translators.md) — Reinterpret a value: struct/bitfield child rows, custom translators, RISC-V disassembly, and the Pro pack.
- [Analysis & debug](analysis.md) — Diff, X-trace, switching activity, pattern search, FSM visualization, cocotb correlation, RTL source annotation, Debug Advisor, SVA.
- [Annotations](annotations.md) — Write notes on the waveform — callouts, arrows and time bands anchored to a signal and a tick, so they survive a reload and flag themselves when the design drifts. Plus the walkthrough, and the `.wavecruxpack` bundle that sends an annotated trace to someone without your dump.
- [AI assistant *(experimental)*](ai-assistant.md) — A bring-your-own-key AI assistant that reads your signals with you: Explain Selection, and the Pro agentic AI Waveform Assistant, every answer grounded in signal data you can click to verify.
- [Protocol decoders](protocol-decoders.md) — How decoders bind and render, plus the full Open Core, Pro, and Enterprise decoder catalog.
- [The Stage panel](stage.md) — Bind signals to live animated widgets — built-in primitives, FPGA boards, and the curated Pro pack.
- [Authoring Rive widgets](authoring-rive-widgets.md) — Exactly what a Rive file and its manifest need to run as a Stage widget.
- [Authoring custom decoders](authoring-custom-decoders.md) — Write your own protocol decoder against the open C ABI, or extend instruction decoding with TOML encoding tables.
- [Sigrok bridge](sigrok-bridge.md) — Download, install, and use the optional bridge that brings libsigrokdecode protocol decoders into WaveCrux.
- [Automation & collaboration](automation-and-collaboration.md) — The WCP remote-control API, interactive VCD over a pipe, cross-probing (CXP), and shared sessions.
- [Administration <span class="tier tier-enterprise">Enterprise</span>](administration.md) — For the person deploying WaveCrux across a fleet: org-wide signal groups and decoder defaults, theme packs and session templates from your own share, the decoder-plugin allowlist by content hash, the audit events WaveCrux records, and the limits of collaborative viewing.
- [Cookbook](cookbook.md) — Task-driven recipes that put the tools together — find a bug by diffing runs, decode a bus, measure timing, build a Stage dashboard.
- [Educational packs](educational-packs.md) — Ready-to-teach lab curriculum — HDL source, fixtures, handouts, and instructor notes — all on Open Core.

## Conventions used in this guide { #conventions }

- Keyboard shortcuts are written for both platforms, macOS first: ++cmd+o++ / ++ctrl+o++. Where only one key is shown, it applies to all platforms.
- `Monospace` marks file names, formats, signal paths, and anything you type; **bold** marks menu items, buttons and settings as they are labelled in the app.
- A <span class="tier tier-pro">Pro</span> or <span class="tier tier-enterprise">Enterprise</span> badge beside a heading means everything under it requires that tier.
- Screens differ by device class — phone, tablet, and desktop. Where layout matters, the text says so.
- A **Known issue** box marks behaviour that does not work yet in current builds.

!!! note "Quick links"

    [Download WaveCrux](https://wavecrux.app/download) · [Try it in your browser](https://app.wavecrux.app) · [Open source](https://edacrux.app/open-source) · [Pricing](https://wavecrux.app/pricing)
