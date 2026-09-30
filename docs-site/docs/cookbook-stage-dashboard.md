# Build a live Stage dashboard

Rows of transitions are precise but abstract. Stage binds your signals to widgets that animate as the cursor scrubs — an LED lights, a gauge sweeps, a board comes alive — so you read system behavior the way the hardware would have shown it. This recipe builds a small dashboard from scratch and brings it to life.

Goal
:   Bind signals to animated Stage widgets and a virtual board, then scrub the cursor to watch them update live.

Time
:   About 10 minutes

Tier
:   Open Core for the Stage panel, layout, built-in widgets, and educational boards. The <span class="tier tier-pro">Pro</span> curated pack and Pro boards are premium content.

You will use
:   The [Stage panel](stage.md), widget binding, and the per-instance config editor.

## Before you start { #before }

Stage runs on desktop and tablet device classes — it is not available on phone, where there is no room to lay out widgets beside the waveform. Have a trace loaded whose signals you want to visualize: a top-level port, a bus, a status register, or a single bit of a wider vector all make good bindings.

## Steps { #steps }

1. **Open the Stage panel.**

    Toggle Stage with ++cmd+shift+g++ / ++ctrl+shift+g++. A default Stage panel is created immediately — a free-form canvas that opens as a tab in the bottom dock.

2. **Add a widget.**

    Click **Add Widget** in the Stage tab's strip to open the picker, then choose a built-in primitive to start — an **LED** for a single bit, a **seven-segment display** or **bus readout** for a value, a **level bar** or **signal graph** for a numeric trend. The built-in primitives are free and carry no tier badge.

3. **Bind a signal to it.**

    Select the widget to open its **Signal Bindings** pane, then drag a signal from the signal tree or signal list onto a binding slot — or tap **Bind a signal…** and pick one. It can be a single signal, a bus, a top-level port, or one bit or slice of a wider vector. The widget renders that signal's value *at the cursor* — the Stage is always a view of the signal state at the current cursor time, whether you move the cursor by hand or let playback advance it for you.

    !!! note "Composite widgets bind by role"

        A board, a bus dashboard, or a memory map binds several signals at once, often by role — clock, address, data, enable. A widget that expects a particular bit width validates its binding per instance and falls back to defaults if a binding is missing or the wrong shape.

4. **Configure the widget.**

    Widgets with knobs — sample rate, color depth, gauge range, character columns — expose them in the **Configuration** section of the same pane. Each instance is configured independently, so two copies of the same widget can hold different settings, and the configuration persists with the session.

5. **Add a board or more widgets.**

    Drop in an FPGA board widget — **Digilent Basys 3**, **Nexys A7**, **Arty A7**, or **Terasic DE10-Lite** are free — and bind your top-level ports using the board's constraint-file pin names; the board's **Auto-bind** button matches your port names for you, and binding a bus such as `led[15:0]` to `led0` offers to **Bind all** the numbered slots at once. Its virtual LEDs, switches, and seven-segment digits then react as the cursor moves. Higher-end boards (Nexys Video, DE10-Nano, Zybo Z7) and the curated peripheral and instrument widgets are <span class="tier tier-pro">Pro</span>.

6. **Arrange the layout.**

    Drag widgets to position them, use the resize handles to size them, set z-order for overlaps (**Bring to Front**, **Send to Back**, …), and nudge with the arrow keys for precise placement. Every edit is undoable with ++cmd+z++ / ++ctrl+z++ and redoable with ++cmd+shift+z++ / ++ctrl+shift+z++. Layout is never Pro-gated.

7. **Scrub to bring it alive.**

    Move the cursor — drag it, step edges with ++q++ / ++e++, or jump to a marker with ++shift+m++ then a letter — and every widget re-evaluates and redraws at the new cursor time. The Stage saves with the session, so the dashboard is there when you reopen the trace.

8. **Press ++space++ to play it.**

    To watch the dashboard run rather than scrub it, use the playback transport in the Stage tab's strip: press ++space++ and the cursor advances across the trace on its own while every widget animates in sync. Set the speed, loop the whole trace or just an A–B span between two cursors, and leave follow-playhead on to keep a zoomed-in run in view. See [Playing the Stage](stage.md#playback) for the full transport reference.

!!! tip "Build your own widget"

    The Stage widget SDK is Open Core and free — the curated pack is premium content, not a gate on authoring. If none of the built-ins fit, you can build your own from a Rive file. See [Authoring Rive widgets](authoring-rive-widgets.md) for exactly what a Rive file needs — a default artboard and state machine, and inputs named like your bindings — to run on the Stage.

## Where to go next { #next }

[The Stage panel](stage.md) documents every built-in and curated widget and the per-instance config system. [Authoring Rive widgets](authoring-rive-widgets.md) walks through building a custom one.
