// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

void main() {
  group('ShortcutAction', () {
    test('enum contains all 123 expected actions', () {
      const expected = {
        ShortcutAction.openFile,
        ShortcutAction.closeFile,
        ShortcutAction.quit,
        ShortcutAction.openAbout,
        ShortcutAction.issueReporter,
        ShortcutAction.zoomIn,
        ShortcutAction.zoomOut,
        ShortcutAction.fitAll,
        ShortcutAction.waveformZoomIn,
        ShortcutAction.waveformZoomOut,
        ShortcutAction.zoomToSelection,
        ShortcutAction.panLeft,
        ShortcutAction.panRight,
        ShortcutAction.panLeftSmall,
        ShortcutAction.panRightSmall,
        ShortcutAction.jumpToStart,
        ShortcutAction.jumpToEnd,
        ShortcutAction.nextTransition,
        ShortcutAction.prevTransition,
        ShortcutAction.setMarker,
        ShortcutAction.jumpToMarker,
        ShortcutAction.removeMarker,
        ShortcutAction.clearCursors,
        ShortcutAction.clearSecondaryCursor,
        ShortcutAction.clearSignalSelection,
        ShortcutAction.openSearch,
        ShortcutAction.toggleTheme,
        // Diagnostics surfaces.
        ShortcutAction.openAppDiagnostics,
        ShortcutAction.openTabDiagnostics,
        ShortcutAction.openPaneRenderStats,
        ShortcutAction.saveSession,
        ShortcutAction.saveSessionAs,
        ShortcutAction.importGtkwSession,
        ShortcutAction.exportWaveform,
        ShortcutAction.shareAnnotatedWaveform,
        ShortcutAction.annotationWalkthroughNext,
        ShortcutAction.annotationWalkthroughPrevious,
        ShortcutAction.annotationWalkthroughPlay,
        ShortcutAction.addAnnotationAtCursor,
        ShortcutAction.annotateSelectedRange,
        ShortcutAction.toggleAnnotationsVisible,
        ShortcutAction.toggleAnnotationsPanel,
        ShortcutAction.openCommandPalette,
        ShortcutAction.openSettings,
        ShortcutAction.addDecoder,
        ShortcutAction.toggleTransactionTable,
        ShortcutAction.toggleSignalTree,
        ShortcutAction.toggleValueColumn,
        ShortcutAction.toggleStagePanel,
        // Stage Playback.
        ShortcutAction.togglePlayback,
        ShortcutAction.toggleStatisticsStrip,
        ShortcutAction.compareWaveforms,
        ShortcutAction.nextDivergence,
        ShortcutAction.prevDivergence,
        ShortcutAction.analyzeSwitchingActivity,
        ShortcutAction.patternSearch,
        ShortcutAction.nextPatternMatch,
        ShortcutAction.prevPatternMatch,
        ShortcutAction.copyDiagnosticsReport,
        ShortcutAction.loadRtlStemsFile,
        ShortcutAction.generateRtlStems,
        ShortcutAction.importVerilatorAst,
        ShortcutAction.toggleRtlSourcePanel,
        // Generate Test VCD — Tools menu action.
        ShortcutAction.generateTestVcd,
        // Convert PCAP to VCD — Enterprise-tier Tools menu action
        // (pulled-forward from Future Phases).
        ShortcutAction.convertPcapToVcd,
        ShortcutAction.loadCocotbLog,
        ShortcutAction.clearCocotbLog,
        ShortcutAction.toggleCocotbLogPanel,
        ShortcutAction.stageUndo,
        ShortcutAction.stageRedo,
        ShortcutAction.debugAdvisorTogglePanel,
        ShortcutAction.toggleSvaPanel,
        ShortcutAction.loadSvaResults,
        ShortcutAction.clearSvaResults,
        ShortcutAction.aiExplainSelection,
        ShortcutAction.aiAdvisorTogglePanel,
        ShortcutAction.setFormatBinary,
        ShortcutAction.setFormatHexadecimal,
        ShortcutAction.setFormatOctal,
        ShortcutAction.setFormatUnsignedDecimal,
        ShortcutAction.setFormatSignedDecimal,
        ShortcutAction.setFormatAscii,
        ShortcutAction.setFormatIeee754Single,
        ShortcutAction.setFormatIeee754Double,
        ShortcutAction.setFormatFixedPointQ,
        ShortcutAction.setFormatSignedMagnitude,
        ShortcutAction.setFormatGrayCode,
        ShortcutAction.setFormatNamedEnum,
        ShortcutAction.shareSession,
        ShortcutAction.joinSession,
        ShortcutAction.stopSharing,
        ShortcutAction.leaveSession,
        ShortcutAction.exportSessionRecording,
        ShortcutAction.exportReviewMinutes,
        // Presenter Mode (Enterprise).
        ShortcutAction.handoffPresenter,
        ShortcutAction.requestPresenter,
        ShortcutAction.resumeFollowing,
        ShortcutAction.dropPing,
        ShortcutAction.dropPin,
        // Tab management actions.
        ShortcutAction.closeTab,
        ShortcutAction.nextTab,
        ShortcutAction.previousTab,
        ShortcutAction.jumpToTab1,
        ShortcutAction.jumpToTab2,
        ShortcutAction.jumpToTab3,
        ShortcutAction.jumpToTab4,
        ShortcutAction.jumpToTab5,
        ShortcutAction.jumpToTab6,
        ShortcutAction.jumpToTab7,
        ShortcutAction.jumpToTab8,
        ShortcutAction.jumpToTab9,
        // Workspace management commands.
        ShortcutAction.resetWorkspace,
        ShortcutAction.newWorkspace,
        ShortcutAction.saveWorkspaceAs,
        ShortcutAction.openWorkspace,
        ShortcutAction.exportTabAsSession,
        // Pane management commands.
        ShortcutAction.splitPaneRight,
        ShortcutAction.closePane,
        ShortcutAction.focusOtherPane,
        ShortcutAction.moveTabToOtherPane,
        // Cross-probe panel (CXP).
        ShortcutAction.openCrossProbePanel,
        // Manual update check.
        ShortcutAction.checkForUpdates,
        ShortcutAction.openDocumentation,
        // Stop Streaming — promoted from a bare toolbar callback to an action
        // so every surface can reach it.
        ShortcutAction.stopStreaming,
      };
      expect(ShortcutAction.values.toSet(), expected);
    });
  });

  group('ShortcutActionIntent', () {
    test('equal when action is equal', () {
      expect(
        const ShortcutActionIntent(ShortcutAction.zoomIn),
        const ShortcutActionIntent(ShortcutAction.zoomIn),
      );
    });

    test('not equal when action differs', () {
      expect(
        const ShortcutActionIntent(ShortcutAction.zoomIn),
        isNot(const ShortcutActionIntent(ShortcutAction.zoomOut)),
      );
    });

    test('hashCode matches for equal intents', () {
      const a = ShortcutActionIntent(ShortcutAction.panLeft);
      const b = ShortcutActionIntent(ShortcutAction.panLeft);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('ShortcutActionLabel', () {
    testWidgets('label() returns a non-empty string for every action in en', (
      tester,
    ) async {
      late L10N l10n;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = L10N.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final action in ShortcutAction.values) {
        final label = action.label(l10n);
        expect(label, isNotEmpty, reason: '${action.name}.label() was empty');
      }
    });

    testWidgets('locale sweep — renders without exception in en', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: SizedBox(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
