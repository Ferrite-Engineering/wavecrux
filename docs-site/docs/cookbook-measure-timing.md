# Measure clock & timing

A clock period, a pulse width, the latency between a request and its acknowledge — these are the measurements you take constantly, and WaveCrux reads them straight off the trace with two cursors. This recipe covers all three, plus how to land on exact edges so the numbers are right.

Goal
:   Read a clock period and frequency, a pulse width, and the delay between two events directly off the waveform.

Time
:   About 3 minutes

Tier
:   Open Core.

You will use
:   The [primary and secondary cursors](navigating-waveforms.md#cursors), [transition stepping](navigating-waveforms.md#transitions), and markers.

## Before you start { #before }

Bring the signal you want to measure onto the canvas. The two-cursor delta works on any pair of points in time, so the same steps measure a clock period, a pulse, or the gap between edges on two different signals. The key habit is to snap the cursors to real edges rather than eyeballing the click — the next two steps cover that.

## Steps { #steps }

1. **Place the primary cursor near the first edge.**

    Click in the waveform canvas or on the time ruler above it. The status bar reports the cursor time in units auto-scaled to the file's timescale, so the unit always matches the resolution of the trace.

2. **Snap it exactly onto the edge.**

    Select the signal and step with ++e++ (next transition) and ++q++ (previous). These move the primary cursor to the precise time of the signal's change — no modifier key — so your measurement starts on a real edge instead of an approximate one.

3. **Drop the secondary cursor on the second edge.**

    ++shift++ + click or right-click to place the secondary cursor on the next rising edge of the clock (for a period) or wherever the interval ends — on touch, long-press and choose **Place Secondary Cursor Here**. With both cursors down, the status bar shows the **Δ** between them and a derived frequency (`f:`) — the clock period and its frequency in one glance, no arithmetic.

4. **Measure a pulse width.**

    Same move, different edges: put the primary cursor on a rising edge and the secondary on the *following falling* edge of the same signal. The Δ readout is the high-time; swap the edges for the low-time.

5. **Measure cross-signal latency.**

    Put the primary cursor on the edge of a `req` and the secondary on the responding edge of `ack` — the Δ is the request-to-acknowledge latency. Because the two cursors are independent of which signal is selected, they measure across any pair of signals.

6. **Keep reference points with markers.**

    If you are taking the same measurement at several places, drop named markers with ++m++ then a letter and jump back with ++shift+m++ then the letter. Clear the secondary cursor with ++shift+esc++ and both cursors with ++esc++.

!!! tip "Let the tool find the clock"

    For a quick estimate without placing cursors at all, run [switching activity](analysis.md#switching-activity) (++cmd+shift+a++ / ++ctrl+shift+a++) over the signals on the canvas — it flags periodic 1-bit signals as clocks and reports an estimated frequency and duty cycle for each. When you zoom in to place cursors, ++cmd++ / ++ctrl++ + scroll wheel zooms around the mouse pointer, so hover over the edge you are measuring.

## Where to go next { #next }

[Navigating & measuring](navigating-waveforms.md) has the full cursor, zoom, and marker reference, including the complete keyboard map.
