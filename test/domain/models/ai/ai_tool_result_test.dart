// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/ai/ai_tool_result.dart';

void main() {
  group('AiCoordinate', () {
    test('toMap omits null fields', () {
      expect(
        const AiCoordinate(time: 10).toMap(),
        {'time': 10},
      );
      expect(
        const AiCoordinate(
          signalRef: 's',
          signalPath: 'top.s',
          time: 10,
        ).toMap(),
        {'signalRef': 's', 'signalPath': 'top.s', 'time': 10},
      );
      expect(const AiCoordinate(signalRef: 's').toMap(), {'signalRef': 's'});
    });

    test('equality keys on all fields', () {
      expect(
        const AiCoordinate(signalRef: 's', time: 1),
        const AiCoordinate(signalRef: 's', time: 1),
      );
      expect(
        const AiCoordinate(signalRef: 's', time: 1),
        isNot(const AiCoordinate(signalRef: 's', time: 2)),
      );
    });
  });

  group('AiToolResult', () {
    test('ok carries data + citations and is not an error', () {
      final r = AiToolResult.ok(
        const {'k': 'v'},
        citations: const [AiCoordinate(time: 5)],
      );
      expect(r.isError, isFalse);
      expect(r.error, isNull);
      expect(r.data, {'k': 'v'});
      expect(r.citations, hasLength(1));
    });

    test('failure carries a message and an empty payload', () {
      final r = AiToolResult.failure('boom');
      expect(r.isError, isTrue);
      expect(r.error, 'boom');
      expect(r.data, isEmpty);
      expect(r.citations, isEmpty);
    });

    test(
      'toMap reflects ok/error and includes citations only when present',
      () {
        final ok = AiToolResult.ok(
          const {'n': 1},
          citations: const [AiCoordinate(time: 5)],
        );
        expect(ok.toMap(), {
          'ok': true,
          'data': {'n': 1},
          'citations': [
            {'time': 5},
          ],
        });

        final fail = AiToolResult.failure('nope');
        expect(fail.toMap(), {
          'ok': false,
          'error': 'nope',
          'data': <String, Object?>{},
        });
      },
    );
  });
}
