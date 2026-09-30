// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/ai_model_client_provider.dart';
import 'package:wavecrux/domain/interfaces/ai_model_client.dart';
import 'package:wavecrux/services/ai/noop_ai_model_client.dart';

class _FakeConfiguredClient implements AiModelClient {
  @override
  bool get isConfigured => true;

  @override
  Stream<AiStreamEvent> send(AiRequest request) async* {
    yield const AiResponseCompleted(finishReason: 'stop');
  }
}

void main() {
  test('open-core default is the unconfigured NoopAiModelClient', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final client = container.read(aiModelClientProvider);
    expect(client, isA<NoopAiModelClient>());
    expect(client.isConfigured, isFalse);
  });

  test('an overlay can override the provider with a configured client', () {
    final container = ProviderContainer(
      overrides: [
        aiModelClientProvider.overrideWithValue(_FakeConfiguredClient()),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(aiModelClientProvider).isConfigured, isTrue);
  });
}
