# Navigating & measuring

The work of reading a trace is moving the viewport precisely and reading time off it exactly. This page covers cursors and delta measurement, jumping between transitions, the 26 named markers, the full zoom and pan vocabulary, and the complete keyboard reference. Bindings are written macOS first; the modifier is ++cmd++ on macOS and iPadOS and ++ctrl++ on Linux, Windows, the web, and Android.

## Cursors & delta measurement { #cursors }

The **primary cursor** is the anchor for every time readout. Place it by clicking anywhere in the waveform canvas or the time ruler above it, or drag it — anywhere in the canvas, or by its triangle on the ruler. The status bar reports the cursor time (`T:`) in units auto-scaled to the file's own timescale, so the unit always matches the resolution of the trace rather than a fixed scale.

The **value column** beside the signal names shows each signal's value at the primary cursor. Move the cursor and the entire column updates to that instant, which is the fastest way to read a bus or sample a set of control signals at one point in time.

For interval measurement, place the **secondary cursor**. A plain click always moves the *primary* cursor; to drop the secondary instead, ++shift++ + click or right-click anywhere in the canvas or on the ruler. On touch, long-press and choose **Place Secondary Cursor Here** from the menu. With both cursors down, the status bar adds the secondary time (`T2:`), the **Δ** between the cursors, and a derived frequency (`f:`) — useful for measuring a clock period, a pulse width, or the latency between two events without arithmetic. Clear just the secondary cursor with ++shift+esc++; clear both cursors with ++esc++ (or, on touch, long-press → **Clear Cursors**).

### How to measure an interval { #measure-interval }

1. **Place the primary cursor.**

    Click at the start of the interval, then — with the signal selected — snap exactly onto the edge with ++e++ (next) or ++q++ (previous) so you start on a real transition.

2. **Place the secondary cursor.**

    ++shift++ + click or right-click where the interval ends — the next clock edge, the falling edge of a pulse, or an edge on a different signal entirely (long-press → **Place Secondary Cursor Here** on touch).

3. **Read the result.**

    The status bar reports the **Δ** time and the derived frequency. Clear just the secondary cursor with ++shift+esc++, or both with ++esc++.

For the full set of timing measurements — clock period, pulse width, and cross-signal latency — follow the cookbook recipe [Measure clock & timing](cookbook-measure-timing.md).

!!! tip "Touch devices"

    On phones and tablets the cursor triangles and markers use enlarged hit targets, so you can grab and drag a cursor precisely with a fingertip rather than a pointer.

## Transitions & markers { #transitions }

To follow a signal edge-by-edge, select it and step to the next or previous transition with ++e++ (next) and ++q++ (previous). These are bare keys — no modifier — and they move the primary cursor to the exact time of the signal's next change, snapping you onto real edges rather than approximate clicks. They step from the primary cursor, so place one first; with no signal selected they follow the first signal in the list.

For points you return to repeatedly, set a **named marker**. WaveCrux provides 26 markers, `a` through `z`. To set one, press ++m++ and then a letter ++a++–++z++ — a two-key chord that drops the marker at the current primary cursor time. To jump back to a marker, press ++shift+m++ and then the letter. **Navigate → Remove Marker…** deletes one, or right-click its flag on the ruler. Markers persist with the session, so a labelled set of points of interest survives across reloads.

!!! note "Reading the marker chords"

    ++m++ then a letter is a sequence, not a simultaneous combination: tap ++m++, release, then tap the letter. The same applies to ++shift+m++ then a letter for the jump.

## Zoom & pan { #zoom }

Zoom in with ++cmd+equal++ / ++ctrl+equal++ and out with ++cmd+minus++ / ++ctrl+minus++; keyboard zoom is centred on the middle of the viewport. The bare keys ++w++ (in) and ++s++ (out) do the same without a modifier, which keeps them under one hand alongside the pan keys. With the mouse, ++cmd++ / ++ctrl++ + scroll wheel zooms around the pointer.

Fit the entire trace to the viewport with ++cmd+0++ / ++ctrl+0++. To zoom into a specific window, ++shift++ + drag across the canvas to select a time range and press ++z++ to zoom to it.

Pan in large steps with ++a++ (left) and ++d++ (right); pan in small steps with the arrow keys ++arrow-left++ and ++arrow-right++. ++home++ and ++end++ scroll the view to the beginning or end of the trace. With the mouse, middle-drag or ++cmd++ / ++ctrl++ + drag pans.

!!! tip "Touch gestures"

    On touch devices, pinch to zoom around the pinch centre, and drag with one or two fingers to pan. On a trackpad, pinch zooms and a horizontal two-finger swipe pans. These map to the same viewport transforms as the keyboard. The full gesture list is on [Keyboard & mouse reference](keyboard-mouse.md).

## Keyboard reference { #reference }

The complete default binding set is grouped below. Modifier shortcuts are shown for both platforms, macOS first; bare navigation keys (++w++ ++a++ ++s++ ++d++ ++q++ ++e++ ++z++ ++m++) take no modifier.

### Files & tabs

| Action | Shortcut |
|---|---|
| Open File | ++cmd+o++ / ++ctrl+o++ |
| Close File | ++ctrl+f4++ on Windows and Linux (no default on macOS) |
| Close Tab | ++cmd+w++ / ++ctrl+w++ |
| Close Pane | ++cmd+shift+w++ / ++ctrl+shift+w++ |
| Split Pane Right | ++cmd+backslash++ / ++ctrl+backslash++ |
| Next Tab | ++ctrl+tab++ |
| Previous Tab | ++ctrl+shift+tab++ |
| Jump to tab 1–9 | ++cmd+1++ … ++cmd+9++ / ++ctrl+1++ … ++ctrl+9++ |
| Save Session | ++cmd+s++ / ++ctrl+s++ |
| Save Session As | ++cmd+shift+s++ / ++ctrl+shift+s++ |
| Import GTKWave Session | ++cmd+i++ / ++ctrl+i++ |
| Export Waveform… | ++cmd+e++ / ++ctrl+e++ |
| Settings… | ++cmd+comma++ / ++ctrl+comma++ |
| About WaveCrux | ++f1++ |
| Quit WaveCrux — **Exit** on Linux and Windows | ++cmd+q++ / ++ctrl+q++ |

### Zoom & pan

| Action | Shortcut |
|---|---|
| Zoom In | ++cmd+equal++ / ++ctrl+equal++ (or ++w++) |
| Zoom Out | ++cmd+minus++ / ++ctrl+minus++ (or ++s++) |
| Fit All | ++cmd+0++ / ++ctrl+0++ |
| Zoom to Selection | ++z++ |
| Pan Left / Right | ++a++ / ++d++ |
| Pan Left / Right (Fine) | ++arrow-left++ / ++arrow-right++ |
| Jump to Start / End | ++home++ / ++end++ |

### Cursors & markers

| Action | Shortcut |
|---|---|
| Next / Previous Transition | ++e++ / ++q++ |
| Set Marker (a–z) | ++m++ then letter |
| Jump to Marker (a–z) | ++shift+m++ then letter |
| Clear All Cursors | ++esc++ |
| Clear Secondary Cursor | ++shift+esc++ |

### Search & analysis

| Action | Shortcut |
|---|---|
| Search Signals | ++cmd+f++ / ++ctrl+f++ |
| Command Palette | ++cmd+shift+p++ / ++ctrl+shift+p++ |
| Multi-Signal Pattern Search | ++cmd+shift+f++ / ++ctrl+shift+f++ |
| Next / Previous Pattern Match | ++f3++ / ++shift+f3++ |
| Analyze Switching Activity | ++cmd+shift+a++ / ++ctrl+shift+a++ |
| Compare Waveforms | ++cmd+shift+c++ / ++ctrl+shift+c++ |
| Next / Previous Divergence | ++f7++ / ++shift+f7++ |

### Panels & view

| Action | Shortcut |
|---|---|
| Toggle Transaction Table | ++cmd+shift+t++ / ++ctrl+shift+t++ |
| Add Protocol Decoder | ++cmd+shift+d++ / ++ctrl+shift+d++ |
| Toggle Stage Panel | ++cmd+shift+g++ / ++ctrl+shift+g++ |
| Play / Pause Stage Playback | ++space++ |
| Toggle Statistics Strip | ++cmd+shift+y++ / ++ctrl+shift+y++ |
| Toggle RTL Source Panel | ++cmd+shift+r++ / ++ctrl+shift+r++ |
| Show Cross-Probe Panel | ++cmd+shift+x++ / ++ctrl+shift+x++ |
| Toggle Theme | ++cmd+shift+k++ / ++ctrl+shift+k++ |
| App Diagnostics | ++cmd+shift+m++ / ++ctrl+shift+m++ |
| Tab Diagnostics | ++cmd+shift+i++ / ++ctrl+shift+i++ |
| Generate Test VCD… | ++cmd+alt+g++ / ++ctrl+alt+g++ |
| Undo / Redo Stage Edit | ++cmd+z++ / ++ctrl+z++ and ++cmd+shift+z++ / ++ctrl+shift+z++ |
| Next / Previous Region | ++f6++ / ++shift+f6++ |
| Resize the Focused Dock | ++cmd+shift++ + arrow key / ++ctrl+shift++ + arrow key |

### Signal tree

With the signal tree focused, the arrow keys, ++home++ / ++end++, ++page-up++ / ++page-down++, ++enter++ and ++space++ move through and act on its rows instead of the waveform; ++shift+arrow-up++ / ++shift+arrow-down++ and ++ctrl+space++ select signals, and ++shift+f10++ or the ++context-menu++ key opens the row's context menu. See [Keyboard & mouse reference → In the signal tree](keyboard-mouse.md#signal-tree-keys).

### Annotations

| Action | Shortcut |
|---|---|
| Add Annotation at Cursor | ++shift+a++ |
| Show Annotations | ++cmd+shift+n++ / ++ctrl+shift+n++ |
| Next / Previous Annotation | ++bracket-right++ / ++bracket-left++ |

### Pro tools <span class="tier tier-pro">Pro</span>

| Action | Shortcut |
|---|---|
| Toggle Debug Advisor Panel | ++cmd+shift+b++ / ++ctrl+shift+b++ |
| Toggle SystemVerilog Assertion Panel | ++cmd+shift+v++ / ++ctrl+shift+v++ |

!!! note "Bindings are yours"

    Every binding above is a default you can change. The command palette always shows an action's current binding next to its name — so even after you remap, the palette is the authoritative reference. The ++w++ / ++a++ / ++s++ / ++d++ and ++q++ / ++e++ navigation keys take no modifier. On an iPad with a Magic Keyboard, the ++cmd++ shortcuts behave exactly as they do on macOS.

### Customizing shortcuts { #customize-shortcuts }

Open **Settings → Keyboard Shortcuts** (Settings is ++cmd+comma++ / ++ctrl+comma++). The full action list is grouped by category, each row showing its current binding.

1. **Start from a preset.**

    The **Preset** chooser at the top loads a complete key map in one step. Pick **WaveCrux (Default)** for the bindings in this reference, or **GTKWave** if your fingers already know GTKWave — it moves Search Signals to ++alt+s++ and Export Waveform to ++cmd+p++ / ++ctrl+p++, and binds hex, decimal, binary and octal display formats to ++alt+x++, ++alt+d++, ++alt+b++ and ++alt+o++. The chooser reads **Custom** automatically once you hand-edit any single binding.

2. **Rebind one action.**

    Press **Change shortcut** (the pencil) on a row, then press the keys you want; ++esc++ cancels the capture. **Remove shortcut** unbinds an action entirely; **Reset to default** restores just that row's default.

3. **Resolve conflicts.**

    If two actions claim the same chord, WaveCrux flags both inline — the row that actually fires reads "Takes precedence over …", the other "Won't fire — shadowed by …" — and a banner above the list counts how many conflicts need attention. Nothing is silently dropped.

4. **Share your map.**

    **Export…** writes your customizations to a `.crux-keymap` file; **Import…** applies one. It carries only the bindings you changed, so it layers cleanly onto a teammate's setup. **Reset all** returns every shortcut to its default after a confirmation.

!!! tip "Scroll-wheel direction"

    One related habit lives in **Settings → Waveform Defaults** too: **Mouse wheel scrolls through time** makes the wheel pan the waveform left and right (GTKWave-style), with ++shift++ + wheel scrolling the signal list. Leave it off and the roles swap. Either way, ++cmd++ / ++ctrl++ + wheel always zooms.

!!! tip "Where to next"

    [Working with signals](working-with-signals.md) covers signal search and the hierarchy browser. [Analysis & debug](analysis.md) covers pattern search, waveform diff and divergence stepping, and switching activity in depth.
