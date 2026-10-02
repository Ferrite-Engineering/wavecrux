// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/collaboration/signal_identity_resolver.dart';
import 'package:wavecrux/services/policy/org_signal_groups.dart';

part 'signal_group_providers.g.dart';

/// The waveform viewer's arranged signal list.
///
/// Provides full management of the ordered signal panel: adding, removing,
/// reordering, grouping, and per-signal customization (color, alias, format,
/// lane height).
@Riverpod(keepAlive: true)
class SignalGroupsNotifier extends _$SignalGroupsNotifier {
  @override
  SignalGroup build() => const SignalGroup();

  /// Appends [variable] at [insertIndex] (or end if null) with an auto-assigned
  /// color from the WaveCrux palette.
  void addSignal(Variable variable, {int? insertIndex}) {
    final color = _nextColor(state.signalCount);
    final entry = SignalEntry.signal(
      signalRef: variable.signalRef,
      signalPath: variable.fullPath,
      displayName: variable.name,
      argbColor: color,
    );
    state = _insertAt(state, entry, insertIndex);
  }

  /// Appends all [variables] with sequentially auto-assigned palette colors.
  void addSignals(List<Variable> variables) {
    if (variables.isEmpty) return;
    var i = state.signalCount;
    final newEntries = variables.map((v) {
      final entry = SignalEntry.signal(
        signalRef: v.signalRef,
        signalPath: v.fullPath,
        displayName: v.name,
        argbColor: _nextColor(i),
      );
      i++;
      return entry;
    }).toList();
    state = state.addEntries(_arranged(newEntries));
  }

  /// Arranges a batch into the organization's standard groups.
  ///
  /// Applied on the way in rather than as a later pass, so the panel never
  /// shows an ungrouped flash that then rearranges itself. With no policy file
  /// this is one early return and the entries come back untouched — the
  /// behaviour every install has today.
  ///
  /// Read, not watched: a policy file that changed mid-session must not
  /// retroactively rearrange a pane the user has already organised. The groups
  /// seed what arrives; they do not police what is there.
  List<SignalEntry> _arranged(List<SignalEntry> entries) =>
      applyOrgSignalGroups(entries, ref.read(orgSignalGroupsProvider));

  /// Chunked variant of [addSignals] for very large batches ("Add All in
  /// Scope" on a gate-level netlist can be 1M+ variables).
  ///
  /// Entry construction is split into [chunkSize] slices that yield to the
  /// event loop between slices, so frames keep rendering (the context menu
  /// closes, the progress indicator animates) instead of the UI freezing for
  /// the whole build. The state is assigned exactly **once** at the end —
  /// per-chunk state updates would re-trigger every O(N) listener (canvas
  /// lane rebuild) per chunk and go quadratic.
  ///
  /// [onProgress] reports the running built-count after each chunk.
  /// [isCancelled] is polled between chunks; when it returns true the whole
  /// add is abandoned — nothing is appended (clean all-or-nothing
  /// semantics) — and this returns false. Returns true when the batch was
  /// applied.
  Future<bool> addSignalsChunked(
    List<Variable> variables, {
    int chunkSize = 20000,
    void Function(int built, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (variables.isEmpty) return true;
    var i = state.signalCount;
    final newEntries = <SignalEntry>[];
    for (var start = 0; start < variables.length; start += chunkSize) {
      if (isCancelled?.call() ?? false) return false;
      final end = start + chunkSize > variables.length
          ? variables.length
          : start + chunkSize;
      for (var k = start; k < end; k++) {
        final v = variables[k];
        newEntries.add(
          SignalEntry.signal(
            signalRef: v.signalRef,
            signalPath: v.fullPath,
            displayName: v.name,
            argbColor: _nextColor(i++),
          ),
        );
      }
      onProgress?.call(newEntries.length, variables.length);
      // Yield so the engine can pump a frame between chunks.
      await Future<void>.delayed(Duration.zero);
      // The notifier can be disposed mid-build (tab closed); assigning
      // state afterwards would throw.
      if (!ref.mounted) return false;
    }
    if (isCancelled?.call() ?? false) return false;
    state = state.addEntries(_arranged(newEntries));
    return true;
  }

  /// Removes the top-level entry at [index]. Out-of-bounds indices are ignored.
  void removeSignal(int index) {
    if (index < 0 || index >= state.entries.length) return;
    final entries = [...state.entries]..removeAt(index);
    state = state.copyWith(entries: entries);
  }

  /// Moves the top-level entry at [oldIndex] to [newIndex].
  ///
  /// Follows Flutter's [ReorderableListView.onReorderItem] convention:
  /// [newIndex] is the insertion index in the *post-removal* list, so callers
  /// no longer need to subtract 1 when moving downward.
  void reorderSignal(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.entries.length) return;
    final entries = [...state.entries];
    final item = entries.removeAt(oldIndex);
    final insertAt = newIndex.clamp(0, entries.length);
    entries.insert(insertAt, item);
    state = state.copyWith(entries: entries);
  }

  /// Inserts a named group header at [insertIndex] (or end if null).
  void addGroup(String name, {int? insertIndex}) {
    state = _insertAt(state, SignalEntry.group(groupName: name), insertIndex);
  }

  /// Inserts a blank separator (when [comment] is null) or a comment row
  /// (when [comment] is provided) at [insertIndex] (or end if null).
  void addSeparator({String? comment, int? insertIndex}) {
    final entry = comment != null
        ? SignalEntry.comment(text: comment)
        : const SignalEntry.separator();
    state = _insertAt(state, entry, insertIndex);
  }

  /// Renames the group at top-level [index].
  ///
  /// No-op if the entry at [index] is not a group or [newName] is empty.
  void renameGroup(int index, String newName) {
    if (index < 0 || index >= state.entries.length) return;
    final entry = state.entries[index];
    if (entry.kind != SignalEntryKind.group) return;
    if (newName.trim().isEmpty) return;
    final entries = [...state.entries];
    entries[index] = entry.copyWith(groupName: newName.trim());
    state = state.copyWith(entries: entries);
  }

  /// Moves the top-level signal at [signalIndex] into the group at [groupIndex]
  /// as the last child. No-op if either entry is out of range or not the
  /// correct kind.
  void moveSignalIntoGroup(int signalIndex, int groupIndex) {
    if (signalIndex < 0 || signalIndex >= state.entries.length) return;
    if (groupIndex < 0 || groupIndex >= state.entries.length) return;
    if (signalIndex == groupIndex) return;
    final signal = state.entries[signalIndex];
    if (signal.kind != SignalEntryKind.signal) return;
    if (state.entries[groupIndex].kind != SignalEntryKind.group) return;

    final entries = [...state.entries]..removeAt(signalIndex);
    final adjustedGroupIndex = signalIndex < groupIndex
        ? groupIndex - 1
        : groupIndex;
    final group = entries[adjustedGroupIndex];
    entries[adjustedGroupIndex] = group.copyWith(
      children: [...group.children, signal],
    );
    state = state.copyWith(entries: entries);
  }

  /// Removes the child at [childIndex] from the group at top-level [groupIndex]
  /// and re-inserts it as a top-level entry immediately after the group.
  void removeChildFromGroup(int groupIndex, int childIndex) {
    if (groupIndex < 0 || groupIndex >= state.entries.length) return;
    final group = state.entries[groupIndex];
    if (group.kind != SignalEntryKind.group) return;
    if (childIndex < 0 || childIndex >= group.children.length) return;

    final child = group.children[childIndex];
    final newChildren = [...group.children]..removeAt(childIndex);
    final entries = [...state.entries];
    entries[groupIndex] = group.copyWith(children: newChildren);
    entries.insert(groupIndex + 1, child);
    state = state.copyWith(entries: entries);
  }

  /// Removes the group at [index] and promotes all its children to top-level
  /// entries at the position where the group was.
  void dissolveGroup(int index) {
    if (index < 0 || index >= state.entries.length) return;
    final group = state.entries[index];
    if (group.kind != SignalEntryKind.group) return;

    final entries = [...state.entries]
      ..removeAt(index)
      ..insertAll(index, group.children);
    state = state.copyWith(entries: entries);
  }

  /// Toggles the collapsed state of the group at [index].
  ///
  /// No-op if the entry at [index] is not a group.
  void toggleGroupCollapsed(int index) {
    if (index < 0 || index >= state.entries.length) return;
    final entry = state.entries[index];
    if (entry.kind != SignalEntryKind.group) return;
    final entries = [...state.entries];
    entries[index] = entry.copyWith(collapsed: !entry.collapsed);
    state = state.copyWith(entries: entries);
  }

  /// Sets the display color of the signal entry at [index].
  ///
  /// No-op if the entry is not a signal.
  void setSignalColor(int index, Color color) {
    if (index < 0 || index >= state.entries.length) return;
    final entry = state.entries[index];
    if (entry.kind != SignalEntryKind.signal) return;
    final entries = [...state.entries];
    entries[index] = entry.copyWith(argbColor: color.toARGB32());
    state = state.copyWith(entries: entries);
  }

  /// Sets the display alias (name shown in the panel) of the signal at [index].
  ///
  /// No-op if the entry is not a signal.
  void setSignalAlias(int index, String alias) {
    if (index < 0 || index >= state.entries.length) return;
    final entry = state.entries[index];
    if (entry.kind != SignalEntryKind.signal) return;
    final entries = [...state.entries];
    entries[index] = entry.copyWith(displayName: alias);
    state = state.copyWith(entries: entries);
  }

  /// Sets the display format of the signal entry at [index].
  ///
  /// No-op if the entry is not a signal.
  void setSignalFormat(int index, DisplayFormat format) {
    if (index < 0 || index >= state.entries.length) return;
    final entry = state.entries[index];
    if (entry.kind != SignalEntryKind.signal) return;
    final entries = [...state.entries];
    entries[index] = entry.copyWith(format: format);
    state = state.copyWith(entries: entries);
  }

  /// Sets the pixel lane height of the signal entry at [index].
  ///
  /// [height] is clamped to `[minHeight, 200.0]`, where [minHeight] defaults
  /// to 16 dp (the historical desktop floor). Callers on touch device classes
  /// pass `MobileMetrics.minLaneHeight` (44 dp) so an interactive resize on
  /// touch leaves the stored value equal to the rendered height — this
  /// avoids the case where a small shrink drag past the visual floor would
  /// otherwise leave a stored value below 44 dp that's invisible on touch
  /// but would surface as a tiny lane the next time the same session is
  /// opened on desktop.
  ///
  /// No-op if the entry is not a signal.
  void setLaneHeight(int index, double height, {double minHeight = 16.0}) {
    if (index < 0 || index >= state.entries.length) return;
    final entry = state.entries[index];
    if (entry.kind != SignalEntryKind.signal) return;
    final entries = [...state.entries];
    entries[index] = entry.copyWith(laneHeight: height.clamp(minHeight, 200.0));
    state = state.copyWith(entries: entries);
  }

  /// Updates the text of the comment entry at [index].
  ///
  /// No-op if the entry is not a comment.
  void setCommentText(int index, String text) {
    if (index < 0 || index >= state.entries.length) return;
    final entry = state.entries[index];
    if (entry.kind != SignalEntryKind.comment) return;
    final entries = [...state.entries];
    entries[index] = entry.copyWith(text: text);
    state = state.copyWith(entries: entries);
  }

  /// Sets the display format of the specific signal row identified by [id].
  ///
  /// Unlike [setSignalFormatByRef], this targets exactly one row even when the
  /// same signal is added to the viewer multiple times. No-op if not found.
  void setSignalFormatById(String id, DisplayFormat format) {
    final updated = _updateFormatById(state.entries, id, format);
    if (updated != null) state = state.copyWith(entries: updated);
  }

  /// Toggles whether the row identified by [id] is drawn as an analog curve.
  ///
  /// Per-row for the same reason [setSignalFormatById] is: two rows of one
  /// signal can legitimately want different renderings — a Q4.12 datapath read
  /// as a curve next to the same bits read as hex is a normal debug layout.
  ///
  /// Orthogonal to the row's [SignalEntry.format], which continues to answer
  /// "what number are these bits". No-op if not found.
  void setSignalRenderAsAnalog(String id, {required bool renderAsAnalog}) {
    final updated = _updateRenderAsAnalogById(
      state.entries,
      id,
      renderAsAnalog: renderAsAnalog,
    );
    if (updated != null) state = state.copyWith(entries: updated);
  }

  /// Sets the display format of the signal with [signalRef] anywhere in the
  /// entry tree (including nested inside groups).
  ///
  /// No-op if no signal with the given ref is found.
  void setSignalFormatByRef(String signalRef, DisplayFormat format) {
    final updated = _updateFormatByRef(state.entries, signalRef, format);
    if (updated != null) state = state.copyWith(entries: updated);
  }

  /// Sets the translator config of the specific signal row identified by [id].
  /// Pass [null] to clear.
  ///
  /// Per-instance, mirroring [setSignalFormatById]: the translator config is the
  /// parameterization of a row's [SignalEntry.format] (Q-format `{m,n,signed}`,
  /// named-enum `{entries}`, custom-translator bindings), so it shares the
  /// per-row scope of `format`. Targets exactly one row even when the same
  /// signal is added to the viewer multiple times — so two rows of one signal
  /// can carry different configs (e.g. Q8.8 vs Q4.12). No-op if not found. Use
  /// [setSignalTranslatorConfigByRef] for a deliberate "apply to all instances"
  /// fan-out. (See issue #39.)
  void setSignalTranslatorConfigById(
    String id,
    Map<String, Object?>? config,
  ) {
    final updated = _updateTranslatorConfigById(state.entries, id, config);
    if (updated != null) state = state.copyWith(entries: updated);
  }

  /// Sets the translator config of the signal with [signalRef] anywhere in the
  /// entry tree (including nested inside groups). Pass [null] to clear.
  ///
  /// Fans out to **every** row showing the signal. Prefer
  /// [setSignalTranslatorConfigById] for the default per-row edit; this is the
  /// explicit "apply to all instances" path. No-op if no signal with the given
  /// ref is found.
  void setSignalTranslatorConfigByRef(
    String signalRef,
    Map<String, Object?>? config,
  ) {
    final updated = _updateTranslatorConfigByRef(
      state.entries,
      signalRef,
      config,
    );
    if (updated != null) state = state.copyWith(entries: updated);
  }

  /// Clears a custom-translator binding from the row identified by [id] and
  /// simultaneously resets its [SignalEntry.format] back to the default
  /// ([DisplayFormat.hexadecimal]).
  ///
  /// "Clear Custom Translator" must restore the row to the pristine appearance
  /// it had when freshly added. Clearing only [SignalEntry.translatorConfig]
  /// (via [setSignalTranslatorConfigById] with `null`) is insufficient: if the
  /// row's `format` had been changed to a non-default value (e.g.
  /// [DisplayFormat.ieee754Single]) before the translator was bound, that stale
  /// format survives. After the binding is cleared the row falls back to
  /// `BuiltinValueTranslator`, which then keeps formatting with the stale
  /// `format` — so the value still looks "translated" (e.g. a float) instead of
  /// reverting to plain hex. Resetting both fields in a single atomic update is
  /// the fix. No-op if not found. (See issue #41.)
  void clearSignalTranslatorById(String id) {
    final updated = _clearTranslatorById(state.entries, id);
    if (updated != null) state = state.copyWith(entries: updated);
  }

  /// Removes all entries from the viewer.
  void clear() => state = const SignalGroup();

  // ── bulk removal ───────────────────────────────────────────────────────────
  //
  // Every bulk removal is ONE state assignment, never N single removals. The
  // canvas, value column and name column each rebuild their lane geometry on
  // every list change, so a loop of `removeSignal` calls would churn the
  // layer tree once per row; one assignment churns it once. Each returns the
  // [SignalRemoval] the undo snackbar hands back to [undoRemoval], or null
  // when nothing was removed (so the caller shows no snackbar).

  /// Clear Canvas: removes every row of the list — signals, groups,
  /// separators and comments — leaving the empty canvas.
  ///
  /// Only the list is touched. Cursors, markers, decoders, zoom and the open
  /// file are separate providers and stay as they are.
  SignalRemoval? clearCanvas() {
    final before = state;
    if (before.entries.isEmpty) return null;
    state = const SignalGroup();
    return SignalRemoval._(
      before: before,
      after: state,
      removed: before.entries,
      signalCount: before.signalCount,
    );
  }

  /// Removes every signal row, at the top level or inside a group, for which
  /// [test] returns true. Group headers stay, even when emptied.
  SignalRemoval? removeSignalsWhere(bool Function(SignalEntry entry) test) {
    final before = state;
    final result = before.withoutSignals(test);
    if (result.removed.isEmpty) return null;
    state = result.group;
    return SignalRemoval._(
      before: before,
      after: state,
      removed: result.removed,
      signalCount: result.removed.length,
    );
  }

  /// Removes the signal rows whose selection path is in [paths] — the
  /// Signals list's "Remove Selected" and its Delete key.
  ///
  /// [variablesMap] resolves a row to the same path the list selects it by;
  /// see [selectionPathOf].
  SignalRemoval? removeSignalsAtPaths(
    Set<String> paths,
    Map<String, Variable> variablesMap,
  ) {
    if (paths.isEmpty) return null;
    return removeSignalsWhere(
      (e) => paths.contains(selectionPathOf(e, variablesMap)),
    );
  }

  /// Removes the group at top-level [index] together with every row in it —
  /// "Remove Group and Signals", the counterpart of [dissolveGroup]
  /// ("Ungroup"), which keeps the rows.
  SignalRemoval? removeGroupWithSignals(int index) {
    if (index < 0 || index >= state.entries.length) return null;
    final group = state.entries[index];
    if (group.kind != SignalEntryKind.group) return null;
    final before = state;
    final entries = [...before.entries]..removeAt(index);
    state = before.copyWith(entries: entries);
    return SignalRemoval._(
      before: before,
      after: state,
      removed: [group],
      signalCount: SignalGroup(entries: [group]).signalCount,
    );
  }

  /// Undoes [removal]: the removed rows come back with their order, groups,
  /// colours, formats and lane heights.
  ///
  /// When the list is still exactly what the removal left, the list from
  /// before it is restored as it was. If something changed in between — a
  /// signal added from the tree while the snackbar was up — that change is
  /// kept and the removed rows are appended after it instead, so the undo
  /// never throws away work done since.
  ///
  /// Returns false when the tab has been closed since the removal.
  bool undoRemoval(SignalRemoval removal) {
    if (!ref.mounted) return false;
    if (state == removal.after) {
      state = removal.before;
    } else {
      state = state.addEntries(removal.removed);
    }
    return true;
  }

  /// The path a Signals-list row is selected by: the row's own
  /// [SignalEntry.signalPath], the full path of the variable it was added
  /// from.
  ///
  /// Not the path looked up through the row's ref. Aliased variables share
  /// one ref: in a VCD, `top.down.clk` and `top.up.clk` both point at the
  /// testbench's clock. The ref map holds only one of them, so resolving
  /// through it gave every alias row the same path. Clicking `up.clk`
  /// selected whichever alias the map held, a tree selection of `down.clk`
  /// never matched its row, and removing one alias removed them all.
  ///
  /// Rows without a stored path (sessions written before paths were kept)
  /// fall back to the ref lookup, then to the row's own name.
  ///
  /// The one definition the list's highlight, its Shift-click range,
  /// [removeSignalsAtPaths] and Remove All in Scope share, so what is
  /// highlighted is what is removed. It matches the Values dock, which
  /// selects by [SignalEntry.signalPath] too.
  static String selectionPathOf(
    SignalEntry entry,
    Map<String, Variable> variablesMap,
  ) {
    if (entry.signalPath case final path? when path.isNotEmpty) return path;
    final ref = entry.signalRef ?? '';
    return variablesMap[ref]?.fullPath ?? entry.displayName ?? ref;
  }

  /// Re-resolves every entry's [SignalEntry.signalRef] against [source]'s
  /// current hierarchy, using [SignalEntry.signalPath] as the canonical
  /// identifier.
  ///
  /// Necessary whenever a session is restored under a different waveform
  /// backend than the one that wrote it: wellen and the pure-Dart parser
  /// assign different `signalRef` values (stringified u32 vs. VCD idcode like
  /// `"!"`), so a cross-backend restore would otherwise crash on the very
  /// first `loadSignal` call. Resolution by hierarchical path is invariant
  /// across backends because it derives from the file's design hierarchy.
  ///
  /// Entries with [SignalEntry.signalPath] that match a variable in [source]
  /// are updated in place with the local backend's `signalRef`. Entries with
  /// a path that no variable matches (file was edited, or path was renamed)
  /// are silently dropped; a debug-mode warning is emitted with the dropped
  /// count so the change is observable in `flutter run`.
  ///
  /// Legacy entries written before paths were tracked ([signalPath] == null)
  /// are left untouched and rely on the defensive try/catch in
  /// `WaveformCanvas._refresh` to skip them when their ref is rejected.
  void reresolveSignalRefs(WaveformDataSource source) {
    final all = source.findVariables(const SignalFilter());
    final pathToRef = <String, String>{
      for (final v in all) v.fullPath: v.signalRef,
    };
    var droppedCount = 0;
    final updated = _reresolveEntries(
      state.entries,
      pathToRef,
      (_) => droppedCount++,
    );
    if (updated == null) return;
    if (kDebugMode && droppedCount > 0) {
      debugPrint(
        'SignalGroupsNotifier: dropped $droppedCount signal entr'
        '${droppedCount == 1 ? "y" : "ies"} whose canonical path is not '
        'present in the active waveform source.',
      );
    }
    state = SignalGroup(entries: updated);
  }

  /// Replaces the entire signal list with [group] (used for session restore).
  // ignore: use_setters_to_change_properties
  void restoreFromSession(SignalGroup group) => state = group;

  // ── view-composition recipe seams ──────────────────────────────────

  /// Serialize the displayed-signal list into a **signal-identity-based**
  /// recipe for collaboration view-composition sync.
  ///
  /// Every signal-kind entry's backend-local [SignalEntry.signalRef] is
  /// normalised to its canonical [SignalEntry.signalPath] so the recipe carries
  /// **no `signalRef`s** — only stable identities a follower on any backend can
  /// re-resolve. Entries without a path (legacy) keep their ref verbatim as a
  /// best-effort fallback. Order, grouping, radix, color, lane height, and
  /// per-row translator config all ride along unchanged.
  SignalGroup toCompositionRecipe() =>
      SignalGroup(entries: _normaliseRefsToPaths(state.entries));

  /// Apply a presenter's displayed-signal [recipe] against the local hierarchy,
  /// re-resolving every canonical path to the follower's own `signalRef` via
  /// [resolver]. Replaces the current list (the [CollabViewerBridge] has
  /// captured the follower's own list for restore-on-detach).
  ///
  /// Returns the canonical paths in [recipe] that no local variable matched —
  /// the missing-reference degradation set. Such rows are dropped from the
  /// applied list rather than crashing the replay.
  List<String> applyCompositionRecipe(
    SignalGroup recipe,
    SignalIdentityResolver resolver,
  ) {
    final missing = <String>[];
    final updated = _reresolveEntries(
      recipe.entries,
      resolver.pathToRef,
      (dropped) {
        final path = dropped.signalPath;
        if (path != null) missing.add(path);
      },
    );
    state = SignalGroup(entries: updated ?? recipe.entries);
    return missing;
  }

  /// Recursively rewrites every signal entry's `signalRef` to its `signalPath`
  /// (when present) so the serialized recipe is purely identity-based.
  static List<SignalEntry> _normaliseRefsToPaths(List<SignalEntry> entries) => [
    for (final e in entries)
      switch (e.kind) {
        SignalEntryKind.signal =>
          e.signalPath == null ? e : e.copyWith(signalRef: e.signalPath),
        SignalEntryKind.group => SignalEntry.group(
          groupName: e.groupName ?? '',
          collapsed: e.collapsed,
          children: _normaliseRefsToPaths(e.children),
        ),
        SignalEntryKind.separator || SignalEntryKind.comment => e,
      },
  ];

  // ── helpers ─────────────────────────────────────────────────────────────────

  static List<SignalEntry>? _updateFormatById(
    List<SignalEntry> entries,
    String id,
    DisplayFormat format,
  ) {
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.kind == SignalEntryKind.signal && entry.id == id) {
        final updated = [...entries];
        updated[i] = entry.copyWith(format: format);
        return updated;
      } else if (entry.kind == SignalEntryKind.group) {
        final childUpdated = _updateFormatById(entry.children, id, format);
        if (childUpdated != null) {
          final updated = [...entries];
          updated[i] = entry.copyWith(children: childUpdated);
          return updated;
        }
      }
    }
    return null;
  }

  static List<SignalEntry>? _updateRenderAsAnalogById(
    List<SignalEntry> entries,
    String id, {
    required bool renderAsAnalog,
  }) {
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.kind == SignalEntryKind.signal && entry.id == id) {
        final updated = [...entries];
        updated[i] = entry.copyWith(renderAsAnalog: renderAsAnalog);
        return updated;
      } else if (entry.kind == SignalEntryKind.group) {
        final childUpdated = _updateRenderAsAnalogById(
          entry.children,
          id,
          renderAsAnalog: renderAsAnalog,
        );
        if (childUpdated != null) {
          final updated = [...entries];
          updated[i] = entry.copyWith(children: childUpdated);
          return updated;
        }
      }
    }
    return null;
  }

  static List<SignalEntry>? _updateFormatByRef(
    List<SignalEntry> entries,
    String signalRef,
    DisplayFormat format,
  ) {
    List<SignalEntry>? updated;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.kind == SignalEntryKind.signal &&
          entry.signalRef == signalRef) {
        updated ??= [...entries];
        updated[i] = entry.copyWith(format: format);
      } else if (entry.kind == SignalEntryKind.group) {
        final childUpdated = _updateFormatByRef(
          entry.children,
          signalRef,
          format,
        );
        if (childUpdated != null) {
          updated ??= [...entries];
          updated[i] = entry.copyWith(children: childUpdated);
        }
      }
    }
    return updated;
  }

  static List<SignalEntry>? _updateTranslatorConfigById(
    List<SignalEntry> entries,
    String id,
    Map<String, Object?>? config,
  ) {
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.kind == SignalEntryKind.signal && entry.id == id) {
        final updated = [...entries];
        updated[i] = config == null
            ? entry.copyWith(clearTranslatorConfig: true)
            : entry.copyWith(translatorConfig: config);
        return updated;
      } else if (entry.kind == SignalEntryKind.group) {
        final childUpdated = _updateTranslatorConfigById(
          entry.children,
          id,
          config,
        );
        if (childUpdated != null) {
          final updated = [...entries];
          updated[i] = entry.copyWith(children: childUpdated);
          return updated;
        }
      }
    }
    return null;
  }

  static List<SignalEntry>? _clearTranslatorById(
    List<SignalEntry> entries,
    String id,
  ) {
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.kind == SignalEntryKind.signal && entry.id == id) {
        final updated = [...entries];
        updated[i] = entry.copyWith(
          format: DisplayFormat.hexadecimal,
          clearTranslatorConfig: true,
        );
        return updated;
      } else if (entry.kind == SignalEntryKind.group) {
        final childUpdated = _clearTranslatorById(entry.children, id);
        if (childUpdated != null) {
          final updated = [...entries];
          updated[i] = entry.copyWith(children: childUpdated);
          return updated;
        }
      }
    }
    return null;
  }

  static List<SignalEntry>? _updateTranslatorConfigByRef(
    List<SignalEntry> entries,
    String signalRef,
    Map<String, Object?>? config,
  ) {
    List<SignalEntry>? updated;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      if (entry.kind == SignalEntryKind.signal &&
          entry.signalRef == signalRef) {
        updated ??= [...entries];
        updated[i] = config == null
            ? entry.copyWith(clearTranslatorConfig: true)
            : entry.copyWith(translatorConfig: config);
      } else if (entry.kind == SignalEntryKind.group) {
        final childUpdated = _updateTranslatorConfigByRef(
          entry.children,
          signalRef,
          config,
        );
        if (childUpdated != null) {
          updated ??= [...entries];
          updated[i] = entry.copyWith(children: childUpdated);
        }
      }
    }
    return updated;
  }

  /// Recursive helper for [reresolveSignalRefs]. Walks [entries], updating
  /// signal-kind rows whose [SignalEntry.signalPath] resolves to a new
  /// `signalRef` in [pathToRef] and dropping rows whose path is absent.
  ///
  /// Returns `null` if no entry was changed or dropped (the caller can keep
  /// the existing list unchanged); otherwise returns a freshly built list.
  /// [onDrop] is invoked once per dropped entry so the caller can surface a
  /// debug-mode count.
  static List<SignalEntry>? _reresolveEntries(
    List<SignalEntry> entries,
    Map<String, String> pathToRef,
    void Function(SignalEntry dropped) onDrop,
  ) {
    final newList = <SignalEntry>[];
    var changed = false;
    for (final e in entries) {
      switch (e.kind) {
        case SignalEntryKind.signal:
          final path = e.signalPath;
          if (path == null) {
            // Legacy entry — leave the stale ref. _refresh's defensive
            // try/catch will skip it if rejected by the active backend.
            newList.add(e);
            break;
          }
          final freshRef = pathToRef[path];
          if (freshRef == null) {
            onDrop(e);
            changed = true;
          } else if (freshRef != e.signalRef) {
            newList.add(e.copyWith(signalRef: freshRef));
            changed = true;
          } else {
            newList.add(e);
          }
        case SignalEntryKind.group:
          final newChildren = _reresolveEntries(e.children, pathToRef, onDrop);
          if (newChildren != null) {
            newList.add(
              SignalEntry.group(
                groupName: e.groupName ?? '',
                collapsed: e.collapsed,
                children: newChildren,
              ),
            );
            changed = true;
          } else {
            newList.add(e);
          }
        case SignalEntryKind.separator:
        case SignalEntryKind.comment:
          newList.add(e);
      }
    }
    return changed ? newList : null;
  }

  static int _nextColor(int index) {
    const palette = WavecruxColors.signalPalette;
    return palette[index % palette.length].toARGB32();
  }

  static SignalGroup _insertAt(
    SignalGroup group,
    SignalEntry entry,
    int? index,
  ) {
    if (index == null) return group.addEntry(entry);
    final entries = [...group.entries];
    entries.insert(index.clamp(0, entries.length), entry);
    return group.copyWith(entries: entries);
  }
}

/// What a bulk removal took out of the list, held by its undo snackbar and
/// handed back to [SignalGroupsNotifier.undoRemoval].
///
/// Built only by [SignalGroupsNotifier]: [after] must be the exact state the
/// removal produced for the undo to restore [before] verbatim.
@immutable
class SignalRemoval {
  const SignalRemoval._({
    required this.before,
    required this.after,
    required this.removed,
    required this.signalCount,
  });

  /// The list as it was before the removal.
  final SignalGroup before;

  /// The list the removal left behind.
  final SignalGroup after;

  /// The removed rows, in their original order — appended back if the list
  /// changed again before the undo.
  final List<SignalEntry> removed;

  /// How many signal rows were removed, counting those inside removed groups.
  final int signalCount;
}

/// The auto-color palette used when adding signals to the viewer.
///
/// Exposed so widgets can preview what color a signal will receive.
List<Color> get signalColorPalette => WavecruxColors.signalPalette;
