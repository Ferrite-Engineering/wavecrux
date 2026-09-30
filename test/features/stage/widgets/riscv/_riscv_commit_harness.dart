// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_stage_renderer.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_stage_widget.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/translator_registry.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';

import '../../../../helpers/generated_vcd_fixture.dart';

/// Directory the generated RVFI fixtures live in.
const String riscvFixtureDir = 'test/fixtures/protocol/riscv/generated';

/// The clean RVFI fixture — 8 retirements, no inconsistency.
const String cleanRvfiFixture = '$riscvFixtureDir/riscv_rvfi_retire.vcd';

/// RV32 set composition, so the fixture's encodings resolve as RV32I rather
/// than being shadowed by the RV64I redefinitions.
InstructionDisassembler rv32Disassembler() {
  const names = ['RV32I', 'RV32M', 'RV32A', 'RV32F', 'RV32C-lower'];
  return InstructionDisassembler(<InstructionSet>[
    for (final n in names)
      parseInstructionSetToml(
        File('assets/decoders/isa/riscv/$n.toml').readAsStringSync(),
        sourceLabel: '$n.toml',
      ),
  ]);
}

/// A Commit Inspector instance bound to every RVFI channel the fixture
/// carries, minus [omit].
StageInstance riscvCommitInstance(
  GeneratedVcdFixture fixture, {
  Set<RvfiChannel> omit = const {},
  Map<String, Object?> configuration = const {},
}) {
  final byName = <String, StageSignalBinding>{};
  for (final variable in fixture.variables.values) {
    for (final channel in RvfiChannel.values) {
      if (variable.name != channel.signalName) continue;
      if (omit.contains(channel)) continue;
      byName[channel.signalName] = StageSignalBinding(
        signalRef: variable.signalRef,
      );
    }
  }
  return StageInstance(
    id: 'rvfi0',
    widgetId: RiscvCommitStageWidget.widgetId,
    signalBindings: byName,
    configuration: configuration,
  );
}

/// Pumps the Commit Inspector over [fixture] in [locale], with the cursor
/// placed at [cursorTime] (defaults to the end of the trace, so every view
/// has content).
Future<ProviderContainer> pumpRiscvCommit(
  WidgetTester tester, {
  required GeneratedVcdFixture fixture,
  required StageInstance instance,
  Locale locale = const Locale('en'),
  int? cursorTime,
  Size surface = const Size(720, 640),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        waveformSourceProvider.overrideWith(
          () => _FixtureSourceNotifier(fixture),
        ),
        riscvDisassemblerProvider.overrideWith(
          (ref) async => rv32Disassembler(),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: RiscvCommitStageRenderer(instance: instance),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
  container
      .read(cursorStateProvider.notifier)
      .placePrimary(cursorTime ?? fixture.source.endTime);
  await tester.pumpAndSettle();
  return container;
}

class _FixtureSourceNotifier extends WaveformSourceNotifier {
  _FixtureSourceNotifier(this._fixture);

  final GeneratedVcdFixture _fixture;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_fixture.source);
}
