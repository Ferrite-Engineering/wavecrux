// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart'
    show announceCrux, showCruxInfoSnack;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/signal_tree/utils/signal_tree_rows.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_menu_anchor.dart';
import 'package:wavecrux/features/viewer/providers/signal_load_progress_provider.dart';
import 'package:wavecrux/features/viewer/widgets/signal_removal_feedback.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/shared/widgets/platform_context_menu.dart';

/// The header row of a [Scope] in the signal hierarchy: icon, name,
/// recursive [Scope.totalVariableCount] badge, expand/collapse arrow.
///
/// Renders ONLY the header. The scope's children are separate rows of the
/// panel's flat lazy list (see `signalTreeRowsInOrder`) — this widget must
/// never render descendants inline again; eager child builds cost a
/// superlinear synchronous frame on gate-level scopes (minutes at 64k rows).
/// Tap to expand/collapse. Right-click for context menu.
///
/// For a screen reader the row is one node: a button named after the scope,
/// with its expanded state and its signal count as the value. The keyboard
/// reaches it through `SignalTreeRowList`, which owns the tree's single Tab
/// stop and tells the row when it is the one the keyboard is on.
class ScopeTreeNode extends ConsumerWidget {
  const ScopeTreeNode({
    required this.scope,
    this.indentLevel = 0,
    this.keyboardFocused = false,
    this.onTapped,
    this.onFocusRequested,
    super.key,
  });

  final Scope scope;

  /// Nesting depth — drives left padding for child rows.
  final int indentLevel;

  /// Whether the tree has keyboard focus and this is its current row: the
  /// row draws a focus ring and reports focus to assistive technology.
  final bool keyboardFocused;

  /// Called when the row is clicked or tapped, before it toggles, so the tree
  /// can make it the keyboard's current row.
  final VoidCallback? onTapped;

  /// Called when assistive technology asks to focus this row.
  final VoidCallback? onFocusRequested;

  static const double _kIndent = 16;
  static const double _kRowHeight = kSignalTreeRowHeight;

  /// Whether [scope] has anything to expand.
  static bool hasContent(Scope scope) =>
      scope.childScopes.isNotEmpty || scope.variables.isNotEmpty;

  /// Expands or collapses [scope] — what a click on its row does. No-op for a
  /// scope with nothing in it.
  static void toggle(WidgetRef ref, Scope scope) {
    if (hasContent(scope)) {
      ref.read(expandedScopesProvider.notifier).toggle(scope.path);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final expandedPaths = ref.watch(expandedScopesProvider);
    final isExpanded = expandedPaths.contains(scope.path);

    final hasContent = ScopeTreeNode.hasContent(scope);
    final deviceClass = ref.watch(deviceClassProvider);
    final enableLongPress = shouldEnableLongPressContextMenu(
      deviceClass,
      theme.platform,
    );

    return Semantics(
      container: true,
      button: true,
      label: scope.name,
      value: scope.totalVariableCount > 0
          ? l10n.signalTreeSignalCount(scope.totalVariableCount)
          : null,
      expanded: hasContent ? isExpanded : null,
      focusable: onFocusRequested != null ? true : null,
      focused: onFocusRequested != null ? keyboardFocused : null,
      onFocus: theme.platform == TargetPlatform.iOS ? null : onFocusRequested,
      child: _gestures(
        context,
        ref,
        l10n: l10n,
        theme: theme,
        isExpanded: isExpanded,
        hasContent: hasContent,
        enableLongPress: enableLongPress,
      ),
    );
  }

  Widget _gestures(
    BuildContext context,
    WidgetRef ref, {
    required L10N l10n,
    required ThemeData theme,
    required bool isExpanded,
    required bool hasContent,
    required bool enableLongPress,
  }) {
    return GestureDetector(
      // Expand/collapse is deliberately the ONLY tap gesture on this row.
      //
      // There used to be an `onDoubleTap` here that ran the identical
      // toggle. A double-tap recognizer HOLDS the gesture arena for the
      // whole `kDoubleTapTimeout` (~300 ms), and `onTap` cannot fire until
      // the tap recognizer wins that arena — so every single click on a
      // scope row sat dead for a third of a second before the tree moved,
      // and the double-tap it was paying for did exactly what the single
      // tap already did. With the double-tap gone, the arena is swept the
      // moment the pointer lifts and expansion is immediate.
      //
      // Trade-off, taken deliberately: a genuine double-click now toggles
      // twice (expand then collapse) instead of once. That is the standard
      // behavior of a click-to-toggle tree (VS Code's explorer does the
      // same) and it costs a rare gesture rather than every common one.
      //
      // Toggling on pointer-DOWN instead (the fix used for latency-critical
      // *selection* elsewhere in the suite) is wrong here: this row lives
      // inside a scrollable list, so a scroll/fling that starts on a scope
      // header would expand it — and on a gate-level scope that expansion
      // is an expensive frame.
      onTap: () {
        onTapped?.call();
        toggle(ref, scope);
      },
      onSecondaryTapDown: (details) => showContextMenu(
        context,
        ref,
        signalTreePointerMenuAnchor(details.globalPosition),
      ),
      onLongPressStart: enableLongPress
          ? (details) => showContextMenu(
              context,
              ref,
              signalTreePointerMenuAnchor(details.globalPosition),
            )
          : null,
      // The row's own node carries the name, state and count; the arrow,
      // icon, name text and badge underneath would otherwise be read again.
      child: ExcludeSemantics(
        child: Container(
          height: _kRowHeight,
          color: Colors.transparent,
          foregroundDecoration: keyboardFocused
              ? BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                )
              : null,
          padding: EdgeInsets.only(left: _kIndent * indentLevel),
          child: Row(
            children: [
              // Expand/collapse arrow
              SizedBox(
                width: _kIndent,
                child: hasContent
                    ? Icon(
                        isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                        size: 18,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      )
                    : null,
              ),
              // Scope icon
              Icon(
                _iconForScopeType(scope.type),
                size: 14,
                color: theme.colorScheme.primary.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
              // Scope name
              Expanded(
                child: Text(
                  scope.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'JetBrainsMono',
                    fontFamilyFallback: const [
                      'FiraCode',
                      'Courier New',
                      'monospace',
                    ],
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Signal count badge
              if (scope.totalVariableCount > 0)
                _SignalCountBadge(
                  count: scope.totalVariableCount,
                  label: l10n.signalTreeSignalCount(
                    scope.totalVariableCount,
                  ),
                ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the row's context menu at [position].
  ///
  /// A right-click or long-press anchors it at the pointer. The tree opens it
  /// from the keyboard (Shift+F10 or the Menu key) through this same method,
  /// anchored at the row, so every item is reachable without a pointer.
  Future<void> showContextMenu(
    BuildContext context,
    WidgetRef ref,
    RelativeRect position,
  ) async {
    final l10n = L10N.of(context);
    final result = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: 'addAll',
          child: Text(l10n.signalTreeAddAllInScope),
        ),
        PopupMenuItem(
          value: 'removeAll',
          child: Text(l10n.signalTreeRemoveAllInScope),
        ),
      ],
    );
    if (result == null || !context.mounted) return;
    if (result == 'addAll') {
      await _addAllInScope(context, ref);
    } else if (result == 'removeAll') {
      await _removeAllInScope(context, ref);
    }
  }

  /// "Remove All in Scope": the inverse of [_addAllInScope]. Every signal row
  /// on this tab's canvas that shows a variable under [scope] — at the top
  /// level or inside a group — leaves in one update, with an Undo.
  ///
  /// A row matches by its own hierarchical path
  /// ([SignalGroupsNotifier.selectionPathOf]), never by its signal ref.
  /// Aliased variables share a ref: in a VCD where `down.clk` and `up.clk`
  /// are both the testbench clock, matching by ref made Remove All in Scope
  /// on `down` also take `up.clk`, `up.reset` and the testbench's own clock.
  /// Groups stay, even when emptied: the user built them.
  Future<void> _removeAllInScope(BuildContext context, WidgetRef ref) async {
    final groups = ref.read(signalGroupsProvider.notifier);
    final container = ProviderScope.containerOf(context, listen: false);
    bool tabClosed() {
      try {
        container.read(signalGroupsProvider);
        return false;
      } on Object {
        return true;
      }
    }

    final all = await _collectAllVariables(scope, isCancelled: tabClosed);
    if (all == null || !context.mounted) return;
    final paths = <String>{for (final v in all) v.fullPath};
    final variablesMap = ref.read(signalVariablesMapProvider);
    final removal = groups.removeSignalsWhere(
      (e) => paths.contains(
        SignalGroupsNotifier.selectionPathOf(e, variablesMap),
      ),
    );
    if (removal == null) {
      showCruxInfoSnack(
        context,
        L10N.of(context).signalTreeRemoveAllInScopeNone,
      );
      return;
    }
    showSignalRemovalUndo(context, removal: removal, notifier: groups);
  }

  /// "Add All in Scope": every variable under [scope], depth-first, appended to
  /// the viewer.
  ///
  /// The progress indicator is armed before any work starts and stays up until
  /// the canvas takes over, so no stage of a large add is silent:
  ///
  /// 1. the scope walk, indeterminate (the count is not known yet), yielding
  ///    to the event loop between chunks so the indicator can paint;
  /// 2. entry building, determinate — chunked above [_kChunkedAddThreshold],
  ///    synchronous below it;
  /// 3. a hold through the frame that materializes the entries, where the
  ///    canvas's refresh picks the indicator up as its loading phase.
  Future<void> _addAllInScope(BuildContext context, WidgetRef ref) async {
    final l10n = L10N.of(context);
    final groups = ref.read(signalGroupsProvider.notifier);
    // Notifiers and container are captured before the awaits; the tab container
    // outlives this widget unless the tab closes, in which case reads throw and
    // the add is treated as cancelled.
    final progress = ref.read(signalLoadProgressProvider.notifier);
    final container = ProviderScope.containerOf(context, listen: false);
    bool cancelled() {
      try {
        return container.read(signalLoadProgressProvider).cancelRequested;
      } on Object {
        return true; // container disposed (tab closed) — abandon the add
      }
    }

    progress.beginIndeterminate(phase: SignalLoadPhase.adding);
    try {
      final all = await _collectAllVariables(scope, isCancelled: cancelled);
      if (all == null || all.isEmpty || !context.mounted) return;

      progress.begin(all.length, phase: SignalLoadPhase.adding);
      if (all.length < _kChunkedAddThreshold) {
        // Building a few thousand entries is imperceptible, so it stays
        // synchronous; the indicator is still armed for the hold below.
        groups.addSignals(all);
        progress.setLoaded(all.length);
      } else {
        // Large batch (gate-level scopes reach 1M+ variables): build entries
        // in event-loop-yielding chunks so progress paints instead of the UI
        // freezing.
        final applied = await groups.addSignalsChunked(
          all,
          onProgress: (built, _) => progress.setLoaded(built),
          isCancelled: cancelled,
        );
        if (!applied) return;
      }
      // Keep the indicator up through the frame that materializes the new
      // entries — on a million-entry add that frame does the O(N) canvas lane
      // build (~0.5–1 s) — and so the canvas's refresh, which runs in that
      // frame, finds the adding phase to hand off to rather than starting
      // from nothing.
      await WidgetsBinding.instance.endOfFrame;
      if (context.mounted) {
        announceCrux(context, l10n.a11ySignalsAdded(all.length));
      }
    } finally {
      // Phase-scoped: if the canvas's refresh already began the loading
      // batch, leave its indicator alone (see finishPhase).
      progress.finishPhase(SignalLoadPhase.adding);
    }
  }

  /// Batches at or above this size build their entries in chunks with
  /// determinate progress; smaller ones build synchronously (imperceptible).
  /// Either way the indicator is armed, from the scope walk through the hand
  /// off to the canvas.
  static const int _kChunkedAddThreshold = 5000;
}

/// Collects every variable in [scope] and its descendants, depth-first in the
/// order the tree shows them (a scope's own variables, then each child scope).
///
/// Iterative rather than recursive, and it yields to the event loop after
/// every [_kWalkYieldEvery] variables or scopes visited, so walking a
/// gate-level hierarchy does not hold the UI thread for the whole traversal —
/// the progress indicator armed before the walk gets frames to paint in.
/// Returns null when [isCancelled] reports true at a yield point.
Future<List<Variable>?> _collectAllVariables(
  Scope scope, {
  required bool Function() isCancelled,
}) async {
  final result = <Variable>[];
  final stack = <Iterator<Scope>>[];
  var sinceYield = 0;
  Scope? current = scope;
  while (true) {
    if (current != null) {
      result.addAll(current.variables);
      sinceYield += current.variables.length + 1;
      stack.add(current.childScopes.iterator);
      current = null;
    }
    if (stack.isEmpty) break;
    final children = stack.last;
    if (children.moveNext()) {
      current = children.current;
    } else {
      stack.removeLast();
    }
    if (sinceYield >= _kWalkYieldEvery) {
      sinceYield = 0;
      await Future<void>.delayed(Duration.zero);
      if (isCancelled()) return null;
    }
  }
  return result;
}

/// Variables (plus scopes, counted as one each) the walk visits between
/// yields: large enough that a typical scope never yields, small enough that a
/// chunk stays well under a frame.
const int _kWalkYieldEvery = 20000;

/// A small rounded badge showing the number of signals in a scope.
class _SignalCountBadge extends StatelessWidget {
  const _SignalCountBadge({required this.count, required this.label});

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 10,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

IconData _iconForScopeType(ScopeType scopeType) {
  return switch (scopeType) {
    ScopeType.module => Icons.memory,
    ScopeType.task => Icons.assignment,
    ScopeType.function => Icons.functions,
    ScopeType.begin || ScopeType.fork => Icons.account_tree,
    ScopeType.generate => Icons.auto_fix_high,
    ScopeType.struct || ScopeType.union => Icons.table_rows,
    ScopeType.svClass ||
    ScopeType.svInterface ||
    ScopeType.svPackage ||
    ScopeType.svProgram => Icons.code,
    _ => Icons.folder,
  };
}
