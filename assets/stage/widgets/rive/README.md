# Tachometer Stage Widget — Rive runtime asset

This directory holds the Rive runtime asset for the Tachometer reference
widget. It is also the canonical worked example for custom Stage widget
authors targeting the Rive binding contract described in the user guide's
*Authoring Rive widgets* page (`https://docs.wavecrux.app/authoring-rive-widgets/`).

## Editor contract

A designer authors `runtime/tachometer.riv` in the
[Rive editor](https://rive.app/) using the contract below. The
`tachometer.wcrux-widget` bundle in this directory is the bundled
`.wcrux-widget` artifact that ships alongside the built-in registration
in `registerBuiltinStageWidgets()`; regenerate it with
`dart run tool/generate_tachometer_bundle.dart` whenever any input
under this directory changes.

The committed `runtime/tachometer.riv` is a zero-byte placeholder that
ships **before** the designer authors the real artboard. The renderer
loads the asset via `loadRiveFileForStageWidget` and surfaces a
localized "Widget failed to load" placeholder when the file is empty or
malformed — there is no other change required when the real `.riv`
lands. The committed bundle artifact is regenerated against whichever
bytes are present at the time `tool/generate_tachometer_bundle.dart`
runs.

### Artboard

- **One artboard.** The artboard is the gauge face plus the needle, the
  redline glow layer, and the redline-pulse animation. The runtime
  loads the file's default artboard (`File.defaultArtboard()`); the
  artboard name is not consulted, so designers may leave it as the
  Rive default.
- **Recommended canvas size:** 320 × 220 dp matches
  `TachometerStageWidget.defaultSize`. The renderer fits the artboard
  into whatever rectangle the user has resized the Stage instance to,
  so smaller canvas sizes will be scaled up at render time. Larger
  canvas sizes are fine but produce no visible benefit on desktop.
- **Origin:** `frameOrigin: true` (the rive package default). The
  renderer does not adjust artboard origin.

### State machine

- **One state machine,** named `Tachometer`. The runtime resolves it
  by name via `Artboard.stateMachine("Tachometer")` — additional state
  machines on the artboard are ignored. Renaming the state machine
  requires a corresponding update to
  `lib/features/stage/widgets/tachometer/tachometer_stage_widget.dart`.

### Inputs

The state machine declares **exactly three** named inputs. Names are
case-sensitive and must match the manifest's `signal_bindings`
verbatim — state-machine input names match the manifest's binding names.

| Name      | Rive type | Source contract |
|-----------|-----------|-----------------|
| `rpm`     | `Number`  | `LinearNormalizer(input_min: 0, input_max: 8192, output_min: 0.0, output_max: 1.0, clamp: true)` applied to the bound vector signal. The renderer further overrides the input range from the per-instance config (`min_rpm`, `max_rpm`) when the user adjusts the gauge bounds. The state machine's needle blend should drive 100 % needle deflection at `rpm = 1.0`. |
| `redline` | `Boolean` | Bound directly from the user's `redline` 1-bit signal. The artboard renders the redline glow when `redline = true`. |
| `shift`   | `Boolean` | Bound directly from the user's `shift` 1-bit signal. The state machine **internally** detects rising edges on this Boolean and triggers the redline-pulse animation in response (e.g. `whenever shift transitions to true → fire pulse`). The runtime does NOT use a Rive Trigger input here — the binding contract's type routing maps `NormalizedBool → BooleanInput`, not `BooleanInput → TriggerInput`, so the edge detection lives in the state machine, not the runtime. |

A misbinding (e.g. defining `rpm` as a `Boolean`, omitting an input,
or adding an undeclared `Number` input the manifest doesn't reference)
is detected by `RiveBackedAnimationController` at runtime — the
mismatched manifest binding logs a warning to `wavecrux_pro.stage_pro`
and the renderer surfaces the localized "Widget failed to load"
placeholder.

### Animations the artboard should expose

- **Needle deflection.** A blend animation (or equivalent) tied to the
  `rpm` input that rotates the needle from the gauge's start angle at
  `rpm = 0.0` to the gauge's end angle at `rpm = 1.0`. The state
  machine should clamp at the endpoints (the renderer's normalizer
  already clamps, but artboard-level clamping is robust against bad
  data).
- **Redline glow.** A layer whose opacity is bound to the `redline`
  Boolean input. Glow visible when `redline = true`; hidden otherwise.
- **Shift pulse.** A short pulse animation (≤ 250 ms) that plays once
  on each rising edge of the `shift` Boolean input. The state machine
  triggers this internally — see the inputs table above.

### Authoring workflow

1. Author the artboard in the Rive editor.
2. Save the editable source as `source/tachometer.rive` (this
   directory's sibling). The `source/` directory is committed so a
   future maintainer can re-edit without losing work; only the
   compiled `.riv` is referenced by the manifest.
3. Export the runtime artifact as `runtime/tachometer.riv` (overwrite
   the placeholder).
4. Run the bundle generator from the repository root:
   ```sh
   dart run tool/generate_tachometer_bundle.dart
   ```
   This rebuilds `tachometer.wcrux-widget` against the new asset.
5. Run `flutter run` and drop the tachometer onto a Stage panel — the
   gauge animates as the user scrubs the timeline.

### Trademark / credits

Tachometer is a generic instrument — no trademarked board, vendor, or
licensed asset is referenced. Reuse / adaptation of the artboard is
unrestricted within the Pro overlay's licensing terms.
