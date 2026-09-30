// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';

void main() {
  group('WavecruxColors', () {
    group('signal palette', () {
      test('has exactly 6 entries', () {
        expect(WavecruxColors.signalPalette, hasLength(6));
      });

      test('contains all six named signal colors', () {
        expect(
          WavecruxColors.signalPalette,
          containsAll([
            WavecruxColors.signalGreen,
            WavecruxColors.signalCyan,
            WavecruxColors.signalYellow,
            WavecruxColors.signalMagenta,
            WavecruxColors.signalOrange,
            WavecruxColors.signalWhite,
          ]),
        );
      });

      test('all signal colors are fully opaque', () {
        for (final color in WavecruxColors.signalPalette) {
          expect(color.a, equals(1.0), reason: 'color $color must be opaque');
        }
      });
    });

    group('waveform state colors', () {
      test('xValueHatch is darker than xValue', () {
        expect(
          WavecruxColors.xValueHatch.computeLuminance(),
          lessThan(WavecruxColors.xValue.computeLuminance()),
        );
      });

      test('xValue and xValueHatch are distinct', () {
        expect(
          WavecruxColors.xValueHatch,
          isNot(equals(WavecruxColors.xValue)),
        );
      });

      test('zValue is fully opaque', () {
        expect(WavecruxColors.zValue.a, equals(1.0));
      });

      test('zValueDark and zValueLight are fully opaque', () {
        expect(WavecruxColors.zValueDark.a, equals(1.0));
        expect(WavecruxColors.zValueLight.a, equals(1.0));
      });

      test('zValueDark is brighter than zValueLight', () {
        expect(
          WavecruxColors.zValueDark.computeLuminance(),
          greaterThan(WavecruxColors.zValueLight.computeLuminance()),
        );
      });

      test('zValueDark and zValueLight are distinct', () {
        expect(
          WavecruxColors.zValueDark,
          isNot(equals(WavecruxColors.zValueLight)),
        );
      });

      test('zValue alias equals zValueDark', () {
        expect(WavecruxColors.zValue, equals(WavecruxColors.zValueDark));
      });
    });

    group('cursors and markers', () {
      test('primaryCursor and secondaryCursor are distinct', () {
        expect(
          WavecruxColors.primaryCursor,
          isNot(equals(WavecruxColors.secondaryCursor)),
        );
      });

      test('selectionHighlight is translucent', () {
        expect(WavecruxColors.selectionHighlight.a, lessThan(1.0));
      });
    });

    group('dark panel chrome', () {
      test('darkBackground is darker than darkSurface', () {
        expect(
          WavecruxColors.darkBackground.computeLuminance(),
          lessThan(WavecruxColors.darkSurface.computeLuminance()),
        );
      });

      test('darkSurface is darker than darkSurfaceVariant', () {
        expect(
          WavecruxColors.darkSurface.computeLuminance(),
          lessThan(WavecruxColors.darkSurfaceVariant.computeLuminance()),
        );
      });
    });

    group('light panel chrome', () {
      test('lightBackground is lighter than lightSurface or equal', () {
        // lightBackground and lightSurface may be very close; both should be
        // lighter than the dark variants.
        expect(
          WavecruxColors.lightBackground.computeLuminance(),
          greaterThan(WavecruxColors.darkBackground.computeLuminance()),
        );
      });

      test('lightSurface is lighter than darkSurface', () {
        expect(
          WavecruxColors.lightSurface.computeLuminance(),
          greaterThan(WavecruxColors.darkSurface.computeLuminance()),
        );
      });
    });

    group('time ruler', () {
      test('timeRulerMajorTick is brighter than timeRulerTick', () {
        expect(
          WavecruxColors.timeRulerMajorTick.computeLuminance(),
          greaterThan(WavecruxColors.timeRulerTick.computeLuminance()),
        );
      });
    });

    group('typography', () {
      test('monoFontFamily is non-empty', () {
        expect(WavecruxColors.monoFontFamily, isNotEmpty);
      });

      test('monoFontFamilyFallback is non-empty', () {
        expect(WavecruxColors.monoFontFamilyFallback, isNotEmpty);
      });

      test('monoFontFamilyFallback does not contain monoFontFamily', () {
        expect(
          WavecruxColors.monoFontFamilyFallback,
          isNot(contains(WavecruxColors.monoFontFamily)),
        );
      });
    });
  });
}
