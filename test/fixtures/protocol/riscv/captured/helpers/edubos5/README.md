# RISC-V captured-fixture helpers (Chili.CHIPS eduBOS5, RVFI)

Rebuild recipe for `riscv_edubos5_rvfi_reset.fst`, the corpus's second
real-core RVFI capture.

The Ibex capture in `../ibex/` was the first trace whose signal names,
hierarchy, widths and retirement timing were chosen by somebody else. This
one comes from an unrelated core and design team:
[eduBOS5](https://github.com/chili-chips-ba/openPCIE/tree/a0d80cd3cb525f911cae61be4c83a44e137ed916/2.rtl/0.common.opensource/src/CPU.eduBOS5),
the RV32I CPU of Chili.CHIPS' openPCIE (BSD-3-Clause), simulated with
Verilator and `+define+RISCV_FORMAL`, and observed through the core's own
`wavecrux/soc_cpu_view.sv`, the module its authors wrote to expose eduBOS5's
RVFI outputs under the riscv-formal names.

## Why eduBOS5 is not vendored

eduBOS5 lives inside the openPCIE repository. The `Makefile` fetches the
pinned commit:

```
OPENPCIE_SHA := a0d80cd3cb525f911cae61be4c83a44e137ed916
```

with a single-commit shallow fetch and a sparse checkout of
`2.rtl/0.common.opensource/src/CPU.eduBOS5/` only (five files are compiled:
`edubos5_pkg.sv`, `edubos5_rf.sv`, `edubos5_alu.sv`, `edubos5.sv` and
`wavecrux/soc_cpu_view.sv`). Nothing in them is modified. `make distclean`
removes the checkout.

## No RISC-V toolchain required

`assemble.py` hand-encodes the eight RV32I instructions and writes a
`$readmemh` image (`prog.hex`) and a listing (`prog.lst`).

eduBOS5 has separate instruction and data memories, and the testbench keeps
them separate, as the core's own `formal/rvfi_wrapper.sv` does:

| Memory | Address | Purpose |
|--------|---------|---------|
| IMEM   | 0x000   | reset vector: eduBOS5 resets its PC to 0 |
| DMEM   | 0x100   | data scratch |

## Files committed here

- `tb_edubos5_rvfi.sv`: our testbench. Clock, reset, the two 1 KiB
  memories, eduBOS5 with `EN_WAIT4REGS = 0` (the default 2-stage pipeline)
  and the core's `soc_cpu_view` instantiated as `cpu_view`. The memories
  follow `formal/rvfi_wrapper.sv`: IMEM is a synchronous one-clock read with
  `imem_rdy` tied high; a DMEM read (a request with no write strobes) is
  answered with `dmem_rdy` for one clock, on the clock after the request,
  which is the fastest behaviour the wrapper's free `dmem_ready` allows. It
  also prints a text account of every retirement to `sim.log`. SPDX `0BSD`.
- `assemble.py`: the RV32I encoder. SPDX `0BSD`.
- `trim.py`: the waveform filter (the Ibex helper's, with a different
  whitelist). SPDX `0BSD`.
- `Makefile`: `make` fetches, builds, runs and trims; `make install`
  copies the FST into both the `test/` and `verification/` trees.
- `riscv-formal/`: a separate, manual reproduction about riscv-formal's
  `ill` check on the same core and commit. Not part of the fixture and not
  run by CI; see its own `README.md`.

## Why there is a trim step

As with Ibex, Verilator ignores the scope and level arguments to `$dumpvars`,
so the raw dump holds the whole testbench and core. `trim.py` keeps
`tb_edubos5_rvfi.clk`, `tb_edubos5_rvfi.arst_n`, and the 21 RVFI channels at
`tb_edubos5_rvfi.cpu_view.rvfi_*`, and fails loudly if any whitelisted
signal is missing. Result: **1524 bytes** (6522 raw).

Verilator dumps three of the kept channels, `rvfi_trap`, `rvfi_halt` and
`rvfi_intr`, under a single FST identifier: eduBOS5 ties all three low
(`edubos5.sv:649-651`), and they are one constant signal with three names.
That is upstream's waveform, kept as is, and it matters to a reader that
indexes signals by their reference rather than by name; the test pins it.

## Rebuild

```
cd test/fixtures/protocol/riscv/captured/helpers/edubos5
make && make install
```

Requires `verilator` (5.x, built with FST support), gtkwave's `fst2vcd` and
`vcd2fst`, `python3`, and `git` 2.25 or later. On macOS the `Makefile`
locates Homebrew's `lz4` for Verilator's FST writer. If the first
`fst2vcd` on `PATH` does not run (an x86_64 GTKWave.app bundle on Apple
silicon, for example), point the build at working converters:
`make FST2VCD=/opt/homebrew/bin/fst2vcd VCD2FST=/opt/homebrew/bin/vcd2fst`.

The decoded snapshot (`riscv_edubos5_rvfi_reset.expected_transactions.json`)
was written from `prog.lst` and the testbench's `sim.log`, not from WaveCrux
output, and then checked against the decoder sweep
(`test/services/decoders/riscv_captured_fixtures_test.dart`), which it
matched on the first run. If the capture is ever re-made, the same applies:
`REGENERATE=1` on that sweep rewrites the snapshot from the decoder, so
compare the result with `prog.lst` and `sim.log` before committing it, and
copy it to `verification/fixtures/protocol/riscv/captured/` as well.

The waveform is deterministic. Rebuilding from clean reproduces the
committed FST byte for byte except for the date string in its header, which
`vcd2fst` copies from the VCD `$date`. In the checks made when the fixture
was committed, only the time of day in that string differed.

## The program

| addr  | word         | assembly            | note |
|-------|--------------|---------------------|------|
| 0x000 | `0x00000093` | `addi x1, x0, 0`    | reset vector |
| 0x004 | `0x10000193` | `addi x3, x0, 0x100`| data base |
| 0x008 | `0x00108093` | `addi x1, x1, 1`    | loop: |
| 0x00c | `0x0011a023` | `sw x1, 0(x3)`      | word store at 0x100 |
| 0x010 | `0x0001a103` | `lw x2, 0(x3)`      | word load from 0x100 |
| 0x014 | `0x00208233` | `add x4, x1, x2`    | x4 = 2 * x1 |
| 0x018 | `0x004182a3` | `sb x4, 5(x3)`      | byte store at 0x105 |
| 0x01c | `0xfedff06f` | `jal x0, -20`       | back to loop: |

The testbench holds reset (`arst_n` low) from time zero through the rising
clock edges at 5 and 15 ns, releases it at 20 ns, and stops at 510 ns, on
the falling edge after the third `jal` has retired. That is 2 + 3 x 6 = 20
real retirements, `rvfi_order` 0 to 19, the first at 25 ns.

## What the capture shows at time zero

The RVFI stream has 21 retirements, not 20. The extra one is at time zero,
before the first clock edge, while `arst_n` is low:

| | time | `rvfi_order` | `rvfi_pc_rdata` | `rvfi_pc_wdata` | `rvfi_insn` |
|---|---|---|---|---|---|
| retirement #0 | 0 ns  | 0 | 0x0 | 0x4 | 0x00000000 |
| retirement #1 | 25 ns | 0 | 0x0 | 0x4 | 0x00000093 (`addi x1, x0, 0`) |

How it arises, at the pinned commit:

- `rvfi_valid = (state == FETCH_INSTR)` (`edubos5.sv:647`): a decode of the
  FSM state alone, with no reset term. `FETCH_INSTR` is `3'd0`
  (`edubos5.sv:72`).
- The FSM resets asynchronously
  (`always_ff @(negedge arst_n or posedge clk)`, `edubos5.sv:394`) into
  `EXECUTE` (`edubos5.sv:397`). `arst_n` is already low at time zero, so
  there is no falling edge of `arst_n`, and in an event-driven simulation
  the reset branch first runs at the first rising clock edge, 5 ns.
- Until then `state` holds its power-up value. Verilator powers registers
  up at zero (`+verilator+rand+reset+0`, its default, passed explicitly by
  the `Makefile`), and zero is `FETCH_INSTR`. So `rvfi_valid` is high from
  0 to 5 ns.
- The reset branch clears `rvfi_order` (`edubos5.sv:691`) and nothing has
  incremented it, so the first real retirement repeats order 0.

After 5 ns the FSM is in `EXECUTE` and `rvfi_valid` stays low for the rest
of reset. The core executes the program correctly; the phantom is only in
its RVFI account of the start of reset. WaveCrux's consistency checker
reports it as two violations on retirement #1, `orderRegression` (order 0,
then 0) and `controlFlowDiscontinuity` (#0 claims next PC 0x4, #1 fetched
from 0x0), and the other 19 retirements are clean. riscv-formal cannot see
it: its harness asserts reset in the first cycle, its checks ignore
`rvfi_valid` while reset is asserted, and SymbiYosys models the asynchronous
reset with `async2sync`, so the power-up window does not exist in the formal
model. Full write-up in
`test/services/riscv/riscv_edubos5_captured_rvfi_test.dart`.

If upstream later keeps `rvfi_valid` low until the reset branch has run, a
re-capture will show 20 retirements and no violations, and the test's
expectations change with it.

## Limits of this capture

- **Two-state only.** Verilator has no `x`/`z`. A four-state simulator
  starts `state` at `x` rather than zero, so it would not show this window
  the same way; this capture says nothing about X-propagation and the test
  asserts the absence of unknown bits.
- **One retirement per cycle**, scalar RVFI ports: nothing about packed
  NRET detection.
- **2-stage pipeline only** (`EN_WAIT4REGS = 0`). The 3-stage configuration
  has the same `rvfi_valid` decode and the same reset state, but it is not
  captured here.
