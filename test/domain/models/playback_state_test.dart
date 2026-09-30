// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/playback_state.dart';

void main() {
  group('PlaybackSpeed', () {
    test('duration mode carries playSeconds and null sim-time', () {
      const s = PlaybackSpeed.duration(10);
      expect(s.playSeconds, 10);
      expect(s.simTimePerWallSecond, isNull);
      expect(s.isDuration, isTrue);
    });

    test('power mode carries sim-time and null playSeconds', () {
      const s = PlaybackSpeed.simTimePerSecond(1e-6);
      expect(s.simTimePerWallSecond, 1e-6);
      expect(s.playSeconds, isNull);
      expect(s.isDuration, isFalse);
    });

    test('equality and hashCode', () {
      expect(
        const PlaybackSpeed.duration(10),
        const PlaybackSpeed.duration(10),
      );
      expect(
        const PlaybackSpeed.duration(10).hashCode,
        const PlaybackSpeed.duration(10).hashCode,
      );
      expect(
        const PlaybackSpeed.duration(10),
        isNot(const PlaybackSpeed.duration(5)),
      );
      // A duration and a power speed are never equal even with matching nulls.
      expect(
        const PlaybackSpeed.duration(10),
        isNot(const PlaybackSpeed.simTimePerSecond(10)),
      );
    });
  });

  group('PlaybackState', () {
    test('defaults', () {
      const s = PlaybackState();
      expect(s.isPlaying, isFalse);
      expect(s.speed, const PlaybackSpeed.duration(10));
      expect(s.loopMode, PlaybackLoopMode.none);
      expect(s.followViewport, isTrue);
    });

    test('copyWith replaces only the given fields', () {
      const s = PlaybackState();
      final p = s.copyWith(isPlaying: true);
      expect(p.isPlaying, isTrue);
      expect(p.speed, s.speed);
      expect(p.loopMode, s.loopMode);
      expect(p.followViewport, s.followViewport);

      final q = s.copyWith(
        speed: const PlaybackSpeed.duration(30),
        loopMode: PlaybackLoopMode.wholeRange,
        followViewport: false,
      );
      expect(q.speed, const PlaybackSpeed.duration(30));
      expect(q.loopMode, PlaybackLoopMode.wholeRange);
      expect(q.followViewport, isFalse);
      expect(q.isPlaying, isFalse);
    });

    test('equality and hashCode', () {
      const a = PlaybackState(loopMode: PlaybackLoopMode.aToB);
      const b = PlaybackState(loopMode: PlaybackLoopMode.aToB);
      const c = PlaybackState(loopMode: PlaybackLoopMode.wholeRange);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
