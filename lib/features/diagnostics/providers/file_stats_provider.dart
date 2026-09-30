// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/file_stats.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/diagnostics/file_stats_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

part 'file_stats_provider.g.dart';

/// Derives a [FileStats] snapshot whenever a waveform file is loaded.
///
/// Returns `null` while no file is open (loading, error, or idle state).
/// Rebuilds whenever the source changes (new file opened or closed).
/// [FileStats.totalTransitions] reflects all signals in the file — computed
/// once by the background isolate at open time.
@riverpod
FileStats? fileStats(Ref ref) {
  final sourceAsync = ref.watch(waveformSourceProvider);

  return sourceAsync.whenOrNull(
    data: (source) {
      if (source == null) return null;
      final notifier = ref.read(waveformSourceProvider.notifier);

      // Extract WellenProvider-specific data when available.
      final wellenSource = source is WellenProvider ? source : null;
      final formatOverride = wellenSource?.fileFormat;
      final totalTransitionsOverride = wellenSource?.totalTransitions;

      return const FileStatsService().collect(
        source: source,
        filePath: notifier.currentFilePath ?? '',
        parseTime: notifier.lastParseTime ?? Duration.zero,
        formatOverride: formatOverride,
        totalTransitionsOverride: totalTransitionsOverride,
        originalFormat: notifier.originalFormat?.isLegacy ?? false
            ? notifier.originalFormat
            : null,
        convertedAt: notifier.convertedAt,
      );
    },
  );
}
