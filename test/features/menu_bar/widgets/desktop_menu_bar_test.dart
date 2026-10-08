// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_window_chrome/src/widgets/menu_mnemonics.dart';
import 'package:crux_window_chrome/src/widgets/window_caption_buttons.dart';
import 'package:crux_window_chrome/src/widgets/window_title_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/tier_gated_actions_available_provider.dart';
import 'package:wavecrux/core/shortcuts/action_category.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/core/shortcuts/action_descriptor.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/action_tier_label.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:wavecrux/features/menu_bar/widgets/desktop_menu_bar.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import '../../../helpers/in_memory_workspace_service.dart';
import '../../../helpers/product_telemetry_config.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

void _noop(ShortcutAction _) {}

Widget _wrap({
  required void Function(ShortcutAction) onAction,
  Widget? body,
  String? locale,
  DeviceClass deviceClass = DeviceClass.desktop,
  bool waveformLoaded = true,
  bool diagnosticsEnabled = true,
  TargetPlatform platform = TargetPlatform.macOS,
}) {
  return ProviderScope(
    overrides: [
      productTelemetryConfig,
      deviceClassProvider.overrideWithValue(deviceClass),
      waveformIsLoadedProvider.overrideWithValue(waveformLoaded),
      diagnosticsEnabledProvider.overrideWithValue(diagnosticsEnabled),
      workspaceServiceProvider.overrideWithValue(InMemoryWorkspaceService()),
      // The native menu bar only exists on a desktop OS, but flutter_test
      // reports TargetPlatform.android, so the provider's own default would
      // hide every PRO/ENT action and the surface-parity assertions below
      // would compare against a truncated table. Pin the desktop answer.
      tierGatedActionsAvailableProvider.overrideWithValue(true),
    ],
    child: MaterialApp(
      // The widget reads Theme.of(context).platform to decide whether to
      // wrap in a PlatformMenuBar. Default to a desktop OS so the menu bar
      // renders by default in tests (mirroring real-world desktop usage).
      theme: ThemeData(platform: platform),
      locale: locale != null ? Locale(locale) : null,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: DesktopMenuBar(
        onAction: onAction,
        child: Scaffold(body: body ?? const SizedBox.shrink()),
      ),
    ),
  );
}

/// Walks the [PlatformMenuBar.menus] tree and returns every leaf
/// [PlatformMenuItem] (i.e. items that are neither [PlatformMenu] containers nor
/// [PlatformMenuItemGroup] separator wrappers).
List<PlatformMenuItem> _allLeafItems(PlatformMenuBar bar) {
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

/// Walks a Material [MenuBar]'s [SubmenuButton] / [MenuItemButton] tree
/// (descending through nested submenus) and returns every leaf
/// [MenuItemButton]. The `menuChildren` are part of the widget configuration
/// even before the submenu is opened, so this needs no interaction.
List<MenuItemButton> _allMaterialItems(MenuBar bar) {
  final result = <MenuItemButton>[];
  void visit(Widget widget) {
    if (widget is SubmenuButton) {
      widget.menuChildren.forEach(visit);
    } else if (widget is MenuItemButton) {
      result.add(widget);
    }
  }

  bar.children.forEach(visit);
  return result;
}

void main() {
  group('DesktopMenuBar', () {
    // ── locale sweep ─────────────────────────────────────────────────────────

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders in $locale locale without exceptions', (
        tester,
      ) async {
        await tester.pumpWidget(_wrap(onAction: _noop, locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // ── platform gating (NOT device-class gating) ────────────────────────────
    //
    // The menu bar is gated on the host OS only. It used to also require
    // DeviceClass.desktop, which meant a Windows/Linux window narrower than
    // 1200 dp lost the whole widget — and with it the frameless window's
    // title bar and its min/maximize/close caption buttons, leaving no way to
    // close the window with the mouse. Window size is a layout concern; the
    // chrome is not. Phone and tablet still reach these commands through the
    // toolbar's ActionOverflowMenu, which the `overflow` surface feeds.

    testWidgets('on desktop: PlatformMenuBar is present in widget tree', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(onAction: _noop));
      await tester.pumpAndSettle();
      expect(find.byType(PlatformMenuBar), findsOneWidget);
    });

    for (final deviceClass in [
      DeviceClass.phone,
      DeviceClass.phoneLandscape,
      DeviceClass.tablet,
    ]) {
      testWidgets(
        'a ${deviceClass.name}-sized window on a desktop OS keeps its menu '
        'bar (and therefore its window chrome)',
        (tester) async {
          await tester.pumpWidget(
            _wrap(onAction: _noop, deviceClass: deviceClass),
          );
          await tester.pumpAndSettle();
          expect(find.byType(PlatformMenuBar), findsOneWidget);
        },
      );
    }

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets('on $platform: PlatformMenuBar is NOT present', (
        tester,
      ) async {
        // An iPad Pro 12.9" in landscape classifies as DeviceClass.desktop
        // (≥ 1200 dp), but Flutter bridges PlatformMenuBar to neither iOS nor
        // Android — so both fall through to the toolbar's overflow menu.
        await tester.pumpWidget(_wrap(onAction: _noop, platform: platform));
        await tester.pumpAndSettle();
        expect(find.byType(PlatformMenuBar), findsNothing);
      });
    }

    testWidgets('on a platform with no menu bar: child is rendered directly', (
      tester,
    ) async {
      const marker = Key('menu-bar-child');
      await tester.pumpWidget(
        _wrap(
          onAction: _noop,
          platform: TargetPlatform.android,
          body: const SizedBox(key: marker),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(marker), findsOneWidget);
    });

    // ── menu structure ───────────────────────────────────────────────────────

    testWidgets('produces one PlatformMenu per populated ActionCategory', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(onAction: _noop));
      await tester.pumpAndSettle();
      final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      // Every category, `edit` included since it gained
      // annotation authoring. An empty category still renders no menu rather
      // than an empty one; nothing exercises that path here any more. The
      // standard macOS Window menu adds one more, but only on a host that
      // actually supplies its provided items (never in a widget test).
      final windowMenu =
          PlatformProvidedMenuItem.hasMenu(
            PlatformProvidedMenuItemType.minimizeWindow,
          )
          ? 1
          : 0;
      expect(bar.menus.length, ActionCategory.values.length + windowMenu);
      for (final menu in bar.menus) {
        expect(menu, isA<PlatformMenu>());
      }
    });

    testWidgets('every menu-visible action appears as a leaf menu item', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(onAction: _noop));
      await tester.pumpAndSettle();
      final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      final leafLabels = _allLeafItems(bar).map((e) => e.label).toSet();
      // Every menu-visible action (per the single source of truth) should map
      // to a leaf label. We check by count to avoid l10n coupling. Visibility
      // is independent of file/diagnostics state on desktop, so any desktop
      // context yields the same count.
      // The harness binds the no-op collaboration service, so Join Session
      // (free, hidden where no real service is bound) is not on the menu.
      const ctx = ActionContext(
        fileLoaded: true,
        deviceClass: DeviceClass.desktop,
        diagnosticsEnabled: true,
        collaborationAvailable: false,
      );
      final expectedCount = groupedActionsFor(
        ActionSurface.menu,
        ctx,
      ).values.expand((x) => x).length;
      expect(leafLabels.length, expectedCount);
    });

    // ── file-loaded gating ───────────────────────────────────────────────────

    testWidgets(
      'when no file is loaded, file-dependent items have null onSelected',
      (tester) async {
        await tester.pumpWidget(
          _wrap(onAction: _noop, waveformLoaded: false),
        );
        await tester.pumpAndSettle();
        final bar = tester.widget<PlatformMenuBar>(
          find.byType(PlatformMenuBar),
        );
        final l10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
        final leafByLabel = {
          for (final item in _allLeafItems(bar)) item.label: item,
        };
        // closeFile is in the file-required set; should be disabled.
        final closeFileItem = leafByLabel[ShortcutAction.closeFile.label(l10n)];
        expect(closeFileItem, isNotNull);
        expect(closeFileItem!.onSelected, isNull);

        // zoomIn requires a file too.
        final zoomInItem = leafByLabel[ShortcutAction.zoomIn.label(l10n)];
        expect(zoomInItem, isNotNull);
        expect(zoomInItem!.onSelected, isNull);

        // openFile is always enabled.
        final openFileItem = leafByLabel[ShortcutAction.openFile.label(l10n)];
        expect(openFileItem, isNotNull);
        expect(openFileItem!.onSelected, isNotNull);
      },
    );

    testWidgets(
      'when a file is loaded, file-dependent items have non-null onSelected',
      (tester) async {
        // Issue 16: the menu bar derives `isLoaded` from the active tab's
        // filePath (not from [waveformIsLoadedProvider], which is per-tab and
        // always resolves false at the root menu-bar scope). Seed a tab with a
        // path so the active tab actually has one.
        await tester.pumpWidget(_wrap(onAction: _noop));
        final ctx = tester.element(find.byType(MaterialApp));
        await ProviderScope.containerOf(
          ctx,
        ).wavecruxWorkspace.openFile('/tmp/test.vcd');
        await tester.pumpAndSettle();
        final bar = tester.widget<PlatformMenuBar>(
          find.byType(PlatformMenuBar),
        );
        final l10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
        final leafByLabel = {
          for (final item in _allLeafItems(bar)) item.label: item,
        };
        final closeFileItem = leafByLabel[ShortcutAction.closeFile.label(l10n)];
        expect(closeFileItem, isNotNull);
        expect(closeFileItem!.onSelected, isNotNull);

        final zoomInItem = leafByLabel[ShortcutAction.zoomIn.label(l10n)];
        expect(zoomInItem, isNotNull);
        expect(zoomInItem!.onSelected, isNotNull);
      },
    );

    testWidgets(
      'openAppDiagnostics is disabled when diagnosticsEnabled is false',
      (tester) async {
        await tester.pumpWidget(
          _wrap(onAction: _noop, diagnosticsEnabled: false),
        );
        await tester.pumpAndSettle();
        final bar = tester.widget<PlatformMenuBar>(
          find.byType(PlatformMenuBar),
        );
        final l10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
        final diag = _allLeafItems(bar).firstWhere(
          (item) => item.label == ShortcutAction.openAppDiagnostics.label(l10n),
        );
        expect(diag.onSelected, isNull);
      },
    );

    testWidgets(
      'openAppDiagnostics is enabled when diagnosticsEnabled is true',
      (tester) async {
        await tester.pumpWidget(
          _wrap(onAction: _noop),
        );
        await tester.pumpAndSettle();
        final bar = tester.widget<PlatformMenuBar>(
          find.byType(PlatformMenuBar),
        );
        final l10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
        final diag = _allLeafItems(bar).firstWhere(
          (item) => item.label == ShortcutAction.openAppDiagnostics.label(l10n),
        );
        expect(diag.onSelected, isNotNull);
      },
    );

    // ── action dispatch ─────────────────────────────────────────────────────

    testWidgets('selecting a menu item invokes onAction with the action', (
      tester,
    ) async {
      ShortcutAction? dispatched;
      await tester.pumpWidget(_wrap(onAction: (a) => dispatched = a));
      await tester.pumpAndSettle();
      final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      final l10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
      final openFile = _allLeafItems(bar).firstWhere(
        (item) => item.label == ShortcutAction.openFile.label(l10n),
      );
      openFile.onSelected!();
      expect(dispatched, ShortcutAction.openFile);
    });

    testWidgets('shortcut metadata is attached for actions with bindings', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(onAction: _noop));
      await tester.pumpAndSettle();
      final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      final l10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
      final openFile = _allLeafItems(bar).firstWhere(
        (item) => item.label == ShortcutAction.openFile.label(l10n),
      );
      // openFile has a Ctrl/Cmd+O binding that is a SingleActivator and so
      // should map to a non-null platform shortcut.
      expect(openFile.shortcut, isNotNull);
    });

    testWidgets('bare-letter shortcuts are not native menu key-equivalents '
        '(no text-input hijack)', (tester) async {
      await tester.pumpWidget(_wrap(onAction: _noop));
      await tester.pumpAndSettle();
      final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      final l10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
      final leaves = _allLeafItems(bar);

      // Bare letters (Q/E transitions, M / ⇧M marker chords) must show no
      // native accelerator — they would otherwise be matched while typing.
      for (final action in const [
        ShortcutAction.prevTransition,
        ShortcutAction.nextTransition,
        ShortcutAction.setMarker,
        ShortcutAction.jumpToMarker,
      ]) {
        final item = leaves
            .where((i) => i.label == action.label(l10n))
            .toList();
        if (item.isEmpty) continue; // not surfaced in this menu config
        expect(
          item.first.shortcut,
          isNull,
          reason:
              '${action.name} is a bare-letter key and must not be a '
              'native menu key-equivalent',
        );
      }
    });

    // ── item placement (calibrated against VS Code) ──────────────────────────

    testWidgets('macOS: Settings lives in the application menu, not Help', (
      tester,
    ) async {
      // macOS is the default platform in [_wrap].
      await tester.pumpWidget(_wrap(onAction: _noop));
      await tester.pumpAndSettle();
      final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      final l10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
      final settingsLabel = ShortcutAction.openSettings.label(l10n);
      final aboutLabel = ShortcutAction.openAbout.label(l10n);

      // The application menu is the FIRST PlatformMenu (the OS renames it to the
      // bundle name). About, Settings and Quit all live there.
      final appMenu = bar.menus.first as PlatformMenu;
      final appLeaves = <String?>[];
      void collect(PlatformMenuItem item) {
        if (item is PlatformMenuItemGroup) {
          item.members.forEach(collect);
        } else {
          appLeaves.add(item.label);
        }
      }

      appMenu.menus.forEach(collect);
      expect(appLeaves, contains(settingsLabel));
      expect(appLeaves, contains(aboutLabel));

      // The Help menu must NOT contain Settings (the historic bug).
      final helpMenu =
          bar.menus.firstWhere(
                (m) => m.label == ActionCategory.help.label(l10n),
              )
              as PlatformMenu;
      final helpLeaves = <String?>[];
      void collectHelp(PlatformMenuItem item) {
        if (item is PlatformMenuItemGroup) {
          item.members.forEach(collectHelp);
        } else {
          helpLeaves.add(item.label);
        }
      }

      helpMenu.menus.forEach(collectHelp);
      expect(helpLeaves, isNot(contains(settingsLabel)));
    });

    // ── Windows / Linux: in-window Material MenuBar ──────────────────────────

    for (final platform in const [
      TargetPlatform.linux,
      TargetPlatform.windows,
    ]) {
      testWidgets('${platform.name}: renders a Material MenuBar, no '
          'PlatformMenuBar', (tester) async {
        const marker = Key('menu-bar-child');
        await tester.pumpWidget(
          _wrap(
            onAction: _noop,
            platform: platform,
            body: const SizedBox(key: marker),
          ),
        );
        await tester.pumpAndSettle();
        // PlatformMenuBar is a silent no-op on Win/Linux, so it must NOT be
        // used — a real in-window Material MenuBar is rendered instead.
        expect(find.byType(PlatformMenuBar), findsNothing);
        expect(find.byType(MenuBar), findsOneWidget);
        // The app body is still rendered below the menu bar.
        expect(find.byKey(marker), findsOneWidget);
      });

      testWidgets(
        '${platform.name}: menus are hosted in a left-aligned, full-width '
        'WindowTitleBar with caption buttons',
        (tester) async {
          await tester.pumpWidget(_wrap(onAction: _noop, platform: platform));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Menus live inline in the custom VS Code-style title bar (logo +
          // menus + caption buttons), not a bare centered strip.
          expect(find.byType(WindowTitleBar), findsOneWidget);
          expect(find.byType(MenuBar), findsOneWidget);
          expect(find.byType(WindowCaptionButtons), findsOneWidget);

          // The Column hosting the title bar stretches it full-width.
          final column = tester.widget<Column>(
            find
                .ancestor(
                  of: find.byType(WindowTitleBar),
                  matching: find.byType(Column),
                )
                .first,
          );
          expect(column.crossAxisAlignment, CrossAxisAlignment.stretch);

          // The title bar spans (near) the full window width...
          final barWidth = tester.getSize(find.byType(WindowTitleBar)).width;
          final windowWidth =
              tester.view.physicalSize.width / tester.view.devicePixelRatio;
          expect(barWidth, greaterThan(windowWidth * 0.9));

          // ...with the menus packed at the LEFT (left of the right-anchored
          // caption buttons), not centered.
          final menuLeft = tester.getTopLeft(find.byType(MenuBar)).dx;
          final captionLeft = tester
              .getTopLeft(find.byType(WindowCaptionButtons))
              .dx;
          expect(menuLeft, lessThan(windowWidth * 0.5));
          expect(menuLeft, lessThan(captionLeft));
        },
      );

      testWidgets(
        '${platform.name}: top-level menus expose Alt-mnemonic accelerators',
        (tester) async {
          await tester.pumpWidget(_wrap(onAction: _noop, platform: platform));
          await tester.pumpAndSettle();
          final bar = tester.widget<MenuBar>(find.byType(MenuBar));
          final tops = bar.children.whereType<SubmenuButton>().toList();
          expect(tops, isNotEmpty);
          for (final b in tops) {
            // Each top-level title is a MnemonicLabel carrying an '&' mnemonic
            // marker (underlined on Alt; MnemonicMenuBar binds Alt+<char> to open
            // the menu on Windows/Linux).
            expect(b.child, isA<MnemonicLabel>());
            expect((b.child! as MnemonicLabel).label, contains('&'));
          }
        },
      );

      testWidgets('${platform.name}: Settings + Quit fold into File, About in '
          'Help', (tester) async {
        await tester.pumpWidget(
          _wrap(onAction: _noop, platform: platform),
        );
        await tester.pumpAndSettle();
        final bar = tester.widget<MenuBar>(find.byType(MenuBar));
        final l10n = L10N.of(tester.element(find.byType(MenuBar)));

        // Top-level menu titles are MnemonicLabels (with '&' mnemonic
        // markers); strip the marker to compare against the plain label.
        String labelOf(SubmenuButton b) =>
            (b.child! as MnemonicLabel).label.replaceFirst('&', '');
        final fileMenu = bar.children.whereType<SubmenuButton>().firstWhere(
          (b) => labelOf(b) == ActionCategory.file.label(l10n),
        );
        final fileItems = fileMenu.menuChildren
            .whereType<MenuItemButton>()
            .map((b) => (b.child! as Text).data)
            .toList();
        expect(fileItems, contains(ShortcutAction.openSettings.label(l10n)));
        // Quit reads "Exit" here — the native Windows/Linux wording, and what
        // VS Code shows. "Quit WaveCrux" is the macOS application-menu form.
        expect(fileItems, contains(l10n.shortcutActionExit));
        expect(
          fileItems,
          isNot(contains(ShortcutAction.quit.label(l10n))),
          reason:
              'the macOS "Quit WaveCrux" wording must not leak to '
              '${platform.name}',
        );
        // Settings and Exit are the last two items, each its own group.
        expect(fileItems.last, l10n.shortcutActionExit);
        expect(
          fileItems[fileItems.length - 2],
          ShortcutAction.openSettings.label(l10n),
        );

        // There is no standalone branded "app" menu on Win/Linux.
        expect(
          bar.children.whereType<SubmenuButton>().map(labelOf),
          isNot(contains(ActionCategory.app.label(l10n))),
        );

        // About lives in Help on Win/Linux.
        final helpMenu = bar.children.whereType<SubmenuButton>().firstWhere(
          (b) => labelOf(b) == ActionCategory.help.label(l10n),
        );
        final helpItems = helpMenu.menuChildren
            .whereType<MenuItemButton>()
            .map((b) => (b.child! as Text).data)
            .toList();
        expect(helpItems, contains(ShortcutAction.openAbout.label(l10n)));
      });

      testWidgets(
        '${platform.name}: every menu-visible action appears exactly once',
        (tester) async {
          await tester.pumpWidget(
            _wrap(onAction: _noop, platform: platform),
          );
          await tester.pumpAndSettle();
          final bar = tester.widget<MenuBar>(find.byType(MenuBar));
          final l10n = L10N.of(tester.element(find.byType(MenuBar)));
          final labels = _allMaterialItems(
            bar,
          ).map((b) => (b.child! as Text).data).toList();
          // The harness binds the no-op collaboration service, so Join
          // Session (free, hidden where no real service is bound) is absent.
          const ctx = ActionContext(
            fileLoaded: true,
            deviceClass: DeviceClass.desktop,
            diagnosticsEnabled: true,
            collaborationAvailable: false,
          );
          final expected = groupedActionsFor(ActionSurface.menu, ctx).values
              .expand((x) => x)
              .map(
                (a) =>
                    // Quit renders as "Exit" off macOS — the one label the
                    // menu bar overrides per platform.
                    (a == ShortcutAction.quit
                        ? l10n.shortcutActionExit
                        : a.label(l10n)) +
                    tierLabelSuffix(descriptorFor(a).requiredTier, l10n),
              )
              .toList();
          expect(labels..sort(), equals(expected..sort()));
        },
      );

      testWidgets(
        '${platform.name}: file-dependent items disabled with no file',
        (tester) async {
          await tester.pumpWidget(
            _wrap(onAction: _noop, platform: platform, waveformLoaded: false),
          );
          await tester.pumpAndSettle();
          final bar = tester.widget<MenuBar>(find.byType(MenuBar));
          final l10n = L10N.of(tester.element(find.byType(MenuBar)));
          final byLabel = {
            for (final b in _allMaterialItems(bar)) (b.child! as Text).data: b,
          };
          // closeFile requires a file → disabled (null onPressed).
          expect(
            byLabel[ShortcutAction.closeFile.label(l10n)]!.onPressed,
            isNull,
          );
          // openFile is always enabled.
          expect(
            byLabel[ShortcutAction.openFile.label(l10n)]!.onPressed,
            isNotNull,
          );
        },
      );

      testWidgets('${platform.name}: selecting an item dispatches the action', (
        tester,
      ) async {
        ShortcutAction? dispatched;
        await tester.pumpWidget(
          _wrap(onAction: (a) => dispatched = a, platform: platform),
        );
        await tester.pumpAndSettle();
        final bar = tester.widget<MenuBar>(find.byType(MenuBar));
        final l10n = L10N.of(tester.element(find.byType(MenuBar)));
        final openFile = _allMaterialItems(bar).firstWhere(
          (b) => (b.child! as Text).data == ShortcutAction.openFile.label(l10n),
        );
        openFile.onPressed!();
        expect(dispatched, ShortcutAction.openFile);
      });
    }
  });
}
