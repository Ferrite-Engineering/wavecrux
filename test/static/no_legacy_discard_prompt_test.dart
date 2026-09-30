// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guard: makes sure the unsaved-changes prompt infrastructure
/// retired when auto-save replaced the user-visible concept is
/// not silently re-introduced. The grep is intentionally broad — any
/// reference to the deleted helpers in production code is a violation.
void main() {
  test(
    'no production code references the retired discard-session helpers',
    () async {
      final lib = Directory('lib');
      expect(lib.existsSync(), isTrue, reason: 'expected lib/ at repo root');

      const banned = <String>[
        'confirmDiscardSession',
        'DiscardSessionDialog',
        'sessionDirtyProvider',
        'SessionDirtyNotifier',
      ];

      final offenders = <String>[];
      await for (final entity in lib.list(recursive: true)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('.g.dart')) continue;
        final contents = entity.readAsStringSync();
        for (final needle in banned) {
          if (contents.contains(needle)) {
            offenders.add('${entity.path}: contains "$needle"');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'The discard-session prompt was removed. '
            'Re-introducing it is a regression — fix:\n  ${offenders.join('\n  ')}',
      );
    },
  );
}
