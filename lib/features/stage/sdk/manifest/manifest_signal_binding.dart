// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_enums.dart';

/// Optional inclusive bit-width range for a vector binding.
///
/// Manifest authors use the range to declare "this widget needs a bus
/// 4–32 bits wide" without having to enumerate every width. The runtime
/// rejects bindings whose declared width falls outside the range.
@immutable
class BitWidthRange {
  const BitWidthRange({this.min, this.max})
    : assert(
        min == null || min >= 0,
        'BitWidthRange.min must be >= 0',
      );

  /// Minimum allowed width, inclusive. Null means "no minimum".
  final int? min;

  /// Maximum allowed width, inclusive. Null means "no maximum".
  final int? max;

  bool get isUnbounded => min == null && max == null;

  bool accepts(int width) {
    if (min != null && width < min!) return false;
    if (max != null && width > max!) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BitWidthRange && min == other.min && max == other.max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'BitWidthRange(min: $min, max: $max)';
}

/// Optional analog input range used by linear-style normalizers and the
/// binding configuration UI to constrain user input.
@immutable
class ValueRange {
  const ValueRange({required this.min, required this.max})
    : assert(max != min, 'ValueRange.max must differ from min');

  final double min;
  final double max;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValueRange && min == other.min && max == other.max;

  @override
  int get hashCode => Object.hash(min, max);

  @override
  String toString() => 'ValueRange(min: $min, max: $max)';
}

/// One declared signal input on a Stage Pro custom widget.
///
/// Mirrors the open-core `SignalBinding` (used by protocol decoders and
/// built-in Stage widgets) but adds the metadata needed for advanced
/// custom-widget UX — direction, signal type discrimination, value-range
/// hints, and unbound-default behavior.
@immutable
class ManifestSignalBinding {
  const ManifestSignalBinding({
    required this.name,
    required this.description,
    required this.signalType,
    this.direction = BindingDirection.input,
    this.bitWidth,
    this.valueRange,
    this.required = true,
    this.defaultPolicy = DefaultPolicy.holdLast,
  });

  /// Logical name (`"data"`, `"clk"`, `"address"`).
  final String name;

  /// One-sentence purpose description shown in the binding dialog.
  final String description;

  /// Logical signal type — drives validation and binding-UI behaviour.
  final SignalType signalType;

  /// Direction (input by default; output reserved for future widgets).
  final BindingDirection direction;

  /// Optional bit-width constraint for vector bindings. Ignored for
  /// scalar / analog / bus-group bindings.
  final BitWidthRange? bitWidth;

  /// Optional value range for analog scaling. Used by linear normalizers
  /// and the binding UI's "range" hint.
  final ValueRange? valueRange;

  /// Whether the user must bind this signal before the widget can render.
  final bool required;

  /// What the runtime should do when the binding is unbound.
  final DefaultPolicy defaultPolicy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManifestSignalBinding &&
          name == other.name &&
          description == other.description &&
          signalType == other.signalType &&
          direction == other.direction &&
          bitWidth == other.bitWidth &&
          valueRange == other.valueRange &&
          required == other.required &&
          defaultPolicy == other.defaultPolicy;

  @override
  int get hashCode => Object.hash(
    name,
    description,
    signalType,
    direction,
    bitWidth,
    valueRange,
    required,
    defaultPolicy,
  );

  @override
  String toString() =>
      'ManifestSignalBinding(name: $name, '
      'signalType: $signalType, required: $required)';
}
