# riscv-formal's `ill` check on eduBOS5: a pass with an unreachable precondition

A reproduction, not a test. Nothing in CI runs it, and nothing in WaveCrux
depends on it. It sits next to the eduBOS5 capture because both look at the
same core at the same commit, and both are about what a passing
verification result does and does not establish.

## The claim

On eduBOS5 at openPCIE commit `a0d80cd3cb525f911cae61be4c83a44e137ed916`,
with the core's own riscv-formal setup (`formal/run-riscv-formal.sh` and
`formal/checks.cfg`, unmodified), riscv-formal's `ill` check passes on both
pipelines, and it passes without ever meeting its precondition: within the
check's bound, no trace retires the all-zero instruction word that the check
is about.

- The `ill` check (`checks/rvfi_ill_check.sv` in riscv-formal) assumes that
  the retirement at the check cycle is valid and is the all-zero word
  (`assume(valid); assume(insn == 0)`), then asserts that it trapped and
  wrote nothing. If no such retirement can occur, the assumptions are
  unsatisfiable and the assertions hold trivially: the check passes.
- eduBOS5's decoder maps every opcode it does not recognise, including the
  all-zero word, to SYSTEM (`edubos5.sv:120`,
  `default: instr_decode.SYSTEM = HI;`), and a SYSTEM instruction stays in
  EXECUTE without retiring (`edubos5.sv:450`, `if (!instr_decode.SYSTEM)`).
  So an all-zero word halts the core rather than retiring, and the `ill`
  precondition never occurs.
- The check carries its own cover statement for exactly this question
  (`rvfi_ill_check.sv:46`, `cover(!reset && check && valid && insn == 0)`).
  Running the same check in SymbiYosys cover mode searches steps 0 to 16 and
  reports that cover statement unreached, on both pipelines.
- The control: the core's own `cover` check from `checks.cfg`
  (`cover (channel[0].cnt_insns == 2)`) passes on both pipelines in the same
  harness, so instructions do retire within the bound. It is specifically
  the all-zero word that never does.

This is consistent with eduBOS5's documented behaviour (its README: "eduBOS5
has no traps or interrupts", "A `SYSTEM` instruction halts the core and does
not retire") and is not a functional bug in the core. The point is narrower:
a green `ill` result on this core is not evidence about illegal instructions,
because the check never exercised one.

## Run it

```
./run-ill-cover.sh
```

The script fetches eduBOS5 through the capture's `Makefile` (`make
openPCIE/.pinned` one directory up, the same shallow sparse checkout), fetches
riscv-formal at `c992aa61fdfe0846c5ed90324c596202a1c69b76` into
`riscv-formal-src/` (single-commit shallow fetch; or set `RISCV_FORMAL` to an
existing checkout at that commit), then for `EN_WAIT4REGS` 0 and 1:

1. runs `run-riscv-formal.sh <EN_WAIT4REGS> 1 "ill_ch0 cover"`, the authors'
   flow unmodified (genchecks, their `sed` edits to the `.sby` files, then
   the two make targets);
2. derives `cover_ill_ch0.sby` from the generated `ill_ch0.sby` by changing
   only the mode (`bmc` to `cover`), the engine (`abc bmc3` to `smtbmc z3`,
   since ABC has no cover mode; the authors' script makes the same swap for
   their own `cover` check), and the file name, and runs it with `sby`;
3. prints a summary, and compares it with `expected.txt`.

riscv-formal's work folders go to `/tmp/rvf_edubos5_*` (that is where
`run-riscv-formal.sh` puts them) and are removed afterwards; `KEEP_WORK=1`
keeps them and prints their paths on stderr.

## Requirements

All on `PATH`:

- `git`, `make`, `python3` with the `click` module (SymbiYosys imports it).
- `sby` (SymbiYosys), `yosys-abc`, `yosys-smtbmc`, `z3`.
- `yosys` **with the slang front end**: the core's `checks.cfg` reads the RTL
  with `read_slang`. Homebrew's yosys has no `read_slang`; a yosys build plus
  the yosys-slang plugin works, put on `PATH` as a `yosys` wrapper that runs
  `yosys -m slang.so "$@"`.
- GNU sed as `sed`: `run-riscv-formal.sh` uses GNU `sed -i '/.../a ...'`.
  On macOS, put GNU sed first on `PATH` under the name `sed`.

`expected.txt` was produced on macOS (Apple silicon) with Yosys 0.69+post
(`143eb14f9cc55d6f8927e68523b0c9d2166ed02c`), yosys-slang
`8aa302273bb97bd7d839c005f94dab1523f3c432`, SymbiYosys
`79fc9eddca5e33a28cc2f2cd19c9825efd9a7255`, Z3 5.1.0, GNU sed 4.9, Python
3.14 and click 8.5. The summary contains no timings, paths or tool versions
(those go to stderr), so it should reproduce byte for byte with other
versions of the same tools unless a tool changes its result.

## Reading `expected.txt`

```
EN_WAIT4REGS=0
  cover (control, checks.cfg [cover]: two instructions retire), mode cover: PASS
  ill_ch0, mode bmc (as run-riscv-formal.sh runs it): PASS (depth 17, check cycle 16)
  cover_ill_ch0, mode cover: searched steps 0..16, unreached: rvfi_ill_check.sv:46.4-46.48, DONE (FAIL, rc=2)
```

`DONE (FAIL, rc=2)` is SymbiYosys reporting an unreached cover statement,
which is the finding: the `ill` precondition is unreachable at the check
cycle, so the `PASS` on the line above it is vacuous. The same holds for
`EN_WAIT4REGS=1`.

## Files

- `run-ill-cover.sh`: the reproduction. SPDX `0BSD`.
- `expected.txt`: its output at the pinned commits.
