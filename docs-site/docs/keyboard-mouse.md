# Keyboard & mouse reference

The waveform canvas is driven almost entirely by the pointer: a click drops a cursor, a drag moves it, and a modifier turns the same drag into a pan, a selection, or an annotation. This page is the single-screen reference for every mouse, trackpad, and touch gesture on the canvas and in the signal tree. Bindings are written macOS first; the platform modifier is ++cmd++ on macOS and iPadOS and ++ctrl++ on Linux, Windows, Android, and the web. For the full keyboard binding set, see [Navigating & measuring → Keyboard reference](navigating-waveforms.md#reference).

## Cursors & measurement { #cursors }

A plain click always moves the **primary cursor** — the anchor for every time readout. Drop the **secondary cursor** to measure an interval; with both down, the status bar reports `T:`, `T2:`, and `Δ:` (plus a derived frequency, `f:`).

| Gesture | Action |
|---|---|
| Left-click on the canvas or the time ruler | Place / move the primary cursor. |
| Left-drag on the canvas (no modifier) | Drag the primary cursor; the view scrolls when you reach the edge. |
| Drag a cursor's triangle on the time ruler | Move that cursor. |
| Right-click, or ++shift++ + left-click | Place the secondary (delta-measurement) cursor. |
| Right-click a marker flag on the time ruler | Remove that marker. |
| Tap (touch) | Place the primary cursor. |
| Long-press (touch) | **Place Primary Cursor Here**, **Place Secondary Cursor Here**, **Clear Cursors**, **Fit All**. |

!!! tip "Reading the measurement"

    With both cursors placed, the status bar shows `T:` (primary time), `T2:` (secondary time), and `Δ:` (the interval), alongside the frequency derived from it — measure a clock period or pulse width without arithmetic.

## Pan & zoom { #pan-zoom }

Move and scale the viewport with the pointer. The scroll wheel does double duty: by default it scrolls the signal list, but with **Mouse wheel scrolls through time** enabled in **Settings → Waveform Defaults** it pans the time axis GTKWave-style.

| Gesture | Action |
|---|---|
| ++cmd++ / ++ctrl++ + left-drag, or middle-mouse drag | Pan the time axis. |
| Scroll wheel | Scroll the signal list — or pan time when **Mouse wheel scrolls through time** is on. |
| ++shift++ + scroll wheel | The other of the two: pan time, or scroll the signal list when the setting is on. |
| Horizontal (tilt) wheel | Pan the time axis. |
| ++cmd++ / ++ctrl++ + scroll wheel | Zoom in / out around the pointer. |
| Toolbar zoom buttons | Zoom In, Zoom Out, Fit All, Zoom to Selection. |
| Pinch (touch or trackpad) | Zoom around the pinch centre. |
| One- or two-finger drag (touch) | Pan the time axis. |
| Two-finger swipe (trackpad) | Horizontal pans time; vertical scrolls the signal list. |

!!! note "Scroll-wheel direction"

    The wheel's roles for time and the signal list swap with the **Mouse wheel scrolls through time** setting. The keyboard equivalents — the ++w++ / ++s++ zoom and ++a++ / ++d++ pan keys, Fit All, and Zoom to Selection — are covered in [Navigating & measuring → Zoom & pan](navigating-waveforms.md#zoom).

## Selection { #selection }

WaveCrux distinguishes two kinds of selection: a **time range** on the canvas (drag a window, then zoom to it) and a **signal selection** (the set of signals targeted by transition stepping, color edits, and analysis). The two are independent.

| Gesture | Action |
|---|---|
| ++shift++ + left-drag on the canvas | Select a time range (then ++z++ zooms to it). |
| Click a signal in the signal tree | Add it to the waveform. |
| ++cmd++ / ++ctrl++ + click a signal in the signal tree | Toggle it into the *selection* without re-adding it. |
| ++shift++ + click a signal in the signal tree | Select the range of rows from the last one you clicked. |
| Right-click a signal in the signal tree | **Add to Viewer**, **Copy Signal Path**, and — with several selected — **Add Selected to Viewer** and **Apply Decoder to Selection…**. |
| Drag a signal from the signal tree | Drop it onto a Stage widget binding. |
| Click a value in the value column | Copy that value to the clipboard. |
| ++cmd++ / ++ctrl++ + click a signal's row in the value column | Toggle its selection from the waveform. |
| Long-press a value row → **Select Signal** (touch) | Toggle a signal's selection on a touch device. |
| ++esc++ | Clear the signal selection — and the cursors. |

!!! tip "Clearing the selection"

    Besides ++esc++, the selection chip in the status bar carries its own clear control (**×**) — click it to drop the current signal selection without also clearing your cursors.

## Annotations { #annotations }

| Gesture | Action |
|---|---|
| ++alt++ / ++option++ + click on the canvas | Write a callout at that point. |
| ++alt++ / ++option++ + drag on the canvas | Draw an arrow from the press to the release point. |
| ++alt++ + ++arrow-left++ / ++arrow-right++ | Nudge the selected annotation's anchor; add ++shift++ to step to the adjacent transition. |

See [Annotations](annotations.md) for the full authoring workflow.

## In the signal tree, from the keyboard { #signal-tree-keys }

The signal tree is a single ++tab++ stop: ++tab++ from its search field lands on the row you were last on, and the next ++tab++ moves on to the waveform. While the tree has focus, its keys take priority over the waveform's arrow-key pan, the ++home++ / ++end++ jumps and ++space++ playback; other keys with a modifier still do what they do everywhere else.

| Key | Action |
|---|---|
| ++arrow-up++ / ++arrow-down++ | Move to the previous / next row. |
| ++home++ / ++end++ | Move to the first / last row. |
| ++page-up++ / ++page-down++ | Move by a screenful. |
| ++arrow-right++ | Expand a collapsed scope; on an expanded scope, move to its first child. |
| ++arrow-left++ | Collapse an expanded scope; otherwise move to the scope that contains the row. |
| ++enter++ or ++space++ | The same as a click: expand or collapse a scope, or add a signal to the viewer and select it. |
| ++shift+arrow-up++ / ++shift+arrow-down++ | Move and extend the selection over a range of signals, the same as ++shift++ + click. |
| ++ctrl+space++ | Add the current signal to the selection, or remove it, without adding it to the viewer — the same as ++cmd++ / ++ctrl++ + click. |
| ++shift+f10++ or ++context-menu++ | Open the row's context menu, the same as a right-click: **Add to Viewer**, **Copy Signal Path**, **Add All in Scope** and, with several signals selected, **Add Selected to Viewer** and **Apply Decoder to Selection…**. Focus starts on the first item; ++arrow-up++ / ++arrow-down++ and ++enter++ choose one, and ++esc++ closes the menu. Either way, focus returns to the same row. |

Clicking a row makes it the tree's current row without taking keyboard focus, so the arrow keys keep panning the waveform after you click signals in. With a screen reader, each row is announced as a button with its expanded or selected state, and adding a signal is announced.

## In the transaction table, from the keyboard { #transaction-table-keys }

The table's controls come first — **Decoder filter**, the search box, **Export CSV** and the sortable column headers — and then the rows, which are a single ++tab++ stop rather than one stop per cell. While the rows have focus their keys take priority over the waveform's pan, jump and playback keys.

| Key | Action |
|---|---|
| ++enter++ or ++space++ on **Decoder filter** | Open the decoder menu with focus on its first item. Each decoder's name filters the table; **Configure** and **Remove** beside it act on that decoder. ++esc++ closes the menu and returns to the button. |
| ++enter++ on a column header | Sort by that column; again to reverse. |
| ++arrow-up++ / ++arrow-down++ | Move to the previous / next transaction. |
| ++home++ / ++end++ | Move to the first / last transaction. |
| ++page-up++ / ++page-down++ | Move by a screenful. |
| ++arrow-left++ / ++arrow-right++ | Scroll the field columns sideways. |
| ++enter++ or ++space++ on a row | The same as a click: select the transaction and move the primary cursor and the view to its start. |

With a screen reader, each row is read as one sentence — number, decoder, start to end time, label, and the error if the decoder flagged one — and arrows in decoder labels are read as words ("R 0x08 to 0xFF"). Rows have no context menu.

## Moving around the window { #regions }

| Key | Action |
|---|---|
| ++f6++ / ++shift+f6++ | Move focus to the next / previous region: the toolbar, each dock, the waveform, the status bar. Coming back to a region returns to the control you left. |
| ++cmd+shift++ + arrow key / ++ctrl+shift++ + arrow key | Resize the dock that has focus. The arrow moves the dock's inner edge 20 px in its direction: ++arrow-right++ widens the left dock, ++arrow-left++ widens the right dock, ++arrow-up++ raises the bottom dock. |

!!! note "Platform modifier"

    Throughout this reference, ++cmd++ / ++ctrl++ means the platform modifier: ++cmd++ (Command) on macOS and iPadOS, ++ctrl++ on Windows, Linux, Android and the web. On an iPad with a Magic Keyboard, the ++cmd++ gestures behave as they do on macOS.

!!! tip "Where to next"

    [Navigating & measuring](navigating-waveforms.md) covers cursors, named markers, and the complete keyboard reference in depth. [Working with signals](working-with-signals.md) covers the hierarchy browser, search, and grouping.
