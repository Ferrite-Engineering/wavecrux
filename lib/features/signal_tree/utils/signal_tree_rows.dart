// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/utils/variable_tree_order.dart';

/// Fixed height of every signal-tree row (scope headers and variable
/// leaves). Shared by the row widgets and the panel's `itemExtent` so the
/// lazy list can compute scroll geometry without building rows.
const double kSignalTreeRowHeight = 28;

/// One visible row of the signal hierarchy tree.
///
/// The tree renders as a single flat lazy list ([SignalTreePanel]'s
/// `ListView.builder`), not as nested widgets: gate-level dumps put tens of
/// thousands of variables in one scope, and eagerly building an expanded
/// scope's children cost a superlinear synchronous frame (19 s at 16k rows,
/// minutes at 64k — the Kevin/GF180 netlist). Flattening the visible rows
/// here and letting the viewport build ~30 of them is the same
/// materialize-only-the-viewport philosophy as the canvas's
/// `LaneGeometryIndex`.
sealed class SignalTreeRow {
  const SignalTreeRow({required this.indentLevel});

  /// Nesting depth — drives the row's left padding.
  final int indentLevel;
}

/// A scope header row (expand/collapse arrow, icon, name, count badge).
class ScopeRow extends SignalTreeRow {
  const ScopeRow({required this.scope, required super.indentLevel});

  final Scope scope;
}

/// A variable leaf row.
class VariableRow extends SignalTreeRow {
  const VariableRow({required this.variable, required super.indentLevel});

  final Variable variable;
}

/// Flattens the hierarchy into the exact top-to-bottom row list the tree
/// shows: every visible scope contributes a header row; an expanded scope
/// is followed by its child scopes (recursively), then its variables —
/// the same order as [variablesInTreeOrder], whose [Variable] sequence this
/// function's [VariableRow]s must always match (a Shift+click range
/// resolved through one must agree with rows rendered through the other).
///
/// [searchQuery] applies the tree's case-insensitive name filter: scopes
/// with no matching descendant are pruned and non-matching variables are
/// dropped (a shared [ScopeMatchIndex] keeps the two paths agreeing). Pass
/// [matchIndex] to reuse an index already built for the same query.
List<SignalTreeRow> signalTreeRowsInOrder(
  List<Scope> rootScopes, {
  required Set<String> expandedPaths,
  String searchQuery = '',
  ScopeMatchIndex? matchIndex,
}) {
  final index = matchIndex ?? ScopeMatchIndex.build(rootScopes, searchQuery);
  final rows = <SignalTreeRow>[];

  void visit(Scope scope, int indentLevel) {
    rows.add(ScopeRow(scope: scope, indentLevel: indentLevel));
    if (!expandedPaths.contains(scope.path)) return;
    for (final child in scope.childScopes) {
      if (index.matchesScope(child)) visit(child, indentLevel + 1);
    }
    for (final variable in scope.variables) {
      if (index.matchesVariable(variable)) {
        rows.add(VariableRow(variable: variable, indentLevel: indentLevel + 1));
      }
    }
  }

  for (final root in rootScopes) {
    if (index.matchesScope(root)) visit(root, 0);
  }
  return rows;
}
