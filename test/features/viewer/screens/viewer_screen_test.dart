// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_stats_strip/crux_stats_strip.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panes/panes.dart';
import 'package:wavecrux/core/providers/paid_tier_actions_installed_provider.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/diff_result.dart';
import 'package:wavecrux/domain/models/memory_stats.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/signal_match.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/comparison/widgets/diff_summary_panel.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/cursors/providers/playback_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_picker_dialog.dart';
import 'package:wavecrux/features/diagnostics/providers/memory_stats_provider.dart';
import 'package:wavecrux/features/search/widgets/signal_search_dialog.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/statistics/widgets/live_statistics_strip.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/mobile_memory_guard_provider.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/features/viewer/widgets/status_bar.dart';
import 'package:wavecrux/features/viewer/widgets/value_column_panel.dart';
import 'package:wavecrux/features/viewer/widgets/viewer_toolbar.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/features/workspace/widgets/wavecrux_empty_canvas.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/bottom_dock_tab.dart';
import 'package:wavecrux/plugins/extra_bottom_dock_tabs_provider.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

import '../../../helpers/product_telemetry_config.dart';

/// Builds an [OpenFilePicker] stub. `file_picker` 12's `pickFiles` is a static
/// method and can't be replaced via `FilePicker.platform = mock`, so the open /
/// compare flows are tested by overriding [openFilePickerProvider]. The stub
/// reports the `allowedExtensions` it was called with via [onExtensions] and
/// resolves to [result].
OpenFilePicker _stubOpenPicker(
  void Function(List<String>? allowedExtensions) onExtensions, {
  FilePickerResult? result,
}) => ({dialogTitle, type = FileType.any, allowedExtensions}) async {
  onExtensions(allowedExtensions);
  return result;
};

/// Fake DiffNotifier that immediately resolves loadSecondFile with an error.
class _ErrorDiffNotifier extends DiffNotifier {
  @override
  Future<void> loadSecondFile(String path) async {
    state = const DiffState(error: 'simulated diff error');
  }
}

/// Fake DiffNotifier that boots in an active, populated diff state — the left
/// pane should swap the signal tree for the [DiffSummaryPanel] when this is the
/// active tab's diff provider.
class _ActiveDiffNotifier extends DiffNotifier {
  @override
  DiffState build() => const DiffState(
    secondFilePath: '/b.vcd',
    diffResult: DiffResult(
      matchedSignals: [
        SignalMatch(pathA: 'top.clk', pathB: 'top.clk'),
        SignalMatch(
          pathA: 'top.data',
          pathB: 'top.data',
          isDifferent: true,
          divergenceRegions: [TimeRange(start: 100, end: 110)],
        ),
      ],
      unmatchedA: [],
      unmatchedB: [],
    ),
  );
}

// ── source notifier stubs ─────────────────────────────────────────────────────

class _LoadingSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() => const AsyncLoading();
}

class _LoadingWithPathNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() {
    currentFilePath = '/tmp/test.vcd';
    return const AsyncLoading();
  }
}

class _ErrorSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() {
    lastAttemptedPath = '/tmp/broken.vcd';
    return AsyncError(Exception('bad VCD'), StackTrace.empty);
  }
}

class _ErrorNoPathNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() =>
      AsyncError(Exception('parse error'), StackTrace.empty);
}

/// Inert memory-guard notifier used in tests that exercise non-desktop
/// device classes. The real notifier starts a periodic Timer on phone/tablet
/// classes which leaks past widget disposal in widget tests.
class _InertMemoryGuardNotifier extends MobileMemoryGuardNotifier {
  @override
  MemoryGuardState build() => const MemoryGuardState();
}

/// Inert memory-stats notifier used in tests where the live statistics strip
/// is visible. The real notifier starts a 2-second periodic Timer that leaks
/// past widget disposal in widget tests.
class _InertMemoryStatsNotifier extends MemoryStatsNotifier {
  @override
  MemoryStats? build() => null;
}

/// Inert session-autosave notifier: skips arming the debounce `ref.listen`
/// chain so a per-tab state mutation (e.g. toggling a panel) doesn't schedule
/// a `Timer(2s)` that leaks past the widget test. Used by tests that mutate
/// per-tab panel state after pumping.
class _InertSessionAutoSaveNotifier extends SessionAutoSaveNotifier {
  @override
  void build() {}
}

/// In-memory [WorkspaceService] that loads/saves nothing and returns
/// [Workspace.empty] immediately. Production [WorkspaceService.load] calls
/// `path_provider.getApplicationSupportDirectory()` which has no test
/// implementation by default — leaving [WorkspaceNotifier.build] hung in
/// `AsyncLoading` and tripping the polling loop in
/// [TabListNotifier._awaitWorkspace].
class _InMemoryWorkspaceService implements WorkspaceService {
  _InMemoryWorkspaceService([this.initialPaneId]);

  /// The id of the single pane the loaded workspace declares. Defaults to
  /// [PaneId.primary] so the placeholder tab seeded by _TestProviderScope
  /// (which carries the primary sentinel) renders. Pass a generated id to
  /// exercise the non-sentinel cross-pane path.
  final PaneId? initialPaneId;

  @override
  Future<Workspace> load() async {
    // The placeholder tab seeded by _TestProviderScope uses
    // [PaneId.primary]; PaneHost filters tabs by paneId == paneId, so the
    // workspace must declare a pane with the same id so the placeholder
    // actually renders. Workspace.empty() generates a new PaneId — use a
    // pinned `WorkspacePane(id: PaneId.primary)` instead.
    final pane = WorkspacePane(id: initialPaneId ?? PaneId.primary);
    return Workspace(
      tabs: const [],
      panes: [pane],
      activePaneId: pane.id,
    );
  }

  @override
  Future<void> save(Workspace workspace) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── test provider scope ───────────────────────────────────────────────────────

/// Wraps a widget tree in a [ProviderContainer] that has [TabContainerManager]
/// properly initialised — required because [ViewerScreen] reads
/// [tabContainerManagerProvider] at build time.
class _TestProviderScope extends StatefulWidget {
  const _TestProviderScope({
    required this.overrides,
    required this.child,
    this.tabOverrides = const [],
    this.seedPlaceholderTab = true,
  });

  final List<Override> overrides;
  final List<Override> tabOverrides;
  final Widget child;

  /// Whether to seed a single placeholder tab in [tabListProvider]
  /// before the widget tree builds. Defaults to `true` so most existing
  /// tests get a non-empty tab list (the IndexedStack renders and per-tab
  /// providers resolve normally). Tests that specifically exercise the
  /// empty-canvas state pass `seedPlaceholderTab: false`.
  final bool seedPlaceholderTab;

  @override
  State<_TestProviderScope> createState() => _TestProviderScopeState();
}

class _TestProviderScopeState extends State<_TestProviderScope> {
  late final TabContainerManager _tcm;
  late final PaneContainerManager _pcm;
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _tcm = TabContainerManager(extraTabOverrides: widget.tabOverrides);
    _pcm = PaneContainerManager();
    // The tab list now derives from the workspace document, so the workspace
    // must hydrate for a seeded tab to appear. Default to the in-memory
    // service (no path_provider, which is unmocked in widget tests) unless a
    // test already supplies its own workspaceServiceProvider override.
    final defaultWsService = workspaceServiceProvider.overrideWithValue(
      _InMemoryWorkspaceService(),
    );
    final testOverridesWsService = widget.overrides.any(
      (o) => o.origin == defaultWsService.origin,
    );
    _container = ProviderContainer(
      overrides: [
        productTelemetryConfig,
        tabContainerManagerProvider.overrideWithValue(_tcm),
        paneContainerManagerProvider.overrideWithValue(_pcm),
        if (!testOverridesWsService) defaultWsService,
        ...widget.overrides,
      ],
    );
    _tcm.init(_container);
    _pcm.init(_container);
    if (widget.seedPlaceholderTab) {
      unawaited(_container.wavecruxWorkspace.newTab(displayName: 'New Tab'));
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

// ── app wrapper ───────────────────────────────────────────────────────────────

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Widget _buildApp({
  Widget home = const ViewerScreen(),
  List<Override> overrides = const [],
  List<Override> tabOverrides = const [],
  TargetPlatform platform = TargetPlatform.macOS,
  bool seedPlaceholderTab = true,
  Locale? locale,
}) {
  return _TestProviderScope(
    overrides: overrides,
    tabOverrides: tabOverrides,
    seedPlaceholderTab: seedPlaceholderTab,
    child: MaterialApp(
      // Default to macOS so MobileMetrics resolves to desktop sizing in
      // tests; touch-platform tests can override per-test.
      theme: ThemeData(platform: platform),
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      locale: locale,
      home: home,
    ),
  );
}

/// Settles a tree whose only animation is indefinite — the empty canvas's
/// [GlowingAppIcon] halo/pulse repeats forever, so [WidgetTester.pumpAndSettle]
/// would spin until it times out. Builds the first frame, then advances fake
/// time enough for the async recent-files/workspaces providers to resolve
/// (without ever waiting for the never-ending animation to settle).
Future<void> _pumpEmptyCanvas(WidgetTester tester) async {
  await tester.pump(); // build the tree
  await tester.pump(const Duration(milliseconds: 300)); // flush async providers
}

void main() {
  group('ViewerScreen', () {
    for (final locale in _locales) {
      testWidgets('renders in $locale without exceptions', (tester) async {
        await tester.pumpWidget(_buildApp(locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // ── empty-canvas state ─────────────────────────────────────────────────────

    testWidgets(
      'renders WaveCruxEmptyCanvas when the tab list is empty',
      (tester) async {
        await tester.pumpWidget(_buildApp(seedPlaceholderTab: false));
        await _pumpEmptyCanvas(tester);
        expect(find.byType(WaveCruxEmptyCanvas), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders the IdeLayout (not the empty-canvas) when at least one tab is open',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pumpAndSettle();
        expect(find.byType(WaveCruxEmptyCanvas), findsNothing);
      },
    );

    // ── toolbar ────────────────────────────────────────────────────────────────

    testWidgets('ViewerToolbar is present', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.byType(ViewerToolbar), findsOneWidget);
    });

    testWidgets('toolbar open-file button is visible', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      // Found by action rather than glyph: the shared toolbar keys every
      // button with its action, so an icon change (filled `folder_open` →
      // the suite-canonical `folder_open_outlined`) cannot break this.
      expect(
        find.byKey(const ValueKey<ShortcutAction>(ShortcutAction.openFile)),
        findsOneWidget,
      );
    });

    testWidgets('toolbar zoom-in button is visible', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.zoom_in), findsOneWidget);
    });

    testWidgets('toolbar settings button is visible', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });

    testWidgets('toolbar Add Decoder button is visible', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.developer_board), findsOneWidget);
    });

    testWidgets('toolbar Add Decoder button disabled when no file loaded', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      final decoderButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.developer_board),
      );
      expect(decoderButton.onPressed, isNull);
    });

    testWidgets(
      'addDecoder shortcut with no file loaded explains itself instead of '
      'opening the picker (descriptor parity + feedback)',
      (tester) async {
        // The keyboard obeys the descriptor table: with no file
        // loaded the picker must NOT open, exactly as the toolbar button is
        // greyed (asserted above), the menu bar / overflow menu grey it, and
        // the palette omits it. A follow-on restored the other half —
        // the guard now names the unmet requirement instead of swallowing the
        // key press, so the Add Decoder guidance the handler used to give is
        // back (from the shared requirement hint, not a per-action string).
        await tester.pumpWidget(_buildApp());
        await tester.pumpAndSettle();

        final toolbarElement = tester.element(find.byType(ViewerToolbar));
        Actions.invoke(
          toolbarElement,
          const ShortcutActionIntent(ShortcutAction.addDecoder),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DecoderPickerDialog), findsNothing);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.text('Load a waveform file to use this command.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'holding a disabled shortcut does not stack duplicate hints',
      (tester) async {
        // Key auto-repeat: `_showDisabledActionHint` drops repeats of the same
        // requirement inside its cooldown, and replaces (never queues) the
        // visible snackbar otherwise, so leaning on the key cannot build a
        // backlog the user then has to sit through.
        await tester.pumpWidget(_buildApp());
        await tester.pumpAndSettle();

        final toolbarElement = tester.element(find.byType(ViewerToolbar));
        for (var i = 0; i < 8; i++) {
          Actions.invoke(
            toolbarElement,
            const ShortcutActionIntent(ShortcutAction.addDecoder),
          );
          await tester.pump(const Duration(milliseconds: 40));
        }
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.text('Load a waveform file to use this command.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('toolbar search button is visible', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      // The search icon appears in both the toolbar and the signal-tree panel.
      expect(find.byIcon(Icons.search), findsAtLeastNWidgets(1));
    });

    testWidgets('tapping toolbar search button opens SignalSearchDialog', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // Tooltips now carry the live keybinding, so an exact-string tooltip
      // match no longer works. Find the button by its action instead.
      await tester.tap(
        find.byKey(const ValueKey<ShortcutAction>(ShortcutAction.openSearch)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SignalSearchDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Ctrl/Cmd+F shortcut intent (ShortcutAction.openSearch) opens SignalSearchDialog',
      (tester) async {
        await tester.pumpWidget(_buildApp());
        await tester.pumpAndSettle();

        // Invoke via the Actions widget registered inside ViewerScreen — the same
        // path the keyboard shortcut takes after ShortcutManagerWidget converts
        // the key event into a ShortcutActionIntent.
        final toolbarElement = tester.element(find.byType(ViewerToolbar));
        Actions.invoke(
          toolbarElement,
          const ShortcutActionIntent(ShortcutAction.openSearch),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SignalSearchDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    // ── status bar ─────────────────────────────────────────────────────────────

    testWidgets('StatusBar is present', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.byType(StatusBar), findsOneWidget);
    });

    testWidgets('status bar shows no range or cursor when idle', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.textContaining('Range:'), findsNothing);
      expect(find.textContaining('T:'), findsNothing);
    });

    // ── panel layout ───────────────────────────────────────────────────────────

    testWidgets('shows signal tree and waveform canvas by default', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.text('Signal Tree'), findsOneWidget);
      expect(
        find.text('Open a waveform file to view signals'),
        findsOneWidget,
      );
    });

    testWidgets('shows value column by default', (tester) async {
      // Default test device class is desktop: the value column is a docked
      // IdeLayout pane (unaffected by the phone behaviour below).
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.byType(ValueColumnPanel), findsOneWidget);
    });

    testWidgets('left pane hosts the signal tree, not the diff panel, by '
        'default', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      expect(find.text('Signal Tree'), findsOneWidget);
      expect(find.byType(DiffSummaryPanel), findsNothing);
    });

    testWidgets('left pane swaps the signal tree for the DiffSummaryPanel when '
        "the active tab's diff is active", (tester) async {
      // A desktop-width surface: activating the diff also renders the center
      // DiffToolbar, and the default 800-wide test surface is too narrow for
      // the full diff chrome (a narrow-surface RenderFlex artifact unrelated to
      // the swap under test). Matches the wider surface other IDE-layout tests
      // in this file use.
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // The leftBuilder watches the per-tab diffProvider, so the active-diff
      // notifier is injected via tabOverrides (not the root scope), mirroring
      // the rightBuilder RtlSourcePanel/ValueColumnPanel swap.
      await tester.pumpWidget(
        _buildApp(
          tabOverrides: [
            diffProvider.overrideWith(_ActiveDiffNotifier.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DiffSummaryPanel), findsOneWidget);
      expect(find.text('Signal Tree'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone has no values endDrawer (inline-at-cursor)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            deviceClassProvider.overrideWithValue(DeviceClass.phone),
            mobileMemoryGuardProvider.overrideWith(
              _InertMemoryGuardNotifier.new,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // There is no modal values endDrawer freezing the canvas
      // behind a scrim; values now render inline at the cursor. No Scaffold
      // exposes an endDrawer. (The left signal-tree Drawer is unaffected.)
      final scaffolds = tester.widgetList<Scaffold>(find.byType(Scaffold));
      expect(scaffolds, isNotEmpty);
      expect(
        scaffolds.every((s) => s.endDrawer == null),
        isTrue,
        reason: 'phone must have no values drawer',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'phone signal-tree drawer reads the active tab scope, not the empty root',
      (tester) async {
        // Regression: on iPhone the signal tree was empty (no signals to add)
        // while iPad/desktop worked. The phone signal-tree lives in the
        // screen-level Scaffold.drawer, which is built OUTSIDE the per-tab
        // UncontrolledProviderScope that PaneHost wraps the body in — so its
        // SignalTreePanel read the empty ROOT waveformSourceProvider. Here the
        // ACTIVE TAB's source is overridden to an error; if the drawer is bound
        // to the tab scope it shows the signal-tree error message, and if it
        // still reads the empty root it shows the "open a file" placeholder.
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              deviceClassProvider.overrideWithValue(DeviceClass.phone),
              mobileMemoryGuardProvider.overrideWith(
                _InertMemoryGuardNotifier.new,
              ),
            ],
            tabOverrides: [
              waveformSourceProvider.overrideWith(_ErrorSourceNotifier.new),
            ],
          ),
        );
        await tester.pumpAndSettle();

        tester
            .state<ScaffoldState>(
              find.byWidgetPredicate((w) => w is Scaffold && w.drawer != null),
            )
            .openDrawer();
        await tester.pumpAndSettle();

        final drawer = find.byType(Drawer);
        expect(drawer, findsOneWidget);
        // Tab scope reached → the tree reflects the active tab's error state.
        expect(
          find.descendant(
            of: drawer,
            matching: find.text('Failed to load waveform'),
          ),
          findsOneWidget,
          reason: 'phone signal-tree drawer must resolve the active tab scope',
        );
        // Empty root scope would instead show this placeholder.
        expect(
          find.descendant(
            of: drawer,
            matching: find.text('Open a waveform file to browse signals'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('transaction view starts hidden per provider default', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ViewerScreen)),
      );
      expect(
        container.read(panelLayoutProvider).transactionViewVisible,
        isFalse,
      );
    });

    testWidgets(
      'panel visibility is per-tab — a new tab keeps its own default and does '
      'not inherit another tab in the same pane',
      (tester) async {
        // Panel visibility is per-tab (panelLayoutProvider, overridden per-tab
        // in wavecruxTabOverrides). Two tabs docked in the same pane each keep
        // their own arrangement, and each tab's IdeController is the geometric
        // mirror of its own state — so the chevron indicator and the rendered
        // panel can never disagree (the desync that motivated the earlier fix
        // is structurally impossible). A new tab starts at the clean-slate
        // defaults; it does NOT pick up another tab's open panel.
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              workspaceServiceProvider.overrideWithValue(
                _InMemoryWorkspaceService(),
              ),
            ],
            // Two tabs each instantiate a per-tab memoryStatsProvider (a
            // Timer.periodic) and a sessionAutoSaveProvider (a debounce timer
            // armed when this test mutates panel state). Both leak past
            // disposal, so stub them inert (TabContainerManager dedupes by
            // Override.origin).
            tabOverrides: [
              memoryStatsProvider.overrideWith(_InertMemoryStatsNotifier.new),
              sessionAutoSaveProvider.overrideWith(
                _InertSessionAutoSaveNotifier.new,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(ViewerScreen)),
        );
        final tcm = container.read(tabContainerManagerProvider);

        // Tab 1 opens its bottom panel — on its OWN per-tab container.
        final tab1Id = container.read(tabListProvider).single.id;
        tcm
            .containerFor(tab1Id)
            .read(panelLayoutProvider.notifier)
            .setTransactionViewVisible(visible: true);
        await tester.pumpAndSettle();

        // Open a second tab in the same pane and make it active.
        await container.wavecruxWorkspace.newTab(displayName: 'New Tab');
        await tester.pumpAndSettle();
        // Creating a tab schedules a debounced workspace save; drain it so the
        // FakeAsync test doesn't fail on the pending Timer.
        await container.wavecruxWorkspace.flushPendingSave();

        final tabs = container.read(tabListProvider);
        expect(tabs, hasLength(2));
        final tab2Id = tabs.last.id;

        // Independence at the state level: tab 2 keeps its default (closed);
        // tab 1 stays open.
        expect(
          tcm
              .containerFor(tab1Id)
              .read(panelLayoutProvider)
              .transactionViewVisible,
          isTrue,
        );
        expect(
          tcm
              .containerFor(tab2Id)
              .read(panelLayoutProvider)
              .transactionViewVisible,
          isFalse,
          reason: "a new tab must not inherit another tab's open panel",
        );

        // Independence at the geometry level: the active tab (tab 2) renders
        // with its bottom pane CLOSED — its IdeController seeded from its OWN
        // default, not from tab 1's open state. (The IndexedStack mounts only
        // the active tab's IdeLayout, so exactly one is findable.) Under the
        // old per-pane model the new tab inherited the pane's open panel.
        final activeIde = tester.widget<IdeLayout>(find.byType(IdeLayout));
        expect(
          activeIde.controller.centerController.isVisible(IdePane.bottom.id),
          isFalse,
          reason:
              'the new active tab seeds its controller from its own closed '
              'default, not from the other tab in the pane',
        );
        // Drain Riverpod's transient dispose-scheduler Timer(0) from the
        // toolbar's Consumer subscription churn so teardown sees no pending
        // timer.
        await tester.pumpAndSettle();
      },
    );

    // ── RTL source panel toggle (regression: per-tab provider scope) ───────────

    testWidgets(
      'toggleRtlSourcePanel flips the ACTIVE TAB state and forces the right '
      'pane open — not the root scope',
      (tester) async {
        // Regression for the orphaned-after-per-tab-refactor bug: the toggle
        // wrote to the root `panelLayoutProvider` while the right-pane builder
        // watched the per-tab instance, so Cmd/Ctrl+Shift+R was a silent no-op.
        // Give the full IDE layout adequate width — with all three panes plus
        // the RTL panel open, the 800px default surface overflows horizontally.
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              // `_handleShortcut` refuses any action the
              // descriptor table reports as disabled, and the root
              // `actionContextProvider` derives `fileLoaded` from the active
              // tab's `filePath` (null for the seeded placeholder tab) or this
              // root-scope flag. Overriding it is the documented widget-test
              // escape hatch (see `actionContextProvider`'s doc comment) for
              // driving the loaded-file branch.
              waveformIsLoadedProvider.overrideWithValue(true),
              workspaceServiceProvider.overrideWithValue(
                _InMemoryWorkspaceService(),
              ),
            ],
            tabOverrides: [
              memoryStatsProvider.overrideWith(_InertMemoryStatsNotifier.new),
              sessionAutoSaveProvider.overrideWith(
                _InertSessionAutoSaveNotifier.new,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final rootContainer = ProviderScope.containerOf(
          tester.element(find.byType(ViewerScreen)),
        );
        final tcm = rootContainer.read(tabContainerManagerProvider);
        final activeTabId = rootContainer.read(activeTabIdProvider);
        final tabContainer = tcm.containerFor(activeTabId);

        // Pre-condition: collapse this tab's value column so the "force the
        // right pane open on reveal" half of the fix is observable.
        tabContainer
            .read(panelLayoutProvider.notifier)
            .setValueColumnVisible(visible: false);
        await tester.pumpAndSettle();
        expect(
          tabContainer.read(panelLayoutProvider).rtlSourceVisible,
          isFalse,
        );

        final toolbarElement = tester.element(find.byType(ViewerToolbar));
        Actions.invoke(
          toolbarElement,
          const ShortcutActionIntent(ShortcutAction.toggleRtlSourcePanel),
        );
        await tester.pumpAndSettle();

        // The ACTIVE TAB's state flips on, and revealing the panel re-opens the
        // value column (the right pane that hosts it).
        expect(
          tabContainer.read(panelLayoutProvider).rtlSourceVisible,
          isTrue,
          reason: 'the toggle must hit the active tab, not the root scope',
        );
        expect(
          tabContainer.read(panelLayoutProvider).valueColumnVisible,
          isTrue,
          reason: 'revealing the RTL panel must open its host right pane',
        );
        // The root scope must be untouched — the precise marker of the bug.
        expect(
          rootContainer.read(panelLayoutProvider).rtlSourceVisible,
          isFalse,
          reason: 'the root panelLayoutProvider must not be written',
        );

        // Toggling again hides the RTL panel; the value column stays visible.
        Actions.invoke(
          toolbarElement,
          const ShortcutActionIntent(ShortcutAction.toggleRtlSourcePanel),
        );
        await tester.pumpAndSettle();
        expect(
          tabContainer.read(panelLayoutProvider).rtlSourceVisible,
          isFalse,
        );
        expect(
          tabContainer.read(panelLayoutProvider).valueColumnVisible,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'toggleCocotbLogPanel flips the ACTIVE TAB state, not the root scope',
      (tester) async {
        // Same scope-leak class as the RTL toggle: the cocotb log panel
        // visibility lives in the per-tab panelLayoutProvider, so the toggle
        // must hit the active tab's container.
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              workspaceServiceProvider.overrideWithValue(
                _InMemoryWorkspaceService(),
              ),
            ],
            tabOverrides: [
              memoryStatsProvider.overrideWith(_InertMemoryStatsNotifier.new),
              sessionAutoSaveProvider.overrideWith(
                _InertSessionAutoSaveNotifier.new,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final rootContainer = ProviderScope.containerOf(
          tester.element(find.byType(ViewerScreen)),
        );
        final tcm = rootContainer.read(tabContainerManagerProvider);
        final tabContainer = tcm.containerFor(
          rootContainer.read(activeTabIdProvider),
        );

        expect(
          tabContainer.read(panelLayoutProvider).cocotbLogPanelVisible,
          isFalse,
        );

        Actions.invoke(
          tester.element(find.byType(ViewerToolbar)),
          const ShortcutActionIntent(ShortcutAction.toggleCocotbLogPanel),
        );
        await tester.pumpAndSettle();

        expect(
          tabContainer.read(panelLayoutProvider).cocotbLogPanelVisible,
          isTrue,
          reason: 'the toggle must hit the active tab, not the root scope',
        );
        // Toggling the cocotb log on also reveals the bottom (transaction) pane.
        expect(
          tabContainer.read(panelLayoutProvider).transactionViewVisible,
          isTrue,
        );
        expect(
          rootContainer.read(panelLayoutProvider).cocotbLogPanelVisible,
          isFalse,
          reason: 'the root panelLayoutProvider must not be written',
        );
        expect(tester.takeException(), isNull);
      },
    );

    // ── toggleStagePanel dock-coupling (dispatch behavior) ────────────────────

    testWidgets(
      'toggleStagePanel opens Stage AND docks the bottom pane; toggling off '
      'hides Stage but leaves the pane docked — all on the ACTIVE TAB',
      (tester) async {
        // The dock-coupling lives only in the dispatch case's closure
        // (viewer_screen_shortcuts.dart): opening Stage force-opens the
        // bottom pane so the panel is actually visible; closing Stage
        // deliberately does NOT undock. Previously untested behavior.
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              // `_handleShortcut` refuses any action the
              // descriptor table reports as disabled, and the root
              // `actionContextProvider` derives `fileLoaded` from the active
              // tab's `filePath` (null for the seeded placeholder tab) or this
              // root-scope flag. Overriding it is the documented widget-test
              // escape hatch (see `actionContextProvider`'s doc comment) for
              // driving the loaded-file branch.
              waveformIsLoadedProvider.overrideWithValue(true),
              workspaceServiceProvider.overrideWithValue(
                _InMemoryWorkspaceService(),
              ),
            ],
            tabOverrides: [
              memoryStatsProvider.overrideWith(_InertMemoryStatsNotifier.new),
              sessionAutoSaveProvider.overrideWith(
                _InertSessionAutoSaveNotifier.new,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final rootContainer = ProviderScope.containerOf(
          tester.element(find.byType(ViewerScreen)),
        );
        final tcm = rootContainer.read(tabContainerManagerProvider);
        final tabContainer = tcm.containerFor(
          rootContainer.read(activeTabIdProvider),
        );

        // Pre-condition: Stage hidden, bottom pane closed.
        expect(
          tabContainer.read(panelLayoutProvider).stageViewVisible,
          isFalse,
        );
        expect(
          tabContainer.read(panelLayoutProvider).transactionViewVisible,
          isFalse,
        );

        Actions.invoke(
          tester.element(find.byType(ViewerToolbar)),
          const ShortcutActionIntent(ShortcutAction.toggleStagePanel),
        );
        await tester.pumpAndSettle();

        expect(
          tabContainer.read(panelLayoutProvider).stageViewVisible,
          isTrue,
          reason: 'the toggle must hit the active tab, not the root scope',
        );
        expect(
          tabContainer.read(panelLayoutProvider).transactionViewVisible,
          isTrue,
          reason: 'opening Stage must dock the bottom pane so it is visible',
        );
        expect(
          rootContainer.read(panelLayoutProvider).stageViewVisible,
          isFalse,
          reason: 'the root panelLayoutProvider must not be written',
        );

        // Toggle off: Stage hides, the docked pane deliberately stays open.
        Actions.invoke(
          tester.element(find.byType(ViewerToolbar)),
          const ShortcutActionIntent(ShortcutAction.toggleStagePanel),
        );
        await tester.pumpAndSettle();
        expect(
          tabContainer.read(panelLayoutProvider).stageViewVisible,
          isFalse,
        );
        expect(
          tabContainer.read(panelLayoutProvider).transactionViewVisible,
          isTrue,
          reason: 'closing Stage must not undock the bottom pane',
        );
        expect(tester.takeException(), isNull);
      },
    );

    // ── togglePlayback stage-visible guard (dispatch behavior) ────────────────

    testWidgets(
      'togglePlayback is inert while the Stage panel is hidden and toggles '
      "the ACTIVE TAB's playback once it is visible",
      (tester) async {
        // The guard lives only in the dispatch case: Space must not start
        // playback when Stage is hidden (the bare-key path is not
        // descriptor-gated). Previously untested behavior.
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              // `_handleShortcut` refuses any action the
              // descriptor table reports as disabled, and the root
              // `actionContextProvider` derives `fileLoaded` from the active
              // tab's `filePath` (null for the seeded placeholder tab) or this
              // root-scope flag. Overriding it is the documented widget-test
              // escape hatch (see `actionContextProvider`'s doc comment) for
              // driving the loaded-file branch.
              waveformIsLoadedProvider.overrideWithValue(true),
              workspaceServiceProvider.overrideWithValue(
                _InMemoryWorkspaceService(),
              ),
            ],
            tabOverrides: [
              memoryStatsProvider.overrideWith(_InertMemoryStatsNotifier.new),
              sessionAutoSaveProvider.overrideWith(
                _InertSessionAutoSaveNotifier.new,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final rootContainer = ProviderScope.containerOf(
          tester.element(find.byType(ViewerScreen)),
        );
        final tcm = rootContainer.read(tabContainerManagerProvider);
        final tabContainer = tcm.containerFor(
          rootContainer.read(activeTabIdProvider),
        );

        // Arm playback: PlaybackNotifier.play() no-ops on an empty time
        // mapper, so seed the ACTIVE TAB's mapper with a non-degenerate range
        // (the same seeding the waveform load performs).
        tabContainer
            .read(timeMapperProvider.notifier)
            .initialize(
              startTime: 0,
              endTime: 10000,
              viewportWidth: 1000,
            );

        // Stage hidden (default): Space is inert.
        expect(
          tabContainer.read(panelLayoutProvider).stageViewVisible,
          isFalse,
        );
        Actions.invoke(
          tester.element(find.byType(ViewerToolbar)),
          const ShortcutActionIntent(ShortcutAction.togglePlayback),
        );
        await tester.pump();
        expect(
          tabContainer.read(playbackProvider).isPlaying,
          isFalse,
          reason: 'togglePlayback must no-op while the Stage panel is hidden',
        );

        // Stage visible: the same action toggles the per-tab engine. Mirror
        // the real toggle site — it seeds a default panel and reveals the
        // stage tab (the guard reads `bottomDockShowsStage`, which needs the
        // bottom pane docked with a stage tab frontmost, not just the flag).
        tabContainer.read(stageWorkspaceProvider.notifier).addPanel('Stage');
        tabContainer.read(panelLayoutProvider.notifier)
          ..setStageViewVisible(visible: true)
          ..revealBottomDockTab(kBottomDockStagePrefix);
        await tester.pump();

        Actions.invoke(
          tester.element(find.byType(ViewerToolbar)),
          const ShortcutActionIntent(ShortcutAction.togglePlayback),
        );
        // Bare pumps: a playing engine schedules frames continuously, so
        // pumpAndSettle would never settle here.
        await tester.pump();
        expect(
          tabContainer.read(playbackProvider).isPlaying,
          isTrue,
          reason: 'with Stage visible the action must start playback',
        );

        // Toggle again: pauses (and stops the ticker so the test ends clean).
        Actions.invoke(
          tester.element(find.byType(ViewerToolbar)),
          const ShortcutActionIntent(ShortcutAction.togglePlayback),
        );
        await tester.pump();
        expect(tabContainer.read(playbackProvider).isPlaying, isFalse);
        expect(tester.takeException(), isNull);
      },
    );

    // ── Clear Canvas / Remove Selected Signals (dispatch behavior) ──────────

    testWidgets(
      "Clear Canvas empties the ACTIVE TAB's list, keeps its cursor and "
      'markers, and the Undo snackbar restores the signals',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              // Same escape hatch as the togglePlayback test: drives the
              // loaded-file branch of the descriptor guard.
              waveformIsLoadedProvider.overrideWithValue(true),
              workspaceServiceProvider.overrideWithValue(
                _InMemoryWorkspaceService(),
              ),
            ],
            tabOverrides: [
              memoryStatsProvider.overrideWith(_InertMemoryStatsNotifier.new),
              sessionAutoSaveProvider.overrideWith(
                _InertSessionAutoSaveNotifier.new,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final rootContainer = ProviderScope.containerOf(
          tester.element(find.byType(ViewerScreen)),
        );
        final tab = rootContainer
            .read(tabContainerManagerProvider)
            .containerFor(rootContainer.read(activeTabIdProvider));
        tab
            .read(signalGroupsProvider.notifier)
            .restoreFromSession(
              SignalGroup(
                entries: [
                  SignalEntry.signal(
                    id: 'id_a',
                    signalRef: 'ref_a',
                    displayName: 'a',
                  ),
                  SignalEntry.signal(
                    id: 'id_b',
                    signalRef: 'ref_b',
                    displayName: 'b',
                  ),
                ],
              ),
            );
        final before = tab.read(signalGroupsProvider);
        tab.read(cursorStateProvider.notifier).placePrimary(120);
        tab.read(markerStateProvider.notifier).setMarker('a', 300);
        await tester.pumpAndSettle();

        Actions.invoke(
          tester.element(find.byType(ViewerToolbar)),
          const ShortcutActionIntent(ShortcutAction.clearCanvas),
        );
        await tester.pumpAndSettle();

        expect(tab.read(signalGroupsProvider).entries, isEmpty);
        expect(tab.read(cursorStateProvider).primaryCursorTime, 120);
        expect(tab.read(markerStateProvider).getMarker('a'), 300);
        expect(find.text('Canvas cleared'), findsOneWidget);

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(tab.read(signalGroupsProvider), before);

        // Remove Selected Signals, by name, takes only the selection.
        tab.read(selectedVariablesProvider.notifier).selectOnly('b');
        await tester.pumpAndSettle();
        Actions.invoke(
          tester.element(find.byType(ViewerToolbar)),
          const ShortcutActionIntent(ShortcutAction.removeSelectedSignals),
        );
        await tester.pumpAndSettle();
        expect(
          tab.read(signalGroupsProvider).entries.map((e) => e.displayName),
          ['a'],
        );
        expect(find.text('Removed 1 signal'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'firing a contributed-tab toggler reveals the bottom pane when the tab '
      'is visible',
      (tester) async {
        // Regression: contributed bottom-dock togglers (SVA, AI Waveform
        // Assistant) only flip their own visibility flag, which selects
        // bottom-pane *content* but does not open the pane. Firing the action
        // while the pane is collapsed appeared to do nothing. Dispatch now calls
        // `_revealBottomPaneForContributedTab`, which opens the pane on the
        // active tab when a contributed tab is visible. The open-core toggler
        // for `aiAdvisorTogglePanel` is a no-op (Pro overrides it), so we drive
        // the helper directly with an already-visible contributed tab.
        final visibility = Provider<bool>((_) => true);
        final tab = BottomDockTab(
          id: 'test_contributed_tab',
          labelResolver: (_) => 'Test Tab',
          icon: Icons.smart_toy_outlined,
          builder: (_) => const SizedBox.shrink(),
          visibilityProvider: visibility,
        );
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              extraBottomDockTabsProvider.overrideWithValue([tab]),
              // An overlay that contributes the tab also installs the
              // Pro-tier action handlers.
              paidTierActionsInstalledProvider.overrideWithValue(true),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final rootContainer = ProviderScope.containerOf(
          tester.element(find.byType(ViewerScreen)),
        );
        final tcm = rootContainer.read(tabContainerManagerProvider);
        final tabContainer = tcm.containerFor(
          rootContainer.read(activeTabIdProvider),
        );

        expect(
          tabContainer.read(panelLayoutProvider).transactionViewVisible,
          isFalse,
        );

        Actions.invoke(
          tester.element(find.byType(ViewerToolbar)),
          const ShortcutActionIntent(ShortcutAction.aiAdvisorTogglePanel),
        );
        await tester.pumpAndSettle();

        expect(
          tabContainer.read(panelLayoutProvider).transactionViewVisible,
          isTrue,
          reason: 'a visible contributed tab must reveal the bottom pane',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a Pro or Enterprise action in open core says which edition it needs',
      (tester) async {
        // Open core lists these with their tier badge, but their extension
        // points are no-ops; firing one used to do nothing at all.
        await tester.pumpWidget(_buildApp());
        await tester.pumpAndSettle();
        final anchor = tester.element(find.byType(ViewerToolbar));
        final l10n = L10N.of(anchor);

        Actions.invoke(
          anchor,
          const ShortcutActionIntent(ShortcutAction.debugAdvisorTogglePanel),
        );
        await tester.pump();
        expect(
          find.text(
            l10n.actionRequiresWaveCruxPro(
              ShortcutAction.debugAdvisorTogglePanel.label(l10n),
            ),
          ),
          findsOneWidget,
        );
        ScaffoldMessenger.of(anchor).removeCurrentSnackBar();
        await tester.pumpAndSettle();

        Actions.invoke(
          anchor,
          const ShortcutActionIntent(ShortcutAction.convertPcapToVcd),
        );
        await tester.pump();
        expect(
          find.text(
            l10n.actionRequiresWaveCruxEnterprise(
              ShortcutAction.convertPcapToVcd.label(l10n),
            ),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'firing a contributed-tab toggler leaves the bottom pane closed when no '
      'tab is visible',
      (tester) async {
        // The reveal only ever *opens*: with no contributed tab visible (e.g. a
        // gated sub-Pro tier, or toggling a tab off) the pane is left as-is.
        final visibility = Provider<bool>((_) => false);
        final tab = BottomDockTab(
          id: 'test_contributed_tab',
          labelResolver: (_) => 'Test Tab',
          icon: Icons.smart_toy_outlined,
          builder: (_) => const SizedBox.shrink(),
          visibilityProvider: visibility,
        );
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              extraBottomDockTabsProvider.overrideWithValue([tab]),
              // An overlay that contributes the tab also installs the
              // Pro-tier action handlers.
              paidTierActionsInstalledProvider.overrideWithValue(true),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final rootContainer = ProviderScope.containerOf(
          tester.element(find.byType(ViewerScreen)),
        );
        final tcm = rootContainer.read(tabContainerManagerProvider);
        final tabContainer = tcm.containerFor(
          rootContainer.read(activeTabIdProvider),
        );

        Actions.invoke(
          tester.element(find.byType(ViewerToolbar)),
          const ShortcutActionIntent(ShortcutAction.aiAdvisorTogglePanel),
        );
        await tester.pumpAndSettle();

        expect(
          tabContainer.read(panelLayoutProvider).transactionViewVisible,
          isFalse,
          reason: 'no visible contributed tab must leave the pane closed',
        );
        expect(tester.takeException(), isNull);
      },
    );

    // ── loading state ──────────────────────────────────────────────────────────

    testWidgets('shows loading indicator when source is loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          // Production [WorkspaceService.load] hits path_provider and stays
          // in AsyncLoading throughout the test, which makes
          // [TabListNotifier._awaitWorkspace] poll a Timer(Duration.zero) 50×
          // and trip the framework's pending-timer check. The stub resolves
          // load() immediately so the polling loop returns on its first read.
          overrides: [
            workspaceServiceProvider.overrideWithValue(
              _InMemoryWorkspaceService(),
            ),
          ],
          tabOverrides: [
            waveformSourceProvider.overrideWith(_LoadingSourceNotifier.new),
          ],
        ),
      );
      await tester.pump();
      // Both WaveformViewCenter and SignalTreePanel show spinners when loading.
      expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows filename in loading text when path is set', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            workspaceServiceProvider.overrideWithValue(
              _InMemoryWorkspaceService(),
            ),
          ],
          tabOverrides: [
            waveformSourceProvider.overrideWith(_LoadingWithPathNotifier.new),
          ],
        ),
      );
      await tester.pump();
      // Filename may appear in both the loading indicator and the status bar.
      expect(find.textContaining('test.vcd'), findsAtLeastNWidgets(1));
      expect(tester.takeException(), isNull);
    });

    // ── error state ────────────────────────────────────────────────────────────

    testWidgets('shows error UI when source fails to load', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          tabOverrides: [
            waveformSourceProvider.overrideWith(_ErrorSourceNotifier.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      // Error text appears in center pane + status bar; verify at least one.
      expect(
        find.textContaining('Failed to load waveform'),
        findsAtLeastNWidgets(1),
      );
      // No retry button: with one parser per platform any load failure is
      // deterministic, so the error overlay no longer offers retry.
      expect(find.text('Try Again'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('error state shows error icon', (tester) async {
      await tester.pumpWidget(
        _buildApp(
          tabOverrides: [
            waveformSourceProvider.overrideWith(_ErrorNoPathNotifier.new),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // ── file picker extensions ─────────────────────────────────────────────────

    testWidgets(
      'open-file uses all wellen extensions when mode is platformDefault',
      (tester) async {
        List<String>? capturedExtensions;
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              openFilePickerProvider.overrideWithValue(
                _stubOpenPicker((e) => capturedExtensions = e),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(
            const ValueKey<ShortcutAction>(ShortcutAction.openFile),
          ),
        );
        await tester.pumpAndSettle();

        // Includes the four waveform formats AND `.wavecrux` session
        // files — the post-pick dispatch routes session files to the
        // session loader instead of the waveform parser.
        expect(
          capturedExtensions,
          containsAll(['vcd', 'fst', 'ghw', 'fsdb', 'wavecrux']),
        );
      },
    );

    // ── compareWaveforms ───────────────────────────────────────────────────────

    testWidgets('compareWaveforms shows snackbar when diff load fails', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          overrides: [
            // `_handleShortcut` refuses any action the
            // descriptor table reports as disabled, and the root
            // `actionContextProvider` derives `fileLoaded` from the active
            // tab's `filePath` (null for the seeded placeholder tab) or this
            // root-scope flag. Overriding it is the documented widget-test
            // escape hatch (see `actionContextProvider`'s doc comment) for
            // driving the loaded-file branch.
            waveformIsLoadedProvider.overrideWithValue(true),
            openFilePickerProvider.overrideWithValue(
              _stubOpenPicker(
                (_) {},
                result: FilePickerResult([
                  PlatformFile(name: 'bad.vcd', size: 0, path: '/bad.vcd'),
                ]),
              ),
            ),
          ],
          // diffProvider is per-tab — _compareWaveforms now (correctly) reads
          // the ACTIVE TAB's container, so the fake must be a TAB override. With
          // it at the root scope (as this test had it before the scope-leak
          // fix) the override silently never applied — exactly the masking that
          // let the diff-into-root-scope bug pass CI.
          tabOverrides: [
            diffProvider.overrideWith(_ErrorDiffNotifier.new),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // ViewerToolbar is inside the Actions widget so invoke can walk up to it.
      final toolbarElement = tester.element(find.byType(ViewerToolbar));
      Actions.invoke(
        toolbarElement,
        const ShortcutActionIntent(ShortcutAction.compareWaveforms),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Diff error:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'compareWaveforms uses all wellen extensions when mode is platformDefault',
      (tester) async {
        List<String>? capturedExtensions;
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              // `_handleShortcut` refuses any action the
              // descriptor table reports as disabled, and the root
              // `actionContextProvider` derives `fileLoaded` from the active
              // tab's `filePath` (null for the seeded placeholder tab) or this
              // root-scope flag. Overriding it is the documented widget-test
              // escape hatch (see `actionContextProvider`'s doc comment) for
              // driving the loaded-file branch.
              waveformIsLoadedProvider.overrideWithValue(true),
              openFilePickerProvider.overrideWithValue(
                _stubOpenPicker((e) => capturedExtensions = e),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final toolbarElement = tester.element(find.byType(ViewerToolbar));
        Actions.invoke(
          toolbarElement,
          const ShortcutActionIntent(ShortcutAction.compareWaveforms),
        );
        await tester.pumpAndSettle();

        expect(capturedExtensions, containsAll(['vcd', 'fst', 'ghw', 'fsdb']));
      },
    );

    // ── live statistics strip ──────────────────────────────────────────────────

    testWidgets(
      'LiveStatisticsStrip is not present when device class is phone',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              deviceClassProvider.overrideWithValue(DeviceClass.phone),
              mobileMemoryGuardProvider.overrideWith(
                _InertMemoryGuardNotifier.new,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LiveStatisticsStrip), findsNothing);
        expect(find.byType(StatusBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'LiveStatisticsStrip is not present when device class is tablet',
      (tester) async {
        // Tablet device class forces touch toolbar metrics (48-dp buttons),
        // which need more horizontal space than the default 800-dp test
        // surface; widen to a typical tablet landscape size.
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              deviceClassProvider.overrideWithValue(DeviceClass.tablet),
              mobileMemoryGuardProvider.overrideWith(
                _InertMemoryGuardNotifier.new,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LiveStatisticsStrip), findsNothing);
        expect(find.byType(StatusBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'LiveStatisticsStrip is mounted but collapsed by default on desktop',
      (tester) async {
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              deviceClassProvider.overrideWithValue(DeviceClass.desktop),
            ],
          ),
        );
        await tester.pumpAndSettle();
        // The strip owns its disclosure row, so it is always mounted on
        // desktop; the default statisticsStripVisible == false collapses it
        // to that row instead of removing it. Without the row there would be
        // nothing left to reveal the feature.
        expect(find.byType(LiveStatisticsStrip), findsOneWidget);
        expect(
          tester.getSize(find.byType(LiveStatisticsStrip)).height,
          kCruxStatsStripCollapsedHeight,
        );
        expect(find.byType(StatusBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'LiveStatisticsStrip expands when statisticsStripVisible is true on desktop',
      (tester) async {
        // Per Issue 20 fix: `memoryStatsProvider` is now overridden per-tab
        // in `wavecruxTabOverrides`. The inert stub must therefore be
        // supplied via `TabContainerManager.extraTabOverrides` (which dedupes
        // by `Override.origin` so caller-supplied entries win over the
        // default per-tab notifier), otherwise the per-tab default starts a
        // real polling Timer.periodic and trips the test framework's
        // pending-timer check.
        final tcm3 = TabContainerManager(
          extraTabOverrides: [
            memoryStatsProvider.overrideWith(_InertMemoryStatsNotifier.new),
            // Strip visibility is per-tab now; toggling it arms the per-tab
            // session autosave debounce. Stub it inert so no Timer leaks.
            sessionAutoSaveProvider.overrideWith(
              _InertSessionAutoSaveNotifier.new,
            ),
          ],
        );
        final pcm3 = PaneContainerManager();
        final container3 = ProviderContainer(
          overrides: [
            productTelemetryConfig,
            tabContainerManagerProvider.overrideWithValue(tcm3),
            paneContainerManagerProvider.overrideWithValue(pcm3),
            deviceClassProvider.overrideWithValue(DeviceClass.desktop),
          ],
        );
        tcm3.init(container3);
        pcm3.init(container3);
        addTearDown(tcm3.dispose);
        addTearDown(pcm3.dispose);
        addTearDown(container3.dispose);
        // Panel visibility is per-tab: set the flag on the active tab's
        // container (the empty-canvas chrome resolves the strip through that
        // tab's scope), not the root.
        tcm3
            .containerFor(container3.read(activeTabIdProvider))
            .read(panelLayoutProvider.notifier)
            .setStatisticsStripVisible(visible: true);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container3,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: const ViewerScreen(),
            ),
          ),
        );
        await _pumpEmptyCanvas(tester);

        expect(find.byType(LiveStatisticsStrip), findsOneWidget);
        expect(
          tester.getSize(find.byType(LiveStatisticsStrip)).height,
          kCruxStatsStripHeight + kCruxStatsStripCollapsedHeight,
        );
        expect(find.byType(StatusBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'LiveStatisticsStrip is not present on phone even when statisticsStripVisible is true',
      (tester) async {
        final tcm4 = TabContainerManager();
        final pcm4 = PaneContainerManager();
        final container4 = ProviderContainer(
          overrides: [
            productTelemetryConfig,
            tabContainerManagerProvider.overrideWithValue(tcm4),
            paneContainerManagerProvider.overrideWithValue(pcm4),
            deviceClassProvider.overrideWithValue(DeviceClass.phone),
            mobileMemoryGuardProvider.overrideWith(
              _InertMemoryGuardNotifier.new,
            ),
          ],
        );
        tcm4.init(container4);
        pcm4.init(container4);
        addTearDown(tcm4.dispose);
        addTearDown(pcm4.dispose);
        addTearDown(container4.dispose);
        container4
            .read(panelLayoutProvider.notifier)
            .setStatisticsStripVisible(visible: true);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container4,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: const ViewerScreen(),
            ),
          ),
        );
        await _pumpEmptyCanvas(tester);

        expect(find.byType(LiveStatisticsStrip), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    // ── cross-pane tab drag: semantics reparent regression ─────────────────
    //
    // Dragging a tab from one pane to another must not crash the semantics
    // layer. The per-tab waveform RepaintBoundary is the ONLY GlobalKey in
    // the tab-content subtree; when a tab's paneId flips, its content leaves
    // the source pane's IndexedStack and enters the target pane's. With a
    // pane-agnostic key Flutter MIGRATED that live element across the two
    // IndexedStacks in a single frame, and flushSemantics then walked a stale
    // parent->child geometry relationship — tripping
    // `identical(childRenderObject, parentRenderObject)` at
    // rendering/object.dart and a follow-on null-check crash. Scoping the key
    // per (pane, tab) tears the canvas down in the source pane and rebuilds it
    // fresh in the target pane, so no element migrates. Semantics MUST be
    // enabled here so the per-frame flushSemantics actually runs.
    testWidgets(
      'dragging a tab between panes does not crash semantics (cross-pane reparent)',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.binding.setSurfaceSize(const Size(1400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _buildApp(
            // Resolve workspace load immediately so splitPane()/the tab mirror
            // don't hang on path_provider (see the loading-state tests above).
            overrides: [
              workspaceServiceProvider.overrideWithValue(
                _InMemoryWorkspaceService(),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(ViewerScreen)),
          listen: false,
        );

        // Two tabs in the starting (primary) pane, then split into two panes.
        // The placeholder tab (T1) is seeded by _TestProviderScope; add a
        // second (T2), which becomes the active tab and renders in the left
        // pane's IndexedStack.
        await container.wavecruxWorkspace.newTab(displayName: 'New Tab');
        await tester.pumpAndSettle();
        final paneB = await container.wavecruxWorkspace.splitPane();
        await container.wavecruxWorkspace.flushPendingSave();
        await tester.pumpAndSettle();

        // Move the active tab (still living in the left pane) into the right
        // pane, mirroring the real drop handler which updates BOTH the live tab
        // list (drives the render) and the workspace (persistence).
        final moveId = container.read(tabListProvider).last.id;
        await container.wavecruxWorkspace.moveTabToPane(moveId, paneB);
        await container.wavecruxWorkspace.moveTabToPane(moveId, paneB);
        // Pump frames so both IndexedStacks rebuild and a semantics flush runs
        // against the reparented tree.
        await tester.pump();
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: 'cross-pane tab move must not trip the semantics assertion',
        );

        // Teardown: unmount before disposing so the workspace mirror's debounced
        // save timer is cancelled, then drop the semantics handle.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        semantics.dispose();
      },
    );

    // Companion smoke test for the non-sentinel path: two REAL (non-primary)
    // panes, so the PaneId.primary sentinel never fires and there is no
    // double-render — the configuration of the user's bug report. It moves a
    // tab between the two panes with semantics enabled and asserts the move
    // completes without exception, exercising the non-sentinel branch of host
    // key resolution (and `_activeTabRepaintKey`).
    //
    // NOTE: unlike the test above, this one does NOT fail pre-fix. The
    // framework's `_SemanticsGeometry.computeChildGeometry`
    // `identical(childRenderObject, parentRenderObject)` assertion that the
    // user hit needs the real desktop binding's per-frame flushSemantics and
    // does not reproduce under the widget-test binding; and with distinct tab
    // ids the pane-agnostic key never collides here. The pre-fix-failing guard
    // for the shared root cause (a pane-agnostic content GlobalKey) is the
    // sentinel-collision test above. This test guards against the host-pane
    // resolution itself regressing (dropping the tab, throwing, or colliding).
    testWidgets(
      'moving a tab between two non-primary panes does not crash semantics',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.binding.setSurfaceSize(const Size(1400, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final paneA = PaneId.generate();
        await tester.pumpWidget(
          _buildApp(
            // No placeholder tab and a non-primary starting pane, so every tab
            // carries a real pane id (no primary sentinel).
            seedPlaceholderTab: false,
            overrides: [
              workspaceServiceProvider.overrideWithValue(
                _InMemoryWorkspaceService(paneA),
              ),
            ],
          ),
        );
        // Starts with zero tabs → empty canvas (indefinite GlowingAppIcon
        // animation), so pump bounded frames instead of pumpAndSettle.
        await _pumpEmptyCanvas(tester);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(ViewerScreen)),
          listen: false,
        );

        // Two empty tabs pinned to the real pane A, then split into A + B.
        await container.wavecruxWorkspace.newTab(
          displayName: 'New Tab',
          paneId: paneA,
        );
        await container.wavecruxWorkspace.newTab(
          displayName: 'New Tab',
          paneId: paneA,
        );
        await tester.pumpAndSettle();
        final paneB = await container.wavecruxWorkspace.splitPane();
        await container.wavecruxWorkspace.flushPendingSave();
        await tester.pumpAndSettle();

        // Move the active tab from pane A to pane B (mirror both notifiers).
        final moveId = container.read(tabListProvider).last.id;
        await container.wavecruxWorkspace.moveTabToPane(moveId, paneB);
        await container.wavecruxWorkspace.moveTabToPane(moveId, paneB);
        await tester.pump();
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'non-sentinel cross-pane move must not trip the '
              'semantics reparent assertion',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        semantics.dispose();
      },
    );
  });
}
