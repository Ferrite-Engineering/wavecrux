// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// User-selectable logging verbosity (Settings → Diagnostics).
///
/// Controls the threshold of the **console sink** and the **default level
/// filter** of the Diagnostics → Logs panel. It does **not** change what the
/// in-app issue-reporter ring buffer captures — that always records every
/// level so a bug report stays complete regardless of this setting.
///
/// Pure domain enum (no `package:logging` dependency). The mapping to a
/// concrete `logging` [Level] lives in
/// `lib/services/logging/log_verbosity_level.dart`.
enum LogVerbosity {
  /// Errors and warnings only (WARNING+).
  quiet,

  /// Default — lifecycle events, warnings, and errors (INFO+).
  normal,

  /// Adds high-frequency breadcrumbs and deep traces (FINE+).
  detailed,

  /// Everything the logging framework emits (ALL).
  verbose,
}
