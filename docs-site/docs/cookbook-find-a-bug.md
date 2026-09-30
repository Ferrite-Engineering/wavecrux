# Find a bug by diffing two runs

You have a run that works and a run that does not — a golden reference and a regression, or last night's pass and this morning's fail. This recipe walks from "something changed" to the exact signal and the exact instant it first went wrong, using waveform comparison and the cursors.

Goal
:   Locate the first point where a failing run diverges from a known-good run, and identify the responsible signal.

Time
:   About 10 minutes

Tier
:   Open Core. Debug Advisor (step 7) is <span class="tier tier-pro">Pro</span>.

You will use
:   [Waveform diff](analysis.md#diff), divergence stepping, [cursors](navigating-waveforms.md#cursors), [markers](navigating-waveforms.md#transitions) and [X-trace](analysis.md#x-trace).

## Before you start { #before }

You need two waveform files that represent the same design: a **golden** run you trust and the **failing** run you are debugging. Any supported format works (VCD, FST, GHW) and the two do not have to match formats. It is fine if the testbenches wrap the design in differently named top-level scopes — when the full paths differ, the comparison matches on the path below the top scope.

## Steps { #steps }

1. **Open the golden run.**

    Open the golden run with ++cmd+o++ / ++ctrl+o++ and add the signals you care about to the canvas.

2. **Compare it against the failing run.**

    Press ++cmd+shift+c++ / ++ctrl+shift+c++ (**Tools → Compare Waveforms**) and pick the failing run. WaveCrux matches signals by hierarchical path, falling back to the path below the top scope where the root differs, highlights every region where the two runs disagree, and opens the **Diff** tab in the left dock.

    !!! note "Check the unmatched list"

        The Diff tab lists signals present in only one run under **Unmatched signals**. Glance at it before you trust the result — if a signal you care about is sitting there, it was never compared.

3. **Jump to the first divergence.**

    Press ++f7++ to move the cursor to the next divergence — the first time, that is the earliest point the two runs differ. This is almost always where you want to be: the first divergence is the cause; everything after it is downstream fallout. ++shift+f7++ steps back.

4. **Find which signal differs.**

    Each compared signal gets an **XOR trace** beneath it that is high wherever the two runs disagree (for a bus, wherever any bit differs), so the lanes that light up at the cursor are your suspects. In the Diff tab, tap a signal marked as different to jump the cursor to where it first diverges.

5. **Snap to the exact edge.**

    Select the offending signal and step transition-by-transition with ++e++ (next) and ++q++ (previous) to land on the real edge rather than an approximate click. ++shift++ + drag across the moment and press ++z++ to zoom into just that window.

6. **Mark the spot so you can return.**

    Drop a named marker with ++m++ then a letter — say ++m++ then ++a++. Markers persist with the session, so you can roam the trace chasing the cause and jump straight back with ++shift+m++ then ++a++.

7. **Trace it back to the root cause.**

    If the divergence is an `X`, right-click the signal and choose **Trace X Origin**: [X-trace](analysis.md#x-trace) finds the tick it went unknown, the value it held before, and the other signals in its scope that went unknown at the same instant. For a wider sweep, open the [Debug Advisor](analysis.md#debug-advisor) <span class="tier tier-pro">Pro</span> (++cmd+shift+b++ / ++ctrl+shift+b++) — it flags X-propagation chains, clock-domain-crossing risks, stuck signals and setup/hold proximity at the cursor, each with a jump to the evidence.

!!! tip "When you do not have a golden run"

    No reference to diff against? Reach for [multi-signal pattern search](analysis.md#pattern-search) (++cmd+shift+f++ / ++ctrl+shift+f++) instead: write the condition that describes the bug — for example `valid == 1 AND data == 0xFF AND ready == 0` — and step through every moment it holds with ++f3++.

## Where to go next { #next }

[Analysis & debug](analysis.md) covers comparison, X-trace, and the Debug Advisor in full. [Navigating & measuring](navigating-waveforms.md) has the complete cursor, transition, and marker reference.
