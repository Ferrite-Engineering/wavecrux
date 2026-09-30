// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/features/stage/sdk/manifest/localized_string.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_enums.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_parameter.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_signal_binding.dart';

/// Strongly-typed Dart parallel of a Stage Pro widget manifest YAML
/// document.
///
/// A manifest declares the identity, presentation metadata, signal
/// bindings, optional parameter normalizers, and runtime hookup for one
/// custom Stage widget. The bundle loader parses the manifest, resolves
/// each [ManifestParameter] into a [ValueNormalizer] instance, validates
/// referenced asset paths, and registers the result as a
/// `CustomStageWidgetDescriptor` in the open-core
/// `CustomStageWidgetRegistry`.
///
/// All fields are immutable. Construct via [StageWidgetManifest.fromYaml]
/// for parsing on-disk manifests, or via the constructor for synthetic /
/// programmatically generated manifests in tests.
@immutable
class StageWidgetManifest {
  const StageWidgetManifest({
    required this.id,
    required this.version,
    required this.displayName,
    required this.category,
    required this.runtime,
    required this.runtimeAssetPath,
    required this.requiredApiVersion,
    this.iconAssetPath,
    this.signalBindings = const [],
    this.parameters = const [],
  });

  /// Reverse-DNS identifier for the widget
  /// (e.g. `com.acme.stage.gauge_cluster`). Stable across versions.
  final String id;

  /// Semantic-version string for this widget release (e.g. `1.0.3`).
  final String version;

  /// Display name — single string or per-locale map.
  final LocalizedString displayName;

  /// Picker category. Reuses the open-core enum.
  final StageWidgetCategory category;

  /// Animation runtime to dispatch into.
  final ManifestRuntime runtime;

  /// Path (relative to the bundle root) of the runtime asset
  /// (e.g. `animations/gauge.riv`).
  final String runtimeAssetPath;

  /// SDK ABI version this manifest targets. The bundle loader rejects
  /// manifests whose major version exceeds the runtime's supported major.
  final int requiredApiVersion;

  /// Optional bundle-relative path to a 64×64 PNG/SVG icon.
  final String? iconAssetPath;

  /// Declared signal inputs. Order matches the manifest source.
  final List<ManifestSignalBinding> signalBindings;

  /// Optional per-binding normalizer pipelines.
  final List<ManifestParameter> parameters;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StageWidgetManifest) return false;
    return id == other.id &&
        version == other.version &&
        displayName == other.displayName &&
        category == other.category &&
        runtime == other.runtime &&
        runtimeAssetPath == other.runtimeAssetPath &&
        requiredApiVersion == other.requiredApiVersion &&
        iconAssetPath == other.iconAssetPath &&
        _listEquals(signalBindings, other.signalBindings) &&
        _listEquals(parameters, other.parameters);
  }

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    id,
    version,
    displayName,
    category,
    runtime,
    runtimeAssetPath,
    requiredApiVersion,
    iconAssetPath,
    Object.hashAll(signalBindings),
    Object.hashAll(parameters),
  );

  @override
  String toString() =>
      'StageWidgetManifest(id: $id, version: $version, '
      'category: $category, bindings: ${signalBindings.length}, '
      'parameters: ${parameters.length})';
}
