// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/config_param.dart';

void main() {
  group('ConfigParam', () {
    test('basic equality + hashCode honor every field', () {
      const a = ConfigParam(
        id: 'x',
        labelKey: 'lbl',
        type: ConfigParamType.integer,
        defaultValue: 42,
      );
      const b = ConfigParam(
        id: 'x',
        labelKey: 'lbl',
        type: ConfigParamType.integer,
        defaultValue: 42,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different ids produce different instances', () {
      const a = ConfigParam(
        id: 'x',
        labelKey: 'lbl',
        type: ConfigParamType.integer,
        defaultValue: 0,
      );
      const b = ConfigParam(
        id: 'y',
        labelKey: 'lbl',
        type: ConfigParamType.integer,
        defaultValue: 0,
      );
      expect(a, isNot(equals(b)));
    });

    test('isVisibleIn returns true when no predicate is set', () {
      const p = ConfigParam(
        id: 'x',
        labelKey: 'lbl',
        type: ConfigParamType.toggle,
        defaultValue: true,
      );
      expect(p.isVisibleIn(const {}), isTrue);
      expect(p.isVisibleIn(const {'x': false}), isTrue);
    });

    test('isVisibleIn matches the predicate against a stored value', () {
      const p = ConfigParam(
        id: 'stereoDisplay',
        labelKey: 'lbl',
        type: ConfigParamType.enumChoice,
        defaultValue: 'stacked',
        visibleWhenKey: 'channelMode',
        visibleWhenValue: 'stereo',
      );
      // No value set: predicate fails (stored != 'stereo').
      expect(p.isVisibleIn(const {}), isFalse);
      // Mismatched value: predicate fails.
      expect(p.isVisibleIn(const {'channelMode': 'mono'}), isFalse);
      // Matching value: predicate passes.
      expect(p.isVisibleIn(const {'channelMode': 'stereo'}), isTrue);
    });

    test(
      'isVisibleIn matches OR-of-values when visibleWhenValues is set',
      () {
        const p = ConfigParam(
          id: 'channelWidth',
          labelKey: 'lbl',
          type: ConfigParamType.enumChoice,
          defaultValue: 'pwm1Bit',
          visibleWhenKey: 'mode',
          visibleWhenValues: {'direct3Channel', 'direct4ChannelWithIntensity'},
        );
        // No value set: predicate fails (stored value not in the set).
        expect(p.isVisibleIn(const {}), isFalse);
        // Either member of the set passes.
        expect(p.isVisibleIn(const {'mode': 'direct3Channel'}), isTrue);
        expect(
          p.isVisibleIn(const {'mode': 'direct4ChannelWithIntensity'}),
          isTrue,
        );
        // A value outside the set fails.
        expect(p.isVisibleIn(const {'mode': 'addressableStrip'}), isFalse);
      },
    );

    test(
      'constructing with both visibleWhenValue and visibleWhenValues asserts',
      () {
        expect(
          () => ConfigParam(
            id: 'x',
            labelKey: 'lbl',
            type: ConfigParamType.enumChoice,
            defaultValue: 'a',
            visibleWhenKey: 'mode',
            visibleWhenValue: 'a',
            visibleWhenValues: const {'a', 'b'},
          ),
          throwsA(isA<AssertionError>()),
        );
      },
    );

    test('visibleWhenValues participates in equality regardless of the '
        "set literal's insertion order", () {
      const a = ConfigParam(
        id: 'x',
        labelKey: 'lbl',
        type: ConfigParamType.enumChoice,
        defaultValue: 'a',
        visibleWhenKey: 'mode',
        visibleWhenValues: {'a', 'b'},
      );
      const b = ConfigParam(
        id: 'x',
        labelKey: 'lbl',
        type: ConfigParamType.enumChoice,
        defaultValue: 'a',
        visibleWhenKey: 'mode',
        visibleWhenValues: {'b', 'a'},
      );
      const c = ConfigParam(
        id: 'x',
        labelKey: 'lbl',
        type: ConfigParamType.enumChoice,
        defaultValue: 'a',
        visibleWhenKey: 'mode',
        visibleWhenValues: {'a', 'c'},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('choices list participates in equality', () {
      const a = ConfigParam(
        id: 'x',
        labelKey: 'lbl',
        type: ConfigParamType.enumChoice,
        defaultValue: 'a',
        choices: [
          ConfigParamChoice(id: 'a', labelKey: 'a.lbl'),
          ConfigParamChoice(id: 'b', labelKey: 'b.lbl'),
        ],
      );
      const b = ConfigParam(
        id: 'x',
        labelKey: 'lbl',
        type: ConfigParamType.enumChoice,
        defaultValue: 'a',
        choices: [
          ConfigParamChoice(id: 'a', labelKey: 'a.lbl'),
          ConfigParamChoice(id: 'b', labelKey: 'b.lbl'),
        ],
      );
      const c = ConfigParam(
        id: 'x',
        labelKey: 'lbl',
        type: ConfigParamType.enumChoice,
        defaultValue: 'a',
        choices: [
          ConfigParamChoice(id: 'a', labelKey: 'a.lbl'),
        ],
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('ConfigParamGroup', () {
    test('equality + hashCode', () {
      const a = ConfigParamGroup(id: 'fft', labelKey: 'fft.lbl');
      const b = ConfigParamGroup(id: 'fft', labelKey: 'fft.lbl');
      const c = ConfigParamGroup(id: 'audio', labelKey: 'fft.lbl');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('ConfigParamChoice', () {
    test('equality + hashCode', () {
      const a = ConfigParamChoice(id: 'hann', labelKey: 'hann.lbl');
      const b = ConfigParamChoice(id: 'hann', labelKey: 'hann.lbl');
      const c = ConfigParamChoice(id: 'hamming', labelKey: 'hann.lbl');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
