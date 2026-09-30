// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The viewer screen's reactive handlers, extracted from viewer_screen.dart:
// the callbacks that fire because something *else* changed, rather than
// because the user asked for something.
//
//   * **File watching** — the on-disk waveform changed or was deleted, and the
//     screen has to offer a reload or say the file is gone.
//   * **Memory guard** — the loaded design crossed a budget and the guard
//     wants to warn or shed.
//   * **Selection** — the selected-variable set changed, which drives the
//     dependent panels.
//   * **Form factor** — a landscape hint on first rotation, and the theme
//     toggle.
//   * **The bottom panel sheet** — the compact-layout presentation of the
//     panels the desktop layout docks.
//
// WHY THIS CLUSTER. Every member here is a `ref.listen` target or a
// device-class reaction: none of them is reachable from an action, none is on
// the render path, and each one is easy to mistake for dead code when read in
// isolation halfway down a screen — because nothing in the file calls it. They
// are called by `initState`'s listener registrations, which now sit next to
// nothing else and are much easier to follow for it.
//
// WHY A PART-FILE EXTENSION: see the header of viewer_screen_file_io.dart,
// which also records what part-splitting does and does not buy.

part of 'viewer_screen.dart';

extension _ViewerScreenReactions on _ViewerScreenState {
  void _onFileWatchStateChanged(FileWatchState? previous, FileWatchState next) {
    if (!mounted) return;
    switch (next) {
      case FileWatchChanged():
        _handleFileChanged();
      case FileWatchDeleted():
        _handleFileDeleted();
      case FileWatchIdle():
        break;
    }
  }

  void _onMemoryGuardStateChanged(
    MemoryGuardState? previous,
    MemoryGuardState next,
  ) {
    if (!mounted) return;
    // Only show a snackbar when signals were actually unloaded.
    if (next.lastUnloadedCount == 0) return;
    // Avoid duplicate snackbars for the same unload event.
    if (previous?.lastUnloadedCount == next.lastUnloadedCount &&
        previous?.pressureLevel == next.pressureLevel) {
      return;
    }
    final l10n = L10N.of(context);
    final message = next.osMemoryPressureReceived
        ? l10n.memoryPressureOsWarningSnackbar
        : l10n.memoryPressureWarningSnackbar(next.lastUnloadedCount);
    showCruxInfoSnack(context, message);
  }

  void _handleFileChanged() {
    final settings = ref.read(appSettingsProvider).value ?? const AppSettings();

    if (settings.autoReloadMode == AutoReloadMode.auto) {
      unawaited(_reloadWaveform());
      return;
    }
    if (settings.autoReloadMode == AutoReloadMode.off) {
      _activeTabContainer.read(fileWatcherProvider.notifier).dismiss();
      return;
    }

    // prompt mode — show a persistent banner.
    final l10n = L10N.of(context);
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: Text(l10n.fileWatcherFileChanged),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              _activeTabContainer.read(fileWatcherProvider.notifier).dismiss();
            },
            child: Text(l10n.fileWatcherIgnore),
          ),
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              unawaited(_reloadWaveform());
            },
            child: Text(l10n.fileWatcherReload),
          ),
        ],
      ),
    );
  }

  void _handleFileDeleted() {
    _activeTabContainer.read(fileWatcherProvider.notifier).dismiss();
    if (mounted) {
      showCruxInfoSnack(context, L10N.of(context).fileWatcherFileDeleted);
    }
  }

  /// Shows the phone-class equivalent of the IdeLayout bottom pane as a
  /// modal bottom sheet. Driven by the [StatusBar] bottom chevron's
  /// `onShowBottomPanelSheet` callback.
  void _showBottomPanelSheet() {
    // showModalBottomSheet builds via the root navigator, OUTSIDE the per-tab
    // UncontrolledProviderScope that PaneHost wraps the body in. The sheet
    // hosts the REAL bottom dock (same entry list, same select-and-persist
    // wiring as the desktop region — see [WaveCruxBottomDockSheet]); rebind
    // to the active tab's container so it resolves THIS tab's
    // [panelLayoutProvider] (and source/cursor/etc.) rather than the empty
    // root scope.
    final tabContainer = _activeTabContainer;
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => UncontrolledProviderScope(
          container: tabContainer,
          child: SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.7,
              child: const WaveCruxBottomDockSheet(),
            ),
          ),
        ),
      ),
    );
  }

  bool _isDesktopDeviceClass() {
    final dc = ref.read(deviceClassProvider);
    return dc != DeviceClass.phone &&
        dc != DeviceClass.phoneLandscape &&
        dc != DeviceClass.tablet;
  }

  void _onSelectedVariablesChanged(Set<String>? previous, Set<String> next) {
    // Only react when the panel is visible, stems are loaded, and the user
    // just picked a (single) new signal — multi-select wouldn't have an
    // unambiguous source target.
    if (!_isDesktopDeviceClass()) return;
    // `panelLayoutProvider` and `signalVariablesMapProvider` are per-tab, so
    // every read must target the active tab's container; a root-scope read
    // observes the empty root instance (rtlSourceVisible always false) and the
    // bidirectional source-nav never fires.
    final container = _activeTabContainer;
    final layout = container.read(panelLayoutProvider);
    if (!layout.rtlSourceVisible) return;
    if (!container.read(rtlStemsLoadedProvider)) return;
    if (next.isEmpty || next.length != 1) return;
    // Selection carries fullPaths (row identity) — resolve to the exact
    // Variable so RTL nav lands on the scope the user actually clicked, not
    // an arbitrary FST alias of the same net.
    final fullPath = next.first;
    if (previous != null && previous.contains(fullPath)) return;
    final variable = container.read(signalVariablesByPathProvider)[fullPath];
    if (variable == null) return;
    // Fire-and-forget; the RtlSourceNotifier handles errors internally and
    // surfaces them via its own state.
    unawaited(
      container
          .read(rtlSourceProvider.notifier)
          .showSignal(signalRef: variable.signalRef, signalPath: fullPath),
    );
  }

  void _toggleTheme() {
    // A theme the organization locked is not the user's to flip; say so rather
    // than ignore the key.
    if (ref.read(orgThemeLockedProvider)) {
      showCruxInfoSnack(
        context,
        L10N.of(context).appearanceThemeLockedByPolicy,
      );
      return;
    }
    // Brightness is driven by the active color-theme preset, not the legacy
    // AppThemeMode flag — flip between the default light and dark presets.
    // See theme_brightness_toggle.dart.
    toggleThemeBrightness(
      ref.read(cruxColorThemeProvider.notifier),
      ref.read(cruxColorThemeProvider),
    );
  }

  /// Shows a one-time snackbar suggesting landscape orientation when a
  /// waveform file is opened on a phone in portrait orientation. No-op on
  /// tablet, desktop, web, or after the user has dismissed it once.
  void _maybeShowLandscapeHint() {
    if (!mounted) return;
    if (kIsWeb) return;
    if (isDesktopPlatform) return;
    final deviceClass = ref.read(deviceClassProvider);
    if (deviceClass != DeviceClass.phone) return; // only phone-portrait
    final hint = ref.read(landscapeHintProvider.notifier);
    if (!hint.shouldShow) return;
    hint.markShown();
    final l10n = L10N.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.landscapeHintSnackbar),
        action: SnackBarAction(
          label: l10n.landscapeHintDismiss,
          onPressed: () {
            messenger.hideCurrentSnackBar();
            ref.read(landscapeHintProvider.notifier).dismiss();
          },
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
