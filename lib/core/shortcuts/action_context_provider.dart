// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/providers/ai_model_client_provider.dart';
import 'package:wavecrux/core/providers/collaboration_service_provider.dart';
import 'package:wavecrux/core/providers/tier_gated_actions_available_provider.dart';
import 'package:wavecrux/core/shortcuts/action_context.dart';
import 'package:wavecrux/features/collaboration/providers/collaboration_session_state_provider.dart';
import 'package:wavecrux/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:wavecrux/features/panes/providers/split_pane_allowed_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/active_tab_action_flags_provider.dart';
import 'package:wavecrux/features/viewer/providers/active_tab_has_selection_provider.dart';
import 'package:wavecrux/features/viewer/providers/active_tab_panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/providers/active_tab_streaming_provider.dart';
import 'package:wavecrux/features/viewer/providers/streaming_source_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Builds the [ActionContext] that every action-discovery surface (menu bar,
/// overflow menu, command palette, toolbar) feeds to the descriptor selectors
/// in `action_descriptors.dart`. Centralizing it here guarantees all four
/// surfaces gate on identical state.
///
/// "Is a file loaded" is derived primarily from the active tab's `filePath`
/// rather than the per-tab `waveformIsLoadedProvider` — the toolbar, menu bar,
/// and overflow menu all live at the root scope where the per-tab provider
/// resolves to `false` (Issues 14/16/17), and the active tab's path is the
/// user-meaningful signal that crosses no per-tab `ProviderScope` boundary. The
/// `|| waveformIsLoadedProvider` fallback is inert in production (false at the
/// root scope) and lets widget tests drive the loaded-state branch by
/// overriding that provider — matching the historical toolbar behavior.
final actionContextProvider = Provider<ActionContext>((ref) {
  final tabs = ref.watch(tabListProvider);
  final activeTabId = ref.watch(activeTabIdProvider);
  String? activeFilePath;
  for (final tab in tabs) {
    if (tab.id == activeTabId) {
      activeFilePath = tab.filePath;
      break;
    }
  }

  final flags = ref.watch(activeTabActionFlagsProvider);

  final session = ref.watch(collaborationSessionStateProvider).value;
  final inSession = session != null;
  final isHost =
      inSession &&
      session.participants.any(
        (p) => p.id == session.myParticipantId && p.isHost,
      );

  return ActionContext(
    fileLoaded: activeFilePath != null || ref.watch(waveformIsLoadedProvider),
    deviceClass: ref.watch(deviceClassProvider),
    diagnosticsEnabled: ref.watch(diagnosticsEnabledProvider),
    paneCount: ref.watch(workspaceProvider).value?.panes.length ?? 1,
    inSession: inSession,
    isHost: isHost,
    // Not "a recording is running" but "a recording exists to export". The
    // session that produced it is usually over by the time anybody wants the
    // minutes, and the service keeps the buffer until the next session starts.
    isRecording:
        (session?.isRecording ?? false) ||
        ref.watch(collaborationServiceProvider).hasRecordedEvents,
    // Panel visibility is per-tab; the root-scope mirror re-emits the active
    // tab's Stage visibility so the `togglePlayback` action greys out when no
    // Stage tab is on screen. Dock-aware: Stage merely being *on* behind the
    // FSM tab does not light the transport — the panel hosting it is not
    // visible.
    stageViewVisible: ref.watch(
      activeTabPanelLayoutProvider.select((s) => s.bottomDockShowsStage),
    ),
    // Dock-aware: the toolbar's cross-probe glyph lights only when the CXP
    // tab is the one on screen, not when the feature is on behind Values.
    crossProbeVisible: ref.watch(
      activeTabPanelLayoutProvider.select((s) => s.rightDockShowsCrossProbe),
    ),
    // AI gating: experimental on (visibility), a model configured (enablement),
    // and a non-empty selection on the active tab (mirrored to root, like the
    // panel-layout mirror above).
    aiAvailable: ref.watch(aiExperimentalEnabledProvider),
    aiModelConfigured: ref.watch(aiModelClientProvider).isConfigured,
    hasSelection: ref.watch(activeTabHasSelectionProvider),
    // Per-tab gating flags (cursor / markers / diff / cocotb / pattern match)
    // mirrored to the root scope so the descriptor predicates can grey out
    // actions that would no-op in the current context.
    cursorPresent: flags.cursorPresent,
    markersPresent: flags.markersPresent,
    annotationsPresent: flags.annotationsPresent,
    signalsDisplayed: flags.signalsDisplayed,
    diffActive: flags.diffActive,
    cocotbLogLoaded: flags.cocotbLogLoaded,
    patternMatchesPresent: flags.patternMatchesPresent,
    playbackActive: flags.playbackActive,
    // Zoom bounds, so Zoom In / Zoom Out grey out at the ends of their range
    // instead of responding to a press the clamp then absorbs.
    canZoomOut: flags.canZoomOut,
    canZoomIn: flags.canZoomIn,
    // Streaming rides its own mirror rather than the flags record: the mirror
    // carries the full state (the LIVE badge needs the elapsed time) and
    // `.select` keeps the once-a-second elapsed tick from churning the action
    // context and rebuilding every surface.
    streamingActive: ref.watch(
      activeTabStreamingProvider.select(
        (s) => s is StreamingViewerActive || s is StreamingViewerStarting,
      ),
    ),
    // Whether PRO/ENT actions are executable in this build at all. False for
    // Open Core on iOS/Android, where their handlers are no-ops and an app
    // store gives the user no way to make them real — see
    // `tierGatedActionsAvailableProvider`.
    tierGatedActionsAvailable: ref.watch(tierGatedActionsAvailableProvider),
    isWeb: kIsWeb,
    splitPaneAllowed: ref.watch(splitPaneAllowedProvider),
  );
});
