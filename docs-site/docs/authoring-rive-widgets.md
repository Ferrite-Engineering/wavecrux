# Authoring Rive widgets

A WaveCrux Stage widget is a [Rive](https://rive.app) animation driven by your waveform's signals. As the cursor scrubs, a bound signal updates a Rive State Machine input every frame, so the artboard moves in lock-step with the timeline. You author the visual in Rive, then describe how signals map to its inputs in a `manifest.yaml`. This page is the full contract: the bundle layout, every manifest field, what your `.riv` file must contain, and how a signal value reaches a Rive input.

!!! tip "Free & Open Core"

    The Stage widget SDK is part of Open Core. Anyone can build, install, and run custom Rive widgets for free — no license key, no Pro tier, no account. The **Tachometer** reference widget ships in the open-core source (`assets/stage/widgets/rive/`, with its manifest and an editor-contract README), so you have a complete, working example to start from. (Only the *curated Pro widget pack* content is paid; the authoring capability is not.)

!!! note "Would rather commission one?"

    Authoring is free and documented here in full, but a polished widget is a design job as much as an engineering one. The BLDC motor, traffic-light intersection and elevator/lift in the curated Pro pack were designed and animated by **Jennifer Phillips**, who takes commissions — so if you want a widget for your own hardware and would rather not draw it yourself, she is the person we work with.

    Widget Design & Rive Animation by Jennifer Phillips · [jenniferphillipscreative.com](https://jenniferphillipscreative.com)

## Bundle layout { #bundle-layout }

A widget is distributed as a single `.wcrux-widget` bundle: a ZIP archive with a `manifest.yaml` at the root and the Rive runtime asset under a `runtime/` directory. An optional icon lives under `assets/`, and a `LICENSE` or `README.md` may ride along (the loader ignores them).

```text
my-tachometer.wcrux-widget   (a ZIP archive)
├── manifest.yaml            # required, at the root
├── runtime/
│   └── tachometer.riv       # required, the Rive runtime asset
└── assets/
    └── icon.png             # optional
```

Bundles are treated as untrusted and validated on load. The limits below keep an installed bundle small and prevent it from reaching outside its own directory:

- **Max 32 MiB** uncompressed.
- **Max path depth 8 segments.**
- Absolute paths, `..` traversal, and symlinks are **rejected**.

Open **Settings → Extensions → Custom Widgets** and click **Load widget bundle…** to install a `.wcrux-widget`; the widget then appears in the Stage **Add Stage Widget** picker. For an authoring loop, click **Watch directory…** instead and point it at the folder you write your bundles into: WaveCrux loads every `.wcrux-widget` in a watched directory and reloads a bundle when its file is added, replaced or removed — so re-zipping over the old bundle updates the widget without reinstalling. Loaded bundles and watched directories are remembered across launches; **Remove** and **Stop watching** undo them.

!!! tip

    A widget instance keeps its bindings by name. If you rename an input in Rive, rename the matching `signal_bindings` entry in the same edit, or the binding will need to be reconnected on the instance.

## The manifest { #manifest }

The `manifest.yaml` declares the widget's identity, points at the Rive asset, and lists the signal bindings the user can connect plus any normalizers applied to them. Here is a complete, realistic manifest for a tachometer widget:

```yaml
id: com.example.stage.tachometer
version: 1.0.0
display_name:
  en: Tachometer
category: instrument
runtime: rive
runtime_asset_path: runtime/tachometer.riv
required_api_version: 1
icon_asset_path: assets/icon.png

signal_bindings:
  - name: rpm
    description: Engine speed driving the needle deflection.
    signal_type: vector
    bit_width:
      min: 8
      max: 16
    required: true
    direction: input
    default_policy: hold_last
  - name: redline
    description: Asserted when the engine is over the redline; lights the warning glow.
    signal_type: scalar
    required: false
    direction: input
    default_policy: treat_as_zero
  - name: shift
    description: Pulses the shift indicator on a rising edge.
    signal_type: scalar
    required: false
    direction: input
    default_policy: treat_as_zero

parameters:
  - binding: rpm
    normalizer:
      kind: linear
      input_min: 0
      input_max: 8000
      output_min: 0.0
      output_max: 1.0
      clamp: true
```

The fields:

| Field | Meaning |
|---|---|
| `id` | A reverse-DNS identifier (e.g. `com.example.stage.tachometer`). Globally unique, persisted in sessions, and used as the registry key. |
| `version` | A semantic version string. |
| `display_name` | Localized labels. `en` is required; `zh`, `zh_CN`, `ja`, and `ko` are optional. |
| `category` | One of `primitive`, `peripheral`, `instrument`, `board`, `protocol`, or `custom`. |
| `runtime` | `rive` for an animated widget. |
| `runtime_asset_path` | Bundle-relative path to the `.riv`; must be under `runtime/`. |
| `required_api_version` | The SDK version the widget targets; currently `1`. A bundle outside the supported range is refused. |
| `icon_asset_path` | Optional bundle-relative path to an icon. |
| `signal_bindings` | An array of bindable inputs (see below). |
| `parameters` | An array of normalizer declarations bound to a `signal_bindings` entry by name. |

Each `signal_bindings` entry has:

| Key | Meaning |
|---|---|
| `name` | The binding id. **Case-sensitive** — must *exactly* match the Rive state-machine input name. |
| `description` | One sentence, shown in the binding UI. |
| `signal_type` | One of `scalar` (1-bit), `vector` (multi-bit), `analog` (real-valued), or `bus_group`. |
| `bit_width` | Optional `{min, max}` for vectors. |
| `value_range` | Optional `{min, max}`. |
| `required` | Boolean. While a required binding is unconnected, the widget shows a "Bind … to render this widget" placeholder instead of the artboard. |
| `direction` | `input`. |
| `default_policy` | Behavior when unbound: `hold_last` (default), `treat_as_zero`, or `treat_as_x`. |

## What your Rive file must contain { #rive-file }

The renderer makes three fixed assumptions about the `.riv` file:

- **One artboard, the file's default.** The renderer loads the default artboard; others are ignored.
- **The artboard's default State Machine.** The manifest has no state-machine name field, so a bundle's widget drives whichever state machine is the artboard's default — name it anything. (The built-in Tachometer is the one exception: it is compiled into the app and looks its state machine up by the name `Tachometer`.)
- **State-machine input names match manifest `signal_bindings` by exact, case-sensitive name.** A binding named `rpm` drives the input `rpm`.

!!! warning "Case-sensitive names"

    Input names are matched *exactly*, including case. A manifest binding named `rpm` will not connect to a Rive input named `RPM` or `Rpm`. When a **required** binding has no matching input, the whole widget shows **Widget failed to load** rather than running with a dead input — confirm the names line up character-for-character.

## How signals drive inputs { #routing }

On every frame the renderer takes the bound signal's value, applies any normalizer, and writes the result into the matching Rive input. The Rive input type you should author depends on the value that arrives:

| Value after normalization | Rive input |
|---|---|
| A true/false value (a `scalar`, or a `boolean` normalizer) | A **Boolean** input. |
| A number (a `vector` or `analog`, or a `linear` normalizer) | A **Number** input. |
| An enum label (an `enum` normalizer) | Fires a **Trigger** — the one named by the label, or else the one named like the binding. |
| An X/Z (unknown) sample | **Nothing is written** — the input holds its previous value. |

!!! note "Tolerate held values"

    When a sample is `X` or `Z`, the renderer writes nothing and the input *holds* its previous value. Design your state machine so that a stale held value is a sensible, non-glitching state — never assume every frame brings a fresh write.

!!! note "Edge detection lives in the state machine"

    Pulse-on-edge behavior — "flash when this Boolean becomes true" — belongs *inside* the Rive state machine as a transition, not as a runtime trigger. Model it as a transition ("when this Boolean becomes true, play the pulse"). This is exactly how the Tachometer's `shift` pulse works.

## Normalizing values { #normalizing }

A raw signal value rarely maps directly onto the 0.0–1.0 range a Rive animation expects. The `parameters` array binds a normalizer to a `signal_bindings` entry by name. Each entry is `{ binding: <name>, normalizer: { kind: <type>, … } }`; the normalizer's option keys are **snake_case** (`input_min`, not `inputMin`) and unknown keys are rejected at load. The normalizers:

| Normalizer | What it does |
|---|---|
| `linear` | Maps a raw value onto an output range: `output = output_min + (input − input_min) / (input_max − input_min) × (output_max − output_min)`. Options: `input_min` and `input_max` (required, and different), `output_min` / `output_max` (default 0.0–1.0), `clamp` (default true), `xz_policy`, and `default_value`. Use it to scale, say, an RPM count onto a 0.0–1.0 needle deflection. |
| `bit_field` | Extracts the bit slice `high_bit`…`low_bit`, optionally feeding it to a nested normalizer under `sub`. |
| `boolean` | Reduces a value to true/false — `reduction` is `lsb` (default), `anyHigh`, or `allHigh` — with `xz_policy` and `default_value`. |
| `enum` | Maps integer values to labels (`labels: {0: IDLE, 1: RUN}`), with an optional `default_label` and `xz_policy`. |

`xz_policy` decides what an unknown sample becomes: `propagate` (the default — the input holds its previous value), `as_default` (use the normalizer's default value or label), or `best_effort` (treat unknown bits as 0 unless every bit is unknown).

Normalizers can be **chained** — for example, a `bit_field` extract followed by a `linear` map, to pull a field out of a packed bus and then scale it onto an animation range. Use a `chain:` list in place of `kind:`; each stage feeds the next:

```yaml
parameters:
  - binding: data
    normalizer:
      chain:
        - kind: bit_field
          high_bit: 15
          low_bit: 8
        - kind: linear
          input_min: 0
          input_max: 255
          output_min: 0.0
          output_max: 1.0
```

## Per-instance configuration { #per-instance }

A widget compiled into the app can expose typed knobs — integer, decimal, toggle, text, and enum choice — each with a default and optional min/max/step. These render in the **Configuration** section of the bindings pane and let a user override ranges *per instance*. The Tachometer, for example, exposes minimum and maximum RPM knobs that override its manifest's static `input_min` / `input_max`, so two instances of the same widget can be calibrated for different engines.

Configuration is stored on the instance and persists in the session. Missing or invalid values fall back to the declared defaults rather than crashing — a malformed config never takes the widget down.

!!! warning "Config knobs need Dart"

    These per-instance knobs are **not** declarable in the manifest. They are defined in Dart on a `StageWidget` subclass (its `configParams`), so they are only available to widgets compiled into the app — the built-in widgets like the Tachometer, and the Pro pack. A community widget shipped as a manifest + `.riv` bundle has no per-instance config UI; bake your ranges into the manifest's static normalizers instead.

## The Tachometer reference { #tachometer }

The open-core **Tachometer** is the worked example to copy from. Its layout:

- One artboard, roughly 320×220.
- One state machine named `Tachometer`.
- Three inputs:
    - `rpm` — a Number, linearly normalized `0..8192` → `0.0..1.0` needle deflection (overridable per instance).
    - `redline` — a Boolean that lights the warning glow.
    - `shift` — a Boolean that triggers a pulse via a state-machine transition.

The reference widget ships in the open-core source under `assets/stage/widgets/rive/` — its `manifest.yaml`, the `.riv`, and a README with the full editor contract. Open the `.riv` in Rive and trace each input back to its manifest binding before building your own.

## Validation and troubleshooting { #troubleshooting }

When a bundle fails to load, **Settings → Extensions → Custom Widgets** lists it under **Failed to load** with the reason; when a loaded widget cannot render, the instance shows **Widget failed to load** and the reason is logged (see [Logs](interface.md#logs)). Map the symptom to its cause:

| Symptom | Cause |
|---|---|
| "Not a valid .wcrux-widget archive." | The file is not a ZIP archive. |
| "Bundle is missing manifest.yaml." / "Bundle manifest is invalid." | No manifest at the root, or it fails validation (unknown key, missing required field, bad value). |
| "Bundle is missing its runtime asset file." | `runtime_asset_path` names a file that is not in the archive. |
| "Bundle requires a newer Stage Pro SDK than this build supports." | `required_api_version` is outside the supported range. |
| Size, path-depth, traversal or symlink refusals | The archive breaks one of the limits above. |
| **Widget failed to load** on the Stage | The `.riv` is empty or corrupt, the artboard has no default state machine, or a required binding has no matching input. |
| "Bind … to render this widget." | A required binding is not connected yet. |

!!! tip "A working loop"

    Load the bundle once, leave it on the Stage, and keep Rive open beside WaveCrux. Write your re-zipped `.wcrux-widget` into a directory you added with **Watch directory…**, and each update reloads the widget — so you can confirm input names, normalizer ranges, and the held-value behavior against a real waveform without reinstalling.
