// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Operator used to compare a signal's value to a literal in a [SignalCondition].
enum ConditionOperator {
  /// Equal: signal == value.
  eq,

  /// Not equal: signal != value.
  neq,

  /// Greater than: signal > value (unsigned numeric comparison).
  gt,

  /// Less than: signal < value (unsigned numeric comparison).
  lt,

  /// Greater than or equal: signal >= value.
  gte,

  /// Less than or equal: signal <= value.
  lte,

  /// Bitwise AND non-zero: `(signal & value) != 0`.
  ///
  /// True when at least one bit from [SignalCondition.value] is set in the
  /// signal.  Use this to test whether a specific bit or group of bits is
  /// asserted.
  bitAnd,

  /// All mask bits set: `(signal & value) == value`.
  ///
  /// True when every bit specified in [SignalCondition.value] is set in the
  /// signal.  Use this to test whether a full bit-mask is present.
  bitOr,
}

/// A boolean expression tree that can be evaluated against a snapshot of signal
/// values at a given simulation time.
///
/// Sealed hierarchy:
/// - [SignalCondition] — compares one signal to a numeric literal.
/// - [AndExpression] — logical AND of two sub-expressions.
/// - [OrExpression] — logical OR of two sub-expressions.
/// - [NotExpression] — logical NOT of a sub-expression.
///
/// Build expressions programmatically or via
/// `PatternSearchService.parseExpression`.
@immutable
sealed class PatternExpression {
  const PatternExpression();

  /// Returns every signal path referenced anywhere in this expression tree.
  Set<String> get signalPaths;
}

/// Compares a single signal's value to a numeric literal using [operator].
///
/// [value] is stored as the original literal string (`0x1F`, `0b1010`, `42`).
/// x/z states from the waveform never satisfy any comparison — they always
/// evaluate to `false`.
@immutable
final class SignalCondition extends PatternExpression {
  const SignalCondition({
    required this.signalPath,
    required this.operator,
    required this.value,
  });

  /// Fully-qualified signal reference path (e.g. `top.cpu.data_bus[7:0]`).
  final String signalPath;

  final ConditionOperator operator;

  /// The right-hand-side numeric literal as entered (`0x1F`, `0b1010`, `42`).
  final String value;

  @override
  Set<String> get signalPaths => {signalPath};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SignalCondition &&
          runtimeType == other.runtimeType &&
          signalPath == other.signalPath &&
          operator == other.operator &&
          value == other.value;

  @override
  int get hashCode => Object.hash(signalPath, operator, value);

  @override
  String toString() => 'SignalCondition($signalPath ${operator.name} $value)';
}

/// Logical AND: both [left] and [right] must evaluate to `true`.
@immutable
final class AndExpression extends PatternExpression {
  const AndExpression({required this.left, required this.right});

  final PatternExpression left;
  final PatternExpression right;

  @override
  Set<String> get signalPaths => {...left.signalPaths, ...right.signalPaths};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AndExpression &&
          runtimeType == other.runtimeType &&
          left == other.left &&
          right == other.right;

  @override
  int get hashCode => Object.hash(left, right);

  @override
  String toString() => 'AndExpression($left, $right)';
}

/// Logical OR: at least one of [left] or [right] must evaluate to `true`.
@immutable
final class OrExpression extends PatternExpression {
  const OrExpression({required this.left, required this.right});

  final PatternExpression left;
  final PatternExpression right;

  @override
  Set<String> get signalPaths => {...left.signalPaths, ...right.signalPaths};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrExpression &&
          runtimeType == other.runtimeType &&
          left == other.left &&
          right == other.right;

  @override
  int get hashCode => Object.hash(left, right);

  @override
  String toString() => 'OrExpression($left, $right)';
}

/// Logical NOT: [operand] must evaluate to `false`.
@immutable
final class NotExpression extends PatternExpression {
  const NotExpression({required this.operand});

  final PatternExpression operand;

  @override
  Set<String> get signalPaths => operand.signalPaths;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotExpression &&
          runtimeType == other.runtimeType &&
          operand == other.operand;

  @override
  int get hashCode => Object.hash(NotExpression, operand);

  @override
  String toString() => 'NotExpression($operand)';
}
