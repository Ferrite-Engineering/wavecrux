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

class _StubWidget extends StageWidget {
  const _StubWidget(this.id, this.displayName);

  @override
  final String id;
  @override
  final String displayName;
  @override
  String get description => 'stub';
  @override
  StageWidgetCategory get category => StageWidgetCategory.custom;
  @override
  List<SignalBinding> get requiredSignals => const [];
}

void main() {
  group('LiveCustomStageWidgetRegistry', () {
    test('starts empty', () {
      final registry = LiveCustomStageWidgetRegistry();
      expect(registry.descriptors, isEmpty);
      expect(registry.get('foo'), isNull);
    });

    test('register adds a descriptor and round-trips through get', () {
      final registry = LiveCustomStageWidgetRegistry();
      const descriptor = CustomStageWidgetDescriptor(
        widget: _StubWidget('foo', 'Foo'),
      );
      registry.register(descriptor);

      expect(registry.descriptors, hasLength(1));
      expect(registry.get('foo'), same(descriptor));
      expect(registry.get('foo')?.requiredTier, LicenseTier.pro);
    });

    test('register replaces an existing descriptor with the same id', () {
      final registry = LiveCustomStageWidgetRegistry()
        ..register(
          const CustomStageWidgetDescriptor(
            widget: _StubWidget('foo', 'Foo v1'),
          ),
        )
        ..register(
          const CustomStageWidgetDescriptor(
            widget: _StubWidget('foo', 'Foo v2'),
            bundleVersion: '2.0.0',
          ),
        );

      expect(registry.descriptors, hasLength(1));
      expect(registry.get('foo')?.widget.displayName, 'Foo v2');
      expect(registry.get('foo')?.bundleVersion, '2.0.0');
    });

    test('unregister removes the descriptor; idempotent on unknown ids', () {
      final registry = LiveCustomStageWidgetRegistry()
        ..register(
          const CustomStageWidgetDescriptor(
            widget: _StubWidget('foo', 'Foo'),
          ),
        );
      expect(registry.descriptors, hasLength(1));

      registry.unregister('foo');
      expect(registry.descriptors, isEmpty);
      expect(registry.get('foo'), isNull);

      // Unregistering an unknown id is a no-op, not an error.
      expect(() => registry.unregister('does-not-exist'), returnsNormally);
    });

    test('descriptors view is unmodifiable', () {
      final registry = LiveCustomStageWidgetRegistry()
        ..register(
          const CustomStageWidgetDescriptor(
            widget: _StubWidget('foo', 'Foo'),
          ),
        );

      final descriptors = registry.descriptors;
      expect(
        () => (descriptors as List<CustomStageWidgetDescriptor>).clear(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('descriptors view tracks subsequent register / unregister calls '
        '(not a frozen snapshot)', () {
      final registry = LiveCustomStageWidgetRegistry();
      final descriptors = registry.descriptors;
      expect(descriptors, isEmpty);

      registry.register(
        const CustomStageWidgetDescriptor(
          widget: _StubWidget('foo', 'Foo'),
        ),
      );
      expect(descriptors, hasLength(1));

      registry.unregister('foo');
      expect(descriptors, isEmpty);
    });

    test('works as the value behind customStageWidgetRegistryProvider — '
        'ProviderContainer round-trip', () {
      final live = LiveCustomStageWidgetRegistry();
      final container = ProviderContainer(
        overrides: [
          customStageWidgetRegistryProvider.overrideWithValue(live),
        ],
      );
      addTearDown(container.dispose);

      final fromProvider = container.read(customStageWidgetRegistryProvider);
      expect(fromProvider, same(live));

      fromProvider.register(
        const CustomStageWidgetDescriptor(
          widget: _StubWidget('foo', 'Foo'),
        ),
      );
      expect(
        container.read(customStageWidgetRegistryProvider).descriptors,
        hasLength(1),
      );
    });
  });
}
