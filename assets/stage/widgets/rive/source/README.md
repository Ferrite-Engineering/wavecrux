# Stage Rive editor sources

This directory holds the **editable** Rive editor sources for the Stage
widgets that use the Rive runtime. Each `<widget>.rev` file (the Rive
editor's source format) pairs with the compiled runtime artifact at
`../runtime/<widget>.riv`.

The compiled `.riv` is the only file the renderer references; the `.rev`
source lives here so maintainers can re-open and re-edit the artboard
without recovering it from the binary runtime file.

## Tachometer (`tachometer.rev`)

Editable source for the open-core Tachometer **reference** widget (it is
free open-core, not Pro). See [`../README.md`](../README.md) for the
binding contract — the editor contract there is what this artboard
implements.

The canonical master is the cloud Rive project (Ferrite Engineering
workspace → *Tachometer*); `tachometer.rev` is a committed export of it so
the artboard is recoverable from this repo. The current artboard is the
fully-styled gauge — dark face + bezel, dashed tick ring, redline arc,
orange needle + hub — with a state machine named `Tachometer` whose three
named inputs (`rpm` Number, `redline` Boolean, `shift` Boolean) are wired
across three layers (needle blend, redline glow, shift pulse).

Authoring workflow:

1. Open `tachometer.rev` in the Rive editor (or edit the cloud project).
2. Export the compiled runtime artifact to `../runtime/tachometer.riv`.
3. Re-export the editable source back over `tachometer.rev`.
4. Run `dart run tool/generate_tachometer_bundle.dart` to regenerate the
   `.wcrux-widget` bundle artifact.

The renderer loads the compiled `.riv` only. This source file is never
read at runtime; it exists purely to support the authoring workflow.
