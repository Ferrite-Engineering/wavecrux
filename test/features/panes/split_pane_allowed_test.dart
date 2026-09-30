// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Split Pane Right on a window the pane host will not split.
//
// Below 1000 dp a tablet's pane host renders only the active pane. Splitting
// there made the new pane active and hid the original one, taking every other
// tab out of view. The tab-bar split button already respected the width; the
// menu action and its chord did not.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/core/shortcuts/action_context_provider.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/panes/providers/split_pane_allowed_provider.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/features/viewer/widgets/viewer_toolbar.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../../helpers/product_telemetry_config.dart';

class _InMemoryWorkspaceService implements WorkspaceService {
  @override
  Future<Workspace> load() async => Workspace(
    tabs: const [],
    panes: const [WorkspacePane(id: PaneId.primary)],
    activePaneId: PaneId.primary,
  );

  @override
  Future<void> save(Workspace workspace) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('isSplitPaneAllowed', () {
    test('phones never split; tablets from 1000 dp; desktop always', () {
      expect(isSplitPaneAllowed(DeviceClass.phone, 2000), isFalse);
      expect(isSplitPaneAllowed(DeviceClass.phoneLandscape, 2000), isFalse);
      expect(isSplitPaneAllowed(DeviceClass.tablet, 834), isFalse);
      expect(isSplitPaneAllowed(DeviceClass.tablet, 1024), isTrue);
      expect(isSplitPaneAllowed(DeviceClass.desktop, 400), isTrue);
    });

    test('the provider measures the reported window', () {
      final container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          deviceClassProvider.overrideWithValue(DeviceClass.tablet),
        ],
      );
      addTearDown(container.dispose);
      container.read(displaySizeProvider.notifier).set(const Size(834, 1112));
      expect(container.read(splitPaneAllowedProvider), isFalse);
      container.read(displaySizeProvider.notifier).set(const Size(1112, 834));
      expect(container.read(splitPaneAllowedProvider), isTrue);
    });

    test('Split Pane Right is hidden where the host cannot split', () {
      final d = descriptorFor(ShortcutAction.splitPaneRight);
      const narrow = ActionContext(
        fileLoaded: true,
        deviceClass: DeviceClass.tablet,
        splitPaneAllowed: false,
      );
      const wide = ActionContext(
        fileLoaded: true,
        deviceClass: DeviceClass.tablet,
      );
      expect(d.isVisible(narrow), isFalse);
      expect(d.isVisible(wide), isTrue);
    });
  });

  testWidgets('its chord leaves a narrow tablet on one pane', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tcm = TabContainerManager();
    final pcm = PaneContainerManager();
    final container = ProviderContainer(
      overrides: <Override>[
        productTelemetryConfig,
        tabContainerManagerProvider.overrideWithValue(tcm),
        paneContainerManagerProvider.overrideWithValue(pcm),
        workspaceServiceProvider.overrideWithValue(_InMemoryWorkspaceService()),
        // Enabled by the table (one pane), so the dispatch guard lets the
        // chord through to the handler; only the window forbids the split.
        actionContextProvider.overrideWithValue(
          const ActionContext(
            fileLoaded: true,
            deviceClass: DeviceClass.tablet,
            splitPaneAllowed: false,
          ),
        ),
        splitPaneAllowedProvider.overrideWithValue(false),
      ],
    );
    tcm.init(container);
    pcm.init(container);
    await container.read(workspaceProvider.future);
    await container.wavecruxWorkspace.newTab(displayName: 'A');
    await container.wavecruxWorkspace.newTab(displayName: 'B');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: const ViewerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final anchor = tester.element(find.byType(ViewerToolbar));
    Actions.invoke(
      anchor,
      const ShortcutActionIntent(ShortcutAction.splitPaneRight),
    );
    await tester.pumpAndSettle();

    final workspace = container.read(workspaceProvider).value!;
    expect(workspace.panes, hasLength(1));
    expect(workspace.tabs.map((t) => t.displayName), containsAll(['A', 'B']));
    expect(tester.takeException(), isNull);

    // Tear the tree and its containers down inside the test body, so their
    // timers are cancelled before the binding checks for pending ones.
    await tester.pumpWidget(const SizedBox.shrink());
    tcm.dispose();
    pcm.dispose();
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
