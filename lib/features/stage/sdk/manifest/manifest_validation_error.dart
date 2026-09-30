// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// One validation failure encountered while parsing a Stage Pro widget
/// manifest.
///
/// The parser collects every error before returning so authors see a full
/// list of problems on each iteration rather than fixing them one at a
/// time. [line] and [column] are 1-based and refer to the byte position
/// of the offending YAML node, mirroring `package:yaml`'s span semantics.
@immutable
class ManifestValidationError {
  const ManifestValidationError({
    required this.message,
    required this.path,
    this.line,
    this.column,
  });

  /// Human-readable description of what went wrong.
  final String message;

  /// JSON-Pointer-style location of the offending node, e.g.
  /// `/signal_bindings/0/bit_width/min` or `/runtime`.
  final String path;

  /// 1-based source line of the offending YAML node, when available.
  final int? line;

  /// 1-based source column of the offending YAML node, when available.
  final int? column;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManifestValidationError &&
          message == other.message &&
          path == other.path &&
          line == other.line &&
          column == other.column;

  @override
  int get hashCode => Object.hash(message, path, line, column);

  @override
  String toString() {
    final loc = (line != null && column != null) ? '$line:$column' : '?:?';
    return 'ManifestValidationError($path @ $loc: $message)';
  }
}

/// Thrown by [StageWidgetManifest.fromYaml] when validation fails. Carries
/// every error the parser collected.
class ManifestValidationException implements Exception {
  const ManifestValidationException(this.errors);

  final List<ManifestValidationError> errors;

  @override
  String toString() {
    final lines = errors.map((e) => '  • $e').join('\n');
    return 'ManifestValidationException with ${errors.length} '
        'error(s):\n$lines';
  }
}
