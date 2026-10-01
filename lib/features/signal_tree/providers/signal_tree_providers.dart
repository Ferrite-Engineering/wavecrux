// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:collection/collection.dart' show mergeSort;
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/natural_compare.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/signal_tree/utils/variable_tree_order.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

// Re-export the signal group provider so existing imports continue to work.
export 'package:wavecrux/features/viewer/providers/signal_group_providers.dart'
    show
        SignalGroupsNotifier,
        SignalRemoval,
        signalColorPalette,
        signalGroupsProvider;

part 'signal_tree_providers.g.dart';

// ── Hierarchy ──────────────────────────────────────────────────────────────────

/// Root scopes from the currently loaded waveform, or an empty list when no
/// file is open. Propagates loading/error states from [waveformSourceProvider].
///
/// When [signalTreeNaturalSortProvider] is on (the default), scopes and
/// variables are natural-sorted by name (digit runs compare numerically —
/// `x[2]` before `x[11]`); gate-level dumps otherwise surface bit-blasted
/// names in meaningless dump order. Sorting happens HERE, once per
/// load/toggle, so every consumer — the flat row list, `variablesInTreeOrder`
/// (Shift+click ranges, bulk-add order), search — inherits one canonical
/// order and can never disagree. Variable instances are preserved (only the
/// list order and Scope containers are rebuilt), so instance-keyed rows and
/// the path/ref maps are unaffected.
@riverpod
AsyncValue<List<Scope>> hierarchy(Ref ref) {
  final sourceAsync = ref.watch(waveformSourceProvider);
  final naturalSort = ref.watch(signalTreeNaturalSortProvider);
  return sourceAsync.whenData((source) {
    final roots = source?.rootScopes ?? const <Scope>[];
    return naturalSort ? _sortedScopes(roots) : roots;
  });
}

List<Scope> _sortedScopes(List<Scope> scopes) {
  final sorted = [for (final s in scopes) _sortedScope(s)];
  mergeSort(sorted, compare: (a, b) => naturalCompare(a.name, b.name));
  return sorted;
}

Scope _sortedScope(Scope scope) {
  final variables = [...scope.variables];
  // mergeSort is stable: gate-level twins (identical names — seen in a real
  // GF180 netlist) keep their dump order relative to each other.
  mergeSort(variables, compare: (a, b) => naturalCompare(a.name, b.name));
  return Scope(
    name: scope.name,
    type: scope.type,
    path: scope.path,
    childScopes: _sortedScopes(scope.childScopes),
    variables: variables,
  );
}

// ── Expanded scopes ────────────────────────────────────────────────────────────

/// Set of scope paths that are currently expanded in the tree.
///
/// Scopes start collapsed. Call [ExpandedScopesNotifier.toggle] to expand or
/// collapse individual scopes, [expandAll] to open everything, or [collapseAll]
/// to close everything.
///
/// When a search query is active, call [expandMatchingScopes] to automatically
/// expand all ancestor scopes of matching variables. The pre-search expansion
/// state is saved internally and can be restored via [restoreState] when the
/// query is cleared.
@riverpod
class ExpandedScopesNotifier extends _$ExpandedScopesNotifier {
  /// Snapshot of the user's expansion state before search-driven expansion
  /// was applied. Non-null only while a search query is active.
  Set<String>? _savedExpansionState;

  @override
  Set<String> build() => const {};

  void toggle(String scopePath) {
    if (state.contains(scopePath)) {
      state = <String>{...state}..remove(scopePath);
    } else {
      state = <String>{...state, scopePath};
    }
  }

  void expandAll(List<Scope> rootScopes) {
    final allPaths = <String>{};
    void collect(Scope scope) {
      allPaths.add(scope.path);
      scope.childScopes.forEach(collect);
    }

    rootScopes.forEach(collect);
    state = allPaths;
  }

  void collapseAll() => state = const {};

  /// Expands [scopePath] and every ancestor scope on the way down from the
  /// root, so a leaf inside it becomes visible in the flat row list. A scope
  /// only contributes its children when its own `path` is in the expanded set,
  /// so every prefix of the dotted path must be expanded for the target row to
  /// render. Used by the cross-probe reveal to surface a programmatically
  /// selected variable in the hierarchy browser. No-op for an empty path.
  void expandAncestorsOf(String scopePath) {
    if (scopePath.isEmpty) return;
    final parts = scopePath.split('.');
    final next = <String>{...state};
    final buffer = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) buffer.write('.');
      buffer.write(parts[i]);
      next.add(buffer.toString());
    }
    if (next.length == state.length) return; // already all expanded
    state = next;
  }

  /// Replaces the expanded set wholesale. Used by session restore to reinstate
  /// the persisted expansion. Paths that no longer exist in the loaded
  /// hierarchy are harmless — [ScopeTreeNode] only ever queries the set with
  /// `contains(scope.path)`, so a stale path simply never matches.
  void applyExpanded(Set<String> scopePaths) => state = <String>{...scopePaths};

  /// Expands all ancestor scopes of variables whose name case-insensitively
  /// contains [query].
  ///
  /// Saves the current expansion state on the first call (when
  /// [_savedExpansionState] is null) so it can be restored later via
  /// [restoreState]. Subsequent calls while a query is active overwrite the
  /// expanded set without touching the saved state.
  ///
  /// Does nothing when [query] is empty (call [restoreState] instead).
  ///
  /// Pass [matchIndex] when the caller already built the index for this
  /// [query] over these [rootScopes] — the signal tree builds one per query
  /// and shares it with the row flattening, so a keystroke walks the
  /// hierarchy once instead of once here and once again for the rows.
  void expandMatchingScopes(
    List<Scope> rootScopes,
    String query, {
    ScopeMatchIndex? matchIndex,
  }) {
    if (query.isEmpty) return;

    // Snapshot user's expansion state the first time we enter search mode.
    _savedExpansionState ??= Set.unmodifiable(state);

    // The same single bottom-up pass the tree flatteners use, so the expanded
    // set and the rendered rows can never disagree about which scopes survive
    // the filter.
    state = <String>{
      ...(matchIndex ?? ScopeMatchIndex.build(rootScopes, query))
          .matchingScopePaths,
    };
  }

  /// Restores the expansion state that was saved before [expandMatchingScopes]
  /// was first called. Clears the saved snapshot after restoring.
  ///
  /// No-ops when no snapshot is present (i.e. search was never activated).
  void restoreState() {
    if (_savedExpansionState == null) return;
    state = Set.of(_savedExpansionState!);
    _savedExpansionState = null;
  }
}

// ── Selected variables ─────────────────────────────────────────────────────────

/// Set of [Variable.fullPath] values that are currently selected in the tree.
///
/// Keyed by **fullPath (row identity), not signalRef (data identity)**: FST
/// files alias one underlying signal into many hierarchy rows (a net wired
/// through ports appears in every scope it crosses, all sharing one wellen
/// signalRef). A ref-keyed selection conflated those rows — selecting
/// `wb_ram0.wb_cyc_i` could resolve to its testbench-level alias, so
/// decoder-from-selection showed names from scopes the user never clicked
/// (the wb_streamer beta report). Consumers that need waveform data resolve
/// path → [Variable] via [signalVariablesByPathProvider], then use the
/// variable's signalRef.
///
/// Supports multi-selection for bulk-add operations. A plain tap selects
/// only the tapped row (via [selectOnly] — it is also the add-to-viewer
/// action); Ctrl/Cmd+click toggles individual rows; Shift+click selects the
/// visible range between the most recent interaction (the anchor) and the
/// clicked row via [selectRangeTo].
@riverpod
class SelectedVariablesNotifier extends _$SelectedVariablesNotifier {
  /// The fixed end of a Shift+click range: the fullPath of the most recent
  /// tap/toggle, matching the row identity [state] is keyed by. Not part of
  /// [state] — it is interaction bookkeeping, not
  /// selection, so changing it must not rebuild selection listeners.
  String? _anchor;

  @override
  Set<String> build() => const {};

  void toggle(String fullPath) {
    if (state.contains(fullPath)) {
      state = {...state}..remove(fullPath);
    } else {
      state = {...state, fullPath};
    }
    _anchor = fullPath;
  }

  void selectOnly(String fullPath) {
    state = {fullPath};
    _anchor = fullPath;
  }

  void clear() => state = const {};

  /// Replaces the selection with the contiguous run of [orderedVisiblePaths]
  /// between the anchor and [fullPath] (inclusive).
  ///
  /// [orderedVisiblePaths] is the tree's current top-to-bottom visible row
  /// order (see `variablesInTreeOrder`). Falls back to selecting only
  /// [fullPath] when there is no anchor or either end is not visible
  /// (e.g. the anchor's scope was collapsed since it was set).
  void selectRangeTo(String fullPath, List<String> orderedVisiblePaths) {
    final anchor = _anchor;
    final anchorIndex = anchor == null
        ? -1
        : orderedVisiblePaths.indexOf(anchor);
    final targetIndex = orderedVisiblePaths.indexOf(fullPath);
    if (anchorIndex == -1 || targetIndex == -1) {
      selectOnly(fullPath);
      return;
    }
    final low = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final high = anchorIndex < targetIndex ? targetIndex : anchorIndex;
    // The anchor stays put so successive Shift+clicks re-range from it.
    state = orderedVisiblePaths.sublist(low, high + 1).toSet();
  }

  /// Replaces the selection wholesale. Used by session restore. Paths absent
  /// from the reopened waveform are harmless — selection is only ever
  /// consulted by equality, so a stale path simply never matches a rendered
  /// row. (Sessions written before 0.2.3 stored signalRefs here; those stale
  /// values drop out the same way.)
  void applySelection(Set<String> fullPaths) => state = <String>{...fullPaths};
}

// ── Cross-probe reveal request ──────────────────────────────────────────────────

/// A request to bring a particular signal — identified by [Variable.fullPath] —
/// into view in the waveform viewer: scroll the synced lane / name / value
/// columns to the signal's lane and expand its containing viewer group if it is
/// collapsed.
///
/// Set by the CXP inbound cross-probe handler immediately after it selects an
/// inbound signal, and consumed (via `ref.listen`) by [WaveformCanvas].
/// Auto-reveal is deliberately restricted to *programmatic* (inbound) selection:
/// a manual click already lands the row under the pointer, so yanking the
/// viewport on every click would be hostile — this is scroll-on-cross-probe, not
/// scroll-on-every-select.
///
/// [token] increments on every request so re-revealing the SAME signal still
/// notifies listeners; plain state-equality on [fullPath] alone would swallow a
/// repeat cross-probe of a signal already selected.
@immutable
class RevealSignalRequest {
  const RevealSignalRequest({required this.fullPath, required this.token});

  /// The [Variable.fullPath] of the signal to bring into view.
  final String fullPath;

  /// Monotonic request id — see the class doc.
  final int token;

  @override
  bool operator ==(Object other) =>
      other is RevealSignalRequest &&
      other.fullPath == fullPath &&
      other.token == token;

  @override
  int get hashCode => Object.hash(fullPath, token);
}

/// Per-tab holder for the most recent [RevealSignalRequest].
///
/// Overridden per tab in `wavecruxTabOverrides` so an inbound cross-probe
/// reveals the signal in the tab it targeted, not a root-scope singleton shared
/// across every tab.
@riverpod
class RevealSignalRequestNotifier extends _$RevealSignalRequestNotifier {
  int _token = 0;

  @override
  RevealSignalRequest? build() => null;

  /// Requests that [fullPath] be scrolled into view (expanding its group when
  /// collapsed). Each call bumps the token so a repeated reveal still fires.
  void request(String fullPath) {
    state = RevealSignalRequest(fullPath: fullPath, token: ++_token);
  }

  /// Clears a consumed request. Not required for correctness (the token
  /// dedupes and `ref.listen` only fires on change), but keeps the state tidy
  /// and is handy for tests.
  void clear() => state = null;
}

// ── Signal search query ────────────────────────────────────────────────────────

/// The current text entered in the signal tree search box.
@riverpod
class SignalSearchQueryNotifier extends _$SignalSearchQueryNotifier {
  @override
  String build() => '';

  // Riverpod notifiers use methods, not setters, for state mutations.
  // ignore: use_setters_to_change_properties
  void setQuery({required String query}) => state = query;

  void clear() => state = '';
}

// ── Signal tree scroll offset ───────────────────────────────────────────────────

/// Vertical scroll offset (logical pixels) of the signal tree browser list.
///
/// Mirrored from the [SignalTreePanel]'s `ScrollController` so the position
/// survives in the per-tab session sidecar and is restored on relaunch (the
/// `ScrollController` itself is widget-lifetime state and cannot persist). The
/// panel seeds its controller from this value on build and writes back as the
/// user scrolls.
@riverpod
class SignalTreeScrollNotifier extends _$SignalTreeScrollNotifier {
  @override
  double build() => 0;

  void setOffset(double offset) {
    if (offset == state) return;
    state = offset;
  }
}

// ── Signal variables flat map ──────────────────────────────────────────────────

/// Flat map from [Variable.signalRef] to [Variable] for every variable in the
/// current waveform hierarchy.
///
/// Derived from [hierarchyProvider]; updates automatically when the file
/// changes.  Returns an empty map while loading or on error.
///
/// Used by [WaveformCanvas] to look up metadata (e.g. [Variable.bitWidth])
/// when only the opaque [SignalEntry.signalRef] is known.
@riverpod
Map<String, Variable> signalVariablesMap(Ref ref) {
  final hierarchyAsync = ref.watch(hierarchyProvider);
  return hierarchyAsync.when(
    data: _buildVariablesMap,
    loading: () => const <String, Variable>{},
    error: (_, _) => const <String, Variable>{},
  );
}

/// Flat map from [Variable.fullPath] to [Variable] — the row-identity
/// counterpart of [signalVariablesMap]. fullPaths are unique per hierarchy
/// row even when FST aliasing gives many rows one signalRef, so this is the
/// correct resolver for tree-selection values.
@riverpod
Map<String, Variable> signalVariablesByPath(Ref ref) {
  final hierarchyAsync = ref.watch(hierarchyProvider);
  return hierarchyAsync.when(
    data: _buildVariablesByPathMap,
    loading: () => const <String, Variable>{},
    error: (_, _) => const <String, Variable>{},
  );
}

Map<String, Variable> _buildVariablesByPathMap(List<Scope> scopes) {
  final map = <String, Variable>{};
  void collect(List<Scope> items) {
    for (final scope in items) {
      for (final variable in scope.variables) {
        map[variable.fullPath] = variable;
      }
      collect(scope.childScopes);
    }
  }

  collect(scopes);
  return map;
}

Map<String, Variable> _buildVariablesMap(List<Scope> scopes) {
  final map = <String, Variable>{};
  void collect(List<Scope> items) {
    for (final scope in items) {
      for (final variable in scope.variables) {
        map[variable.signalRef] = variable;
      }
      collect(scope.childScopes);
    }
  }

  collect(scopes);
  return map;
}
