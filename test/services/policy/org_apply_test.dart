// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/services/policy/org_session_template.dart';

void main() {
  group('the session template', () {
    // The real on-disk shape: panel flags live under `panels`, and the source
    // file under `sourceFile`. Written the way `SessionService` writes it, so
    // this exercises the decoder rather than a shape invented for the test.
    String documentWith({String? sourceFilePath}) => jsonEncode(
      <String, Object?>{
        'version': 1,
        'sourceFilePath': ?sourceFilePath,
        'panels': <String, Object?>{
          'signalTree': false,
          'stageView': true,
        },
      },
    );

    test('a layout decodes', () {
      final template = decodeOrgSessionTemplate(
        documentWith(),
        diagnosticName: 'house.wavecrux',
      );
      expect(template.isAvailable, isTrue);
      expect(template.state!.signalTreeVisible, isFalse);
      expect(template.state!.stageViewVisible, isTrue);
    });

    test("the template's source file is DROPPED", () {
      final template = decodeOrgSessionTemplate(
        documentWith(sourceFilePath: '/home/alice/dump.vcd'),
        diagnosticName: 'house.wavecrux',
      );
      expect(
        template.state!.sourceFilePath,
        isNull,
        reason:
            'an org template carrying one engineer’s capture would have every '
            'fresh session trying to open Alice’s file — at best a missing '
            'file, at worst somebody else’s data',
      );
    });

    test('stripping is idempotent and leaves the rest alone', () {
      const state = SessionState(
        sourceFilePath: '/tmp/a.vcd',
        stageViewVisible: true,
      );
      final once = stripSourceFile(state);
      final twice = stripSourceFile(once);
      expect(once.sourceFilePath, isNull);
      expect(twice.sourceFilePath, isNull);
      expect(twice.stageViewVisible, isTrue);
    });

    test('a malformed document reports rather than throwing', () {
      final template = decodeOrgSessionTemplate(
        '{ not json',
        diagnosticName: 'broken.wavecrux',
      );
      expect(template.isAvailable, isFalse);
      expect(template.problem, contains('broken.wavecrux'));
    });

    test('a JSON array is not a session', () {
      final template = decodeOrgSessionTemplate(
        jsonEncode(<Object?>[1, 2]),
        diagnosticName: 'array.wavecrux',
      );
      expect(template.isAvailable, isFalse);
    });
  });
}
