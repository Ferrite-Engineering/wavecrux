// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/pane_id.dart';
import 'package:wavecrux/features/panes/widgets/wavecrux_pane_host.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../../../helpers/in_memory_workspace_service.dart';
import '../../../helpers/product_telemetry_config.dart';

// Verifies that WaveCruxPaneHost wires the crux_workspace 0.4.0 parity seams:
// the full context menu (monospace path header + Reveal + close block), the
// name-bearing close tooltip, and the whole-chip-drag leading insertion slot.
// The seam mechanics themselves are covered in the package's
// viewer_tab_bar_parity_seams_test.dart; this asserts WaveCrux opts into them.

ProviderContainer _makeContainer() {
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
  return container;
}

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Future<void> _pumpHost(
  WidgetTester tester, {
  required ProviderContainer container,
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: WaveCruxPaneHost(
            tabContentBuilder: (context, tab) => const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Collects the [Border]s of the per-pane container decorations. The pane
/// border is the only uniform 3 dp `Border.all` in the tree, so filtering on
/// that width isolates the pane borders from incidental decorations.
List<Border> _paneBorders(WidgetTester tester) {
  return tester
      .widgetList<Container>(find.byType(Container))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .map((d) => d.border)
      .whereType<Border>()
      .where((b) => b.top.width == 3)
      .toList();
}

void main() {
  group('WaveCruxPaneHost — locale sweep', () {
    for (final locale in _locales) {
      testWidgets('renders in $locale without exceptions', (tester) async {
        final container = _makeContainer();
        addTearDown(container.dispose);
        await container.read(workspaceProvider.future);
        await container.wavecruxWorkspace.openFile(
          '/tmp/cpu.vcd',
          displayName: 'cpu.vcd',
        );

        await _pumpHost(tester, container: container, locale: locale);

        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('un-split: the pane border is suppressed (transparent) — #46', (
    tester,
  ) async {
    final container = _makeContainer();
    addTearDown(container.dispose);
    await container.read(workspaceProvider.future);
    await container.wavecruxWorkspace.openFile(
      '/tmp/cpu.vcd',
      displayName: 'cpu.vcd',
    );

    await _pumpHost(tester, container: container);

    final borders = _paneBorders(tester);
    expect(borders, hasLength(1));
    // The sole pane carries a fully transparent border: nothing to
    // disambiguate when there is only one pane.
    expect(borders.single.top.color, Colors.transparent);
  });

  testWidgets(
    'split: borders are 3 dp on both panes (no squeeze) and only the active '
    'pane is accented — #45/#46',
    (tester) async {
      final container = _makeContainer();
      addTearDown(container.dispose);
      await container.read(workspaceProvider.future);
      await container.wavecruxWorkspace.openFile(
        '/tmp/cpu.vcd',
        displayName: 'cpu.vcd',
      );
      // A second pane makes the active-pane indicator meaningful.
      await container.wavecruxWorkspace.splitPaneRight();

      await _pumpHost(tester, container: container);

      final colorScheme = Theme.of(
        tester.element(find.byType(WaveCruxPaneHost)),
      ).colorScheme;

      final borders = _paneBorders(tester);
      expect(borders, hasLength(2));
      // Width is locked at 3 dp for BOTH states, so a focus switch never
      // resizes the content area (the issue #45 squeeze).
      expect(borders.every((b) => b.top.width == 3), isTrue);
      // Exactly one pane (the active one) is accented with primary; the other
      // shows the faint at-rest divider — neither is transparent now that the
      // workspace is split.
      final colors = borders.map((b) => b.top.color).toList();
      expect(colors, contains(colorScheme.primary));
      expect(colors.contains(Colors.transparent), isFalse);
      expect(colors.toSet(), hasLength(2));
    },
  );

  testWidgets('renders a name-bearing close tooltip and a leading drop slot', (
    tester,
  ) async {
    final container = _makeContainer();
    addTearDown(container.dispose);
    await container.read(workspaceProvider.future);
    await container.wavecruxWorkspace.openFile(
      '/tmp/cpu.vcd',
      displayName: 'cpu.vcd',
    );

    await _pumpHost(tester, container: container);

    // Whole-chip drag mode renders the keyed leading insertion slot.
    expect(
      find.byKey(ValueKey('tabInsertionSlot_${PaneId.primary.value}_0')),
      findsOneWidget,
    );

    // Close-button tooltip carries the tab name (re-uses tabChipCloseTooltip).
    final closeButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(IconButton),
      ),
    );
    expect(closeButton.tooltip, 'Close cpu.vcd');
  });

  testWidgets('context menu restores the full-path header + close actions', (
    tester,
  ) async {
    final container = _makeContainer();
    addTearDown(container.dispose);
    await container.read(workspaceProvider.future);
    await container.wavecruxWorkspace.openFile(
      '/tmp/cpu.vcd',
      displayName: 'cpu.vcd',
    );

    await _pumpHost(tester, container: container);

    await tester.tap(find.text('cpu.vcd'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    // Monospace full-path header (ARCHITECTURE §3.1.8.14) is back at the top.
    expect(find.text('/tmp/cpu.vcd'), findsOneWidget);
    // The standard close action and the Duplicate action are present.
    expect(find.text('Close Tab'), findsOneWidget);
    expect(find.text('Duplicate Tab'), findsOneWidget);
  });
}
