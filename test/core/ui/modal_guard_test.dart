// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart' show ModalGuard;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModalGuard', () {
    test('runs the opener on the first call', () async {
      var opened = 0;
      final completer = Completer<void>();
      unawaited(
        ModalGuard.run('k', () {
          opened++;
          return completer.future;
        }),
      );
      await Future<void>.delayed(Duration.zero);

      expect(opened, 1);
      expect(ModalGuard.isOpen('k'), isTrue);

      completer.complete();
      await Future<void>.delayed(Duration.zero);
      expect(ModalGuard.isOpen('k'), isFalse);
    });

    test('suppresses a re-entrant call while the surface is open', () async {
      var opened = 0;
      final completer = Completer<void>();
      Future<void> open() {
        opened++;
        return completer.future;
      }

      unawaited(ModalGuard.run('k', open));
      await Future<void>.delayed(Duration.zero);

      // Three more presses while still open — all ignored.
      await ModalGuard.run('k', open);
      await ModalGuard.run('k', open);
      await ModalGuard.run('k', open);

      expect(opened, 1, reason: 'only the first open should have run');

      completer.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test('allows re-opening after the surface closes', () async {
      var opened = 0;
      Future<void> openOnce() {
        opened++;
        return Future<void>.value();
      }

      await ModalGuard.run('k', openOnce);
      await ModalGuard.run('k', openOnce);

      expect(opened, 2, reason: 'each fully-closed open can re-run');
      expect(ModalGuard.isOpen('k'), isFalse);
    });

    test('different keys are independent', () async {
      final a = Completer<void>();
      final b = Completer<void>();
      unawaited(ModalGuard.run('a', () => a.future));
      unawaited(ModalGuard.run('b', () => b.future));
      await Future<void>.delayed(Duration.zero);

      expect(ModalGuard.isOpen('a'), isTrue);
      expect(ModalGuard.isOpen('b'), isTrue);

      a.complete();
      await Future<void>.delayed(Duration.zero);
      expect(ModalGuard.isOpen('a'), isFalse);
      expect(ModalGuard.isOpen('b'), isTrue);

      b.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test('releases the key even if the opener throws', () async {
      await expectLater(
        ModalGuard.run('k', () => Future<void>.error(StateError('boom'))),
        throwsStateError,
      );
      expect(ModalGuard.isOpen('k'), isFalse);
    });
  });
}
