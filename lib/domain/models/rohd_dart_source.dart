// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A position in a Dart source file, as ROHD's source tracing recorded it.
@immutable
class RohdDartLocation {
  /// Creates a location.
  const RohdDartLocation({
    required this.file,
    required this.line,
    required this.column,
  });

  /// The Dart file: absolute when the package root was found, else relative to
  /// the package.
  final String file;

  /// 1-based line.
  final int line;

  /// 1-based column.
  final int column;

  /// `file:line:column`, the form an editor command takes.
  String get target => '$file:$line:$column';

  @override
  bool operator ==(Object other) =>
      other is RohdDartLocation &&
      other.file == file &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(file, line, column);

  @override
  String toString() => target;
}

/// The Dart line a waveform signal was created on (ROHD 0.7 or later, source
/// tracing).
@immutable
class RohdDartSource {
  /// Creates a Dart source.
  const RohdDartSource({
    required this.primary,
    this.calledFrom = const <RohdDartLocation>[],
    this.candidates = 1,
  });

  /// The innermost frame: the Dart line that created the signal.
  final RohdDartLocation primary;

  /// The frames outward from [primary], nearest caller first.
  final List<RohdDartLocation> calledFrom;

  /// How many different Dart lines the signal's name matched in the source-trace
  /// file. More than one means it could not be told apart (two bus slices of a
  /// signal share a name); [primary] is then the first the file listed.
  final int candidates;

  /// Whether [primary] is one of several equally good matches.
  bool get ambiguous => candidates > 1;
}
