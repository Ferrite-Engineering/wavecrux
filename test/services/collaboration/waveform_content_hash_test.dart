// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/collaboration/waveform_content_hash.dart';

void main() {
  group('WaveformContentHash.ofBytes', () {
    test('is deterministic for identical bytes', () {
      final a = WaveformContentHash.ofBytes(Uint8List.fromList([1, 2, 3, 4]));
      final b = WaveformContentHash.ofBytes(Uint8List.fromList([1, 2, 3, 4]));
      expect(a, b);
    });

    test('differs for different content', () {
      final a = WaveformContentHash.ofBytes(Uint8List.fromList([1, 2, 3]));
      final b = WaveformContentHash.ofBytes(Uint8List.fromList([1, 2, 4]));
      expect(a, isNot(b));
    });

    test('is lowercase hex with length-prefixed shape', () {
      final hash = WaveformContentHash.ofBytes(Uint8List.fromList([1, 2, 3]));
      // `<lengthHex>-<h1Hex>-<h2Hex>` — all lowercase hex.
      expect(RegExp(r'^[0-9a-f]+-[0-9a-f]+-[0-9a-f]+$').hasMatch(hash), isTrue);
      expect(hash, startsWith('3-')); // 3 bytes → length 0x3
    });

    test('folds in the byte length so equal-prefix lengths differ', () {
      final a = WaveformContentHash.ofBytes(Uint8List.fromList([0]));
      final b = WaveformContentHash.ofBytes(Uint8List.fromList([0, 0]));
      expect(a, isNot(b));
    });
  });

  group('WaveformContentHash.ofFile', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('wch_test_');
    });
    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('hashes file bytes identically to ofBytes', () async {
      final bytes = Uint8List.fromList(List.generate(5000, (i) => i % 256));
      final file = File('${tmp.path}/wave.vcd')..writeAsBytesSync(bytes);

      final fileHash = await WaveformContentHash.ofFile(file.path);
      expect(fileHash, WaveformContentHash.ofBytes(bytes));
    });

    test('two files with identical content hash equal', () async {
      final bytes = Uint8List.fromList([9, 8, 7, 6, 5]);
      final a = File('${tmp.path}/a.vcd')..writeAsBytesSync(bytes);
      final b = File('${tmp.path}/b.vcd')..writeAsBytesSync(bytes);
      expect(
        await WaveformContentHash.ofFile(a.path),
        await WaveformContentHash.ofFile(b.path),
      );
    });

    test('files with different content hash differently', () async {
      final a = File('${tmp.path}/a.vcd')..writeAsBytesSync([1, 2, 3]);
      final b = File('${tmp.path}/b.vcd')..writeAsBytesSync([1, 2, 4]);
      expect(
        await WaveformContentHash.ofFile(a.path),
        isNot(await WaveformContentHash.ofFile(b.path)),
      );
    });

    test('returns null for a missing file rather than throwing', () async {
      expect(
        await WaveformContentHash.ofFile('${tmp.path}/does_not_exist.vcd'),
        isNull,
      );
    });

    test('hashes a multi-chunk (>1 MiB) file correctly', () async {
      // Exercises the streaming chunked-conversion path.
      final bytes = Uint8List.fromList(
        List.generate(3 * 1024 * 1024, (i) => i % 251),
      );
      final file = File('${tmp.path}/big.fst')..writeAsBytesSync(bytes);
      expect(
        await WaveformContentHash.ofFile(file.path),
        WaveformContentHash.ofBytes(bytes),
      );
    });
  });
}
