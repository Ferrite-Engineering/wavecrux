// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The viewer's tool flows, extracted from viewer_screen.dart: everything a
// user opens *over* a loaded waveform rather than to load one.
//
// Cocotb log import, RTL stem loading (file, generate, Verilator AST),
// switching-activity analysis, waveform comparison, the decoder picker, the
// two search dialogs, export and share, the marker-removal dialog and the
// command palette — plus the display-format setter and the two telemetry
// recorders every one of them calls.
//
// WHY THIS CLUSTER. Each of these is the same shape: resolve some per-tab
// state, run an async import or open a dialog, then reveal a panel and record
// that the tool was opened. They were interleaved with annotation handlers and
// pane management across 600 lines of the screen. `_recordToolOpened` and
// `_recordFormatSet` travel with them because every member here calls one of
// the two and nothing outside this file does.
//
// WHY A PART-FILE EXTENSION: see the header of viewer_screen_file_io.dart.
// The short version is that these are glue over the screen's private surface
// and a collaborator class would need it all as a callback bag. That header
// also records what part-splitting does and does not buy — it reduces what a
// reviewer holds at once, not coupling.
//
// PER-TAB ROUTING INVARIANT (issue #44 scope-leak class): handlers that mutate
// file-scoped state resolve providers through `_activeTabContainer` or
// `_togglePanelOnActiveTab`, never the screen's root-scope `ref`, which would
// silently write the empty root instance and make the tool a no-op.

part of 'viewer_screen.dart';

extension _ViewerScreenTools on _ViewerScreenState {
  /// Records `tool.opened` for one of the five analysis surfaces telemetry tracks.
  ///
  /// [tool] is a literal from the catalog's closed set, never a dock-tab id:
  /// the ids the layout uses are `xtrace`, `rtlSource`, `crossProbe` and
  /// friends, two of which are camelCase and would be dropped by the ingestion
  /// Worker, and all of which are layout vocabulary that may be renamed
  /// without anyone thinking about a dashboard.
  void _recordToolOpened(String tool) {
    ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'tool.opened',
            properties: <String, Object?>{'tool': tool},
          ),
        );
  }

  /// Records `format.set` for the bulk shortcut path.
  ///
  /// The per-row context menu records its own — see `value_column_row.dart`.
  /// Two call sites rather than one in `SignalGroupsNotifier`, because the
  /// notifier's setters are per-signal and this action is per-selection.
  void _recordFormatSet(DisplayFormat format) {
    ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'format.set',
            properties: <String, Object?>{
              'format': telemetryEnumToken(format),
            },
          ),
        );
  }

  void _setSelectedFormat(DisplayFormat format) {
    final selected = _activeTabContainer.read(selectedVariablesProvider);
    if (selected.isEmpty) return;
    // One event per keypress, not per selected signal: the catalog question is
    // the distribution of radices users choose, and a fifty-signal selection is
    // still one choice. Past the empty-selection guard, so a shortcut pressed
    // with nothing selected is an attempt and stays uncounted.
    _recordFormatSet(format);
    // Selection carries fullPaths (row identity); resolve each to its
    // Variable to reach the signalRef the group notifier operates on.
    final byPath = _activeTabContainer.read(signalVariablesByPathProvider);
    final notifier = _activeTabContainer.read(signalGroupsProvider.notifier);
    for (final path in selected) {
      final variable = byPath[path];
      if (variable == null) continue;
      notifier.setSignalFormatByRef(variable.signalRef, format);
    }
  }

  /// Picks a `.log` / `.txt` file and feeds it to [CocotbLog].
  Future<void> _loadCocotbLog() async {
    if (ref.read(systemDialogInFlightProvider)) return;
    final l10n = L10N.of(context);
    // Read before the await; see [SystemDialogInFlight.end].
    final inFlight = ref.read(systemDialogInFlightProvider.notifier)..begin();
    final FilePickerResult? picked;
    try {
      picked = await ref.read(openFilePickerProvider)(
        dialogTitle: l10n.cocotbLogFilePickerTitle,
      );
    } finally {
      inFlight.end();
    }
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null || !mounted) return;
    try {
      // cocotbLogProvider is per-tab — load into the active tab's container so
      // the log lands in the focused tab (and its per-tab timescale is read at
      // parse time), rather than a single root-scope log shared by every tab.
      await _activeTabContainer
          .read(cocotbLogProvider.notifier)
          .loadFromFile(path);
      if (!mounted) return;
      // Surface the panel after a successful load so the user can see what
      // they just opened.
      // panelLayoutProvider is per-tab — route through the active tab's
      // container, not the screen's root-scope `ref` (the RTL/cocotb/diff
      // scope-leak class).
      _activeTabContainer.read(panelLayoutProvider.notifier)
        ..setCocotbLogPanelVisible(visible: true)
        ..revealDockTabPlaced(kBottomDockTabCocotb, kDockRegionBottom);
    } on Exception catch (e) {
      if (!mounted) return;
      showCruxErrorSnack(context, l10n.cocotbLogLoadError(e.toString()));
    }
  }

  void _clearCocotbLog() {
    // cocotbLogProvider is per-tab — clear the active tab's log.
    _activeTabContainer.read(cocotbLogProvider.notifier).clear();
    // Per-tab panel visibility — see _loadCocotbLog.
    _activeTabContainer
        .read(panelLayoutProvider.notifier)
        .setCocotbLogPanelVisible(visible: false);
  }

  void _toggleCocotbLogPanel() {
    // Per-tab panel visibility — route through the active tab's container, not
    // the screen's root-scope `ref` (the scope-leak class that broke RTL too).
    final notifier = _activeTabContainer.read(panelLayoutProvider.notifier);
    final state = _activeTabContainer.read(panelLayoutProvider);
    notifier.setCocotbLogPanelVisible(visible: !state.cocotbLogPanelVisible);
    if (!state.cocotbLogPanelVisible) {
      // Turning the feature on reveals its dock tab (VSCode semantics),
      // wherever the user has placed it.
      notifier.revealDockTabPlaced(kBottomDockTabCocotb, kDockRegionBottom);
    }
  }

  /// After a contributed bottom-dock tab toggler runs (SVA, AI Waveform
  /// Assistant), open the bottom pane if the toggler just turned a tab *on*.
  ///
  /// Togglers contributed through [extraBottomDockTabsProvider] only flip their
  /// own visibility flag. That flag selects bottom-pane *content* in
  /// the bottom dock's entry list but does not open the pane itself — so firing
  /// the action while the bottom pane is collapsed sets the flag and appears to
  /// do nothing; the panel only surfaces once the user opens the pane by hand.
  /// This mirrors the built-in cocotb handler, which force-opens the pane on
  /// show. It only ever *opens*: toggling a tab off leaves no contributed tab
  /// visible, so the pane is left as-is rather than yanked shut. The gated
  /// (sub-Pro, post-beta) path sets no visibility flag, so the pane stays put.
  void _revealBottomPaneForContributedTab() {
    final extraTabs = _activeTabContainer.read(extraBottomDockTabsProvider);
    if (extraTabs.isEmpty) return;
    final tier = _activeTabContainer.read(licenseTierProvider);
    for (final tab in extraTabs) {
      if (!FeatureGate.isAvailable(tab.requiredTier, tier)) continue;
      if (_activeTabContainer.read(tab.visibilityProvider)) {
        // Reveal, dock-style: open the region AND make the contributed tab
        // the active one. The dock's own auto-reveal also fires for a newly
        // present contributed tab, but only post-frame and only while the
        // dock is mounted; this reveals synchronously from the action.
        _activeTabContainer
            .read(panelLayoutProvider.notifier)
            .revealBottomDockTab(tab.id);
        return;
      }
    }
  }

  /// Opens a file picker for a stems file and feeds the result into the
  /// [RtlSourceNotifier]. Desktop-only — gated on [deviceClassProvider].
  Future<void> _loadRtlStemsFile() async {
    if (!_isDesktopDeviceClass()) return;
    if (ref.read(systemDialogInFlightProvider)) return;
    final l10n = L10N.of(context);
    // Read before the await; see [SystemDialogInFlight.end].
    final inFlight = ref.read(systemDialogInFlightProvider.notifier)..begin();
    final FilePickerResult? picked;
    try {
      picked = await ref.read(openFilePickerProvider)(
        dialogTitle: l10n.rtlSourceFilePickerTitle,
      );
    } finally {
      inFlight.end();
    }
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null || !mounted) return;
    await _loadStemsFromPath(path);
  }

  /// Generates a stems file from an HDL (Verilog/VHDL) source tree — the in-app
  /// replacement for GTKWave's xml2stems/vermin — then loads it. Desktop-only.
  Future<void> _generateRtlStems() async {
    if (!_isDesktopDeviceClass()) return;
    final l10n = L10N.of(context);
    final outcome = await GenerateStemsDialog.show(context);
    if (outcome == null || !mounted) return;
    await _loadStemsFromPath(outcome.stemsPath);
    if (!mounted) return;
    final message = outcome.warningCount > 0
        ? l10n.rtlGenerateWarningsNotice(outcome.warningCount)
        : l10n.rtlGenerateSuccess(outcome.mappingCount, outcome.topModule);
    showCruxInfoSnack(context, message);
  }

  /// Imports a Verilator `--json-only` AST dump as a stems file (elaborated
  /// hierarchy, generate loops unrolled) — then loads it. Desktop-only.
  Future<void> _importVerilatorAst() async {
    if (!_isDesktopDeviceClass()) return;
    final l10n = L10N.of(context);
    final outcome = await ImportVerilatorAstDialog.show(context);
    if (outcome == null || !mounted) return;
    await _loadStemsFromPath(outcome.stemsPath);
    if (!mounted) return;
    final message = outcome.warningCount > 0
        ? l10n.rtlImportAstWarningsNotice(outcome.warningCount)
        : l10n.rtlImportAstSuccess(outcome.mappingCount, outcome.topModule);
    showCruxInfoSnack(context, message);
  }

  /// Loads the stems file at [path] into the RTL notifier and, on success,
  /// reveals the panel on the ACTIVE tab (forcing its host right pane open).
  /// `panelLayoutProvider` is per-tab, so the reveal must target the active
  /// tab's container — a root-scope write flips an instance nothing watches.
  Future<void> _loadStemsFromPath(String path) async {
    final l10n = L10N.of(context);
    // rtlSourceProvider is per-tab — load into the active tab's container so
    // the stems annotate the focused tab, not a root-scope singleton shared by
    // every tab.
    final notifier = _activeTabContainer.read(rtlSourceProvider.notifier);
    await notifier.loadStemsFile(path);
    final state = _activeTabContainer.read(rtlSourceProvider);
    if (!mounted) return;
    if (state.status == RtlStemsStatus.error) {
      showCruxErrorSnack(context, l10n.rtlSourceLoadError(state.error ?? ''));
      return;
    }
    // The RTL panel replaces the value column in the right pane, which only
    // renders when the value column is visible — force the host pane open.
    _activeTabContainer.read(panelLayoutProvider.notifier)
      ..setValueColumnVisible(visible: true)
      ..setRtlSourceVisible(visible: true);
  }

  void _toggleRtlSourcePanel() {
    if (!_isDesktopDeviceClass()) return;
    // Per-tab provider: route through the active tab's container (see
    // [_togglePanelOnActiveTab]). A root-scope write is the bug that made
    // Cmd/Ctrl+Shift+R a no-op regardless of value-column state.
    final notifier = _activeTabContainer.read(panelLayoutProvider.notifier);
    final willShow = !_activeTabContainer
        .read(panelLayoutProvider)
        .rtlSourceVisible;
    notifier.setRtlSourceVisible(visible: willShow);
    // Revealing the RTL panel opens the right dock with its tab active.
    if (willShow) notifier.revealRightDockTab(kRightDockTabRtlSource);
  }

  Future<void> _analyzeSwitchingActivity() async {
    final source = _activeTabContainer.read(waveformSourceProvider).value;
    if (source == null) return;

    final variablesMap = _activeTabContainer.read(signalVariablesMapProvider);
    final signalRefToPath = _collectSignalRefToPath(
      _activeTabContainer.read(signalGroupsProvider).entries,
      variablesMap,
    );
    if (signalRefToPath.isEmpty) return;

    final (startTime, endTime) = _activeTabContainer.read(
      visibleTimeRangeProvider,
    );

    await _activeTabContainer
        .read(switchingActivityProvider.notifier)
        .analyze(signalRefToPath, startTime, endTime);

    // Auto-dock the bottom pane on the active tab with the Activity tab
    // frontmost, so the report is visible without the user opening it
    // manually. A call-site reveal, not the dock's auto-reveal: the dock may
    // be unmounted (region hidden) when the analysis lands, and an entry that
    // exists at mount is baseline, not news.
    _togglePanelOnActiveTab(
      (n) => n.revealDockTabPlaced(kBottomDockTabActivity, kDockRegionBottom),
    );
    _recordToolOpened('activity');
  }

  static Map<String, String> _collectSignalRefToPath(
    List<SignalEntry> entries,
    Map<String, Variable> variablesMap,
  ) {
    final result = <String, String>{};
    for (final entry in entries) {
      if (entry.kind == SignalEntryKind.signal && entry.signalRef != null) {
        final signalRef = entry.signalRef!;
        result[signalRef] = variablesMap[signalRef]?.fullPath ?? signalRef;
      } else if (entry.kind == SignalEntryKind.group) {
        result.addAll(_collectSignalRefToPath(entry.children, variablesMap));
      }
    }
    return result;
  }

  /// Opens a picker of the currently-set markers; selecting one removes it.
  /// No-op (with a hint) when no markers are set.
  Future<void> _showRemoveMarkerDialog() async {
    final letters = _activeTabContainer
        .read(markerStateProvider)
        .getAllMarkers()
        .map((e) => e.key)
        .toList();
    if (letters.isEmpty) {
      showCruxInfoSnack(context, L10N.of(context).markerNone);
      return;
    }
    final letter = await showDialog<String>(
      context: context,
      builder: (ctx) => _RemoveMarkerDialog(letters: letters),
    );
    if (letter == null || !mounted) return;
    _activeTabContainer.read(markerStateProvider.notifier).removeMarker(letter);
  }

  void _openCommandPalette() {
    // Re-entrancy guarded inside CommandPaletteDialog.show (also covers the
    // global Cmd/Ctrl+Shift+P handler wired in app.dart).
    unawaited(
      CommandPaletteDialog.show(
        context,
        onAction: _handleShortcut,
        tabContainer: _activeTabContainer,
      ),
    );
  }

  Future<void> _compareWaveforms() async {
    if (ref.read(systemDialogInFlightProvider)) return;
    // Read before the await; see [SystemDialogInFlight.end].
    final inFlight = ref.read(systemDialogInFlightProvider.notifier)..begin();
    final FilePickerResult? result;
    try {
      result = await ref.read(openFilePickerProvider)(
        type: FileType.custom,
        allowedExtensions: const ['vcd', 'fst', 'ghw', 'fsdb', 'lxt', 'lxt2'],
      );
    } finally {
      inFlight.end();
    }
    if (!mounted) return;
    final path = result?.files.firstOrNull?.path;
    if (path == null) return;
    // diffProvider is per-tab (nextDivergence/prevDivergence already route
    // through _activeTabContainer); loading the comparison into the root scope
    // would leave the focused tab's diff panel empty (scope-leak class).
    await _activeTabContainer.read(diffProvider.notifier).loadSecondFile(path);
    if (!mounted) return;
    final err = _activeTabContainer.read(diffProvider).error;
    if (err != null) {
      showCruxErrorSnack(context, L10N.of(context).diffLoadError(err));
      return;
    }
    // Call-site reveal: surface the Diff tab in the left dock, opening the
    // region if the user had it hidden (the dock's own auto-reveal cannot
    // fire while the region — and so the dock — is unmounted).
    _activeTabContainer
        .read(panelLayoutProvider.notifier)
        .revealLeftDockTab(kLeftDockTabDiff);
    _recordToolOpened('comparison');
  }

  // No file-loaded guard here: every surface that can reach this method
  // (toolbar button's `isLoaded ? onAddDecoder : null`, and the keyboard /
  // menu bar / overflow menu / command palette dispatch through
  // `_handleShortcut`'s `unmetActionRequirement` check, since `addDecoder`'s
  // `ActionDescriptor` declares `requires: [ActionRequirement.fileLoaded]`)
  // already refuses before calling in when no file is loaded. See
  // `_handleShortcut` in viewer_screen_shortcuts.dart for the single source
  // of truth.
  void _openDecoderPicker() {
    // One entry per name, so every name of an aliased signal is offered.
    final signalMap = _activeTabContainer.read(signalVariablesByPathProvider);
    unawaited(
      ModalGuard.run(
        'addDecoder',
        () async => await DecoderPickerDialog.show(
          context,
          signalMap: signalMap,
          tabContainer: _activeTabContainer,
        ),
      ),
    );
  }

  void _openSearch() {
    unawaited(
      ModalGuard.run(
        'openSearch',
        () async => await SignalSearchDialog.show(
          context,
          tabContainer: _activeTabContainer,
        ),
      ),
    );
  }

  void _openPatternSearch() {
    unawaited(
      ModalGuard.run(
        'patternSearch',
        () async => await PatternSearchDialog.show(
          context,
          tabContainer: _activeTabContainer,
        ),
      ),
    );
  }

  void _exportWaveform() {
    // Issue 17: route the export through the active tab's
    // [ProviderContainer]. The `exportProvider` is overridden per-tab
    // in [`wavecruxTabOverrides`], so reading the notifier from the
    // active tab's container produces an instance whose internal
    // `ref` reads `waveformSourceProvider` / `signalGroupsProvider` /
    // `timeMapperProvider` from the same per-tab scope where the
    // user's actual file is loaded. Going through `ref.read(...)` on
    // the screen-level (root) ref would resolve to a no-file root
    // scope and trigger the "no waveform loaded" snackbar.
    unawaited(
      ModalGuard.run(
        'exportWaveform',
        () async => await _activeTabContainer
            .read(exportProvider.notifier)
            .showExportDialog(
              context,
              waveformRepaintKey: _activeTabRepaintKey(),
            ),
      ),
    );
  }

  /// File ▸ Share Annotated Waveform… — routed through the active tab's
  /// container for exactly the reason [_exportWaveform] is: the notifier reads
  /// per-tab state (the source, the signal list, the annotations), and the
  /// root scope has none of it.
  void _shareAnnotatedWaveform() {
    unawaited(
      ModalGuard.run(
        'shareAnnotatedWaveform',
        () async => await _activeTabContainer
            .read(sharePackProvider.notifier)
            .shareAnnotatedWaveform(
              context,
              waveformRepaintKey: _activeTabRepaintKey(),
            ),
      ),
    );
  }
}
