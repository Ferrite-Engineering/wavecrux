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
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
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
  /// Inserts an [OverlayEntry] into the root [Overlay] rather than pushing a
  /// modal dialog route. The former [showGeneralDialog] implementation
  /// (Issue 24) installed a full-screen [ModalBarrier] beneath the drawer
  /// that — even with `barrierColor: Colors.transparent` — captured every
  /// pointer event outside the drawer's bounds, making the tab close (×)
  /// button (and every other surface outside the drawer) unresponsive
  /// while the drawer was open. The overlay-entry approach leaves the
  /// underlying chrome fully interactive; only the drawer's own Material
  /// region absorbs events.
  ///
  /// Returns when the drawer is closed (close button, Escape key, or the
  /// no-tabs-remaining auto-dismiss).
  static Future<void> open(BuildContext context) {
    // Re-entrancy guard: a second trigger (Cmd/Ctrl+Shift+I auto-repeat, the
    // per-pane `i`-icon, or the menu while the drawer is already up) must not
    // stack a second overlay drawer on top of itself.
    return ModalGuard.run('tabDiagnostics', () {
      final overlay = Overlay.of(context, rootOverlay: true);
      final completer = Completer<void>();
      late OverlayEntry entry;
      void close() {
        if (entry.mounted) entry.remove();
        if (!completer.isCompleted) completer.complete();
      }

      entry = OverlayEntry(
        builder: (overlayContext) => _TabDiagnosticsDrawerHost(
          onClose: close,
        ),
      );
      overlay.insert(entry);
      return completer.future;
    });
  }

  @override
  ConsumerState<TabDiagnosticsDrawer> createState() =>
      _TabDiagnosticsDrawerState();
}

/// Wraps [TabDiagnosticsDrawer] with the slide-in transition and an
/// Escape-to-close keyboard shortcut. Owns the [AnimationController] so
/// the entrance animation runs the first time the entry mounts.
class _TabDiagnosticsDrawerHost extends StatefulWidget {
  const _TabDiagnosticsDrawerHost({required this.onClose});

  final VoidCallback onClose;

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
          autofocus: true,
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
    // Snapshot the active tab at open time. The drawer follows the active
    // tab thereafter (build() re-reads `activeTabIdProvider`); this
    // initial value drives the auto-dismiss check when no tabs are open.
    _targetTabId = ref.read(activeTabIdProvider);
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

    // Follow the active tab. The user may have switched tabs since the
    // drawer opened; mirror that update so the sections re-render against
    // the new tab's per-tab providers.
    _targetTabId = activeTabId;
    final WavecruxTab? activeTab = _firstWhereOrNull(
      tabs,
      (t) => t.id == activeTabId,
    );

    final mediaSize = MediaQuery.sizeOf(context);
    // The drawer hosts the existing FileInfoPanel / SignalHealthPanel /
    // ParserBenchmarkRunner widgets, which were designed for a full
    // diagnostics dialog (~800 dp). The drawer takes ~45% of the viewport
    // with a 480 dp floor and a 720 dp ceiling so these panels still fit
    // without overflow.
    final drawerWidth = mediaSize.width * 0.45;
    final clampedWidth = drawerWidth.clamp(480.0, 720.0);

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
              height: mediaSize.height,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    key: const Key('tabDiagnosticsHeader'),
                    activeTab: activeTab,
                    onCopy: () => _copyReport(context, ref, l10n, activeTab),
                    onClose: widget.onClose,
                  ),
                  const Divider(height: 1),
                  Expanded(
                    // The embedded panels (FileInfoPanel,
                    // SignalHealthPanel, ParserBenchmarkRunner) read
                    // per-tab providers — `waveformSourceProvider`,
                    // `hierarchyProvider`, etc. — that are only
                    // overridden inside each tab's [ProviderContainer].
                    // showGeneralDialog mounts this drawer above the
                    // Navigator, which sits above every per-tab
                    // [UncontrolledProviderScope], so without an
                    // explicit scope wrapper the panels would resolve
                    // those providers from the root container where no
                    // file is loaded — File Info would show "No
                    // waveform loaded" and Signal Health would report
                    // zero clocks even when the active tab has a file
                    // open (Issue 10).
                    child: UncontrolledProviderScope(
                      // Keyed by the target tab id so a tab switch fully
                      // remounts this subtree against the new tab's
                      // container — without the key, Flutter reuses the
                      // existing scope state across container changes
                      // and the embedded panels' subscriptions can race
                      // teardown of the previous container's elements.
                      // Namespaced so it never collides with the tab chip's
                      // `ValueKey(tab.id)` (see tab_drag_reorder regression).
                      key: ValueKey('tabScope.diag:${_targetTabId.value}'),
                      container: ref
                          .read(tabContainerManagerProvider)
                          .containerFor(_targetTabId),
                      child: SingleChildScrollView(
                        key: const Key('tabDiagnosticsScroll'),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Section(
                              key: const Key('tabDiagnosticsSectionFileInfo'),
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
