// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/custom_stage_widget_registry.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_picker_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/custom_stage_widget_registry_provider.dart';
import 'package:wavecrux/plugins/stage_registry.dart';
import 'package:wavecrux/shared/widgets/wavecrux_feature_tier_badge.dart';

import '../../../helpers/product_telemetry_config.dart';

/// Captures recorded events for the telemetry assertions below.
class _RecordingTelemetry implements TelemetryService {
  final events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);

  List<TelemetryEvent> named(String name) =>
      events.where((e) => e.name == name).toList();
}

class _StubWidget extends StageWidget {
  const _StubWidget({
    required this.id,
    required this.displayName,
    this.category = StageWidgetCategory.primitive,
    this.tier = LicenseTier.openCore,
  });
  @override
  final String id;
  @override
  final String displayName;
  @override
  String get description => 'Stub $id';
  @override
  final StageWidgetCategory category;
  @override
  List<SignalBinding> get requiredSignals => const [];
  @override
  LicenseTier get requiredTier => tier;

  final LicenseTier tier;
}

Widget _wrap(
  Widget child, {
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [productTelemetryConfig, ...overrides],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: child),
  ),
);

/// Taps every `ExpansionTile` in the picker once to open it. Categories
/// now default to collapsed so tests that assert on individual widget
/// rows (display name, FeatureTierBadge inside a row, tap-to-add) must call
/// this after pumping the dialog.
///
/// After each tap the just-expanded section's children push later
/// sections below the dialog's 360 dp fold; [scrollUntilVisible] brings
/// the next section back into the visible region of the dialog's
/// [SingleChildScrollView] before tapping it.
Future<void> _expandAllSections(WidgetTester tester) async {
  final keys = <Key>[
    for (final tile in tester.widgetList<ExpansionTile>(
      find.byType(ExpansionTile),
    ))
      if (tile.key != null) tile.key!,
  ];
  final scrollable = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(Scrollable),
  );
  for (final key in keys) {
    final finder = find.byKey(key);
    if (scrollable.evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(finder, 80, scrollable: scrollable);
    }
    await tester.tap(finder, warnIfMissed: false);
    await tester.pumpAndSettle();
  }
}

class _MutableCustomStageRegistry implements CustomStageWidgetRegistry {
  final Map<String, CustomStageWidgetDescriptor> _byId = {};

  @override
  void register(CustomStageWidgetDescriptor descriptor) =>
      _byId[descriptor.id] = descriptor;

  @override
  void unregister(String id) => _byId.remove(id);

  @override
  CustomStageWidgetDescriptor? get(String id) => _byId[id];

  @override
  Iterable<CustomStageWidgetDescriptor> get descriptors =>
      List.unmodifiable(_byId.values);
}

void main() {
  setUp(StageRegistry.instance.clear);
  tearDown(StageRegistry.instance.clear);

  group('StageWidgetPickerDialog — locale sweep', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        StageRegistry.instance.register(
          const _StubWidget(id: 'led', displayName: 'LED'),
        );
        await tester.pumpWidget(
          _wrap(const StageWidgetPickerDialog(), locale: Locale(locale)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('StageWidgetPickerDialog', () {
    testWidgets('shows empty state when no widgets registered', (tester) async {
      await tester.pumpWidget(_wrap(const StageWidgetPickerDialog()));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No Stage widgets are registered'),
        findsOneWidget,
      );
    });

    testWidgets('lists every registered widget by display name', (
      tester,
    ) async {
      StageRegistry.instance
        ..register(const _StubWidget(id: 'led', displayName: 'LED'))
        ..register(
          const _StubWidget(
            id: 'b3',
            displayName: 'Basys 3',
            category: StageWidgetCategory.board,
          ),
        );
      await tester.pumpWidget(_wrap(const StageWidgetPickerDialog()));
      await tester.pumpAndSettle();
      await _expandAllSections(tester);
      // Both widgets render under their respective ExpansionTile sections
      // once the user opens them.
      expect(find.text('LED'), findsOneWidget);
      expect(find.text('Basys 3'), findsOneWidget);
    });

    testWidgets('tapping a widget adds an instance to the active panel', (
      tester,
    ) async {
      StageRegistry.instance.register(
        const _StubWidget(id: 'led', displayName: 'LED'),
      );
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [productTelemetryConfig],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return Scaffold(
                  body: TextButton(
                    onPressed: () => StageWidgetPickerDialog.show(context),
                    child: const Text('open'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Need an active panel before adding instances.
      container.read(stageWorkspaceProvider.notifier).addPanel('A');
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _expandAllSections(tester);

      await tester.tap(find.text('LED'));
      await tester.pumpAndSettle();

      final state = container.read(stageWorkspaceProvider);
      expect(state.panels.first.instances, hasLength(1));
      expect(state.panels.first.instances.first.widgetId, 'led');
    });
  });

  group('StageWidgetPickerDialog — category grouping', () {
    testWidgets('renders one ExpansionTile per populated category', (
      tester,
    ) async {
      StageRegistry.instance
        ..register(const _StubWidget(id: 'led', displayName: 'LED'))
        ..register(
          const _StubWidget(
            id: 'b3',
            displayName: 'Basys 3',
            category: StageWidgetCategory.board,
          ),
        )
        ..register(
          const _StubWidget(
            id: 'fb',
            displayName: 'Framebuffer',
            category: StageWidgetCategory.peripheral,
          ),
        );
      await tester.pumpWidget(_wrap(const StageWidgetPickerDialog()));
      await tester.pumpAndSettle();
      // Three populated categories → three ExpansionTiles.
      expect(find.byType(ExpansionTile), findsNWidgets(3));
    });

    testWidgets('renders the localized category label in section header', (
      tester,
    ) async {
      StageRegistry.instance.register(
        const _StubWidget(id: 'led', displayName: 'LED'),
      );
      await tester.pumpWidget(_wrap(const StageWidgetPickerDialog()));
      await tester.pumpAndSettle();
      final l10n = L10N.of(
        tester.element(find.byType(StageWidgetPickerDialog)),
      );
      // Header is "Primitive (1)" via pickerCategoryHeader format.
      final expected = l10n.pickerCategoryHeader(
        l10n.stageCategoryPrimitive,
        1,
      );
      expect(find.text(expected), findsOneWidget);
    });

    testWidgets('renders the new peripheral category section', (tester) async {
      StageRegistry.instance.register(
        const _StubWidget(
          id: 'audio',
          displayName: 'Audio Waveform',
          category: StageWidgetCategory.peripheral,
        ),
      );
      await tester.pumpWidget(_wrap(const StageWidgetPickerDialog()));
      await tester.pumpAndSettle();
      final l10n = L10N.of(
        tester.element(find.byType(StageWidgetPickerDialog)),
      );
      final expected = l10n.pickerCategoryHeader(
        l10n.stageCategoryPeripheral,
        1,
      );
      expect(find.text(expected), findsOneWidget);
    });

    testWidgets('omits empty categories', (tester) async {
      StageRegistry.instance.register(
        const _StubWidget(id: 'led', displayName: 'LED'),
      );
      await tester.pumpWidget(_wrap(const StageWidgetPickerDialog()));
      await tester.pumpAndSettle();
      final l10n = L10N.of(
        tester.element(find.byType(StageWidgetPickerDialog)),
      );
      // Other category labels do NOT appear in the header.
      expect(find.text(l10n.stageCategoryBoard), findsNothing);
      expect(find.text(l10n.stageCategoryPeripheral), findsNothing);
      expect(find.text(l10n.stageCategoryProtocol), findsNothing);
    });

    testWidgets('all categories initially collapsed — children hidden', (
      tester,
    ) async {
      StageRegistry.instance.register(
        const _StubWidget(id: 'led', displayName: 'LED'),
      );
      await tester.pumpWidget(_wrap(const StageWidgetPickerDialog()));
      await tester.pumpAndSettle();
      // LED's display name is hidden until the user opens the section.
      expect(find.text('LED'), findsNothing);
    });

    testWidgets('tapping a collapsed section header expands it', (
      tester,
    ) async {
      StageRegistry.instance.register(
        const _StubWidget(id: 'led', displayName: 'LED'),
      );
      await tester.pumpWidget(_wrap(const StageWidgetPickerDialog()));
      await tester.pumpAndSettle();
      // Initially collapsed → LED row hidden.
      expect(find.text('LED'), findsNothing);
      await _expandAllSections(tester);
      // After expanding → LED row visible.
      expect(find.text('LED'), findsOneWidget);
    });
  });

  group('StageWidgetPickerDialog — custom registry seam', () {
    testWidgets(
      'descriptors from customStageWidgetRegistryProvider appear in the '
      'picker alongside built-in widgets',
      (tester) async {
        StageRegistry.instance.register(
          const _StubWidget(id: 'led', displayName: 'LED'),
        );
        final liveRegistry = _MutableCustomStageRegistry()
          ..register(
            const CustomStageWidgetDescriptor(
              widget: _StubWidget(
                id: 'pro_widget',
                displayName: 'Pro Widget',
                category: StageWidgetCategory.custom,
              ),
            ),
          );

        await tester.pumpWidget(
          _wrap(
            const StageWidgetPickerDialog(),
            overrides: [
              customStageWidgetRegistryProvider.overrideWithValue(liveRegistry),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await _expandAllSections(tester);

        expect(find.text('LED'), findsOneWidget);
        expect(find.text('Pro Widget'), findsOneWidget);
      },
    );

    testWidgets(
      'descriptors with requiredTier == Pro render a FeatureTierBadge',
      (
        tester,
      ) async {
        final liveRegistry = _MutableCustomStageRegistry()
          ..register(
            const CustomStageWidgetDescriptor(
              widget: _StubWidget(
                id: 'pro_widget',
                displayName: 'Pro Widget',
                category: StageWidgetCategory.custom,
              ),
            ),
          );
        // Register a built-in LED upfront so a single _expandAllSections
        // call exposes both rows; calling the helper twice would toggle
        // the first-expanded section back to collapsed.
        StageRegistry.instance.register(
          const _StubWidget(id: 'led', displayName: 'LED'),
        );

        await tester.pumpWidget(
          _wrap(
            const StageWidgetPickerDialog(),
            overrides: [
              customStageWidgetRegistryProvider.overrideWithValue(liveRegistry),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await _expandAllSections(tester);

        // Built-in LED has openCore tier (no badge); Pro Widget has Pro
        // tier (badge). Exactly one FeatureTierBadge across both expanded
        // sections.
        expect(find.byType(WaveCruxFeatureTierBadge), findsOneWidget);
      },
    );

    testWidgets(
      'beta period: tapping a Pro descriptor adds an instance even when '
      'tier is Open Core (FeatureGate short-circuits)',
      (tester) async {
        // This is the public-beta short-circuit, so the beta is pinned below
        // rather than read from the build.

        final liveRegistry = _MutableCustomStageRegistry()
          ..register(
            const CustomStageWidgetDescriptor(
              widget: _StubWidget(
                id: 'pro_widget',
                displayName: 'Pro Widget',
                category: StageWidgetCategory.custom,
              ),
            ),
          );

        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              productTelemetryConfig,
              customStageWidgetRegistryProvider.overrideWithValue(liveRegistry),
              betaPeriodProvider.overrideWithValue(true),
              licenseTierProvider.overrideWith((_) => LicenseTier.openCore),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Builder(
                builder: (context) {
                  container = ProviderScope.containerOf(context);
                  return Scaffold(
                    body: TextButton(
                      onPressed: () => StageWidgetPickerDialog.show(context),
                      child: const Text('open'),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        container.read(stageWorkspaceProvider.notifier).addPanel('A');
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await _expandAllSections(tester);

        await tester.tap(find.text('Pro Widget'));
        await tester.pumpAndSettle();

        // Beta short-circuits FeatureGate; the picker should add the instance
        // and dismiss instead of opening the upgrade dialog.
        final state = container.read(stageWorkspaceProvider);
        expect(state.panels.first.instances, hasLength(1));
        expect(state.panels.first.instances.first.widgetId, 'pro_widget');
      },
    );

    testWidgets(
      'post-beta semantics: when the gate denies activation, the upgrade '
      'dialog is shown and no instance is added',
      (tester) async {
        // `betaPeriodProvider.overrideWithValue(false)` flips the picker's
        // gate check without touching the compile-time `kBetaPeriod`
        // constant — see `_WidgetTile._onTap` for why the picker computes
        // the gate inline from this provider instead of routing through
        // `FeatureGate.isAvailable`.
        final liveRegistry = _MutableCustomStageRegistry()
          ..register(
            const CustomStageWidgetDescriptor(
              widget: _StubWidget(
                id: 'pro_widget',
                displayName: 'Pro Widget',
                category: StageWidgetCategory.custom,
              ),
            ),
          );

        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              productTelemetryConfig,
              customStageWidgetRegistryProvider.overrideWithValue(liveRegistry),
              licenseTierProvider.overrideWith((_) => LicenseTier.openCore),
              betaPeriodProvider.overrideWithValue(false),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Builder(
                builder: (context) {
                  container = ProviderScope.containerOf(context);
                  return Scaffold(
                    body: TextButton(
                      onPressed: () => StageWidgetPickerDialog.show(context),
                      child: const Text('open'),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        container.read(stageWorkspaceProvider.notifier).addPanel('A');
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await _expandAllSections(tester);

        final l10n = L10N.of(
          tester.element(find.byType(StageWidgetPickerDialog)),
        );
        final upgradeTitle = l10n.upgradeDialogTitle;

        await tester.tap(find.text('Pro Widget'));
        await tester.pumpAndSettle();

        // Blocked: picker still open, upgrade dialog stacked on top, no
        // instance added.
        expect(find.byType(StageWidgetPickerDialog), findsOneWidget);
        expect(find.text(upgradeTitle), findsOneWidget);
        final state = container.read(stageWorkspaceProvider);
        expect(state.panels.first.instances, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'post-beta semantics: when the gate admits activation, the widget is '
      'added and no upgrade dialog appears',
      (tester) async {
        final liveRegistry = _MutableCustomStageRegistry()
          ..register(
            const CustomStageWidgetDescriptor(
              widget: _StubWidget(
                id: 'pro_widget',
                displayName: 'Pro Widget',
                category: StageWidgetCategory.custom,
              ),
            ),
          );

        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              productTelemetryConfig,
              customStageWidgetRegistryProvider.overrideWithValue(liveRegistry),
              licenseTierProvider.overrideWith((_) => LicenseTier.pro),
              betaPeriodProvider.overrideWithValue(false),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Builder(
                builder: (context) {
                  container = ProviderScope.containerOf(context);
                  return Scaffold(
                    body: TextButton(
                      onPressed: () => StageWidgetPickerDialog.show(context),
                      child: const Text('open'),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        container.read(stageWorkspaceProvider.notifier).addPanel('A');
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await _expandAllSections(tester);

        await tester.tap(find.text('Pro Widget'));
        await tester.pumpAndSettle();

        // Admitted: picker popped, instance added.
        expect(find.byType(StageWidgetPickerDialog), findsNothing);
        final state = container.read(stageWorkspaceProvider);
        expect(state.panels.first.instances, hasLength(1));
        expect(state.panels.first.instances.first.widgetId, 'pro_widget');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'built-in widget with requiredTier == Pro renders a FeatureTierBadge '
      '(extraStageWidgetsProvider path)',
      (tester) async {
        // Built-in Pro widgets contributed via `extraStageWidgetsProvider`
        // register directly into `StageRegistry`; the picker must consult
        // `StageWidget.requiredTier` to badge them, not just the custom
        // registry's descriptor metadata.
        StageRegistry.instance
          ..register(const _StubWidget(id: 'led', displayName: 'LED'))
          ..register(
            const _StubWidget(
              id: 'audio_waveform',
              displayName: 'Audio Waveform',
              category: StageWidgetCategory.peripheral,
              tier: LicenseTier.pro,
            ),
          );

        await tester.pumpWidget(_wrap(const StageWidgetPickerDialog()));
        await tester.pumpAndSettle();
        await _expandAllSections(tester);

        // Exactly one badge — the built-in Pro widget. The Open-Core LED
        // does not render a badge.
        expect(find.byType(WaveCruxFeatureTierBadge), findsOneWidget);
        expect(find.text('Audio Waveform'), findsOneWidget);
        expect(find.text('LED'), findsOneWidget);
      },
    );

    testWidgets(
      'built-in widget tier in beta period: tapping a Pro built-in adds '
      'an instance even when the user tier is Open Core',
      (tester) async {
        // The public-beta short-circuit, pinned below rather than read from
        // the build.
        StageRegistry.instance.register(
          const _StubWidget(
            id: 'pro_builtin',
            displayName: 'Pro Built-in',
            tier: LicenseTier.pro,
          ),
        );

        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              productTelemetryConfig,
              betaPeriodProvider.overrideWithValue(true),
              licenseTierProvider.overrideWith((_) => LicenseTier.openCore),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Builder(
                builder: (context) {
                  container = ProviderScope.containerOf(context);
                  return Scaffold(
                    body: TextButton(
                      onPressed: () => StageWidgetPickerDialog.show(context),
                      child: const Text('open'),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        container.read(stageWorkspaceProvider.notifier).addPanel('A');
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await _expandAllSections(tester);

        await tester.tap(find.text('Pro Built-in'));
        await tester.pumpAndSettle();

        final state = container.read(stageWorkspaceProvider);
        expect(state.panels.first.instances, hasLength(1));
        expect(state.panels.first.instances.first.widgetId, 'pro_builtin');
      },
    );

    testWidgets(
      'custom-registry tier wins over built-in requiredTier on id collision',
      (tester) async {
        // A vendor-supplied override of an open-core widget should be able to
        // lift the tier without forking the open-core widget definition. The
        // picker resolves the custom-registry tier last, so it overrides any
        // built-in default.
        StageRegistry.instance.register(
          const _StubWidget(id: 'shared', displayName: 'Shared'),
        );
        // CustomStageWidgetDescriptor.requiredTier defaults to Pro, which
        // is exactly what this test wants to assert wins on id collision.
        final liveRegistry = _MutableCustomStageRegistry()
          ..register(
            const CustomStageWidgetDescriptor(
              widget: _StubWidget(id: 'shared', displayName: 'Shared'),
            ),
          );

        await tester.pumpWidget(
          _wrap(
            const StageWidgetPickerDialog(),
            overrides: [
              customStageWidgetRegistryProvider.overrideWithValue(liveRegistry),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await _expandAllSections(tester);

        // The picker dedupes by id and the custom descriptor wins, so the row
        // shows a Pro badge despite the built-in default being Open Core.
        expect(find.byType(WaveCruxFeatureTierBadge), findsOneWidget);
      },
    );

    // Locale sweep is split into one testWidgets per locale rather
    // than a single for-loop because Flutter's Element tree reuses
    // ExpansionTile state across consecutive pumpWidget calls when the
    // tile's ValueKey is identical — a tap that expanded the tile in
    // iteration N would collapse it in iteration N+1, hiding the
    // FeatureTierBadge under test.
    for (final locale in const ['zh', 'ja', 'ko']) {
      testWidgets('locale sweep — Pro descriptors render in $locale', (
        tester,
      ) async {
        final liveRegistry = _MutableCustomStageRegistry()
          ..register(
            const CustomStageWidgetDescriptor(
              widget: _StubWidget(
                id: 'pro_widget',
                displayName: 'Pro Widget',
                category: StageWidgetCategory.custom,
              ),
            ),
          );
        await tester.pumpWidget(
          _wrap(
            const StageWidgetPickerDialog(),
            locale: Locale(locale),
            overrides: [
              customStageWidgetRegistryProvider.overrideWithValue(liveRegistry),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await _expandAllSections(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(WaveCruxFeatureTierBadge), findsOneWidget);
      });
    }
  });

  // `tier.gate_hit` — which locked features drive upgrade
  // intent, and from which tier. Only the DENIAL is instrumented; the allowed
  // path is already counted by `stage.widget_added`.
  group('StageWidgetPickerDialog — telemetry', () {
    Future<ProviderContainer> pumpPicker(
      WidgetTester tester, {
      required bool beta,
      required LicenseTier tier,
      required TelemetryService telemetry,
    }) async {
      final liveRegistry = _MutableCustomStageRegistry()
        ..register(
          const CustomStageWidgetDescriptor(
            widget: _StubWidget(
              id: 'pro_widget',
              displayName: 'Pro Widget',
              category: StageWidgetCategory.custom,
            ),
          ),
        );
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productTelemetryConfig,
            customStageWidgetRegistryProvider.overrideWithValue(liveRegistry),
            licenseTierProvider.overrideWith((_) => tier),
            betaPeriodProvider.overrideWithValue(beta),
            telemetryServiceProvider.overrideWithValue(telemetry),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return Scaffold(
                  body: TextButton(
                    onPressed: () => StageWidgetPickerDialog.show(context),
                    child: const Text('open'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      container.read(stageWorkspaceProvider.notifier).addPanel('A');
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await _expandAllSections(tester);
      return container;
    }

    testWidgets('a post-beta sub-Pro tap records tier.gate_hit', (
      tester,
    ) async {
      final telemetry = _RecordingTelemetry();
      await pumpPicker(
        tester,
        beta: false,
        tier: LicenseTier.openCore,
        telemetry: telemetry,
      );
      // Expanding every section rebuilt every tile; nothing may have been
      // recorded from a build(). `badge.impression` is the one deliberate
      // exception — a badge becoming visible IS the event — and it is
      // deduplicated to once per tier per session rather than in the render
      // path, which is what keeps this rebuild storm from inflating it.
      expect(
        telemetry.events.where((e) => e.name != 'badge.impression'),
        isEmpty,
      );
      expect(telemetry.named('badge.impression'), hasLength(1));

      await tester.tap(find.text('Pro Widget'));
      await tester.pumpAndSettle();

      expect(telemetry.named('tier.gate_hit'), hasLength(1));
      // A closed call-site id, never the locale-resolved display name the
      // upgrade dialog renders.
      expect(telemetry.named('tier.gate_hit').single.properties, {
        'feature': 'stage_widget_pack',
        'required': 'pro',
      });
      // `badge.click` rides along from `WaveCruxUpgradeDialog.show` — the
      // badge funnel's other half, sharing `tier` with `badge.impression`.
      expect(telemetry.named('badge.click').single.properties, {'tier': 'pro'});
    });

    testWidgets('the beta short-circuit records no tier.gate_hit', (
      tester,
    ) async {
      final telemetry = _RecordingTelemetry();
      await pumpPicker(
        tester,
        beta: true,
        tier: LicenseTier.openCore,
        telemetry: telemetry,
      );
      await tester.tap(find.text('Pro Widget'));
      await tester.pumpAndSettle();

      expect(
        telemetry.events.where((e) => e.name == 'tier.gate_hit'),
        isEmpty,
      );
    });
  });
}
