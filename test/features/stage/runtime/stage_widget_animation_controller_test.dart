// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/runtime/stage_widget_animation_controller.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';

import '_fakes.dart';

void main() {
  group('StageWidgetAnimationController contract', () {
    test('setInput records calls and pause/play round-trip is clean', () {
      final controller = FakeAnimationController(
        declaredInputs: {'value', 'alarm'},
      );

      // Initially nothing.
      expect(controller.isPlayingAtConstruction, isFalse);

      controller.play();
      expect(controller.playing, isTrue);
      expect(controller.playCount, 1);

      final r1 = controller.setInput('value', const NormalizedDouble(0.5));
      expect(r1.kind, SetInputResultKind.applied);
      expect(controller.calls.single.key, 'value');
      expect(controller.calls.single.value, const NormalizedDouble(0.5));

      controller.pause();
      expect(controller.playing, isFalse);
      expect(controller.pauseCount, 1);

      controller.play();
      expect(controller.playing, isTrue);
      expect(controller.playCount, 2);

      controller.dispose();
      expect(controller.isDisposed, isTrue);
      expect(controller.disposeCount, 1);
    });

    test('SetInputResult variants compare structurally', () {
      final a = SetInputResult.applied(inputName: 'x');
      final b = SetInputResult.applied(inputName: 'x');
      final c = SetInputResult.applied(inputName: 'y');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('hasInput reports declared inputs', () {
      final controller = FakeAnimationController(declaredInputs: {'value'});
      expect(controller.hasInput('value'), isTrue);
      expect(controller.hasInput('missing'), isFalse);
    });

    test('setInput on undeclared input returns inputMissing', () {
      final controller = FakeAnimationController(declaredInputs: {'value'});
      final r = controller.setInput('ghost', const NormalizedDouble(1));
      expect(r.kind, SetInputResultKind.inputMissing);
    });

    test('NormalizedXZ samples are reported as heldStale', () {
      final controller = FakeAnimationController(declaredInputs: {'value'});
      final r = controller.setInput('value', const NormalizedXZ(isX: true));
      expect(r.kind, SetInputResultKind.heldStale);
    });
  });
}

extension on FakeAnimationController {
  bool get isPlayingAtConstruction => playing;
}
