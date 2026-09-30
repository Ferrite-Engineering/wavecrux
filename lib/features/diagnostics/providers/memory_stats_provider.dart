// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/memory_stats.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/diagnostics/memory_stats_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

part 'memory_stats_provider.g.dart';

/// Polls memory and resource usage every 2 seconds while the diagnostics
/// panel is open.
///
/// Returns `null` when no waveform file is loaded.  The provider is
/// auto-disposed when the diagnostics panel closes, which also cancels the
/// timer.
@riverpod
class MemoryStatsNotifier extends _$MemoryStatsNotifier {
  Timer? _timer;
  bool _disposed = false;

  @override
  MemoryStats? build() {
    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
    });
    _startPolling();
    return null;
  }

  void _startPolling() {
    // Defer first update past build() so state can be set on the notifier.
    unawaited(Future.microtask(_update));
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _update(),
    );
  }

  Future<void> _update() async {
    final sourceAsync = ref.read(waveformSourceProvider);
    final source = sourceAsync.value;

    if (source == null) {
      if (!_disposed) state = null;
      return;
    }

    int? wellenBytes;
    if (source is WellenProvider) {
      wellenBytes = await source.memoryUsageBytes();
    }

    if (!_disposed) {
      state = const MemoryStatsService().collect(
        source: source,
        wellenMemoryBytes: wellenBytes,
      );
    }
  }
}
