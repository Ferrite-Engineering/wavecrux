// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dev_tools_provider.g.dart';

/// Parse timing and throughput results from a benchmark run.
@immutable
class BenchmarkResult {
  const BenchmarkResult({
    required this.fileSizeBytes,
    required this.signalCount,
    required this.parseMs,
  });

  /// Size of the benchmarked file in bytes.
  final int fileSizeBytes;

  /// Number of signals discovered during parsing.
  final int signalCount;

  /// Parse time for the active backend in milliseconds.
  final int parseMs;

  /// Throughput in MB/s, computed from [fileSizeBytes] and [parseMs].
  double get throughputMbps {
    if (parseMs <= 0) return 0;
    return (fileSizeBytes / 1024 / 1024) / (parseMs / 1000);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BenchmarkResult &&
        other.fileSizeBytes == fileSizeBytes &&
        other.signalCount == signalCount &&
        other.parseMs == parseMs;
  }

  @override
  int get hashCode => Object.hash(fileSizeBytes, signalCount, parseMs);
}

/// Mutable configuration and results state for the diagnostics panel.
@immutable
class DevToolsState {
  const DevToolsState({
    this.signalCount = 10,
    this.duration = 10000,
    this.includeAnalog = false,
    this.includeXz = false,
    this.seed = 42,
    this.isBenchmarkRunning = false,
    this.benchmarkResult,
    this.lastGeneratedPath,
    this.benchmarkError,
  });

  final int signalCount;
  final int duration;
  final bool includeAnalog;
  final bool includeXz;
  final int seed;
  final bool isBenchmarkRunning;
  final BenchmarkResult? benchmarkResult;
  final String? lastGeneratedPath;
  final String? benchmarkError;

  DevToolsState copyWith({
    int? signalCount,
    int? duration,
    bool? includeAnalog,
    bool? includeXz,
    int? seed,
    bool? isBenchmarkRunning,
    BenchmarkResult? benchmarkResult,
    String? lastGeneratedPath,
    String? benchmarkError,
    bool clearBenchmarkResult = false,
    bool clearBenchmarkError = false,
    bool clearLastGeneratedPath = false,
  }) {
    return DevToolsState(
      signalCount: signalCount ?? this.signalCount,
      duration: duration ?? this.duration,
      includeAnalog: includeAnalog ?? this.includeAnalog,
      includeXz: includeXz ?? this.includeXz,
      seed: seed ?? this.seed,
      isBenchmarkRunning: isBenchmarkRunning ?? this.isBenchmarkRunning,
      benchmarkResult: clearBenchmarkResult
          ? null
          : (benchmarkResult ?? this.benchmarkResult),
      lastGeneratedPath: clearLastGeneratedPath
          ? null
          : (lastGeneratedPath ?? this.lastGeneratedPath),
      benchmarkError: clearBenchmarkError
          ? null
          : (benchmarkError ?? this.benchmarkError),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DevToolsState &&
        other.signalCount == signalCount &&
        other.duration == duration &&
        other.includeAnalog == includeAnalog &&
        other.includeXz == includeXz &&
        other.seed == seed &&
        other.isBenchmarkRunning == isBenchmarkRunning &&
        other.benchmarkResult == benchmarkResult &&
        other.lastGeneratedPath == lastGeneratedPath &&
        other.benchmarkError == benchmarkError;
  }

  @override
  int get hashCode => Object.hash(
    signalCount,
    duration,
    includeAnalog,
    includeXz,
    seed,
    isBenchmarkRunning,
    benchmarkResult,
    lastGeneratedPath,
    benchmarkError,
  );
}

/// Manages configuration and results state for the diagnostics panel.
///
/// Synthetic-VCD generator configuration (signal count, duration, X/Z, seed)
/// is consumed by `Tools → Generate Test VCD…`. Benchmark fields drive the
/// per-tab "Benchmark This File" action which re-parses the active file with
/// a fresh provider and records timing.
@riverpod
class DevToolsNotifier extends _$DevToolsNotifier {
  @override
  DevToolsState build() => const DevToolsState();

  void setSignalCount(int count) =>
      state = state.copyWith(signalCount: count.clamp(1, 500));

  void setDuration(int duration) =>
      state = state.copyWith(duration: duration.clamp(100, 1000000));

  void setIncludeAnalog({required bool value}) =>
      state = state.copyWith(includeAnalog: value);

  void setIncludeXz({required bool value}) =>
      state = state.copyWith(includeXz: value);

  void setSeed(int seed) => state = state.copyWith(seed: seed);

  void setLastGeneratedPath(String path) =>
      state = state.copyWith(lastGeneratedPath: path);

  void startBenchmark() => state = state.copyWith(
    isBenchmarkRunning: true,
    clearBenchmarkError: true,
  );

  void completeBenchmark(BenchmarkResult result) => state = state.copyWith(
    isBenchmarkRunning: false,
    benchmarkResult: result,
    clearBenchmarkError: true,
  );

  void failBenchmark(String error) => state = state.copyWith(
    isBenchmarkRunning: false,
    benchmarkError: error,
  );
}
