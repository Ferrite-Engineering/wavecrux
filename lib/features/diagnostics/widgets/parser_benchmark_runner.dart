// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/features/diagnostics/providers/dev_tools_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

/// "Benchmark This File" widget hosted in the Tab Diagnostics drawer.
///
/// Opens the currently loaded file with a fresh [WellenProvider] (FFI),
/// records parse time, signal count, and throughput, and renders the
/// result. The active viewer source is not touched — the benchmark uses
/// its own independent provider instance.
///
/// Web is not supported: on web, files are loaded via in-memory byte
/// buffers that are not retained for re-parsing, so timing the active
/// backend without those bytes would force the user to reload the file.
/// The Run button is disabled on web with an explanatory tooltip.
class ParserBenchmarkRunner extends ConsumerWidget {
  const ParserBenchmarkRunner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final state = ref.watch(devToolsProvider);
    final notifier = ref.read(devToolsProvider.notifier);

    final filePath = ref.watch(waveformSourceProvider.notifier).currentFilePath;
    final fileLoaded = filePath != null;
    final disabled = state.isBenchmarkRunning || !fileLoaded || kIsWeb;

    final tooltip = kIsWeb
        ? l10n.diagnosticsBenchmarkDisabledWeb
        : !fileLoaded
        ? l10n.diagnosticsBenchmarkDisabledNoFile
        : null;

    // Hosted inside the Tab Diagnostics drawer's outer SingleChildScrollView,
    // so this widget renders its full content vertically without an inner
    // scroll wrapper — nesting two vertical viewports would give this
    // widget's scroll an unbounded height.
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Tooltip(
            message: tooltip ?? '',
            child: FilledButton.icon(
              onPressed: disabled
                  ? null
                  : () => _runBenchmark(ref, notifier, filePath),
              icon: state.isBenchmarkRunning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.speed_rounded, size: 18),
              label: Text(
                state.isBenchmarkRunning
                    ? l10n.diagnosticsBenchmarkRunning
                    : l10n.diagnosticsBenchmarkRun,
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (state.benchmarkError != null)
            _ErrorCard(message: state.benchmarkError!)
          else if (state.benchmarkResult != null)
            _ResultsTable(result: state.benchmarkResult!, l10n: l10n)
          else
            Text(
              l10n.diagnosticsBenchmarkEmpty,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Future<void> _runBenchmark(
    WidgetRef ref,
    DevToolsNotifier notifier,
    String path,
  ) async {
    notifier.startBenchmark();

    try {
      final fileSizeBytes = await File(path).length();

      final provider = WellenProvider();
      final watch = Stopwatch()..start();
      await provider.openFile(path);
      watch.stop();
      final parseMs = watch.elapsedMilliseconds;
      final signalCount = _countSignals(provider.rootScopes);
      provider.close();

      notifier.completeBenchmark(
        BenchmarkResult(
          fileSizeBytes: fileSizeBytes,
          signalCount: signalCount,
          parseMs: parseMs,
        ),
      );
    } on Object catch (e) {
      notifier.failBenchmark(e.toString());
    }
  }

  int _countSignals(List<Scope> scopes) =>
      scopes.fold(0, (sum, s) => sum + s.totalVariableCount);
}

// ── Private helpers ──────────────────────────────────────────────────────────

class _ResultsTable extends StatelessWidget {
  const _ResultsTable({required this.result, required this.l10n});

  final BenchmarkResult result;
  final L10N l10n;

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(3),
      },
      border: TableBorder.all(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      children: [
        _row(
          context,
          l10n.diagnosticsBenchmarkFileSize,
          _formatBytes(result.fileSizeBytes),
        ),
        _row(
          context,
          l10n.diagnosticsBenchmarkSignals,
          '${result.signalCount}',
        ),
        _row(
          context,
          l10n.diagnosticsBenchmarkParseTime,
          '${result.parseMs} ms',
        ),
        _row(
          context,
          l10n.diagnosticsBenchmarkThroughput,
          '${result.throughputMbps.toStringAsFixed(1)} MB/s',
        ),
      ],
    );
  }

  TableRow _row(BuildContext context, String label, String value) {
    final style = Theme.of(context).textTheme.bodySmall;
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            label,
            style: style?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(value, style: style),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
