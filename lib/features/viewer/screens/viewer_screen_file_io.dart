// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// File, session and pack I/O for the viewer screen, extracted from
// viewer_screen.dart. Every way a waveform can enter the app lives here: the
// desktop and web pickers, files dropped on the desktop window, CLI arguments,
// the runtime file-open channel, URLs, recents, workspace restore, `.wavecrux`
// sessions, `.wcxpack` bundles, and GTKWave `.gtkw` import — plus the save
// side and the close/reload pair.
//
// WHY THIS CLUSTER. These 30 members were spread across 1,800 lines of the
// screen and call each other constantly (`_openFile` → `_openFileDesktop` →
// `_openPath` → `_checkFileSizeBeforeLoad` → `_handleFsdbOpen`). Reading any
// one of them meant paging past unrelated tool and annotation handlers.
// Nothing about the split changes behaviour: the members moved verbatim.
//
// WHY A PART-FILE EXTENSION (and not a service class). The same argument the
// shortcut extraction records, and it applies harder here: these handlers are
// glue over the screen's private surface — `_tabContainer`,
// `_activeTabContainer`, `_repaintKeyForTab`, `setState`, `mounted`,
// `widget.*` — and several are `await`-heavy with `context.mounted` guards
// afterwards. A collaborator class would need that surface as a
// twenty-callback constructor, which is a whole-file split with no benefit
// and nothing meaningfully unit-testable at the far end. The part keeps
// private access, so the move needed zero member promotions and zero import
// churn (a part shares the library's imports), and coverage stays exactly
// where it was: these flows are exercised end-to-end through the screen in
// viewer_screen_test.dart, which is the same entry the running app uses.
//
// WHAT THIS DOES NOT DO. Splitting the library into parts reduces the size of
// each *file* and therefore what a reviewer has to hold at once. It does not
// reduce coupling: the extension still reaches into the state's privates, and
// the library is still the same size in total. Genuinely decoupling these
// flows means giving the screen a file-open seam it can be tested against —
// which is the shape NetCrux uses (`services/file_open_service.dart`) and a
// larger piece of work than the file split. It is worth doing and it is not
// what this is.
//
// PER-TAB ROUTING INVARIANT (issue #44 scope-leak class): handlers that mutate
// file-scoped state MUST resolve providers through `_tabContainer(id)` or
// `_activeTabContainer`, never through the screen's root-scope `ref`. A
// root-scope `ref.read` of a per-tab provider silently writes the empty root
// instance, and the open silently targets nothing. Root-scope `ref.read` is
// correct ONLY for genuinely app-global state (device class, recents,
// workspace/tab management, extension-point seams).

part of 'viewer_screen.dart';

/// File, session and pack I/O for [_ViewerScreenState] — see the header above
/// for why this lives in a part-file extension.
extension _ViewerScreenFileIo on _ViewerScreenState {
  /// Opens a file that arrived at RUNTIME — an OS "Open With" / Finder
  /// double-click / `open -a` (delivered on desktop as a `file://` deep-link
  /// the router rewrites to `/viewer?file=…`) or a warm share-sheet delivery —
  /// once the cold-start workspace reconcile has settled.
  ///
  /// The wait on [startupReconcileProvider] mirrors [_openInitialCliFiles] and
  /// is the fix for the macOS "open-file event ignored while a large session is
  /// restoring" defect: a file opened while a
  /// big workspace (e.g. a multi-hundred-MB FST) is still restoring would
  /// otherwise race the reconcile — its tab activation gets clobbered by the
  /// reconcile's focus restore, or it lands before the deferred-load listener
  /// is installed — and the open is silently lost, never applied even after the
  /// restore finishes. Parking on the barrier queues the open and drains it the
  /// moment the reconcile completes (the barrier is always completed by
  /// `_WaveCruxAppState`, even on the `--workspace`/nothing-to-restore paths).
  Future<void> _openRuntimeFile(String path) async {
    await ref.read(startupReconcileProvider).future;
    if (!mounted) return;
    await _openOrFocusFile(path);
  }

  /// Opens the file(s) passed on the command line (the first positional file
  /// plus any extras), after the cold-start workspace reconcile has settled.
  ///
  /// The wait on [startupReconcileProvider] is what makes the
  /// open-file-with-a-saved-workspace launch coherent: `_WaveCruxAppState`
  /// restores the saved tabs first (deferred-loaded), then completes the
  /// barrier; only then does this open run, so it can de-duplicate against an
  /// already-restored copy ([_openOrFocusFile]) instead of opening the same
  /// file twice, and its activation of the opened file is the final word on
  /// focus. The CLI contract is that the FIRST positional file ends active.
  Future<void> _openInitialCliFiles(String firstPath) async {
    await ref.read(startupReconcileProvider).future;
    if (!mounted) return;
    final paths = <String>[
      firstPath,
      ...ref.read(initialAdditionalFilePathsProvider),
    ];
    TabId? firstTabId;
    for (final path in paths) {
      final id = await _openOrFocusFile(path);
      if (!mounted) return;
      firstTabId ??= id;
    }
    if (firstTabId != null) {
      ref.read(activeTabIdProvider.notifier).activate(firstTabId);
    }
  }

  /// Focuses the existing tab for [path] if one is already open (e.g. restored
  /// from the saved workspace), otherwise opens it via [_openPath]. Returns the
  /// resolved tab id (null if the open was declined — size warning / cancelled
  /// conversion).
  ///
  /// A `<design>.crux-project` manifest — or a design directory holding one —
  /// is swapped for the waveform it names **before** anything else here runs,
  /// so tab reuse, the large-file warning, format conversion and session
  /// restore all behave exactly as they do for a directly-opened dump. Nothing
  /// downstream needs to know a manifest was involved — which is also why the
  /// swap happens here rather than in each caller.
  Future<TabId?> _openOrFocusFile(String rawPath) async {
    final resolution = const CruxProjectResolver().resolve(rawPath);
    final String path;
    switch (resolution) {
      case NotAManifest(path: final passthrough):
        path = passthrough;
      case ManifestWaveform(
        :final waveformPath,
        :final legacySuggestedFileName,
      ):
        path = waveformPath;
        // A legacy bare `.crux-project` still opens; say once, in the user's
        // language, what to rename it to so pickers can show it.
        if (legacySuggestedFileName != null && mounted) {
          showCruxInfoSnack(
            context,
            L10N.of(context).cruxProjectLegacyFileName(legacySuggestedFileName),
          );
        }
      case ManifestAmbiguous(:final directory, :final candidates):
        if (mounted) {
          showCruxErrorSnack(
            context,
            L10N
                .of(context)
                .cruxProjectAmbiguousDirectory(
                  p.basename(directory),
                  candidates.map(p.basename).join(', '),
                ),
          );
        }
        return null;
      case ManifestUnusable(:final message):
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(message),
                behavior: SnackBarBehavior.floating,
              ),
            );
        }
        return null;
    }

    final existing = ref.read(tabListProvider).where((t) => t.filePath == path);
    if (existing.isNotEmpty) {
      final id = existing.first.id;
      final wasAlreadyActive = ref.read(activeTabIdProvider) == id;
      ref.read(activeTabIdProvider.notifier).activate(id);
      await _refreshFocusedExistingTab(
        id,
        path,
        wasAlreadyActive: wasAlreadyActive,
      );
      return id;
    }
    final before = ref.read(tabListProvider).map((t) => t.id).toSet();
    await _openPath(path);
    if (!mounted) return null;
    // _openPath → openFile creates and activates the new tab; the active id is
    // it, unless the open was declined (then no new tab exists).
    final activeId = ref.read(activeTabIdProvider);
    return before.contains(activeId) ? null : activeId;
  }

  /// A just-focused already-open tab may still need a (re)load. Two bug
  /// states, both hit routinely by the mobile share-sheet flow (which imports
  /// every incoming file to `Documents/SharedImports/<name>`, so a same-named
  /// share re-targets the exact path an existing tab holds):
  ///
  ///  * **Replaced on disk** — the import overwrote the path in place, so the
  ///    focused tab silently shows the PREVIOUS file's waveform (HDL dumps
  ///    are all called `dump.vcd`; this is the phone "second file won't
  ///    open / drawer shows the earlier file's signals" defect). Detected
  ///    via the mtime+size stat captured at parse time; reloaded through
  ///    [SessionNotifier.reloadCurrentFile], the same path the file watcher's
  ///    Reload action uses, so decoders and viewer state survive.
  ///  * **Never loaded** — the tab was restored deferred (phone single-tab
  ///    restore, or the crash-guard suppressed the auto-load) and activating
  ///    an ALREADY-ACTIVE tab emits no `activeTabIdProvider` change, so the
  ///    deferred-load listener in `_WaveCruxAppState` never fires and the
  ///    signal tree stays empty. Only the [wasAlreadyActive] case is loaded
  ///    here (sidecar first, mirroring `_ensureTabLoaded`); when the
  ///    activation actually changes the active tab, the deferred-load
  ///    listener owns the load — loading here too would race it (see the
  ///    double-load hazard documented on that listener).
  Future<void> _refreshFocusedExistingTab(
    TabId id,
    String path, {
    required bool wasAlreadyActive,
  }) async {
    // The dedupe path reaches here synchronously from didUpdateWidget (i.e.
    // mid-build), and both load paths below mutate per-tab providers in their
    // synchronous prologue — which Riverpod forbids during build. Yield to
    // the event loop first; this also lets the just-issued activate() settle,
    // so the isLoading check correctly skips when the deferred-load listener
    // has already picked the tab up.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final container = _tabContainer(id);
    final source = container.read(waveformSourceProvider);
    if (source.isLoading) return; // a load is already in flight
    final sourceNotifier = container.read(waveformSourceProvider.notifier);

    if (source.value != null) {
      if (sourceNotifier.isSourceFileReplacedOnDisk()) {
        await container.read(sessionProvider.notifier).reloadCurrentFile();
      }
      return;
    }

    if (!wasAlreadyActive) return; // deferred-load listener owns this load
    try {
      final sidecarPath = await ref
          .read(workspaceServiceProvider)
          .sidecarPathFor(id.value);
      if (sidecarPath != null && File(sidecarPath).existsSync()) {
        await container
            .read(sessionProvider.notifier)
            .loadFromPath(sidecarPath);
        return;
      }
    } on Object {
      // Fall through to a plain open, mirroring _ensureTabLoaded.
    }
    await sourceNotifier.openFile(path);
    // No sidecar, so this tab has a NEW session — the one moment an
    // organization's session template may seed one. Reaching this line is
    // itself the proof: the restore branch above returned.
    await seedOrgSessionTemplateLogging(container);
  }

  Future<void> _openFile() async {
    if (!mounted) return;
    if (kIsWeb) {
      await _openFileWeb();
    } else {
      await _openFileDesktop();
    }
  }

  Future<void> _openFileDesktop() async {
    if (ref.read(systemDialogInFlightProvider)) return;
    // Read before the await; see [SystemDialogInFlight.end].
    final inFlight = ref.read(systemDialogInFlightProvider.notifier)..begin();
    final FilePickerResult? result;
    try {
      result = await ref.read(openFilePickerProvider)(
        type: FileType.custom,
        // .wavecrux session files are accepted alongside waveform
        // formats — the post-pick dispatch below routes them to the
        // session loader instead of the waveform loader. Without
        // this users couldn't pick a previously-saved session file
        // from File→Open.
        allowedExtensions: const [
          'vcd',
          'fst',
          'ghw',
          'fsdb',
          'lxt',
          'lxt2',
          'wavecrux',
          // A share bundle arrives from someone else, so File▸Open is the
          // path most recipients will actually take to it — the file
          // association only helps once they know what the icon is.
          'wavecruxpack',
          // A design manifest opens the waveform it names.
          kCruxProjectExtension,
        ],
      );
    } finally {
      inFlight.end();
    }
    if (result == null || result.files.isEmpty) return;
    // `FilePicker.pickFiles` IS the multi-select API — `allowMultiple` defaults
    // to true and is deprecated in favour of `pickFile` for the single case —
    // so the panel has always offered a multiple selection here and the caller
    // has always had to handle one. This read `result.files.single`, which
    // throws on two files, inside an async callback where nothing surfaced it:
    // choosing two waveforms and clicking Open did nothing at all. No tab, no
    // error, no message. Dropping the same two files on the window opened both.
    //
    // Each path routes itself: _openChosenPath dispatches a pack, a session, a
    // design manifest or a waveform by extension, so a mixed selection needs no
    // policy here. This is the same loop as _openDroppedPaths, deliberately —
    // the two routes to "open this file" now agree, which is what the drop
    // overlay has been promising all along ("Each file opens in its own tab").
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      if (!mounted) return;
      // Save each bookmark while the picker session is still active, so every
      // chosen path survives a restart — not just the first.
      await SecurityScopedBookmarkService.saveBookmark(path);
      if (!mounted) return;
      await _openChosenPath(path);
    }
  }

  /// Opens a path the user chose on this machine — from the File > Open
  /// picker, or by dropping it on the window ([_openDroppedPaths]) — by its
  /// extension: a share bundle, a saved session, a design manifest, or else a
  /// waveform in a new tab.
  ///
  /// Branching matters because [_openPath] would otherwise feed a session's
  /// JSON to [WaveformDataSource.openFile] and fail with a parser error.
  Future<void> _openChosenPath(String path) async {
    if (WaveCruxPackSpec.isPackFilePath(path)) {
      await _openPack(path);
    } else if (SessionService.isSessionFilePath(path)) {
      await ref.read(recentFilesProvider.notifier).addFile(path);
      if (!mounted) return;
      await _loadSession(path);
    } else if (CruxProjectParser.isManifestPath(path)) {
      await _openOrFocusFile(path);
    } else {
      await _openPath(path);
    }
  }

  /// Opens files dropped onto the desktop window, delivered by
  /// [DesktopFileDropRouter] in its open order (waveforms first, `.gtkw`
  /// sessions last).
  ///
  /// Each path takes the File > Open route ([_openChosenPath]), so a drop
  /// behaves exactly as picking the same file would: every waveform opens in
  /// its own tab, FSDB gets its conversion offer, a file that cannot be parsed
  /// shows the load error in its tab, and Recent Files records it. Two
  /// additions a picker never needs:
  ///
  ///  * **A dropped `.gtkw`** is imported into the active tab, as
  ///    File > Import GTKWave Session does after its own picker — including
  ///    the same summary when no waveform is open to apply it to.
  ///  * **A dropped folder** goes through [_openOrFocusFile], which resolves
  ///    a design folder to the waveform its `.crux-project` names, as a folder
  ///    passed on the command line is.
  ///
  /// Waits for the cold-start workspace restore first, as a runtime open-file
  /// event does ([_openRuntimeFile]): a drop onto a window that is still
  /// restoring would otherwise race the restore's own focus changes.
  Future<void> _openDroppedPaths(List<String> paths) async {
    await ref.read(startupReconcileProvider).future;
    for (final path in paths) {
      if (!mounted) return;
      if (DesktopFileDropRouter.isGtkwPath(path)) {
        await SecurityScopedBookmarkService.saveBookmark(path);
        if (!mounted) return;
        await _importGtkwFromPath(path);
      } else if (FileSystemEntity.isDirectorySync(path)) {
        await _openOrFocusFile(path);
      } else {
        await SecurityScopedBookmarkService.saveBookmark(path);
        if (!mounted) return;
        await _openChosenPath(path);
      }
    }
  }

  /// Makes this screen the destination of files dropped on the desktop
  /// window (see [DesktopFileDropRouter]); returns the call that undoes it.
  void Function() _attachFileDrop() => ref
      .read(desktopFileDropRouterProvider)
      .attach(
        DesktopFileDropHandler(
          canAccept: _canAcceptFileDrop,
          onDrop: _openDroppedPaths,
        ),
      );

  /// Whether a window drop may land now: the viewer is the current route, no
  /// native file dialog is up, and no modal gate (the licence agreement, the
  /// telemetry disclosure) has taken the viewer out of focus.
  bool _canAcceptFileDrop() {
    if (!mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    if (ref.read(systemDialogInFlightProvider)) return false;
    // A gate stacked over the app wraps it in `ExcludeFocus`, which marks a
    // focus node above the viewer as not letting its descendants be focused.
    final node = Focus.maybeOf(context, scopeOk: true, createDependency: false);
    if (node == null) return true;
    return [node, ...node.ancestors].every((n) => n.descendantsAreFocusable);
  }

  Future<void> _openFileWeb() async {
    final pick = await ref.read(webFileLoaderProvider).pickFile();
    if (pick == null || !mounted) return;
    if (WaveCruxPackSpec.isPackFilePath(pick.name)) {
      await _openPackBytes(pick.bytes, pick.name);
      return;
    }
    if (await _rejectFsdbOnWeb(pick.name)) return;
    if (WebFileLoader.isLargeFile(pick.bytes.length) && mounted) {
      final proceed = await _showWebFileSizeWarning(pick.bytes.length);
      if (!proceed || !mounted) return;
    }
    // Always create a new tab — never replace an existing one. The web
    // "path" is the upload's filename; the per-tab waveform source loads
    // from in-memory bytes.
    final tabId = await ref.wavecruxWorkspace.openFile(
      pick.name,
      displayName: pick.name,
    );
    if (!mounted) return;
    // Same convert-on-open progress dialog hook as the desktop
    // path. Magic-byte routing inside `openFromBytes` decides whether a
    // conversion runs; the debounce in `showIfNeeded` keeps the dialog
    // invisible on native opens.
    unawaited(
      LegacyConversionProgressDialog.showIfNeeded(
        context: context,
        ref: ref,
      ),
    );
    await _tabContainer(tabId)
        .read(waveformSourceProvider.notifier)
        .openFromBytes(pick.bytes, pick.name);
  }

  /// On web, FSDB cannot be opened: conversion needs the local `fsdb2vcd`
  /// tool, which the browser can't run. Detect a `.fsdb` upload by name and
  /// show a clear message instead of letting the raw bytes fail with a
  /// confusing generic "unsupported format" error in `openFromBytes`.
  /// Returns true when the file was an FSDB and has been handled (the caller
  /// must abort the open).
  Future<bool> _rejectFsdbOnWeb(String name) async {
    if (!const FsdbConversionService().isFsdbFile(name)) return false;
    if (mounted) await FsdbConversionDialog.showWebUnsupported(context);
    return true;
  }

  /// Bridges the EmptyCanvasState "Open Workspace…" action to the
  /// `.wavecrux-workspace` open command.
  Future<void> _openWorkspace() async {
    if (!mounted) return;
    await runOpenWorkspaceCommand(context: context, ref: ref);
  }

  /// Bridges the EmptyCanvasState recent-workspaces list to the
  /// open-workspace flow when the user taps a row.
  Future<void> _openRecentWorkspace(String path) async {
    if (!mounted) return;
    final container = ProviderScope.containerOf(context);
    final error = await openWorkspaceFromPathForContainer(container, path);
    if (!mounted) return;
    if (error != null) {
      showCruxErrorSnack(context, L10N.of(context).openWorkspaceError(error));
      return;
    }
    await container.read(recentWorkspacesProvider.notifier).addWorkspace(path);
  }

  /// Bridges the EmptyCanvasState "Other tabs from your last session" list
  /// (phone single-tab fallback, ARCHITECTURE.md §3.1.4) to the file-open
  /// flow. Removes the entry from [otherTabsFromLastSessionProvider] on
  /// success so the list shrinks as the user works through it.
  Future<void> _openOtherTabFromLastSession(WorkspaceTab tab) async {
    final path = tab.filePath;
    if (path == null || !mounted) return;
    ref.read(otherTabsFromLastSessionProvider.notifier).remove(tab);
    await _openPath(path);
  }

  /// Bridges the [EmptyCanvasState] web drop-zone callback to the file-open
  /// flow. Always creates a new tab — never
  /// replaces an existing one.
  Future<void> _openBytesAndNavigate(Uint8List bytes, String name) async {
    if (!mounted) return;
    if (WaveCruxPackSpec.isPackFilePath(name)) {
      await _openPackBytes(bytes, name);
      return;
    }
    if (await _rejectFsdbOnWeb(name)) return;
    if (WebFileLoader.isLargeFile(bytes.length) && mounted) {
      final proceed = await _showWebFileSizeWarning(bytes.length);
      if (!proceed || !mounted) return;
    }
    final tabId = await ref.wavecruxWorkspace.openFile(name, displayName: name);
    if (!mounted) return;
    await _tabContainer(
      tabId,
    ).read(waveformSourceProvider.notifier).openFromBytes(bytes, name);
  }

  Future<bool> _showWebFileSizeWarning(int sizeBytes) async {
    final l10n = L10N.of(context);
    final sizeMb = (sizeBytes / (1024 * 1024)).toStringAsFixed(1);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.webFileSizeWarningTitle),
        content: Text(l10n.webFileSizeWarningBody(sizeMb)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.webFileSizeWarningContinue),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Opens [path], handling HTTP/HTTPS URLs on web, FSDB on desktop.
  ///
  /// File→Open **always** creates a new tab —
  /// never replaces an existing one. The new tab is appended via
  /// [TabListNotifier.openFile] (which generates the tab id and activates the
  /// tab); the waveform source is then loaded into that new tab's per-tab
  /// `ProviderContainer`.
  Future<void> _openPath(String path) async {
    if (kIsWeb && UrlFileLoader.isUrl(path)) {
      await _openFromUrl(path);
      return;
    }
    const service = FsdbConversionService();
    final bool opened;
    if (service.isFsdbFile(path)) {
      opened = await _handleFsdbOpen(path, service);
    } else {
      if (!await _checkFileSizeBeforeLoad(path)) return;
      if (!mounted) return;
      final tabId = await ref.wavecruxWorkspace.openFile(path);
      if (!mounted) return;
      // Schedule the convert-on-open progress dialog. The helper
      // waits the 250 ms debounce window and only pushes the dialog if the
      // converter is still running — sub-debounce conversions and native
      // formats never produce a visible dialog.
      unawaited(
        LegacyConversionProgressDialog.showIfNeeded(
          context: context,
          ref: ref,
        ),
      );
      await _tabContainer(
        tabId,
      ).read(waveformSourceProvider.notifier).openFile(path);
      if (!mounted) return;
      _announceOpenResult(tabId, path);
      opened = true;
    }
    // Record the *original* user-facing path the user opened (the `.fsdb`,
    // not the converted `.fst`) in Recent Files, but only once a load was
    // actually initiated — a declined size warning or cancelled FSDB
    // conversion must not pollute the list. The sidecar guard inside
    // [RecentFilesNotifier.addFile] is irrelevant here (these are real
    // user files), but harmless.
    if (opened) {
      await ref.read(recentFilesProvider.notifier).addFile(path);
    }
  }

  /// Opens an entry tapped in the Welcome screen's Recent Files list,
  /// routing by file type the same way the File→Open picker does
  /// ([_openFileDesktop]): a `.wavecrux` session loads through
  /// [_loadSession], a `.gtkw` GTKWave session imports through
  /// [_importGtkwFromPath], and everything else is treated as a waveform
  /// file via [_openPath]. Routing here matters because the list now holds
  /// waveform files, saved sessions, and `.gtkw` imports — feeding a session
  /// or `.gtkw` straight to [_openPath] would hand its JSON/text to the
  /// waveform parser and fail.
  Future<void> _openRecentFile(String path) async {
    if (WaveCruxPackSpec.isPackFilePath(path)) {
      await _openPack(path);
    } else if (SessionService.isSessionFilePath(path)) {
      await _loadSession(path);
    } else if (p.extension(path).toLowerCase() == '.gtkw') {
      await _importGtkwFromPath(path);
    } else if (CruxProjectParser.isManifestPath(path)) {
      await _openOrFocusFile(path);
    } else {
      await _openPath(path);
    }
  }

  /// Opens the sample waveform bundled with the app (Welcome screen →
  /// "Open Sample Waveform").
  ///
  /// Exists so the app can demonstrate itself with no user-supplied file.
  /// That matters most on mobile, where a user cannot produce a VCD on the
  /// device at all — before this, a fresh iPhone install offered only
  /// "Open File…" into an empty picker, so the app appeared to do nothing.
  ///
  /// Routes by platform for the same reason the drop-zone path does: the
  /// waveform engine reads a real file through FFI on desktop/mobile, while
  /// web has no filesystem and must go through the byte-loading path.
  Future<void> _openSampleWaveform() async {
    const service = SampleWaveformService();
    try {
      if (kIsWeb) {
        final bytes = await service.loadBytes();
        if (!mounted) return;
        await _openBytesAndNavigate(bytes, SampleWaveformService.fileName);
      } else {
        final path = await service.materializeToFile();
        if (!mounted) return;
        await _openPath(path);
      }
    } on Exception {
      if (mounted) {
        showCruxErrorSnack(context, L10N.of(context).emptyCanvasSampleFailed);
      }
    }
  }

  /// Checks whether [path] exceeds the mobile file-size threshold for the
  /// current device class.  Returns `false` (and shows a warning dialog) when
  /// the user cancels; returns `true` when the load should proceed.
  ///
  /// Always returns `true` on desktop (no size limit) and when the file
  /// cannot be stat'd.
  Future<bool> _checkFileSizeBeforeLoad(String path) async {
    if (kIsWeb) return true;
    final deviceClass = ref.read(deviceClassProvider);
    const guard = MobileMemoryGuardService();
    int fileSize;
    try {
      fileSize = File(path).lengthSync();
    } on Exception {
      return true;
    }
    if (!guard.shouldWarnBeforeLoad(fileSize, deviceClass)) return true;
    if (!mounted) return false;
    final threshold = guard.fileSizeThresholdBytes(deviceClass)!;
    return await LargeFileWarningDialog.show(
      context,
      fileSizeBytes: fileSize,
      thresholdBytes: threshold,
    );
  }

  /// Fetches [url] via HTTP and loads the resulting bytes as a waveform.
  ///
  /// Shows the same large-file warning as the file-picker flow. Displays a
  /// SnackBar on network or HTTP errors.
  Future<void> _openFromUrl(String url) async {
    try {
      final result = await const UrlFileLoader().fetchFile(url);
      if (!mounted) return;
      if (WebFileLoader.isLargeFile(result.bytes.length) && mounted) {
        final proceed = await _showWebFileSizeWarning(result.bytes.length);
        if (!proceed || !mounted) return;
      }
      // Always create a new tab for the fetched file.
      final tabId = await ref.wavecruxWorkspace.openFile(
        result.filename,
        displayName: result.filename,
      );
      if (!mounted) return;
      await _tabContainer(tabId)
          .read(waveformSourceProvider.notifier)
          .openFromBytes(result.bytes, result.filename);
    } on UrlFetchException catch (e) {
      if (mounted) {
        showCruxErrorSnack(
          context,
          L10N.of(context).urlFileLoadError(e.reason),
        );
      }
    }
  }

  /// Handles opening an FSDB file: checks for a cached FST, prompts for
  /// conversion if `fsdb2vcd` is available, or shows an error if it is not.
  /// Handles opening an FSDB file (cached-FST reuse or convert-on-open).
  ///
  /// Returns `true` when a waveform was actually loaded (cache hit or
  /// successful conversion), `false` when the open did not proceed (no
  /// `fsdb2vcd` tool found, or the user cancelled the conversion dialog).
  /// The caller uses this to decide whether to record the FSDB path in
  /// Recent Files.
  Future<bool> _handleFsdbOpen(
    String fsdbPath,
    FsdbConversionService service,
  ) async {
    // Use a cached FST if it exists and is newer than the FSDB.
    final cached = service.getCachedFst(fsdbPath);
    if (cached != null) {
      final tabId = await ref.wavecruxWorkspace.openFile(cached);
      if (!mounted) return false;
      await _tabContainer(
        tabId,
      ).read(waveformSourceProvider.notifier).openFile(cached);
      return true;
    }

    final toolPath = service.findFsdb2Vcd();
    if (!mounted) return false;

    if (toolPath == null) {
      await FsdbConversionDialog.showNotFound(context);
      return false;
    }

    // Show confirmation dialog; it runs the conversion and returns the path.
    final convertedPath = await FsdbConversionDialog.show(
      context,
      fsdbPath: fsdbPath,
      toolPath: toolPath,
      service: service,
    );
    if (convertedPath != null && mounted) {
      final tabId = await ref.wavecruxWorkspace.openFile(convertedPath);
      if (!mounted) return false;
      await _tabContainer(
        tabId,
      ).read(waveformSourceProvider.notifier).openFile(convertedPath);
      return true;
    }
    return false;
  }

  Future<void> _loadSession(String path) async {
    // Always create a new tab for the session — never replace an existing
    // one. The tab notifier sets the session file path and a provisional
    // display name; once the session finishes loading we update the display
    // name to match the underlying waveform file (if any).
    final tabId = await ref.wavecruxWorkspace.openSession(path);
    if (!mounted) return;
    try {
      await _tabContainer(
        tabId,
      ).read(sessionProvider.notifier).loadFromPath(path);
      final filePath = _tabContainer(
        tabId,
      ).read(waveformSourceProvider.notifier).currentFilePath;
      await ref.wavecruxWorkspace.updateTab(
        tabId,
        displayName: filePath != null
            ? p.basename(filePath)
            : p.basenameWithoutExtension(path),
        filePath: filePath,
        sessionFilePath: path,
      );
    } on SessionLoadException catch (e) {
      if (mounted) {
        showCruxErrorSnack(
          context,
          L10N.of(context).sessionLoadError(e.reason),
        );
      }
    }
  }

  Future<void> _saveSession() async {
    // Not offered in the browser (see the Save Session descriptor); this
    // stops the Cmd/Ctrl+S chord reaching a save dialog the web cannot show.
    if (kIsWeb) return;
    final currentPath = _activeTabContainer.read(sessionProvider);
    if (currentPath != null) {
      await _doSave(currentPath);
    } else {
      await _saveSessionAs();
    }
  }

  Future<void> _saveSessionAs() async {
    if (kIsWeb) return;
    if (ref.read(systemDialogInFlightProvider)) return;
    final l10n = L10N.of(context);
    // Read before the await; see [SystemDialogInFlight.end].
    final inFlight = ref.read(systemDialogInFlightProvider.notifier)..begin();
    final String? result;
    try {
      result = await FilePicker.saveFile(
        // file_picker 12 requires bytes & writes the file; pass empty so it
        // only returns the chosen path and we write via our own service below.
        bytes: Uint8List(0),
        dialogTitle: l10n.sessionSaveAsDialogTitle,
        fileName: 'session.wavecrux',
        allowedExtensions: ['wavecrux'],
        type: FileType.custom,
      );
    } finally {
      inFlight.end();
    }
    // `_doSave` resolves the tab through `ref`, which throws once the screen
    // is gone.
    if (result == null || !mounted) return;
    await _doSave(result);
  }

  Future<void> _doSave(String path) async {
    try {
      await _activeTabContainer.read(sessionProvider.notifier).saveToPath(path);
      if (mounted) {
        showCruxInfoSnack(context, L10N.of(context).sessionSaveSuccess);
      }
    } on SessionSaveException catch (e) {
      if (mounted) {
        showCruxErrorSnack(
          context,
          L10N.of(context).sessionSaveError(e.reason),
        );
      }
    }
  }

  Future<void> _reloadWaveform() async {
    _activeTabContainer.read(fileWatcherProvider.notifier).dismiss();
    try {
      await _activeTabContainer
          .read(sessionProvider.notifier)
          .reloadCurrentFile();
    } on Exception catch (e) {
      if (mounted) {
        showCruxErrorSnack(
          context,
          L10N.of(context).fileWatcherReloadError(e.toString()),
        );
      }
    }
  }

  /// Speaks the outcome of opening [path] into [tabId].
  ///
  /// The waveform pane shows a load failure, but nothing moves focus to it
  /// and the desktop screen-reader bridges ignore live regions, so a file
  /// that failed to parse sounded exactly like one that opened.
  void _announceOpenResult(TabId tabId, String path) {
    final l10n = L10N.of(context);
    final source = _tabContainer(tabId).read(waveformSourceProvider);
    final fileName = p.basename(path);
    if (source is AsyncError) {
      announceCrux(
        context,
        l10n.a11yWaveformOpenFailed(fileName, '${source.error}'),
        assertive: true,
      );
    } else if (source.value != null) {
      announceCrux(context, l10n.a11yWaveformOpened(fileName));
    }
  }

  Future<void> _closeFile() async {
    if (!mounted) return;
    // Issue 7: closing a file used to leave the empty tab open with stale
    // time-mapper state — the time ruler kept rendering tick marks at the
    // last file's tick density even though no signal data was loaded. Closing
    // the tab is the cleaner UX (the user can re-open via File → Open) AND
    // it cascades into PaneHost / WorkspaceNotifier so the workspace's
    // active-pane pointer collapses correctly.
    final id = _activeTabId;
    await _activeTabContainer.read(waveformSourceProvider.notifier).close();
    if (!mounted) return;
    await ref.read(workspaceProvider.notifier).closeTab(id);
  }

  /// Routes a restore-a-view path to the loader it needs.
  ///
  /// Both arrive the same way — the CLI's session argument, a Finder
  /// double-click rewritten to `/viewer?session=…` — and only the extension
  /// distinguishes them, so the branch lives here rather than at each of the
  /// three call sites.
  Future<void> _loadSessionOrPack(String path) =>
      WaveCruxPackSpec.isPackFilePath(path)
      ? _openPack(path)
      : _loadSession(path);

  /// Expands a `.wavecruxpack` and opens the session inside it.
  ///
  /// The pack is not a second restore path: it extracts, then hands the
  /// extracted `session.wavecrux` to [_loadSession], so a shared view goes
  /// through exactly the code a locally-saved session does.
  Future<void> _openPack(String path) async {
    final extracted = await ref
        .read(sharePackProvider.notifier)
        .openPack(path, context: context);
    if (extracted == null || !mounted) return;
    await ref.read(recentFilesProvider.notifier).addFile(path);
    if (!mounted) return;
    await _loadSession(extracted.sessionPath);
  }

  /// Opens a `.wavecruxpack` from bytes, with no filesystem — the browser.
  ///
  /// **Why this exists at all.** The pack's whole purpose is to be emailed to
  /// somebody, and the recipient most worth reaching is the one who does not
  /// have WaveCrux. Until now that person landed on a page telling them to
  /// install something before they could look at what they had been sent,
  /// which is the point at which most of them stop.
  ///
  /// Structurally the same three steps as the desktop path — validate, open
  /// the dump, restore the session — with the middle step reading bytes
  /// instead of a file. It shares the reader's validation and the one
  /// `_restore`, so a pack cannot be accepted on web that would be refused on
  /// desktop, and a restored view cannot drift between them.
  Future<void> _openPackBytes(Uint8List bytes, String name) async {
    final l10n = L10N.of(context);
    final Map<String, Uint8List> entries;
    try {
      entries = WaveCruxPackReader().readEntries(
        bytes: bytes,
        diagnosticName: name,
      );
    } on WaveCruxPackException catch (e) {
      if (mounted) {
        showCruxErrorSnack(context, packFailureMessage(l10n, e.kind));
      }
      return;
    }

    final waveform = entries[WaveCruxPackSpec.waveformEntryName];
    if (waveform == null) {
      // A session with no dump beside it is the empty-pack case the desktop
      // reader cannot hit, because there the session resolves against a
      // directory that may hold one. Here there is nowhere else to look.
      if (mounted) {
        showCruxErrorSnack(
          context,
          packFailureMessage(l10n, WaveCruxPackFailureKind.missingSession),
        );
      }
      return;
    }

    final SessionState session;
    try {
      session = ref
          .read(sessionServiceProvider)
          .decodeDocument(
            utf8.decode(
              entries[WaveCruxPackSpec.sessionEntryName]!,
              allowMalformed: true,
            ),
            diagnosticName: '$name/${WaveCruxPackSpec.sessionEntryName}',
          );
    } on SessionLoadException catch (e) {
      if (mounted) showCruxErrorSnack(context, l10n.sessionLoadError(e.reason));
      return;
    }

    if (WebFileLoader.isLargeFile(waveform.length) && mounted) {
      final proceed = await _showWebFileSizeWarning(waveform.length);
      if (!proceed || !mounted) return;
    }
    if (!mounted) return;

    // The tab is named for the pack, not for the dump inside it: the pack is
    // what the user was sent and what they will look for again.
    final tabId = await ref.wavecruxWorkspace.openFile(
      name,
      displayName: name,
    );
    if (!mounted) return;
    await _tabContainer(tabId)
        .read(sessionProvider.notifier)
        .restoreFromBytes(
          // The relative `sourceFilePath` names a ZIP entry, and nothing on
          // web can resolve it. Dropped so no later save or reload mistakes it
          // for a path on a machine that has no paths.
          session: session.copyWith(sourceFilePath: null),
          waveformBytes: waveform,
          displayName: WaveCruxPackSpec.waveformEntryName,
        );
  }

  Future<void> _importGtkwSession() async {
    if (!mounted) return;
    final l10n = L10N.of(context);

    // 1. File picker — restrict to .gtkw files.
    if (ref.read(systemDialogInFlightProvider)) return;
    // Read before the await; see [SystemDialogInFlight.end].
    final inFlight = ref.read(systemDialogInFlightProvider.notifier)..begin();
    final FilePickerResult? picked;
    try {
      picked = await ref.read(openFilePickerProvider)(
        dialogTitle: l10n.gtkwImportPickerTitle,
        type: FileType.custom,
        allowedExtensions: ['gtkw'],
      );
    } finally {
      inFlight.end();
    }
    if (picked == null || picked.files.isEmpty) return;

    final gtkwPath = picked.files.first.path;
    if (gtkwPath == null) return;

    // Persist a security-scoped bookmark so a later open from the Recent
    // Files list survives an app restart (mirrors the waveform picker).
    await SecurityScopedBookmarkService.saveBookmark(gtkwPath);
    if (!mounted) return;

    await _importGtkwFromPath(gtkwPath);
  }

  /// Imports a GTKWave `.gtkw` session from [gtkwPath] into the active tab's
  /// currently-loaded waveform: parses the file, applies it through
  /// [applyGtkwImport], records the path in Recent Files, and shows the import
  /// summary dialog. Split from [_importGtkwSession] so the Recent Files
  /// list can re-open a previously-imported `.gtkw` without re-prompting for
  /// the file.
  Future<void> _importGtkwFromPath(String gtkwPath) async {
    if (!mounted) return;
    final l10n = L10N.of(context);

    // 2. Read the .gtkw file.
    String content;
    try {
      content = await File(gtkwPath).readAsString();
    } on IOException catch (e) {
      if (mounted) {
        showCruxErrorSnack(context, l10n.gtkwImportError(e.toString()));
      }
      return;
    }

    // 3. Parse the .gtkw file.
    const parser = GtkwParser();
    final gtkwFile = parser.parse(content);

    // 4. Get all variables from the currently loaded waveform (empty when none).
    final source = _activeTabContainer.read(waveformSourceProvider).value;
    final variables = source != null
        ? source.findVariables(const SignalFilter())
        : const <Variable>[];

    // 5. Run the import.
    final currentFilePath = _activeTabContainer
        .read(waveformSourceProvider.notifier)
        .currentFilePath;
    const importService = GtkwImportService();
    final importResult = importService.importSession(
      gtkwFile,
      variables,
      sourceFilePath: currentFilePath,
      gtkwFilePath: gtkwPath,
      fileExists: (path) => File(path).existsSync(),
    );

    // 6. Apply everything the import carries: traces, markers and cursor,
    // zoom and scroll position, expanded scopes and translate filters.
    await applyGtkwImport(_activeTabContainer, importResult);
    if (!mounted) return;

    // Record the imported .gtkw session in Recent Files (parse + apply
    // succeeded by this point — the only earlier exit is a file-read error).
    await ref.read(recentFilesProvider.notifier).addFile(gtkwPath);

    // The same "success is certain here" point serves the catalog counter that
    // sizes the GTKWave-migration funnel. No properties: `GtkwImportResult`
    // carries matched/unmatched signal counts, and how many signals a user's
    // design has is a fact about their design, not about the importer.
    ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent('session.gtkw_imported'),
        );

    // 8. Show summary dialog.
    if (mounted) {
      await GtkwImportResultDialog.show(context, result: importResult);
    }
  }
}
