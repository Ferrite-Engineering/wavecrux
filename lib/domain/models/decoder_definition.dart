// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/models/decoder_parameter.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';

/// Static metadata that describes a protocol decoder plugin.
///
/// Each concrete [ProtocolDecoder] implementation provides one
/// [DecoderDefinition] that tells the UI:
/// - which signals to ask the user to bind,
/// - which configuration knobs to expose, and
/// - human-readable names and descriptions for each.
@immutable
class DecoderDefinition {
  const DecoderDefinition({
    required this.id,
    required this.displayName,
    required this.description,
    required this.requiredSignals,
    this.optionalSignals = const [],
    this.parameters = const [],
    this.requiredTier = LicenseTier.openCore,
    this.category = DecoderCategory.custom,
    this.parentDecoderId,
  });

  /// Stable, unique identifier used to look up this decoder in the registry.
  ///
  /// Use lower-snake-case (e.g. `"spi"`, `"i2c"`, `"axi4_lite"`).
  final String id;

  /// Short, user-visible name (e.g. `"SPI"`, `"I²C"`, `"AXI4-Lite"`).
  final String displayName;

  /// One-sentence description of what the decoder does.
  final String description;

  /// Signal inputs the user **must** bind before the decoder can run.
  final List<SignalBinding> requiredSignals;

  /// Signal inputs that improve decoding quality but are not mandatory.
  final List<SignalBinding> optionalSignals;

  /// Configurable parameters exposed in the decoder setup UI.
  final List<DecoderParameter> parameters;

  /// Minimum product tier required to activate this decoder.
  ///
  /// Open-core decoders default to [LicenseTier.openCore]. Pro and Enterprise
  /// decoders shipped via the closed-source overlay set this to the tier they
  /// require; the picker UI renders a `FeatureTierBadge` next to gated entries and
  /// routes activation through `FeatureGate.isAvailable` (which short-circuits
  /// to allow during the public-beta period — see `kBetaPeriod`).
  final LicenseTier requiredTier;

  /// Broad category used to group decoders in the picker.
  ///
  /// Decoders that ship with WaveCrux declare a specific category (`serial`,
  /// `amba`, `highSpeed`, `testManagement`, `ethernet`). Dynamically loaded
  /// plugins use [DecoderCategory.userPlugin]. The default
  /// ([DecoderCategory.custom]) keeps third-party decoders compiling without
  /// forcing them to pick a built-in group.
  final DecoderCategory category;

  /// When non-null, this decoder stacks on top of the decoder whose [id]
  /// matches [parentDecoderId].
  ///
  /// Stacked decoders implement [StackedDecoder] and receive their parent's
  /// [DecodedTransaction] output rather than raw signal data. The two-pass
  /// logic in `ActiveDecodersNotifier.decodeAll()` runs stacked decoders after
  /// all base decoders have produced their transactions.
  ///
  /// `null` for all non-stacked (base) decoders.
  final String? parentDecoderId;

  // ── copyWith ───────────────────────────────────────────────────────────────

  DecoderDefinition copyWith({
    String? id,
    String? displayName,
    String? description,
    List<SignalBinding>? requiredSignals,
    List<SignalBinding>? optionalSignals,
    List<DecoderParameter>? parameters,
    LicenseTier? requiredTier,
    DecoderCategory? category,
    Object? parentDecoderId = _sentinel,
  }) => DecoderDefinition(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    description: description ?? this.description,
    requiredSignals: requiredSignals ?? this.requiredSignals,
    optionalSignals: optionalSignals ?? this.optionalSignals,
    parameters: parameters ?? this.parameters,
    requiredTier: requiredTier ?? this.requiredTier,
    category: category ?? this.category,
    parentDecoderId: parentDecoderId == _sentinel
        ? this.parentDecoderId
        : parentDecoderId as String?,
  );

  static const Object _sentinel = Object();

  // ── equality ───────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DecoderDefinition) return false;
    if (id != other.id) return false;
    if (displayName != other.displayName) return false;
    if (description != other.description) return false;
    if (requiredTier != other.requiredTier) return false;
    if (category != other.category) return false;
    if (parentDecoderId != other.parentDecoderId) return false;
    if (!_listEqual(requiredSignals, other.requiredSignals)) return false;
    if (!_listEqual(optionalSignals, other.optionalSignals)) return false;
    return _listEqual(parameters, other.parameters);
  }

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    description,
    requiredTier,
    category,
    parentDecoderId,
    Object.hashAll(requiredSignals),
    Object.hashAll(optionalSignals),
    Object.hashAll(parameters),
  );

  @override
  String toString() => 'DecoderDefinition(id: $id, displayName: $displayName)';

  // ── private helpers ────────────────────────────────────────────────────────

  static bool _listEqual<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
