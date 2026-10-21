// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_dock/crux_dock.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart'
    show CruxPopUpButton, CruxPopUpItem, announceCrux;
import 'package:crux_policy/crux_policy.dart' show PolicySource;
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/decoder_parameter.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/decoders/l10n/decoder_strings.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/providers/decoder_config_label_resolver_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_auto_bind_preview_dialog.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/inspector_openers.dart';
import 'package:wavecrux/features/viewer/providers/inspector_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/decoders/decoder_auto_bind_service.dart';
import 'package:wavecrux/services/policy/org_decoder_settings.dart';

/// The Inspector's decoder sections: signal bindings, then parameters, for
/// an active decoder ([InspectedDecoder]) or one being added
/// ([InspectedNewDecoder]). Null when [target] is neither or the decoder no
/// longer exists.
Widget? decoderInspectorSection(
  BuildContext context,
  WaveCruxInspectable target,
) => switch (target) {
  InspectedDecoder() || InspectedNewDecoder() => DecoderConfigSection(
    target: target,
  ),
  InspectedSignal() => null,
};

/// See [decoderInspectorSection].
///
/// Edits apply together on Apply (Add for a new decoder), which re-runs the
/// decoders once: never per keystroke. The draft lives in the tab's
/// [decoderDraftsProvider], so it outlasts the dock showing another tab;
/// while it holds unapplied edits the Inspector keeps showing this decoder.
/// A new decoder's draft is unapplied from its first frame.
class DecoderConfigSection extends ConsumerStatefulWidget {
  /// Creates the sections for [target].
  const DecoderConfigSection({required this.target, super.key});

  /// The inspected decoder.
  final WaveCruxInspectable target;

  @override
  ConsumerState<DecoderConfigSection> createState() =>
      _DecoderConfigSectionState();
}

class _DecoderConfigSectionState extends ConsumerState<DecoderConfigSection> {
  /// The organization's decoder defaults, read once per inspected decoder:
  /// a policy file that changed mid-edit would otherwise reseed fields the
  /// user is part-way through.
  late final OrgDecoderSettings _org;

  /// The loaded signals keyed by [Variable.fullPath], read once per
  /// inspected decoder: a provider update mid-gesture would rebuild the
  /// pickers and cancel a pending dropdown open.
  late final Map<String, Variable> _signals;

  /// First name (in path order) per signalRef, to show a binding whose
  /// picked name is unknown (an existing config).
  late final Map<String, String> _firstPathByRef;

  /// The seed used while no draft is kept: the decoder's stored config.
  DecoderDraft? _seed;

  /// Bumped on Revert, so the parameter fields rebuild from the seed.
  int _revision = 0;

  String get _key => decoderDraftKey(widget.target);

  @override
  void initState() {
    super.initState();
    _org = ref.read(orgDecoderSettingsProvider);
    _signals = signalsByFullPath(ref.read(signalVariablesByPathProvider));
    _firstPathByRef = <String, String>{};
    for (final path in _signals.keys.toList()..sort()) {
      _firstPathByRef.putIfAbsent(_signals[path]!.signalRef, () => path);
    }
    // A section remounted over a kept draft must hold the decoder again.
    CruxInspector.markDirty(
      context,
      dirty: ref.read(decoderDraftsProvider)[_key]?.isDirty ?? false,
    );
  }

  DecoderDraft? _currentDraft(DecoderDefinition definition) {
    final kept = ref.read(decoderDraftsProvider)[_key];
    if (kept != null) return kept;
    final target = widget.target;
    if (target is! InspectedDecoder) return null;
    final active = ref
        .read(activeDecodersProvider)
        .where((d) => d.id == target.instanceId)
        .firstOrNull;
    if (active == null) return null;
    final seed = _seed;
    if (seed != null &&
        seed.initialBindingsMatch(active.config) &&
        seed.initialParamsMatch(active.config)) {
      return seed;
    }
    return _seed = seedDecoderDraft(
      definition: definition,
      org: _org,
      signalsByPath: _signals,
      instanceId: active.id,
      initialConfig: active.config,
    );
  }

  void _put(DecoderDraft draft) {
    ref.read(decoderDraftsProvider.notifier).put(_key, draft);
  }

  /// The picker value for [name]: the name it was picked by, else the first
  /// name of its signalRef, else the raw signalRef (a binding to a signal the
  /// trace no longer has, which the row still shows rather than dropping).
  String? _pickerValueFor(DecoderDraft draft, String name) {
    final signalRef = draft.bindings[name];
    if (signalRef == null) return null;
    final picked = draft.bindingPaths[name];
    if (picked != null && _signals[picked]?.signalRef == signalRef) {
      return picked;
    }
    return _firstPathByRef[signalRef] ?? signalRef;
  }

  void _onPicked(DecoderDraft draft, String name, String? path) {
    _put(
      draft.copyWith(
        bindings: <String, String?>{
          ...draft.bindings,
          name: path == null ? null : (_signals[path]?.signalRef ?? path),
        },
        bindingPaths: <String, String?>{...draft.bindingPaths, name: path},
        showValidationError: false,
      ),
    );
  }

  void _onParam(DecoderDraft draft, String name, dynamic value) {
    _put(
      draft.copyWith(params: <String, dynamic>{...draft.params, name: value}),
    );
  }

  /// The signals the pickers and auto-bind offer: the draft's own list (the
  /// selection, for "Apply Decoder to Selection"), else every loaded one.
  Map<String, Variable> _offered(DecoderDraft draft) {
    final paths = draft.offeredPaths;
    if (paths == null) return _signals;
    return <String, Variable>{
      for (final entry in _signals.entries)
        if (paths.contains(entry.key)) entry.key: entry.value,
    };
  }

  Future<void> _runAutoBind(
    DecoderDefinition definition,
    DecoderDraft draft,
  ) async {
    // The preview is a route above the tab's provider scope; it takes every
    // value it needs here and returns its outcome.
    final outcome = await DecoderAutoBindPreviewDialog.show(
      context,
      definition: definition,
      availableSignals: _offered(draft),
      currentParameters: Map<String, dynamic>.from(draft.params),
      existingBindings: Map<String, String?>.from(draft.bindings),
    );
    if (!mounted || outcome == null) return;
    final latest = _currentDraft(definition) ?? draft;
    _put(
      latest.copyWith(
        bindings: <String, String?>{
          ...latest.bindings,
          ...outcome.appliedBindings,
        },
        bindingPaths: <String, String?>{
          ...latest.bindingPaths,
          for (final name in outcome.appliedBindings.keys)
            name: outcome.appliedPaths[name],
        },
      ),
    );
  }

  bool _allRequiredBound(DecoderDefinition definition, DecoderDraft draft) =>
      definition.requiredSignals.every(
        (s) => (draft.bindings[s.name] ?? '').isNotEmpty,
      );

  void _apply(DecoderDefinition definition) {
    final draft = _currentDraft(definition);
    if (draft == null) return;
    if (!_allRequiredBound(definition, draft)) {
      _put(draft.copyWith(showValidationError: true));
      announceCrux(context, L10N.of(context).decoderConfigValidationError);
      return;
    }
    final config = DecoderConfig(
      signalBindings: <String, String>{
        for (final entry in draft.bindings.entries)
          if (entry.value != null && entry.value!.isNotEmpty)
            entry.key: entry.value!,
      },
      parameters: Map<String, dynamic>.unmodifiable(draft.params),
    );
    final decoders = ref.read(activeDecodersProvider.notifier);
    final drafts = ref.read(decoderDraftsProvider.notifier);
    final instanceId = draft.instanceId;
    if (instanceId != null) {
      decoders.updateConfig(instanceId, config);
      drafts.discard(_key);
      _seed = null;
    } else {
      final newId = decoders.addDecoder(definition.id, config);
      drafts.discard(_key);
      ref
          .read(inspectedObjectProvider.notifier)
          .select(InspectedDecoder(newId));
    }
    unawaited(decoders.decodeAll());
  }

  void _revert() {
    ref.read(decoderDraftsProvider.notifier).discard(_key);
    if (widget.target is InspectedNewDecoder) {
      ref.read(inspectedObjectProvider.notifier).clear();
      return;
    }
    setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    ref.listen<DecoderDraft?>(
      decoderDraftsProvider.select((d) => d[_key]),
      (_, next) =>
          CruxInspector.markDirty(context, dirty: next?.isDirty ?? false),
    );
    // Rebuild on the kept draft and on the decoder's stored config.
    ref
      ..watch(decoderDraftsProvider.select((d) => d[_key]))
      ..watch(activeDecodersProvider);
    final definitionId = switch (widget.target) {
      InspectedDecoder(:final instanceId) =>
        ref
            .read(activeDecodersProvider)
            .where((d) => d.id == instanceId)
            .firstOrNull
            ?.decoderId,
      InspectedNewDecoder(:final definitionId) => definitionId,
      InspectedSignal() => null,
    };
    final definition = definitionId == null
        ? null
        : DecoderRegistry.instance.getDefinition(definitionId);
    final draft = definition == null ? null : _currentDraft(definition);
    if (definition == null || draft == null) return const SizedBox.shrink();

    final resolveLabel = ref.watch(decoderConfigLabelResolverFactoryProvider)(
      context,
    );
    final dirty = draft.isDirty;
    final applyBar = CruxInspectorApplyBar(
      applyLabel: draft.isNew
          ? l10n.decoderConfigAddButton
          : l10n.decoderConfigUpdateButton,
      revertLabel: draft.isNew
          ? l10n.decoderConfigCancelButton
          : l10n.inspectorRevert,
      onApply: dirty ? () => _apply(definition) : null,
      onRevert: dirty ? _revert : null,
    );
    final validation = draft.showValidationError
        ? Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.decoderConfigValidationError,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          )
        : null;
    final hasParameters = definition.parameters.isNotEmpty;
    final offered = _offered(draft);

    final bindings = CruxInspectorSection(
      title: l10n.decoderConfigSignalBindingsSection,
      onSubmit: dirty ? () => _apply(definition) : null,
      footer: hasParameters
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[?validation, applyBar],
            ),
      children: <Widget>[
        _AutoBindButton(
          enabled: offered.isNotEmpty,
          onPressed: () => unawaited(_runAutoBind(definition, draft)),
        ),
        for (final (signal, required) in <(SignalBinding, bool)>[
          for (final s in definition.requiredSignals) (s, true),
          for (final s in definition.optionalSignals) (s, false),
        ])
          _SignalBindingRow(
            decoderId: definition.id,
            signalBinding: signal,
            isRequired: required,
            currentValue: _pickerValueFor(draft, signal.name),
            expectedWidth: const DecoderAutoBindService().expectedWidthFor(
              binding: signal,
              currentParameters: draft.params,
              definition: definition,
            ),
            signalMap: offered,
            onChanged: (v) => _onPicked(draft, signal.name, v),
          ),
      ],
    );
    if (!hasParameters) return bindings;

    final parameters = CruxInspectorSection(
      title: l10n.decoderConfigParametersSection,
      onSubmit: dirty ? () => _apply(definition) : null,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[?validation, applyBar],
      ),
      children: <Widget>[
        for (final p in definition.parameters)
          _ParameterRow(
            key: ValueKey<String>('decoderParam-${p.name}-$_revision'),
            decoderId: definition.id,
            parameter: p,
            value: draft.params[p.name],
            resolveLabel: resolveLabel,
            // Locked, not hidden: support can ask what the value is, and a
            // control that invites an edit which does nothing is worse than
            // one that is plainly unavailable.
            lockedByPolicy: _org.isLocked(definition.id, p.name),
            onChanged: (v) => _onParam(draft, p.name, v),
          ),
      ],
    );
    // ScrollConfiguration keeps a 1 px mouse drift during a click from being
    // taken as a drag by the Inspector's list, which would cancel the
    // dropdown's tap before its menu opens. Wheel scrolling is unaffected.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: const <PointerDeviceKind>{PointerDeviceKind.touch},
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[bindings, const Divider(height: 24), parameters],
      ),
    );
  }
}

extension on DecoderDraft {
  bool initialBindingsMatch(DecoderConfig config) => initialBindings.entries
      .every((e) => config.signalBindings[e.key] == e.value);

  bool initialParamsMatch(DecoderConfig config) => initialParams.entries.every(
    (e) =>
        !config.parameters.containsKey(e.key) ||
        config.parameters[e.key] == e.value,
  );
}

// ── Auto-bind button ──────────────────────────────────────────────────────────

class _AutoBindButton extends StatelessWidget {
  const _AutoBindButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final tooltip = enabled
        ? l10n.decoderConfigAutoBindButtonTooltip
        : l10n.decoderAutoBindNoSignalsLoaded;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Tooltip(
        message: tooltip,
        // Manual trigger keeps long-press from competing with a context menu.
        triggerMode: TooltipTriggerMode.manual,
        child: TextButton.icon(
          onPressed: enabled ? onPressed : null,
          icon: const Icon(Icons.auto_fix_high, size: 18),
          label: Text(l10n.decoderConfigAutoBindButton),
        ),
      ),
    );
  }
}

// ── Signal binding row ────────────────────────────────────────────────────────

class _SignalBindingRow extends StatelessWidget {
  const _SignalBindingRow({
    required this.decoderId,
    required this.signalBinding,
    required this.isRequired,
    required this.currentValue,
    required this.expectedWidth,
    required this.signalMap,
    required this.onChanged,
  });

  final String decoderId;
  final SignalBinding signalBinding;
  final bool isRequired;

  /// The selected [Variable.fullPath], or a raw signalRef the trace does not
  /// resolve.
  final String? currentValue;

  /// Width a signal must have to be offered, or `null` for any width.
  final int? expectedWidth;

  /// Available signals keyed by [Variable.fullPath].
  final Map<String, Variable> signalMap;

  /// Called with the picked [Variable.fullPath] (or `null` for none).
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final sortedPaths =
        signalMap.keys
            .where(
              (path) =>
                  expectedWidth == null ||
                  signalMap[path]?.bitWidth == expectedWidth,
            )
            .toList()
          ..sort();
    // The current binding must be exactly one item, or the pop-up shows its
    // placeholder instead of it. A reconfigured decoder can name a signal the width filter
    // excludes, or one the trace no longer has: list it first so it stays
    // visible and selectable.
    final dropdownValues = [
      if (currentValue != null && !sortedPaths.contains(currentValue))
        currentValue!,
      ...sortedPaths,
    ];
    final description = DecoderStrings.signalDescription(
      l10n,
      decoderId,
      signalBinding.name,
      signalBinding.description,
    );
    return CruxFormRow(
      label: signalBinding.name,
      help: isRequired
          ? '${l10n.decoderConfigRequiredLabel}. $description'
          : description,
      // The row label names the pop-up, so it takes no label of its own.
      child: CruxPopUpButton<String?>(
        value: currentValue,
        items: [
          if (!isRequired)
            CruxPopUpItem<String?>(
              value: null,
              label: l10n.decoderConfigSelectSignal,
            ),
          for (final value in dropdownValues)
            CruxPopUpItem<String?>(value: value, label: value),
        ],
        placeholder: l10n.decoderConfigSelectSignal,
        expand: true,
        valueStyle: const TextStyle(fontFamily: 'monospace'),
        onChanged: onChanged,
      ),
    );
  }
}

// ── Parameter row ─────────────────────────────────────────────────────────────

class _ParameterRow extends StatelessWidget {
  const _ParameterRow({
    required this.decoderId,
    required this.parameter,
    required this.value,
    required this.resolveLabel,
    required this.onChanged,
    this.lockedByPolicy = false,
    super.key,
  });

  final String decoderId;
  final DecoderParameter parameter;
  final dynamic value;

  /// Resolves an ARB key declared on [parameter] to a localized string.
  final DecoderConfigLabelResolver resolveLabel;

  final ValueChanged<dynamic> onChanged;

  /// Whether the organization's policy file fixes this parameter (the key is
  /// locked and names this parameter).
  final bool lockedByPolicy;

  String _label(L10N l10n) => parameter.labelKey != null
      ? resolveLabel(parameter.labelKey!)
      : DecoderStrings.paramName(
          l10n,
          decoderId,
          parameter.name,
          parameter.displayName ?? parameter.name,
        );

  String _description(L10N l10n) => parameter.descriptionKey != null
      ? resolveLabel(parameter.descriptionKey!)
      : DecoderStrings.paramDescription(
          l10n,
          decoderId,
          parameter.name,
          parameter.description,
        );

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final label = _label(l10n);
    if (parameter.type == DecoderParameterType.boolean) {
      // A checkbox, not a switch: the form applies on Apply. The lock note
      // sits below the row, as for every other input.
      return CruxPolicyLock(
        source: lockedByPolicy
            ? PolicySource.policyLocked
            : PolicySource.userSetting,
        placement: CruxPolicyLockNotePlacement.below,
        child: CruxFormRow.checkbox(
          label: label,
          help: _description(l10n),
          value: (value as bool?) ?? false,
          onChanged: onChanged,
        ),
      );
    }
    return CruxFormRow(
      label: label,
      help: _description(l10n),
      // The shared lock dims the input and takes it out of pointer and
      // focus, rather than each input's own disable spelling.
      child: CruxPolicyLock(
        source: lockedByPolicy
            ? PolicySource.policyLocked
            : PolicySource.userSetting,
        placement: CruxPolicyLockNotePlacement.below,
        child: _buildInput(),
      ),
    );
  }

  Widget _buildInput() {
    switch (parameter.type) {
      case DecoderParameterType.boolean:
        return const SizedBox.shrink();
      case DecoderParameterType.enumeration:
        return CruxPopUpButton<String>(
          value: value as String?,
          items: [
            for (final e in parameter.enumValues ?? <String>[])
              CruxPopUpItem<String>(
                value: e,
                label: parameter.enumLabelKeys?[e] != null
                    ? resolveLabel(parameter.enumLabelKeys![e]!)
                    : (parameter.enumLabels?[e] ?? e),
              ),
          ],
          onChanged: onChanged,
          expand: true,
        );
      case DecoderParameterType.integer:
        return TextFormField(
          initialValue: value?.toString(),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (s) {
            final parsed = int.tryParse(s);
            if (parsed != null) onChanged(parsed);
          },
          decoration: const InputDecoration(isDense: true),
        );
      case DecoderParameterType.string:
        return TextFormField(
          initialValue: value?.toString(),
          onChanged: onChanged,
          decoration: const InputDecoration(isDense: true),
        );
    }
  }
}

/// The Inspector heading for [target]'s decoder, or null when it is not a
/// decoder.
String? decoderInspectorTitle(
  L10N l10n,
  WidgetRef ref,
  WaveCruxInspectable target,
) {
  switch (target) {
    case InspectedDecoder(:final instanceId):
      final active = ref
          .read(activeDecodersProvider)
          .where((d) => d.id == instanceId)
          .firstOrNull;
      if (active == null) return null;
      final definition = DecoderRegistry.instance.getDefinition(
        active.decoderId,
      );
      final name = DecoderStrings.decoderName(
        l10n,
        active.decoderId,
        definition?.displayName ?? active.decoderId,
      );
      return l10n.inspectorDecoderTitle(name, active.instanceNumber);
    case InspectedNewDecoder(:final definitionId):
      final definition = DecoderRegistry.instance.getDefinition(definitionId);
      return l10n.decoderConfigTitle(
        DecoderStrings.decoderName(
          l10n,
          definitionId,
          definition?.displayName ?? definitionId,
        ),
      );
    case InspectedSignal():
      return null;
  }
}

/// The definition id of [target]'s decoder, for its documentation link.
String? decoderDefinitionIdOf(WidgetRef ref, WaveCruxInspectable target) =>
    switch (target) {
      InspectedDecoder(:final instanceId) =>
        ref
            .read(activeDecodersProvider)
            .where((d) => d.id == instanceId)
            .firstOrNull
            ?.decoderId,
      InspectedNewDecoder(:final definitionId) => definitionId,
      InspectedSignal() => null,
    };
