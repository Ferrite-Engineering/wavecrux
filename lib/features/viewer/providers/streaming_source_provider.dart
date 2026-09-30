// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// StreamingSourceNotifier — manages the lifecycle of an interactive /
// streaming VCD session (Section 4.3.1).
//
// Start streaming from stdin with [startFromStdin] or from a named pipe with
// [startFromPipe]. The [StreamingVcdService] is registered with
// [WaveformSourceNotifier] via [attachStreamingSource] so the rest of the
// viewer (canvas, value column, signal tree) works without modification.
//
// The notifier state ([StreamingViewerState]) drives the toolbar LIVE badge
// and Stop button.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/waveform/streaming_vcd_service.dart';

part 'streaming_source_provider.g.dart';

// ── State model ───────────────────────────────────────────────────────────────

/// State emitted by [StreamingSourceNotifier].
sealed class StreamingViewerState {
  const StreamingViewerState();
}

/// No active streaming session.
@immutable
final class StreamingViewerIdle extends StreamingViewerState {
  const StreamingViewerIdle();

  @override
  bool operator ==(Object other) => other is StreamingViewerIdle;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Header is being parsed — the hierarchy is not yet available.
@immutable
final class StreamingViewerStarting extends StreamingViewerState {
  const StreamingViewerStarting();

  @override
  bool operator ==(Object other) => other is StreamingViewerStarting;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Streaming in progress — value changes are arriving.
///
/// [elapsed] is the wall-clock time since streaming started.
/// [currentEndTime] is the latest simulation timestamp received.
@immutable
final class StreamingViewerActive extends StreamingViewerState {
  const StreamingViewerActive({
    required this.elapsed,
    required this.currentEndTime,
  });

  final Duration elapsed;
  final int currentEndTime;

  StreamingViewerActive copyWith({
    Duration? elapsed,
    int? currentEndTime,
  }) => StreamingViewerActive(
    elapsed: elapsed ?? this.elapsed,
    currentEndTime: currentEndTime ?? this.currentEndTime,
  );

  @override
  bool operator ==(Object other) =>
      other is StreamingViewerActive &&
      other.elapsed == elapsed &&
      other.currentEndTime == currentEndTime;

  @override
  int get hashCode => Object.hash(elapsed, currentEndTime);
}

// ── Notifier ──────────────────────────────────────────────────────────────────

/// Manages interactive / streaming VCD mode.
///
/// Call [startFromStdin] or [startFromPipe] to begin; [stop] to end. The
/// [StreamingVcdService] is injected into [WaveformSourceNotifier] so the
/// full viewer UI is available immediately after the header is parsed.
///
/// The notifier auto-transitions back to [StreamingViewerIdle] when the
/// underlying stream reaches EOF so the user can browse the final waveform.
@Riverpod(keepAlive: true)
class StreamingSourceNotifier extends _$StreamingSourceNotifier {
  StreamingVcdService? _service;
  StreamSubscription<void>? _updateSub;
  Timer? _elapsedTimer;
  DateTime? _startedAt;

  /// The active [StreamingVcdService] while streaming is in progress.
  ///
  /// Returns `null` when the notifier is in the [StreamingViewerIdle] state.
  /// Exposed for integration tests that need to wait on the underlying
  /// stream lifecycle (e.g. `streamEndedFuture`, `currentEndTime`) — see
  /// `integration_test/streaming/`.
  @visibleForTesting
  StreamingVcdService? get serviceForTesting => _service;

  @override
  StreamingViewerState build() => const StreamingViewerIdle();

  // ── public methods ────────────────────────────────────────────────────────

  /// Starts streaming from stdin.
  ///
  /// Resolves once the VCD header is parsed and the hierarchy is available.
  /// Throws [UnsupportedError] on Flutter Web.
  Future<void> startFromStdin() async {
    if (kIsWeb) {
      throw UnsupportedError('Streaming VCD is not supported on Flutter Web.');
    }
    await _start(stdin);
  }

  /// Starts streaming from a named pipe at [path].
  ///
  /// Resolves once the VCD header is parsed and the hierarchy is available.
  /// Throws [UnsupportedError] on Flutter Web.
  Future<void> startFromPipe(String path) async {
    if (kIsWeb) {
      throw UnsupportedError('Streaming VCD is not supported on Flutter Web.');
    }
    await _start(File(path).openRead());
  }

  /// Stops streaming and returns to [StreamingViewerIdle].
  ///
  /// The waveform data accumulated so far remains in [WaveformSourceNotifier]
  /// and is still queryable — the user can browse the final waveform normally.
  void stop() => _stopInternal();

  /// Starts streaming from an arbitrary byte [stream].
  ///
  /// This is the test-only entry point that lets integration tests drive
  /// the full streaming pipeline (header parse → `attachStreamingSource` →
  /// hierarchy population → LIVE-badge state machine → EOF auto-stop)
  /// without depending on a real stdin / FIFO. Production code calls
  /// [startFromStdin] or [startFromPipe], both of which delegate to the
  /// same private `_start` method this method exposes.
  @visibleForTesting
  Future<void> startFromStream(Stream<List<int>> stream) => _start(stream);

  // ── internal ──────────────────────────────────────────────────────────────

  Future<void> _start(Stream<List<int>> stream) async {
    _stopInternal();

    final service = StreamingVcdService();
    _service = service;
    _startedAt = DateTime.now();
    state = const StreamingViewerStarting();

    // Register the service with the waveform source provider so the viewer UI
    // picks it up without going through the normal openFile path.
    ref.read(waveformSourceProvider.notifier).attachStreamingSource(service);

    // When the stream ends naturally, auto-stop so the toolbar badge disappears
    // and the user can browse the final waveform. Guard with `ref.mounted` —
    // the future may complete after the notifier has been disposed (test
    // teardown, hot reload), and `_stopInternal` writes to `state`.
    unawaited(
      service.streamEndedFuture.then((_) {
        if (!ref.mounted) return;
        if (_service == service) _stopInternal();
      }),
    );

    // Wait for the header so the hierarchy is available before returning.
    try {
      await service.startAndWaitForHeader(stream);
    } on Object {
      _stopInternal();
      rethrow;
    }

    // Header parsed — start elapsed ticker and subscribe to data updates.
    // `ref.mounted` guards: Riverpod 3 disposes the notifier eagerly, but the
    // Timer / Stream callbacks can still fire one tick later and would touch
    // `state` on a disposed notifier (throws `UnmountedRefException`).
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!ref.mounted) return;
      if (_startedAt != null && state is StreamingViewerActive) {
        final elapsed = DateTime.now().difference(_startedAt!);
        state = (state as StreamingViewerActive).copyWith(elapsed: elapsed);
      }
    });

    _updateSub = service.onDataUpdated.listen((_) {
      if (!ref.mounted) return;
      if (state is StreamingViewerActive) {
        state = (state as StreamingViewerActive).copyWith(
          currentEndTime: service.currentEndTime,
        );
      }
    });

    state = StreamingViewerActive(
      elapsed: DateTime.now().difference(_startedAt!),
      currentEndTime: service.currentEndTime,
    );
  }

  void _stopInternal() {
    _service?.stop();
    _service = null;
    unawaited(_updateSub?.cancel());
    _updateSub = null;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _startedAt = null;
    state = const StreamingViewerIdle();
  }
}
