// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/tier_gated_actions_available_provider.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/annotations/widgets/annotation_markdown.dart';
import 'package:wavecrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:wavecrux/features/menu_bar/edit_commands.dart';
import 'package:wavecrux/features/menu_bar/widgets/desktop_menu_bar.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../../helpers/in_memory_workspace_service.dart';
import '../../helpers/product_telemetry_config.dart';

/// The macOS Edit menu's Cut, Copy, Paste and Select All.
///
/// A shipped macOS build beeped on Cmd+C over a selection in a rendered
/// annotation and copied nothing, although the same key copied in a widget
/// test: the test sends the key inside the framework, and the app's Edit menu
/// had no item claiming it. These tests cover what a widget test can reach of
/// that path: the menu offers the four commands on their chords, and choosing
/// one (which is what AppKit does with a key equivalent the framework left
/// alone) acts on the selection without depending on the key having found its
/// way to the focused widget.
void main() {
  const note = 'Handshake **stalls** after `req` rises';
  const plain = 'Handshake stalls after req rises';

  setUp(EditSelectionRegistry.instance.debugReset);

  /// Records what the app writes to the clipboard, and answers reads with
  /// [onPaste].
  List<String> captureClipboard(WidgetTester tester, {String onPaste = ''}) {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<Object?, Object?>;
          copied.add(args['text']! as String);
        }
        if (call.method == 'Clipboard.getData') {
          return <String, Object?>{'text': onPaste};
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
    return copied;
  }

  Widget host(Widget body, {TargetPlatform platform = TargetPlatform.macOS}) {
    return ProviderScope(
      overrides: [
        productTelemetryConfig,
        deviceClassProvider.overrideWithValue(DeviceClass.desktop),
        waveformIsLoadedProvider.overrideWithValue(true),
        diagnosticsEnabledProvider.overrideWithValue(true),
        workspaceServiceProvider.overrideWithValue(InMemoryWorkspaceService()),
        tierGatedActionsAvailableProvider.overrideWithValue(true),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: DesktopMenuBar(
          onAction: (_) {},
          child: Scaffold(body: body),
        ),
      ),
    );
  }

  Widget noteAndField(FocusNode other, TextEditingController field) => Column(
    children: [
      const SizedBox(width: 400, child: AnnotationMarkdown(text: note)),
      Focus(focusNode: other, child: const SizedBox(width: 10, height: 10)),
      SizedBox(width: 200, child: TextField(controller: field)),
    ],
  );

  /// Gives the note keyboard focus, as a click on it does.
  Future<void> focusNote(WidgetTester tester) async {
    Focus.of(
      tester.element(find.textContaining('Handshake', findRichText: true)),
    ).requestFocus();
    await tester.pump();
  }

  /// The Edit menu's own items, in order, from the PlatformMenuBar.
  List<PlatformMenuItem> editCommandItems(WidgetTester tester) {
    final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
    final l10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
    final edit = bar.menus.whereType<PlatformMenu>().firstWhere(
      (m) => m.label == l10n.actionCategoryEdit,
    );
    final leaves = <PlatformMenuItem>[];
    void visit(PlatformMenuItem item) {
      if (item is PlatformMenu) {
        item.menus.forEach(visit);
      } else if (item is PlatformMenuItemGroup) {
        item.members.forEach(visit);
      } else {
        leaves.add(item);
      }
    }

    edit.menus.forEach(visit);
    return leaves;
  }

  group('the macOS Edit menu', () {
    testWidgets('leads with Cut, Copy, Paste and Select All on Cmd+X, C, V '
        'and A', (tester) async {
      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(PlatformMenuBar)));
      final items = editCommandItems(tester);
      final firstFour = items.take(4).toList();
      expect(
        [for (final i in firstFour) i.label],
        [
          l10n.menuEditCut,
          l10n.menuEditCopy,
          l10n.menuEditPaste,
          l10n.menuEditSelectAll,
        ],
      );
      expect(
        [for (final i in firstFour) i.label],
        [
          'Cut',
          'Copy',
          'Paste',
          'Select All',
        ],
      );
      const keys = [
        LogicalKeyboardKey.keyX,
        LogicalKeyboardKey.keyC,
        LogicalKeyboardKey.keyV,
        LogicalKeyboardKey.keyA,
      ];
      for (var i = 0; i < 4; i++) {
        final chord = firstFour[i].shortcut! as SingleActivator;
        expect(chord.trigger, keys[i]);
        expect(chord.meta, isTrue);
        expect(chord.shift || chord.alt || chord.control, isFalse);
      }
      // The product's own Edit actions follow, so nothing was displaced.
      expect(items.length, greaterThan(4));
    });

    testWidgets('every one is enabled, with or without a selection: a greyed '
        'item does not claim its key, and the key beeps', (tester) async {
      await tester.pumpWidget(host(const SizedBox.shrink()));
      await tester.pumpAndSettle();
      for (final item in editCommandItems(tester).take(4)) {
        expect(item.onSelected, isNotNull, reason: item.label);
      }
    });

    testWidgets('Copy copies the selection in a rendered annotation, with '
        'focus on the note', (tester) async {
      final copied = captureClipboard(tester);
      final other = FocusNode();
      final field = TextEditingController();
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(host(noteAndField(other, field)));
      await tester.pumpAndSettle();
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll();
      await tester.pump();
      Focus.of(
        tester.element(find.textContaining('Handshake', findRichText: true)),
      ).requestFocus();
      await tester.pump();

      editCommandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, [plain]);
    });

    testWidgets('Copy still copies a selection that is on screen when nothing '
        'in the focus chain answers to it', (tester) async {
      // The beep: a highlighted selection and a key press that found no
      // handler. The area keeps its selection while the window is inactive;
      // with focus then somewhere that does not copy, only the menu's own
      // routing reaches it.
      final copied = captureClipboard(tester);
      final other = FocusNode();
      final field = TextEditingController();
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(host(noteAndField(other, field)));
      await tester.pumpAndSettle();
      await focusNote(tester);
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      other.requestFocus();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(other.hasPrimaryFocus, isTrue);

      editCommandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, [plain]);
    });

    testWidgets('Copy with nothing selected copies nothing and does not '
        'throw', (tester) async {
      final copied = captureClipboard(tester);
      final other = FocusNode();
      final field = TextEditingController();
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(host(noteAndField(other, field)));
      await tester.pumpAndSettle();
      other.requestFocus();
      await tester.pump();
      editCommandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a selection that cleared is not copied later', (
      tester,
    ) async {
      final copied = captureClipboard(tester);
      final other = FocusNode();
      final field = TextEditingController();
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(host(noteAndField(other, field)));
      await tester.pumpAndSettle();
      await focusNote(tester);
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll();
      await tester.pump();
      expect(EditSelectionRegistry.instance.text, plain);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      // Focus leaves the running app's note: the area clears its selection.
      other.requestFocus();
      await tester.pump();
      expect(EditSelectionRegistry.instance.text, isNull);
      editCommandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, isEmpty);
    });

    testWidgets('Cut, Copy, Paste and Select All act on a focused text '
        'field', (tester) async {
      final copied = captureClipboard(tester, onPaste: 'pasted');
      final other = FocusNode();
      final field = TextEditingController(text: 'abc def');
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(host(noteAndField(other, field)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final items = editCommandItems(tester);

      items[3].onSelected!(); // Select All
      await tester.pump();
      expect(
        field.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7),
      );

      items[1].onSelected!(); // Copy
      await tester.pump();
      expect(copied, ['abc def']);

      items[0].onSelected!(); // Cut
      await tester.pump();
      expect(field.text, isEmpty);
      expect(copied, ['abc def', 'abc def']);

      items[2].onSelected!(); // Paste
      await tester.pump();
      expect(field.text, 'pasted');
    });

    for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
      testWidgets('on $platform the menu does not carry them: the keys work '
          'in the focused widget and a menu button would take its focus', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(const SizedBox.shrink(), platform: platform),
        );
        await tester.pumpAndSettle();
        final bar = tester.widget<MenuBar>(find.byType(MenuBar));
        final labels = <String>[];
        void visit(Widget w) {
          if (w is SubmenuButton) {
            w.menuChildren.forEach(visit);
          } else if (w is MenuItemButton && w.child is Text) {
            labels.add((w.child! as Text).data ?? '');
          }
        }

        bar.children.forEach(visit);
        expect(labels, isNotEmpty);
        expect(labels, isNot(contains('Copy')));
        expect(labels, isNot(contains('Select All')));
      });
    }
  });

  group('performEditCommand', () {
    testWidgets('reports a command nothing could take', (tester) async {
      captureClipboard(tester);
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      expect(performEditCommand(EditCommand.copy), isFalse);
      expect(performEditCommand(EditCommand.paste), isFalse);
      expect(performEditCommand(EditCommand.cut), isFalse);
      expect(performEditCommand(EditCommand.selectAll), isFalse);
    });

    test('the latest selection to report is the one copied', () {
      final registry = EditSelectionRegistry.instance;
      final a = Object();
      final b = Object();
      registry
        ..report(a, 'first')
        ..report(b, 'second');
      expect(registry.text, 'second');
      registry.report(b, null);
      expect(registry.text, 'first');
      registry.forget(a);
      expect(registry.text, isNull);
    });
  });
}
