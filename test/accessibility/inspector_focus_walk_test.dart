// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// What a keyboard and screen reader user meets in the Inspector: a decoder's
// bindings and parameters, and a fixed-point signal row's Q-format knobs. The
// transcripts under `goldens/` are what the focus walk records, as text and so
// independent of the renderer; a change in what is announced shows up as a
// diff there. Value rows are not Tab stops, and a clean form's Apply and
// Revert are disabled, so neither is walked.
//
// LOCALE_SWEEP_EXEMPT: the transcripts are English goldens of the Tab order;
// every locale's rendering is swept by decoder_config_section_test.dart and
// signal_format_section_test.dart.

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/decoder_parameter.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/viewer/providers/inspector_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';

import '../helpers/inspector_test_host.dart';

const _uart = DecoderDefinition(
  id: 'uart_walk',
  displayName: 'UART',
  description: 'UART',
  requiredSignals: [SignalBinding(name: 'rx', description: 'Receive')],
  optionalSignals: [SignalBinding(name: 'tx', description: 'Transmit')],
  parameters: [
    DecoderParameter(
      name: 'baud',
      type: DecoderParameterType.integer,
      defaultValue: 9600,
      description: 'Baud rate',
    ),
  ],
);

void main() {
  const goldens = 'test/accessibility/goldens';

  testWidgets('a decoder in the Inspector is walked as named controls', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    registerInspectorTestDecoder(_uart);
    final container = await pumpInspectorHost(
      tester,
      signals: inspectorTestSignals([inspectorTestVar('tb.rx')]),
    );
    final id = container
        .read(activeDecodersProvider.notifier)
        .addDecoder(
          _uart.id,
          const DecoderConfig(signalBindings: {'rx': 'tb.rx'}),
        );
    container
        .read(inspectedObjectProvider.notifier)
        .select(InspectedDecoder(id));
    await tester.pumpAndSettle();

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'Inspector, UART #1');
    expect(
      walk.stops.map((s) => s.line).join('\n'),
      allOf(contains('Auto-bind signals'), contains('rx'), contains('baud')),
    );
    expectFocusWalkGolden(walk, '$goldens/inspector_decoder.txt');
    handle.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a fixed-point signal row in the Inspector is walked as named '
      'controls', (tester) async {
    final handle = tester.ensureSemantics();
    final container = await pumpInspectorHost(tester);
    final groups = container.read(signalGroupsProvider.notifier)
      ..addSignal(inspectorTestVar('tb.sample', bitWidth: 16));
    final entry = container.read(signalGroupsProvider).entries.last;
    groups.setSignalFormatById(entry.id, DisplayFormat.fixedPointQ);
    container
        .read(inspectedObjectProvider.notifier)
        .select(InspectedSignal(entry.id));
    await tester.pumpAndSettle();

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'Inspector, signal sample');
    expect(
      walk.stops.map((s) => s.line).join('\n'),
      allOf(contains('Integer bits'), contains('Signed')),
    );
    expectFocusWalkGolden(walk, '$goldens/inspector_signal_q_format.txt');
    handle.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
