// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/auto_bind_candidate.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/inspector_providers.dart';
import 'package:wavecrux/features/viewer/widgets/wavecrux_inspector_panel.dart';
import 'package:wavecrux/services/decoders/decoder_auto_bind_service.dart';
import 'package:wavecrux/services/policy/org_decoder_settings.dart';

/// Whether the Inspector is hosted in a bottom sheet rather than the right
/// dock: on iOS and Android, where the right dock is not phone UI.
///
/// Keyed on the host platform, not the size-derived device class: a tablet
/// in a narrow split view is still a tablet with a dock. Root-scoped; a test
/// overrides it.
final inspectorInBottomSheetProvider = Provider<bool>(
  (_) =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android),
  name: 'inspectorInBottomSheetProvider',
);

/// Shows [target] in the Inspector of the tab whose container is [tab], with
/// keyboard focus on its first control.
///
/// On the desktop the right dock's Inspector tab is revealed. On iOS and
/// Android the same sections are hosted in a bottom sheet over the tab, under
/// the tab's provider container, so they read and write the tab's state.
void openWaveCruxInspector(
  BuildContext context,
  ProviderContainer tab,
  WaveCruxInspectable target,
) {
  tab.read(inspectedObjectProvider.notifier).select(target);
  if (tab.read(inspectorInBottomSheetProvider)) {
    unawaited(_showInspectorSheet(context, tab));
    return;
  }
  tab.read(inspectorControllerProvider).open();
}

Future<void> _showInspectorSheet(BuildContext context, ProviderContainer tab) {
  // Phone only: the right dock is not phone UI, so the sheet hosts the
  // dock's sections.
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => UncontrolledProviderScope(
      container: tab,
      child: SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.7,
        child: const WaveCruxInspectorPanel(),
      ),
    ),
  );
}

/// Starts adding a decoder of [definition] in the Inspector of [tab]: a
/// draft seeded from the organization's defaults and, when [autoBind] is
/// set, the auto-bind name heuristic over [autoBindSignals]. For "Apply
/// Decoder to Selection" those are the selected signals, and the binding
/// pickers offer only them; with null, every loaded signal. The draft is
/// unapplied from its first frame, so the Inspector holds it until its Add
/// or its Cancel.
void startNewDecoderInInspector(
  BuildContext context,
  ProviderContainer tab, {
  required DecoderDefinition definition,
  bool autoBind = false,
  Map<String, Variable>? autoBindSignals,
}) {
  final target = InspectedNewDecoder(definition.id);
  final draft = seedDecoderDraft(
    definition: definition,
    org: tab.read(orgDecoderSettingsProvider),
    signalsByPath:
        autoBindSignals ??
        signalsByFullPath(tab.read(signalVariablesByPathProvider)),
    autoBind: autoBind,
    offeredPaths: autoBindSignals?.keys.toSet(),
  );
  tab.read(decoderDraftsProvider.notifier).put(decoderDraftKey(target), draft);
  openWaveCruxInspector(context, tab, target);
}

/// [variables] keyed by [Variable.fullPath], so every name of an aliased
/// signal is listed (the signalRef-keyed map keeps one name per alias group).
Map<String, Variable> signalsByFullPath(Map<String, Variable> variables) => {
  for (final v in variables.values) v.fullPath: v,
};

/// A decoder draft for [definition]: [initialConfig]'s bindings (none for a
/// new decoder), every parameter under the organization's precedence rule
/// (`locked > user setting > policy default > built-in`), and with
/// [autoBind] the auto-bind heuristic's prefill. [instanceId] is null for a
/// new decoder.
DecoderDraft seedDecoderDraft({
  required DecoderDefinition definition,
  required OrgDecoderSettings org,
  required Map<String, Variable> signalsByPath,
  String? instanceId,
  DecoderConfig? initialConfig,
  bool autoBind = false,
  Set<String>? offeredPaths,
}) {
  final bindings = <String, String?>{
    for (final s in definition.requiredSignals)
      s.name: initialConfig?.signalBindings[s.name],
    for (final s in definition.optionalSignals)
      s.name: initialConfig?.signalBindings[s.name],
  };
  final paths = <String, String?>{};
  final params = <String, dynamic>{
    for (final p in definition.parameters)
      p.name: org.resolve(
        definition.id,
        p.name,
        userValue: initialConfig?.parameters[p.name],
        builtIn: p.defaultValue,
      ),
  };
  if (autoBind && instanceId == null) {
    final result = const DecoderAutoBindService().computeBindings(
      definition: definition,
      availableSignals: signalsByPath,
      currentParameters: Map<String, dynamic>.from(params),
      existingBindings: Map<String, String?>.from(bindings),
    );
    for (final entry in result.candidates.entries) {
      final candidate = entry.value;
      if (candidate.signalRef != null &&
          candidate.confidence != AutoBindConfidence.noMatch) {
        bindings[entry.key] = candidate.signalRef;
        paths[entry.key] = candidate.fullPath;
      }
    }
  }
  return DecoderDraft(
    definitionId: definition.id,
    instanceId: instanceId,
    bindings: Map<String, String?>.unmodifiable(bindings),
    bindingPaths: Map<String, String?>.unmodifiable(paths),
    params: Map<String, dynamic>.unmodifiable(params),
    initialBindings: Map<String, String?>.unmodifiable(bindings),
    initialParams: Map<String, dynamic>.unmodifiable(params),
    offeredPaths: offeredPaths,
  );
}
