// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/debug_advisor_service.dart';

DebugAdvisorSuggestion _makeSuggestion({
  DebugAdvisorRuleId rule = DebugAdvisorRuleId.xPropagationChain,
  DebugAdvisorSeverity severity = DebugAdvisorSeverity.warning,
  double confidence = 0.5,
  String label = 'debugAdvisorRuleXProp',
  String explanation = 'debugAdvisorExplainXProp',
  List<String> signals = const ['top.cpu.dataout'],
  int start = 100,
  int end = 200,
  Map<String, String> placeholders = const {},
}) => DebugAdvisorSuggestion(
  ruleId: rule,
  severity: severity,
  confidence: confidence,
  labelArbKey: label,
  explanationArbKey: explanation,
  affectedSignals: signals,
  affectedTimeRangeStart: start,
  affectedTimeRangeEnd: end,
  placeholders: placeholders,
);

void main() {
  group('DebugAdvisorSuggestion', () {
    test('equality matches all fields', () {
      final a = _makeSuggestion();
      final b = _makeSuggestion();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs by ruleId / severity / confidence / range / signals', () {
      final base = _makeSuggestion();
      expect(
        base,
        isNot(_makeSuggestion(rule: DebugAdvisorRuleId.stuckAt)),
      );
      expect(
        base,
        isNot(_makeSuggestion(severity: DebugAdvisorSeverity.error)),
      );
      expect(base, isNot(_makeSuggestion(confidence: 0.9)));
      expect(
        base,
        isNot(_makeSuggestion(signals: const ['top.other'])),
      );
      expect(base, isNot(_makeSuggestion(start: 0)));
      expect(base, isNot(_makeSuggestion(end: 999)));
    });

    test('placeholder map equality', () {
      final a = _makeSuggestion(placeholders: const {'signal': 'top.foo'});
      final b = _makeSuggestion(placeholders: const {'signal': 'top.foo'});
      final c = _makeSuggestion(placeholders: const {'signal': 'top.bar'});
      expect(a, b);
      expect(a, isNot(c));
    });

    test('toString includes rule, severity, confidence', () {
      final s = _makeSuggestion();
      final str = s.toString();
      expect(str, contains('xPropagationChain'));
      expect(str, contains('warning'));
      expect(str, contains('0.50'));
    });
  });

  group('DebugAdvisorRuleId', () {
    test('declares all four rule families', () {
      expect(DebugAdvisorRuleId.values, hasLength(4));
      expect(
        DebugAdvisorRuleId.values,
        containsAll(<DebugAdvisorRuleId>[
          DebugAdvisorRuleId.xPropagationChain,
          DebugAdvisorRuleId.clockDomainCrossing,
          DebugAdvisorRuleId.stuckAt,
          DebugAdvisorRuleId.timingViolation,
        ]),
      );
    });
  });

  group('DebugAdvisorSeverity', () {
    test('declares info / warning / error in ascending severity order', () {
      expect(DebugAdvisorSeverity.values, hasLength(3));
      expect(DebugAdvisorSeverity.info.index, 0);
      expect(DebugAdvisorSeverity.warning.index, 1);
      expect(DebugAdvisorSeverity.error.index, 2);
    });
  });
}
