// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/platform_info.dart';

void main() {
  // ── ScreenInfo ────────────────────────────────────────────────────────────

  group('ScreenInfo', () {
    const s = ScreenInfo(
      physicalWidth: 2560,
      physicalHeight: 1664,
      devicePixelRatio: 2,
    );

    test('logicalWidth divides by DPR', () {
      expect(s.logicalWidth, 1280);
    });

    test('logicalHeight divides by DPR', () {
      expect(s.logicalHeight, 832);
    });

    test('1x display has same logical and physical dimensions', () {
      const s1x = ScreenInfo(
        physicalWidth: 1920,
        physicalHeight: 1080,
        devicePixelRatio: 1,
      );
      expect(s1x.logicalWidth, 1920);
      expect(s1x.logicalHeight, 1080);
    });

    test('copyWith replaces fields', () {
      final copy = s.copyWith(physicalWidth: 3840);
      expect(copy.physicalWidth, 3840);
      expect(copy.physicalHeight, s.physicalHeight);
      expect(copy.devicePixelRatio, s.devicePixelRatio);
    });

    test('copyWith with no args returns equal value', () {
      expect(s.copyWith(), equals(s));
    });

    test('equality: same values are equal', () {
      const other = ScreenInfo(
        physicalWidth: 2560,
        physicalHeight: 1664,
        devicePixelRatio: 2,
      );
      expect(s, equals(other));
    });

    test('equality: different physicalWidth is not equal', () {
      expect(s, isNot(equals(s.copyWith(physicalWidth: 1920))));
    });

    test('equality: different physicalHeight is not equal', () {
      expect(s, isNot(equals(s.copyWith(physicalHeight: 1080))));
    });

    test('equality: different DPR is not equal', () {
      expect(s, isNot(equals(s.copyWith(devicePixelRatio: 1))));
    });

    test('hashCode is equal for equal objects', () {
      const other = ScreenInfo(
        physicalWidth: 2560,
        physicalHeight: 1664,
        devicePixelRatio: 2,
      );
      expect(s.hashCode, equals(other.hashCode));
    });

    test('toString contains physical dimensions', () {
      expect(s.toString(), contains('2560'));
      expect(s.toString(), contains('1664'));
    });

    test('toString contains logical dimensions', () {
      expect(s.toString(), contains('1280'));
      expect(s.toString(), contains('832'));
    });
  });

  // ── PlatformInfo ──────────────────────────────────────────────────────────

  group('PlatformInfo', () {
    const info = PlatformInfo(
      operatingSystem: 'macos',
      osVersion: 'Version 15.4 (Build 24E248)',
      cpuArchitecture: 'arm64',
      cpuCores: 10,
      locale: 'en_US',
      dartVersion: '3.5.3 (stable)',
      totalRamBytes: 17179869184, // 16 GB
      screens: [
        ScreenInfo(
          physicalWidth: 2560,
          physicalHeight: 1664,
          devicePixelRatio: 2,
        ),
      ],
    );

    test('default screens is empty list', () {
      const minimal = PlatformInfo(
        operatingSystem: 'linux',
        osVersion: '',
        cpuArchitecture: 'x64',
        cpuCores: 4,
        locale: 'en_US',
        dartVersion: '3.5.3 (stable)',
      );
      expect(minimal.screens, isEmpty);
    });

    test('totalRamBytes defaults to null', () {
      const minimal = PlatformInfo(
        operatingSystem: 'linux',
        osVersion: '',
        cpuArchitecture: 'x64',
        cpuCores: 4,
        locale: 'en_US',
        dartVersion: '3.5.3',
      );
      expect(minimal.totalRamBytes, isNull);
    });

    test('copyWith replaces operatingSystem', () {
      final copy = info.copyWith(operatingSystem: 'linux');
      expect(copy.operatingSystem, 'linux');
      expect(copy.cpuCores, info.cpuCores);
    });

    test('copyWith replaces totalRamBytes', () {
      final copy = info.copyWith(totalRamBytes: 8589934592);
      expect(copy.totalRamBytes, 8589934592);
    });

    test('copyWith replaces screens', () {
      final copy = info.copyWith(screens: const []);
      expect(copy.screens, isEmpty);
    });

    test('copyWith with no args returns equal value', () {
      expect(info.copyWith(), equals(info));
    });

    test('equality: same values are equal', () {
      const other = PlatformInfo(
        operatingSystem: 'macos',
        osVersion: 'Version 15.4 (Build 24E248)',
        cpuArchitecture: 'arm64',
        cpuCores: 10,
        locale: 'en_US',
        dartVersion: '3.5.3 (stable)',
        totalRamBytes: 17179869184,
        screens: [
          ScreenInfo(
            physicalWidth: 2560,
            physicalHeight: 1664,
            devicePixelRatio: 2,
          ),
        ],
      );
      expect(info, equals(other));
    });

    test('equality: different OS is not equal', () {
      expect(info, isNot(equals(info.copyWith(operatingSystem: 'linux'))));
    });

    test('equality: different cpuCores is not equal', () {
      expect(info, isNot(equals(info.copyWith(cpuCores: 8))));
    });

    test('equality: different totalRamBytes is not equal', () {
      expect(info, isNot(equals(info.copyWith(totalRamBytes: 8589934592))));
    });

    test('equality: null vs non-null totalRamBytes is not equal', () {
      const noRam = PlatformInfo(
        operatingSystem: 'macos',
        osVersion: 'Version 15.4 (Build 24E248)',
        cpuArchitecture: 'arm64',
        cpuCores: 10,
        locale: 'en_US',
        dartVersion: '3.5.3 (stable)',
      );
      expect(info, isNot(equals(noRam)));
    });

    test('equality: different screens list is not equal', () {
      expect(info, isNot(equals(info.copyWith(screens: const []))));
    });

    test('equality: different screen contents is not equal', () {
      const otherScreen = ScreenInfo(
        physicalWidth: 1920,
        physicalHeight: 1080,
        devicePixelRatio: 1,
      );
      expect(
        info,
        isNot(equals(info.copyWith(screens: const [otherScreen]))),
      );
    });

    test('hashCode is equal for equal objects', () {
      const other = PlatformInfo(
        operatingSystem: 'macos',
        osVersion: 'Version 15.4 (Build 24E248)',
        cpuArchitecture: 'arm64',
        cpuCores: 10,
        locale: 'en_US',
        dartVersion: '3.5.3 (stable)',
        totalRamBytes: 17179869184,
        screens: [
          ScreenInfo(
            physicalWidth: 2560,
            physicalHeight: 1664,
            devicePixelRatio: 2,
          ),
        ],
      );
      expect(info.hashCode, equals(other.hashCode));
    });

    test('toString contains OS', () {
      expect(info.toString(), contains('macos'));
    });

    test('toString contains architecture', () {
      expect(info.toString(), contains('arm64'));
    });
  });
}
