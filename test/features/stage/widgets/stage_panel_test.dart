// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/features/stage/providers/stage_selection_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_startup_render_gate_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/draggable_resizable_instance.dart';
import 'package:wavecrux/features/stage/widgets/stage_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/stage_registry.dart';
import 'package:wavecrux/services/host_bridge/editor_host_provider.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../../../helpers/product_telemetry_config.dart';

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

Widget _wrap({
  required Widget child,
  Locale locale = const Locale('en'),
  DeviceClass deviceClass = DeviceClass.desktop,
  EditorHostKind hostKind = EditorHostKind.none,
}) {
  final container = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      deviceClassProvider.overrideWithValue(deviceClass),
    ],
  );
  container.read(editorHostKindProvider.notifier).set(hostKind);
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() {
    StageRegistry.instance
      ..clear()
      ..register(const _LedStub());
  });

  tearDown(StageRegistry.instance.clear);

  group('StagePanel — locale sweep', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          _wrap(child: const StagePanel(), locale: Locale(locale)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('StagePanel — empty workspace', () {
    testWidgets('renders NO create-stage CTA — the empty state is retired', (
      tester,
    ) async {
      // Turning the Stage feature on seeds a default panel at the toggle
      // site, and closing the last panel's tab turns the feature off — so
      // this widget never legitimately renders over an empty workspace.
      // The defensive branch is a blank body, not a create-first CTA.
      await tester.pumpWidget(_wrap(child: const StagePanel()));
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Create Stage'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('StagePanel — phone gating', () {
    testWidgets('phone device class shows the unsupported message', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(child: const StagePanel(), deviceClass: DeviceClass.phone),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('unavailable on phone-class'),
        findsOneWidget,
      );
    });

    testWidgets('phone-landscape device class is also gated', (tester) async {
      await tester.pumpWidget(
        _wrap(
          child: const StagePanel(),
          deviceClass: DeviceClass.phoneLandscape,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('unavailable on phone-class'),
        findsOneWidget,
      );
    });

    testWidgets('tablet device class shows the panel', (tester) async {
      await tester.pumpWidget(
        _wrap(child: const StagePanel(), deviceClass: DeviceClass.tablet),
      );
      await tester.pumpAndSettle();
      // The panel body renders, not the phone-unsupported notice. (The
      // playback transport lives in the dock strip's action cluster, so an
      // empty workspace renders as a blank body — nothing but the absence
      // of the gate message to assert on.)
      expect(
        find.textContaining('unavailable on phone-class'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // Editor host: the Stage panel is
  // **present and empty with an explanation** inside an editor panel, never
  // omitted. An absent feature teaches nothing.
  group('StagePanel — editor host boundary', () {
    testWidgets('under a VSCode host the panel explains itself', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(child: const StagePanel(), hostKind: EditorHostKind.vscode),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('editorHostBoundaryTitle')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Stage needs the desktop app'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the explanation states why, not merely that', (tester) async {
      await tester.pumpWidget(
        _wrap(child: const StagePanel(), hostKind: EditorHostKind.vscode),
      );
      await tester.pumpAndSettle();
      // The fsdbWebUnsupportedMessage voice: what, why, and what to do.
      expect(find.textContaining('full application window'), findsOneWidget);
      expect(find.textContaining('loaded from disk'), findsOneWidget);
      expect(find.textContaining('desktop app'), findsWidgets);
    });

    testWidgets('nothing changes when no editor is hosting us', (tester) async {
      // `_wrap`'s default host kind is `none` — the desktop/browser case.
      await tester.pumpWidget(_wrap(child: const StagePanel()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editorHostBoundaryTitle')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the phone gate still wins over the editor-host gate', (
      tester,
    ) async {
      // Ordering matters: a phone in a webview is still a phone, and the
      // phone message is the more specific truth.
      await tester.pumpWidget(
        _wrap(
          child: const StagePanel(),
          deviceClass: DeviceClass.phone,
          hostKind: EditorHostKind.vscode,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('unavailable on phone-class'), findsOneWidget);
      expect(find.byKey(const Key('editorHostBoundaryTitle')), findsNothing);
    });
  });

  group('StagePanel — populated workspace', () {
    Future<ProviderContainer> pumpStage(WidgetTester tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productTelemetryConfig,
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const StagePanel();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('renders the active panel canvas with NO internal tab strip', (
      tester,
    ) async {
      // Panel selection moved to the bottom dock's strip (one dock tab per
      // Stage panel); the panel's old internal `_StageTabBar` — a second row
      // of tabs directly under the dock's — is gone. The panel name renders
      // only in the dock now, so it must NOT appear inside StagePanel.
      final container = await pumpStage(tester);

      container.read(stageWorkspaceProvider.notifier)
        ..addPanel('Bus Monitor')
        ..addInstance('led');
      await tester.pumpAndSettle();

      expect(find.text('Bus Monitor'), findsNothing);
      // Tile renders with the LED display name from the registry stub.
      expect(find.text('LED'), findsAtLeastNWidgets(1));
    });

    testWidgets(
      'startup render gate defers instance content to a placeholder, then '
      'releases to the real instances',
      (tester) async {
        final container = await pumpStage(tester);
        container.read(stageWorkspaceProvider.notifier)
          ..addPanel('Bus Monitor')
          ..addInstance('led');
        await tester.pumpAndSettle();

        // Ungated (default): the instance tile is built, no deferral spinner in
        // the canvas body.
        expect(find.byType(DraggableResizableInstance), findsOneWidget);

        // Engage the cold-start gate: the GPU-heavy instance content is held
        // back behind a lightweight placeholder so it stays out of the restore
        // burst (the concurrent-GPU-init crash mitigation).
        container.read(stageStartupRenderGateProvider.notifier).engage();
        // Not pumpAndSettle: the placeholder spinner animates forever.
        await tester.pump();
        expect(find.byType(DraggableResizableInstance), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // Release (as the restore's content frame would): the instances build.
        container.read(stageStartupRenderGateProvider.notifier).release();
        await tester.pumpAndSettle();
        expect(find.byType(DraggableResizableInstance), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );

    testWidgets('tapping empty canvas clears the selection', (tester) async {
      final container = await pumpStage(tester);
      final notifier = container.read(stageWorkspaceProvider.notifier)
        ..addPanel('Canvas');
      await tester.pumpAndSettle();
      final id = notifier.addInstance('led')!;
      await tester.pumpAndSettle();
      container.read(stageSelectedInstanceProvider.notifier).select(id);
      await tester.pumpAndSettle();
      expect(container.read(stageSelectedInstanceProvider), id);

      // Move the instance to the top-left so a tap in the lower-right of
      // the InteractiveViewer canvas lands on empty space (the canvas
      // GestureDetector with HitTestBehavior.translucent), which clears
      // the selection.
      container
          .read(stageWorkspaceProvider.notifier)
          .updateLayout(id, x: 0, y: 0);
      await tester.pumpAndSettle();
      final viewer = find.byType(InteractiveViewer);
      final rect = tester.getRect(viewer);
      await tester.tapAt(rect.bottomRight - const Offset(40, 40));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
      expect(container.read(stageSelectedInstanceProvider), isNull);
    });

    testWidgets('removing the last instance shows the no-instances message', (
      tester,
    ) async {
      final container = await pumpStage(tester);

      final notifier = container.read(stageWorkspaceProvider.notifier)
        ..addPanel('Test');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No widgets on this Stage panel'),
        findsOneWidget,
      );

      final id = notifier.addInstance('led')!;
      await tester.pumpAndSettle();
      expect(find.text('LED'), findsOneWidget);

      notifier.removeInstance(id);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No widgets on this Stage panel'),
        findsOneWidget,
      );
    });
  });

  // ── keyboard nudging + delete (canvas-scoped shortcuts) ───────────────────

  group('StagePanel — keyboard editing', () {
    /// Pumps a desktop StagePanel containing one panel + one selected
    /// instance and returns the workspace's `ProviderContainer` so the
    /// test can read the underlying state.
    ///
    /// The canvas's `Focus(autofocus: true, ...)` is best-effort in a
    /// test environment — pumping is sometimes not enough to actually
    /// move primary focus onto the canvas. The implementation tap-with-
    /// position grabs focus *and* clears selection, so we re-select
    /// after the tap; selection state is independent of focus.
    Future<(ProviderContainer, String)> pumpWithSelection(
      WidgetTester tester,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productTelemetryConfig,
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const StagePanel();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final notifier = container.read(stageWorkspaceProvider.notifier)
        ..addPanel('Test');
      await tester.pumpAndSettle();
      final id = notifier.addInstance('led')!;
      await tester.pumpAndSettle();
      // Explicitly request focus on the canvas's Focus widget. We tag
      // the FocusNode with the debugLabel 'StageInstanceCanvas' in
      // production code, so the test can identify it unambiguously
      // among the many Focus nodes a MaterialApp puts in the tree.
      final canvasFocus = tester
          .widgetList<Focus>(find.byType(Focus))
          .firstWhere(
            (f) => f.focusNode?.debugLabel == 'StageInstanceCanvas',
          );
      canvasFocus.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      // Establish selection so the keyboard callbacks have a target.
      container.read(stageSelectedInstanceProvider.notifier).select(id);
      await tester.pumpAndSettle();
      return (container, id);
    }

    StageWidgetSnapshot readInstance(
      ProviderContainer container,
      String id,
    ) {
      final ws = container.read(stageWorkspaceProvider);
      for (final p in ws.panels) {
        for (final i in p.instances) {
          if (i.id == id) {
            return StageWidgetSnapshot(x: i.x, y: i.y);
          }
        }
      }
      throw StateError('instance $id not found');
    }

    /// Returns the active `CallbackShortcuts.bindings` map for the
    /// canvas — there is exactly one in the populated workspace
    /// (the `_StageInstanceCanvasState` mounts it inside its
    /// `LayoutBuilder`).
    Map<ShortcutActivator, VoidCallback> bindings(WidgetTester tester) {
      return tester
          .widget<CallbackShortcuts>(find.byType(CallbackShortcuts))
          .bindings;
    }

    /// Invokes the callback registered for [activator] in the canvas's
    /// `CallbackShortcuts`. Bypasses the `tester.sendKeyEvent` /
    /// `HardwareKeyboard` path, which is flaky in widget tests because
    /// the canvas's autofocus does not deterministically claim primary
    /// focus before the test sends key events. Invoking the closure
    /// directly tests the wiring without depending on the focus
    /// machinery.
    void fire(WidgetTester tester, ShortcutActivator activator) {
      final cb = bindings(tester)[activator];
      expect(
        cb,
        isNotNull,
        reason: 'no callback registered for $activator',
      );
      cb!();
    }

    testWidgets('arrow right nudges the selected instance by 1 dp', (
      tester,
    ) async {
      final (container, id) = await pumpWithSelection(tester);
      final before = readInstance(container, id);
      fire(tester, const SingleActivator(LogicalKeyboardKey.arrowRight));
      await tester.pumpAndSettle();
      final after = readInstance(container, id);
      expect(after.x, before.x + kStageNudgeSmallStep);
      expect(after.y, before.y);
    });

    testWidgets('shift+arrow right nudges by kStageNudgeLargeStep', (
      tester,
    ) async {
      final (container, id) = await pumpWithSelection(tester);
      final before = readInstance(container, id);
      fire(
        tester,
        const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true),
      );
      await tester.pumpAndSettle();
      final after = readInstance(container, id);
      expect(after.x, before.x + kStageNudgeLargeStep);
    });

    testWidgets('arrow up clamps at the top edge', (tester) async {
      final (container, id) = await pumpWithSelection(tester);
      container
          .read(stageWorkspaceProvider.notifier)
          .updateLayout(id, x: 50, y: 0); // pin to the top edge
      await tester.pumpAndSettle();
      fire(tester, const SingleActivator(LogicalKeyboardKey.arrowUp));
      await tester.pumpAndSettle();
      expect(readInstance(container, id).y, 0);
    });

    testWidgets('Delete removes the selected instance', (tester) async {
      final (container, _) = await pumpWithSelection(tester);
      expect(
        container.read(stageWorkspaceProvider).panels.first.instances,
        hasLength(1),
      );
      fire(tester, const SingleActivator(LogicalKeyboardKey.delete));
      await tester.pumpAndSettle();
      expect(
        container.read(stageWorkspaceProvider).panels.first.instances,
        isEmpty,
      );
    });

    testWidgets('arrow with no selection is a no-op', (tester) async {
      final (container, id) = await pumpWithSelection(tester);
      container.read(stageSelectedInstanceProvider.notifier).clear();
      await tester.pumpAndSettle();
      final before = readInstance(container, id);
      fire(tester, const SingleActivator(LogicalKeyboardKey.arrowRight));
      await tester.pumpAndSettle();
      final after = readInstance(container, id);
      expect(after.x, before.x);
      expect(after.y, before.y);
    });

    testWidgets('arrow nudge is undoable (Stage workspace command stack)', (
      tester,
    ) async {
      final (container, id) = await pumpWithSelection(tester);
      final before = readInstance(container, id);
      fire(tester, const SingleActivator(LogicalKeyboardKey.arrowRight));
      await tester.pumpAndSettle();
      final notifier = container.read(stageWorkspaceProvider.notifier);
      expect(notifier.canUndo, isTrue);
      notifier.undo();
      await tester.pumpAndSettle();
      final reverted = readInstance(container, id);
      expect(reverted.x, before.x);
      expect(reverted.y, before.y);
    });

    testWidgets('canvas registers nudge + delete + backspace bindings', (
      tester,
    ) async {
      await pumpWithSelection(tester);
      final keys = bindings(tester).keys.whereType<SingleActivator>();
      // 4 plain arrows + 4 shift arrows + Delete + Backspace = 10.
      expect(keys.length, 10);
      // Spot-check the four cardinal arrows under both unshifted and
      // shifted activators.
      for (final logical in const [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
      ]) {
        expect(
          keys.any((k) => k.trigger == logical && !k.shift),
          isTrue,
          reason: 'missing plain $logical binding',
        );
        expect(
          keys.any((k) => k.trigger == logical && k.shift),
          isTrue,
          reason: 'missing shift+$logical binding',
        );
      }
    });
  });
}

/// Minimal value-type for the keyboard-editing tests above to read an
/// instance's position without leaking the full domain model into the
/// test surface.
class StageWidgetSnapshot {
  StageWidgetSnapshot({required this.x, required this.y});
  final double x;
  final double y;
}
