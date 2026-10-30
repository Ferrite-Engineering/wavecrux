# ROHD + EDACrux, from WaveCrux 1.2

[ROHD](https://github.com/intel/rohd) is Intel's open-source hardware framework written in Dart. You describe hardware as Dart classes, simulate it in Dart, and generate SystemVerilog or a netlist from the same code. This page is for ROHD users. It shows how to get a ROHD waveform into WaveCrux, how to jump from a signal back to the Dart line that created it, and how WaveCrux works with the other EDACrux apps on the same design.

!!! note "From WaveCrux 1.2"

    Opening a ROHD waveform works in any WaveCrux, because it is an ordinary VCD. **Go to Dart Source** is from WaveCrux 1.2 and needs ROHD 0.7 or later, with source tracing on (below). The other EDACrux apps have the same kind of page: [NetCrux](https://docs.netcrux.app/rohd-and-edacrux), [LintCrux](https://docs.lintcrux.app/rohd-and-edacrux) and [SimCrux](https://docs.simcrux.app/rohd-and-edacrux).

## What WaveCrux does with ROHD output

| You have | WaveCrux | Where |
|---|---|---|
| A VCD written by ROHD | Opens it, with ROHD's module hierarchy as the scope tree. | [Write the waveform](#write), [Open it](#open) |
| ROHD's source-trace file, `<Top>.flc.json`, beside the VCD | Adds **Go to Dart Source** to a signal's menu, which opens your editor on the Dart line that created the signal. | [Go to Dart Source](#source) |
| A signal selected in NetCrux, or a failing test in SimCrux | Receives it over CXP and shows the signal. | [Cross-probe](#cross-probe) |

## Write the waveform from ROHD {#write}

ROHD writes a VCD for a simulation with `dumpWaves`. Call it before you run the simulation:

```dart
import 'dart:io';
import 'package:rohd/rohd.dart';

Future<void> main() async {
  final top = MyDesign(Logic(), Logic());  // your top module
  await top.build();

  Directory('build').createSync(recursive: true);
  top.dumpWaves(outputPath: 'build/MyDesign.vcd');

  // Drive your inputs with Simulator.registerAction, as usual.
  Simulator.setMaxSimTime(1000);
  await Simulator.run();
}
```

Earlier ROHD releases write the same kind of file with `WaveDumper(top, outputPath: 'build/MyDesign.vcd')`, which newer ROHD deprecates in favour of `dumpWaves`.

## Open it in WaveCrux {#open}

```bash
wavecrux build/MyDesign.vcd
```

Or choose `File → Open File`, or ++cmd+o++ / ++ctrl+o++. The format is detected from the file itself. Opening the VCD is all you need to browse signals, measure, decode buses and annotate. See [Files & sessions](files-and-sessions.md).

To open the waveform together with the rest of the design, name it in a `<design>.crux-project` file. See [one file for the whole design](https://docs.netcrux.app/rohd-and-edacrux#manifest).

## Go to Dart Source {#source}

The VCD says which signal changed, not which Dart line created the signal. ROHD 0.7 can record that when source tracing is on, in a source-trace file next to the waveform. With that file, a signal's menu in the signal tree gets **Go to Dart Source (ROHD 0.7 or later)**, and it opens your editor on the line.

Activate the tracer before the design is built, and write the trace file after:

```dart
import 'dart:io';
import 'package:rohd/rohd.dart';

Future<void> main() async {
  SourceTracer.activate();                 // before any Logic or Module is created
  final top = MyDesign(Logic(), Logic());
  await top.build();

  TraceService(
    top,
    svService: SystemVerilogService(top),
    packageRoot: Directory.current.path,
  ).write('build');                        // writes build/MyDesign.flc.json

  top.dumpWaves(outputPath: 'build/MyDesign.vcd');
  Simulator.setMaxSimTime(1000);
  await Simulator.run();
}
```

`MyDesign.flc.json` is the source-trace file ("FLC": file, line, column). WaveCrux reads version 6. It looks for the file in this order: the path in `Settings → Editors → ROHD source-trace file` if you set one, then `<waveform name>.flc.json` next to the waveform, then every `*.flc.json` next to it. The first that describes the waveform's top scope wins.

**Go to Dart Source** runs the command in `Settings → Editors → Editor Command` (for example `code -g`) with `file:line:column` appended. With no editor command set, the action tells you so.

[Waveforms from ROHD: Go to Dart source](rohd.md) has the rules for how a signal is matched to the file, and the limits: bus slices, whole structs, and signals in ROHD's own modules.

## Cross-probe with the other apps {#cross-probe}

WaveCrux, NetCrux, LintCrux and SimCrux find each other on the same machine and talk over **CXP**, the cross-probe protocol. An element travels as a dot-separated hierarchical path such as `top.cpu.alu.result`, so every app means the same thing by the same name.

- Select a signal in WaveCrux and send it to NetCrux, and it lights up on the schematic of the same design. Select a net in NetCrux and it highlights in the waveform. See [CXP, cross-probing](automation-and-collaboration.md#cxp).
- If a name differs between the two files, the app that cannot find it says so and selects nothing. ROHD renames an instance called `reg` to `reg_` in its generated SystemVerilog and in its waveform, because `reg` is a SystemVerilog keyword.

### From your own Dart code, coming with EDACrux 1.2

A Dart package, `edacrux_cxp`, is coming with EDACrux 1.2. It is a pure-Dart CXP client with no Flutter dependency, so a running ROHD simulation or test can ask WaveCrux to show a signal and NetCrux to highlight a net. It is not published yet, so there is nothing to add to your `pubspec.yaml` today.

## Related

- [Waveforms from ROHD: Go to Dart source](rohd.md)
- [Files & sessions](files-and-sessions.md)
- [Automation & collaboration](automation-and-collaboration.md#cxp)
- [Use in VS Code](vscode.md)
