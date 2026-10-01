# Working with signals

Everything between the file and the canvas happens here: browsing the design hierarchy, finding the nets you care about, arranging them into a readable trace, and rendering each value in the radix or symbolic form that makes the trace mean something. This page covers the signal hierarchy browser, search and filtering, organizing signals, all twelve value-display formats, structured and custom translators, and GTKWave-compatible translate filters and filter processes.

## From file to readable trace { #quickstart }

Every step below is covered in full further down the page; this is the path most people take to turn a freshly opened file into a trace they can actually read.

1. **Find the signals.**

    Type a fragment of a name into the signal tree's **Search signals…** box, or open **Search Signals** with ++cmd+f++ / ++ctrl+f++ for substring or glob matching with type, width, scope and direction filters.

2. **Add them to the canvas.**

    Click a signal in the signal tree to add it (or press ++enter++ on it). Drag a signal by its handle in the signal list to reorder it within the trace.

3. **Group what belongs together.**

    Right-click a signal in the signal list (long-press on touch) and choose **Move to Group** to collect a bus or a set of related control nets into a named, collapsible group you can fold away when it is not the focus.

4. **Make it readable.**

    Tap a signal's color swatch to cycle its color (or right-click → **Change Color…** for the full picker), size its lane, then set each signal's [display format](#formats) — hex for a bus, a named enum for a state register.

## The signal hierarchy browser { #hierarchy }

The left panel presents the design as a tree of scopes and variables. Each entry carries a type icon and its bit width, so you can tell a single-bit net from a wide bus at a glance and see where one scope ends and the next begins. **Expand All** and **Collapse All** keep the tree focused on the part of the hierarchy you are working in.

To bring a signal onto the canvas, click it, press ++enter++ on it, or right-click it and choose **Add to Viewer**; **Add All in Scope** adds a whole scope, and **Remove All in Scope**, right beside it, takes that scope's signals off the canvas again (see [Removing signals](#removing)). Clicking a signal that is already on the canvas adds it again, so to *select* an existing signal, click its name in the signal list instead. You can also drag a signal from the tree onto a Stage widget to bind it.

To add many signals at once, ++shift++ + click to select a range of rows (or ++cmd++ / ++ctrl++ + click to pick individual ones), then right-click and choose **Add N Selected to Viewer** — the signals land on the canvas in tree order. The same context menu can **Apply Decoder to Selection…** in one step. Leaves declared as HDL parameters show their constant value inline in the row, so module generics are readable without adding them to the trace.

The tree sorts **alphanumerically** by default: digit runs compare as numbers, so `bit[2]` lists before `bit[11]` instead of the raw dump order — which matters on bit-blasted gate-level netlists with thousands of numbered nets. Prefer the file's declaration order? Turn off **Settings → Waveform Defaults → Sort hierarchy alphanumerically**.

## Searching and filtering { #search }

The signal tree's own search box narrows the tree to signals whose name contains what you type. For more, open **Search Signals** with ++cmd+f++ / ++ctrl+f++. It matches the signal *name* — as a case-insensitive **Substring**, or as a **Glob** pattern where `*` matches any run of characters and `?` exactly one — and its **Filters** narrow the results further by type (**Wire**, **Reg**, **Integer**, **Real**, **Port**), by bit width (**Min** / **Max**), by scope prefix, and by direction (**Input**, **Output**, **Inout**). Pick results and **Add** them, or **Add All**.

The direction can also be typed as a GTKWave-compatible prefix at the start of the query, so existing habits carry over:

| Prefix | Matches |
|---|---|
| `+I+` | Inputs |
| `+O+` | Outputs |
| `+IO+` | Bidirectional signals |

## Organizing signals { #organizing }

Once signals are on the canvas, you arrange them into a trace that reads cleanly. Collect related signals into named, collapsible groups — a bus, a set of correlated control nets, or everything belonging to one functional module. To make a group, right-click a signal in the signal list (long-press on touch) and choose **Move to Group**; pick an existing group or create one inline. You can also start an empty group with the **Create a new signal group** button in the signal panel and drag signals into it. Collapse a group with its disclosure triangle when you want it out of the way without removing it, and right-click a group's header to **Rename…** it, **Ungroup** it (the header goes and its signals stay on the canvas), or **Remove Group and Signals** (the header and everything in it leave the canvas). To pull one signal back out, right-click it and choose **Remove from Group**.

Reorder signals by dragging an explicit drag handle. On touch devices the handle is the only part of the row that starts a drag; long-pressing the body of the row instead opens the context menu, so you never reorder a signal by accident while reaching for its menu.

Color and density are adjustable per signal. The quickest way to recolor a signal is to tap its **color swatch** at the left of the row — each tap cycles to the next palette color. For a specific color, right-click the signal (long-press on touch) and choose **Change Color…** to open the picker. Colors are saved with the session. Lane height is per-signal too: drag a row's lane-resize handle, so you can pack low-interest nets into dense rows and give the signals you are studying more vertical room; double-click the signal's name to return the lane to its default height.

## Removing signals { #removing }

Each row in the signal list has a **×** that takes that one signal off the canvas. For more than a few, remove them together:

- **Remove Selected.** Click a signal's name in the signal list to select it, ++shift++ + click another to select the run of rows between them, or ++cmd++ / ++ctrl++ + click to add or drop single rows. Selected rows are highlighted across the signal list, the canvas and the value column. Press ++delete++ or ++backspace++, or right-click a selected row and choose **Remove Selected**. **Edit → Remove Selected Signals** and the command palette do the same.
- **Remove All in Scope.** Right-click a scope in the signal hierarchy and choose **Remove All in Scope**, the inverse of **Add All in Scope**. Every signal from that scope and the scopes below it leaves the canvas, including ones you have moved into groups. Use it after an **Add All in Scope** on a scope wider than you meant.
- **Remove Group and Signals.** Right-click a group's header to remove the group together with every signal in it. **Ungroup** is the other choice there: it removes only the header and keeps the signals.
- **Clear Canvas.** **View → Clear Canvas**, or **Clear Canvas** in the command palette, removes every signal, group, separator and comment from the active tab. The file stays open, and the cursors, markers, decoders and zoom stay as they are.

Removal is per tab: it changes only the tab you are looking at. Every bulk removal shows a message at the bottom of the window with an **Undo** button, which puts the removed signals back where they were, with their groups, colors, display formats and lane heights. Groups emptied by **Remove Selected** or **Remove All in Scope** stay in the list, ready to be refilled.

A cleared canvas is a real state of the session. Saving after **Clear Canvas** saves an empty signal list, and reopening that session shows an empty canvas.

!!! tip

    If you already have this trace set up in GTKWave, you do not have to rebuild it. Importing a `.gtkw` file (see [Files & sessions](files-and-sessions.md)) brings your groups, colors, display formats, and translate filter files across in one step.

## Display formats { #formats }

The value column shows each signal's current value in its selected display format; on phones, where the value column gives way to space, the value appears inline at the cursor instead. Display formats are set per signal and saved with the session, so a bus you read in hex and a status register you read as a named enum keep those settings as you move around the trace. New signals start in **Settings → Waveform Defaults → Default Display Format** (Hexadecimal unless you change it).

WaveCrux provides twelve formats:

| Format | What it shows |
|---|---|
| Binary | The raw bits. |
| Hexadecimal | The value in base 16. |
| Octal | The value in base 8. |
| Unsigned Decimal | The value as an unsigned integer. |
| Signed Decimal | The value as a two's-complement signed integer. |
| ASCII | Each byte rendered as a character; non-printable bytes are shown as a dot. |
| IEEE 754 (32-bit) | A 32-bit value interpreted as a single-precision float. |
| IEEE 754 (64-bit) | A 64-bit value interpreted as a double-precision float. |
| Fixed-point (Q) | A Qm.n fixed-point value, with configurable integer bits, fraction bits, and sign. |
| Signed-magnitude | The value where the MSB is the sign bit and the remaining bits are the magnitude. |
| Gray code | A binary-reflected Gray code decoded to its unsigned value. |
| Named enum | A value-to-label map you define — for example, `2'b01` shown as `WRITE`. |

## Drawing a bus as an analog curve { #analog }

A fixed-point or floating-point datapath is unreadable as hex. Right-click a signal — in the signal list or in the value column — and choose **Render as analog** to draw it as a curve instead of a bus lane. Choose **Render as digital** on the same menu to switch back.

The analog toggle is deliberately *separate from* the display format, not one of the formats above. The format answers *what number are these bits*; the toggle answers *how should that number be drawn*. So the same 16-bit bus plots a meaningless sawtooth under hex and a clean sine under Q4.12 — you change the format, not the toggle, to fix the shape. GTKWave draws the same distinction, and a `.gtkw` session that marks a trace analog imports already switched on.

Everything the value column can interpret numerically can be plotted: signed and unsigned decimal, IEEE 754 single and double, fixed-point Q*m.n*, signed-magnitude, Gray code — and, with the <span class="tier tier-pro">Pro</span> translator pack, the ML float formats (bf16, FP16, FP8 E4M3/E5M2). Gray code is decoded before plotting, so a Gray counter draws the ramp it really is rather than the sawtooth its raw bits would suggest.

Unknown (`x`) and high-impedance (`z`) stretches render as **gaps** in the curve, never as zero. A zero is a value your design could legitimately hold, so drawing unknown data on the axis would invent data that was never there.

Real-valued signals — VCD `real`, `realtime` and SystemVerilog `shortreal` — are analog by nature and need no toggle; they draw as curves the moment you add them.

## Translators { #translators }

A display format reinterprets one value; a **translator** goes further — it can decompose a value into named parts and render them as their own child rows. Translators are bound per signal, just like display formats, and the built-in formats above are themselves the default translator. Struct and bitfield decomposition, user-authored custom translators (**Settings → Extensions → Custom Translators**), the RISC-V instruction format, and the curated <span class="tier tier-pro">Pro</span> translator pack all build on this.

See [Translators](translators.md) for the full reference.

## GTKWave translate filters and filter processes { #filters }

For compatibility with existing GTKWave libraries — and for symbolic decoding driven by an external program — WaveCrux reads GTKWave filters directly.

**Translate filters** map a signal's values to symbolic names — an opcode value to its mnemonic, for instance. Right-click a signal and choose **Assign Translate Filter…**, then pick a GTKWave `.txt` translate filter file; existing GTKWave filter libraries work without modification. **Remove Translate Filter** takes it off again.

**Filter processes** hand the translation to an external program, exactly as GTKWave's filter processes do: WaveCrux starts the program once, writes each value to its standard input as a hex string, and shows the line it prints back (an empty line keeps the raw value). Choose **Set Translate Filter Process…** on a signal and pick the executable; **Clear Translate Filter Process** removes it. Filter processes need a desktop build, since they run a local program.

!!! note "Context menu"

    Right-click a signal row — or long-press it on touch — to reach the per-signal actions: display format, color, analog rendering, translators and filters, copy value and path, and related commands.
