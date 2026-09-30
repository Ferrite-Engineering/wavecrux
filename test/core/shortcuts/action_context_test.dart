// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/domain/enums/device_class.dart';

void main() {
  group('ActionContext', () {
    test(
      'defaults are conservative (no file, no diagnostics, single pane)',
      () {
        const c = ActionContext(
          fileLoaded: false,
          deviceClass: DeviceClass.desktop,
        );
        expect(c.diagnosticsEnabled, isFalse);
        expect(c.paneCount, 1);
        expect(c.inSession, isFalse);
        expect(c.isHost, isFalse);
        expect(c.isRecording, isFalse);
        expect(c.stageViewVisible, isFalse);
        expect(c.cursorPresent, isFalse);
        expect(c.markersPresent, isFalse);
        expect(c.diffActive, isFalse);
        expect(c.cocotbLogLoaded, isFalse);
        expect(c.patternMatchesPresent, isFalse);
      },
    );

    test('new gating flags participate in equality and hashCode', () {
      for (final mutate in <ActionContext Function()>[
        () => const ActionContext(
          fileLoaded: true,
          deviceClass: DeviceClass.desktop,
          cursorPresent: true,
        ),
        () => const ActionContext(
          fileLoaded: true,
          deviceClass: DeviceClass.desktop,
          markersPresent: true,
        ),
        () => const ActionContext(
          fileLoaded: true,
          deviceClass: DeviceClass.desktop,
          diffActive: true,
        ),
        () => const ActionContext(
          fileLoaded: true,
          deviceClass: DeviceClass.desktop,
          cocotbLogLoaded: true,
        ),
        () => const ActionContext(
          fileLoaded: true,
          deviceClass: DeviceClass.desktop,
          patternMatchesPresent: true,
        ),
      ]) {
        const base = ActionContext(
          fileLoaded: true,
          deviceClass: DeviceClass.desktop,
        );
        final flagged = mutate();
        expect(flagged, isNot(equals(base)));
        expect(flagged, equals(mutate()));
        expect(flagged.hashCode, equals(mutate().hashCode));
      }
    });

    test('stageViewVisible participates in equality and hashCode', () {
      const a = ActionContext(
        fileLoaded: true,
        deviceClass: DeviceClass.desktop,
        stageViewVisible: true,
      );
      const b = ActionContext(
        fileLoaded: true,
        deviceClass: DeviceClass.desktop,
        stageViewVisible: true,
      );
      const c = ActionContext(
        fileLoaded: true,
        deviceClass: DeviceClass.desktop,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('isPhoneClass mirrors the device class', () {
      for (final dc in DeviceClass.values) {
        final c = ActionContext(fileLoaded: true, deviceClass: dc);
        expect(c.isPhoneClass, dc.isPhoneClass);
      }
    });

    test('value equality and hashCode', () {
      const a = ActionContext(
        fileLoaded: true,
        deviceClass: DeviceClass.tablet,
      );
      const b = ActionContext(
        fileLoaded: true,
        deviceClass: DeviceClass.tablet,
      );
      const c = ActionContext(
        fileLoaded: false,
        deviceClass: DeviceClass.tablet,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
