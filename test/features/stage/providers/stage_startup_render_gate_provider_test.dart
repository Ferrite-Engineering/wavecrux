// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/providers/stage_startup_render_gate_provider.dart';

void main() {
  group('StageStartupRenderGate', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('defaults to false (not gated) so the Stage renders immediately', () {
      expect(container.read(stageStartupRenderGateProvider), isFalse);
    });

    test('engage() gates; release() ungates', () {
      container.read(stageStartupRenderGateProvider.notifier).engage();
      expect(container.read(stageStartupRenderGateProvider), isTrue);

      container.read(stageStartupRenderGateProvider.notifier).release();
      expect(container.read(stageStartupRenderGateProvider), isFalse);
    });

    test('release() is idempotent on an already-released gate', () {
      container.read(stageStartupRenderGateProvider.notifier)
        ..release()
        ..release();
      expect(container.read(stageStartupRenderGateProvider), isFalse);
    });

    test('engage() is idempotent on an already-engaged gate', () {
      container.read(stageStartupRenderGateProvider.notifier)
        ..engage()
        ..engage();
      expect(container.read(stageStartupRenderGateProvider), isTrue);
    });
  });
}
