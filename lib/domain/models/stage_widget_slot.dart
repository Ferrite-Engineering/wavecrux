// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// One child-widget slot in a [CompoundStageWidget] backdrop.
///
/// Compound widgets (FPGA boards, dashboards) lay out one or more child
/// [StageWidget]s at fixed positions on top of an illustration. Each slot
/// carries:
/// - the [childWidgetId] of the primitive to render (e.g. `"led"`);
/// - the slot's normalised position and size on the backdrop (`0..1` in
///   each axis, so the layout scales when the user resizes the compound);
/// - a stable [name] used both as the picker label and as the key under
///   which the user's signal-binding for this child is stored.
///
/// Pure Dart — no Flutter imports.
@immutable
class StageWidgetSlot {
  const StageWidgetSlot({
    required this.name,
    required this.childWidgetId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.label,
    this.pinBindings,
  });

  /// Stable identifier within the compound (e.g. `"led0"`, `"sw5"`,
  /// `"seg_digit_2"`). Used as the binding key in session files.
  final String name;

  /// [StageWidget.id] of the primitive that renders into this slot.
  final String childWidgetId;

  /// Normalised X position (0.0 = left edge, 1.0 = right edge).
  final double x;

  /// Normalised Y position (0.0 = top edge, 1.0 = bottom edge).
  final double y;

  /// Normalised width (0.0–1.0).
  final double width;

  /// Normalised height (0.0–1.0).
  final double height;

  /// Optional human-readable label rendered next to the child widget
  /// (e.g. constraint-file pin name `"LD0"`). May be null.
  final String? label;

  /// Optional multi-pin binding map for slots whose child widget needs
  /// more than one signal to render correctly (e.g. the Pro framebuffer
  /// peripheral primitive needs `pixelClk`, `data`, and optional
  /// `hSync` / `vSync` / `dataEnable`).
  ///
  /// Keys are the child widget's binding pin names (matching its
  /// `requiredSignals` / `optionalSignals` declarations); values are
  /// **sibling slot names** on the same compound widget whose
  /// `parentInstance.signalBindings[<sibling>]` entry holds the
  /// signal binding for that pin. The board scaffold reads each pin's
  /// binding from the named sibling slot, populating the child
  /// instance's `signalBindings` accordingly.
  ///
  /// When `null` (the default), the slot follows the single-pin
  /// convention: one binding stored under `slot.name` in the parent's
  /// `signalBindings`, mapped to the child widget's primary pin via
  /// `childInputPinName(childWidgetId)`.
  ///
  /// **Sibling slot pattern.** Each pin in the map should have a
  /// matching standalone slot in the same compound widget (typically
  /// rendered as a small chip via a 1-bit primitive like
  /// `LedStageWidget`) so the user has a per-pin drop target in the
  /// bindings UI. Drag-to-bind on the multi-pin slot itself currently
  /// no-ops — users bind each pin via its sibling chip slot.
  final Map<String, String>? pinBindings;

  /// True when this slot represents a multi-pin peripheral (its child
  /// widget needs more than one signal binding to render).
  bool get isMultiPin => pinBindings != null && pinBindings!.isNotEmpty;

  StageWidgetSlot copyWith({
    String? name,
    String? childWidgetId,
    double? x,
    double? y,
    double? width,
    double? height,
    String? label,
    bool clearLabel = false,
    Map<String, String>? pinBindings,
    bool clearPinBindings = false,
  }) => StageWidgetSlot(
    name: name ?? this.name,
    childWidgetId: childWidgetId ?? this.childWidgetId,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    label: clearLabel ? null : (label ?? this.label),
    pinBindings: clearPinBindings ? null : (pinBindings ?? this.pinBindings),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StageWidgetSlot &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          childWidgetId == other.childWidgetId &&
          x == other.x &&
          y == other.y &&
          width == other.width &&
          height == other.height &&
          label == other.label &&
          _mapsEqual(pinBindings, other.pinBindings);

  @override
  int get hashCode => Object.hash(
    name,
    childWidgetId,
    x,
    y,
    width,
    height,
    label,
    pinBindings == null
        ? null
        : Object.hashAllUnordered(
            pinBindings!.entries.map(
              (e) => Object.hash(e.key, e.value),
            ),
          ),
  );

  @override
  String toString() =>
      'StageWidgetSlot(name: $name, childWidgetId: $childWidgetId, '
      'x: $x, y: $y, w: $width, h: $height'
      '${isMultiPin ? ', pinBindings: $pinBindings' : ''})';

  static bool _mapsEqual(Map<String, String>? a, Map<String, String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
