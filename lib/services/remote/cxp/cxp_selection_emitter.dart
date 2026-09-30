// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_async/crux_async.dart';
import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/collaboration/signal_identity_resolver.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_server.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_name_resolver.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/tabs/active_tab_container.dart';

/// Debounce window applied to cursor-move events before they fan out as
/// CXP `notify_selection` messages. Cursor scrubbing can fire dozens of
/// updates per second from a drag gesture; the debounce coalesces them
/// into a single broadcast per quiescent burst so we don't flood every
/// subscribed peer.
const Duration kCxpCursorDebounce = Duration(milliseconds: 100);

/// Where a [CxpSelectionEmitter] sends what it produces.
///
/// Matches [WaveCruxCxpServer.broadcast]'s signature, which is the production
/// sink on desktop; the editor-host bridge is the second, posting the same
/// messages to a VSCode extension host over `window.postMessage` instead of a
/// socket. A sink rather than a server because there is exactly one selection
/// story in this app and both front doors have to tell it identically — a
/// second emitter for the bridge is how "the editor sees a different selection
/// from the peer apps" would get built.
///
/// [summary] is a human-readable one-liner for a transport that keeps an event
/// log. A sink with nothing to log ignores it.
typedef CxpSelectionSink = void Function(CxpMessage message, {String? summary});

/// Bridges WaveCrux's selection providers to outbound CXP
/// `notify_selection` broadcasts. Watches:
///
/// * [selectedSignalProvider] — emit on signal selection changes.
/// * [cursorStateProvider] — emit (debounced) on primary cursor moves,
///   carrying the current cursor tick in `metadata.wavecrux.cursor_time_fs`
///   alongside the selected signal (if any).
/// * [markerStateProvider] — emit on marker create / update / delete with
///   `ElementKind.marker`.
///
/// All emissions go through the [CxpSelectionSink]. On desktop that is
/// [WaveCruxCxpServer.broadcast], which routes the message only to peers whose
/// `Subscribe` filters match the `notify_selection` kind — silent peers never
/// see anything. Under a VSCode extension host it is the editor-host bridge,
/// which posts the same message to the host for it to relay.
///
/// The emitter is constructed by `cxpSelectionEmitterProvider` and bound
/// to the running server's lifetime; `dispose` cancels all subscriptions
/// and the debounce timer so a server restart starts from a clean slate.
class CxpSelectionEmitter {
  /// Creates an emitter that sends to [sink]. The resolver
  /// defaults to [WaveCruxNameResolver]; injection is provided for tests.
  CxpSelectionEmitter({
    required Ref ref,
    required CxpSelectionSink sink,
    NameResolver? resolver,
    Duration cursorDebounce = kCxpCursorDebounce,
  }) : _ref = ref,
       _sink = sink,
       _resolver = resolver ?? const WaveCruxNameResolver(),
       _cursorDebounce = Debouncer(duration: cursorDebounce);

  final Ref _ref;
  final CxpSelectionSink _sink;
  final NameResolver _resolver;
  final Debouncer _cursorDebounce;

  ProviderSubscription<String?>? _selectionSub;
  ProviderSubscription<TabId>? _activeTabSub;
  ProviderSubscription<CursorState>? _cursorSub;
  ProviderSubscription<MarkerState>? _markerSub;
  String? _lastSelection;
  MarkerState _lastMarkerSnapshot = const MarkerState();

  /// The active tab's container, or null to read per-tab state off the root
  /// [_ref] (no real tab / flat-container tests).
  ProviderContainer? _activeContainer;
  bool _disposed = false;

  /// Wire up the listen subscriptions. Idempotent. Must be called before
  /// the emitter does any useful work; the [cxpSelectionEmitterProvider]
  /// calls this in its build closure.
  ///
  /// `cursorStateProvider` and `markerStateProvider` are **per-tab**, so they
  /// are bound to the active tab's container and re-bound whenever the active
  /// tab changes — the CXP/collab scope-leak class. `selectedSignalProvider` is
  /// the CXP server's own global focus, so it stays on the root [_ref].
  void start() {
    if (_selectionSub != null) return;
    _lastSelection = _ref.read(selectedSignalProvider);
    _selectionSub = _ref.listen<String?>(
      selectedSignalProvider,
      _onSelectionChanged,
    );
    _activeTabSub = _ref.listen<TabId>(
      activeTabIdProvider,
      (_, _) => _bindActiveTab(),
    );
    _bindActiveTab();
  }

  /// (Re)bind the per-tab cursor/marker listens to the active tab's container.
  void _bindActiveTab() {
    _cursorSub?.close();
    _markerSub?.close();
    final container = activeTabContainer(_ref);
    _activeContainer = container;
    _lastMarkerSnapshot = _readMarkers();
    if (container != null) {
      _cursorSub = container.listen<CursorState>(
        cursorStateProvider,
        (_, next) => _scheduleCursorBroadcast(next),
      );
      _markerSub = container.listen<MarkerState>(
        markerStateProvider,
        _onMarkerChanged,
      );
    } else {
      // No tab system (unit tests / empty canvas): fall back to the root ref so
      // a flat test container still drives the emitter.
      _cursorSub = _ref.listen<CursorState>(
        cursorStateProvider,
        (_, next) => _scheduleCursorBroadcast(next),
      );
      _markerSub = _ref.listen<MarkerState>(
        markerStateProvider,
        _onMarkerChanged,
      );
    }
  }

  CursorState _readCursor() =>
      _activeContainer?.read(cursorStateProvider) ??
      _ref.read(cursorStateProvider);

  /// The active waveform's `crux.design_id` (derived from its containing
  /// directory), or null when no on-disk waveform is open. Attached to every
  /// outbound `notify_selection` so a receiver that has no matching waveform
  /// open can resolve and open this design's dump from the shared workspace —
  /// the reverse cross-probe half of the shared workspace.
  String? _designId() {
    final path = _activeContainer
        ?.read(waveformSourceProvider.notifier)
        .currentFilePath;
    return path == null ? null : cxpDesignIdForPath(path);
  }

  MarkerState _readMarkers() =>
      _activeContainer?.read(markerStateProvider) ??
      _ref.read(markerStateProvider);

  /// Whether live auto-broadcast of the local selection is enabled
  /// ([AppSettings.broadcastSelectionOnCrossProbe]). Read fresh on each
  /// emission so a Settings toggle takes effect immediately, without a server
  /// restart. Defaults to `true` while settings are still loading so the live
  /// cross-probe works from launch. Explicit per-peer sends from the panel do
  /// not go through the emitter, so they are unaffected by this gate.
  bool get _autoBroadcastEnabled =>
      _ref.read(appSettingsProvider).value?.broadcastSelectionOnCrossProbe ??
      true;

  /// Release subscriptions + cancel the debounce timer. Safe to call
  /// repeatedly.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _selectionSub?.close();
    _selectionSub = null;
    _activeTabSub?.close();
    _activeTabSub = null;
    _cursorSub?.close();
    _cursorSub = null;
    _markerSub?.close();
    _markerSub = null;
    _cursorDebounce.dispose();
  }

  // ── Selection ──────────────────────────────────────────────────────────────

  void _onSelectionChanged(String? previous, String? next) {
    _lastSelection = next;
    if (next == null) return;
    if (!_autoBroadcastEnabled) return;
    // `next` is a backend-local `signalRef` — meaningless to any peer. Emit the
    // canonical hierarchical PATH instead so a receiver can leaf-match it
    // against its own model; skip when it doesn't resolve (stale selection).
    final path = _fullPathForSelection(next);
    if (path == null) return;
    final element = _resolver.toCanonical(
      kind: ElementKind.signal,
      local: path,
    );
    if (element == null) return;
    final cursorTime = _readCursor().primaryCursorTime;
    final designId = _designId();
    _sink(
      NotifySelection(
        elements: [element],
        displayName: path,
        metadata: <String, Object?>{
          'wavecrux.cursor_time_fs': ?cursorTime,
          cxpDesignIdMetadataKey: ?designId,
        },
      ),
      summary: path,
    );
  }

  /// Resolves the backend-local [signalRef] focus to its canonical hierarchical
  /// `fullPath` against the active tab's loaded waveform, or `null` when no
  /// waveform is open or the ref no longer resolves. A `signalRef` is a
  /// per-process handle, so cross-probe must travel in path space (see
  /// [fullPathForSignalRef]).
  String? _fullPathForSelection(String signalRef) {
    final container = _activeContainer;
    final async = container != null
        ? container.read(waveformSourceProvider)
        : _ref.read(waveformSourceProvider);
    final source = async.value;
    if (source == null) return null;
    return fullPathForSignalRef(source, signalRef);
  }

  // ── Cursor (debounced) ─────────────────────────────────────────────────────

  void _scheduleCursorBroadcast(CursorState next) {
    _cursorDebounce.run(() {
      if (_disposed) return;
      _broadcastCursor(next);
    });
  }

  void _broadcastCursor(CursorState cursor) {
    if (!_autoBroadcastEnabled) return;
    final time = cursor.primaryCursorTime;
    if (time == null) return;
    final selection = _lastSelection;
    if (selection == null) return;
    // Emit the canonical PATH, not the backend-local signalRef (see
    // [_onSelectionChanged]); skip when the ref no longer resolves.
    final path = _fullPathForSelection(selection);
    if (path == null) return;
    final element = _resolver.toCanonical(
      kind: ElementKind.signal,
      local: path,
    );
    if (element == null) return;
    _sink(
      NotifySelection(
        elements: [element],
        displayName: path,
        metadata: <String, Object?>{
          'wavecrux.cursor_time_fs': time,
          cxpDesignIdMetadataKey: ?_designId(),
        },
      ),
      summary: '$path @ $time',
    );
  }

  // ── Markers ────────────────────────────────────────────────────────────────

  void _onMarkerChanged(MarkerState? previous, MarkerState next) {
    // Keep the snapshot current even when auto-broadcast is off, so re-enabling
    // it does not replay marker diffs accumulated while it was silenced.
    if (!_autoBroadcastEnabled) {
      _lastMarkerSnapshot = next;
      return;
    }
    final prev = previous ?? _lastMarkerSnapshot;
    // Identify any markers that changed (added, updated, or removed)
    // and emit notify_selection messages for each — peers can then
    // mirror the marker placement onto their own timeline.
    final allLetters = <String>{...prev.markers.keys, ...next.markers.keys};
    for (final letter in allLetters) {
      final prevTime = prev.markers[letter];
      final nextTime = next.markers[letter];
      if (prevTime == nextTime) continue;
      if (nextTime == null) continue; // marker removed — no broadcast
      final element = _resolver.toCanonical(
        kind: ElementKind.marker,
        local: letter,
      );
      if (element == null) continue;
      _sink(
        NotifySelection(
          elements: [element],
          displayName: 'marker $letter @ $nextTime',
          metadata: <String, Object?>{
            'wavecrux.cursor_time_fs': nextTime,
            cxpDesignIdMetadataKey: ?_designId(),
          },
        ),
        summary: 'marker $letter @ $nextTime',
      );
    }
    _lastMarkerSnapshot = next;
  }
}
