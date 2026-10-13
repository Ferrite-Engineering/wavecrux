// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_guards/crux_guards.dart';
import 'package:flutter_test/flutter_test.dart';

// Every key in the template ARB is read by some hand-written lib/ code, or
// retained here with a reason. A dead key still costs a translation in four
// locales and misleads the next reader about what the UI says. The scanner is
// crux_guards' `cruxAuditUnusedL10nKeys` (crux-shared#2). A key kept on
// purpose goes in `retained:` with its reason; none is needed today.

void main() {
  test('every template ARB key is read by lib/ code', () {
    final keys = cruxArbMessageKeys(
      File('lib/l10n/app_en.arb').readAsStringSync(),
    );
    final sources = [
      for (final f in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') &&
            !f.path.replaceAll(r'\', '/').contains('lib/l10n/generated/'))
          CruxGuardSource(path: f.path, source: f.readAsStringSync()),
    ];

    final result = cruxAuditUnusedL10nKeys(
      keys: keys,
      sources: sources,
      arbPath: 'lib/l10n/app_en.arb',
    );

    expect(keys.length, greaterThan(500));
    expect(result.filesScanned, greaterThan(100));
    expect(result.isClean, isTrue, reason: result.describe());
  });
}
