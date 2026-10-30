# Waveforms from ROHD: Go to Dart source

[ROHD](https://github.com/intel/rohd) builds hardware in Dart and writes a VCD
with its `WaveDumper`. That VCD says which signal changed, but not which Dart
line created the signal. When ROHD has recorded that, WaveCrux adds a **Go to
Dart Source** action to the signal's context menu, which opens your editor on
the line.

This is from WaveCrux 1.2, and is labelled **ROHD 0.7 or later (source
tracing)**: the source-trace file it reads is written by ROHD 0.7 and later, and
only when source tracing is on. For the whole path from ROHD to WaveCrux, see
[ROHD + EDACrux](rohd-and-edacrux.md).

## Turn tracing on in your ROHD flow {#flow}

Call `SourceTracer.activate()` before the design is built, and write the
trace file next to the waveform:

```dart
SourceTracer.activate();
final top = Top(/* ... */);
await top.build();

final sv = SystemVerilogService(top);
TraceService(top, svService: sv, packageRoot: Directory.current.path)
    .write('build');                       // writes build/Top.flc.json
top.dumpWaves(outputPath: 'build/top.vcd');
```

`Top.flc.json` is the source-trace file ("FLC": file, line, column). Version 6
is the version read here. The waveform itself carries no source information,
so the file is required.

## Where WaveCrux looks {#find}

When a signal's menu opens, WaveCrux looks for the source-trace file in this
order:

1. **Settings > Editors > ROHD source-trace file**, if set: a `.flc.json` file,
   or a folder holding some.
2. `<waveform name>.flc.json` next to the open waveform.
3. Every `*.flc.json` next to the open waveform.

When there are several candidates, the first that describes the waveform's top
scope is used. A file of any version other than 6, or one that cannot be read,
is skipped and noted in the log; nothing else happens.

**Go to Dart Source** runs the editor command from **Settings > Editors > Editor
Command** (for example `code -g`) with `file:line:column` appended, the same
command WaveCrux uses when another Crux app asks it to open a source file. With
no editor command set, the action says so.

## What it resolves {#resolve}

The action appears only when the signal is found; a signal ROHD did not trace
shows an unchanged menu.

- The waveform's scope path is matched to the instance paths in the file.
  ROHD names a module instance `reg` in the trace file and `reg_` in the
  SystemVerilog and the waveform, because `reg` is a SystemVerilog keyword; a
  trailing underscore is dropped from any part of the path when the exact path
  is not found.
- The signal name is matched to the traced name, then to the original Dart name
  for struct fields (`inner_pkt_data` in the waveform, `data` in Dart).
- Signals inside ROHD's own modules (the adder, the flop, a combinational
  block) resolve to the line that created them.
- The signal's creator is the innermost Dart frame. The frames outward from it
  (where the module was instantiated) are recorded but the action opens the
  creator.

**Bus slices.** Two slices of one signal are listed under the same path, each
with a copy of the signal's name. When those copies trace to different Dart
lines, the waveform cannot tell them apart: WaveCrux opens the first one the
file lists, always the same one, and says that the name matched more than one
line.

**Whole structs.** A struct shown as one wide signal has no entry of its own in
the file, only its fields do. Its menu has no Go to Dart Source; its fields do.

## Limits {#limits}

- Only waveforms ROHD wrote itself are mapped: the join relies on ROHD's
  instance naming.
- The action does not appear in the viewer's signal list, only in the signal
  tree.
