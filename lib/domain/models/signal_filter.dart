// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/variable.dart';

/// Criteria for searching variables in the signal hierarchy.
///
/// All non-null fields are ANDed together. A [SignalFilter] with all-null
/// fields ([matchesAll] == `true`) matches every variable.
///
/// **Name matching rules:**
/// - `null` or empty → matches all names.
/// - Pattern containing `*` or `?` → glob match (case-insensitive).
///   - `*` matches any sequence of characters (including empty).
///   - `?` matches exactly one character.
/// - Plain string → case-insensitive substring search.
@immutable
class SignalFilter {
  const SignalFilter({
    this.namePattern,
    this.varTypes,
    this.scopePath,
    this.minBitWidth,
    this.maxBitWidth,
  });

  /// Glob pattern or substring for the signal name. `null` = match all.
  final String? namePattern;

  /// Restrict to these variable types. `null` = allow all types.
  final Set<VarType>? varTypes;

  /// Restrict to variables whose [Variable.scopePath] equals this path or
  /// starts with `"$scopePath."`. `null` = all scopes.
  final String? scopePath;

  /// Minimum bit-width (inclusive). `null` = no lower bound.
  final int? minBitWidth;

  /// Maximum bit-width (inclusive). `null` = no upper bound.
  final int? maxBitWidth;

  // ── computed ───────────────────────────────────────────────────────────────

  /// `true` when all fields are `null` — the filter matches every variable.
  bool get matchesAll =>
      namePattern == null &&
      varTypes == null &&
      scopePath == null &&
      minBitWidth == null &&
      maxBitWidth == null;

  // ── matching ───────────────────────────────────────────────────────────────

  /// Returns `true` if [variable] satisfies every criterion in this filter.
  bool matches(Variable variable) =>
      _matchesName(variable.name) &&
      _matchesScopePath(variable.scopePath) &&
      _matchesVarType(variable.varType) &&
      _matchesBitWidth(variable.bitWidth);

  bool _matchesName(String name) {
    final pattern = namePattern;
    if (pattern == null || pattern.isEmpty) return true;
    if (pattern.contains('*') || pattern.contains('?')) {
      return _buildGlobRegex(pattern).hasMatch(name);
    }
    return name.toLowerCase().contains(pattern.toLowerCase());
  }

  bool _matchesScopePath(String variableScopePath) {
    final filter = scopePath;
    if (filter == null || filter.isEmpty) return true;
    return variableScopePath == filter ||
        variableScopePath.startsWith('$filter.');
  }

  bool _matchesVarType(VarType type) {
    final allowed = varTypes;
    if (allowed == null) return true;
    return allowed.contains(type);
  }

  bool _matchesBitWidth(int? width) {
    final min = minBitWidth;
    final max = maxBitWidth;
    if (min == null && max == null) return true;
    if (width == null) return false;
    if (min != null && width < min) return false;
    if (max != null && width > max) return false;
    return true;
  }

  static RegExp _buildGlobRegex(String glob) {
    final sb = StringBuffer('^');
    for (final rune in glob.runes) {
      final ch = String.fromCharCode(rune);
      switch (ch) {
        case '*':
          sb.write('.*');
        case '?':
          sb.write('.');
        default:
          sb.write(RegExp.escape(ch));
      }
    }
    sb.write(r'$');
    return RegExp(sb.toString(), caseSensitive: false);
  }

  // ── copyWith ───────────────────────────────────────────────────────────────

  SignalFilter copyWith({
    String? namePattern,
    Set<VarType>? varTypes,
    String? scopePath,
    int? minBitWidth,
    int? maxBitWidth,
    bool clearNamePattern = false,
    bool clearVarTypes = false,
    bool clearScopePath = false,
    bool clearMinBitWidth = false,
    bool clearMaxBitWidth = false,
  }) => SignalFilter(
    namePattern: clearNamePattern ? null : (namePattern ?? this.namePattern),
    varTypes: clearVarTypes ? null : (varTypes ?? this.varTypes),
    scopePath: clearScopePath ? null : (scopePath ?? this.scopePath),
    minBitWidth: clearMinBitWidth ? null : (minBitWidth ?? this.minBitWidth),
    maxBitWidth: clearMaxBitWidth ? null : (maxBitWidth ?? this.maxBitWidth),
  );

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SignalFilter) return false;
    if (namePattern != other.namePattern) return false;
    if (scopePath != other.scopePath) return false;
    if (minBitWidth != other.minBitWidth) return false;
    if (maxBitWidth != other.maxBitWidth) return false;
    // Set equality: same elements regardless of insertion order.
    final a = varTypes;
    final b = other.varTypes;
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  @override
  int get hashCode => Object.hash(
    namePattern,
    scopePath,
    minBitWidth,
    maxBitWidth,
    // XOR is commutative → order-independent hash for the Set.
    varTypes?.fold<int>(0, (acc, e) => acc ^ e.hashCode),
  );

  @override
  String toString() =>
      'SignalFilter('
      'namePattern: $namePattern, '
      'varTypes: $varTypes, '
      'scopePath: $scopePath, '
      'bitWidth: $minBitWidth–$maxBitWidth)';
}
