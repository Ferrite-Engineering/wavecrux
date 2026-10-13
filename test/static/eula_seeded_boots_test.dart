// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_eula/crux_eula_guards.dart';
import 'package:flutter_test/flutter_test.dart';

// Every integration test that boots the app seeds EULA acceptance first.
// CruxEulaGate covers an unseeded boot with a modal barrier, so every tap
// misses, and the weekly integration runs report it days late. The scanner is
// crux_eula's; this names WaveCrux's boot and seed helpers.
//
// `seedFirstLaunchAnswers` (integration_test/helpers/app_driver.dart) seeds
// acceptance and the telemetry answer. The fixture loaders that call it
// (`loadFixtureVcd`, `loadFixtureVcdAbsolute`) are not boot calls here: they
// seed before they boot.

void main() {
  test('every integration-test boot seeds EULA acceptance first', () {
    final dir = Directory('integration_test');
    expect(dir.existsSync(), isTrue, reason: 'run from the repository root');
    final sources = [
      for (final f in dir.listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart'))
          CruxEulaGuardSource(path: f.path, source: f.readAsStringSync()),
    ];
    expect(sources, isNotEmpty);

    final findings = cruxAuditEulaSeededBoots(
      sources: sources,
      seedCalls: {'seedFirstLaunchAnswers', 'seedEulaAcceptance'},
    );
    expect(findings, isEmpty, reason: findings.join('\n'));
  });
}
