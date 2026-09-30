// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/models/decoder_parameter.dart';

void main() {
  group('DecoderParameter', () {
    const boolParam = DecoderParameter(
      name: 'cpol',
      type: DecoderParameterType.boolean,
      defaultValue: false,
      description: 'Clock polarity',
    );

    const enumParam = DecoderParameter(
      name: 'bit_order',
      type: DecoderParameterType.enumeration,
      defaultValue: 'msb_first',
      description: 'Bit order',
      enumValues: ['msb_first', 'lsb_first'],
    );

    const labeledParam = DecoderParameter(
      name: 'cs_active_level',
      displayName: 'CS Active Level',
      type: DecoderParameterType.enumeration,
      defaultValue: '0',
      description: 'Chip-select active level',
      enumValues: ['0', '1'],
      enumLabels: {'0': 'Active Low', '1': 'Active High'},
    );

    const keyedParam = DecoderParameter(
      name: 'cpol',
      displayName: 'CPOL',
      labelKey: 'spiParamCpol',
      descriptionKey: 'spiParamCpolDescription',
      type: DecoderParameterType.enumeration,
      defaultValue: '0',
      description: 'Clock polarity',
      enumValues: ['0', '1'],
      enumLabels: {'0': '0 (Idle Low)', '1': '1 (Idle High)'},
      enumLabelKeys: {'0': 'spiChoiceCpol0', '1': 'spiChoiceCpol1'},
    );

    // ── equality ──────────────────────────────────────────────────────────────

    test('equal when all fields match (no enumValues)', () {
      const other = DecoderParameter(
        name: 'cpol',
        type: DecoderParameterType.boolean,
        defaultValue: false,
        description: 'Clock polarity',
      );
      expect(boolParam, equals(other));
    });

    test('equal when enumValues match', () {
      const other = DecoderParameter(
        name: 'bit_order',
        type: DecoderParameterType.enumeration,
        defaultValue: 'msb_first',
        description: 'Bit order',
        enumValues: ['msb_first', 'lsb_first'],
      );
      expect(enumParam, equals(other));
    });

    test('not equal when enumValues differ', () {
      const other = DecoderParameter(
        name: 'bit_order',
        type: DecoderParameterType.enumeration,
        defaultValue: 'msb_first',
        description: 'Bit order',
        enumValues: ['msb_first'],
      );
      expect(enumParam, isNot(equals(other)));
    });

    test('not equal when one enumValues is null', () {
      const other = DecoderParameter(
        name: 'bit_order',
        type: DecoderParameterType.enumeration,
        defaultValue: 'msb_first',
        description: 'Bit order',
      );
      expect(enumParam, isNot(equals(other)));
    });

    test('both null enumValues are equal', () {
      const other = DecoderParameter(
        name: 'cpol',
        type: DecoderParameterType.boolean,
        defaultValue: false,
        description: 'Clock polarity',
      );
      expect(boolParam, equals(other));
    });

    test('not equal when name differs', () {
      const other = DecoderParameter(
        name: 'cpha',
        type: DecoderParameterType.boolean,
        defaultValue: false,
        description: 'Clock polarity',
      );
      expect(boolParam, isNot(equals(other)));
    });

    test('not equal when type differs', () {
      const other = DecoderParameter(
        name: 'cpol',
        type: DecoderParameterType.integer,
        defaultValue: false,
        description: 'Clock polarity',
      );
      expect(boolParam, isNot(equals(other)));
    });

    test('not equal when defaultValue differs', () {
      const other = DecoderParameter(
        name: 'cpol',
        type: DecoderParameterType.boolean,
        defaultValue: true,
        description: 'Clock polarity',
      );
      expect(boolParam, isNot(equals(other)));
    });

    test('hashCode consistent with equality', () {
      const other = DecoderParameter(
        name: 'cpol',
        type: DecoderParameterType.boolean,
        defaultValue: false,
        description: 'Clock polarity',
      );
      expect(boolParam.hashCode, equals(other.hashCode));
    });

    // ── displayName ───────────────────────────────────────────────────────────

    test('equal when both displayName are null', () {
      const a = DecoderParameter(
        name: 'x',
        type: DecoderParameterType.boolean,
        defaultValue: false,
        description: 'd',
      );
      const b = DecoderParameter(
        name: 'x',
        type: DecoderParameterType.boolean,
        defaultValue: false,
        description: 'd',
      );
      expect(a, equals(b));
    });

    test('equal when displayName matches', () {
      const a = DecoderParameter(
        name: 'x',
        displayName: 'My Param',
        type: DecoderParameterType.boolean,
        defaultValue: false,
        description: 'd',
      );
      const b = DecoderParameter(
        name: 'x',
        displayName: 'My Param',
        type: DecoderParameterType.boolean,
        defaultValue: false,
        description: 'd',
      );
      expect(a, equals(b));
    });

    test('not equal when displayName differs', () {
      const a = DecoderParameter(
        name: 'x',
        displayName: 'Alpha',
        type: DecoderParameterType.boolean,
        defaultValue: false,
        description: 'd',
      );
      const b = DecoderParameter(
        name: 'x',
        displayName: 'Beta',
        type: DecoderParameterType.boolean,
        defaultValue: false,
        description: 'd',
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when one displayName is null', () {
      const a = DecoderParameter(
        name: 'x',
        displayName: 'Alpha',
        type: DecoderParameterType.boolean,
        defaultValue: false,
        description: 'd',
      );
      const b = DecoderParameter(
        name: 'x',
        type: DecoderParameterType.boolean,
        defaultValue: false,
        description: 'd',
      );
      expect(a, isNot(equals(b)));
    });

    // ── enumLabels ────────────────────────────────────────────────────────────

    test('equal when both enumLabels are null', () {
      expect(enumParam, equals(enumParam.copyWith()));
    });

    test('equal when enumLabels match', () {
      const other = DecoderParameter(
        name: 'cs_active_level',
        displayName: 'CS Active Level',
        type: DecoderParameterType.enumeration,
        defaultValue: '0',
        description: 'Chip-select active level',
        enumValues: ['0', '1'],
        enumLabels: {'0': 'Active Low', '1': 'Active High'},
      );
      expect(labeledParam, equals(other));
    });

    test('not equal when enumLabels differ in value', () {
      const other = DecoderParameter(
        name: 'cs_active_level',
        displayName: 'CS Active Level',
        type: DecoderParameterType.enumeration,
        defaultValue: '0',
        description: 'Chip-select active level',
        enumValues: ['0', '1'],
        enumLabels: {'0': 'Active Low', '1': 'Active LOW'},
      );
      expect(labeledParam, isNot(equals(other)));
    });

    test('not equal when one enumLabels is null', () {
      const other = DecoderParameter(
        name: 'cs_active_level',
        displayName: 'CS Active Level',
        type: DecoderParameterType.enumeration,
        defaultValue: '0',
        description: 'Chip-select active level',
        enumValues: ['0', '1'],
      );
      expect(labeledParam, isNot(equals(other)));
    });

    test('hashCode consistent for labeled param', () {
      const other = DecoderParameter(
        name: 'cs_active_level',
        displayName: 'CS Active Level',
        type: DecoderParameterType.enumeration,
        defaultValue: '0',
        description: 'Chip-select active level',
        enumValues: ['0', '1'],
        enumLabels: {'0': 'Active Low', '1': 'Active High'},
      );
      expect(labeledParam.hashCode, equals(other.hashCode));
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    test('copyWith returns equal when no args', () {
      expect(boolParam.copyWith(), equals(boolParam));
    });

    test('copyWith updates name', () {
      expect(boolParam.copyWith(name: 'cpha').name, 'cpha');
    });

    test('copyWith updates type', () {
      expect(
        boolParam.copyWith(type: DecoderParameterType.integer).type,
        DecoderParameterType.integer,
      );
    });

    test('copyWith updates enumValues', () {
      expect(
        enumParam.copyWith(enumValues: ['a', 'b']).enumValues,
        ['a', 'b'],
      );
    });

    test('clearEnumValues sets enumValues to null', () {
      expect(enumParam.copyWith(clearEnumValues: true).enumValues, isNull);
    });

    test('copyWith updates displayName', () {
      expect(
        boolParam.copyWith(displayName: 'CPOL').displayName,
        'CPOL',
      );
    });

    test('clearDisplayName sets displayName to null', () {
      expect(
        labeledParam.copyWith(clearDisplayName: true).displayName,
        isNull,
      );
    });

    test('copyWith updates enumLabels', () {
      final updated = labeledParam.copyWith(
        enumLabels: {'0': 'Lo', '1': 'Hi'},
      );
      expect(updated.enumLabels, equals({'0': 'Lo', '1': 'Hi'}));
    });

    test('clearEnumLabels sets enumLabels to null', () {
      expect(
        labeledParam.copyWith(clearEnumLabels: true).enumLabels,
        isNull,
      );
    });

    test('copyWith preserves existing enumLabels when not specified', () {
      final updated = labeledParam.copyWith(displayName: 'New Name');
      expect(updated.enumLabels, equals(labeledParam.enumLabels));
    });

    // ── ARB key fields (labelKey / descriptionKey / enumLabelKeys) ──────────────

    test('default ARB key fields are null', () {
      expect(boolParam.labelKey, isNull);
      expect(boolParam.descriptionKey, isNull);
      expect(boolParam.enumLabelKeys, isNull);
    });

    test('ARB key fields are stored', () {
      expect(keyedParam.labelKey, 'spiParamCpol');
      expect(keyedParam.descriptionKey, 'spiParamCpolDescription');
      expect(
        keyedParam.enumLabelKeys,
        equals({'0': 'spiChoiceCpol0', '1': 'spiChoiceCpol1'}),
      );
    });

    test('equal when ARB key fields match', () {
      const other = DecoderParameter(
        name: 'cpol',
        displayName: 'CPOL',
        labelKey: 'spiParamCpol',
        descriptionKey: 'spiParamCpolDescription',
        type: DecoderParameterType.enumeration,
        defaultValue: '0',
        description: 'Clock polarity',
        enumValues: ['0', '1'],
        enumLabels: {'0': '0 (Idle Low)', '1': '1 (Idle High)'},
        enumLabelKeys: {'0': 'spiChoiceCpol0', '1': 'spiChoiceCpol1'},
      );
      expect(keyedParam, equals(other));
      expect(keyedParam.hashCode, equals(other.hashCode));
    });

    test('not equal when labelKey differs', () {
      final other = keyedParam.copyWith(labelKey: 'spiParamCpha');
      expect(keyedParam, isNot(equals(other)));
    });

    test('not equal when descriptionKey differs', () {
      final other = keyedParam.copyWith(descriptionKey: 'other');
      expect(keyedParam, isNot(equals(other)));
    });

    test('not equal when enumLabelKeys differ in value', () {
      final other = keyedParam.copyWith(
        enumLabelKeys: {'0': 'spiChoiceCpol0', '1': 'changed'},
      );
      expect(keyedParam, isNot(equals(other)));
    });

    test('not equal when one labelKey is null', () {
      final other = keyedParam.copyWith(clearLabelKey: true);
      expect(keyedParam, isNot(equals(other)));
    });

    test('not equal when one enumLabelKeys is null', () {
      final other = keyedParam.copyWith(clearEnumLabelKeys: true);
      expect(keyedParam, isNot(equals(other)));
    });

    test('copyWith updates labelKey', () {
      expect(boolParam.copyWith(labelKey: 'k').labelKey, 'k');
    });

    test('copyWith updates descriptionKey', () {
      expect(boolParam.copyWith(descriptionKey: 'k').descriptionKey, 'k');
    });

    test('copyWith updates enumLabelKeys', () {
      expect(
        boolParam.copyWith(enumLabelKeys: {'0': 'k'}).enumLabelKeys,
        equals({'0': 'k'}),
      );
    });

    test('clearLabelKey sets labelKey to null', () {
      expect(keyedParam.copyWith(clearLabelKey: true).labelKey, isNull);
    });

    test('clearDescriptionKey sets descriptionKey to null', () {
      expect(
        keyedParam.copyWith(clearDescriptionKey: true).descriptionKey,
        isNull,
      );
    });

    test('clearEnumLabelKeys sets enumLabelKeys to null', () {
      expect(
        keyedParam.copyWith(clearEnumLabelKeys: true).enumLabelKeys,
        isNull,
      );
    });

    test('copyWith preserves ARB key fields when not specified', () {
      final updated = keyedParam.copyWith(displayName: 'New');
      expect(updated.labelKey, keyedParam.labelKey);
      expect(updated.descriptionKey, keyedParam.descriptionKey);
      expect(updated.enumLabelKeys, equals(keyedParam.enumLabelKeys));
    });

    // ── toString ──────────────────────────────────────────────────────────────

    test('toString contains name, type, and default', () {
      final s = boolParam.toString();
      expect(s, contains('cpol'));
      expect(s, contains('boolean'));
      expect(s, contains('false'));
    });
  });
}
