// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:wavecrux/features/stage/runtime/rive_backed_animation_controller.dart';
import 'package:wavecrux/features/stage/runtime/rive_state_machine_host.dart';
import 'package:wavecrux/features/stage/runtime/stage_widget_animation_controller.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';

import '_fakes.dart';

void main() {
  group('RiveBackedAnimationController routing', () {
    late FakeRiveHost host;
    late RiveBackedAnimationController controller;

    setUp(() {
      host = FakeRiveHost(
        stateMachineName: 'main',
        inputs: {
          'speed': RiveInputType.number,
          'alarm': RiveInputType.boolean,
          'reset': RiveInputType.trigger,
          'idle': RiveInputType.trigger,
        },
      );
      controller = RiveBackedAnimationController(host: host);
    });

    tearDown(() {
      if (!controller.isDisposed) controller.dispose();
    });

    test('NormalizedDouble routes to a number input', () {
      final r = controller.setInput('speed', const NormalizedDouble(42.5));
      expect(r.kind, SetInputResultKind.applied);
      expect(host.numberWrites.single.key, 'speed');
      expect(host.numberWrites.single.value, 42.5);
      expect(host.boolWrites, isEmpty);
      expect(host.triggerFires, isEmpty);
    });

    test('NormalizedBool routes to a boolean input', () {
      final r = controller.setInput('alarm', const NormalizedBool(value: true));
      expect(r.kind, SetInputResultKind.applied);
      expect(host.boolWrites.single.key, 'alarm');
      expect(host.boolWrites.single.value, isTrue);
    });

    test('NormalizedString matching trigger by value fires the trigger', () {
      final r = controller.setInput('state', const NormalizedString('reset'));
      expect(r.kind, SetInputResultKind.applied);
      expect(r.inputName, 'reset');
      expect(host.triggerFires.single, 'reset');
    });

    test('NormalizedString matching trigger by binding name fires it', () {
      final r = controller.setInput('idle', const NormalizedString('whatever'));
      expect(r.kind, SetInputResultKind.applied);
      expect(r.inputName, 'idle');
      expect(host.triggerFires.single, 'idle');
    });

    test(
      'NormalizedString with no matching trigger logs and reports missing',
      () {
        final r = controller.setInput(
          'state',
          const NormalizedString('does_not_exist'),
        );
        expect(r.kind, SetInputResultKind.inputMissing);
        expect(host.triggerFires, isEmpty);
      },
    );

    test('NormalizedXZ leaves prior value intact and reports stale', () {
      // Push a real value first, then an X/Z sample; the X/Z must NOT
      // overwrite the host state.
      controller.setInput('speed', const NormalizedDouble(7));
      expect(host.numberWrites.single.key, 'speed');
      expect(host.numberWrites.single.value, 7);

      final r = controller.setInput('speed', const NormalizedXZ(isX: true));
      expect(r.kind, SetInputResultKind.heldStale);
      // Host received no further writes for the X sample.
      expect(host.numberWrites.length, 1);
    });

    test('Number input write to a missing input reports inputMissing', () {
      final r = controller.setInput('ghost', const NormalizedDouble(1));
      expect(r.kind, SetInputResultKind.inputMissing);
    });

    test(
      'Number input write to a boolean-typed input reports typeMismatch',
      () {
        final r = controller.setInput('alarm', const NormalizedDouble(1));
        expect(r.kind, SetInputResultKind.typeMismatch);
      },
    );

    test(
      'Boolean input write to a number-typed input reports typeMismatch',
      () {
        final r = controller.setInput(
          'speed',
          const NormalizedBool(value: true),
        );
        expect(r.kind, SetInputResultKind.typeMismatch);
      },
    );

    test(
      'NormalizedNumList is unsupported on Rive and reports typeMismatch',
      () {
        final r = controller.setInput('speed', NormalizedNumList(const [1, 2]));
        expect(r.kind, SetInputResultKind.typeMismatch);
      },
    );

    test('play and pause delegate to the host', () {
      controller.play();
      expect(host.playing, isTrue);
      controller.pause();
      expect(host.playing, isFalse);
    });

    test('dispose tears down the host and forbids further calls', () {
      controller.dispose();
      expect(host.disposed, isTrue);
      expect(controller.isDisposed, isTrue);
      expect(
        () => controller.setInput('speed', const NormalizedDouble(0)),
        throwsStateError,
      );
    });

    test('hasInput reflects host introspection', () {
      expect(controller.hasInput('speed'), isTrue);
      expect(controller.hasInput('ghost'), isFalse);
      controller.dispose();
      expect(controller.hasInput('speed'), isFalse);
    });

    // The renderers do not show a mismatch, and `developer.log` emits nothing
    // from a release build, so the product log is where a widget author finds
    // one. `setInput` runs on every sample, so each input is reported once.
    test('a binding that misses is warned once on the product log', () {
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);

      for (var i = 0; i < 5; i++) {
        controller
          ..setInput('ghost', NormalizedDouble(i.toDouble()))
          ..setInput('speed', const NormalizedBool(value: true));
      }

      final warnings = records.where((r) => r.loggerName == 'wavecrux.stage');
      expect(warnings.map((r) => r.level).toSet(), {Level.WARNING});
      expect(warnings, hasLength(2));
      expect(warnings.first.message, contains('"ghost"'));
      expect(warnings.last.message, contains('"speed"'));
    });
  });
}
