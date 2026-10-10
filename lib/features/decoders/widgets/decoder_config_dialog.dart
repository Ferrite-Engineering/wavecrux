// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/models/auto_bind_candidate.dart';
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
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/decoders/decoder_auto_bind_service.dart';
import 'package:wavecrux/services/policy/org_decoder_settings.dart';
import 'package:wavecrux/shared/widgets/confirm_discard_changes.dart';
import 'package:wavecrux/shared/widgets/help_link.dart';

/// Modal dialog for configuring a specific protocol decoder instance.
///
/// Displays required and optional signal binding dropdowns (populated from
/// the loaded waveform hierarchy) and parameter input fields generated from
/// [DecoderDefinition.parameters]. Validates that all required bindings are
/// assigned before adding the decoder via [ActiveDecodersNotifier].
///
/// Pass [instanceId] and [initialConfig] to open the dialog in *edit* mode,
/// which pre-fills the form with the existing bindings and parameters.  On
/// confirm it calls [ActiveDecodersNotifier.updateConfig] instead of
/// [ActiveDecodersNotifier.addDecoder].
class DecoderConfigDialog extends ConsumerStatefulWidget {
  const DecoderConfigDialog({
    required this.definition,
    this.instanceId,
    this.instanceNumber,
    this.initialConfig,
    this.signalMap,
    this.decodersNotifier,
    this.autoBindOnOpen = false,
    super.key,
  });

  final DecoderDefinition definition;

  /// Non-null in edit mode — the [ActiveDecoder.id] being reconfigured.
  final String? instanceId;

  /// Non-null in edit mode — the [ActiveDecoder.instanceNumber] used for title.
  final int? instanceNumber;

  /// Non-null in edit mode — pre-fills the form with existing bindings/params.
  final DecoderConfig? initialConfig;

  /// Pre-computed signal map from the per-tab provider scope. Dialogs are
  /// rendered in a Navigator context that sits above the per-tab
  /// UncontrolledProviderScope, so provider reads inside the dialog resolve
  /// from the root container (no file loaded). Passing the map here avoids
  /// that Navigator-scope gap. When null, falls back to reading the provider
  /// (e.g. in edit mode opened from within the tab scope).
  ///
  /// Only the values are read, and the pickers list one entry per
  /// [Variable.fullPath]. Pass `signalVariablesByPathProvider` (one entry per
  /// name) rather than `signalVariablesMapProvider`, whose signalRef keys keep
  /// one name per alias group and would hide the others.
  final Map<String, Variable>? signalMap;

  /// Pre-captured [ActiveDecodersNotifier] from the per-tab provider scope.
  ///
  /// Dialog routes are children of the Navigator, which sits above the
  /// per-tab [UncontrolledProviderScope]. Without this, [_submit] would write
  /// to the root container's [activeDecodersProvider] instead of the
  /// correct tab's — so [TransactionTablePanel] would never see the decoder.
  /// Callers read the notifier from the tab container *before* pushing the
  /// dialog route and pass it here; [_submit] uses it directly.
  final ActiveDecodersNotifier? decodersNotifier;

  /// When true (add mode only), runs the auto-bind name heuristic against
  /// [signalMap] once on open and pre-fills every binding it can resolve —
  /// so a "apply decoder to selection" gesture lands in a dialog whose
  /// dropdowns are already best-guess mapped. The user reviews the prefill
  /// in the dropdowns themselves; the Auto-bind button (with its confidence
  /// preview) remains available to re-run or refine.
  final bool autoBindOnOpen;

  bool get _isEditMode => instanceId != null;

  /// Binds the launching context's [ProviderContainer] to the dialog subtree.
  ///
  /// A dialog route is a child of the Navigator, which sits **above** the
  /// per-tab [UncontrolledProviderScope] — so a `ref` inside the dialog
  /// resolves the ROOT container, where no file is loaded. Reading
  /// `activeDecodersProvider` there writes the edit to a notifier no tab
  /// watches: no error, no visible change, the tab keeps its old config.
  ///
  /// [signalMap] and [decodersNotifier] let a caller pre-read from its own
  /// per-tab `ref` instead, and most callers do — but they are *optional*,
  /// and the `??` fallbacks behind them are what actually leaked. A caller
  /// that simply omitted an argument got the root container silently, which
  /// is exactly how the transaction-table site shipped broken (fixed in
  /// `22231934`). Fixing that one caller did not close the class: the next
  /// call site added would reintroduce it just as quietly.
  ///
  /// Binding the container here closes it. The fallbacks now resolve the
  /// launching tab's container, so omitting an argument is no longer a bug,
  /// and a new call site cannot reintroduce the leak by forgetting one.
  ///
  /// `listen: false` because this reads the container once at route-push
  /// time; the dialog is not rebuilt when an ancestor scope changes.
  static Widget _scoped(BuildContext launchContext, Widget child) =>
      UncontrolledProviderScope(
        container: ProviderScope.containerOf(launchContext, listen: false),
        child: child,
      );

  /// Opens [DecoderConfigDialog] as a modal dialog for [definition] (add mode).
  ///
  /// [signalMap] and [decodersNotifier] may be pre-read from the per-tab
  /// provider scope; when omitted they resolve from the launching context's
  /// container, which [_scoped] binds to the dialog subtree.
  static Future<void> show(
    BuildContext context, {
    required DecoderDefinition definition,
    Map<String, Variable>? signalMap,
    ActiveDecodersNotifier? decodersNotifier,
    bool autoBindOnOpen = false,
  }) {
    return showDialog<void>(
      context: context,
      // Editor dialogs hold in-progress user input: closing must be a
      // deliberate act (Cancel / Save), never a stray scrim click — the
      // suite-wide dialog rule. Note this
      // also disables Escape (Flutter routes DismissIntent through the
      // barrier flag).
      barrierDismissible: false,
      builder: (_) => _scoped(
        context,
        DecoderConfigDialog(
          definition: definition,
          signalMap: signalMap,
          decodersNotifier: decodersNotifier,
          autoBindOnOpen: autoBindOnOpen,
        ),
      ),
    );
  }

  /// Opens [DecoderConfigDialog] pre-filled for editing an existing instance.
  ///
  /// Scoped the same way as [show] — see [_scoped].
  static Future<void> showEdit(
    BuildContext context, {
    required DecoderDefinition definition,
    required String instanceId,
    required int instanceNumber,
    required DecoderConfig initialConfig,
    Map<String, Variable>? signalMap,
    ActiveDecodersNotifier? decodersNotifier,
  }) {
    return showDialog<void>(
      context: context,
      // Editor dialogs hold in-progress user input: closing must be a
      // deliberate act (Cancel / Save), never a stray scrim click — the
      // suite-wide dialog rule. Note this
      // also disables Escape (Flutter routes DismissIntent through the
      // barrier flag).
      barrierDismissible: false,
      builder: (_) => _scoped(
        context,
        DecoderConfigDialog(
          definition: definition,
          instanceId: instanceId,
          instanceNumber: instanceNumber,
          initialConfig: initialConfig,
          signalMap: signalMap,
          decodersNotifier: decodersNotifier,
        ),
      ),
    );
  }

  @override
  ConsumerState<DecoderConfigDialog> createState() =>
      _DecoderConfigDialogState();
}

class _DecoderConfigDialogState extends ConsumerState<DecoderConfigDialog> {
  /// The organization's decoder defaults, read once at open.
  ///
  /// Read rather than watched: a policy file that changed mid-dialog would
  /// otherwise reseed fields the user is part-way through editing, which is a
  /// worse failure than a stale default in a dialog that lives for seconds.
  late final OrgDecoderSettings _orgSettings;

  /// Current signal binding selections: logical name → signalRef or null.
  late final Map<String, String?> _bindings;

  /// The name each binding was picked by: logical name → [Variable.fullPath].
  ///
  /// Aliased names share one signalRef, so [_bindings] alone cannot say which
  /// of them the user chose. Display only: the binding stores the signalRef.
  final Map<String, String?> _bindingPaths = {};

  /// First name (in path order) for each signalRef, used to show a binding
  /// that has no entry in [_bindingPaths] (an existing config, a manual
  /// binding the auto-bind passed through).
  late final Map<String, String> _firstPathByRef;

  /// Current parameter values: parameter name → current value.
  late final Map<String, dynamic> _params;

  /// Snapshot of available signals taken when the dialog opens, keyed by
  /// [Variable.fullPath] so every name of an aliased signal is listed.
  ///
  /// Using ref.read (not ref.watch) so that provider updates triggered by
  /// the canvas or signal loading don't cause mid-gesture rebuilds of the
  /// DropdownButton widgets, which would cancel pending dropdown opens.
  late final Map<String, Variable> _signalMap;

  /// Snapshots of [_bindings] / [_params] as the dialog opened (taken
  /// *after* any auto-bind prefill, so only user edits count as dirty).
  late final Map<String, String?> _initialBindings;
  late final Map<String, dynamic> _initialParams;

  String? _validationError;

  Future<void> _runAutoBind() async {
    final outcome = await DecoderAutoBindPreviewDialog.show(
      context,
      definition: widget.definition,
      availableSignals: _signalMap,
      currentParameters: Map<String, dynamic>.from(_params),
      existingBindings: Map<String, String?>.from(_bindings),
    );
    if (!mounted || outcome == null) return;
    setState(() {
      for (final entry in outcome.appliedBindings.entries) {
        _bindings[entry.key] = entry.value;
        _bindingPaths[entry.key] = outcome.appliedPaths[entry.key];
      }
    });
  }

  /// The picker value for [name]: the name it was picked by, else the first
  /// name of its signalRef, else the raw signalRef (a binding to a signal the
  /// trace no longer has, which the row still shows rather than dropping).
  String? _pickerValueFor(String name) {
    final signalRef = _bindings[name];
    if (signalRef == null) return null;
    final picked = _bindingPaths[name];
    if (picked != null && _signalMap[picked]?.signalRef == signalRef) {
      return picked;
    }
    return _firstPathByRef[signalRef] ?? signalRef;
  }

  /// The width [binding]'s picker filters by under the current parameters,
  /// the same width auto-bind matches: a parameter-driven width (a plugin's
  /// `width_param`, or an AXI / APB data or address width) or the literal
  /// [SignalBinding.bitWidth].
  int? _expectedWidth(SignalBinding binding) =>
      const DecoderAutoBindService().expectedWidthFor(
        binding: binding,
        currentParameters: _params,
        definition: widget.definition,
      );

  void _onPicked(String name, String? value) {
    setState(() {
      _bindingPaths[name] = value;
      _bindings[name] = value == null
          ? null
          : (_signalMap[value]?.signalRef ?? value);
    });
  }

  @override
  void initState() {
    super.initState();
    final def = widget.definition;
    final initial = widget.initialConfig;
    _bindings = {
      for (final s in def.requiredSignals)
        s.name: initial?.signalBindings[s.name],
      for (final s in def.optionalSignals)
        s.name: initial?.signalBindings[s.name],
    };
    // The organization's decoder defaults, at the one place the
    // precedence rule is expressible: `locked > user setting > policy default
    // > built-in`. Unlocked, the org value replaces the decoder's own default
    // so a fresh decoder starts right; locked, it wins outright, because a
    // lock that yielded to a saved session would be a lock in name only.
    //
    // With no policy file this resolves to the built-in on every parameter and
    // the dialog behaves byte-for-byte as it did before the key had a reader.
    _orgSettings = ref.read(orgDecoderSettingsProvider);
    _params = {
      for (final p in def.parameters)
        p.name: _orgSettings.resolve(
          def.id,
          p.name,
          userValue: initial?.parameters[p.name],
          builtIn: p.defaultValue,
        ),
    };
    // Use the pre-captured map when provided (avoids the Navigator-scope gap
    // where dialog contexts are above the per-tab UncontrolledProviderScope).
    final available =
        widget.signalMap ??
        ref.read<Map<String, Variable>>(signalVariablesByPathProvider);
    _signalMap = {for (final v in available.values) v.fullPath: v};
    _firstPathByRef = {};
    for (final path in _signalMap.keys.toList()..sort()) {
      _firstPathByRef.putIfAbsent(_signalMap[path]!.signalRef, () => path);
    }

    if (widget.autoBindOnOpen && !widget._isEditMode) {
      final result = const DecoderAutoBindService().computeBindings(
        definition: def,
        availableSignals: _signalMap,
        currentParameters: Map<String, dynamic>.from(_params),
        existingBindings: Map<String, String?>.from(_bindings),
      );
      for (final entry in result.candidates.entries) {
        final candidate = entry.value;
        if (candidate.signalRef != null &&
            candidate.confidence != AutoBindConfidence.noMatch) {
          _bindings[entry.key] = candidate.signalRef;
          _bindingPaths[entry.key] = candidate.fullPath;
        }
      }
    }

    _initialBindings = Map<String, String?>.from(_bindings);
    _initialParams = Map<String, dynamic>.from(_params);
  }

  /// Whether any binding or parameter differs from the state the
  /// dialog opened with. Clean forms close without a prompt; dirty
  /// ones confirm first (suite unsaved-changes canon — see
  /// [confirmDiscardChanges]).
  bool get _isDirty =>
      !mapEquals(_bindings, _initialBindings) ||
      !mapEquals(_params, _initialParams);

  Future<void> _onCancel() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final confirmed = await confirmDiscardChanges(context);
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop();
  }

  bool get _allRequiredBound => widget.definition.requiredSignals.every(
    (s) => (_bindings[s.name] ?? '').isNotEmpty,
  );

  void _submit() {
    if (!_allRequiredBound) {
      setState(() {
        _validationError = L10N.of(context).decoderConfigValidationError;
      });
      return;
    }

    final config = DecoderConfig(
      signalBindings: {
        for (final entry in _bindings.entries)
          if (entry.value != null && entry.value!.isNotEmpty)
            entry.key: entry.value!,
      },
      parameters: Map.unmodifiable(_params),
    );

    // Dart infers the ?? expression as nullable when the right side comes from
    // Riverpod ref.read; the explicit annotation is the fix.
    // ignore: omit_local_variable_types
    final ActiveDecodersNotifier notifier =
        widget.decodersNotifier ?? ref.read(activeDecodersProvider.notifier);
    if (widget._isEditMode) {
      notifier.updateConfig(widget.instanceId!, config);
    } else {
      notifier.addDecoder(widget.definition.id, config);
    }
    unawaited(notifier.decodeAll());

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final def = widget.definition;
    final signalMap = _signalMap;
    // ARB-key resolver for decoder parameter labels/descriptions/enum values.
    // The Pro overlay overrides this provider to also resolve Pro decoder keys.
    final resolveLabel = ref.watch(decoderConfigLabelResolverFactoryProvider)(
      context,
    );

    final localizedName = DecoderStrings.decoderName(
      l10n,
      def.id,
      def.displayName,
    );
    final title = widget._isEditMode
        ? l10n.decoderConfigEditTitle(localizedName, widget.instanceNumber!)
        : l10n.decoderConfigTitle(localizedName);

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(title)),
          HelpLink(
            url: HelpUrls.decoder(def.id),
            tooltip: l10n.helpLinkDecoderDocs,
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        // ScrollConfiguration removes PointerDeviceKind.mouse from dragDevices.
        // On desktop, kPrecisePointerPanSlop is 1px, so the scroll view's
        // VerticalDragGestureRecognizer would win the gesture arena on any
        // 1-pixel cursor drift during a click, cancelling the DropdownButton
        // tap before the dropdown route can open.  Mouse-wheel scrolling uses
        // PointerScrollEvent (a separate path) and is unaffected.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: const <PointerDeviceKind>{PointerDeviceKind.touch},
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Auto-bind button ──────────────────────────────────────
                _AutoBindButton(
                  enabled: signalMap.isNotEmpty,
                  onPressed: _runAutoBind,
                ),
                // ── Signal bindings ───────────────────────────────────────
                _SectionHeader(label: l10n.decoderConfigSignalBindingsSection),
                ...def.requiredSignals.map(
                  (s) => _SignalBindingRow(
                    decoderId: def.id,
                    signalBinding: s,
                    isRequired: true,
                    currentValue: _pickerValueFor(s.name),
                    expectedWidth: _expectedWidth(s),
                    signalMap: signalMap,
                    onChanged: (v) => _onPicked(s.name, v),
                  ),
                ),
                ...def.optionalSignals.map(
                  (s) => _SignalBindingRow(
                    decoderId: def.id,
                    signalBinding: s,
                    isRequired: false,
                    currentValue: _pickerValueFor(s.name),
                    expectedWidth: _expectedWidth(s),
                    signalMap: signalMap,
                    onChanged: (v) => _onPicked(s.name, v),
                  ),
                ),
                // ── Parameters ────────────────────────────────────────────
                if (def.parameters.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _SectionHeader(label: l10n.decoderConfigParametersSection),
                  ...def.parameters.map(
                    (p) => _ParameterRow(
                      decoderId: def.id,
                      parameter: p,
                      value: _params[p.name],
                      resolveLabel: resolveLabel,
                      // Locked, not hidden. Support has to be able to ask the
                      // engineer on the phone what the value is, and a
                      // control that invites an edit which does nothing is
                      // worse than one that is plainly unavailable.
                      lockedByPolicy: _orgSettings.isLocked(def.id, p.name),
                      onChanged: (v) => setState(() => _params[p.name] = v),
                    ),
                  ),
                ],
                // ── Validation error ──────────────────────────────────────
                if (_validationError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _validationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _onCancel,
          child: Text(l10n.decoderConfigCancelButton),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(
            widget._isEditMode
                ? l10n.decoderConfigUpdateButton
                : l10n.decoderConfigAddButton,
          ),
        ),
      ],
    );
  }
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: tooltip,
          // Manual trigger keeps long-press from competing with any
          // PlatformContextMenu the row might pick up later, per
          // ARCHITECTURE.md §3.1.8.5.
          triggerMode: TooltipTriggerMode.manual,
          child: TextButton.icon(
            onPressed: enabled ? onPressed : null,
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: Text(l10n.decoderConfigAutoBindButton),
          ),
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
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

    // The current binding must always be representable as exactly one dropdown
    // item, or DropdownButton asserts ("exactly one item with value X"). When
    // reconfiguring an existing decoder, `currentValue` can reference a signal
    // that the bitWidth filter above excludes (or one absent from `signalMap`
    // entirely if the trace changed), which would leave `value` matching zero
    // items. Surface it as a leading item so the existing binding stays visible
    // and selectable rather than crashing the dialog. See issue #47.
    final dropdownValues = [
      if (currentValue != null && !sortedPaths.contains(currentValue))
        currentValue!,
      ...sortedPaths,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        signalBinding.name,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    if (isRequired) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          l10n.decoderConfigRequiredLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  DecoderStrings.signalDescription(
                    l10n,
                    decoderId,
                    signalBinding.name,
                    signalBinding.description,
                  ),
                  style: Theme.of(context).textTheme.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<String>(
              value: currentValue,
              hint: Text(
                l10n.decoderConfigSelectSignal,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              isExpanded: true,
              items: [
                if (!isRequired)
                  DropdownMenuItem<String>(
                    child: Text(
                      l10n.decoderConfigSelectSignal,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ...dropdownValues.map(
                  (value) => DropdownMenuItem<String>(
                    value: value,
                    child: Text(
                      value,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
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
  });

  final String decoderId;
  final DecoderParameter parameter;
  final dynamic value;

  /// Resolves an ARB key declared on [parameter] to a localized string.
  final DecoderConfigLabelResolver resolveLabel;

  final ValueChanged<dynamic> onChanged;

  /// Whether the organization's policy file fixes this parameter.
  ///
  /// True only when the key is locked **and** names this parameter: locking
  /// `decoderSettings` fixes the values written in it, not every parameter of
  /// every decoder.
  final bool lockedByPolicy;

  /// Localized parameter label. Prefers the model's [DecoderParameter.labelKey]
  /// ARB-key indirection; falls back to the [DecoderStrings] per-decoder switch
  /// (which itself falls back to displayName / name for plugin decoders).
  String _label(L10N l10n) => parameter.labelKey != null
      ? resolveLabel(parameter.labelKey!)
      : DecoderStrings.paramName(
          l10n,
          decoderId,
          parameter.name,
          parameter.displayName ?? parameter.name,
        );

  /// Localized parameter description, with the same labelKey-first fallback.
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label(l10n),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  _description(l10n),
                  style: Theme.of(context).textTheme.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // `IgnorePointer` plus `Opacity` rather than each input's own
                // `enabled`/`onChanged: null`: the five input types below take
                // five different disable spellings, and one wrapper cannot be
                // got wrong for a type somebody adds later.
                Opacity(
                  opacity: lockedByPolicy ? 0.6 : 1,
                  child: IgnorePointer(
                    ignoring: lockedByPolicy,
                    child: _buildInput(context),
                  ),
                ),
                if (lockedByPolicy)
                  CruxPolicyLockNote(
                    message: l10n.decoderParameterLockedByPolicy,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(BuildContext context) {
    switch (parameter.type) {
      case DecoderParameterType.boolean:
        return Align(
          alignment: Alignment.centerLeft,
          child: Switch(
            value: (value as bool?) ?? false,
            onChanged: onChanged,
          ),
        );
      case DecoderParameterType.enumeration:
        return DropdownButton<String>(
          value: value as String?,
          isExpanded: true,
          items: (parameter.enumValues ?? <String>[])
              .map(
                (e) => DropdownMenuItem<String>(
                  value: e,
                  child: Text(
                    parameter.enumLabelKeys?[e] != null
                        ? resolveLabel(parameter.enumLabelKeys![e]!)
                        : (parameter.enumLabels?[e] ?? e),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
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
