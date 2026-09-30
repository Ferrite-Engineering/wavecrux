// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/diagnostics/app_diagnostics_report_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

/// Builds the full app diagnostics report, copies it to the clipboard and
/// confirms with a snack.
///
/// The one implementation behind both ways to ask for it: the App Diagnostics
/// dialog's Copy Report button and the Tools ▸ Copy Diagnostics Report action.
/// The dialog passes the frame timings it samples while open; the action has
/// none to pass, so that section of its report says no samples were taken.
Future<void> copyAppDiagnosticsReport(
  BuildContext context,
  WidgetRef ref, {
  List<double>? recentFrameTimesMs,
  int frameBudgetOverruns = 0,
  DateTime? lastFrameTimestamp,
}) async {
  final tabs = ref.read(tabListProvider);
  final activeTabId = ref.read(activeTabIdProvider);
  final activeTab = tabs.where((t) => t.id == activeTabId).firstOrNull;

  final report = const AppDiagnosticsReportService().generate(
    read: ref.read,
    tabs: tabs,
    activeTabId: activeTabId,
    activeTab: activeTab,
    tabContainerManager: ref.read(tabContainerManagerProvider),
    recentFrameTimesMs: recentFrameTimesMs,
    frameBudgetOverruns: frameBudgetOverruns,
    lastFrameTimestamp: lastFrameTimestamp,
  );

  await Clipboard.setData(ClipboardData(text: report));
  if (!context.mounted) return;
  showCruxInfoSnack(context, L10N.of(context).appDiagnosticsCopyReportSuccess);
}
