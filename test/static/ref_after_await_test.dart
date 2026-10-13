// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_guards/crux_guards.dart';
import 'package:flutter_test/flutter_test.dart';

// A ConsumerState's `ref`, or a WidgetRef parameter, is never used after an
// `await` without a `mounted` check in between: once the widget is gone the
// read throws and the rest of the handler never runs. The scanner is
// crux_guards' `cruxAuditRefAfterAwait` (crux-shared#12). All 41 sites it
// found at adoption were fixed rather than exempted; a site that is safe for
// a reason the scan cannot see goes in `exemptions:` with that reason.

void main() {
  test('ref is never used after an await without a mounted check', () {
    final sources = [
      for (final f in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
          CruxGuardSource(
            path: f.path.replaceAll(r'\', '/'),
            source: f.readAsStringSync(),
          ),
    ];

    final result = cruxAuditRefAfterAwait(sources: sources);

    expect(result.filesScanned, greaterThan(100));
    expect(result.isClean, isTrue, reason: result.describe());
  });
}
