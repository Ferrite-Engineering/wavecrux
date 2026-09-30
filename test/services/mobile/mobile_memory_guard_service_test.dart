// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/memory_stats.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/services/mobile/mobile_memory_guard_service.dart';

const DeviceClass _phone = DeviceClass.phone;
const DeviceClass _phoneLandscape = DeviceClass.phoneLandscape;
const DeviceClass _tablet = DeviceClass.tablet;
const DeviceClass _desktop = DeviceClass.desktop;

const int _mb = 1024 * 1024;

MemoryStats _stats(int rssBytes) => MemoryStats(
  dartProcessRssBytes: rssBytes,
  wellenEstimateBytes: 0,
  loadedSignalCount: 0,
  totalSignalCount: 0,
);

void main() {
  const service = MobileMemoryGuardService();

  // ── fileSizeThresholdBytes ────────────────────────────────────────────────

  group('fileSizeThresholdBytes', () {
    test('phone returns 100 MB', () {
      expect(service.fileSizeThresholdBytes(_phone), 100 * _mb);
    });

    test('phoneLandscape returns 100 MB', () {
      expect(service.fileSizeThresholdBytes(_phoneLandscape), 100 * _mb);
    });

    test('tablet returns 250 MB', () {
      expect(service.fileSizeThresholdBytes(_tablet), 250 * _mb);
    });

    test('desktop returns null (no limit)', () {
      expect(service.fileSizeThresholdBytes(_desktop), isNull);
    });
  });

  // ── shouldWarnBeforeLoad ──────────────────────────────────────────────────

  group('shouldWarnBeforeLoad', () {
    test('returns false on desktop regardless of size', () {
      expect(
        service.shouldWarnBeforeLoad(500 * _mb, _desktop),
        isFalse,
      );
    });

    test('returns false when file is exactly at phone threshold', () {
      expect(
        service.shouldWarnBeforeLoad(100 * _mb, _phone),
        isFalse,
      );
    });

    test('returns true when file exceeds phone threshold', () {
      expect(
        service.shouldWarnBeforeLoad(100 * _mb + 1, _phone),
        isTrue,
      );
    });

    test('returns false when file is below tablet threshold', () {
      expect(
        service.shouldWarnBeforeLoad(249 * _mb, _tablet),
        isFalse,
      );
    });

    test('returns true when file exceeds tablet threshold', () {
      expect(
        service.shouldWarnBeforeLoad(251 * _mb, _tablet),
        isTrue,
      );
    });

    test('phoneLandscape uses same threshold as phone', () {
      expect(
        service.shouldWarnBeforeLoad(101 * _mb, _phoneLandscape),
        isTrue,
      );
    });
  });

  // ── rssWarningThresholdBytes / rssCriticalThresholdBytes ──────────────────

  group('rssWarningThresholdBytes', () {
    test('phone returns 300 MB', () {
      expect(service.rssWarningThresholdBytes(_phone), 300 * _mb);
    });

    test('phoneLandscape returns 300 MB', () {
      expect(service.rssWarningThresholdBytes(_phoneLandscape), 300 * _mb);
    });

    test('tablet returns 600 MB', () {
      expect(service.rssWarningThresholdBytes(_tablet), 600 * _mb);
    });

    test('desktop returns null', () {
      expect(service.rssWarningThresholdBytes(_desktop), isNull);
    });
  });

  group('rssCriticalThresholdBytes', () {
    test('phone returns 500 MB', () {
      expect(service.rssCriticalThresholdBytes(_phone), 500 * _mb);
    });

    test('tablet returns 1000 MB', () {
      expect(service.rssCriticalThresholdBytes(_tablet), 1000 * _mb);
    });

    test('desktop returns null', () {
      expect(service.rssCriticalThresholdBytes(_desktop), isNull);
    });
  });

  // ── assessPressure ────────────────────────────────────────────────────────

  group('assessPressure', () {
    test('desktop always returns ok', () {
      expect(
        service.assessPressure(_stats(999 * _mb), _desktop),
        MemoryPressureLevel.ok,
      );
    });

    test('phone: ok when below warning threshold', () {
      expect(
        service.assessPressure(_stats(299 * _mb), _phone),
        MemoryPressureLevel.ok,
      );
    });

    test('phone: warning when at warning threshold', () {
      expect(
        service.assessPressure(_stats(300 * _mb), _phone),
        MemoryPressureLevel.warning,
      );
    });

    test('phone: warning between warning and critical', () {
      expect(
        service.assessPressure(_stats(400 * _mb), _phone),
        MemoryPressureLevel.warning,
      );
    });

    test('phone: critical when at critical threshold', () {
      expect(
        service.assessPressure(_stats(500 * _mb), _phone),
        MemoryPressureLevel.critical,
      );
    });

    test('phone: critical above critical threshold', () {
      expect(
        service.assessPressure(_stats(700 * _mb), _phone),
        MemoryPressureLevel.critical,
      );
    });

    test('tablet: ok when below 600 MB', () {
      expect(
        service.assessPressure(_stats(599 * _mb), _tablet),
        MemoryPressureLevel.ok,
      );
    });

    test('tablet: warning at 600 MB', () {
      expect(
        service.assessPressure(_stats(600 * _mb), _tablet),
        MemoryPressureLevel.warning,
      );
    });

    test('tablet: critical at 1000 MB', () {
      expect(
        service.assessPressure(_stats(1000 * _mb), _tablet),
        MemoryPressureLevel.critical,
      );
    });

    test('phoneLandscape uses phone thresholds', () {
      expect(
        service.assessPressure(_stats(500 * _mb), _phoneLandscape),
        MemoryPressureLevel.critical,
      );
    });
  });

  // ── visibleSignalRefs ─────────────────────────────────────────────────────

  group('visibleSignalRefs', () {
    test('empty group returns empty set', () {
      expect(service.visibleSignalRefs(const SignalGroup()), isEmpty);
    });

    test('flat signal entries are collected', () {
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: 'a', displayName: 'a'),
          SignalEntry.signal(signalRef: 'b', displayName: 'b'),
        ],
      );
      expect(service.visibleSignalRefs(group), {'a', 'b'});
    });

    test('signals inside groups are collected recursively', () {
      final group = SignalGroup(
        entries: [
          SignalEntry.group(
            groupName: 'g',
            children: [
              SignalEntry.signal(signalRef: 'c', displayName: 'c'),
            ],
          ),
        ],
      );
      expect(service.visibleSignalRefs(group), {'c'});
    });

    test('separators and comments are ignored', () {
      final group = SignalGroup(
        entries: [
          const SignalEntry.separator(),
          const SignalEntry.comment(text: 'note'),
          SignalEntry.signal(signalRef: 'd', displayName: 'd'),
        ],
      );
      expect(service.visibleSignalRefs(group), {'d'});
    });

    test('nested groups are traversed even when collapsed', () {
      final group = SignalGroup(
        entries: [
          SignalEntry.group(
            groupName: 'outer',
            collapsed: true,
            children: [
              SignalEntry.group(
                groupName: 'inner',
                children: [
                  SignalEntry.signal(signalRef: 'e', displayName: 'e'),
                ],
              ),
            ],
          ),
        ],
      );
      expect(service.visibleSignalRefs(group), {'e'});
    });

    test('custom thresholds are respected', () {
      const custom = MobileMemoryGuardService(
        phoneFileSizeLimitBytes: 50 * 1024 * 1024,
        tabletFileSizeLimitBytes: 200 * 1024 * 1024,
        phoneRssWarningBytes: 200 * 1024 * 1024,
        phoneRssCriticalBytes: 400 * 1024 * 1024,
        tabletRssWarningBytes: 500 * 1024 * 1024,
        tabletRssCriticalBytes: 800 * 1024 * 1024,
      );
      expect(custom.fileSizeThresholdBytes(_phone), 50 * _mb);
      expect(custom.shouldWarnBeforeLoad(51 * _mb, _phone), isTrue);
      expect(
        custom.assessPressure(_stats(200 * _mb), _phone),
        MemoryPressureLevel.warning,
      );
      expect(
        custom.assessPressure(_stats(400 * _mb), _phone),
        MemoryPressureLevel.critical,
      );
    });
  });
}
