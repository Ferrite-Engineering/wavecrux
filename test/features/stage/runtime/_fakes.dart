// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/features/stage/runtime/rive_state_machine_host.dart';
import 'package:wavecrux/features/stage/runtime/stage_widget_animation_controller.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';

/// In-memory `StageWidgetAnimationController` used in tests to verify the
/// renderer pipeline without engaging Rive.
class FakeAnimationController implements StageWidgetAnimationController {
  FakeAnimationController({
    required Set<String> declaredInputs,
  }) : _declaredInputs = declaredInputs;

  final Set<String> _declaredInputs;
  final List<MapEntry<String, NormalizedValue>> calls = [];
  bool _disposed = false;
  bool playing = false;
  String? lastPlayName;
  int playCount = 0;
  int pauseCount = 0;
  int disposeCount = 0;

  @override
  bool get isDisposed => _disposed;

  @override
  bool hasInput(String inputName) => _declaredInputs.contains(inputName);

  @override
  SetInputResult setInput(String inputName, NormalizedValue value) {
    calls.add(MapEntry(inputName, value));
    if (value is NormalizedXZ) {
      return SetInputResult.heldStale(inputName: inputName);
    }
    if (!_declaredInputs.contains(inputName)) {
      return SetInputResult.inputMissing(inputName: inputName);
    }
    return SetInputResult.applied(inputName: inputName);
  }

  @override
  void play([String? stateMachineName]) {
    lastPlayName = stateMachineName;
    playing = true;
    playCount += 1;
  }

  @override
  void pause() {
    playing = false;
    pauseCount += 1;
  }

  @override
  void dispose() {
    _disposed = true;
    disposeCount += 1;
  }
}

/// Minimal `RiveStateMachineHost` whose declared input set is configurable.
class FakeRiveHost implements RiveStateMachineHost {
  FakeRiveHost({
    required this.stateMachineName,
    Map<String, RiveInputType> inputs = const {},
  }) : _inputs = Map.of(inputs);

  @override
  final String stateMachineName;

  final Map<String, RiveInputType> _inputs;

  final List<MapEntry<String, double>> numberWrites = [];
  final List<MapEntry<String, bool>> boolWrites = [];
  final List<String> triggerFires = [];
  bool playing = false;
  bool disposed = false;

  @override
  bool hasInput(String name) => _inputs.containsKey(name);

  @override
  RiveInputType? inputType(String name) => _inputs[name];

  @override
  bool setNumber(String name, double value) {
    if (_inputs[name] != RiveInputType.number) return false;
    numberWrites.add(MapEntry(name, value));
    return true;
  }

  @override
  bool setBoolean(String name, {required bool value}) {
    if (_inputs[name] != RiveInputType.boolean) return false;
    boolWrites.add(MapEntry(name, value));
    return true;
  }

  @override
  bool fireTrigger(String name) {
    if (_inputs[name] != RiveInputType.trigger) return false;
    triggerFires.add(name);
    return true;
  }

  @override
  void play() {
    playing = true;
  }

  @override
  void pause() {
    playing = false;
  }

  @override
  void dispose() {
    disposed = true;
  }
}
