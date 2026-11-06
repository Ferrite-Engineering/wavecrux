// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The viewer screen on a foldable (iPhone Duo, Android foldables): the dock area
// that splits around a tabletop crease, Stage brought forward when the device
// folds into tabletop posture, and tilt-to-zoom. Every member here is inert on
// a device without a hinge, where the fold state is always FoldState.none.

part of 'viewer_screen.dart';

extension _ViewerScreenFold on _ViewerScreenState {
  /// Tilt-to-zoom (Settings > Orientation, off by default): in tabletop
  /// posture each tilt of the upright half beyond the dead band zooms the
  /// active tab's time axis around its cursor (the viewport centre when no
  /// cursor is placed). Leaving the posture drops the reference, so unfolding
  /// or closing the device never zooms.
  void _onFoldStateChanged(FoldState? previous, FoldState next) {
    final angle = next.hingeAngle;
    if (next.posture != FoldPosture.tabletop || angle == null) {
      _hingeZoomReference = null;
      return;
    }
    final enabled =
        ref.read(appSettingsProvider).value?.hingeZoomEnabled ?? false;
    final from = _hingeZoomReference;
    if (!enabled || from == null) {
      _hingeZoomReference = angle;
      return;
    }
    final step = hingeZoomStep(from, angle);
    if (step == null) return;
    _hingeZoomReference = angle;
    final container = _activeTabContainer;
    final mapper = container.read(timeMapperProvider);
    if (mapper.isEmpty || mapper.viewportWidth <= 0) return;
    final cursor = container.read(cursorStateProvider).primaryCursorTime;
    final focal = cursor == null
        ? mapper.viewportWidth / 2
        : mapper.timeToPixel(cursor).clamp(0.0, mapper.viewportWidth);
    final notifier = container.read(timeMapperProvider.notifier);
    if (step.zoomIn) {
      notifier.zoomIn(focalPixel: focal, factor: step.factor);
    } else {
      notifier.zoomOut(focalPixel: focal, factor: step.factor);
    }
  }

  /// The tab's dock area: [CruxIdeLayout] in its docks-restore wrapper.
  ///
  /// [tabletop] is non-null only while a foldable is half-folded like a
  /// laptop; [compactSides] only while two panes share a book-posture
  /// foldable. Both are null/false on every other device.
  Widget _buildIdeArea(
    WorkspaceTab tab, {
    required PaneId hostPaneId,
    required PanelLayoutState panelState,
    required bool ideIsPhone,
    required ({double left, double right}) paneDefaults,
    required MobileMetrics paneMetrics,
    required TabletopSplit? tabletop,
    required bool compactSides,
  }) {
    final inset = tabletop?.inset ?? 0.0;
    return WaveCruxDockRestoreBars(
      onLoadStems: _loadRtlStemsFile,
      foldHeld: tabletop != null,
      child: CruxIdeLayout(
        layout: _WaveCruxIdePanelLayout(
          panelState,
          isPhone: ideIsPhone,
          defaultLeft: paneDefaults.left,
          defaultRight: paneDefaults.right,
          tabletopBottom: tabletop?.bottomSize,
          compactSides: compactSides,
        ),
        sink: tabletop != null
            ? const _FoldHeldIdePanelLayoutSink()
            : _WaveCruxIdePanelLayoutSink(
                _tabContainer(
                  tab.id,
                ).read(panelLayoutProvider.notifier),
              ),
        // Geometry only. The resizer colours come from the theme
        // (its splitter tokens, else outlineVariant / primary);
        // passing them here would override a user's choice.
        theme: CruxIdeLayoutTheme(
          resizerThickness: paneMetrics.splitterVisualWidth,
          resizerHitTestThickness: paneMetrics.splitterHitWidth,
        ),
        leftMinSize: PaneSize.pixel(150),
        rightMinSize: PaneSize.pixel(150),
        bottomMinSize: PaneSize.pixel(80),
        centerMinSize: PaneSize.pixel(120),
        // Left dock: Signals (pinned) · Diff (on-demand). The
        // signal-tree ⇄ diff-summary swap became tabs.
        leftBuilder: (context, _) => const WaveCruxLeftDock(),
        // Both halves keep clear of the crease band in tabletop
        // posture; the padding is zero (and stays in the tree, so
        // nothing remounts) everywhere else.
        centerBuilder: (context, _) => Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: _FocusableWaveformPane(
            child: _PaneScopedCanvas(
              paneId: tab.paneId,
              repaintKey: _repaintKeyForTab(hostPaneId, tab.id),
              child: WaveformViewCenter(
                onCompareWith: _compareWaveforms,
              ),
            ),
          ),
        ),
        // Right dock: Values (pinned) · RTL Source · Cross-Probe.
        // The 3-deep priority chain became tabs.
        rightBuilder: (context, _) => WaveCruxRightDock(
          onLoadStems: _loadRtlStemsFile,
        ),
        // The VSCode-style bottom dock: every candidate surface is
        // a tab (Transactions pinned; Stage ×N dynamic; analyses
        // on-demand). The phone sheet hosts the same entries via
        // [WaveCruxBottomDockSheet] — the priority chain is gone.
        bottomBuilder: (context, _) => Padding(
          padding: EdgeInsets.only(top: inset),
          child: const WaveCruxBottomDock(),
        ),
      ),
    );
  }

  /// Selects the active Stage panel's tab in [paneRef]'s bottom dock, when
  /// the tab has a Stage session with at least one panel. Nothing otherwise:
  /// tabletop posture does not invent a Stage session.
  void _revealStageForTabletop(WidgetRef paneRef) {
    final panelState = paneRef.read(panelLayoutProvider);
    final stage = paneRef.read(stageWorkspaceProvider);
    if (!panelState.stageViewVisible || stage.panels.isEmpty) return;
    final active = stage.activePanel ?? stage.panels.first;
    selectBottomDockTab(paneRef, '$kBottomDockStagePrefix${active.id}');
  }
}
