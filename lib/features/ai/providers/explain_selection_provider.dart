// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/providers/ai_model_client_provider.dart';
import 'package:wavecrux/core/providers/ai_tool_registry_provider.dart';
import 'package:wavecrux/domain/interfaces/ai_model_client.dart';
import 'package:wavecrux/services/ai/explain_selection.dart';

part 'explain_selection_provider.g.dart';

/// Lifecycle phase of an Explain Selection run.
enum ExplainSelectionPhase {
  /// Nothing requested — the result panel is hidden.
  idle,

  /// The model call is in flight.
  loading,

  /// A parsed explanation is available.
  ready,

  /// No signals were selected when the run started.
  emptySelection,

  /// No AI model is configured (open-core no-op client, or unconfigured key).
  notConfigured,

  /// The model could not be reached / returned an error.
  error,
}

/// Immutable state of the Explain Selection feature for one tab.
@immutable
class ExplainSelectionState {
  const ExplainSelectionState({
    this.phase = ExplainSelectionPhase.idle,
    this.segments = const [],
    this.rawText = '',
  });

  /// Current phase.
  final ExplainSelectionPhase phase;

  /// Parsed explanation segments (non-empty only when [phase] is
  /// [ExplainSelectionPhase.ready]).
  final List<ExplainSegment> segments;

  /// The raw model response (for diagnostics / copy).
  final String rawText;

  /// Whether the result panel should take over the bottom pane.
  bool get isActive => phase != ExplainSelectionPhase.idle;
}

/// Drives the open-core, non-agentic **Explain Selection** flow for one tab:
/// build context (via the `getSelectionContext` tool) → a single
/// [AiModelClient] call (no tool loop) → parse the response into segments.
@riverpod
class ExplainSelection extends _$ExplainSelection {
  @override
  ExplainSelectionState build() => const ExplainSelectionState();

  /// Runs an Explain Selection pass over the active tab's current selection.
  Future<void> explainCurrentSelection() async {
    // 1. Build the compact structured context with the open-core tool.
    final ctx = await ref
        .read(aiToolRegistryProvider)
        .invoke(ref, 'getSelectionContext', const {});
    if (ctx.isError) {
      state = const ExplainSelectionState(phase: ExplainSelectionPhase.error);
      return;
    }
    final signalCount = ctx.data['signalCount'];
    if (signalCount is int && signalCount == 0) {
      state = const ExplainSelectionState(
        phase: ExplainSelectionPhase.emptySelection,
      );
      return;
    }

    state = const ExplainSelectionState(phase: ExplainSelectionPhase.loading);

    // 2. ONE non-agentic model call — no tools offered, no loop.
    final client = ref.read(aiModelClientProvider);
    final buffer = StringBuffer();
    try {
      await for (final event in client.send(
        buildExplainSelectionRequest(ctx.data),
      )) {
        switch (event) {
          case AiTextDelta(:final text):
            buffer.write(text);
          case AiClientUnavailable(:final reason):
            state = ExplainSelectionState(
              phase: reason == AiUnavailableReason.notConfigured
                  ? ExplainSelectionPhase.notConfigured
                  : ExplainSelectionPhase.error,
            );
            return;
          // Non-agentic: a tool-call request from the model is ignored, and a
          // completion event just ends the stream.
          case AiToolCallRequested():
          case AiResponseCompleted():
            break;
        }
      }
    } on Object {
      state = const ExplainSelectionState(phase: ExplainSelectionPhase.error);
      return;
    }

    // 3. Parse the response into text + citation segments.
    final raw = buffer.toString();
    state = ExplainSelectionState(
      phase: ExplainSelectionPhase.ready,
      segments: parseExplanation(raw),
      rawText: raw,
    );

    // Counted on the `ready` phase, not on invocation: an empty selection, an
    // unconfigured provider and a failed request all return above, and the
    // question the telemetry answers — whether open-core AI justifies investing in the
    // Pro Assistant — is answered by explanations users actually received.
    // No properties: everything about the request is the user's design.
    ref
        .read(telemetryServiceProvider)
        .record(TelemetryEvent('ai.explain_used'));
  }

  /// Closes the result panel and clears the result.
  void close() => state = const ExplainSelectionState();
}
