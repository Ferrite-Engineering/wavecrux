// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/signal_direction.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';

void main() {
  group('SignalDirection', () {
    group('values', () {
      test('has exactly 4 values', () {
        expect(SignalDirection.values.length, 4);
      });

      test('contains input, output, inout, unknown', () {
        expect(
          SignalDirection.values,
          containsAll([
            SignalDirection.input,
            SignalDirection.output,
            SignalDirection.inout,
            SignalDirection.unknown,
          ]),
        );
      });
    });

    group('fromVarDirection', () {
      test('maps VarDirection.input to SignalDirection.input', () {
        expect(
          SignalDirection.fromVarDirection(VarDirection.input),
          SignalDirection.input,
        );
      });

      test('maps VarDirection.output to SignalDirection.output', () {
        expect(
          SignalDirection.fromVarDirection(VarDirection.output),
          SignalDirection.output,
        );
      });

      test('maps VarDirection.inout to SignalDirection.inout', () {
        expect(
          SignalDirection.fromVarDirection(VarDirection.inout),
          SignalDirection.inout,
        );
      });

      test('maps VarDirection.unknown to SignalDirection.unknown', () {
        expect(
          SignalDirection.fromVarDirection(VarDirection.unknown),
          SignalDirection.unknown,
        );
      });

      test('maps VarDirection.implicit to SignalDirection.unknown', () {
        expect(
          SignalDirection.fromVarDirection(VarDirection.implicit),
          SignalDirection.unknown,
        );
      });

      test('maps VarDirection.buffer to SignalDirection.unknown', () {
        expect(
          SignalDirection.fromVarDirection(VarDirection.buffer),
          SignalDirection.unknown,
        );
      });

      test('maps VarDirection.linkage to SignalDirection.unknown', () {
        expect(
          SignalDirection.fromVarDirection(VarDirection.linkage),
          SignalDirection.unknown,
        );
      });

      test('all VarDirection values map without error', () {
        for (final dir in VarDirection.values) {
          expect(
            () => SignalDirection.fromVarDirection(dir),
            returnsNormally,
          );
        }
      });
    });
  });
}
