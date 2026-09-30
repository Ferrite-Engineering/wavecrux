// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/search_mode.dart';
import 'package:wavecrux/domain/interfaces/debug_advisor_service.dart';

/// The `Enum` → telemetry-token bridge.
///
/// The ingestion Worker's property-value class has no capitals, so a Dart
/// enum's `lowerCamelCase` name cannot be sent as-is; it is dropped, silently,
/// leaving the event with one fewer dimension than the catalog claims.
enum _Shapes { plain, twoWords, ieee754Single, fixedPointQ, htmlParser, lxt2 }

void main() {
  final valueClass = RegExp(r'^[a-z0-9_]{1,64}$');

  test('splits camel humps and digit-adjacent capitals', () {
    expect(telemetryEnumToken(_Shapes.plain), 'plain');
    expect(telemetryEnumToken(_Shapes.twoWords), 'two_words');
    expect(telemetryEnumToken(_Shapes.ieee754Single), 'ieee754_single');
    expect(telemetryEnumToken(_Shapes.fixedPointQ), 'fixed_point_q');
    expect(telemetryEnumToken(_Shapes.htmlParser), 'html_parser');
  });

  test('leaves an already-lowercase name alone', () {
    expect(telemetryEnumToken(_Shapes.lxt2), 'lxt2');
    expect(telemetryEnumToken(SearchMode.substring), 'substring');
    expect(telemetryEnumToken(SearchMode.glob), 'glob');
  });

  test('every token of every instrumented enum passes the Worker class', () {
    for (final value in <Enum>[
      ...DisplayFormat.values,
      ...DebugAdvisorRuleId.values,
      ...DebugAdvisorSeverity.values,
      ...SearchMode.values,
    ]) {
      expect(
        telemetryEnumToken(value),
        matches(valueClass),
        reason: '${value.runtimeType}.${value.name} would be dropped',
      );
    }
  });

  test('tokens stay distinct within an enum', () {
    // Snake-casing is many-to-one in principle; two constants collapsing onto
    // one token would silently merge two rows in the dataset.
    for (final values in <List<Enum>>[
      DisplayFormat.values,
      DebugAdvisorRuleId.values,
      DebugAdvisorSeverity.values,
      SearchMode.values,
    ]) {
      final tokens = values.map(telemetryEnumToken).toList();
      expect(tokens.toSet(), hasLength(tokens.length));
    }
  });
}
