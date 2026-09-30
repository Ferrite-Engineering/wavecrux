// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/license/tier_unlocked_provider.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_config_label_resolver_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_selection_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_renderer_registry.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/custom_stage_widget_registry_provider.dart';
import 'package:wavecrux/plugins/stage_registry.dart';
import 'package:wavecrux/shared/widgets/wavecrux_withheld_notice.dart';

/// Visual representation of one [StageInstance] inside a Stage panel.
///
/// The tile contains **only** the renderer body (the
/// signal-bound widget itself fills the available space below the
/// header). Bindings configuration moved to the right-side
/// [StageBindingsPane] that appears when an instance is selected.
///
/// Tapping the tile selects this instance (showing the bindings pane).
/// If the widget exposes exactly one input pin, the binding picker
/// opens immediately on tap so single-input widgets like LED can be
/// wired without a second click. Multi-input widgets just select on
/// tap and rely on the bindings pane for picking.
///
/// The tile must be hosted inside a [Positioned] (or other parent
/// providing bounded constraints) — the inner [Column] uses [Expanded]
/// to give the renderer the full remaining height.
///
/// **The tile asks the tier before it renders.** The Stage widget picker gates
/// adding a widget, but a session restore puts back every instance it saved,
/// and the Pro overlay registers its widgets and renderers at every tier. So a
/// widget whose tier this seat does not have (the custom registry's tier wins,
/// as it does in the picker) draws a locked body that says why instead of its
/// renderer. The instance stays in the workspace, header and all, so it can be
/// moved or removed, the next save writes it back, and an upgrade brings it
/// back without a restart: the tier is watched.
class StageInstanceTile extends ConsumerWidget {
  const StageInstanceTile({required this.instance, super.key});

  final StageInstance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final widgetDef = StageRegistry.instance.get(instance.widgetId);
    // A community-bundle widget id may not resolve yet if its async bundle
    // manager hasn't registered the definition — e.g. right after a session
    // restore on app startup. Watch the manager (only when unresolved) so the
    // tile rebuilds and re-resolves once it finishes loading, and so we can
    // show a spinner rather than the "Unknown widget" message while it loads.
    final customWidgetsLoading =
        widgetDef == null &&
        ref.watch(
          customWidgetBundleManagerProvider.select((a) => a.isLoading),
        );
    final selectedId = ref.watch(stageSelectedInstanceProvider);
    final isSelected = selectedId == instance.id;

    final resolveName = ref.watch(stageConfigLabelResolverFactoryProvider)(
      context,
    );
    final defName = widgetDef == null
        ? null
        : (widgetDef.displayNameKey != null
              ? resolveName(widgetDef.displayNameKey!)
              : widgetDef.displayName);
    final title = instance.label ?? defName ?? instance.widgetId;
    final requiredTier =
        ref
            .watch(customStageWidgetRegistryProvider)
            .get(instance.widgetId)
            ?.requiredTier ??
        widgetDef?.requiredTier ??
        LicenseTier.openCore;
    final unlocked = ref.watch(tierUnlockedProvider(requiredTier));

    final cardShape = RoundedRectangleBorder(
      side: BorderSide(
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.outlineVariant,
        width: isSelected ? 2 : 1,
      ),
      borderRadius: const BorderRadius.all(Radius.circular(6)),
    );

    return Card(
      key: ValueKey('stageInstance:${instance.id}'),
      margin: const EdgeInsets.all(4),
      clipBehavior: Clip.hardEdge,
      shape: cardShape,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            title: title,
            onRemove: () {
              ref
                  .read(stageWorkspaceProvider.notifier)
                  .removeInstance(instance.id);
            },
            removeTooltip: l10n.stageInstanceRemoveTooltip,
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              // Breathing room between the tile border and the
              // renderer's outer edge — without this, renderers that
              // draw their own bordered container (bus readout,
              // seven-segment) merge visually with the card border.
              padding: const EdgeInsets.all(4),
              child: _Body(
                instance: instance,
                widgetDef: widgetDef,
                customWidgetsLoading: customWidgetsLoading,
                withheldTier: unlocked ? null : requiredTier,
                featureLabel: defName ?? instance.widgetId,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onRemove,
    required this.removeTooltip,
  });

  final String title;
  final VoidCallback onRemove;
  final String removeTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.labelLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
            iconSize: 14,
            icon: const Icon(Icons.close),
            tooltip: removeTooltip,
            onPressed: onRemove,
          ),
          // Right-side gutter so the resize corner handle (which sits
          // at the absolute top-right of the tile) doesn't cover the
          // close button.
          const SizedBox(width: 14),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.instance,
    required this.widgetDef,
    required this.featureLabel,
    this.customWidgetsLoading = false,
    this.withheldTier,
  });

  final StageInstance instance;
  final StageWidget? widgetDef;

  /// The widget's display name, for the locked body's sentence.
  final String featureLabel;

  /// The tier this seat lacks for [widgetDef], or `null` when it may render.
  final LicenseTier? withheldTier;

  /// True when [widgetDef] is unresolved *and* the community custom-widget
  /// bundle manager is still loading — the id may resolve once it finishes,
  /// so we show a spinner rather than the "Unknown widget" error.
  final bool customWidgetsLoading;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final renderer = StageWidgetRendererRegistry.instance.get(
      instance.widgetId,
    );

    if (widgetDef == null) {
      if (customWidgetsLoading) {
        return const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          l10n.stageInstanceUnknownWidget(instance.widgetId),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    }
    final withheld = withheldTier;
    if (withheld != null) {
      return WaveCruxWithheldNotice(
        featureLabel: featureLabel,
        requiredTier: withheld,
        // The Stage picker's id: the same pack, reached through a restore
        // instead of the picker.
        gateFeatureId: 'stage_widget_pack',
      );
    }
    if (renderer != null) {
      return renderer(context, instance);
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        widgetDef!.description,
        style: theme.textTheme.bodySmall,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        maxLines: 4,
      ),
    );
  }
}
