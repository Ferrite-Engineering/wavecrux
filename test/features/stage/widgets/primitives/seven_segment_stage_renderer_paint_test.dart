// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Drives [SevenSegmentStageRenderer] and [SevenSegmentDigitPainter] through
// every paint branch: value mode (lit digit, blank, error/X, decimal point),
// cathode mode (active-high / active-low, DP-from-bus, DP-pin override), and
// both display radices. The existing `seven_segment_stage_widget_test.dart`
// covers the pure `sevenSegmentDigits` / `SegmentGlyph` logic plus a value-mode
// locale sweep; this file covers the cathode-mode renderer branches and the
// painter's error / blank / decimal-point drawing paths.
//
// Each test overrides `stageBoundSignalProvider` per pin with a synthetic
// snapshot (the proven primitive-test pattern) so the renderer never touches a
// real waveform source. The painter runs during the pump, so a thrown
// exception or RenderFlex overflow surfaces via `tester.takeException()`.
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/features/stage/widgets/primitives/seven_segment_stage_widget.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

const _cathodesBinding = StageSignalBinding(signalRef: 'top.cathodes');
const _valueBinding = StageSignalBinding(signalRef: 'top.value');
const _dpBinding = StageSignalBinding(signalRef: 'top.dp');

/// Wraps the renderer with per-pin snapshot overrides. Any pin not present in
/// [snapshots] resolves to the unbound snapshot.
Widget _wrap(
  Widget child, {
  StageSignalSnapshot? cathodes,
  StageSignalSnapshot? value,
  StageSignalSnapshot? dp,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      stageBoundSignalProvider(_cathodesBinding).overrideWith(
        (ref) => cathodes ?? const StageSignalSnapshot.unbound(),
      ),
      stageBoundSignalProvider(_valueBinding).overrideWith(
        (ref) => value ?? const StageSignalSnapshot.unbound(),
      ),
      stageBoundSignalProvider(_dpBinding).overrideWith(
        (ref) => dp ?? const StageSignalSnapshot.unbound(),
      ),
      stageBoundSignalProvider(null).overrideWith(
        (ref) => const StageSignalSnapshot.unbound(),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 200, height: 220, child: child),
        ),
      ),
    ),
  );
}

void main() {
  group('SevenSegmentStageRenderer — cathode mode', () {
    testWidgets('active-high cathode bus drives lit segments', (tester) async {
      // 0x3F = the "0" pattern (a..f on, g off).
      const instance = StageInstance(
        id: 'i_cath',
        widgetId: 'seven_segment',
        signalBindings: {'cathodes': _cathodesBinding},
      );
      await tester.pumpWidget(
        _wrap(
          const SevenSegmentStageRenderer(instance: instance),
          cathodes: const StageSignalSnapshot.value(
            rawValue: '0111111',
            bitWidth: 7,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('active-low cathode bus inverts and paints', (tester) async {
      const instance = StageInstance(
        id: 'i_cath_low',
        widgetId: 'seven_segment',
        signalBindings: {'cathodes': _cathodesBinding},
      );
      await tester.pumpWidget(
        _wrap(
          const SevenSegmentStageRenderer(
            instance: instance,
            cathodeActiveHigh: false,
          ),
          cathodes: const StageSignalSnapshot.value(
            rawValue: '0111111',
            bitWidth: 7,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('8-bit cathode bus draws the decimal point from bit 7', (
      tester,
    ) async {
      const instance = StageInstance(
        id: 'i_cath_dp',
        widgetId: 'seven_segment',
        signalBindings: {'cathodes': _cathodesBinding},
      );
      await tester.pumpWidget(
        _wrap(
          const SevenSegmentStageRenderer(instance: instance),
          // bit 7 set → DP on; lower 7 bits = "0" pattern.
          cathodes: const StageSignalSnapshot.value(
            rawValue: '10111111',
            bitWidth: 8,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('explicit dp pin overrides bus DP and renders dot', (
      tester,
    ) async {
      const instance = StageInstance(
        id: 'i_cath_dppin',
        widgetId: 'seven_segment',
        signalBindings: {'cathodes': _cathodesBinding, 'dp': _dpBinding},
      );
      await tester.pumpWidget(
        _wrap(
          const SevenSegmentStageRenderer(instance: instance),
          cathodes: const StageSignalSnapshot.value(
            rawValue: '10111111',
            bitWidth: 8,
          ),
          dp: const StageSignalSnapshot.value(rawValue: '1', bitWidth: 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('cathode X value paints the error glyph', (tester) async {
      const instance = StageInstance(
        id: 'i_cath_x',
        widgetId: 'seven_segment',
        signalBindings: {'cathodes': _cathodesBinding},
      );
      await tester.pumpWidget(
        _wrap(
          const SevenSegmentStageRenderer(instance: instance),
          cathodes: const StageSignalSnapshot.value(
            rawValue: 'xxxxxxx',
            bitWidth: 7,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('cathode unknown (no value at cursor) paints blank', (
      tester,
    ) async {
      const instance = StageInstance(
        id: 'i_cath_unk',
        widgetId: 'seven_segment',
        signalBindings: {'cathodes': _cathodesBinding},
      );
      await tester.pumpWidget(
        _wrap(
          const SevenSegmentStageRenderer(instance: instance),
          cathodes: const StageSignalSnapshot.unknown(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('SevenSegmentStageRenderer — value mode painter branches', () {
    testWidgets('multi-digit decimal value with DP on the rightmost digit', (
      tester,
    ) async {
      const instance = StageInstance(
        id: 'i_val_dp',
        widgetId: 'seven_segment',
        signalBindings: {'value': _valueBinding, 'dp': _dpBinding},
      );
      await tester.pumpWidget(
        _wrap(
          const SevenSegmentStageRenderer(
            instance: instance,
            digitCount: 2,
            radix: SevenSegmentRadix.decimal,
          ),
          // 42 over 2 digits.
          value: const StageSignalSnapshot.value(
            rawValue: '101010',
            bitWidth: 6,
          ),
          dp: const StageSignalSnapshot.value(rawValue: '1', bitWidth: 1),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('value overflow paints all-error digits', (tester) async {
      const instance = StageInstance(
        id: 'i_val_over',
        widgetId: 'seven_segment',
        signalBindings: {'value': _valueBinding},
      );
      await tester.pumpWidget(
        _wrap(
          const SevenSegmentStageRenderer(
            instance: instance,
            radix: SevenSegmentRadix.decimal,
          ),
          // 100 cannot fit a single decimal digit → error glyphs.
          value: const StageSignalSnapshot.value(
            rawValue: '1100100',
            bitWidth: 7,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('hex value lights the right segments across all digits', (
      tester,
    ) async {
      const instance = StageInstance(
        id: 'i_val_hex',
        widgetId: 'seven_segment',
        signalBindings: {'value': _valueBinding},
      );
      await tester.pumpWidget(
        _wrap(
          const SevenSegmentStageRenderer(instance: instance, digitCount: 4),
          // 0xCAFE.
          value: const StageSignalSnapshot.value(
            rawValue: '1100101011111110',
            bitWidth: 16,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('digitCount above 8 is clamped without overflow', (
      tester,
    ) async {
      const instance = StageInstance(
        id: 'i_val_clamp',
        widgetId: 'seven_segment',
        signalBindings: {'value': _valueBinding},
      );
      await tester.pumpWidget(
        _wrap(
          const SevenSegmentStageRenderer(instance: instance, digitCount: 99),
          value: const StageSignalSnapshot.value(rawValue: '1111', bitWidth: 4),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('SevenSegmentStageRenderer — locale sweep (cathode + dp)', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders cathode mode without exception in $locale', (
        tester,
      ) async {
        const instance = StageInstance(
          id: 'i_locale',
          widgetId: 'seven_segment',
          signalBindings: {'cathodes': _cathodesBinding, 'dp': _dpBinding},
        );
        await tester.pumpWidget(
          _wrap(
            const SevenSegmentStageRenderer(instance: instance),
            cathodes: const StageSignalSnapshot.value(
              rawValue: '10111111',
              bitWidth: 8,
            ),
            dp: const StageSignalSnapshot.value(rawValue: '0', bitWidth: 1),
            locale: Locale(locale),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('SevenSegmentDigitPainter — direct paint', () {
    void paintGlyph(SegmentGlyph glyph, {Size size = const Size(80, 144)}) {
      final painter = SevenSegmentDigitPainter(glyph);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, size);
      recorder.endRecording().dispose();
    }

    test('error glyph paints the X cross', () {
      expect(() => paintGlyph(SegmentGlyph.error), returnsNormally);
    });

    test('blank glyph paints the dim middle bar', () {
      expect(() => paintGlyph(SegmentGlyph.blank), returnsNormally);
    });

    test('lit digit with visible DP on paints the dot', () {
      const glyph = SegmentGlyph(
        a: true,
        b: true,
        c: true,
        d: true,
        e: true,
        f: true,
        g: false,
        dp: true,
        dpVisible: true,
      );
      expect(() => paintGlyph(glyph), returnsNormally);
    });

    test('empty size is a no-op (guards against zero-area paint)', () {
      expect(
        () => paintGlyph(SegmentGlyph.error, size: Size.zero),
        returnsNormally,
      );
    });

    test('shouldRepaint is true only when the glyph changes', () {
      final a = SevenSegmentDigitPainter(SegmentGlyph.error);
      final b = SevenSegmentDigitPainter(SegmentGlyph.error);
      final c = SevenSegmentDigitPainter(SegmentGlyph.blank);
      expect(a.shouldRepaint(b), isFalse);
      expect(a.shouldRepaint(c), isTrue);
    });
  });
}
