// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Riverpod state machine for an active LXT/LXT2 → FST conversion.
//
// Owned by [WaveformSourceNotifier]: the open path calls [begin],
// [updateProgress], [completeSuccess] / [completeWithError]; the UI watches
// the resulting state to drive the progress dialog and reacts to the
// last-event sentinel to drive the legacy-format banner.
//
// Hand-written (not `@riverpod` generated) so introducing the file does not
// require a `build_runner` step on every clone, matching the pattern used by
// [lxt2fst_providers.dart].

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/waveform_format.dart';
import 'package:wavecrux/services/waveform/lxt2fst_conversion_types.dart';

/// Raised by [WaveformSourceNotifier]'s convert-on-open path when the user
/// taps Cancel in the progress dialog. Surfaces as an [AsyncError] on the
/// waveform-source provider so the open-file callsite returns to the
/// previous state. Carries no information beyond identity — the cancel
/// reason is the user action.
@immutable
class LegacyConversionCancelledException implements Exception {
  const LegacyConversionCancelledException();

  @override
  String toString() => 'LegacyConversionCancelledException';
}

/// Immutable snapshot of the currently active LXT/LXT2 → FST conversion.
///
/// The idle state — no conversion in flight — is [LegacyConversionState.idle].
@immutable
class LegacyConversionState {
  const LegacyConversionState({
    required this.inProgress,
    required this.sourcePath,
    required this.origin,
    required this.progress,
    required this.startedAt,
  });

  /// The idle constant — no conversion is running.
  static const LegacyConversionState idle = LegacyConversionState(
    inProgress: false,
    sourcePath: null,
    origin: null,
    progress: null,
    startedAt: null,
  );

  /// `true` while a conversion is running.
  final bool inProgress;

  /// Absolute path of the source `.lxt` / `.lxt2` file. Null when [idle].
  final String? sourcePath;

  /// Origin format of the conversion (LXT or LXT2). Null when [idle].
  final WaveformFormat? origin;

  /// Most recent progress event from the converter. Null between [begin] and
  /// the first emitted progress event, or when [idle].
  final ConversionProgress? progress;

  /// Wall-clock time at which the conversion started. The progress dialog
  /// uses this to implement the 250 ms show-after debounce — files that
  /// complete in under that interval never flash a dialog.
  final DateTime? startedAt;

  LegacyConversionState copyWith({
    bool? inProgress,
    String? sourcePath,
    WaveformFormat? origin,
    ConversionProgress? progress,
    DateTime? startedAt,
  }) => LegacyConversionState(
    inProgress: inProgress ?? this.inProgress,
    sourcePath: sourcePath ?? this.sourcePath,
    origin: origin ?? this.origin,
    progress: progress ?? this.progress,
    startedAt: startedAt ?? this.startedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LegacyConversionState &&
          other.inProgress == inProgress &&
          other.sourcePath == sourcePath &&
          other.origin == origin &&
          other.progress == progress &&
          other.startedAt == startedAt;

  @override
  int get hashCode =>
      Object.hash(inProgress, sourcePath, origin, progress, startedAt);
}

/// One-shot record describing the most recently completed *fresh* legacy
/// conversion (i.e. one that actually ran the converter — not a cache hit).
///
/// Drives the legacy-format banner: the viewer screen watches the
/// "last event" provider and shows the banner exactly once per fresh
/// conversion, then leaves the event in place so a re-mount of the tab does
/// not duplicate the banner.
@immutable
class LegacyConversionEvent {
  const LegacyConversionEvent({
    required this.origin,
    required this.fstPath,
    required this.completedAt,
    required this.sequence,
  });

  /// Origin format (LXT or LXT2).
  final WaveformFormat origin;

  /// Absolute path of the cached `.fst` produced by the conversion.
  final String fstPath;

  /// Wall-clock completion time. Surfaced in the Diagnostics → File Info
  /// "Original Format" row ("converted to FST on …").
  final DateTime completedAt;

  /// Monotonically increasing counter — lets `ref.listen` distinguish two
  /// back-to-back conversions of the same source file.
  final int sequence;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LegacyConversionEvent &&
          other.origin == origin &&
          other.fstPath == fstPath &&
          other.completedAt == completedAt &&
          other.sequence == sequence;

  @override
  int get hashCode => Object.hash(origin, fstPath, completedAt, sequence);
}

/// Notifier the open path owns and the UI watches.
class LegacyConversionController extends Notifier<LegacyConversionState> {
  void Function()? _cancelHook;

  @override
  LegacyConversionState build() => LegacyConversionState.idle;

  /// Hook the open path installs so the dialog's Cancel button can stop the
  /// underlying converter stream subscription. Cleared on [completeSuccess]
  /// / [completeWithError] / [cancel].
  // ignore: avoid_setters_without_getters
  set cancelHook(void Function()? hook) => _cancelHook = hook;

  /// Start tracking a fresh conversion. Sets [LegacyConversionState.inProgress]
  /// to `true` and records the start time so the dialog's 250 ms
  /// show-after debounce can fire.
  void begin({
    required String sourcePath,
    required WaveformFormat origin,
    DateTime? now,
  }) {
    state = LegacyConversionState(
      inProgress: true,
      sourcePath: sourcePath,
      origin: origin,
      progress: null,
      startedAt: now ?? DateTime.now(),
    );
  }

  /// Forward a new [progress] event from the converter to the UI. No-op when
  /// no conversion is in progress.
  void updateProgress(ConversionProgress progress) {
    if (!state.inProgress) return;
    state = state.copyWith(progress: progress);
  }

  /// Mark the active conversion as finished successfully. Clears state and
  /// drops the cancel hook.
  void completeSuccess() {
    _cancelHook = null;
    state = LegacyConversionState.idle;
  }

  /// Mark the active conversion as finished with an error. Same state
  /// transition as [completeSuccess] from the UI's perspective; the error
  /// itself is surfaced through the open path's normal AsyncError flow.
  void completeWithError() {
    _cancelHook = null;
    state = LegacyConversionState.idle;
  }

  /// Invoke the installed cancel hook (typically a `StreamSubscription.cancel`)
  /// and reset to idle. Used by the progress dialog's Cancel button.
  void cancel() {
    final hook = _cancelHook;
    _cancelHook = null;
    state = LegacyConversionState.idle;
    hook?.call();
  }
}

/// One-shot event sink for the most recent fresh conversion.
///
/// Distinct from [LegacyConversionController] because the dialog cares about
/// the "in-flight" axis ([LegacyConversionState]) while the banner cares
/// about the "just completed successfully" edge. Keeping them separate avoids
/// the dialog flickering on the trailing event and the banner racing against
/// the same state.
class LegacyConversionEventSink extends Notifier<LegacyConversionEvent?> {
  int _nextSequence = 1;

  @override
  LegacyConversionEvent? build() => null;

  /// Emit a fresh-conversion event. Only called when an actual conversion
  /// ran — cache hits never emit so the banner never fires for them.
  void emit({
    required WaveformFormat origin,
    required String fstPath,
    DateTime? completedAt,
  }) {
    state = LegacyConversionEvent(
      origin: origin,
      fstPath: fstPath,
      completedAt: completedAt ?? DateTime.now(),
      sequence: _nextSequence++,
    );
  }

  /// Wipe the most recent event so the banner stops rendering. Called by the
  /// banner's Dismiss / "Don't show again" actions and by tests to reset
  /// between cases.
  void clear() => state = null;
}

/// The active [LegacyConversionController]. Root-scoped keep-alive: only one
/// open file is loading at any moment so the in-flight axis is global.
final NotifierProvider<LegacyConversionController, LegacyConversionState>
legacyConversionControllerProvider =
    NotifierProvider<LegacyConversionController, LegacyConversionState>(
      LegacyConversionController.new,
    );

/// The most-recent-fresh-conversion event sink. Root-scoped keep-alive so
/// `ref.listen` callers can observe the same edge regardless of tab.
final NotifierProvider<LegacyConversionEventSink, LegacyConversionEvent?>
legacyConversionEventProvider =
    NotifierProvider<LegacyConversionEventSink, LegacyConversionEvent?>(
      LegacyConversionEventSink.new,
    );
