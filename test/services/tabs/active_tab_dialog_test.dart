// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/diagnostics/widgets/tab_diagnostics_drawer.dart';
import 'package:wavecrux/features/panes/widgets/wavecrux_pane_host.dart';
import 'package:wavecrux/features/search/widgets/signal_search_dialog.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/active_tab_navigator.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../../helpers/in_memory_workspace_service.dart';
import '../../helpers/product_telemetry_config.dart';

// A dialog on the root navigator is outside every tab's
// `UncontrolledProviderScope`, and WaveCrux used to give one that reads a tab's
// providers a SECOND scope over the tab's container. Riverpod flushes a
// container's pending rebuilds from inside the build of every scope that
// mounts it; the dialog's scope builds first and flushes into the tab content,
// which it is not an ancestor of, so a per-tab write while the dialog was open
// marked the tab's widgets dirty mid-build ("setState() or markNeedsBuild()
// called during build"). The dialogs are now pushed on the tab's own
// navigator, under the one scope the pane host mounts.

/// The tab content: a per-tab DERIVED provider, watched (a derived provider's
/// rebuild is the one Riverpod defers to a scope's build; a provider watched
/// directly is notified at write time, outside any build), and a button that
/// opens the real signal search dialog the way the viewer does.
class _TabBody extends ConsumerWidget {
  const _TabBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(tabIdProvider);
    final delta = ref.watch(cursorDeltaProvider);
    return Column(
      children: [
        Text('delta ${delta.deltaDisplay ?? 'none'}'),
        ElevatedButton(
          key: ValueKey('search-${tab.value}'),
          onPressed: () => unawaited(
            ModalGuard.run(
              ActiveTab.guardKey(context, 'openSearch'),
              () => SignalSearchDialog.show(context),
            ),
          ),
          child: const Text('open search'),
        ),
        ElevatedButton(
          key: ValueKey('drawer-${tab.value}'),
          onPressed: () => unawaited(TabDiagnosticsDrawer.open(context)),
          child: const Text('open drawer'),
        ),
      ],
    );
  }
}

void main() {
  setUp(ModalGuard.reset);
  tearDown(ModalGuard.reset);

  /// A container wired as `bootstrap` wires it: the tab navigators are
  /// registered as a scope reconciler before the container managers.
  ProviderContainer makeContainer() {
    final tcm = TabContainerManager();
    final pcm = PaneContainerManager();
    final container = ProviderContainer(
      overrides: [
        productTelemetryConfig,
        ...testWorkspaceOverrides(),
        deviceClassProvider.overrideWithValue(DeviceClass.desktop),
        tabContainerManagerProvider.overrideWithValue(tcm),
        paneContainerManagerProvider.overrideWithValue(pcm),
      ],
    );
    tcm.init(container);
    pcm.init(container);
    container.read(workspaceProvider.notifier)
      ..addScopeReconciler(container.read(tabNavigatorsProvider))
      ..addScopeReconciler(tcm)
      ..addScopeReconciler(pcm);
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpHost(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: WaveCruxPaneHost(
              tabContentBuilder: (context, tab) => const _TabBody(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Two file tabs in one pane, `alpha` active.
  Future<(TabId, TabId)> openTwoTabs(ProviderContainer container) async {
    await container.read(workspaceProvider.future);
    final a = await container.wavecruxWorkspace.openFile(
      '/tmp/alpha.vcd',
      displayName: 'alpha.vcd',
    );
    final b = await container.wavecruxWorkspace.openFile(
      '/tmp/beta.vcd',
      displayName: 'beta.vcd',
    );
    await container.read(workspaceProvider.notifier).setActiveTab(a);
    return (a, b);
  }

  ProviderContainer tabContainer(ProviderContainer root, TabId tab) =>
      root.read(tabContainerManagerProvider).containerFor(tab);

  Finder search() => find.byType(SignalSearchDialog);

  /// Lets the tab's debounced session autosave and Riverpod's refresh timers
  /// run out, so no timer is pending when the test ends.
  Future<void> drain(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 3));

  // Mutation-verified: putting `SignalSearchDialog.show` back on the root
  // navigator with an `UncontrolledProviderScope(container: <the tab's>)`
  // around the dialog fails this test on the first write with the field
  // report's assertion ("setState() or markNeedsBuild() called during
  // build", on `_TabBody`, while `UncontrolledProviderScope` was building).
  testWidgets('a per-tab write while a dialog reads the same tab rebuilds '
      'the dialog and the tab content without marking either dirty '
      'mid-build', (tester) async {
    final container = makeContainer();
    final (alphaId, _) = await openTwoTabs(container);
    await pumpHost(tester, container);
    final alpha = tabContainer(container, alphaId);

    await tester.tap(find.byKey(ValueKey('search-${alphaId.value}')));
    await tester.pumpAndSettle();
    expect(search(), findsOneWidget);
    // On the tab's own navigator, so under the tab's one scope.
    expect(
      ProviderScope.containerOf(tester.element(search()), listen: false),
      same(alpha),
    );

    for (var i = 1; i <= 3; i++) {
      alpha.read(cursorStateProvider.notifier)
        ..placePrimary(0)
        ..placeSecondary(i * 100);
      // No duration: the frame builds before the zero-delay timers Riverpod
      // also arms, so the pending rebuild is flushed from inside a scope's
      // build, which is the path the assertion fired on.
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    expect(search(), findsOneWidget);
    await drain(tester);
  });

  testWidgets('a dialog covers only its tab: one pane in a split, the other '
      'pane stays usable', (tester) async {
    final container = makeContainer();
    final (alphaId, betaId) = await openTwoTabs(container);
    final notifier = container.wavecruxWorkspace;
    final pane = await notifier.splitPane();
    await notifier.moveTabToPane(betaId, pane);
    await pumpHost(tester, container);

    final betaButton = find.byKey(ValueKey('search-${betaId.value}'));
    await tester.tap(find.byKey(ValueKey('search-${alphaId.value}')));
    await tester.pumpAndSettle();
    expect(search(), findsOneWidget);

    // The dialog's area is the left pane's width, not the window's, and does
    // not reach the right pane's content.
    final area = tester.getRect(search());
    expect(area.width, lessThan(1400 / 2));
    expect(area.right, lessThanOrEqualTo(tester.getTopLeft(betaButton).dx));
    // The other pane takes input while the dialog is open.
    expect(betaButton.hitTestable(), findsOneWidget);
    await tester.tap(betaButton);
    await tester.pumpAndSettle();
    expect(search(), findsNWidgets(2));
    await drain(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dialog stays with its tab: hidden while another tab is '
      'active, which can open its own, and back on return', (tester) async {
    final container = makeContainer();
    final (alphaId, betaId) = await openTwoTabs(container);
    final notifier = container.read(workspaceProvider.notifier);
    await pumpHost(tester, container);

    await tester.tap(find.byKey(ValueKey('search-${alphaId.value}')));
    await tester.pumpAndSettle();
    expect(search(), findsOneWidget);

    await notifier.setActiveTab(betaId);
    await tester.pumpAndSettle();
    // Alpha's dialog is offstage with its tab; beta opens its own, which its
    // own guard key allows.
    expect(search().hitTestable(), findsNothing);
    await tester.tap(find.byKey(ValueKey('search-${betaId.value}')));
    await tester.pumpAndSettle();
    final shown = search().hitTestable();
    expect(shown, findsOneWidget);
    expect(
      ProviderScope.containerOf(tester.element(shown), listen: false),
      same(tabContainer(container, betaId)),
    );

    await notifier.setActiveTab(alphaId);
    await tester.pumpAndSettle();
    final back = search().hitTestable();
    expect(back, findsOneWidget);
    expect(
      ProviderScope.containerOf(tester.element(back), listen: false),
      same(tabContainer(container, alphaId)),
    );
    await drain(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing a tab with its dialog open closes the dialog, '
      'completes its future and frees its guard', (tester) async {
    final container = makeContainer();
    final (alphaId, _) = await openTwoTabs(container);
    await pumpHost(tester, container);
    final context = tester.element(
      find.byKey(ValueKey('search-${alphaId.value}')),
    );
    final key = ActiveTab.guardKey(context, 'openSearch');
    expect(key, 'openSearch@${alphaId.value}');

    var completed = false;
    unawaited(
      ModalGuard.run(
        key,
        () => SignalSearchDialog.show(context),
      ).then((_) => completed = true),
    );
    await tester.pumpAndSettle();
    expect(search(), findsOneWidget);
    expect(ModalGuard.isOpen(key), isTrue);

    await container.read(workspaceProvider.notifier).closeTab(alphaId);
    await tester.pumpAndSettle();

    expect(search(), findsNothing);
    expect(completed, isTrue);
    expect(ModalGuard.isOpen(key), isFalse);
    await drain(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the diagnostics drawer reads the active tab under its one '
      'scope, follows a tab switch and closes with the last tab', (
    tester,
  ) async {
    final container = makeContainer();
    final (alphaId, betaId) = await openTwoTabs(container);
    final notifier = container.read(workspaceProvider.notifier);
    await pumpHost(tester, container);
    final alpha = tabContainer(container, alphaId);

    await tester.tap(find.byKey(ValueKey('drawer-${alphaId.value}')));
    await tester.pumpAndSettle();
    final drawer = find.byType(TabDiagnosticsDrawer);
    expect(drawer, findsOneWidget);
    expect(
      ProviderScope.containerOf(tester.element(drawer), listen: false),
      same(alpha),
    );
    expect(ModalGuard.isOpen('tabDiagnostics'), isTrue);

    for (var i = 1; i <= 2; i++) {
      alpha.read(cursorStateProvider.notifier)
        ..placePrimary(0)
        ..placeSecondary(i * 100);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    await notifier.setActiveTab(betaId);
    await tester.pumpAndSettle();
    final moved = find.byKey(const Key('tabDiagnosticsHeader')).hitTestable();
    expect(moved, findsOneWidget);
    expect(
      ProviderScope.containerOf(tester.element(moved), listen: false),
      same(tabContainer(container, betaId)),
    );

    await notifier.closeTab(betaId);
    await tester.pumpAndSettle();
    expect(
      ProviderScope.containerOf(
        tester.element(find.byType(TabDiagnosticsDrawer)),
        listen: false,
      ),
      same(alpha),
    );
    await notifier.closeTab(alphaId);
    await tester.pumpAndSettle();
    expect(find.byType(TabDiagnosticsDrawer), findsNothing);
    expect(ModalGuard.isOpen('tabDiagnostics'), isFalse);
    await drain(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no tab the dialog goes on the root navigator and the '
      'guard key is the plain one', (tester) async {
    final container = makeContainer();
    await container.read(workspaceProvider.future);
    late BuildContext context;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (c) {
              context = c;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      ),
    );
    expect(ActiveTab.navigatorFor(context), isNull);
    expect(ActiveTab.guardKey(context, 'openSearch'), 'openSearch');
    await drain(tester);
  });
}
