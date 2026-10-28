// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_config_section.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/inspector_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/widgets/fsm_state_names_section.dart';
import 'package:wavecrux/features/viewer/widgets/signal_format_section.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/help_link.dart';

/// The Inspector: the properties of a decoder (its signal bindings and
/// parameters) or of a signal row (its display format's Q-format knobs or
/// enum labels, and an FSM signal's state names), on the shared
/// [CruxInspector].
///
/// The right dock's on-demand Inspector tab on the desktop; a bottom sheet
/// on iOS and Android (see `openWaveCruxInspector`). Mounted inside the
/// tab's provider scope either way, so it reads and writes that tab's
/// decoders, signal rows and drafts. Escape returns focus to the waveform
/// pane.
class WaveCruxInspectorPanel extends ConsumerWidget {
  /// Creates the Inspector.
  const WaveCruxInspectorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final pro = ref.watch(proInspectorSectionsProvider);
    // The headings name decoders and rows by their current values, and a
    // decoder or row that is gone shows the empty state.
    final rows = ref.watch(signalGroupsProvider).entries;
    final decoders = ref.watch(activeDecodersProvider);
    // The FSM section shows for a row whose signal has known states.
    final fsmModel = ref.watch(fsmProvider.select((s) => s.model));
    final fsmNamed = ref.watch(fsmAnnotationProvider);
    final fsmFound = ref.watch(fsmKnownStateIdsProvider);
    final fsmDrafts = ref.watch(fsmStateNameDraftsProvider);
    bool hasFsmStates(String signalRef) => fsmStateIdsOf(
      signalRef,
      model: fsmModel,
      named: fsmNamed,
      found: fsmFound,
      draft: fsmDrafts[signalRef],
    ).isNotEmpty;
    bool exists(WaveCruxInspectable target) => switch (target) {
      InspectedDecoder(:final instanceId) => decoders.any(
        (d) => d.id == instanceId,
      ),
      InspectedNewDecoder() => true,
      InspectedSignal(:final entryId) => findSignalEntry(rows, entryId) != null,
    };
    return Material(
      color: theme.colorScheme.surface,
      child: CruxInspector<WaveCruxInspectable>(
        selection: ref.watch(inspectedObjectProvider),
        controller: ref.watch(inspectorControllerProvider),
        onEscape: () => ref.read(waveformPaneFocusNodeProvider).requestFocus(),
        emptyMessage: l10n.inspectorEmpty,
        title: (target) => _title(l10n, ref, target),
        heldMessage: (target) =>
            l10n.inspectorHeldMessage(_title(l10n, ref, target)),
        headerActions: (context, target) => <Widget>[
          if (decoderDefinitionIdOf(ref, target) case final definitionId?)
            HelpLink(
              url: HelpUrls.decoder(definitionId),
              tooltip: l10n.helpLinkDecoderDocs,
            ),
        ],
        sections: <CruxInspectorSectionBuilder<WaveCruxInspectable>>[
          (context, target) =>
              exists(target) ? decoderInspectorSection(context, target) : null,
          (context, target) =>
              exists(target) ? signalInspectorSection(context, target) : null,
          (context, target) => exists(target)
              ? fsmStateNamesInspectorSection(
                  context,
                  target,
                  rows: rows,
                  hasStates: hasFsmStates,
                )
              : null,
          ...pro,
        ],
      ),
    );
  }

  static String _title(L10N l10n, WidgetRef ref, WaveCruxInspectable target) {
    if (decoderInspectorTitle(l10n, ref, target) case final title?) {
      return title;
    }
    if (target case InspectedSignal(:final entryId)) {
      final entry = findSignalEntry(
        ref.read(signalGroupsProvider).entries,
        entryId,
      );
      if (entry != null) return entry.displayName ?? entry.signalRef ?? '';
    }
    return l10n.dockTabInspector;
  }
}
