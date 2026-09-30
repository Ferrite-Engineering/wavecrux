// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/stage/providers/riscv_commit_auto_stage.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_stage_widget.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';

/// Unit-level cover for the auto-mount's own decisions. The end-to-end proof
/// that it fires on the real hand-off lives in
/// `riscv_counterexample_handoff_test.dart`; this file is about the cases that
/// hand-off never reaches.
void main() {
  Variable rvfi(String name) => Variable(
    name: name,
    varType: VarType.wire,
    direction: VarDirection.output,
    signalRef: 'rvfi.$name',
    scopePath: 'rvfi',
    bitWidth: 32,
  );

  Map<String, Variable> fullBundle() => <String, Variable>{
    for (final c in RvfiChannel.values)
      'rvfi.${c.signalName}': rvfi(
        c.signalName,
      ),
  };

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  String? mount(Map<String, Variable> signals) => mountRiscvCommitInspector(
    workspace: container.read(stageWorkspaceProvider.notifier),
    current: container.read(stageWorkspaceProvider),
    layout: container.read(panelLayoutProvider.notifier),
    availableSignals: signals,
    panelName: 'RVFI Commit',
  );

  test('mounts one bound inspector on a fresh workspace', () {
    final id = mount(fullBundle());
    expect(id, isNotNull);
    final workspace = container.read(stageWorkspaceProvider);
    final instance = workspace.panels.single.instances.single;
    expect(instance.widgetId, RiscvCommitStageWidget.widgetId);
    expect(instance.id, id);
    expect(
      instance.signalBindings.keys.toSet(),
      {for (final c in RvfiChannel.values) c.signalName},
    );
    // The cross-probe's own mount size, NOT the widget's `defaultSize`. At
    // 380 tall the inspector's chrome leaves room for four commit rows and a
    // six-retirement counterexample lands below the fold — the panel is
    // mounted for one purpose and has to be big enough to serve it.
    expect((instance.width, instance.height), kRiscvCrossProbeMountSize);
    expect(
      instance.height,
      greaterThan(const RiscvCommitStageWidget().defaultSize.$2),
      reason: 'the auto-mount must not fall back to the bare default',
    );
    final layout = container.read(panelLayoutProvider);
    expect(layout.stageViewVisible, isTrue);
    expect(layout.bottomDockShowsStage, isTrue);
    // Sizing the instance is only half of "visible": the Stage canvas pans
    // rather than scrolls, so a 420 px instance in the default 200 px dock is
    // a banner and nothing else.
    expect(layout.bottomPaneSize, kRiscvCrossProbeDockHeight);
  });

  test('a dock the user already made taller is left alone', () {
    // Raise-only. The dock's height is the user's setting everywhere else, and
    // a reveal has no business shrinking one they deliberately made big.
    container
        .read(panelLayoutProvider.notifier)
        .setBottomPaneSize(kRiscvCrossProbeDockHeight + 260);
    mount(fullBundle());
    expect(
      container.read(panelLayoutProvider).bottomPaneSize,
      kRiscvCrossProbeDockHeight + 260,
    );
  });

  test('the whole mount is ONE undo step', () {
    // Three mutations — panel, instance, bindings — but a user who did not
    // want the panel presses Ctrl+Z once, not three times.
    mount(fullBundle());
    final notifier = container.read(stageWorkspaceProvider.notifier);
    expect(notifier.canUndo, isTrue);
    notifier.undo();
    expect(container.read(stageWorkspaceProvider).panels, isEmpty);
    expect(notifier.canUndo, isFalse);
  });

  test('a second cross-probe onto the same tab does not stack a second '
      'inspector', () {
    expect(mount(fullBundle()), isNotNull);
    expect(mount(fullBundle()), isNull);
    expect(container.read(stageWorkspaceProvider).panels, hasLength(1));
  });

  test('a reduced bundle still mounts — the widget degrades, it does not '
      'block', () {
    // Rule 4: bind through the detection service and let the widget say which
    // channels are missing. Refusing to mount here would hide the one surface
    // that can explain the gap.
    final reduced = <String, Variable>{
      for (final c in [
        RvfiChannel.valid,
        RvfiChannel.order,
        RvfiChannel.insn,
        RvfiChannel.pcRdata,
      ])
        'rvfi.${c.signalName}': rvfi(c.signalName),
    };
    expect(mount(reduced), isNotNull);
    final instance = container
        .read(stageWorkspaceProvider)
        .panels
        .single
        .instances
        .single;
    expect(instance.signalBindings, hasLength(4));
  });

  test('a trace with no RVFI in it mounts nothing and leaves the layout '
      'alone', () {
    expect(mount(<String, Variable>{'top.clk': rvfi('clk')}), isNull);
    expect(container.read(stageWorkspaceProvider).panels, isEmpty);
    final layout = container.read(panelLayoutProvider);
    expect(layout.stageViewVisible, isFalse);
    // Including the dock height: nothing was mounted, so there is nothing to
    // make room for.
    expect(layout.bottomPaneSize, isNull);
  });
}
