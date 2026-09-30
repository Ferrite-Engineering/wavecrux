// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_file_watcher/crux_file_watcher.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

part 'file_watcher_provider.g.dart';

// ── FileWatchState ────────────────────────────────────────────────────────────

/// State emitted by [FileWatcherNotifier].
sealed class FileWatchState {
  const FileWatchState();
}

/// No active notification — either no file is loaded or the last event was
/// dismissed by the user.
@immutable
final class FileWatchIdle extends FileWatchState {
  const FileWatchIdle();

  @override
  bool operator ==(Object other) => other is FileWatchIdle;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The watched file was modified on disk.
@immutable
final class FileWatchChanged extends FileWatchState {
  const FileWatchChanged();

  @override
  bool operator ==(Object other) => other is FileWatchChanged;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// The watched file was deleted or moved away from its original path.
@immutable
final class FileWatchDeleted extends FileWatchState {
  const FileWatchDeleted();

  @override
  bool operator ==(Object other) => other is FileWatchDeleted;

  @override
  int get hashCode => runtimeType.hashCode;
}

// ── FileWatcherNotifier ───────────────────────────────────────────────────────

/// Watches the currently loaded waveform file and emits [FileWatchState] when
/// the file changes or is deleted.
///
/// The watcher is restarted whenever [WaveformSourceNotifier] finishes loading
/// a new file. Call [dismiss] to return to [FileWatchIdle] after the UI has
/// handled the notification.
// Duration to suppress file-watch events after starting or restarting the
// watcher. WellenProvider's Rust FFI reads (and on macOS, any companion file
// writes from wellen) can trigger OS-level FS events that arrive at the
// FSEvents stream immediately after it is created, producing a spurious
// "file changed on disk" notification. Suppressing events for this window
// prevents that false positive without affecting real changes after the file
// has settled.
const _watchSettleDuration = Duration(seconds: 2);

@Riverpod(keepAlive: true)
class FileWatcherNotifier extends _$FileWatcherNotifier {
  late final FileWatcherService _service;
  StreamSubscription<FileWatchEvent>? _eventSub;
  Timer? _settleTimer;
  bool _settling = false;

  @override
  FileWatchState build() {
    _service = FileWatcherService();

    ref
      ..onDispose(() {
        _settleTimer?.cancel();
        unawaited(_eventSub?.cancel());
        _service.dispose();
      })
      // Restart the watcher whenever the loaded source changes.
      ..listen<AsyncValue<WaveformDataSource?>>(
        waveformSourceProvider,
        (_, next) {
          if (!next.isLoading) _restartWatch();
        },
      );

    _restartWatch();
    return const FileWatchIdle();
  }

  /// Resets the state to [FileWatchIdle].
  ///
  /// Call this after the UI has handled a [FileWatchChanged] or
  /// [FileWatchDeleted] notification so that the next file-change event
  /// triggers a new notification.
  void dismiss() => state = const FileWatchIdle();

  void _restartWatch() {
    unawaited(_eventSub?.cancel());
    _eventSub = null;
    _settleTimer?.cancel();
    _settleTimer = null;
    _settling = false;
    _service.stopWatching();

    final path = ref.read(waveformSourceProvider.notifier).currentFilePath;
    if (path == null) {
      state = const FileWatchIdle();
      return;
    }

    // Suppress events for a short window after the watcher starts. On macOS,
    // FSEvents can deliver stale events from just before the stream was created
    // (e.g. file reads or companion file writes by WellenProvider's Rust FFI),
    // which would appear as a spurious "file changed on disk" notification.
    _settling = true;
    _settleTimer = Timer(_watchSettleDuration, () {
      _settling = false;
      _settleTimer = null;
      if (kDebugMode) {
        debugPrint('FileWatcher: settle window expired, watching $path');
      }
    });

    _eventSub = _service.events.listen((event) {
      if (_settling) return;
      state = switch (event) {
        FileWatchEvent.modified => const FileWatchChanged(),
        FileWatchEvent.deleted => const FileWatchDeleted(),
      };
    });
    _service.startWatching(path);
  }
}
