# FSM Robustness Plan

**Status:** Layer **A ✅** · Layer **B ✅** · Layer **C ✅** · Layer **D ✅** · Layer **E ✅** · Layer **F ✅** · Layer **G ✅** — **all layers complete**
**Last Updated:** 2026-06-10
**Owner:** FSM visualization hardening (open-core `lib/services/signal_query/fsm_*`)
**Lives in:** open-core `wavecrux/verification/` — the FSM feature is entirely open-core (no tier gating), so its corpus, sweeps, and guardrails live here, alongside the decoder ones, not in the Pro overlay.

> Purpose: bring the FSM visualization feature
> (`lib/services/signal_query/fsm_analysis_service.dart`,
> `fsm_layout_service.dart`, and the `fsm_*` providers/widgets) up to the same
> robustness bar the protocol **decoders** already meet, and keep it there via CI
> on every platform. This document is written to be *executed* — each layer lists
> the exact files to create, the corpus schema, the regeneration commands, and a
> machine-checkable acceptance test. A future agent (or a fresh context) can pick
> up at the first unchecked layer and continue without re-deriving anything. The
> Pro overlay's translator robustness plan is the model for this doc's shape.

---

## 0. Why this exists — the decoder bar, restated for FSM

`FsmAnalysisService.buildModel()` is **structurally a decoder**: it takes a
`WaveformDataSource`, calls `valueAt()` once and walks `changesInRange()` over a
time window, and emits a structured result (`FsmModel` = states + transitions)
exactly the way a `ProtocolDecoder` walks the same APIs and emits transactions.
Yet it is the one trace-walker in the codebase that is **absent from the
decoder edge-case sweep** that hardens every decoder against real-world VCDs.

When the decoders shipped, "robust" meant **eight** interlocking layers, not a
pile of unit tests. FSM currently has layers 3, 7, and 8 only (good per-unit
tests, integration tests, and a verification-guide section). This plan fills the
rest. The same eight-layer frame the translators were brought up to:

| # | Layer | Decoder artifact (the bar) | FSM target |
|---|---|---|---|
| 1 | Generated fixtures | `tool/generate_*.dart` → `test/fixtures/protocol/<d>/generated/*.vcd` | ✅ `tool/generate_fsm_fixtures.dart` → `test/fixtures/fsm/<machine>/generated/*.vcd` (+ `.expected_fsm.json` golden) |
| 2 | Captured fixtures | `…/<d>/captured/*.fst` + `PROVENANCE.md` + license allow-list | ✅ `test/fixtures/fsm/picorv32_state/captured/picorv32_state.vcd` — real picorv32 `cpu_state` FSM (ISC) + `PROVENANCE.md` (Layer F) |
| 3 | Per-unit unit tests | `test/services/decoders/<d>_decoder_test.dart` | ✅ `test/services/signal_query/fsm_analysis_service_test.dart` + `fsm_layout_service_test.dart` (already shipped) |
| 4 | Golden-snapshot tests | `<d>_captured_fixtures_test.dart` vs `.expected_transactions.json` (real FFI replay) | ✅ `test/services/signal_query/fsm_golden_test.dart` vs `.expected_fsm.json` (real FFI replay) |
| 5 | Static guardrails | `test/static/` ×4 (`fixture_dir_layout`, `all_decoders_have_fixtures`, `captured_fixture_companion`, `captured_fixture_licenses`) | ✅ `test/static/` ×2 (`fsm_fixture_layout`, `fsm_fixture_companion` — the latter also guards the non-empty corpus) + license guard deferred to Layer F |
| 6 | Edge-case / fuzz sweep | `_decoder_edge_cases_test.dart`, `_captured_sweep.dart` | ✅ `test/services/signal_query/fsm_edge_cases_test.dart` + `fsm_fuzz_test.dart` |
| 7 | Integration tests | `integration_test/decoders/*` | ✅ `integration_test/fsm/fsm_cursor_tracking_test.dart`, `integration_test/gestures/fsm_context_menu_dispatch_test.dart`, `integration_test/coexistence/*fsm*` (already shipped) |
| 8 | Verification docs | guide section + checklist + Automation Assessment | ✅ `VERIFICATION_GUIDE.md` §11 (exists) — Layer G promotes its MANUAL rows |

**Two layers are the highest-leverage, and they need no corpus, so they ship
first (Layer C + D):** the edge-case sweep closes the exact inconsistency above
— a decoder-shaped walker exempt from decoder hardening — and the fuzz sweep
pins the model invariants. Both are pure-Dart and platform-agnostic (no wellen
FFI, no fixtures), mirroring `_decoder_edge_cases_test.dart` which constructs its
queries synthetically. **Layer B (static guardrails)** is the second-highest:
it makes the corpus self-enforcing so a future FSM analyzer change physically
cannot ship without a golden, a companion snapshot, or with a GPL capture.

### What "today" actually looks like (honest baseline)

- `fsm_analysis_service_test.dart` is genuinely thoughtful: it covers two-state
  toggle, single-state (`isTrivial`), 5-state binary encoding, self-loops, x/z
  breaking the transition chain, translate-filter labels, annotation-overrides-
  filter precedence, empty range, all-x → empty model, real-value rejection,
  `b`-prefix, the transition-count-sum invariant, and `stateIdAt` x/z/null. But
  **every input is hand-stubbed via `mocktail`** (max ~5 states / ~5
  transitions), it never runs through the real wellen parser, and it is not
  swept over pathological shapes.
- `fsm_layout_service_test.dart` tops out at **16 states**;
  `fsm_bubble_painter_test.dart` tops out at **10** and only asserts
  "does not throw" (no golden image).
- `VERIFICATION_GUIDE.md` §11.3 claims "Very large state machines (50+ states) —
  graph layout remains usable" and §11.5 lists **"Graph layout for large FSMs |
  MANUAL (visual judgement)"**. That 50+ claim is asserted only by a human eye,
  never by a test. Layer E backs it; Layer G promotes the row.
- A grep for `fuzz|propert|random|stress|matchesGoldenFile|benchmark|Timeout`
  across all `fsm_*` test files returns **zero** matches.

---

## 1. The fixture model for a trace-walking analyzer

Unlike a translator (a pure `value → text` function), the FSM analyzer consumes
a **signal stream**, exactly like a decoder. So the fixture analog *is* a VCD —
the decoder `generated/` + `captured/` split maps directly, with one change to
the golden payload:

- A decoder golden is `.expected_transactions.json`.
- An FSM golden is **`.expected_fsm.json`** — the serialized `FsmModel`: the
  sorted state list (`id`, `label`, `entryCount`, `firstEntryTime`), the sorted
  transition list (`fromId`, `toId`, `count`, `times`), and
  `totalTransitionCount`. (Layout is deterministic from the model and is golden-
  tested separately in Layer E, so it is **not** part of this snapshot.)

### 1.1 Corpus directory layout

```
test/fixtures/fsm/
├── helpers/
│   └── README.md                       # regeneration commands + provenance rationale
├── traffic_light/                      # a classic 3-state machine
│   └── generated/
│       ├── traffic_light.vcd
│       └── traffic_light.expected_fsm.json
├── onehot_8/                           # one-hot encoded, 8 states, sparse transitions
│   └── generated/
│       ├── onehot_8.vcd
│       └── onehot_8.expected_fsm.json
├── gray_counter_5bit/                  # 32-state dense ring (exercises large-N)
│   └── generated/
│       ├── gray_counter_5bit.vcd
│       └── gray_counter_5bit.expected_fsm.json
├── glitchy_reset/                      # x/z at boot, then settles — chain-break coverage
│   └── generated/
│       ├── glitchy_reset.vcd
│       └── glitchy_reset.expected_fsm.json
└── picorv32_state/                     # Layer F — real captured IP, PROVENANCE.md required
    └── captured/
        ├── picorv32_state.fst
        ├── picorv32_state.expected_fsm.json
        └── PROVENANCE.md
```

Mirror the same tree under `verification/fixtures/fsm/` for the release sign-off
corpus (Layer G), and have the generator write both trees in one pass so they
cannot drift — the translator generator's dual-tree pattern.

Respect the existing open-core corpus budget rule (CLAUDE.md "Protocol Decoder
Fixture Layout"): prefer FST over VCD where wellen reads it natively, compress
raw VCDs as `.vcd.zst` when large, cap any single fixture at ~5 MB
raw-equivalent, total corpus ≤100 MB shared across all features.

### 1.2 Golden schema — `<machine>.expected_fsm.json`

```jsonc
{
  "signalPath": "top.dut.state",     // informational; from the generator
  "startTime": 0,
  "endTime": 100000,
  "totalTransitionCount": 1287,
  "states": [
    { "id": "0", "label": "IDLE", "entryCount": 322, "firstEntryTime": 0 },
    { "id": "1", "label": "1",    "entryCount": 321, "firstEntryTime": 80 }
    /* sorted by numeric id, as buildModel emits them */
  ],
  "transitions": [
    { "fromId": "0", "toId": "1", "count": 321, "times": [80, 240, /* … */] }
    /* sorted by "from→to", as buildModel emits them */
  ]
}
```

`label` reflects whatever the generator binds (raw decimal id when no
annotation/filter; a symbolic name when the fixture ships a translate filter, to
exercise the label-resolution path). `times` arrays can be long for dense
machines — that is intentional corpus weight and is what makes the golden a real
regression net for transition timing.

---

## 2. Layer C — Edge-case sweep  ✅  *(first PR, highest leverage, no corpus)*

**Goal:** `buildModel()` and `stateIdAt()` are thrown the same ~20 pathological
shapes every decoder already survives, and must return within a `Timeout`
without throwing, NaN-ing, or hanging. The model may be empty or trivial — it
must not crash.

**Create:** `test/services/signal_query/fsm_edge_cases_test.dart` — modeled
directly on `test/services/decoders/_decoder_edge_cases_test.dart`. Each case
constructs a synthetic `WaveformDataSource` (a fake implementing `valueAt` /
`changesInRange` / `isSignalLoaded` from an in-memory change list — reuse the
`_stub` shape already in `fsm_analysis_service_test.dart`, no wellen FFI), so the
sweep stays fast and pure-Dart. Wrap each in `Timeout(Duration(seconds: 5))`.

Cases (the decoder `_edgeCases` list, adapted to a state register):

1. `emptyChanges` — `valueAt` null, no changes → empty model.
2. `allConstantZero` / `allConstantOne` — single held value → 1 state, 0
   transitions, `isTrivial`.
3. `allX` / `allZ` / `allXZ` — every value tainted → empty model (no states).
4. `xzMidStream` — `0 → x → 1 → x → 0`: the chain breaks across every x; assert
   **no transition crosses an x/z gap** (this is the property `buildModel`'s
   `prevId = null` reset enforces — the highest-value assertion here).
5. `emptyStringValue` (`''`) and `whitespaceValue` (`'  '`) → treated as
   undefined, no state.
6. `invalidChars` — `'@@@@'`, `'5'` (decimal digit in a binary string), `'b'`
   (bare prefix), `'0x1f'` → all rejected by `_normalize`, no state.
7. `realLiteral` — `'3.14'` → rejected (not a state value).
8. `bPrefixed` — `'b1010'` → normalized to `"10"`, one state.
9. `simultaneousChangesAtSameTick` — two changes at the same `time` → must not
   double-count or throw; deterministic output.
10. `subCycleFlicker` — toggle every tick for 500 ticks → bounded states (2),
    large transition counts, returns within timeout.
11. `changeExactlyAtStartTime` — a change whose `time == startTime` (the
    boundary the `continue` guard in `buildModel` handles) → not double-entered.
12. `hugeTickRange` — `endTime = 5e9` (> 2³²) with sparse changes → no overflow,
    `times`/`firstEntryTime` preserved as the real (large) ints.
13. `nonMonotonicChanges` — out-of-order change list → must not throw (decoders
    must survive this; assert termination, document whatever ordering falls out).
14. `veryWideVector` — a 256-bit one-hot value → `BigInt` path in `_normalize`
    holds; state id is the full decimal expansion, no truncation.
15. `manyStates` — 1024 distinct values → 1024 states, returns within timeout
    (functional correctness of the count; perf budget is Layer E).
16. `unloadedSignal` — `isSignalLoaded` false / `valueAt` null throughout →
    empty model, no throw.
17. `stateIdAt` variants — at an x/z time → null; at a defined time → the decimal
    id; before the first change → the initial value's id or null.

**Acceptance:** `flutter test test/services/signal_query/fsm_edge_cases_test.dart`
green; temporarily removing the `prevId = null` reset in `buildModel` (the x/z
chain break) makes case 4 red.

**Landed (2026-06-10):** `test/services/signal_query/fsm_edge_cases_test.dart`
— ~24 cases over a concrete `_FakeSource` (no FFI, no mocktail), each under a
5 s `Timeout`: empty/held-constant, all-X/all-Z, the x/z chain-break marquee
(`transitions` empty across every gap), self-loop, empty/whitespace/invalid
chars, real literal, `b`-prefix, simultaneous-same-tick (determinism +
count-sum), 500-tick sub-cycle flicker, change-exactly-at-startTime boundary,
huge tick range (> 2³²), non-monotonic changes, 256-bit one-hot, 1024 distinct
states, zero-duration window, and `stateIdAt` x/z/before-first-change.
**Finding:** an *inverted* range (`start > end`) is out of contract —
`buildModel` builds `TimeRange(start, end)`, which asserts `end >= start`, so it
throws in debug. The in-contract boundary is the zero-duration window
(`start == end`), which is what the sweep covers; the caller owns the
`end >= start` invariant (the file's `[start, end]` always satisfies it).

---

## 3. Layer D — Fuzz / property sweep  ✅  *(first PR, no corpus)*

**Goal:** over randomized but seed-deterministic value-change streams, the
analyzer's structural invariants always hold. This catches the classes of bug
example-based tests miss.

**Create:** `test/services/signal_query/fsm_fuzz_test.dart` — a fixed-seed
(`math.Random(0xF5...)`) generator producing N≈500 random streams: random width
1..64, random change count 0..2000, values drawn from `{0,1,x,z}` bit-strings of
that width (so x/z taint appears naturally), random start/end windows including
empty and inverted ranges, optional random annotation and translate filter.
For each stream, build the model and assert the invariants:

- **No exception, returns within a per-stream `Timeout`.**
- `totalTransitionCount == sum(t.count for t in transitions)` (the invariant the
  per-unit test already checks once — fuzz it).
- **No transition's `fromId`/`toId` is an undefined value**, and no transition is
  recorded across an x/z position (reconstruct expected segments and cross-check).
- States are **sorted by numeric id**; every `state.entryCount >= 1`; every
  `firstEntryTime` is within `[start, end)`.
- Every `transition.times` list is **sorted and length == count**, every time in
  `[start, end)`.
- Feeding the **same seed twice yields an identical `FsmModel`** (determinism).
- Then run `FsmLayoutService.compute(model)` and assert **every position is
  finite and inside the unit square `[0,1]²`** for arbitrary N (the layout
  property that the 16-state cap in the current test never stresses).

**Acceptance:** green on the committed seed; intentionally breaking the
transition-count accounting or the x/z reset makes a property red. Pure-compute
and `dart:io`-free, so it is web-runnable if a `--platform chrome` job is added.

**Landed (2026-06-10):** `test/services/signal_query/fsm_fuzz_test.dart` — 500
seed-deterministic streams (seed `0xF50FF5E`, width 1–8, 0–59 changes,
~10%-per-bit x/z taint, strictly-increasing times so the start-boundary skip
never applies) cross-checked against an **independent oracle** (`_oracle`,
re-deriving states/transitions from the contract, not copied from the impl).
Per stream it asserts: `totalTransitionCount` == Σcounts == oracle; state set +
numeric ordering + per-state `entryCount`/`firstEntryTime`; transition set with
every endpoint a real state, no duplicates, `count == times.length`, sorted
times, all times in range; **determinism** (a second run is `==`); and layout
positions finite, inside `[0,1]²`, one per state, all distinct. A second test
sweeps 100 zero-duration windows. The boundary-skip path (change exactly at
`startTime`) is deliberately excluded here and covered deterministically in
Layer C, keeping the oracle a clean statement of the contract.

---

## 4. Layer A — Generated VCD corpus + FsmModel golden sweep  ✅

**Goal:** a handful of representative state machines exist as committed VCDs with
a golden `FsmModel`, replayed through the **real wellen parser** by a single
sweep — closing the gap that the analyzer is today validated only against mocks.

**Create:**

1. `tool/generate_fsm_fixtures.dart` — pure-Dart `dart run` tool (the VCD-writer
   chain is Flutter-free; mirror `tool/generate_wishbone_fixtures.dart`). It
   declares a machine table in Dart (traffic_light, onehot_8, gray_counter_5bit,
   glitchy_reset — §1.1), emits a deterministic `.vcd` per machine into
   `test/fixtures/fsm/<machine>/generated/`, then opens it back through the same
   `WaveformDataSource` the app uses, runs `FsmAnalysisService.buildModel`, and
   writes the serialized `.expected_fsm.json` beside it. Writes the
   `verification/fixtures/fsm/` mirror in the same pass.
2. `test/services/signal_query/fsm_golden_test.dart` — discovers every
   `test/fixtures/fsm/*/generated/*.vcd` (and `captured/*.fst` once Layer F
   lands), opens each via the real provider, runs `buildModel` over the full
   range, serializes, and asserts equality with the sibling `.expected_fsm.json`.
   `REGENERATE=1 flutter test …` rewrites the goldens (the decoder
   `_captured_sweep.dart` REGENERATE escape hatch).

**Regenerate:**

```bash
dart run tool/generate_fsm_fixtures.dart                       # rewrites VCDs + goldens, both trees
REGENERATE=1 flutter test test/services/signal_query/fsm_golden_test.dart   # refresh goldens against live analyzer only
```

**Acceptance:** `flutter test test/services/signal_query/fsm_golden_test.dart`
passes with the committed corpus; deleting a golden fails with a "run
REGENERATE=1" message; a hand-verified anchor (traffic_light has exactly 3
states and a known transition count) is asserted explicitly, not only by
snapshot equality.

**Landed (2026-06-10):** `tool/generate_fsm_fixtures.dart` (pure-Dart, emits
`.vcd` into both trees) + `test/services/signal_query/fsm_golden_test.dart`
(FFI-gated; opens each VCD via the real `WellenProvider`, runs `buildModel`
over the sole `STATE` register, and compares the serialized `FsmModel` against
`<machine>.expected_fsm.json`). `REGENERATE=1` rewrites both the `test/` and
`verification/` goldens in lockstep. Four machines: `traffic_light` (3/9),
`onehot_8` (8/8), `gray_counter_5bit` (32/32 — dense large-N), `glitchy_reset`
(4/3 — and the golden proves no transition crosses the x-glitch *through the
real wellen parser*, not just a synthetic source). Each carries a hand-verified
`(states, transitions)` anchor asserted alongside the snapshot. The replay
skips cleanly when the native lib isn't built (the goldens are committed and
presence-guarded by Layer B).

---

## 5. Layer B — Static guardrails (self-enforcing corpus)  ✅

**Goal:** the corpus discipline is enforced by CI, not memory — so the *next*
change to the FSM analyzer or a *new* committed machine can't quietly skip its
golden, drop a companion, or smuggle in a GPL capture.

**Create:**

1. `test/static/fsm_fixture_layout_test.dart` — no loose fixture files at
   `test/fixtures/fsm/<machine>/` (or the `verification/` mirror); every `.vcd` /
   `.fst` / `.vcd.zst` / `.expected_fsm.json` lives in `generated/` or
   `captured/`. Mirror of `fixture_dir_layout_test.dart`.
2. `test/static/fsm_fixture_companion_test.dart` — every fixture VCD/FST has a
   sibling `.expected_fsm.json` and vice-versa. Mirror of
   `captured_fixture_companion_test.dart`.
3. **Non-empty corpus guard** (fold into #2 or a third test): assert the golden
   sweep discovers **≥1 generated machine** so the corpus can't silently empty
   out and turn the sweep into a no-op green. (FSM has a single analyzer rather
   than many decoders, so there is no `all_decoders_have_fixtures` analog — the
   risk it guards against, "shipped without a corpus," is covered by this
   non-empty assertion instead.)
4. **Reuse** `test/static/captured_fixture_licenses_test.dart` for the Layer F
   `captured/` tier — extend its `_findProvenanceFiles()` to also walk
   `test/fixtures/fsm/*/captured/`. No new license guard.

**Acceptance:** each guard fails on an injected violation (a loose file at the
machine root, a golden with no VCD, an emptied corpus, a GPL `PROVENANCE.md`) and
passes on the committed tree.

**Landed (2026-06-10):** `test/static/fsm_fixture_layout_test.dart` (no loose
files at `fsm/<machine>/` root, both trees) and
`test/static/fsm_fixture_companion_test.dart` (every `.vcd`/`.fst`/`.vcd.zst`
has a sibling `.expected_fsm.json` in both trees **and** the generated corpus is
non-empty). The license-guard extension is deferred to Layer F — there is no
`fsm/*/captured/` tree to guard yet; extending `captured_fixture_licenses_test`'s
`_findProvenanceFiles()` lands with the first capture.

---

## 6. Layer E — Perf / stress + layout stability  ✅

**Goal:** back the `VERIFICATION_GUIDE.md` §11.3 "50+ states remains usable"
claim with a test instead of a human eye, and prove the analyzer and the circular
layout hold up under state explosion and rapid transitions.

**Create:** `test/services/signal_query/fsm_stress_test.dart`:

- **State explosion** — synthesize a stream with 256, 1024, and 4096 distinct
  states and tens of thousands of transitions; assert `buildModel` completes
  under a generous wall-clock budget (e.g. < 2 s in CI, asserted via a
  `Stopwatch`, tolerance-documented) and the counts are exact.
- **Rapid transitions** — 100k changes across 2 states; assert completion and
  `totalTransitionCount` accuracy.
- **Long range / large timestamps** — `endTime` near 2⁶³ with sparse changes;
  assert no overflow in `times`/`firstEntryTime`.
- **Layout stability at large N** — for N ∈ {50, 256, 4096}: every position is
  finite, inside `[0,1]²`, and **distinct** (no two states share a coordinate —
  the circular layout's separation property); the layout is **deterministic**
  across repeated calls; and a small **golden geometry snapshot** for N=50 pins
  the circle so a layout refactor is caught.

**Acceptance:** green within budget on CI; the N=50 layout golden makes an
accidental radius/anchor change red. Document the perf numbers as soft budgets
(hybrid automation — numeric thresholds with CI tolerance), not hard equality.

**Landed (2026-06-10):** `test/services/signal_query/fsm_stress_test.dart` —
state explosion (256/1024/4096 distinct states, exact counts), 100k rapid
transitions across 2 states, very large timestamps (near 2⁶²), and layout
stability at N ∈ {50, 256, 4096} (finite, in `[0,1]²`, distinct, deterministic).
Rather than a float-brittle committed geometry golden, the N=50 case **pins the
circle by property**: it recomputes the expected position per node from the
layout formula (radius 0.45, equal angular spacing from 12 o'clock) and asserts
each within 1e-9 — a layout refactor still turns it red, without snapshot
fragility. Perf assertions are soft canaries (`< 10 s`) under a 30 s `Timeout`;
the hard guarantee is non-hang.

---

## 7. Layer F — Captured real-IP corpus  ✅

**Goal:** at least one FSM golden comes from a **real open-source IP core**, not
a synthetic generator — the analog to the decoders' captured bus traffic.

**Do:**

1. Pick a permissively-licensed core with a clear state register — e.g.
   **picorv32** (the `cpu_state` / one-hot control FSM; ISC license, already on
   the decoder allow-list and already used as a decoder capture source). Run its
   upstream testbench through `iverilog`/`verilator`, dump the state signal to
   FST, trim to a representative window (≤5 MB).
2. Land it at `test/fixtures/fsm/picorv32_state/captured/` with
   `picorv32_state.fst`, a regenerated `.expected_fsm.json`, and a
   `PROVENANCE.md` (source project, commit SHA, license, capture method,
   hand-verified anchor states) per the open-core captured-fixture rules. The
   Layer A golden sweep picks it up automatically; the Layer B license guard
   (extended in step 5.4) validates the license.

**Acceptance:** the golden sweep replays the capture through the real FFI and
matches; `captured_fixture_licenses_test.dart` passes; a hand-verified anchor
(e.g. the boot state id and that the trap/error state is reached exactly K times)
is asserted explicitly.

**Landed (2026-06-10):** `test/fixtures/fsm/picorv32_state/captured/picorv32_state.vcd`
— the **real PicoRV32 `cpu_state` one-hot control FSM** (ISC, pinned commit
`87c89acc…`), 7 reachable states (fetch/ld_rs1/ld_rs2/exec/shift/stmem/ldmem;
trap intentionally not reached), 21 transitions, boot `x` skipped. Reproducible
end-to-end: the committed testbench `tool/picorv32_fsm_tb.v` drives the upstream
core (fetched at the pin) through Icarus Verilog via
`tool/generate_picorv32_fsm_capture.sh` — no RISC-V toolchain (the 6-instruction
program is inlined as hex), `$date` stripped for byte-stability. The golden
sweep grew a `<name>.fsm.json` signal selector (the capture dumps only
`tb.uut.cpu_state`; generated single-signal VCDs still auto-pick) and a
`(7, 21)` anchor. `captured/PROVENANCE.md` carries the ISC attribution +
hand-verified anchors; the license guard's `_findProvenanceFiles()` was extended
to walk the `fsm/` tree.

---

## 8. Layer G — Verification doc sync + CI wiring  ✅

**Landed (2026-06-10):** `VERIFICATION_GUIDE.md` §11.5 — the "Graph layout for
large FSMs" row was promoted **MANUAL → UNIT** (now automated by Layer E), and
rows were added for the golden sweep (A, incl. the picorv32 capture), edge-case
sweep (C), fuzz sweep (D), and the static corpus guards (B). Helper READMEs under
both `test/fixtures/fsm/helpers/` and `verification/fixtures/fsm/helpers/`; the
`verification/fixtures/fsm/` mirror (VCDs + goldens + capture + PROVENANCE) is
written in lockstep by the generator and golden sweep. A `VERIFICATION_CHECKLIST.md`
FSM-robustness bullet group was added.

**CI needs no workflow change.** `flutter test` already runs all of `test/`
(so `test/static/fsm_*`, `fsm_golden_test.dart`, `fsm_edge_cases_test.dart`,
`fsm_fuzz_test.dart`, and `fsm_stress_test.dart` execute on Linux/macOS/Windows
in the existing matrix). The golden sweep's real-FFI replay self-skips where the
native wellen library isn't built; the committed goldens are presence-guarded by
Layer B so the corpus can't silently empty. The edge-case + fuzz + stress tests
are `dart:io`-free and would run under a `--platform chrome` job if one is ever
added. The picorv32 capture regeneration (`tool/generate_picorv32_fsm_capture.sh`)
needs `iverilog`, which is a manual/dev step, not a CI gate — the trace is
committed.


**Goal:** the new sweeps run on every platform in CI, and the verification
guide's MANUAL/visual rows are promoted as automation lands (the open-core "new
features update the verification documents in the same change" rule, applied to
the hardening itself).

**Do:**

1. `verification/fixtures/fsm/helpers/README.md` — the
   `dart run tool/generate_fsm_fixtures.dart` regeneration command and the
   dual-tree / captured-derivation rationale. Add the same line to
   `verification/fixtures/helpers/README.md` if a global regeneration index
   exists.
2. `VERIFICATION_GUIDE.md` §11.5 Automation Assessment — promote
   **"Graph layout for large FSMs | MANUAL (visual judgement)"** to the Layer E
   coverage, and add rows for: the generated golden sweep, the captured golden,
   the edge-case sweep, the fuzz/property sweep, and the perf/stress budgets.
   Reconcile the §11.3 "50+ states usable" prose with the now-automated bound.
3. `VERIFICATION_CHECKLIST.md` — add an FSM-robustness bullet group referencing
   the new fixtures.
4. **CI:** `flutter test` already runs all of `test/` (so `test/static/fsm_*`,
   `fsm_golden_test.dart`, `fsm_edge_cases_test.dart`, `fsm_fuzz_test.dart`, and
   `fsm_stress_test.dart` execute on Linux/macOS/Windows in the existing matrix).
   Confirm the golden/captured replay tests (which read fixtures via `dart:io`)
   are not gated behind a web-only job; the edge-case + fuzz + property tests are
   `dart:io`-free and web-runnable if a `--platform chrome` job is ever added.
   Add the generator to any "fixtures up to date" CI check if one exists.
5. Plan sync: note the FSM hardening in `docs/ARCHITECTURE.md` §10 (or the FSM
   subsection) and in any open-core integration-test backlog doc, per the Phase
   Close-Out Plan Sync Discipline.

**Acceptance:** CI green on all platforms; no MANUAL-only claim remains for a
behavior a new test now covers; the §11.3 prose and §11.5 table agree with the
landed automation.

---

## 9. Execution order & handoff boundary

**First PR — platform-agnostic, no corpus (highest leverage, cheapest):**
Layer **C** (edge-case sweep) + Layer **D** (fuzz/property). These close the
exact "decoder-shaped walker exempt from the decoder hardening" gap and pin the
invariants, with no fixtures to build. **✅ Landed 2026-06-10** —
`fsm_edge_cases_test.dart` + `fsm_fuzz_test.dart`, analyzer-clean, 25 tests
green.

**Second PR — corpus + self-enforcement:** Layer **A** (generated golden) +
Layer **B** (static guardrails) + Layer **E** (perf/stress + layout golden).
Layer **B** is load-bearing here: it makes the corpus self-enforcing.
**✅ Landed 2026-06-10** — `generate_fsm_fixtures.dart`, `fsm_golden_test.dart`
(4 machines, real-FFI replay), `fsm_stress_test.dart`, two `test/static/`
guards, helper READMEs; analyzer-clean, full FSM + static suites green.

**Third PR — real capture + doc/CI sync:** Layer **F** (picorv32 capture) +
Layer **G** (verification doc promotion + CI confirmation). **✅ Landed
2026-06-10** — real PicoRV32 `cpu_state` capture (ISC) + testbench + reproducible
script + PROVENANCE, license-guard extended to the `fsm/` tree, `VERIFICATION_GUIDE`
§11.5 + `VERIFICATION_CHECKLIST` updated. **All eight layers complete.**

Each layer's checkbox at the top of this doc is the progress tracker — flip it
when the layer's acceptance passes, and keep the §0 table's Layer column and the
status banner in sync (Phase Close-Out Plan Sync Discipline applies to this doc
too).
