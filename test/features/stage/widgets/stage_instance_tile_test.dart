// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_manager.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_selection_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/stage_instance_tile.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/stage_registry.dart';

class _LedStub extends StageWidget {
  const _LedStub();
  @override
  String get id => 'led';
  @override
  String get displayName => 'LED';
  @override
  String get description => '1-bit indicator';
  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;
  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(name: 'in', description: '1-bit signal'),
  ];
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required StageInstance instance,
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 160,
              child: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return StageInstanceTile(instance: instance);
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Seed the workspace so removeInstance / select have a target.
  container
      .read(stageWorkspaceProvider.notifier)
      .restoreFromSession(
        StageWorkspaceState(
          panels: [
            StagePanelConfig(
              id: 'p0',
              name: 'P',
              instances: [instance],
            ),
          ],
          activePanelId: 'p0',
        ),
      );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() {
    StageRegistry.instance
      ..clear()
      ..register(const _LedStub());
  });
  tearDown(StageRegistry.instance.clear);

  group('StageInstanceTile — locale sweep', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await _pump(
          tester,
          locale: Locale(locale),
          instance: const StageInstance(id: 'i0', widgetId: 'led'),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('StageInstanceTile — header', () {
    testWidgets('renders widget displayName when no label', (tester) async {
      await _pump(
        tester,
        instance: const StageInstance(id: 'i0', widgetId: 'led'),
      );
      expect(find.text('LED'), findsOneWidget);
    });

    testWidgets('renders custom label when provided', (tester) async {
      await _pump(
        tester,
        instance: const StageInstance(
          id: 'i0',
          widgetId: 'led',
          label: 'Power LED',
        ),
      );
      expect(find.text('Power LED'), findsOneWidget);
    });

    testWidgets('close button removes the instance from the workspace', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        instance: const StageInstance(id: 'i0', widgetId: 'led'),
      );
      await tester.tap(find.byTooltip('Remove widget'));
      await tester.pumpAndSettle();
      final panel = container.read(stageWorkspaceProvider).activePanel!;
      expect(panel.instances.where((i) => i.id == 'i0'), isEmpty);
    });
  });

  group('StageInstanceTile — selection visual', () {
    testWidgets('card border is highlighted when this instance is selected', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        instance: const StageInstance(id: 'i0', widgetId: 'led'),
      );

      final cardFinder = find.byKey(const ValueKey('stageInstance:i0'));
      final initialShape =
          (tester.widget<Card>(cardFinder).shape!) as RoundedRectangleBorder;
      final initialWidth = initialShape.side.width;

      container.read(stageSelectedInstanceProvider.notifier).select('i0');
      await tester.pumpAndSettle();

      final selectedShape =
          (tester.widget<Card>(cardFinder).shape!) as RoundedRectangleBorder;
      expect(selectedShape.side.width, greaterThan(initialWidth));
    });
  });

  group('StageInstanceTile — body', () {
    testWidgets('shows unknown widget message when widgetId not registered', (
      tester,
    ) async {
      StageRegistry.instance.clear();
      await _pump(
        tester,
        instance: const StageInstance(id: 'i0', widgetId: 'led'),
        // Settle the custom-widget manager (not loading) so an unresolved id
        // surfaces the "Unknown widget" message rather than the spinner.
        overrides: [
          customWidgetBundleManagerProvider.overrideWith(
            (ref) => Future<CustomWidgetBundleManager>.error(
              StateError('no bundle manager in test'),
            ),
          ),
        ],
      );
      expect(
        find.textContaining('Unknown widget'),
        findsOneWidget,
      );
    });

    testWidgets(
      'shows a spinner (not "Unknown widget") while the custom-widget '
      'manager is still loading',
      (tester) async {
        // An unresolved id during manager-loading is the session-restore
        // race: the bundle may register once the manager finishes, so we
        // show a spinner rather than the "Unknown widget" error.
        StageRegistry.instance.clear();
        final pending = Completer<CustomWidgetBundleManager>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              customWidgetBundleManagerProvider.overrideWith(
                (ref) => pending.future,
              ),
            ],
            child: const MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SizedBox(
                  width: 200,
                  height: 160,
                  child: StageInstanceTile(
                    instance: StageInstance(id: 'i0', widgetId: 'not_loaded'),
                  ),
                ),
              ),
            ),
          ),
        );
        // One frame only — pumpAndSettle would hang on the spinner animation.
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.textContaining('Unknown widget'), findsNothing);
      },
    );
  });
}
