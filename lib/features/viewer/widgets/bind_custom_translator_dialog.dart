// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/features/settings/providers/custom_translators_provider.dart';
import 'package:wavecrux/features/settings/screens/settings_screen.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/extra_translator_presets_provider.dart';
import 'package:wavecrux/plugins/translator_preset.dart';
import 'package:wavecrux/services/value_format/bitfield_translator.dart';
import 'package:wavecrux/services/value_format/riscv_disasm_translator.dart';
import 'package:wavecrux/shared/widgets/wavecrux_feature_tier_badge.dart';
import 'package:wavecrux/shared/widgets/wavecrux_upgrade_dialog.dart';

/// Lets the user bind a custom translator to the selected signal.
///
/// Lists, in order: contributed [TranslatorPreset]s (the curated Pro pack, via
/// [extraTranslatorPresetsProvider]) — each with a [WaveCruxFeatureTierBadge] and a
/// `FeatureGate` at tap — then the built-in (Open Core) RISC-V
/// instruction-disassembly translator, then the user's authored bit-field
/// translators. Returns the `translatorConfig` map to write onto the signal
/// (carrying the [kTranslatorIdConfigKey] marker the value column resolves), or
/// null when cancelled.
class BindCustomTranslatorDialog extends ConsumerWidget {
  const BindCustomTranslatorDialog({super.key});

  static Future<Map<String, Object?>?> show(BuildContext context) =>
      showDialog<Map<String, Object?>>(
        context: context,
        builder: (_) => const BindCustomTranslatorDialog(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final translators = ref.watch(customTranslatorsProvider);
    final presets = ref.watch(extraTranslatorPresetsProvider);
    final currentTier = ref.watch(licenseTierProvider);
    // Read `betaPeriodProvider` (not `FeatureGate.isAvailable`) so the
    // post-beta upgrade path stays reachable from widget tests via
    // `betaPeriodProvider.overrideWithValue(false)` — see the identical
    // rationale in `DecoderPickerDialog`.
    final beta = ref.watch(betaPeriodProvider);

    return AlertDialog(
      title: Text(l10n.bindCustomTranslatorTitle),
      content: SizedBox(
        width: 420,
        // One scroll region for the whole list (presets + RISC-V + authored)
        // so it scrolls as a unit. The default `ScrollBehavior` omits mouse
        // and trackpad from its drag devices, so two-finger trackpad and
        // click-drag scrolling don't work inside a dialog without this
        // `ScrollConfiguration` — mirrors `DecoderPickerDialog`.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
            },
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Contributed presets (curated Pro pack). Each carries its
                  // own tier badge + feature gate.
                  for (final preset in presets)
                    _PresetTile(
                      preset: preset,
                      currentTier: currentTier,
                      beta: beta,
                    ),
                  if (presets.isNotEmpty) const Divider(),
                  // Built-in RISC-V disassembly translator (Open Core).
                  ListTile(
                    leading: const Icon(Icons.memory_outlined),
                    title: Text(l10n.bindCustomTranslatorRiscv),
                    onTap: () => Navigator.of(context).pop(
                      const <String, Object?>{
                        kTranslatorIdConfigKey:
                            RiscvDisasmTranslator.translatorId,
                      },
                    ),
                  ),
                  const Divider(),
                  if (translators.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        l10n.bindCustomTranslatorEmpty,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    for (final def in translators)
                      ListTile(
                        leading: const Icon(Icons.account_tree_outlined),
                        title: Text(def.name),
                        subtitle: Text(
                          l10n.customTranslatorFieldCount(
                            def.config.fields.length,
                          ),
                        ),
                        onTap: () => Navigator.of(context).pop(
                          _bitfieldConfigMap(def.config),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await SettingsScreen.openAdaptive(context);
          },
          child: Text(l10n.bindCustomTranslatorManage),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.customTranslatorCancel),
        ),
      ],
    );
  }

  /// Serializes [config] plus the bitfield-translator binding marker into the
  /// per-signal `translatorConfig` map.
  static Map<String, Object?> _bitfieldConfigMap(
    BitfieldTranslatorConfig config,
  ) => {
    ...config.toMap(),
    kTranslatorIdConfigKey: BitfieldTranslator.translatorId,
  };
}

/// One contributed [TranslatorPreset] row, rendering a tier badge for
/// non-open-core presets and gating the tap through the same
/// `beta || tier.featureEquivalent >= required` rule the decoder picker uses.
///
/// A [ConsumerWidget] rather than a plain [StatelessWidget] only so the tap
/// handler can reach `telemetryServiceProvider`: the bind records
/// `translator.preset_bound`. The denial's `tier.gate_hit` is recorded by
/// `WaveCruxUpgradeDialog.show`, when the dialog opens.
class _PresetTile extends ConsumerWidget {
  const _PresetTile({
    required this.preset,
    required this.currentTier,
    required this.beta,
  });

  final TranslatorPreset preset;
  final LicenseTier currentTier;
  final bool beta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final description = preset.descriptionResolver?.call(context);
    final showBadge =
        preset.requiredTier != LicenseTier.openCore &&
        preset.requiredTier != LicenseTier.edu;
    return ListTile(
      key: ValueKey('translator_preset_${preset.id}'),
      leading: Icon(preset.icon),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(preset.labelResolver(context))),
          if (showBadge) ...[
            const SizedBox(width: 8),
            WaveCruxFeatureTierBadge(requiredTier: preset.requiredTier),
          ],
        ],
      ),
      subtitle: description == null ? null : Text(description),
      onTap: () => _onTap(context, ref),
    );
  }

  void _onTap(BuildContext context, WidgetRef ref) {
    // Equivalent to `FeatureGate.isAvailable(preset.requiredTier,
    // currentTier)`, but bypasses its compile-time `kBetaPeriod`
    // short-circuit so tests can flip the post-beta path via
    // `betaPeriodProvider`. See `DecoderPickerDialog` for the full rationale.
    final allowed =
        beta ||
        currentTier.featureEquivalent.index >= preset.requiredTier.index;
    if (allowed) {
      final config = preset.configBuilder();
      // The family the preset binds, not the preset id: `pro.amba` → `amba`,
      // the same last-segment derivation `stage.widget_added` performs on a
      // widget-family id. Recorded here rather than in the value column's
      // `setSignalTranslatorConfigById`, which is also the session-restore
      // path — nobody chooses a translator on a restore. The built-in RISC-V
      // row and the user's own bit-field translators are not presets and do
      // not pass through this tile; the pack is what the event measures.
      final translatorId = config[kTranslatorIdConfigKey];
      if (translatorId is String) {
        ref
            .read(telemetryServiceProvider)
            .record(
              TelemetryEvent(
                'translator.preset_bound',
                properties: <String, Object?>{
                  'family': translatorId.split('.').last.toLowerCase(),
                },
              ),
            );
      }
      Navigator.of(context).pop(config);
    } else {
      _showUpgradeDialog(context);
    }
  }

  void _showUpgradeDialog(BuildContext context) {
    // The suite's gate-denial convention, and so the one place a denied
    // activation of a tier-gated translator preset is countable. Unreachable
    // during the beta by construction (see `WaveCruxUpgradeDialog`): the gate
    // above short-circuits to allow, so `tier.gate_hit` cannot fire until the
    // beta flip. That is correct — it matches telemetry's own dark launch —
    // and is not dead code to be "fixed". The dialog records the hit, and
    // only when it opens, so a repeated activation counts once.
    unawaited(
      WaveCruxUpgradeDialog.show(
        context,
        featureLabel: preset.labelResolver(context),
        requiredTier: preset.requiredTier,
        // A closed id for this call site. NEVER `preset.labelResolver`,
        // which is the localized display string the dialog shows.
        gateFeatureId: 'translator_preset',
      ),
    );
  }
}
