// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// What a screen reader user hears in the viewer, asserted.
//
// Every case here reproduces a finding from the first external NVDA pass
// (Windows 11, NVDA 2026.1): FLUTTERVIEW at launch, bare "text" Tab stops,
// Space not activating buttons, and a file that failed to load sounding like
// one that opened. It also pins the signal tree's keyboard control and keys
// pressed inside a dialog staying there. The transcripts under `goldens/` are
// what the focus walk
// records; a change in what is announced shows up as a diff there. Rewrite
// them with `flutter test --update-goldens test/accessibility` and read the
// diff before committing it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_eula/crux_eula.dart' show CruxEulaGate;
import 'package:crux_telemetry/crux_telemetry.dart' show TelemetryConsentGate;
import 'package:crux_workspace/crux_workspace.dart' show CruxGlowingAppIcon;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/utils/speakable_text.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/widgets/transaction_table_panel.dart';
import 'package:wavecrux/features/search/widgets/signal_search_dialog.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_panel.dart';
import 'package:wavecrux/features/viewer/providers/selected_transaction_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/features/viewer/widgets/viewer_toolbar.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/decoders/apb_decoder.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../helpers/fake_waveform_data_source.dart';
import '../helpers/product_telemetry_config.dart';

// ── harness ─────────────────────────────────────────────────────────────────

class _InMemoryWorkspaceService implements WorkspaceService {
  @override
  Future<Workspace> load() async {
    const pane = WorkspacePane(id: PaneId.primary);
    return Workspace(
      tabs: const [],
      panes: const [pane],
      activePaneId: pane.id,
    );
  }

  @override
  Future<void> save(Workspace workspace) async {}

  /// No session sidecar: the auto-save that selecting a transaction arms
  /// has nowhere to write, and skips.
  @override
  Future<String?> sidecarPathFor(
    String tabId, {
    String extension = '.wavecrux',
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Scope extends StatefulWidget {
  const _Scope({
    required this.child,
    required this.overrides,
    required this.tabOverrides,
    required this.seedTab,
  });

  final Widget child;
  final List<Override> overrides;
  final List<Override> tabOverrides;
  final bool seedTab;

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
    _tcm = TabContainerManager(extraTabOverrides: widget.tabOverrides);
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
    if (widget.seedTab) {
      unawaited(_container.wavecruxWorkspace.newTab(displayName: 'sample.vcd'));
    }
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

Future<void> _pumpViewer(
  WidgetTester tester, {
  List<Override> overrides = const [],
  List<Override> tabOverrides = const [],
  bool seedTab = false,
}) async {
  tester.view
    ..physicalSize = const Size(1600, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  CruxGlowingAppIcon.debugDisableAnimations = true;
  addTearDown(() => CruxGlowingAppIcon.debugDisableAnimations = false);
  await tester.pumpWidget(
    _Scope(
      overrides: overrides,
      tabOverrides: tabOverrides,
      seedTab: seedTab,
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const ViewerScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// Pumps the app as a first launch reaches it: both blocking surfaces
/// mounted over the viewer, the way `app.dart` mounts them, with nothing
/// accepted and nothing answered.
///
/// Neither gate is seeded here on purpose — this is the one test that wants
/// them up. Everything else in the suite pumps [ViewerScreen] directly and
/// never sees them.
Future<void> _pumpFirstLaunch(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1600, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  CruxGlowingAppIcon.debugDisableAnimations = true;
  addTearDown(() => CruxGlowingAppIcon.debugDisableAnimations = false);
  await tester.pumpWidget(
    _Scope(
      overrides: const [],
      tabOverrides: const [],
      seedTab: false,
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const CruxEulaGate(
          child: TelemetryConsentGate(child: ViewerScreen()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

OpenFilePicker _picker(String? path, void Function() onCalled) =>
    ({dialogTitle, type = FileType.any, allowedExtensions}) async {
      onCalled();
      if (path == null) return null;
      return FilePickerResult([
        PlatformFile(name: path.split('/').last, size: 0, path: path),
      ]);
    };

class _LoadedSource extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() {
    currentFilePath = '/kit/sample.vcd';
    return AsyncData(
      FakeWaveformDataSource(
        scopes: const [
          Scope(
            name: 'axi4lite_tb',
            type: ScopeType.module,
            path: 'axi4lite_tb',
            variables: [
              Variable(
                name: 'ACLK',
                varType: VarType.wire,
                direction: VarDirection.unknown,
                signalRef: '0',
                scopePath: 'axi4lite_tb',
              ),
              Variable(
                name: 'ARADDR',
                varType: VarType.wire,
                direction: VarDirection.unknown,
                signalRef: '1',
                scopePath: 'axi4lite_tb',
                bitWidth: 32,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FailingSource extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() => const AsyncData(null);

  @override
  Future<void> openFile(String path, {bool preserveDecoders = false}) async {
    lastAttemptedPath = path;
    state = AsyncError(
      Exception(r'unexpected end of file in $comment'),
      StackTrace.empty,
    );
  }
}

/// The labelled semantics containers around the node that has focus, outermost
/// first — what [describeFocus] needs to report only newly entered containers.
List<SemanticsNode> _namedAncestorsOfFocus(WidgetTester tester) {
  SemanticsNode? focused;
  void visit(SemanticsNode node) {
    if (node.isMergedIntoParent) return;
    if (node.getSemanticsData().flagsCollection.isFocused ==
        ui.Tristate.isTrue) {
      focused = node;
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  for (final view in tester.binding.renderViews) {
    final root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
  }
  final chain = <SemanticsNode>[];
  for (var node = focused?.parent; node != null; node = node.parent) {
    if (node.getSemanticsData().label.trim().isNotEmpty) chain.add(node);
  }
  return chain.reversed.toList();
}

/// A plain-text golden, rewritten by `flutter test --update-goldens`.
void _expectTextGolden(String actual, String path) {
  final file = File(path);
  if (autoUpdateGoldenFiles) {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(actual);
    return;
  }
  expect(
    file.existsSync(),
    isTrue,
    reason:
        'No golden at $path. Run flutter test --update-goldens and read '
        'what it writes.\n\n$actual',
  );
  expect(
    actual,
    file.readAsStringSync().replaceAll('\r\n', '\n'),
    reason:
        'What the signal tree announces changed. If that is intended, run '
        'flutter test --update-goldens and read the diff before committing.',
  );
}

/// The APB decoder's committed output for `apb_basic.vcd`: four transactions,
/// two reads whose labels carry an arrow and one slave error. The table shows
/// decoded output, so the snapshot stands in for running the decoder over the
/// waveform (which needs the FFI parser and a background isolate).
class _ApbFixtureDecoders extends ActiveDecodersNotifier {
  @override
  List<ActiveDecoder> build() {
    final json =
        jsonDecode(
              File(
                'test/fixtures/protocol/apb/generated/'
                'apb_basic.expected_transactions.json',
              ).readAsStringSync(),
            )
            as List<dynamic>;
    return [
      ActiveDecoder(
        id: 'apb-1',
        decoderId: ApbDecoder.decoderDefinition.id,
        config: const DecoderConfig(signalBindings: {}),
        instanceNumber: 1,
        transactions: [
          for (final t in json.cast<Map<String, dynamic>>())
            DecodedTransaction(
              startTime: t['startTime'] as int,
              endTime: t['endTime'] as int,
              label: t['label'] as String,
              fields: (t['fields'] as Map<String, dynamic>).cast(),
              isError: t['isError'] as bool,
              errorMessage: t['errorMessage'] as String?,
            ),
        ],
      ),
    ];
  }
}

/// Presses Tab around the whole window and records the stops whose focus is
/// inside [region], so a panel's transcript can be pinned without the rest
/// of the viewer.
Future<FocusWalk> _walkRegion(WidgetTester tester, Finder region) async {
  final regionElement = tester.element(region);
  bool inside() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    if (identical(context, regionElement)) return true;
    var found = false;
    context.visitAncestorElements((element) {
      found = identical(element, regionElement);
      return !found;
    });
    return found;
  }

  final stops = <FocusStop>[];
  FocusNode? first;
  var cycled = false;
  var previous = _namedAncestorsOfFocus(tester);
  for (var i = 0; i < 300; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final node = FocusManager.instance.primaryFocus;
    if (node == null) break;
    if (first == null) {
      first = node;
    } else if (identical(node, first)) {
      cycled = true;
      break;
    }
    if (inside()) stops.add(describeFocus(tester, previous: previous));
    previous = _namedAncestorsOfFocus(tester);
  }
  return FocusWalk(
    stops: stops,
    cycled: cycled,
    reverse: false,
    offscreen: const {},
  );
}

// ── tests ───────────────────────────────────────────────────────────────────

void main() {
  const goldens = 'test/accessibility/goldens';

  testWidgets('launch puts focus on Open File, so something is announced', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpViewer(tester);

    expectFocusAnnounced(tester, named: 'Open File', context: 'launch');
    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'start screen');
    expectFocusWalkGolden(walk, '$goldens/start_screen.txt');
    handle.dispose();
  });

  testWidgets('with a file open, every Tab stop is named', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpViewer(
      tester,
      seedTab: true,
      overrides: [waveformIsLoadedProvider.overrideWithValue(true)],
      tabOverrides: [waveformSourceProvider.overrideWith(_LoadedSource.new)],
    );

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'viewer with a file open');
    expectFocusWalkGolden(walk, '$goldens/viewer_file_open.txt');
    handle.dispose();
  });

  testWidgets('signal search results are single, named check boxes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpViewer(
      tester,
      seedTab: true,
      overrides: [waveformIsLoadedProvider.overrideWithValue(true)],
      tabOverrides: [waveformSourceProvider.overrideWith(_LoadedSource.new)],
    );

    Actions.invoke(
      tester.element(find.byType(ViewerToolbar)),
      const ShortcutActionIntent(ShortcutAction.openSearch),
    );
    await tester.pumpAndSettle();

    expectFocusAnnounced(tester, context: 'search dialog opened');
    final forward = await walkFocus(tester);
    expectCleanFocusWalk(forward, context: 'signal search');
    expect(
      forward.stops.map((s) => s.line),
      containsAllInOrder(<String>[
        'ACLK, axi4lite_tb check box not checked',
        'ARADDR, axi4lite_tb, [31:0] check box not checked',
      ]),
    );
    expectFocusWalkGolden(forward, '$goldens/signal_search.txt');

    // Shift+Tab visits the same stops in the opposite order: the rows the
    // list builds below its visible edge no longer sort after the buttons.
    final backward = await walkFocus(tester, reverse: true);
    expect(
      backward.stops.map((s) => s.line).toList().reversed,
      forward.stops.map(
        (s) => s.line.replaceFirst(RegExp(r'^(\[[^\]]*\] )+'), ''),
      ),
    );
    handle.dispose();
  });

  testWidgets('the signal tree is reached and operated from the keyboard', (
    tester,
  ) async {
    // The tester found no keyboard route to a signal: the tree's rows were
    // bare gesture detectors, and Ctrl+F was the only way to add one. The
    // transcript below is what the walk hears, keystroke by keystroke, from
    // the search field into the tree and down to adding a signal.
    final handle = tester.ensureSemantics();
    final recorder = AnnouncementRecorder.attach(tester);
    await _pumpViewer(
      tester,
      seedTab: true,
      overrides: [waveformIsLoadedProvider.overrideWithValue(true)],
      tabOverrides: [waveformSourceProvider.overrideWith(_LoadedSource.new)],
    );
    await tester.tap(
      find.descendant(
        of: find.byType(SignalTreePanel),
        matching: find.byType(TextField),
      ),
    );
    await tester.pump();

    final transcript = StringBuffer('# Signal tree, from the search field\n');
    final stops = <FocusStop>[];
    Future<void> press(
      String name,
      LogicalKeyboardKey key, {
      bool shift = false,
    }) async {
      final before = _namedAncestorsOfFocus(tester);
      final heard = recorder.messages.length;
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(key);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      // Menus animate open and closed; the stop is read once they settle.
      await tester.pumpAndSettle();
      final stop = describeFocus(tester, previous: before);
      stops.add(stop);
      transcript.writeln('$name: ${stop.line}');
      for (final message in recorder.messages.skip(heard)) {
        transcript.writeln('  announced: $message');
      }
    }

    await press('Tab', LogicalKeyboardKey.tab);
    await press('Right', LogicalKeyboardKey.arrowRight);
    await press('Down', LogicalKeyboardKey.arrowDown);
    await press('Down', LogicalKeyboardKey.arrowDown);
    await press('Enter', LogicalKeyboardKey.enter);
    // The row's context menu, opened, walked and closed without a pointer.
    await press('Shift+F10', LogicalKeyboardKey.f10, shift: true);
    await press('Down', LogicalKeyboardKey.arrowDown);
    await press('Escape', LogicalKeyboardKey.escape);
    // A range selected from the keyboard, then added from the menu.
    await press('Up', LogicalKeyboardKey.arrowUp);
    await press('Shift+Down', LogicalKeyboardKey.arrowDown, shift: true);
    await press('Menu', LogicalKeyboardKey.contextMenu);
    await press('Down', LogicalKeyboardKey.arrowDown);
    await press('Enter', LogicalKeyboardKey.enter);
    await press('Left', LogicalKeyboardKey.arrowLeft);
    await press('Left', LogicalKeyboardKey.arrowLeft);
    await press('Tab', LogicalKeyboardKey.tab);

    expectCleanFocusWalk(
      FocusWalk(
        stops: stops,
        cycled: true,
        reverse: false,
        offscreen: const {},
      ),
      context: 'signal tree keys',
    );
    _expectTextGolden(transcript.toString(), '$goldens/signal_tree.txt');

    final tab = ProviderScope.containerOf(
      tester.element(find.byType(SignalTreePanel)),
    );
    expect(
      tab.read(signalGroupsProvider).entries.map((e) => e.signalRef),
      ['1', '0'],
      reason:
          'Enter on ARADDR adds it; Add Selected adds ACLK and skips ARADDR, '
          'which is already shown',
    );
    handle.dispose();
  });

  group('the transaction table', () {
    setUp(() {
      DecoderRegistry.instance.register(
        ApbDecoder.decoderDefinition,
        ApbDecoder.new,
      );
    });
    tearDown(DecoderRegistry.instance.clear);

    Future<void> pumpWithApb(WidgetTester tester) async {
      await _pumpViewer(
        tester,
        seedTab: true,
        overrides: [waveformIsLoadedProvider.overrideWithValue(true)],
        tabOverrides: [
          waveformSourceProvider.overrideWith(_LoadedSource.new),
          activeDecodersProvider.overrideWith(_ApbFixtureDecoders.new),
        ],
      );
      Actions.invoke(
        tester.element(find.byType(ViewerToolbar)),
        const ShortcutActionIntent(ShortcutAction.toggleTransactionTable),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TransactionTablePanel), findsOneWidget);
    }

    testWidgets('is walked as named controls and one row stop, by ear', (
      tester,
    ) async {
      // Before: the decoder filter was not a Tab stop, the sort headers were
      // "# text", "Start text", and every cell of every row was its own Tab
      // stop read as a bare value — 44 stops for these four transactions,
      // two of them silent, and the reads' arrows spoken as "?".
      final handle = tester.ensureSemantics();
      final recorder = AnnouncementRecorder.attach(tester);
      await pumpWithApb(tester);
      final panel = find.byType(TransactionTablePanel);

      final walk = await _walkRegion(tester, panel);
      expectCleanFocusWalk(walk, context: 'transaction table');
      final transcript = StringBuffer()
        ..writeln(
          '# Tab stops inside the transaction table: ${walk.stops.length}',
        );
      for (var i = 0; i < walk.stops.length; i++) {
        transcript.writeln('${i + 1}. ${walk.stops[i].line}');
      }

      final stops = <FocusStop>[];
      Future<void> press(
        String name,
        LogicalKeyboardKey key, {
        bool shift = false,
      }) async {
        final before = _namedAncestorsOfFocus(tester);
        final heard = recorder.messages.length;
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(key);
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        final stop = describeFocus(tester, previous: before);
        stops.add(stop);
        transcript.writeln('$name: ${stop.line}');
        for (final message in recorder.messages.skip(heard)) {
          transcript.writeln('  announced: $message');
        }
      }

      Future<void> tabUntil(String name) async {
        for (var i = 0; i < 80; i++) {
          if (describeFocus(tester).name.startsWith(name)) return;
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        fail('Tab never reached "$name"');
      }

      transcript.writeln('# The rows');
      await tabUntil('1, APB #1');
      await press('Down', LogicalKeyboardKey.arrowDown);
      await press('End', LogicalKeyboardKey.end);
      await press('Up', LogicalKeyboardKey.arrowUp);
      await press('Up', LogicalKeyboardKey.arrowUp);
      await press('Enter', LogicalKeyboardKey.enter);

      final tab = ProviderScope.containerOf(tester.element(panel));
      expect(
        tab.read(selectedTransactionProvider)?.$1,
        isA<DecodedTransaction>().having((t) => t.startTime, 'start', 25),
        reason: 'Enter selects the row, as a click does',
      );
      expect(tab.read(cursorStateProvider).primaryCursorTime, 25);

      transcript.writeln('# The decoder filter');
      await tabUntil('Decoder filter');
      await press('Enter', LogicalKeyboardKey.enter);
      await press('Down', LogicalKeyboardKey.arrowDown);
      await press('Tab', LogicalKeyboardKey.tab);
      await press('Tab', LogicalKeyboardKey.tab);
      await press('Escape', LogicalKeyboardKey.escape);

      expectCleanFocusWalk(
        FocusWalk(
          stops: stops,
          cycled: true,
          reverse: false,
          offscreen: const {},
        ),
        context: 'transaction table keys',
      );
      _expectTextGolden(
        transcript.toString(),
        '$goldens/transaction_table.txt',
      );
      handle.dispose();
    });

    testWidgets('no label in the table reaches a screen reader as a glyph', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpWithApb(tester);

      final offenders = <String>[];
      void visit(SemanticsNode node) {
        final data = node.getSemanticsData();
        for (final text in [data.label, data.value, data.tooltip]) {
          if (kUnspeakableGlyph.hasMatch(text)) offenders.add(text);
        }
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      for (final view in tester.binding.renderViews) {
        final root = view.owner?.semanticsOwner?.rootSemanticsNode;
        if (root != null) visit(root);
      }
      // The arrows are still on screen; only what is spoken changes.
      expect(find.text('R 0x00000008 → 0x12345678'), findsOneWidget);
      expect(offenders, isEmpty);
      handle.dispose();
    });
  });

  testWidgets(
    'closing the last file puts focus back on the start screen',
    (tester) async {
      // The focused Close File button is rebuilt away when the layout swaps
      // to the empty canvas; NVDA heard nothing and the next Tab restarted
      // at the toolbar. Desktop platforms, where the region scope restores
      // lost focus.
      final handle = tester.ensureSemantics();
      await _pumpViewer(
        tester,
        seedTab: true,
        overrides: [waveformIsLoadedProvider.overrideWithValue(true)],
        tabOverrides: [waveformSourceProvider.overrideWith(_LoadedSource.new)],
      );

      Actions.invoke(
        tester.element(find.byType(ViewerToolbar)),
        const ShortcutActionIntent(ShortcutAction.closeFile),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      expectFocusAnnounced(
        tester,
        named: 'Open File',
        context: 'after closing the last file',
      );
      handle.dispose();
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.windows,
    }),
  );

  group('keys pressed in a dialog stay in the dialog', () {
    // The viewer's bare-key handler listens to the hardware keyboard, below
    // focus, so it used to run with Settings or a dialog on top: Escape in
    // Settings cleared the waveform's cursors, and W, A, D or the M marker
    // chord acted on the waveform behind the dialog.

    Future<ProviderContainer> pumpLoaded(WidgetTester tester) async {
      await _pumpViewer(
        tester,
        seedTab: true,
        overrides: [waveformIsLoadedProvider.overrideWithValue(true)],
        tabOverrides: [waveformSourceProvider.overrideWith(_LoadedSource.new)],
      );
      final tab = ProviderScope.containerOf(
        tester.element(find.byType(SignalTreePanel)),
      );
      tab.read(cursorStateProvider.notifier).placePrimary(500);
      await tester.pump();
      return tab;
    }

    (double, double) zoomOf(ProviderContainer tab) {
      final mapper = tab.read(timeMapperProvider);
      return (mapper.ticksPerPixel, mapper.panOffsetTicks);
    }

    testWidgets('a modal dialog takes Escape, bare keys and marker chords', (
      tester,
    ) async {
      final tab = await pumpLoaded(tester);
      final zoomBefore = zoomOf(tab);

      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(ViewerToolbar)),
          builder: (context) => AlertDialog(
            content: const Text('Dialog'),
            actions: [
              TextButton(
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final key in const [
        LogicalKeyboardKey.keyW,
        LogicalKeyboardKey.keyD,
        LogicalKeyboardKey.keyM,
        LogicalKeyboardKey.keyA,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }
      expect(zoomOf(tab), zoomBefore, reason: 'W and D act on the dialog');
      expect(tab.read(markerStateProvider).markers, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing, reason: 'Escape closes');
      expect(tab.read(cursorStateProvider).primaryCursorTime, 500);

      // Control: with the dialog gone the same keys reach the waveform again,
      // so the assertions above are not vacuous.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.pump();
      expect(zoomOf(tab), isNot(zoomBefore));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(tab.read(cursorStateProvider).primaryCursorTime, isNull);
    });

    testWidgets('Escape in the signal search dialog only closes it', (
      tester,
    ) async {
      final tab = await pumpLoaded(tester);
      Actions.invoke(
        tester.element(find.byType(ViewerToolbar)),
        const ShortcutActionIntent(ShortcutAction.openSearch),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SignalSearchDialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(SignalSearchDialog), findsNothing);
      expect(tab.read(cursorStateProvider).primaryCursorTime, 500);
    });
  });

  testWidgets('Space activates the focused start-screen button', (
    tester,
  ) async {
    var picks = 0;
    await _pumpViewer(
      tester,
      overrides: [
        openFilePickerProvider.overrideWithValue(_picker(null, () => picks++)),
      ],
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(picks, 1, reason: 'Space must reach the focused Open File button');
  });

  testWidgets('a file that fails to load says so', (tester) async {
    final dir = Directory.systemTemp.createTempSync('a11y_open');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/truncated.vcd')
      ..writeAsStringSync(r'$comment');
    final recorder = AnnouncementRecorder.attach(tester);
    await _pumpViewer(
      tester,
      overrides: [
        openFilePickerProvider.overrideWithValue(_picker(file.path, () {})),
      ],
      tabOverrides: [waveformSourceProvider.overrideWith(_FailingSource.new)],
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var i = 0; i < 20 && recorder.messages.isEmpty; i++) {
      // The open path awaits real platform-channel and file work, which fake
      // time alone does not complete.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 1));

    expect(
      recorder.messages,
      contains(startsWith('Could not open truncated.vcd.')),
    );
  });

  // A first launch puts a blocking surface over the app. Before the shared
  // modal gate, focus stayed on the app behind it: Tab walked controls the
  // barrier had silenced, every stop was mute, and Enter could press a button
  // the user could not see. Every other test in this suite seeds the answers,
  // which is why none of them saw it.
  testWidgets('a first launch keeps the keyboard inside the agreement', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpFirstLaunch(tester);

    // The app is built behind the agreement, and unreachable from the
    // keyboard while it is up.
    expect(find.text('Open File…'), findsOneWidget);

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'first launch');
    expect(
      walk.cycled,
      isTrue,
      reason: 'Tab must cycle within the agreement, never escape it',
    );
    expect(
      walk.stops.map((s) => s.name),
      isNot(contains('Open File')),
      reason: 'the app behind the agreement must not be a Tab stop',
    );
    // Two stops, not four: the agreement's Accept and Decline buttons are
    // disabled until the check box is ticked, and a disabled button is not a
    // Tab stop. Ticking it is what the next case does.
    expectFocusWalkGolden(walk, '$goldens/first_launch.txt');
    handle.dispose();
  });

  // The hand-off between the two surfaces. Accepting the agreement closes it
  // with focus inside a dialog that is going away, and the telemetry
  // disclosure is waiting behind it: focus has to land there rather than on
  // the app, which is still covered.
  testWidgets('accepting the agreement moves the keyboard into the telemetry '
      'disclosure', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpFirstLaunch(tester);

    await tester.tap(
      find.text('I have read and accept the End User License Agreement.'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    await tester.pumpAndSettle();

    expect(find.text('End User License Agreement'), findsNothing);
    expect(find.text('Help make WaveCrux better'), findsOneWidget);

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'telemetry disclosure');
    expect(
      walk.cycled,
      isTrue,
      reason: 'Tab must cycle within the disclosure, never escape it',
    );
    expect(
      walk.stops.map((s) => s.name),
      isNot(contains('Open File')),
      reason: 'the app behind the disclosure must not be a Tab stop',
    );
    expectFocusWalkGolden(walk, '$goldens/first_launch_telemetry.txt');
    handle.dispose();
  });
}
