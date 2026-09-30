// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Tests for the WebDropTarget stub (non-web platforms).
//
// On non-web, WebDropTarget is a no-op: enable/disable do nothing and
// the files stream never emits. These tests verify that behaviour
// without requiring a browser environment.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/platform/web_drop_target.dart';

void main() {
  group('WebDropTarget (stub — non-web)', () {
    late WebDropTarget target;

    setUp(() => target = WebDropTarget());
    tearDown(() => target.dispose());

    test('enable and disable are no-ops', () {
      expect(() => target.enable(), returnsNormally);
      expect(() => target.disable(), returnsNormally);
    });

    test('files stream never emits on non-web', () async {
      final emitted = <WebDropFile>[];
      final sub = target.files.listen(emitted.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();
      expect(emitted, isEmpty);
    });

    test('dispose closes the stream', () async {
      final events = <Object>[];
      final sub = target.files.listen(
        events.add,
        onDone: () => events.add('done'),
      );
      target.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();
      expect(events, contains('done'));
    });

    test('multiple enable/disable calls do not throw', () {
      target
        ..enable()
        ..enable()
        ..disable()
        ..disable();
    });
  });

  group('WebDropFile', () {
    test('holds bytes and name', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final file = WebDropFile(bytes: bytes, name: 'dump.vcd');
      expect(file.bytes, equals([1, 2, 3]));
      expect(file.name, equals('dump.vcd'));
    });
  });
}
