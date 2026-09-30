// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/providers/stage_config_label_resolver_provider.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_config_editor.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

void main() {
  group('stageConfigLabelResolverFactoryProvider', () {
    test('default factory falls through to identity for unknown keys', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final factory = container.read(stageConfigLabelResolverFactoryProvider);
      // The default factory is lazy: it only resolves `L10N.of(context)`
      // when the key matches one of its known labels. Pro pack keys
      // (characterLcd*, audioWaveform*, …) are unknown to open-core and
      // fall through to identity, which doesn't touch the context — so a
      // synthetic `_FakeContext` is sufficient here. The open-core
      // Tachometer config labels (tachometerGroupRange, …) are resolved
      // via `L10N` and are exercised in a widget test that mounts a
      // real `MaterialApp`.
      final resolver = factory(_FakeContext());

      expect(
        resolver('characterLcdParamGeometry'),
        'characterLcdParamGeometry',
      );
      expect(
        resolver('audioWaveformGroupDisplay'),
        'audioWaveformGroupDisplay',
      );
      expect(resolver(''), '');
    });

    test('overlay can override the factory (Pro substitution path)', () {
      ConfigLabelResolver proFactory(BuildContext _) =>
          (key) => key == 'characterLcdParamGeometry' ? 'Geometry' : key;

      final container = ProviderContainer(
        overrides: [
          stageConfigLabelResolverFactoryProvider.overrideWithValue(proFactory),
        ],
      );
      addTearDown(container.dispose);

      final factory = container.read(stageConfigLabelResolverFactoryProvider);
      final resolver = factory(_FakeContext());

      expect(resolver('characterLcdParamGeometry'), 'Geometry');
      expect(resolver('unknownKey'), 'unknownKey');
    });
  });

  group('openCoreStageConfigLabelResolver', () {
    // Mounts a real MaterialApp so `L10N.of(context)` resolves. This is
    // the seam the Pro overlay chains to for any key its own catalog
    // doesn't recognise — the regression it guards against is the Pro
    // override falling back to the raw key (e.g. rendering the literal
    // "stageTachometerDisplayName") for every open-core Stage label.
    testWidgets('resolves open-core widget display-name + config keys', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final resolver = openCoreStageConfigLabelResolver(ctx);
      final l10n = L10N.of(ctx);

      // Open-core Stage widget display names (resolved via `displayNameKey`
      // at the picker / bindings-pane / instance-tile render sites).
      expect(
        resolver('stageTachometerDisplayName'),
        l10n.stageTachometerDisplayName,
      );
      expect(
        resolver('stageLevelBarDisplayName'),
        l10n.stageLevelBarDisplayName,
      );
      expect(
        resolver('stageSignalGraphDisplayName'),
        l10n.stageSignalGraphDisplayName,
      );
      // Open-core Tachometer per-instance config labels.
      expect(resolver('tachometerParamMinRpm'), l10n.tachometerParamMinRpm);
      expect(resolver('tachometerGroupRange'), l10n.tachometerGroupRange);
    });

    testWidgets('returns the raw key for keys it does not recognise', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final resolver = openCoreStageConfigLabelResolver(ctx);
      // A Pro pack key open-core knows nothing about → identity fallback,
      // so a chaining Pro override can detect "no open-core match" too.
      expect(
        resolver('characterLcdParamGeometry'),
        'characterLcdParamGeometry',
      );
    });
  });
}

/// `BuildContext` is abstract; the open-core default factory ignores it,
/// so a stand-in implementation is sufficient for the identity test.
class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
