# RISC-V captured-fixture helpers (OpenHW CV32E40X, RVFI)

Capture recipe for a Verilator run of OpenHW's
[CV32E40X](https://github.com/openhwfoundation/cv32e40x) with its
behavioural RVFI monitor, used to check WaveCrux's RVFI detection, retire
stream and consistency checker against a second real core after Ibex.

**Recipe only.** No FST fixture, expected-transactions snapshot or test is
committed from this directory yet, and there is no `make install`. The
results below were produced by running the two captures through WaveCrux
with the harness described under [Running the captures through
WaveCrux](#running-the-captures-through-wavecrux). Turning a capture into a
committed fixture is a separate step; see [Limits](#limits-of-this-capture)
for what that needs.

CV32E40X is a useful second core because its RVFI port is unlike Ibex's in
every way that matters to detection and decoding: the RVFI monitor is a
separate behavioural module (`bhv/cv32e40x_rvfi.sv`, instance `rvfi_i`)
rather than ports on the core, `rvfi_trap` and `rvfi_intr` are packed
structs (15 and 14 bits), the memory channels carry 128 slots
(`rvfi_mem_addr` is 4096 bits wide), and debug entry is reported on a
nonstandard `rvfi_dbg` channel.

## Why CV32E40X is not vendored

The Makefile fetches the pinned commit:

```
CORE_SHA := d952cd63bc1b4eb58cd893c28ef8283c781e345e
```

using a single-commit shallow fetch, as the Ibex helper does. Upstream's
`cv32e40x_manifest.flist` lists 52 RTL and behavioural files, and
CV32E40X is licensed under the Solderpad Hardware License v0.51
(SPDX `SHL-0.51`), so neither the tree nor anything derived from it is
carried here. `make distclean` removes the clone.

## No RISC-V toolchain required

`assemble.py` hand-encodes the program (RV32I, Zicsr, `mret`, `dret`,
`wfi`, and one Zcmp `cm.push`) and writes a `$readmemh` image.

Memory map (2 KiB, byte addresses 0x000-0x7FF):

| Region | Purpose |
|--------|---------|
| 0x000  | `mtvec` base: exceptions land here, `jal` to 0x100 |
| 0x01C  | `mtvec + 4*7`: machine-timer interrupt, `jal` to 0x140 |
| 0x080  | `boot_addr_i` (CV32E40X boots exactly at `boot_addr_i`) |
| 0x100  | exception handler |
| 0x140  | interrupt handler |
| 0x200  | data scratch |
| 0x3F0  | doorbell: a store raises `irq_i[7]` (MTIP) |
| 0x3F4  | doorbell: a store clears `irq_i[7]` |
| 0x3F8  | doorbell: a store raises `debug_req_i` (debug variant) |
| 0x600  | `dm_halt_addr_i`: debug handler (debug variant) |

## Files committed here

- `tb_cv32e40x_rvfi.sv`: our testbench. Clock, reset, a 2 KiB memory on
  separate OBI instruction and data ports (`gnt = req`, `rvalid` one cycle
  later), the three doorbells, and the `cv32e40x_wrapper` tie-offs, which
  follow cv32e40x-dv's `tb/uvmt/uvmt_cv32e40x_dut_wrap.sv`. Parameters are
  the wrapper defaults (RV32I + M, no A/B/X, no CLIC, `DEBUG=1`,
  `PMA_NUM_REGIONS=0`); Zca/Zcb/Zcmp are always present because `ZC_EXT`
  is a localparam of `cv32e40x_core`. `+prog=` and `+dump=` plusargs pick
  the program image and dump file. SPDX `0BSD`.
- `assemble.py`: the encoder. `--debug` emits the debug variant. SPDX `0BSD`.
- `patch_wrapper.py`: writes the Verilator-compatible wrapper copy, see
  below. SPDX `0BSD`.
- `trim.py`: the waveform filter, same approach as the Ibex helper. It keeps
  `clk`, `rst_n` and the 21 RVFI channels WaveCrux binds at their real
  hierarchical names (`tb_cv32e40x_rvfi.wrapper_i.rvfi_i.rvfi_*`) and fails
  loudly if any is missing. SPDX `0BSD`.
- `dump_retires.py`: an independent retire dump that shares no code with
  WaveCrux. It parses the VCD text directly and also prints `rvfi_dbg`,
  which the trimmed file does not carry, so run it on the raw VCD. Every
  retirement WaveCrux reported below was cross-checked against it. SPDX
  `0BSD`.
- `Makefile`: `make` fetches, builds, runs and trims the main capture;
  `make debug` runs the same simulator binary on the debug program.

Nothing in CV32E40X's `rtl/` or in `bhv/cv32e40x_rvfi.sv` is modified.

## Build notes

Three things are needed to get a correct capture out of Verilator. Each is
handled by the recipe; they are written down because each one fails
quietly or confusingly.

**`+define+COREV_ASSERT_OFF`.** The upstream wrapper `` `include``s ten SVA
files and `bind`s assertion modules into the core
(`bhv/cv32e40x_wrapper.sv:15-25` and `169-544`). The `sva/` files are not
on the manifest and a capture does not need them; the define drops both
blocks.

**The Verilator interface-alias crash.** The wrapper connects the RVFI
monitor's instruction-OBI probe with a hierarchical reference to an
interface instance inside the core:

```
.m_c_obi_instr_if ( core_i.m_c_obi_instr_if ),
```

Verilator 5.049 stops on this with `Internal Error: V3LinkDot ... No symbol
for interface alias rhs`. `patch_wrapper.py` writes
`cv32e40x_wrapper_vl.sv`, a copy of the wrapper in which that one actual is
replaced by a local `cv32e40x_if_c_obi` instance whose five members
(`s_req`, `s_gnt`, `req_payload`, `s_rvalid`, `resp_payload`) are driven
from `core_i.m_c_obi_instr_if` by continuous assignment. The monitor sees
the same values. The script asserts on both of its anchors, so an upstream
change to the wrapper fails the build instead of producing a different
design. The Makefile builds `cv32e40x.f` from upstream's manifest with the
wrapper swapped for the copy.

**Two-state reset at t=0.** Verilator has no `x`. A reset that is already
low at time zero never produces a `negedge rst_n`, so the core's
asynchronous resets never fire, and flops clocked by CV32E40X's gated clock
(which does not toggle during reset) keep Verilator's zero initialisation
instead of their reset value. The visible symptom was `mtvec.MODE` coming
up 0 (direct) instead of 1 (vectored), so the machine-timer interrupt
vectored to the wrong address. The testbench therefore starts `rst_n` high
and drives it low at t=1, then releases it after four clocks.

## Rebuild

```
cd test/fixtures/protocol/riscv/captured/helpers/cv32e40x
make              # cv32e40x_rvfi.fst
make debug        # cv32e40x_rvfi_debug.fst
python3 dump_retires.py raw_debug.vcd
```

Requires `verilator` (>= 5.0, built with FST support), gtkwave's `fst2vcd`
and `vcd2fst`, `python3`, and `git`. `make TOOLS=<dir>` prepends a tool
directory, an oss-cad-suite `bin/` for example, to `PATH`. On macOS the
Makefile locates Homebrew's `lz4` for you. Built and checked with Verilator
5.049 on macOS; both targets reproduce from a clean copy of this directory,
and the trimmed VCDs match the ones analysed below sample for sample (only
the `$date` header differs).

## The programs

### Main (`make`): 46 retirements

| addr  | word         | assembly                 | note |
|-------|--------------|--------------------------|------|
| 0x000 | `0x1000006f` | `jal x0, 0x100`          | exception vector |
| 0x01c | `0x1240006f` | `jal x0, 0x140`          | MTI vector |
| 0x080 | `0x12300093` | `addi x1, x0, 0x123`     | boot |
| 0x084 | `0x45600113` | `addi x2, x0, 0x456`     | |
| 0x088 | `0x002081b3` | `add x3, x1, x2`         | 0x579 |
| 0x08c | `0x40110233` | `sub x4, x2, x1`         | 0x333 |
| 0x090 | `0x20000293` | `addi x5, x0, 0x200`     | data base |
| 0x094 | `0x0032a023` | `sw x3, 0(x5)`           | word store |
| 0x098 | `0x0002a303` | `lw x6, 0(x5)`           | word load |
| 0x09c | `0x00618463` | `beq x3, x6, +8`         | taken |
| 0x0a0 | `0xfff00393` | `addi x7, x0, -1`        | **never retired** |
| 0x0a4 | `0x05a00413` | `addi x8, x0, 0x5a`      | |
| 0x0a8 | `0x00828223` | `sb x8, 4(x5)`           | byte store |
| 0x0ac | `0x0042c483` | `lbu x9, 4(x5)`          | byte load |
| 0x0b0 | `0x00329423` | `sh x3, 8(x5)`           | halfword store |
| 0x0b4 | `0x0082d503` | `lhu x10, 8(x5)`         | halfword load |
| 0x0b8 | `0x0041c5b3` | `xor x11, x3, x4`        | 0x64a |
| 0x0bc | `0x00300793` | `addi x15, x0, 3`        | loop counter |
| 0x0c0 | `0xfff78793` | `addi x15, x15, -1`      | loop: retired 3x |
| 0x0c4 | `0xfe079ee3` | `bne x15, x0, -4`        | backward, taken 2x |
| 0x0c8 | `0x00178463` | `beq x15, x1, +8`        | not taken |
| 0x0cc | `0x00000073` | `ecall`                  | traps to 0x000 |
| 0x0d0 | `0x08000813` | `addi x16, x0, 0x80`     | resume point (mepc + 4) |
| 0x0d4 | `0x30482073` | `csrrs x0, mie, x16`     | MTIE |
| 0x0d8 | `0x30046073` | `csrrsi x0, mstatus, 8`  | MIE |
| 0x0dc | `0x00100893` | `addi x17, x0, 1`        | |
| 0x0e0 | `0x1f12a823` | `sw x17, 0x1f0(x5)`      | raise `irq_i[7]` |
| 0x0e4 | `0x00000013` | `nop`                    | interrupt taken after this |
| 0x0e8 | `0x00000013` | `nop`                    | mepc of the interrupt |
| 0x0ec | `0x00000013` | `nop`                    | |
| 0x0f0 | `0x00000013` | `nop`                    | |
| 0x0f4 | `0x07700913` | `addi x18, x0, 0x77`     | last retirement |
| 0x0f8 | `0x10500073` | `wfi`                    | core sleeps; not retired in the capture window |
| 0x100 | `0x34202673` | `csrrs x12, mcause, x0`  | exception handler: 0xb |
| 0x104 | `0x341026f3` | `csrrs x13, mepc, x0`    | 0xcc |
| 0x108 | `0x00468693` | `addi x13, x13, 4`       | |
| 0x10c | `0x34169073` | `csrrw x0, mepc, x13`    | |
| 0x110 | `0x02a00713` | `addi x14, x0, 42`       | |
| 0x114 | `0x30200073` | `mret`                   | to 0x0d0 |
| 0x140 | `0x342029f3` | `csrrs x19, mcause, x0`  | interrupt handler: 0x80000007 |
| 0x144 | `0x34102a73` | `csrrs x20, mepc, x0`    | 0xe8 |
| 0x148 | `0x1e02aa23` | `sw x0, 0x1f4(x5)`       | clear `irq_i[7]` |
| 0x14c | `0x1f42aa83` | `lw x21, 0x1f4(x5)`      | |
| 0x150 | `0x30200073` | `mret`                   | to 0x0e8 |

`rvfi_order` runs densely from 1 to 46. Both handler entries (the `jal`s
at 0x000 and 0x01c) retire with `rvfi_intr.intr` set.

### Debug variant (`make debug`): 49 retirements

The same program with five words replaced:

| addr  | word         | assembly                      | note |
|-------|--------------|-------------------------------|------|
| 0x0e8 | `0x38000113` | `addi x2, x0, 0x380`          | sp for `cm.push` |
| 0x0ec | `0x0001b852` | `cm.push {ra, s0}, -16` ; `c.nop` | two 16-bit instructions |
| 0x0f4 | `0x1f12ac23` | `sw x17, 0x1f8(x5)`           | raise `debug_req_i` |
| 0x600 | `0x05500b13` | `addi x22, x0, 0x55`          | debug handler, `rvfi_dbg = 3` |
| 0x604 | `0x7b200073` | `dret`                        | to 0x0f8 |

`cm.push` retires once with two memory slots in use: slot 0 writes `s0`
(0x5a) to 0x37c and slot 1 writes `ra` (0x123) to 0x378, `wmask` 0xf in
each.

## Result

Detection bound all 21 channels automatically, at
`tb_cv32e40x_rvfi.wrapper_i.rvfi_i`, single channel, completeness full, on
the trimmed files and on the untrimmed 3574-signal dump alike. The
packed-struct `rvfi_trap` and `rvfi_intr` decode correctly on their
least-significant bit (`.trap`, `.intr`).

On the main capture all six consistency rules (`controlFlow`, `x0Write`,
`destinationRegister`, `memoryAccess`, `retireOrder`, `trapConsistency`)
ran and reported **0 violations** over 46 retirements, covering ALU ops,
every load/store width, taken and not-taken branches, a backward loop, an
`ecall` trap with `mret`, and a vectored machine-timer interrupt with
`mret`. Every retirement matches `dump_retires.py`.

## Gaps found

The debug variant exposed three gaps in WaveCrux, filed upstream and fixed
in 1.2 (the descriptions are of the behaviour before the fix):

1. **[#56](https://github.com/Ferrite-Engineering/wavecrux/issues/56)**:
   a false `controlFlow` violation at debug-mode entry. CV32E40X reports
   debug entry on `rvfi_dbg` and leaves `rvfi_intr` clear by design, and
   WaveCrux does not bind `rvfi_dbg`. One violation: the `sw` at 0x0f4
   reports `rvfi_pc_wdata=0x0f8`, and the next retirement, the first
   instruction of the debug handler, fetched from 0x600.
2. **[#57](https://github.com/Ferrite-Engineering/wavecrux/issues/57)**:
   the 4096-bit `rvfi_mem_*` channels are folded into one 62-bit integer, so
   `cm.push`'s two slots decode as address 0x3780000037c, `wmask` 0xff,
   `wdata` 0x1230000005a. No rule fires, because the memory rule skips
   compressed encodings.
3. **[#58](https://github.com/Ferrite-Engineering/wavecrux/issues/58)**:
   Zicsr, privileged (`mret`, `dret`, `wfi`) and Zcmp encodings disassemble
   as unknown. Display only; the checker rules decode raw bits.

Since the fixes, `rvfi_dbg` binds when the untrimmed dump carries it and
debug entry is a handler entry; the memory ports decode one access per
slot; and `Zicsr.toml`, `Privileged.toml`, `RV32Zcb-lower.toml` and
`RV32Zcmp-lower.toml` disassemble every instruction above. `trim.py` keeps
the 21 riscv-formal channels only, so the trimmed debug capture still lacks
`rvfi_dbg`; bind it from `raw_debug.vcd`.

## Running the captures through WaveCrux

There is no committed test. The results above came from a throwaway
`flutter test` file in `test/services/riscv/` that, for each FST: opened it
with `WellenProvider`, ran `RvfiDetectionService().detect` over every
variable, loaded the bound signals, built the retire stream with
`RiscvRetireStreamService` and a disassembler over `RV32I`, `RV32M`,
`RV32A`, `RV32F` and `RV32C-lower` from `assets/decoders/isa/riscv/`, then
ran `RiscvConsistencyChecker.checkRule` for every `RiscvCheckRule` with
`RiscvConsistencyCheckOptions.forBindings`. The test that commits a capture
as a fixture should do the same and pin the counts above, in the style of
`test/services/riscv/riscv_ibex_captured_rvfi_test.dart`.

## Limits of this capture

- **Two-state only.** No `x`/`z` anywhere, as with the Ibex capture, so
  `hasUnknownBits` is never exercised.
- **One retirement per cycle.** CV32E40X's `rvfi_valid` is one bit
  (`bhv/cv32e40x_rvfi.sv:303`); nothing here exercises packed-NRET
  detection.
- **Debug entry by external request only.** `ebreak` with `dcsr.ebreakm`,
  trigger match and single step were not run.
- **The trimmed files drop CV32E40X's extension channels** (`rvfi_dbg`,
  `rvfi_dbg_mode`, `rvfi_csr_*`, `rvfi_gpr_*`, `rvfi_mem_exokay` and the
  rest). They are in `raw.vcd` / `raw_debug.vcd`.
- **Not yet committable as a captured fixture.** CV32E40X is `SHL-0.51`,
  which is not on the captured-fixture licence allow-list enforced by
  `test/static/captured_fixture_licenses_test.dart`. Committing either FST
  needs that list extended first, plus a `PROVENANCE.md` entry and an
  expected-transactions snapshot.
