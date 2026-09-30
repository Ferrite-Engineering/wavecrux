// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/crux_license.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/decoders/l10n/decoder_strings.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_config_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/shared/widgets/wavecrux_feature_tier_badge.dart';
import 'package:wavecrux/shared/widgets/wavecrux_upgrade_dialog.dart';

/// Modal dialog that lists all registered protocol decoders, grouped by
/// [DecoderCategory] in collapsible sections.
///
/// Each section header shows the localized category name, an icon, and the
/// count of decoders in that group. Categories render in
/// [DecoderCategory.values] declaration order — the fixed display order is
/// locale-independent and groups related protocols together (Serial → AMBA
/// → High-Speed → Test/Management → Ethernet → User Plugins → Custom).
///
/// Each decoder tile shows display name, description, required signal count,
/// and — for tier-gated entries — a [FeatureTierBadge] (PRO/ENT). Tapping an entry
/// routes through `FeatureGate.isAvailable`: when the active tier satisfies
/// the decoder's `requiredTier` (always true during the public-beta period —
/// see `kBetaPeriod`), the dialog closes and immediately opens
/// [DecoderConfigDialog]. Post-beta, an unsatisfied tier surfaces an upgrade
/// prompt instead.
class DecoderPickerDialog extends ConsumerWidget {
  const DecoderPickerDialog({
    required this.signalMap,
    this.tabContainer,
    this.autoBindOnSelect = false,
    super.key,
  });

  /// Signal map captured from the per-tab provider before the dialog route was
  /// pushed. Dialogs are rendered outside the per-tab UncontrolledProviderScope
  /// (their context is a child of the Navigator, which sits above the tab
  /// scope), so provider reads inside a dialog always resolve from the root
  /// container where no file is loaded. Passing the map as a constructor
  /// argument bypasses this Navigator-scope gap entirely.
  final Map<String, Variable> signalMap;

  /// The per-tab [ProviderContainer] forwarded to [DecoderConfigDialog] when
  /// a decoder is selected. Without this, `ref` inside [DecoderConfigDialog]
  /// resolves from the root container (Navigator sits above the tab scope) and
  /// writes to the root's [activeDecodersProvider] instead of the
  /// tab's, so transactions never appear in [TransactionTablePanel].
  final ProviderContainer? tabContainer;

  /// When true, the config dialog opened on decoder selection pre-fills its
  /// bindings by running the auto-bind name heuristic against [signalMap]
  /// on open. Set by the signal tree's "Apply decoder to selection" flow,
  /// where [signalMap] is the user's selected subset and an eager best-guess
  /// mapping is the whole point of the gesture.
  final bool autoBindOnSelect;

  /// Opens [DecoderPickerDialog] as a full-screen modal dialog.
  ///
  /// [signalMap] must be read from a context that is inside the per-tab
  /// ProviderScope before calling this method (e.g. from the viewer screen's
  /// toolbar handler, before the dialog route is pushed).
  ///
  /// Pass [tabContainer] so that the config dialog opened on decoder selection
  /// resolves providers from the correct tab scope.
  static Future<void> show(
    BuildContext context, {
    required Map<String, Variable> signalMap,
    ProviderContainer? tabContainer,
    bool autoBindOnSelect = false,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => DecoderPickerDialog(
        signalMap: signalMap,
        tabContainer: tabContainer,
        autoBindOnSelect: autoBindOnSelect,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    // Stacked decoders (those declaring a `parentDecoderId`) are gated:
    // they appear in their own "Stacked Decoders" section only when at
    // least one instance of the parent decoder is currently active in
    // the tab. Until then the parent decoder isn't producing
    // transactions for them to consume, so listing the dependent
    // decoder under its own category section would be misleading.
    //
    // Read the active-decoder list once at build time. The dialog won't
    // refresh if the user activates a parent decoder while the picker
    // is open (uncommon — the parent decoder would have had to be
    // activated from outside the picker, e.g. via right-click on a
    // signal); the next open of the picker will pick up the new state.
    final activeDecoderIds =
        tabContainer
            ?.read(activeDecodersProvider)
            .map((a) => a.decoderId)
            .toSet() ??
        const <String>{};

    final allByCategory = DecoderRegistry.instance.listByCategory();
    final regularByCategory = <DecoderCategory, List<DecoderDefinition>>{};
    final stackedAll = <DecoderDefinition>[];
    for (final entry in allByCategory.entries) {
      final regular = <DecoderDefinition>[];
      for (final def in entry.value) {
        if (def.parentDecoderId == null) {
          regular.add(def);
        } else {
          stackedAll.add(def);
        }
      }
      if (regular.isNotEmpty) {
        regularByCategory[entry.key] = regular;
      }
    }
    final stackedVisible = stackedAll
        .where((d) => activeDecoderIds.contains(d.parentDecoderId))
        .toList();

    final grouped = regularByCategory;
    final currentTier = ref.watch(licenseTierProvider);
    // Read `betaPeriodProvider` and compute the gate at the call site
    // (see `_DecoderListTile._onTapDecoder`) instead of routing through
    // `FeatureGate.isAvailable`. `FeatureGate.isAvailable` short-circuits
    // on the compile-time `crux_license` `kBetaPeriod` constant — a
    // provider override does not flip that constant, so `FeatureGate`'s
    // short-circuit always wins during beta and the post-beta
    // upgrade-dialog path is unreachable from widget tests. Computing
    // the equivalent `beta || tier.featureEquivalent.index >=
    // required.index` expression directly preserves identical runtime
    // behavior (during beta both produce true; post-beta both compare
    // active tier vs required tier — the same `featureEquivalent`
    // mapping `FeatureGate` uses) while letting
    // `betaPeriodProvider.overrideWithValue(false)` flip the gate from
    // a test process.
    final beta = ref.watch(betaPeriodProvider);

    return AlertDialog(
      title: Text(l10n.decoderPickerTitle),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 480,
        // Height grew from 360 → 520 when the RISC-V
        // instruction-trace decoder added a third populated category on
        // open core (Serial / AMBA / Instruction Trace). 360 dp left
        // expanded sections clipping siblings out of the ListView's
        // cacheExtent; 520 dp comfortably fits all three categories
        // collapsed plus one expanded.
        height: 520,
        child: grouped.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.decoderPickerEmptyState,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            : ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                  },
                ),
                // SingleChildScrollView + Column keeps all category sections
                // permanently in the widget tree. The previous ListView with
                // shrinkWrap: true could still unmount tiles whose y-position
                // exceeded viewport + cacheExtent once two categories were
                // expanded — the combined content height (~750 dp for three
                // populated open-core categories with 3-line decoder tiles)
                // exceeded the 520 dp SizedBox + the 250 dp default cacheExtent,
                // causing the third ExpansionTile to be garbage-collected.
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entry in grouped.entries)
                        _DecoderCategorySection(
                          category: entry.key,
                          decoders: entry.value,
                          currentTier: currentTier,
                          beta: beta,
                          signalMap: signalMap,
                          tabContainer: tabContainer,
                          autoBindOnSelect: autoBindOnSelect,
                        ),
                      if (stackedVisible.isNotEmpty)
                        _StackedDecodersSection(
                          decoders: stackedVisible,
                          currentTier: currentTier,
                          beta: beta,
                          signalMap: signalMap,
                          tabContainer: tabContainer,
                          autoBindOnSelect: autoBindOnSelect,
                        ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
      ],
    );
  }
}

/// One collapsible section in the decoder picker, rendering all decoders
/// in a single [DecoderCategory].
class _DecoderCategorySection extends StatelessWidget {
  const _DecoderCategorySection({
    required this.category,
    required this.decoders,
    required this.currentTier,
    required this.beta,
    required this.signalMap,
    required this.autoBindOnSelect,
    this.tabContainer,
  });

  final DecoderCategory category;
  final List<DecoderDefinition> decoders;
  final LicenseTier currentTier;
  final bool beta;
  final Map<String, Variable> signalMap;
  final bool autoBindOnSelect;
  final ProviderContainer? tabContainer;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return ExpansionTile(
      key: ValueKey('decoder_category_${category.name}'),
      leading: Icon(_iconFor(category)),
      title: Text(
        l10n.pickerCategoryHeader(_labelFor(l10n, category), decoders.length),
      ),
      childrenPadding: EdgeInsets.zero,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final def in decoders)
          _DecoderListTile(
            definition: def,
            currentTier: currentTier,
            beta: beta,
            signalMap: signalMap,
            tabContainer: tabContainer,
            autoBindOnSelect: autoBindOnSelect,
          ),
      ],
    );
  }

  static IconData _iconFor(DecoderCategory category) => switch (category) {
    DecoderCategory.serial => Icons.cable,
    DecoderCategory.automotive => Icons.directions_car_outlined,
    DecoderCategory.amba => Icons.memory,
    DecoderCategory.highSpeed => Icons.speed,
    DecoderCategory.testManagement => Icons.bug_report_outlined,
    DecoderCategory.ethernet => Icons.lan_outlined,
    DecoderCategory.instructionTrace => Icons.code_outlined,
    DecoderCategory.userPlugin => Icons.extension_outlined,
    DecoderCategory.custom => Icons.category_outlined,
  };

  static String _labelFor(L10N l10n, DecoderCategory category) =>
      switch (category) {
        DecoderCategory.serial => l10n.decoderCategorySerial,
        DecoderCategory.automotive => l10n.decoderCategoryAutomotive,
        DecoderCategory.amba => l10n.decoderCategoryAmba,
        DecoderCategory.highSpeed => l10n.decoderCategoryHighSpeed,
        DecoderCategory.testManagement => l10n.decoderCategoryTestManagement,
        DecoderCategory.ethernet => l10n.decoderCategoryEthernet,
        DecoderCategory.instructionTrace =>
          l10n.decoderCategoryInstructionTrace,
        DecoderCategory.userPlugin => l10n.decoderCategoryUserPlugin,
        DecoderCategory.custom => l10n.decoderCategoryCustom,
      };
}

/// One decoder row. An insufficient-tier tap is counted as `tier.gate_hit` by
/// [WaveCruxUpgradeDialog.show], when the dialog opens. The allowed path stays
/// uninstrumented here: `decoder.opened` already counts it, from
/// `addDecoder`, which is the one seam every activation passes through.
class _DecoderListTile extends StatelessWidget {
  const _DecoderListTile({
    required this.definition,
    required this.currentTier,
    required this.beta,
    required this.signalMap,
    required this.autoBindOnSelect,
    this.tabContainer,
  });

  final DecoderDefinition definition;
  final LicenseTier currentTier;

  /// Public-beta short-circuit read from `betaPeriodProvider` by the
  /// parent `DecoderPickerDialog`. Combined with
  /// `FeatureGate.isAvailable` at the gate-check call site below so
  /// tests can flip the post-beta path by overriding
  /// `betaPeriodProvider` to `false`. See the parent for the full
  /// rationale.
  final bool beta;

  final Map<String, Variable> signalMap;

  /// Forwarded to [DecoderConfigDialog.show] — see
  /// [DecoderPickerDialog.autoBindOnSelect].
  final bool autoBindOnSelect;

  final ProviderContainer? tabContainer;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final required = definition.requiredSignals;
    final optional = definition.optionalSignals;

    final signalSummary = [
      if (required.isNotEmpty)
        l10n.decoderPickerRequiredSignals(
          required.map((s) => s.name).join(', '),
        ),
      if (optional.isNotEmpty)
        l10n.decoderPickerOptionalSignals(
          optional.map((s) => s.name).join(', '),
        ),
    ].join('  ·  ');

    // For stacked decoders, look up the parent display name so the
    // "Stacks on <Parent>" badge reads naturally instead of carrying
    // the raw registry id.
    String? parentDisplayName;
    final parentId = definition.parentDecoderId;
    if (parentId != null) {
      final parentDef = DecoderRegistry.instance.getDefinition(parentId);
      parentDisplayName = parentDef == null
          ? parentId
          : DecoderStrings.decoderName(
              l10n,
              parentDef.id,
              parentDef.displayName,
            );
    }

    return ListTile(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              DecoderStrings.decoderName(
                l10n,
                definition.id,
                definition.displayName,
              ),
            ),
          ),
          if (definition.requiredTier != LicenseTier.openCore &&
              definition.requiredTier != LicenseTier.edu) ...[
            const SizedBox(width: 8),
            WaveCruxFeatureTierBadge(requiredTier: definition.requiredTier),
          ],
          if (parentDisplayName != null) ...[
            const SizedBox(width: 8),
            _StacksOnBadge(parentDisplayName: parentDisplayName),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DecoderStrings.decoderDescription(
              l10n,
              definition.id,
              definition.description,
            ),
          ),
          if (signalSummary.isNotEmpty)
            Text(
              signalSummary,
              style: Theme.of(context).textTheme.labelSmall,
            ),
        ],
      ),
      isThreeLine: signalSummary.isNotEmpty,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _onTapDecoder(context),
    );
  }

  void _onTapDecoder(BuildContext context) {
    // Equivalent to `FeatureGate.isAvailable(definition.requiredTier,
    // currentTier) || beta`, but bypasses `FeatureGate.isAvailable`'s
    // compile-time `kBetaPeriod` short-circuit so tests can flip the
    // gate by overriding `betaPeriodProvider`. See the parent dialog's
    // `build` for the full rationale.
    final allowed =
        beta ||
        currentTier.featureEquivalent.index >= definition.requiredTier.index;
    if (allowed) {
      Navigator.of(context).pop();
      // Read the notifier from the tab container BEFORE pushing the dialog
      // route. The dialog's context is a child of the Navigator (above the
      // per-tab UncontrolledProviderScope), so ref.read inside the dialog
      // would resolve from the root container — writing to the wrong notifier.
      final decodersNotifier = tabContainer?.read(
        activeDecodersProvider.notifier,
      );
      unawaited(
        DecoderConfigDialog.show(
          context,
          definition: definition,
          signalMap: signalMap,
          decodersNotifier: decodersNotifier,
          autoBindOnOpen: autoBindOnSelect,
        ),
      );
    } else {
      _showUpgradeDialog(context);
    }
  }

  void _showUpgradeDialog(BuildContext context) {
    final l10n = L10N.of(context);
    // The suite's gate-denial convention, and so the one countable denial.
    // Unreachable during the beta by construction — the gate above
    // short-circuits to allow — which matches telemetry's own dark launch and
    // is not dead code to be "fixed". The dialog records the hit, and only
    // when it opens, so a repeated activation counts once.
    unawaited(
      WaveCruxUpgradeDialog.show(
        context,
        featureLabel: DecoderStrings.decoderName(
          l10n,
          definition.id,
          definition.displayName,
        ),
        requiredTier: definition.requiredTier,
        // One closed id for this call site, not `definition.id`: the
        // question is which locked *area* drives upgrade intent, and a
        // runtime-loaded plugin could not report an id we authored anyway.
        // NEVER the localized `featureLabel` above.
        gateFeatureId: 'decoder_pack',
      ),
    );
  }
}

/// Dedicated picker section for decoders that consume another decoder's
/// output ([DecoderDefinition.parentDecoderId] != null). The parent
/// `DecoderPickerDialog` filters the global list and only forwards
/// stacked decoders whose parent is currently active, so this widget
/// trusts its inputs and simply renders them in their own
/// `ExpansionTile`.
class _StackedDecodersSection extends StatelessWidget {
  const _StackedDecodersSection({
    required this.decoders,
    required this.currentTier,
    required this.beta,
    required this.signalMap,
    required this.autoBindOnSelect,
    this.tabContainer,
  });

  final List<DecoderDefinition> decoders;
  final LicenseTier currentTier;
  final bool beta;
  final Map<String, Variable> signalMap;
  final bool autoBindOnSelect;
  final ProviderContainer? tabContainer;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return ExpansionTile(
      key: const ValueKey('decoder_category_stacked'),
      leading: const Icon(Icons.layers_outlined),
      title: Text(
        l10n.pickerCategoryHeader(
          l10n.decoderCategoryStacked,
          decoders.length,
        ),
      ),
      childrenPadding: EdgeInsets.zero,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final def in decoders)
          _DecoderListTile(
            definition: def,
            currentTier: currentTier,
            beta: beta,
            signalMap: signalMap,
            tabContainer: tabContainer,
            autoBindOnSelect: autoBindOnSelect,
          ),
      ],
    );
  }
}

/// Small inline badge ("Stacks on SPI") rendered next to a stacked
/// decoder's name in the picker. Uses the theme's secondary container
/// surface so it visually contrasts with `WaveCruxFeatureTierBadge` (which
/// uses the brand colour) — the two badges can coexist on the same
/// row without colour clash.
class _StacksOnBadge extends StatelessWidget {
  const _StacksOnBadge({required this.parentDisplayName});

  final String parentDisplayName;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        l10n.decoderStacksOnBadge(parentDisplayName),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
