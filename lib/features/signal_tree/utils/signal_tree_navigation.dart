// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/utils/signal_tree_rows.dart';

// Keyboard navigation over the flat row list the signal tree renders.
//
// The tree is one flat lazy list (see `signalTreeRowsInOrder`), so the
// parent/child relations a tree keyboard needs are recovered from each row's
// `indentLevel` rather than from nested widgets. Every function here is pure
// so the navigation rules are testable without pumping a widget.

/// The hierarchy object a row stands for: its [Scope] or its [Variable].
///
/// The instance, not a path, is the row's identity. Gate-level dumps contain
/// sibling scopes and variables that share a full path, so a path alone can
/// name two rows.
Object signalTreeRowItem(SignalTreeRow row) => switch (row) {
  ScopeRow(:final scope) => scope,
  VariableRow(:final variable) => variable,
};

/// Index of the scope row that contains the row at [index], or null for a
/// root scope.
///
/// Rows are flattened depth first, so the parent is the nearest earlier row
/// one indent level shallower.
int? signalTreeParentIndex(List<SignalTreeRow> rows, int index) {
  if (index <= 0 || index >= rows.length) return null;
  final level = rows[index].indentLevel;
  for (var i = index - 1; i >= 0; i--) {
    if (rows[i].indentLevel < level) return i;
  }
  return null;
}

/// Index of the first visible child of the scope row at [index], or null
/// when the row is a variable, is collapsed, or shows no children (a search
/// filter can leave an expanded scope with none).
int? signalTreeFirstChildIndex(List<SignalTreeRow> rows, int index) {
  if (index < 0 || index + 1 >= rows.length) return null;
  if (rows[index] is! ScopeRow) return null;
  return rows[index + 1].indentLevel > rows[index].indentLevel
      ? index + 1
      : null;
}

/// Where the keyboard's current row is after [rows] changed underneath it.
///
/// The current row is remembered as its hierarchy [item] and the index it
/// was last found at. In order of preference the result is:
///
/// 1. the row for [item] itself, when it is still visible;
/// 2. a row with the same path — a natural-sort toggle or a reload rebuilds
///    the hierarchy objects — nearest to [previousIndex];
/// 3. the nearest visible scope that contains it, so collapsing a subtree
///    leaves the keyboard on the scope that was collapsed;
/// 4. [previousIndex], clamped to the list.
///
/// Returns 0 for an empty list; callers check for rows before using it.
int resolveSignalTreeActiveIndex(
  List<SignalTreeRow> rows, {
  required Object? item,
  required int previousIndex,
}) {
  if (rows.isEmpty) return 0;
  final clamped = previousIndex.clamp(0, rows.length - 1);
  if (item == null) return clamped;
  if (identical(signalTreeRowItem(rows[clamped]), item)) return clamped;
  for (var i = 0; i < rows.length; i++) {
    if (identical(signalTreeRowItem(rows[i]), item)) return i;
  }

  final path = _pathOf(item);
  if (path == null) return clamped;
  int? samePath;
  for (var i = 0; i < rows.length; i++) {
    if (_pathOf(signalTreeRowItem(rows[i])) != path ||
        signalTreeRowItem(rows[i]).runtimeType != item.runtimeType) {
      continue;
    }
    if (samePath == null || (i - clamped).abs() < (samePath - clamped).abs()) {
      samePath = i;
    }
  }
  if (samePath != null) return samePath;

  final container = switch (item) {
    Variable(:final scopePath) => scopePath,
    Scope(path: final scopePath) => _parentPath(scopePath),
    _ => null,
  };
  if (container != null && container.isNotEmpty) {
    int? best;
    var bestLength = -1;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row is! ScopeRow) continue;
      final candidate = row.scope.path;
      final contains =
          container == candidate || container.startsWith('$candidate.');
      if (contains && candidate.length > bestLength) {
        best = i;
        bestLength = candidate.length;
      }
    }
    if (best != null) return best;
  }
  return clamped;
}

String? _pathOf(Object item) => switch (item) {
  Scope(:final path) => path,
  Variable(:final fullPath) => fullPath,
  _ => null,
};

String? _parentPath(String path) {
  final dot = path.lastIndexOf('.');
  return dot <= 0 ? null : path.substring(0, dot);
}
