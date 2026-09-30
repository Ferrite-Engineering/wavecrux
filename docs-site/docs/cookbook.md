# Cookbook

The rest of these docs explain what each tool *is*. The Cookbook shows you how to put the tools together to get something done. Each recipe is a complete task — start with a file, end with an answer — written as numbered steps you can follow at the keyboard. They are short on purpose: a recipe is a worked example, not a manual.

!!! tip "No file handy?"

    Every recipe works against a waveform you already have, but if you just want to follow along, generate a synthetic trace from inside the app with ++cmd+alt+g++ / ++ctrl+alt+g++ (*Generate test VCD*), or grab a ready-made lab trace from [Educational packs](educational-packs.md).

## Recipes { #recipes }

- [Find a bug by diffing two runs](cookbook-find-a-bug.md) — Load a known-good run and a failing run side by side, jump to the first divergence, and trace it back to the signal that broke. **~10 min · Free**
- [Decode a bus from raw signals](cookbook-decode-a-bus.md) — Turn raw SPI, I²C, or UART wires into a readable transaction table — attach a decoder, fix the bindings, set the protocol options, and read the traffic. **~5 min · Free**
- [Measure clock & timing](cookbook-measure-timing.md) — Use the two cursors to read a clock period and frequency, a pulse width, and the latency between two events — without doing the arithmetic yourself. **~3 min · Free**
- [Build a live Stage dashboard](cookbook-stage-dashboard.md) — Bind signals to animated widgets and an FPGA board, then scrub the cursor and watch your design come alive the way the hardware would show it. **~10 min · Free + Pro**

## How each recipe is laid out { #how-recipes-work }

Every recipe opens with a short summary box — the goal, a rough time, the tier you need, and the features it exercises — followed by numbered steps. Keyboard shortcuts are written macOS first (++cmd++), with the ++ctrl++ equivalent for Linux, Windows, the web, and Android. Where a step leans on a feature covered in depth elsewhere, it links straight to that page so you can go deeper without leaving the workflow.

!!! note "More on the way"

    This is the opening set of recipes. If there is a workflow you keep repeating and would like written up — a migration from another viewer, a verification sign-off pass, a bring-up checklist — that is exactly the kind of thing the Cookbook is meant to grow into.
