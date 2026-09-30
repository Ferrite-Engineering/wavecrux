// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/bitfield_translator_config.dart';
import 'package:wavecrux/domain/models/custom_translator_def.dart';

void main() {
  const def = CustomTranslatorDef(
    name: 'AXI ARSIZE',
    config: BitfieldTranslatorConfig(
      fields: [
        BitFieldSpec(name: 'size', hiBit: 2, loBit: 0),
      ],
    ),
  );

  test('fromMap/toMap round-trip', () {
    final restored = CustomTranslatorDef.fromMap(def.toMap());
    expect(restored, def);
    expect(restored.config.fields, hasLength(1));
  });

  test('equality and hashCode', () {
    final a = CustomTranslatorDef.fromMap(def.toMap());
    expect(a, def);
    expect(a.hashCode, def.hashCode);
    expect(a == def.copyWith(name: 'other'), isFalse);
  });

  test('fromMap tolerates a missing config', () {
    final restored = CustomTranslatorDef.fromMap(const {'name': 'x'});
    expect(restored.name, 'x');
    expect(restored.config.fields, isEmpty);
  });
}
