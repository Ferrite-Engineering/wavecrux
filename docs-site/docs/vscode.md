# Use in VS Code

The **WaveCrux extension** opens waveforms in a VS Code editor tab, beside the RTL that produced them. It embeds the free, open-source WaveCrux viewer — no account, no license key, no separate download — and connects your editor to the WaveCrux, NetCrux, LintCrux and SimCrux desktop apps over [CXP](automation-and-collaboration.md#cxp).

It installs from the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=ferrite-engineering.wavecrux) and from [Open VSX](https://open-vsx.org/extension/ferrite-engineering/wavecrux), which is where Cursor, Windsurf, VSCodium and Theia install from. To install all four EDACrux extensions at once, install the [EDACrux Suite](https://marketplace.visualstudio.com/items?itemName=ferrite-engineering.edacrux) pack.

## What it does { #what-it-does }

- **Waveforms open as editor tabs.** Open a `.vcd`, `.fst`, `.ghw`, `.lxt` or `.lxt2` file from the Explorer and it opens in a WaveCrux tab; LXT and LXT2 convert to FST in memory each time they open, as they do in the [browser](files-and-sessions.md). Tabs split into editor groups, restore with the window, and follow your VS Code theme.
- **The Open Core analysis tools come with it:** the Open Core [protocol decoders](protocol-decoders.md#open-core-decoders) with their transaction table, [X-trace](analysis.md#x-trace), [waveform comparison](analysis.md#diff), [FSM visualization](analysis.md#fsm), [switching activity](analysis.md#switching-activity), [multi-signal pattern search](analysis.md#pattern-search), [cocotb log correlation](analysis.md#cocotb) and GTKWave `.gtkw` session import.
- **Signal values in your source.** Run **EDACrux: Toggle RTL Value Annotation** with a Verilog or VHDL file open, and the value of each signal at the waveform cursor appears inline in your source. It is off until you turn it on (`edacrux.rtlAnnotation.enabled`), and it only annotates names the design's stems index resolves exactly.
- **From a signal to its declaration.** With `edacrux.crossProbe.followWaveformSelection` on (it is off by default), selecting a signal in a waveform tab reveals its RTL declaration in the editor.

## Working with the desktop apps { #desktop }

Your VS Code window joins the suite's cross-probe network as **one** peer, however many of the EDACrux extensions you install:

- A desktop app can ask it to open a source file at a line, and the file opens in the editor.
- **EDACrux: Send Selection to Crux App** and **EDACrux: Highlight Selection in Crux App** send the identifier under your cursor to a running EDACrux app. With one app connected it goes there directly; with several you pick one.

Cross-probing works between apps on the same machine.

## What stays in the desktop app { #desktop-only }

- Pro and Enterprise features — such as the [Debug Advisor](analysis.md#debug-advisor), [SVA visualization](analysis.md#sva), [collaborative viewing](automation-and-collaboration.md#collaborative-viewing) and the Pro Stage widgets — are not in the extension.
- Multi-tab workspaces, the [Stage panel](stage.md), [WCP remote control](automation-and-collaboration.md#wcp) and [interactive VCD](automation-and-collaboration.md#interactive-vcd) are desktop features.
- FSDB files are refused with an explanation: reading them needs Synopsys libraries that cannot be redistributed.

## Commands, settings and telemetry { #reference }

The extension's listing on the [Marketplace](https://marketplace.visualstudio.com/items?itemName=ferrite-engineering.wavecrux) has the full list of commands and settings. The extension sends usage statistics only while VS Code's own telemetry setting is on, and it checks that setting each time rather than once at startup.
