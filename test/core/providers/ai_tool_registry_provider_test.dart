// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/ai_tool_registry_provider.dart';
import 'package:wavecrux/domain/interfaces/ai_model_client.dart';
import 'package:wavecrux/domain/models/ai/ai_tool_result.dart';
import 'package:wavecrux/services/ai/ai_tool.dart';

void main() {
  test('default registry exposes the six viewer-navigation tools', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final registry = container.read(aiToolRegistryProvider);
    expect(
      registry.toolNames.toSet(),
      {
        'searchSignal',
        'getTransitionsInWindow',
        'listDecodedTransactions',
        'getSelectionContext',
        'jumpCursor',
        'addMarker',
      },
    );
  });

  test('extraAiToolsProvider tools are appended (Pro injection seam)', () {
    final extra = AiTool(
      spec: const AiToolSpec(name: 'runDebugAdvisor', description: 'pro'),
      handler: (ref, args) async => AiToolResult.ok(const {}),
    );
    final container = ProviderContainer(
      overrides: [
        extraAiToolsProvider.overrideWithValue([extra]),
      ],
    );
    addTearDown(container.dispose);

    final registry = container.read(aiToolRegistryProvider);
    expect(registry.lookup('runDebugAdvisor'), isNotNull);
    // Open-core tools are still present alongside the injected one.
    expect(registry.lookup('searchSignal'), isNotNull);
    expect(registry.length, 7);
  });

  test('a contributed tool that collides with an open-core name throws', () {
    final clash = AiTool(
      spec: const AiToolSpec(name: 'jumpCursor', description: 'dup'),
      handler: (ref, args) async => AiToolResult.ok(const {}),
    );
    final container = ProviderContainer(
      overrides: [
        extraAiToolsProvider.overrideWithValue([clash]),
      ],
    );
    addTearDown(container.dispose);

    // Riverpod rethrows the build-time error (possibly wrapped); assert it is
    // the duplicate-name guard tripping on the colliding tool.
    expect(
      () => container.read(aiToolRegistryProvider),
      throwsA(
        predicate<Object>(
          (e) =>
              e.toString().contains('Duplicate AI tool name') &&
              e.toString().contains('jumpCursor'),
        ),
      ),
    );
  });
}
