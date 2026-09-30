// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/platform_info.dart';
import 'package:wavecrux/services/diagnostics/platform_info_service.dart';

void main() {
  const service = PlatformInfoService();

  // ── collect() smoke tests ─────────────────────────────────────────────────

  group('PlatformInfoService.collect', () {
    test('returns without throwing', () {
      expect(() => service.collect(), returnsNormally);
    });

    test('operatingSystem is non-empty', () {
      final info = service.collect();
      expect(info.operatingSystem, isNotEmpty);
    });

    test('cpuArchitecture is non-empty', () {
      final info = service.collect();
      expect(info.cpuArchitecture, isNotEmpty);
    });

    test('cpuCores is positive', () {
      final info = service.collect();
      expect(info.cpuCores, greaterThan(0));
    });

    test('dartVersion is non-empty', () {
      final info = service.collect();
      expect(info.dartVersion, isNotEmpty);
    });

    test('passes through provided screens list', () {
      const screens = [
        ScreenInfo(
          physicalWidth: 1920,
          physicalHeight: 1080,
          devicePixelRatio: 1,
        ),
      ];
      final info = service.collect(screens: screens);
      expect(info.screens, equals(screens));
    });

    test('screens defaults to empty when not provided', () {
      final info = service.collect();
      expect(info.screens, isEmpty);
    });
  });

  // ── parseDartVersion ──────────────────────────────────────────────────────

  group('PlatformInfoService.parseDartVersion', () {
    test('extracts version and channel from full version string', () {
      const raw =
          "3.5.3 (stable) (Mon Sep 30 09:03:00 2024 +0000) on 'macos_arm64'";
      expect(PlatformInfoService.parseDartVersion(raw), '3.5.3 (stable)');
    });

    test('handles beta channel', () {
      const raw =
          "3.6.0 (beta) (Tue Oct 01 00:00:00 2024 +0000) on 'linux_x64'";
      expect(PlatformInfoService.parseDartVersion(raw), '3.6.0 (beta)');
    });

    test('handles dev channel', () {
      const raw = "3.7.0 (dev) (Wed Oct 02 00:00:00 2024 +0000) on 'linux_x64'";
      expect(PlatformInfoService.parseDartVersion(raw), '3.7.0 (dev)');
    });

    test('falls back to first token when pattern does not match', () {
      expect(PlatformInfoService.parseDartVersion('3.5.3'), '3.5.3');
    });

    test('falls back to first token for malformed string', () {
      final result = PlatformInfoService.parseDartVersion(
        '3.5.3 something else',
      );
      expect(result, '3.5.3');
    });

    test('returns raw string when completely unrecognisable', () {
      expect(PlatformInfoService.parseDartVersion('unknown'), 'unknown');
    });

    test('empty string returns empty string', () {
      expect(PlatformInfoService.parseDartVersion(''), '');
    });
  });

  // ── parseCpuArch ──────────────────────────────────────────────────────────
  //
  // Replaces the previous `Abi.current()` (`dart:ffi`) lookup so the service
  // compiles on web. Verifies the regex covers the documented Platform.version
  // shapes (single quotes, double quotes, all major OS_arch combinations) and
  // falls back to 'unknown' for malformed inputs.

  group('PlatformInfoService.parseCpuArch', () {
    test('extracts arm64 from macos with double quotes', () {
      const raw =
          '3.5.3 (stable) (Mon Sep 30 09:03:00 2024 +0000) on "macos_arm64"';
      expect(PlatformInfoService.parseCpuArch(raw), 'arm64');
    });

    test('extracts arm64 from macos with single quotes', () {
      const raw =
          "3.5.3 (stable) (Mon Sep 30 09:03:00 2024 +0000) on 'macos_arm64'";
      expect(PlatformInfoService.parseCpuArch(raw), 'arm64');
    });

    test('extracts x64 from linux', () {
      const raw =
          '3.6.0 (beta) (Tue Oct 01 00:00:00 2024 +0000) on "linux_x64"';
      expect(PlatformInfoService.parseCpuArch(raw), 'x64');
    });

    test('extracts ia32 from windows', () {
      const raw =
          '3.5.3 (stable) (Mon Sep 30 09:03:00 2024 +0000) on "windows_ia32"';
      expect(PlatformInfoService.parseCpuArch(raw), 'ia32');
    });

    test('extracts x64 from windows', () {
      const raw =
          '3.5.3 (stable) (Mon Sep 30 09:03:00 2024 +0000) on "windows_x64"';
      expect(PlatformInfoService.parseCpuArch(raw), 'x64');
    });

    test('extracts arm64 from android', () {
      const raw =
          '3.5.3 (stable) (Mon Sep 30 09:03:00 2024 +0000) on "android_arm64"';
      expect(PlatformInfoService.parseCpuArch(raw), 'arm64');
    });

    test('returns unknown for missing on-clause', () {
      expect(PlatformInfoService.parseCpuArch('3.5.3 (stable)'), 'unknown');
    });

    test('returns unknown for malformed on-clause', () {
      expect(
        PlatformInfoService.parseCpuArch('3.5.3 (stable) on macos_arm64'),
        'unknown',
      );
    });

    test('returns unknown for empty string', () {
      expect(PlatformInfoService.parseCpuArch(''), 'unknown');
    });
  });
}
