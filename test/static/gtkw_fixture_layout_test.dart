// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guardrail: the GTKWave session-import corpus under test/fixtures/gtkw/
// follows the same generated/ + captured/ split as the protocol decoders —
// no loose fixture files at the gtkw/ root. Every `.gtkw`, `.vcd`, `.txt`, and
// `.expected_*.json` must live in either generated/ or captured/.
//
// The verification flow consumes this same tree directly (there is no
// duplicate verification/fixtures/gtkw/ copy), so this single root is the only
// place to enforce.
//
// Catches "regenerated a fixture without writing it under generated/" — i.e. a
// file reappearing at the gtkw/ root.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/os_detritus.dart';

const _root = 'test/fixtures/gtkw';
const _allowedSubdirs = {'generated', 'captured'};

void main() {
  test(
    'test/fixtures/gtkw/ has no loose files — only generated/ + captured/',
    () {
      final rootDir = Directory(_root);
      expect(rootDir.existsSync(), isTrue, reason: '$_root is missing');

      final looseFiles = <String>[];
      final unexpectedDirs = <String>[];

      for (final entity in rootDir.listSync()) {
        final name = p.basename(entity.path);
        if (entity is File) {
          // Browsing the corpus is not a corpus defect; any other dotfile at
          // the root is a stray and is reported.
          if (isOsDetritus(name)) continue;
          looseFiles.add(p.relative(entity.path));
        } else if (entity is Directory && !_allowedSubdirs.contains(name)) {
          unexpectedDirs.add(p.relative(entity.path));
        }
      }

      expect(
        looseFiles,
        isEmpty,
        reason:
            'loose files at the gtkw/ root — every fixture must live in '
            'generated/ or captured/:\n  ${looseFiles.join('\n  ')}\n'
            'If this is a regenerated fixture, point the generator at '
            'test/fixtures/gtkw/generated/.',
      );
      expect(
        unexpectedDirs,
        isEmpty,
        reason:
            'unexpected subdirectory under gtkw/ (only generated/ + '
            'captured/ are allowed):\n  ${unexpectedDirs.join('\n  ')}',
      );

      // Both tiers must actually exist — a missing tier means the corpus
      // was half-migrated.
      for (final sub in _allowedSubdirs) {
        expect(
          Directory(p.join(_root, sub)).existsSync(),
          isTrue,
          reason: 'missing required gtkw fixture tier: $_root/$sub',
        );
      }
    },
  );
}
