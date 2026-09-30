// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Type discriminator for one named input on a Rive state machine.
enum RiveInputType {
  /// `NumberInput` — accepts doubles.
  number,

  /// `BooleanInput` — accepts booleans.
  boolean,

  /// `TriggerInput` — fires on call (no value payload).
  trigger,
}

/// Narrow surface that abstracts the Rive runtime away from the controller
/// integration logic.
///
/// The default implementation (`RiveRuntimeStateMachineHost`) wraps a real
/// Rive `StateMachine`. Tests substitute a `_FakeRiveStateMachineHost` so
/// `RiveBackedAnimationController` can be unit-tested without loading
/// binary `.riv` assets.
///
/// Methods are intentionally minimal — only what the controller needs:
///
/// - [setNumber] / [setBoolean] / [fireTrigger] write to a named input.
///   Each returns `true` when the input exists and was written; `false`
///   when no input with that name and type is available.
/// - [hasInput] / [inputType] expose introspection so the controller can
///   route a `NormalizedString` enum-state to a matching trigger only when
///   one actually exists.
/// - [play] / [pause] / [dispose] manage playback lifecycle on the
///   underlying state machine.
abstract class RiveStateMachineHost {
  /// Name of the bound state machine.
  String get stateMachineName;

  /// True if an input with the given [name] is declared on the state
  /// machine, regardless of its type.
  bool hasInput(String name);

  /// Returns the type of the input named [name], or `null` if it is not
  /// declared.
  RiveInputType? inputType(String name);

  /// Writes [value] to the number input named [name]. Returns `true` when
  /// the input exists and is a number; `false` otherwise.
  bool setNumber(String name, double value);

  /// Writes [value] to the boolean input named [name]. Returns `true` when
  /// the input exists and is a boolean; `false` otherwise.
  bool setBoolean(String name, {required bool value});

  /// Fires the trigger input named [name]. Returns `true` when the input
  /// exists and is a trigger; `false` otherwise.
  bool fireTrigger(String name);

  /// Starts (or resumes) playback.
  void play();

  /// Suspends playback.
  void pause();

  /// Releases native / runtime resources.
  void dispose();
}
