# Analog-rendering fixture corpus

Deterministic VCDs for the analog trace renderer, mirrored into
`verification/fixtures/analog/` by the generator.

```
dart run tool/generate_analog_fixtures.dart          # the .vcd files
REGENERATE=1 flutter test \
  test/services/waveform/analog_fixture_golden_test.dart   # the .expected.json goldens
```

## Why the primary fixture is deliberately mixed

WaveCrux has always drawn a `real` signal as a curve. What it gained is the
ability to draw a **digital bus** as one — the GTKWave "Data Format → Analog"
behaviour a DSP or ML engineer hits in their first session, because a Q4.12 or
bf16 datapath is unreadable as hex.

The bugs that matter are therefore not about analog rendering in isolation.
They are about a file that carries *both* kinds at once and the renderer
picking the wrong one for a lane. `mixed_analog_digital.vcd` puts real signals,
buses meant to be plotted, and buses meant to stay digital on a single timeline
under a single clock, so:

- a change that turned every lane analog fails, because the digital signals are
  recorded as digital in the golden;
- a change that turned none of them analog fails for the mirror-image reason;
- a change to how a bus becomes a number fails on the `min`/`max` anchors,
  which are hand-checkable against the generator's arithmetic.

A corpus of only-analog or only-digital signals catches none of those.

## `mixed_analog_digital.vcd`

200 samples over 0–2000 ns, 1 ns timescale.

| Signal | Width | Intended rendering | What it exercises |
|---|---|---|---|
| `top.clk` | 1 | digital | a scalar lane stays a scalar lane |
| `top.rst_n` | 1 | digital | one early edge, then nothing |
| `top.vref` | real | **analog** (native) | the pre-existing real path, untouched |
| `top.dsp.sample_q` | 16 | **analog** | Q4.12 signed sine — the migration-blocker case |
| `top.dsp.gain_f32` | 32 | **analog** | IEEE-754 single bit-cast, decaying envelope |
| `top.dsp.err_signed` | 12 | **analog** | two's complement triangle crossing zero |
| `top.dsp.count_u` | 8 | digital | a counter that should stay hex |
| `top.dsp.gray_ctr` | 4 | digital | Gray code — a ramp only once decoded |
| `top.dsp.bus_xz` | 8 | **analog** | an x run and a z run, which must be gaps |

Anchors worth knowing when reading a golden diff, all derived from the
generator's arithmetic rather than from a recorded run:

- `sample_q` spans exactly **−3.5 … +3.5** (amplitude 3.5 in Q4.12).
- `gain_f32` spans **1.0 … exp(−3) ≈ 0.0498**.
- `err_signed` spans **−2047 … +2047** (12-bit full scale).
- `vref` spans **1.6 … 2.0** (1.8 V ± 0.2 V).
- `gray_ctr` decodes to **0 … 15**, not the raw Gray values.
- `bus_xz` has exactly **2 gaps** — one x window, one z window.

The Gray counter is the sharpest of these: plotted raw it is a sawtooth that
does not exist in the design, so a golden showing anything but a clean ramp
means the decode was skipped.

## `analog_edge_cases.vcd`

The degenerate inputs, kept out of the primary file so its curves stay
readable:

| Signal | What it exercises |
|---|---|
| `edge.constant_bus` | a bus that never changes — zero auto-range span |
| `edge.single_change` | one transition, well after t=0 |
| `edge.full_swing` | 16-bit signed swinging between `0x8000` and `0x7FFF` |
| `edge.always_x` | unknown for its entire life — an all-gap trace |
| `edge.lone_real` | a real with a single sample |

## Provenance

Everything here is **generated, not captured**: every value is computed by
`tool/generate_analog_fixtures.dart` from a closed-form expression, so the
waveforms are reproducible on any machine and carry no third-party licence
obligations. No `PROVENANCE.md` is required (that requirement applies to the
`captured/` tier of the protocol corpus).
