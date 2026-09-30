// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:wavecrux/domain/enums/ai_provider.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/log_verbosity.dart';

import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

part 'settings_providers.g.dart';

// ── WaveCruxSettingsService provider ─────────────────────────────────────────────────

/// Provides the [WaveCruxSettingsService] instance.
///
/// Override in tests to inject a fake implementation.
@riverpod
WaveCruxSettingsService settingsService(Ref ref) =>
    const WaveCruxSettingsService();

// ── AppSettingsNotifier ──────────────────────────────────────────────────────

/// Loads, holds, and persists all [AppSettings].
///
/// State is an [AsyncValue] because the initial load is asynchronous
/// (reading from [SharedPreferences]). Once loaded, all mutation methods
/// update the in-memory state synchronously and persist in the background.
///
/// The presentation layer reads individual fields directly:
/// ```dart
/// final settings = ref.watch(appSettingsProvider).value
///     ?? const AppSettings();
/// ```
@Riverpod(keepAlive: true)
class AppSettingsNotifier extends _$AppSettingsNotifier {
  @override
  Future<AppSettings> build() => ref.read(settingsServiceProvider).load();

  /// Persists the legacy [AppThemeMode] preference.
  ///
  /// NOTE: this no longer drives the app's light/dark brightness — that is
  /// owned entirely by the active color-theme preset (see
  /// `wavecrux_color_theme_bootstrap.dart` and `theme_brightness_toggle.dart`).
  /// The setter is retained as persisted plumbing (the field lives in the
  /// shared `CoreSettings` model) but has no UI surface; the light/dark/system
  /// selector that called it was removed as redundant with the preset picker.
  Future<void> setThemeMode(AppThemeMode mode) =>
      _update((s) => s.copyWith(themeMode: mode));

  Future<void> setWaveformFontSize(double size) =>
      _update((s) => s.copyWith(waveformFontSize: size));

  Future<void> setCanvasLegibilityBoost({required bool enabled}) =>
      _update((s) => s.copyWith(canvasLegibilityBoost: enabled));

  Future<void> setDefaultDisplayFormat(DisplayFormat format) =>
      _update((s) => s.copyWith(defaultDisplayFormat: format));

  Future<void> setDefaultLaneHeight(int height) =>
      _update((s) => s.copyWith(defaultLaneHeight: height));

  Future<void> setAutoReloadMode(AutoReloadMode mode) =>
      _update((s) => s.copyWith(autoReloadMode: mode));

  Future<void> setAutoSaveIntervalSeconds(int seconds) =>
      _update((s) => s.copyWith(autoSaveIntervalSeconds: seconds));

  Future<void> setAutoConvertLargeVcd({required bool enabled}) =>
      _update((s) => s.copyWith(autoConvertLargeVcd: enabled));

  Future<void> setLocale(String locale) =>
      _update((s) => s.copyWith(locale: locale));

  Future<void> setRemoteControlEnabled({required bool enabled}) =>
      _update((s) => s.copyWith(remoteControlEnabled: enabled));

  Future<void> setRemoteControlPort(int port) =>
      _update((s) => s.copyWith(remoteControlPort: port.clamp(1, 65535)));

  /// Enables or disables the CXP peer cross-probe server. See [AppSettings]
  /// for the WCP/CXP delineation.
  Future<void> setCxpServerEnabled({required bool enabled}) =>
      _update((s) => s.copyWith(cxpServerEnabled: enabled));

  /// Sets the CXP server TCP port. Clamped to the valid 1–65535 range.
  Future<void> setCxpServerPort(int port) =>
      _update((s) => s.copyWith(cxpServerPort: port.clamp(1, 65535)));

  /// Sets the editor command used by inbound `request_open_source` CXP
  /// handlers (e.g. `code -g`, `subl`, `nvr`, `emacsclient`). The empty
  /// string disables the open-source path.
  Future<void> setCxpEditorCommand(String command) =>
      _update((s) => s.copyWith(cxpEditorCommand: command));

  Future<void> setDiagnosticsEnabled({required bool enabled}) =>
      _update((s) => s.copyWith(diagnosticsEnabled: enabled));

  Future<void> setOrientationLockMode(OrientationLockMode mode) =>
      _update((s) => s.copyWith(orientationLockMode: mode));

  Future<void> setAutoHideChromeSeconds(int seconds) => _update(
    (s) => s.copyWith(autoHideChromeSeconds: seconds.clamp(1, 30)),
  );

  /// Records that the user has read and accepted the one-time plugin
  /// safety acknowledgment. Until this flag is `true` the loader does
  /// not scan the filesystem.
  Future<void> setPluginSafetyAcknowledged({required bool acknowledged}) =>
      _update((s) => s.copyWith(pluginSafetyAcknowledged: acknowledged));

  /// Master switch for the entire plugin loader. When `true` the
  /// loader returns an empty list without scanning.
  Future<void> setPluginLoadingDisabled({required bool disabled}) =>
      _update((s) => s.copyWith(pluginLoadingDisabled: disabled));

  /// Replaces the user-configured plugin directory list. Existing
  /// entries are not preserved — pass the full target list. Each path
  /// must be absolute (the resolver rejects relative paths with a
  /// logged warning).
  Future<void> setUserPluginDirectories(List<String> directories) => _update(
    (s) => s.copyWith(
      userPluginDirectories: List<String>.unmodifiable(directories),
    ),
  );

  /// Appends [path] to the user plugin directory list. No-op when
  /// [path] is already present (case-insensitive on Windows/macOS).
  Future<void> addUserPluginDirectory(String path) {
    final current = state.value?.userPluginDirectories ?? const <String>[];
    if (current.contains(path)) return Future<void>.value();
    return setUserPluginDirectories(<String>[...current, path]);
  }

  /// Removes [path] from the user plugin directory list. No-op when
  /// [path] is not present.
  Future<void> removeUserPluginDirectory(String path) {
    final current = state.value?.userPluginDirectories ?? const <String>[];
    if (!current.contains(path)) return Future<void>.value();
    return setUserPluginDirectories(
      current.where((p) => p != path).toList(growable: false),
    );
  }

  /// Replaces the ISA table directory list. Each path must be absolute; the
  /// loader drops relative entries with a logged warning.
  ///
  /// Takes effect on the next launch, because instruction-set assets are
  /// composed once during `bootstrap()` — before the provider container
  /// exists — and every decoder instance holds the composed set. The Settings
  /// panel says so rather than leaving the user to wonder why their table has
  /// not appeared.
  Future<void> setIsaTableDirectories(List<String> directories) => _update(
    (s) => s.copyWith(
      isaTableDirectories: List<String>.unmodifiable(directories),
    ),
  );

  /// Appends [path] to the ISA table directory list. No-op when already
  /// present.
  Future<void> addIsaTableDirectory(String path) {
    final current = state.value?.isaTableDirectories ?? const <String>[];
    if (current.contains(path)) return Future<void>.value();
    return setIsaTableDirectories(<String>[...current, path]);
  }

  /// Removes [path] from the ISA table directory list. No-op when absent.
  Future<void> removeIsaTableDirectory(String path) {
    final current = state.value?.isaTableDirectories ?? const <String>[];
    if (!current.contains(path)) return Future<void>.value();
    return setIsaTableDirectories(
      current.where((p) => p != path).toList(growable: false),
    );
  }

  /// Sets the per-plugin disable flag for [pluginId]. The loader
  /// honors this on the next scan: disabled plugins are reported with
  /// status [DecoderPluginLoadStatus.disabled] but never have their
  /// register entry point invoked.
  Future<void> setPluginDisabled(
    String pluginId, {
    required bool disabled,
  }) {
    final current = state.value?.perPluginDisabled ?? const <String, bool>{};
    final next = Map<String, bool>.from(current);
    if (disabled) {
      next[pluginId] = true;
    } else {
      next.remove(pluginId);
    }
    return _update(
      (s) =>
          s.copyWith(perPluginDisabled: Map<String, bool>.unmodifiable(next)),
    );
  }

  /// Sets the active color theme by name (preset id or user theme filename
  /// without the `.wavecrux-theme.json` extension).
  Future<void> setActiveThemeName(String name) =>
      _update((s) => s.copyWith(activeThemeName: name));

  /// Replaces the flat token-path override map fed into the
  /// `cruxColorThemeProvider` bridge in
  /// `core/theme/wavecrux_color_theme_bootstrap.dart`. Pass an empty
  /// map to clear all overrides.
  Future<void> setThemeOverrides(Map<String, String> overrides) => _update(
    (s) => s.copyWith(
      themeOverrides: Map<String, String>.unmodifiable(overrides),
    ),
  );

  /// Whether to restore the previous session's open tabs on next launch.
  Future<void> setRestoreTabsOnLaunch({required bool enabled}) =>
      _update((s) => s.copyWith(restoreTabsOnLaunch: enabled));

  /// Whether to suppress the "Opened from legacy LXT/LXT2 format" banner that
  /// the convert-on-open path shows above the waveform area on the
  /// first open of a converted file. Set by the banner's "Don't show again"
  /// action and by the Settings → Advanced surface.
  Future<void> setSuppressLegacyFormatBanner({required bool suppressed}) =>
      _update((s) => s.copyWith(suppressLegacyFormatBanner: suppressed));

  /// Whether a collaborative session's annotations are adopted without asking
  ///. Set by the end-of-session prompt's "don't ask again".
  /// Deliberately one-directional — see
  /// [AppSettings.alwaysKeepSessionAnnotations].
  Future<void> setAlwaysKeepSessionAnnotations({required bool always}) =>
      _update((s) => s.copyWith(alwaysKeepSessionAnnotations: always));

  /// Whether the mouse scroll wheel pans time (GTKWave-style) instead of
  /// scrolling the signal list. See [AppSettings.wheelNavigatesTime].
  Future<void> setWheelNavigatesTime({required bool enabled}) =>
      _update((s) => s.copyWith(wheelNavigatesTime: enabled));

  /// Persists whether the signal hierarchy sorts alphanumerically.
  /// See [AppSettings.signalTreeNaturalSort].
  Future<void> setSignalTreeNaturalSort({required bool enabled}) =>
      _update((s) => s.copyWith(signalTreeNaturalSort: enabled));

  /// Persists whether an actionable inbound cross-probe requests the user's
  /// attention. See [AppSettings.requestAttentionOnCrossProbe].
  Future<void> setRequestAttentionOnCrossProbe({required bool enabled}) =>
      _update((s) => s.copyWith(requestAttentionOnCrossProbe: enabled));

  /// Persists whether WaveCrux auto-broadcasts the local selection to
  /// connected CXP peers as it changes.
  /// See [AppSettings.broadcastSelectionOnCrossProbe].
  Future<void> setBroadcastSelectionOnCrossProbe({required bool enabled}) =>
      _update((s) => s.copyWith(broadcastSelectionOnCrossProbe: enabled));

  /// How much detail the console sink prints and the Diagnostics → Logs panel
  /// shows by default. See [AppSettings.logVerbosity].
  Future<void> setLogVerbosity(LogVerbosity verbosity) =>
      _update((s) => s.copyWith(logVerbosity: verbosity));

  /// The user's opt-in to the Experimental AI Waveform Assistant. Combined
  /// with the `kAiExperimental` build flag in `aiExperimentalEnabledProvider`.
  /// See [AppSettings.aiExperimentalEnabled].
  Future<void> setAiExperimentalEnabled({required bool enabled}) =>
      _update((s) => s.copyWith(aiExperimentalEnabled: enabled));

  /// The selected bring-your-own-key AI provider. See [AppSettings.aiProvider].
  Future<void> setAiProvider(AiProvider provider) =>
      _update((s) => s.copyWith(aiProvider: provider));

  /// The optional override endpoint for the selected AI provider. See
  /// [AppSettings.aiEndpoint].
  Future<void> setAiEndpoint(String endpoint) =>
      _update((s) => s.copyWith(aiEndpoint: endpoint));

  /// Whether the app automatically checks for updates on launch and
  /// periodically. See [AppSettings.autoCheckForUpdates].
  Future<void> setAutoCheckForUpdates({required bool enabled}) =>
      _update((s) => s.copyWith(autoCheckForUpdates: enabled));

  Future<void> _update(AppSettings Function(AppSettings) mutate) async {
    final current = state.value ?? const AppSettings();
    final next = mutate(current);
    state = AsyncData(next);
    await ref.read(settingsServiceProvider).save(next);
  }
}

// ── Derived selectors ─────────────────────────────────────────────────────────

/// Whether the mouse scroll wheel pans the time axis instead of scrolling the
/// signal list. Defaults to `false` before settings have loaded.
///
/// Watched by `WaveformScrollModifierInterceptor` so a settings change reroutes
/// the wheel without rebuilding the whole settings object graph.
@riverpod
bool wheelNavigatesTime(Ref ref) =>
    ref.watch(appSettingsProvider).value?.wheelNavigatesTime ?? false;

/// Whether the signal hierarchy sorts in natural (alphanumeric) order.
/// Narrow derived view so the hierarchy rebuilds only when THIS bit flips,
/// not on every settings write. Defaults to sorted while settings load.
@riverpod
bool signalTreeNaturalSort(Ref ref) =>
    ref.watch(appSettingsProvider).value?.signalTreeNaturalSort ?? true;
