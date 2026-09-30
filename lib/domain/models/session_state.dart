// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/fsm_annotation.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/domain/models/persisted_decoder.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';

/// Immutable snapshot of a complete WaveCrux viewer session.
///
/// Serialized to/from `.wavecrux` JSON files by [SessionService]. Captures
/// everything needed to fully restore the viewer: the waveform source file,
/// the arranged signal list, cursor/marker positions, zoom/pan state, and
/// panel visibility settings.
///
/// [ticksPerPixel] and [panOffsetTicks] store the zoom and pan state. They are
/// applied after the waveform file is reopened (which re-establishes the
/// simulation time range and viewport width).
@immutable
class SessionState {
  const SessionState({
    this.sourceFilePath,
    this.signalGroup = const SignalGroup(),
    this.cursorState = const CursorState(),
    this.markerState = const MarkerState(),
    this.ticksPerPixel = 1.0,
    this.panOffsetTicks = 0.0,
    this.scrollOffset = 0.0,
    this.signalTreeVisible = true,
    this.valueColumnVisible = true,
    this.transactionViewVisible = false,
    this.stageViewVisible = false,
    this.statisticsStripVisible = false,
    this.cocotbLogPanelVisible = false,
    this.annotationsPanelVisible,
    this.rtlSourceVisible = false,
    this.bottomDockTab,
    this.rightDockTab,
    this.dockPlacements = const <String, String>{},
    this.cocotbLogPath,
    this.rtlStemsPath,
    this.leftPaneSize,
    this.rightPaneSize,
    this.bottomPaneSize,
    this.expandedScopePaths = const <String>{},
    this.signalTreeSearchQuery = '',
    this.signalTreeSelectedRefs = const <String>{},
    this.signalTreeScrollOffset = 0.0,
    this.translateFilterPaths = const {},
    this.fsmAnnotations = const <String, FsmAnnotation>{},
    this.stageWorkspace = const StageWorkspaceState(),
    this.activeThemeName = 'wavecrux-dark',
    this.extensions = const <String, Object?>{},
    this.decoders = const <PersistedDecoder>[],
    this.annotations = const <Annotation>[],
    this.annotationLayers = const <AnnotationLayer>[],
    this.annotationsVisible = true,
  });

  /// Absolute path to the loaded waveform file, or null if none.
  final String? sourceFilePath;

  /// The ordered signal list with groups, separators, and comments.
  final SignalGroup signalGroup;

  /// Primary and secondary cursor positions in simulation ticks.
  final CursorState cursorState;

  /// Named markers (a–z) at simulation ticks.
  final MarkerState markerState;

  /// Zoom level: simulation ticks represented by one viewport pixel.
  final double ticksPerPixel;

  /// Pan offset: simulation tick at pixel x = 0 (left edge of viewport).
  final double panOffsetTicks;

  /// Vertical scroll offset (in logical pixels) for the signal list and
  /// waveform canvas. Restored verbatim so a user who scrolled to the bottom
  /// of a 33-signal viewport before quitting sees the same view on restart.
  final double scrollOffset;

  /// Whether the signal tree (SST) panel is visible.
  final bool signalTreeVisible;

  /// Whether the value column panel is visible.
  final bool valueColumnVisible;

  /// Whether the transaction/decoder panel is visible.
  final bool transactionViewVisible;

  /// Whether the Stage panel (signal-bound widget dashboard) is visible.
  final bool stageViewVisible;

  /// Whether the live statistics strip is expanded (desktop only, default false).
  final bool statisticsStripVisible;

  /// Whether the cocotb log panel owns the bottom pane.
  ///
  /// Restored together with [cocotbLogPath]: the flag re-docks the panel and the
  /// path triggers a fail-soft re-parse of the log file. A missing/moved log
  /// leaves the panel in its normal empty state.
  final bool cocotbLogPanelVisible;

  /// Whether the Annotations dock panel is shown, or `null` for "decide from
  /// whether the tab has annotations". See
  /// `PanelLayoutState.annotationsPanelVisible` for why this is a tri-state.
  final bool? annotationsPanelVisible;

  /// Whether the RTL source-annotation panel is visible (desktop only).
  /// Restored together with [rtlStemsPath].
  final bool rtlSourceVisible;

  /// The bottom dock's active tab id, or null for a session saved before the
  /// dock existed (restores via the legacy priority-chain derivation in
  /// `PanelLayoutState.effectiveBottomDockTab`).
  final String? bottomDockTab;

  /// The right dock's active tab id — same null contract as [bottomDockTab].
  final String? rightDockTab;

  /// Drag-between-docks placement overrides (tab id → region). Empty for a
  /// session that never moved a tab.
  final Map<String, String> dockPlacements;

  /// Absolute path of the cocotb log last loaded into the bottom pane, or null.
  /// Re-parsed fail-soft on restore (mirrors the Pro SVA log restore).
  final String? cocotbLogPath;

  /// Absolute path of the RTL stems file last loaded, or null. Re-loaded
  /// fail-soft on restore.
  final String? rtlStemsPath;

  /// Persisted left/right pane widths and bottom pane height in logical pixels,
  /// or null to use the layout default. Mirror [PanelLayoutState] geometry so a
  /// relaunch keeps the user's pane sizes (VS Code-style).
  final double? leftPaneSize;

  /// See [leftPaneSize].
  final double? rightPaneSize;

  /// See [leftPaneSize].
  final double? bottomPaneSize;

  /// Scope paths expanded in the signal-tree browser. Mirrors
  /// `expandedScopesProvider`. Stale paths (scopes absent from the reopened
  /// waveform) are harmless on restore.
  final Set<String> expandedScopePaths;

  /// Text last entered in the signal-tree search box. Mirrors
  /// `signalSearchQueryProvider`.
  final String signalTreeSearchQuery;

  /// Signal rows multi-selected in the signal-tree browser, as
  /// `Variable.fullPath` values (row identity — see
  /// `selectedVariablesProvider`). The JSON key keeps its historical
  /// `selectedRefs` name for compatibility; values written by pre-0.2.3
  /// builds were signalRefs and are harmlessly stale on restore (a stale
  /// value simply never matches a rendered row).
  final Set<String> signalTreeSelectedRefs;

  /// Vertical scroll offset (logical pixels) of the signal-tree browser list.
  /// Mirrors `signalTreeScrollProvider`.
  final double signalTreeScrollOffset;

  /// Per-signal translate filter file paths (signalRef → absolute file path).
  final Map<String, String> translateFilterPaths;

  /// User-supplied FSM state-name annotations, keyed by signalRef. Mirrors the
  /// per-tab `fsmAnnotationProvider` state. Persisted so an FSM the user marked
  /// up (state labels) survives a session save / re-open, the same way the
  /// translate filters these annotations supplement do.
  final Map<String, FsmAnnotation> fsmAnnotations;

  /// Stage workspace: list of Stage panels (tabs) and their widget instances.
  final StageWorkspaceState stageWorkspace;

  /// Active theme pack name (matches a built-in preset or a file in the
  /// user's theme directory). Persisted in `.wavecrux` session files.
  final String activeThemeName;

  /// Pro-side per-tab payloads keyed by codec namespace (e.g. `"pro.sva"`,
  /// `"pro.debug_advisor"`). The map round-trips through the reserved
  /// top-level `extensions` field of the `.wavecrux` document. Entries
  /// whose namespace has no registered codec on the current build are
  /// preserved-but-inert: read in, re-emitted verbatim on the next save.
  /// See `lib/services/session/session_extension_codec.dart`.
  final Map<String, Object?> extensions;

  /// Persisted snapshot of every active decoder instance in the viewer.
  /// On restore, each entry is re-added to
  /// `ActiveDecodersNotifier` with the same per-type `instanceNumber`
  /// it had at snapshot time, then a `decodeAll()` pass populates
  /// transactions against the freshly-opened waveform. Entries whose
  /// `decoderId` is not in the active `DecoderRegistry` (Pro decoder
  /// opened on the Open Core viewer, uninstalled plugin) are skipped
  /// silently — see `SessionService` for the cross-tier-open contract.
  final List<PersistedDecoder> decoders;

  /// User-authored waveform annotations — balloons, arrows and
  /// time bands anchored to `(tick, signalPath)` rather than to pixels.
  ///
  /// Open-core state, so it lives here on the document proper rather than in
  /// [extensions]: that map is the Pro-overlay payload seam, and an annotation
  /// written by an open-core build must be readable by one.
  final List<Annotation> annotations;

  /// Named groups of adopted annotations, referenced by
  /// [Annotation.layerId]. The implicit `null` layer — the user's own notes —
  /// has no entry here.
  ///
  /// Additive: a document written before layers existed simply has none, and a
  /// layer whose annotations have all been deleted is dropped with them, so
  /// the registry never accumulates entries for groups that no longer exist.
  final List<AnnotationLayer> annotationLayers;

  /// Whether the canvas draws annotations. A view setting, so it rides with
  /// the rest of the panel state rather than with the notes themselves.
  final bool annotationsVisible;

  // ── copyWith ────────────────────────────────────────────────────────────────

  SessionState copyWith({
    Object? sourceFilePath = _unset,
    SignalGroup? signalGroup,
    CursorState? cursorState,
    MarkerState? markerState,
    double? ticksPerPixel,
    double? panOffsetTicks,
    double? scrollOffset,
    bool? signalTreeVisible,
    bool? valueColumnVisible,
    bool? transactionViewVisible,
    bool? stageViewVisible,
    bool? statisticsStripVisible,
    bool? cocotbLogPanelVisible,
    bool? annotationsPanelVisible,
    bool clearAnnotationsPanelVisible = false,
    bool? rtlSourceVisible,
    String? bottomDockTab,
    String? rightDockTab,
    Map<String, String>? dockPlacements,
    Object? cocotbLogPath = _unset,
    Object? rtlStemsPath = _unset,
    Object? leftPaneSize = _unset,
    Object? rightPaneSize = _unset,
    Object? bottomPaneSize = _unset,
    Set<String>? expandedScopePaths,
    String? signalTreeSearchQuery,
    Set<String>? signalTreeSelectedRefs,
    double? signalTreeScrollOffset,
    Map<String, String>? translateFilterPaths,
    Map<String, FsmAnnotation>? fsmAnnotations,
    StageWorkspaceState? stageWorkspace,
    String? activeThemeName,
    Map<String, Object?>? extensions,
    List<PersistedDecoder>? decoders,
    List<Annotation>? annotations,
    List<AnnotationLayer>? annotationLayers,
    bool? annotationsVisible,
  }) => SessionState(
    sourceFilePath: sourceFilePath == _unset
        ? this.sourceFilePath
        : sourceFilePath as String?,
    signalGroup: signalGroup ?? this.signalGroup,
    cursorState: cursorState ?? this.cursorState,
    markerState: markerState ?? this.markerState,
    ticksPerPixel: ticksPerPixel ?? this.ticksPerPixel,
    panOffsetTicks: panOffsetTicks ?? this.panOffsetTicks,
    scrollOffset: scrollOffset ?? this.scrollOffset,
    signalTreeVisible: signalTreeVisible ?? this.signalTreeVisible,
    valueColumnVisible: valueColumnVisible ?? this.valueColumnVisible,
    transactionViewVisible:
        transactionViewVisible ?? this.transactionViewVisible,
    stageViewVisible: stageViewVisible ?? this.stageViewVisible,
    statisticsStripVisible:
        statisticsStripVisible ?? this.statisticsStripVisible,
    cocotbLogPanelVisible: cocotbLogPanelVisible ?? this.cocotbLogPanelVisible,
    annotationsPanelVisible: clearAnnotationsPanelVisible
        ? null
        : (annotationsPanelVisible ?? this.annotationsPanelVisible),
    rtlSourceVisible: rtlSourceVisible ?? this.rtlSourceVisible,
    bottomDockTab: bottomDockTab ?? this.bottomDockTab,
    rightDockTab: rightDockTab ?? this.rightDockTab,
    dockPlacements: dockPlacements ?? this.dockPlacements,
    cocotbLogPath: cocotbLogPath == _unset
        ? this.cocotbLogPath
        : cocotbLogPath as String?,
    rtlStemsPath: rtlStemsPath == _unset
        ? this.rtlStemsPath
        : rtlStemsPath as String?,
    leftPaneSize: leftPaneSize == _unset
        ? this.leftPaneSize
        : leftPaneSize as double?,
    rightPaneSize: rightPaneSize == _unset
        ? this.rightPaneSize
        : rightPaneSize as double?,
    bottomPaneSize: bottomPaneSize == _unset
        ? this.bottomPaneSize
        : bottomPaneSize as double?,
    expandedScopePaths: expandedScopePaths ?? this.expandedScopePaths,
    signalTreeSearchQuery: signalTreeSearchQuery ?? this.signalTreeSearchQuery,
    signalTreeSelectedRefs:
        signalTreeSelectedRefs ?? this.signalTreeSelectedRefs,
    signalTreeScrollOffset:
        signalTreeScrollOffset ?? this.signalTreeScrollOffset,
    translateFilterPaths: translateFilterPaths ?? this.translateFilterPaths,
    fsmAnnotations: fsmAnnotations ?? this.fsmAnnotations,
    stageWorkspace: stageWorkspace ?? this.stageWorkspace,
    activeThemeName: activeThemeName ?? this.activeThemeName,
    extensions: extensions ?? this.extensions,
    decoders: decoders ?? this.decoders,
    annotations: annotations ?? this.annotations,
    annotationLayers: annotationLayers ?? this.annotationLayers,
    annotationsVisible: annotationsVisible ?? this.annotationsVisible,
  );

  // ── equality ────────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SessionState) return false;
    return sourceFilePath == other.sourceFilePath &&
        signalGroup == other.signalGroup &&
        cursorState == other.cursorState &&
        markerState == other.markerState &&
        ticksPerPixel == other.ticksPerPixel &&
        panOffsetTicks == other.panOffsetTicks &&
        scrollOffset == other.scrollOffset &&
        signalTreeVisible == other.signalTreeVisible &&
        valueColumnVisible == other.valueColumnVisible &&
        transactionViewVisible == other.transactionViewVisible &&
        stageViewVisible == other.stageViewVisible &&
        statisticsStripVisible == other.statisticsStripVisible &&
        cocotbLogPanelVisible == other.cocotbLogPanelVisible &&
        annotationsPanelVisible == other.annotationsPanelVisible &&
        rtlSourceVisible == other.rtlSourceVisible &&
        cocotbLogPath == other.cocotbLogPath &&
        rtlStemsPath == other.rtlStemsPath &&
        leftPaneSize == other.leftPaneSize &&
        rightPaneSize == other.rightPaneSize &&
        bottomPaneSize == other.bottomPaneSize &&
        _setsEqual(expandedScopePaths, other.expandedScopePaths) &&
        signalTreeSearchQuery == other.signalTreeSearchQuery &&
        _setsEqual(signalTreeSelectedRefs, other.signalTreeSelectedRefs) &&
        signalTreeScrollOffset == other.signalTreeScrollOffset &&
        _mapsEqual(translateFilterPaths, other.translateFilterPaths) &&
        _fsmAnnotationsEqual(fsmAnnotations, other.fsmAnnotations) &&
        stageWorkspace == other.stageWorkspace &&
        activeThemeName == other.activeThemeName &&
        _extensionsEqual(extensions, other.extensions) &&
        _decodersEqual(decoders, other.decoders) &&
        _annotationsEqual(annotations, other.annotations) &&
        _listEquals(annotationLayers, other.annotationLayers) &&
        annotationsVisible == other.annotationsVisible;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    sourceFilePath,
    signalGroup,
    cursorState,
    markerState,
    ticksPerPixel,
    panOffsetTicks,
    scrollOffset,
    signalTreeVisible,
    valueColumnVisible,
    transactionViewVisible,
    stageViewVisible,
    statisticsStripVisible,
    cocotbLogPanelVisible,
    annotationsPanelVisible,
    rtlSourceVisible,
    cocotbLogPath,
    rtlStemsPath,
    leftPaneSize,
    rightPaneSize,
    bottomPaneSize,
    Object.hashAll(expandedScopePaths),
    signalTreeSearchQuery,
    Object.hashAll(signalTreeSelectedRefs),
    signalTreeScrollOffset,
    Object.hashAll(
      translateFilterPaths.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAll(
      fsmAnnotations.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    stageWorkspace,
    activeThemeName,
    Object.hashAll(
      extensions.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAll(decoders),
    Object.hashAll(annotations),
    Object.hashAll(annotationLayers),
    annotationsVisible,
  ]);

  @override
  String toString() =>
      'SessionState('
      'sourceFilePath: $sourceFilePath, '
      'signals: ${signalGroup.signalCount}, '
      'ticksPerPixel: $ticksPerPixel)';

  static bool _mapsEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _setsEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  static bool _fsmAnnotationsEqual(
    Map<String, FsmAnnotation> a,
    Map<String, FsmAnnotation> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  // Shallow per-key equality. Pro codec payloads round-trip through JSON,
  // so reference equality of nested maps/lists isn't preserved and a full
  // structural compare would inflate the model's equality contract beyond
  // what the snapshot/restore round-trip actually depends on.
  static bool _extensionsEqual(
    Map<String, Object?> a,
    Map<String, Object?> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _annotationsEqual(List<Annotation> a, List<Annotation> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _listEquals(List<AnnotationLayer> a, List<AnnotationLayer> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _decodersEqual(
    List<PersistedDecoder> a,
    List<PersistedDecoder> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// Sentinel for distinguishing "not provided" from explicit null in copyWith.
const _unset = Object();
