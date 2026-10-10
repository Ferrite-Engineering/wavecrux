// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/interfaces/stage_auto_bind_service.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/stage/providers/stage_config_label_resolver_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_selection_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/board_auto_bind_preview_dialog.dart';
import 'package:wavecrux/features/stage/widgets/boards/arty_a7_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/signal_binding_picker_dialog.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_config_editor.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/stage_registry.dart';
import 'package:wavecrux/services/stage/stage_auto_bind_resolver.dart';

/// Right-side properties pane showing the selected stage instance's
/// signal bindings.
///
/// The pane is built only when [stageSelectedInstanceProvider] holds a
/// non-null id and the workspace contains an instance with that id.
/// Callers (the host Stage panel) decide whether to render this widget
/// by checking [stageSelectedInstanceProvider]; the widget itself
/// safely returns an empty fallback when the selection has gone stale.
class StageBindingsPane extends ConsumerWidget {
  const StageBindingsPane({super.key});

  /// Default width of the pane on tablet/desktop.
  static const double width = 260;

  /// Runs auto-bind for [instance] against the loaded waveform and shows
  /// the preview dialog. Applies the user's choice via `setBindings`
  /// (atomic — every slot updates in one state transition).
  ///
  /// [service] comes from `stageAutoBindServiceFor`, which resolves every
  /// compound board widget to the unchanged `BoardAutoBindService` and lets
  /// a non-compound widget (the RISC-V Commit Inspector) declare its own.
  ///
  /// [title] is the widget's own resolved `autoBindTitleKey`, or null to
  /// leave the dialog on its board heading. A non-board widget that let the
  /// default stand would tell the user it is about to bind "board signals",
  /// which is wrong in a way that costs trust for no reason.
  Future<void> _runAutoBind(
    BuildContext context,
    WidgetRef ref, {
    required StageInstance instance,
    required StageWidget widget,
    required StageAutoBindService service,
    String? title,
  }) async {
    // One entry per name, so auto-bind can match any name of an aliased
    // signal; the binding still stores the shared signalRef.
    final variables = ref.read(signalVariablesByPathProvider);
    final result = service.autoBind(
      widget: widget,
      availableSignals: variables,
      existingBindings: instance.signalBindings,
      configuration: instance.configuration,
    );
    final apply = await BoardAutoBindPreviewDialog.show(
      context,
      result: result,
      title: title,
    );
    if (apply == null) return;
    // Merge the auto-bind result with any existing bindings the user
    // had that the auto-bind did not touch (apply contains every slot
    // the dialog suggested binding; everything else is preserved).
    final merged = <String, StageSignalBinding>{
      ...instance.signalBindings,
      ...apply.bindings,
    };
    ref.read(stageWorkspaceProvider.notifier).setBindings(instance.id, merged);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final selectedId = ref.watch(stageSelectedInstanceProvider);
    final workspace = ref.watch(stageWorkspaceProvider);
    final resolverFactory = ref.watch(stageConfigLabelResolverFactoryProvider);

    StageInstance? instance;
    if (selectedId != null) {
      for (final p in workspace.panels) {
        for (final i in p.instances) {
          if (i.id == selectedId) {
            instance = i;
            break;
          }
        }
        if (instance != null) break;
      }
    }
    if (instance == null) {
      return const SizedBox.shrink();
    }

    final widgetDef = StageRegistry.instance.get(instance.widgetId);
    final resolveName = resolverFactory(context);
    final defName = widgetDef == null
        ? null
        : (widgetDef.displayNameKey != null
              ? resolveName(widgetDef.displayNameKey!)
              : widgetDef.displayName);
    final title = instance.label ?? defName ?? instance.widgetId;
    final autoBindService = widgetDef == null
        ? null
        : stageAutoBindServiceFor(widgetDef);
    final autoBindTitleKey = widgetDef?.autoBindTitleKey;
    final autoBindTitle = autoBindTitleKey == null
        ? null
        : resolveName(autoBindTitleKey);
    // Per-pin visibility mirrors ConfigParam.isVisibleIn: a pin with no
    // `visibleWhen` predicate is always listed (so every pre-existing widget
    // enumerates exactly as it did), while a widget whose pin count is itself
    // configurable — 2–8 pipeline stages — hides the pins for stages the
    // user has not enabled.
    final config = instance.configuration;
    final allBindings = <_PinDescriptor>[
      if (widgetDef != null)
        for (final b in widgetDef.requiredSignals)
          if (b.isVisibleIn(config))
            _PinDescriptor(
              name: b.name,
              description: resolveBindingDescription(b.description, l10n),
              optional: false,
            ),
      if (widgetDef != null)
        for (final b in widgetDef.optionalSignals)
          if (b.isVisibleIn(config))
            _PinDescriptor(
              name: b.name,
              description: resolveBindingDescription(b.description, l10n),
              optional: true,
            ),
    ];

    final hasConfig = widgetDef != null && widgetDef.configParams.isNotEmpty;

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header.
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (autoBindService != null && widgetDef != null)
                  IconButton(
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    tooltip: l10n.stageBoardAutoBindButton,
                    onPressed: () => _runAutoBind(
                      context,
                      ref,
                      instance: instance!,
                      widget: widgetDef,
                      service: autoBindService,
                      title: autoBindTitle,
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: l10n.stageBindingsPaneCloseTooltip,
                  onPressed: () =>
                      ref.read(stageSelectedInstanceProvider.notifier).clear(),
                ),
              ],
            ),
          ),
          // Body — bindings + optional configuration section, co-scrolled.
          Expanded(
            // Re-enable trackpad two-finger scroll. The app-wide
            // ScrollConfiguration (app.dart) restricts dragDevices to
            // {touch} so a 1-px mouse drift during a click can't let a
            // scroll view steal the tap; that also drops trackpad
            // pan-zoom, so this tall inspector (bindings + the widget's
            // configuration section) wouldn't scroll on a trackpad. Add
            // trackpad back here (keeping touch for tablet); mouse is
            // deliberately left out — mouse-wheel scroll uses
            // PointerScrollEvent, which bypasses dragDevices entirely,
            // and re-adding mouse-drag would reintroduce the tap-steal
            // bug the global override exists to prevent.
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: const <PointerDeviceKind>{
                  PointerDeviceKind.touch,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Bindings section heading.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: Text(
                        l10n.stageBindingsPaneHeading,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    // Bindings list (or empty state).
                    if (allBindings.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          l10n.stageInstanceNoBindings,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < allBindings.length;
                              index++
                            ) ...[
                              if (index != 0) const SizedBox(height: 4),
                              StageBindingRow(
                                instanceId: instance.id,
                                pinName: allBindings[index].name,
                                pinDescription: allBindings[index].description,
                                binding: instance
                                    .signalBindings[allBindings[index].name],
                                optional: allBindings[index].optional,
                              ),
                            ],
                          ],
                        ),
                      ),

                    // Configuration section — rendered only when the widget
                    // declares `configParams`. The generic editor reads the
                    // schema from the widget definition and two-way binds it
                    // to `instance.configuration`.
                    if (hasConfig) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        child: Text(
                          l10n.stageBindingsPaneConfigurationHeading,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      StageWidgetConfigEditor(
                        key: ValueKey(
                          'stageConfigEditor:${instance.id}',
                        ),
                        instance: instance,
                        params: widgetDef.configParams,
                        groups: widgetDef.configGroups,
                        labelResolver: resolverFactory(context),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in the bindings pane: pin label + signal ref + tap-to-pick.
///
/// Public so the host can also expose this row in compact contexts (Phase
/// 3 will reuse it inside a popover when a board's slot is targeted by a
/// drag-and-drop gesture).
class StageBindingRow extends ConsumerWidget {
  const StageBindingRow({
    required this.instanceId,
    required this.pinName,
    required this.pinDescription,
    required this.binding,
    this.optional = false,
    super.key,
  });

  final String instanceId;
  final String pinName;
  final String pinDescription;
  final StageSignalBinding? binding;
  final bool optional;

  /// Renders the bound signal label, including a `[bitIndex]` suffix
  /// when a single bit of a multi-bit signal is bound to this slot.
  ///
  /// [StageSignalBinding.signalRef] is wellen's **opaque** handle (a
  /// bare number like `"10"`), not a human path — so we resolve it back
  /// to the variable's hierarchical [Variable.fullPath] via [variables]
  /// for display. When the ref can't be resolved (e.g. a session bound
  /// against a signal absent from the currently loaded file) we fall
  /// back to the raw ref rather than showing nothing.
  String _bindingLabel(StageSignalBinding b, Map<String, Variable> variables) {
    final name = variables[b.signalRef]?.fullPath ?? b.signalRef;
    if (b.bitIndex == null) return name;
    return '$name[${b.bitIndex}]';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final variables = ref.watch(signalVariablesMapProvider);
    final currentBinding = binding;
    final isUnbound =
        currentBinding == null || currentBinding.signalRef.isEmpty;

    return DragTarget<String>(
      onAcceptWithDetails: (details) {
        ref
            .read(stageWorkspaceProvider.notifier)
            .setBinding(instanceId, pinName, details.data);
      },
      builder: (context, candidate, rejected) {
        final isDropTarget = candidate.isNotEmpty;
        return Material(
          color: isDropTarget
              ? theme.colorScheme.primary.withValues(alpha: 0.10)
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: isDropTarget
                ? BorderSide(color: theme.colorScheme.primary, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            key: ValueKey('stageBindingRow:$instanceId:$pinName'),
            onTap: () async {
              final result = await SignalBindingPickerDialog.show(
                context,
                pinName: pinName,
                pinDescription: pinDescription,
                currentSignalRef: currentBinding?.signalRef,
                tabContainer: ProviderScope.containerOf(context, listen: false),
              );
              if (result == null) return;
              ref
                  .read(stageWorkspaceProvider.notifier)
                  .setBinding(instanceId, pinName, result.signalRef);
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pinName,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (optional)
                          Text(
                            l10n.stageBindingsPaneOptionalLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isUnbound
                          ? l10n.stageInstanceUnboundLabel
                          : _bindingLabel(currentBinding, variables),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isUnbound
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                        fontStyle: isUnbound
                            ? FontStyle.italic
                            : FontStyle.normal,
                        fontFamily: isUnbound ? null : 'monospace',
                      ),
                    ),
                  ),
                  if (!isUnbound)
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        maxWidth: 24,
                        maxHeight: 24,
                      ),
                      icon: const Icon(Icons.close, size: 14),
                      tooltip: l10n.stageInstanceClearBindingTooltip,
                      onPressed: () => ref
                          .read(stageWorkspaceProvider.notifier)
                          .setBinding(instanceId, pinName, null),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

@immutable
class _PinDescriptor {
  const _PinDescriptor({
    required this.name,
    required this.description,
    required this.optional,
  });

  final String name;
  final String description;
  final bool optional;
}
