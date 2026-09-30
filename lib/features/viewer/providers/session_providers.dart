// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:typed_data';

import 'package:crux_async/crux_async.dart';
import 'package:crux_audit/crux_audit.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/annotations/providers/annotation_layers_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/rtl_source/providers/rtl_source_provider.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/translate_filter_provider.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/recent_files_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/session/session_extension_codec.dart';
import 'package:wavecrux/services/session/session_service.dart';

part 'session_providers.g.dart';

/// Captures silent session auto-save failures into the issue-reporter buffer.
final _log = Logger('wavecrux.session');

// ── SessionService provider ───────────────────────────────────────────────────

/// Provides the [SessionService] instance.
///
/// Override in tests to inject a mock or a service backed by a temp directory.
@riverpod
SessionService sessionService(Ref ref) => const SessionService();

// ── SessionNotifier ───────────────────────────────────────────────────────────

/// Manages the current session file path and provides save/load actions.
///
/// State is the absolute path of the currently open `.wavecrux` session file,
/// or null when the viewer is running without a saved session.
@Riverpod(keepAlive: true)
class SessionNotifier extends _$SessionNotifier {
  @override
  String? build() => null;

  /// Preserve-unknown base for the reserved `.wavecrux` `extensions` map.
  ///
  /// Set on [_restore] from the loaded document and used as the capture base
  /// in [_snapshot] so that (a) namespaces this build does not understand
  /// survive a load → save cycle (the preserve-unknown invariant),
  /// and (b) registered Pro codecs (`pro.sva`, …) overlay their freshly
  /// captured payload on top via [SessionExtensions.capture].
  Map<String, Object?> _lastLoadedExtensions = const <String, Object?>{};

  /// Serializes the current viewer state and writes it to [filePath].
  ///
  /// Updates [state] to [filePath] and adds it to the recent files list.
  /// Throws [SessionSaveException] on failure.
  Future<void> saveToPath(String filePath) async {
    final session = _snapshot();
    // Read before the await: a `Ref` is invalid across an async gap.
    final audit = ref.read(cruxAuditRecorderProvider);
    await ref.read(sessionServiceProvider).saveSession(session, filePath);
    state = filePath;
    await ref.read(recentFilesProvider.notifier).addFile(filePath);
    // Recorded AFTER the write succeeds. `saveSession` throws
    // `SessionSaveException` on failure, so an event here means the file is on
    // disk — an audit line for a save that did not happen is worse than no
    // line, because it is the one an investigation would trust.
    audit.record(
      WaveCruxAuditKinds.sessionSaved,
      // The FILE NAME, never the path. An audit payload carries no filesystem
      // path (`crux_license`'s `PolicyReportDestination` states the suite rule,
      // and this log is forwarded off the machine by a shipper), and a session
      // is saved wherever the user likes — a home directory, a customer's
      // share. The name is what an investigation needs; the directory is what
      // it must not export.
      payload: <String, Object?>{
        'file': p.basename(filePath),
        'trigger': 'user',
      },
    );
  }

  /// Saves to the current session path. No-op when no path is set.
  Future<void> save() async {
    final path = state;
    if (path != null) await saveToPath(path);
  }

  /// Loads a session from [filePath] and restores all viewer state.
  ///
  /// Opens the referenced waveform file (if any), restores signals, cursors,
  /// markers, panel visibility, and zoom/pan state. Updates [state] to
  /// [filePath] and adds it to the recent files list.
  /// Throws [SessionLoadException] on failure.
  Future<void> loadFromPath(String filePath) async {
    final session = await ref
        .read(sessionServiceProvider)
        .loadSession(filePath);
    await _restore(session);
    state = filePath;
    await ref.read(recentFilesProvider.notifier).addFile(filePath);
  }

  /// Snapshots the current viewer state into a [SessionState] without
  /// writing to disk. Used by in-process state transfers — e.g. the
  /// "Duplicate Tab" handler captures the source tab's signal arrangement,
  /// cursors, markers, zoom, etc. and replays them into the new tab's
  /// container via [restoreFromState].
  SessionState snapshot() => _snapshot();

  /// Restores [session] into this tab's providers without first
  /// serializing through a file. Used by in-process state transfers — see
  /// [snapshot]. Does not update [SessionNotifier.state] (the tab's
  /// session file path is unchanged); does not touch the recent files
  /// list.
  Future<void> restoreFromState(SessionState session) => _restore(session);

  /// Restores [session] with its waveform coming from [waveformBytes] rather
  /// than from a path.
  ///
  /// The web pack path. A `.wavecruxpack` carries its own dump as a ZIP entry,
  /// and the session inside it names that entry relatively — which resolves to
  /// a real file once extracted on desktop, and to nothing at all in a browser,
  /// where there is no filesystem to extract into.
  ///
  /// Deliberately the *same* [_restore] as every other route rather than a
  /// second one that happens to do similar things: signal-ref re-resolution,
  /// decoder restore, marker and annotation replay are all subtle enough that
  /// a parallel implementation would drift, and the drift would show up as a
  /// shared view that looks slightly wrong only in the browser.
  Future<void> restoreFromBytes({
    required SessionState session,
    required Uint8List waveformBytes,
    required String displayName,
  }) => _restore(
    session,
    openSource: () => ref
        .read(waveformSourceProvider.notifier)
        .openFromBytes(waveformBytes, displayName),
  );

  /// Reloads the current waveform file while preserving the full viewer state.
  ///
  /// Captures a snapshot of all state (signals, cursors, markers, zoom/pan,
  /// panel visibility), reopens the file, then restores the snapshot. Used by
  /// the auto-reload flow when the file changes on disk.
  ///
  /// No-op when no waveform file is loaded. Throws if [openFile] fails.
  Future<void> reloadCurrentFile() async {
    final snapshot = _snapshot();
    if (snapshot.sourceFilePath == null) return;

    // Stage zoom/pan so the next initialize() call picks it up.
    ref
        .read(timeMapperProvider.notifier)
        .setPendingZoomPan(
          ticksPerPixel: snapshot.ticksPerPixel,
          panOffsetTicks: snapshot.panOffsetTicks,
        );

    // Reopen the file — this triggers TimeMapper.initialize via the canvas.
    // Same `preserveDecoders: true` seam as _restore so the
    // user's active decoders survive an auto-reload of the same file
    // changing on disk; without it the reload-clear flicker would empty
    // the transaction table mid-reload.
    await ref
        .read(waveformSourceProvider.notifier)
        .openFile(snapshot.sourceFilePath!, preserveDecoders: true);

    // Restore the remaining viewer state.
    ref
        .read(signalGroupsProvider.notifier)
        .restoreFromSession(snapshot.signalGroup);

    // Re-resolve stale signalRefs against the freshly opened backend (the
    // same cross-backend defense as in [_restore]). Idempotent on same-
    // backend reload — when refs already match `pathToRef` it is a no-op.
    final reloadedSource = ref.read(waveformSourceProvider).value;
    if (reloadedSource != null) {
      ref
          .read(signalGroupsProvider.notifier)
          .reresolveSignalRefs(reloadedSource);
    }

    final cursorNotifier = ref.read(cursorStateProvider.notifier)..clearAll();
    final primary = snapshot.cursorState.primaryCursorTime;
    final secondary = snapshot.cursorState.secondaryCursorTime;
    if (primary != null) cursorNotifier.placePrimary(primary);
    if (secondary != null) cursorNotifier.placeSecondary(secondary);

    for (final entry in snapshot.markerState.getAllMarkers()) {
      ref
          .read(markerStateProvider.notifier)
          .setMarker(
            entry.key,
            entry.value,
          );
    }

    ref.read(panelLayoutProvider.notifier)
      ..setSignalTreeVisible(visible: snapshot.signalTreeVisible)
      ..setValueColumnVisible(visible: snapshot.valueColumnVisible)
      ..setTransactionViewVisible(visible: snapshot.transactionViewVisible)
      ..setStageViewVisible(visible: snapshot.stageViewVisible)
      ..setStatisticsStripVisible(
        visible: snapshot.statisticsStripVisible,
      );
    final snapshotDockTab = snapshot.bottomDockTab;
    if (snapshotDockTab != null) {
      ref.read(panelLayoutProvider.notifier).setBottomDockTab(snapshotDockTab);
    }
    final snapshotRightTab = snapshot.rightDockTab;
    if (snapshotRightTab != null) {
      ref.read(panelLayoutProvider.notifier).setRightDockTab(snapshotRightTab);
    }
    if (snapshot.dockPlacements.isNotEmpty) {
      ref
          .read(panelLayoutProvider.notifier)
          .restoreDockPlacements(snapshot.dockPlacements);
    }

    ref
        .read(stageWorkspaceProvider.notifier)
        .restoreFromSession(snapshot.stageWorkspace);

    await ref
        .read(translateFilterProvider.notifier)
        .restoreFromSession(snapshot.translateFilterPaths);

    // Restore FSM state-name annotations (openFile clears them on the
    // fresh-file path, so re-apply the snapshot we took above).
    ref
        .read(fsmAnnotationProvider.notifier)
        .restoreFromSession(snapshot.fsmAnnotations);

    // Decoders survived the reload via `preserveDecoders:
    // true`; rerun decodeAll() so their transactions reflect the new
    // file contents instead of stale results computed against the
    // pre-reload waveform.
    if (reloadedSource != null) {
      final decoders = ref.read(activeDecodersProvider);
      if (decoders.isNotEmpty) {
        await ref.read(activeDecodersProvider.notifier).decodeAll();
      }
    }
  }

  // ── snapshot ─────────────────────────────────────────────────────────────────

  SessionState _snapshot() {
    final sourceFilePath = ref
        .read(waveformSourceProvider.notifier)
        .currentFilePath;
    final signalGroup = ref.read(signalGroupsProvider);
    final cursorState = ref.read(cursorStateProvider);
    final markerState = ref.read(markerStateProvider);
    final mapper = ref.read(timeMapperProvider);
    final panels = ref.read(panelLayoutProvider);
    final filterPaths = ref.read(translateFilterProvider.notifier).filterPaths;
    final fsmAnnotations = ref.read(fsmAnnotationProvider);
    final stageWorkspace = ref.read(stageWorkspaceProvider);
    final scrollOffset = ref.read(waveformScrollProvider);
    final decoders = ref.read(activeDecodersProvider.notifier).snapshot();
    final annotations = ref.read(annotationsProvider.notifier).snapshot();
    final annotationLayers = ref
        .read(annotationLayersProvider.notifier)
        .snapshot();
    final annotationsVisible = ref.read(annotationsVisibleProvider);
    // Bottom-pane content selection that re-derives from a file: the cocotb
    // log path and RTL stems path (re-loaded fail-soft on restore).
    final cocotbLogPath = ref.read(cocotbLogProvider)?.filePath;
    final rtlStemsPath = ref.read(rtlSourceProvider).stemsPath;
    // Signal-tree browser state.
    final expandedScopes = ref.read(expandedScopesProvider);
    final searchQuery = ref.read(signalSearchQueryProvider);
    final selectedRefs = ref.read(selectedVariablesProvider);
    final treeScroll = ref.read(signalTreeScrollProvider);
    // Capture every registered session-extension codec's payload, overlaid
    // on the preserve-unknown base so namespaces this build does not
    // understand ride through untouched. Open-core registers no
    // codecs (empty registry → empty map → `extensions` omitted from JSON);
    // the Pro overlay contributes `pro.sva` and friends.
    final extensions = SessionExtensions.capture(ref, _lastLoadedExtensions);

    return SessionState(
      sourceFilePath: sourceFilePath,
      signalGroup: signalGroup,
      cursorState: cursorState,
      markerState: markerState,
      ticksPerPixel: mapper.ticksPerPixel,
      panOffsetTicks: mapper.panOffsetTicks,
      scrollOffset: scrollOffset,
      signalTreeVisible: panels.signalTreeVisible,
      valueColumnVisible: panels.valueColumnVisible,
      transactionViewVisible: panels.transactionViewVisible,
      stageViewVisible: panels.stageViewVisible,
      bottomDockTab: panels.bottomDockTab,
      rightDockTab: panels.rightDockTab,
      dockPlacements: panels.dockPlacements,
      statisticsStripVisible: panels.statisticsStripVisible,
      cocotbLogPanelVisible: panels.cocotbLogPanelVisible,
      annotationsPanelVisible: panels.annotationsPanelVisible,
      rtlSourceVisible: panels.rtlSourceVisible,
      cocotbLogPath: cocotbLogPath,
      rtlStemsPath: rtlStemsPath,
      leftPaneSize: panels.leftPaneSize,
      rightPaneSize: panels.rightPaneSize,
      bottomPaneSize: panels.bottomPaneSize,
      expandedScopePaths: expandedScopes,
      signalTreeSearchQuery: searchQuery,
      signalTreeSelectedRefs: selectedRefs,
      signalTreeScrollOffset: treeScroll,
      translateFilterPaths: filterPaths,
      fsmAnnotations: fsmAnnotations,
      stageWorkspace: stageWorkspace,
      decoders: decoders,
      annotations: annotations,
      annotationLayers: annotationLayers,
      annotationsVisible: annotationsVisible,
      extensions: extensions,
    );
  }

  // ── restore ───────────────────────────────────────────────────────────────────

  /// [openSource] replaces step 2's path-based open. Null means "open
  /// `session.sourceFilePath` from the filesystem", which is every route but
  /// the web pack.
  Future<void> _restore(
    SessionState session, {
    Future<void> Function()? openSource,
  }) async {
    // 0. Stash the loaded `extensions` map as the preserve-unknown base for
    // the next snapshot. Namespaces with no registered codec ride through a
    // load → save cycle untouched; registered codecs overlay fresh payloads.
    _lastLoadedExtensions = session.extensions;

    // 1. Stage zoom/pan restore so the next TimeMapper.initialize picks it up.
    ref
        .read(timeMapperProvider.notifier)
        .setPendingZoomPan(
          ticksPerPixel: session.ticksPerPixel,
          panOffsetTicks: session.panOffsetTicks,
        );

    // 2. Open the waveform file (triggers TimeMapper.initialize via canvas).
    // `preserveDecoders: true` is the decoder-restore seam — openFile's default
    // `activeDecodersProvider.clearAll()` would clobber the persisted set
    // we are about to re-add in step 7a; the listener observing the
    // active-decoders provider must never see a transient `[]`.
    final sourcePath = session.sourceFilePath;
    if (openSource != null) {
      // `openFromBytes` has no `preserveDecoders` seam, but the web pack always
      // restores into a freshly opened tab whose decoder set is already empty,
      // so there is no persisted set for the clear to clobber.
      await openSource();
    } else if (sourcePath != null) {
      await ref
          .read(waveformSourceProvider.notifier)
          .openFile(sourcePath, preserveDecoders: true);
    }

    // 3. Restore the ordered signal list.
    ref
        .read(signalGroupsProvider.notifier)
        .restoreFromSession(session.signalGroup);

    // 3a. Re-resolve every signal entry's `signalRef` against the active
    // backend, using the canonical `signalPath` as the lookup key. Sessions
    // may carry refs from a previous backend or release (and historically
    // from the retired pure-Dart parser that keyed by VCD idcode), so we
    // refresh against the current source to avoid stale refs tripping
    // `loadSignal` → `ArgumentError("Invalid signalRef")` on the very next
    // frame. Entries without a path (pre-path legacy sessions) are left
    // untouched and depend on `_refresh`'s defensive try/catch.
    final source = ref.read(waveformSourceProvider).value;
    if (source != null) {
      ref.read(signalGroupsProvider.notifier).reresolveSignalRefs(source);
    }

    // 3b. Eagerly load each restored signal so the value column has data the
    // moment it queries `signalValuesAtCursor` after restore. Without this,
    // `source.isSignalLoaded(ref)` returns false for every signal until the
    // canvas paints (which is what normally calls `loadSignal`), so the
    // value panel stays empty until the user nudges the cursor. Errors are
    // swallowed per-signal — a single bad ref must not abort the restore.
    if (source != null) {
      final refs = _flattenSignalRefs(
        ref.read(signalGroupsProvider).entries,
      );
      for (final signalRef in refs) {
        if (source.isSignalLoaded(signalRef)) continue;
        try {
          await source.loadSignal(signalRef);
        } on Object {
          // Best-effort: missing/unknown signal ref in the persisted session
          // (file changed since save) must not abort the rest of the restore.
        }
      }
    }

    // 4. Restore cursors.
    final cursorNotifier = ref.read(cursorStateProvider.notifier)..clearAll();
    final primary = session.cursorState.primaryCursorTime;
    final secondary = session.cursorState.secondaryCursorTime;
    if (primary != null) cursorNotifier.placePrimary(primary);
    if (secondary != null) cursorNotifier.placeSecondary(secondary);

    // 5. Restore markers.
    for (final entry in session.markerState.getAllMarkers()) {
      ref
          .read(markerStateProvider.notifier)
          .setMarker(
            entry.key,
            entry.value,
          );
    }

    // 5a. Restore annotations. Wholesale rather than one add()
    // per entry: restoreFromSession also clears undo history, because undoing
    // across a file load would resurrect notes belonging to a different
    // waveform.
    ref
        .read(annotationsProvider.notifier)
        .restoreFromSession(session.annotations);
    // The layer registry restores alongside them. Order does not matter — an
    // annotation naming a layer with no registry entry degrades to an unnamed
    // group rather than disappearing, which is also what a pre-registry document
    // opened by a build that predates the registry does.
    ref
        .read(annotationLayersProvider.notifier)
        .restoreFromSession(session.annotationLayers);
    ref.read(annotationsVisibleProvider.notifier).visible =
        session.annotationsVisible;

    // 6. Restore panel visibility and pane geometry. The bottom pane's
    // *content* is selected by the viewer's priority chain over these flags, so
    // restoring them reproduces the panel the user last had on screen (the AI
    // Advisor / SVA selection is restored separately via the Pro session-
    // extension codecs). Pane sizes only take effect when non-null — null keeps
    // the layout default.
    final panelNotifier = ref.read(panelLayoutProvider.notifier)
      ..setSignalTreeVisible(visible: session.signalTreeVisible)
      ..setValueColumnVisible(visible: session.valueColumnVisible)
      ..setTransactionViewVisible(visible: session.transactionViewVisible)
      ..setStageViewVisible(visible: session.stageViewVisible)
      ..setStatisticsStripVisible(visible: session.statisticsStripVisible)
      ..setCocotbLogPanelVisible(visible: session.cocotbLogPanelVisible)
      ..setAnnotationsPanelVisible(visible: session.annotationsPanelVisible)
      ..setRtlSourceVisible(visible: session.rtlSourceVisible);
    // Null (a pre-dock session) keeps the legacy chain derivation in
    // `effectiveBottomDockTab`, which reproduces the panel it saved with.
    final sessionDockTab = session.bottomDockTab;
    if (sessionDockTab != null) {
      panelNotifier.setBottomDockTab(sessionDockTab);
    }
    final sessionRightTab = session.rightDockTab;
    if (sessionRightTab != null) {
      panelNotifier.setRightDockTab(sessionRightTab);
    }
    if (session.dockPlacements.isNotEmpty) {
      panelNotifier.restoreDockPlacements(session.dockPlacements);
    }
    if (session.leftPaneSize != null) {
      panelNotifier.setLeftPaneSize(session.leftPaneSize!);
    }
    if (session.rightPaneSize != null) {
      panelNotifier.setRightPaneSize(session.rightPaneSize!);
    }
    if (session.bottomPaneSize != null) {
      panelNotifier.setBottomPaneSize(session.bottomPaneSize!);
    }

    // 6a. Re-load the cocotb log / RTL stems whose paths were persisted, so the
    // restored panel shows content rather than an empty state. Fire-and-forget
    // and fail-soft: a moved/deleted file leaves the panel empty (mirrors the
    // Pro `pro.sva` log restore) and must not abort the rest of the restore.
    final cocotbLogPath = session.cocotbLogPath;
    if (cocotbLogPath != null && cocotbLogPath.isNotEmpty) {
      unawaited(_reloadCocotbLog(cocotbLogPath));
    }
    final rtlStemsPath = session.rtlStemsPath;
    if (rtlStemsPath != null && rtlStemsPath.isNotEmpty) {
      unawaited(_reloadRtlStems(rtlStemsPath));
    }

    // 6b. Restore signal-tree browser state. Expansion / selection are applied
    // directly (stale paths/refs are harmless — see the notifier docs); scroll
    // is mirrored into the per-tab provider the panel seeds its ScrollController
    // from. The search query is applied LAST: a non-empty query drives the
    // panel's search-expansion (overriding the restored expansion), which is
    // faithful to "a search was active when the session was saved".
    ref
        .read(expandedScopesProvider.notifier)
        .applyExpanded(session.expandedScopePaths);
    ref
        .read(selectedVariablesProvider.notifier)
        .applySelection(session.signalTreeSelectedRefs);
    ref
        .read(signalTreeScrollProvider.notifier)
        .setOffset(session.signalTreeScrollOffset);
    ref
        .read(signalSearchQueryProvider.notifier)
        .setQuery(query: session.signalTreeSearchQuery);

    // 7. Restore Stage workspace.
    ref
        .read(stageWorkspaceProvider.notifier)
        .restoreFromSession(session.stageWorkspace);

    // 8. Restore translate filter assignments.
    await ref
        .read(translateFilterProvider.notifier)
        .restoreFromSession(session.translateFilterPaths);

    // 8a. Restore user-supplied FSM state-name annotations.
    ref
        .read(fsmAnnotationProvider.notifier)
        .restoreFromSession(session.fsmAnnotations);

    // 9. Restore vertical scroll offset. Must be after the signal list is
    // restored (otherwise the SignalListPanel's scroll controller hasn't
    // attached yet and the value is dropped).
    ref.read(waveformScrollProvider.notifier).setOffset(session.scrollOffset);

    // 10. Restore protocol decoder instances. Runs after the
    // waveform source is ready so the immediate decodeAll() pass has
    // valid signal data to consume. Unknown-decoderId entries (Pro
    // decoder on Open Core, uninstalled plugin) are skipped silently
    // inside restoreDecoders; the cross-tier-open case must not throw.
    if (session.decoders.isNotEmpty) {
      ref
          .read(activeDecodersProvider.notifier)
          .restoreDecoders(session.decoders);
      if (source != null) {
        // Eager re-decode: matches user expectation that the
        // transaction table is populated the moment the tab finishes
        // restoring. There is no settings toggle — the open-time cost is
        // accepted until a user reports it.
        await ref.read(activeDecodersProvider.notifier).decodeAll();
      }
    }

    // 11. Restore Pro session-extension payloads. Runs last,
    // after the waveform source is ready, so codecs that re-load an external
    // artifact (e.g. the `pro.sva` codec re-invoking
    // SvaResultsNotifier.loadFromFile) observe a valid timescale. Codecs whose
    // namespace this build does not understand are skipped; their payloads
    // survive on `_lastLoadedExtensions` (stashed in step 0) for the next
    // snapshot. The open-core registry is empty, so this is a no-op without a
    // Pro overlay.
    SessionExtensions.restore(ref, session.extensions);
  }

  /// Flattens nested groups into a list of signal refs for eager loading.
  /// Skips separators, comments, and group headers themselves.
  static List<String> _flattenSignalRefs(List<SignalEntry> entries) {
    final out = <String>[];
    for (final e in entries) {
      switch (e.kind) {
        case SignalEntryKind.signal:
          final r = e.signalRef;
          if (r != null) out.add(r);
        case SignalEntryKind.group:
          out.addAll(_flattenSignalRefs(e.children));
        case SignalEntryKind.separator:
        case SignalEntryKind.comment:
          break;
      }
    }
    return out;
  }

  /// Fail-soft re-parse of a persisted cocotb log on restore. A moved/deleted
  /// file leaves the panel empty rather than surfacing an error every launch.
  Future<void> _reloadCocotbLog(String path) async {
    try {
      await ref.read(cocotbLogProvider.notifier).loadFromFile(path);
    } on Object catch (error, stack) {
      _log.info(
        'cocotb log not restored — unreadable at "$path"',
        error,
        stack,
      );
    }
  }

  /// Fail-soft re-load of a persisted RTL stems file on restore.
  Future<void> _reloadRtlStems(String path) async {
    try {
      await ref.read(rtlSourceProvider.notifier).loadStemsFile(path);
    } on Object catch (error, stack) {
      _log.info('RTL stems not restored — unreadable at "$path"', error, stack);
    }
  }
}

// ── SessionAutoSaveNotifier ───────────────────────────────────────────────────

/// Watches all per-tab viewer state providers and incrementally writes the
/// tab's session sidecar at `{appSupportDir}/sessions/{tabId}.wavecrux`.
///
/// Why this exists: workspace.json is written by [WorkspaceNotifier] on every
/// tab/pane mutation, but the *per-tab* state (cursors, signal arrangement,
/// zoom, markers, Stage workspace, translate filters, panel visibility) is
/// not part of the workspace document. Without this notifier, that state is
/// only captured at app quit via the lifecycle-paused flush — and on desktop
/// macOS the process can exit before the unawaited flush completes, leaving
/// the sidecar stale or empty. Continuous incremental writes here close that
/// window: the sidecar is up-to-date within `autoSaveInterval` of the user's
/// last mutation.
///
/// This notifier is overridden per-tab in [TabContainerManager.containerFor]
/// (so [tabIdProvider] resolves to the hosting tab's id). It is eagerly read
/// in `containerFor` so the listeners are armed the moment the tab opens.
///
/// Saves are silently skipped when:
/// - No waveform file is loaded (the autosave runs ahead of file open during
///   restore, when there is nothing yet to capture).
/// - The [path_provider] platform channel is unavailable (unit tests).
/// - Any I/O error occurs.
@Riverpod(keepAlive: true)
class SessionAutoSaveNotifier extends _$SessionAutoSaveNotifier {
  /// Coalesces a burst of edits into one write, on [autoSaveInterval] as it
  /// stands when the edit arrives: an interval changed since the last edit
  /// gets a fresh debouncer, and the save pending on the old one is dropped
  /// as the next edit would have dropped it anyway.
  Debouncer? _debounce;

  /// The auto-save debounce interval. Short enough that a user's cursor
  /// placement persists across an abrupt quit, long enough that rapid edits
  /// (cursor drag, zoom inertia) collapse into a single write. Override in
  /// tests to speed up saves.
  Duration autoSaveInterval = const Duration(seconds: 2);

  @override
  void build() {
    ref
      ..listen<dynamic>(signalGroupsProvider, (_, _) => _schedule())
      ..listen<dynamic>(cursorStateProvider, (_, _) => _schedule())
      ..listen<dynamic>(markerStateProvider, (_, _) => _schedule())
      ..listen<dynamic>(timeMapperProvider, (_, _) => _schedule())
      ..listen<dynamic>(panelLayoutProvider, (_, _) => _schedule())
      ..listen<dynamic>(stageWorkspaceProvider, (_, _) => _schedule())
      ..listen<dynamic>(activeDecodersProvider, (_, _) => _schedule())
      ..listen<dynamic>(fsmAnnotationProvider, (_, _) => _schedule())
      ..listen<dynamic>(annotationsProvider, (_, _) => _schedule())
      ..listen<dynamic>(annotationLayersProvider, (_, _) => _schedule())
      ..listen<dynamic>(annotationsVisibleProvider, (_, _) => _schedule())
      // Bottom-pane content (cocotb log / RTL stems) and signal-tree browser
      // state (expand/collapse, search, selection, scroll) — restored on
      // relaunch, so a change to any of them must reschedule the sidecar write.
      ..listen<dynamic>(cocotbLogProvider, (_, _) => _schedule())
      ..listen<dynamic>(rtlSourceProvider, (_, _) => _schedule())
      ..listen<dynamic>(expandedScopesProvider, (_, _) => _schedule())
      ..listen<dynamic>(signalSearchQueryProvider, (_, _) => _schedule())
      ..listen<dynamic>(selectedVariablesProvider, (_, _) => _schedule())
      ..listen<dynamic>(signalTreeScrollProvider, (_, _) => _schedule())
      // Cancelled, not disposed: Riverpod keeps this notifier instance when
      // the provider rebuilds, so the next build schedules through it again.
      ..onDispose(() => _debounce?.cancel());
  }

  void _schedule() {
    var debounce = _debounce;
    if (debounce == null || debounce.duration != autoSaveInterval) {
      debounce?.cancel();
      debounce = _debounce = Debouncer(duration: autoSaveInterval);
    }
    debounce.run(() => unawaited(_performAutoSave()));
  }

  Future<void> _performAutoSave() async {
    if (!ref.read(waveformIsLoadedProvider)) return;

    final tabId = ref.read(tabIdProvider);
    final service = ref.read(workspaceServiceProvider);
    try {
      final path = await service.sidecarPathFor(tabId.value);
      if (path == null) return;
      final session = ref.read(sessionProvider.notifier)._snapshot();
      final audit = ref.read(cruxAuditRecorderProvider);
      await ref.read(sessionServiceProvider).saveSession(session, path);
      // `debug`, so it lands only at `verbosity: verbose`. The autosave is
      // debounced but still fires on a timer nobody asked for, and an audit
      // log whose signal is drowned by a background writer is one an
      // administrator stops reading. `AuditVerbosity` exists for exactly this
      // distinction, so use it rather than dropping the event.
      audit.record(
        WaveCruxAuditKinds.sessionSaved,
        severity: AuditSeverity.debug,
        payload: <String, Object?>{
          'file': p.basename(path),
          'trigger': 'autosave',
        },
      );
    } on MissingPluginException catch (_) {
      // path_provider not available in tests — skip silently.
    } on Exception catch (e) {
      // The user didn't explicitly request this save, so don't interrupt them
      // with UI — but record it: a persistently failing auto-save is silent
      // session-state loss worth seeing in a bug report.
      _log.warning('Auto-save failed for tab ${tabId.value}: $e');
    }
  }

  /// Forces any pending debounced save to flush immediately. Exposed for
  /// lifecycle handlers and tests.
  Future<void> flushPendingSave() async {
    _debounce?.cancel();
    await _performAutoSave();
  }
}
