// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';

/// Library-agnostic controller seam for the animation runtime that drives a
/// Stage Pro custom widget.
///
/// The Stage Pro SDK ships a single concrete implementation —
/// `RiveBackedAnimationController` — because Rive is the sole supported
/// animation library. The interface itself is deliberately library-agnostic: keeping the
/// seam means a future addition would land as a new implementation rather
/// than an SDK-wide refactor.
///
/// The contract is intentionally narrow:
///
/// - [setInput] pushes one normalized signal sample into a named animation
///   parameter. Implementations decide how the value type maps onto the
///   underlying animation library (e.g. for Rive: `NormalizedDouble` →
///   number input, `NormalizedBool` → boolean input, `NormalizedString` →
///   trigger input matching the value, `NormalizedXZ` → leave the previous
///   value intact). Returns a [SetInputResult] so the renderer can surface
///   stale-input or warning UX without re-inspecting the implementation.
/// - [play] starts (or resumes) the named state machine. A null name picks
///   the implementation's default state machine.
/// - [pause] suspends advancement without releasing resources.
/// - [dispose] releases all underlying animation resources. After dispose,
///   no other method may be called.
///
/// Implementations must be safe to construct on the main isolate and run
/// for the full lifetime of one widget instance — they do not need to be
/// re-entrant across isolates.
abstract class StageWidgetAnimationController {
  /// Pushes [value] into the named [inputName] animation parameter.
  ///
  /// Returns a [SetInputResult] describing whether the input was applied,
  /// missing, type-mismatched, or held-stale (X/Z policy).
  SetInputResult setInput(String inputName, NormalizedValue value);

  /// Starts (or resumes) animation playback on [stateMachineName]. Pass
  /// `null` to use the implementation's default state machine.
  void play([String? stateMachineName]);

  /// Suspends playback without releasing resources. Subsequent [play]
  /// resumes from the current state.
  void pause();

  /// Releases all resources held by this controller. Must be called by
  /// the renderer when the widget is removed from the tree.
  void dispose();

  /// Whether [dispose] has been invoked. Useful for asserting lifetime
  /// expectations in tests.
  bool get isDisposed;

  /// True iff the underlying animation exposes an input named [inputName].
  ///
  /// Used by the renderer to early-validate manifest bindings before pumping
  /// samples — a manifest declaring an input the animation does not expose
  /// surfaces the localized "Widget failed to load" placeholder rather than
  /// failing silently on every sample. Implementations that cannot
  /// introspect their underlying animation should return `true` (defer to
  /// `setInput` returning [SetInputResultKind.inputMissing]).
  bool hasInput(String inputName);
}

/// Outcome of one [StageWidgetAnimationController.setInput] call.
///
/// The renderer uses this to surface debug indicators (e.g. a "stale" badge
/// when an X/Z sample held the previous value) and to log warnings when an
/// input the manifest declared is missing from the underlying animation.
@immutable
class SetInputResult {
  const SetInputResult._({
    required this.kind,
    this.inputName,
    this.message,
  });

  /// The input was applied successfully.
  factory SetInputResult.applied({required String inputName}) =>
      SetInputResult._(
        kind: SetInputResultKind.applied,
        inputName: inputName,
      );

  /// The previous value was held — typically because an X/Z sample arrived
  /// and the renderer's policy is "leave prior value intact".
  factory SetInputResult.heldStale({
    required String inputName,
    String? message,
  }) => SetInputResult._(
    kind: SetInputResultKind.heldStale,
    inputName: inputName,
    message: message,
  );

  /// The named input does not exist on the underlying animation.
  factory SetInputResult.inputMissing({
    required String inputName,
    String? message,
  }) => SetInputResult._(
    kind: SetInputResultKind.inputMissing,
    inputName: inputName,
    message: message,
  );

  /// The value's runtime type does not match the input's expected type
  /// (e.g. a boolean value pushed into a numeric input). Implementations
  /// log and skip rather than throwing.
  factory SetInputResult.typeMismatch({
    required String inputName,
    String? message,
  }) => SetInputResult._(
    kind: SetInputResultKind.typeMismatch,
    inputName: inputName,
    message: message,
  );

  /// Outcome category.
  final SetInputResultKind kind;

  /// The input that was targeted, when known.
  final String? inputName;

  /// Optional human-readable explanation (debug builds may surface this in
  /// tooltips or logs).
  final String? message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetInputResult &&
          kind == other.kind &&
          inputName == other.inputName &&
          message == other.message;

  @override
  int get hashCode => Object.hash(kind, inputName, message);

  @override
  String toString() =>
      'SetInputResult(kind: $kind, inputName: $inputName, message: $message)';
}

/// Kind discriminator for [SetInputResult].
enum SetInputResultKind {
  /// The value was successfully written to the input.
  applied,

  /// The renderer chose to leave the input at its previous value (X/Z policy).
  heldStale,

  /// The named input is not present on the underlying animation.
  inputMissing,

  /// The value's type does not match the input's expected type.
  typeMismatch,
}
