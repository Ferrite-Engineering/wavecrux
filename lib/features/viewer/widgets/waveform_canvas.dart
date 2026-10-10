// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:crux_async/crux_async.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/core/theme/wavecrux_theme_accessors.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/annotations/providers/annotation_authoring_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/annotations/widgets/annotation_overlay.dart';
import 'package:wavecrux/features/comparison/constants/diff_constants.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/decoders/constants/transaction_lane_constants.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/diagnostics/providers/render_pipeline_stats_provider.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/lane_geometry_provider.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/providers/selected_transaction_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_load_progress_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/translate_filter_provider.dart';
import 'package:wavecrux/features/viewer/providers/translator_expansion_provider.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_data_revision_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/providers/x_trace_provider.dart';
import 'package:wavecrux/features/viewer/rendering/lane_geometry_index.dart';
import 'package:wavecrux/features/viewer/rendering/signal_load_planner.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_canvas_render_object.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_lane_data.dart';
import 'package:wavecrux/features/viewer/widgets/collaborator_cursor_overlay.dart';
import 'package:wavecrux/features/viewer/widgets/cursor_overlay.dart';
import 'package:wavecrux/features/viewer/widgets/inline_cursor_value_overlay.dart';
import 'package:wavecrux/features/viewer/widgets/shared_marker_overlay.dart';
import 'package:wavecrux/features/viewer/widgets/shared_pointer_overlay.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_gesture_handler.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_scroll_modifier_interceptor.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';
import 'package:wavecrux/services/translate/translate_filter_service.dart';
import 'package:wavecrux/services/value_format/analog_value_extractor.dart';
import 'package:wavecrux/services/waveform/display_changes.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/shared/widgets/trackpad_scroll_listener.dart';

// ── long-press context menu actions ───────────────────────────────────────────

enum _WaveformContextAction {
  placePrimary,
  placeSecondary,
  clearCursors,
  fitAll,
  addAnnotation,
  addRange,
  addRangeOnLane,
}

// ── lane height constants ─────────────────────────────────────────────────────

// Per-row signal/group/separator/comment heights are owned by [LaneGeometry]
// (lane_geometry.dart) and resolved into a [LaneMetrics] shared by all three
// per-row columns, so they cannot diverge.
//
// transactionLaneHeight imported from transaction_lane_constants.dart, and
// diffXorLaneHeight from diff_constants.dart — both shared with sibling panels
// so the three synchronized columns maintain identical scroll extents.

/// The main waveform canvas panel.
///
/// Reads signal groups, zoom/pan state, cursor positions, and the waveform
/// data source from Riverpod providers. Manages async signal loading and
/// pre-fetches visible [SignalChange] data before each paint.
///
/// Also watches [activeDecodersProvider] and appends one transaction
/// overlay lane per active decoder at the bottom of the lane stack.  Tapping
/// a transaction block jumps the primary cursor to the transaction's
/// [DecodedTransaction.startTime] and updates [selectedTransactionProvider].
///
/// All pointer and gesture handling is delegated to [WaveformGestureHandler].
///
/// Wraps [WaveformCanvasView] (a [LeafRenderObjectWidget]) inside a
/// [SingleChildScrollView] for vertical scrolling when lanes overflow the
/// panel height.
///
/// When [externalScrollController] is provided (e.g. by [WaveformViewCenter]
/// for scroll-sync with [SignalListPanel]) it is used instead of an internal
/// controller. The caller owns that controller's lifecycle.
class WaveformCanvas extends ConsumerStatefulWidget {
  const WaveformCanvas({this.externalScrollController, super.key});

  /// Stable key used by integration tests to locate the canvas widget.
  ///
  /// Tests that need to perform tap / gesture assertions on the waveform
  /// area use `find.byKey(WaveformCanvas.waveformCanvasKey)` rather than
  /// relying on widget-type finders, which could match multiple widgets.
  static const Key waveformCanvasKey = Key('waveform_canvas');

  /// Optional external scroll controller for vertical sync with a sibling panel.
  final ScrollController? externalScrollController;

  /// Test-only hook invoked with the freshly built lane list on each rebuild,
  /// so the lane-alignment-invariant test can assert the canvas's per-row
  /// geometry matches the shared [LaneGeometry] model. Always null in
  /// production (only ever assigned from tests).
  @visibleForTesting
  static void Function(List<WaveformLaneData> lanes)? debugOnLanesBuilt;

  /// At or below this many lanes, materialize the full lane list (the
  /// pre-gating behavior — exact for every normally-sized file and for the
  /// existing widget/golden tests). Above it, materialize only the viewport
  /// window: constructing rich [WaveformLaneData] for a million-entry
  /// gate-level add costs seconds per pass on slow targets (a 17 s frozen
  /// frame on web/DDC in the beta recording), while the geometry pass over
  /// the same entries is typed-array work and stays cheap.
  @visibleForTesting
  static const int fullMaterializeThreshold = 20000;

  @override
  ConsumerState<WaveformCanvas> createState() => _WaveformCanvasState();
}

class _WaveformCanvasState extends ConsumerState<WaveformCanvas> {
  // ── async data cache ────────────────────────────────────────────────────────

  final Map<String, List<SignalChange>> _changesCache = {};
  final Map<String, String?> _initialValueCache = {};

  // ── bulk-load tuning ────────────────────────────────────────────────────────
  //
  // The canvas loads (decompresses) signal data lazily and now does so
  // *viewport-first*: only the lanes within the visible window (plus an
  // over-scan margin) are loaded, the rest stream in as the user scrolls.
  // This keeps the decompressed working set — and therefore peak memory and
  // time-to-first-pixel — bounded regardless of how many signals were added.

  /// How many extra *viewport heights* above and below the visible window are
  /// eagerly loaded, so the user can scroll a couple of screens in either
  /// direction over already-decompressed (already-painted) lanes before the
  /// gate has to fetch more. The dominant knob for scroll smoothness on wide
  /// files: bigger = smoother scroll, more retained memory. The retention
  /// budget ([SignalLoadPlanner.budgetFor]) scales with the resulting visible
  /// count, so a larger margin is not evicted out from under itself.
  static const double _kOverscanScreens = 2.5;

  /// Lower bound on the over-scan margin (px) for very short windows, so even a
  /// tiny pane keeps a usable band of lanes loaded above/below.
  static const double _kMinOverscanPx = 900;

  /// Assumed viewport height (px) for the very first refresh, before layout has
  /// reported the real height — bounds the initial "Add All" load to roughly a
  /// screenful rather than every signal.
  static const double _kInitialViewportHeight = 900;

  /// Number of concurrent in-flight [WaveformDataSource.loadSignal] calls. The
  /// worker isolate decompresses serially, but pipelining removes the
  /// per-request round-trip gap. Kept small so the UI isolate stays responsive.
  static const int _kLoadConcurrency = 6;

  /// Repaint after this many newly-loaded signals so lanes fill in
  /// progressively (incremental paint) instead of all at once at the end.
  static const int _kIncrementalPaintBatch = 12;

  /// Surface the progress indicator at once for a load of at least this many
  /// signals. Below it the indicator waits for [_kProgressDelay], because a
  /// handful of signals usually load fast enough that a flashing bar is noise.
  static const int _kProgressThreshold = 24;

  /// How long a load below [_kProgressThreshold] may run before the indicator
  /// appears anyway. Signal count is a poor proxy for work: a few signals with
  /// millions of transitions each can take seconds to decompress. A load that
  /// finishes inside this never shows the indicator, so fast ones do not flash.
  static const Duration _kProgressDelay = Duration(milliseconds: 200);

  /// Floor on how many loaded signals are retained before LRU eviction kicks
  /// in; below this the unload churn isn't worth it.
  static const int _kMinLoadedBudget = 256;

  /// Bumped whenever [_doRefresh] starts, so an older in-flight refresh whose
  /// generation no longer matches stops touching widget state (supersede +
  /// cancel).
  int _refreshGeneration = 0;

  /// The pending [_kProgressDelay] trigger for the loads in flight, if any.
  ///
  /// It spans refreshes: a newer refresh re-requests the loads a superseded
  /// one left in flight, so the delay counts from when loading started, not
  /// from the latest refresh — otherwise refreshes landing inside the delay
  /// would keep a multi-second load from ever showing the indicator.
  Timer? _slowLoadTimer;

  /// Shows the indicator for the newest refresh's batch; returns false when
  /// that refresh has been superseded. Set by each refresh the timer covers.
  bool Function()? _showSlowLoad;

  /// The delay ran out while no current refresh could take the indicator (a
  /// newer one was scheduled but not yet started), so the next refresh with
  /// loads to do shows it at once.
  bool _slowLoadOverdue = false;

  /// The generation of the last refresh that ran to completion while current.
  int _completedGeneration = 0;

  /// Most-recently-visible-last ordering of signals the canvas has loaded, used
  /// for LRU eviction of off-screen signals once the loaded set exceeds budget.
  final List<String> _lruOrder = <String>[];

  /// Trailing half of [_throttledRefresh]: one viewport-gated load 120 ms
  /// after scrolling settles, so newly-revealed lanes load without thrashing
  /// on every pixel.
  final _scrollLoadSettle = Debouncer(
    duration: const Duration(milliseconds: 120),
  );

  /// Minimum gap between load-ahead refreshes fired *during* a continuous
  /// scroll (throttle), so a long drag keeps fetching ahead instead of waiting
  /// for the trailing debounce.
  static const Duration _kScrollLoadThrottle = Duration(milliseconds: 150);

  /// When the last scroll-driven load ran, for the throttle above. Read from
  /// `package:clock`, so a test on fake time drives the throttle too.
  DateTime _lastScrollLoad = DateTime.fromMillisecondsSinceEpoch(0);

  // ── horizontal cache band ───────────────────────────────────────────────────
  //
  // The change caches cover the visible time range plus [_kHorizontalBand]
  // viewport widths either side, reduced to the zoom's pixel columns
  // (`changesForDisplay`). A pan that stays inside the band repaints from the
  // caches with no data work at all; leaving it, or zooming, refreshes through
  // the same throttle + trailing debounce the vertical scroll uses. Before
  // this, every pan or zoom frame re-read every loaded lane's changes in the
  // visible range as objects — at fit-all, every change in the trace.

  /// Viewport widths of time cached either side of the visible range.
  ///
  /// Half a view: pans of up to half a screen repaint for free, and a
  /// refresh at medium zoom — where columns hold only a few changes each, so
  /// reducing them saves little — reads two views' worth rather than three.
  /// Measured with `test/benchmarks/ui_thread_blocking_benchmark.dart`.
  static const double _kHorizontalBand = 0.5;

  /// Time range and zoom the change caches were built for; null until the
  /// first refresh lands.
  int? _cacheStart;
  int? _cacheEnd;
  double? _cacheTicksPerPixel;

  // ── X-origin signal refs (memoized) ────────────────────────────────────────
  //
  // Resolving the X-trace's involved signal paths back to signalRefs scans the
  // whole variables map, which on a gate-level dump is over a million entries.
  // The canvas rebuilds for every zoom, pan, signal edit and theme change, so
  // recomputing it in build() puts a full-hierarchy scan on the critical path
  // while an X-trace is active. Both inputs are immutable, so identity of the
  // trace state and of the map is a sufficient cache key.

  XTraceState? _xOriginRefsTrace;
  Map<String, Variable>? _xOriginRefsVariables;
  Set<String> _xOriginRefsCache = const {};

  /// The signalRefs whose variables appear in [xTrace]'s involved signal
  /// paths, recomputed only when the trace or the hierarchy changes.
  Set<String> _xOriginSignalRefs(
    XTraceState xTrace,
    Map<String, Variable> variablesMap,
  ) {
    if (!xTrace.isActive) return const <String>{};
    if (identical(xTrace, _xOriginRefsTrace) &&
        identical(variablesMap, _xOriginRefsVariables)) {
      return _xOriginRefsCache;
    }
    final refs = <String>{
      for (final entry in variablesMap.entries)
        if (xTrace.involvedSignalPaths.contains(entry.value.fullPath))
          entry.key,
    };
    _xOriginRefsTrace = xTrace;
    _xOriginRefsVariables = variablesMap;
    _xOriginRefsCache = refs;
    return refs;
  }

  // ── layout tracking ─────────────────────────────────────────────────────────

  double _viewportWidth = 1000;

  // ── viewport vertical range (for lane culling) ─────────────────────────────
  //
  // Tracked by listening to the vertical scroll controller and combining with
  // the layout height. Passed to [WaveformCanvasView] so the render object
  // skips lanes outside the visible region — the dominant optimization for
  // large signal counts.

  double? _viewportTop;
  double? _viewportBottom;
  double _viewportHeight = 0;

  /// The arrow being drawn by an in-flight Alt-drag, if any.
  String? _arrowInFlight;

  // ── last built lanes (for tap hit-testing) ──────────────────────────────────
  //
  // With viewport-gated materialization these are the *visible-window* lanes
  // only. Hit-testing is inherently viewport-local (the user can only tap
  // what is on screen), so visible lanes are sufficient.

  List<WaveformLaneData> _lastLanes = const [];

  /// Compact geometry of ALL lanes — the coordinate system for the load
  /// planner, the scroll extent, and the materialization window.
  LaneGeometryIndex _lastGeometry = LaneGeometryIndex.empty;

  /// Token of the most recently handled cross-probe reveal request. Guards the
  /// dedupe in [_maybeReveal] so the same request is not re-revealed on an
  /// unrelated rebuild, while a genuinely new request (token bumped) — including
  /// one already present when this canvas first mounts on a freshly-opened tab —
  /// still fires exactly once.
  int? _handledRevealToken;

  // ── geometry memoization ────────────────────────────────────────────────────
  //
  // Building the geometry index is O(signal count) but allocation-light. It
  // depends only on the lane *structure* inputs below — NOT on the vertical
  // scroll offset, the change caches, or per-signal display metadata (those
  // affect only the O(visible) materialization, which runs fresh every
  // build). Inputs are compared by identity because the providers return the
  // same instance when unchanged.

  LaneGeometryIndex? _memoGeometry;
  SignalGroup? _memoSignalGroup;
  DiffState? _memoDiff;
  List<ActiveDecoder>? _memoDecoders;
  Map<String, int>? _memoChildRowCounts;
  double _memoMinLaneHeight = -1;

  // ── scroll ──────────────────────────────────────────────────────────────────

  ScrollController? _ownedScroll;

  ScrollController get _verticalScroll =>
      widget.externalScrollController ?? _ownedScroll!;

  // ── lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (widget.externalScrollController == null) {
      _ownedScroll = ScrollController();
    }
    _verticalScroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleRefresh();
      // Canvas may mount after file is already loaded (loading overlay hides it
      // during load, so ref.listen never fires with the initial loaded value).
      if (mounted) {
        final source = ref.read(waveformSourceProvider).value;
        if (source != null) {
          ref
              .read(timeMapperProvider.notifier)
              .initialize(
                startTime: source.startTime,
                endTime: source.endTime,
                viewportWidth: _viewportWidth,
              );
        }
      }
    });
  }

  @override
  void didUpdateWidget(WaveformCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.externalScrollController != widget.externalScrollController) {
      oldWidget.externalScrollController?.removeListener(_onScroll);
      _ownedScroll?.removeListener(_onScroll);
      _verticalScroll.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _slowLoadTimer?.cancel();
    _scrollLoadSettle.dispose();
    _verticalScroll.removeListener(_onScroll);
    _ownedScroll?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !_verticalScroll.hasClients || _viewportHeight <= 0) {
      return;
    }
    final offset = _verticalScroll.offset;
    final newTop = offset;
    final newBottom = offset + _viewportHeight;
    if (newTop != _viewportTop || newBottom != _viewportBottom) {
      setState(() {
        _viewportTop = newTop;
        _viewportBottom = newBottom;
      });
      // Throttle + trailing-debounce the scroll-load so newly-revealed lanes
      // start decompressing *while* a continuous drag is still moving (a pure
      // trailing debounce would never fire until the user pauses, so a long
      // drag outruns the loaded band). The throttle fires a load-ahead at most
      // every [_kScrollLoadThrottle], and the trailing timer catches the final
      // resting position. The large over-scan band means these loads land
      // off-screen, so the visible area stays painted while they run.
      _throttledRefresh();
    }
  }

  /// Refreshes at most once per [_kScrollLoadThrottle] while the viewport
  /// keeps moving, plus once 120 ms after it stops. Shared by vertical scroll
  /// and horizontal pan/zoom, which both only need the caches to catch up
  /// with where the viewport ended up.
  void _throttledRefresh() {
    final now = clock.now();
    if (now.difference(_lastScrollLoad) >= _kScrollLoadThrottle) {
      _lastScrollLoad = now;
      _scheduleRefresh();
    }
    _scrollLoadSettle.run(() {
      if (!mounted) return;
      _lastScrollLoad = clock.now();
      _scheduleRefresh();
    });
  }

  /// Empties the change caches and forgets the band they covered, so the
  /// next pan cannot mistake an empty cache for a covering one.
  void _clearChangeCaches() {
    _changesCache.clear();
    _initialValueCache.clear();
    _cacheStart = null;
    _cacheEnd = null;
    _cacheTicksPerPixel = null;
  }

  /// Whether the change caches already hold what [mapper] shows: built at
  /// its zoom, over a range containing its visible one.
  bool _cachesCover(TimeMapper mapper) {
    final start = _cacheStart;
    final end = _cacheEnd;
    return start != null &&
        end != null &&
        _cacheTicksPerPixel == mapper.ticksPerPixel &&
        mapper.visibleStartTime >= start &&
        mapper.visibleEndTime <= end;
  }

  /// A pan or zoom. Inside the cached band it only repaints (the build that
  /// delivered this already did); otherwise the caches are refreshed.
  void _onHorizontalViewChanged() {
    if (_cachesCover(ref.read(timeMapperProvider))) return;
    _throttledRefresh();
  }

  // ── data refresh ────────────────────────────────────────────────────────────

  /// Schedules a viewport-gated data refresh, superseding any in-flight one.
  ///
  /// Deferred to the post-frame so the refresh reads *fresh* lane geometry: the
  /// providers that trigger a refresh (signal add/remove, zoom) rebuild the
  /// canvas, and [_visibleSignalRefs] depends on the rebuilt [_lastGeometry]. If
  /// we ran synchronously here the geometry would still reflect the previous
  /// signal group and a freshly "Add All"-ed scope would be computed as not
  /// visible — and never load.
  ///
  /// The frame is requested, not assumed: a refresh scheduled from a timer
  /// (the trailing edge of [_throttledRefresh]) arrives when nothing else is
  /// drawing, and a bare post-frame callback would then wait for whatever
  /// input next schedules one.
  void _scheduleRefresh() {
    final gen = ++_refreshGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh(gen));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Whether [gen] is still the active refresh. A newer [_scheduleRefresh]
  /// (signal add/remove, zoom, file change, scroll) or a user cancel bumps
  /// [_refreshGeneration], so an in-flight refresh bails at its next checkpoint
  /// rather than fighting the newer one for widget state.
  bool _isCurrent(int gen) => mounted && gen == _refreshGeneration;

  Future<void> _refresh(int gen) async {
    if (!_isCurrent(gen)) return;
    final source = ref.read(waveformSourceProvider).value;
    if (source == null) {
      _lruOrder.clear();
      setState(_clearChangeCaches);
      return;
    }

    final mapper = ref.read(timeMapperProvider);
    final window = _cacheWindowFor(mapper, source);

    // Viewport-gating: only lanes in (or near) the visible window are loaded;
    // the rest stream in on scroll. Keeps the decompressed working set — and so
    // peak memory and time-to-first-pixel — bounded regardless of scope width.
    // Derived from the geometry index (built by the frame this refresh was
    // scheduled behind), so no O(all-entries) flatten runs here — this method
    // fires on every scroll throttle tick.
    final visibleEntries = _visibleSignalEntries();
    final variablesMap = ref.read(signalVariablesMapProvider);
    final visibleRefs = <String>[];
    final seenRefs = <String>{};
    // Refs drawn as an analog curve in at least one lane: their cache also
    // keeps each column's min and max, which the curve needs to show a spike.
    final magnitudes = <String, AnalogValueExtractor>{};
    for (final entry in visibleEntries) {
      final r = entry.signalRef!;
      if (!magnitudes.containsKey(r)) {
        final m = _analogMagnitudeFor(entry, variablesMap[r]);
        if (m != null) magnitudes[r] = m;
      }
      if (seenRefs.add(r)) visibleRefs.add(r);
    }
    for (final r in visibleRefs) {
      _lruOrder
        ..remove(r)
        ..add(r);
    }

    final toLoad = visibleRefs.where((r) => !source.isSignalLoaded(r)).toList();

    final progress = ref.read(signalLoadProgressProvider.notifier);
    // Shown at once for a big batch, or when "Add All in Scope" is holding its
    // adding-phase indicator for exactly this hand-off (entries built, waiting
    // on the frame that brings this refresh). Otherwise only once the batch
    // has run past _kProgressDelay.
    final handOff = _isAddingHold(ref.read(signalLoadProgressProvider));
    var showProgress =
        toLoad.isNotEmpty && (toLoad.length >= _kProgressThreshold || handOff);
    if (toLoad.isNotEmpty && _slowLoadOverdue) showProgress = true;
    var loadedCount = 0;
    if (showProgress) progress.begin(toLoad.length);
    if (showProgress || toLoad.isEmpty) {
      _cancelSlowLoadTimer();
    } else {
      _showSlowLoad = () {
        if (!_isCurrent(gen)) return false;
        // An "Add All in Scope" still building its entries owns the
        // indicator; its own hand-off brings the next refresh in.
        final current = ref.read(signalLoadProgressProvider);
        if (current.active &&
            current.phase == SignalLoadPhase.adding &&
            !_isAddingHold(current)) {
          return true;
        }
        showProgress = true;
        progress
          ..begin(toLoad.length)
          ..setLoaded(loadedCount);
        return true;
      };
      _slowLoadTimer ??= Timer(_kProgressDelay, _onSlowLoad);
    }

    // Bounded-concurrency pipeline of loadSignal calls. The worker isolate
    // decompresses serially, but pipelining removes the per-request round-trip
    // gap; lanes repaint incrementally every _kIncrementalPaintBatch signals.
    var nextIndex = 0;
    var loadedSincePaint = 0;
    Future<void> worker() async {
      while (true) {
        if (!_isCurrent(gen)) return;
        if (ref.read(signalLoadProgressProvider).cancelRequested) return;
        final i = nextIndex++;
        if (i >= toLoad.length) return;
        try {
          await source.loadSignal(toLoad[i]);
        } on Object {
          // Skip a ref that can't be resolved (legacy session entry with no
          // signalPath) — keep loading the rest rather than aborting the frame.
        }
        // Web only: let a frame actually render between decompressions.
        // The WASM backend decompresses ON the main thread inside a
        // synchronous JS call, and awaiting its wrapper future only hops
        // microtasks — the browser never got a paint opportunity, so the
        // loading indicator and incremental repaints stayed invisible for
        // the whole batch (the "static screen then everything at once"
        // symptom in the beta recording). endOfFrame schedules and waits
        // out one real frame per load. Desktop/mobile skip this: their
        // decompression runs on a background isolate, the UI thread is
        // already free, and serializing loads against vsync would only
        // slow the pipeline.
        if (kIsWeb) await WidgetsBinding.instance.endOfFrame;
        if (!_isCurrent(gen)) return;
        loadedCount++;
        if (showProgress) progress.advance();
        if (++loadedSincePaint >= _kIncrementalPaintBatch) {
          loadedSincePaint = 0;
          _rebuildVisibleCaches(gen, source, visibleRefs, window, magnitudes);
        }
      }
    }

    await Future.wait(<Future<void>>[
      for (var w = 0; w < _kLoadConcurrency; w++) worker(),
    ]);

    if (showProgress) progress.finishPhase(SignalLoadPhase.loading);
    if (_isCurrent(gen)) {
      _cancelSlowLoadTimer();
      _slowLoadOverdue = false;
      _completedGeneration = gen;
    } else if (showProgress && _completedGeneration != _refreshGeneration) {
      // Superseded with the indicator up. The newer refresh carries on with
      // the same loads, so it takes the indicator over now rather than
      // leaving a gap for a fresh delay.
      _slowLoadTimer?.cancel();
      _slowLoadTimer = null;
      final show = _showSlowLoad;
      _showSlowLoad = null;
      if (show == null || !show()) _slowLoadOverdue = true;
    }
    if (!_isCurrent(gen)) return;

    // Final paint with everything that loaded, then trim the loaded set back
    // toward budget by unloading the least-recently-visible off-screen signals.
    _rebuildVisibleCaches(gen, source, visibleRefs, window, magnitudes);
    _evictBeyondBudget(source, visibleRefs.toSet());

    // The view may have moved while the loads ran. A pan that looked covered
    // against the previous caches may be outside the band just built.
    if (!_cachesCover(ref.read(timeMapperProvider))) _throttledRefresh();

    // Publish that sample data is now readable. Providers that derive values
    // from the source (annotation drift, and anything like it) cannot see this
    // moment any other way: the source is the same instance and the signal
    // list settled before the loads began.
    ref.read(waveformDataRevisionProvider.notifier).bump();
  }

  void _onSlowLoad() {
    _slowLoadTimer = null;
    final show = _showSlowLoad;
    _showSlowLoad = null;
    if (!mounted || show == null) return;
    if (!show()) _slowLoadOverdue = true;
  }

  void _cancelSlowLoadTimer() {
    _slowLoadTimer?.cancel();
    _slowLoadTimer = null;
    _showSlowLoad = null;
  }

  /// Whether [p] is "Add All in Scope" holding its indicator after building
  /// every entry — the moment it waits for a refresh to take the indicator
  /// over. A scope walk (no total yet) or a chunked build still in progress is
  /// not a hold.
  static bool _isAddingHold(SignalLoadProgressState p) =>
      p.active &&
      p.phase == SignalLoadPhase.adding &&
      p.total > 0 &&
      p.loaded >= p.total;

  /// Over-scan margin (px) above and below the viewport: a couple of screen
  /// heights so the user can scroll a few screens over already-loaded lanes
  /// before the gate fetches more. Adapts to window size and never drops below
  /// [_kMinOverscanPx] on a short pane.
  double get _overscanPx {
    final height = _viewportHeight > 0
        ? _viewportHeight
        : _kInitialViewportHeight;
    final scaled = height * _kOverscanScreens;
    return scaled > _kMinOverscanPx ? scaled : _kMinOverscanPx;
  }

  /// Signal entries whose lane intersects the visible vertical window.
  /// Delegates to [SignalLoadPlanner.viewportVisibleEntries] against the last
  /// built geometry index (data-independent, so correct even before any signal
  /// loaded — and covering ALL lanes, not just the materialized window).
  List<SignalEntry> _visibleSignalEntries() =>
      SignalLoadPlanner.viewportVisibleEntries(
        geometry: _lastGeometry,
        viewportTop: _viewportTop,
        viewportBottom: _viewportBottom,
        viewportHeight: _viewportHeight,
        overscanPx: _overscanPx,
        initialViewportHeight: _kInitialViewportHeight,
      );

  /// The time range and column grid the caches are built for under [mapper]:
  /// the visible range plus [_kHorizontalBand] viewport widths either side,
  /// clamped to the trace, in columns of the current zoom aligned to the
  /// viewport's pixel columns.
  static ({int start, int end, double ticksPerPixel, double origin})
  _cacheWindowFor(TimeMapper mapper, WaveformDataSource source) {
    final visibleStart = mapper.visibleStartTime;
    final visibleEnd = mapper.visibleEndTime;
    final band = ((visibleEnd - visibleStart) * _kHorizontalBand).ceil();
    var start = visibleStart - band;
    if (start < source.startTime) start = source.startTime;
    if (start > visibleStart) start = visibleStart;
    var end = visibleEnd + band;
    if (end > source.endTime) end = source.endTime;
    if (end < visibleEnd) end = visibleEnd;
    return (
      start: start,
      end: end,
      ticksPerPixel: mapper.ticksPerPixel,
      origin: mapper.panOffsetTicks,
    );
  }

  /// How an analog lane for [entry] turns a raw value into a number, or null
  /// when the lane is drawn digitally. Mirrors the extractor choice in
  /// [_materializeLanes].
  static AnalogValueExtractor? _analogMagnitudeFor(
    SignalEntry entry,
    Variable? variable,
  ) {
    if (variable?.isReal ?? false) return AnalogValueExtractors.real;
    if (!entry.renderAsAnalog) return null;
    return AnalogValueExtractors.forDigitalLane(
      bitWidth: variable?.bitWidth ?? 1,
      format: entry.format,
      config: entry.translatorConfig,
    );
  }

  /// Rebuilds the per-signal change / initial-value caches for the loaded
  /// members of [refs] over [window], then [setState]s so freshly-loaded lanes
  /// paint. Guarded by [gen] so a superseded refresh never clobbers a newer
  /// one's caches.
  ///
  /// Each lane's changes come back reduced to the zoom's pixel columns
  /// (`changesForDisplay`): a column keeps the few changes it needs to look
  /// right — a sub-pixel pulse included — however many it holds, so a lane
  /// costs O(columns) rather than O(transitions in range). [magnitudes] names
  /// the refs drawn as analog curves, whose columns also keep their min and
  /// max.
  void _rebuildVisibleCaches(
    int gen,
    WaveformDataSource source,
    List<String> refs,
    ({int start, int end, double ticksPerPixel, double origin}) window,
    Map<String, AnalogValueExtractor> magnitudes,
  ) {
    if (!_isCurrent(gen)) return;
    final newChanges = <String, List<SignalChange>>{};
    final newInitial = <String, String?>{};
    for (final r in refs) {
      if (!source.isSignalLoaded(r)) continue;
      // Extend end by 1 tick so a transition exactly at the range's end is
      // included (TimeMapper.fitAll rounding can land visibleEnd one tick
      // short).
      newChanges[r] = source.changesForDisplay(
        r,
        window.start,
        window.end + 1,
        ticksPerColumn: window.ticksPerPixel,
        columnOrigin: window.origin,
        magnitude: magnitudes[r],
      );
      newInitial[r] = source.valueAt(r, window.start);
    }
    setState(() {
      _changesCache
        ..clear()
        ..addAll(newChanges);
      _initialValueCache
        ..clear()
        ..addAll(newInitial);
      _cacheStart = window.start;
      _cacheEnd = window.end;
      _cacheTicksPerPixel = window.ticksPerPixel;
    });
  }

  /// Unloads the least-recently-visible off-screen signals once the loaded set
  /// exceeds budget, keeping the decompressed working set bounded while
  /// scrolling a wide file. Never unloads a currently-[visible] signal.
  void _evictBeyondBudget(WaveformDataSource source, Set<String> visible) {
    final plan = SignalLoadPlanner.evictionPlan(
      lruOrder: _lruOrder,
      isLoaded: source.isSignalLoaded,
      visible: visible,
      budget: SignalLoadPlanner.budgetFor(
        visibleCount: visible.length,
        minBudget: _kMinLoadedBudget,
      ),
    );
    for (final r in plan) {
      unawaited(source.unloadSignal(r));
      _lruOrder.remove(r);
    }
  }

  // ── lane geometry + materialization ────────────────────────────────────────

  /// Builds the compact geometry index for ALL lanes — entry recursion,
  /// XOR-diff lane injection, translator child-row reservations, and
  /// trailing transaction lanes — with typed-array/pointer work only (no
  /// strings, colors, or change lists), so it stays cheap at gate-level
  /// scale. Mirrors exactly the lane order [_materializeLanes] renders.
  ///
  /// The returned [LaneGeometryIndex.bottom] is the true content extent:
  /// child-row reservations advance the running y but add no lane, so it is
  /// NOT recoverable from the lane arrays alone (see issue #43).
  LaneGeometryIndex _buildGeometryIndex(
    List<SignalEntry> entries,
    DiffState diff,
    LaneMetrics metrics,
    Map<String, int> childRowCounts,
    List<ActiveDecoder> decoders,
  ) {
    final tops = <double>[];
    final heights = <double>[];
    final kinds = <int>[];
    final payloads = <Object?>[];
    var y = 0.0;
    var signalLanes = 0;

    void add(WaveformLaneKind kind, Object? payload, double height) {
      tops.add(y);
      heights.add(height);
      kinds.add(kind.index);
      payloads.add(payload);
      y += height;
    }

    void visit(List<SignalEntry> list) {
      for (final entry in list) {
        switch (entry.kind) {
          case SignalEntryKind.signal:
            add(
              WaveformLaneKind.signal,
              entry,
              LaneGeometry.heightForEntry(entry, metrics),
            );
            signalLanes++;
            // Inject an XOR diff lane immediately after a differing signal.
            if (diff.isActive && diff.xorTraces.containsKey(entry.signalRef)) {
              add(WaveformLaneKind.xorDiff, entry, diffXorLaneHeight);
            }
            // Reserve blank space for the signal's expanded translator child
            // rows so the next lane — and every column — stays aligned.
            y += (childRowCounts[entry.id] ?? 0) * metrics.childRowHeight;
          case SignalEntryKind.group:
            add(WaveformLaneKind.group, entry, metrics.groupHeaderHeight);
            if (!entry.collapsed) visit(entry.children);
          case SignalEntryKind.separator:
            add(WaveformLaneKind.separator, entry, metrics.separatorHeight);
          case SignalEntryKind.comment:
            add(WaveformLaneKind.comment, entry, metrics.commentHeight);
        }
      }
    }

    visit(entries);
    for (final decoder in decoders) {
      add(WaveformLaneKind.transaction, decoder, transactionLaneHeight);
    }

    return LaneGeometryIndex(
      tops: Float64List.fromList(tops),
      heights: Float64List.fromList(heights),
      kinds: Uint8List.fromList(kinds),
      payloads: payloads,
      bottom: y,
      signalLaneCount: signalLanes,
    );
  }

  /// Materializes rich [WaveformLaneData] for geometry lanes
  /// `[first, lastExclusive)` — the per-lane map lookups and object
  /// construction the geometry pass deliberately skips. O(materialized):
  /// a screenful at gate-level scale, everything for normal files.
  List<WaveformLaneData> _materializeLanes(
    LaneGeometryIndex geometry,
    int first,
    int lastExclusive,
    Map<String, Variable> variablesMap,
    Map<String, TranslateFilter> filtersMap,
    DiffState diff,
    int visibleStart,
    List<ActiveDecoder> decoders,
    L10N l10n,
  ) {
    final lanes = <WaveformLaneData>[];
    for (var i = first; i < lastExclusive; i++) {
      final y = geometry.tops[i];
      final height = geometry.heights[i];
      switch (geometry.kindAt(i)) {
        case WaveformLaneKind.signal:
          final entry = geometry.payloads[i]! as SignalEntry;
          final signalRef = entry.signalRef!;
          final variable = variablesMap[signalRef];
          final bitWidth = variable?.bitWidth ?? 1;
          final isReal = variable?.isReal ?? false;
          // A digital signal the user asked to see as a curve renders through
          // the same painter; only the value extractor differs. Real signals
          // keep the default extractor — `renderAsAnalog` on one is a no-op.
          final asDigitalAnalog = !isReal && entry.renderAsAnalog;
          final isAnalog = isReal || asDigitalAnalog;
          lanes.add(
            WaveformLaneData(
              kind: WaveformLaneKind.signal,
              y: y,
              height: height,
              signalRef: signalRef,
              rowPath: SignalGroupsNotifier.selectionPathOf(
                entry,
                variablesMap,
              ),
              displayName: entry.displayName ?? signalRef,
              signalColor: entry.argbColor != null
                  ? Color(entry.argbColor!)
                  : WavecruxColors.signalGreen,
              format: entry.format,
              isScalar: bitWidth == 1 && !isAnalog,
              isAnalog: isAnalog,
              analogValueExtractor: asDigitalAnalog
                  ? AnalogValueExtractors.forDigitalLane(
                      bitWidth: bitWidth,
                      format: entry.format,
                      config: entry.translatorConfig,
                    )
                  : null,
              bitWidth: bitWidth,
              changes: _changesCache[signalRef] ?? const [],
              valueAtStart: _initialValueCache[signalRef],
              translateFilter: filtersMap[signalRef],
              translatorConfig: entry.translatorConfig,
            ),
          );
        case WaveformLaneKind.xorDiff:
          final entry = geometry.payloads[i]! as SignalEntry;
          final xorChanges =
              diff.xorTraces[entry.signalRef] ?? const <SignalChange>[];
          lanes.add(
            WaveformLaneData(
              kind: WaveformLaneKind.xorDiff,
              y: y,
              height: height,
              xorChanges: xorChanges,
              xorValueAtStart: _xorValueAt(xorChanges, visibleStart),
              displayName: '⊕',
            ),
          );
        case WaveformLaneKind.group:
          final entry = geometry.payloads[i]! as SignalEntry;
          lanes.add(
            WaveformLaneData(
              kind: WaveformLaneKind.group,
              y: y,
              height: height,
              groupName: entry.groupName,
              displayName: entry.groupName ?? '',
            ),
          );
        case WaveformLaneKind.separator:
          lanes.add(
            WaveformLaneData(
              kind: WaveformLaneKind.separator,
              y: y,
              height: height,
            ),
          );
        case WaveformLaneKind.comment:
          final entry = geometry.payloads[i]! as SignalEntry;
          lanes.add(
            WaveformLaneData(
              kind: WaveformLaneKind.comment,
              y: y,
              height: height,
              commentText: entry.text,
              displayName: entry.text ?? '',
            ),
          );
        case WaveformLaneKind.transaction:
          final decoder = geometry.payloads[i]! as ActiveDecoder;
          final definition = DecoderRegistry.instance.getDefinition(
            decoder.decoderId,
          );
          final baseName = definition?.displayName ?? decoder.decoderId;
          // Lane color follows the decoder's position among active decoders
          // (identity search — the list is tiny).
          var decoderIndex = 0;
          for (var d = 0; d < decoders.length; d++) {
            if (identical(decoders[d], decoder)) {
              decoderIndex = d;
              break;
            }
          }
          lanes.add(
            WaveformLaneData(
              kind: WaveformLaneKind.transaction,
              y: y,
              height: height,
              decoderInstanceId: decoder.id,
              decoderDisplayName: l10n.decoderInstanceLabel(
                baseName,
                decoder.instanceNumber,
              ),
              transactions: decoder.transactions,
              transactionColor: transactionLaneColorForIndex(decoderIndex),
            ),
          );
      }
    }
    return lanes;
  }

  /// Returns the XOR value at [time] via binary search on pre-computed changes.
  static String? _xorValueAt(List<SignalChange> changes, int time) {
    if (changes.isEmpty) return null;
    var lo = 0;
    var hi = changes.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (changes[mid].time <= time) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return changes[lo].time <= time ? changes[lo].value : null;
  }

  // ── cross-probe auto-reveal ─────────────────────────────────────────────────

  /// Brings the signal at [fullPath] into view: expands its containing viewer
  /// group when collapsed, then scrolls the (scroll-synced) lane / name / value
  /// columns so its lane is visible. Driven only by an inbound cross-probe
  /// (see [revealSignalRequestProvider]) — never a manual click.
  ///
  /// Deferred to a post-frame callback so mutating the group-collapse state
  /// does not run inside the `ref.listen` dispatch, and so the scroll reads the
  /// geometry rebuilt after any expansion.
  /// Runs [fn] after the next frame, forcing that frame to be scheduled.
  ///
  /// A reveal arrives via `ref.listen`, which does NOT rebuild this widget, so
  /// nothing otherwise schedules a frame and a bare `addPostFrameCallback`
  /// would sit until some unrelated rebuild happened. `ensureVisualUpdate`
  /// schedules the frame so the reveal always progresses on its own (in
  /// production the paired selection change usually schedules one anyway, but
  /// the reveal must not depend on that coupling — a top-level signal with no
  /// group to expand triggers no other rebuild).
  void _afterNextFrame(VoidCallback fn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) fn();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Applies a reveal request if it is new (its token has not been handled).
  ///
  /// Called from BOTH the `revealSignalRequestProvider` listener AND a one-shot
  /// read in `build`. The build read is the fix for the reverse cross-probe /
  /// fresh-open case: a reveal targeting a just-opened tab is written to that
  /// tab's provider before this canvas has mounted and registered its listener,
  /// so the listener never sees the null→request transition and the reveal was
  /// silently dropped. Reading the current request on mount recovers it; the
  /// per-token dedupe keeps it from re-firing on every later rebuild.
  void _maybeReveal(RevealSignalRequest? request) {
    if (request == null) return;
    if (request.token == _handledRevealToken) return;
    _handledRevealToken = request.token;
    _revealSignal(request.fullPath);
  }

  void _revealSignal(String fullPath, {int attemptsLeft = 8}) {
    _afterNextFrame(() {
      final signalRef = ref
          .read(signalVariablesByPathProvider)[fullPath]
          ?.signalRef;
      if (signalRef == null) {
        // Fresh open (reverse cross-probe): the reveal can land before the
        // just-opened waveform's variables are indexed, so the path does not
        // resolve yet. Retry across a few frames rather than dropping the
        // reveal — the previous single-shot read gave up here permanently.
        if (attemptsLeft > 0) {
          _revealSignal(fullPath, attemptsLeft: attemptsLeft - 1);
        }
        return;
      }
      _expandGroupContaining(signalRef);
      _scrollLaneIntoView(signalRef, attemptsLeft: 6);
    });
  }

  /// Expands the first collapsed top-level viewer group whose children include
  /// the signal [signalRef], so the signal's lane materializes. No-op when the
  /// signal is at the top level or its group is already expanded.
  void _expandGroupContaining(String signalRef) {
    final entries = ref.read(signalGroupsProvider).entries;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.kind != SignalEntryKind.group || !entry.collapsed) continue;
      final holdsSignal = entry.children.any(
        (c) => c.kind == SignalEntryKind.signal && c.signalRef == signalRef,
      );
      if (holdsSignal) {
        ref.read(signalGroupsProvider.notifier).toggleGroupCollapsed(i);
        return;
      }
    }
  }

  /// Scrolls the vertical controller so the lane for [signalRef] sits within
  /// the viewport, centering it when it is currently off-screen. Retries across
  /// a few frames because expanding a group rebuilds the lane geometry on the
  /// following frame ([attemptsLeft] guards against an unresolvable ref).
  void _scrollLaneIntoView(String signalRef, {required int attemptsLeft}) {
    _afterNextFrame(() {
      final geom = _laneGeometryForRef(signalRef);
      if (geom == null || !_verticalScroll.hasClients) {
        // The lane geometry may still be rebuilding after a group expansion —
        // retry a few frames before giving up.
        if (attemptsLeft > 0) {
          _scrollLaneIntoView(signalRef, attemptsLeft: attemptsLeft - 1);
        }
        return;
      }
      final (laneTop, laneHeight) = geom;
      final position = _verticalScroll.position;
      final viewportH = position.viewportDimension;
      final currentTop = position.pixels;
      final currentBottom = currentTop + viewportH;
      // Already fully visible — don't disturb the viewport.
      if (laneTop >= currentTop && laneTop + laneHeight <= currentBottom) {
        return;
      }
      final target = (laneTop - (viewportH - laneHeight) / 2).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _verticalScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// `(top, height)` of the signal lane whose payload signalRef matches
  /// [signalRef] in the last-built full-lane geometry, or null when no such
  /// lane exists (e.g. still inside a collapsed group). Scans all lanes — a
  /// rare per-cross-probe cost, not on any hot path.
  (double, double)? _laneGeometryForRef(String signalRef) {
    final geom = _lastGeometry;
    for (var i = 0; i < geom.length; i++) {
      if (geom.kindAt(i) != WaveformLaneKind.signal) continue;
      final payload = geom.payloads[i];
      if (payload is SignalEntry && payload.signalRef == signalRef) {
        return (geom.tops[i], geom.heights[i]);
      }
    }
    return null;
  }

  // ── trackpad vertical scroll ────────────────────────────────────────────────

  /// Called by [WaveformGestureHandler] when the user performs a trackpad
  /// two-finger vertical scroll (iPad Magic Keyboard / macOS).  Scrolls the
  /// shared lane-list controller by [delta] pixels (positive moves the
  /// viewport down).  The signal list and value column are wired to the same
  /// controller via [WaveformViewCenter] so they all stay in sync.
  void _onTrackpadVerticalScroll(double delta) {
    if (!_verticalScroll.hasClients) return;
    final position = _verticalScroll.position;
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _verticalScroll.jumpTo(next);
  }

  // ── tap hit-testing ─────────────────────────────────────────────────────────

  /// Called by [WaveformGestureHandler] after a primary (non-shift, non-right)
  /// tap is finalised.  Checks whether the tap landed on a transaction block
  /// and, if so, selects it and moves the primary cursor to its start time.
  void _onPrimaryTap(Offset viewportPosition) {
    _dismissAnnotationEditor();
    final lanes = _lastLanes;
    // Account for vertical scroll offset to get canvas-local y.
    // Guard against scroll controller with no clients (e.g. during widget
    // tree transitions where the canvas is being remounted).
    final scrollOffset = _verticalScroll.hasClients
        ? _verticalScroll.offset
        : 0.0;
    final canvasY = viewportPosition.dy + scrollOffset;

    for (final lane in lanes) {
      if (lane.kind != WaveformLaneKind.transaction) continue;
      if (canvasY < lane.y || canvasY > lane.y + lane.height) continue;

      // Tap landed in a transaction lane — search for a hit block.
      final timeMapper = ref.read(timeMapperProvider);
      final tappedTime = timeMapper.pixelToTime(viewportPosition.dx);

      for (final tx in lane.transactions) {
        if (tx.startTime <= tappedTime && tappedTime <= tx.endTime) {
          ref
              .read(selectedTransactionProvider.notifier)
              .select(tx, lane.decoderInstanceId!);
          // Override the cursor to the transaction's start time.
          ref.read(cursorStateProvider.notifier).placePrimary(tx.startTime);
          return;
        }
      }

      // Tapped in the lane gap between blocks — clear selection.
      ref.read(selectedTransactionProvider.notifier).clearSelection();
      return;
    }

    // Not in any transaction lane — clear selection.
    ref.read(selectedTransactionProvider.notifier).clearSelection();
  }

  // ── long-press context menu ─────────────────────────────────────────────────

  /// Fired by [WaveformGestureHandler] when a touch pointer is held stationary
  /// for the long-press duration.  Computes the time at the press location and
  /// shows a popup menu with cursor-related actions, anchored at the press
  /// position.  Touch users have no right-click affordance; this menu is the
  /// mobile-equivalent context menu that lets them place the secondary cursor,
  /// clear cursors, or fit the full time range without leaving the canvas.
  Future<void> _onLongPress(
    Offset globalPosition,
    Offset localPosition,
  ) async {
    final l10n = L10N.of(context);
    final time = ref.read(timeMapperProvider).pixelToTime(localPosition.dx);
    final result = await showMenu<_WaveformContextAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: _WaveformContextAction.placePrimary,
          child: Text(l10n.waveformContextMenuPlacePrimary),
        ),
        PopupMenuItem(
          value: _WaveformContextAction.placeSecondary,
          child: Text(l10n.waveformContextMenuPlaceSecondary),
        ),
        PopupMenuItem(
          value: _WaveformContextAction.clearCursors,
          child: Text(l10n.waveformContextMenuClearCursors),
        ),
        PopupMenuItem(
          value: _WaveformContextAction.fitAll,
          child: Text(l10n.waveformContextMenuFitAll),
        ),
        PopupMenuItem(
          value: _WaveformContextAction.addAnnotation,
          child: Text(l10n.annotationAddHere),
        ),
        // Both band flavours are offered here rather than inferred, because
        // "this window of time" and "this signal over this window" are
        // different claims and the app cannot tell which one the user means.
        PopupMenuItem(
          value: _WaveformContextAction.addRange,
          child: Text(l10n.annotationAddRange),
        ),
        PopupMenuItem(
          value: _WaveformContextAction.addRangeOnLane,
          child: Text(l10n.annotationAddRangeOnLane),
        ),
      ],
    );
    if (result == null || !mounted) return;
    switch (result) {
      case _WaveformContextAction.placePrimary:
        ref.read(cursorStateProvider.notifier).placePrimary(time);
      case _WaveformContextAction.placeSecondary:
        ref.read(cursorStateProvider.notifier).placeSecondary(time);
      case _WaveformContextAction.clearCursors:
        ref.read(cursorStateProvider.notifier).clearAll();
      case _WaveformContextAction.fitAll:
        ref.read(navigationProvider.notifier).fitAll();
      case _WaveformContextAction.addAnnotation:
        _createAnnotationAt(localPosition);
      case _WaveformContextAction.addRange:
        _createRangeAnnotation();
      case _WaveformContextAction.addRangeOnLane:
        _createRangeAnnotation(atPosition: localPosition);
    }
  }

  /// Authors an annotation at a canvas-local position and opens its inline
  /// editor, or tells the user why nothing happened.
  ///
  /// Silence would be the wrong answer here: an Alt-click that lands between
  /// lanes, or on a group header, looks identical to one that worked.
  void _createAnnotationAt(Offset localPosition) {
    final metrics = MobileMetrics.of(context, ref.read(deviceClassProvider));
    final id = ref
        .read(annotationAuthoringProvider.notifier)
        .createAtPosition(
          dx: localPosition.dx,
          dy: localPosition.dy,
          scrollOffset: _viewportTop ?? 0,
          minLaneHeight: metrics.minLaneHeight,
        );

    if (id == null) {
      showCruxInfoSnack(context, L10N.of(context).annotationNoRowHere);
      return;
    }
    ref.read(annotationBeingEditedProvider.notifier).editing = id;
  }

  /// Creates a band between the two cursors.
  ///
  /// With [atPosition] the band is confined to the lane under that point;
  /// without it the band spans the whole canvas. The delta is pre-filled as the
  /// label so the common measurement needs no typing, and the editor opens so
  /// the user can replace it with what the measurement *means*.
  void _createRangeAnnotation({Offset? atPosition}) {
    String? rowId;
    if (atPosition != null) {
      final metrics = MobileMetrics.of(context, ref.read(deviceClassProvider));
      final geometry = ref.read(
        laneGeometryProvider(LaneMetrics(minLaneHeight: metrics.minLaneHeight)),
      );
      final y = atPosition.dy + (_viewportTop ?? 0);
      for (final row in geometry.rows) {
        if (y >= row.top && y < row.top + row.height) {
          rowId = row.entry.signalPath;
          break;
        }
      }
      if (rowId == null) {
        showCruxInfoSnack(context, L10N.of(context).annotationNoRowHere);
        return;
      }
    }

    final cursor = ref.read(cursorStateProvider);
    final label =
        TimeFormatService(
          timescale: ref.read(waveformSourceProvider).value?.timescale,
        ).formatDelta(
          cursor.primaryCursorTime ?? 0,
          cursor.secondaryCursorTime ?? 0,
        );

    final id = ref
        .read(annotationAuthoringProvider.notifier)
        .createRangeFromCursors(label: label, rowId: rowId);
    if (id == null) {
      showCruxInfoSnack(
        context,
        L10N.of(context).annotationRangeNeedsTwoCursors,
      );
      return;
    }
    ref.read(annotationSelectedProvider.notifier).selected = id;
    ref.read(annotationBeingEditedProvider.notifier).editing = id;
  }

  /// Shortest arrow worth keeping, in logical pixels.
  ///
  /// Below this an arrow is visually indistinguishable from the dot already
  /// drawn at its anchor, so an Alt-click that slipped a couple of pixels
  /// would leave a note the user cannot see well enough to delete.
  static const double _kMinArrowLength = 12;

  /// Starts an arrow: same anchor resolution as [_createAnnotationAt], but the
  /// note is an arrow and no editor opens, because an arrow carries no text.
  ///
  /// The label offset starts at zero rather than the callout default, so the
  /// arrowhead begins at the anchor and the drag *is* the arrow — a leader that
  /// jumped 32 px up before the user had moved would look like a bug.
  void _beginArrowAt(Offset localPosition) {
    final metrics = MobileMetrics.of(context, ref.read(deviceClassProvider));
    // Opened BEFORE the create, so drawing an arrow is one press of undo
    // rather than two — and so the discard path below can drop the whole
    // thing by cancelling rather than by deleting, which would otherwise
    // leave an undo step that resurrects an arrow the user never wanted.
    ref.read(annotationsProvider.notifier).beginTransaction();
    final id = ref
        .read(annotationAuthoringProvider.notifier)
        .createAtPosition(
          dx: localPosition.dx,
          dy: localPosition.dy,
          scrollOffset: _viewportTop ?? 0,
          minLaneHeight: metrics.minLaneHeight,
          shape: AnnotationShape.arrow,
        );
    if (id == null) {
      ref.read(annotationsProvider.notifier).cancelTransaction();
      showCruxInfoSnack(context, L10N.of(context).annotationNoRowHere);
      return;
    }
    _arrowInFlight = id;
    ref.read(annotationsProvider.notifier).setLabelOffset(id, 0, 0);
    // Selecting it as it is drawn means the keyboard nudge applies to the thing
    // the user is looking at without a second gesture to say so.
    ref.read(annotationSelectedProvider.notifier).selected = id;
  }

  void _extendArrow(Offset delta) {
    final id = _arrowInFlight;
    if (id == null) return;
    ref.read(annotationsProvider.notifier).nudgeLabel(id, delta.dx, delta.dy);
  }

  /// Ends the arrow drag as ONE undo step.
  ///
  /// An arrow the user dragged nowhere is discarded: a zero-length arrow is
  /// indistinguishable from the dot at its anchor, and leaving one behind makes
  /// an Alt-click that slipped a pixel into litter the user cannot see to
  /// delete.
  void _endArrow() {
    final id = _arrowInFlight;
    _arrowInFlight = null;
    if (id == null) return;
    final notifier = ref.read(annotationsProvider.notifier);
    final arrow = notifier.snapshot().where((a) => a.id == id).firstOrNull;
    final tooShort =
        arrow != null &&
        Offset(arrow.labelDx, arrow.labelDy).distance < _kMinArrowLength;
    if (tooShort) {
      // Removed INSIDE the still-open transaction so it records nothing, then
      // cancelled — the undo stack ends where it started.
      notifier
        ..remove(id)
        ..cancelTransaction();
      ref.read(annotationSelectedProvider.notifier).clear();
      return;
    }
    notifier.endTransaction();
  }

  /// Closes any open annotation editor when the user goes back to reading the
  /// waveform.
  ///
  /// A bare canvas takes no focus of its own, so a text field opened over it
  /// keeps focus until something else claims it. Left alone, the note stays in
  /// edit mode indefinitely — which also makes it undraggable, since a drag
  /// would fight text selection.
  void _dismissAnnotationEditor() {
    if (ref.read(annotationBeingEditedProvider) == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  // ── build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final colorTheme = ref.watch(cruxColorThemeProvider);

    final signalGroup = ref.watch(signalGroupsProvider);
    final timeMapper = ref.watch(timeMapperProvider);
    // Cursor state is intentionally NOT watched in this build method.
    //
    // Watching it here would force the entire 1000+-lane build pipeline
    // (`_buildGeometryIndex`, `_materializeLanes`,
    // and reconstruction of every widget below this point) to re-run on
    // every cursor frame. The render object's `lanes` setter compares
    // lane lists by reference equality (Dart's default `List.==`), so a
    // freshly built lanes list would always trigger `markNeedsLayout`,
    // forcing a full repaint and defeating the CursorOverlay layer split.
    //
    // Instead, the cursor lines + delta chip live in [CursorOverlay]
    // (its own RepaintBoundary), and the analog inline cursor label
    // is delivered via an inline Consumer wrapping [WaveformCanvasView]
    // (see _CanvasViewWithLiveCursor below). The outer build only re-runs
    // when something other than cursor moves changes — zoom, signal
    // add/remove, decoder activation, theme change, etc.
    //
    // The Semantics accessibility label uses a one-shot `ref.read`
    // snapshot for the same reason. Screen readers query labels on focus
    // events rather than continuously, so a stale cursor time during
    // rapid scrubbing is acceptable; the label refreshes on the next
    // legitimate rebuild (zoom, signal-list edit, file load).
    final cursorState = ref.read(cursorStateProvider);
    final selection = ref.watch(navigationProvider);
    final sourceAsync = ref.watch(waveformSourceProvider);
    final variablesMap = ref.watch(signalVariablesMapProvider);
    final filtersMap = ref.watch(translateFilterProvider);

    // The per-tab selection (keyed by fullPath) goes to the render object
    // as it is; each lane carries its own row path to match it against.
    // Resolving the paths to signalRefs instead tinted every alias of a
    // selected net, since aliased variables share one ref. Watching
    // selectedVariablesProvider here is what repaints the canvas on a
    // selection change — including an inbound CXP cross-probe, whose
    // selection was previously visible only in the side panes.
    final selectedRowPaths = ref.watch(selectedVariablesProvider);
    // Accent color mirrors the value/name pane row highlight (Theme primary).
    final selectionColor = Theme.of(context).colorScheme.primary;
    final activeDecoders = ref.watch(activeDecodersProvider);
    final selectedTxRecord = ref.watch(selectedTransactionProvider);
    final selectedTx = selectedTxRecord?.$1;
    final diff = ref.watch(diffProvider);
    final patternMatchRanges = ref.watch(
      patternSearchProvider.select((s) => s.matchRanges),
    );
    final xTrace = ref.watch(xTraceProvider);
    final statsCollector = ref.watch(renderStatsCollectorProvider);
    // Read once for the Semantics label snapshot — see comment on
    // `cursorState = ref.read(...)` above.
    final timescale = ref.read(currentTimescaleProvider);

    // Derive X-origin canvas data from the active X-trace (if any).
    final xOriginTime = xTrace.isActive ? xTrace.rootNode?.xStartTime : null;
    final xOriginSignalRefs = _xOriginSignalRefs(xTrace, variablesMap);

    // Initialize TimeMapper and refresh data when the data source changes.
    ref
      ..listen<AsyncValue<WaveformDataSource?>>(
        waveformSourceProvider,
        (prev, next) {
          final source = next.value;
          if (source != null) {
            ref
                .read(timeMapperProvider.notifier)
                .initialize(
                  startTime: source.startTime,
                  endTime: source.endTime,
                  viewportWidth: _viewportWidth,
                );
            _scheduleRefresh();
          } else {
            setState(_clearChangeCaches);
          }
        },
      )
      ..listen<SignalGroup>(signalGroupsProvider, (prev, next) {
        if (prev != next) _scheduleRefresh();
      })
      ..listen<(int, int)>(visibleTimeRangeProvider, (prev, next) {
        if (prev != next) _onHorizontalViewChanged();
      })
      // Auto-reveal on an inbound cross-probe: scroll the selected signal's
      // lane into view and expand its group if collapsed. Registered before
      // the loading/empty early-returns so a reveal that arrives while the
      // canvas is briefly in a placeholder state is not dropped.
      ..listen<RevealSignalRequest?>(revealSignalRequestProvider, (prev, next) {
        _maybeReveal(next);
      });

    // One-shot recovery for a reveal that was written BEFORE this canvas
    // mounted (the reverse cross-probe / fresh-open case): the `ref.listen`
    // above only fires on a transition, so a request already sitting in the
    // provider when the tab's canvas first builds would never be seen. Reading
    // it here on every build, gated by the per-token dedupe in [_maybeReveal],
    // fires it exactly once without yanking the viewport on unrelated rebuilds.
    _maybeReveal(ref.read(revealSignalRequestProvider));

    // ── empty / loading states ─────────────────────────────────────────────

    if (sourceAsync is AsyncLoading) {
      // Parse-in-progress placeholder, named after the file so the multi-
      // second open of a huge trace reads as deliberate work. On web the
      // spinner freezes once the main-thread WASM parse starts (see the
      // paint-before-parse yield in WaveformSourceNotifier.openFromBytes);
      // the filename text is what carries the message there. Desktop/mobile
      // parse on the background isolate, so the spinner animates throughout.
      final parsingPath = ref
          .read(waveformSourceProvider.notifier)
          .lastAttemptedPath;
      final parsingName = parsingPath?.split('/').last.split(r'\').last;
      return Semantics(
        label: l10n.accessibilityWaveformNoFile,
        child: _buildPlaceholder(
          context: context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 14),
              Text(
                parsingName == null
                    ? l10n.signalTreeLoading
                    : l10n.waveformCanvasParsing(parsingName),
                style: TextStyle(color: colorTheme.canvasRulerTickMajor),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (sourceAsync.value == null) {
      return Semantics(
        label: l10n.accessibilityWaveformNoFile,
        child: _buildPlaceholder(
          context: context,
          child: Text(
            l10n.waveformCanvasNoFile,
            style: TextStyle(color: colorTheme.canvasRulerTickMajor),
          ),
        ),
      );
    }

    final (visibleStart, _) = ref.read(visibleTimeRangeProvider);
    // Row heights come from the shared [LaneGeometry] model via a [LaneMetrics]
    // resolved identically by SignalListPanel and ValueColumnPanel, so the
    // three columns stay vertically aligned by construction.
    final deviceClass = ref.watch(deviceClassProvider);
    final canvasMetrics = MobileMetrics.of(context, deviceClass);
    final laneMetrics = LaneMetrics(minLaneHeight: canvasMetrics.minLaneHeight);
    // Reserved translator child-row space per signal id — shared with the value
    // column and signal-names list so an expanded bitfield signal reserves the
    // same vertical span in every column and its wave never drifts.
    final childRowCounts = ref.watch(signalChildRowCountsProvider);
    // Reuse the memoized geometry index when no structure-affecting input
    // changed — a vertical scroll, a change-cache bump, and per-signal
    // display metadata all leave the geometry untouched. Inputs are compared
    // by identity because the providers return the same instance when
    // unchanged.
    final geometryMemoHit =
        _memoGeometry != null &&
        identical(_memoSignalGroup, signalGroup) &&
        identical(_memoDiff, diff) &&
        identical(_memoDecoders, activeDecoders) &&
        identical(_memoChildRowCounts, childRowCounts) &&
        _memoMinLaneHeight == laneMetrics.minLaneHeight;
    final LaneGeometryIndex geometry;
    if (geometryMemoHit) {
      geometry = _memoGeometry!;
    } else {
      geometry = _buildGeometryIndex(
        signalGroup.entries,
        diff,
        laneMetrics,
        childRowCounts,
        activeDecoders,
      );
      _memoGeometry = geometry;
      _memoSignalGroup = signalGroup;
      _memoDiff = diff;
      _memoDecoders = activeDecoders;
      _memoChildRowCounts = childRowCounts;
      _memoMinLaneHeight = laneMetrics.minLaneHeight;
    }
    _lastGeometry = geometry;
    final contentBottom = geometry.bottom;

    // Materialize rich lane objects — all of them for normal files, only the
    // viewport window (plus overscan) at gate-level scale. This runs fresh
    // every build: it is O(materialized), so ~a screenful of object work per
    // frame, and it picks up the change caches without any versioned memo.
    final (
      firstLane,
      lastLane,
    ) = geometry.length <= WaveformCanvas.fullMaterializeThreshold
        ? (0, geometry.length)
        : geometry.visibleRange(
            (_viewportTop ?? 0) - _overscanPx,
            (_viewportBottom ?? _kInitialViewportHeight) + _overscanPx,
          );
    final lanes = _materializeLanes(
      geometry,
      firstLane,
      lastLane,
      variablesMap,
      filtersMap,
      diff,
      visibleStart,
      activeDecoders,
      l10n,
    );

    final divergenceRegions = diff.isActive
        ? diff.allDivergenceRegions
        : const <TimeRange>[];

    // Keep the last materialized lanes for transaction tap hit-testing (taps
    // are viewport-local, so the materialized window always covers them).
    _lastLanes = lanes;
    assert(() {
      WaveformCanvas.debugOnLanesBuilt?.call(lanes);
      return true;
    }(), 'debug-only lane geometry sink for the alignment-invariant test');

    if (geometry.length == 0) {
      // The render object is not in the tree when the placeholder is shown, so
      // paint() is never called to reset the stats. Schedule the reset here so
      // the diagnostics panel does not show stale values from the last frame
      // that had visible signal lanes. Issue 26: pre-fix this reset recorded
      // `Size.zero`, which surfaced as a misleading "0×0 px" canvas size in
      // the Pane Render Stats popover even though the empty-state placeholder
      // occupies the pane's real physical dimensions. Wrap the placeholder
      // in a [LayoutBuilder] so we report the *actual* canvas extent — the
      // paint metrics legitimately stay at 0.0 ms / 0 transitions (nothing
      // is being painted) but the canvas size now matches what the user
      // sees on screen.
      return Semantics(
        label: l10n.accessibilityWaveformNoSignals,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final canvasSize = Size(
              constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
              constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              statsCollector
                ..beginFrame()
                ..recordViewportInfo(0, 0, canvasSize)
                ..endFrame();
            });
            return _buildPlaceholder(
              context: context,
              child: Text(
                l10n.waveformCanvasNoSignals,
                style: TextStyle(color: colorTheme.canvasRulerTickMajor),
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
      );
    }

    // The true content extent, NOT `sum(lane.height)`: blank translator
    // child-row space reserved after a lane advances the layout but adds no
    // lane, so folding heights under-counts and the canvas SizedBox ends up
    // shorter than what's painted — clipping the lanes below an expanded
    // signal (issue #43, bug 1). `contentBottom` carries that reserved space.
    final totalHeight = contentBottom;

    final cursorTicks = cursorState.primaryCursorTime;
    final timeFormatter = TimeFormatService(timescale: timescale);
    final cursorTimeLabel = cursorTicks != null
        ? timeFormatter.format(cursorTicks)
        : '—';
    final signalCount = geometry.signalLaneCount;

    return Semantics(
      key: WaveformCanvas.waveformCanvasKey,
      label: l10n.accessibilityWaveformActive(signalCount, cursorTimeLabel),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final newWidth = constraints.maxWidth;
          // Re-sync the TimeMapper whenever the layout width disagrees with
          // EITHER our local tracker or the mapper's own viewportWidth. The
          // second check is the safety net: the actual update below is deferred
          // to a post-frame callback that can be dropped (the `if (mounted)`
          // branch failing when the canvas is momentarily unmounted/reparented
          // during an IdeLayout pane reflow on resize, or a macOS live-resize
          // frame being coalesced). If that happens, `_viewportWidth` has
          // already advanced to `newWidth`, so comparing against it alone would
          // never re-trigger and the mapper would stay stuck at the stale width
          // — the waveform packs into a strip, the scrollbar thumb shrinks, and
          // the cursor lines/ruler markers land at the wrong x. Comparing
          // against the watched `timeMapper` (re-read every build) closes that
          // hole: the next rebuild notices the divergence and reschedules.
          if ((newWidth - _viewportWidth).abs() > 0.5 ||
              (newWidth - timeMapper.viewportWidth).abs() > 0.5) {
            _viewportWidth = newWidth;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ref
                    .read(timeMapperProvider.notifier)
                    .updateViewportWidth(newWidth);
              }
            });
          }

          final newHeight = constraints.maxHeight;
          if (newHeight.isFinite && (newHeight - _viewportHeight).abs() > 0.5) {
            _viewportHeight = newHeight;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              // Recompute viewport bounds with the new height so the next frame
              // sees correct culling values.
              _onScroll();
              // Republish the canvas viewport height so ValueColumnPanel resizes
              // its body to match. WaveformViewCenter also publishes this, but
              // only when *it* rebuilds — a bottom-panel toggle or splitter drag
              // changes the canvas height via constraints WITHOUT rebuilding it,
              // which left the value column sized to the stale (shorter) height
              // with an uncolored gap painting over the lower values. This
              // LayoutBuilder reliably rebuilds on the constraint change, so it
              // is the right place to keep the published height fresh.
              final dim = _verticalScroll.hasClients
                  ? _verticalScroll.position.viewportDimension
                  : newHeight;
              ref.read(canvasViewportHeightProvider.notifier).setHeight(dim);
            });
          }

          return WaveformGestureHandler(
            onPrimaryTap: _onPrimaryTap,
            onLongPress: _onLongPress,
            onAltTap: _createAnnotationAt,
            onAltDragStart: _beginArrowAt,
            onAltDragUpdate: _extendArrow,
            onAltDragEnd: _endArrow,
            onVerticalScroll: _onTrackpadVerticalScroll,
            // Stack the cursor overlay above the scrolling canvas so cursor
            // moves only invalidate the overlay's RepaintBoundary, not the
            // lane painter. The overlay is wrapped in IgnorePointer so it
            // does not intercept pinch-zoom, drag-pan, tap, or long-press
            // events that the gesture handler above must receive.
            // The ColoredBox provides the canvas background colour for the area
            // beyond the last lane (where the render object's paint region ends)
            // so theme switches recolor the empty space below the signals too.
            child: ColoredBox(
              color: colorTheme.canvasBackground,
              child: Stack(
                children: [
                  Positioned.fill(
                    // Opt the lane scroll view OUT of the app-wide `trackpad`
                    // dragDevice (see [kTrackpadOwnedDragDevices]).
                    // [WaveformGestureHandler] already owns the two-finger
                    // pan-zoom over the canvas — it maps the scale to zoom, the
                    // horizontal pan to time-pan, and the vertical pan to lane
                    // scroll (via onVerticalScroll). Letting this
                    // SingleChildScrollView ALSO drag-scroll on the same
                    // pan-zoom would double-drive vertical scroll and fight the
                    // pinch-zoom gesture.
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: kTrackpadOwnedDragDevices,
                      ),
                      child: Scrollbar(
                        controller: _verticalScroll,
                        child: SingleChildScrollView(
                          controller: _verticalScroll,
                          // Clamping physics prevents iOS-style bounce on desktop,
                          // which causes a delay where new scroll events are ignored
                          // mid-animation.
                          physics: const ClampingScrollPhysics(),
                          // _ScrollModifierInterceptor must be the direct child of
                          // SingleChildScrollView so it is dispatched before the
                          // Scrollable in Flutter's hit-test path. That lets it
                          // claim Ctrl/Shift scroll events via pointerSignalResolver
                          // before Scrollable can, preventing the lane list from
                          // also scrolling vertically when the user zooms or pans
                          // with a modifier key held.
                          child: WaveformScrollModifierInterceptor(
                            onVerticalScroll: _onTrackpadVerticalScroll,
                            child: RepaintBoundary(
                              child: SizedBox(
                                width: double.infinity,
                                height: totalHeight,
                                // The Consumer here is the only point in the
                                // canvas tree that subscribes to cursor state.
                                // Cursor scrubbing rebuilds *only* this leaf —
                                // no parent rebuilds, no `_buildLaneData`
                                // recomputation, no fresh lanes list. The
                                // analog-aware `cursorState` setter on the
                                // render object then no-ops when there are no
                                // analog lanes (typical case), so the entire
                                // lane painting stays cached and only the
                                // CursorOverlay layer repaints.
                                child: Consumer(
                                  builder: (context, ref, _) {
                                    final liveCursor = ref.watch(
                                      cursorStateProvider,
                                    );
                                    final fontSize = ref.watch(
                                      appSettingsProvider.select(
                                        (s) =>
                                            s.value?.waveformFontSize ?? 12.0,
                                      ),
                                    );
                                    // Settings → Appearance "Boost legibility for
                                    // XR / large displays": thickens traces and
                                    // raises a font floor so the canvas stays
                                    // readable at the low angular resolution of
                                    // XR/AR glasses. No effect when off (default).
                                    final legibilityBoost = ref.watch(
                                      appSettingsProvider.select(
                                        (s) =>
                                            s.value?.canvasLegibilityBoost ??
                                            false,
                                      ),
                                    );
                                    final lineWidthScale = legibilityBoost
                                        ? 1.6
                                        : 1.0;
                                    final effectiveFontSize =
                                        legibilityBoost && fontSize < 14.0
                                        ? 14.0
                                        : fontSize;
                                    return WaveformCanvasView(
                                      lanes: lanes,
                                      timeMapper: timeMapper,
                                      cursorState: liveCursor,
                                      colorTheme: colorTheme,
                                      fontSize: effectiveFontSize,
                                      lineWidthScale: lineWidthScale,
                                      selectionRange: selection,
                                      selectedTransaction: selectedTx,
                                      divergenceRegions: divergenceRegions,
                                      patternMatchRegions: patternMatchRanges,
                                      xOriginTime: xOriginTime,
                                      xOriginSignalRefs: xOriginSignalRefs,
                                      selectedRowPaths: selectedRowPaths,
                                      selectionColor: selectionColor,
                                      statsCollector: statsCollector,
                                      viewportTop: _viewportTop,
                                      viewportBottom: _viewportBottom,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // User-authored annotations. Below every
                  // cursor layer on purpose: a note is context, the cursor is
                  // the instrument, and a balloon must never occlude the thing
                  // the user is measuring with. Anchored through the same
                  // time-mapper + lane geometry as the canvas, so it tracks
                  // pan/zoom/scroll; needs the vertical scroll offset to map
                  // row Y, so it is not const. Renders nothing when the tab
                  // has no annotations.
                  Positioned.fill(
                    child: AnnotationOverlay(scrollOffset: _viewportTop ?? 0),
                  ),
                  const Positioned.fill(child: CursorOverlay()),
                  // Remote collaborator cursors (Enterprise collaborative
                  // viewing). Renders nothing when no session is active (the
                  // open-core noop service produces no session state), so this
                  // layer is inert in Open Core and Pro builds. Layered above
                  // the local CursorOverlay and wrapped in its own
                  // RepaintBoundary + IgnorePointer so remote cursor churn
                  // never invalidates the lane cache or steals gestures.
                  const Positioned.fill(child: CollaboratorCursorOverlay()),
                  // Session-wide shared markers (Enterprise collaborative
                  // viewing). Like the collaborator cursors, this renders
                  // nothing when no session is active, so it is inert in Open
                  // Core and idle Pro builds.
                  const Positioned.fill(child: SharedMarkerOverlay()),
                  // Data-anchored collaboration pointers — pings (TTL fade) and
                  // pins (author-only delete), with an off-screen directional
                  // affordance. Anchored through the same time-mapper +
                  // lane geometry as the canvas so they track pan/zoom/scroll.
                  // Needs the vertical scroll offset to map row Y, so (unlike
                  // the full-height cursor/marker overlays) it is not const.
                  // Inert when no session is active.
                  Positioned.fill(
                    child: SharedPointerOverlay(
                      scrollOffset: _viewportTop ?? 0,
                    ),
                  ),
                  // Phone-only: inline-at-cursor value labels replace the modal
                  // values endDrawer. Layered above CursorOverlay so
                  // the one interactive surface (tap-to-expand on a truncated
                  // label) is not occluded; non-interactive pills pass gestures
                  // through to WaveformGestureHandler via IgnorePointer. Gated on
                  // device class per the UI-gating convention — tablet/desktop use
                  // the docked value pane instead.
                  if (deviceClass == DeviceClass.phone ||
                      deviceClass == DeviceClass.phoneLandscape)
                    Positioned.fill(
                      child: InlineCursorValueOverlay(
                        scrollOffset: _viewportTop ?? 0,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaceholder({
    required BuildContext context,
    required Widget child,
  }) {
    final colorTheme = ProviderScope.containerOf(
      context,
    ).read(cruxColorThemeProvider);
    return ColoredBox(
      color: colorTheme.canvasBackground,
      child: Center(child: child),
    );
  }
}
