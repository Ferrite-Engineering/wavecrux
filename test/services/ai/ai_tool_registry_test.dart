// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/ai_model_client.dart';
import 'package:wavecrux/domain/models/ai/ai_tool_result.dart';
import 'package:wavecrux/services/ai/ai_tool.dart';
import 'package:wavecrux/services/ai/ai_tool_registry.dart';

/// Hands a live [Ref] back to the test so tool handlers can be invoked outside
/// a provider build.
final _refProbe = Provider<Ref>((ref) => ref);

AiTool _tool(String name) => AiTool(
  spec: AiToolSpec(name: name, description: 'd'),
  handler: (ref, args) async => AiToolResult.ok({'tool': name, 'args': args}),
);

void main() {
  late ProviderContainer container;
  late Ref ref;

  setUp(() {
    container = ProviderContainer();
    ref = container.read(_refProbe);
  });
  tearDown(() => container.dispose());

  group('AiToolRegistry', () {
    test('exposes specs and names in registration order', () {
      final reg = AiToolRegistry([_tool('a'), _tool('b'), _tool('c')]);
      expect(reg.toolNames.toList(), ['a', 'b', 'c']);
      expect(reg.specs.map((s) => s.name).toList(), ['a', 'b', 'c']);
      expect(reg.length, 3);
    });

    test('lookup returns the registered tool or null', () {
      final reg = AiToolRegistry([_tool('a')]);
      expect(reg.lookup('a'), isNotNull);
      expect(reg.lookup('missing'), isNull);
    });

    test('duplicate tool names throw at construction', () {
      expect(
        () => AiToolRegistry([_tool('dup'), _tool('dup')]),
        throwsArgumentError,
      );
    });

    test('invoke dispatches to the handler with arguments', () async {
      final reg = AiToolRegistry([_tool('echo')]);
      final result = await reg.invoke(ref, 'echo', const {'k': 'v'});
      expect(result.isError, isFalse);
      expect(result.data['tool'], 'echo');
      expect(result.data['args'], const {'k': 'v'});
    });

    test(
      'invoking an unknown tool returns a typed failure — never throws',
      () async {
        final reg = AiToolRegistry([_tool('a')]);
        final result = await reg.invoke(ref, 'ghost', const {});
        expect(result.isError, isTrue);
        expect(result.error, contains('ghost'));
      },
    );
  });
}
