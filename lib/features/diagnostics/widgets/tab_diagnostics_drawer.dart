// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/domain/models/wavecrux_tab.dart';
import 'package:wavecrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:wavecrux/features/diagnostics/widgets/file_info_panel.dart';
import 'package:wavecrux/features/diagnostics/widgets/parser_benchmark_runner.dart';
import 'package:wavecrux/features/diagnostics/widgets/signal_health_panel.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/diagnostics/tab_diagnostics_report_service.dart';
import 'package:wavecrux/services/tabs/active_tab_navigator.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Non-modal per-tab side drawer (see `docs/ARCHITECTURE.md` §8.8).
///
/// Reads the active tab via [activeTabIdProvider] (derived from the
/// workspace) and displays three collapsible sections — File Info, Signal
/// Health, and Benchmark This File — sourced from the existing per-tab
/// diagnostics providers. When the source tab is closed, the drawer
/// auto-dismisses.
///
/// Rendered on tablet and desktop only; hidden on phone (matches the existing
/// diagnostics gating). Open via [TabDiagnosticsDrawer.open]; the open path is
/// also wired into the tab context menu, command palette, and a keyboard
/// shortcut (Cmd/Ctrl+Shift+I).
class TabDiagnosticsDrawer extends ConsumerStatefulWidget {
  const TabDiagnosticsDrawer({required this.onClose, super.key});

  /// Invoked when the drawer requests dismissal — close button tap, Escape
  /// key, or the no-tabs-remaining auto-dismiss. The host (the [open] static
  /// method's overlay-entry plumbing) removes the entry from the overlay.
  final VoidCallback onClose;

  /// Opens the drawer as a right-aligned non-modal overlay.
  ///
  /// Inserts an [OverlayEntry] into the ACTIVE tab's navigator overlay
  /// ([ActiveTab.navigatorFor]) rather than pushing a modal dialog route, so
  /// the drawer is built under the tab's one provider scope and reads the
  /// tab's providers (a root-scope mount would show "No waveform loaded" with
  /// a file open). When another tab becomes active the drawer moves to that
  /// tab's overlay, so it keeps following the active tab. With no tab
  /// navigator (a host with no tabs mounted) it goes on the root overlay.
  ///
  /// The former [showGeneralDialog] implementation (Issue 24) installed a
  /// full-screen [ModalBarrier] beneath the drawer that — even with
  /// `barrierColor: Colors.transparent` — captured every pointer event
  /// outside the drawer's bounds, making the tab close (×) button (and every
  /// other surface outside the drawer) unresponsive while the drawer was
  /// open. The overlay-entry approach leaves the underlying chrome fully
  /// interactive; only the drawer's own Material region absorbs events.
  ///
  /// Returns when the drawer is closed (close button, Escape key, or the
  /// no-tabs-remaining auto-dismiss).
  static Future<void> open(BuildContext context) {
    // Re-entrancy guard: a second trigger (Cmd/Ctrl+Shift+I auto-repeat, the
    // per-pane `i`-icon, or the menu while the drawer is already up) must not
    // stack a second overlay drawer on top of itself. One key for the window:
    // there is one drawer, and it follows the active tab.
    return ModalGuard.run('tabDiagnostics', () async {
      final drawer = _TabDiagnosticsDrawerPlacement(context)..show();
      await drawer.closed;
    });
  }

  @override
  ConsumerState<TabDiagnosticsDrawer> createState() =>
      _TabDiagnosticsDrawerState();
}

/// Keeps the drawer's one overlay entry on the active tab's navigator.
///
/// The entry is built under whichever tab's scope owns that navigator, so
/// following the active tab means moving the entry: when the active tab
/// changes (a switch, or the drawer's own tab closing) the entry is
/// re-inserted into the new active tab's overlay after the frame that built
/// it. No tab left closes the drawer.
class _TabDiagnosticsDrawerPlacement {
  _TabDiagnosticsDrawerPlacement(BuildContext callerContext)
    : _rootOverlay = Overlay.of(callerContext, rootOverlay: true);

  final OverlayState _rootOverlay;
  final Completer<void> _closed = Completer<void>();
  ProviderSubscription<TabId>? _activeSubscription;
  ProviderSubscription<List<WavecruxTab>>? _tabsSubscription;
  OverlayEntry? _entry;
  TabId? _tab;
  bool _syncScheduled = false;

  /// The ROOT container: the root overlay sits above every tab scope. Not a
  /// tab's container, which closes with its tab.
  ProviderContainer get _root =>
      ProviderScope.containerOf(_rootOverlay.context, listen: false);

  /// Completes when the drawer has closed.
  Future<void> get closed => _closed.future;

  void show() {
    _place(animateIn: true);
    if (_closed.isCompleted) return;
    _activeSubscription = _root.listen<TabId>(
      activeTabIdProvider,
      (_, _) => _scheduleSync(),
    );
    _tabsSubscription = _root.listen<List<WavecruxTab>>(
      tabListProvider,
      (_, _) => _scheduleSync(),
    );
  }

  void close() {
    _activeSubscription?.close();
    _activeSubscription = null;
    _tabsSubscription?.close();
    _tabsSubscription = null;
    _entry?.remove();
    _entry = null;
    if (!_closed.isCompleted) _closed.complete();
  }

  void _place({required bool animateIn}) {
    final tabs = _root.read(tabListProvider);
    if (tabs.isEmpty) {
      close(); // the no-tabs auto-dismiss
      return;
    }
    final active = _root.read(activeTabIdProvider);
    final navigator = _root.read(tabNavigatorsProvider).navigatorFor(active);
    _entry?.remove();
    _tab = navigator == null ? null : active;
    final entry = OverlayEntry(
      builder: (_) =>
          _TabDiagnosticsDrawerHost(onClose: close, animateIn: animateIn),
    );
    _entry = entry;
    (navigator?.overlay ?? _rootOverlay).insert(entry);
  }

  void _scheduleSync() {
    if (_syncScheduled || _closed.isCompleted) return;
    _syncScheduled = true;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        _syncScheduled = false;
        if (_closed.isCompleted) return;
        final tabs = _root.read(tabListProvider);
        if (tabs.isEmpty) {
          close();
          return;
        }
        if (_root.read(activeTabIdProvider) != _tab) _place(animateIn: false);
      })
      ..ensureVisualUpdate();
  }
}

/// Wraps [TabDiagnosticsDrawer] with the slide-in transition and an
/// Escape-to-close keyboard shortcut. Owns the [AnimationController] so
/// the entrance animation runs the first time the entry mounts. It is built
/// under the tab scope of the navigator its entry is on, so the drawer reads
/// that tab's providers without a scope of its own.
class _TabDiagnosticsDrawerHost extends StatefulWidget {
  const _TabDiagnosticsDrawerHost({
    required this.onClose,
    required this.animateIn,
  });

  final VoidCallback onClose;

  /// False when the drawer moves to another tab: it is already open, so it
  /// neither slides in again nor takes focus.
  final bool animateIn;

  @override
  State<_TabDiagnosticsDrawerHost> createState() =>
      _TabDiagnosticsDrawerHostState();
}

class _TabDiagnosticsDrawerHostState extends State<_TabDiagnosticsDrawerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _offset =
        Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
        );
    if (!widget.animateIn) {
      _controller.value = 1;
      return;
    }
    _controller.forward();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _controller.reverse();
    if (!mounted) return;
    widget.onClose();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Escape-to-close. The shortcut activator binds at this host's
    // [Focus]/[Shortcuts] level (not deeper inside the drawer) so the key
    // event is consumed even when no inner widget has focus.
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              unawaited(_close());
              return null;
            },
          ),
        },
        child: FocusScope(
          autofocus: widget.animateIn,
          child: SlideTransition(
            position: _offset,
            child: TabDiagnosticsDrawer(onClose: () => unawaited(_close())),
          ),
        ),
      ),
    );
  }
}

class _TabDiagnosticsDrawerState extends ConsumerState<TabDiagnosticsDrawer> {
  late TabId _targetTabId;

  @override
  void initState() {
    super.initState();
    _targetTabId = _ownTabId() ?? ref.read(activeTabIdProvider);
  }

  /// The tab whose scope this drawer is built under, or null on the root
  /// overlay (no tab navigator): the drawer then shows the active tab's name
  /// over the root scope's empty state.
  TabId? _ownTabId() {
    try {
      return ref.read(tabIdProvider);
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final deviceClass = ref.watch(deviceClassProvider);
    final diagnosticsEnabled = ref.watch(diagnosticsEnabledProvider);

    // Device gating: hide on phone / phone-landscape; hide when the user has
    // disabled diagnostics. In both cases close immediately so the drawer does
    // not linger when the gating condition flips after open (window resize).
    if (deviceClass == DeviceClass.phone ||
        deviceClass == DeviceClass.phoneLandscape ||
        !diagnosticsEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onClose();
      });
      return const SizedBox.shrink();
    }

    final activeTabId = ref.watch(activeTabIdProvider);
    final tabs = ref.watch(tabListProvider);

    // Auto-dismiss when no tabs remain (its target is gone). Watching the
    // tab list keeps this reactive: closing the last tab triggers a rebuild
    // and the post-frame pop fires.
    if (tabs.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onClose();
      });
      return const SizedBox.shrink();
    }

    // The tab this drawer is built under (the placement moves the drawer to
    // the new active tab's navigator when the active tab changes). On the
    // root overlay there is no such tab: follow the active one.
    _targetTabId = _ownTabId() ?? activeTabId;
    final targetTabId = _targetTabId;
    final WavecruxTab? activeTab = _firstWhereOrNull(
      tabs,
      (t) => t.id == targetTabId,
    );

    // The drawer hosts the existing FileInfoPanel / SignalHealthPanel /
    // ParserBenchmarkRunner widgets, which were designed for a full
    // diagnostics dialog (~800 dp). The drawer takes ~45% of the overlay it
    // is on (the tab's area) with a 480 dp floor and a 720 dp ceiling so these
    // panels still fit without overflow, and never more than that area.
    return LayoutBuilder(
      builder: (context, constraints) {
        final drawerWidth = (constraints.maxWidth * 0.45).clamp(480.0, 720.0);
        final clampedWidth = constraints.maxWidth < drawerWidth
            ? constraints.maxWidth
            : drawerWidth;
        return Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
            child: Material(
              elevation: 8,
              color: theme.colorScheme.surface,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: clampedWidth),
                child: SizedBox(
                  width: clampedWidth,
                  height: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(
                        key: const Key('tabDiagnosticsHeader'),
                        activeTab: activeTab,
                        onCopy: () =>
                            _copyReport(context, ref, l10n, activeTab),
                        onClose: widget.onClose,
                      ),
                      const Divider(height: 1),
                      Expanded(
                        // The embedded panels (FileInfoPanel,
                        // SignalHealthPanel, ParserBenchmarkRunner) read
                        // per-tab providers (`waveformSourceProvider`,
                        // `hierarchyProvider`, ...) that only a tab's
                        // container overrides. The drawer's overlay entry is
                        // on that tab's navigator, so it is built under the
                        // tab's one scope; no scope of its own.
                        child: SingleChildScrollView(
                          key: const Key('tabDiagnosticsScroll'),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Section(
                                key: const Key(
                                  'tabDiagnosticsSectionFileInfo',
                                ),
                                title: l10n.tabDiagnosticsSectionFileInfo,
                                child: const FileInfoPanel(),
                              ),
                              _Section(
                                key: const Key(
                                  'tabDiagnosticsSectionSignalHealth',
                                ),
                                title: l10n.tabDiagnosticsSectionSignalHealth,
                                child: const SignalHealthPanel(),
                              ),
                              _Section(
                                key: const Key(
                                  'tabDiagnosticsSectionBenchmarkFile',
                                ),
                                title: l10n.tabDiagnosticsSectionBenchmarkFile,
                                child: const ParserBenchmarkRunner(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _copyReport(
    BuildContext context,
    WidgetRef ref,
    L10N l10n,
    WavecruxTab? tab,
  ) async {
    final report = const TabDiagnosticsReportService().generate(
      ref: ref,
      tabId: _targetTabId,
      tab: tab,
    );
    await Clipboard.setData(ClipboardData(text: report));
    if (!context.mounted) return;
    showCruxInfoSnack(context, l10n.tabDiagnosticsCopyReportSuccess);
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.activeTab,
    required this.onCopy,
    required this.onClose,
    super.key,
  });

  final WavecruxTab? activeTab;
  final VoidCallback onCopy;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final fileName = activeTab?.displayName;
    final subtitle = fileName == null || fileName.isEmpty
        ? l10n.tabDiagnosticsSubtitleNoFile
        : l10n.tabDiagnosticsSubtitle(fileName);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.tabDiagnosticsTitle,
                  style: theme.textTheme.titleLarge,
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('tabDiagnosticsCopyReportButton'),
            tooltip: l10n.tabDiagnosticsCopyReportTooltip,
            icon: const Icon(Icons.copy),
            onPressed: onCopy,
          ),
          const SizedBox(width: 4),
          IconButton(
            key: const Key('tabDiagnosticsCloseButton'),
            tooltip: l10n.tabDiagnosticsCloseTooltip,
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

// ── Section ───────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    super.key,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      // Strip the ExpansionTile splash divider so successive sections render
      // cleanly under the drawer's single elevation surface.
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        childrenPadding: EdgeInsets.zero,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        // The embedded panels (FileInfoPanel, SignalHealthPanel,
        // ParserBenchmarkRunner) lay out with Flexible / Expanded rows that
        // adapt to whatever bounded horizontal constraint the drawer
        // provides. Render them directly without a fixed height or width:
        // the outer drawer's SingleChildScrollView handles vertical
        // overflow across all sections. The legacy SizedBox(height: 320) +
        // horizontal-scroll-with-SizedBox(width: 720) wrapper hid sections
        // below the 320-pixel fold (Issue 33: "Signals by direction
        // section absent") and clipped the value column off the right
        // edge on drawer widths < 720 dp (Issue 32: right edge clipped).
        children: [child],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

T? _firstWhereOrNull<T>(Iterable<T> source, bool Function(T) test) {
  for (final element in source) {
    if (test(element)) return element;
  }
  return null;
}
