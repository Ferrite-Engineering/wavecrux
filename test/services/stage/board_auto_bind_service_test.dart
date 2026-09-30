// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/board_auto_bind_candidate.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_widget_slot.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/stage/board_auto_bind_service.dart';

const _service = BoardAutoBindService();

Variable _v(String name, {int? bitWidth = 1, String scopePath = 'top'}) {
  final ref = scopePath.isEmpty ? name : '$scopePath.$name';
  return Variable(
    name: name,
    varType: VarType.wire,
    direction: VarDirection.unknown,
    signalRef: ref,
    scopePath: scopePath,
    bitWidth: bitWidth,
  );
}

StageWidgetSlot _slot(String name, {String childWidgetId = 'led'}) =>
    StageWidgetSlot(
      name: name,
      childWidgetId: childWidgetId,
      x: 0,
      y: 0,
      width: 0.05,
      height: 0.05,
    );

Map<String, Variable> _signalsByPath(Iterable<Variable> vs) => {
  for (final v in vs) v.fullPath: v,
};

void main() {
  group('BoardAutoBindService — vector fan-out', () {
    test('binds 16 LEDs to a 16-bit leds vector', () {
      final slots = [for (var i = 0; i < 16; i++) _slot('led$i')];
      final variables = _signalsByPath([
        _v('leds', bitWidth: 16),
      ]);
      final result = _service.computeBindings(
        slots: slots,
        availableSignals: variables,
      );
      // Every LED slot resolves to a per-bit binding into top.leds.
      for (var i = 0; i < 16; i++) {
        final c = result.candidates['led$i'];
        expect(c, isNotNull);
        expect(c!.confidence, BoardAutoBindConfidence.vectorFanOut);
        expect(c.binding?.signalRef, 'top.leds');
        expect(c.binding?.bitIndex, i);
        expect(c.familyPrefix, 'led');
      }
    });

    test('matches via known alias (led ↔ ld)', () {
      final slots = [for (var i = 0; i < 4; i++) _slot('led$i')];
      final variables = _signalsByPath([
        _v('ld', bitWidth: 4),
      ]);
      final result = _service.computeBindings(
        slots: slots,
        availableSignals: variables,
      );
      for (var i = 0; i < 4; i++) {
        final c = result.candidates['led$i']!;
        expect(c.confidence, BoardAutoBindConfidence.vectorFanOut);
        expect(c.binding?.signalRef, 'top.ld');
        expect(c.binding?.bitIndex, i);
      }
    });

    test('does not fan out when widths mismatch', () {
      final slots = [for (var i = 0; i < 16; i++) _slot('led$i')];
      final variables = _signalsByPath([
        _v('leds', bitWidth: 8),
      ]);
      final result = _service.computeBindings(
        slots: slots,
        availableSignals: variables,
      );
      // No vector fan-out — falls through to per-slot tier which can't
      // find anything either.
      for (var i = 0; i < 16; i++) {
        expect(
          result.candidates['led$i']!.confidence,
          isNot(BoardAutoBindConfidence.vectorFanOut),
        );
      }
    });
  });

  group('BoardAutoBindService — per-bit match', () {
    test('falls back to per-bit when no vector signal exists', () {
      final slots = [for (var i = 0; i < 4; i++) _slot('led$i')];
      final variables = _signalsByPath([
        for (var i = 0; i < 4; i++) _v('led$i'),
      ]);
      final result = _service.computeBindings(
        slots: slots,
        availableSignals: variables,
      );
      for (var i = 0; i < 4; i++) {
        final c = result.candidates['led$i']!;
        expect(c.confidence, BoardAutoBindConfidence.exactMatch);
        expect(c.binding?.signalRef, 'top.led$i');
        expect(c.binding?.bitIndex, isNull);
      }
    });
  });

  group('BoardAutoBindService — single-slot match', () {
    test('matches a non-family slot directly', () {
      final slots = [_slot('btnC')];
      final variables = _signalsByPath([_v('btnC')]);
      final result = _service.computeBindings(
        slots: slots,
        availableSignals: variables,
      );
      final c = result.candidates['btnC']!;
      expect(c.confidence, BoardAutoBindConfidence.exactMatch);
      expect(c.binding?.signalRef, 'top.btnC');
    });

    test('matches via alias (btn ↔ key)', () {
      final slots = [_slot('btn')];
      final variables = _signalsByPath([_v('key')]);
      final result = _service.computeBindings(
        slots: slots,
        availableSignals: variables,
      );
      final c = result.candidates['btn']!;
      expect(c.confidence, BoardAutoBindConfidence.knownAlias);
      expect(c.binding?.signalRef, 'top.key');
    });

    test('returns noMatch when no plausible signal exists', () {
      final slots = [_slot('totally_unique_slot')];
      final variables = _signalsByPath([_v('clock')]);
      final result = _service.computeBindings(
        slots: slots,
        availableSignals: variables,
      );
      final c = result.candidates['totally_unique_slot']!;
      expect(c.confidence, BoardAutoBindConfidence.noMatch);
      expect(c.binding, isNull);
    });
  });

  group('BoardAutoBindService — manual bindings preserved', () {
    test('passthrough manual binding stays intact', () {
      final slots = [for (var i = 0; i < 4; i++) _slot('led$i')];
      final variables = _signalsByPath([
        _v('leds', bitWidth: 4),
        _v('special'),
      ]);
      final result = _service.computeBindings(
        slots: slots,
        availableSignals: variables,
        existingBindings: const {
          'led0': StageSignalBinding(signalRef: 'top.special'),
        },
      );
      // led0 stays manually bound to top.special.
      expect(
        result.candidates['led0']!.binding?.signalRef,
        'top.special',
      );
      expect(result.candidates['led0']!.matchReason, 'manually bound');
      // led1..led3 take the vector fan-out from top.leds.
      for (var i = 1; i < 4; i++) {
        final c = result.candidates['led$i']!;
        expect(c.confidence, BoardAutoBindConfidence.vectorFanOut);
        expect(c.binding?.signalRef, 'top.leds');
        expect(c.binding?.bitIndex, i);
      }
    });
  });
}
