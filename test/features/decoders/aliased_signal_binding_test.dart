// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Decoder signal pickers and auto-bind over an aliased waveform: one signal
// declared under several names (one VCD identifier code on three `$var`
// lines). Every name must be offered and must be an auto-bind candidate; the
// binding stores the shared signalRef.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/auto_bind_candidate.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_config_dialog.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/decoders/decoder_auto_bind_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

const _fixture = 'test/fixtures/vcd/aliased_signals.vcd';
const _aliases = ['tb.data', 'tb.u_view.TxData', 'tb.u_view.src_data'];

/// A decoder whose only input is named after one alias of the signal.
const _txDef = DecoderDefinition(
  id: 'alias_probe',
  displayName: 'Alias probe',
  description: 'One 8-bit input named TxData',
  requiredSignals: [
    SignalBinding(name: 'TxData', description: 'Data', bitWidth: 8),
  ],
);

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

void main() {
  if (!requireWellenFfiLibrary('aliased signal binding')) return;

  late WellenProvider source;
  late Map<String, Variable> byPath;
  late Map<String, Variable> byRef;

  setUpAll(() async {
    source = WellenProvider();
    await source.openFile(_fixture);
    final container = ProviderContainer(
      overrides: [
        waveformSourceProvider.overrideWith(() => _FakeSourceNotifier(source)),
      ],
    );
    byPath = container.read(signalVariablesByPathProvider);
    byRef = container.read(signalVariablesMapProvider);
    container.dispose();
  });

  tearDownAll(() => source.close());

  test('the fixture declares three names for one signal', () {
    expect(byPath.keys.toSet(), _aliases.toSet());
    expect({for (final v in byPath.values) v.signalRef}, hasLength(1));
    // The ref-keyed map keeps one name per alias group, which is why the
    // pickers must not list from it.
    expect(byRef, hasLength(1));
  });

  test('auto-bind matches an input by any alias name and stores the '
      'shared signalRef', () {
    final result = const DecoderAutoBindService().computeBindings(
      definition: _txDef,
      availableSignals: byPath,
      currentParameters: const {},
    );
    final candidate = result.candidates['TxData']!;
    expect(candidate.confidence, isNot(AutoBindConfidence.noMatch));
    expect(candidate.fullPath, 'tb.u_view.TxData');
    expect(candidate.signalRef, byPath['tb.u_view.TxData']!.signalRef);
  });

  Widget host({bool autoBindOnOpen = false}) => ProviderScope(
    child: MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: DecoderConfigDialog(
          definition: _txDef,
          signalMap: byPath,
          autoBindOnOpen: autoBindOnOpen,
        ),
      ),
    ),
  );

  testWidgets('the signal picker lists every alias name', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();

    for (final path in _aliases) {
      expect(find.text(path), findsWidgets, reason: path);
    }

    // Picking one alias shows that name, not whichever alias the shared
    // signalRef happens to resolve to first.
    await tester.tap(find.text('tb.u_view.src_data').last);
    await tester.pumpAndSettle();
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(dropdown.value, 'tb.u_view.src_data');
  });

  testWidgets('auto-bind on open selects the matching alias name', (
    tester,
  ) async {
    await tester.pumpWidget(host(autoBindOnOpen: true));
    await tester.pumpAndSettle();

    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(dropdown.value, 'tb.u_view.TxData');
  });
}
