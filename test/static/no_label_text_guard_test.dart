// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: no `InputDecoration.labelText` under `lib/`.
//
// The Crux Desktop theme turns floating labels off
// (`FloatingLabelBehavior.never`), so a `labelText` shows only while its field
// is empty. A field that holds a value then reads as a bare number or string
// with no label at all.
//
// A field the user has to identify (a setting, a path, a name, a number, any
// form field) sits in a `CruxFormRow`, which keeps the label on screen and is
// the control's accessible name. A search or filter box whose purpose stays
// obvious while it holds text uses `hintText` and an explicit `Semantics`
// label.
//
// Every use found in a code line (a comment mentioning the word is not a use)
// must be pinned in [_allowed] with the exact file, the trimmed line and a
// reason the field still shows a label while it holds a value. The list is
// empty on purpose; an entry that matches nothing is a finding too, so it
// cannot outlive the code.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reviewed uses: `'<file>|<trimmed line>'` mapped to the reason it is safe.
const Map<String, String> _allowed = <String, String>{};

final RegExp _labelText = RegExp(r'\blabelText\s*:');

void main() {
  test('no InputDecoration labelText under lib/', () {
    final root = Directory('lib');
    expect(
      root.existsSync(),
      isTrue,
      reason: 'lib/ must exist; run from the repository root',
    );

    final findings = <String>[];
    final matched = <String>{};
    var scanned = 0;
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      scanned++;
      final path = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.startsWith('//')) continue;
        if (!_labelText.hasMatch(trimmed)) continue;
        final key = '$path|$trimmed';
        if (_allowed.containsKey(key)) {
          matched.add(key);
        } else {
          findings.add('$path:${i + 1}: $trimmed');
        }
      }
    }

    // Non-vacuity: a wrong working directory would pass by finding nothing.
    expect(scanned, greaterThan(100));
    expect(
      findings,
      isEmpty,
      reason:
          'labelText shows only while the field is empty under the desktop '
          'theme. Put the field in a CruxFormRow, or for a search box use '
          'hintText plus a Semantics label:\n${findings.join('\n')}',
    );
    expect(
      _allowed.keys.toSet().difference(matched),
      isEmpty,
      reason: 'an allowlist entry matches no line; remove it',
    );
  });
}
