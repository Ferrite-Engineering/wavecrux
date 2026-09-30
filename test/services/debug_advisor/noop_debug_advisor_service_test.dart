// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/debug_advisor_service.dart';
import 'package:wavecrux/services/debug_advisor/noop_debug_advisor_service.dart';

import '../../helpers/fake_waveform_data_source.dart';

void main() {
  group('NoopDebugAdvisorService', () {
    test('always returns an empty suggestion list', () {
      const service = NoopDebugAdvisorService();
      final source = FakeWaveformDataSource();

      final result = service.analyze(
        source: source,
        hierarchy: source.rootScopes,
        cursorTime: 100,
      );

      expect(result, isEmpty);
      expect(result, isA<List<DebugAdvisorSuggestion>>());
    });

    test('focusSignalRef is accepted and ignored', () {
      const service = NoopDebugAdvisorService();
      final source = FakeWaveformDataSource();

      final result = service.analyze(
        source: source,
        hierarchy: source.rootScopes,
        cursorTime: 0,
        focusSignalRef: 'sig.x',
      );

      expect(result, isEmpty);
    });
  });
}
