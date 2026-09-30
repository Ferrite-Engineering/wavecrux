// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/signal_integrity_report.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/diagnostics/signal_integrity_service.dart';

part 'signal_integrity_provider.g.dart';

/// On-demand signal integrity analysis notifier.
///
/// Initial state is [AsyncData] with `null` (no analysis run yet). Call
/// [runAnalysis] to start a run — the state transitions to [AsyncLoading]
/// while the service iterates every signal, then settles to [AsyncData] with
/// the completed [SignalIntegrityReport] or [AsyncError] on failure.
///
/// The provider auto-disposes when the diagnostics panel closes, which resets
/// the analysis state for the next panel open.
///
/// Declares [WaveformSourceNotifier] as a dependency because it reads the
/// per-tab [waveformSourceProvider]: callers must resolve it inside the active
/// tab's scope (the Tab Diagnostics drawer and the App Diagnostics report
/// service both do). Without the declaration a future root-scope read would
/// silently see the empty root source.
@Riverpod(dependencies: [WaveformSourceNotifier])
class SignalIntegrityNotifier extends _$SignalIntegrityNotifier {
  @override
  AsyncValue<SignalIntegrityReport?> build() => const AsyncData(null);

  /// Run the full signal integrity analysis on the currently loaded waveform.
  ///
  /// Does nothing (leaves state as [AsyncData] null) when no waveform is
  /// loaded.
  Future<void> runAnalysis() async {
    final source = ref.read(waveformSourceProvider).value;
    if (source == null) {
      state = const AsyncData(null);
      return;
    }

    state = const AsyncLoading<SignalIntegrityReport?>();
    state = await AsyncValue.guard(
      () => const SignalIntegrityService().analyze(source),
    );
  }
}
