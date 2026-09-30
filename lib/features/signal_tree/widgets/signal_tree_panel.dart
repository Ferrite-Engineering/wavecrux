// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_async/crux_async.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/signal_tree/utils/signal_tree_rows.dart';
import 'package:wavecrux/features/signal_tree/utils/variable_tree_order.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_row_list.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// The left-pane signal hierarchy browser (SST panel).
///
/// Displays the design hierarchy from the currently loaded waveform as an
/// expandable tree. When no file is loaded, shows an empty-state prompt. A
/// search box filters visible scopes and variables.
///
/// The tree is a single flat `ListView.builder` over `signalTreeRowsInOrder`
/// with a fixed `itemExtent` — only the ~viewport rows are ever built. The
/// list, and the keyboard control over it, is [SignalTreeRowList].
/// Nested/eager child rendering is forbidden here: gate-level dumps put 64k+
/// variables in one scope, and building them eagerly cost a superlinear
/// synchronous frame (minutes at 64k rows). Recomputing the flat row list is
/// O(visible rows) and takes ~10 ms even at 1.3M variables.
///
/// Uses [ConsumerStatefulWidget] because it owns the search [TextEditingController].
class SignalTreePanel extends ConsumerStatefulWidget {
  const SignalTreePanel({super.key});

  @override
  ConsumerState<SignalTreePanel> createState() => _SignalTreePanelState();
}

class _SignalTreePanelState extends ConsumerState<SignalTreePanel> {
  final _searchController = TextEditingController();
  late final ScrollController _scrollController;

  /// Token of the most recently handled cross-probe reveal — the tree browser's
  /// counterpart of the canvas dedupe. See [_maybeRevealInTree].
  int? _handledRevealToken;

  // ── search: debounce + one index per query ──────────────────────────────────
  //
  // Filtering walks the whole hierarchy (1.3M variables on a gate-level dump),
  // and it used to run on every keystroke — twice: once to expand the matching
  // scopes, once more to flatten the rows. The field now pushes its text to
  // the query provider only once typing pauses for [_kSearchDebounce], and a
  // query's match index is built once and shared by both.

  /// Same settle delay the waveform canvas waits after a scroll.
  static const Duration _kSearchDebounce = Duration(milliseconds: 120);

  final _searchDebounce = Debouncer(duration: _kSearchDebounce);

  List<Scope>? _matchIndexScopes;
  String? _matchIndexQuery;
  ScopeMatchIndex? _matchIndex;

  /// The match index for [query] over [scopes], built at most once per
  /// (hierarchy, query) pair.
  ScopeMatchIndex _matchIndexFor(List<Scope> scopes, String query) {
    final cached = _matchIndex;
    if (cached != null &&
        identical(_matchIndexScopes, scopes) &&
        _matchIndexQuery == query) {
      return cached;
    }
    final built = ScopeMatchIndex.build(scopes, query);
    _matchIndexScopes = scopes;
    _matchIndexQuery = query;
    _matchIndex = built;
    return built;
  }

  void _onSearchChanged(String text) {
    _searchDebounce.run(() {
      if (!mounted) return;
      ref.read(signalSearchQueryProvider.notifier).setQuery(query: text);
    });
  }

  /// The field's clear button: applies at once, and drops a keystroke still
  /// waiting out the debounce so it cannot put the query back.
  void _clearSearch() {
    _searchDebounce.cancel();
    _searchController.clear();
    ref.read(signalSearchQueryProvider.notifier).clear();
  }

  @override
  void initState() {
    super.initState();
    // Seed both controllers from the per-tab session state so a restored
    // session shows the same scroll position and search text the user left.
    // The controllers are widget-lifetime state and cannot themselves persist;
    // the backing providers (restored from the session sidecar) are the source
    // of truth.
    _scrollController = ScrollController(
      initialScrollOffset: ref.read(signalTreeScrollProvider),
    )..addListener(_onScroll);
    _searchController.text = ref.read(signalSearchQueryProvider);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    ref
        .read(signalTreeScrollProvider.notifier)
        .setOffset(
          _scrollController.offset,
        );
  }

  @override
  void dispose() {
    _searchDebounce.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── cross-probe auto-reveal ─────────────────────────────────────────────────

  /// Applies a reveal request to the hierarchy browser if it is new (token not
  /// yet handled) AND the target variable is already indexed in this tab's
  /// hierarchy. Driven by both the `revealSignalRequestProvider` listener and a
  /// one-shot read in `build`.
  ///
  /// The token is consumed ONLY once the variable resolves. A cross-probe that
  /// opens a fresh waveform (the SimCrux "Debug in WaveCrux" handoff and the
  /// reverse single-signal cross-probe both do) writes the reveal request before
  /// this tab's `hierarchyProvider` async has resolved, so the first call here
  /// finds nothing. Leaving the token unhandled lets the panel try again: `build`
  /// watches `hierarchyProvider`, so the load transition rebuilds the panel, this
  /// runs once more with the still-unhandled request — now resolvable — and the
  /// reveal fires. This rebuild-driven retry replaced a fixed frame-budget retry
  /// that gave up (and permanently consumed the token) before a large file
  /// finished indexing, which is why the tree never expanded on a real handoff.
  void _maybeRevealInTree(RevealSignalRequest? request) {
    if (request == null) return;
    if (request.token == _handledRevealToken) return;
    final variable = ref.read(signalVariablesByPathProvider)[request.fullPath];
    if (variable == null) return; // not indexed yet — a later rebuild retries.
    _handledRevealToken = request.token;
    _revealInTree(variable);
  }

  /// Expands the ancestor scopes of the cross-probed [variable] so its leaf row
  /// materializes, then scrolls it into view. The leaf already highlights itself
  /// (VariableTreeLeaf watches `selectedVariablesProvider`, which the inbound
  /// handler set), so this only has to expand + scroll.
  ///
  /// The expansion is deferred to a post-frame callback rather than run inline:
  /// a reveal arrives via `revealSignalRequestProvider`'s `ref.listen` (or a
  /// one-shot `build` read), and mutating `expandedScopesProvider` from inside
  /// that dispatch applies the state but the `build`-time `ref.watch` on it does
  /// NOT reliably schedule a rebuild — so the row list stays collapsed even
  /// though the provider reports the scope expanded (the observed bug). Running
  /// the mutation after the frame settles lets the watch schedule its rebuild
  /// normally. The canvas guards its own group-collapse mutation the same way.
  void _revealInTree(Variable variable) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(expandedScopesProvider.notifier)
          .expandAncestorsOf(variable.scopePath);
      // Scroll on the NEXT frame, after the expansion rebuilds the flat row
      // list; `_scrollTreeTo` itself retries until the list's scroll extent has
      // grown to include the freshly-materialized row.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollTreeTo(variable.fullPath);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Centers the leaf row for [fullPath] in the tree's viewport, if it is
  /// present in the current (expanded, possibly search-filtered) row list and
  /// not already fully visible.
  ///
  /// Converges across a few frames rather than scrolling once. The tree is a
  /// lazy `ListView.builder` with a fixed `itemExtent`, so its scrollable only
  /// grows `maxScrollExtent` toward the true content height as rows are actually
  /// scrolled into the built range — right after the reveal's [expandAncestorsOf]
  /// adds a row, `maxScrollExtent` still reflects the shorter list. A single
  /// `animateTo` therefore clamps to a stale max and strands a row near the
  /// bottom just below the fold (the observed bug: a cross-probed signal in the
  /// last scope expanded but never scrolled fully into view). Each attempt jumps
  /// to the current max to force the sliver to extend, then retries next frame
  /// until the true [target] is reachable, and finishes with a smooth animate.
  void _scrollTreeTo(String fullPath, {int attemptsLeft = 8}) {
    void retry() {
      if (attemptsLeft <= 0) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollTreeTo(fullPath, attemptsLeft: attemptsLeft - 1);
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }

    if (!_scrollController.hasClients) {
      retry();
      return;
    }
    final scopes = ref.read(hierarchyProvider).value;
    if (scopes == null || scopes.isEmpty) return;
    final query = ref.read(signalSearchQueryProvider);
    final rows = signalTreeRowsInOrder(
      scopes,
      expandedPaths: ref.read(expandedScopesProvider),
      searchQuery: query,
      matchIndex: _matchIndexFor(scopes, query),
    );
    final index = rows.indexWhere(
      (r) => r is VariableRow && r.variable.fullPath == fullPath,
    );
    if (index < 0) return;
    final position = _scrollController.position;
    final viewportH = position.viewportDimension;
    final rowTop = index * kSignalTreeRowHeight;
    final rowBottom = rowTop + kSignalTreeRowHeight;
    if (rowTop >= position.pixels && rowBottom <= position.pixels + viewportH) {
      return; // already fully visible — don't disturb the viewport.
    }
    // Content-based target, computed from the known row count / itemExtent
    // rather than the lazily-grown `maxScrollExtent` so it targets the row's
    // true position even before the sliver has measured that far.
    final contentMax = (rows.length * kSignalTreeRowHeight - viewportH).clamp(
      0.0,
      double.infinity,
    );
    final target = (rowTop - (viewportH - kSignalTreeRowHeight) / 2).clamp(
      0.0,
      contentMax,
    );
    // The lazy sliver won't let us reach `target` yet: jump to as far as it
    // currently allows (which builds the next rows and grows its extent) and
    // retry next frame to converge.
    if (position.maxScrollExtent + 0.5 < target) {
      _scrollController.jumpTo(position.maxScrollExtent);
      retry();
      return;
    }
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final hierarchyAsync = ref.watch(hierarchyProvider);
    final query = ref.watch(signalSearchQueryProvider);

    // Auto-expand scopes that contain matching variables while a query is
    // active; restore the saved expansion state when the query is cleared.
    ref
      ..listen<String>(signalSearchQueryProvider, (_, next) {
        final scopes = ref.read(hierarchyProvider).value ?? const <Scope>[];
        final notifier = ref.read(expandedScopesProvider.notifier);
        if (next.isEmpty) {
          notifier.restoreState();
        } else {
          notifier.expandMatchingScopes(
            scopes,
            next,
            matchIndex: _matchIndexFor(scopes, next),
          );
        }
      })
      // Auto-reveal a cross-probed signal in the hierarchy browser: expand its
      // ancestor scopes and scroll it into view (it highlights itself via
      // selectedVariablesProvider). The one-shot read below handles a reveal
      // written before this panel mounted; the listener handles later ones.
      ..listen<RevealSignalRequest?>(revealSignalRequestProvider, (_, next) {
        _maybeRevealInTree(next);
      });
    _maybeRevealInTree(ref.read(revealSignalRequestProvider));

    return Semantics(
      label: l10n.accessibilitySignalTreeRegion,
      container: true,
      // Header buttons, search field, tree: Tab visits them in that order
      // wherever the panel is hosted, instead of being sorted by position
      // against whatever sits beside it.
      child: FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelHeader(
              query: query,
              searchController: _searchController,
              onSearchChanged: _onSearchChanged,
              onSearchCleared: _clearSearch,
            ),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: hierarchyAsync.when(
                data: (scopes) {
                  if (scopes.isEmpty) {
                    return CruxPanelEmptyState(
                      message: l10n.signalTreeNoWaveform,
                    );
                  }

                  final rows = signalTreeRowsInOrder(
                    scopes,
                    expandedPaths: ref.watch(expandedScopesProvider),
                    searchQuery: query,
                    matchIndex: _matchIndexFor(scopes, query),
                  );

                  if (rows.isEmpty) {
                    return CruxPanelEmptyState(
                      message: l10n.signalTreeNoResults,
                    );
                  }

                  return SignalTreeRowList(
                    rows: rows,
                    scrollController: _scrollController,
                  );
                },
                loading: () => _fitOrScroll(
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        l10n.signalTreeLoading,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                error: (_, _) =>
                    CruxPanelEmptyState(message: l10n.signalTreeError),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centres [child] when the region is tall enough and scrolls it when it is
/// not, so a fixed-height state stack never clips in a dragged-short panel.
///
/// The empty and error branches above delegate to `CruxPanelEmptyState`, which
/// carries this same guard; the loading branch builds its own spinner stack and
/// so needs its own. Measured before the fix: 64 px of content in a 53 px dock
/// region — `RenderFlex overflowed by 11 pixels` (integration run 30591309796).
Widget _fitOrScroll(Widget child) => LayoutBuilder(
  builder: (context, constraints) {
    if (!constraints.hasBoundedHeight) return Center(child: child);
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(child: child),
      ),
    );
  },
);

/// Header row: panel title, search box, expand/collapse buttons.
class _PanelHeader extends ConsumerWidget {
  const _PanelHeader({
    required this.query,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSearchCleared,
  });

  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final hierarchyAsync = ref.watch(hierarchyProvider);
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);
    final headerButtonHit = metrics.isTouch ? metrics.touchTarget : 28.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title + toolbar
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.panelSignalTree,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.unfold_more, size: metrics.iconSize * 0.75),
                tooltip: l10n.signalTreeExpandAll,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: headerButtonHit,
                  minHeight: headerButtonHit,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: hierarchyAsync.value?.isNotEmpty ?? false
                    ? () => ref
                          .read(expandedScopesProvider.notifier)
                          .expandAll(hierarchyAsync.requireValue)
                    : null,
              ),
              IconButton(
                icon: Icon(Icons.unfold_less, size: metrics.iconSize * 0.75),
                tooltip: l10n.signalTreeCollapseAll,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: headerButtonHit,
                  minHeight: headerButtonHit,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: hierarchyAsync.value?.isNotEmpty ?? false
                    ? () => ref
                          .read(expandedScopesProvider.notifier)
                          .collapseAll()
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Search box. Its own semantics container: otherwise the field
          // became the node that also carried the panel's region label and
          // header text, so it was announced as "Signal browser Signal Tree
          // Search signals…", and the header buttons were its children.
          Semantics(
            container: true,
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              style: theme.textTheme.bodySmall,
              decoration: InputDecoration(
                hintText: l10n.signalTreeSearchHint,
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                prefixIcon: const Icon(Icons.search, size: 16),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 30,
                  minHeight: 30,
                ),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        tooltip: l10n.signalTreeClearSearchTooltip,
                        icon: const Icon(Icons.clear, size: 14),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        onPressed: onSearchCleared,
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
