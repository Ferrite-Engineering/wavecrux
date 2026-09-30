// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Per-instance configuration for the Tachometer reference widget.
///
/// The schema is declared on `TachometerStageWidget.configParams` and
/// stored in `StageInstance.configuration` as a JSON-natural map of
/// scalar values. Round-trips through [fromMap] / [toMap] losslessly
/// for any in-range config; missing or non-coercible keys fall back to
/// constructor defaults, and out-of-range zone thresholds are clamped
/// into the live `[minRpm, maxRpm]` range rather than discarding the
/// whole config (the invalid-input policy — see [fromMap]).
///
/// `minRpm` / `maxRpm` describe the **input** range the gauge expects on
/// the bound RPM signal. The renderer constructs a `LinearNormalizer`
/// from these values and overrides the manifest's static normalizer at
/// runtime — the "per-instance config knobs" path. The
/// `warningRpm` and `redlineRpm` thresholds are decorative metadata
/// stored in the config; they are not yet consumed by the renderer
/// (reserved for an overlay painter).
///
/// Pure Dart — no Flutter imports.
@immutable
class TachometerConfig {
  /// Constructs a config with the documented defaults for an automotive
  /// engine tachometer (0–8000 RPM, warning at 6500, redline at 7500).
  const TachometerConfig({
    this.minRpm = 0,
    this.maxRpm = 8000,
    this.warningRpm = 6500,
    this.redlineRpm = 7500,
  }) : assert(minRpm < maxRpm, 'minRpm must be < maxRpm'),
       assert(warningRpm >= minRpm, 'warningRpm must be >= minRpm'),
       assert(warningRpm <= maxRpm, 'warningRpm must be <= maxRpm'),
       assert(redlineRpm >= minRpm, 'redlineRpm must be >= minRpm'),
       assert(redlineRpm <= maxRpm, 'redlineRpm must be <= maxRpm'),
       assert(
         redlineRpm >= warningRpm,
         'redlineRpm must be >= warningRpm',
       );

  /// Parses a config from a `StageInstance.configuration` map.
  ///
  /// Missing keys fall back to the corresponding default; values that
  /// fail to coerce fall back per-key. Cross-field relationships are
  /// **repaired, not rejected**: the decorative `warningRpm` /
  /// `redlineRpm` zones are clamped into the `[minRpm, maxRpm]` range
  /// (and `redlineRpm >= warningRpm` is preserved) so that lowering
  /// `maxRpm` below the default zone thresholds keeps the user's
  /// `maxRpm` instead of silently reverting the whole config to
  /// defaults. Only a degenerate range (`minRpm >= maxRpm`), which has
  /// no sensible needle mapping, falls the *range* back to the default
  /// 0..8000 — the zones then clamp into that. Mirror of [toMap].
  ///
  /// History: before 2026-06 this discarded the entire config on any
  /// invariant breach, so editing `maxRpm` alone (leaving the default
  /// warning 6500 / redline 7500 in place) tripped `warning > max` and
  /// silently snapped `maxRpm` back to 8000 — the gauge appeared to
  /// ignore the range knob entirely.
  factory TachometerConfig.fromMap(Map<String, Object?> map) {
    const defaults = TachometerConfig();
    var minRpm = _readInt(map['minRpm'], defaults.minRpm);
    var maxRpm = _readInt(map['maxRpm'], defaults.maxRpm);
    // A degenerate/inverted range is the only relation the gauge cannot
    // repair by clamping (there is no needle mapping for min >= max), so
    // fall the range itself back to the defaults.
    if (minRpm >= maxRpm) {
      minRpm = defaults.minRpm;
      maxRpm = defaults.maxRpm;
    }
    // Zones are decorative metadata (not yet consumed by the renderer);
    // clamp them into the live range rather than rejecting the config.
    // warningRpm in [minRpm, maxRpm]; redlineRpm in [warningRpm, maxRpm]
    // so redlineRpm >= warningRpm holds for the constructor's asserts.
    final warningRpm = _readInt(
      map['warningRpm'],
      defaults.warningRpm,
    ).clamp(minRpm, maxRpm);
    final redlineRpm = _readInt(
      map['redlineRpm'],
      defaults.redlineRpm,
    ).clamp(warningRpm, maxRpm);
    return TachometerConfig(
      minRpm: minRpm,
      maxRpm: maxRpm,
      warningRpm: warningRpm,
      redlineRpm: redlineRpm,
    );
  }

  /// Lower bound of the RPM range. Drives the `LinearNormalizer`'s
  /// `inputMin`.
  final int minRpm;

  /// Upper bound of the RPM range. Drives the `LinearNormalizer`'s
  /// `inputMax`.
  final int maxRpm;

  /// RPM at which the gauge enters the warning zone (between
  /// [warningRpm] and [redlineRpm]). Decorative metadata for a future
  /// overlay painter.
  final int warningRpm;

  /// RPM at which the gauge enters the redline zone. Decorative
  /// metadata for a future overlay painter.
  final int redlineRpm;

  /// Serializes this config to a `StageInstance.configuration` map.
  /// Round-trip with [TachometerConfig.fromMap] is lossless.
  Map<String, Object?> toMap() => <String, Object?>{
    'minRpm': minRpm,
    'maxRpm': maxRpm,
    'warningRpm': warningRpm,
    'redlineRpm': redlineRpm,
  };

  /// Returns a copy of this config with the given fields overridden.
  TachometerConfig copyWith({
    int? minRpm,
    int? maxRpm,
    int? warningRpm,
    int? redlineRpm,
  }) => TachometerConfig(
    minRpm: minRpm ?? this.minRpm,
    maxRpm: maxRpm ?? this.maxRpm,
    warningRpm: warningRpm ?? this.warningRpm,
    redlineRpm: redlineRpm ?? this.redlineRpm,
  );

  static int _readInt(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is double) return raw.round();
    if (raw is String) return int.tryParse(raw) ?? fallback;
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TachometerConfig &&
          minRpm == other.minRpm &&
          maxRpm == other.maxRpm &&
          warningRpm == other.warningRpm &&
          redlineRpm == other.redlineRpm;

  @override
  int get hashCode => Object.hash(minRpm, maxRpm, warningRpm, redlineRpm);

  @override
  String toString() =>
      'TachometerConfig(minRpm: $minRpm, maxRpm: $maxRpm, '
      'warningRpm: $warningRpm, redlineRpm: $redlineRpm)';
}
