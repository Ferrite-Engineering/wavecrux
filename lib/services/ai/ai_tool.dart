// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/interfaces/ai_model_client.dart';
import 'package:wavecrux/domain/models/ai/ai_tool_result.dart';

/// Async handler that executes an AI tool against the live provider graph.
///
/// Receives the [Ref] (so the tool can read the loaded waveform, cursor,
/// decoders, selection, …) and the decoded [arguments] the model supplied.
/// Returns an [AiToolResult] — handlers report expected failures (no waveform
/// loaded, unknown signal) as [AiToolResult.failure], never by throwing.
typedef AiToolHandler =
    Future<AiToolResult> Function(
      Ref ref,
      Map<String, Object?> arguments,
    );

/// One registered AI tool: its model-facing [spec] paired with the [handler]
/// that grounds the call in real viewer data.
class AiTool {
  const AiTool({required this.spec, required this.handler});

  /// The model-facing declaration (name, description, JSON-Schema parameters).
  final AiToolSpec spec;

  /// The implementation that executes the call.
  final AiToolHandler handler;

  /// Shorthand for [AiToolSpec.name].
  String get name => spec.name;
}
