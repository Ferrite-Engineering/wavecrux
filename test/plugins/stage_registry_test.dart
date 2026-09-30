// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/plugins/stage_registry.dart';

class _StubWidget extends StageWidget {
  const _StubWidget({
    required this.id,
    required this.displayName,
    this.category = StageWidgetCategory.primitive,
  });

  @override
  final String id;

  @override
  final String displayName;

  @override
  String get description => 'Stub widget $id';

  @override
  final StageWidgetCategory category;

  @override
  List<SignalBinding> get requiredSignals => const [];
}

class _ProTierStub extends StageWidget {
  const _ProTierStub();

  @override
  String get id => 'pro_stub';

  @override
  String get displayName => 'Pro Stub';

  @override
  String get description => 'Pro-tier stub';

  @override
  StageWidgetCategory get category => StageWidgetCategory.peripheral;

  @override
  List<SignalBinding> get requiredSignals => const [];

  @override
  LicenseTier get requiredTier => LicenseTier.pro;
}

void main() {
  final registry = StageRegistry.instance;

  setUp(registry.clear);

  group('StageRegistry', () {
    test('isRegistered returns false for unknown id', () {
      expect(registry.isRegistered('led'), isFalse);
    });

    test('register + isRegistered + get', () {
      const w = _StubWidget(id: 'led', displayName: 'LED');
      registry.register(w);
      expect(registry.isRegistered('led'), isTrue);
      expect(registry.get('led'), same(w));
    });

    test('get returns null for unknown id', () {
      expect(registry.get('missing'), isNull);
    });

    test('re-registering same id replaces the entry', () {
      registry
        ..register(const _StubWidget(id: 'led', displayName: 'LED v1'))
        ..register(const _StubWidget(id: 'led', displayName: 'LED v2'));
      expect(registry.get('led')?.displayName, 'LED v2');
      expect(registry.listAll(), hasLength(1));
    });

    test('listAll empty when nothing registered', () {
      expect(registry.listAll(), isEmpty);
    });

    test('listAll returns every registered widget', () {
      registry
        ..register(const _StubWidget(id: 'led', displayName: 'LED'))
        ..register(const _StubWidget(id: 'sevenSeg', displayName: '7-Seg'))
        ..register(const _StubWidget(id: 'gauge', displayName: 'Gauge'));
      final ids = registry.listAll().map((w) => w.id).toList();
      expect(ids, containsAll(['led', 'sevenSeg', 'gauge']));
      expect(ids, hasLength(3));
    });

    test('listAll sorts by displayName', () {
      registry
        ..register(const _StubWidget(id: 'zebra', displayName: 'Zebra'))
        ..register(const _StubWidget(id: 'alpha', displayName: 'Alpha'))
        ..register(const _StubWidget(id: 'mango', displayName: 'Mango'));
      final names = registry.listAll().map((w) => w.displayName).toList();
      expect(names, ['Alpha', 'Mango', 'Zebra']);
    });

    test('listByCategory filters then sorts', () {
      registry
        ..register(const _StubWidget(id: 'led', displayName: 'LED'))
        ..register(
          const _StubWidget(
            id: 'basys3',
            displayName: 'Basys 3',
            category: StageWidgetCategory.board,
          ),
        )
        ..register(
          const _StubWidget(
            id: 'de10',
            displayName: 'DE10-Lite',
            category: StageWidgetCategory.board,
          ),
        );
      final boards = registry.listByCategory(StageWidgetCategory.board);
      expect(boards.map((w) => w.id).toList(), ['basys3', 'de10']);
      expect(
        registry.listByCategory(StageWidgetCategory.primitive),
        hasLength(1),
      );
      expect(
        registry.listByCategory(StageWidgetCategory.protocol),
        isEmpty,
      );
    });

    test('unregister removes a single registration', () {
      registry
        ..register(const _StubWidget(id: 'led', displayName: 'LED'))
        ..register(const _StubWidget(id: 'gauge', displayName: 'Gauge'))
        ..unregister('led');
      expect(registry.isRegistered('led'), isFalse);
      expect(registry.isRegistered('gauge'), isTrue);
      expect(registry.listAll(), hasLength(1));
    });

    test('unregister is a no-op for an unknown id', () {
      registry
        ..register(const _StubWidget(id: 'led', displayName: 'LED'))
        ..unregister('missing');
      expect(registry.isRegistered('led'), isTrue);
      expect(registry.listAll(), hasLength(1));
    });

    test('clear removes all registrations', () {
      registry
        ..register(const _StubWidget(id: 'led', displayName: 'LED'))
        ..clear();
      expect(registry.isRegistered('led'), isFalse);
      expect(registry.listAll(), isEmpty);
    });
  });

  group('StageWidget.requiredTier', () {
    test('default is LicenseTier.openCore', () {
      const w = _StubWidget(id: 'led', displayName: 'LED');
      expect(w.requiredTier, LicenseTier.openCore);
    });

    test('subclasses can override to declare a higher required tier', () {
      const w = _ProTierStub();
      expect(w.requiredTier, LicenseTier.pro);
    });

    test('registry round-trips the requiredTier override', () {
      registry.register(const _ProTierStub());
      expect(registry.get('pro_stub')?.requiredTier, LicenseTier.pro);
    });
  });
}
