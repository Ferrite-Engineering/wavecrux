// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/ai_model_client.dart';

void main() {
  group('AiMessage', () {
    test('user/system convenience constructors set the role', () {
      expect(const AiMessage.user('hi').role, AiRole.user);
      expect(const AiMessage.system('be terse').role, AiRole.system);
      expect(const AiMessage.user('hi').content, 'hi');
    });

    test('equality ignores nothing material', () {
      const a = AiMessage.user('hi');
      const b = AiMessage.user('hi');
      const c = AiMessage.user('bye');
      expect(a, b);
      expect(a, isNot(c));
    });

    test('tool message carries a toolCallId', () {
      const m = AiMessage(
        role: AiRole.tool,
        content: '{}',
        toolCallId: 'call_1',
      );
      expect(m.toolCallId, 'call_1');
    });
  });

  group('AiToolSpec / AiToolCall', () {
    test('spec equality keys on name + description', () {
      const a = AiToolSpec(name: 'searchSignal', description: 'd');
      const b = AiToolSpec(name: 'searchSignal', description: 'd');
      const c = AiToolSpec(name: 'searchSignal', description: 'other');
      expect(a, b);
      expect(a, isNot(c));
    });

    test('call carries decoded arguments', () {
      const call = AiToolCall(
        id: 'c1',
        name: 'jumpCursor',
        arguments: {'time': 10},
      );
      expect(call.arguments['time'], 10);
      expect(call, const AiToolCall(id: 'c1', name: 'jumpCursor'));
    });
  });

  group('AiStreamEvent', () {
    test('variants are equatable', () {
      expect(const AiTextDelta('a'), const AiTextDelta('a'));
      expect(const AiTextDelta('a'), isNot(const AiTextDelta('b')));
      expect(
        const AiClientUnavailable(AiUnavailableReason.notConfigured),
        const AiClientUnavailable(AiUnavailableReason.notConfigured),
      );
      expect(
        const AiClientUnavailable(AiUnavailableReason.notConfigured),
        isNot(const AiClientUnavailable(AiUnavailableReason.networkError)),
      );
    });

    test('sealed hierarchy supports exhaustive switch', () {
      String label(AiStreamEvent e) => switch (e) {
        AiTextDelta() => 'text',
        AiToolCallRequested() => 'tool',
        AiResponseCompleted() => 'done',
        AiClientUnavailable() => 'unavailable',
      };
      expect(label(const AiTextDelta('x')), 'text');
      expect(
        label(const AiToolCallRequested(AiToolCall(id: 'i', name: 'n'))),
        'tool',
      );
      expect(label(const AiResponseCompleted()), 'done');
      expect(
        label(const AiClientUnavailable(AiUnavailableReason.cancelled)),
        'unavailable',
      );
    });
  });

  test('AiRequest defaults to an empty tool list', () {
    const req = AiRequest(messages: [AiMessage.user('hi')]);
    expect(req.tools, isEmpty);
    expect(req.messages, hasLength(1));
  });
}
