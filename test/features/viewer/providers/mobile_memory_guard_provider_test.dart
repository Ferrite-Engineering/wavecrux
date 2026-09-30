// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/providers/mobile_memory_guard_provider.dart';
import 'package:wavecrux/services/mobile/mobile_memory_guard_service.dart';

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  // ── MemoryGuardState ──────────────────────────────────────────────────────

  group('MemoryGuardState', () {
    test('default values', () {
      const s = MemoryGuardState();
      expect(s.pressureLevel, MemoryPressureLevel.ok);
      expect(s.lastUnloadedCount, 0);
      expect(s.osMemoryPressureReceived, isFalse);
    });

    test('copyWith replaces individual fields', () {
      const s = MemoryGuardState();
      final s2 = s.copyWith(
        pressureLevel: MemoryPressureLevel.warning,
        lastUnloadedCount: 3,
      );
      expect(s2.pressureLevel, MemoryPressureLevel.warning);
      expect(s2.lastUnloadedCount, 3);
      expect(s2.osMemoryPressureReceived, isFalse);
    });

    test('copyWith with osMemoryPressureReceived', () {
      const s = MemoryGuardState();
      final s2 = s.copyWith(osMemoryPressureReceived: true);
      expect(s2.osMemoryPressureReceived, isTrue);
    });

    test('equality: identical fields are equal', () {
      const a = MemoryGuardState(
        pressureLevel: MemoryPressureLevel.warning,
        lastUnloadedCount: 5,
      );
      const b = MemoryGuardState(
        pressureLevel: MemoryPressureLevel.warning,
        lastUnloadedCount: 5,
      );
      expect(a, b);
    });

    test('equality: different pressureLevel is not equal', () {
      const a = MemoryGuardState();
      const b = MemoryGuardState(pressureLevel: MemoryPressureLevel.warning);
      expect(a, isNot(b));
    });

    test('equality: different lastUnloadedCount is not equal', () {
      const a = MemoryGuardState();
      const b = MemoryGuardState(lastUnloadedCount: 1);
      expect(a, isNot(b));
    });

    test('equality: different osMemoryPressureReceived is not equal', () {
      const a = MemoryGuardState();
      const b = MemoryGuardState(osMemoryPressureReceived: true);
      expect(a, isNot(b));
    });

    test('hashCode is consistent for equal states', () {
      const a = MemoryGuardState(
        pressureLevel: MemoryPressureLevel.critical,
        lastUnloadedCount: 2,
      );
      const b = MemoryGuardState(
        pressureLevel: MemoryPressureLevel.critical,
        lastUnloadedCount: 2,
      );
      expect(a.hashCode, b.hashCode);
    });

    test('toString contains field values', () {
      const s = MemoryGuardState(
        pressureLevel: MemoryPressureLevel.warning,
        lastUnloadedCount: 7,
        osMemoryPressureReceived: true,
      );
      final str = s.toString();
      expect(str, contains('warning'));
      expect(str, contains('7'));
      expect(str, contains('true'));
    });
  });

  // ── MemoryPressureLevel enum ──────────────────────────────────────────────

  group('MemoryPressureLevel', () {
    test('has three values', () {
      expect(MemoryPressureLevel.values.length, 3);
    });

    test('ordering: ok < warning < critical', () {
      expect(
        MemoryPressureLevel.ok.index < MemoryPressureLevel.warning.index,
        isTrue,
      );
      expect(
        MemoryPressureLevel.warning.index < MemoryPressureLevel.critical.index,
        isTrue,
      );
    });
  });

  // ── Provider initialises to default state ─────────────────────────────────

  group('mobileMemoryGuardProvider', () {
    test('initial state has ok pressure level', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(mobileMemoryGuardProvider);
      expect(state.pressureLevel, MemoryPressureLevel.ok);
      expect(state.lastUnloadedCount, 0);
      expect(state.osMemoryPressureReceived, isFalse);
    });
  });
}
