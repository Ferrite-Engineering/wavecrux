// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_stats_strip/crux_stats_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/pane_id.dart';
import 'package:wavecrux/domain/models/render_pipeline_stats.dart';
import 'package:wavecrux/features/diagnostics/providers/memory_stats_provider.dart';
import 'package:wavecrux/features/panes/providers/active_pane_id_provider.dart';
import 'package:wavecrux/features/panes/providers/pane_render_stats_provider.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';

/// Pane indicator labels used by the strip when split-pane is active.
///
/// First pane is "L", second is "R". With a single pane the indicator is
/// suppressed — see [_panesIndicatorFor].
const List<String> _kPaneIndicators = ['L', 'R'];

/// Ambient real-time performance monitor displayed between the `IdeLayout`
/// and the status bar.
///
/// Presentation is the suite's shared [CruxStatsStrip] — the same widget
/// NetCrux and SimCrux render, and itself the extraction of WaveCrux's
/// original statistics strip. WaveCrux supplies the readings; the strip supplies
/// the cells, typography, sparklines and scroll behaviour.
///
/// Two ownership tiers, per ARCHITECTURE.md §8.8:
///
///   - **App-level segments** read root-scope providers and stay continuous
///     across pane focus changes. Memory, FPS and Dropped come from the
///     suite's shared collectors ([cruxMemoryStatsProvider],
///     [cruxFrameStatsProvider]) so the three products report the same
///     quantities the same way; Wellen DB and the decompressed-signal count
///     are WaveCrux's own ([memoryStatsProvider]).
///   - **Per-pane segments** (paint time + sparkline, render time) read the
///     *active pane's* [paneRenderStatsProvider]. Each pane retains its own
///     rolling sparkline buffer inside its [ProviderContainer], so switching
///     the active pane swaps the visible sparkline without losing either
///     pane's history.
///
/// FPS was WaveCrux-specific and wrong: `1e6 / paintMicroseconds` for the
/// active pane, which is the rate the canvas *could* sustain if the app did
/// nothing else. It read a pinned "999" on any healthy design and never
/// moved between repaints. [CruxFrameStatsNotifier] measures real
/// `SchedulerBinding` frame timings, which is also what §8.8 always said
/// this segment was.
///
/// The disclosure triangle is the shared one, in the same place as every
/// other product's. It drives WaveCrux's own `statisticsStripVisible` rather
/// than [cruxStatsStripExpandedProvider], because that bit is per tab,
/// persisted in the session sidecar, and reachable from a keyboard shortcut
/// — all of which the shared provider is explicitly there to let a host
/// keep.
///
/// The strip mounts collapsed-but-present: the parent renders it whenever the
/// platform allows one at all, and the triangle decides whether it is 24 px
/// or 120 px tall. The strip is desktop only — see ARCHITECTURE.md §3.1.6
/// (Mobile Feature Matrix).
class LiveStatisticsStrip extends ConsumerWidget {
  const LiveStatisticsStrip({this.paneId, super.key});

  /// Identifies the owning pane when the strip is rendered inside a pane's
  /// subtree. When non-null the per-pane segments (paint time, render time,
  /// FPS, sparkline) are sourced from THIS pane's slot in
  /// [paneRenderStatsProvider] via [PaneContainerManager.containerFor],
  /// not the workspace-wide active pane. So pane A's strip shows pane A's
  /// canvas stats and pane B's strip shows pane B's canvas stats —
  /// independent and simultaneous. When null (empty-canvas state, tests),
  /// falls back to the workspace's [activePaneIdProvider].
  final PaneId? paneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);

    // Read the disclosure state HERE, not down in [_StripSegments]: that
    // subtree runs inside the *pane's* provider container, whose parent chain
    // reaches the root rather than this tab, so a read from in there would
    // resolve some other tab's panel layout. The callback closes over this
    // ref for the same reason.
    final expanded = ref.watch(
      panelLayoutProvider.select((s) => s.statisticsStripVisible),
    );
    void toggle() =>
        ref.read(panelLayoutProvider.notifier).toggleStatisticsStrip();

    // Collapsed: return before watching anything else. The strip is mounted
    // for the whole desktop session now, and the readings below are live
    // subscriptions — memory polls on a timer, render stats tick every
    // painted frame. Watching them behind a row nobody has opened would burn
    // both for a widget that is 24 px of caption.
    // No labelled container around the strip: the disclosure control carries
    // the one name, and a container label on top of it was announced as a
    // third ("Statistics / Stats. Show Statistics").
    if (!expanded) {
      return CruxStatsStrip(
        label: l10n.statsStripLabel,
        semanticLabel: l10n.statisticsStripTitle,
        expandTooltip: l10n.statsStripExpandTooltip,
        collapseTooltip: l10n.statsStripCollapseTooltip,
        expanded: false,
        onToggle: toggle,
        segments: const <CruxStatSegment>[],
      );
    }

    final waveform = ref.watch(memoryStatsProvider);
    final process = ref.watch(cruxMemoryStatsProvider);
    final frame = ref.watch(cruxFrameStatsProvider);
    final activePaneId = ref.watch(activePaneIdProvider);
    // Per-pane scoping: prefer the explicit paneId passed by the host
    // widget, fall back to the workspace's active pane.
    final scopedPaneId = paneId ?? activePaneId;
    final workspace = ref.watch(workspaceProvider).value;
    final paneCount = workspace?.panes.length ?? 1;
    final paneIndex = workspace == null
        ? 0
        : workspace.panes.indexWhere((p) => p.id == scopedPaneId).clamp(0, 1);
    final paneIndicator = _panesIndicatorFor(paneCount, paneIndex);

    final readings = _AppLevelReadings(
      memory: process.hasSample
          ? cruxFormatBytes(process.residentBytes)
          // Before the first 2 s sample lands, WaveCrux's own collector
          // already knows the RSS — showing a dash for two seconds beside a
          // number the app has would look broken.
          : waveform == null || waveform.dartProcessRssBytes == 0
          ? '—'
          : cruxFormatBytes(waveform.dartProcessRssBytes),
      memoryHistory: process.recentResidentBytes,
      fps: frame.sampledFrames == 0
          ? '—'
          : frame.framesPerSecond.toStringAsFixed(1),
      fpsHistory: frame.recentFrameMillis,
      dropped: '${frame.budgetOverruns}',
      // Same 5% threshold the other products flag at.
      droppedEmphasis: frame.overrunRatio > 0.05
          ? CruxStatEmphasis.warning
          : CruxStatEmphasis.normal,
      wellen: waveform == null || waveform.wellenEstimateBytes == 0
          ? '—'
          : cruxFormatBytes(waveform.wellenEstimateBytes),
      signals:
          '${waveform?.loadedSignalCount ?? 0} / '
          '${waveform?.totalSignalCount ?? 0}',
    );

    return _MemoryPollDemand(
      child: _PerPaneSegmentsHost(
        activePaneId: scopedPaneId,
        paneIndicator: paneIndicator,
        onToggle: toggle,
        readings: readings,
      ),
    );
  }

  static String? _panesIndicatorFor(int paneCount, int paneIndex) {
    if (paneCount < 2) return null;
    final i = paneIndex.clamp(0, _kPaneIndicators.length - 1);
    return _kPaneIndicators[i];
  }
}

/// The strip's app-level readings, already formatted.
///
/// Bundled rather than passed as eight positional strings: they are read
/// once at the top of the strip, where the tab's provider scope is in
/// reach, and carried down through the pane scope unchanged.
@immutable
class _AppLevelReadings {
  const _AppLevelReadings({
    required this.memory,
    required this.memoryHistory,
    required this.fps,
    required this.fpsHistory,
    required this.dropped,
    required this.droppedEmphasis,
    required this.wellen,
    required this.signals,
  });

  final String memory;
  final List<double> memoryHistory;
  final String fps;
  final List<double> fpsHistory;
  final String dropped;
  final CruxStatEmphasis droppedEmphasis;
  final String wellen;
  final String signals;
}

/// Holds a [cruxMemoryPollRequestProvider] tag for as long as it is mounted.
///
/// The shared RSS collector only samples while something says it is being
/// watched, and it takes that cue from [cruxStatsStripExpandedProvider] —
/// which WaveCrux does not use, because its disclosure state is per tab and
/// persisted. The tag API is the collector's own answer for exactly this: a
/// surface that wants samples says so while it is open. Mounted only inside
/// the expanded branch, so its lifetime *is* the demand — no flag to keep in
/// sync with the strip's own.
class _MemoryPollDemand extends ConsumerStatefulWidget {
  const _MemoryPollDemand({required this.child});

  static const String _tag = 'wavecrux-statistics-strip';

  final Widget child;

  @override
  ConsumerState<_MemoryPollDemand> createState() => _MemoryPollDemandState();
}

class _MemoryPollDemandState extends ConsumerState<_MemoryPollDemand> {
  /// The notifier the tag was taken on, held so [dispose] can give it back.
  ///
  /// `ref` is not usable once the element is being torn down, and reaching
  /// for it there left the tag held and the collector's 2 s timer running
  /// for the rest of the session — which a widget test reports, correctly,
  /// as a pending timer after the tree was disposed.
  CruxMemoryPollRequestNotifier? _requests;

  @override
  void initState() {
    super.initState();
    // Post-frame: requesting mid-build would mutate a provider while the
    // tree that reads it is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final requests = ref.read(cruxMemoryPollRequestProvider.notifier);
      _requests = requests;
      requests.request(_MemoryPollDemand._tag);
    });
  }

  @override
  void dispose() {
    try {
      _requests?.release(_MemoryPollDemand._tag);
    } on Object {
      // The container went first (test teardown, app shutdown); its own
      // onDispose already stopped the poll, so there is nothing to release.
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Wraps the per-pane portion of the strip in the active pane's
/// [UncontrolledProviderScope] so [paneRenderStatsProvider] resolves
/// to *that pane's* notifier (and its rolling sparkline buffer).
///
/// The app-level readings are passed in already formatted — they were read
/// above this scope, so pane focus changes cannot swap them.
class _PerPaneSegmentsHost extends ConsumerWidget {
  const _PerPaneSegmentsHost({
    required this.activePaneId,
    required this.paneIndicator,
    required this.onToggle,
    required this.readings,
  });

  final PaneId activePaneId;
  final String? paneIndicator;
  final VoidCallback onToggle;
  final _AppLevelReadings readings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve the host pane's container so its [paneRenderStatsProvider]
    // override is in scope. When the workspace has not yet hydrated or there
    // is no PaneContainerManager registered (pure unit tests / open-core boot
    // edge cases) we fall back to reading the root-scope notifier — its
    // sparkline buffer is still a valid (empty/default) source.
    PaneContainerManager? pcm;
    try {
      pcm = ref.read(paneContainerManagerProvider);
    } on Object {
      pcm = null;
    }

    final paneContainer = pcm?.containerFor(activePaneId);
    final segments = _StripSegments(
      paneIndicator: paneIndicator,
      onToggle: onToggle,
      readings: readings,
    );

    if (paneContainer == null) return segments;
    return UncontrolledProviderScope(
      container: paneContainer,
      child: segments,
    );
  }
}

class _StripSegments extends ConsumerWidget {
  const _StripSegments({
    required this.paneIndicator,
    required this.onToggle,
    required this.readings,
  });

  final String? paneIndicator;
  final VoidCallback onToggle;
  final _AppLevelReadings readings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final paneStats = ref.watch(paneRenderStatsProvider);
    final latest = paneStats.latest;

    final paintMsStr = _formatPaintMs(latest?.totalPaintTimeUs);
    final renderMsStr = _formatRenderMs(latest);
    final history = paneStats.paintTimesMs;

    return CruxStatsStrip(
      label: l10n.statsStripLabel,
      semanticLabel: l10n.statisticsStripTitle,
      expandTooltip: l10n.statsStripExpandTooltip,
      collapseTooltip: l10n.statsStripCollapseTooltip,
      // This subtree only builds while the strip is open — the collapsed
      // case returns early up in [LiveStatisticsStrip].
      expanded: true,
      onToggle: onToggle,
      segments: <CruxStatSegment>[
        // Memory, FPS, Dropped, then the product's own readings — the
        // segment order every product in the suite uses.
        CruxStatSegment(
          label: l10n.statsSegmentMemory,
          value: readings.memory,
          sparkline: readings.memoryHistory,
          tooltip: l10n.statsSegmentMemoryTooltip,
        ),
        CruxStatSegment(
          label: l10n.statsSegmentFps,
          value: readings.fps,
          sparkline: readings.fpsHistory,
          tooltip: l10n.statsSegmentFpsTooltip,
        ),
        CruxStatSegment(
          label: l10n.statsSegmentDropped,
          value: readings.dropped,
          emphasis: readings.droppedEmphasis,
          tooltip: l10n.statsSegmentDroppedTooltip,
        ),
        CruxStatSegment(
          label: _withIndicator(paneIndicator, l10n.statsSegmentPaint),
          value: paintMsStr,
          sparkline: history,
          tooltip: l10n.statsSegmentPaintTooltip,
        ),
        CruxStatSegment(
          label: _withIndicator(paneIndicator, l10n.statsSegmentRender),
          value: renderMsStr,
          tooltip: l10n.statsSegmentRenderTooltip,
        ),
        CruxStatSegment(
          label: l10n.statsSegmentWellenDb,
          value: readings.wellen,
          tooltip: l10n.statsSegmentWellenDbTooltip,
        ),
        CruxStatSegment(
          label: l10n.statsSegmentSignals,
          value: readings.signals,
          tooltip: l10n.statsSegmentSignalsTooltip,
        ),
      ],
    );
  }

  /// Prefixes per-pane segment captions with the pane indicator (e.g. "L: ")
  /// when split-pane is active. Returns the raw label unchanged when
  /// [indicator] is null (single-pane).
  static String _withIndicator(String? indicator, String label) {
    if (indicator == null) return label;
    return '$indicator: $label';
  }

  static String _formatPaintMs(int? totalPaintTimeUs) {
    if (totalPaintTimeUs == null) return '—';
    return '${(totalPaintTimeUs / 1000.0).toStringAsFixed(1)} ms';
  }

  static String _formatRenderMs(RenderPipelineStats? stats) {
    if (stats == null) return '—';
    final us =
        stats.scalarPaintTimeUs +
        stats.vectorPaintTimeUs +
        stats.analogPaintTimeUs;
    return '${(us / 1000.0).toStringAsFixed(1)} ms';
  }
}
