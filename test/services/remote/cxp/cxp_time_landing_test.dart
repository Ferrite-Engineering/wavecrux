// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/services/remote/cxp/cxp_time_landing.dart';

/// `crux.time_ps` (CXP §9.3.2) against a waveform's own timescale: the
/// conversion the inbound handler relies on, without any widget or provider.
void main() {
  Timescale scale(int factor, TimescaleUnit unit) =>
      Timescale(factor: factor, unit: unit);

  CxpTimeResolution? resolve(
    Object? ps, {
    Timescale? timescale,
    int startTime = 0,
    int endTime = 1000000,
  }) => resolveCxpTimePs(
    <String, Object?>{kCxpTimePsMetadataKey: ?ps},
    timescale: timescale ?? scale(1, TimescaleUnit.nanoSeconds),
    startTime: startTime,
    endTime: endTime,
  );

  test('the registered key is crux.time_ps', () {
    expect(kCxpTimePsMetadataKey, 'crux.time_ps');
  });

  test('a message without the key asks nothing about time', () {
    expect(
      resolveCxpTimePs(
        const <String, Object?>{'crux.design_id': 'abc'},
        timescale: scale(1, TimescaleUnit.nanoSeconds),
        startTime: 0,
        endTime: 100,
      ),
      isNull,
    );
    // The un-namespaced name the draft used before revision 10 is just an
    // unknown key to a receiver, and is ignored as CXP §9.3 requires.
    expect(
      resolveCxpTimePs(
        const <String, Object?>{'time_ps': 41250},
        timescale: scale(1, TimescaleUnit.nanoSeconds),
        startTime: 0,
        endTime: 100000,
      ),
      isNull,
    );
  });

  group('converts picoseconds to the waveform tick', () {
    test(
      '1 ns ticks: 41250 ps is tick 41',
      () {
        final r = resolve(41250)!;
        expect(r.tick, 41);
        expect(r.reason, isNull);
      },
    );

    test('rounds half up to the nearest tick', () {
      expect(resolve(41499)!.tick, 41);
      expect(resolve(41500)!.tick, 42);
    });

    test('1 ps ticks: the value is the tick', () {
      expect(
        resolve(41250, timescale: scale(1, TimescaleUnit.picoSeconds))!.tick,
        41250,
      );
    });

    test('10 ns ticks', () {
      expect(
        resolve(50000, timescale: scale(10, TimescaleUnit.nanoSeconds))!.tick,
        5,
      );
    });

    test('100 ps ticks', () {
      expect(
        resolve(1250, timescale: scale(100, TimescaleUnit.picoSeconds))!.tick,
        13,
      );
    });

    test('us ticks', () {
      expect(
        resolve(
          5000000,
          timescale: scale(1, TimescaleUnit.microSeconds),
        )!.tick,
        5,
      );
    });

    test('fs ticks are finer than the picosecond the key counts', () {
      expect(
        resolve(7, timescale: scale(1, TimescaleUnit.femtoSeconds))!.tick,
        7000,
      );
      expect(
        resolve(7, timescale: scale(100, TimescaleUnit.femtoSeconds))!.tick,
        70,
      );
    });

    test('time zero is time zero', () {
      expect(resolve(0)!.tick, 0);
    });
  });

  group('clamps to the waveform and says so', () {
    test('past the end goes to the end', () {
      final r = resolve(5000000, endTime: 1000)!;
      expect(r.tick, 1000);
      expect(r.reason, contains('nearest end'));
    });

    test('before a waveform that starts late goes to its start', () {
      final r = resolve(1000, startTime: 500, endTime: 1000)!;
      expect(r.tick, 500);
      expect(r.reason, contains('nearest end'));
    });

    test('inside the range is not reported', () {
      final r = resolve(500000, startTime: 500, endTime: 1000)!;
      expect(r.tick, 500);
      expect(r.reason, isNull);
    });

    test('a value far past a femtosecond waveform is its end, not a wrap', () {
      final r = resolve(
        1 << 60,
        timescale: scale(1, TimescaleUnit.femtoSeconds),
        endTime: 2000,
      )!;
      expect(r.tick, 2000);
      expect(r.reason, contains('nearest end'));
    });
  });

  group('declines, never refuses', () {
    void expectDeclined(CxpTimeResolution? r, String why) {
      expect(r, isNotNull);
      expect(r!.tick, isNull);
      expect(r.reason, contains(why));
    }

    test('negative', () {
      expectDeclined(resolve(-1), 'non-negative integer');
    });

    test('a float, even a whole one: the key is an integer', () {
      expectDeclined(resolve(41250.0), 'non-negative integer');
      expectDeclined(resolve(41250.5), 'non-negative integer');
    });

    test('a string, a bool, a list', () {
      expectDeclined(resolve('41250'), 'non-negative integer');
      expectDeclined(resolve(true), 'non-negative integer');
      expectDeclined(resolve(<int>[1]), 'non-negative integer');
    });

    test('null', () {
      expectDeclined(
        resolveCxpTimePs(
          <String, Object?>{kCxpTimePsMetadataKey: null},
          timescale: scale(1, TimescaleUnit.nanoSeconds),
          startTime: 0,
          endTime: 100,
        ),
        'non-negative integer',
      );
    });

    test('a waveform that declares no timescale', () {
      final r = resolveCxpTimePs(
        const <String, Object?>{kCxpTimePsMetadataKey: 5000},
        timescale: null,
        startTime: 0,
        endTime: 100,
      );
      expectDeclined(r, 'no timescale');
    });

    test('an unknown unit, and a zero factor', () {
      expectDeclined(
        resolve(5000, timescale: scale(1, TimescaleUnit.unknown)),
        'no timescale',
      );
      expectDeclined(
        resolve(5000, timescale: scale(0, TimescaleUnit.nanoSeconds)),
        'no timescale',
      );
    });
  });
}
