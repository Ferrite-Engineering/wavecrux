// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Keyboard-dispatch conformance: the shortcut path is the FIFTH action surface
// and must obey the same single source of truth as the other four.
//
// `action_surface_conformance_test.dart` proves the toolbar, menu bar, overflow
// menu, and command palette all render exactly what `descriptorFor` prescribes.
// Nothing proved the same for the keyboard, and the 2026-07-19 audit found two
// live divergences behind that gap:
//
//   * `jumpToStart` / `jumpToEnd` — the handler guarded only `mapper.isEmpty`
//     while the descriptor requires a file AND a cursor, so the keys panned the
//     viewport in a state where all four visible surfaces greyed the action out.
//   * `shareSession` / `joinSession` — the handlers opened their dialogs
//     unconditionally while the descriptor requires `_notInSession`, so the key
//     could stack a second Share dialog on top of a live session.
//
// `_ViewerScreenShortcuts._handleShortcut` now refuses any action whose
// descriptor reports an unmet [ActionRequirement]. This test locks that in
// table-driven form: mount [ViewerScreen] under a deliberately impoverished
// [ActionContext] and fire EVERY action the table reports as disabled,
// asserting none of them runs (no pushed route, no thrown exception).
//
// The guard is not silent, though — that was the descriptor-parity
// regression this follow-on closes. A greyed menu item explains itself; a dead key does not,
// and the original early-return swallowed the Add Decoder "load a waveform
// file" guidance. So the sweep also asserts the POSITIVE half: every refused
// shortcut surfaces the localized hint for its own unmet requirement, and no
// other. That pairing is what keeps a future "just return early" edit from
// re-breaking the feedback while the parity assertions stay green.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/core/shortcuts/action_context_provider.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/action_requirement.dart';
import 'package:wavecrux/core/shortcuts/action_requirement_label.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/features/viewer/widgets/viewer_toolbar.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../../helpers/product_telemetry_config.dart';

/// In-memory [WorkspaceService] — widget tests have no `path_provider`.
/// Pins the single pane to [PaneId.primary] so the seeded placeholder tab
/// (which carries the primary sentinel) actually renders.
class _InMemoryWorkspaceService implements WorkspaceService {
  @override
  Future<Workspace> load() async {
    const pane = WorkspacePane(id: PaneId.primary);
    return Workspace(
      tabs: const [],
      panes: const [pane],
      activePaneId: PaneId.primary,
    );
  }

  @override
  Future<void> save(Workspace workspace) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal mirror of `viewer_screen_test.dart`'s `_TestProviderScope`:
/// [ViewerScreen] reads [tabContainerManagerProvider] at build time, so the
/// managers must be live before the tree builds.
class _Scope extends StatefulWidget {
  const _Scope({required this.overrides, required this.child});

  final List<Override> overrides;
  final Widget child;

  @override
  State<_Scope> createState() => _ScopeState();
}

class _ScopeState extends State<_Scope> {
  late final TabContainerManager _tcm;
  late final PaneContainerManager _pcm;
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _tcm = TabContainerManager();
    _pcm = PaneContainerManager();
    _container = ProviderContainer(
      overrides: [
        productTelemetryConfig,
        tabContainerManagerProvider.overrideWithValue(_tcm),
        paneContainerManagerProvider.overrideWithValue(_pcm),
        workspaceServiceProvider.overrideWithValue(_InMemoryWorkspaceService()),
        ...widget.overrides,
      ],
    );
    _tcm.init(_container);
    _pcm.init(_container);
    unawaited(_container.wavecruxWorkspace.newTab(displayName: 'New Tab'));
  }

  @override
  void dispose() {
    _tcm.dispose();
    _pcm.dispose();
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      UncontrolledProviderScope(container: _container, child: widget.child);
}

class _RouteSpy extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // The home route itself is pushed at mount; only count later pushes.
    if (previousRoute != null) pushed.add(route);
  }
}

/// The impoverished context: nothing loaded, nothing selected, no cursor, no
/// markers, no session, no diagnostics. Everything the table can disable IS
/// disabled here, which is what makes the sweep below meaningful.
// (Every other `ActionContext` field already defaults to the "nothing
// available" value, so only the non-default ones are named here.)
const _disabledCtx = ActionContext(
  fileLoaded: false,
  deviceClass: DeviceClass.desktop,
);

void main() {
  final disabledActions = ShortcutAction.values
      .where((a) => !isActionEnabled(a, _disabledCtx))
      .toList();

  test('the impoverished context actually disables a meaningful set', () {
    // Guards the guard: if a refactor made `isEnabled` unconditionally true the
    // sweep below would pass vacuously.
    expect(disabledActions, isNotEmpty);
    expect(
      disabledActions,
      containsAll(<ShortcutAction>[
        ShortcutAction.jumpToStart,
        ShortcutAction.jumpToEnd,
      ]),
      reason: 'jumpToStart/jumpToEnd require file AND cursor per the table',
    );
  });

  testWidgets(
    'every descriptor-disabled action is refused AND explains itself when its '
    'shortcut is fired',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final spy = _RouteSpy();
      await tester.pumpWidget(
        _Scope(
          overrides: [actionContextProvider.overrideWithValue(_disabledCtx)],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            navigatorObservers: [spy],
            home: const ViewerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final anchor = tester.element(find.byType(ViewerToolbar));
      final l10n = L10N.of(anchor);

      for (final action in disabledActions) {
        Actions.invoke(anchor, ShortcutActionIntent(action));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          spy.pushed,
          isEmpty,
          reason:
              '$action is disabled in this context but its handler pushed a '
              'route — the dispatch guard did not run',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '$action threw while disabled',
        );

        final unmet = unmetActionRequirement(action, _disabledCtx);
        expect(
          unmet,
          isNotNull,
          reason: '$action is disabled, so it must name an unmet requirement',
        );
        expect(
          find.text(unmet!.hint(l10n)),
          findsOneWidget,
          reason:
              '$action was refused without telling the user why — the guard '
              'must surface the hint for $unmet',
        );

        // Clear the hint before the next action so each iteration asserts on
        // its own snackbar rather than a leftover.
        ScaffoldMessenger.of(anchor).removeCurrentSnackBar();
        await tester.pump();
      }
    },
  );

  testWidgets('the hint renders in every supported locale', (tester) async {
    // Locale sweep (CLAUDE.md): the hints are the only new user-visible
    // strings, and they render inside a width-constrained SnackBar where a CJK
    // line-break failure would show up as an overflow.
    for (final locale in L10N.supportedLocales) {
      late L10N l10n;
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = L10N.of(context);
              return Scaffold(
                body: Column(
                  children: [
                    for (final r in ActionRequirement.values)
                      Text(r.hint(l10n)),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: 'locale $locale');
      final hints = ActionRequirement.values.map((r) => r.hint(l10n)).toList();
      for (final hint in hints) {
        expect(hint, isNotEmpty, reason: 'locale $locale');
      }
      expect(
        hints.toSet(),
        hasLength(hints.length),
        reason:
            'locale $locale reuses one hint for two requirements — the user '
            'would be told the wrong remedy',
      );
    }
  });
}
