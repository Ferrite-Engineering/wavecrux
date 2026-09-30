// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';

void main() {
  // ── CursorStateNotifier ───────────────────────────────────────────────────

  group('CursorStateNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state has both cursors null', () {
      final state = container.read(cursorStateProvider);
      expect(state, const CursorState());
    });

    test('placePrimary sets the primary cursor', () {
      container.read(cursorStateProvider.notifier).placePrimary(1000);
      expect(container.read(cursorStateProvider).primaryCursorTime, 1000);
    });

    test('placePrimary does not affect secondary cursor', () {
      container.read(cursorStateProvider.notifier)
        ..placeSecondary(500)
        ..placePrimary(1000);
      expect(container.read(cursorStateProvider).secondaryCursorTime, 500);
    });

    test('placeSecondary sets the secondary cursor', () {
      container.read(cursorStateProvider.notifier).placeSecondary(2000);
      expect(
        container.read(cursorStateProvider).secondaryCursorTime,
        2000,
      );
    });

    test('clearSecondary removes the secondary cursor', () {
      container.read(cursorStateProvider.notifier)
        ..placePrimary(100)
        ..placeSecondary(200)
        ..clearSecondary();
      final state = container.read(cursorStateProvider);
      expect(state.secondaryCursorTime, isNull);
      expect(state.primaryCursorTime, 100);
    });

    test('clearAll removes both cursors', () {
      container.read(cursorStateProvider.notifier)
        ..placePrimary(100)
        ..placeSecondary(200)
        ..clearAll();
      expect(container.read(cursorStateProvider), const CursorState());
    });

    test('placePrimary overwrites previous primary position', () {
      container.read(cursorStateProvider.notifier)
        ..placePrimary(100)
        ..placePrimary(999);
      expect(container.read(cursorStateProvider).primaryCursorTime, 999);
    });

    test('placing primary at time zero is valid', () {
      container.read(cursorStateProvider.notifier).placePrimary(0);
      expect(container.read(cursorStateProvider).primaryCursorTime, 0);
    });
  });

  // Regression: Issue 30. On iPhone landscape, a pan gesture could carry the
  // viewport — and the cursor placed via [WaveformGestureHandler] — past the
  // simulation's `t=0` boundary, producing a status-bar reading of
  // `T: -233 ns` and a dash in every signal value cell because no waveform
  // data exists at negative time. After the fix, [CursorStateNotifier] reads
  // the live [timeMapperProvider] and clamps every place call to
  // `[startTime, endTime]`.
  group('CursorStateNotifier — clamps to waveform range (Issue 30)', () {
    test('placePrimary below startTime clamps to startTime', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 10000,
            viewportWidth: 800,
          );

      c.read(cursorStateProvider.notifier).placePrimary(-233);
      expect(c.read(cursorStateProvider).primaryCursorTime, 0);
    });

    test('placePrimary above endTime clamps to endTime', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 0,
            endTime: 10000,
            viewportWidth: 800,
          );

      c.read(cursorStateProvider.notifier).placePrimary(99999);
      expect(c.read(cursorStateProvider).primaryCursorTime, 10000);
    });

    test('placeSecondary is clamped the same way', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
          .read(timeMapperProvider.notifier)
          .initialize(
            startTime: 100,
            endTime: 500,
            viewportWidth: 800,
          );

      c.read(cursorStateProvider.notifier)
        ..placeSecondary(-500)
        ..placePrimary(99999);
      final state = c.read(cursorStateProvider);
      expect(state.secondaryCursorTime, 100);
      expect(state.primaryCursorTime, 500);
    });

    test('no waveform loaded (empty mapper) preserves the requested time '
        '— clamp is opt-in once a range is known', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      // Default TimeMapper.empty() has startTime == endTime == 0; the
      // notifier should let any placement through so callers that move the
      // cursor before a file loads (session restore, deeplink) don't lose
      // their request.
      c.read(cursorStateProvider.notifier).placePrimary(1234);
      expect(c.read(cursorStateProvider).primaryCursorTime, 1234);
    });
  });

  // ── MarkerStateNotifier ───────────────────────────────────────────────────

  group('MarkerStateNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state has no markers', () {
      final state = container.read(markerStateProvider);
      expect(state, const MarkerState());
    });

    test('setMarker adds a marker', () {
      container.read(markerStateProvider.notifier).setMarker('a', 500);
      expect(
        container.read(markerStateProvider).getMarker('a'),
        500,
      );
    });

    test('setMarker overwrites an existing marker', () {
      container.read(markerStateProvider.notifier)
        ..setMarker('b', 100)
        ..setMarker('b', 999);
      expect(container.read(markerStateProvider).getMarker('b'), 999);
    });

    test('removeMarker removes the marker', () {
      container.read(markerStateProvider.notifier)
        ..setMarker('c', 300)
        ..removeMarker('c');
      expect(
        container.read(markerStateProvider).getMarker('c'),
        isNull,
      );
    });

    test('removeMarker on absent marker leaves state unchanged', () {
      final before = container.read(markerStateProvider);
      container.read(markerStateProvider.notifier).removeMarker('z');
      final after = container.read(markerStateProvider);
      expect(after, equals(before));
    });

    test('jumpToMarker returns the marker time', () {
      container.read(markerStateProvider.notifier).setMarker('d', 750);
      final time = container
          .read(markerStateProvider.notifier)
          .jumpToMarker('d');
      expect(time, 750);
    });

    test('jumpToMarker returns null for unset marker', () {
      final time = container
          .read(markerStateProvider.notifier)
          .jumpToMarker('x');
      expect(time, isNull);
    });

    test('multiple markers coexist independently', () {
      container.read(markerStateProvider.notifier)
        ..setMarker('a', 100)
        ..setMarker('m', 500)
        ..setMarker('z', 900);
      final state = container.read(markerStateProvider);
      expect(state.getMarker('a'), 100);
      expect(state.getMarker('m'), 500);
      expect(state.getMarker('z'), 900);
    });
  });

  // ── cursorDeltaProvider ───────────────────────────────────────────────────

  group('cursorDeltaProvider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('delta is null when no cursors are placed', () {
      final delta = container.read(cursorDeltaProvider);
      expect(delta.deltaDisplay, isNull);
      expect(delta.frequencyDisplay, isNull);
    });

    test('delta is null when only primary cursor is placed', () {
      container.read(cursorStateProvider.notifier).placePrimary(100);
      final delta = container.read(cursorDeltaProvider);
      expect(delta.deltaDisplay, isNull);
    });

    test('delta is null when only secondary cursor is placed', () {
      container.read(cursorStateProvider.notifier).placeSecondary(200);
      final delta = container.read(cursorDeltaProvider);
      expect(delta.deltaDisplay, isNull);
    });

    test('delta display is non-null when both cursors are placed', () {
      container.read(cursorStateProvider.notifier)
        ..placePrimary(100)
        ..placeSecondary(300);
      final delta = container.read(cursorDeltaProvider);
      expect(delta.deltaDisplay, isNotNull);
    });

    test('delta display contains tick count when no timescale', () {
      container.read(cursorStateProvider.notifier)
        ..placePrimary(0)
        ..placeSecondary(500);
      final delta = container.read(cursorDeltaProvider);
      // Without a timescale the formatter returns raw tick counts.
      expect(delta.deltaDisplay, contains('500'));
    });

    test('frequency display is null when no timescale is available', () {
      container.read(cursorStateProvider.notifier)
        ..placePrimary(0)
        ..placeSecondary(500);
      final delta = container.read(cursorDeltaProvider);
      expect(delta.frequencyDisplay, isNull);
    });

    test('delta is symmetric: swapping cursors gives same delta', () {
      container.read(cursorStateProvider.notifier)
        ..placePrimary(100)
        ..placeSecondary(300);
      final d1 = container.read(cursorDeltaProvider).deltaDisplay;

      container.read(cursorStateProvider.notifier)
        ..placePrimary(300)
        ..placeSecondary(100);
      final d2 = container.read(cursorDeltaProvider).deltaDisplay;

      expect(d1, equals(d2));
    });

    test('CursorDelta equality holds for identical values', () {
      const a = CursorDelta(deltaDisplay: '100 ns', frequencyDisplay: '10 MHz');
      const b = CursorDelta(deltaDisplay: '100 ns', frequencyDisplay: '10 MHz');
      expect(a, equals(b));
    });

    test('CursorDelta inequality when fields differ', () {
      const a = CursorDelta(deltaDisplay: '100 ns', frequencyDisplay: null);
      const b = CursorDelta(deltaDisplay: '200 ns', frequencyDisplay: null);
      expect(a, isNot(equals(b)));
    });

    test('CursorDelta hashCode equal for equal objects', () {
      const a = CursorDelta(deltaDisplay: '50 ticks', frequencyDisplay: null);
      const b = CursorDelta(deltaDisplay: '50 ticks', frequencyDisplay: null);
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
