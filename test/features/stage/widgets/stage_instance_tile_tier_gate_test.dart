// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// A session restore puts back every Stage instance it saved, and the Pro
// overlay registers its widgets and their renderers at every tier: the picker
// is the only door that asks. So the tile asks the tier before it renders, and
// these tests restore a workspace naming a Pro widget the way a session saved
// during the beta would name one.

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/custom_stage_widget_registry.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/stage_instance_tile.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_renderer_registry.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/custom_stage_widget_registry_provider.dart';
import 'package:wavecrux/plugins/stage_registry.dart';

import '../../../helpers/product_telemetry_config.dart';

class _ProWidgetStub extends StageWidget {
  const _ProWidgetStub();
  @override
  String get id => 'pro_scope';
  @override
  String get displayName => 'Pro Scope';
  @override
  String get description => 'A widget sold at Pro';
  @override
  StageWidgetCategory get category => StageWidgetCategory.instrument;
  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(name: 'in', description: 'input'),
  ];
  @override
  LicenseTier get requiredTier => LicenseTier.pro;
}

/// An open-core widget definition whose custom-registry descriptor lifts it
/// to Pro, the way a vendor bundle can.
class _OpenWidgetStub extends StageWidget {
  const _OpenWidgetStub();
  @override
  String get id => 'lifted';
  @override
  String get displayName => 'Lifted';
  @override
  String get description => 'Open core by definition';
  @override
  StageWidgetCategory get category => StageWidgetCategory.custom;
  @override
  List<SignalBinding> get requiredSignals => const [];
}

const _instance = StageInstance(id: 'i0', widgetId: 'pro_scope');

const _workspace = StageWorkspaceState(
  panels: [
    StagePanelConfig(id: 'p0', name: 'P', instances: [_instance]),
  ],
  activePanelId: 'p0',
);

final Finder _rendered = find.text('pro-rendered');
final Finder _notice = find.text('“Pro Scope” requires WaveCrux Pro.');

/// Licence actions of a build that can sell.
class _SellingActions extends UnsupportedLicenseActions {
  /// One entry per purchase page opened.
  final List<void> purchasePagesOpened = [];

  @override
  bool get supportsPurchaseLinks => true;

  @override
  Future<CruxLicenseActionResult> openPurchasePage() async {
    purchasePagesOpened.add(null);
    return const LicenseActionSucceeded();
  }
}

/// A `licenseTierProvider` source a test can change after the scope is
/// built, the way a stored licence resolves after startup.
final _tier = NotifierProvider<_TierNotifier, LicenseTier>(_TierNotifier.new);

class _TierNotifier extends Notifier<LicenseTier> {
  @override
  LicenseTier build() => LicenseTier.openCore;

  LicenseTier get tier => state;
  set tier(LicenseTier value) => state = value;
}

/// Restores [_workspace] the way `SessionNotifier` does, then renders the
/// restored instance's tile.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required bool beta,
  LicenseTier? tier,
  CruxLicenseActions? actions,
  Locale locale = const Locale('en'),
}) async {
  final container = ProviderContainer(
    overrides: <Override>[
      productTelemetryConfig,
      betaPeriodProvider.overrideWithValue(beta),
      if (actions != null) licenseActionsProvider.overrideWithValue(actions),
      if (tier != null)
        licenseTierProvider.overrideWithValue(tier)
      else
        licenseTierProvider.overrideWith((ref) => ref.watch(_tier)),
    ],
  );
  addTearDown(container.dispose);
  container
      .read(stageWorkspaceProvider.notifier)
      .restoreFromSession(_workspace);
  final restored = container
      .read(stageWorkspaceProvider)
      .panels
      .single
      .instances
      .single;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              height: 180,
              child: StageInstanceTile(instance: restored),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() {
    StageRegistry.instance
      ..clear()
      ..register(const _ProWidgetStub());
    StageWidgetRendererRegistry.instance
      ..clear()
      ..register('pro_scope', (_, _) => const Text('pro-rendered'));
  });
  tearDown(() {
    StageRegistry.instance.clear();
    StageWidgetRendererRegistry.instance.clear();
  });

  group('Restored Pro Stage widget — tier gate', () {
    testWidgets('Open Core during the beta: the widget renders', (
      tester,
    ) async {
      await _pump(tester, beta: true, tier: LicenseTier.openCore);
      expect(_rendered, findsOneWidget);
      expect(_notice, findsNothing);
    });

    testWidgets('Open Core after the beta: withheld, and kept in the session', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        beta: false,
        tier: LicenseTier.openCore,
      );
      expect(_rendered, findsNothing);
      // Never silently: the tile says why, under the header that still names
      // the instance.
      expect(_notice, findsOneWidget);
      expect(find.text('Pro Scope'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Kept in the session model, so the next save writes it back.
      expect(
        container.read(stageWorkspaceProvider).panels.single.instances,
        [_instance],
      );
    });

    testWidgets('a build that can sell offers See pricing on the locked tile', (
      tester,
    ) async {
      final actions = _SellingActions();
      await _pump(
        tester,
        beta: false,
        tier: LicenseTier.openCore,
        actions: actions,
      );
      await tester.tap(find.text('See pricing'));
      await tester.pumpAndSettle();
      expect(actions.purchasePagesOpened, hasLength(1));
    });

    testWidgets('a build that cannot sell offers no dead button', (
      tester,
    ) async {
      await _pump(tester, beta: false, tier: LicenseTier.openCore);
      expect(_notice, findsOneWidget);
      expect(find.text('See pricing'), findsNothing);
    });

    testWidgets('a custom-registry tier outranks the widget definition, as '
        'in the picker', (tester) async {
      final container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWithValue(LicenseTier.openCore),
        ],
      );
      addTearDown(container.dispose);
      StageRegistry.instance.register(const _OpenWidgetStub());
      StageWidgetRendererRegistry.instance.register(
        'lifted',
        (_, _) => const Text('lifted-rendered'),
      );
      container
          .read(customStageWidgetRegistryProvider)
          .register(
            const CustomStageWidgetDescriptor(widget: _OpenWidgetStub()),
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 240,
                height: 180,
                child: StageInstanceTile(
                  instance: StageInstance(id: 'i1', widgetId: 'lifted'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('lifted-rendered'), findsNothing);
      expect(
        find.text('“Lifted” requires WaveCrux Pro.'),
        findsOneWidget,
      );
    });

    testWidgets('the locked body fits a tile shrunk to its minimum', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWithValue(LicenseTier.openCore),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 80,
                  height: 60,
                  child: StageInstanceTile(instance: _instance),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_rendered, findsNothing);
    });

    for (final tier in const [
      LicenseTier.edu,
      LicenseTier.pro,
      LicenseTier.enterprise,
    ]) {
      testWidgets('${tier.name} after the beta: the widget renders', (
        tester,
      ) async {
        await _pump(tester, beta: false, tier: tier);
        expect(_rendered, findsOneWidget);
        expect(_notice, findsNothing);
      });
    }

    testWidgets('a licence change mid-session follows, both ways', (
      tester,
    ) async {
      final container = await _pump(tester, beta: false);
      expect(_rendered, findsNothing);
      expect(_notice, findsOneWidget);

      container.read(_tier.notifier).tier = LicenseTier.pro;
      await tester.pumpAndSettle();
      expect(_rendered, findsOneWidget);
      expect(_notice, findsNothing);

      container.read(_tier.notifier).tier = LicenseTier.openCore;
      await tester.pumpAndSettle();
      expect(_rendered, findsNothing);
      expect(_notice, findsOneWidget);
    });
  });

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('the withheld state renders in $locale', (tester) async {
        await _pump(
          tester,
          beta: false,
          tier: LicenseTier.openCore,
          locale: locale,
        );
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      });
    }
  });
}
