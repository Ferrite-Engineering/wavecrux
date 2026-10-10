// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Cross-surface conformance: every action-discovery surface (toolbar, menu bar,
// the toolbar's overflow menu, command palette) must render exactly the actions
// — and exactly
// the enabled/disabled state — that the single-source-of-truth selectors in
// `action_descriptors.dart` prescribe, on every platform and in every scenario.
//
// Each surface reads the shared [actionContextProvider], so the harness simply
// overrides that provider with a precise [ActionContext] and asserts the
// rendered surface matches `groupedActionsFor` / `paletteActionsFor` /
// `isActionEnabled` for the same context. This keeps the assertions tied to the
// contract, not to any surface's internals.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_category.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/core/shortcuts/action_context_provider.dart';
import 'package:wavecrux/core/shortcuts/action_descriptor.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/action_tier_label.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/command_palette/widgets/command_palette_dialog.dart';
import 'package:wavecrux/features/menu_bar/widgets/desktop_menu_bar.dart';
import 'package:wavecrux/features/viewer/widgets/viewer_toolbar.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

void _noop(ShortcutAction _) {}

ActionContext _ctx({
  required bool fileLoaded,
  required DeviceClass deviceClass,
  bool diagnosticsEnabled = false,
  int paneCount = 1,
  bool inSession = false,
  bool isHost = false,
  bool isRecording = false,
}) => ActionContext(
  fileLoaded: fileLoaded,
  deviceClass: deviceClass,
  diagnosticsEnabled: diagnosticsEnabled,
  paneCount: paneCount,
  inSession: inSession,
  isHost: isHost,
  isRecording: isRecording,
);

Widget _wrap({
  required Widget home,
  required ActionContext ctx,
  String locale = 'en',
  TargetPlatform platform = TargetPlatform.macOS,
}) => ProviderScope(
  overrides: [
    actionContextProvider.overrideWithValue(ctx),
    deviceClassProvider.overrideWithValue(ctx.deviceClass),
  ],
  child: MaterialApp(
    theme: ThemeData(platform: platform),
    locale: Locale(locale),
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: home,
  ),
);

List<PlatformMenuItem> _leafItems(PlatformMenuBar bar) {
  final result = <PlatformMenuItem>[];
  void visit(PlatformMenuItem item) {
    if (item is PlatformMenu) {
      item.menus.forEach(visit);
    } else if (item is PlatformMenuItemGroup) {
      item.members.forEach(visit);
    } else {
      result.add(item);
    }
  }

  bar.menus.forEach(visit);
  return result;
}

String _menuLabel(ShortcutAction a, L10N l10n) =>
    a.label(l10n) + tierLabelSuffix(descriptorFor(a).requiredTier, l10n);

/// Every button now dispatches a [ShortcutAction] through one handler, so the
/// toolbar takes a dispatcher rather than a bag of per-button callbacks.
ViewerToolbar _toolbar() => const ViewerToolbar(
  onShortcutAction: _noop,
  isTransactionTableVisible: false,
  isStagePanelVisible: false,
);

void main() {
  // ── Menu bar (desktop) ─────────────────────────────────────────────────────
  group('DesktopMenuBar conformance', () {
    Future<(PlatformMenuBar, L10N)> pumpMenu(
      WidgetTester tester,
      ActionContext ctx,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ctx: ctx,
          home: const DesktopMenuBar(
            onAction: _noop,
            child: Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      final l10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
      return (bar, l10n);
    }

    testWidgets('presence matches groupedActionsFor(menu) incl. tier suffix', (
      tester,
    ) async {
      final ctx = _ctx(
        fileLoaded: true,
        deviceClass: DeviceClass.desktop,
        diagnosticsEnabled: true,
      );
      final (bar, l10n) = await pumpMenu(tester, ctx);
      final expected = groupedActionsFor(
        ActionSurface.menu,
        ctx,
      ).values.expand((x) => x).map((a) => _menuLabel(a, l10n)).toSet();
      expect(_leafItems(bar).map((e) => e.label).toSet(), equals(expected));
    });

    testWidgets('enablement matches isActionEnabled (no file, no session)', (
      tester,
    ) async {
      final ctx = _ctx(
        fileLoaded: false,
        deviceClass: DeviceClass.desktop,
        diagnosticsEnabled: true,
      );
      final (bar, l10n) = await pumpMenu(tester, ctx);
      final leafByLabel = {for (final i in _leafItems(bar)) i.label: i};
      for (final a in groupedActionsFor(
        ActionSurface.menu,
        ctx,
      ).values.expand((x) => x)) {
        final item = leafByLabel[_menuLabel(a, l10n)];
        expect(item, isNotNull, reason: '$a missing from menu');
        expect(
          item!.onSelected != null,
          isActionEnabled(a, ctx),
          reason: '$a enablement mismatch',
        );
      }
    });

    testWidgets('collaboration actions gate on session state (hosting)', (
      tester,
    ) async {
      final ctx = _ctx(
        fileLoaded: true,
        deviceClass: DeviceClass.desktop,
        diagnosticsEnabled: true,
        inSession: true,
        isHost: true,
      );
      final (bar, l10n) = await pumpMenu(tester, ctx);
      final leafByLabel = {for (final i in _leafItems(bar)) i.label: i};
      for (final a in [
        ShortcutAction.shareSession,
        ShortcutAction.stopSharing,
        ShortcutAction.leaveSession,
        ShortcutAction.exportSessionRecording,
      ]) {
        final item = leafByLabel[_menuLabel(a, l10n)];
        expect(item, isNotNull, reason: '$a missing');
        expect(
          item!.onSelected != null,
          isActionEnabled(a, ctx),
          reason: '$a enablement mismatch under hosting',
        );
      }
    });
  });

  // ── Overflow menu (phone bottom sheet) ──────────────────────────────────────
  // The overflow is the trailing menu of the mounted ViewerToolbar, shown once
  // the strip is too narrow for its buttons — on a phone, always. It lists the
  // `overflow` surface minus the App category, which the phone reaches through
  // the toolbar's Settings button and the palette.
  group('ViewerToolbar overflow conformance (phone)', () {
    Future<Map<ShortcutAction, ListTile>> openSheet(
      WidgetTester tester,
      ActionContext ctx,
    ) async {
      // A phone-narrow view, tall enough that the sheet's lazily built list
      // lays out every row at once.
      tester.view
        ..physicalSize = const Size(360, 8000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _wrap(
          ctx: ctx,
          platform: TargetPlatform.iOS,
          home: Scaffold(body: _toolbar()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      return {
        for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
          if (tile.key case ValueKey<ShortcutAction>(:final value)) value: tile,
      };
    }

    Set<ShortcutAction> expectedFor(ActionContext ctx) => {
      for (final MapEntry(key: category, value: actions) in groupedActionsFor(
        ActionSurface.overflow,
        ctx,
      ).entries)
        if (category != ActionCategory.app) ...actions,
    };

    testWidgets('presence matches groupedActionsFor(overflow) on phone', (
      tester,
    ) async {
      final ctx = _ctx(fileLoaded: true, deviceClass: DeviceClass.phone);
      final tiles = await openSheet(tester, ctx);
      expect(tiles.keys.toSet(), equals(expectedFor(ctx)));
    });

    testWidgets('enablement matches isActionEnabled on phone (no file)', (
      tester,
    ) async {
      final ctx = _ctx(fileLoaded: false, deviceClass: DeviceClass.phone);
      final tiles = await openSheet(tester, ctx);
      for (final a in expectedFor(ctx)) {
        final tile = tiles[a];
        expect(tile, isNotNull, reason: '$a missing from overflow');
        expect(
          tile!.enabled,
          isActionEnabled(a, ctx),
          reason: '$a enablement mismatch',
        );
      }
    });
  });

  // ── Command palette ─────────────────────────────────────────────────────────
  group('CommandPaletteDialog conformance', () {
    Future<void> pumpPalette(
      WidgetTester tester, {
      required ActionContext ctx,
      TargetPlatform platform = TargetPlatform.macOS,
      String locale = 'en',
    }) async {
      await tester.pumpWidget(
        _wrap(
          ctx: ctx,
          platform: platform,
          locale: locale,
          home: const Scaffold(body: CommandPaletteDialog(onAction: _noop)),
        ),
      );
      await tester.pumpAndSettle();
    }

    // Goal: the search field is present and functional on every platform type.
    for (final platform in TargetPlatform.values) {
      for (final deviceClass in [DeviceClass.desktop, DeviceClass.phone]) {
        testWidgets(
          'search field present + filters on $platform/$deviceClass',
          (tester) async {
            await pumpPalette(
              tester,
              ctx: _ctx(fileLoaded: true, deviceClass: deviceClass),
              platform: platform,
            );
            expect(find.byType(TextField), findsOneWidget);
            final l10n = L10N.of(
              tester.element(find.byType(CommandPaletteDialog)),
            );
            final open = ShortcutAction.openFile.label(l10n);
            await tester.enterText(find.byType(TextField), open);
            await tester.pumpAndSettle();
            expect(find.text(open), findsWidgets);
            await tester.enterText(find.byType(TextField), 'zzzqqq___');
            await tester.pumpAndSettle();
            expect(find.text(open), findsNothing);
          },
        );
      }
    }

    // A result *row* with [label] (scoped to the results list so the search
    // field's own typed text doesn't count as a match).
    Finder resultRow(String label) => find.descendant(
      of: find.byType(ListView),
      matching: find.text(label),
    );

    testWidgets('hidden families never appear (setFormat, tab jumps)', (
      tester,
    ) async {
      await pumpPalette(
        tester,
        ctx: _ctx(fileLoaded: true, deviceClass: DeviceClass.desktop),
      );
      final l10n = L10N.of(tester.element(find.byType(CommandPaletteDialog)));
      // nextTab / previousTab are NOT in this list: the suite menu-consistency
      // pass made them browsable (View → tab group), so they are legitimately
      // reachable from the palette too. Only the nine direct jump-to-tab-N
      // actions and the format setters stay accelerator-/context-only.
      for (final a in [
        ShortcutAction.setFormatBinary,
        ShortcutAction.setFormatHexadecimal,
        ShortcutAction.jumpToTab1,
      ]) {
        final label = a.label(l10n);
        await tester.enterText(find.byType(TextField), label);
        await tester.pumpAndSettle();
        expect(resultRow(label), findsNothing, reason: '$a should be hidden');
      }
    });

    testWidgets('file-gated actions are absent without a file, present with', (
      tester,
    ) async {
      await pumpPalette(
        tester,
        ctx: _ctx(fileLoaded: false, deviceClass: DeviceClass.desktop),
      );
      final l10n = L10N.of(tester.element(find.byType(CommandPaletteDialog)));
      final zoom = ShortcutAction.zoomIn.label(l10n);
      await tester.enterText(find.byType(TextField), zoom);
      await tester.pumpAndSettle();
      expect(resultRow(zoom), findsNothing);

      await pumpPalette(
        tester,
        ctx: _ctx(fileLoaded: true, deviceClass: DeviceClass.desktop),
      );
      await tester.enterText(find.byType(TextField), zoom);
      await tester.pumpAndSettle();
      expect(resultRow(zoom), findsWidgets);
    });
  });

  // ── Toolbar (full layout) ───────────────────────────────────────────────────
  group('ViewerToolbar conformance', () {
    Future<void> pumpToolbar(WidgetTester tester, ActionContext ctx) async {
      await tester.pumpWidget(
        _wrap(
          ctx: ctx,
          home: Scaffold(body: _toolbar()),
        ),
      );
      await tester.pumpAndSettle();
    }

    // Per the descriptor contract an action appears in a surface iff the
    // surface is listed AND `isVisible(ctx)` holds — so the expectation is
    // context-dependent. Stop Streaming is the case that makes it matter: it
    // lists the toolbar but is structurally hidden unless a stream is live.
    Iterable<ShortcutAction> toolbarActions(ActionContext ctx) =>
        ShortcutAction.values.where(
          (a) =>
              descriptorFor(a).surfaces.contains(ActionSurface.toolbar) &&
              descriptorFor(a).isVisible(ctx) &&
              // Rendered on touch form factors only; see ViewerToolbar and
              // the tablet test in viewer_toolbar_test.dart.
              a != ShortcutAction.openCommandPalette,
        );

    testWidgets('every toolbar action has a button, enabled per descriptor', (
      tester,
    ) async {
      for (final fileLoaded in [false, true]) {
        final ctx = _ctx(
          fileLoaded: fileLoaded,
          deviceClass: DeviceClass.desktop,
        );
        await pumpToolbar(tester, ctx);
        for (final a in toolbarActions(ctx)) {
          final keyFinder = find.byKey(ValueKey(a));
          expect(keyFinder, findsOneWidget, reason: '$a button missing');
          final button = tester.widget<IconButton>(
            find.descendant(of: keyFinder, matching: find.byType(IconButton)),
          );
          expect(
            button.onPressed != null,
            isActionEnabled(a, ctx),
            reason: '$a enablement mismatch (fileLoaded=$fileLoaded)',
          );
        }
      }
    });
  });

  // ── Locale sweep ────────────────────────────────────────────────────────────
  group('locale sweep', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('palette renders in $locale without exceptions', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            ctx: _ctx(fileLoaded: true, deviceClass: DeviceClass.desktop),
            locale: locale,
            home: const Scaffold(body: CommandPaletteDialog(onAction: _noop)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
