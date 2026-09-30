// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/log_verbosity.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/services/logging/log_console_sink.dart';
import 'package:wavecrux/services/logging/log_verbosity_level.dart';
import 'package:wavecrux/services/logging/severe_log_stderr_sink.dart';

/// App-lifetime console log sink whose print threshold tracks the user's
/// Settings → Diagnostics "Log verbosity" choice.
///
/// Watch this once near the app root (e.g. in the root app widget's `build`)
/// so it stays attached for the whole session. Rebuilds — detaching the old
/// subscription and attaching a fresh one — whenever the verbosity changes.
///
/// The ring buffer (`CruxIssueReporterLogBuffer`) is unaffected: it always
/// captures every level so bug reports remain complete regardless of this
/// setting.
final logConsoleSinkProvider = Provider<LogConsoleSink>((ref) {
  final verbosity = ref.watch(
    appSettingsProvider.select(
      (s) => s.value?.logVerbosity ?? LogVerbosity.normal,
    ),
  );
  // SEVERE and above go to stderr once `bootstrap()` has attached that sink;
  // printing them here too would put every error on both streams.
  final stderrSink = SevereLogStderrSink.instance;
  final sink = LogConsoleSink(
    threshold: verbosity.threshold,
    ceiling: stderrSink.isAttached ? SevereLogStderrSink.threshold : null,
  )..attach();
  ref.onDispose(sink.detach);
  return sink;
});
