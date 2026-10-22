# Captured fixtures: formal witness traces

Every `.vcd` under this directory is a byte-identical copy of a witness trace
in SimCrux's formal fixture corpus (`verification/fixtures/formal/` in the
SimCrux open core), at the same relative path. WaveCrux's `formal.trace_step`
receiver (CXP §9.9.3) and the EQY pairing are tested against them:
`test/services/remote/cxp/formal_stream_coordinate_resolver_test.dart`,
`formal_eqy_pairing_test.dart` and `formal_counterexample_handoff_test.dart`
in the same directory.

## Where they came from

- **Written by:** `yosys-smtbmc`, run by SymbiYosys and EQY, through SimCrux's
  `tool/regenerate_formal_fixtures.sh` on 2026-10-21.
- **Toolchain:** YosysHQ OSS CAD Suite build 20261021: Yosys 0.70+186, SBY
  v0.70-9-g79fc9ed, EQY v0.70-1-gfb8b211, yosys-slang 12.0.0+545f88b2e.
- **Designs:** small designs written for the corpus (a request/acknowledge
  handshake, a FIFO, a pre-trace `$past` case, and an ALU with a gate-level
  netlist for equivalence). SimCrux's own `PROVENANCE.md` there records the
  inputs, the expectations and how each was written.
- **Copied:** 2026-10-21 from SimCrux commit `a092b70` (the last change to
  these captures), with `git archive` of every `*.vcd` under
  `verification/fixtures/formal/` and the first three path components
  stripped:

      git -C <simcrux> archive -o formal-vcds.tar origin/main ":(glob)verification/fixtures/formal/**/*.vcd"
      tar -xf formal-vcds.tar -C test/fixtures/formal/captured --strip-components=3

- **License:** Apache-2.0 (SPDX: `Apache-2.0`), as the SimCrux open core.
- **Count:** 27 traces. 11 are property checks in bounded, prove and cover
  modes (`sby/fifo_slang`, `sby/handshake_imm`, `sby/handshake_slang`), 7 are
  the pre-trace case (`sby/pretrace`), and 9 are EQY partitions
  (`eqy/captured/alu_fail`, `alu_fail2`, `alu_pass`).

## Pinned, so the copies cannot drift

`kFormalCorpusDigest` in `formal_stream_coordinate_resolver_test.dart` is the
FNV-1a/32 of every copy in sorted relative-path order (each file as its posix
path, a newline, then its bytes, carriage returns dropped). A regenerated
SimCrux corpus that is not re-copied here, or a hand edit here, fails that
test. Re-copy with the two commands above and update the digest in the same
commit.

## What the tests take from them, and from where

Nothing here is an expectation written by WaveCrux. The time of each step is
read from each file's own text: the trace declares the solver's step counter,
`smt_step`, outside every scope, and the time each of its values sits at is
the time of that step. The property values checked at a resolved step
(`f_wait` is 3 at step 5 of both `prove_bug` traces, `rst` is high at step 0
of `fifo_slang/dis`) come from SimCrux's hand-written corpus expectations,
which were written from the RTL before any capture existed.

## Hand-verified anchors

- `sby/handshake_imm/captured/prove_bug/engine_0/trace.vcd`: `smt_step` 0 to
  7 at times 0 to 70; `clk` is 1 at 0, falls at 5 and rises at 10, and so on;
  `f_wait` reads `011` at time 50.
- `eqy/captured/alu_fail/strategies/alu.z/sby/trace.vcd`: scopes `miter`,
  `miter.__po_z__assert`, `miter.gate` (119 variables), `miter.gold` (14
  variables); six `__pi_*` inputs and six `__po_z__*` wires directly under
  `miter`; samples at 0, 10 and 20, with `__pi_clk` falling at 5 and 15.
- `eqy/captured/alu_fail/strategies/alu.r/sby/trace.vcd`: no clock wire;
  samples at 0 and 10 only.
