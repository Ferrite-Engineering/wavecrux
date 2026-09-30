// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/ai_model_client_provider.dart';
import 'package:wavecrux/domain/interfaces/ai_model_client.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/features/ai/providers/explain_selection_provider.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/ai/explain_selection.dart';

import '../../../helpers/product_telemetry_config.dart';
import '../../../support/fake_waveform_source.dart';

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource _source;
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

/// A configured client that replays a canned response, simulating the
/// "recorded/faked model response" the grounding test feeds in.
class _CannedClient implements AiModelClient {
  _CannedClient(this._response);
  final String _response;
  @override
  bool get isConfigured => true;
  @override
  Stream<AiStreamEvent> send(AiRequest request) async* {
    yield AiTextDelta(_response);
    yield const AiResponseCompleted(finishReason: 'stop');
  }
}

ProviderContainer _container({AiModelClient? client}) {
  final container = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      waveformSourceProvider.overrideWith(
        () => _FakeSourceNotifier(FakeWaveformSource.reference()),
      ),
      if (client != null) aiModelClientProvider.overrideWithValue(client),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'a configured client produces a ready state with parsed citations',
    () async {
      final c = _container(
        client: _CannedClient(
          'The clock toggles [[cite:signal=top.clk,time=10]] and data updates '
          '[[cite:time=15]].',
        ),
      );
      // Selection is keyed by fullPath (row identity), not signalRef.
      c.read(selectedVariablesProvider.notifier).toggle('top.clk');

      await c.read(explainSelectionProvider.notifier).explainCurrentSelection();

      final state = c.read(explainSelectionProvider);
      expect(state.phase, ExplainSelectionPhase.ready);
      final citations = state.segments.whereType<ExplainCitation>().toList();
      expect(citations, hasLength(2));
      expect(citations.first.signal, 'top.clk');
      expect(citations.first.time, 10);
      expect(citations.last.time, 15);
    },
  );

  test(
    'an empty selection yields the emptySelection phase (no model call)',
    () async {
      // No signal selected; a canned client is supplied but must not be reached.
      final c = _container(client: _CannedClient('unused'));

      await c.read(explainSelectionProvider.notifier).explainCurrentSelection();

      expect(
        c.read(explainSelectionProvider).phase,
        ExplainSelectionPhase.emptySelection,
      );
    },
  );

  test('the open-core no-op client surfaces a notConfigured phase', () async {
    // No client override → the default NoopAiModelClient (isConfigured false).
    final c = _container();
    c.read(selectedVariablesProvider.notifier).toggle('top.clk');

    await c.read(explainSelectionProvider.notifier).explainCurrentSelection();

    expect(
      c.read(explainSelectionProvider).phase,
      ExplainSelectionPhase.notConfigured,
    );
  });

  test('close() returns the controller to idle', () async {
    final c = _container(client: _CannedClient('hi'));
    c.read(selectedVariablesProvider.notifier).toggle('top.clk');
    await c.read(explainSelectionProvider.notifier).explainCurrentSelection();
    expect(c.read(explainSelectionProvider).isActive, isTrue);

    c.read(explainSelectionProvider.notifier).close();
    expect(c.read(explainSelectionProvider).isActive, isFalse);
  });
}
