// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_status_bar/crux_status_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/providers/status_bar_trailing_widgets_provider.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/signal_load_indicator.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Highlight color applied to the secondary cursor time and delta segments
/// so they stand out as a measurement pair.
const _kMeasureColor = Color(0xFF64B5F6); // blue-300

/// Status bar displayed at the bottom of the waveform viewer screen.
///
/// On phone shows only the loaded file name and primary cursor time to
/// conserve vertical space. On tablet and desktop shows the full set of
/// segments: file name, primary cursor, secondary cursor + delta, selected
/// signal value, simulation range, and zoom level.
class StatusBar extends ConsumerWidget {
  const StatusBar({
    this.onShowBottomPanelSheet,
    super.key,
  });

  /// Called when the user taps the bottom-pane chevron on a phone-class
  /// device. Phone widths force-hide the IdeLayout bottom pane, so the
  /// host (ViewerScreen) is responsible for surfacing the same content as
  /// a modal bottom sheet. When `null` the chevron falls back to the
  /// regular [PanelLayoutNotifier.setTransactionViewVisible] toggle —
  /// useful for tests and any embedding that has its own bottom-panel UX.
  final VoidCallback? onShowBottomPanelSheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);
    final isPhone =
        deviceClass == DeviceClass.phone ||
        deviceClass == DeviceClass.phoneLandscape;
    final sourceAsync = ref.watch(waveformSourceProvider);
    final cursorState = ref.watch(cursorStateProvider);
    final mapper = ref.watch(timeMapperProvider);
    final timescale = ref.watch(currentTimescaleProvider);

    // Reactive file path: re-reads the notifier field whenever the source
    // state changes so the file name stays in sync with loads and closes.
    final filePath = ref.read(waveformSourceProvider.notifier).currentFilePath;

    final formatter = TimeFormatService(timescale: timescale);
    final theme = Theme.of(context);
    // Typography per ARCHITECTURE.md §3.1.8.13 — read from MobileMetrics so the
    // status bar text scales to 13 sp on touch / 11 pt on desktop. Everything
    // else is the shared bar's own baseline, so its colour follows the theme's
    // status bar foreground like the rest of the suite's status text.
    final textStyle = CruxStatusBar.resolveTextStyle(
      context,
    )?.copyWith(fontSize: metrics.statusBarText);

    // ── build segments ────────────────────────────────────────────────────────
    // Phone: file name + primary cursor only (conserve vertical space).
    // Tablet / desktop: full status bar with all segments.

    final segments = <Widget>[];

    // File name
    if (filePath != null) {
      final filename = _basename(filePath);
      segments.add(_StatusSegment(label: filename, style: textStyle));
    } else if (sourceAsync.hasError) {
      segments.add(
        _StatusSegment(
          label: l10n.waveformCenterLoadError,
          style: textStyle?.copyWith(color: theme.colorScheme.error),
        ),
      );
    }

    // Primary cursor time (shown on all device classes)
    final cursorTime = cursorState.primaryCursorTime;
    if (cursorTime != null && !mapper.isEmpty) {
      segments.add(
        _StatusSegment(
          label: l10n.statusBarCursorAt(formatter.format(cursorTime)),
          style: textStyle,
        ),
      );
    }

    if (!isPhone) {
      // Secondary cursor time and delta measurement
      final secondaryTime = cursorState.secondaryCursorTime;
      if (secondaryTime != null && !mapper.isEmpty) {
        final measureStyle = textStyle?.copyWith(color: _kMeasureColor);
        segments.add(
          _StatusSegment(
            label: l10n.statusBarSecondaryCursorAt(
              formatter.format(secondaryTime),
            ),
            style: measureStyle,
          ),
        );

        final delta = ref.watch(cursorDeltaProvider);
        if (delta.deltaDisplay != null) {
          segments.add(
            _StatusSegment(
              label: l10n.statusBarDelta(delta.deltaDisplay!),
              style: measureStyle,
            ),
          );
        }
        if (delta.frequencyDisplay != null) {
          segments.add(
            _StatusSegment(
              label: l10n.statusBarFrequency(delta.frequencyDisplay!),
              style: measureStyle,
            ),
          );
        }
      }

      // Selected signal value — first selected signal from the tree, if any.
      //
      // Switched from the global signalValuesAtCursorProvider (which forced
      // a 1000+-call valueAt sweep on every cursor frame) to the per-signal
      // family provider. We watch only the *one* signal whose value the
      // status bar actually shows.
      // Selection carries fullPaths (row identity); resolve the first one to
      // its Variable to reach the signalRef the value providers key on. The
      // displayed name comes from the selected row's own path, so with FST
      // aliasing it matches the scope the user clicked.
      final selectedPaths = ref.watch(selectedVariablesProvider);
      final selectedVariable = selectedPaths.isNotEmpty
          ? ref.watch(signalVariablesByPathProvider)[selectedPaths.first]
          : null;
      if (selectedPaths.isNotEmpty) {
        final signalGroup = ref.watch(signalGroupsProvider);
        final entry = selectedVariable == null
            ? null
            : _findSignalEntry(signalGroup.entries, selectedVariable.signalRef);
        if (entry != null) {
          final sigValue = ref.watch(
            signalValueAtCursorProvider(
              selectedVariable!.signalRef,
              entry.format,
              entry.translatorConfig,
            ),
          );
          if (sigValue != null) {
            final varName = selectedVariable.name;
            segments.add(
              _StatusSegment(
                label: '$varName = ${sigValue.formatted}',
                style: textStyle,
              ),
            );
          }
        }
        // A small ✕ affordance to clear the whole signal selection, shown
        // whenever a selection exists (independent of whether the selected
        // signal has a value at the cursor). Calls the same notifier as the
        // clearSignalSelection action / Escape key.
        segments.add(
          _ClearSelectionButton(
            tooltip: l10n.statusBarClearSelectionTooltip,
            metrics: metrics,
            color:
                textStyle?.color ??
                theme.colorScheme.onSurface.withValues(alpha: 0.75),
            onClear: () => ref.read(selectedVariablesProvider.notifier).clear(),
          ),
        );
      }

      // Simulation range
      if (!mapper.isEmpty) {
        final start = formatter.format(mapper.startTime);
        final end = formatter.format(mapper.endTime);
        segments.add(
          _StatusSegment(
            label: l10n.statusBarSimRange('$start – $end'),
            style: textStyle,
          ),
        );
      }

      // Zoom level (visible range as % of full range; 100 % = fit-all)
      if (!mapper.isEmpty) {
        final fullRange = mapper.endTime - mapper.startTime;
        final visibleRange = mapper.visibleRange.clamp(1, fullRange);
        final pct = (fullRange / visibleRange * 100).round();
        segments.add(
          _StatusSegment(
            label: l10n.statusBarZoom('$pct%'),
            style: textStyle,
          ),
        );
      }
    }

    // Panel chevrons render on every device class. Touch users on phone find
    // it hard to grab the panel splitters with a finger, so the chevrons give
    // them a deterministic toggle target. The overflow-menu toggle actions
    // remain available as a backup but the chevrons in the status bar are
    // the primary discoverable toggle.

    // Three direction-flipping chevrons control the panel visibility on every
    // device class. Left and right chevrons pin to the screen edges; the
    // bottom chevron sits at the geometric center between two equal-flex
    // Expanded gaps.
    //
    // The chevron arrow points in the direction the panel will move on tap
    // (left chevron pointing left = "I will close the left panel"). The
    // arrow direction must reflect *effective* visibility, not the raw
    // [panelState] field — on phone widths the IdeLayout force-hide
    // override (ARCHITECTURE.md §3.1.8.6 and `_syncControllerToState` in
    // ViewerScreen) keeps the side / bottom panes hidden regardless of the
    // user's stored preference, so showing the chevron pointing inward
    // ("close") would lie about the rendered state. We mirror the same
    // computation here so the chevron tracks reality.
    // Panel visibility is **per-tab**: the StatusBar is always rendered inside
    // its tab's `ProviderContainer` (PaneHost wraps the per-tab content; the
    // empty-canvas chrome wraps the active tab's container), so reading
    // [panelLayoutProvider] resolves to THIS tab's state. Each tab keeps its
    // own panel arrangement and the per-tab session sidecar persists it.
    final panelState = ref.watch(panelLayoutProvider);
    final notifier = ref.read(panelLayoutProvider.notifier);
    void setSignalTreeVisible({required bool visible}) =>
        notifier.setSignalTreeVisible(visible: visible);

    void setTransactionViewVisible({required bool visible}) =>
        notifier.setTransactionViewVisible(visible: visible);

    final effectiveLeft = !isPhone && panelState.signalTreeVisible;
    final effectiveBottom = !isPhone && panelState.transactionViewVisible;

    // Compose the shared cross-suite chrome (CruxStatusBar owns the height,
    // typography, surface/border, and clamped text scaling — the canonical
    // WaveCrux look). WaveCrux contributes its own slots: the left panel
    // chevron (leading), its status segments (divider-joined + scrolling), the
    // desktop statistics toggle (segmentsTrailing), the geometrically-centered
    // bottom-panel chevron (center), and the trailing group — signal-load
    // indicator, the open-core/Pro `statusBarTrailingWidgetsProvider` slot, and
    // the value-column chevron.
    return CruxStatusBar(
      height: metrics.statusBarHeight,
      textStyle: textStyle,
      semanticsLabel: l10n.accessibilityStatusBarRegion,
      // Desktop/tablet chevrons are GONE (the panel-model pass): collapse
      // lives in each dock's strip, reveal in the View menu / palette /
      // toolbar. The chevrons that remain are phone-only, where they are not
      // collapse affordances at all — they are the phone's ONLY panel access
      // (the drawer and the bottom sheet).
      leading: [
        if (isPhone)
          _PanelChevronButton(
            visible: effectiveLeft,
            edge: _PanelChevronEdge.left,
            metrics: metrics,
            tooltipShow: l10n.panelEdgeTabShowSignalTree,
            tooltipHide: l10n.panelHide,
            semanticsLabel: l10n.panelSignalTree,
            onTap: () {
              // On phone the IdeLayout left pane is force-hidden — present
              // the same content as a Drawer instead. ViewerScreen provides
              // the drawer; we just open it here.
              final scaffold = Scaffold.maybeOf(context);
              if (scaffold?.hasDrawer ?? false) {
                scaffold!.openDrawer();
                return;
              }
              setSignalTreeVisible(
                visible: !panelState.signalTreeVisible,
              );
            },
          ),
      ],
      segments: segments,
      // No trailing segment: the statistics strip's disclosure lives on the
      // strip itself, where the rest of the suite puts it — see
      // LiveStatisticsStrip. A control here would be a second affordance for
      // one piece of state.
      center: isPhone
          ? _PanelChevronButton(
              visible: effectiveBottom,
              edge: _PanelChevronEdge.bottom,
              metrics: metrics,
              tooltipShow: l10n.panelEdgeTabShowTransactionView,
              tooltipHide: l10n.panelHide,
              semanticsLabel: l10n.panelTransactionView,
              onTap: () {
                if (onShowBottomPanelSheet != null) {
                  // Phone widths can't host the IdeLayout bottom pane — the
                  // host renders the equivalent content as a modal bottom
                  // sheet so the user can still review transactions / Stage /
                  // FSM / x-trace / activity / cocotb panels on a small
                  // screen.
                  onShowBottomPanelSheet!();
                  return;
                }
                setTransactionViewVisible(
                  visible: !panelState.transactionViewVisible,
                );
              },
            )
          : null,
      trailing: [
        // Determinate progress while a large batch of signals decompresses
        // (e.g. "Add All in Scope" on a wide scope, or scrolling a wide file).
        // Renders nothing when idle.
        const SignalLoadIndicator(),
        // Trailing extension slot (open-core seam). Open Core injects nothing;
        // the Pro overlay injects Enterprise chrome such as the collaborative-
        // session status chip. Each injected widget renders SizedBox.shrink()
        // when it has nothing to show, so the slot is weightless when idle.
        for (final trailing in ref.watch(statusBarTrailingWidgetsProvider))
          trailing,
        // No right chevron on any device class: the right dock's strip owns
        // collapse on desktop/tablet, and on phone there is no values pane at
        // all — values render inline at the cursor via
        // InlineCursorValueOverlay.
      ],
    );
  }

  /// Extracts the last path component (filename) from [path].
  static String _basename(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  /// Recursively searches [entries] for a [SignalEntryKind.signal] whose
  /// `signalRef` matches [signalRef]. Used by the status bar to look up the
  /// display format for the currently selected signal so it can call the
  /// per-signal `signalValueAtCursorProvider` family with the correct args.
  static SignalEntry? _findSignalEntry(
    List<SignalEntry> entries,
    String signalRef,
  ) {
    for (final entry in entries) {
      if (entry.kind == SignalEntryKind.signal &&
          entry.signalRef == signalRef) {
        return entry;
      }
      if (entry.kind == SignalEntryKind.group) {
        final found = _findSignalEntry(entry.children, signalRef);
        if (found != null) return found;
      }
    }
    return null;
  }
}

/// A small tappable ✕ button rendered next to the selected-signal indicator
/// that clears the entire signal selection. Its hit area honors
/// [MobileMetrics.touchTarget] so it meets the 44 dp touch floor on touch
/// device classes while staying compact on desktop. The tooltip uses the
/// default trigger mode — the status bar is chrome, not a row inside a
/// `PlatformContextMenu`, so there is no long-press arena to lose.
class _ClearSelectionButton extends StatelessWidget {
  const _ClearSelectionButton({
    required this.tooltip,
    required this.metrics,
    required this.color,
    required this.onClear,
  });

  final String tooltip;
  final MobileMetrics metrics;
  final Color color;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: metrics.touchTarget,
        height: metrics.touchTarget,
        child: InkWell(
          key: const ValueKey('status_bar_clear_selection'),
          onTap: onClear,
          child: Center(
            child: Icon(Icons.close, size: metrics.iconSize, color: color),
          ),
        ),
      ),
    );
  }
}

/// A single text segment in the status bar.
class _StatusSegment extends StatelessWidget {
  const _StatusSegment({required this.label, required this.style});

  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: style, overflow: TextOverflow.ellipsis);
  }
}

/// Which screen edge a [_PanelChevronButton] is anchored to.
enum _PanelChevronEdge { left, right, bottom }

/// Direction-flipping chevron button rendered in the [StatusBar] for one of
/// the three docked panels. Per ARCHITECTURE.md §3.1.8.6.1, the chevron points
/// in the direction of the on-tap motion (left chevron pointing left = "tap
/// to close left panel"; pointing right = "tap to open").
class _PanelChevronButton extends StatelessWidget {
  const _PanelChevronButton({
    required this.visible,
    required this.edge,
    required this.metrics,
    required this.tooltipShow,
    required this.tooltipHide,
    required this.semanticsLabel,
    required this.onTap,
  });

  final bool visible;
  final _PanelChevronEdge edge;
  final MobileMetrics metrics;
  final String tooltipShow;
  final String tooltipHide;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    switch (edge) {
      case _PanelChevronEdge.left:
        icon = visible ? Icons.chevron_left : Icons.chevron_right;
      case _PanelChevronEdge.right:
        icon = visible ? Icons.chevron_right : Icons.chevron_left;
      case _PanelChevronEdge.bottom:
        icon = visible ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up;
    }
    final tooltip = visible ? tooltipHide : tooltipShow;
    return Semantics(
      button: true,
      label: '$semanticsLabel — $tooltip',
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          width: metrics.touchTarget,
          height: metrics.touchTarget,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Icon(
                icon,
                size: metrics.iconSize,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
