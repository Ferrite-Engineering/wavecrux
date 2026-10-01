// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/cursors/providers/playback_provider.dart';
import 'package:wavecrux/features/decoders/widgets/transaction_table_panel.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/stage_panel.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/x_trace_provider.dart';
import 'package:wavecrux/features/viewer/widgets/bottom_dock.dart';
import 'package:wavecrux/features/viewer/widgets/x_trace_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/stage_registry.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

Annotation _note({String id = 'n1'}) => Annotation(
  id: id,
  shape: AnnotationShape.callout,
  anchor: const PointAnchor(time: 100, rowId: 'top.bus'),
  authorName: 'Martin',
  createdAt: DateTime.utc(2026, 8, 13),
  text: 'note $id',
);

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
  List<SignalBinding> get requiredSignals => const [];
}

/// An X-trace notifier a test can put into the refused state directly.
class _RefusingXTrace extends XTraceNotifier {
  void refuse() => state = const XTraceState(error: XTraceFailure.notXAtTime);
}

Future<ProviderContainer> _pump(WidgetTester tester) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceClassProvider.overrideWithValue(DeviceClass.desktop),
        xTraceProvider.overrideWith(_RefusingXTrace.new),
      ],
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return const WaveCruxBottomDock();
            },
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
      ..register(const _LedStub());
  });

  tearDown(StageRegistry.instance.clear);

  group('WaveCruxBottomDock', () {
    testWidgets('defaults to the pinned Transactions tab', (tester) async {
      await _pump(tester);
      expect(find.byType(CruxDock), findsOneWidget);
      expect(find.byType(TransactionTablePanel), findsOneWidget);
    });

    group('Stage — dynamic per-panel tabs', () {
      testWidgets('one dock tab per Stage panel, labeled with its name', (
        tester,
      ) async {
        final container = await _pump(tester);
        container.read(panelLayoutProvider.notifier)
          ..setStageViewVisible(visible: true)
          ..revealBottomDockTab(kBottomDockStagePrefix);
        container.read(stageWorkspaceProvider.notifier)
          ..addPanel('Decode')
          ..addPanel('Fetch');
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('cruxDockTab-stage:stagePanel_0')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('cruxDockTab-stage:stagePanel_1')),
          findsOneWidget,
        );
        expect(find.text('Decode'), findsOneWidget);
        expect(find.text('Fetch'), findsOneWidget);
      });

      testWidgets('selecting a stage tab drives the Stage active panel', (
        tester,
      ) async {
        // The behavior the panel's internal tab bar used to own.
        final container = await _pump(tester);
        container.read(panelLayoutProvider.notifier)
          ..setStageViewVisible(visible: true)
          ..revealBottomDockTab(kBottomDockStagePrefix);
        container.read(stageWorkspaceProvider.notifier)
          ..addPanel('Decode')
          ..addPanel('Fetch');
        await tester.pumpAndSettle();
        expect(
          container.read(stageWorkspaceProvider).activePanel!.name,
          'Fetch',
        );

        await tester.tap(find.text('Decode'));
        await tester.pumpAndSettle();
        expect(
          container.read(stageWorkspaceProvider).activePanel!.name,
          'Decode',
        );
        expect(find.byType(StagePanel), findsOneWidget);
      });

      testWidgets("a stage tab's × removes that panel", (tester) async {
        final container = await _pump(tester);
        container.read(panelLayoutProvider.notifier)
          ..setStageViewVisible(visible: true)
          ..revealBottomDockTab(kBottomDockStagePrefix);
        container.read(stageWorkspaceProvider.notifier)
          ..addPanel('Keep')
          ..addPanel('Doomed');
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('cruxDockClose-stage:stagePanel_1')),
        );
        await tester.pumpAndSettle();
        final names = container
            .read(stageWorkspaceProvider)
            .panels
            .map((p) => p.name)
            .toList();
        expect(names, ['Keep']);
      });

      testWidgets('with Stage on and zero panels there is NO stage tab — '
          'the retired create-first empty state is gone', (tester) async {
        // Turning the feature on seeds a default panel at the toggle site,
        // so an empty workspace can only mean a legacy restored session;
        // the dock falls back to the pinned Transactions tab.
        final container = await _pump(tester);
        container.read(panelLayoutProvider.notifier)
          ..setStageViewVisible(visible: true)
          ..revealBottomDockTab(kBottomDockStagePrefix);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('cruxDockTab-stage:')), findsNothing);
        expect(find.byType(StagePanel), findsNothing);
        expect(find.byType(TransactionTablePanel), findsOneWidget);
        expect(container.read(panelLayoutProvider).stageViewVisible, isTrue);
      });

      testWidgets("the last stage tab's × turns the Stage feature off", (
        tester,
      ) async {
        final container = await _pump(tester);
        container.read(panelLayoutProvider.notifier)
          ..setStageViewVisible(visible: true)
          ..revealBottomDockTab(kBottomDockStagePrefix);
        container.read(stageWorkspaceProvider.notifier).addPanel('Only');
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('cruxDockClose-stage:stagePanel_0')),
        );
        await tester.pumpAndSettle();
        expect(container.read(stageWorkspaceProvider).panels, isEmpty);
        expect(
          container.read(panelLayoutProvider).stageViewVisible,
          isFalse,
        );
        // Falls back to the pinned Transactions tab.
        expect(find.byType(TransactionTablePanel), findsOneWidget);
      });

      testWidgets('the strip actions add and rename panels', (tester) async {
        // Add Panel / Add Widget / Rename moved from the internal tab bar to
        // the dock strip's per-active-tab action cluster.
        final container = await _pump(tester);
        container.read(panelLayoutProvider.notifier)
          ..setStageViewVisible(visible: true)
          ..revealBottomDockTab(kBottomDockStagePrefix);
        container.read(stageWorkspaceProvider.notifier).addPanel('Existing');
        await tester.pumpAndSettle();

        // Add Panel opens the create dialog; OK creates a second panel.
        await tester.tap(find.byIcon(Icons.add_circle_outline));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(
          container.read(stageWorkspaceProvider).panels.length,
          2,
        );

        // Rename acts on the ACTIVE panel.
        await tester.tap(find.byIcon(Icons.drive_file_rename_outline));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'New Name');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(
          container.read(stageWorkspaceProvider).activePanel!.name,
          'New Name',
        );
      });

      testWidgets('the strip hosts the playback transport: play/pause · '
          'speed · loop · follow (no stop)', (tester) async {
        // The transport moved out of the Stage panel's bottom row (and off
        // the main toolbar) into the active stage tab's action cluster, with
        // a single play/pause toggle replacing the old play + stop pair.
        final container = await _pump(tester);
        container.read(panelLayoutProvider.notifier)
          ..setStageViewVisible(visible: true)
          ..revealBottomDockTab(kBottomDockStagePrefix);
        container.read(stageWorkspaceProvider.notifier).addPanel('Motor');
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('stagePlaybackPlayPause')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('stagePlaybackSpeed')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('stagePlaybackLoop')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('stagePlaybackFollow')),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.stop), findsNothing);

        // Follow-viewport toggles the per-tab playback state from the strip.
        expect(container.read(playbackProvider).followViewport, isTrue);
        await tester.tap(find.byKey(const ValueKey('stagePlaybackFollow')));
        await tester.pumpAndSettle();
        expect(container.read(playbackProvider).followViewport, isFalse);
      });

      testWidgets('Add Widget opens the widget picker dialog', (tester) async {
        final container = await _pump(tester);
        container.read(panelLayoutProvider.notifier)
          ..setStageViewVisible(visible: true)
          ..revealBottomDockTab(kBottomDockStagePrefix);
        container.read(stageWorkspaceProvider.notifier).addPanel('Panel');
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsWidgets);
      });
    });

    group('on-demand tabs', () {
      testWidgets('cocotb tab appears with its flag and its × clears it', (
        tester,
      ) async {
        final container = await _pump(tester);
        container
            .read(panelLayoutProvider.notifier)
            .setCocotbLogPanelVisible(visible: true);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('cruxDockTab-cocotb')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('cruxDockClose-cocotb')));
        await tester.pumpAndSettle();
        expect(
          container.read(panelLayoutProvider).cocotbLogPanelVisible,
          isFalse,
        );
        expect(find.byKey(const ValueKey('cruxDockTab-cocotb')), findsNothing);
      });

      testWidgets('a refused X-trace mounts the X-Trace tab with its reason, '
          'and its × clears it', (tester) async {
        final container = await _pump(tester);
        expect(find.byKey(const ValueKey('cruxDockTab-xtrace')), findsNothing);

        (container.read(xTraceProvider.notifier) as _RefusingXTrace).refuse();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('cruxDockTab-xtrace')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('cruxDockTab-xtrace')));
        await tester.pumpAndSettle();
        expect(find.byType(XTracePanel), findsOneWidget);
        expect(find.byKey(const Key('xTracePanelError')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('cruxDockClose-xtrace')));
        await tester.pumpAndSettle();
        expect(container.read(xTraceProvider), const XTraceState());
        expect(find.byKey(const ValueKey('cruxDockTab-xtrace')), findsNothing);
      });

      testWidgets('a newly appearing on-demand tab auto-reveals', (
        tester,
      ) async {
        final container = await _pump(tester);
        // The dock is open on Transactions; loading a cocotb log flips the
        // flag from elsewhere — the tab must reveal without a manual click.
        container
            .read(panelLayoutProvider.notifier)
            .setCocotbLogPanelVisible(visible: true);
        await tester.pumpAndSettle();
        expect(
          container.read(panelLayoutProvider).effectiveBottomDockTab,
          kBottomDockTabCocotb,
        );
      });
    });

    group('legacy sessions (null bottomDockTab)', () {
      testWidgets('stageViewVisible=true restores showing Stage', (
        tester,
      ) async {
        // Mirrors the retired priority chain: a pre-dock session that saved
        // with Stage open must restore showing Stage, not Transactions.
        final container = await _pump(tester);
        container
            .read(panelLayoutProvider.notifier)
            .setStageViewVisible(visible: true);
        container.read(stageWorkspaceProvider.notifier).addPanel('Restored');
        await tester.pumpAndSettle();

        expect(find.byType(StagePanel), findsOneWidget);
        expect(find.byType(TransactionTablePanel), findsNothing);
      });
    });

    testWidgets('the collapse button hides the bottom region', (tester) async {
      final container = await _pump(tester);
      container
          .read(panelLayoutProvider.notifier)
          .setTransactionViewVisible(visible: true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('cruxDockCollapse')));
      await tester.pumpAndSettle();
      expect(
        container.read(panelLayoutProvider).transactionViewVisible,
        isFalse,
      );
    });

    testWidgets('renders NO pop-out affordance', (tester) async {
      // Multi-window detachment is a future Pro-only feature; open-core
      // exposes no hint of it. The dock's pop-out seam stays in crux_dock
      // for the Pro overlay to enable when Flutter multi-window lands.
      await _pump(tester);
      expect(find.byKey(const ValueKey('cruxDockPopOut')), findsNothing);
    });

    group('drag-between-docks placement', () {
      testWidgets('a moved tab leaves the bottom entries and reveals right', (
        tester,
      ) async {
        final container = await _pump(tester);
        final notifier = container.read(panelLayoutProvider.notifier)
          ..setCocotbLogPanelVisible(visible: true);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('cruxDockTab-cocotb')),
          findsOneWidget,
        );

        // The drop handler the right dock wires to onTabMovedIn.
        notifier.moveDockTab(kBottomDockTabCocotb, kDockRegionRight);
        await tester.pumpAndSettle();

        // Gone from the bottom strip…
        expect(find.byKey(const ValueKey('cruxDockTab-cocotb')), findsNothing);
        final state = container.read(panelLayoutProvider);
        // …homed and revealed on the right.
        expect(
          state.dockRegionOf(kBottomDockTabCocotb, kDockRegionBottom),
          kDockRegionRight,
        );
        expect(state.valueColumnVisible, isTrue);
        expect(state.effectiveRightDockTab, kBottomDockTabCocotb);
      });

      testWidgets('placement-aware reveal follows the moved tab', (
        tester,
      ) async {
        final container = await _pump(tester);
        final notifier = container.read(panelLayoutProvider.notifier)
          ..setCocotbLogPanelVisible(visible: true)
          ..moveDockTab(kBottomDockTabCocotb, kDockRegionRight)
          ..setValueColumnVisible(visible: false);
        await tester.pumpAndSettle();

        // Re-activating the feature (loading a log) reveals where the user
        // PUT the tab, not its native region.
        notifier.revealDockTabPlaced(kBottomDockTabCocotb, kDockRegionBottom);
        final state = container.read(panelLayoutProvider);
        expect(state.valueColumnVisible, isTrue);
        expect(state.effectiveRightDockTab, kBottomDockTabCocotb);
      });
    });

    group('phone sheet presentation', () {
      testWidgets('hosts the SAME entry list as the desktop dock', (
        tester,
      ) async {
        // One assembler, two presentations — the retired priority chain
        // cannot fork between them because it no longer exists.
        final container = await _pump(tester);
        container
            .read(panelLayoutProvider.notifier)
            .setCocotbLogPanelVisible(visible: true);
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(body: WaveCruxBottomDockSheet()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('cruxDockTab-transactions')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('cruxDockTab-cocotb')),
          findsOneWidget,
        );
        // Desktop-region concerns are omitted in the sheet.
        expect(find.byKey(const ValueKey('cruxDockMaximize')), findsNothing);
        expect(find.byKey(const ValueKey('cruxDockPopOut')), findsNothing);
      });
    });

    group('locale sweep', () {
      for (final locale in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        testWidgets('renders in $locale without exceptions', (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                deviceClassProvider.overrideWithValue(DeviceClass.desktop),
              ],
              child: MaterialApp(
                locale: locale,
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: const Scaffold(body: WaveCruxBottomDock()),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    });
  });

  group('PanelLayoutState dock derivations', () {
    test('effectiveBottomDockTab mirrors the legacy chain when unset', () {
      expect(
        const PanelLayoutState().effectiveBottomDockTab,
        kBottomDockTabTransactions,
      );
      expect(
        const PanelLayoutState(stageViewVisible: true).effectiveBottomDockTab,
        kBottomDockStagePrefix,
      );
      expect(
        const PanelLayoutState(
          cocotbLogPanelVisible: true,
        ).effectiveBottomDockTab,
        kBottomDockTabCocotb,
      );
      // Stage outranks cocotb, as the chain did.
      expect(
        const PanelLayoutState(
          stageViewVisible: true,
          cocotbLogPanelVisible: true,
        ).effectiveBottomDockTab,
        kBottomDockStagePrefix,
      );
    });

    test('a stale stage id falls back once the feature is off', () {
      const state = PanelLayoutState(bottomDockTab: 'stage:stagePanel_0');
      expect(state.effectiveBottomDockTab, kBottomDockTabTransactions);
      const on = PanelLayoutState(
        bottomDockTab: 'stage:stagePanel_0',
        stageViewVisible: true,
      );
      expect(on.effectiveBottomDockTab, 'stage:stagePanel_0');
    });

    test('bottomDockShowsStage requires the region open AND a stage tab', () {
      const hidden = PanelLayoutState(stageViewVisible: true);
      expect(hidden.bottomDockShowsStage, isFalse, reason: 'region closed');
      const behindFsm = PanelLayoutState(
        stageViewVisible: true,
        transactionViewVisible: true,
        bottomDockTab: kBottomDockTabFsm,
      );
      expect(
        behindFsm.bottomDockShowsStage,
        isFalse,
        reason:
            'Stage is on but behind the FSM tab — the transport is not '
            'on screen',
      );
      const showing = PanelLayoutState(
        stageViewVisible: true,
        transactionViewVisible: true,
        bottomDockTab: 'stage:stagePanel_0',
      );
      expect(showing.bottomDockShowsStage, isTrue);
    });

    test('bottomDockShowsTransactions tracks the active tab', () {
      const showing = PanelLayoutState(transactionViewVisible: true);
      expect(showing.bottomDockShowsTransactions, isTrue);
      const behindCocotb = PanelLayoutState(
        transactionViewVisible: true,
        cocotbLogPanelVisible: true,
        bottomDockTab: kBottomDockTabCocotb,
      );
      expect(behindCocotb.bottomDockShowsTransactions, isFalse);
    });
  });

  group('Annotations — presence, and the empty state it guards', () {
    testWidgets('absent with no annotations and no explicit choice', (
      tester,
    ) async {
      await _pump(tester);
      expect(
        find.byKey(const ValueKey('cruxDockTab-annotations')),
        findsNothing,
      );
    });

    testWidgets('appears once the tab has a note', (tester) async {
      final container = await _pump(tester);
      container.read(annotationsProvider.notifier).add(_note());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('cruxDockTab-annotations')),
        findsOneWidget,
      );
    });

    testWidgets('**opens with zero annotations when asked**', (tester) async {
      // The defect this fixes: presence was derived from
      // `annotations.isNotEmpty` alone, so the panel's empty state — the one
      // place in the app naming the Option-click authoring gesture — could
      // never render. It appeared only to users who had already worked the
      // gesture out.
      final container = await _pump(tester);
      container
          .read(panelLayoutProvider.notifier)
          .toggleAnnotationsPanel(annotationsPresent: false);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('cruxDockTab-annotations')),
        findsOneWidget,
      );
    });

    testWidgets('closing it does not delete the notes', (tester) async {
      // Every other closable panel here clears what it displays. This one
      // must not: what it displays is the user's writing.
      final container = await _pump(tester)
        // Hold the list. Once the panel is explicitly closed the dock stops
        // watching `annotationsProvider` — correct, but in this harness
        // nothing else watches it either, so the auto-dispose would empty it
        // and the assertion below would pass for the wrong reason. In the app
        // the session autosave listener keeps it alive.
        ..listen(annotationsProvider, (_, _) {});
      container.read(annotationsProvider.notifier).add(_note());
      await tester.pumpAndSettle();

      container
          .read(panelLayoutProvider.notifier)
          .setAnnotationsPanelVisible(visible: false);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('cruxDockTab-annotations')),
        findsNothing,
      );
      expect(container.read(annotationsProvider), hasLength(1));
    });

    testWidgets('a closed panel stays closed when a note is added', (
      tester,
    ) async {
      final container = await _pump(tester)
        ..listen(annotationsProvider, (_, _) {});
      container.read(annotationsProvider.notifier).add(_note());
      container
          .read(panelLayoutProvider.notifier)
          .setAnnotationsPanelVisible(visible: false);
      await tester.pumpAndSettle();

      container.read(annotationsProvider.notifier).add(_note(id: 'n2'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('cruxDockTab-annotations')),
        findsNothing,
      );
    });
  });
}
