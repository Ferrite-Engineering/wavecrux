// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/waveform_format.dart';

void main() {
  group('WaveformFormat.fromWellenLabel', () {
    test('round-trips the labels the wellen FFI bridge emits', () {
      expect(WaveformFormat.fromWellenLabel('VCD'), WaveformFormat.vcd);
      expect(WaveformFormat.fromWellenLabel('FST'), WaveformFormat.fst);
      expect(WaveformFormat.fromWellenLabel('GHW'), WaveformFormat.ghw);
    });

    test('is case-insensitive', () {
      expect(WaveformFormat.fromWellenLabel('vcd'), WaveformFormat.vcd);
      expect(WaveformFormat.fromWellenLabel('Fst'), WaveformFormat.fst);
    });

    test('also recognises the legacy LXT / LXT2 labels', () {
      expect(WaveformFormat.fromWellenLabel('LXT'), WaveformFormat.lxt);
      expect(WaveformFormat.fromWellenLabel('LXT2'), WaveformFormat.lxt2);
    });

    test('collapses unknown labels to WaveformFormat.unknown', () {
      expect(WaveformFormat.fromWellenLabel(''), WaveformFormat.unknown);
      expect(WaveformFormat.fromWellenLabel('Unknown'), WaveformFormat.unknown);
      expect(WaveformFormat.fromWellenLabel('FSDB'), WaveformFormat.unknown);
    });
  });

  group('WaveformFormat.isLegacy', () {
    test('is true only for the LXT / LXT2 GTKWave formats', () {
      expect(WaveformFormat.lxt.isLegacy, isTrue);
      expect(WaveformFormat.lxt2.isLegacy, isTrue);
      expect(WaveformFormat.vcd.isLegacy, isFalse);
      expect(WaveformFormat.fst.isLegacy, isFalse);
      expect(WaveformFormat.ghw.isLegacy, isFalse);
      expect(WaveformFormat.unknown.isLegacy, isFalse);
    });
  });
}
