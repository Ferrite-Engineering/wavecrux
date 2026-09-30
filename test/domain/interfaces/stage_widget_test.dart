// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/compound_stage_widget.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_widget_slot.dart';

// ── stub implementations for testing the interface contract ──────────────────

class _FakeLed extends StageWidget {
  const _FakeLed();

  @override
  String get id => 'led';

  @override
  String get displayName => 'LED';

  @override
  String get description => 'A single 1-bit indicator.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;

  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(name: 'in', description: '1-bit input', bitWidth: 1),
  ];
}

/// Stage widget that asserts a finite [maxSize] ceiling — exercises the
/// override path that the Stage panel's resize handles use to clamp.
class _BoundedLed extends StageWidget {
  const _BoundedLed();

  @override
  String get id => 'bounded_led';

  @override
  String get displayName => 'Bounded LED';

  @override
  String get description => 'LED that caps out at 200x200.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;

  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(name: 'in', description: '1-bit input', bitWidth: 1),
  ];

  @override
  (double, double)? get maxSize => (200, 200);
}

class _FakeBoard extends CompoundStageWidget {
  const _FakeBoard();

  @override
  String get id => 'fakeBoard';

  @override
  String get displayName => 'Fake Board';

  @override
  String get description => 'Board with two LEDs and one switch.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.board;

  @override
  List<StageWidgetSlot> get slots => const [
    StageWidgetSlot(
      name: 'led0',
      childWidgetId: 'led',
      x: 0.1,
      y: 0.1,
      width: 0.05,
      height: 0.05,
      label: 'LD0',
    ),
    StageWidgetSlot(
      name: 'led1',
      childWidgetId: 'led',
      x: 0.2,
      y: 0.1,
      width: 0.05,
      height: 0.05,
    ),
    StageWidgetSlot(
      name: 'sw0',
      childWidgetId: 'switch',
      x: 0.1,
      y: 0.5,
      width: 0.05,
      height: 0.1,
    ),
  ];
}

void main() {
  group('StageWidget (primitive)', () {
    test('exposes identity and category', () {
      const w = _FakeLed();
      expect(w.id, 'led');
      expect(w.displayName, 'LED');
      expect(w.description, isNotEmpty);
      expect(w.category, StageWidgetCategory.primitive);
    });

    test('isCompound defaults to false', () {
      expect(const _FakeLed().isCompound, isFalse);
    });

    test('requiredSignals are exposed verbatim', () {
      const w = _FakeLed();
      expect(w.requiredSignals, hasLength(1));
      expect(w.requiredSignals.first.name, 'in');
      expect(w.requiredSignals.first.bitWidth, 1);
    });

    test('optionalSignals defaults to empty', () {
      expect(const _FakeLed().optionalSignals, isEmpty);
    });

    test('defaultSize falls back to (160, 100)', () {
      const w = _FakeLed();
      final (width, height) = w.defaultSize;
      expect(width, 160);
      expect(height, 100);
    });

    test('minSize falls back to (80, 60)', () {
      const w = _FakeLed();
      final (width, height) = w.minSize;
      expect(width, 80);
      expect(height, 60);
    });

    test('maxSize defaults to null (unbounded)', () {
      const w = _FakeLed();
      expect(w.maxSize, isNull);
    });

    test('maxSize override returns the declared ceiling', () {
      const w = _BoundedLed();
      expect(w.maxSize, isNotNull);
      final (width, height) = w.maxSize!;
      expect(width, 200);
      expect(height, 200);
    });
  });

  group('CompoundStageWidget', () {
    test('isCompound is true', () {
      expect(const _FakeBoard().isCompound, isTrue);
    });

    test('default requiredSignals derived from slots', () {
      const w = _FakeBoard();
      expect(w.requiredSignals, hasLength(3));
      final names = w.requiredSignals.map((b) => b.name).toList();
      expect(names, ['led0', 'led1', 'sw0']);
    });

    test('binding description falls back to slot name when label is null', () {
      const w = _FakeBoard();
      final led1 = w.requiredSignals.firstWhere((b) => b.name == 'led1');
      expect(led1.description, 'led1');
    });

    test('binding description uses slot label when present', () {
      const w = _FakeBoard();
      final led0 = w.requiredSignals.firstWhere((b) => b.name == 'led0');
      expect(led0.description, 'LD0');
    });

    test('slots maintain insertion order', () {
      const w = _FakeBoard();
      expect(w.slots.map((s) => s.name).toList(), ['led0', 'led1', 'sw0']);
    });

    test('category reports board', () {
      expect(const _FakeBoard().category, StageWidgetCategory.board);
    });
  });
}
