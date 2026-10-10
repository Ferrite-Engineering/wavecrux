// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_toolbar/crux_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_category.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/core/shortcuts/action_context_provider.dart';
import 'package:wavecrux/core/shortcuts/action_descriptor.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/viewer/widgets/viewer_toolbar.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

/// A file loaded with a cursor, a selection and the panels open — every
/// descriptor gate the toolbar reads is satisfied, so the buttons are live.
const _loaded = ActionContext(
  fileLoaded: true,
  deviceClass: DeviceClass.desktop,
  diagnosticsEnabled: true,
  cursorPresent: true,
  hasSelection: true,
  stageViewVisible: true,
);

Widget _wrap({
  ActionContext ctx = _loaded,
  void Function(ShortcutAction)? onShortcutAction,
  bool isTransactionTableVisible = false,
  bool isStagePanelVisible = false,
  List<Override> overrides = const [],
  TargetPlatform platform = TargetPlatform.macOS,
  double width = 1400,
}) => ProviderScope(
  overrides: [
    actionContextProvider.overrideWithValue(ctx),
    deviceClassProvider.overrideWithValue(ctx.deviceClass),
    ...overrides,
  ],
  child: MaterialApp(
    theme: ThemeData(platform: platform),
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: ViewerToolbar(
          onShortcutAction: onShortcutAction ?? (_) {},
          isTransactionTableVisible: isTransactionTableVisible,
          isStagePanelVisible: isStagePanelVisible,
        ),
      ),
    ),
  ),
);

/// Every action the strip currently renders a button for.
Set<ShortcutAction> _rendered(WidgetTester tester) => tester
    .widgetList<CruxToolbarButton>(find.byType(CruxToolbarButton))
    .where((b) => b.key is ValueKey<ShortcutAction>)
    .map((b) => (b.key! as ValueKey<ShortcutAction>).value)
    .toSet();

IconButton _buttonFor(WidgetTester tester, ShortcutAction a) =>
    tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(ValueKey<ShortcutAction>(a)),
        matching: find.byType(IconButton),
      ),
    );

/// The same loaded context, but with a live streaming session.
const _streaming = ActionContext(
  fileLoaded: true,
  deviceClass: DeviceClass.desktop,
  diagnosticsEnabled: true,
  cursorPresent: true,
  hasSelection: true,
  stageViewVisible: true,
  streamingActive: true,
);

void main() {
  group('ViewerToolbar', () {
    testWidgets('renders through the shared CruxToolbar', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CruxToolbar<ShortcutAction>), findsOneWidget);
    });

    testWidgets('leads with the canonical common block, in suite order', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // Open · Save · Close │ Search · Cross-Probe · Settings — the six
      // buttons that mean the same thing in all four products.
      const common = [
        ShortcutAction.openFile,
        ShortcutAction.saveSession,
        ShortcutAction.closeFile,
        ShortcutAction.openSearch,
        ShortcutAction.openCrossProbePanel,
        ShortcutAction.openSettings,
      ];
      final xs = [
        for (final a in common)
          tester.getCenter(find.byKey(ValueKey<ShortcutAction>(a))).dx,
      ];
      expect(
        xs,
        orderedEquals(List<double>.from(xs)..sort()),
        reason: 'the common block must render in the canonical order',
      );
      for (final a in [ShortcutAction.zoomIn, ShortcutAction.addDecoder]) {
        expect(
          tester.getCenter(find.byKey(ValueKey<ShortcutAction>(a))).dx,
          greaterThan(xs.last),
          reason: '$a is app-specific and belongs after the section divider',
        );
      }
    });

    testWidgets('every rendered button declares the toolbar surface', (
      tester,
    ) async {
      // The direction the old conformance test did not check. It caught
      // openCrossProbePanel, which had a button and a descriptor that listed
      // menu/overflow/palette only.
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      for (final action in _rendered(tester)) {
        expect(
          descriptorFor(action).surfaces,
          contains(ActionSurface.toolbar),
          reason:
              '${action.name} has a toolbar button but its descriptor does '
              'not list ActionSurface.toolbar',
        );
      }
    });

    group('command palette on touch form factors', () {
      const tablet = ActionContext(
        fileLoaded: true,
        deviceClass: DeviceClass.tablet,
        diagnosticsEnabled: true,
        cursorPresent: true,
        hasSelection: true,
        stageViewVisible: true,
      );

      testWidgets('a tablet wide enough not to overflow opens the palette by '
          'touch, with no keyboard', (tester) async {
        // 1600 dp fits the whole strip, so the overflow menu is not painted:
        // the strip button is the only touch path.
        tester.view.physicalSize = const Size(1600, 400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final dispatched = <ShortcutAction>[];
        await tester.pumpWidget(
          _wrap(
            ctx: tablet,
            platform: TargetPlatform.iOS,
            width: 1600,
            onShortcutAction: dispatched.add,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byIcon(Icons.more_vert),
          findsNothing,
          reason: 'precondition: the strip does not overflow at this width',
        );
        final button = find.byKey(
          const ValueKey<ShortcutAction>(ShortcutAction.openCommandPalette),
        );
        expect(button, findsOneWidget);

        await tester.tap(button);
        await tester.pump();
        expect(dispatched, <ShortcutAction>[ShortcutAction.openCommandPalette]);
      });

      testWidgets('the button is on a phone strip too, and not on desktop', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            ctx: const ActionContext(
              fileLoaded: true,
              deviceClass: DeviceClass.phone,
            ),
            platform: TargetPlatform.android,
          ),
        );
        await tester.pumpAndSettle();
        expect(_rendered(tester), contains(ShortcutAction.openCommandPalette));

        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        expect(
          _rendered(tester),
          isNot(contains(ShortcutAction.openCommandPalette)),
        );
      });
    });

    testWidgets('Save Session As is deliberately NOT on the strip', (
      tester,
    ) async {
      // A Save-As button one pixel from Save is the most mis-clickable pair a
      // toolbar can offer; it keeps its menu item and its chord.
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(_rendered(tester), isNot(contains(ShortcutAction.saveSessionAs)));
      expect(
        descriptorFor(ShortcutAction.saveSessionAs).surfaces,
        isNot(contains(ActionSurface.toolbar)),
      );
    });

    group('streaming chrome', () {
      testWidgets('no LIVE badge and no Stop button when nothing streams', (
        tester,
      ) async {
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        expect(
          _rendered(tester),
          isNot(contains(ShortcutAction.stopStreaming)),
        );
        expect(
          find.text(
            L10N
                .of(tester.element(find.byType(ViewerToolbar)))
                .streamingLiveLabel,
          ),
          findsNothing,
        );
      });

      testWidgets('both appear while a stream is live', (tester) async {
        await tester.pumpWidget(_wrap(ctx: _streaming));
        // The badge pulses forever, so `pumpAndSettle` would never return.
        await tester.pump();
        expect(_rendered(tester), contains(ShortcutAction.stopStreaming));
        expect(
          _buttonFor(tester, ShortcutAction.stopStreaming).onPressed,
          isNotNull,
        );
      });

      testWidgets('Stop dispatches the action rather than a bare callback', (
        tester,
      ) async {
        // It used to be a `VoidCallback` threaded down from ViewerScreen —
        // mouse-only, and invisible to the menu, palette and keymap editor.
        //
        // Stop sits at the far right of the strip, past the 800 dp default
        // test view, so the surface has to be wide enough to hit-test it.
        tester.view.physicalSize = const Size(1600, 400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final dispatched = <ShortcutAction>[];
        await tester.pumpWidget(
          _wrap(ctx: _streaming, onShortcutAction: dispatched.add),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(
            const ValueKey<ShortcutAction>(ShortcutAction.stopStreaming),
          ),
        );
        await tester.pump();
        expect(dispatched, <ShortcutAction>[ShortcutAction.stopStreaming]);
      });
    });

    group('Stage Playback glyph', () {
      testWidgets('renders NO play/pause glyph — the transport lives in the '
          "Stage dock tab's action cluster", (tester) async {
        // The toolbar's play/pause duplicated the Stage transport; both are
        // gone in favor of the dock strip's per-active-tab playback actions.
        await tester.pumpWidget(
          _wrap(
            ctx: const ActionContext(
              fileLoaded: true,
              deviceClass: DeviceClass.desktop,
              stageViewVisible: true,
              playbackActive: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.play_circle_outline), findsNothing);
        expect(find.byIcon(Icons.pause_circle_outline), findsNothing);
      });
    });

    group('enablement comes from the descriptor table', () {
      testWidgets('greys the file-gated buttons with no file loaded', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            ctx: const ActionContext(
              fileLoaded: false,
              deviceClass: DeviceClass.desktop,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          _buttonFor(tester, ShortcutAction.openFile).onPressed,
          isNotNull,
        );
        expect(_buttonFor(tester, ShortcutAction.zoomIn).onPressed, isNull);
        expect(_buttonFor(tester, ShortcutAction.closeFile).onPressed, isNull);
        expect(_buttonFor(tester, ShortcutAction.addDecoder).onPressed, isNull);
      });

      testWidgets('enables them once a file is loaded', (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        expect(_buttonFor(tester, ShortcutAction.zoomIn).onPressed, isNotNull);
        expect(
          _buttonFor(tester, ShortcutAction.closeFile).onPressed,
          isNotNull,
        );
      });

      testWidgets('transition buttons follow their cursor requirement', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            ctx: const ActionContext(
              fileLoaded: true,
              deviceClass: DeviceClass.desktop,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          _buttonFor(tester, ShortcutAction.nextTransition).onPressed,
          isNull,
          reason: 'no cursor placed',
        );

        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        expect(
          _buttonFor(tester, ShortcutAction.nextTransition).onPressed,
          isNotNull,
        );
      });
    });

    testWidgets('dispatches the action for the tapped button', (tester) async {
      final fired = <ShortcutAction>[];
      await tester.pumpWidget(_wrap(onShortcutAction: fired.add));
      await tester.pumpAndSettle();
      for (final action in [
        ShortcutAction.openFile,
        ShortcutAction.saveSession,
        ShortcutAction.openSearch,
        ShortcutAction.openSettings,
        ShortcutAction.zoomIn,
        ShortcutAction.addDecoder,
      ]) {
        fired.clear();
        await tester.tap(find.byKey(ValueKey<ShortcutAction>(action)));
        await tester.pump();
        expect(fired, [action], reason: 'tapping $action should dispatch it');
      }
    });

    testWidgets('App Diagnostics dispatches its action rather than a '
        'private callback', (tester) async {
      // The old "Developer Tools" button called AppDiagnosticsDialog.open
      // through its own callback while openAppDiagnostics already existed and
      // did exactly that, so the dialog had two entry points and one of them
      // was invisible to the palette, the menu and the keymap editor.
      final fired = <ShortcutAction>[];
      await tester.pumpWidget(_wrap(onShortcutAction: fired.add));
      await tester.pumpAndSettle();
      const key = ValueKey<ShortcutAction>(
        ShortcutAction.openAppDiagnostics,
      );
      if (find.byKey(key).evaluate().isEmpty) return; // release build
      await tester.tap(find.byKey(key));
      await tester.pump();
      expect(fired, [ShortcutAction.openAppDiagnostics]);
    });

    testWidgets('panel toggles swap glyph with their open state', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.table_chart_outlined), findsOneWidget);

      await tester.pumpWidget(_wrap(isTransactionTableVisible: true));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.table_chart), findsOneWidget);
    });

    testWidgets('shows the overflow button only when the strip overflows', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.more_vert), findsNothing);

      await tester.pumpWidget(_wrap(width: 300));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('uses touch metrics on a touch device class', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ctx: const ActionContext(
            fileLoaded: true,
            deviceClass: DeviceClass.phone,
          ),
          width: 400,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(
              find.byKey(
                const ValueKey<ShortcutAction>(ShortcutAction.openFile),
              ),
            )
            .width,
        CruxToolbarMetrics.touch.buttonSize,
        reason: 'touch hit boxes must clear the 44 dp minimum',
      );
    });

    testWidgets('tooltips carry the action label plus its live binding', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(ViewerToolbar)));
      final tooltips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message ?? '')
          .toList();
      // The accelerator is resolved at render time now, not written into the
      // ARB string — five keys used to spell it into the label across five
      // locales, which a rebind made wrong.
      expect(
        tooltips.any(
          (m) => m.startsWith(ShortcutAction.zoomIn.label(l10n)),
        ),
        isTrue,
      );
      expect(
        tooltips.any((m) => m.contains('(W)')),
        isFalse,
        reason: 'the chord must not be baked into the label',
      );
    });

    // The overflow is the phone's menu bar. These are the checks that used to
    // run against a stand-alone overflow widget the app never mounted; they
    // now run against the overflow the toolbar actually renders.
    group('overflow menu', () {
      /// A phone-narrow view, tall enough for the sheet's lazily built list to
      /// lay out every row at once.
      void phoneView(WidgetTester tester) {
        tester.view
          ..physicalSize = const Size(360, 8000)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      }

      Set<ShortcutAction> rows(WidgetTester tester) => {
        for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
          if (tile.key case ValueKey<ShortcutAction>(:final value)) value,
      };

      // This is the exact surface, on the exact device class, that produced
      // an App Store rejection: a reviewer opened the phone overflow sheet,
      // tapped PRO/ENT rows such as "Share Session", and nothing happened —
      // Open Core's handlers for them are empty. On a mobile Open Core build
      // those rows must not exist at all.
      testWidgets('Open Core on a phone lists no PRO/ENT rows', (tester) async {
        phoneView(tester);
        const ctx = ActionContext(
          fileLoaded: true,
          deviceClass: DeviceClass.phone,
          diagnosticsEnabled: true,
          tierGatedActionsAvailable: false,
        );
        await tester.pumpWidget(_wrap(ctx: ctx, width: 360));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);

        final listed = rows(tester);
        final tierGated = ShortcutAction.values.where(
          (a) => descriptorFor(a).requiredTier != LicenseTier.openCore,
        );
        expect(tierGated, isNotEmpty);
        expect(listed.intersection(tierGated.toSet()), isEmpty);
        // …and the Open Core rows are all still there, so the suppression did
        // not simply empty the sheet.
        expect(listed, {
          for (final MapEntry(key: category, value: actions)
              in groupedActionsFor(ActionSurface.overflow, ctx).entries)
            if (category != ActionCategory.app) ...actions,
        });
      });

      testWidgets('a tapped row dispatches its action and closes the sheet', (
        tester,
      ) async {
        phoneView(tester);
        ShortcutAction? dispatched;
        await tester.pumpWidget(
          _wrap(
            ctx: const ActionContext(
              fileLoaded: true,
              deviceClass: DeviceClass.phone,
            ),
            width: 360,
            onShortcutAction: (a) => dispatched = a,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byKey(
              const ValueKey<ShortcutAction>(ShortcutAction.addDecoder),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(dispatched, ShortcutAction.addDecoder);
        expect(find.byType(BottomSheet), findsNothing);
      });

      testWidgets('a tablet gets a popup menu, not a sheet', (tester) async {
        await tester.pumpWidget(
          _wrap(
            ctx: const ActionContext(
              fileLoaded: true,
              deviceClass: DeviceClass.tablet,
            ),
            width: 300,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        final l10n = L10N.of(tester.element(find.byType(ViewerToolbar)));
        expect(
          find.text(ActionCategory.file.label(l10n).toUpperCase()),
          findsOneWidget,
        );
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
                actionContextProvider.overrideWithValue(_loaded),
                deviceClassProvider.overrideWithValue(DeviceClass.desktop),
              ],
              child: MaterialApp(
                locale: locale,
                theme: ThemeData(platform: TargetPlatform.macOS),
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: Scaffold(
                  body: SizedBox(
                    width: 1400,
                    child: ViewerToolbar(
                      onShortcutAction: (_) {},
                      isTransactionTableVisible: false,
                      isStagePanelVisible: false,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    });
  });
}
