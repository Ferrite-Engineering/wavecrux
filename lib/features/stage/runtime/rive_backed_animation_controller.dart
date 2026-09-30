// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:logging/logging.dart';
import 'package:wavecrux/features/stage/runtime/rive_state_machine_host.dart';
import 'package:wavecrux/features/stage/runtime/stage_widget_animation_controller.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';

/// A widget whose bindings do not match its state machine. The renderers do
/// not show the [SetInputResult] these produce, and `developer.log` emits
/// nothing from a release build, so a widget author had no way to see why a
/// gauge stood still.
final _log = Logger('wavecrux.stage');

/// `StageWidgetAnimationController` implementation backed by a Rive state
/// machine.
///
/// Rive is the sole supported animation library. The controller is constructed
/// with a [RiveStateMachineHost] (typically wrapping a real Rive
/// `StateMachine`); tests substitute a fake host so the routing logic can be
/// unit-tested without binary `.riv` assets.
///
/// Routing rules for `setInput(name, value)`:
///
/// - [NormalizedDouble] → write to the matching number input.
/// - [NormalizedBool]   → write to the matching boolean input.
/// - [NormalizedString] → if the matching input is a trigger and the input
///   name (or the value) matches the host's trigger names, fire it.
///   String enum-states whose name does not correspond to an existing
///   trigger log a non-fatal warning and return
///   [SetInputResultKind.inputMissing].
/// - [NormalizedNumList] → not currently supported on Rive inputs;
///   returns [SetInputResultKind.typeMismatch] with a logged warning.
/// - [NormalizedXZ] → leaves the input at its previous value and returns
///   [SetInputResultKind.heldStale] so the renderer can surface a per-input
///   "stale" indicator in debug builds.
///
/// Each input's warning is logged once per controller: `setInput` runs on
/// every sample, and a binding that misses misses on all of them.
class RiveBackedAnimationController implements StageWidgetAnimationController {
  /// Creates a controller bound to [host]. The controller takes ownership
  /// of [host] and disposes it from [dispose].
  RiveBackedAnimationController({required RiveStateMachineHost host})
    : _host = host;

  final RiveStateMachineHost _host;
  bool _disposed = false;
  bool _playing = false;

  /// Inputs whose warning has been logged; see the class doc.
  final Set<String> _warned = <String>{};

  @override
  bool get isDisposed => _disposed;

  /// Visible for tests. The bound state machine name.
  String get stateMachineName => _host.stateMachineName;

  @override
  bool hasInput(String inputName) {
    if (_disposed) return false;
    return _host.hasInput(inputName);
  }

  @override
  SetInputResult setInput(String inputName, NormalizedValue value) {
    _assertAlive();
    switch (value) {
      case NormalizedDouble(value: final v):
        return _writeNumber(inputName, v);
      case NormalizedBool(value: final v):
        return _writeBool(inputName, value: v);
      case NormalizedString(value: final v):
        return _writeStringAsTrigger(inputName, enumState: v);
      case NormalizedNumList():
        const message =
            'NormalizedNumList is not supported by the Rive runtime; '
            'split into per-channel scalar bindings.';
        _warnOnce(inputName, 'input "$inputName": $message');
        return SetInputResult.typeMismatch(
          inputName: inputName,
          message: message,
        );
      case NormalizedXZ():
        return SetInputResult.heldStale(
          inputName: inputName,
          message: 'X/Z sample held the previous value',
        );
    }
  }

  @override
  void play([String? stateMachineName]) {
    _assertAlive();
    if (stateMachineName != null &&
        stateMachineName != _host.stateMachineName) {
      _log.warning(
        'Stage Pro: play("$stateMachineName") requested but controller is '
        'bound to "${_host.stateMachineName}"; ignoring requested name.',
      );
    }
    _host.play();
    _playing = true;
  }

  @override
  void pause() {
    _assertAlive();
    _host.pause();
    _playing = false;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _host.dispose();
  }

  /// Visible for tests; reports whether the host is currently playing.
  bool get isPlaying => _playing;

  SetInputResult _writeNumber(String inputName, double value) {
    if (!_host.hasInput(inputName)) {
      return _missingInput(inputName);
    }
    if (_host.inputType(inputName) != RiveInputType.number) {
      return _typeMismatch(inputName, expected: 'number');
    }
    final ok = _host.setNumber(inputName, value);
    if (!ok) {
      return _typeMismatch(inputName, expected: 'number');
    }
    return SetInputResult.applied(inputName: inputName);
  }

  SetInputResult _writeBool(String inputName, {required bool value}) {
    if (!_host.hasInput(inputName)) {
      return _missingInput(inputName);
    }
    if (_host.inputType(inputName) != RiveInputType.boolean) {
      return _typeMismatch(inputName, expected: 'boolean');
    }
    final ok = _host.setBoolean(inputName, value: value);
    if (!ok) {
      return _typeMismatch(inputName, expected: 'boolean');
    }
    return SetInputResult.applied(inputName: inputName);
  }

  /// Routes a `NormalizedString` enum-state to a Rive trigger.
  ///
  /// Two routing strategies are tried in order:
  ///
  /// 1. The string value names a trigger directly (e.g. value `"alarm"`
  ///    fires the trigger named `"alarm"`). This is the typical state-
  ///    machine pattern where each enum state has a corresponding trigger.
  /// 2. Otherwise the binding name itself is treated as the trigger name
  ///    (e.g. binding `"state"` fires the trigger named `"state"`). This
  ///    suits widgets that pulse a single trigger every time the bound
  ///    enum signal changes.
  ///
  /// If neither matches, a non-fatal warning is logged and the method
  /// returns [SetInputResultKind.inputMissing].
  SetInputResult _writeStringAsTrigger(
    String inputName, {
    required String enumState,
  }) {
    // Strategy 1: value names a trigger.
    if (_host.inputType(enumState) == RiveInputType.trigger) {
      _host.fireTrigger(enumState);
      return SetInputResult.applied(inputName: enumState);
    }
    // Strategy 2: binding name names a trigger.
    if (_host.inputType(inputName) == RiveInputType.trigger) {
      _host.fireTrigger(inputName);
      return SetInputResult.applied(inputName: inputName);
    }
    final message =
        'No trigger input matches enum state "$enumState" or binding '
        '"$inputName".';
    _warnOnce(inputName, message);
    return SetInputResult.inputMissing(
      inputName: inputName,
      message: message,
    );
  }

  SetInputResult _missingInput(String inputName) {
    final message =
        'Input "$inputName" is not declared on state machine '
        '"${_host.stateMachineName}".';
    _warnOnce(inputName, message);
    return SetInputResult.inputMissing(
      inputName: inputName,
      message: message,
    );
  }

  SetInputResult _typeMismatch(
    String inputName, {
    required String expected,
  }) {
    final message =
        'Input "$inputName" is not a $expected on state machine '
        '"${_host.stateMachineName}".';
    _warnOnce(inputName, message);
    return SetInputResult.typeMismatch(
      inputName: inputName,
      message: message,
    );
  }

  void _warnOnce(String inputName, String message) {
    if (_warned.add(inputName)) _log.warning('Stage Pro: $message');
  }

  void _assertAlive() {
    if (_disposed) {
      throw StateError(
        'RiveBackedAnimationController used after dispose() — the renderer '
        'should never invoke setInput / play / pause on a disposed '
        'controller.',
      );
    }
  }
}
