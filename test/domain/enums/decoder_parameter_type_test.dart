// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';

void main() {
  group('DecoderParameterType', () {
    test('has four values', () {
      expect(DecoderParameterType.values, hasLength(4));
    });

    test('values are boolean, integer, enumeration, string', () {
      expect(
        DecoderParameterType.values,
        containsAll([
          DecoderParameterType.boolean,
          DecoderParameterType.integer,
          DecoderParameterType.enumeration,
          DecoderParameterType.string,
        ]),
      );
    });

    test('name does not collide with dart reserved keyword', () {
      expect(DecoderParameterType.enumeration.name, 'enumeration');
    });

    test('each value has a distinct name', () {
      final names = DecoderParameterType.values.map((v) => v.name).toSet();
      expect(names, hasLength(DecoderParameterType.values.length));
    });
  });
}
