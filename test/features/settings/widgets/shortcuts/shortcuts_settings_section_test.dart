// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_keybindings/crux_keybindings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:wavecrux/features/settings/widgets/shortcuts/shortcuts_settings_section.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> freshPrefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  Widget wrap(
    SharedPreferences prefs, {
    Locale locale = const Locale('en'),
    Future<File?> Function()? pickExport,
    Future<File?> Function()? pickImport,
  }) => ProviderScope(
    overrides: [
      shortcutBindingsStoreProvider.overrideWithValue(
        KeyBindingsStore<ShortcutAction>(
          codec: waveCruxKeymapCodec,
          prefsOverride: prefs,
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ShortcutsSettingsSection(
            pickExportLocation: pickExport,
            pickImportFile: pickImport,
          ),
        ),
      ),
    ),
  );

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(ShortcutsSettingsSection)),
        listen: false,
      );

  testWidgets('renders rows and the import/export/reset-all controls', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    expect(find.byType(KeyBindingRow), findsWidgets);
    expect(find.text('Import…'), findsOneWidget);
    expect(find.text('Export…'), findsOneWidget);
    expect(find.text('Reset all'), findsOneWidget);
    // A known action label renders.
    expect(find.text('Zoom In'), findsOneWidget);
  });

  testWidgets('capturing a chord rebinds the action', (tester) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    final editButton = find.descendant(
      of: find.widgetWithText(KeyBindingRow, 'Zoom In'),
      matching: find.byIcon(Icons.edit_outlined),
    );
    await tester.ensureVisible(editButton);
    await tester.tap(editButton);
    await tester.pumpAndSettle(); // let the capture field autofocus

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final activator =
        containerOf(
              tester,
            ).read(shortcutBindingsProvider)[ShortcutAction.zoomIn]!
            as SingleActivator;
    expect(activator.trigger, LogicalKeyboardKey.keyJ);
    expect(activator.control, isTrue); // mod → control on the non-mac test host
  });

  testWidgets('shows a conflict warning when two actions share a chord', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    final zoomOut = containerOf(
      tester,
    ).read(shortcutBindingsProvider)[ShortcutAction.zoomOut]!;
    containerOf(tester)
        .read(shortcutBindingsProvider.notifier)
        .setBinding(ShortcutAction.zoomIn, zoomOut);
    await tester.pump();

    expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
  });

  testWidgets("conflict warning is asymmetric: only the shadowed row says it won't "
      'fire (issue #36 bug 1)', (tester) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    // Remap zoomIn onto zoomOut's chord: zoomIn is the customized interloper
    // (wins); zoomOut is the default owner (shadowed).
    final zoomOut = containerOf(
      tester,
    ).read(shortcutBindingsProvider)[ShortcutAction.zoomOut]!;
    containerOf(tester)
        .read(shortcutBindingsProvider.notifier)
        .setBinding(ShortcutAction.zoomIn, zoomOut);
    await tester.pump();

    // English message fragments: exactly one shadowed row, exactly one winner.
    expect(find.textContaining('shadowed by'), findsOneWidget);
    expect(find.textContaining('Takes precedence over'), findsOneWidget);
    // issue #42: the apostrophe renders once ("Won't"), not doubled ("Won''t").
    // This is a simple (non-plural/non-select) ICU message, so gen-l10n does not
    // un-escape apostrophes — a doubled apostrophe in the ARB would render
    // literally.
    expect(find.textContaining("Won't fire"), findsOneWidget);
    expect(find.textContaining("Won''t"), findsNothing);
    // The shadowed row uses the blocking error icon (plus the summary banner).
    expect(find.byIcon(Icons.error_outline), findsWidgets);
  });

  testWidgets('conflict summary banner shows the count (issue #36 bug 2)', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    // No conflicts → no banner.
    expect(find.textContaining('needs attention'), findsNothing);

    final zoomOut = containerOf(
      tester,
    ).read(shortcutBindingsProvider)[ShortcutAction.zoomOut]!;
    containerOf(tester)
        .read(shortcutBindingsProvider.notifier)
        .setBinding(ShortcutAction.zoomIn, zoomOut);
    await tester.pump();

    // One distinct conflicting chord → singular banner (=1 plural case).
    expect(
      find.text('1 shortcut conflict needs attention'),
      findsOneWidget,
    );
  });

  testWidgets('reset-all asks for confirmation, then restores defaults', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    final notifier = containerOf(tester).read(shortcutBindingsProvider.notifier)
      ..setBinding(
        ShortcutAction.zoomIn,
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
      );
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, 'Reset all'));
    await tester.pumpAndSettle();
    expect(find.text('Reset all shortcuts?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Reset all'));
    await tester.pumpAndSettle();

    expect(notifier.currentDiffs(), isEmpty);
  });

  testWidgets('export writes the current diffs to the chosen file', (
    tester,
  ) async {
    // Build the path synchronously (Directory.systemTemp.path is a sync getter);
    // all real file I/O happens inside tester.runAsync so it actually completes.
    final file = File(
      '${Directory.systemTemp.path}/wc_keymap_export_'
      '${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() {
      // Best-effort cleanup. On Windows the handle from the just-written
      // export/import file may not be released yet when teardown runs, so
      // deleteSync throws PathAccessException ("being used by another
      // process"). The temp file is harmless if it lingers.
      try {
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // OS will reclaim the temp file.
      }
    });

    await tester.pumpWidget(
      wrap(await freshPrefs(), pickExport: () async => file),
    );
    await tester.pump();

    containerOf(tester)
        .read(shortcutBindingsProvider.notifier)
        .setBinding(
          ShortcutAction.zoomIn,
          const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
        );
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text('Export…'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(file.existsSync(), isTrue);
    final content = await tester.runAsync(file.readAsString);
    final diffs = waveCruxKeymapCodec.decodeString(content!);
    expect(diffs.containsKey(ShortcutAction.zoomIn), isTrue);
  });

  testWidgets('import applies a keymap file', (tester) async {
    final file = File(
      '${Directory.systemTemp.path}/wc_keymap_import_'
      '${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() {
      // Best-effort cleanup. On Windows the handle from the just-written
      // export/import file may not be released yet when teardown runs, so
      // deleteSync throws PathAccessException ("being used by another
      // process"). The temp file is harmless if it lingers.
      try {
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // OS will reclaim the temp file.
      }
    });
    await tester.runAsync(
      () => file.writeAsString(
        waveCruxKeymapCodec.encodeToString({
          ShortcutAction.openFile: const KeyBinding(
            key: LogicalKeyboardKey.keyP,
            modifiers: {KeyModifier.mod, KeyModifier.shift},
          ),
        }),
      ),
    );

    await tester.pumpWidget(
      wrap(await freshPrefs(), pickImport: () async => file),
    );
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.text('Import…'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    final activator =
        containerOf(
              tester,
            ).read(shortcutBindingsProvider)[ShortcutAction.openFile]!
            as SingleActivator;
    expect(activator.trigger, LogicalKeyboardKey.keyP);
    expect(activator.shift, isTrue);
  });

  testWidgets(
    'importing a keymap from a newer version shows the version-specific message',
    (tester) async {
      // `decodeString` throws `KeymapSchemaVersionException` (a
      // `FormatException` subclass) for an envelope newer than this build
      // supports. The generic handler would still catch it, but would dump
      // the raw exception text at the user; the file is not corrupt, this
      // build is simply behind, and the message must say so.
      final dir = Directory.systemTemp.createTempSync('wc_keymap_version_');
      final file = File('${dir.path}/newer.crux-keymap.json');
      addTearDown(() {
        try {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        } on FileSystemException {
          // Windows may still hold the handle at teardown.
        }
      });
      await tester.runAsync(
        () => file.writeAsString(
          '{"version": ${kKeymapVersion + 1}, "bindings": {}}',
        ),
      );

      await tester.pumpWidget(
        wrap(await freshPrefs(), pickImport: () async => file),
      );
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.text('Import…'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      final l10n = L10N.of(
        tester.element(find.byType(ShortcutsSettingsSection)),
      );
      expect(
        find.text(l10n.settingsShortcutImportVersionFailure),
        findsOneWidget,
      );
      // And specifically NOT the generic "invalid file" message.
      expect(
        find.textContaining('KeymapSchemaVersionException'),
        findsNothing,
      );
    },
  );

  testWidgets('preset dropdown defaults to WaveCrux and applies GTKWave', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    // The chooser is present and reflects the shipped default.
    expect(find.text('Preset'), findsOneWidget);
    expect(find.text('WaveCrux (Default)'), findsOneWidget);

    // Open the dropdown and pick GTKWave.
    await tester.tap(find.text('WaveCrux (Default)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GTKWave').last);
    await tester.pumpAndSettle();

    final activator =
        containerOf(
              tester,
            ).read(shortcutBindingsProvider)[ShortcutAction.openSearch]!
            as SingleActivator;
    expect(activator.trigger, LogicalKeyboardKey.keyS);
    expect(activator.alt, isTrue);
  });

  testWidgets('preset dropdown shows Custom after a hand edit', (tester) async {
    await tester.pumpWidget(wrap(await freshPrefs()));
    await tester.pumpAndSettle();

    containerOf(tester)
        .read(shortcutBindingsProvider.notifier)
        .setBinding(
          ShortcutAction.zoomIn,
          const SingleActivator(LogicalKeyboardKey.keyJ, control: true),
        );
    await tester.pump();

    expect(find.text('Custom'), findsOneWidget);
  });

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders without exceptions in $locale', (tester) async {
        await tester.pumpWidget(wrap(await freshPrefs(), locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(KeyBindingRow), findsWidgets);
      });
    }
  });
}
