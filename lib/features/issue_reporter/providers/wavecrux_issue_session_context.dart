// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/diagnostics/providers/file_stats_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

/// Attribute key carrying the open-tab count to a `*-pro` data provider.
const String kWavecruxIssueAttrOpenTabs = 'openTabCount';

/// Attribute key carrying the active tab's waveform format name (or `null`).
const String kWavecruxIssueAttrActiveFileFormat = 'activeFileFormat';

/// Attribute key carrying the active tab's total signal count.
const String kWavecruxIssueAttrActiveSignalCount = 'activeSignalCount';

/// Attribute key carrying the sorted registry ids of decoders active on the
/// current tab. A fixed vocabulary — never a user-supplied signal path.
const String kWavecruxIssueAttrActiveDecoderIds = 'activeDecoderIds';

/// Attribute key carrying the sorted registry ids of the active decoders whose
/// [LicenseTier] is above open core, so the Pro overlay can surface a "Pro
/// State" category only when a Pro/Enterprise decoder is actually in use.
const String kWavecruxIssueAttrProDecoderIds = 'proDecoderIds';

/// Attribute key carrying the number of Stage panels on the active tab.
const String kWavecruxIssueAttrStagePanelCount = 'stagePanelCount';

/// Attribute key carrying the sorted, de-duplicated Stage widget type ids
/// present across the active tab's Stage panels.
const String kWavecruxIssueAttrStageWidgetTypes = 'stageWidgetTypes';

/// Builds WaveCrux's privacy-scrubbed [CruxIssueSessionContext] — the product
/// seam of the shared beta issue reporter.
///
/// **Privacy contract.** Every rendered field is a count, a format name, or a
/// decoder *display* name. Nothing here is derived from the user's filesystem
/// or from the values inside their waveform: no file paths, no decoder
/// configuration values, no bound signal paths. The sibling test asserts the
/// rendered Session State body contains no path separator.
///
/// Built on `crux_issue_reporter`'s [CruxIssueSessionContextBuilder] — all
/// four products used to hand-roll the same accumulate/fallback/guard moves.
/// The field labels and the `kWavecruxIssueAttr*` keys are unchanged by that
/// move; the Pro overlay reads the keys.
///
/// Per-tab state is read out of the **active tab's** own [ProviderContainer]
/// via the [TabContainerManager], mirroring `AppDiagnosticsReportService`.
/// Reading those providers off the root `ref` would resolve the empty root
/// container instead of the loaded waveform — the recurring per-tab scope-leak
/// class. Degrades to whatever it managed to collect when the workspace
/// plumbing is absent (a bare unit-test container has no tab manager), so the
/// reporter never fails to open because the snapshot could not be built.
CruxIssueSessionContext buildWavecruxIssueSessionContext(Ref ref) {
  final builder = CruxIssueSessionContextBuilder();

  var tabCount = 0;
  String? activeFileFormat;
  var signalCount = 0;
  final decoderNames = <String>[];
  final decoderIds = <String>[];
  final proDecoderIds = <String>[];
  var stagePanelCount = 0;
  var stageWidgetTypes = const <String>[];

  // Degrades to whatever it managed to collect: the reporter exists to let a
  // user report a broken state, so it must open even when the state it wants
  // to describe is the broken thing.
  builder
    ..guard(() {
      tabCount = ref.read(tabListProvider).length;
      final activeTabId = ref.read(activeTabIdProvider);
      final container = ref
          .read(tabContainerManagerProvider)
          .containerFor(
            activeTabId,
          );

      final fileStats = container.read(fileStatsProvider);
      activeFileFormat = fileStats?.formatName;
      signalCount = fileStats?.totalSignals ?? 0;

      for (final active in container.read(activeDecodersProvider)) {
        final def = DecoderRegistry.instance.getDefinition(active.decoderId);
        final baseName = def?.displayName ?? active.decoderId;
        decoderNames.add(active.instanceLabel(baseName));
        decoderIds.add(active.decoderId);
        if ((def?.requiredTier ?? LicenseTier.openCore) !=
            LicenseTier.openCore) {
          proDecoderIds.add(active.decoderId);
        }
      }
      decoderIds.sort();
      proDecoderIds.sort();

      final stage = container.read(stageWorkspaceProvider);
      stagePanelCount = stage.panels.length;
      stageWidgetTypes = <String>{
        for (final panel in stage.panels)
          for (final instance in panel.instances) instance.widgetId,
      }.toList()..sort();
    })
    ..addCount(
      'Open tabs',
      tabCount,
      attributeKey: kWavecruxIssueAttrOpenTabs,
    )
    ..addText(
      'Active file format',
      activeFileFormat,
      fallback: CruxIssueFallback.noneLoaded,
      attributeKey: kWavecruxIssueAttrActiveFileFormat,
    )
    ..addCount(
      'Signals in active tab',
      signalCount,
      attributeKey: kWavecruxIssueAttrActiveSignalCount,
    )
    // The visible field carries the decoders' *display* names (with their
    // instance suffix); the attribute carries the sorted registry ids, which
    // is what the Pro overlay reads. Two different shapes of the same fact,
    // so this one field is added by hand rather than through `addList`.
    ..addList('Active decoders', decoderNames)
    ..attribute(kWavecruxIssueAttrActiveDecoderIds, decoderIds)
    ..attribute(kWavecruxIssueAttrProDecoderIds, proDecoderIds)
    ..attribute(kWavecruxIssueAttrStagePanelCount, stagePanelCount)
    ..attribute(kWavecruxIssueAttrStageWidgetTypes, stageWidgetTypes);

  return builder.build();
}

/// Root-scope override binding [buildWavecruxIssueSessionContext] to the shared
/// reporter's product seam. Spread into the root container by `bootstrap`.
final Override wavecruxIssueSessionContextOverride =
    cruxIssueSessionContextProvider.overrideWith(
      buildWavecruxIssueSessionContext,
    );
