# FSM fixture corpus

Committed VCDs and `FsmModel` goldens for the FSM golden sweep
([`test/services/signal_query/fsm_golden_test.dart`](../../../services/signal_query/fsm_golden_test.dart)),
part of the FSM robustness plan ([`verification/fsm_robustness_plan.md`](../../../../verification/fsm_robustness_plan.md), Layer A).

## Layout

```
test/fixtures/fsm/<machine>/generated/<machine>.vcd               # the fixture
test/fixtures/fsm/<machine>/generated/<machine>.expected_fsm.json # the golden
```

The same tree is mirrored under `verification/fixtures/fsm/` for release
sign-off; both trees are kept in lockstep automatically (see below). The
`generated/` + `captured/` split and the 1:1 golden companion are enforced by
[`test/static/fsm_fixture_layout_test.dart`](../../../static/fsm_fixture_layout_test.dart)
and [`test/static/fsm_fixture_companion_test.dart`](../../../static/fsm_fixture_companion_test.dart).

Each machine is a single multi-bit `STATE` register — the analyzer
reconstructs the graph from that one signal's value changes, so no clock or
other signals are needed.

## Regeneration (two steps)

```bash
# 1. (Re)write the deterministic .vcd files — pure Dart, no FFI:
dart run tool/generate_fsm_fixtures.dart

# 2. (Re)write the .expected_fsm.json goldens by parsing those VCDs through
#    the real wellen FFI and running FsmAnalysisService. Writes BOTH the
#    test/ and verification/ trees, so they can't drift:
REGENERATE=1 flutter test test/services/signal_query/fsm_golden_test.dart
```

Generation is split this way on purpose: step 1 stays FFI-free (a plain
`dart run`), while the golden in step 2 reflects exactly what the production
parser produces (value padding, x/z representation, tick boundaries). The
golden sweep is skipped where the native wellen library isn't built; the
goldens are committed and validated on machines that have it.

## Machines

| Machine | Tier | Width | Shape | Anchor (states / transitions) |
|---|---|---|---|---|
| `traffic_light` | generated | 2 | 3-state cycle ×3 laps | 3 / 9 |
| `onehot_8` | generated | 8 | one-hot walking ring | 8 / 8 |
| `gray_counter_5bit` | generated | 5 | 32-state Gray ring (dense large-N) | 32 / 32 |
| `glitchy_reset` | generated | 3 | x-at-boot + mid-stream glitch | 4 / 3 (no transition crosses an x) |
| `picorv32_state` | captured | 8 | real PicoRV32 `cpu_state` one-hot CPU FSM (ISC) | 7 / 21 |

## Captured fixtures

`picorv32_state/captured/` is a **real IP-core** trace (not synthetic): the
PicoRV32 `cpu_state` control register, captured by driving the upstream core
through Icarus Verilog. It carries a `PROVENANCE.md` (ISC attribution + pinned
source commit + hand-verified anchors) and a `picorv32_state.fsm.json` naming
the FSM signal (`tb.uut.cpu_state`). Regenerate the trace with:

```bash
tool/generate_picorv32_fsm_capture.sh   # needs iverilog; no RISC-V toolchain
REGENERATE=1 flutter test test/services/signal_query/fsm_golden_test.dart
```

The committed testbench is `tool/picorv32_fsm_tb.v`. Captured fixtures share the
protocol corpus's license allow-list, enforced by
[`test/static/captured_fixture_licenses_test.dart`](../../../static/captured_fixture_licenses_test.dart).
