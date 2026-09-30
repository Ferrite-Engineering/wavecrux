// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guard: makes sure the legacy seven-tab diagnostics dialog
/// (`DiagnosticsScreen` and its private `_DiagnosticsDialog` wrapper) is not
/// re-introduced after its split into the Tab Diagnostics drawer,
/// the App Diagnostics dialog, and the Pane Render Stats popover.
///
/// The legacy ARB-key prefixes (`diagnosticsTabFileInfo`,
/// `diagnosticsTabBenchmarks`, etc., and `diagnosticsCopyReport*`) are also
/// banned so a regression that re-adds them in any locale will be caught
/// before review.
void main() {
  test('no production code references the retired diagnostics dialog', () async {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'expected lib/ at repo root');

    // Banned identifiers — these are exact substrings.
    const banned = <String>[
      'DiagnosticsScreen',
      '_DiagnosticsDialog',
      'diagnosticsTabFileInfo',
      'diagnosticsTabBenchmarks',
      'diagnosticsTabRender',
      'diagnosticsTabMemory',
      'diagnosticsTabSignalHealth',
      'diagnosticsTabProvider',
      'diagnosticsTitle',
      'diagnosticsCopyReportLabel',
      'diagnosticsCopyReportSubtitle',
      'diagnosticsCopyReportTooltip',
      'diagnosticsCopyReportSuccess',
    ];

    final offenders = <String>[];
    await _scan(lib, banned, offenders);

    expect(
      offenders,
      isEmpty,
      reason:
          'The single seven-tab DiagnosticsScreen/Dialog was retired '
          'in favor of the Tab Diagnostics drawer, the App Diagnostics dialog, '
          'and the Pane Render Stats popover. Re-introducing the old surface '
          'is a regression — fix:\n  ${offenders.join('\n  ')}',
    );
  });

  test('no test code references the retired DiagnosticsScreen', () async {
    final tests = Directory('test');
    expect(tests.existsSync(), isTrue, reason: 'expected test/ at repo root');

    // Banned identifiers in tests — narrower set since some legacy strings
    // legitimately appear in regression-guard tests like this one.
    const bannedInTests = <String>[
      // Only the class name itself — strings inside this file are listed
      // below in `selfReferenceAllowlist` so the guard doesn't flag itself.
      'DiagnosticsScreen',
      '_DiagnosticsDialog',
    ];

    // Files allowed to mention the banned names (this regression-guard
    // itself, plus any future static guard that needs to enforce removal).
    const selfReferenceAllowlist = <String>{
      'test/static/no_legacy_diagnostics_test.dart',
    };

    final offenders = <String>[];
    await for (final entity in tests.list(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      final rel = entity.path.replaceAll(Platform.pathSeparator, '/');
      if (selfReferenceAllowlist.contains(rel)) continue;
      final contents = entity.readAsStringSync();
      for (final needle in bannedInTests) {
        if (contents.contains(needle)) {
          offenders.add('${entity.path}: contains "$needle"');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'The diagnostics-dialog test file was deleted. '
          'Re-introducing references is a regression — fix:\n'
          '  ${offenders.join('\n  ')}',
    );
  });
}

Future<void> _scan(
  Directory root,
  List<String> banned,
  List<String> offenders,
) async {
  await for (final entity in root.list(recursive: true)) {
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
}
