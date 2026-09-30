// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/services/waveform/display_changes.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../helpers/fake_waveform_data_source.dart';

List<(int, String)> _pairs(List<SignalChange> changes) => [
  for (final c in changes) (c.time, c.value),
];

/// Values seen in each [ticksPerColumn]-wide column, keyed by column.
Map<int, List<String>> _byColumn(List<SignalChange> changes, double tpc) {
  final out = <int, List<String>>{};
  for (final c in changes) {
    (out[(c.time / tpc).floor()] ??= <String>[]).add(c.value);
  }
  return out;
}

double _real(String v) => double.tryParse(v) ?? double.nan;

void main() {
  group('decimateChanges', () {
    test('keeps every change when no column holds more than two', () {
      final changes = [
        for (var i = 0; i < 100; i++)
          SignalChange(time: i * 10, value: i.isEven ? '1' : '0'),
      ];
      // 10 ticks per column: one change per column.
      expect(
        _pairs(decimateChanges(changes, ticksPerColumn: 10)),
        _pairs(changes),
      );
      // 20 ticks per column: two per column, still all kept.
      expect(
        _pairs(decimateChanges(changes, ticksPerColumn: 20)),
        _pairs(changes),
      );
    });

    test('is bounded by the column count, not the change count', () {
      final changes = [
        for (var i = 0; i < 1000000; i++)
          SignalChange(time: i, value: i.isEven ? '1' : '0'),
      ];
      const columns = 1600;
      final out = decimateChanges(
        changes,
        ticksPerColumn: changes.length / columns,
      );
      expect(out.length, lessThanOrEqualTo(4 * (columns + 1)));
      // A toggling signal: every column still shows both levels.
      final perColumn = _byColumn(out, changes.length / columns);
      expect(
        perColumn.values.every((v) => v.toSet().length == 2),
        isTrue,
      );
    });

    // The acceptance test for decimation: a pulse narrower than a pixel
    // column, in an otherwise quiet signal, must survive as two distinct
    // values in its column — which is what the painters draw as a mark.
    test('keeps a sub-pixel pulse inside a busy column', () {
      final changes = [
        const SignalChange(time: 0, value: '0'),
        // Column 5 (ticks 500..599): 0 → 0 → 1 → 0 → 0, first == last.
        const SignalChange(time: 510, value: '0'),
        const SignalChange(time: 520, value: '0'),
        const SignalChange(time: 530, value: '1'),
        const SignalChange(time: 531, value: '0'),
        const SignalChange(time: 560, value: '0'),
      ];
      final out = decimateChanges(changes, ticksPerColumn: 100);
      final column5 = _byColumn(out, 100)[5]!;
      expect(column5, contains('1'), reason: 'the pulse itself');
      expect(column5.first, '0');
      expect(column5.last, '0');
      expect(column5.length, lessThanOrEqualTo(4));
    });

    test('keeps an unknown value the first and last change do not carry', () {
      final changes = [
        for (var i = 0; i < 50; i++)
          SignalChange(time: i, value: i.isEven ? '1' : '0'),
      ]..[25] = const SignalChange(time: 25, value: 'x');
      final out = decimateChanges(changes, ticksPerColumn: 100);
      expect(out.map((c) => c.value), contains('x'));
      expect(out.length, lessThanOrEqualTo(4));
    });

    test('keeps each column’s min and max when given a magnitude', () {
      final changes = [
        const SignalChange(time: 0, value: '0.0'),
        const SignalChange(time: 10, value: '0.5'),
        const SignalChange(time: 20, value: '9.0'), // spike up
        const SignalChange(time: 30, value: '0.2'),
        const SignalChange(time: 40, value: '-4.0'), // spike down
        const SignalChange(time: 50, value: '0.1'),
        const SignalChange(time: 60, value: '0.0'),
      ];
      final plain = decimateChanges(changes, ticksPerColumn: 100);
      expect(plain.map((c) => c.value), isNot(contains('9.0')));
      final analog = decimateChanges(
        changes,
        ticksPerColumn: 100,
        magnitude: _real,
      );
      expect(analog.map((c) => c.value), containsAll(<String>['9.0', '-4.0']));
      expect(
        analog.map((c) => c.time).toList(),
        orderedEquals([...analog.map((c) => c.time)]..sort()),
        reason: 'output stays in time order',
      );
    });

    test('columns are laid out from the given origin', () {
      // Three same-valued changes: one column drops the middle one (nothing
      // to show), but a grid starting at 5.5 splits them across two columns
      // and keeps all three.
      final changes = [
        const SignalChange(time: 104, value: '1'),
        const SignalChange(time: 105, value: '1'),
        const SignalChange(time: 106, value: '1'),
      ];
      expect(
        _pairs(decimateChanges(changes, ticksPerColumn: 10)),
        [(104, '1'), (106, '1')],
      );
      // From 5.5: [95.5, 105.5) holds 104 and 105; [105.5, 115.5) holds 106.
      expect(
        _pairs(
          decimateChanges(changes, ticksPerColumn: 10, columnOrigin: 5.5),
        ),
        _pairs(changes),
      );
    });

    test('an unusable column width returns the changes unchanged', () {
      final changes = [
        for (var i = 0; i < 10; i++) SignalChange(time: i, value: '$i'),
      ];
      for (final tpc in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          _pairs(decimateChanges(changes, ticksPerColumn: tpc)),
          _pairs(changes),
          reason: '$tpc',
        );
      }
    });
  });

  group('changesForDisplay', () {
    // The packed-store path and the changesInRange path must agree exactly:
    // production runs the first, every fake-backed test the second.
    test('the packed store and changesInRange give identical results', () {
      final random = Random(7);
      const alphabet = ['0', '1', 'x', 'z', '1', '0', '0', '1'];
      for (var trial = 0; trial < 40; trial++) {
        var t = 0;
        final changes = <SignalChange>[];
        final n = 1 + random.nextInt(4000);
        for (var i = 0; i < n; i++) {
          t += random.nextInt(random.nextBool() ? 3 : 200);
          changes.add(
            SignalChange(
              time: t,
              value: alphabet[random.nextInt(alphabet.length)],
            ),
          );
        }
        // Keep times strictly increasing, as a real store holds them.
        final deduped = <SignalChange>[];
        for (final c in changes) {
          if (deduped.isEmpty || c.time > deduped.last.time) deduped.add(c);
        }
        final packed = WellenProvider()..injectLoadedSignal('3', deduped);
        final fake = FakeWaveformDataSource(signals: {'3': deduped});
        final start = random.nextInt(t + 1);
        final end = start + random.nextInt(t + 1);
        final tpc = 0.5 + random.nextDouble() * 60;
        final origin = random.nextDouble() * 50;
        expect(
          _pairs(
            packed.changesForDisplay(
              '3',
              start,
              end,
              ticksPerColumn: tpc,
              columnOrigin: origin,
            ),
          ),
          _pairs(
            fake.changesForDisplay(
              '3',
              start,
              end,
              ticksPerColumn: tpc,
              columnOrigin: origin,
            ),
          ),
          reason: 'trial $trial',
        );
      }
    });

    test('an unloaded signal yields nothing', () {
      expect(
        WellenProvider().changesForDisplay('9', 0, 100, ticksPerColumn: 1),
        isEmpty,
      );
    });
  });
}
