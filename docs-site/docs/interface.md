# The interface

WaveCrux runs the same application on desktop, tablet, and phone, and reshapes its layout to the device and window you give it. This page is a map of every region on screen, how they collapse and expand across device classes, and the independent ways to reach any action — so you can find what you need without hunting.

!!! note "Device classes"

    On a **desktop operating system** (macOS, Windows, Linux) WaveCrux always uses the full desktop layout; a narrow window keeps every panel and simply shrinks to the operating system's minimum window size. In the **browser** and on **iOS, iPadOS and Android**, the layout follows the window size:

    - **Desktop** (width ≥ 1200 dp) — the IDE-style multi-pane view with resizable splitters. A large tablet in landscape can qualify.
    - **Tablet** (600–1200 dp wide, at least 500 dp tall) — the same multi-pane view, with narrower panel defaults below 800 dp.
    - **Phone** (&lt; 600 dp) — a full-width canvas, with panels in a drawer and a bottom sheet.
    - **Phone landscape** (600 dp or wider but under 500 dp tall) — the phone layout, keeping the extra width for the time axis.

    Tabs are a tablet and desktop capability; split panes need a desktop, or a tablet at least 1000 dp wide.

## Layout regions { #layout }

On desktop and tablet the regions sit in fixed positions around the waveform canvas. On phone the canvas takes the full width, and the other regions are reached through the status bar's chevrons, a drawer, a bottom sheet, and the overflow menu. The table lists every region and, where one exists, the shortcut that toggles it.

| Region | What it is | Toggle |
|---|---|---|
| Toolbar | The strip across the top. Icon buttons for the most frequent actions. | — |
| Signal hierarchy browser | Left dock. The scope tree and the variables within each scope. On phone, a drawer opened from the status bar. | **View → Toggle Signal Tree**, or the hide button (double-arrow) in the dock's tab strip; restore bar when hidden |
| Waveform canvas | The center region where signals are drawn against time. | — |
| Value column | On desktop and tablet, the right dock — values aligned to each signal row. On phone, the value renders inline at the cursor instead of in a column. | **View → Toggle Value Column**, or the hide button (double-arrow) in the dock's tab strip |
| Status bar | The strip across the bottom. | — |
| Bottom dock / transaction table | A tabbed dock below the canvas — hosts the transaction table, Stage panels, and analyses, with a maximize button in its strip. On phone, a bottom sheet. | ++cmd+shift+t++ / ++ctrl+shift+t++ |
| Stage panel | Hosts live animated Stage widgets bound to your signals. Each Stage panel is a top-level tab in the bottom dock. | ++cmd+shift+g++ / ++ctrl+shift+g++ |

!!! tip

    On phone, the value you would read from the value column appears inline at the cursor on the canvas, so the single pane stays uncluttered. Turn the phone to landscape for a wider time axis — WaveCrux suggests it once per session when you open a waveform in portrait, but never forces the rotation.

## Tabs and split panes { #tabs-and-panes }

Tabs are available on tablet and desktop, and split panes on desktop and on tablets at least 1000 dp wide — on a narrower tablet **Split Pane Right** is not offered and its shortcut does nothing. Opening a file creates a new tab — or brings forward the tab already showing that file — and each tab is fully isolated: it carries its own file, cursor, zoom, signal arrangement, decoder bindings, and Stage configuration. Switching tabs updates every panel instantly — the signal tree, value column, bottom dock, and Stage all swap to match the tab you land on. On phone there are no tab bars: one waveform is open at a time, and the other tabs from your last session are listed on the empty canvas for one-tap opening.

| Action | Shortcut |
|---|---|
| Close Tab | ++cmd+w++ / ++ctrl+w++ |
| Next Tab / Previous Tab | ++ctrl+tab++ / ++ctrl+shift+tab++ (all platforms) |
| Jump to tab 1–9 | ++cmd+1++ … ++cmd+9++ / ++ctrl+1++ … ++ctrl+9++ |
| Split Pane Right | ++cmd+backslash++ / ++ctrl+backslash++ |
| Close Pane | ++cmd+shift+w++ / ++ctrl+shift+w++ |
| Focus Other Pane, Move Tab to Other Pane | **View** menu or command palette (no default shortcut) |

Splitting the center canvas gives you two side-by-side panes, each hosting its own active tab. Drag a tab from one pane into the other to compare a reference run against the current one in a single window. The divider between panes is a draggable splitter.

!!! note

    Your whole arrangement — tabs, panes, panel layout, and statistics-strip state — auto-saves and restores on every launch. The session is implicit: there is no "unsaved changes?" prompt to dismiss. When you want a named, portable arrangement, save it as a `.wavecrux-workspace` file — see [Files & sessions](files-and-sessions.md).

## Finding any action { #finding-actions }

Almost every action in WaveCrux is reachable from more than one place, across several independent discovery surfaces. You never have to memorize where a command lives.

1. **Toolbar icons** — the frequent actions, one click away across the top. When the window is too narrow for all of them, the rest move into the toolbar's overflow menu.
2. **Menus** — the menu bar on desktop (the system menu bar on macOS, an in-window menu bar on Windows and Linux), and the categorized overflow menu on every device class, presented as a bottom sheet on phone.
3. **The command palette** — open it with ++cmd+shift+p++ / ++ctrl+shift+p++ (or **View → Command Palette**) and fuzzy-search any action by name. Each result shows its keyboard shortcut and its required license tier inline. The palette lists only actions you can run right now; menus show the rest greyed out.

Pro and Enterprise actions carry a tier badge wherever they are listed in the menu bar, the overflow menu and the command palette, so you can always see what a command requires before you run it. See [Tiers & licensing](licensing.md) for what each tier covers.

!!! tip

    The command palette is the fastest path to a rarely-used command and a live cheat-sheet for its shortcut at the same time — type a few letters of the action name, read the bound key off the result, and next time reach for the key directly. Every shortcut can be changed in **Settings → Keyboard Shortcuts**.

## Panel docks and toggles { #panel-toggles }

On tablet and desktop, the left, right, and bottom regions are tabbed docks in the VS Code style. Each dock carries a tab strip: click a tab to switch surfaces, click a tab's **×** to close that surface, and use the action cluster at the strip's edge — it changes with the active tab. The bottom dock adds a maximize button, and you can drag an analysis tab or the Cross-Probe tab between the right and bottom docks to put it where you want it; the placement is saved with the session.

To hide a whole dock, click its **double-arrow** button — it points toward the window edge the panel will slide into. A hidden dock leaves a slim restore bar of its tab icons along that edge; click an icon to reopen the dock on that tab.

On phone there are no docks: the status bar's chevrons open the signal-tree drawer and the bottom-dock sheet, and the overflow menu reaches the rest. The shortcut toggles from the [Layout regions](#layout) table work on every device class that has the panel.

!!! note

    Two app-wide toggles are not panels: **Settings** opens with ++cmd+comma++ / ++ctrl+comma++, and **View → Toggle Theme** flips between light and dark with ++cmd+shift+k++ / ++ctrl+shift+k++. See [Appearance & themes](appearance-and-themes.md) for the full set of themes and how to author your own.

## Diagnostics and performance { #diagnostics }

WaveCrux exposes its own performance and health data so you can see how it is handling a file rather than guessing.

The **statistics strip** is a desktop-only ambient performance monitor shown between the layout and the status bar. It reads **Memory**, **FPS** and **Paint** time (each with a sparkline), **Dropped** frames, **Render** time, the **Wellen DB** size, and **Signals** — how many signals are decompressed out of the total the file declares. Toggle it with ++cmd+shift+y++ / ++ctrl+shift+y++ (**View → Toggle Statistics Strip**).

Three deeper diagnostics surfaces are available on tablet and desktop, and are hidden on phone:

| Surface | What it shows | Open with |
|---|---|---|
| Tab Diagnostics drawer | **File Info**, **Signal Health**, and **Benchmark This File** for the active tab. | ++cmd+shift+i++ / ++ctrl+shift+i++ (**Tools → Tab Diagnostics**) |
| App Diagnostics dialog | **Memory**, **Frame Stats**, a **Per-Tab Memory Breakdown**, and a live [Logs](#logs) view for the whole app, with **Copy Full Diagnostics Report**. | ++cmd+shift+m++ / ++ctrl+shift+m++ (**Tools → App Diagnostics**) |
| Pane Render Stats popover | Render statistics for a single pane — paint, layout and per-layer times, visible transitions, line segments, canvas size. | The **i** icon in a pane's tab bar, or **Pane Render Stats** in the command palette (no default shortcut) |

!!! tip

    **Copy Full Diagnostics Report** in the App Diagnostics dialog puts a complete memory and frame-stats snapshot on your clipboard — the fastest way to attach hard numbers to a bug report. **Tools → Copy Diagnostics Report** (also in the command palette) copies the same report without opening the dialog; its frame-stats section is empty, because frame timings are only sampled while the dialog is open.

## Logs and log verbosity { #logs }

WaveCrux keeps a rolling, in-memory log of what it is doing — files opening, decoders binding, background work, and anything that goes wrong (a file that fails to parse, a translate filter that will not load, a network hiccup). You can watch that log live, control how much of it you see, and it travels with a bug report automatically. There is nothing to enable and no log file to hunt for on disk; it lives in memory and resets when you quit.

### The Logs view { #logs-panel }

Open the **App Diagnostics** dialog (++cmd+shift+m++ / ++ctrl+shift+m++) and scroll to the **Logs** section, below Frame Stats. Each line reads `time LEVEL source: message`, newest first, colour-coded by severity — errors in red, warnings in amber, ordinary events in the default text colour, and fine-grained traces muted.

- **Level filter.** The dropdown limits the view to a minimum level — pick *Quiet* to see only warnings and errors, or *Verbose* to see everything down to fine-grained traces. It starts at your saved verbosity (below) and only changes this view.
- **Copy.** Puts the lines that pass the filter on your clipboard as plain text, oldest first with full timestamps — handy for pasting into a bug report or a message.
- **Clear.** Empties the log. Because the report and this view share one buffer, clearing here also clears what a *subsequent* bug report would carry, so clear right before reproducing a problem to capture just the relevant lines.

!!! note "Live, but the dialog is modal"

    The Logs view updates in real time as events arrive, so it is perfect for reproducing something and then reviewing exactly what happened, and for watching background activity while it is open. Because the dialog sits on top of the app, though, you cannot click around the rest of WaveCrux while it is open. To watch the log *while you drive the app*, run WaveCrux from a terminal and use the console at a higher verbosity — see below.

### Log verbosity { #log-verbosity }

**Settings → General → Log Verbosity** sets one global level. It controls two things: how much WaveCrux prints to the **console** (the terminal, when you launch the app from one), and the default level the Logs view opens at. Your choice is remembered across launches.

| Level | What you see |
|---|---|
| Quiet | Warnings and errors only. |
| Normal *(default)* | The above plus notable lifecycle events (a file opened, a session restored). |
| Detailed | Adds high-frequency breadcrumbs and traces. |
| Verbose | Everything WaveCrux emits. |

For the live "watch while I use the app" workflow, launch WaveCrux from a terminal, set verbosity to **Verbose**, and the full stream prints to the console as you work — no dialog in the way.

!!! tip "Bug reports always carry the full log"

    The verbosity setting only changes what you *see*. WaveCrux always records every level internally, so a report filed with **Help → Submit Issue…** includes the complete recent log no matter how the setting is set — you never have to crank verbosity up before reproducing a problem to file a useful report. See [Reporting issues](getting-started.md#reporting-issues).

!!! note "Next"

    With the layout under your belt, move on to [Navigating & measuring](navigating-waveforms.md) for the full keyboard reference, or read [Tiers & licensing](licensing.md) for what the Pro and Enterprise badges mean.
