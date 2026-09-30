// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/custom_stage_widget_registry.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';

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

void main() {
  group('CustomStageWidgetDescriptor', () {
    test('defaults requiredTier to Pro and exposes underlying widget id', () {
      const widget = _FakeStageWidget('foo', 'Foo');
      const descriptor = CustomStageWidgetDescriptor(widget: widget);

      expect(descriptor.id, 'foo');
      expect(descriptor.requiredTier, LicenseTier.pro);
      expect(descriptor.bundleId, isNull);
      expect(descriptor.bundleVersion, isNull);
    });

    test('copyWith replaces only the supplied fields', () {
      const widget = _FakeStageWidget('foo', 'Foo');
      const a = CustomStageWidgetDescriptor(
        widget: widget,
        bundleId: 'bundle.alpha',
        bundleVersion: '1.0.0',
      );

      final b = a.copyWith(requiredTier: LicenseTier.enterprise);
      expect(b.widget, widget);
      expect(b.requiredTier, LicenseTier.enterprise);
      expect(b.bundleId, 'bundle.alpha');
      expect(b.bundleVersion, '1.0.0');
    });

    test('equality compares all four fields', () {
      const w = _FakeStageWidget('foo', 'Foo');
      const a = CustomStageWidgetDescriptor(widget: w);
      const b = CustomStageWidgetDescriptor(widget: w);
      const c = CustomStageWidgetDescriptor(
        widget: w,
        requiredTier: LicenseTier.enterprise,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString includes id, tier, and bundle id', () {
      const a = CustomStageWidgetDescriptor(
        widget: _FakeStageWidget('foo', 'Foo'),
        bundleId: 'bundle.alpha',
      );
      final s = a.toString();
      expect(s, contains('foo'));
      expect(s, contains('LicenseTier.pro'));
      expect(s, contains('bundle.alpha'));
    });
  });
}
