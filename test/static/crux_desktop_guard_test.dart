// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_guards/crux_guards.dart';
import 'package:flutter_test/flutter_test.dart';

// The desktop layout is the Crux Desktop layer, not stock Material: dialogs
// open through `showCruxDialog` and are a `CruxDialog`, settings that apply at
// once are a `CruxSwitch`, options inside a form that applies on OK are
// checkboxes in a `CruxFormRow`, a row's actions are a `CruxOverflowMenu`
// ("⋯") plus a right-click menu, and transient feedback goes through the toast
// helpers. The scanner is crux_guards' `cruxAuditCruxDesktop`.
//
// A call site that renders only in the phone layout keeps the Material
// pattern behind `// crux-desktop: phone-only, <why>` on the line above its
// statement or member. `crux_desktop_allow_list.txt` holds the exact counts of
// sites that have not moved yet; it only shrinks.

void main() {
  test('no raw Material pattern the Crux Desktop layer replaces', () {
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
    final allowances = cruxParseDesktopAllowList(
      File('test/static/crux_desktop_allow_list.txt').readAsStringSync(),
    );

    // The allow-list is empty and stays empty: every site is on the Crux
    // Desktop layer or marked phone-only.
    expect(
      allowances,
      isEmpty,
      reason: 'crux_desktop_allow_list.txt must stay empty',
    );

    final result = cruxAuditCruxDesktop(
      sources: sources,
      allowances: allowances,
    );

    expect(result.filesScanned, greaterThan(100));
    expect(result.isClean, isTrue, reason: result.describe());
  });
}
