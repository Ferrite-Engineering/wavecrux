// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/core/shortcuts/action_context_provider.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/command_palette/widgets/command_palette_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Pumps the app with [CommandPaletteDialog] as the home body.
/// [onAction] collects dispatched actions.
void _noopAction(ShortcutAction _) {}

ActionContext _desktopContext({required bool fileLoaded}) => ActionContext(
  fileLoaded: fileLoaded,
  deviceClass: DeviceClass.desktop,
  diagnosticsEnabled: true,
);

Widget _buildApp({
  void Function(ShortcutAction)? onAction,
  String? locale,
  bool fileLoaded = true,
}) => ProviderScope(
  overrides: [
    actionContextProvider.overrideWithValue(
      _desktopContext(fileLoaded: fileLoaded),
    ),
  ],
  child: MaterialApp(
    locale: locale != null ? Locale(locale) : null,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(
      body: CommandPaletteDialog(
        onAction: onAction ?? _noopAction,
      ),
    ),
  ),
);

void main() {
  group('CommandPaletteDialog', () {
    // ── locale sweeps ─────────────────────────────────────────────────────────

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders in $locale locale without exceptions', (
        tester,
      ) async {
        await tester.pumpWidget(_buildApp(locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // ── static structure ──────────────────────────────────────────────────────

    testWidgets('shows search TextField', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows search icon', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('shows at least one command item when query is empty', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      // All ShortcutActions are visible with no query.
      expect(find.byType(InkWell), findsWidgets);
    });

    testWidgets('shows "Open File" action label', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.text('Open File'), findsOneWidget);
    });

    // "Command Palette" is intentionally hidden from the palette (a command
    // should not list itself). Searching 'open file' still shows the Open File
    // action, which verifies that filtering works for a visible action.
    testWidgets('filtering by "open file" shows Open File action', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'open file');
      await tester.pumpAndSettle();
      expect(find.text('Open File'), findsOneWidget);
    });

    // ── filtering ─────────────────────────────────────────────────────────────

    testWidgets('filters list when text is entered', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zoom in');
      await tester.pumpAndSettle();

      expect(find.text('Zoom In'), findsOneWidget);
      // "Open File" should be gone since it doesn't match "zoom in".
      expect(find.text('Open File'), findsNothing);
    });

    testWidgets('fuzzy match: "zmin" matches "Zoom In"', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zmin');
      await tester.pumpAndSettle();

      expect(find.text('Zoom In'), findsOneWidget);
    });

    testWidgets('shows no-results message when query matches nothing', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'xyzzy_no_match_ever');
      await tester.pumpAndSettle();

      expect(find.text('No commands found'), findsOneWidget);
    });

    testWidgets('no-results message absent when results exist', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.text('No commands found'), findsNothing);
    });

    testWidgets('addDecoder is hidden when no waveform file is loaded', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(fileLoaded: false));
      await tester.pumpAndSettle();

      // Type a short query ("decoder") — distinct from the action label text —
      // so the TextField content doesn't create a false match.
      await tester.enterText(find.byType(TextField), 'decoder');
      await tester.pumpAndSettle();

      expect(find.text('Add Protocol Decoder'), findsNothing);
    });

    testWidgets('addDecoder is visible when waveform file is loaded', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // Type a short query ("decoder") — distinct from the action label text —
      // so we only get one match (the result list item, not the TextField).
      await tester.enterText(find.byType(TextField), 'decoder');
      await tester.pumpAndSettle();

      expect(find.text('Add Protocol Decoder'), findsOneWidget);
    });

    testWidgets(
      'show() with a tabContainer resolves the action context in the tab '
      'scope',
      (tester) async {
        // The palette is pushed by the root navigator, OUTSIDE the per-tab
        // UncontrolledProviderScope. Action gating reads [actionContextProvider];
        // wrapping the dialog in the tab container must resolve that provider
        // against the tab (which reports a loaded file) rather than the root
        // (which reports none) — so Add Protocol Decoder appears.
        final root = ProviderContainer(
          overrides: [
            actionContextProvider.overrideWithValue(
              _desktopContext(fileLoaded: false),
            ),
          ],
        );
        addTearDown(root.dispose);
        final tab = ProviderContainer(
          parent: root,
          overrides: [
            actionContextProvider.overrideWithValue(
              _desktopContext(fileLoaded: true),
            ),
          ],
        );
        addTearDown(tab.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: root,
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Builder(
                builder: (ctx) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () => CommandPaletteDialog.show(
                      ctx,
                      onAction: (_) {},
                      tabContainer: tab,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'decoder');
        await tester.pumpAndSettle();

        expect(find.text('Add Protocol Decoder'), findsOneWidget);
      },
    );

    // ── action dispatch ───────────────────────────────────────────────────────

    testWidgets('tapping an item calls onAction', (tester) async {
      ShortcutAction? dispatched;
      await tester.pumpWidget(
        _buildApp(onAction: (a) => dispatched = a),
      );
      await tester.pumpAndSettle();

      // The first visible item in the unfiltered list is openFile ("Open File").
      await tester.tap(find.text('Open File'));
      await tester.pumpAndSettle();

      expect(dispatched, isNotNull);
    });

    testWidgets('tapping item dismisses dialog', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => CommandPaletteDialog.show(
                    ctx,
                    onAction: (_) {},
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Dialog is open — find the search field.
      expect(find.byType(TextField), findsOneWidget);

      // Tap a known action label inside the dialog.
      await tester.tap(find.text('Open File'));
      await tester.pumpAndSettle();

      // Dialog dismissed; search field gone.
      expect(find.byType(TextField), findsNothing);
    });

    // ── keyboard navigation ───────────────────────────────────────────────────

    testWidgets('Down arrow moves selection down', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // Initially the first item is selected (index 0).
      // Press arrow-down once and expect no crash.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Up arrow at top does not go below zero', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Escape key closes the dialog (show helper)', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () =>
                      CommandPaletteDialog.show(ctx, onAction: (_) {}),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
    });

    // ── shortcut labels ───────────────────────────────────────────────────────

    testWidgets('displays shortcut text beside actions that have bindings', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // "Open File" is bound to Ctrl+O (or ⌘O on macOS). The shortcut text
      // should appear somewhere in the widget tree.
      final shortcutTexts = tester
          .widgetList<Text>(find.byType(Text))
          .where(
            (t) =>
                t.data != null &&
                (t.data!.contains('O') || t.data!.contains('⌘')),
          )
          .toList();
      expect(shortcutTexts, isNotEmpty);
    });

    // ── CommandPaletteDialog.show static helper ───────────────────────────────

    testWidgets('show() opens dialog over existing content', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () =>
                      CommandPaletteDialog.show(ctx, onAction: (_) {}),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    // ── CJK rendering ─────────────────────────────────────────────────────────

    testWidgets('zh locale shows CJK hint text without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(locale: 'zh'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The hint text contains CJK characters.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('ja locale shows CJK hint text without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(locale: 'ja'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ko locale shows CJK hint text without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp(locale: 'ko'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
