// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/enums/waveform_format.dart';
import 'package:wavecrux/services/waveform/legacy_format_detector.dart';

void main() {
  group('LegacyFormatDetector.detect', () {
    test('recognises the LXT classic 0x0138 magic word', () {
      final bytes = Uint8List.fromList([0x01, 0x38, 0xff, 0xee]);
      expect(LegacyFormatDetector.detect(bytes), WaveformFormat.lxt);
    });

    test('recognises the LXT2 0x1380 magic word', () {
      final bytes = Uint8List.fromList([0x13, 0x80, 0xff, 0xee]);
      expect(LegacyFormatDetector.detect(bytes), WaveformFormat.lxt2);
    });

    test('returns unknown for short buffers', () {
      expect(LegacyFormatDetector.detect(const []), WaveformFormat.unknown);
      expect(LegacyFormatDetector.detect(const [0x01]), WaveformFormat.unknown);
    });

    test('returns unknown for VCD / FST / GHW signatures', () {
      // VCD starts with `$` (0x24) or whitespace; pick `$d` for `$date`.
      expect(
        LegacyFormatDetector.detect(const [0x24, 0x64]),
        WaveformFormat.unknown,
      );
      // FST headers begin with a section tag byte; common values are
      // 0x00 / 0x01 / 0x06 / 0x07 — none of which match the LXT magics.
      expect(
        LegacyFormatDetector.detect(const [0x00, 0x01]),
        WaveformFormat.unknown,
      );
      // GHW starts with the ASCII string "GHDLwave\n" → 'G' = 0x47.
      expect(
        LegacyFormatDetector.detect(const [0x47, 0x48]),
        WaveformFormat.unknown,
      );
    });
  });

  group('LegacyFormatDetector.detectFile', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('lxt-detect-test-');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('identifies LXT2 from disk', () async {
      final file = File(p.join(tempDir.path, 'sample.lxt2'))
        ..writeAsBytesSync([0x13, 0x80, 0x00, 0x00, 0x00, 0x01]);
      final fmt = await LegacyFormatDetector.detectFile(file.path);
      expect(fmt, WaveformFormat.lxt2);
    });

    test('identifies LXT classic from disk', () async {
      final file = File(p.join(tempDir.path, 'sample.lxt'))
        ..writeAsBytesSync([0x01, 0x38, 0x00, 0x00, 0x00, 0x01]);
      final fmt = await LegacyFormatDetector.detectFile(file.path);
      expect(fmt, WaveformFormat.lxt);
    });

    test('returns unknown for a non-legacy file', () async {
      final file = File(p.join(tempDir.path, 'sample.vcd'))
        ..writeAsBytesSync([0x24, 0x64, 0x61, 0x74, 0x65]);
      final fmt = await LegacyFormatDetector.detectFile(file.path);
      expect(fmt, WaveformFormat.unknown);
    });

    test('uses the magic bytes and not the extension', () async {
      // A `.lxt2` file whose content is actually VCD must NOT be reported
      // as LXT2 — routing is on content, not extension,
      // because users carry archives whose extensions were stripped.
      final file = File(p.join(tempDir.path, 'mislabelled.lxt2'))
        ..writeAsBytesSync([0x24, 0x64, 0x61, 0x74, 0x65]);
      final fmt = await LegacyFormatDetector.detectFile(file.path);
      expect(fmt, WaveformFormat.unknown);
    });
  });
}
