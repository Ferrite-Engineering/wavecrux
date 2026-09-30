// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';

/// Precomputed answer to "does this scope contain a matching variable
/// anywhere below it?" for one search query.
///
/// Built in a single bottom-up pass over the hierarchy: every scope and every
/// variable name is examined exactly once, and the query is lower-cased once
/// for the whole traversal. The alternative — asking each scope independently
/// while descending — rescans a subtree once per ancestor level, so the cost
/// is depth × variable count. On a gate-level dump (1.3M variables, deep
/// bit-blasted hierarchies) that turns one keystroke into seconds of
/// synchronous work on the UI isolate.
///
/// Scopes are identified by [Scope.path], which is unique per hierarchy row.
@immutable
class ScopeMatchIndex {
  const ScopeMatchIndex._(this._query, this._matchingPaths);

  /// Builds the index for [query] over [rootScopes].
  ///
  /// An empty [query] yields an index that matches everything without
  /// traversing at all.
  factory ScopeMatchIndex.build(List<Scope> rootScopes, String query) {
    final q = query.toLowerCase();
    if (q.isEmpty) return const ScopeMatchIndex._('', <String>{});

    final matching = <String>{};
    var visits = 0;

    bool visit(Scope scope) {
      visits++;
      var hasMatch = false;
      for (final variable in scope.variables) {
        if (variable.name.toLowerCase().contains(q)) {
          hasMatch = true;
          break;
        }
      }
      for (final child in scope.childScopes) {
        // Every child is visited even after a match is found: the child's own
        // membership is needed when the tree descends into it.
        if (visit(child)) hasMatch = true;
      }
      if (hasMatch) matching.add(scope.path);
      return hasMatch;
    }

    rootScopes.forEach(visit);
    debugLastBuildVisits = visits;
    debugTraversals++;
    return ScopeMatchIndex._(q, matching);
  }

  /// Number of scope visits performed by the most recent [build] call.
  ///
  /// Read by the complexity guard test to assert the build stays linear in
  /// scope count rather than scaling with hierarchy depth.
  @visibleForTesting
  static int debugLastBuildVisits = 0;

  /// Number of [build] calls that walked the hierarchy (a non-empty query).
  ///
  /// Read by the signal tree's search tests: one query must cost one walk,
  /// shared by the scope expansion and the row list.
  @visibleForTesting
  static int debugTraversals = 0;

  /// The lower-cased query this index was built for. Empty means "no filter".
  final String _query;

  final Set<String> _matchingPaths;

  /// True when no query is active, so every scope and variable passes.
  bool get isEmpty => _query.isEmpty;

  /// The set of scope paths that contain at least one matching variable.
  ///
  /// Empty when [isEmpty] — an inactive filter matches by short-circuit, not
  /// by membership.
  Set<String> get matchingScopePaths => _matchingPaths;

  /// True when [scope] or any descendant has a matching variable.
  bool matchesScope(Scope scope) =>
      _query.isEmpty || _matchingPaths.contains(scope.path);

  /// True when [variable]'s name case-insensitively contains the query.
  bool matchesVariable(Variable variable) =>
      _query.isEmpty || variable.name.toLowerCase().contains(_query);
}

/// Flattens the signal hierarchy into the top-to-bottom order the signal
/// tree renders: for each scope, child scopes first, then variables —
/// matching `ScopeTreeNode`'s row layout.
///
/// When [expandedPaths] is non-null, variables inside a collapsed scope are
/// omitted and collapsed scopes are not descended into — the result is
/// exactly the rows currently visible on screen (used to resolve a
/// Shift+click range). When null, every scope is treated as expanded — the
/// result is the full deterministic tree order (used to order a bulk-add so
/// signals land in the viewer in the order the user sees in the tree).
///
/// [searchQuery] applies the same case-insensitive name filter the tree
/// widgets apply: scopes with no matching descendant are pruned and
/// non-matching variables are dropped. Pass [matchIndex] to share one
/// prebuilt index with a caller that also flattens rows for the same query.
List<Variable> variablesInTreeOrder(
  List<Scope> rootScopes, {
  Set<String>? expandedPaths,
  String searchQuery = '',
  ScopeMatchIndex? matchIndex,
}) {
  final index = matchIndex ?? ScopeMatchIndex.build(rootScopes, searchQuery);
  final result = <Variable>[];

  void visit(Scope scope) {
    if (expandedPaths != null && !expandedPaths.contains(scope.path)) {
      return;
    }
    for (final child in scope.childScopes) {
      if (index.matchesScope(child)) visit(child);
    }
    if (index.isEmpty) {
      result.addAll(scope.variables);
    } else {
      result.addAll(scope.variables.where(index.matchesVariable));
    }
  }

  for (final root in rootScopes) {
    if (index.matchesScope(root)) visit(root);
  }
  return result;
}
