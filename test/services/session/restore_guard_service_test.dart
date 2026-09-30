// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/session/restore_guard_service.dart';

void main() {
  group('RestoreGuardService', () {
    late Directory tempDir;
    late RestoreGuardService guard;

    File sentinel() => File('${tempDir.path}/restore_in_progress');

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('restore_guard_test_');
      guard = RestoreGuardService(directoryFactory: () async => tempDir);
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('wasInterrupted is false on a clean (un-armed) slate', () async {
      expect(await guard.wasInterrupted(), isFalse);
    });

    test(
      'arm() writes the sentinel; wasInterrupted then reports true',
      () async {
        await guard.arm();
        expect(sentinel().existsSync(), isTrue);
        expect(await guard.wasInterrupted(), isTrue);
      },
    );

    test(
      'arm() then disarm() leaves no sentinel — the clean-run path',
      () async {
        await guard.arm();
        await guard.disarm();
        expect(sentinel().existsSync(), isFalse);
        expect(await guard.wasInterrupted(), isFalse);
      },
    );

    test(
      'a sentinel that survives (no disarm) is detected next launch',
      () async {
        // Simulate a crash/hang: arm, never disarm, then a fresh service over
        // the same directory (a new launch) observes the interruption.
        await guard.arm();
        final nextLaunch = RestoreGuardService(
          directoryFactory: () async => tempDir,
        );
        expect(await nextLaunch.wasInterrupted(), isTrue);
      },
    );

    test('wasInterrupted does not clear the sentinel (read-only)', () async {
      await guard.arm();
      expect(await guard.wasInterrupted(), isTrue);
      expect(await guard.wasInterrupted(), isTrue);
      expect(sentinel().existsSync(), isTrue);
    });

    test('disarm() is a no-op when nothing is armed', () async {
      await expectLater(guard.disarm(), completes);
      expect(sentinel().existsSync(), isFalse);
    });
  });
}
