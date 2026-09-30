// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/sdk/manifest/localized_string.dart';

void main() {
  group('LocalizedString.resolve', () {
    test('single-string resolves identically for any locale', () {
      const s = LocalizedString.single('Gauge Cluster');
      expect(s.resolve('en'), 'Gauge Cluster');
      expect(s.resolve('zh_CN'), 'Gauge Cluster');
      expect(s.resolve('xx'), 'Gauge Cluster');
    });

    test('localized exact match wins', () {
      final s = LocalizedString.localized(const {
        'en': 'PWM Analyzer',
        'zh_CN': 'PWM 分析仪',
        'ja': 'PWM アナライザ',
        'ko': 'PWM 분석기',
      });
      expect(s.resolve('en'), 'PWM Analyzer');
      expect(s.resolve('zh_CN'), 'PWM 分析仪');
      expect(s.resolve('ja'), 'PWM アナライザ');
      expect(s.resolve('ko'), 'PWM 분석기');
    });

    test('fallback to language-code prefix', () {
      final s = LocalizedString.localized(const {
        'en': 'Hello',
        'zh': '你好',
      });
      // zh_CN requested, only zh available — should match zh.
      expect(s.resolve('zh_CN'), '你好');
    });

    test('fallback to en when locale missing', () {
      final s = LocalizedString.localized(const {
        'en': 'Default',
        'fr': 'Bonjour',
      });
      expect(s.resolve('zh_CN'), 'Default');
    });

    test('fallback to first declared entry when no en', () {
      final s = LocalizedString.localized(const {
        'fr': 'Bonjour',
        'de': 'Hallo',
      });
      expect(s.resolve('zh_CN'), 'Bonjour');
    });

    test('empty localized map throws on construction', () {
      expect(
        () => LocalizedString.localized(const {}),
        throwsA(isA<AssertionError>()),
      );
    });

    test('equality considers single vs localized origin', () {
      const a = LocalizedString.single('X');
      final b = LocalizedString.localized(const {'en': 'X'});
      expect(a, isNot(equals(b)));
    });
  });
}
