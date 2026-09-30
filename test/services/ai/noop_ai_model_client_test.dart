// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/ai_model_client.dart';
import 'package:wavecrux/services/ai/noop_ai_model_client.dart';

void main() {
  group('NoopAiModelClient', () {
    test('reports it is not configured', () {
      expect(const NoopAiModelClient().isConfigured, isFalse);
    });

    test(
      'send yields a single notConfigured event and completes — no throw',
      () async {
        const client = NoopAiModelClient();
        final events = await client
            .send(const AiRequest(messages: [AiMessage.user('explain this')]))
            .toList();

        expect(events, hasLength(1));
        final only = events.single;
        expect(only, isA<AiClientUnavailable>());
        expect(
          (only as AiClientUnavailable).reason,
          AiUnavailableReason.notConfigured,
        );
      },
    );

    test('reports unconfigured even when tools are offered', () async {
      const client = NoopAiModelClient();
      final events = await client
          .send(
            const AiRequest(
              messages: [AiMessage.user('hi')],
              tools: [AiToolSpec(name: 'searchSignal', description: 'd')],
            ),
          )
          .toList();
      expect(events.single, isA<AiClientUnavailable>());
    });
  });
}
