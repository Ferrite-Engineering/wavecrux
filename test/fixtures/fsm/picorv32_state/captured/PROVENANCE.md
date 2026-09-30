# Captured FSM fixtures — picorv32

Real finite-state-machine traces captured from public open-source IP cores, to
complement the synthetic fixtures next door in `../generated/`. The same license
allow-list and static guards apply as for the protocol-decoder captured corpus
(`test/static/captured_fixture_licenses_test.dart` +
`test/static/fsm_fixture_companion_test.dart`).

## License allow-list

Captured fixtures must come from projects under one of these licenses:

- MIT
- BSD-2-Clause / BSD-3-Clause
- Apache-2.0
- ISC
- CC0-1.0
- public domain

GPL/AGPL/proprietary captures are excluded by policy. `captured_fixture_licenses_test.dart`
fails the build if any entry below uses a license outside this list, or if any
trace file in this directory has no matching `## ` entry.

## `picorv32_state.vcd` — RV32I CPU control FSM (`cpu_state` one-hot register)

- **Source project:** PicoRV32 — https://github.com/YosysHQ/picorv32
- **Source commit:** `87c89acc18994c8cf9a2311e871818e87d304568` (acquired 2026-06-10)
- **License:** ISC (SPDX: `ISC`) — Copyright (C) 2015 Claire Xenia Wolf <claire@yosyshq.com>
- **Signal:** `tb.uut.cpu_state` — the core's 8-bit one-hot control-FSM register
  (named in the sibling `picorv32_state.fsm.json`; only this signal is dumped).
- **Capture method:** the committed testbench `tool/picorv32_fsm_tb.v` drives the
  upstream `picorv32.v` (fetched at the pinned commit) with a six-instruction
  hand-encoded RV32I program through Icarus Verilog (`iverilog` + `vvp`).
  Reproduce end-to-end with `tool/generate_picorv32_fsm_capture.sh`; the `$date`
  header is stripped so the committed trace is byte-stable. No RISC-V toolchain
  is required — the program is inlined as hex.
- **Scenario:** `addi, addi, add, sll, sw, lw`, then a `jal x0, 0` spin.
  `ENABLE_REGS_DUALPORT=0` forces the separate `ld_rs2` state; the load/store
  reach `ldmem`/`stmem`. Seven of the eight states are exercised; `trap` is
  intentionally never reached (the program is legal and bounded).
- **Hand-verified anchors** (confirmed by eye before the snapshot was committed):
  - `cpu_state` is `x` throughout reset, then resolves to `fetch` (`0x40` = 64).
    The boot `x` is skipped by the analyzer, so the first `fetch` carries no
    incoming transition.
  - The 7 reachable states map to the one-hot encodings:
    `ldmem`=1, `stmem`=2, `shift`=4, `exec`=8, `ld_rs2`=16, `ld_rs1`=32,
    `fetch`=64 (`trap`=128 absent).
  - 22 defined-state entries → `totalTransitionCount` = 21. The first
    instruction's `fetch → ld_rs1 → ld_rs2 → exec` chain is visible at the head
    of the trace.
