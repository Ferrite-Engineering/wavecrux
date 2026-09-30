// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_load_status.dart';

/// One discovered decoder plugin and its current load state.
///
/// Produced by the FFI plugin loader after walking the configured plugin
/// directories. Consumed by the Settings → Decoders → Plugins panel and
/// by tests.
///
/// Pure data: no Flutter imports, no FFI imports. Equality is by-value so
/// the Settings panel can rebuild only when the user-visible state for a
/// given plugin actually changes.
@immutable
class DecoderPluginInfo {
  const DecoderPluginInfo({
    required this.pluginId,
    required this.displayName,
    required this.filePath,
    required this.declaredAbiVersion,
    required this.loadStatus,
    this.errorMessage,
    this.registeredDecoderIds = const <String>[],
    this.pluginDescription,
  });

  /// Stable identifier for this plugin file. The loader derives it from
  /// the absolute file path so the user can disable a specific plugin
  /// across restarts even before any decoder names are known.
  final String pluginId;

  /// Human-readable display name. For successfully loaded plugins this
  /// is the plugin's first decoder's `display_name`; for failed plugins
  /// the loader falls back to the file's basename so the row in
  /// Settings remains identifiable.
  final String displayName;

  /// Absolute filesystem path to the discovered shared library. Shown
  /// in the Settings panel under the display name.
  final String filePath;

  /// The ABI version word the plugin reported via
  /// `wavecrux_decoder_abi_version()`. Encoded as
  /// `(major << 16) | minor`. Zero when the plugin failed to load
  /// before the version could be queried.
  final int declaredAbiVersion;

  /// Outcome of the most recent load attempt.
  final DecoderPluginLoadStatus loadStatus;

  /// Free-form diagnostic text. Populated for every status except
  /// [DecoderPluginLoadStatus.loaded] (and may also be populated on
  /// loaded plugins to surface non-fatal warnings).
  final String? errorMessage;

  /// Decoder ids the plugin contributed to the registry. Empty for
  /// plugins that did not load.
  final List<String> registeredDecoderIds;

  /// Optional one-line description the plugin reported about itself via
  /// the ABI 1.1 `wavecrux_decoder_plugin_description` entry point (e.g.
  /// an origin or license notice). Null when the plugin did not export
  /// the symbol or returned NULL.
  final String? pluginDescription;

  /// Major component of [declaredAbiVersion].
  int get declaredAbiMajor => (declaredAbiVersion >> 16) & 0xFFFF;

  /// Minor component of [declaredAbiVersion].
  int get declaredAbiMinor => declaredAbiVersion & 0xFFFF;

  DecoderPluginInfo copyWith({
    String? pluginId,
    String? displayName,
    String? filePath,
    int? declaredAbiVersion,
    DecoderPluginLoadStatus? loadStatus,
    String? errorMessage,
    bool clearErrorMessage = false,
    List<String>? registeredDecoderIds,
    String? pluginDescription,
    bool clearPluginDescription = false,
  }) {
    return DecoderPluginInfo(
      pluginId: pluginId ?? this.pluginId,
      displayName: displayName ?? this.displayName,
      filePath: filePath ?? this.filePath,
      declaredAbiVersion: declaredAbiVersion ?? this.declaredAbiVersion,
      loadStatus: loadStatus ?? this.loadStatus,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      registeredDecoderIds: registeredDecoderIds ?? this.registeredDecoderIds,
      pluginDescription: clearPluginDescription
          ? null
          : (pluginDescription ?? this.pluginDescription),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DecoderPluginInfo) return false;
    if (other.pluginId != pluginId) return false;
    if (other.displayName != displayName) return false;
    if (other.filePath != filePath) return false;
    if (other.declaredAbiVersion != declaredAbiVersion) return false;
    if (other.loadStatus != loadStatus) return false;
    if (other.errorMessage != errorMessage) return false;
    if (other.pluginDescription != pluginDescription) return false;
    if (other.registeredDecoderIds.length != registeredDecoderIds.length) {
      return false;
    }
    for (var i = 0; i < registeredDecoderIds.length; i++) {
      if (other.registeredDecoderIds[i] != registeredDecoderIds[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    pluginId,
    displayName,
    filePath,
    declaredAbiVersion,
    loadStatus,
    errorMessage,
    Object.hashAll(registeredDecoderIds),
    pluginDescription,
  );

  @override
  String toString() =>
      'DecoderPluginInfo('
      'pluginId: $pluginId, '
      'displayName: $displayName, '
      'filePath: $filePath, '
      'declaredAbiVersion: 0x${declaredAbiVersion.toRadixString(16)}, '
      'loadStatus: $loadStatus, '
      'errorMessage: $errorMessage, '
      'registeredDecoderIds: $registeredDecoderIds, '
      'pluginDescription: $pluginDescription'
      ')';
}
