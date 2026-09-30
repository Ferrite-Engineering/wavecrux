// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/search_mode.dart';
import 'package:wavecrux/domain/enums/signal_direction.dart';
import 'package:wavecrux/domain/enums/signal_type_category.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';

/// A single result returned by [SignalSearchService.search].
///
/// [nameMatchRange] is the `(start, end)` character range in [Variable.name]
/// that matched the query when [SearchMode.substring] was used. It is `null`
/// for glob matches (no single contiguous highlight) or when no pattern was
/// supplied.
@immutable
class SearchResult {
  const SearchResult({required this.variable, this.nameMatchRange});

  final Variable variable;

  /// Character range `(inclusive start, exclusive end)` within
  /// [Variable.name] that matched the search query.
  ///
  /// `null` when no highlight position is available.
  final (int, int)? nameMatchRange;

  bool get hasHighlight => nameMatchRange != null;
}

/// Pure-Dart service that filters a flat list of [Variable]s and returns
/// [SearchResult]s with optional match-highlight information.
///
/// All methods are static — this class is stateless and not instantiated.
class SignalSearchService {
  const SignalSearchService._();

  // ── Hierarchy helpers ────────────────────────────────────────────────────────

  /// Flattens all [Variable]s from [scopes] and their children into a single
  /// list with depth-first traversal order.
  static List<Variable> flattenVariables(List<Scope> scopes) {
    final result = <Variable>[];
    void collect(Scope scope) {
      result.addAll(scope.variables);
      scope.childScopes.forEach(collect);
    }

    scopes.forEach(collect);
    return result;
  }

  // ── Search ───────────────────────────────────────────────────────────────────

  /// Searches [variables] using the given criteria and returns matching
  /// [SearchResult]s in the same order they appear in [variables].
  ///
  /// - [query]: text typed by the user. Empty string matches everything.
  ///   GTKWave direction-prefix syntax is recognised: `+I+` (inputs only),
  ///   `+O+` (outputs only), `+IO+` (bidirectional only). When present the
  ///   prefix is stripped before name matching and the extracted direction
  ///   filter takes precedence over [selectedDirections].
  /// - [mode]: controls whether [query] is a substring pattern or glob.
  /// - [selectedCategories]: when non-null and non-empty, restricts results
  ///   to variables whose [VarType] belongs to one of the selected categories.
  ///   Null or empty = no type restriction (show all types).
  /// - [minBitWidth] / [maxBitWidth]: inclusive bit-width range filter.
  ///   `null` = unbounded.
  /// - [scopePath]: when non-empty, restricts to variables whose
  ///   [Variable.scopePath] equals [scopePath] or starts with `"$scopePath."`.
  /// - [selectedDirections]: when non-null and non-empty, restricts results to
  ///   variables whose [VarDirection] maps to one of the selected
  ///   [SignalDirection] values. Null or empty = no direction restriction.
  ///   Overridden by a direction prefix in [query] when one is present.
  static List<SearchResult> search({
    required List<Variable> variables,
    required String query,
    SearchMode mode = SearchMode.substring,
    Set<SignalTypeCategory>? selectedCategories,
    int? minBitWidth,
    int? maxBitWidth,
    String? scopePath,
    Set<SignalDirection>? selectedDirections,
  }) {
    final (effectiveQuery, prefixDirections) = _parseDirectionPrefix(query);
    final effectiveDirections =
        prefixDirections ??
        (selectedDirections == null || selectedDirections.isEmpty
            ? null
            : selectedDirections);

    final effectiveVarTypes = _resolveVarTypes(selectedCategories);
    final trimmedScope = (scopePath == null || scopePath.isEmpty)
        ? null
        : scopePath;

    final results = <SearchResult>[];
    for (final v in variables) {
      if (!_nameMatches(v.name, effectiveQuery, mode)) continue;
      if (!_varTypeMatches(v.varType, effectiveVarTypes)) continue;
      if (!_bitWidthMatches(v.bitWidth, minBitWidth, maxBitWidth)) continue;
      if (!_scopePathMatches(v.scopePath, trimmedScope)) continue;
      if (!_directionMatches(v.direction, effectiveDirections)) continue;

      results.add(
        SearchResult(
          variable: v,
          nameMatchRange: _computeHighlight(v.name, effectiveQuery, mode),
        ),
      );
    }
    return results;
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  /// Detects a GTKWave direction-prefix at the start of [query] and returns
  /// the stripped query plus the implied direction set, or `null` when no
  /// prefix is present.
  ///
  /// Recognised prefixes (case-sensitive, matching GTKWave):
  /// - `+IO+` → `{SignalDirection.inout}`
  /// - `+I+`  → `{SignalDirection.input}`
  /// - `+O+`  → `{SignalDirection.output}`
  static (String, Set<SignalDirection>?) _parseDirectionPrefix(String query) {
    if (query.startsWith('+IO+')) {
      return (query.substring(4), const {SignalDirection.inout});
    }
    if (query.startsWith('+I+')) {
      return (query.substring(3), const {SignalDirection.input});
    }
    if (query.startsWith('+O+')) {
      return (query.substring(3), const {SignalDirection.output});
    }
    return (query, null);
  }

  static Set<VarType>? _resolveVarTypes(Set<SignalTypeCategory>? categories) {
    if (categories == null || categories.isEmpty) return null;
    final types = <VarType>{};
    for (final cat in categories) {
      types.addAll(cat.varTypes);
    }
    return types;
  }

  static bool _nameMatches(String name, String query, SearchMode mode) {
    if (query.isEmpty) return true;
    return switch (mode) {
      SearchMode.substring => name.toLowerCase().contains(query.toLowerCase()),
      SearchMode.glob => _buildGlobRegex(query).hasMatch(name),
    };
  }

  static bool _varTypeMatches(VarType type, Set<VarType>? allowed) {
    if (allowed == null) return true;
    return allowed.contains(type);
  }

  static bool _bitWidthMatches(int? width, int? min, int? max) {
    if (min == null && max == null) return true;
    if (width == null) return false;
    if (min != null && width < min) return false;
    if (max != null && width > max) return false;
    return true;
  }

  static bool _scopePathMatches(String variableScopePath, String? filter) {
    if (filter == null) return true;
    return variableScopePath == filter ||
        variableScopePath.startsWith('$filter.');
  }

  static bool _directionMatches(
    VarDirection dir,
    Set<SignalDirection>? filter,
  ) {
    if (filter == null) return true;
    return filter.contains(SignalDirection.fromVarDirection(dir));
  }

  /// Returns the `(start, end)` highlight range for a substring match, or
  /// `null` when the match position cannot be pinpointed (glob or empty query).
  static (int, int)? _computeHighlight(
    String name,
    String query,
    SearchMode mode,
  ) {
    if (query.isEmpty || mode == SearchMode.glob) return null;
    final idx = name.toLowerCase().indexOf(query.toLowerCase());
    if (idx < 0) return null;
    return (idx, idx + query.length);
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
}
