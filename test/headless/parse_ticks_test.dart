// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Times in, ticks out: a whole tick count, or a time with a unit in a link's
// `t` grammar converted with the file's timescale. Expected values are worked
// by hand from the timescale (one tick = factor x unit).

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/headless/wave_commands.dart';

const Timescale _ns = Timescale(factor: 1, unit: TimescaleUnit.nanoSeconds);
const Timescale _ps10 = Timescale(factor: 10, unit: TimescaleUnit.picoSeconds);
const Timescale _unknown = Timescale(factor: 1, unit: TimescaleUnit.unknown);

int _ticks(String text, Timescale? ts) => parseTicks(text, ts, flag: '--at');

void main() {
  test('a bare count is ticks, whatever the timescale', () {
    expect(_ticks('0', _ns), 0);
    expect(_ticks('1500', _ps10), 1500);
    expect(_ticks('42', null), 42);
    expect(_ticks('9223372036854775807', null), 9223372036854775807);
  });

  test('a time with a unit becomes ticks of the timescale', () {
    expect(_ticks('1500ns', _ns), 1500);
    expect(_ticks('1.5us', _ns), 1500);
    expect(_ticks('2s', _ns), 2000000000);
    expect(_ticks('20ps', _ps10), 2); // 20 ps / 10 ps
    expect(_ticks('1ns', _ps10), 100); // 1000 ps / 10 ps
    expect(_ticks('0.5ns', _ps10), 50);
    expect(_ticks('3µs', _ns), 3000);
  });

  test('a time between ticks is refused, never rounded', () {
    expect(
      () => _ticks('1.5ns', _ns),
      throwsA(
        isA<WaveUsageException>().having(
          (e) => e.message,
          'message',
          "`--at 1.5ns` is not a whole number of ticks of this file's 1ns "
              'timescale',
        ),
      ),
    );
    expect(() => _ticks('15ps', _ps10), throwsA(isA<WaveUsageException>()));
  });

  test('a unit on a file with no known timescale is refused', () {
    expect(() => _ticks('10ns', null), throwsA(isA<WaveUsageException>()));
    expect(() => _ticks('10ns', _unknown), throwsA(isA<WaveUsageException>()));
  });

  test('what is not a time is refused', () {
    for (final bad in <String>['-1', '1.5', 'ten', '10 ns', '10min', '']) {
      expect(
        () => _ticks(bad, _ns),
        throwsA(isA<WaveUsageException>()),
        reason: bad,
      );
    }
  });

  test('a tick past the 64-bit range is refused', () {
    expect(
      () => _ticks('9223372036854775808', null),
      throwsA(isA<WaveUsageException>()),
    );
    expect(
      () => _ticks('10000000000s', _ns),
      throwsA(isA<WaveUsageException>()),
    );
  });
}
