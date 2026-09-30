// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';

/// One concrete Stage widget instance placed on a Stage panel.
///
/// A [StageInstance] pairs a registered [StageWidget] (referenced by
/// [widgetId]) with the user's per-instance configuration: a unique
/// runtime id, signal-binding map, position and size on the panel, and
/// an optional display label.
///
/// Pure Dart — no Flutter imports.
@immutable
class StageInstance {
  const StageInstance({
    required this.id,
    required this.widgetId,
    this.signalBindings = const {},
    this.configuration = const <String, Object?>{},
    this.x = 0,
    this.y = 0,
    this.width = 160,
    this.height = 100,
    this.label,
  });

  /// Unique id for this instance within the workspace. Stable across
  /// session save / load. Generated with `stage_<n>` format by
  /// [StageWorkspaceNotifier].
  final String id;

  /// [StageWidget.id] from the registry. Lookup fails gracefully when
  /// the registered widget has been removed since the session was saved.
  final String widgetId;

  /// Maps logical pin name (from [StageWidget.requiredSignals] /
  /// [StageWidget.optionalSignals]) to a [StageSignalBinding].
  ///
  /// A binding is `(signalRef, bitIndex?)`: the signal reference plus
  /// an optional bit index that lets a multi-bit vector be bound to a
  /// 1-bit slot — e.g., binding `top.dut.led[15:0]` bit 3 to slot
  /// `led3` of the Basys 3 board widget.
  ///
  /// Empty when the user has not bound any signals yet. Unbound entries
  /// cause the widget to render in an "unbound" state until the user
  /// supplies them.
  final Map<String, StageSignalBinding> signalBindings;

  /// Per-instance configuration. Maps each [StageWidget.configParams]
  /// id to its stored scalar value (`int` / `double` / `bool` /
  /// `String`). Widgets translate this to and from typed payloads via
  /// their own `parseConfig` / `serializeConfig` helpers — see
  /// ARCHITECTURE.md §10 (Pro Overlay Seams).
  ///
  /// Empty by default. Missing keys mean "use the schema default", so
  /// pre-config-field session files round-trip cleanly. Widgets with
  /// no configurable params (most open-core primitives) leave this
  /// empty for every instance.
  final Map<String, Object?> configuration;

  /// X offset of the instance within its Stage panel, in logical pixels.
  final double x;

  /// Y offset of the instance within its Stage panel, in logical pixels.
  final double y;

  /// Width of the instance, in logical pixels.
  final double width;

  /// Height of the instance, in logical pixels.
  final double height;

  /// Optional user-provided label shown on the instance header. Null
  /// falls back to the widget's [StageWidget.displayName].
  final String? label;

  StageInstance copyWith({
    String? id,
    String? widgetId,
    Map<String, StageSignalBinding>? signalBindings,
    Map<String, Object?>? configuration,
    double? x,
    double? y,
    double? width,
    double? height,
    String? label,
    bool clearLabel = false,
  }) => StageInstance(
    id: id ?? this.id,
    widgetId: widgetId ?? this.widgetId,
    signalBindings: signalBindings ?? this.signalBindings,
    configuration: configuration ?? this.configuration,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    label: clearLabel ? null : (label ?? this.label),
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StageInstance) return false;
    return id == other.id &&
        widgetId == other.widgetId &&
        x == other.x &&
        y == other.y &&
        width == other.width &&
        height == other.height &&
        label == other.label &&
        _bindingsEqual(signalBindings, other.signalBindings) &&
        _configEqual(configuration, other.configuration);
  }

  @override
  int get hashCode => Object.hash(
    id,
    widgetId,
    x,
    y,
    width,
    height,
    label,
    // Map iteration order is implementation-defined, so the entry
    // hashes must combine order-independently — otherwise two
    // instances with the same content but different insertion order
    // produce different hashCodes and break the equality contract.
    Object.hashAllUnordered(
      signalBindings.entries.map(
        (e) => Object.hash(e.key, e.value),
      ),
    ),
    Object.hashAllUnordered(
      configuration.entries.map(
        (e) => Object.hash(e.key, e.value),
      ),
    ),
  );

  @override
  String toString() =>
      'StageInstance(id: $id, widgetId: $widgetId, bindings: '
      '${signalBindings.length}, config: ${configuration.length})';

  static bool _bindingsEqual(
    Map<String, StageSignalBinding> a,
    Map<String, StageSignalBinding> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _configEqual(
    Map<String, Object?> a,
    Map<String, Object?> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
