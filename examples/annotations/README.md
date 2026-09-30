# Annotation demo

A hand-authored fixture for exercising **waveform annotations** without
authoring any first.

```
File ▸ Open…  →  examples/annotations/annotations-demo.wavecrux
```

The session references `annotations-demo.vcd` by a **relative** path, so the
pair travels together — open the `.wavecrux`, not the `.vcd`.

## What you should see

| Annotation | Expect |
|---|---|
| `req asserts here…` | A balloon with a leader line to the rising edge of `req` at 200 ns |
| `bus should read a3…` | A balloon on `bus` at 500 ns, rendered **normally** — its witness matches the committed trace |
| (arrow on `ack`) | A leader line and anchor dot at 500 ns, **no balloon** |
| `handshake window` | A translucent full-height band from 200 ns to 700 ns |
| `bus driven` | A band confined to the `bus` lane, 400–700 ns |
| `authored collapsed` | A numbered **dot** rather than a balloon |
| `top.spare` note | **Nothing on the canvas** — the signal is not displayed |
| `top.does_not_exist` note | **Nothing on the canvas** — no such signal in this file |

Those last two are the point of the orphan rule: persistent annotations with no
lane to draw against are surfaced by the Annotations panel, never
piled onto the top edge of the canvas.

## Verifying the anchor

Pan and zoom. Every balloon, arrow and band must stay glued to the tick it
marks — they are anchored to `(tick, signal path)`, not to pixels. Scroll the
lane list vertically and they should track their rows.

## Verifying drift — the interesting one

**Copy the pair somewhere scratch first:**

```bash
cp -r examples/annotations /tmp/ann-demo   # then open /tmp/ann-demo/annotations-demo.wavecrux
```

The committed trace is guarded by a test asserting the shipped example opens
**not** drifted, so editing it in place leaves the repo red until you revert.
Working on a copy keeps that guard meaningful and your tree clean.

1. Open the session and note the balloon on `bus` renders normally.
2. Edit `annotations-demo.vcd`: find the line `b10100011 #` under `#400` and
   change it to, say, `b00000000 #`.
3. Let the file watcher auto-reload it (or reopen the session).

Annotations survive a reload of the same file on purpose — a re-simulation is
exactly when the witness has something to say, so wiping the notes at that
moment would delete the user's work right when it became useful. Opening a
*different* waveform does clear them.

The `bus` annotation should now render **drifted** — dashed leader line, amber
accent, italic text. Nothing was deleted and nothing errored: the note is intact
and is telling you the design underneath it changed. That is the behaviour a
callout drawn on a screenshot cannot have.

Change the value back and it returns to normal.

Changing the row's **display format** — right-click `bus`, switch hex to
decimal — must *not* drift it. The witness stores canonical bits, not a
formatted string, precisely so a radix preference cannot masquerade as a design
change. A badge that fires on a display setting is one users learn to ignore.
