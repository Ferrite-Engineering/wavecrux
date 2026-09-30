// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:logging/logging.dart';
import 'package:wavecrux/domain/enums/log_verbosity.dart';

/// **WaveCrux logging-level rubric** — pick the level by what happened, not by
/// how loud you want to be. The verbosity setting decides how much is *shown*;
/// the call site decides the *level*:
///
/// - `SEVERE`  — a user-visible operation failed, data was lost, or an
///   uncaught error fired (waveform open failed, export failed, crash).
/// - `WARNING` — silent degradation / a feature fell back without telling the
///   user (filter didn't load, bookmark failed, mDNS discovery failed,
///   auto-save failed, a malformed input row was skipped).
/// - `INFO`    — notable lifecycle events (collab connected/disconnected,
///   one-shot migration ran).
/// - `CONFIG`  — environment/config resolved at startup.
/// - `FINE`/`FINER`/`FINEST` — high-frequency or deep-internal breadcrumbs
///   (per-broadcast send errors, decode-step traces). Hidden unless the user
///   raises verbosity.
///
/// The issue-reporter ring buffer always captures *every* level regardless of
/// the verbosity setting, so a bug report stays complete.

/// Maps the user-facing [LogVerbosity] onto a concrete `package:logging`
/// [Level] threshold. Records at or above the returned level pass the filter;
/// records below it are hidden (from the console sink / Logs-panel default).
///
/// Kept out of the domain layer because [Level] is a third-party type.
extension LogVerbosityLevel on LogVerbosity {
  /// The minimum [Level] a record must reach to be shown at this verbosity.
  Level get threshold => switch (this) {
    LogVerbosity.quiet => Level.WARNING,
    LogVerbosity.normal => Level.INFO,
    LogVerbosity.detailed => Level.FINE,
    LogVerbosity.verbose => Level.ALL,
  };
}
