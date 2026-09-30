// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/playback_state.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/domain/models/time_selection.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/cursors/providers/playback_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// A [TimeMapperNotifier] that always reports a fixed mapper, so the engine
/// captures a deterministic `[startTime, endTime]` range and visible window.
class _FixedTimeMapper extends TimeMapperNotifier {
  _FixedTimeMapper(this._fixed);
  final TimeMapper _fixed;
  @override
  TimeMapper build() => _fixed;
}

/// A [NavigationNotifier] that records every `jumpToTime` instead of panning,
/// so viewport-follow can be asserted without a real mapper.
class _SpyNavigation extends NavigationNotifier {
  final List<int> jumps = [];
  @override
  TimeSelection? build() => null;
  @override
  void jumpToTime(int time) => jumps.add(time);
}

class _MockSource extends Mock implements WaveformDataSource {}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

ProviderContainer _container({
  required int start,
  required int end,
  double viewportWidth = 1e9,
  double ticksPerPixel = 1,
  double panOffset = 0,
  Timescale? timescale,
  NavigationNotifier Function()? nav,
  WaveformDataSource? source,
}) {
  final mapper = TimeMapper(
    startTime: start,
    endTime: end,
    viewportWidth: viewportWidth,
    ticksPerPixel: ticksPerPixel,
    panOffsetTicks: panOffset,
  );
  final c = ProviderContainer(
    overrides: [
      timeMapperProvider.overrideWith(() => _FixedTimeMapper(mapper)),
      if (timescale != null)
        currentTimescaleProvider.overrideWithValue(timescale),
      if (nav != null) navigationProvider.overrideWith(nav),
      if (source != null)
        waveformSourceProvider.overrideWith(() => _FakeSourceNotifier(source)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

PlaybackNotifier _pb(ProviderContainer c) => c.read(playbackProvider.notifier);
PlaybackState _state(ProviderContainer c) => c.read(playbackProvider);
int? _primary(ProviderContainer c) =>
    c.read(cursorStateProvider).primaryCursorTime;

void main() {
  // The engine creates a real [Ticker] in play(); a binding must exist for
  // SchedulerBinding.instance. The ticker never fires (no pump) — tests drive
  // the math via advanceBy directly.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackNotifier — advance', () {
    test(
      'advanceBy moves the primary cursor forward proportional to speed',
      () {
        final c = _container(start: 0, end: 1000); // duration(10) → 100 ticks/s
        _pb(c).play();
        _pb(c).advanceBy(const Duration(seconds: 1));
        expect(_primary(c), 100);
        _pb(c).advanceBy(const Duration(seconds: 1));
        expect(_primary(c), 200);
      },
    );

    test('a non-degenerate range is required (empty mapper → no-op)', () {
      final c = _container(start: 0, end: 0);
      _pb(c).play();
      expect(_state(c).isPlaying, isFalse);
      _pb(c).advanceBy(const Duration(seconds: 1));
      expect(_primary(c), isNull);
    });
  });

  group('PlaybackNotifier — stop at end (loopMode.none)', () {
    test('reaching the end pins the cursor at hi and clears isPlaying', () {
      final c = _container(start: 0, end: 1000);
      _pb(c).play();
      expect(_state(c).isPlaying, isTrue);
      _pb(c).advanceBy(const Duration(seconds: 11)); // overshoot
      expect(_primary(c), 1000); // clamped at hi
      expect(_state(c).isPlaying, isFalse);
    });

    test('stop() returns the cursor to the start of the range', () {
      final c = _container(start: 0, end: 1000);
      _pb(c).play();
      _pb(c).advanceBy(const Duration(seconds: 3));
      expect(_primary(c), 300);
      _pb(c).stop();
      expect(_primary(c), 0);
      expect(_state(c).isPlaying, isFalse);
    });
  });

  group('PlaybackNotifier — loop wrap (wholeRange)', () {
    test('crossing hi wraps back into the range and keeps playing', () {
      final c = _container(start: 0, end: 1000);
      _pb(c)
        ..setLoopMode(PlaybackLoopMode.wholeRange)
        ..play();
      _pb(c).advanceBy(const Duration(seconds: 15)); // +1500 → wrap to 500
      expect(_primary(c), 500);
      expect(_state(c).isPlaying, isTrue);
    });
  });

  group('PlaybackNotifier — A–B loop', () {
    test('captures [min, max] of the two cursors and wraps within it', () {
      final c = _container(start: 0, end: 1000);
      c.read(cursorStateProvider.notifier)
        ..placePrimary(200)
        ..placeSecondary(600);
      _pb(c)
        ..setLoopMode(PlaybackLoopMode.aToB)
        ..play();
      // span = 400 → 40 ticks/s; +600 from 200 → 800, wraps to 400.
      _pb(c).advanceBy(const Duration(seconds: 15));
      expect(_primary(c), 400);
      expect(_state(c).isPlaying, isTrue);
    });

    test('falls back to whole-range when the secondary cursor is unset', () {
      final c = _container(start: 0, end: 1000);
      c.read(cursorStateProvider.notifier).placePrimary(200);
      _pb(c)
        ..setLoopMode(PlaybackLoopMode.aToB)
        ..play();
      // Whole range [0,1000] → 100 ticks/s. From seed 200, +500 → 700 (no wrap
      // at 600, proving the A–B bound was NOT applied).
      _pb(c).advanceBy(const Duration(seconds: 5));
      expect(_primary(c), 700);
      expect(_state(c).isPlaying, isTrue);
    });
  });

  group('PlaybackNotifier — duration speed is file-independent', () {
    test('the same duration(10) completes a ps- and a second-scale range', () {
      for (final end in [1000, 1000000000]) {
        final c = _container(start: 0, end: end, viewportWidth: end.toDouble());
        _pb(c).play();
        _pb(c).advanceBy(const Duration(seconds: 10));
        expect(_primary(c), end, reason: 'range [0,$end] should complete');
        expect(_state(c).isPlaying, isFalse);
      }
    });
  });

  group('PlaybackNotifier — power mode', () {
    test('uses the trace timescale to convert sim-time to ticks', () {
      // 1 ns/tick. simTimePerSecond = 1e-6 s/s → 1e-6 / 1e-9 = 1000 ticks/s.
      final c = _container(
        start: 0,
        end: 100000,
        viewportWidth: 100000,
        timescale: const Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds),
      );
      _pb(c)
        ..setSpeed(const PlaybackSpeed.simTimePerSecond(1e-6))
        ..play();
      _pb(c).advanceBy(const Duration(seconds: 2)); // +2000 ticks
      expect(_primary(c), 2000);
    });

    test('falls back to default duration playback when no timescale exists', () {
      // No timescale override → currentTimescale resolves to null (no source);
      // power mode falls back to the 10 s duration default. Range 1000 → 100
      // ticks/s.
      final c = _container(start: 0, end: 1000);
      _pb(c)
        ..setSpeed(const PlaybackSpeed.simTimePerSecond(5))
        ..play();
      _pb(c).advanceBy(const Duration(seconds: 1));
      expect(_primary(c), 100);
    });
  });

  group('PlaybackNotifier — re-press play at the end restarts', () {
    test('seeds from lo when the primary cursor is at/past the end', () {
      final c = _container(start: 0, end: 1000);
      _pb(c).play();
      _pb(c).advanceBy(const Duration(seconds: 11)); // finish at 1000
      expect(_primary(c), 1000);
      expect(_state(c).isPlaying, isFalse);

      _pb(c).play(); // primary 1000 ≥ hi → reseed to lo
      expect(_state(c).isPlaying, isTrue);
      _pb(c).advanceBy(const Duration(seconds: 1)); // +100 from lo (not 1100)
      expect(_primary(c), 100);
    });
  });

  group('PlaybackNotifier — viewport follow', () {
    test('recentres the viewport only when the playhead leaves the window', () {
      final spy = _SpyNavigation();
      final c = _container(
        start: 0,
        end: 1000,
        viewportWidth: 100, // visible window [0, 100]
        nav: () => spy,
      );
      _pb(c).play(); // follow on (default)
      _pb(c).advanceBy(const Duration(seconds: 3)); // → 300, off-screen
      expect(spy.jumps, contains(300));
    });

    test('does not recentre when followViewport is off', () {
      final spy = _SpyNavigation();
      final c = _container(
        start: 0,
        end: 1000,
        viewportWidth: 100,
        nav: () => spy,
      );
      _pb(c)
        ..setFollowViewport(value: false)
        ..play();
      _pb(c).advanceBy(const Duration(seconds: 3));
      expect(spy.jumps, isEmpty);
    });
  });

  group('PlaybackNotifier — toggle', () {
    test('toggle plays then pauses', () {
      final c = _container(start: 0, end: 1000);
      _pb(c).toggle();
      expect(_state(c).isPlaying, isTrue);
      _pb(c).toggle();
      expect(_state(c).isPlaying, isFalse);
    });
  });

  group('Stage widgets re-animate under simulated advance', () {
    test('a bound Stage signal re-samples the new cursor value', () {
      final source = _MockSource();
      when(() => source.isSignalLoaded('top.q')).thenReturn(true);
      when(() => source.startTime).thenReturn(0);
      when(() => source.rootScopes).thenReturn(const <Scope>[]);
      when(() => source.valueAt('top.q', any())).thenAnswer((inv) {
        final t = inv.positionalArguments[1] as int;
        return t >= 500 ? '1' : '0';
      });

      final c = _container(
        start: 0,
        end: 1000,
        viewportWidth: 1000,
        source: source,
      );
      const binding = StageSignalBinding(signalRef: 'top.q');

      // Cursor unset → sampled at source.startTime (0) → '0'.
      final before = c.read(stageBoundSignalProvider(binding));
      expect(before.kind, StageSignalSnapshotKind.value);
      expect(before.rawValue, '0');

      _pb(c)
        ..setFollowViewport(value: false)
        ..play()
        ..advanceBy(const Duration(seconds: 6)); // → cursor 600 ≥ 500

      final after = c.read(stageBoundSignalProvider(binding));
      expect(after.rawValue, '1'); // the bound widget would re-render
    });
  });
}
