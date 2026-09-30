# The Stage panel

Stage is an animated signal-visualization panel. You bind signals to widgets, and those widgets update live as the cursor scrubs through the waveform — a virtual board lights up, a gauge sweeps, a terminal prints — so you read system behavior the way the hardware would have shown it, not as rows of transitions.

## What Stage is { #what-stage-is }

A Stage is a free-form canvas of widgets that lives as a top-level tab in the bottom dock, below the waveform. Each widget is bound to one or more signals: you pick a signal — a single bit, a bus, a top-level port, or a slice of a wider vector — and the widget renders that signal's current value at the cursor. As you move the cursor — by scrubbing, stepping edges, or jumping to a marker — every widget on the Stage re-evaluates at the new cursor time and redraws. The Stage is always a view of the signal state at the cursor; the built-in [playback transport](#playback) simply advances that cursor for you, automatically, so a design that changes over time plays back like an animation instead of something you scrub by hand.

Toggle the Stage panel with ++cmd+shift+g++ / ++ctrl+shift+g++ (**View → Toggle Stage Panel**) — turning Stage on creates a default panel immediately, as a tab in the bottom dock. Stage is available on desktop and tablet device classes; on a phone the panel explains that it needs a larger display, because a phone screen is too small to lay out and read widgets alongside the waveform.

### How to put a signal on the Stage { #put-a-signal-on-stage }

1. **Open Stage.**

    Toggle the panel with ++cmd+shift+g++ / ++ctrl+shift+g++ (desktop and tablet).

2. **Add a widget.**

    Click **Add Widget** in the Stage tab's strip to open the **Add Stage Widget** picker, then choose a widget — an LED, a seven-segment display, a level bar, a bus readout, a board — to drop it on the canvas. (Use **New Stage Panel** if you want a second panel to organize widgets across — each Stage panel is its own top-level tab in the bottom dock, and **Rename Stage Panel** names it.)

3. **Bind a signal.**

    Select the widget to open its **Signal Bindings** pane, then fill a binding slot: drag a signal from the signal tree or the signal list onto the slot, or tap **Bind a signal…** to pick one. When you bind a wider bus to a 1-bit slot, WaveCrux asks which bit to use — or, on a board with a numbered row of slots such as `led0`…`led15`, offers to **Bind all** slots to their matching bits in one step.

4. **Configure and scrub.**

    Set any per-instance knobs in the **Configuration** section of the same pane, then move the cursor — the widget re-evaluates and redraws at every new cursor time.

For a full dashboard with a virtual board, follow the cookbook recipe [Build a live Stage dashboard](cookbook-stage-dashboard.md).

!!! note "Binding, briefly"

    Most primitives bind to a single signal. Composite widgets — a board, a bus dashboard, a memory map — bind several signals at once, often by role (clock, address, data, enable), and boards offer **Auto-bind** to match your port names for you. A widget that expects a particular bit width validates its binding per instance and falls back to defaults if a binding is missing or the wrong shape.

## Playing the Stage { #playback }

Scrubbing the cursor by hand is fine for picking apart a single event, but when you want to *watch* a design run — an FSM walk its states, a frame paint, a gauge sweep — let WaveCrux drive the cursor for you. The Stage has a built-in **playback transport** — play/pause, speed, loop, and follow controls in the Stage tab's strip (not the main toolbar) — that advances the primary cursor through time at a steady rate, so every signal-bound widget animates together. Because it is the ordinary cursor that moves, the waveform canvas, the value column, and the Stage all stay in lock-step — playback is not a separate mode, just an automatic scrub.

Press ++space++ (**View → Play / Pause Stage Playback**) to play or pause at any time, or use the transport buttons. Playback is available wherever the Stage is — desktop and tablet — and each tab keeps its own playback state, so switching tabs never disturbs a run in another.

### How to play a Stage { #playback-how-to }

1. **Bind at least one widget.**

    Put a widget on the Stage and bind it to a signal (see above). The transport always shows, but there is nothing to watch until something is bound.

2. **Choose where to start.**

    Playback runs across the whole trace, resuming from the primary cursor when it sits inside it. To repeat just one span instead, place the primary and secondary cursors at its two ends and choose **Loop A–B** (below).

3. **Press ++space++.**

    The cursor advances and every bound widget animates. Press ++space++ again to pause where it is.

4. **Tune speed, looping, and follow.**

    Use the transport's speed, loop, and follow-playhead controls (below) to get the run you want.

### The transport controls { #playback-controls }

| Control | What it does |
|---|---|
| Play / Pause | Starts or pauses playback. Bound to ++space++. |
| Playback speed | How fast to play, expressed as wall-clock seconds to traverse the range: **5 s**, **10 s** (default), or **30 s**. Because it is defined by duration, it behaves the same whether your trace spans nanoseconds or seconds. |
| Loop | **No loop** (default) stops at the end of the trace. **Loop range** wraps back to the start and keeps going. **Loop A–B** repeats just the span between your two cursors — offered only when a secondary cursor is set. |
| Follow playhead | When on (the default), the viewport re-centers on the playhead when it scrolls off-screen, so a zoomed-in run keeps the action in view. Turn it off to hold the viewport still and let the cursor sweep across it. |

!!! tip "A repeatable demo loop"

    For a hands-off demo — a class, a design review, a recorded walkthrough — frame the interval with two cursors, set **Loop A–B**, pick a comfortable speed, and press ++space++. The Stage cycles that exact window indefinitely while you talk.

## Built-in widgets { #built-in-widgets }

The built-in widgets ship with Open Core and carry no tier badge. They cover the everyday cases — a bit, a small bus, a numeric level, a discrete state — plus a Rive reference widget and two processor-design instruments.

| Widget | What it shows |
|---|---|
| LED | A single bit as an on/off indicator. |
| Toggle Switch | A single bit rendered as a physical switch position. |
| Seven-Segment Display | A numeric value across one or more seven-segment digits. |
| Level Bar | A numeric value as a filled bar against a configurable range. |
| State Indicator | A discrete encoded value shown as a named state. |
| Bus Readout | A multi-bit bus shown as a formatted value (hex, decimal, binary, and so on). |
| Signal Graph | A mini time-series plot of a signal over a configurable window around the cursor. |
| Tachometer | An animated Rive gauge — the reference widget for [authoring your own](authoring-rive-widgets.md). |
| RVFI Commit Inspector | Reads a core's riscv-formal (RVFI) ports: the commit stream, architectural register and memory state folded to the cursor, traps, and consistency checks you can click through to the retirement that broke. |
| Pipeline Diagram | Rows of in-flight instructions against clock cycles, shaded by stage, for any pipeline you describe with per-stage valid / stall / flush signals — a five-stage `IF`/`ID`/`EX`/`MEM`/`WB` preset included. It states when its tracking confidence is low rather than drawing a plausible guess. |

## FPGA board widgets { #fpga-board-widgets }

The educational FPGA board widgets are free Open Core content. Each is a stylized rendering of a real development board. You bind your top-level ports using the board's constraint-file pin names, and the board's virtual LEDs, switches, seven-segment digits, and buttons react as the cursor moves — so a simulation of your top module reads like the physical board on your desk.

- **Digilent Basys 3**
- **Digilent Nexys A7**
- **Digilent Arty A7**
- **Terasic DE10-Lite**

## Layout and per-instance configuration { #layout-and-config }

The layout editor is free. You arrange the Stage directly: drag widgets to move them, use the resize handles to size them, set z-order for overlapping widgets (**Bring to Front**, **Bring Forward**, **Send Backward**, **Send to Back**), and nudge with the arrow keys for precise placement. Every edit is undoable with ++cmd+z++ / ++ctrl+z++ and redoable with ++cmd+shift+z++ / ++ctrl+shift+z++ (**Tools → Undo Stage Edit** / **Redo Stage Edit**) while the Stage panel is open. Authoring and layout are never Pro-gated.

Widgets with knobs — sample rate, color depth, character columns, gauge ranges, and so on — expose them through a schema-driven config editor. Each instance is configured independently: two copies of the same widget on one Stage can hold different settings. A widget's configuration persists in the session, and missing or invalid values fall back to that widget's defaults rather than failing.

!!! tip "Build your own widget"

    The Stage widget SDK — the capability to author and run custom widgets — is Open Core and free. The curated pack below is premium *content*, not a gate on authoring: you can always build your own. See [Authoring Rive widgets](authoring-rive-widgets.md) for exactly what a Rive file needs to run on the Stage.

## Curated Pro widget pack <span class="tier tier-pro">Pro</span> { #curated-pro-pack }

The curated pack is a set of high-fidelity, ready-to-use widgets for common peripherals, instruments, and protocols. These are premium content; the underlying SDK that runs them is free.

### Animated mechanisms { #animated-mechanisms }

Vector-drawn mechanisms with real state machines behind them. Each one renders what your logic actually emitted rather than tidying it up — an impossible state shows as an impossible state, which is the point.

| Widget | What it shows |
|---|---|
| BLDC Motor | A three-phase brushless-DC motor: rotor speed, per-coil phase polarity, commutation events and an over-current fault, driven from your gate-drive signals. |
| Traffic-Light Intersection | A four-way intersection with north–south and east–west heads driven independently, a pedestrian WALK signal, and an all-red flash/fault mode. Both directions green at once renders faithfully. |
| Elevator / Lift | Cab position, doors, direction lantern, a two-digit floor readout, and an overload fault that layers over the current pose. Cab position and readout are independent, and an out-of-range floor (`07` on a four-floor shaft) is drawn as-is rather than masked. |

Widget Design & Rive Animation by Jennifer Phillips · [jenniferphillipscreative.com](https://jenniferphillipscreative.com)

### DSP scope { #dsp-scope }

The canonical signal-processing instruments, driven straight from a numeric sample bus in your trace over a cursor-anchored window — no capture hardware and no export to a separate tool.

| Widget | What it shows |
|---|---|
| Spectrum Analyzer | Magnitude versus frequency from a real or IQ sample bus — dB or linear, with a peak marker and frequency readout — plus a time × frequency spectrogram / waterfall. |
| X-Y / Constellation | **Lissajous** mode draws a continuous X-Y trace with a phosphor-decay trail, for gain, phase and general two-signal relationships. **Constellation** mode plots one point per symbol-clock edge with density accumulation and an optional ideal N-QAM grid, for QPSK / QAM / PSK datapaths. |
| Eye Diagram | A sampled serial signal folded modulo one unit interval and overlaid into the classic density-shaded eye, with an optional eye-height / eye-width measurement overlay. For SerDes and signal integrity in simulation. |

### Processor design { #processor-design }

Instruments for people building cores, alongside the free RVFI Commit Inspector and Pipeline Diagram.

| Widget | What it shows |
|---|---|
| Tag-Tracked Pipeline | A pipeline diagram driven by the identity your design already carries (a tag or ROB index), so multiple instructions per stage, out-of-order completion, tag reuse and multiple harts draw correctly, with stall- and flush-cause shading. |
| Cycle Accounting | Over a window around the cursor, attributes every cycle to retiring or to one of up to eight named causes, with a per-cause histogram and a cycles-per-retire ratio. |
| Branch-Predictor Scoreboard | Mispredict rate with its divisor and window shown, an optional BTB/BHT hit rate, a mispredict timeline, and the worst addresses disassembled. |
| CSR & Trap Inspector | `mstatus`, `mie`, `mip`, `mcause`, `mtvec`, `mepc`, `mtval` and their S-mode equivalents decoded into named bitfields at the cursor, changed bits highlighted, and a trap timeline. |

### Advanced peripherals { #advanced-peripherals }

| Widget | What it shows |
|---|---|
| Framebuffer | Reconstructs a frame from address, data, and sync traffic. |
| Audio Waveform | Time-domain plot plus FFT spectrum, with configurable sample rate and bit depth, mono or stereo. |
| Character LCD | A dot-matrix character display emulator (for example 16×2 or 20×4). |
| OLED Graphic Display | A graphic OLED panel emulator. |
| 3-Axis Orientation | Orientation from accelerometer, gyroscope, or sensor-fusion data. |
| PS/2 Keyboard / Mouse Visualizer | A PS/2 keyboard or mouse activity visualizer. |
| RGB LED | A multi-channel color LED. |

### Engineering instruments { #engineering-instruments }

| Widget | What it shows |
|---|---|
| Gauge Cluster | 2–6 radial or linear gauges with warning/critical zones, labels, and units. |
| PWM Analyzer | Live duty cycle, frequency, and edge count, plus a mini-scope view. |
| Memory Map Viewer | A sparse memory image reconstructed from address, data, and enable bus traffic. |
| Register File Viewer | Live register state rebuilt from write-port activity, with per-write change indicators. |

### Protocol / communication { #protocol-communication }

| Widget | What it shows |
|---|---|
| UART Terminal | A VT-100-subset terminal: bind the TX and/or RX lines and it decodes the UART frames itself and prints the byte stream. |
| SPI/I²C Bus Dashboard | A device-perspective transaction log with optional address→device-name mapping; click a log row to jump the cursor to that transaction. |

## Pro FPGA boards <span class="tier tier-pro">Pro</span> { #pro-fpga-boards }

The Pro board widgets cover higher-end development boards whose richer peripherals — HDMI, audio codecs, ADCs, and accelerometers — are wired into the Stage primitives, so the board's outputs come alive in the same way the educational boards do.

- **Digilent Nexys Video**
- **Terasic DE10-Nano**
- **Digilent Zybo Z7**

!!! info "Unlocked in the beta, licensed from 1.0"

    The curated Pro widget pack and the Pro FPGA boards are unlocked for everyone through the 0.8.x public beta; from 1.0 they need a Pro license key. The <span class="tier tier-pro">Pro</span> badges above mark which widgets and boards that covers — the unbadged [built-in widgets](#built-in-widgets) and [educational FPGA boards](#fpga-board-widgets) are Open Core and stay free, as does [authoring your own Rive widgets](authoring-rive-widgets.md). See [Tiers & licensing](licensing.md) for how the license key system works.
