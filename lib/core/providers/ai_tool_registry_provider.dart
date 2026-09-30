// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/services/ai/ai_tool.dart';
import 'package:wavecrux/services/ai/ai_tool_registry.dart';
import 'package:wavecrux/services/ai/tools/viewer_navigation_tools.dart';

/// Open-core extension point: additional AI tools contributed by an overlay,
/// appended after the open-core viewer-navigation tools.
///
/// The open-core default is an empty list. The closed-source Pro
/// overlay overrides this binding to add its analysis tools (`runDebugAdvisor`
/// over the deterministic detectors, decoder-aware transaction queries, X-trace
/// causal lookups) without forking the open-core registry. Mirrors the
/// `extraDecodersProvider` composition pattern.
final extraAiToolsProvider = Provider<List<AiTool>>((_) => const <AiTool>[]);

/// Open-core extension point exposing the active [AiToolRegistry] — the
/// function-calling surface presented to the [AiModelClient].
///
/// Open-core registers the viewer-navigation tools (`searchSignal`,
/// `getTransitionsInWindow`, `listDecodedTransactions`, `getSelectionContext`,
/// `jumpCursor`, `addMarker`), each grounded in real loaded-waveform data, then
/// appends every tool from [extraAiToolsProvider]. The Pro overlay's analysis
/// tools join through that seam. See `docs/ARCHITECTURE.md` §10.
final aiToolRegistryProvider = Provider<AiToolRegistry>((ref) {
  final extra = ref.watch(extraAiToolsProvider);
  return AiToolRegistry(<AiTool>[
    ...viewerNavigationAiTools(),
    ...extra,
  ]);
});
