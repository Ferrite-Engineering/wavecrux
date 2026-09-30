// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/core/theme/wavecrux_theme.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/inline_cursor_value_overlay.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

// ── fixture ─────────────────────────────────────────────────────────────────
//
// Two signals: 'clk' (short value → "1", never truncated) and 'bus' (128-bit
// value → 32 hex chars, always wider than a collapsed label so it truncates and
// becomes the tap-to-expand subject). The waveform engine's hex formatter is
// bit-length driven, so no Variable bitWidth override is needed.

const _busBits =
    'b1010101010101010101010101010101010101010101010101010101010101010'
    '1010101010101010101010101010101010101010101010101010101010101010';
const _busHex =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; // 128 bits → 32 nibbles of 'a'
const _clkHex = '1';

class _MockSource extends Mock implements WaveformDataSource {}

WaveformDataSource _source() {
  final s = _MockSource();
  when(() => s.startTime).thenReturn(0);
  when(() => s.endTime).thenReturn(1000);
  when(() => s.timescale).thenReturn(null);
  when(() => s.rootScopes).thenReturn([]);
  when(() => s.isSignalLoaded(any())).thenReturn(true);
  when(() => s.changesInRange(any(), any(), any())).thenReturn([]);
  when(() => s.valueAt('clk', any())).thenReturn('b0001');
  when(() => s.valueAt('bus', any())).thenReturn(_busBits);
  return s;
}

class _LoadedSourceNotifier extends WaveformSourceNotifier {
  _LoadedSourceNotifier(this._s);
  final WaveformDataSource _s;
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_s);
}

class _TwoSignalsNotifier extends SignalGroupsNotifier {
  @override
  SignalGroup build() => SignalGroup(
    entries: [
      SignalEntry.signal(signalRef: 'clk', displayName: 'clk'),
      SignalEntry.signal(signalRef: 'bus', displayName: 'bus'),
    ],
  );
}

// fitAll over [0, 1000] at 350 px → ticksPerPixel ≈ 2.857, so timeToPixel(t) is
// roughly t / 2.857.
class _Mapper extends TimeMapperNotifier {
  @override
  TimeMapper build() =>
      TimeMapper.fitAll(startTime: 0, endTime: 1000, viewportWidth: 350);
}

class _CursorMid extends CursorStateNotifier {
  @override
  CursorState build() => const CursorState(primaryCursorTime: 500);
}

class _CursorNearRightEdge extends CursorStateNotifier {
  @override
  CursorState build() => const CursorState(primaryCursorTime: 950);
}

class _NoCursor extends CursorStateNotifier {
  @override
  CursorState build() => const CursorState();
}

const double _surfaceWidth = 350;
const double _surfaceHeight = 200;

List<Override> _baseOverrides() => [
  signalGroupsProvider.overrideWith(_TwoSignalsNotifier.new),
  waveformSourceProvider.overrideWith(() => _LoadedSourceNotifier(_source())),
  timeMapperProvider.overrideWith(_Mapper.new),
  deviceClassProvider.overrideWithValue(DeviceClass.phone),
];

Widget _overlayApp({
  Locale? locale,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [..._baseOverrides(), ...overrides],
  child: MaterialApp(
    // iOS host → touch metrics (minLaneHeight = 44, monoText = 13).
    theme: WavecruxTheme.dark.copyWith(platform: TargetPlatform.iOS),
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    // Fills the Scaffold body so the overlay's LayoutBuilder width matches
    // the surface (and the timeMapper's viewportWidth). Tests set the
    // surface size to [_surfaceWidth] × [_surfaceHeight] via _pumpOverlay.
    home: const Scaffold(body: InlineCursorValueOverlay(scrollOffset: 0)),
  ),
);

/// Pumps [_overlayApp] at a surface whose width equals the timeMapper's
/// viewport width (350), so cursor-x math and label placement are consistent.
Future<void> _pumpOverlay(
  WidgetTester tester, {
  Locale? locale,
  List<Override> overrides = const [],
}) async {
  await tester.binding.setSurfaceSize(
    const Size(_surfaceWidth, _surfaceHeight),
  );
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_overlayApp(locale: locale, overrides: overrides));
  await tester.pump();
}

void main() {
  group('InlineCursorValueOverlay', () {
    testWidgets('renders one value label per visible signal lane', (
      tester,
    ) async {
      await _pumpOverlay(
        tester,
        overrides: [
          cursorStateProvider.overrideWith(_CursorMid.new),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(find.text(_clkHex), findsOneWidget);
      expect(find.text(_busHex), findsOneWidget);
    });

    testWidgets('labels render to the right of the cursor by default', (
      tester,
    ) async {
      await _pumpOverlay(
        tester,
        overrides: [
          cursorStateProvider.overrideWith(_CursorMid.new),
        ],
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(InlineCursorValueOverlay)),
      );
      final cursorX = container.read(timeMapperProvider).timeToPixel(500);

      final clkLeft = tester.getTopLeft(find.text(_clkHex)).dx;
      expect(
        clkLeft,
        greaterThan(cursorX),
        reason: 'default placement is right of the cursor x',
      );
    });

    testWidgets('labels flip to the left of the cursor near the right edge', (
      tester,
    ) async {
      await _pumpOverlay(
        tester,
        overrides: [
          cursorStateProvider.overrideWith(_CursorNearRightEdge.new),
        ],
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(InlineCursorValueOverlay)),
      );
      final cursorX = container
          .read(timeMapperProvider)
          .timeToPixel(950)
          .clamp(0.0, _surfaceWidth);

      final clkRight = tester.getTopRight(find.text(_clkHex)).dx;
      expect(
        clkRight,
        lessThanOrEqualTo(cursorX),
        reason: 'near the right edge the label flips left of the cursor',
      );
    });

    testWidgets('each label is vertically pinned to its own lane band', (
      tester,
    ) async {
      await _pumpOverlay(
        tester,
        overrides: [
          cursorStateProvider.overrideWith(_CursorMid.new),
        ],
      );

      // Touch metrics clamp both lanes to 44 dp: lane 0 = [0, 44], lane 1 =
      // [44, 88]. Each label's vertical centre must sit inside its own band.
      final clkCentreY = tester.getRect(find.text(_clkHex)).center.dy;
      final busCentreY = tester.getRect(find.text(_busHex)).center.dy;
      expect(clkCentreY, inInclusiveRange(0, 44));
      expect(busCentreY, inInclusiveRange(44, 88));
    });

    testWidgets('labels move horizontally as the cursor moves (live scrub)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(
        const Size(_surfaceWidth, _surfaceHeight),
      );
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer(overrides: _baseOverrides())
        ..listen(timeMapperProvider, (_, _) {})
        ..listen(cursorStateProvider, (_, _) {})
        ..listen(waveformSourceProvider, (_, _) {});
      addTearDown(container.dispose);

      container.read(cursorStateProvider.notifier).placePrimary(300);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: WavecruxTheme.dark.copyWith(platform: TargetPlatform.iOS),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: const Scaffold(
              body: InlineCursorValueOverlay(scrollOffset: 0),
            ),
          ),
        ),
      );
      await tester.pump();

      final xAt300 = tester.getTopLeft(find.text(_clkHex)).dx;

      container.read(cursorStateProvider.notifier).placePrimary(500);
      await tester.pump();
      final xAt500 = tester.getTopLeft(find.text(_clkHex)).dx;

      expect(
        xAt500,
        greaterThan(xAt300),
        reason: 'the label tracks the cursor x as it advances',
      );
    });

    testWidgets('no labels render when there is no primary cursor', (
      tester,
    ) async {
      await _pumpOverlay(
        tester,
        overrides: [
          cursorStateProvider.overrideWith(_NoCursor.new),
        ],
      );

      expect(find.text(_clkHex), findsNothing);
      expect(find.text(_busHex), findsNothing);
    });

    testWidgets(
      'tapping a truncated long value expands it and collapses again',
      (tester) async {
        await _pumpOverlay(
          tester,
          overrides: [
            cursorStateProvider.overrideWith(_CursorMid.new),
          ],
        );

        // Collapsed: single line with an ellipsis.
        expect(tester.widget<Text>(find.text(_busHex)).maxLines, 1);

        await tester.tap(find.text(_busHex));
        await tester.pump();
        // Expanded: full value, no single-line clamp.
        expect(tester.widget<Text>(find.text(_busHex)).maxLines, isNull);

        await tester.tap(find.text(_busHex));
        await tester.pump();
        // Collapsed again.
        expect(tester.widget<Text>(find.text(_busHex)).maxLines, 1);
      },
    );

    testWidgets('truncated label is a translucent, tap-only GestureDetector '
        '(gesture-bubbling rule)', (tester) async {
      await _pumpOverlay(
        tester,
        overrides: [
          cursorStateProvider.overrideWith(_CursorMid.new),
        ],
      );

      // The non-truncated label is non-interactive: it is wrapped in an
      // IgnorePointer (so gestures pass through) and is NOT a GestureDetector.
      expect(
        find.ancestor(
          of: find.text(_clkHex),
          matching: find.descendant(
            of: find.byType(InlineCursorValueOverlay),
            matching: find.byType(IgnorePointer),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.text(_clkHex),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );

      // The interactive label never claims long-press (so the canvas
      // long-press context menu still bubbles) and is translucent (so scrub
      // drags pass through to WaveformGestureHandler).
      final gesture = tester.widget<GestureDetector>(
        find.ancestor(
          of: find.text(_busHex),
          matching: find.byType(GestureDetector),
        ),
      );
      expect(gesture.onLongPress, isNull);
      expect(gesture.behavior, HitTestBehavior.translucent);
    });

    testWidgets('interactive label hit surface is at least 44x44 dp', (
      tester,
    ) async {
      await _pumpOverlay(
        tester,
        overrides: [
          cursorStateProvider.overrideWith(_CursorMid.new),
        ],
      );

      final size = tester.getSize(
        find.ancestor(
          of: find.text(_busHex),
          matching: find.byType(GestureDetector),
        ),
      );
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets(
      'exposes a single combined cursor readout, not one node per lane',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pumpOverlay(
          tester,
          overrides: [
            cursorStateProvider.overrideWith(_CursorMid.new),
          ],
        );

        // Exactly one semantics node carries BOTH signal values together — a
        // single combined readout rather than a per-lane node.
        expect(
          find.bySemanticsLabel(RegExp('clk $_clkHex, bus $_busHex')),
          findsOneWidget,
        );
        // The visual pills are excluded from the semantics tree (so they cannot
        // each become their own node).
        expect(
          find.descendant(
            of: find.byType(InlineCursorValueOverlay),
            matching: find.byType(ExcludeSemantics),
          ),
          findsOneWidget,
        );

        handle.dispose();
      },
    );

    testWidgets('locale sweep — no exceptions in en/zh_CN/ja/ko', (
      tester,
    ) async {
      const locales = [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('ja'),
        Locale('ko'),
      ];
      for (final locale in locales) {
        await _pumpOverlay(
          tester,
          locale: locale,
          overrides: [cursorStateProvider.overrideWith(_CursorMid.new)],
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'InlineCursorValueOverlay threw under locale $locale',
        );
      }
    });
  });
}
