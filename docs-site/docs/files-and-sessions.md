# Files & sessions

WaveCrux opens the waveform formats you already have on disk and auto-detects each one when you open it — no manual format selection. This page covers the supported input formats and how each loads, opening and auto-reloading files on desktop and mobile, the human-readable `.wavecrux` and `.wavecrux-workspace` session files, importing GTKWave `.gtkw` sessions, and exporting.

## Input formats { #input-formats }

Format is detected automatically when you open a file. Native formats are parsed in place by the wellen Rust engine on every platform; the remaining formats load through a conversion step, described below.

| Format | Extension | How it loads |
|---|---|---|
| VCD | `.vcd` | Native on every platform via the wellen Rust engine. |
| FST | `.fst` | Native on every platform via the wellen Rust engine — read natively, not converted. |
| GHW | `.ghw` | Native on every platform via the wellen Rust engine — read natively, not converted. |
| LXT (GTKWave legacy) | `.lxt` | The original 2003 streaming GTKWave format. Converts on open via the clean-room `lxt2fst` Rust crate, on every platform. Desktop and mobile cache the result as a sibling FST so re-opens are fast (in the app's cache folder when the file's folder is read-only); the browser converts in memory on every open. |
| LXT2 (GTKWave legacy) | `.lxt2` | Converts on open the same way as LXT, with the same caching. Good for years of pre-FST captures on disk. |
| FSDB (Synopsys) | `.fsdb` | Desktop only, conversion only. If Synopsys's `fsdb2vcd` is on `$PATH`, WaveCrux asks before converting it on open — to FST when GTKWave's `vcd2fst` is also on `$PATH`, otherwise to VCD — and keeps the result next to the FSDB. There is no native FSDB reader — the format is proprietary Synopsys IP. The browser build explains this and does not open FSDB. |
| Interactive VCD | `.vcd` (stream) | Desktop only. WaveCrux reads VCD from stdin or a named pipe while a simulation runs; the canvas updates as the stream arrives. |

!!! note "Interactive VCD"

    The streaming path is for driving WaveCrux from a running simulation. Setup, the named-pipe workflow, and the remote-control API are documented on [Automation & collaboration](automation-and-collaboration.md).

## Opening and reloading files { #opening }

Open a waveform with **File → Open File** or ++cmd+o++ / ++ctrl+o++. The format is detected from the file itself, so the same command handles every input type above, as well as `.wavecrux` sessions and `.wavecruxpack` share bundles. On desktop you can also pass files on the command line, one tab per file. Recent files and recent workspaces appear on the empty canvas, so returning to a recent debug session is one click.

### Dropping files onto the window { #drop }

On macOS, Windows and Linux you can drag files from Finder, Explorer or your file manager and drop them anywhere on the WaveCrux window — on the empty canvas or over a waveform you already have open. A green outline and a **Drop to open** card appear while you drag. A drop does exactly what **File → Open File** does with the same files: each waveform opens in its own new tab, FSDB gets the same conversion offer, and `.wavecrux` sessions, `.wavecruxpack` bundles and `<design>.crux-project` manifests open as they would from the picker. Several files dropped at once each get a tab. A file WaveCrux cannot read opens into the tab's load error, which says why.

A dropped GTKWave `.gtkw` file is imported into the current tab, as **File → Import GTKWave Session** does. Drop a dump and its `.gtkw` together and the dump opens first, then the session is applied to it.

Drops are ignored while a dialog is open.

In the browser, drop a file onto the empty canvas's drop zone instead; dropping elsewhere in the page does nothing.

### Auto-reload { #auto-reload }

WaveCrux watches the loaded file and reacts when it changes on disk. **Settings → File Handling → Auto-Reload on File Change** picks what happens — **Prompt**, **Auto** or **Off**: ask before reloading (a snackbar with **Reload** and **Ignore**), reload automatically, or ignore the change. This is built for the iterative simulate-then-debug loop: re-run the simulation and the new trace replaces the old one in place.

### Loading on mobile { #mobile }

On iOS, iPadOS and Android the usual path is **Open with WaveCrux** — from Files, Mail, a chat app, a cloud drive, or AirDrop. The in-app file picker, with iCloud Drive, Google Drive and other document providers, is the other path. File-type associations are registered for `.vcd`, `.fst`, `.ghw`, `.lxt`, `.lxt2` and `.wavecrux` (and, on Android, `.wavecruxpack`), so those open in WaveCrux directly from other apps. A received file is copied into WaveCrux's own storage first.

## Opening a design with `<design>.crux-project` { #crux-project }

A design usually spans more than one Crux product — the dump in WaveCrux, the RTL in NetCrux, the lint project in LintCrux, the regression suite in SimCrux. Without help that is four file-open rituals, each with its own recents list and its own chance of picking yesterday's dump.

A manifest named `<design>.crux-project` — for example `uart_tx.crux-project` — at the root of your design replaces all four. It is a small YAML file you write once and check in alongside the RTL:

```yaml
# uart_tx.crux-project
version: 1
name: uart_tx

design:
  top: uart_tx
  sources:
    - rtl/uart_tx.v

artifacts:
  waveform:   sim/uart_tx.vcd
  lint:       project.lintcrux
  simulation: simcrux.yaml
```

Open it in any of the four products and that product opens the part it owns — WaveCrux loads the `waveform:` artifact, here `sim/uart_tx.vcd`. Every path is relative to the manifest's own directory, so the file travels with the repository. In WaveCrux, choose it in **File → Open File** (the picker lists `.crux-project` files alongside waveforms, sessions and packs), double-click it in Finder on macOS, or pass it on the command line — `wavecrux path/to/design/uart_tx.crux-project`, or the design folder itself, `wavecrux path/to/design`. A design folder holds exactly one manifest; if it holds more, WaveCrux names them and opens nothing.

All four products also derive the same design identity from it, which means cross-probing between them works exactly as it does when you open each file by hand — the manifest is a shortcut, not a different mode.

!!! note

    **Everything except `version` is optional.** A manifest with no `waveform:` artifact, or one whose waveform is not on disk, gets a plain message in WaveCrux rather than an error. Keys a newer version understands and an older one does not are ignored with a warning, so a manifest never becomes unopenable.

!!! note "Manifests named `.crux-project`"

    A manifest with the bare name `.crux-project` still opens, with a notice naming the file to rename it to (`<folder>.crux-project`). File pickers hide names that start with a dot, and a later release stops reading the bare name.

A `<design>.crux-project` holds no view state and no personal settings — it says what the design *is*, not how you last looked at it. That is what sessions below are for, and it is why a manifest is comfortable to share while a session generally is not.

## Sessions and workspaces { #sessions }

A loaded waveform is raw signal data; a *session* is the arrangement you built around it — which signals are shown, how they are grouped and formatted, where the cursors and markers sit, and what is in the Stage panel. WaveCrux saves that arrangement to named files with the product extension, not hidden dotfiles. Both session formats are human-readable JSON.

| Format | Extension | What it captures |
|---|---|---|
| Session | `.wavecrux` | A single-tab session: the waveform it belongs to, signals and groups with their display formats, cursor positions, named markers, zoom and scroll, panel layout, translate filters, decoders, annotations, and Stage panel configuration. Use it to hand one debug arrangement to a colleague, or to ship a pre-built session inside an educational pack. |
| Workspace | `.wavecrux-workspace` | The entire multi-tab, multi-pane arrangement — all tabs, all panes, and the panel layout. For team sharing, version control, or organization-wide templates. Example: `team-debug.wavecrux-workspace`. |

Save a session with **File → Save Session** (++cmd+s++ / ++ctrl+s++), and **Save Session As** with ++cmd+shift+s++ / ++ctrl+shift+s++.

!!! note "In the browser"

    A browser cannot hand WaveCrux back a path to a file it saved, so the browser build leaves out the commands that work with one: **Save Session**, **Save Session As**, the workspace commands (**New Workspace**, **Save Workspace As**, **Export Tab as Session…**) and **Generate Test VCD**. Use a desktop build for those. **Export Waveform…**, **Share Annotated Waveform…** and the other exports still work there — the file downloads under a default name (for example `export.vcd` or `waveform.png`) instead of opening a save dialog.

Workspaces are managed from the **File** menu (or the command palette). Build the arrangement first: open extra traces in new tabs with **File → Open File** (++cmd+o++ / ++ctrl+o++) — each new file gets its own tab — and split the view into side-by-side panes with ++cmd+backslash++ / ++ctrl+backslash++. Then **Save Workspace As** writes the whole multi-tab, multi-pane arrangement to a `.wavecrux-workspace` file, **Open Workspace…** restores one, and **New Workspace** starts an empty one. To pull just the active tab out as a portable single session, use **Export Tab as Session…**.

!!! note "Plain JSON, version-control friendly"

    Both `.wavecrux` and `.wavecrux-workspace` files are human-readable JSON. They diff cleanly in version control, so you can review changes to a shared debug arrangement line by line and track organization-wide templates in your repository like any other source file.

!!! tip "Migrating from GTKWave"

    Already have GTKWave save files? Use **File → Import GTKWave Session** or ++cmd+i++ / ++ctrl+i++ to bring in a `.gtkw` session, or [drop the `.gtkw` onto the window](#drop) on desktop. This is the main migration path from GTKWave.

    **What the import applies:**

    - your signal list, with groups, separators, comments, color assignments, display formats and analog rendering;
    - named markers A–Z, and GTKWave's primary marker, which becomes the primary cursor;
    - the zoom level and scroll position, so the view opens on the same stretch of time GTKWave showed (a zoom wider than the waveform opens fitted to the whole trace);
    - the scopes you had expanded in GTKWave's hierarchy, which open in the hierarchy tree alongside any already open;
    - translate filter files. GTKWave saves each filter's full path on the machine that wrote the file; if that path does not exist here, WaveCrux looks for the filter in the same place relative to the `.gtkw` (so a moved or freshly cloned project still works), then by file name next to the `.gtkw` and next to the waveform.

    **What it does not apply:**

    - filter processes and transaction filters. An imported save file never starts a program; set a filter process yourself with **Set Translate Filter Process…** on the signal;
    - time shifts on individual traces;
    - the canvas background color. The WaveCrux theme owns the canvas; change it in **Settings → Appearance**.

    The import dialog lists anything it could not bring across: signals that do not exist in the loaded waveform, and under **Filters not applied**, filter files it could not find and the filter processes it skipped.

## Recovering when the app won't start { #recovery }

WaveCrux reopens your previous session on launch. In rare cases a saved session can be the thing that wedges startup — a capture that exhausts memory, a file that trips a graphics-driver bug, a corrupt workspace file. Here is how to get back to a working app, in order from least to most drastic. You almost never need to delete files by hand.

### WaveCrux usually recovers on its own { #recovery-automatic }

If a launch crashes or hangs *while reopening your last waveform*, the next launch notices and **skips reopening it**. Your tabs still come back as chips — nothing is deleted — but no waveform is auto-opened, and a banner appears at the top:

- **Open last session** — reopen the waveform that was held back (use this once you suspect the file is fine).
- **Reset** — clear the saved session and start with an empty workspace.
- **Dismiss** — leave the chips in place; tap any tab to load it when you're ready.

If the saved workspace file itself cannot be read, WaveCrux moves it aside with a `.corrupt` suffix, starts with an empty workspace, and tells you so in the same banner.

This is automatic on every platform, including mobile. A second normal launch resumes restoring your session as usual.

### Desktop: command-line flags { #recovery-desktop }

If startup is wedged before the banner can help, launch WaveCrux from a terminal with a flag:

- `--no-restore` — **try this first.** Launches without reopening the previous session's waveforms. Nothing is deleted; if this fixes startup, your last session was the culprit.
- `--reset` — clears all saved session and workspace state (open tabs, panes, and per-tab session data), then launches empty. Your **settings, keyboard shortcuts, and recent-files history are kept** — this is not a factory reset.

The executable to run with the flag:

- **macOS:** `/Applications/WaveCrux.app/Contents/MacOS/WaveCrux --reset`
- **Linux** (`.deb` / `.rpm`): `wavecrux_pro --reset`; with the AppImage, pass the flag to the AppImage itself.
- **Windows:** `"C:\Program Files\WaveCrux Pro\wavecrux_pro.exe" --reset`
- **Built from the open-core source:** `wavecrux --reset`

### Mobile and in-app reset { #recovery-mobile }

There is no command line on iOS or Android, so the automatic recovery above is the primary path. To clear the saved session deliberately — on any platform — use **Settings → File Handling → Reset workspace & sessions**. It clears the same state as `--reset` and keeps your settings, keymap and recent files.

!!! warning "Last resort: clearing files by hand"

    If the app cannot start at all and you cannot reach a terminal, you can delete WaveCrux's saved session files directly. Quit WaveCrux first, then remove `workspace.json` and the `sessions` folder from the app-support directory:

    - **macOS:** `~/Library/Application Support/com.ferriteengineering.wavecruxPro/`
    - **Windows:** `%APPDATA%\com.ferriteengineering\WaveCrux\`
    - **Linux:** `~/.local/share/com.ferriteengineering.wavecrux_pro/`
    - **Android:** Settings → Apps → WaveCrux → Storage → *Clear storage* (this also clears app settings).
    - **iOS:** offload or delete and reinstall the app (iOS has no per-app data-clear; this also resets settings).

    A build made from the open-core source uses `com.ferriteengineering.wavecrux` in place of the macOS and Linux folder names above.

## Exporting { #exporting }

Export with **File → Export Waveform…** (++cmd+e++ / ++ctrl+e++). Pick a format, then the signals (**Visible Signals Only** or **All Loaded Signals**) and the time range (**Visible Range** or **Full Simulation**) where they apply:

- **VCD (Value Change Dump)** — a filtered subset of the loaded waveform.
- **SAIF (switching activity)**, for a power-analysis tool — per-bit time at 0, 1, `x` and `z` plus toggle counts, over the same signal and range selection. See [Exporting switching activity as SAIF](analysis.md#saif).
- **PNG Image** or **SVG Vector** of the canvas, for documentation, bug reports, or slides. A PNG captures exactly what is on screen; either can include your annotations.

To put a single value or a signal path on the clipboard, right-click (long-press on touch) the signal: **Copy Value** and **Copy Full Path** in the signal list, **Copy Signal Path** in the signal tree.

!!! note "Sessions vs. export"

    Save a `.wavecrux` session when you want someone to *open the same arrangement* and keep working in it; export a VCD, PNG, or SVG when you want a *static artifact* of what is on screen.
