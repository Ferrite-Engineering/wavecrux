// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Severity level of a cocotb log entry.
///
/// Mirrors the Python `logging` module's standard levels used by cocotb.
/// Ordered from least to most severe.
enum CocotbLogSeverity {
  /// Below [debug]. Cocotb registers it itself — `logging.addLevelName(5,
  /// "TRACE")` — so it is not one of Python's stock levels and does not appear
  /// unless something asks for it.
  ///
  /// Cocotb 2.1's `GPI_DEBUG` and `PYGPI_DEBUG` are what make that likely:
  /// both turn on TRACE logging. Before this entry existed the parser returned
  /// null for the level and **dropped the line**, so a user who enabled either
  /// variable lost output with nothing on screen to say why.
  trace,
  debug,
  info,
  warning,
  error,
  critical;

  /// Maps a string from a cocotb log line (e.g. `"INFO"`, `"warning"`) to a
  /// severity. Case-insensitive. Returns `null` for unrecognised input.
  ///
  /// Cocotb sometimes emits aliases (`WARN` for `WARNING`, `FATAL` for
  /// `CRITICAL`) inherited from Python's logging module — both are accepted.
  static CocotbLogSeverity? fromString(String value) {
    switch (value.trim().toUpperCase()) {
      case 'TRACE':
        return CocotbLogSeverity.trace;
      case 'DEBUG':
        return CocotbLogSeverity.debug;
      case 'INFO':
        return CocotbLogSeverity.info;
      case 'WARN':
      case 'WARNING':
        return CocotbLogSeverity.warning;
      case 'ERROR':
        return CocotbLogSeverity.error;
      case 'FATAL':
      case 'CRITICAL':
        return CocotbLogSeverity.critical;
      default:
        return null;
    }
  }

  /// Human-readable label for UI display (matches cocotb's emitted spelling).
  String get displayLabel => switch (this) {
    CocotbLogSeverity.trace => 'TRACE',
    CocotbLogSeverity.debug => 'DEBUG',
    CocotbLogSeverity.info => 'INFO',
    CocotbLogSeverity.warning => 'WARNING',
    CocotbLogSeverity.error => 'ERROR',
    CocotbLogSeverity.critical => 'CRITICAL',
  };
}
