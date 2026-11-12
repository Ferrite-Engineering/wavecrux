// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Wording canon for the menu and About labels the 2026-11 suite audit found
// worded differently across the four products (D04, D05, D51, D52, D54). The
// canon: a label that opens a dialog ends in the ellipsis character in every
// locale; "Cross-Probe Selection…" is hyphenated and capitalised like the other
// Title Case cross-probe labels; "license" is the spelling in every English
// string; the About box names its issue button as the Help menu does.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _locales = ['en', 'zh_CN', 'zh', 'ja', 'ko'];

/// Menu labels that open a dialog or a picker (D04, D05).
const _dialogOpeners = <String>[
  'shortcutActionOpenFile',
  'shortcutActionSaveSessionAs',
  'shortcutActionSaveWorkspaceAs',
  'shortcutActionShareSession',
  'shortcutActionJoinSession',
  'shortcutActionOpenCommandPalette',
  'shortcutActionOpenTabDiagnostics',
  'shortcutActionOpenAppDiagnostics',
  'shortcutActionResetWorkspace',
  'actionCrossProbeSelection',
  'aboutButtonReportIssue',
];

Map<String, dynamic> _load(String locale) {
  final file = File('lib/l10n/app_$locale.arb');
  if (!file.existsSync()) {
    throw StateError('missing ${file.path}');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  final arbs = {for (final l in _locales) l: _load(l)};

  for (final locale in _locales) {
    test('$locale: every dialog-opening menu label ends in an ellipsis', () {
      for (final key in _dialogOpeners) {
        expect(
          (arbs[locale]![key] as String).endsWith('…'),
          isTrue,
          reason: '$key in app_$locale.arb is "${arbs[locale]![key]}"',
        );
      }
    });
  }

  test('en: Cross-Probe Selection… is hyphenated and capitalised', () {
    expect(arbs['en']!['actionCrossProbeSelection'], 'Cross-Probe Selection…');
  });

  test('en: the About issue button reads as the Help menu item does', () {
    expect(arbs['en']!['aboutButtonReportIssue'], 'Submit Issue…');
    expect(
      arbs['en']!['aboutButtonReportIssue'],
      arbs['en']!['shortcutActionSubmitIssue'],
    );
  });

  test('en: no user-visible string spells "licence"', () {
    final offenders = <String>[
      for (final e in arbs['en']!.entries)
        if (!e.key.startsWith('@') &&
            e.value is String &&
            (e.value as String).toLowerCase().contains('licence'))
          e.key,
    ];
    expect(offenders, isEmpty);
  });
}
