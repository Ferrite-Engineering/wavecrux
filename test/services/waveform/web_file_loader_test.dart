// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/waveform/web_file_loader.dart';

void main() {
  group('WebFileLoader.isLargeFile', () {
    test('returns false for files below threshold', () {
      expect(WebFileLoader.isLargeFile(0), isFalse);
      expect(WebFileLoader.isLargeFile(1024), isFalse);
      expect(WebFileLoader.isLargeFile(10 * 1024 * 1024), isFalse); // 10 MB
    });

    test('returns false exactly at threshold', () {
      expect(
        WebFileLoader.isLargeFile(WebFileLoader.fileSizeWarningThresholdBytes),
        isFalse,
      );
    });

    test('returns true for files above threshold', () {
      expect(
        WebFileLoader.isLargeFile(
          WebFileLoader.fileSizeWarningThresholdBytes + 1,
        ),
        isTrue,
      );
      expect(
        WebFileLoader.isLargeFile(200 * 1024 * 1024), // 200 MB
        isTrue,
      );
    });

    test('threshold is 100 MB (web WASM)', () {
      expect(
        WebFileLoader.fileSizeWarningThresholdBytes,
        equals(100 * 1024 * 1024),
      );
    });
  });

  group('WebPickResult', () {
    test('holds bytes and name', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final result = WebPickResult(bytes: Uint8List(0), name: 'dump.vcd');
      expect(result.name, equals('dump.vcd'));
      expect(result.bytes, isEmpty);

      final result2 = WebPickResult(bytes: bytes, name: 'test.vcd');
      expect(result2.bytes, equals([1, 2, 3]));
      expect(result2.name, equals('test.vcd'));
    });
  });
}
