// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The viewer screen on a foldable (iPhone Duo, Android foldables): the dock area
// that splits around a tabletop crease, Stage brought forward when the device
// folds into tabletop posture, and tilt-to-zoom. Every member here is inert on
// a device without a hinge, where the fold state is always FoldState.none.

part of 'viewer_screen.dart';

extension _ViewerScreenFold on _ViewerScreenState {
  /// Tilt-to-zoom (Settings > Orientation & Display, off by default): in tabletop
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
  ///
  /// In tabletop posture the two halves are the layout's center slot (above
  /// the crease) and its bottom slot (below). With [waveformBelow] (the
  /// default) they swap contents: the dock, Stage included, goes in the upper
  /// slot, where it is watched like a laptop's screen, and the waveform in
  /// the lower one, under the hands, where the cursor is scrubbed. The
  /// shared layout has no top dock, so the swap is of slot contents, not of
  /// regions; geometry is the same either way.
  Widget _buildIdeArea(
    WorkspaceTab tab, {
    required PaneId hostPaneId,
    required PanelLayoutState panelState,
    required bool ideIsPhone,
    required ({double left, double right}) paneDefaults,
    required MobileMetrics paneMetrics,
    required TabletopSplit? tabletop,
    required bool compactSides,
    required bool waveformBelow,
  }) {
    final inset = tabletop?.inset ?? 0.0;
    final swap = tabletop != null && waveformBelow;
    Widget waveform() => _FocusableWaveformPane(
      child: _PaneScopedCanvas(
        paneId: tab.paneId,
        repaintKey: _repaintKeyForTab(hostPaneId, tab.id),
        child: WaveformViewCenter(onCompareWith: _compareWaveforms),
      ),
    );
    const dock = WaveCruxBottomDock();
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
          child: swap ? dock : waveform(),
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
          child: swap ? waveform() : dock,
        ),
      ),
    );
  }

  /// This tab's fold layout flags, read in the per-tab Consumer's build (the
  /// LayoutBuilder that uses them runs during layout, where watching is not
  /// allowed).
  ///
  /// [bookShared]: two panes on a half-folded book-posture foldable get one
  /// page each, and a page has no room for the side docks beside a waveform.
  /// [waveformBelow]: in laptop posture the waveform takes the flat half
  /// (the default; Settings > Orientation & Display swaps it).
  ({bool bookShared, bool waveformBelow}) _foldFlagsForTab(WidgetRef paneRef) {
    final bookShared =
        paneRef.watch(foldPostureProvider) == FoldPosture.book &&
        (paneRef.watch(workspaceProvider).value?.panes.length ?? 1) >= 2;
    final waveformBelow =
        paneRef.watch(
          appSettingsProvider.select((s) => s.value?.tabletopWaveformBelow),
        ) ??
        true;
    return (bookShared: bookShared, waveformBelow: waveformBelow);
  }

  /// Folding into laptop posture gives the bottom dock a half of its own
  /// (the upright one by default); bring Stage forward there, when [tab] is
  /// active and has a Stage session, so the pose shows the design's widgets
  /// beside the waveform without a tap. Only on entering the posture, so a
  /// dock tab picked afterwards stays picked.
  void _listenFoldForTab(WidgetRef paneRef, WorkspaceTab tab) {
    paneRef.listen<FoldPosture>(foldPostureProvider, (prev, next) {
      if (next != FoldPosture.tabletop || prev == FoldPosture.tabletop) {
        return;
      }
      if (tab.id != paneRef.read(activeTabIdProvider)) return;
      _revealStageForTabletop(paneRef);
    });
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
