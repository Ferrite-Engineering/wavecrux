// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The ShortcutAction dispatch for the viewer screen, extracted from
// viewer_screen.dart so the single hottest
// change-concentration point in the codebase — the exhaustive switch that
// every new user-facing action adds a case to — lives in its own reviewable
// file instead of the middle of the 3,000-line screen.
//
// WHY A PART-FILE EXTENSION (and not a standalone dispatcher class): every
// case here is deliberate glue binding a [ShortcutAction] to the screen's
// private members — `_openFile`, `_togglePanelOnActiveTab`,
// `_activeTabContainer`, dialog openers needing `context`, and the
// `ref.read(...)` extension-point seams. A separate collaborator class would
// need that entire private surface as an interface or a ~30-callback
// constructor: that is a whole-file split with no benefit, and a
// callback-bag is not meaningfully unit-testable anyway (each test would only
// assert "callback N fired"). The part keeps:
//   * the ONE exhaustive `switch` — a new [ShortcutAction] value still fails
//     compilation until a case is added HERE (the same guarantee
//     `descriptorFor` gives for surface placement; see ARCHITECTURE §3.1.6);
//   * private access, so the 360-line body moved verbatim with zero member
//     promotions and zero import churn (a part shares the library's imports);
//   * behavior coverage exactly where it was: dispatch is exercised
//     end-to-end by the `ShortcutActionIntent` → `Actions.invoke` widget
//     tests in viewer_screen_test.dart — the same entry the running app uses,
//     which a unit seam would bypass.
//
// PER-TAB ROUTING INVARIANT (issue #44 scope-leak class): handlers that
// mutate file-scoped state MUST resolve providers through
// `_activeTabContainer` (or `_togglePanelOnActiveTab`), never through the
// screen's root-scope `ref`. A root-scope `ref.read` of a per-tab provider
// silently writes the empty root instance and the shortcut becomes a no-op —
// the exact bug class the per-tab annotations below guard against. Root-scope
// `ref.read` is correct ONLY for genuinely app-global state (device class,
// diagnostics gate, workspace/tab management, extension-point seams).

part of 'viewer_screen.dart';

/// Shortcut dispatch for [_ViewerScreenState] — see the header above for why
/// this lives in a part-file extension.
extension _ViewerScreenShortcuts on _ViewerScreenState {
  void _handleShortcut(ShortcutAction action) {
    // DESCRIPTOR-PARITY GUARD. The keyboard is a fifth action surface
    // and it must obey the same single source of truth as the other four: if
    // `descriptorFor(action).isEnabled(ctx)` is false the menu bar greys the
    // item, the overflow menu greys it, the palette omits it, and the toolbar
    // button is inert — so pressing the key must be inert too. Before this
    // guard the shortcut path bypassed the table entirely and each handler
    // re-derived its own (weaker, drifting) precondition: `jumpToStart` /
    // `jumpToEnd` checked only `mapper.isEmpty` while the descriptor requires
    // a file AND a cursor, and `shareSession` / `joinSession` opened their
    // dialogs unconditionally while the descriptor requires `_notInSession`.
    // Guarding once at dispatch keeps the parity structural instead of
    // per-handler, and is enforced by
    // `test/core/shortcuts/shortcut_dispatch_conformance_test.dart`.
    //
    // PARITY *AND* FEEDBACK. A greyed menu item explains itself — it sits next
    // to its own label, in a menu the user just opened. A key press has no
    // such anchor, so an early `return` alone reads as a broken keyboard (it
    // notably swallowed the "load a waveform file to use protocol decoders"
    // guidance the Add Decoder handler used to give). So the guard resolves
    // the *unmet requirement* and surfaces its localized hint instead of
    // going silent. Resolving from the requirement rather than from a static
    // per-action string keeps the message accurate for actions with several
    // preconditions (Explain Selection: file, selection, model).
    final actionContext = ref.read(actionContextProvider);
    final unmet = unmetActionRequirement(action, actionContext);
    if (unmet != null) {
      _showDisabledActionHint(unmet);
      return;
    }

    // A Pro or Enterprise action in a build without the overlay that
    // implements it: its extension point is a no-op, so name the tier it
    // needs rather than do nothing.
    final tier = descriptorFor(action).requiredTier;
    if ((tier == LicenseTier.pro || tier == LicenseTier.enterprise) &&
        !ref.read(paidTierActionsInstalledProvider)) {
      final l10n = L10N.of(context);
      final label = action.label(l10n);
      showCruxInfoSnack(
        context,
        tier == LicenseTier.enterprise
            ? l10n.actionRequiresWaveCruxEnterprise(label)
            : l10n.actionRequiresWaveCruxPro(label),
      );
      return;
    }

    final nav = _activeTabContainer.read(navigationProvider.notifier);
    switch (action) {
      case ShortcutAction.openFile:
        unawaited(_openFile());
      case ShortcutAction.closeFile:
        unawaited(_closeFile());
      case ShortcutAction.quit:
        exit(0);
      case ShortcutAction.openAbout:
        unawaited(
          ModalGuard.run(
            'openAbout',
            () => WaveCruxAboutDialog.openAdaptive(context, ref),
          ),
        );
      case ShortcutAction.issueReporter:
        unawaited(
          ModalGuard.run(
            'issueReporter',
            () => CruxIssueReporterDialog.openAdaptive(context),
          ),
        );
      case ShortcutAction.checkForUpdates:
        unawaited(
          ModalGuard.run(
            'checkForUpdates',
            () => runManualUpdateCheck(context, ref),
          ),
        );
      case ShortcutAction.openDocumentation:
        unawaited(documentationLaunchUrl(Uri.parse(HelpUrls.docs)));
      case ShortcutAction.zoomIn:
      case ShortcutAction.waveformZoomIn:
        nav.zoomIn();
      case ShortcutAction.zoomOut:
      case ShortcutAction.waveformZoomOut:
        nav.zoomOut();
      case ShortcutAction.fitAll:
        nav.fitAll();
      case ShortcutAction.zoomToSelection:
        nav.zoomToSelection();
      case ShortcutAction.panLeft:
        nav.panLeft();
      case ShortcutAction.panRight:
        nav.panRight();
      case ShortcutAction.panLeftSmall:
        nav.panLeft(small: true);
      case ShortcutAction.panRightSmall:
        nav.panRight(small: true);
      case ShortcutAction.jumpToStart:
        nav.jumpToStart();
      case ShortcutAction.jumpToEnd:
        nav.jumpToEnd();
      case ShortcutAction.nextTransition:
        _navigateTransition(forward: true);
      case ShortcutAction.prevTransition:
        _navigateTransition(forward: false);
      case ShortcutAction.setMarker:
        ref.read(markerChordCoordinatorProvider).arm(MarkerChordMode.set);
      case ShortcutAction.jumpToMarker:
        ref.read(markerChordCoordinatorProvider).arm(MarkerChordMode.jump);
      case ShortcutAction.removeMarker:
        unawaited(_showRemoveMarkerDialog());
      case ShortcutAction.clearCursors:
        _activeTabContainer.read(cursorStateProvider.notifier).clearAll();
      case ShortcutAction.clearSecondaryCursor:
        _activeTabContainer.read(cursorStateProvider.notifier).clearSecondary();
      case ShortcutAction.clearSignalSelection:
        _activeTabContainer.read(selectedVariablesProvider.notifier).clear();
      case ShortcutAction.saveSession:
        unawaited(_saveSession());
      case ShortcutAction.saveSessionAs:
        unawaited(_saveSessionAs());
      case ShortcutAction.importGtkwSession:
        unawaited(_importGtkwSession());
      case ShortcutAction.exportWaveform:
        _exportWaveform();
      case ShortcutAction.shareAnnotatedWaveform:
        _shareAnnotatedWaveform();
      case ShortcutAction.annotationWalkthroughNext:
        _stepWalkthrough(forward: true);
      case ShortcutAction.annotationWalkthroughPrevious:
        _stepWalkthrough(forward: false);
      case ShortcutAction.annotationWalkthroughPlay:
        _toggleWalkthroughPlayback();
      case ShortcutAction.addAnnotationAtCursor:
        _addAnnotationAtCursor();
      case ShortcutAction.annotateSelectedRange:
        _annotateSelectedRange();
      case ShortcutAction.toggleAnnotationsVisible:
        _toggleAnnotationsVisible();
      case ShortcutAction.toggleAnnotationsPanel:
        _toggleAnnotationsPanel();
      case ShortcutAction.stopStreaming:
        _stopStreaming();
      case ShortcutAction.openSearch:
        _openSearch();
      case ShortcutAction.openCommandPalette:
        _openCommandPalette();
      case ShortcutAction.addDecoder:
        _openDecoderPicker();
      case ShortcutAction.toggleTransactionTable:
        // VSCode reveal semantics: activate the Transactions tab and open the
        // dock; if it is already the visible tab, collapse the dock instead.
        final layout = _activeTabContainer.read(panelLayoutProvider);
        _togglePanelOnActiveTab((n) {
          if (layout.bottomDockShowsTransactions) {
            n.setTransactionViewVisible(visible: false);
          } else {
            n.revealBottomDockTab(kBottomDockTabTransactions);
          }
        });
      case ShortcutAction.toggleSignalTree:
        _togglePanelOnActiveTab((n) => n.toggleSignalTree());
      case ShortcutAction.toggleValueColumn:
        // Reveal semantics: activate the Values tab and open the right dock;
        // collapse the dock if Values is already frontmost.
        final rightLayout = _activeTabContainer.read(panelLayoutProvider);
        _togglePanelOnActiveTab((n) {
          if (rightLayout.valueColumnVisible &&
              rightLayout.effectiveRightDockTab == kRightDockTabValues) {
            n.setValueColumnVisible(visible: false);
          } else {
            n.revealRightDockTab(kRightDockTabValues);
          }
        });
      case ShortcutAction.toggleStagePanel:
        // The action toggles the Stage *feature*: turning it on reveals its
        // dock tab; turning it off removes the stage tabs from the strip
        // (the dock stays open and falls back to Transactions).
        final wasStageVisible = _activeTabContainer
            .read(panelLayoutProvider)
            .stageViewVisible;
        // First use: seed a default panel so the feature lands directly on a
        // working canvas — no create-first interstitial, matching how the
        // dock's per-panel tabs assume a non-empty workspace.
        if (!wasStageVisible &&
            _activeTabContainer.read(stageWorkspaceProvider).panels.isEmpty) {
          _activeTabContainer
              .read(stageWorkspaceProvider.notifier)
              .addPanel(L10N.of(context).stagePanelDefaultName);
        }
        _togglePanelOnActiveTab((n) {
          n.setStageViewVisible(visible: !wasStageVisible);
          if (!wasStageVisible) n.revealBottomDockTab(kBottomDockStagePrefix);
        });
      case ShortcutAction.togglePlayback:
        // Stage Playback play/pause. Defense-in-depth: no-op when no Stage
        // tab is on screen (the transport lives inside the Stage panel; with
        // the FSM tab in front there is nothing animating). The
        // dispatch-level descriptor-parity guard already keeps the Space key
        // inert when the action is disabled; this local check backs that up.
        // Engine `play()` additionally bails on an empty trace, so a missing
        // file is covered too.
        if (_activeTabContainer
            .read(panelLayoutProvider)
            .bottomDockShowsStage) {
          _activeTabContainer.read(playbackProvider.notifier).toggle();
        }
      case ShortcutAction.toggleStatisticsStrip:
        // The strip's visibility is per-tab; the toggle targets the active
        // tab so toggling in one tab does not move another tab's strip.
        _togglePanelOnActiveTab((n) => n.toggleStatisticsStrip());
      case ShortcutAction.openSettings:
        unawaited(
          ModalGuard.run(
            'openSettings',
            () => SettingsScreen.openAdaptive(context),
          ),
        );
      case ShortcutAction.toggleTheme:
        _toggleTheme();
      case ShortcutAction.openAppDiagnostics:
        if (ref.read(diagnosticsEnabledProvider)) {
          final dc = ref.read(deviceClassProvider);
          if (dc != DeviceClass.phone && dc != DeviceClass.phoneLandscape) {
            // Re-entrancy guarded inside AppDiagnosticsDialog.open (covers the
            // shortcut, the menu, and the diagnostics-panel button alike).
            unawaited(AppDiagnosticsDialog.open(context));
          }
        }
      case ShortcutAction.openTabDiagnostics:
        if (ref.read(diagnosticsEnabledProvider)) {
          final dc = ref.read(deviceClassProvider);
          if (dc != DeviceClass.phone && dc != DeviceClass.phoneLandscape) {
            // Re-entrancy guarded inside TabDiagnosticsDrawer.open (also
            // covers the per-pane `i`-icon caller in WaveCruxPaneHost).
            unawaited(TabDiagnosticsDrawer.open(context));
          }
        }
      case ShortcutAction.openPaneRenderStats:
        // Anchor-less invocation routes to the active pane. Per ARCHITECTURE.md
        // §8.8 the popover's natural anchor is the per-pane `i`-icon in
        // ViewerTabBar; the command palette path falls back to using the
        // viewer screen itself as anchor, surfacing the active pane's data.
        if (ref.read(diagnosticsEnabledProvider)) {
          final dc = ref.read(deviceClassProvider);
          if (dc != DeviceClass.phone && dc != DeviceClass.phoneLandscape) {
            final activePane = ref.read(activePaneIdProvider);
            // Re-entrancy guarded inside PaneRenderStatsPopover.showAnchoredTo
            // (also covers the per-pane `i`-icon caller in WaveCruxPaneHost).
            unawaited(
              PaneRenderStatsPopover.showAnchoredTo(
                context,
                paneId: activePane,
              ),
            );
          }
        }
      case ShortcutAction.openCrossProbePanel:
        final dc = ref.read(deviceClassProvider);
        if (dc != DeviceClass.phone && dc != DeviceClass.phoneLandscape) {
          // The cross-probe panel is a right-dock tab. The action
          // toggles the feature; turning it on reveals its tab (routed
          // through the active tab's container, the RTL/cocotb scope-leak
          // class).
          final cxpLayout = _activeTabContainer.read(panelLayoutProvider);
          final notifier = _activeTabContainer.read(
            panelLayoutProvider.notifier,
          );
          if (cxpLayout.crossProbeVisible) {
            notifier.setCrossProbeVisible(visible: false);
          } else {
            notifier
              ..setCrossProbeVisible(visible: true)
              ..revealDockTabPlaced(kRightDockTabCrossProbe, kDockRegionRight);
          }
        }
      case ShortcutAction.compareWaveforms:
        unawaited(_compareWaveforms());
      case ShortcutAction.nextDivergence:
        _activeTabContainer.read(diffProvider.notifier).nextDivergence();
      case ShortcutAction.prevDivergence:
        _activeTabContainer.read(diffProvider.notifier).prevDivergence();
      case ShortcutAction.analyzeSwitchingActivity:
        unawaited(_analyzeSwitchingActivity());
      case ShortcutAction.patternSearch:
        _openPatternSearch();
      case ShortcutAction.nextPatternMatch:
        _activeTabContainer.read(patternSearchProvider.notifier).nextMatch();
      case ShortcutAction.prevPatternMatch:
        _activeTabContainer.read(patternSearchProvider.notifier).prevMatch();
      case ShortcutAction.copyDiagnosticsReport:
        // The same report the App Diagnostics dialog's Copy Report button
        // copies, without the frame timings only the open dialog samples.
        unawaited(copyAppDiagnosticsReport(context, ref));
      case ShortcutAction.loadRtlStemsFile:
        unawaited(_loadRtlStemsFile());
      case ShortcutAction.generateRtlStems:
        unawaited(_generateRtlStems());
      case ShortcutAction.importVerilatorAst:
        unawaited(_importVerilatorAst());
      case ShortcutAction.toggleRtlSourcePanel:
        _toggleRtlSourcePanel();
      case ShortcutAction.generateTestVcd:
        // Hidden in the browser; its chord must not open a dialog whose save
        // step the web cannot run.
        if (kIsWeb) return;
        unawaited(
          ModalGuard.run(
            'generateTestVcd',
            () => GenerateTestVcdDialog.show(context),
          ),
        );
      case ShortcutAction.convertPcapToVcd:
        // Enterprise-tier feature dispatched through the open-core
        // dialog-opener extension point. Open-core ships a no-op opener;
        // the Pro overlay overrides `pcapToVcdDialogOpenerProvider` with
        // a callback that mounts the Convert PCAP to VCD dialog. The
        // opener runs `FeatureGate.isAvailable` internally so the gate
        // semantics (beta short-circuit + post-beta enterprise check)
        // live next to the feature implementation.
        ref.read(pcapToVcdDialogOpenerProvider)(context);
      case ShortcutAction.loadCocotbLog:
        unawaited(_loadCocotbLog());
      case ShortcutAction.clearCocotbLog:
        _clearCocotbLog();
      case ShortcutAction.toggleCocotbLogPanel:
        _toggleCocotbLogPanel();
      case ShortcutAction.stageUndo:
        _activeTabContainer.read(stageWorkspaceProvider.notifier).undo();
      case ShortcutAction.stageRedo:
        _activeTabContainer.read(stageWorkspaceProvider.notifier).redo();
      case ShortcutAction.debugAdvisorTogglePanel:
        // Pro-tier feature dispatched through the open-core panel-opener
        // extension point. Open-core ships a no-op opener; the Pro
        // overlay overrides `debugAdvisorPanelOpenerProvider` with a
        // callback that mounts the panel.
        ref.read(debugAdvisorPanelOpenerProvider)(context);
      case ShortcutAction.toggleSvaPanel:
        // Pro-tier feature dispatched through the open-core panel-toggler
        // extension point. Open-core ships a no-op toggler; the Pro
        // overlay overrides `svaPanelTogglerProvider` with a callback
        // that flips the SVA panel's visibility provider so the bottom-
        // dock priority chain picks it up via
        // `extraBottomDockTabsProvider`.
        ref.read(svaPanelTogglerProvider)(context);
        _revealBottomPaneForContributedTab();
      case ShortcutAction.loadSvaResults:
        // Pro-tier feature dispatched through the open-core SVA results-loader
        // extension point. Open-core ships a no-op loader; the Pro overlay
        // overrides `svaResultsLoaderProvider` with a callback that prompts
        // for a simulator assertion-log file, parses it, force-opens the SVA
        // bottom-dock panel, and surfaces a load-error snackbar on failure.
        ref.read(svaResultsLoaderProvider)(context);
        _revealBottomPaneForContributedTab();
      case ShortcutAction.clearSvaResults:
        // Pro-overridden clear seam — unloads the SVA result file and hides
        // the panel. No-op in open-core builds.
        ref.read(svaResultsClearerProvider)(context);
      case ShortcutAction.aiAdvisorTogglePanel:
        // Pro-tier agentic AI Waveform Assistant, dispatched through the
        // open-core panel-toggler extension point. Open-core ships a no-op
        // toggler; the Pro overlay overrides `aiAdvisorPanelTogglerProvider`
        // with a callback that flips the Advisor panel's visibility provider
        // (and routes through FeatureGate → upgrade dialog post-beta), so the
        // bottom-dock priority chain picks it up via
        // `extraBottomDockTabsProvider`.
        ref.read(aiAdvisorPanelTogglerProvider)(context);
        _revealBottomPaneForContributedTab();
      case ShortcutAction.aiExplainSelection:
        // Open-core, non-agentic Explain Selection. Runs against the active
        // tab's selection and the configured `AiModelClient`; the result
        // surfaces as the bottom dock's Explain tab. Gating (experimental on
        // + model configured + non-empty selection) is enforced by the action
        // descriptor, but the controller also fails soft on an empty
        // selection / unconfigured model. Call-site reveal — the dock may be
        // unmounted when the result lands.
        _activeTabContainer
            .read(panelLayoutProvider.notifier)
            .revealDockTabPlaced(kBottomDockTabExplain, kDockRegionBottom);
        unawaited(
          _activeTabContainer
              .read(explainSelectionProvider.notifier)
              .explainCurrentSelection(),
        );
      // ── set signal format on selected signals ──────────────────────────────
      case ShortcutAction.setFormatBinary:
        _setSelectedFormat(DisplayFormat.binary);
      case ShortcutAction.setFormatHexadecimal:
        _setSelectedFormat(DisplayFormat.hexadecimal);
      case ShortcutAction.setFormatOctal:
        _setSelectedFormat(DisplayFormat.octal);
      case ShortcutAction.setFormatUnsignedDecimal:
        _setSelectedFormat(DisplayFormat.unsignedDecimal);
      case ShortcutAction.setFormatSignedDecimal:
        _setSelectedFormat(DisplayFormat.signedDecimal);
      case ShortcutAction.setFormatAscii:
        _setSelectedFormat(DisplayFormat.ascii);
      case ShortcutAction.setFormatIeee754Single:
        _setSelectedFormat(DisplayFormat.ieee754Single);
      case ShortcutAction.setFormatIeee754Double:
        _setSelectedFormat(DisplayFormat.ieee754Double);
      case ShortcutAction.setFormatFixedPointQ:
        _setSelectedFormat(DisplayFormat.fixedPointQ);
      case ShortcutAction.setFormatSignedMagnitude:
        _setSelectedFormat(DisplayFormat.signedMagnitude);
      case ShortcutAction.setFormatGrayCode:
        _setSelectedFormat(DisplayFormat.grayCode);
      case ShortcutAction.setFormatNamedEnum:
        _setSelectedFormat(DisplayFormat.namedEnum);
      // ── collaborative viewing (Enterprise) ───────────────────────────────────
      // Routes through the open-core extension point; the Enterprise overlay
      // overrides `collaborationCommandHandlerProvider` with the real
      // implementation. Open Core builds silently absorb these actions.
      case ShortcutAction.shareSession:
      case ShortcutAction.joinSession:
      case ShortcutAction.stopSharing:
      case ShortcutAction.leaveSession:
      case ShortcutAction.exportSessionRecording:
      case ShortcutAction.exportReviewMinutes:
      // ── Presenter Mode (Enterprise) ─────────────────────────────────────────
      // Same open-core extension point; the Enterprise overlay's handler
      // performs the handoff / request / resume-follow / pointer-drop. Open
      // Core builds silently absorb these actions.
      case ShortcutAction.handoffPresenter:
      case ShortcutAction.requestPresenter:
      case ShortcutAction.resumeFollowing:
      case ShortcutAction.dropPing:
      case ShortcutAction.dropPin:
        ref.read(collaborationCommandHandlerProvider)(context, action);
      // ── workspace management ──────────────────────────────────────────────
      case ShortcutAction.resetWorkspace:
        unawaited(runResetWorkspaceCommand(context: context, ref: ref));
      case ShortcutAction.newWorkspace:
        unawaited(runNewWorkspaceCommand(context: context, ref: ref));
      case ShortcutAction.saveWorkspaceAs:
        unawaited(runSaveWorkspaceAsCommand(context: context, ref: ref));
      case ShortcutAction.openWorkspace:
        unawaited(runOpenWorkspaceCommand(context: context, ref: ref));
      case ShortcutAction.exportTabAsSession:
        unawaited(runExportTabCommand(context: context, ref: ref));
      // ── tab management ────────────────────────────────────────────────────────
      case ShortcutAction.closeTab:
        _closeActiveTab();
      case ShortcutAction.nextTab:
        _activateAdjacentTab(forward: true);
      case ShortcutAction.previousTab:
        _activateAdjacentTab(forward: false);
      case ShortcutAction.jumpToTab1:
        _jumpToTab(0);
      case ShortcutAction.jumpToTab2:
        _jumpToTab(1);
      case ShortcutAction.jumpToTab3:
        _jumpToTab(2);
      case ShortcutAction.jumpToTab4:
        _jumpToTab(3);
      case ShortcutAction.jumpToTab5:
        _jumpToTab(4);
      case ShortcutAction.jumpToTab6:
        _jumpToTab(5);
      case ShortcutAction.jumpToTab7:
        _jumpToTab(6);
      case ShortcutAction.jumpToTab8:
        _jumpToTab(7);
      case ShortcutAction.jumpToTab9:
        _jumpToTab(8);
      case ShortcutAction.splitPaneRight:
        unawaited(_splitPaneRight());
      case ShortcutAction.closePane:
        unawaited(_closeActivePane());
      case ShortcutAction.focusOtherPane:
        unawaited(_focusOtherPane());
      case ShortcutAction.moveTabToOtherPane:
        unawaited(_moveActiveTabToOtherPane());
    }
  }
}
