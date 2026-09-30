// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Tools ▸ Copy Diagnostics Report used to be listed in the Tools menu, the
// overflow and the command palette while its handler was an empty `break`:
// choosing it did nothing. Firing the action through the viewer's real
// dispatch must now put the full report on the clipboard.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/features/viewer/widgets/viewer_toolbar.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

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
  testWidgets('the action copies the full diagnostics report', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final tcm = TabContainerManager();
    final pcm = PaneContainerManager();
    final container = ProviderContainer(
      overrides: [
        productTelemetryConfig,
        tabContainerManagerProvider.overrideWithValue(tcm),
        paneContainerManagerProvider.overrideWithValue(pcm),
        workspaceServiceProvider.overrideWithValue(_InMemoryWorkspaceService()),
      ],
    );
    tcm.init(container);
    pcm.init(container);
    await container.read(workspaceProvider.future);
    await container.wavecruxWorkspace.newTab(displayName: 'cpu.vcd');

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
      const ShortcutActionIntent(ShortcutAction.copyDiagnosticsReport),
    );
    await tester.pumpAndSettle();

    expect(copied, startsWith('=== WaveCrux Full Diagnostics Report ==='));
    expect(copied, contains('Active Tab Name: cpu.vcd'));
    expect(
      find.text(L10N.of(anchor).appDiagnosticsCopyReportSuccess),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    tcm.dispose();
    pcm.dispose();
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  });

  test('no viewer shortcut case is an empty break', () {
    // A handler that is only `break` is a menu item that does nothing. Every
    // action the viewer dispatches must do something, or not be dispatched.
    final source = File(
      'lib/features/viewer/screens/viewer_screen_shortcuts.dart',
    ).readAsStringSync();
    final emptyCase = RegExp(
      r'case ShortcutAction\.(\w+):\s*(?://[^\n]*\n\s*)*break;',
    );
    expect(
      emptyCase.allMatches(source).map((m) => m.group(1)).toList(),
      isEmpty,
    );
  });
}
