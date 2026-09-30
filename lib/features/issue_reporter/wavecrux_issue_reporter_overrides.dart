// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wavecrux/core/app_info/application_build_info_provider.dart';
import 'package:wavecrux/core/app_info/crux_app_info_adapter.dart';
import 'package:wavecrux/domain/models/wavecrux_tab.dart';
import 'package:wavecrux/features/issue_reporter/providers/wavecrux_issue_session_context.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/services/diagnostics/app_diagnostics_report_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

/// WaveCrux's binding of the cross-suite [CruxIssueReporterConfig].
///
/// Reports are filed against the public open-core repository. The slug is
/// selected here rather than inside `crux_issue_reporter` so the package stays
/// free of per-product routing. It is deliberately *not* keyed off
/// `kBetaPeriod`: that flag governs tier gating and flips on its own schedule,
/// while the issue tracker moved to the open-core repo at the 1.0 launch. No
/// `issueTemplate`: WaveCrux files against the plain new-issue form (the
/// pre-migration in-tree behavior), and the default `bug`, `user-report`,
/// `<platform>` labels match too.
///
/// The reporter is open to every tier: no `FeatureGate`, no tier badge. It is
/// the beta feedback mechanism, and a user who cannot report a bug is a user
/// whose bug never gets fixed.
const CruxIssueReporterConfig wavecruxIssueReporterConfig =
    CruxIssueReporterConfig(
      productName: 'WaveCrux',
      repositorySlug: 'Ferrite-Engineering/wavecrux',
    );

/// Root-scope overrides that bind the shared beta issue reporter to WaveCrux's
/// configuration, build metadata, privacy-scrubbed session snapshot, and the
/// structured diagnostics report.
///
/// Spread into the root `ProviderContainer` by `bootstrap`, ahead of the
/// Pro overlay's `proOverrides` — the overlay contributes its extra
/// "Pro State" category through `cruxIssueReporterDataProviderProvider`, whose
/// open-core default contributes nothing.
///
/// The localized string bundle is deliberately **not** here: it needs a
/// `BuildContext` for `L10N.of(context)`, so `WaveCruxApp` overrides
/// `cruxIssueReporterStringsProvider` from inside `MaterialApp.builder`.
///
/// `cruxIssueDiagnosticsReportProvider` is overridden with the same structured
/// snapshot WaveCrux's Diagnostics panel "Copy Full Diagnostics Report" emits,
/// folded into the Diagnostics category ahead of the session log — the behavior
/// the in-tree reporter had. It reads per-tab state through the active tab's
/// container and degrades to a placeholder on any failure so the reporter never
/// fails to open.
final List<Override> wavecruxIssueReporterOverrides = <Override>[
  cruxIssueReporterConfigProvider.overrideWithValue(
    wavecruxIssueReporterConfig,
  ),
  cruxIssueReporterBuildInfoProvider.overrideWith(
    (ref) => ref.watch(applicationBuildInfoProvider).value?.toCruxAppInfo(),
  ),
  cruxIssueDiagnosticsReportProvider.overrideWith(_buildDiagnosticsReport),
  wavecruxIssueSessionContextOverride,
];

/// Builds the structured diagnostics report snapshot (the same text the
/// Diagnostics panel's "Copy Full Diagnostics Report" emits) that the shared
/// reporter folds into the Diagnostics category. Frame-timing fields are absent
/// — the reporter runs no frame callback — so the report notes "(no frames
/// recorded yet)". Wrapped defensively: a provider-scope failure degrades to a
/// placeholder rather than breaking submission.
String? _buildDiagnosticsReport(Ref ref) {
  try {
    final tabs = ref.read(tabListProvider);
    final activeTabId = ref.read(activeTabIdProvider);
    final tabContainerManager = ref.read(tabContainerManagerProvider);
    final activeTab = tabs
        .where((t) => t.id == activeTabId)
        .cast<WavecruxTab?>()
        .firstWhere((_) => true, orElse: () => null);
    return const AppDiagnosticsReportService().generate(
      read: ref.read,
      tabs: tabs,
      activeTabId: activeTabId,
      tabContainerManager: tabContainerManager,
      activeTab: activeTab,
    );
  } on Object {
    return '(diagnostics report unavailable)';
  }
}
