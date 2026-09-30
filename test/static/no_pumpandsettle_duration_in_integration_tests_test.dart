// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guard: `pumpAndSettle(const Duration(seconds: N))` (and the
/// non-const `pumpAndSettle(Duration(...))`) is banned in integration tests.
///
/// Background: integration tests run under [LiveTestWidgetsFlutterBinding],
/// where the `duration` argument to `pump` / `pumpAndSettle` is the *per-pump
/// real-time interval*, NOT a timeout. `pumpAndSettle(const Duration(seconds:
/// 10))` schedules a real ten-second `Timer` and blocks the full ten seconds
/// even when the UI settled instantly — minutes of wasted CI wall-clock across
/// the suite. The background-isolate FFI parse and the decoder decode pass
/// schedule no Flutter frames until they complete, so a bare `pumpAndSettle()`
/// would instead race the load. The only correct shape is a bounded
/// condition-poll: the `pumpUntil` / `pumpUntilWaveformReady` helpers in
/// `integration_test/helpers/app_driver.dart`, or an inline
/// `for (…) { await tester.pump(interval); if (ready) break; }`.
///
/// This test fails fast if a `pumpAndSettle(Duration…)` call is reintroduced
/// anywhere under `integration_test/`. Comment lines are exempt so the helper
/// doc-comments may still name the anti-pattern when explaining it.
void main() {
  test(
    'no integration test calls pumpAndSettle with a Duration argument',
    () async {
      final dir = Directory('integration_test');
      expect(
        dir.existsSync(),
        isTrue,
        reason: 'expected integration_test/ at repo root',
      );

      // Matches `pumpAndSettle(const Duration` and `pumpAndSettle(Duration`,
      // tolerating whitespace. A bare `pumpAndSettle()` (the correct form for a
      // pure UI-animation settle) does not match.
      final antiPattern = RegExp(r'pumpAndSettle\(\s*(const\s+)?Duration');

      final offenders = <String>[];
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // Skip comment lines so the convention can still be documented in
          // helper doc-comments (which legitimately name the anti-pattern).
          if (line.trimLeft().startsWith('//')) continue;
          if (antiPattern.hasMatch(line)) {
            offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'pumpAndSettle(Duration…) burns real CI wall-clock under the live '
            'integration-test binding (the duration is a per-pump interval, not '
            'a timeout). Replace it with a bounded condition-poll — '
            'pumpUntil / pumpUntilWaveformReady in '
            'integration_test/helpers/app_driver.dart, or an inline '
            'pump-until-ready loop. Offenders:\n  ${offenders.join('\n  ')}',
      );
    },
  );
}
