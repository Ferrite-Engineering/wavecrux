// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/interfaces/ai_model_client.dart';
import 'package:wavecrux/domain/models/ai/ai_tool_result.dart';
import 'package:wavecrux/services/ai/ai_tool.dart';

/// The function-calling surface presented to an [AiModelClient]: a set of
/// [AiTool]s keyed by name.
///
/// Open-core builds the registry from the viewer-navigation tools plus any
/// tools contributed through `extraAiToolsProvider` (the Pro overlay registers
/// its analysis tools there). The registry is immutable once constructed;
/// composition happens at provider-build time, not by mutating an instance.
///
/// Tool names must be unique — a duplicate is a programming error (two overlays
/// claiming the same name) and throws at construction rather than silently
/// shadowing.
class AiToolRegistry {
  AiToolRegistry(List<AiTool> tools) : _tools = _index(tools);

  final Map<String, AiTool> _tools;

  static Map<String, AiTool> _index(List<AiTool> tools) {
    final map = <String, AiTool>{};
    for (final tool in tools) {
      if (map.containsKey(tool.name)) {
        throw ArgumentError('Duplicate AI tool name: "${tool.name}"');
      }
      map[tool.name] = tool;
    }
    return map;
  }

  /// The model-facing specs for every registered tool, in registration order.
  List<AiToolSpec> get specs => <AiToolSpec>[
    for (final tool in _tools.values) tool.spec,
  ];

  /// The names of every registered tool, in registration order.
  Iterable<String> get toolNames => _tools.keys;

  /// Number of registered tools.
  int get length => _tools.length;

  /// Returns the tool registered under [name], or `null` if none.
  AiTool? lookup(String name) => _tools[name];

  /// Invokes the tool named [name] with [arguments].
  ///
  /// Returns an [AiToolResult.failure] (never throws) when no tool is
  /// registered under [name], so a model that hallucinates a tool name gets a
  /// typed error it can recover from rather than crashing the agent loop.
  Future<AiToolResult> invoke(
    Ref ref,
    String name,
    Map<String, Object?> arguments,
  ) async {
    final tool = _tools[name];
    if (tool == null) return AiToolResult.failure('Unknown tool: "$name"');
    return tool.handler(ref, arguments);
  }
}
