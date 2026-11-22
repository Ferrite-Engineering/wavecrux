// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/tier_gated_actions_available_provider.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/features/annotations/providers/active_tab_annotation_copy_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/widgets/annotation_markdown.dart';
import 'package:wavecrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:wavecrux/features/menu_bar/edit_commands.dart';
import 'package:wavecrux/features/menu_bar/widgets/desktop_menu_bar.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
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

  List<Override> hostOverrides() => [
    productTelemetryConfig,
    deviceClassProvider.overrideWithValue(DeviceClass.desktop),
    waveformIsLoadedProvider.overrideWithValue(true),
    diagnosticsEnabledProvider.overrideWithValue(true),
    workspaceServiceProvider.overrideWithValue(InMemoryWorkspaceService()),
    tierGatedActionsAvailableProvider.overrideWithValue(true),
  ];

  Widget app(Widget body, TargetPlatform platform) => MaterialApp(
    theme: ThemeData(platform: platform),
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: DesktopMenuBar(
      onAction: (_) {},
      child: Scaffold(body: body),
    ),
  );

  /// The app's menu bar over [body]. [annotation] stands in for the active
  /// tab's selected annotation, as Copy would put it on the clipboard.
  Widget host(
    Widget body, {
    TargetPlatform platform = TargetPlatform.macOS,
    String? annotation,
  }) {
    return ProviderScope(
      overrides: [
        ...hostOverrides(),
        activeTabAnnotationCopyTextProvider.overrideWith(
          () => _SelectedAnnotation(annotation),
        ),
      ],
      child: app(body, platform),
    );
  }

  Widget noteAndField(FocusNode other, TextEditingController field) => Column(
    children: [
      const SizedBox(width: 400, child: AnnotationMarkdown(text: note)),
      Focus(focusNode: other, child: const SizedBox(width: 10, height: 10)),
      SizedBox(width: 200, child: TextField(controller: field)),
    ],
  );

  /// Selects [text] as the active tab's annotation, or clears it with null.
  void selectAnnotation(WidgetTester tester, String? text) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    (container.read(activeTabAnnotationCopyTextProvider.notifier)
                as _SelectedAnnotation)
            .selected =
        text;
  }

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

  /// Whether each of Cut, Copy, Paste and Select All is enabled, in order.
  List<bool> enabled(WidgetTester tester) => [
    for (final item in editCommandItems(tester).take(4))
      item.onSelected != null,
  ];

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

    testWidgets('with nothing to act on every one is greyed, so its key '
        'falls through to the alert sound', (tester) async {
      final pane = FocusNode(debugLabel: 'Waveform pane');
      addTearDown(pane.dispose);
      await tester.pumpWidget(
        host(Focus(focusNode: pane, child: const SizedBox(width: 10))),
      );
      await tester.pumpAndSettle();
      pane.requestFocus();
      await tester.pump();
      expect(enabled(tester), [false, false, false, false]);
    });

    testWidgets('each item enables and greys as focus, text selection and '
        'annotation selection change', (tester) async {
      final other = FocusNode(debugLabel: 'Waveform pane');
      final field = TextEditingController(text: 'abc def');
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(host(noteAndField(other, field)));
      await tester.pumpAndSettle();
      other.requestFocus();
      await tester.pump();
      //                 Cut    Copy   Paste  Select All
      expect(enabled(tester), [false, false, false, false]);

      // An annotation selected: Copy, and only Copy.
      selectAnnotation(tester, '200 ns  top.req\nreq rises');
      await tester.pump();
      expect(enabled(tester), [false, true, false, false]);

      // Into a text field with nothing selected: the field owns Copy and has
      // nothing to copy; Paste and Select All apply.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      field.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();
      expect(enabled(tester), [false, false, true, true]);

      // A selection in the field: Cut and Copy too.
      field.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      await tester.pump();
      expect(enabled(tester), [true, true, true, true]);

      // The selection collapses again.
      field.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      expect(enabled(tester), [false, false, true, true]);

      // A rendered note focused, nothing selected in it: Select All, and Copy
      // for the selected annotation. No Cut or Paste: it is not editable.
      await focusNote(tester);
      expect(enabled(tester), [false, true, false, true]);

      // The annotation deselected: Copy greys.
      selectAnnotation(tester, null);
      await tester.pump();
      expect(enabled(tester), [false, false, false, true]);

      // Text selected in the note: Copy again.
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll();
      await tester.pump();
      await tester.pump();
      expect(enabled(tester), [false, true, false, true]);
    });

    testWidgets('a password field never offers Cut or Copy', (tester) async {
      final field = TextEditingController(text: 'secret');
      addTearDown(field.dispose);
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 200,
            child: TextField(controller: field, obscureText: true),
          ),
          annotation: 'a note',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      field.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
      await tester.pump();
      expect(enabled(tester), [false, false, true, true]);
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

    testWidgets('Copy with nothing selected is greyed, copies nothing and '
        'does not throw', (tester) async {
      final copied = captureClipboard(tester);
      final other = FocusNode();
      final field = TextEditingController();
      addTearDown(other.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(host(noteAndField(other, field)));
      await tester.pumpAndSettle();
      other.requestFocus();
      await tester.pump();
      expect(editCommandItems(tester)[1].onSelected, isNull);
      expect(performEditCommand(EditCommand.copy), isFalse);
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
      // The menu hears of it once the frame that cleared it is done.
      await tester.pump();
      expect(editCommandItems(tester)[1].onSelected, isNull);
      expect(performEditCommand(EditCommand.copy), isFalse);
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
      // Read the items afresh at each step: the menu is rebuilt as the
      // selection changes, and a greyed item has no callback.
      List<PlatformMenuItem> items() => editCommandItems(tester);

      items()[3].onSelected!(); // Select All
      await tester.pump();
      expect(
        field.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7),
      );

      items()[1].onSelected!(); // Copy
      await tester.pump();
      expect(copied, ['abc def']);

      items()[0].onSelected!(); // Cut
      await tester.pump();
      expect(field.text, isEmpty);
      expect(copied, ['abc def', 'abc def']);

      items()[2].onSelected!(); // Paste
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

  group('Copy on a selected annotation', () {
    const copiedNote =
        '200 ns  top.req\nreq asserts here, one clock before the bus is driven';

    testWidgets('the menu Copy, with focus on the waveform pane, copies the '
        "annotation's time, signal and note", (tester) async {
      final copied = captureClipboard(tester);
      final pane = FocusNode(debugLabel: 'Waveform pane');
      final field = TextEditingController();
      addTearDown(pane.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        host(noteAndField(pane, field), annotation: copiedNote),
      );
      await tester.pumpAndSettle();
      pane.requestFocus();
      await tester.pump();
      // What a key press there finds: nothing.
      expect(
        Actions.maybeFind<CopySelectionTextIntent>(
          FocusManager.instance.primaryFocus!.context!,
        ),
        isNull,
      );

      editCommandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, [copiedNote]);
    });

    testWidgets('performEditCommand copies the annotation from the waveform '
        'pane, and reports it', (tester) async {
      final copied = captureClipboard(tester);
      final pane = FocusNode(debugLabel: 'Waveform pane');
      addTearDown(pane.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Focus(focusNode: pane, child: const SizedBox()),
        ),
      );
      pane.requestFocus();
      await tester.pump();
      expect(
        performEditCommand(EditCommand.copy, annotationText: copiedNote),
        isTrue,
      );
      expect(performEditCommand(EditCommand.copy), isFalse);
      // The other three have nothing to act on there.
      for (final c in [
        EditCommand.cut,
        EditCommand.paste,
        EditCommand.selectAll,
      ]) {
        expect(performEditCommand(c, annotationText: copiedNote), isFalse);
      }
      await tester.pump();
      expect(copied, [copiedNote]);
    });

    testWidgets('a selection in a note wins over the annotation', (
      tester,
    ) async {
      final copied = captureClipboard(tester);
      final pane = FocusNode(debugLabel: 'Waveform pane');
      final field = TextEditingController();
      addTearDown(pane.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        host(noteAndField(pane, field), annotation: copiedNote),
      );
      await tester.pumpAndSettle();
      await focusNote(tester);
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll();
      await tester.pump();
      editCommandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, [plain]);
    });

    testWidgets('an empty selection in a focused note does not stand in for '
        'the annotation', (tester) async {
      // The note's copy action reports a copy handled with nothing selected;
      // the annotation must still be what Copy copies.
      final copied = captureClipboard(tester);
      final pane = FocusNode(debugLabel: 'Waveform pane');
      final field = TextEditingController();
      addTearDown(pane.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        host(noteAndField(pane, field), annotation: copiedNote),
      );
      await tester.pumpAndSettle();
      await focusNote(tester);
      expect(EditSelectionRegistry.instance.text, isNull);
      editCommandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, [copiedNote]);
    });

    testWidgets('a selection in a focused text field wins over the '
        'annotation', (tester) async {
      final copied = captureClipboard(tester);
      final pane = FocusNode(debugLabel: 'Waveform pane');
      final field = TextEditingController(text: 'abc def');
      addTearDown(pane.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        host(noteAndField(pane, field), annotation: copiedNote),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      field.selection = const TextSelection(baseOffset: 4, extentOffset: 7);
      await tester.pump();
      editCommandItems(tester)[1].onSelected!();
      await tester.pump();
      expect(copied, ['def']);
    });

    testWidgets('a focused text field with nothing selected keeps Copy: it is '
        'greyed and copies nothing', (tester) async {
      final copied = captureClipboard(tester);
      final pane = FocusNode(debugLabel: 'Waveform pane');
      final field = TextEditingController(text: 'abc def');
      addTearDown(pane.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        host(noteAndField(pane, field), annotation: copiedNote),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      field.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();
      expect(editCommandItems(tester)[1].onSelected, isNull);
      expect(
        performEditCommand(EditCommand.copy, annotationText: copiedNote),
        isFalse,
      );
      await tester.pump();
      expect(copied, isEmpty);
    });

    testWidgets('end to end: the annotation selected in the active tab is '
        'what the menu copies', (tester) async {
      final copied = captureClipboard(tester);
      final tcm = TabContainerManager();
      final root = ProviderContainer(
        overrides: [
          ...hostOverrides(),
          tabContainerManagerProvider.overrideWithValue(tcm),
        ],
      );
      tcm.init(root);
      final pane = FocusNode(debugLabel: 'Waveform pane');
      final field = TextEditingController();
      addTearDown(pane.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: root,
          child: app(noteAndField(pane, field), TargetPlatform.macOS),
        ),
      );
      await tester.pumpAndSettle();
      pane.requestFocus();
      await tester.pump();
      expect(editCommandItems(tester)[1].onSelected, isNull);

      final tab = tcm.containerFor(root.read(activeTabIdProvider));
      tab
          .read(annotationsProvider.notifier)
          .add(
            Annotation(
              id: 'n1',
              shape: AnnotationShape.callout,
              anchor: const PointAnchor(time: 200, rowId: 'top.req'),
              authorName: 'Ada',
              createdAt: DateTime.utc(2026, 11, 22),
              text: 'req **rises**',
            ),
          );
      // What a click on its balloon or its panel row does.
      tab.read(annotationSelectedProvider.notifier).selected = 'n1';
      // The tab container refreshes its derived providers on a timer of its
      // own; let it run.
      await tester.pump(const Duration(milliseconds: 1));

      editCommandItems(tester)[1].onSelected!();
      await tester.pump();
      // No file is loaded, so the time is in ticks, as the panel shows it.
      expect(copied, ['200 ticks  top.req\nreq **rises**']);

      tab.read(annotationSelectedProvider.notifier).clear();
      await tester.pump();
      expect(editCommandItems(tester)[1].onSelected, isNull);

      await tester.pumpWidget(const SizedBox());
      tcm.dispose();
      root.dispose();
      // Lets the scheduler run the refresh the disposal queued.
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('Ctrl+C on Windows and Linux', () {
    const copiedNote = '200 ns  top.req\nreq rises';

    Future<void> pressCtrlC(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    const desktops = TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.linux,
    });

    testWidgets('copies the selected annotation with focus on the waveform '
        'pane', (tester) async {
      final copied = captureClipboard(tester);
      final pane = FocusNode(debugLabel: 'Waveform pane');
      final field = TextEditingController();
      addTearDown(pane.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        host(
          noteAndField(pane, field),
          platform: defaultTargetPlatform,
          annotation: copiedNote,
        ),
      );
      await tester.pumpAndSettle();
      pane.requestFocus();
      await tester.pump();
      await pressCtrlC(tester);
      expect(copied, [copiedNote]);
    }, variant: desktops);

    testWidgets('does nothing with no annotation selected', (tester) async {
      final copied = captureClipboard(tester);
      final pane = FocusNode(debugLabel: 'Waveform pane');
      final field = TextEditingController();
      addTearDown(pane.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        host(noteAndField(pane, field), platform: defaultTargetPlatform),
      );
      await tester.pumpAndSettle();
      pane.requestFocus();
      await tester.pump();
      await pressCtrlC(tester);
      expect(copied, isEmpty);
    }, variant: desktops);

    testWidgets('leaves a text field its own Ctrl+C', (tester) async {
      final copied = captureClipboard(tester);
      final pane = FocusNode(debugLabel: 'Waveform pane');
      final field = TextEditingController(text: 'abc def');
      addTearDown(pane.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        host(
          noteAndField(pane, field),
          platform: defaultTargetPlatform,
          annotation: copiedNote,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      field.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
      await tester.pump();
      await pressCtrlC(tester);
      expect(copied, ['abc']);

      // Nothing selected in the field: still the field's key, not the note's.
      field.selection = const TextSelection.collapsed(offset: 1);
      await tester.pump();
      await pressCtrlC(tester);
      expect(copied, ['abc']);
    }, variant: desktops);

    testWidgets('a selection in a note wins over the annotation', (
      tester,
    ) async {
      final copied = captureClipboard(tester);
      final pane = FocusNode(debugLabel: 'Waveform pane');
      final field = TextEditingController();
      addTearDown(pane.dispose);
      addTearDown(field.dispose);
      await tester.pumpWidget(
        host(
          noteAndField(pane, field),
          platform: defaultTargetPlatform,
          annotation: copiedNote,
        ),
      );
      await tester.pumpAndSettle();
      await focusNote(tester);
      tester
          .state<SelectableRegionState>(find.byType(SelectableRegion))
          .selectAll();
      await tester.pump();
      await pressCtrlC(tester);
      expect(copied, [plain]);
    }, variant: desktops);
  });

  group('EditAvailability.resolve', () {
    EditAvailability resolve(
      EditFocus focus, {
      bool selectedText = false,
      bool annotation = false,
    }) => EditAvailability.resolve(
      focus: focus,
      hasSelectedText: selectedText,
      annotationSelected: annotation,
    );

    const field = EditFocus(editable: true);
    const fieldWithSelection = EditFocus(
      editable: true,
      hasTextSelection: true,
    );

    test("Copy's precedence: field selection, note selection, annotation", () {
      expect(
        resolve(
          fieldWithSelection,
          selectedText: true,
          annotation: true,
        ).copySource,
        CopySource.focusedText,
      );
      expect(
        resolve(
          EditFocus.none,
          selectedText: true,
          annotation: true,
        ).copySource,
        CopySource.selectedText,
      );
      expect(
        resolve(
          const EditFocus(selectable: true),
          annotation: true,
        ).copySource,
        CopySource.annotation,
      );
      expect(
        resolve(EditFocus.none, annotation: true).copySource,
        CopySource.annotation,
      );
      expect(resolve(EditFocus.none).copySource, isNull);
      // A focused field with nothing selected has nothing to copy.
      expect(resolve(field, annotation: true).copySource, isNull);
    });

    test('Cut needs a selection in changeable text; Paste changeable text; '
        'Select All any text', () {
      expect(resolve(fieldWithSelection).canCut, isTrue);
      expect(resolve(field).canCut, isFalse);
      expect(
        resolve(
          const EditFocus(
            editable: true,
            readOnly: true,
            hasTextSelection: true,
          ),
        ).canCut,
        isFalse,
      );
      expect(resolve(field).canPaste, isTrue);
      expect(
        resolve(const EditFocus(editable: true, readOnly: true)).canPaste,
        isFalse,
      );
      expect(resolve(const EditFocus(selectable: true)).canPaste, isFalse);
      expect(resolve(field).canSelectAll, isTrue);
      expect(resolve(const EditFocus(selectable: true)).canSelectAll, isTrue);
      expect(resolve(EditFocus.none, annotation: true).canSelectAll, isFalse);
    });

    test('a password is never cut or copied', () {
      const password = EditFocus(
        editable: true,
        obscured: true,
        hasTextSelection: true,
      );
      expect(resolve(password, annotation: true).copySource, isNull);
      expect(resolve(password).canCut, isFalse);
      expect(resolve(password).canPaste, isTrue);
    });
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

/// The active tab's selected annotation, set by the test.
class _SelectedAnnotation extends ActiveTabAnnotationCopyText {
  _SelectedAnnotation(this._initial);

  final String? _initial;

  @override
  String? build() => _initial;

  String? get selected => state;

  set selected(String? text) => state = text;
}
