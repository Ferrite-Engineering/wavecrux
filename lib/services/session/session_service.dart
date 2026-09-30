// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/fsm_annotation.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/domain/models/persisted_decoder.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';

/// Current `.wavecrux` JSON schema version.
///
/// Increment this constant for breaking changes. [SessionService._fromJson]
/// reads this field and can branch on it to migrate older files.
///
/// **Version history:**
/// - `1` — initial format (signals, cursors, markers, view, panels,
///   translateFilters, stage workspace, activeTheme).
/// - `2` — adds the reserved top-level `extensions` map.
///   Each entry is owned by a Pro-side codec registered through
///   `extraSessionPayloadCodecsProvider`. The map is the designed
///   forward-compat surface: any per-feature payload added in a later
///   build lands here, where the preserve-unknown invariant survives a
///   round-trip on this build.
/// v3 (session restore parity): adds bottom-pane content selection
///   (`panels.cocotbLogPanel`/`rtlSource` + their source paths), pane
///   geometry (`panels.sizes`), and the signal-tree browser state
///   (`signalTree`: expanded scopes, search query, selection, scroll). All are
///   lenient-defaulted on read, so a v1/v2 document loads unchanged.
/// - `4` — adds the top-level `annotations` list: user-authored
///   balloons, arrows and time bands anchored to `(tick, signalPath)`. Purely
///   additive and omitted when empty, so a v1–v3 document loads with no
///   annotations and re-saves byte-stable. Annotations are **open-core state**
///   and therefore live on the document proper rather than in `extensions`,
///   which is the Pro-overlay payload seam — a note written by an open-core
///   build must be readable by one.
const _kCurrentVersion = 4;

/// Serializes and deserializes [SessionState] to/from `.wavecrux` JSON files.
///
/// Files are human-readable, pretty-printed JSON. A [_kCurrentVersion] field
/// in the top-level object enables future schema migrations.
///
/// ### JSON structure
/// ```json
/// {
///   "version": 2,
///   // Absolute, or relative to this .wavecrux file's own directory
///   // (relative paths are resolved on load — see [loadSession]).
///   "sourceFilePath": "/path/to/dump.vcd",
///   "signals": [ ... ],
///   "cursor":  { "primary": 1000, "secondary": null },
///   "markers": { "a": 500, "b": 1500 },
///   "view":    { "ticksPerPixel": 1.5, "panOffsetTicks": 0.0 },
///   "panels":  { "signalTree": true, "valueColumn": true, "transactionView": false, "stageView": false },
///   "translateFilters": { "top.state": "/path/to/filter.txt" },
///   "stage":   { "activePanelId": "stagePanel_0", "panels": [ ... ] },
///   "activeTheme": "wavecrux-dark",
///   "decoders": [
///     { "decoderId": "spi", "instanceNumber": 1, "config": { "bindings": { ... }, "parameters": { ... } } }
///   ],
///   "extensions": { "pro.sva": { "logPath": "/abs/run.log" }, "pro.debug_advisor": [ ... ] }
/// }
/// ```
///
/// ### Forward-compatibility policy
///
/// The version bump from `1` to `2` is purely additive — the
/// `extensions` map's preserve-unknown contract handles all subsequent
/// per-feature payloads. SessionService therefore reads any
/// `version >= 1` document silently:
///
/// - **Older (`version == 1`)** — missing `extensions` is treated as
///   empty; everything else is already optional.
/// - **Same (`version == 2`)** — current format.
/// - **Newer (`version > _kCurrentVersion`)** — read in lenient mode.
///   Known top-level fields parse as today; the `extensions` map
///   round-trips verbatim so any new per-feature payload the newer
///   build added survives an open + re-save on this build. Unknown
///   *top-level* fields (added by a future schema bump that was NOT
///   funneled through `extensions`) are dropped on re-save — a future
///   breaking change of that shape would need its own dedicated
///   migration branch added here.
///
/// **Decision:** option (a) silently
/// preserve over option (b) read-only banner. The codec seam is built
/// specifically so a slightly-older build can carry a newer build's
/// per-feature payloads forward without surfacing UX. A read-only
/// banner would have no concrete user action attached during the beta
/// (we ship the same `_kCurrentVersion` to all installs in a release)
/// and would alarm users who legitimately roundtrip between current
/// and pre-release builds. When a future breaking top-level change
/// arrives, that change introduces its own branch here and decides
/// whether to surface UX — not the seam's own version bump.
class SessionService {
  const SessionService();

  /// File extension used by every WaveCrux session file. Includes the
  /// dot so callers can compose paths or compare directly.
  static const String fileExtension = '.wavecrux';

  /// The schema version this build stamps onto every document it writes.
  ///
  /// Public so tests can assert "re-stamped at the current version" rather
  /// than a literal that has to be chased through the suite on every additive
  /// bump — the churn that a v3→v4 bump would otherwise cause in three
  /// unrelated round-trip tests.
  static const int currentSchemaVersion = _kCurrentVersion;

  /// True when [path] points at a session file (case-insensitive
  /// match on [fileExtension]). Used by file-open call sites to
  /// dispatch a picked / recent path to the session loader instead
  /// of the waveform loader. Does not check that the file actually
  /// exists or parses — that's the loader's responsibility.
  static bool isSessionFilePath(String path) =>
      path.toLowerCase().endsWith(fileExtension);

  /// Signal-entry count at or above which serialization runs on a worker
  /// isolate and drops pretty-printing. A gate-level "Add All in Scope"
  /// session can hold 1M+ entries: building + indent-encoding that on the
  /// UI thread stalls it for seconds every time the 2 s autosave debounce
  /// fires, and the indented output roughly doubles the file size. Normal
  /// sessions stay pretty-printed (they are documented as human-readable).
  static const int largeSessionEntryThreshold = 50000;

  /// Writes [state] as JSON to [filePath] — pretty-printed for normal
  /// sessions, compact for very large ones (see
  /// [largeSessionEntryThreshold]).
  ///
  /// For large sessions the entire map-build + encode runs on a short-lived
  /// worker isolate ([Isolate.run]); the UI thread pays only the one-time
  /// object-graph copy into the isolate instead of the full serialization.
  /// [SessionState] is plain immutable data, so it is isolate-sendable.
  ///
  /// Creates parent directories and overwrites any existing file.
  /// Throws [SessionSaveException] on I/O failure.
  Future<void> saveSession(SessionState state, String filePath) async {
    final isLarge = state.signalGroup.signalCount >= largeSessionEntryThreshold;
    final encoded = isLarge
        ? await Isolate.run(() => jsonEncode(_toJson(state)))
        : encodeDocument(state);
    try {
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(encoded, flush: true);
    } on IOException catch (e) {
      throw SessionSaveException(filePath, e.toString());
    }
  }

  /// Renders [state] as the `.wavecrux` document text without touching disk.
  ///
  /// Exists for the share bundle, which needs the document as a ZIP entry
  /// rather than a file. Public and shared with [saveSession] on purpose:
  /// serializing a session in two places is how the pack's copy comes to be
  /// missing a field the on-disk format gained.
  ///
  /// Always pretty-printed. The large-session compact path in [saveSession] is
  /// an autosave-latency concession, and a pack is neither autosaved nor
  /// written from a gate-level session.
  String encodeDocument(SessionState state) =>
      const JsonEncoder.withIndent('  ').convert(_toJson(state));

  /// Reads a `.wavecrux` JSON file from [filePath] and returns a
  /// [SessionState].
  ///
  /// Missing optional fields use their default values (forward compatibility).
  /// Throws [SessionLoadException] on I/O or parse failure.
  /// Parses a `.wavecrux` document from [encoded], with no filesystem involved.
  ///
  /// The inverse of [encodeDocument], and split out of [loadSession] for the
  /// same reason [encodeDocument] was split out of `saveSession`: a pack
  /// carries the document as a ZIP entry, and on web there is no file to read
  /// it from. Parsing it a second way is how the pack's copy comes to disagree
  /// with the on-disk format about a field.
  ///
  /// [diagnosticName] only labels failures — a file path, or something like
  /// `session.wavecrux (in pack)`. **No path resolution happens here**: a
  /// relative `sourceFilePath` is returned exactly as written, because what it
  /// should resolve against is the caller's business — a directory on disk for
  /// [loadSession], a sibling ZIP entry for a pack.
  SessionState decodeDocument(
    String encoded, {
    required String diagnosticName,
  }) {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(encoded) as Object?;
      if (decoded is! Map<String, dynamic>) {
        throw SessionLoadException(
          diagnosticName,
          'Expected a JSON object at root',
        );
      }
      json = decoded;
    } on FormatException catch (e) {
      throw SessionLoadException(diagnosticName, 'Invalid JSON: ${e.message}');
    }

    try {
      return _fromJson(json);
    } on SessionLoadException {
      rethrow;
    } on Object catch (e) {
      throw SessionLoadException(
        diagnosticName,
        'Failed to parse session: $e',
      );
    }
  }

  Future<SessionState> loadSession(String filePath) async {
    String encoded;
    try {
      encoded = await File(filePath).readAsString();
    } on IOException catch (e) {
      throw SessionLoadException(filePath, e.toString());
    }

    final state = decodeDocument(encoded, diagnosticName: filePath);

    // Resolve a relative `sourceFilePath` against the session file's own
    // directory, so a `.wavecrux` committed or shared next to its waveform
    // (a demo pack, an EDU reference session, a session emailed alongside its
    // dump) opens regardless of the process working directory. A
    // normally-saved session stores the absolute path it was opened from,
    // which `p.isRelative` leaves untouched.
    final source = state.sourceFilePath;
    if (source != null && source.isNotEmpty && p.isRelative(source)) {
      return state.copyWith(
        sourceFilePath: p.normalize(p.join(p.dirname(filePath), source)),
      );
    }
    return state;
  }

  // ── serialization ────────────────────────────────────────────────────────────

  static Map<String, dynamic> _toJson(SessionState state) => {
    'version': _kCurrentVersion,
    if (state.sourceFilePath != null) 'sourceFilePath': state.sourceFilePath,
    'signals': _entriesToJson(state.signalGroup.entries),
    'cursor': {
      'primary': state.cursorState.primaryCursorTime,
      'secondary': state.cursorState.secondaryCursorTime,
    },
    'markers': {
      for (final e in state.markerState.getAllMarkers()) e.key: e.value,
    },
    'view': {
      'ticksPerPixel': state.ticksPerPixel,
      'panOffsetTicks': state.panOffsetTicks,
      'scrollOffset': state.scrollOffset,
    },
    'panels': {
      'signalTree': state.signalTreeVisible,
      'valueColumn': state.valueColumnVisible,
      'transactionView': state.transactionViewVisible,
      'stageView': state.stageViewVisible,
      'statisticsStrip': state.statisticsStripVisible,
      'cocotbLogPanel': state.cocotbLogPanelVisible,
      // Omitted when null so a session that never touched the panel stays
      // byte-stable and keeps the automatic rule on reload.
      if (state.annotationsPanelVisible != null)
        'annotationsPanel': state.annotationsPanelVisible,
      'rtlSource': state.rtlSourceVisible,
      // Omitted when true so pre-annotation sessions stay byte-stable.
      if (!state.annotationsVisible) 'annotationsVisible': false,
      // Omitted when null so pre-dock sessions round-trip byte-stable.
      if (state.bottomDockTab != null) 'bottomDockTab': state.bottomDockTab,
      if (state.rightDockTab != null) 'rightDockTab': state.rightDockTab,
      if (state.dockPlacements.isNotEmpty)
        'dockPlacements': state.dockPlacements,
      if (state.cocotbLogPath != null) 'cocotbLogPath': state.cocotbLogPath,
      if (state.rtlStemsPath != null) 'rtlStemsPath': state.rtlStemsPath,
      // Pane geometry (logical pixels). Each key is omitted when null so a
      // never-resized session round-trips without spurious size keys and
      // falls back to the layout defaults.
      if (state.leftPaneSize != null ||
          state.rightPaneSize != null ||
          state.bottomPaneSize != null)
        'sizes': {
          if (state.leftPaneSize != null) 'left': state.leftPaneSize,
          if (state.rightPaneSize != null) 'right': state.rightPaneSize,
          if (state.bottomPaneSize != null) 'bottom': state.bottomPaneSize,
        },
    },
    // Signal-tree browser state. Omit when entirely at defaults so v1/v2
    // sessions round-trip byte-stable.
    if (state.expandedScopePaths.isNotEmpty ||
        state.signalTreeSearchQuery.isNotEmpty ||
        state.signalTreeSelectedRefs.isNotEmpty ||
        state.signalTreeScrollOffset != 0.0)
      'signalTreeState': {
        if (state.expandedScopePaths.isNotEmpty)
          'expanded': state.expandedScopePaths.toList(),
        if (state.signalTreeSearchQuery.isNotEmpty)
          'search': state.signalTreeSearchQuery,
        if (state.signalTreeSelectedRefs.isNotEmpty)
          'selected': state.signalTreeSelectedRefs.toList(),
        if (state.signalTreeScrollOffset != 0.0)
          'scroll': state.signalTreeScrollOffset,
      },
    'translateFilters': state.translateFilterPaths,
    // User-supplied FSM state-name annotations, keyed by signalRef. Omit
    // when empty so sessions without any FSM annotation round-trip
    // byte-stable.
    if (state.fsmAnnotations.isNotEmpty)
      'fsmAnnotations': {
        for (final e in state.fsmAnnotations.entries) e.key: e.value.toJson(),
      },
    'stage': _stageWorkspaceToJson(state.stageWorkspace),
    'activeTheme': state.activeThemeName,
    // Persisted decoder instances. Omit when empty so
    // pre-decoder sessions round-trip byte-stable.
    if (state.decoders.isNotEmpty)
      'decoders': state.decoders.map((d) => d.toJson()).toList(),
    // Waveform annotations. Omit when empty so pre-annotation
    // sessions round-trip byte-stable, exactly as `renderAsAnalog` and the
    // decoder list do.
    if (state.annotations.isNotEmpty)
      'annotations': state.annotations.map((a) => a.toJson()).toList(),
    // The adopted-layer registry. Additive on top of v4 —
    // annotations already carried `layerId`, so a v4 document with layered
    // annotations and no registry degrades to unnamed groups rather than to
    // lost notes, and the version does not move.
    if (state.annotationLayers.isNotEmpty)
      'annotationLayers': state.annotationLayers
          .map((l) => l.toJson())
          .toList(),
    // Pro-side per-tab payloads. Omit when empty so v1 sessions that
    // never gained an entry round-trip byte-stable. Unknown-namespace
    // entries (no codec registered on this build) ride through here
    // untouched — see SessionExtensionCodec for the contract.
    if (state.extensions.isNotEmpty) 'extensions': state.extensions,
  };

  static Map<String, dynamic> _stageWorkspaceToJson(
    StageWorkspaceState workspace,
  ) => {
    if (workspace.activePanelId != null)
      'activePanelId': workspace.activePanelId,
    'panels': workspace.panels.map(_stagePanelToJson).toList(),
  };

  static Map<String, dynamic> _stagePanelToJson(StagePanelConfig panel) => {
    'id': panel.id,
    'name': panel.name,
    'instances': panel.instances.map(_stageInstanceToJson).toList(),
  };

  static Map<String, dynamic> _stageInstanceToJson(StageInstance instance) => {
    'id': instance.id,
    'widgetId': instance.widgetId,
    'bindings': {
      for (final e in instance.signalBindings.entries)
        e.key: {
          'ref': e.value.signalRef,
          if (e.value.bitIndex != null) 'bit': e.value.bitIndex,
          // Slice width — only emitted for multi-bit slice bindings
          // (e.g. DE10-Nano `adc_ch[95:0]` 96-bit bus → 8 ADC slots
          // at 12 bits each). Omitted when null OR when the slice is
          // semantically a single bit (`bitWidth == 1`), so existing
          // single-bit fan-out sessions round-trip byte-stable.
          if (e.value.bitWidth != null && e.value.bitWidth != 1)
            'bitWidth': e.value.bitWidth,
        },
    },
    // Per-instance config map. Omit when empty so existing pre-config
    // session files round-trip byte-stable (no spurious empty key).
    if (instance.configuration.isNotEmpty)
      'configuration': Map<String, Object?>.from(instance.configuration),
    'x': instance.x,
    'y': instance.y,
    'width': instance.width,
    'height': instance.height,
    if (instance.label != null) 'label': instance.label,
  };

  static List<Map<String, dynamic>> _entriesToJson(
    List<SignalEntry> entries,
  ) => entries.map(_entryToJson).toList();

  static Map<String, dynamic> _entryToJson(SignalEntry entry) {
    switch (entry.kind) {
      case SignalEntryKind.signal:
        return {
          'kind': 'signal',
          'id': entry.id,
          'ref': entry.signalRef,
          // Canonical hierarchical path — survives cross-backend session
          // restore (FFI vs. pure-Dart parser). `ref` is kept alongside as
          // a hint / fast path; on load the path is the authoritative
          // identifier and `ref` is re-resolved via the active backend.
          // Omit when null so legacy entries written before the path was
          // tracked round-trip byte-stable.
          if (entry.signalPath != null) 'path': entry.signalPath,
          'name': entry.displayName,
          if (entry.argbColor != null) 'color': entry.argbColor,
          'format': entry.format.name,
          'height': entry.laneHeight,
          // Per-signal translator config — omit when null so existing
          // sessions round-trip byte-stable.
          if (entry.translatorConfig != null)
            'config': Map<String, Object?>.from(entry.translatorConfig!),
          // Analog rendering toggle — omitted when false for the same
          // byte-stability reason, so a session written before this feature
          // reloads unchanged.
          if (entry.renderAsAnalog) 'analog': true,
        };
      case SignalEntryKind.group:
        return {
          'kind': 'group',
          'name': entry.groupName,
          'collapsed': entry.collapsed,
          'children': _entriesToJson(entry.children),
        };
      case SignalEntryKind.separator:
        return {'kind': 'separator'};
      case SignalEntryKind.comment:
        return {'kind': 'comment', 'text': entry.text};
    }
  }

  // ── deserialization ──────────────────────────────────────────────────────────

  static SessionState _fromJson(Map<String, dynamic> json) {
    // Version field present since v1. Forward-compat policy: read
    // anything >= 1 silently. The schema header is documented in the
    // class doc-comment ("Forward-compatibility policy").
    // ignore: unused_local_variable
    final version = (json['version'] as int?) ?? 1;

    final signalsList =
        (json['signals'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    final cursorJson = (json['cursor'] as Map<String, dynamic>?) ?? {};
    final markersJson = (json['markers'] as Map<String, dynamic>?) ?? {};
    final viewJson = (json['view'] as Map<String, dynamic>?) ?? {};
    final panelsJson = (json['panels'] as Map<String, dynamic>?) ?? {};
    final filtersJson =
        (json['translateFilters'] as Map<String, dynamic>?) ?? {};

    final stageJson = (json['stage'] as Map<String, dynamic>?) ?? {};
    final sizesJson = (panelsJson['sizes'] as Map<String, dynamic>?) ?? {};
    final signalTreeJson =
        (json['signalTreeState'] as Map<String, dynamic>?) ?? {};

    return SessionState(
      sourceFilePath: json['sourceFilePath'] as String?,
      signalGroup: SignalGroup(
        entries: signalsList.map(_entryFromJson).toList(),
      ),
      cursorState: CursorState(
        primaryCursorTime: cursorJson['primary'] as int?,
        secondaryCursorTime: cursorJson['secondary'] as int?,
      ),
      markerState: MarkerState(
        markers: Map.unmodifiable({
          for (final e in markersJson.entries)
            if (e.value is int) e.key: e.value as int,
        }),
      ),
      ticksPerPixel: (viewJson['ticksPerPixel'] as num?)?.toDouble() ?? 1.0,
      panOffsetTicks: (viewJson['panOffsetTicks'] as num?)?.toDouble() ?? 0.0,
      scrollOffset: (viewJson['scrollOffset'] as num?)?.toDouble() ?? 0.0,
      signalTreeVisible: (panelsJson['signalTree'] as bool?) ?? true,
      valueColumnVisible: (panelsJson['valueColumn'] as bool?) ?? true,
      transactionViewVisible: (panelsJson['transactionView'] as bool?) ?? false,
      stageViewVisible: (panelsJson['stageView'] as bool?) ?? false,
      statisticsStripVisible: (panelsJson['statisticsStrip'] as bool?) ?? false,
      cocotbLogPanelVisible: (panelsJson['cocotbLogPanel'] as bool?) ?? false,
      annotationsPanelVisible: panelsJson['annotationsPanel'] as bool?,
      rtlSourceVisible: (panelsJson['rtlSource'] as bool?) ?? false,
      bottomDockTab: panelsJson['bottomDockTab'] as String?,
      rightDockTab: panelsJson['rightDockTab'] as String?,
      dockPlacements: {
        for (final e
            in ((panelsJson['dockPlacements'] as Map<String, dynamic>?) ??
                    const <String, dynamic>{})
                .entries)
          if (e.value is String) e.key: e.value as String,
      },
      cocotbLogPath: panelsJson['cocotbLogPath'] as String?,
      rtlStemsPath: panelsJson['rtlStemsPath'] as String?,
      leftPaneSize: (sizesJson['left'] as num?)?.toDouble(),
      rightPaneSize: (sizesJson['right'] as num?)?.toDouble(),
      bottomPaneSize: (sizesJson['bottom'] as num?)?.toDouble(),
      expandedScopePaths: {
        for (final p
            in (signalTreeJson['expanded'] as List<dynamic>?) ?? const [])
          if (p is String) p,
      },
      signalTreeSearchQuery: (signalTreeJson['search'] as String?) ?? '',
      signalTreeSelectedRefs: {
        for (final r
            in (signalTreeJson['selected'] as List<dynamic>?) ?? const [])
          if (r is String) r,
      },
      signalTreeScrollOffset:
          (signalTreeJson['scroll'] as num?)?.toDouble() ?? 0.0,
      translateFilterPaths: {
        for (final e in filtersJson.entries)
          if (e.value is String) e.key: e.value as String,
      },
      fsmAnnotations: _fsmAnnotationsFromJson(json['fsmAnnotations']),
      stageWorkspace: _stageWorkspaceFromJson(stageJson),
      activeThemeName: (json['activeTheme'] as String?) ?? 'wavecrux-dark',
      extensions: _extensionsFromJson(json['extensions']),
      decoders: _decodersFromJson(json['decoders']),
      annotations: _annotationsFromJson(json['annotations']),
      annotationLayers: _annotationLayersFromJson(json['annotationLayers']),
      annotationsVisible: (panelsJson['annotationsVisible'] as bool?) ?? true,
    );
  }

  // Pull the optional `annotations` list (schema v4). Missing in v1–v3
  // sessions and in any session with no annotations at snapshot time.
  //
  // Per-entry failures are DROPPED, not fatal: `Annotation.fromJson` returns
  // null for an unusable anchor, an unknown shape (a document written by a
  // newer build), or a missing id. One bad annotation must never cost the user
  // the rest of the session — the same tolerance the decoder and FSM lists
  // already apply.
  static List<Annotation> _annotationsFromJson(Object? raw) {
    if (raw is! List) return const <Annotation>[];
    final out = <Annotation>[];
    for (final entry in raw) {
      final parsed = Annotation.fromJson(entry);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  // Pull the optional `annotationLayers` registry. Absent in every
  // document written before layers existed, and in any session that never
  // adopted one. Per-entry failures are dropped for the same reason
  // annotations' are: one malformed group must not cost the user the rest.
  static List<AnnotationLayer> _annotationLayersFromJson(Object? raw) {
    if (raw is! List) return const <AnnotationLayer>[];
    final out = <AnnotationLayer>[];
    for (final entry in raw) {
      final parsed = AnnotationLayer.fromJson(entry);
      if (parsed != null) out.add(parsed);
    }
    return out;
  }

  // Pull the optional `decoders` list. Missing in pre-decoder
  // sessions, missing in any session that had no active decoders at
  // snapshot time. Non-Map entries are skipped silently — a per-entry
  // parse failure must not abort the rest of the session restore.
  static List<PersistedDecoder> _decodersFromJson(Object? raw) {
    if (raw is! List) return const <PersistedDecoder>[];
    final out = <PersistedDecoder>[];
    for (final entry in raw) {
      if (entry is Map) {
        out.add(PersistedDecoder.fromJson(entry.cast<String, Object?>()));
      }
    }
    return out;
  }

  // Pull the reserved `extensions` map off the document. Missing in v1
  // sessions, missing whenever no codec has contributed a payload. We
  // keep every entry (registered or not) so the preserve-unknown
  // invariant can fire on the next save: a `"pro.unknown"` payload
  // written by a build that ships a codec for it survives a roundtrip
  // through a build that does not.
  static Map<String, Object?> _extensionsFromJson(Object? raw) {
    if (raw is! Map) return const <String, Object?>{};
    return <String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  // Pull the optional `fsmAnnotations` map off the document. Missing in
  // sessions written before FSM-annotation persistence and in any session
  // that had no annotations at snapshot time. Non-Map entries (or a non-Map
  // root) are skipped silently so a partially-corrupt entry never aborts the
  // rest of the session restore. The map key is the authoritative signalRef.
  static Map<String, FsmAnnotation> _fsmAnnotationsFromJson(Object? raw) {
    if (raw is! Map) return const <String, FsmAnnotation>{};
    final out = <String, FsmAnnotation>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is Map) {
        out[key] = FsmAnnotation.fromJson(value.cast<String, dynamic>());
      }
    }
    return out;
  }

  static StageWorkspaceState _stageWorkspaceFromJson(
    Map<String, dynamic> json,
  ) {
    final panelsList =
        (json['panels'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    return StageWorkspaceState(
      panels: panelsList.map(_stagePanelFromJson).toList(),
      activePanelId: json['activePanelId'] as String?,
    );
  }

  static StagePanelConfig _stagePanelFromJson(Map<String, dynamic> json) {
    final instancesList =
        (json['instances'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
        [];
    return StagePanelConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      instances: instancesList.map(_stageInstanceFromJson).toList(),
    );
  }

  static StageInstance _stageInstanceFromJson(Map<String, dynamic> json) {
    final bindingsRaw = (json['bindings'] as Map<String, dynamic>?) ?? {};
    // Forward-compatible: pre-config-field session files have no
    // 'configuration' key; we treat that as the empty map and the
    // widget's parseConfig falls back to schema defaults. Unknown keys
    // (added by a newer version) round-trip verbatim through the map.
    final configRaw =
        (json['configuration'] as Map<String, dynamic>?) ?? const {};
    return StageInstance(
      id: json['id'] as String? ?? '',
      widgetId: json['widgetId'] as String? ?? '',
      signalBindings: {
        for (final e in bindingsRaw.entries)
          if (e.value is Map<String, dynamic>)
            if ((e.value as Map<String, dynamic>)['ref'] is String)
              e.key: StageSignalBinding(
                signalRef: (e.value as Map<String, dynamic>)['ref'] as String,
                bitIndex: (e.value as Map<String, dynamic>)['bit'] as int?,
                // Slice width is only present in newer sessions that
                // exercised multi-bit fan-out (DE10-Nano ADC, etc.).
                // Older sessions omit the field entirely; that's the
                // single-bit / whole-signal case.
                bitWidth: (e.value as Map<String, dynamic>)['bitWidth'] as int?,
              ),
      },
      configuration: Map<String, Object?>.from(configRaw),
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      width: (json['width'] as num?)?.toDouble() ?? 160.0,
      height: (json['height'] as num?)?.toDouble() ?? 100.0,
      label: json['label'] as String?,
    );
  }

  static SignalEntry _entryFromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String? ?? 'signal';
    switch (kind) {
      case 'signal':
        final configRaw = json['config'] as Map<String, dynamic>?;
        return SignalEntry.signal(
          id: json['id'] as String?,
          signalRef: json['ref'] as String? ?? '',
          signalPath: json['path'] as String?,
          displayName: json['name'] as String? ?? '',
          argbColor: json['color'] as int?,
          format: _displayFormatFromName(json['format'] as String?),
          laneHeight: (json['height'] as num?)?.toDouble() ?? 30.0,
          translatorConfig: configRaw != null
              ? Map<String, Object?>.from(configRaw)
              : null,
          renderAsAnalog: json['analog'] as bool? ?? false,
        );
      case 'group':
        final childrenJson =
            (json['children'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        return SignalEntry.group(
          groupName: json['name'] as String? ?? 'Group',
          collapsed: (json['collapsed'] as bool?) ?? false,
          children: childrenJson.map(_entryFromJson).toList(),
        );
      case 'separator':
        return const SignalEntry.separator();
      case 'comment':
        return SignalEntry.comment(text: json['text'] as String? ?? '');
      default:
        // Unknown kind — degrade gracefully for forward compatibility.
        return const SignalEntry.separator();
    }
  }

  static DisplayFormat _displayFormatFromName(String? name) {
    if (name == null) return DisplayFormat.hexadecimal;
    for (final f in DisplayFormat.values) {
      if (f.name == name) return f;
    }
    return DisplayFormat.hexadecimal;
  }
}

// ── exceptions ────────────────────────────────────────────────────────────────

/// Thrown when [SessionService.saveSession] fails.
class SessionSaveException implements Exception {
  const SessionSaveException(this.filePath, this.reason);

  final String filePath;
  final String reason;

  @override
  String toString() => 'SessionSaveException($filePath): $reason';
}

/// Thrown when [SessionService.loadSession] fails.
class SessionLoadException implements Exception {
  const SessionLoadException(this.filePath, this.reason);

  final String filePath;
  final String reason;

  @override
  String toString() => 'SessionLoadException($filePath): $reason';
}
