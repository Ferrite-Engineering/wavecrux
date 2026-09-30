// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/ai_provider.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/log_verbosity.dart';

/// Persistent application preferences.
///
/// Immutable value object — update via [copyWith]. Persisted and loaded by
/// `SettingsService` using [shared_preferences].
///
/// Composes a [CoreSettings] (cross-suite shared subset — 14 fields) plus
/// the wavecrux-specific fields (6 fields). Consumers can read either via
/// the flat forwarder getters (`settings.themeMode`) or via the explicit
/// `settings.core.themeMode` traversal. Both work; flat is preferred for
/// brevity.
///
/// All defaults are chosen to give a good out-of-the-box experience for
/// hardware engineers: dark theme, hex display, reasonable lane height.
@immutable
class AppSettings {
  /// Creates an [AppSettings]. Every parameter has a documented default so
  /// `const AppSettings()` returns the WaveCrux baseline. To override
  /// [CoreSettings] fields (theme mode, locale, plugin dirs, …), either
  /// pass an explicit [core] sub-object or use
  /// `const AppSettings().copyWith(themeMode: ..., locale: ...)`. The
  /// wavecrux-specific fields are direct constructor parameters because
  /// they don't have a cross-suite home.
  const AppSettings({
    this.core = const CoreSettings.defaults(),
    this.waveformFontSize = 12.0,
    this.defaultDisplayFormat = DisplayFormat.hexadecimal,
    this.defaultLaneHeight = 30,
    this.autoConvertLargeVcd = true,
    this.remoteControlEnabled = false,
    this.remoteControlPort = 54321,
    this.cxpServerEnabled = true,
    this.cxpServerPort = 54322,
    this.cxpEditorCommand = '',
    this.requestAttentionOnCrossProbe = true,
    this.broadcastSelectionOnCrossProbe = true,
    this.suppressLegacyFormatBanner = false,
    this.alwaysKeepSessionAnnotations = false,
    this.wheelNavigatesTime = false,
    this.signalTreeNaturalSort = true,
    this.logVerbosity = LogVerbosity.normal,
    this.aiExperimentalEnabled = false,
    this.aiProvider = AiProvider.anthropic,
    this.aiEndpoint = '',
    this.autoCheckForUpdates = true,
    this.canvasLegibilityBoost = false,
    this.isaTableDirectories = const <String>[],
  });

  /// The cross-suite shared subset of settings (theme, locale, diagnostics
  /// flag, plugin directories, theme overrides, restore-tabs-on-launch,
  /// …). Stored as a sub-object so wavecrux and the rest of the suite can
  /// share the model.
  final CoreSettings core;

  // ─── wavecrux-specific fields ────────────────────────────────────────────

  /// Font size in logical pixels for signal values and names in the waveform.
  final double waveformFontSize;

  /// Display format applied to newly added signals.
  final DisplayFormat defaultDisplayFormat;

  /// Default lane height in pixels for newly added signal rows.
  final int defaultLaneHeight;

  /// A stored preference for converting large VCD files to FST on first open.
  ///
  /// Kept so existing settings still load and save unchanged, but no feature
  /// reads it and Settings no longer offers it: there is no automatic
  /// conversion to switch.
  final bool autoConvertLargeVcd;

  /// Whether the WCP (Waveform Control Protocol) remote control server is
  /// enabled.
  final bool remoteControlEnabled;

  /// TCP port for the WCP remote control server. Defaults to 54321, the WCP
  /// spec default.
  final int remoteControlPort;

  /// Whether the Cross-Tool eXchange Protocol (CXP) peer cross-probe server is
  /// enabled. CXP is distinct from WCP: WCP is the external driver protocol
  /// (imperative, viewer-bound); CXP is the peer cross-probe protocol that
  /// gossips selection events between Crux apps. The two coexist on
  /// distinct ports.
  final bool cxpServerEnabled;

  /// TCP port for the CXP peer cross-probe server. Defaults to 54322 to
  /// stay clear of WCP's default port (54321).
  final int cxpServerPort;

  /// External editor command used to fulfil inbound CXP `request_open_source`
  /// requests (e.g. `code -g`, `subl`, `nvr`, `emacsclient`). The recipient
  /// shells out to this command with `{path}:{line}[:{column}]` appended.
  /// Empty disables the open-source path; the handler replies with
  /// `honored: false`.
  final String cxpEditorCommand;

  /// Whether an actionable inbound cross-probe (a highlight applied, or a
  /// waveform opened via the shared workspace) requests the user's attention —
  /// a dock bounce on macOS, taskbar flash on Windows, urgency hint on Linux
  /// — never stealing focus. Default on; when off the app installs the
  /// no-op attention backend so nothing is nudged.
  final bool requestAttentionOnCrossProbe;

  /// Whether WaveCrux auto-broadcasts the local selection (signal, cursor,
  /// marker) to connected CXP peers as it changes — the live cross-probe.
  /// Default on. When off, the [CxpSelectionEmitter] is silenced and only
  /// explicit per-peer sends from the cross-probe panel share a selection.
  final bool broadcastSelectionOnCrossProbe;

  /// When `true`, the "Opened from legacy LXT/LXT2 format" banner that
  /// appears above the waveform area on the first open of a converted file
  /// is suppressed. Toggled by the banner's "Don't show again" action and
  /// by the Settings → Advanced surface.
  final bool suppressLegacyFormatBanner;

  /// When `true`, annotations made in a collaborative session are adopted
  /// without asking — the "don't ask again" branch of the
  /// end-of-session prompt.
  ///
  /// It can only mean *keep*, never *discard*. A preference that silently threw
  /// away a meeting's output because somebody ticked a box once, weeks ago, is
  /// not a preference anybody consented to.
  final bool alwaysKeepSessionAnnotations;

  /// When `true`, the mouse scroll wheel pans the time axis (GTKWave-style) and
  /// Shift+wheel scrolls the signal list; when `false` (default) plain wheel
  /// scrolls the signal list and Shift+wheel pans time. Ctrl/Cmd+wheel always
  /// zooms regardless. Applies to the mouse wheel only — trackpad pinch/pan
  /// gestures are unaffected.
  final bool wheelNavigatesTime;

  /// Whether the signal hierarchy tree sorts scopes and variables in
  /// natural (alphanumeric) order — digit runs compare numerically, so
  /// `x[2]` lists before `x[11]`. When off, the dump's declaration order
  /// is preserved. Default on.
  final bool signalTreeNaturalSort;

  /// How much detail the console sink prints and the Diagnostics → Logs panel
  /// shows by default. Does not affect what the issue-reporter ring buffer
  /// captures (always every level). See [LogVerbosity].
  final LogVerbosity logVerbosity;

  /// The user's persisted opt-in to the **Experimental** AI Waveform Assistant
  /// ("Enable experimental AI features"). Off by default. Combined with the
  /// `kAiExperimental` build flag in `aiExperimentalEnabledProvider`; AI
  /// surfaces appear only when both are on. The API key is **never** stored
  /// here — it lives in platform secure storage via `AiKeyStore`.
  final bool aiExperimentalEnabled;

  /// The selected bring-your-own-key AI provider for the assistant. Non-secret
  /// configuration; the key itself is in secure storage.
  final AiProvider aiProvider;

  /// Optional override endpoint for the selected [aiProvider] (e.g. a local
  /// Ollama URL or an Azure-OpenAI-compatible gateway). Empty means the client
  /// uses the provider's implied default. Non-secret.
  final String aiEndpoint;

  /// Whether the app checks the version manifest for updates on launch and
  /// periodically. Default on. Governs only the automatic checks; the
  /// manual "Check for Updates" action always runs regardless. The single
  /// transmitted signal is app version + OS — see `crux_updates`'
  /// `HttpUpdateCheckService`.
  final bool autoCheckForUpdates;

  /// When `true`, the waveform canvas thickens every trace / lane-divider
  /// stroke (≈1.6×) and raises a 14 px floor on the in-canvas value/label
  /// font, so signals stay legible at the low angular resolution of XR/AR
  /// glasses and other large, far-viewed displays. Off by default; pairs
  /// naturally with the `oled-xr` theme preset but is independent of it.
  final bool canvasLegibilityBoost;

  /// Directories scanned for user-authored ISA encoding tables (`*.toml`).
  ///
  /// Absolute paths only; relative entries are ignored with a logged warning
  /// rather than resolved against the working directory. Desktop only — a web
  /// build has no filesystem to scan and leaves this empty.
  ///
  /// Deliberately WaveCrux-local rather than a `CoreSettings` field: no other
  /// product in the suite decodes instruction streams, and
  /// `userPluginDirectories` is shared only because every product can load a
  /// decoder plugin.
  final List<String> isaTableDirectories;

  // ─── Forwarder getters into [core] ───────────────────────────────────────
  // Preserve the historical flat API so existing read sites keep working.
  // Equivalent to writing `settings.core.themeMode` everywhere; consumer
  // code uses whichever feels more natural.

  /// Forwarder for [CoreSettings.themeMode].
  AppThemeMode get themeMode => core.themeMode;

  /// Forwarder for [CoreSettings.autoReloadMode].
  AutoReloadMode get autoReloadMode => core.autoReloadMode;

  /// Forwarder for [CoreSettings.autoSaveIntervalSeconds].
  int get autoSaveIntervalSeconds => core.autoSaveIntervalSeconds;

  /// Forwarder for [CoreSettings.locale].
  String get locale => core.locale;

  /// Forwarder for [CoreSettings.diagnosticsEnabled].
  bool get diagnosticsEnabled => core.diagnosticsEnabled;

  /// Forwarder for [CoreSettings.orientationLockMode].
  OrientationLockMode get orientationLockMode => core.orientationLockMode;

  /// Forwarder for [CoreSettings.autoHideChromeSeconds].
  int get autoHideChromeSeconds => core.autoHideChromeSeconds;

  /// Forwarder for [CoreSettings.userPluginDirectories].
  List<String> get userPluginDirectories => core.userPluginDirectories;

  /// Forwarder for [CoreSettings.pluginSafetyAcknowledged].
  bool get pluginSafetyAcknowledged => core.pluginSafetyAcknowledged;

  /// Forwarder for [CoreSettings.pluginLoadingDisabled].
  bool get pluginLoadingDisabled => core.pluginLoadingDisabled;

  /// Forwarder for [CoreSettings.perPluginDisabled].
  Map<String, bool> get perPluginDisabled => core.perPluginDisabled;

  /// Forwarder for [CoreSettings.activeThemeName].
  String get activeThemeName => core.activeThemeName;

  /// Forwarder for [CoreSettings.themeOverrides].
  Map<String, String> get themeOverrides => core.themeOverrides;

  /// Forwarder for [CoreSettings.restoreTabsOnLaunch].
  bool get restoreTabsOnLaunch => core.restoreTabsOnLaunch;

  /// Returns a copy with overridden fields.
  ///
  /// Accepts both the wavecrux-specific fields and the flat `CoreSettings`
  /// forwarders, so call sites can write
  /// `settings.copyWith(themeMode: AppThemeMode.light)` unchanged. Pass
  /// [core] directly to swap the entire sub-object at once.
  AppSettings copyWith({
    CoreSettings? core,
    // Flat core forwarders:
    AppThemeMode? themeMode,
    AutoReloadMode? autoReloadMode,
    int? autoSaveIntervalSeconds,
    String? locale,
    bool? diagnosticsEnabled,
    OrientationLockMode? orientationLockMode,
    int? autoHideChromeSeconds,
    List<String>? userPluginDirectories,
    bool? pluginSafetyAcknowledged,
    bool? pluginLoadingDisabled,
    Map<String, bool>? perPluginDisabled,
    String? activeThemeName,
    Map<String, String>? themeOverrides,
    bool? restoreTabsOnLaunch,
    // Wavecrux-specific:
    double? waveformFontSize,
    DisplayFormat? defaultDisplayFormat,
    int? defaultLaneHeight,
    bool? autoConvertLargeVcd,
    bool? remoteControlEnabled,
    int? remoteControlPort,
    bool? cxpServerEnabled,
    int? cxpServerPort,
    String? cxpEditorCommand,
    bool? requestAttentionOnCrossProbe,
    bool? broadcastSelectionOnCrossProbe,
    bool? suppressLegacyFormatBanner,
    bool? alwaysKeepSessionAnnotations,
    bool? wheelNavigatesTime,
    bool? signalTreeNaturalSort,
    LogVerbosity? logVerbosity,
    bool? aiExperimentalEnabled,
    AiProvider? aiProvider,
    String? aiEndpoint,
    bool? autoCheckForUpdates,
    bool? canvasLegibilityBoost,
    List<String>? isaTableDirectories,
  }) {
    final newCore =
        core ??
        this.core.copyWith(
          themeMode: themeMode,
          autoReloadMode: autoReloadMode,
          autoSaveIntervalSeconds: autoSaveIntervalSeconds,
          locale: locale,
          diagnosticsEnabled: diagnosticsEnabled,
          orientationLockMode: orientationLockMode,
          autoHideChromeSeconds: autoHideChromeSeconds,
          userPluginDirectories: userPluginDirectories,
          pluginSafetyAcknowledged: pluginSafetyAcknowledged,
          pluginLoadingDisabled: pluginLoadingDisabled,
          perPluginDisabled: perPluginDisabled,
          activeThemeName: activeThemeName,
          themeOverrides: themeOverrides,
          restoreTabsOnLaunch: restoreTabsOnLaunch,
        );
    return AppSettings(
      core: newCore,
      waveformFontSize: waveformFontSize ?? this.waveformFontSize,
      defaultDisplayFormat: defaultDisplayFormat ?? this.defaultDisplayFormat,
      defaultLaneHeight: defaultLaneHeight ?? this.defaultLaneHeight,
      autoConvertLargeVcd: autoConvertLargeVcd ?? this.autoConvertLargeVcd,
      remoteControlEnabled: remoteControlEnabled ?? this.remoteControlEnabled,
      remoteControlPort: remoteControlPort ?? this.remoteControlPort,
      cxpServerEnabled: cxpServerEnabled ?? this.cxpServerEnabled,
      cxpServerPort: cxpServerPort ?? this.cxpServerPort,
      cxpEditorCommand: cxpEditorCommand ?? this.cxpEditorCommand,
      requestAttentionOnCrossProbe:
          requestAttentionOnCrossProbe ?? this.requestAttentionOnCrossProbe,
      broadcastSelectionOnCrossProbe:
          broadcastSelectionOnCrossProbe ?? this.broadcastSelectionOnCrossProbe,
      suppressLegacyFormatBanner:
          suppressLegacyFormatBanner ?? this.suppressLegacyFormatBanner,
      alwaysKeepSessionAnnotations:
          alwaysKeepSessionAnnotations ?? this.alwaysKeepSessionAnnotations,
      wheelNavigatesTime: wheelNavigatesTime ?? this.wheelNavigatesTime,
      signalTreeNaturalSort:
          signalTreeNaturalSort ?? this.signalTreeNaturalSort,
      logVerbosity: logVerbosity ?? this.logVerbosity,
      aiExperimentalEnabled:
          aiExperimentalEnabled ?? this.aiExperimentalEnabled,
      aiProvider: aiProvider ?? this.aiProvider,
      aiEndpoint: aiEndpoint ?? this.aiEndpoint,
      autoCheckForUpdates: autoCheckForUpdates ?? this.autoCheckForUpdates,
      canvasLegibilityBoost:
          canvasLegibilityBoost ?? this.canvasLegibilityBoost,
      isaTableDirectories: isaTableDirectories ?? this.isaTableDirectories,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AppSettings) return false;
    if (other.core != core) return false;
    if (other.waveformFontSize != waveformFontSize) return false;
    if (other.defaultDisplayFormat != defaultDisplayFormat) return false;
    if (other.defaultLaneHeight != defaultLaneHeight) return false;
    if (other.autoConvertLargeVcd != autoConvertLargeVcd) return false;
    if (other.remoteControlEnabled != remoteControlEnabled) return false;
    if (other.remoteControlPort != remoteControlPort) return false;
    if (other.cxpServerEnabled != cxpServerEnabled) return false;
    if (other.cxpServerPort != cxpServerPort) return false;
    if (other.cxpEditorCommand != cxpEditorCommand) return false;
    if (other.requestAttentionOnCrossProbe != requestAttentionOnCrossProbe) {
      return false;
    }
    if (other.broadcastSelectionOnCrossProbe !=
        broadcastSelectionOnCrossProbe) {
      return false;
    }
    if (other.alwaysKeepSessionAnnotations != alwaysKeepSessionAnnotations) {
      return false;
    }
    if (other.suppressLegacyFormatBanner != suppressLegacyFormatBanner) {
      return false;
    }
    if (other.wheelNavigatesTime != wheelNavigatesTime) return false;
    if (other.signalTreeNaturalSort != signalTreeNaturalSort) return false;
    if (other.logVerbosity != logVerbosity) return false;
    if (other.aiExperimentalEnabled != aiExperimentalEnabled) return false;
    if (other.aiProvider != aiProvider) return false;
    if (other.aiEndpoint != aiEndpoint) return false;
    if (other.autoCheckForUpdates != autoCheckForUpdates) return false;
    if (other.canvasLegibilityBoost != canvasLegibilityBoost) return false;
    if (!_listEquals(other.isaTableDirectories, isaTableDirectories)) {
      return false;
    }
    return true;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll([
    core,
    waveformFontSize,
    defaultDisplayFormat,
    defaultLaneHeight,
    autoConvertLargeVcd,
    remoteControlEnabled,
    remoteControlPort,
    cxpServerEnabled,
    cxpServerPort,
    cxpEditorCommand,
    requestAttentionOnCrossProbe,
    broadcastSelectionOnCrossProbe,
    suppressLegacyFormatBanner,
    alwaysKeepSessionAnnotations,
    wheelNavigatesTime,
    signalTreeNaturalSort,
    logVerbosity,
    aiExperimentalEnabled,
    aiProvider,
    aiEndpoint,
    autoCheckForUpdates,
    canvasLegibilityBoost,
    Object.hashAll(isaTableDirectories),
  ]);

  @override
  String toString() =>
      'AppSettings('
      // Core (cross-suite) fields, forwarded for diagnostic completeness:
      'themeMode: $themeMode, '
      'autoReloadMode: $autoReloadMode, '
      'autoSaveIntervalSeconds: $autoSaveIntervalSeconds, '
      'locale: $locale, '
      'diagnosticsEnabled: $diagnosticsEnabled, '
      'orientationLockMode: $orientationLockMode, '
      'autoHideChromeSeconds: $autoHideChromeSeconds, '
      'userPluginDirectories: $userPluginDirectories, '
      'pluginSafetyAcknowledged: $pluginSafetyAcknowledged, '
      'pluginLoadingDisabled: $pluginLoadingDisabled, '
      'perPluginDisabled: $perPluginDisabled, '
      'activeThemeName: $activeThemeName, '
      'themeOverrides: $themeOverrides, '
      'restoreTabsOnLaunch: $restoreTabsOnLaunch, '
      // Wavecrux-specific fields:
      'waveformFontSize: $waveformFontSize, '
      'defaultDisplayFormat: $defaultDisplayFormat, '
      'defaultLaneHeight: $defaultLaneHeight, '
      'autoConvertLargeVcd: $autoConvertLargeVcd, '
      'remoteControlEnabled: $remoteControlEnabled, '
      'remoteControlPort: $remoteControlPort, '
      'cxpServerEnabled: $cxpServerEnabled, '
      'cxpServerPort: $cxpServerPort, '
      'cxpEditorCommand: $cxpEditorCommand, '
      'requestAttentionOnCrossProbe: $requestAttentionOnCrossProbe, '
      'broadcastSelectionOnCrossProbe: $broadcastSelectionOnCrossProbe, '
      'suppressLegacyFormatBanner: $suppressLegacyFormatBanner, '
      'alwaysKeepSessionAnnotations: $alwaysKeepSessionAnnotations, '
      'wheelNavigatesTime: $wheelNavigatesTime, '
      'signalTreeNaturalSort: $signalTreeNaturalSort, '
      'logVerbosity: $logVerbosity, '
      'aiExperimentalEnabled: $aiExperimentalEnabled, '
      'aiProvider: $aiProvider, '
      'aiEndpoint: $aiEndpoint, '
      'autoCheckForUpdates: $autoCheckForUpdates'
      ')';
}
