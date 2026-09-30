// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guardrail for the real-world parser-robustness zoo.
//
// For every committed waveform file under `test/fixtures/real_world/`,
// fail the build if:
//   1. there is no sibling `<name>.provenance.json` sidecar; OR
//   2. the sidecar's `license_spdx` is not on the allow-list.
//
// Pairs with the runtime sweep in
// `test/services/waveform/_real_world_zoo_test.dart` — the runtime
// sweep checks the file actually parses; this static test catches
// commit-time license / provenance hygiene before any parser runs.
//
// Allow-list matches the captured-fixture corpus exactly (see
// `test/static/captured_fixture_licenses_test.dart`).

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _zooDir = 'test/fixtures/real_world';
// Mirrors the runtime sweep's allow-list — wellen 0.20 lacks native
// compressed-input support, so .zst / .gz are deliberately omitted.
const _waveformExtensions = {'.fst', '.vcd', '.ghw'};

const _allowedLicenseSpdx = <String>{
  'MIT',
  'BSD-2-Clause',
  'BSD-3-Clause',
  'Apache-2.0',
  'ISC',
  'CC0-1.0',
  'public-domain',
};

void main() {
  group('Real-world zoo provenance hygiene', () {
    final dir = Directory(_zooDir);
    if (!dir.existsSync()) {
      test('zoo directory does not yet exist', () {
        // Scaffolding-only state — the runtime sweep test surfaces this
        // gracefully. Static guardrail is a no-op until the dir lands.
      });
      return;
    }

    final files =
        dir
            .listSync()
            .whereType<File>()
            .where(
              (f) => _waveformExtensions.contains(
                p.extension(f.path).toLowerCase(),
              ),
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    if (files.isEmpty) {
      test('zoo is currently empty (scaffolding only)', () {});
      return;
    }

    for (final fixture in files) {
      final name = p.basenameWithoutExtension(fixture.path);
      final sidecarPath = '${p.withoutExtension(fixture.path)}.provenance.json';

      test('$name: has .provenance.json sidecar', () {
        expect(
          File(sidecarPath).existsSync(),
          isTrue,
          reason:
              'Missing $sidecarPath — see '
              'test/fixtures/real_world/README.md for the sidecar schema.',
        );
      });

      test('$name: sidecar license is on the allow-list', () {
        final sidecar = File(sidecarPath);
        if (!sidecar.existsSync()) return;
        final json =
            jsonDecode(sidecar.readAsStringSync()) as Map<String, dynamic>;
        final spdx = json['license_spdx'];
        expect(
          spdx,
          isA<String>(),
          reason: 'sidecar must declare a string license_spdx',
        );
        expect(
          _allowedLicenseSpdx,
          contains(spdx),
          reason:
              'License $spdx is not on the allow-list. '
              'Only MIT / BSD-2 / BSD-3 / Apache-2.0 / ISC / CC0-1.0 / '
              'public-domain captures are permitted in the real-world zoo.',
        );
      });
    }
  });
}
