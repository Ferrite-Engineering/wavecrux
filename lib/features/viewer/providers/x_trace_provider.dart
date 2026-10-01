// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/signal_query/x_trace_service.dart';

part 'x_trace_provider.g.dart';

// ── XTraceFailure ─────────────────────────────────────────────────────────────

/// Why the last [XTraceNotifier.traceX] produced no causal chain.
///
/// A code rather than a message, so the X-Trace panel shows it in the user's
/// language.
enum XTraceFailure {
  /// The signal is not X at the requested time, so there is nothing to trace.
  notXAtTime,

  /// The signal is not in the loaded design hierarchy.
  signalNotFound,
}

// ── XTraceState ───────────────────────────────────────────────────────────────

/// Immutable state for the X-origin trace feature.
@immutable
class XTraceState {
  const XTraceState({
    this.rootNode,
    this.involvedSignalPaths = const {},
    this.error,
  });

  /// Root of the causal chain tree, or `null` when no trace is active.
  final XCausalNode? rootNode;

  /// Set of all signal paths present in the causal tree (root + children).
  ///
  /// Widgets (e.g. the waveform canvas) can watch this to render X-origin
  /// markers at the relevant signal lanes.
  final Set<String> involvedSignalPaths;

  /// Why the last [XTraceNotifier.traceX] failed, or null when it did not.
  final XTraceFailure? error;

  /// Whether an X-trace result is currently displayed.
  bool get isActive => rootNode != null;

  /// Whether the X-Trace panel has anything to show: a causal chain, or the
  /// reason the last trace could not build one.
  ///
  /// The dock keys the panel's presence on this rather than [isActive]. A
  /// refused trace used to leave the panel unmounted, so its reason had no
  /// surface and the action that asked for it appeared to do nothing.
  bool get hasContent => rootNode != null || error != null;

  XTraceState copyWith({
    XCausalNode? rootNode,
    Set<String>? involvedSignalPaths,
    XTraceFailure? error,
    bool clearRoot = false,
    bool clearError = false,
  }) => XTraceState(
    rootNode: clearRoot ? null : (rootNode ?? this.rootNode),
    involvedSignalPaths: involvedSignalPaths ?? this.involvedSignalPaths,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is XTraceState &&
          rootNode == other.rootNode &&
          involvedSignalPaths == other.involvedSignalPaths &&
          error == other.error;

  @override
  int get hashCode => Object.hash(rootNode, involvedSignalPaths, error);

  @override
  String toString() =>
      'XTraceState(active: $isActive, involved: ${involvedSignalPaths.length}, '
      'error: $error)';
}

// ── XTraceNotifier ────────────────────────────────────────────────────────────

/// Manages the X-origin trace state.
///
/// Call [traceX] to walk backward from a signal that is X at a given time and
/// build a [XCausalNode] tree.  Call [clearTrace] to dismiss the result.
///
/// When a trace is active the notifier also moves the primary cursor to the
/// X-origin time so the waveform canvas highlights the moment X appeared.
@Riverpod(keepAlive: true)
class XTraceNotifier extends _$XTraceNotifier {
  @override
  XTraceState build() => const XTraceState();

  // ── public API ───────────────────────────────────────────────────────────────

  /// Traces the X origin for [signalRef] at simulation tick [time].
  ///
  /// Looks up the corresponding [Variable] from the loaded hierarchy, loads
  /// its signal data if necessary, builds the causal chain, and updates state.
  /// Moves the primary cursor to the X-origin time on success.
  Future<void> traceX(String signalRef, int time) async {
    final source = ref.read(waveformSourceProvider).value;
    if (source == null) return;

    // Look up Variable from the flat signalRef map.
    final variablesMap = ref.read(signalVariablesMapProvider);
    final variable = variablesMap[signalRef];
    if (variable == null) {
      state = const XTraceState(error: XTraceFailure.signalNotFound);
      return;
    }

    // Ensure signal data is loaded.
    if (!source.isSignalLoaded(signalRef)) {
      await source.loadSignal(signalRef);
    }

    // `loadSignal` can span a tab close. Riverpod 3 disposes the notifier
    // eagerly, so both the `state` writes and the `ref.read` cursor/navigation
    // calls below would throw `UnmountedRefException` on a dead container.
    if (!ref.mounted) return;

    // Quick check: is the signal actually X at the requested time?
    final valueAtTime = source.valueAt(signalRef, time);
    if (valueAtTime == null || !valueAtTime.toLowerCase().contains('x')) {
      state = const XTraceState(error: XTraceFailure.notXAtTime);
      return;
    }

    const service = XTraceService();
    final hierarchy = source.rootScopes;

    final chain = service.buildCausalChain(variable, time, hierarchy, source);

    // Collect all involved signal paths for canvas markers.
    final involved = <String>{
      chain.signalPath,
      for (final child in chain.children) child.signalPath,
    };

    state = XTraceState(
      rootNode: chain,
      involvedSignalPaths: involved,
    );

    // Move primary cursor to X-origin time.
    ref.read(cursorStateProvider.notifier).placePrimary(chain.xStartTime);
    ref.read(navigationProvider.notifier).jumpToTime(chain.xStartTime);
  }

  /// Runs [traceX] and brings its result in front of the user: selects the
  /// X-Trace tab in whichever dock it is placed in and opens that dock if it
  /// was collapsed.
  ///
  /// The one entry point for every user action that starts a trace (the
  /// signal list's *Trace X Origin*, the Debug Advisor's *View causal
  /// chain*), so reveal is part of the action rather than something each
  /// caller has to remember. A refused trace is revealed too: the panel then
  /// shows why.
  Future<void> traceXAndReveal(String signalRef, int time) async {
    await traceX(signalRef, time);
    if (!ref.mounted || !state.hasContent) return;
    ref
        .read(panelLayoutProvider.notifier)
        .revealDockTabPlaced(kBottomDockTabXTrace, kDockRegionBottom);
  }

  /// Clears the active trace result and resets to idle.
  void clearTrace() {
    state = const XTraceState();
  }

  /// Jumps the primary cursor to the X-start time of [node].
  void jumpToNode(XCausalNode node) {
    ref.read(cursorStateProvider.notifier).placePrimary(node.xStartTime);
    ref.read(navigationProvider.notifier).jumpToTime(node.xStartTime);
  }
}
