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
import 'package:wavecrux/features/stage/widgets/pipeline/pipeline_stage_renderer.dart';
import 'package:wavecrux/features/stage/widgets/pipeline/pipeline_stage_widget.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/translator_registry.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';

import '../../../../helpers/generated_vcd_fixture.dart';

/// Directory the generated pipeline fixtures live in.
const String pipelineFixtureDir = 'test/fixtures/protocol/riscv/generated';

/// The five-stage fixture whose branch kill is signalled on the flush pins —
/// positional tracking models it exactly and reports high confidence.
const String cleanPipelineFixture =
    '$pipelineFixtureDir/riscv_pipeline_5stage.vcd';

/// The same pipe with the kill expressed only by dropping `valid`. Positional
/// tracking cannot model it and must say so.
const String defeatPipelineFixture =
    '$pipelineFixtureDir/riscv_pipeline_defeat.vcd';

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

/// Every pin the five-stage fixture carries a signal for.
List<String> pipelinePins({int stages = 5}) => <String>[
  PipelineStageWidget.clockPin,
  PipelineStageWidget.instructionPin,
  for (var s = 1; s <= stages; s++)
    for (final role in const ['valid', 'pc', 'stall', 'flush'])
      PipelineStageWidget.stagePin(s, role),
];

/// A Pipeline Diagram instance bound to the fixture's signals, minus [omit].
StageInstance pipelineInstance(
  GeneratedVcdFixture fixture, {
  int stages = 5,
  Set<String> omit = const {},
  Map<String, Object?> configuration = const {},
}) {
  final byName = <String, StageSignalBinding>{};
  for (final pin in pipelinePins(stages: stages)) {
    if (omit.contains(pin)) continue;
    final variable = fixture.variables.values
        .where((v) => v.name == pin)
        .firstOrNull;
    if (variable == null) continue;
    byName[pin] = StageSignalBinding(signalRef: variable.signalRef);
  }
  return StageInstance(
    id: 'pipe0',
    widgetId: PipelineStageWidget.widgetId,
    signalBindings: byName,
    configuration: {
      PipelineStageWidget.paramStageCount: stages,
      ...configuration,
    },
  );
}

/// Pumps the Pipeline Diagram over [fixture] in [locale], with the cursor at
/// [cursorTime] (defaults to the end of the trace).
Future<ProviderContainer> pumpPipeline(
  WidgetTester tester, {
  required GeneratedVcdFixture fixture,
  required StageInstance instance,
  Locale locale = const Locale('en'),
  int? cursorTime,
  Size surface = const Size(900, 640),
  bool withDisassembler = true,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        waveformSourceProvider.overrideWith(
          () => _FixtureSourceNotifier(fixture),
        ),
        if (withDisassembler)
          riscvDisassemblerProvider.overrideWith((ref) async {
            return rv32Disassembler();
          }),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: PipelineStageRenderer(instance: instance)),
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
