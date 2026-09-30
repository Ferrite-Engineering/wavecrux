// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/crux_license.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/custom_stage_widget_registry.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/features/stage/providers/stage_config_label_resolver_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/custom_stage_widget_registry_provider.dart';
import 'package:wavecrux/plugins/stage_registry.dart';
import 'package:wavecrux/shared/widgets/wavecrux_feature_tier_badge.dart';
import 'package:wavecrux/shared/widgets/wavecrux_upgrade_dialog.dart';

/// Modal dialog that lists every registered [StageWidget], grouped by
/// [StageWidgetCategory] in collapsible sections.
///
/// Each section header shows the localized category name, an icon, and
/// the count of widgets in that group. Categories render in
/// [StageWidgetCategory.values] declaration order — the fixed display
/// order is locale-independent and groups widgets by capability
/// (Primitive → Peripheral → Instrument → Board → Protocol → Custom).
///
/// Tier-gated entries (Stage Pro custom widgets contributed via the
/// [customStageWidgetRegistryProvider] extension point) render a
/// `FeatureTierBadge` next to the display name and route activation through
/// `FeatureGate.isAvailable` — during the public-beta period this
/// short-circuits to allow; post-beta, an unsatisfied tier surfaces an
/// upgrade prompt instead of adding the widget. Built-in widgets register
/// directly into `StageRegistry` and carry no badge.
///
/// Tapping an unblocked widget adds a fresh instance to the active Stage
/// panel. Empty state appears when no widgets and no custom descriptors
/// are registered.
class StageWidgetPickerDialog extends ConsumerWidget {
  const StageWidgetPickerDialog({super.key});

  /// Opens the picker as a modal dialog.
  ///
  /// Pass [tabContainer] so the picker's `stageWorkspaceProvider` writes
  /// (Add Widget) target the active tab's Stage workspace. The dialog is pushed
  /// by the root navigator, outside the per-tab [UncontrolledProviderScope], so
  /// without this it mutates the empty root workspace instead of the tab's.
  static Future<void> show(
    BuildContext context, {
    ProviderContainer? tabContainer,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) {
        const dialog = StageWidgetPickerDialog();
        return tabContainer != null
            ? UncontrolledProviderScope(container: tabContainer, child: dialog)
            : dialog;
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final customRegistry = ref.watch(customStageWidgetRegistryProvider);
    final currentTier = ref.watch(licenseTierProvider);
    final resolveName = ref.watch(stageConfigLabelResolverFactoryProvider)(
      context,
    );
    String displayNameFor(StageWidget w) => w.displayNameKey != null
        ? resolveName(w.displayNameKey!)
        : w.displayName;
    final grouped = _groupByCategory(customRegistry, displayNameFor);
    final tierById = _tierById(customRegistry);
    // Read `betaPeriodProvider` and compute the gate at the call site (see
    // `_WidgetTile._onTap`) instead of routing through `FeatureGate.isAvailable`.
    // `FeatureGate.isAvailable` short-circuits on the compile-time `crux_license`
    // `kBetaPeriod` constant — a provider override does not flip that constant,
    // so `FeatureGate`'s short-circuit always wins during beta and the
    // post-beta upgrade-dialog path is unreachable from widget tests.
    // Computing the equivalent `beta || tier.featureEquivalent.index >=
    // required.index` expression directly preserves identical runtime
    // behavior (during beta both produce true; post-beta both compare active
    // tier vs required tier — the same `featureEquivalent` mapping
    // `FeatureGate` uses) while letting `betaPeriodProvider.overrideWithValue(false)`
    // flip the gate from a test process. Mirrors `DecoderPickerDialog`.
    final beta = ref.watch(betaPeriodProvider);

    return AlertDialog(
      title: Text(l10n.stageWidgetPickerTitle),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 480,
        height: 360,
        child: grouped.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.stageWidgetPickerEmpty,
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
                child: ListView(
                  children: [
                    for (final entry in grouped.entries)
                      _StageCategorySection(
                        category: entry.key,
                        widgets: entry.value,
                        tierById: tierById,
                        currentTier: currentTier,
                        beta: beta,
                        displayNameFor: displayNameFor,
                        onTapWidget: (id) {
                          final newId = ref
                              .read(stageWorkspaceProvider.notifier)
                              .addInstance(id);
                          Navigator.of(context).pop(newId);
                        },
                      ),
                  ],
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

  /// Groups every registered widget by [StageWidgetCategory] in fixed
  /// declaration order, omitting empty categories. Within a category
  /// widgets are sorted by display name.
  ///
  /// Combines built-in widgets from [StageRegistry] with custom
  /// descriptors from [CustomStageWidgetRegistry]. Custom descriptors that
  /// reuse an existing widget id (override scenario) are deduplicated in
  /// favor of the custom contribution so tier metadata is preserved.
  Map<StageWidgetCategory, List<StageWidget>> _groupByCategory(
    CustomStageWidgetRegistry customRegistry,
    String Function(StageWidget) displayNameFor,
  ) {
    final byId = <String, StageWidget>{};
    for (final w in StageRegistry.instance.listAll()) {
      byId[w.id] = w;
    }
    for (final d in customRegistry.descriptors) {
      byId[d.widget.id] = d.widget;
    }

    final result = <StageWidgetCategory, List<StageWidget>>{};
    for (final category in StageWidgetCategory.values) {
      final entries = byId.values.where((w) => w.category == category).toList()
        ..sort((a, b) => displayNameFor(a).compareTo(displayNameFor(b)));
      if (entries.isNotEmpty) {
        result[category] = entries;
      }
    }
    return result;
  }

  /// Builds an id → required-tier map covering both built-in widgets
  /// (whose tier comes from [StageWidget.requiredTier]) and custom
  /// registry descriptors (whose tier comes from
  /// [CustomStageWidgetDescriptor.requiredTier]).
  ///
  /// Custom-registry tier wins on id collision so a vendor-supplied
  /// override of an open-core widget can lift its tier without forking
  /// the open-core widget definition.
  Map<String, LicenseTier> _tierById(CustomStageWidgetRegistry registry) {
    return {
      for (final w in StageRegistry.instance.listAll()) w.id: w.requiredTier,
      for (final d in registry.descriptors) d.widget.id: d.requiredTier,
    };
  }
}

/// One collapsible section in the Stage picker, rendering all widgets in
/// a single [StageWidgetCategory].
class _StageCategorySection extends StatelessWidget {
  const _StageCategorySection({
    required this.category,
    required this.widgets,
    required this.tierById,
    required this.currentTier,
    required this.beta,
    required this.displayNameFor,
    required this.onTapWidget,
  });

  final StageWidgetCategory category;
  final List<StageWidget> widgets;
  final Map<String, LicenseTier> tierById;
  final LicenseTier currentTier;
  final bool beta;
  final String Function(StageWidget) displayNameFor;
  final void Function(String widgetId) onTapWidget;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return ExpansionTile(
      key: ValueKey('stage_category_${category.name}'),
      leading: Icon(_iconFor(category)),
      title: Text(
        l10n.pickerCategoryHeader(_labelFor(l10n, category), widgets.length),
      ),
      childrenPadding: EdgeInsets.zero,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final widget in widgets)
          _WidgetTile(
            widget: widget,
            displayName: displayNameFor(widget),
            requiredTier: tierById[widget.id] ?? LicenseTier.openCore,
            currentTier: currentTier,
            beta: beta,
            onTap: () => onTapWidget(widget.id),
          ),
      ],
    );
  }

  static IconData _iconFor(StageWidgetCategory category) => switch (category) {
    StageWidgetCategory.primitive => Icons.lightbulb_outline,
    StageWidgetCategory.peripheral => Icons.memory_outlined,
    StageWidgetCategory.instrument => Icons.speed_outlined,
    StageWidgetCategory.board => Icons.developer_board,
    StageWidgetCategory.protocol => Icons.swap_horizontal_circle_outlined,
    StageWidgetCategory.custom => Icons.extension_outlined,
  };

  static String _labelFor(L10N l10n, StageWidgetCategory category) =>
      switch (category) {
        StageWidgetCategory.primitive => l10n.stageCategoryPrimitive,
        StageWidgetCategory.peripheral => l10n.stageCategoryPeripheral,
        StageWidgetCategory.instrument => l10n.stageCategoryInstrument,
        StageWidgetCategory.board => l10n.stageCategoryBoard,
        StageWidgetCategory.protocol => l10n.stageCategoryProtocol,
        StageWidgetCategory.custom => l10n.stageCategoryCustom,
      };
}

/// One widget row. An insufficient-tier tap is counted as `tier.gate_hit` by
/// [WaveCruxUpgradeDialog.show], when the dialog opens. The allowed path stays
/// uninstrumented here: `stage.widget_added` already counts it, from the
/// workspace notifier.
class _WidgetTile extends StatelessWidget {
  const _WidgetTile({
    required this.widget,
    required this.displayName,
    required this.requiredTier,
    required this.currentTier,
    required this.beta,
    required this.onTap,
  });

  final StageWidget widget;

  /// Locale-resolved display name for [widget] (resolves the widget's
  /// optional `displayNameKey` through the stage config-label resolver,
  /// falling back to the raw English `displayName`).
  final String displayName;
  final LicenseTier requiredTier;
  final LicenseTier currentTier;

  /// Public-beta short-circuit read from `betaPeriodProvider` by the parent
  /// dialog. Deliberately NOT re-derived from `FeatureGate.isAvailable` at
  /// the gate-check call site below so tests can flip the post-beta path by
  /// overriding `betaPeriodProvider`. See the parent dialog's `build` for
  /// the full rationale.
  final bool beta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final showBadge =
        requiredTier != LicenseTier.openCore && requiredTier != LicenseTier.edu;
    return ListTile(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(displayName)),
          if (showBadge) ...[
            const SizedBox(width: 8),
            WaveCruxFeatureTierBadge(requiredTier: requiredTier),
          ],
        ],
      ),
      subtitle: Text(
        widget.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _onTap(context),
    );
  }

  void _onTap(BuildContext context) {
    // Equivalent to `FeatureGate.isAvailable(requiredTier, currentTier)`, but
    // bypasses `FeatureGate.isAvailable`'s compile-time `kBetaPeriod`
    // short-circuit so tests can flip the gate by overriding
    // `betaPeriodProvider`. See the parent dialog's `build` for the full
    // rationale.
    final allowed =
        beta || currentTier.featureEquivalent.index >= requiredTier.index;
    if (allowed) {
      onTap();
    } else {
      _showUpgradeDialog(context);
    }
  }

  void _showUpgradeDialog(BuildContext context) {
    // The suite's gate-denial convention, and so the one countable denial.
    // Unreachable during the beta by construction — the gate above
    // short-circuits to allow — which matches telemetry's own dark launch and
    // is not dead code to be "fixed". The dialog records the hit, and only
    // when it opens, so a repeated activation counts once.
    unawaited(
      WaveCruxUpgradeDialog.show(
        context,
        featureLabel: displayName,
        requiredTier: requiredTier,
        // One closed id for this call site. NEVER `displayName`, which is
        // the locale-resolved label the dialog shows.
        gateFeatureId: 'stage_widget_pack',
      ),
    );
  }
}
