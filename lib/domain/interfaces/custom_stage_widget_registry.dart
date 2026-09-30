// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';

/// One descriptor contributed by a Stage Pro custom-widget bundle (or
/// equivalent runtime source).
///
/// A descriptor pairs a [StageWidget] definition with the metadata needed to
/// gate, identify, and version it independently of the built-in registry.
/// Built-in primitive and board widgets register directly into the global
/// `StageRegistry` and do not flow through this descriptor — `requiredTier`
/// for those defaults to [LicenseTier.openCore].
///
/// `CustomWidgetBundleManager` constructs one of these for each `.wcrux-widget`
/// bundle it loads and registers it into the [CustomStageWidgetRegistry]. The
/// picker UI surfaces them
/// alongside built-ins with a `FeatureTierBadge` matching [requiredTier] and routes
/// activation through `FeatureGate.isAvailable`.
///
/// Pure Dart — no Flutter imports. Immutable.
@immutable
class CustomStageWidgetDescriptor {
  /// Creates a descriptor pairing [widget] with its tier and optional bundle
  /// provenance metadata.
  ///
  /// [requiredTier] defaults to [LicenseTier.pro]. The bundle manager passes
  /// its own tier explicitly — open core unless its owner says otherwise — so
  /// an installed community bundle is free to use.
  /// Built-in widgets use the [StageWidget] interface directly via
  /// `StageRegistry` and do not construct descriptors at all.
  const CustomStageWidgetDescriptor({
    required this.widget,
    this.requiredTier = LicenseTier.pro,
    this.bundleId,
    this.bundleVersion,
  });

  /// The Stage widget definition contributed by this descriptor.
  final StageWidget widget;

  /// Minimum product tier required to activate this widget.
  ///
  /// Defaults to [LicenseTier.pro]. The picker dialog reads this to render a
  /// `FeatureTierBadge` and to gate activation through `FeatureGate.isAvailable`.
  /// Setting [LicenseTier.openCore] is allowed but defeats the whole reason
  /// for using a descriptor — built-in widgets should register directly into
  /// `StageRegistry` instead.
  final LicenseTier requiredTier;

  /// Optional identifier of the bundle that contributed this widget. The SDK
  /// sets this from the bundle manifest so the picker UI can group widgets
  /// by source and present uninstall actions.
  final String? bundleId;

  /// Optional bundle version string (semver, etc.) for surfacing in the
  /// picker UI.
  final String? bundleVersion;

  /// Convenience accessor that returns the underlying widget id used by the
  /// registry and persisted in `.wavecrux` session files.
  String get id => widget.id;

  CustomStageWidgetDescriptor copyWith({
    StageWidget? widget,
    LicenseTier? requiredTier,
    String? bundleId,
    String? bundleVersion,
  }) => CustomStageWidgetDescriptor(
    widget: widget ?? this.widget,
    requiredTier: requiredTier ?? this.requiredTier,
    bundleId: bundleId ?? this.bundleId,
    bundleVersion: bundleVersion ?? this.bundleVersion,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CustomStageWidgetDescriptor) return false;
    return widget == other.widget &&
        requiredTier == other.requiredTier &&
        bundleId == other.bundleId &&
        bundleVersion == other.bundleVersion;
  }

  @override
  int get hashCode =>
      Object.hash(widget, requiredTier, bundleId, bundleVersion);

  @override
  String toString() =>
      'CustomStageWidgetDescriptor(id: ${widget.id}, '
      'requiredTier: $requiredTier, bundleId: $bundleId)';
}

/// Mutable registry of [CustomStageWidgetDescriptor]s contributed at runtime
/// by the Stage widget SDK (bundle loader, etc.).
///
/// `customStageWidgetRegistryProvider` binds the writable
/// `LiveCustomStageWidgetRegistry` by default: the bundle manager registers
/// into it and the picker UI reads the live descriptor list from it.
///
/// The interface is deliberately minimal:
///
/// - [register] adds (or replaces) a descriptor. Implementations must be
///   thread-safe — the bundle loader may register from a non-UI isolate.
/// - [unregister] removes by id. Idempotent: missing ids are not an error.
/// - [descriptors] returns the current descriptor list for the picker.
/// - [get] returns a descriptor by id, or null if unknown.
///
/// The registry is intentionally separate from the global `StageRegistry`
/// singleton so the open-core extension-point seam (this provider) can be
/// overridden without forking `StageRegistry`. Picker UI watches this
/// provider and merges its contents with built-in `StageRegistry` entries.
abstract class CustomStageWidgetRegistry {
  /// Registers (or replaces by id) the given [descriptor].
  void register(CustomStageWidgetDescriptor descriptor);

  /// Removes the descriptor with the given [id]. No-op if [id] is unknown.
  void unregister(String id);

  /// Returns the descriptor for [id], or null if not registered.
  CustomStageWidgetDescriptor? get(String id);

  /// Returns every currently-registered descriptor. Iteration order is
  /// implementation-defined; the picker UI sorts before display.
  Iterable<CustomStageWidgetDescriptor> get descriptors;
}
