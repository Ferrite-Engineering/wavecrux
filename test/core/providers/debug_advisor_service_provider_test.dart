// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/debug_advisor_service_provider.dart';
import 'package:wavecrux/domain/interfaces/debug_advisor_service.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/services/debug_advisor/noop_debug_advisor_service.dart';

void main() {
  group('debugAdvisorServiceProvider', () {
    test('default returns NoopDebugAdvisorService', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(debugAdvisorServiceProvider),
        isA<NoopDebugAdvisorService>(),
      );
    });

    test('can be overridden by Pro overlay', () {
      final stub = _StubDebugAdvisorService();
      final container = ProviderContainer(
        overrides: [
          debugAdvisorServiceProvider.overrideWithValue(stub),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(debugAdvisorServiceProvider), same(stub));
    });
  });
}

class _StubDebugAdvisorService implements DebugAdvisorService {
  @override
  List<DebugAdvisorSuggestion> analyze({
    required WaveformDataSource source,
    required List<Scope> hierarchy,
    required int cursorTime,
    String? focusSignalRef,
  }) => const [];
}
