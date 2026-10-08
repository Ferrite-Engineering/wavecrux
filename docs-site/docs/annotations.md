# Annotations

Annotations are notes you write directly on a waveform — a balloon on an edge, an arrow at a transition, a shaded band over a window of time. They are anchored to the data rather than to the picture, they travel with the session, and they can be packaged into a single file you can send to a colleague who has never seen your dump. Annotations are part of Open Core and free in every tier. Sharing them *live*, in a session with other people, is described in [Automation & collaboration](automation-and-collaboration.md#collaborative-viewing): from WaveCrux 1.1, anyone can join a session and write notes in it, and hosting one is the Enterprise feature.

!!! note "Not the same as RTL source annotation"

    [RTL source annotation](analysis.md#rtl-annotation) is a different feature — it shows your Verilog or VHDL beside the waveform. This page is about notes you write yourself.

## Writing a note { #authoring }

There are three routes to the same thing, because the right one depends on what you have in your hands:

- **Option-click (Alt-click) a signal lane.** The fast one. Click where you want the note and start typing. This is the gesture the Annotations panel names in its own empty state.
- **Edit ▸ Add Annotation at Cursor** (++shift+a++). The one that works without a pointing device. It needs a cursor placed and exactly one signal row selected — "at the cursor, on that signal" has no answer otherwise — and WaveCrux says *“Select exactly one signal to annotate”* if the selection is missing rather than leaving the menu item mysteriously greyed.
- **Edit ▸ Annotate Selected Range.** Draws a band rather than a balloon. It reads a ++shift++-drag time selection when there is one and falls back to the span between your two cursors when there isn't, so you can bracket a window either way.

A note holds up to about 280 characters comfortably; the hard ceiling is 1000. Keep them short — an annotation is a margin note, not a report.

### The three shapes { #shapes }

| Shape | What it is | Anchored to |
|---|---|---|
| **Callout** | A balloon of text with a leader line back to the point it describes. | One time on one signal. |
| **Arrow** | A leader line and anchor dot with no balloon — *“this edge, here.”* | One time on one signal. |
| **Band** | A shaded time span with a label. Full-height across every lane for *“this whole transaction is wrong,”* or confined to a single lane when the point is about one signal. | A time range, optionally one signal. |

### Adjusting one { #editing }

- **Double-tap a note's text** on the canvas to edit it in place.
- **Drag a balloon** to move it out of the way. This moves the *label* and provably not the anchor — the leader line stretches and the note stays attached to the tick it describes. Getting these two confused is how annotation systems usually go wrong, so they are kept in separate coordinate spaces.
- **Collapse one** to a numbered dot when the canvas gets busy (*Collapse on canvas* in the panel's row menu). A fold, not a hide — it is still listed, still exported, still part of a walkthrough.
- **Set anchor time…** in the row menu retypes the anchor in ticks, for when you know the exact cycle and would rather not aim at it with a mouse. A time outside the trace is clamped, and WaveCrux tells you where it landed instead.

## What a note is attached to { #anchoring }

An annotation is anchored to a **time in ticks and a signal's full path** — never to a screen position, and never to a row number. Pan, zoom, reorder your signals, group them, hide and re-show them: the notes track their signals. Nothing about the anchor is expressed in pixels.

Nor is any *formatted* time stored. A persisted `1.25 us` would be wrong the moment the timescale changed, so the model holds the raw tick and formats it for display against whatever file is open.

## Drift — when the design moves under a note { #drift }

This is the part a callout drawn on a screenshot cannot do. When you write a note, WaveCrux also records **what the signal was doing at that moment** — a witness. Every time the session is loaded, it re-reads the signal and compares. If they disagree, the note renders in **amber** and the panel marks it *Drifted*:

!!! note "What the panel says"

    Amber marks a note whose signal no longer reads what it did when the note was written — the design changed under it.

So the workflow the feature is really for is: annotate a bug today, fix the RTL, re-simulate, reopen the session next week — and the claims that no longer hold flag themselves. Drift is not an error. The note is intact and may still be worth reading; what changed is the design underneath it.

The witness is stored as canonical bits rather than as a formatted value, deliberately. If it were formatted, flipping a row from hex to decimal would make every note on it report drift while the design had not moved — and a badge that fires on a display preference is one people learn to ignore.

A note can be in one of a few states:

| State | Meaning |
|---|---|
| **Resolved** | The signal is on screen and still reads what it read. |
| **Drifted** | The signal is on screen but no longer matches the witness. |
| **Not displayed** | The signal exists in this file but isn't currently in your signal list, so there is no lane to draw against. Use *Show signal* in the panel to bring it back. |
| **Not in this file** | No signal with that path exists here — a note written against a different design, or a signal since renamed. |

The last two are grouped at the bottom of the panel rather than piled onto the top edge of the canvas. A note with nowhere to point is still yours and still readable; it just has no lane.

## The Annotations panel { #panel }

The panel is the list view of everything on the trace, in time order. Open it with **View ▸ Annotations Panel** (also in the command palette) — even on a trace with no notes yet, where its empty state names the Option-click gesture. It gives you:

- Every note with its time, signal path and author, sortable by **Time**, **Author** or **Created**.
- A **Filter annotations…** box, and a **Drifted only** toggle for the "what did my change break" pass.
- Per-row actions: *Edit text*, *Collapse* / *Expand on canvas*, *Set anchor time…*, *Show signal*, *Delete*.
- The walkthrough transport — see below.

!!! tip "Hiding the notes and closing the list are different things"

    **View ▸ Show Annotations** (++cmd+shift+n++ / ++ctrl+shift+n++) hides the annotation layer on the canvas — useful for a clean look at the waveform, and it is honoured by image exports. Closing the panel just closes the list; the notes stay drawn. The panel's close button closes the panel rather than clearing what it displays, because what it displays is your writing.

## Walkthrough — handing someone a document { #walkthrough }

An annotated waveform with six notes on it is a picture until somebody knows what order to read them in. The walkthrough turns it into a document:

- **Next Annotation** (++bracket-right++) and **Previous Annotation** (++bracket-left++) step through the tab's notes in time order, centring each, expanding it and folding the one before.
- **Play Walkthrough** does the same on a timer, with a dwell you set in seconds — for a demo, or for an unattended loop on a second screen.
- Stepping past the last note wraps to the first and says so (*“Back to the first annotation”*). Silence there reads as the key not having worked.

Stepping is *reading*, not editing: the folding and unfolding it does is not recorded as an edit, so the **Undo** offered after you delete a note still restores that note. The three walkthrough actions are hidden entirely when the tab has no annotations rather than sitting greyed out in every session that never annotates.

This is also, almost exactly, the interaction a guided lab wants — see [Educational packs](educational-packs.md).

## Where annotations live { #persistence }

Annotations are saved in the `.wavecrux` session document alongside your signal list, cursors and layout. They also persist **per trace**, independently of any tab: close a tab and reopen the same dump tomorrow and your notes come back. That is what makes drift meaningful at all — the whole premise is that you return days later, and a note that did not survive until then could never flag anything.

A session document you explicitly saved wins over the per-trace record, because a file you chose to save is a stronger statement about what belongs to that waveform than an autosave.

## Notes from a review, kept as a group { #layers }

When a collaborative session ends, the notes other people wrote during it are offered to you as a group:

*“12 annotations were made in this session by 3 people. Keep them?”*

**Keep all**, **Keep only mine**, or **Discard**. Anything you keep becomes a named **layer** — labelled with the date and the number of participants — that you can hide, show, or delete as a unit, separately from *My notes*. So a meeting's output does not silently become permanent clutter on your trace, and it does not silently vanish either.

A note adopted from somebody else is read-only as to its words: *hide, delete or duplicate it, but its words stay its author's*. **Duplicate as mine** makes an editable copy under your own name if you want to build on what they said.

## Sending an annotated waveform — `.wavecruxpack` { #sharing }

**File ▸ Share Annotated Waveform…** writes a single self-contained file: the session with its annotations, the part of the waveform those notes actually refer to, and a preview image. Open one on a machine that has never seen the original dump and the whole annotated view comes back.

This exists because a bare `.wavecrux` session *references* a dump the recipient does not have, so mailing one opens to nothing on the other end. A pack is the first WaveCrux artifact that is both self-contained and small enough to travel. The bundled time range is the annotated span with some context either side — or the visible range when nothing is annotated yet — and the signals are the ones in your view.

!!! note "In the browser"

    In the browser build the pack downloads instead of opening a save dialog, and the preview image stays inside the pack rather than also landing beside it. Opening a pack works everywhere.

### You are shown exactly what leaves { #disclosure }

Before anything is written, WaveCrux shows a step titled **“This will leave your machine.”** It lists:

- The **signal paths** going in — the actual paths, not a count.
- The **time range**, and whether it was chosen from your annotations or from the visible window.
- The **author names** embedded in the notes, with a **Strip author names** option.
- The approximate **size**, with a warning when it is larger than most mail servers accept as an attachment.

Packaging design data to leave your machine is the exception in WaveCrux, not the rule, so showing you the manifest is the feature, not friction. There is also a hard ceiling: a selection too large to bundle is refused with a suggestion to narrow the range or show fewer signals, rather than quietly producing something unmailable.

### Opening one { #opening-a-pack }

Open a `.wavecruxpack` the way you open any other file. WaveCrux treats every pack as untrusted input — entries that would escape the extraction directory, symbolic links, and archives that expand to more than it will extract are all refused before a byte is written, and a file that is not really a pack is named as such rather than reported as "no session inside".

## Annotations in image exports { #exports }

**File ▸ Export Waveform…** draws annotations into PNG and SVG output when the layer is visible, with an **Include annotations** control in the dialog. In SVG they are real elements rather than flattened pixels. Exports match what the application draws — same palette, same per-signal colours, same sizing.

## In a live session { #live-sessions }

Everything above is free. In a collaborative session (from 1.1 anyone can join one, and an **Enterprise** seat hosts it), annotations also become a shared surface: notes you write reach everyone in the room, the host carries them so somebody joining late gets the whole conversation rather than only what happens after they arrive, and a chip shows where a colleague is composing before their note exists. When the meeting ends, **File ▸ Export Review Minutes…** writes the session's notes as Markdown or CSV — time-ordered, with author, wall clock, signal path and the time in the file's own timescale — so the review lands in a ticket instead of in somebody's memory.

Attribution is not negotiable in a session: a participant cannot add a note as somebody else, edit one they did not write, or delete one they neither wrote nor host. The full picture, including how sessions are admitted and encrypted, is in [Automation & collaboration](automation-and-collaboration.md#collaborative-viewing).

!!! note "Related"

    For what a `.wavecrux` session holds and how it resolves its waveform, see [Files & sessions](files-and-sessions.md). For cursors, markers and the time measurements annotations anchor against, see [Navigating & measuring](navigating-waveforms.md). For the full keyboard list, see [Keyboard & mouse reference](keyboard-mouse.md).
