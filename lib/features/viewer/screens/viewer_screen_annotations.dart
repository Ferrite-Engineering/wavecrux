// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Annotation, walkthrough, marker-navigation and pane/tab management for the
// viewer screen, extracted from viewer_screen.dart.
//
// Three related concerns that all manipulate *what is on screen* rather than
// what is loaded into it:
//
//   * **Annotations and walkthroughs** — adding one at the cursor, annotating
//     a selected range, toggling visibility and the panel, nudging a selected
//     annotation with the arrow keys, and stepping or playing a walkthrough.
//   * **Transition navigation** — jumping the cursor to the next or previous
//     edge of the focused signal, with the first-signal fallback that decides
//     what "focused" means when nothing is explicitly selected.
//   * **Panes and tabs** — split, close, focus-other, move-tab-across, close
//     tab, cycle, and jump-to-index.
//
// WHY TOGETHER. They share the property that makes them awkward in the
// screen: each is a handful of lines that reads as trivial and is not — the
// pane operations have to keep the workspace notifier and the per-tab
// container in step, and the annotation ones have to route through the active
// tab or write to an empty root scope. Grouping them puts the ones that can
// go subtly wrong the same way next to each other.
//
// WHY A PART-FILE EXTENSION: see the header of viewer_screen_file_io.dart,
// which also records what part-splitting does and does not buy.
//
// PER-TAB ROUTING INVARIANT (issue #44 scope-leak class): every handler here
// that mutates file-scoped state resolves providers through
// `_activeTabContainer` or `_togglePanelOnActiveTab`. Root-scope `ref.read` is
// correct only for workspace and tab management, which is genuinely app-global
// — and that distinction is exactly why these two groups share a file.

part of 'viewer_screen.dart';

extension _ViewerScreenAnnotations on _ViewerScreenState {
  /// Moves the selected annotation's anchor with Alt+←/→ (one tick) or
  /// Alt+Shift+←/→ (the adjacent transition on its signal).
  ///
  /// Returns true when the key was consumed — which includes the case where the
  /// anchor could not move (already at the trace's edge, or no further
  /// transition). Consuming it either way matters: falling through would pan
  /// the viewport instead, so a nudge that hit a limit would look like the
  /// waveform jumped sideways for no reason.
  bool _nudgeSelectedAnnotation(LogicalKeyboardKey key) {
    final hw = HardwareKeyboard.instance;
    if (!hw.isAltPressed || hw.isControlPressed || hw.isMetaPressed) {
      return false;
    }
    final direction = switch (key) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      _ => 0,
    };
    if (direction == 0) return false;

    final container = _activeTabContainer;
    final id = container.read(annotationSelectedProvider);
    if (id == null) return false;

    container
        .read(annotationAuthoringProvider.notifier)
        .nudgeAnchor(id, direction: direction, toEdge: hw.isShiftPressed);
    return true;
  }

  /// Splits the active pane horizontally, creating a second pane to the right
  /// and moving the active tab into it. The newly-created pane becomes the
  /// active pane. No-op when the workspace is already split.
  Future<void> _splitPaneRight() async {
    // The chord obeys the same rule that hides the action: a split the pane
    // host cannot show would hide the tabs left in the original pane.
    if (!ref.read(splitPaneAllowedProvider)) return;
    final workspace = ref.read(workspaceProvider).value;
    if (workspace == null || workspace.panes.length >= 2) return;
    final activeTabId = ref.read(activeTabIdProvider);
    final notifier = ref.wavecruxWorkspace;
    final newPaneId = await notifier.splitPane();
    if (workspace.tabs.any((t) => t.id == activeTabId)) {
      await notifier.moveTabToPane(activeTabId, newPaneId);
    }
  }

  /// Closes the active pane and merges its tabs into the surviving pane.
  /// No-op when the workspace is single-pane.
  Future<void> _closeActivePane() async {
    final workspace = ref.read(workspaceProvider).value;
    if (workspace == null || workspace.panes.length < 2) return;
    final activePaneId = workspace.activePaneId;
    // closePane merges the closed pane's tabs into the surviving pane; the
    // derived tab list reflects the new pane assignments automatically.
    await ref.read(workspaceProvider.notifier).closePane(activePaneId);
  }

  /// Moves focus to the other pane. No-op when single-pane.
  Future<void> _focusOtherPane() async {
    final workspace = ref.read(workspaceProvider).value;
    if (workspace == null || workspace.panes.length < 2) return;
    final other = workspace.panes
        .firstWhere((p) => p.id != workspace.activePaneId)
        .id;
    await ref.read(workspaceProvider.notifier).setActivePane(other);
  }

  /// Moves the currently active tab to the other pane. No-op when single-pane.
  Future<void> _moveActiveTabToOtherPane() async {
    final workspace = ref.read(workspaceProvider).value;
    if (workspace == null || workspace.panes.length < 2) return;
    final activeTabId = ref.read(activeTabIdProvider);
    final other = workspace.panes
        .firstWhere((p) => p.id != workspace.activePaneId)
        .id;
    await ref
        .read(workspaceProvider.notifier)
        .moveTabToPane(activeTabId, other);
  }

  void _closeActiveTab() {
    final activeTabId = ref.read(activeTabIdProvider);
    unawaited(ref.read(workspaceProvider.notifier).closeTab(activeTabId));
  }

  void _activateAdjacentTab({required bool forward}) {
    final tabs = ref.read(tabListProvider);
    if (tabs.length < 2) return;
    final activeTabId = ref.read(activeTabIdProvider);
    final currentIndex = tabs.indexWhere((t) => t.id == activeTabId);
    if (currentIndex == -1) return;
    final nextIndex = forward
        ? (currentIndex + 1) % tabs.length
        : (currentIndex - 1 + tabs.length) % tabs.length;
    ref.read(activeTabIdProvider.notifier).activate(tabs[nextIndex].id);
  }

  void _jumpToTab(int index) {
    final tabs = ref.read(tabListProvider);
    if (index >= tabs.length) return;
    ref.read(activeTabIdProvider.notifier).activate(tabs[index].id);
  }

  void _navigateTransition({required bool forward}) {
    final source = _activeTabContainer.read(waveformSourceProvider).value;
    if (source == null) return;

    // Prefer the first signal selected in the signal tree, fall back to the
    // first signal entry in the viewer panel. Selection carries fullPaths
    // (row identity) — resolve to a signalRef for the transition query.
    final selected = _activeTabContainer.read(selectedVariablesProvider);
    final signalRef = selected.isNotEmpty
        ? _activeTabContainer
              .read(signalVariablesByPathProvider)[selected.first]
              ?.signalRef
        : _firstSignalRefInGroups(
            _activeTabContainer.read(signalGroupsProvider).entries,
          );

    if (signalRef == null) {
      showCruxInfoSnack(context, L10N.of(context).transitionNoSignal);
      return;
    }

    // Strict-cursor gate: transition navigation steps relative to the primary
    // cursor. With no cursor there is no anchor to step from, so this is a
    // no-op (the menu / toolbar / palette entries are descriptor-gated to match;
    // this guards the keyboard path, which is not descriptor-gated).
    final cursorTime = _activeTabContainer
        .read(cursorStateProvider)
        .primaryCursorTime;
    if (cursorTime == null) return;

    final change = forward
        ? source.nextTransition(signalRef, cursorTime)
        : source.prevTransition(signalRef, cursorTime);

    if (change == null) return;
    _activeTabContainer
        .read(cursorStateProvider.notifier)
        .placePrimary(change.time);
    _activeTabContainer
        .read(navigationProvider.notifier)
        .jumpToTime(change.time);
  }

  static String? _firstSignalRefInGroups(List<SignalEntry> entries) {
    for (final entry in entries) {
      if (entry.kind == SignalEntryKind.signal && entry.signalRef != null) {
        return entry.signalRef;
      }
      if (entry.kind == SignalEntryKind.group) {
        final ref = _firstSignalRefInGroups(entry.children);
        if (ref != null) return ref;
      }
    }
    return null;
  }

  /// Steps the walkthrough one annotation and reports a wrap.
  ///
  /// The wrap notice is the point: a reader pressing `]` who lands back on
  /// note 1 with no signal reads it as the key having done nothing, and then
  /// presses it again.
  void _stepWalkthrough({required bool forward}) {
    final metrics = MobileMetrics.of(context, ref.read(deviceClassProvider));
    final walkthrough = _activeTabContainer.read(
      annotationWalkthroughProvider.notifier,
    );
    final moved = forward
        ? walkthrough.next(minLaneHeight: metrics.minLaneHeight)
        : walkthrough.previous(minLaneHeight: metrics.minLaneHeight);
    if (!moved || !mounted) return;

    if (_activeTabContainer.read(annotationWalkthroughProvider).wrapped) {
      final l10n = L10N.of(context);
      showCruxInfoSnack(
        context,
        forward
            ? l10n.annotationWalkthroughWrappedForward
            : l10n.annotationWalkthroughWrappedBackward,
      );
    }
  }

  void _toggleWalkthroughPlayback() {
    final metrics = MobileMetrics.of(context, ref.read(deviceClassProvider));
    _activeTabContainer
        .read(annotationWalkthroughProvider.notifier)
        .toggle(minLaneHeight: metrics.minLaneHeight);
  }

  /// Creates an annotation at the primary cursor on the selected signal row,
  /// and opens its editor.
  ///
  /// "The selected row" is the single-selection rule the band confine toggle
  /// already uses: with zero or several signals selected there is no answer,
  /// and picking one would attach the note to a signal the user did not name.
  /// The action's descriptor greys on `hasSelection` for the same reason, so
  /// this only ever declines when the selection changed between the two.
  void _addAnnotationAtCursor() {
    final container = _activeTabContainer;
    final metrics = MobileMetrics.of(context, ref.read(deviceClassProvider));
    final geometry = container.read(
      laneGeometryProvider(LaneMetrics(minLaneHeight: metrics.minLaneHeight)),
    );
    // Through the shared resolver, because the selection is keyed by fullPath
    // and comparing it against `signalRef` silently never matches — see
    // [singleSelectedRowId].
    final rowId = singleSelectedRowId(
      geometry,
      container.read(selectedVariablesProvider),
    );
    if (rowId == null) {
      showCruxInfoSnack(context, L10N.of(context).annotationSelectOneSignal);
      return;
    }

    final id = container
        .read(annotationAuthoringProvider.notifier)
        .createAtCursor(rowId: rowId, minLaneHeight: metrics.minLaneHeight);
    if (id == null) {
      // The only remaining failure is "no cursor placed", which the descriptor
      // also greys on — say which of the two preconditions is missing rather
      // than doing nothing.
      showCruxInfoSnack(context, L10N.of(context).annotationNeedsCursor);
      return;
    }
    container.read(annotationSelectedProvider.notifier).selected = id;
    container.read(annotationBeingEditedProvider.notifier).editing = id;
  }

  /// Creates a full-height band over the selected time range.
  ///
  /// The range comes from the Shift+drag selection when there is one and from
  /// the two cursors otherwise — see `AnnotationAuthoring.bandRange`. Confining
  /// it to a lane stays a canvas gesture, because "which lane" is a question
  /// only a pointer position answers.
  void _annotateSelectedRange() {
    final container = _activeTabContainer;
    final authoring = container.read(annotationAuthoringProvider.notifier);
    final range = authoring.bandRange();
    if (range == null) {
      showCruxInfoSnack(
        context,
        L10N.of(context).annotationRangeNeedsSelection,
      );
      return;
    }

    final label = TimeFormatService(
      timescale: container.read(waveformSourceProvider).value?.timescale,
    ).formatDelta(range.$1, range.$2);
    final id = authoring.createRangeFromCursors(label: label);
    if (id == null) return;
    container.read(annotationSelectedProvider.notifier).selected = id;
    container.read(annotationBeingEditedProvider.notifier).editing = id;
  }

  /// Shows or hides every annotation on the canvas.
  void _toggleAnnotationsVisible() {
    final container = _activeTabContainer
      ..read(annotationsVisibleProvider.notifier).toggle();
    if (!mounted) return;
    final l10n = L10N.of(context);
    showCruxInfoSnack(
      context,
      container.read(annotationsVisibleProvider)
          ? l10n.annotationsShownToast
          : l10n.annotationsHiddenToast,
    );
  }

  /// Shows or hides the Annotations dock panel.
  ///
  /// Opening it with **no** annotations is the valuable case: the panel's empty
  /// state is where the authoring gesture is explained.
  void _toggleAnnotationsPanel() {
    final container = _activeTabContainer;
    container
        .read(panelLayoutProvider.notifier)
        .toggleAnnotationsPanel(
          annotationsPresent: container.read(annotationsProvider).isNotEmpty,
        );
  }
}
