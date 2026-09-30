# WaveCrux examples

Ready-to-open sessions. Launch WaveCrux, then **File → Open File**
(`Cmd/Ctrl+O`) and pick the `.wavecrux` in one of the directories below.
There is no separate "open session" menu item — the file picker accepts
`.wavecrux` alongside `.vcd` / `.fst` / `.ghw`, and WaveCrux routes it to
the session loader, opening the trace named inside it at the same time.

Each session names its trace **relative to its own directory**, so it works
from any checkout with no editing and nothing to install.

| Example | What it shows | Needs |
|---|---|---|
| [`five-buses/`](five-buses/five-buses.wavecrux) | Five protocol decoders running at once — SPI, I²C, UART, AXI4-Lite and APB — over one 60 µs trace, with the signals already grouped per bus and the **Transactions** dock tab open. | Nothing |
| [`pipeline-diagram/`](pipeline-diagram/pipeline-diagram.wavecrux) | Stage: a Pipeline Diagram tile reconstructing a classic five-stage in-order pipeline from `valid` / `stall` / `flush` pins, next to the raw lanes it was built from. | Nothing |
| [`annotations/`](annotations/annotations-demo.wavecrux) | Waveform annotations — callouts, an arrow, a full-height band and a lane band — anchored to `(tick, signal)` rather than pixels, plus the **drift** behaviour you can trigger by editing the trace. | Nothing |
| [`annotation-review/`](annotation-review/bus-review.wavecrux) | The same feature as a **real review**: a FIFO overflow found, argued and annotated across a request/grant/burst trace. `annotations/` is the fixture whose notes are deliberately broken; this is the one that shows what a finished review looks like. | Nothing |

None of them needs a simulator, a cross-compiler, a decoder plugin or a
network connection. Every trace is committed beside its session.

## `five-buses/` — what to click

The five buses are five sibling scopes in one VCD (`spi_tb`, `i2c_tb`,
`uart_tb`, `axi4lite_tb`, `apb_tb`), so this is the "one dump, several
unrelated interfaces" shape a real testbench produces.

1. The **Transactions** tab in the bottom dock is already populated — five
   decoder instances are baked into the session and re-run against the trace
   the moment it opens.
2. Click any row. The cursor jumps to that transaction and the waveform
   scrolls to it.
3. The **APB** group opens collapsed. Click the group header to expand it and
   see that groups persist collapsed/expanded state in the session.
4. The AXI4-Lite address and data lanes are set to hexadecimal and the
   handshake lanes to binary. To change one, right-click its row in the
   **Values** panel and pick **Display Format** — the format menu hangs off the
   value column, not the signal tree, and both the lane and the value follow.

Baud matters here: `uart_tb` runs at 1 Mbaud, not the 9600 default, and the
session carries that parameter. A UART decoder pointed at this trace with
default settings finds nothing — which is worth seeing once, because it is
the single most common reason a real UART decode comes up empty.

## `pipeline-diagram/` — what to click

1. One Stage panel opens in the bottom dock. Its tab reads **Pipeline** —
   Stage tabs carry the panel's own name, and this session named it — and it
   holds a single Pipeline Diagram tile. Rows are in-flight instructions,
   columns are cycles, and each cell is the stage that instruction occupied
   that cycle.
2. Click a cell. The cursor moves to that cycle, and the raw `stage*_valid` /
   `stage*_stall` / `stage*_flush` lanes on the left show you the bits the
   cell was derived from.
3. The trace contains a **stall** and a **flush**, and both are visible as a
   shape in the grid rather than as a number you have to hunt for.

The widget is architecture-neutral — its id is the bare `pipeline`, there is
no ISA content in it, and the stage names `IF` / `ID` / `EX` / `MEM` / `WB`
are free-text config you overwrite for your own design. It happens to be
configured here for the classic five-stage pipeline because that is the
shape most people recognise.

Positional tracking is a shift-register model of a pipe: correct for a
single-issue in-order core, wrong for anything wider. The widget checks its
own model against the observed `valid` bits every cycle and says so in a
banner when they disagree, rather than drawing a plausible lie.

## `annotations/` — what to click

See [`annotations/README.md`](annotations/README.md) for the full walkthrough.
The short version: open the session, confirm every balloon, arrow and band
stays glued to its edge as you pan and zoom, then edit one value in the trace
and reopen to watch the affected note flag itself as **drifted** rather than
quietly continuing to assert something the design no longer does.

## `annotation-review/` — what to click

See [`annotation-review/README.md`](annotation-review/README.md) for the
design and the bug it documents. The short version: a bus master bursts writes
into a 16-deep FIFO, `wr_en` is generated from the *previous* cycle's count,
and two beats are already committed by the time `fifo_full` asserts — so the
second one overflows. The notes walk that argument in order.

It exists separately from `annotations/` because the two want opposite things.
`annotations/` is the verification fixture: its notes are *supposed* to be
broken — an orphaned row, a signal that does not exist, a drifted witness — so
the status rules can be exercised. Those are the right cases to test and the
wrong ones to photograph.

## Where the traces come from

`five-buses.vcd` and `pipeline-diagram.vcd` are byte-identical copies of
fixtures already in the repository, and
[`test/examples/examples_test.dart`](../test/examples/examples_test.dart)
fails if either copy drifts:

- `five-buses.vcd` ← `verification/fixtures/protocol/multi/all5_basic.vcd`,
  generated by `tool/generate_multi_coexistence_fixture.dart` from the five
  single-bus decoder fixtures. Its five `.expected_transactions.json`
  companions are what the guard compares the decode against.
- `pipeline-diagram.vcd` ←
  `test/fixtures/protocol/riscv/generated/riscv_pipeline_5stage.vcd`.

`annotations-demo.vcd` is the exception: it is hand-authored for this example
rather than copied, because no corpus fixture is a five-signal handshake short
enough to read at a glance. What it must keep meaning is pinned instead by
`test/examples/annotations_demo_session_test.dart`, which asserts the exact
witness value the annotation README tells you to edit away from.

The copies live here on purpose. `verification/fixtures/` is the right home
for a corpus and the wrong place to send someone opening WaveCrux for the
first time — a directory named "fixtures" reads as internal scaffolding.

## The guard

[`test/examples/examples_test.dart`](../test/examples/examples_test.dart)
loads every session through the real `SessionService`, opens the trace each
one names through the real `WellenProvider`, and then re-derives **every
baked reference** against that trace: every signal path, every signal ref,
every Stage pin and every decoder binding. It also runs all five decoders
through the registry factories and compares the result to the committed
expectations.

That matters because a `.wavecrux` stores Stage and decoder bindings as
backend-local signal refs, and restore does not re-resolve them; the signal
list is re-resolved by path, and an entry whose path matches nothing is
dropped *without an error*. Both failure modes open to a window that is
merely emptier than intended. Nothing here asserts a file exists and calls
that a pass.

## The plugin examples

Two other directories here are for developers rather than evaluators — they
are source you build, not sessions you open:

| Example | What it is |
|---|---|
| [`decoder-plugin-demo/`](decoder-plugin-demo/README.md) | A 1-Wire protocol decoder written in C against the WaveCrux decoder plugin ABI, with a `Makefile`, a `CMakeLists.txt` and its own fixture. Needs a C toolchain. |
| [`decoder-plugin-demo-rust/`](decoder-plugin-demo-rust/README.md) | The same plugin ABI from Rust. Needs `cargo`. |
