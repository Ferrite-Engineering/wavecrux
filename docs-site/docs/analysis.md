# Analysis & debug

WaveCrux ships a set of analysis tools that go beyond reading values off the canvas: comparing two runs, tracing where an unknown originated, searching for a multi-signal condition, visualizing state machines, and correlating testbench logs against the timeline. Most of these are Open Core; the Debug Advisor and SystemVerilog assertion visualization are Pro. There is also a separate, experimental [AI assistant](ai-assistant.md) that builds on these same engines — covered on its own page. Many of these tools have a keyboard shortcut; the full reference lives in [Navigating & measuring](navigating-waveforms.md).

## Waveform comparison (diff) { #diff }

Compare the waveform in the current tab against a second run with **Tools → Compare Waveforms** (++cmd+shift+c++ / ++ctrl+shift+c++). WaveCrux asks for the second file and matches signals between the two: it matches on the exact hierarchical path first, then — when the root scope differs — on the path below the root, so a renamed top-level module does not break the comparison of everything underneath it.

The comparison opens a **Diff** tab in the left dock with a summary — how many matched signals are identical, how many differ, and how many exist only in A or only in B — followed by the **Matched signals** and **Unmatched signals** lists. Regions where the two runs diverge are highlighted on the canvas, and a toolbar above it reads *Divergence N of M*. Step between divergences with ++f7++ (next) and ++shift+f7++ (previous). For every matched signal the diff also builds an **XOR trace** — a 1-bit lane that is high wherever the two runs disagree (for a bus, wherever any bit differs).

1. **Open the reference run.**

    Open the first file with ++cmd+o++ / ++ctrl+o++.

2. **Start the comparison.**

    Press ++cmd+shift+c++ / ++ctrl+shift+c++ and pick the second run. Diverging regions are highlighted on the canvas and the Diff tab opens.

3. **Step the divergences.**

    Jump through them with ++f7++ (next) and ++shift+f7++ (previous). The first divergence is usually the cause; everything after it is downstream fallout.

4. **Confirm the match.**

    Check the unmatched list so a signal you cared about was not silently left out of the comparison. **Compare with…** on the toolbar swaps in a different second file; **Close comparison** ends it.

This is the spine of the cookbook recipe [Find a bug by diffing two runs](cookbook-find-a-bug.md), which carries it through to the root-cause signal.

!!! tip

    The below-the-root fallback is what makes a golden-vs-DUT comparison work when the two testbenches wrap the design under test in differently named top scopes. `x` and `z` are compared literally — an `x` in one run against a `0` in the other is a divergence.

## X-trace { #x-trace }

X-trace answers a single question: where did this `X` come from? Starting from a signal that reads `X` at the cursor, WaveCrux walks backward through that signal's own transitions to the **first tick of its current unknown streak** — the moment it went `X` — and reports the value it was holding just before. It then lists the other signals in the same scope that were *also* `X` at that same instant, because co-temporal unknowns across neighbouring signals are a strong hint they share an upstream cause.

1. **Land the cursor on the unknown.**

    Place the primary cursor at a time where the signal reads `X`.

2. **Trace the origin.**

    Right-click the signal in the signal list (long-press on touch) and choose **Trace X Origin** — the item appears when the value at the cursor contains an `X`. The **X-Trace** panel opens showing *Became X at &lt;time&gt;* and *Was: &lt;value&gt;* — the exact tick it went unknown and the last good value it held.

3. **Inspect the co-temporal suspects.**

    Under the **Co-temporal X in scope** heading, the panel lists sibling signals that were unknown at the same tick. Tap any entry to jump the cursor to that signal's own X-start time and keep tracing.

!!! note "How it works"

    WaveCrux works from the waveform alone — it has no RTL netlist — so X-trace does not walk a gate-level fan-in chain. Rather than guess at drivers it cannot see, it gives you the precise origin time, the last known-good value, and the co-temporal suspects in the same scope. Pair it with [RTL source annotation](#rtl-annotation) below — or the Pro [Debug Advisor](#debug-advisor) — to connect that origin back to the line of HDL that drove it.

## Switching activity { #switching-activity }

Switching activity (++cmd+shift+a++ / ++ctrl+shift+a++, or **Tools → Analyze Switching Activity**) counts how often each signal changes value and ranks the busiest nets. It analyses the signals you have **added to the viewer**, over the **currently visible time range** — so you can zoom to a window of interest and measure activity just there. When it finishes, the **Switching Activity** report docks at the bottom automatically and a colour heatmap is painted onto the signal-tree rows, so the hot nets are obvious at a glance.

The report is a sortable table — click any column header to re-sort:

- **Signal** — the hierarchical path.
- **Transitions** — value-change count over the analysed window (the time-0 initial dump is excluded).
- **Toggle Rate** — transitions per unit time, the default sort (busiest first).
- **Clock / Frequency / Duty Cycle** — for 1-bit signals whose edges are periodic, WaveCrux flags a **CLK** candidate and reports the estimated frequency and duty cycle.

Click a row to select that signal in the waveform, or use **Export CSV** to take the full table into a spreadsheet. Re-run the action after panning or zooming to re-measure over the new visible window.

!!! note

    The heatmap is a fast way to spot a net that is toggling far more — or far less — than you expect, which often points at a missing enable, a free-running clock left ungated, or a stuck line that never moves. A line that should clock but shows no detected frequency is just as telling as one that toggles too much.

### Exporting switching activity as SAIF { #saif }

**File → Export Waveform…** offers **SAIF (switching activity)** alongside VCD, PNG and SVG. SAIF — the Switching Activity Interchange Format — is what power-analysis tools read, so this is how you hand a simulation's activity to PrimePower, Joules or PowerArtist without re-running anything.

The export uses the same signal and time-range choices as a VCD export: the signals you are looking at, over the window you are looking at, or everything loaded over the whole simulation. For each bit of each signal WaveCrux writes the time spent at 0, at 1, at `x` and at `z`, plus the toggle count.

!!! note

    **WaveCrux does not estimate power**, and this export is not a power report. Power needs cell capacitance and leakage from a PDK's Liberty data, which WaveCrux does not read. What it gives you is the half of the calculation that requires actually running a simulation — and which your power tool would otherwise ask you to produce anyway. Two details worth knowing: time before a signal's first recorded value is reported as *unknown* rather than as logic 0, and only genuine 0↔1 edges count as toggles, so a settle out of `x` does not inflate an energy estimate.

## Multi-signal pattern search { #pattern-search }

Multi-signal pattern search (++cmd+shift+f++ / ++ctrl+shift+f++, **Search → Multi-Signal Pattern Search**) finds the moments where a condition across *several* signals holds at once — for example, the next time a `valid` line is high **AND** a data bus equals `0xFF` **AND** an `enable` is `1`.

The dialog offers two ways to express the condition:

- **Builder** — **Add Condition** for each row (signal, operator, value), negate any row with its **NOT** toggle, and join the rows with **AND** / **OR**. No syntax to remember.
- **Expression** — type the condition directly, e.g. `(clk == 1) AND (data == 0xFF)`. Supported comparisons are `==`, `!=`, `>`, `<`, `>=`, `<=`, plus bitwise `&` / `|`; combine terms with the uppercase keywords `AND`, `OR`, `NOT` and parentheses. Values may be decimal, hex (`0xFF`), or binary (`0b1010`). Use signal names from the tree, or full paths (`scope.name`, including bit ranges such as `top.cpu.data[7:0]`) to disambiguate.

1. **Write the condition.**

    Build it row-by-row or type the expression, then choose the **Time Range**: **Visible**, **Full Simulation**, or a **Custom** start/end range.

2. **Search.**

    Press **Search**. A toolbar appears showing *N of M* matches, with the current match highlighted on the timeline; adjacent matching regions are merged into one match.

3. **Step the matches.**

    Jump between them with ++f3++ (next) and ++shift+f3++ (previous); the cursor lands on each match in turn. **Clear search** removes the highlights.

!!! note

    A signal that is `x` or `z` at the evaluated time never satisfies a comparison — including `!=` — so unknowns are skipped rather than reported as spurious matches.

## FSM visualization { #fsm }

Point WaveCrux at a state register and it draws a bubble diagram of the state machine: each distinct value the signal takes becomes a state, and every value change becomes a directed transition labelled with how many times it fired. As you scrub the timeline the **current state lights up in sync with the cursor**, so you can watch the machine walk its sequence. The diagram pans and zooms (drag, pinch, or scroll), and clicking a state jumps the cursor to the first time the machine entered it.

1. **Open the diagram.**

    Right-click the state-register signal in the signal list and choose **Visualize as FSM**. The bubble diagram opens as a tab in the bottom dock (a sheet on phones), titled *FSM: &lt;signal path&gt;* with a *N states · M transitions* summary.

2. **Name the states (optional).**

    Raw encodings like `0`, `1`, `2` are hard to read. If the signal already carries a named-enum format or a GTKWave translate filter, WaveCrux uses those names automatically. Otherwise right-click the signal and choose **Annotate FSM states…** to give each numeric value a readable name; the names are saved with the session. See [Working with signals](working-with-signals.md) for value-display formats and translate filters.

3. **Walk the machine.**

    Scrub the timeline and watch the active state highlight follow the cursor. Click a state bubble to jump to its first occurrence; read the count on each edge to see which transitions dominate and which fire only once.

!!! note

    Detection works on any integer-valued signal. `x` / `z` samples are skipped rather than charted as states, and a signal that never changes shows as a single trivial bubble — itself a useful signal that a state machine is wedged. Clarity is best up to a couple of dozen states; beyond that the bubble layout gets dense.

## Cocotb log correlation { #cocotb }

A cocotb run prints a timestamped log; the waveform records what the signals did. Cocotb log correlation lines the two up so a failing message in the log points straight at the waveform state at the moment it printed. WaveCrux parses cocotb's default log format — reading each line's **sim-time, severity, logger name, and message** — and understands time units from `fs` through `s` (bare tick counts are taken in the waveform's own timescale).

1. **Load the log.**

    Open **Tools → Load Cocotb Log** and pick the log your testbench wrote. The entries appear in the **Cocotb Log** panel (toggle it any time with **View → Toggle Cocotb Log Panel**), and a thin marker strip is drawn above the canvas — one tick per entry, coloured by severity.

2. **Narrow to what matters.**

    Filter the list by **test name**, by **severity** (Trace / Debug / Info / Warning / Error / Critical), and by keyword — the three combine, and the header shows how many of the total entries are currently visible. Test pass/fail lines are called out with a **Passed** / **Failed** pill.

3. **Jump to the waveform.**

    Click any log line to move the cursor to that timestamp and pan the canvas there. Right-click a line (long-press on touch) for **Jump to Time**, **Copy Message**, or **Copy Timestamp**. A failing assertion in the log is now one click from the exact cycle that produced it.

!!! note

    Lines without a parseable timestamp (continuation lines, tracebacks) still appear in the list and inherit the severity of the entry above them, but they have no timeline marker and clicking them does not move the cursor. Loading a new log replaces the previous one; **Tools → Clear Cocotb Log** removes it.

## RTL source annotation { #rtl-annotation }

RTL source annotation (desktop only) shows your Verilog or VHDL source alongside the waveform, with the selected signal's value annotated at the current cursor position and updating live as you scrub. It pairs the *what* (signal values over time) with the *why* (the line of HDL that drove them).

The panel is driven by a **stems file** — a mapping from signal hierarchy paths to source-file locations. WaveCrux can **generate one for you** directly from your HDL (no external tools required), **import Verilator's elaborated AST** for exact per-instance accuracy, and it also loads existing GTKWave-compatible stems files (`xml2stems` / `vermin` output).

1. **Generate a stems file from your sources**

    Open **Tools → Generate RTL Stems…**. **Add Files…** (`.v`, `.sv`, `.vhd`) or **Add Folder…** to scan a tree, optionally fill in **Top module** (leave it blank to auto-detect a unique top), and click **Generate & Load**. WaveCrux parses the module hierarchy, asks where to save the `.stems` file, and loads it automatically.

2. **…or import Verilator's elaborated AST**

    If you simulate with Verilator, run it with `--json-only`, open **Tools → Import Verilator AST (JSON)…**, **Choose AST File…** and pick the `V<top>.tree.json` it emits (the sibling `.tree.meta.json` is found automatically), then **Import & Load**. Because the dump is post-elaboration, generate loops arrive unrolled (`gen_blink[0]`, `gen_blink[1]`, …) and every mapping carries the exact per-instance path your waveform uses. WaveCrux writes the result as a portable `.stems` file and loads it — useful even outside WaveCrux, since Verilator 5.x removed the XML output that GTKWave's `xml2stems` consumed.

3. **…or load an existing stems file**

    Already have one (for example from GTKWave's `xml2stems` / `vermin`)? Use **Tools → Load RTL Stems File…**, or the **Load Stems File…** button in the panel's empty state.

4. **View values at the cursor**

    Toggle the panel with ++cmd+shift+r++ / ++ctrl+shift+r++ (or **View → Toggle RTL Source Panel**). Select a signal in the signal list and the source view scrolls to its declaration; its value at the cursor is shown and tracks the cursor as you move it.

5. **Navigate in both directions**

    Select a signal to jump to its source line; click an identifier in the source to add that signal to the waveform.

!!! note "Desktop only"

    The in-app source panel and stems generation are desktop features; they are not offered on phones, tablets, or in the browser.

## Debug Advisor <span class="tier tier-pro">Pro</span> { #debug-advisor }

The Debug Advisor (**Tools → Toggle Debug Advisor Panel**, ++cmd+shift+b++ / ++ctrl+shift+b++) is a **rule-based heuristic engine — not an LLM**. It surfaces likely problems **for the current cursor position** as a ranked list of suggestions, each with a severity (Info / Warning / Error) and a confidence percentage. The list re-computes as you move the cursor, so it reads the part of the run you are actually looking at rather than dumping every issue in the file at once.

It checks four families of rules:

- **X-propagation chain** — signals in a scope that went unknown within a few ticks of the focus signal's X-start, pointing at a shared upstream `X` source.
- **Possible clock-domain crossing** — data transitions tied to differently named clocks, close together, with no synchronizer between them.
- **Signal appears stuck** — a non-trivial-width signal that held one value for at least 95% of the loaded simulation window, often an undriven net, a tie-off, or a line only set during reset.
- **Setup/hold proximity** — a data signal that switched within a few ticks of a clock edge, below the heuristic setup/hold window.

Each suggestion explains itself in plain language with the specific signals, clocks, and tick deltas filled in, and gives you actions: **tap to jump** the cursor to the evidence, **Learn more** for the rule's full rationale, **View causal chain** (on X-propagation findings) to seed [X-trace](#x-trace) with the focus signal, and **Accept** / **Dismiss** to clear a lead you have judged.

!!! note "Heuristics, not proofs"

    Without an RTL netlist the rules reason from waveform shape alone, so each finding is a lead to investigate with the signals and timestamp already in hand. Confirm an X-propagation finding with [X-trace](#x-trace), or a stuck-at finding against the [RTL source](#rtl-annotation), before treating it as the cause.

## AI assistant *(experimental)* { #ai }

The Debug Advisor above is a fixed set of rules. The [AI assistant](ai-assistant.md) puts a model on top of those same engines: you connect **your own** API key (Anthropic, OpenAI, Google, or a local Ollama model), then ask questions in plain English. A free **Explain Selection** gives a single-shot, grounded explanation of any region you select; the <span class="tier tier-pro">Pro</span> **AI Waveform Assistant** works agentically — searching signals, querying decoded transactions, and running the Debug Advisor and [X-trace](#x-trace) on your behalf to find a condition, explain a region with follow-ups, or hypothesise why a design hung.

The guiding rule is that every answer is **grounded**: each claim cites real signal data, and clicking it jumps the cursor to that evidence so you can verify it. WaveCrux runs no model and ships no key — you choose the provider and your data goes only where you send it. It is experimental and off by default. The full how-to lives on the dedicated [AI assistant](ai-assistant.md) page.

## SystemVerilog assertion (SVA) visualization <span class="tier tier-pro">Pro</span> { #sva }

SVA visualization (**View → Toggle SystemVerilog Assertion Panel**, ++cmd+shift+v++ / ++ctrl+shift+v++) brings your simulator's assertion results onto the waveform. It parses the assertion log, auto-detects the format — **Verilator**, **VCS**, or **Questa** — and renders each evaluation as a coloured band on the timeline: pass, fail, vacuous (the precondition never triggered), and cover.

1. **Load the results.**

    Choose **Tools → Load SVA Results** and pick your simulator's assertion log. WaveCrux detects the format (shown as a badge in the panel header) and bands appear on the timeline; the **SystemVerilog Assertions** panel auto-opens.

2. **Scan the summary.**

    The panel lists each assertion by hierarchical name with its source location, evaluation count, and the timestamp of its **First failure**. Filter with the **PASS / FAIL / VACUOUS / COVER** chips, a source-file selector, or a name keyword.

3. **Jump to a failure.**

    Click an assertion (or **Jump to first failure**) to move the cursor to its first failing event and see exactly what the signals were doing when it fired.

!!! note

    A vacuous result is worth a second look — it means the assertion never actually evaluated, so a "no failures" run may simply not have exercised it. Combine a failing band with [cocotb log correlation](#cocotb) to read the assertion message and the waveform at the same instant. **Tools → Clear SVA Results** removes the overlay.

!!! info "Unlocked in the beta, licensed from 1.0"

    The Debug Advisor and SVA visualization are Pro features. Through the 0.8.x public beta they are unlocked for everyone and nothing is gated; from 1.0 they need a Pro license key. The <span class="tier tier-pro">Pro</span> badges above mark which features that covers — everything on this page without a badge is Open Core and stays free. See [Tiers & licensing](licensing.md) for the full picture.
