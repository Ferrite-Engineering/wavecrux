// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart' as crux;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/enums/ai_provider.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/log_verbosity.dart';
import 'package:wavecrux/domain/models/app_settings.dart';

/// Reads the configured ISA table directories before the settings provider
/// has hydrated.
///
/// Decoders are registered during `bootstrap()`, which runs ahead of the
/// provider container, so the ISA asset load cannot read `AppSettings` the
/// normal way. This is the same side-effect-free peek `peekPersistedWindow-
/// Bounds` performs against `workspace.json` for the same reason, and it reads
/// the identical SharedPreferences key the codec writes — there is one source
/// of truth, consulted twice.
///
/// Returns empty on any failure. A user whose tables cannot be located should
/// get the bundled corpus and a quiet log line, not a failed startup.
Future<List<String>> peekIsaTableDirectories() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(WaveCruxSettingsCodec.isaTableDirectoriesKey) ??
        const <String>[];
  } on Object {
    return const <String>[];
  }
}

/// `SettingsCodec` for WaveCrux's [AppSettings].
///
/// Delegates the cross-suite portion to [crux.CoreSettingsCodec] and adds
/// load/save for the wavecrux-specific fields (`waveformFontSize`,
/// `defaultDisplayFormat`, `defaultLaneHeight`, `autoConvertLargeVcd`,
/// `remoteControlEnabled`, `remoteControlPort`, `cxpServerEnabled`,
/// `cxpServerPort`, `cxpEditorCommand`). Uses the same `settings.*`
/// SharedPreferences key namespace WaveCrux has shipped with since v0, so
/// existing user preferences survive the migration to the cross-suite
/// settings shape.
class WaveCruxSettingsCodec implements crux.SettingsCodec<AppSettings> {
  /// Const constructor — codec is stateless.
  const WaveCruxSettingsCodec();

  static const _kFontSize = 'settings.waveformFontSize';
  static const _kDefaultFormat = 'settings.defaultDisplayFormat';
  static const _kDefaultLaneHeight = 'settings.defaultLaneHeight';
  static const _kAutoConvertVcd = 'settings.autoConvertLargeVcd';
  static const _kRemoteControlEnabled = 'settings.remoteControlEnabled';
  static const _kRemoteControlPort = 'settings.remoteControlPort';
  static const _kCxpServerEnabled = 'settings.cxpServerEnabled';
  static const _kCxpServerPort = 'settings.cxpServerPort';
  static const _kCxpEditorCommand = 'settings.cxpEditorCommand';
  static const _kRequestAttentionOnCrossProbe =
      'settings.requestAttentionOnCrossProbe';
  static const _kBroadcastSelectionOnCrossProbe =
      'settings.broadcastSelectionOnCrossProbe';
  static const _kSuppressLegacyFormatBanner =
      'settings.suppressLegacyFormatBanner';
  static const _kAlwaysKeepSessionAnnotations =
      'settings.alwaysKeepSessionAnnotations';
  static const _kWheelNavigatesTime = 'settings.wheelNavigatesTime';
  static const _kSignalTreeNaturalSort = 'settings.signalTreeNaturalSort';
  static const _kLogVerbosity = 'settings.logVerbosity';
  static const _kAiExperimentalEnabled = 'settings.aiExperimentalEnabled';
  static const _kAiProvider = 'settings.aiProvider';
  static const _kAiEndpoint = 'settings.aiEndpoint';
  static const _kAutoCheckForUpdates = 'settings.autoCheckForUpdates';
  static const _kCanvasLegibilityBoost = 'settings.canvasLegibilityBoost';

  /// Public because [peekIsaTableDirectories] reads it before the provider
  /// container exists. Kept as the single definition so the pre-hydration read
  /// and the codec cannot drift onto different keys.
  static const isaTableDirectoriesKey = 'settings.isaTableDirectories';

  static const _coreCodec = crux.CoreSettingsCodec();

  @override
  Future<AppSettings> load(SharedPreferences prefs) async {
    final core = await _coreCodec.load(prefs);
    return AppSettings(
      core: core,
      waveformFontSize: (prefs.getDouble(_kFontSize) ?? 12.0).clamp(8.0, 24.0),
      defaultDisplayFormat: _enumOf(
        DisplayFormat.values,
        prefs.getInt(_kDefaultFormat),
        DisplayFormat.hexadecimal,
      ),
      defaultLaneHeight: (prefs.getInt(_kDefaultLaneHeight) ?? 30).clamp(
        16,
        200,
      ),
      autoConvertLargeVcd: prefs.getBool(_kAutoConvertVcd) ?? true,
      remoteControlEnabled: prefs.getBool(_kRemoteControlEnabled) ?? false,
      remoteControlPort: (prefs.getInt(_kRemoteControlPort) ?? 54321).clamp(
        1,
        65535,
      ),
      cxpServerEnabled: prefs.getBool(_kCxpServerEnabled) ?? true,
      cxpServerPort: (prefs.getInt(_kCxpServerPort) ?? 54322).clamp(1, 65535),
      cxpEditorCommand: prefs.getString(_kCxpEditorCommand) ?? '',
      requestAttentionOnCrossProbe:
          prefs.getBool(_kRequestAttentionOnCrossProbe) ?? true,
      broadcastSelectionOnCrossProbe:
          prefs.getBool(_kBroadcastSelectionOnCrossProbe) ?? true,
      suppressLegacyFormatBanner:
          prefs.getBool(_kSuppressLegacyFormatBanner) ?? false,
      alwaysKeepSessionAnnotations:
          prefs.getBool(_kAlwaysKeepSessionAnnotations) ?? false,
      wheelNavigatesTime: prefs.getBool(_kWheelNavigatesTime) ?? false,
      signalTreeNaturalSort: prefs.getBool(_kSignalTreeNaturalSort) ?? true,
      logVerbosity: _enumOf(
        LogVerbosity.values,
        prefs.getInt(_kLogVerbosity),
        LogVerbosity.normal,
      ),
      aiExperimentalEnabled: prefs.getBool(_kAiExperimentalEnabled) ?? false,
      aiProvider: _enumOf(
        AiProvider.values,
        prefs.getInt(_kAiProvider),
        AiProvider.anthropic,
      ),
      aiEndpoint: prefs.getString(_kAiEndpoint) ?? '',
      autoCheckForUpdates: prefs.getBool(_kAutoCheckForUpdates) ?? true,
      canvasLegibilityBoost: prefs.getBool(_kCanvasLegibilityBoost) ?? false,
      isaTableDirectories:
          prefs.getStringList(isaTableDirectoriesKey) ?? const <String>[],
    );
  }

  @override
  Future<void> save(SharedPreferences prefs, AppSettings settings) async {
    await _coreCodec.save(prefs, settings.core);
    await Future.wait([
      prefs.setDouble(_kFontSize, settings.waveformFontSize),
      prefs.setInt(_kDefaultFormat, settings.defaultDisplayFormat.index),
      prefs.setInt(_kDefaultLaneHeight, settings.defaultLaneHeight),
      prefs.setBool(_kAutoConvertVcd, settings.autoConvertLargeVcd),
      prefs.setBool(_kRemoteControlEnabled, settings.remoteControlEnabled),
      prefs.setInt(_kRemoteControlPort, settings.remoteControlPort),
      prefs.setBool(_kCxpServerEnabled, settings.cxpServerEnabled),
      prefs.setInt(_kCxpServerPort, settings.cxpServerPort),
      prefs.setString(_kCxpEditorCommand, settings.cxpEditorCommand),
      prefs.setBool(
        _kRequestAttentionOnCrossProbe,
        settings.requestAttentionOnCrossProbe,
      ),
      prefs.setBool(
        _kBroadcastSelectionOnCrossProbe,
        settings.broadcastSelectionOnCrossProbe,
      ),
      prefs.setBool(
        _kSuppressLegacyFormatBanner,
        settings.suppressLegacyFormatBanner,
      ),
      prefs.setBool(
        _kAlwaysKeepSessionAnnotations,
        settings.alwaysKeepSessionAnnotations,
      ),
      prefs.setBool(_kWheelNavigatesTime, settings.wheelNavigatesTime),
      prefs.setBool(_kSignalTreeNaturalSort, settings.signalTreeNaturalSort),
      prefs.setInt(_kLogVerbosity, settings.logVerbosity.index),
      prefs.setBool(_kAiExperimentalEnabled, settings.aiExperimentalEnabled),
      prefs.setInt(_kAiProvider, settings.aiProvider.index),
      prefs.setString(_kAiEndpoint, settings.aiEndpoint),
      prefs.setBool(_kAutoCheckForUpdates, settings.autoCheckForUpdates),
      prefs.setBool(_kCanvasLegibilityBoost, settings.canvasLegibilityBoost),
      prefs.setStringList(isaTableDirectoriesKey, settings.isaTableDirectories),
    ]);
  }

  /// Returns `values[index]` when [index] is valid; otherwise [fallback].
  T _enumOf<T>(List<T> values, int? index, T fallback) {
    if (index == null || index < 0 || index >= values.length) return fallback;
    return values[index];
  }
}

/// Persists and loads [AppSettings] using `SharedPreferences`.
///
/// Backward-compatibility wrapper: existing wavecrux consumers depend on a
/// `SettingsService` class with `load()` / `save(AppSettings)` methods.
/// The class now delegates to the cross-suite generic
/// `crux.SettingsService<AppSettings>` configured with
/// [WaveCruxSettingsCodec]. Unknown or out-of-range persisted values fall
/// back to defaults so forward-compatible changes never crash.
class WaveCruxSettingsService {
  /// Creates a service backed by [WaveCruxSettingsCodec].
  const WaveCruxSettingsService();

  static const _delegate = crux.SettingsService<AppSettings>(
    WaveCruxSettingsCodec(),
  );

  /// Loads persisted settings. Missing keys return [AppSettings] defaults.
  Future<AppSettings> load() => _delegate.load();

  /// Persists all fields of [settings].
  Future<void> save(AppSettings settings) => _delegate.save(settings);
}
