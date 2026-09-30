// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/custom_stage_widget_registry.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/features/stage/runtime/live_custom_stage_widget_registry.dart';
import 'package:wavecrux/plugins/custom_stage_widget_registry_provider.dart';

class _FakeStageWidget extends StageWidget {
  const _FakeStageWidget(this.id, this.displayName);

  @override
  final String id;
  @override
  final String displayName;
  @override
  String get description => 'fake';
  @override
  StageWidgetCategory get category => StageWidgetCategory.custom;
  @override
  List<SignalBinding> get requiredSignals => const [];
}

/// In-memory test registry mimicking the shape of the Pro overlay's
/// `LiveCustomStageWidgetRegistry`. Living in a test file keeps the
/// open-core seam free of implementation cost.
class _InMemoryRegistry implements CustomStageWidgetRegistry {
  final Map<String, CustomStageWidgetDescriptor> _byId = {};

  @override
  void register(CustomStageWidgetDescriptor descriptor) {
    _byId[descriptor.id] = descriptor;
  }

  @override
  void unregister(String id) {
    _byId.remove(id);
  }

  @override
  CustomStageWidgetDescriptor? get(String id) => _byId[id];

  @override
  Iterable<CustomStageWidgetDescriptor> get descriptors =>
      List.unmodifiable(_byId.values);
}

void main() {
  group('customStageWidgetRegistryProvider', () {
    test('open-core default is a LiveCustomStageWidgetRegistry', () {
      // The Stage widget SDK is part of open-core (the *capability* to build
      // and load custom widgets is free; only the curated Pro widget pack
      // lives in the Pro overlay). The provider's default has to be a real,
      // mutable registry so the open-core bundle loader has somewhere to
      // register descriptors discovered at startup.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final registry = container.read(customStageWidgetRegistryProvider);
      expect(registry, isA<LiveCustomStageWidgetRegistry>());
      expect(registry.descriptors, isEmpty);
    });

    test('open-core default accepts register / unregister', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final registry = container.read(customStageWidgetRegistryProvider)
        ..register(
          const CustomStageWidgetDescriptor(
            widget: _FakeStageWidget('foo', 'Foo'),
          ),
        );
      expect(registry.descriptors, hasLength(1));
      registry.unregister('foo');
      expect(registry.descriptors, isEmpty);
    });

    test('overlay override surfaces a live, mutable registry', () {
      final live = _InMemoryRegistry();
      final container = ProviderContainer(
        overrides: [
          customStageWidgetRegistryProvider.overrideWithValue(live),
        ],
      );
      addTearDown(container.dispose);

      final registry = container.read(customStageWidgetRegistryProvider);
      expect(registry, same(live));

      registry.register(
        const CustomStageWidgetDescriptor(
          widget: _FakeStageWidget('foo', 'Foo'),
        ),
      );
      expect(registry.descriptors, hasLength(1));
      expect(registry.get('foo')?.requiredTier, LicenseTier.pro);

      registry.unregister('foo');
      expect(registry.descriptors, isEmpty);
    });

    test('register replaces existing descriptor with the same id', () {
      final live = _InMemoryRegistry();
      final container = ProviderContainer(
        overrides: [
          customStageWidgetRegistryProvider.overrideWithValue(live),
        ],
      );
      addTearDown(container.dispose);

      final registry = container.read(customStageWidgetRegistryProvider)
        ..register(
          const CustomStageWidgetDescriptor(
            widget: _FakeStageWidget('foo', 'Foo v1'),
          ),
        )
        ..register(
          const CustomStageWidgetDescriptor(
            widget: _FakeStageWidget('foo', 'Foo v2'),
            bundleVersion: '2.0.0',
          ),
        );

      expect(registry.descriptors, hasLength(1));
      expect(registry.get('foo')?.widget.displayName, 'Foo v2');
      expect(registry.get('foo')?.bundleVersion, '2.0.0');
    });
  });
}
