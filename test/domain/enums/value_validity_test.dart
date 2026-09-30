// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/value_validity.dart';

void main() {
  test('exposes ok / hasX / hasZ in a stable order', () {
    expect(ValueValidity.values, [
      ValueValidity.ok,
      ValueValidity.hasX,
      ValueValidity.hasZ,
    ]);
  });
}
