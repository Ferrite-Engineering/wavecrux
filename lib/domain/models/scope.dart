// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/models/variable.dart';

/// A node in the design hierarchy (module, block, VHDL architecture, …).
///
/// [childScopes] and [variables] are the **direct** children only; the full
/// subtree is reachable by recursing through [childScopes].
@immutable
class Scope {
  const Scope({
    required this.name,
    required this.type,
    required this.path,
    this.childScopes = const [],
    this.variables = const [],
  });

  /// Local (unqualified) scope name, e.g. `"cpu"`.
  final String name;

  /// Structural type of this scope.
  final ScopeType type;

  /// Full hierarchical path including this scope's name, e.g. `"top.cpu"`.
  final String path;

  /// Direct child scopes (not recursively expanded).
  final List<Scope> childScopes;

  /// Variables declared directly in this scope (not in child scopes).
  final List<Variable> variables;

  // ── computed ───────────────────────────────────────────────────────────────

  /// Total number of variables in this scope and all descendant scopes.
  int get totalVariableCount =>
      variables.length +
      childScopes.fold(0, (sum, s) => sum + s.totalVariableCount);

  // ── copyWith ───────────────────────────────────────────────────────────────

  Scope copyWith({
    String? name,
    ScopeType? type,
    String? path,
    List<Scope>? childScopes,
    List<Variable>? variables,
  }) => Scope(
    name: name ?? this.name,
    type: type ?? this.type,
    path: path ?? this.path,
    childScopes: childScopes ?? this.childScopes,
    variables: variables ?? this.variables,
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Scope) return false;
    if (name != other.name || type != other.type || path != other.path) {
      return false;
    }
    if (variables.length != other.variables.length ||
        childScopes.length != other.childScopes.length) {
      return false;
    }
    for (var i = 0; i < variables.length; i++) {
      if (variables[i] != other.variables[i]) return false;
    }
    for (var i = 0; i < childScopes.length; i++) {
      if (childScopes[i] != other.childScopes[i]) return false;
    }
    return true;
  }

  /// Hash on the identity fields; child content does not contribute to avoid
  /// O(n) hashing on every tree traversal.
  @override
  int get hashCode => Object.hash(name, type, path);

  @override
  String toString() =>
      'Scope(path: $path, type: $type, '
      'vars: ${variables.length}, children: ${childScopes.length})';
}
