// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/enums/search_mode.dart';
import 'package:wavecrux/domain/enums/signal_direction.dart';
import 'package:wavecrux/domain/enums/signal_type_category.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/services/signal_query/signal_search_service.dart';

part 'search_providers.g.dart';

// ── Filter model ───────────────────────────────────────────────────────────────

/// Immutable snapshot of all search filter criteria managed by the dialog.
@immutable
class SearchDialogFilter {
  const SearchDialogFilter({
    this.query = '',
    this.mode = SearchMode.substring,
    this.selectedCategories = const {},
    this.selectedDirections = const {},
    this.minBitWidth,
    this.maxBitWidth,
    this.scopePath,
  });

  /// Text entered in the search field.
  final String query;

  /// Whether [query] is interpreted as a substring or glob pattern.
  final SearchMode mode;

  /// Type categories selected as filters; empty = no type restriction.
  final Set<SignalTypeCategory> selectedCategories;

  /// Port direction filter; empty = no direction restriction.
  final Set<SignalDirection> selectedDirections;

  /// Minimum bit-width (inclusive). `null` = no lower bound.
  final int? minBitWidth;

  /// Maximum bit-width (inclusive). `null` = no upper bound.
  final int? maxBitWidth;

  /// Scope-path prefix filter. `null` or empty = all scopes.
  final String? scopePath;

  /// `true` when no filter criteria have been set (shows all signals).
  bool get isDefault =>
      query.isEmpty &&
      selectedCategories.isEmpty &&
      selectedDirections.isEmpty &&
      minBitWidth == null &&
      maxBitWidth == null &&
      (scopePath == null || scopePath!.isEmpty);

  // ── copyWith ─────────────────────────────────────────────────────────────────

  SearchDialogFilter copyWith({
    String? query,
    SearchMode? mode,
    Set<SignalTypeCategory>? selectedCategories,
    Set<SignalDirection>? selectedDirections,
    int? minBitWidth,
    int? maxBitWidth,
    String? scopePath,
    bool clearMinBitWidth = false,
    bool clearMaxBitWidth = false,
    bool clearScopePath = false,
    bool clearSelectedDirections = false,
  }) => SearchDialogFilter(
    query: query ?? this.query,
    mode: mode ?? this.mode,
    selectedCategories: selectedCategories ?? this.selectedCategories,
    selectedDirections: clearSelectedDirections
        ? const {}
        : (selectedDirections ?? this.selectedDirections),
    minBitWidth: clearMinBitWidth ? null : (minBitWidth ?? this.minBitWidth),
    maxBitWidth: clearMaxBitWidth ? null : (maxBitWidth ?? this.maxBitWidth),
    scopePath: clearScopePath ? null : (scopePath ?? this.scopePath),
  );

  // ── equality ──────────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SearchDialogFilter) return false;
    if (query != other.query) return false;
    if (mode != other.mode) return false;
    if (minBitWidth != other.minBitWidth) return false;
    if (maxBitWidth != other.maxBitWidth) return false;
    if (scopePath != other.scopePath) return false;
    if (selectedCategories.length != other.selectedCategories.length) {
      return false;
    }
    if (!selectedCategories.containsAll(other.selectedCategories)) {
      return false;
    }
    if (selectedDirections.length != other.selectedDirections.length) {
      return false;
    }
    return selectedDirections.containsAll(other.selectedDirections);
  }

  @override
  int get hashCode => Object.hash(
    query,
    mode,
    minBitWidth,
    maxBitWidth,
    scopePath,
    selectedCategories.fold<int>(0, (acc, e) => acc ^ e.hashCode),
    selectedDirections.fold<int>(0, (acc, e) => acc ^ e.hashCode),
  );
}

// ── Filter notifier ────────────────────────────────────────────────────────────

/// Manages the active search dialog filter criteria.
///
/// The dialog calls [reset] in its `initState` so each dialog session starts
/// with a clean slate.
@riverpod
class SearchDialogFilterNotifier extends _$SearchDialogFilterNotifier {
  @override
  SearchDialogFilter build() => const SearchDialogFilter();

  void setQuery(String query) => state = state.copyWith(query: query);
  void setMode(SearchMode mode) => state = state.copyWith(mode: mode);

  /// Adds or removes [category] from the selected type filter set.
  void toggleCategory(SignalTypeCategory category) {
    final next = Set<SignalTypeCategory>.from(state.selectedCategories);
    if (next.contains(category)) {
      next.remove(category);
    } else {
      next.add(category);
    }
    state = state.copyWith(selectedCategories: next);
  }

  /// Adds or removes [direction] from the selected direction filter set.
  void toggleDirection(SignalDirection direction) {
    final next = Set<SignalDirection>.from(state.selectedDirections);
    if (next.contains(direction)) {
      next.remove(direction);
    } else {
      next.add(direction);
    }
    state = state.copyWith(selectedDirections: next);
  }

  void setMinBitWidth(int? value) => value == null
      ? state = state.copyWith(clearMinBitWidth: true)
      : state = state.copyWith(minBitWidth: value);

  void setMaxBitWidth(int? value) => value == null
      ? state = state.copyWith(clearMaxBitWidth: true)
      : state = state.copyWith(maxBitWidth: value);

  void setScopePath(String? path) => (path == null || path.isEmpty)
      ? state = state.copyWith(clearScopePath: true)
      : state = state.copyWith(scopePath: path);

  /// Resets all filter criteria to their defaults.
  void reset() => state = const SearchDialogFilter();
}

// ── Search results provider ────────────────────────────────────────────────────

/// Derived provider that runs [SignalSearchService.search] against the current
/// hierarchy using the active [SearchDialogFilter].
///
/// Returns an empty list when no waveform is loaded.
///
/// [hierarchyProvider] is declared as a dependency so that Riverpod allows this
/// provider to be read from inside a sub-container where [hierarchyProvider] is
/// overridden (the per-tab [ProviderContainer] passed through
/// [SignalSearchDialog.show]). Without this declaration, reading
/// [searchResultsProvider] from a sub-container that overrides one of its
/// transitive dependencies causes a Riverpod assertion error.
@Riverpod(dependencies: [hierarchy])
List<SearchResult> searchResults(Ref ref) {
  final hierarchyAsync = ref.watch(hierarchyProvider);
  final filter = ref.watch(searchDialogFilterProvider);

  final scopes = hierarchyAsync.value ?? const [];
  final variables = SignalSearchService.flattenVariables(scopes);

  return SignalSearchService.search(
    variables: variables,
    query: filter.query,
    mode: filter.mode,
    selectedCategories: filter.selectedCategories.isEmpty
        ? null
        : filter.selectedCategories,
    minBitWidth: filter.minBitWidth,
    maxBitWidth: filter.maxBitWidth,
    scopePath: filter.scopePath,
    selectedDirections: filter.selectedDirections.isEmpty
        ? null
        : filter.selectedDirections,
  );
}
