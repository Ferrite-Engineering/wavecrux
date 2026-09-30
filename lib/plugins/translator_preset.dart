// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:collection/collection.dart' show DeepCollectionEquality;
import 'package:crux_license/crux_license.dart';
import 'package:flutter/widgets.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart'
    show kTranslatorIdConfigKey;

/// Resolves a localized string for a [TranslatorPreset] from the current
/// [BuildContext]. Open-core presets read from `L10N.of(context)`; Pro presets
/// pass a resolver that delegates to `L10NPro.of(context).…` so they localize
/// through the Pro ARB sweep without open-core depending on the Pro l10n class.
typedef TranslatorPresetStringResolver = String Function(BuildContext context);

/// Builds the per-signal `translatorConfig` map this preset writes onto the
/// bound signal. The returned map MUST carry the `kTranslatorIdConfigKey`
/// binding (the registry id the value column resolves) plus whatever payload
/// that translator reads (`fields` for bitfield-backed translators, a format
/// selector for the Pro float / pixel translators, …).
typedef TranslatorPresetConfigBuilder = Map<String, Object?> Function();

/// Open-core descriptor for a ready-made translator binding offered in the
/// value-column "Custom translator…" dialog ([BindCustomTranslatorDialog]).
///
/// The bind dialog already hard-wires the Open-Core RISC-V disassembly entry
/// and lists the user's authored bit-field translators. [TranslatorPreset] is
/// the extension point through which *contributed* translators — notably the
/// curated **Pro** translator pack (AMBA control-word
/// expanders, extended/ML floats, pixel formats) — surface in the same dialog
/// without forking it.
///
/// Each preset carries its own [labelResolver] / [descriptionResolver] (so the
/// label survives the locale sweep), an [icon], the [configBuilder] that
/// produces the binding map, and an optional [requiredTier]. The dialog renders
/// a [WaveCruxFeatureTierBadge] for any non-open-core tier and routes activation
/// through `FeatureGate.isAvailable(requiredTier, …)`: during the public beta
/// (`kBetaPeriod`) the gate short-circuits to allow; post-beta an unsatisfied
/// tier surfaces the upgrade dialog instead of binding.
///
/// Mirrors the [BottomDockTab] pattern (a Flutter-aware plugin descriptor in
/// `lib/plugins/` carrying an `IconData`, a label resolver, and a
/// `requiredTier`). The default contribution list is empty in open-core; the
/// Pro overlay replaces [extraTranslatorPresetsProvider] to populate it.
@immutable
class TranslatorPreset {
  /// Creates a translator preset. [requiredTier] defaults to
  /// [LicenseTier.openCore] (no badge, never gated).
  const TranslatorPreset({
    required this.id,
    required this.labelResolver,
    required this.icon,
    required this.configBuilder,
    this.descriptionResolver,
    this.requiredTier = LicenseTier.openCore,
  });

  /// Stable identifier for the preset (e.g. `"pro.amba.axcache"`). Unique
  /// across all contributed presets; used as the list-tile key.
  final String id;

  /// Resolves the localized human-readable label shown as the tile title
  /// (e.g. `"AXI4 · AxCACHE"`).
  final TranslatorPresetStringResolver labelResolver;

  /// Resolves the optional localized one-line description shown as the tile
  /// subtitle. `null` renders no subtitle.
  final TranslatorPresetStringResolver? descriptionResolver;

  /// Leading icon for the tile.
  final IconData icon;

  /// Builds the `translatorConfig` map written onto the signal when the user
  /// taps this preset. Must include the `kTranslatorIdConfigKey` binding.
  final TranslatorPresetConfigBuilder configBuilder;

  /// License tier required to bind this preset. Open-core defaults to
  /// [LicenseTier.openCore]; Pro presets pass [LicenseTier.pro]. The bind
  /// dialog gates activation through `FeatureGate.isAvailable`.
  final LicenseTier requiredTier;
}

/// The preset among [presets] that a signal's translator binding [config]
/// came from, for naming the binding to the user.
///
/// The preset whose built configuration [config] carries in full wins, which
/// tells apart the presets that bind one translator with different settings
/// (RGB565 and RGB888 both bind the pixel translator). Failing that, the first
/// preset that binds the same translator id; failing that, `null`.
TranslatorPreset? presetForBinding(
  Iterable<TranslatorPreset> presets,
  Map<String, Object?> config,
) {
  const equality = DeepCollectionEquality();
  final id = config[kTranslatorIdConfigKey];
  TranslatorPreset? sameTranslator;
  for (final preset in presets) {
    final built = preset.configBuilder();
    if (built[kTranslatorIdConfigKey] != id) continue;
    sameTranslator ??= preset;
    final carried = built.entries.every(
      (e) =>
          config.containsKey(e.key) && equality.equals(config[e.key], e.value),
    );
    if (carried) return preset;
  }
  return sameTranslator;
}
