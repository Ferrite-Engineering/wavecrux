# FSM fixture corpus (verification mirror)

Release-sign-off mirror of the FSM golden corpus. The canonical copy and the
full regeneration documentation live in the test tree:
[`test/fixtures/fsm/helpers/README.md`](../../../../test/fixtures/fsm/helpers/README.md).

Both trees are written in lockstep — the generator mirrors the `.vcd` files and
the golden sweep mirrors the `.expected_fsm.json` goldens — so do not hand-edit
files here. Regenerate from the repo root:

```bash
dart run tool/generate_fsm_fixtures.dart
REGENERATE=1 flutter test test/services/signal_query/fsm_golden_test.dart
```

See the FSM robustness plan: [`verification/fsm_robustness_plan.md`](../../../fsm_robustness_plan.md).
