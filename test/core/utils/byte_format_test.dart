// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/utils/byte_format.dart';

void main() {
  group('formatBytes', () {
    group('bytes range (< 1 KB)', () {
      test('zero bytes', () => expect(formatBytes(0), '0 B'));
      test('1 byte', () => expect(formatBytes(1), '1 B'));
      test('1023 bytes', () => expect(formatBytes(1023), '1023 B'));
    });

    group('kilobytes range (1 KB – 1 MB)', () {
      test('exactly 1 KB', () => expect(formatBytes(1024), '1.0 KB'));
      test('1.5 KB', () => expect(formatBytes(1536), '1.5 KB'));
      test('1023 KB', () => expect(formatBytes(1023 * 1024), '1023.0 KB'));
    });

    group('megabytes range (1 MB – 1 GB)', () {
      test('exactly 1 MB', () => expect(formatBytes(1024 * 1024), '1.0 MB'));
      test('42.3 MB', () {
        final bytes = (42.3 * 1024 * 1024).round();
        expect(formatBytes(bytes), '42.3 MB');
      });
      test('512 MB', () {
        expect(formatBytes(512 * 1024 * 1024), '512.0 MB');
      });
      test('1023 MB', () {
        expect(formatBytes(1023 * 1024 * 1024), '1023.0 MB');
      });
    });

    group('gigabytes range (>= 1 GB)', () {
      test('exactly 1 GB', () {
        expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
      });
      test('1.5 GB', () {
        expect(formatBytes((1.5 * 1024 * 1024 * 1024).round()), '1.5 GB');
      });
      test('large value', () {
        expect(formatBytes(10 * 1024 * 1024 * 1024), '10.0 GB');
      });
    });

    test('boundary: 1024 is 1.0 KB not bytes', () {
      expect(formatBytes(1024), contains('KB'));
      expect(formatBytes(1023), contains('B'));
    });
  });
}
