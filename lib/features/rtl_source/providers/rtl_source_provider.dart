// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/stems_entry.dart';
import 'package:wavecrux/domain/models/stems_file.dart';
import 'package:wavecrux/services/rtl_source/rtl_source_loader.dart';
import 'package:wavecrux/services/rtl_source/stems_parser.dart';

part 'rtl_source_provider.g.dart';

// ── State ─────────────────────────────────────────────────────────────────────

/// Status of the RTL stems file currently associated with the viewer.
enum RtlStemsStatus {
  /// No stems file is loaded.
  idle,

  /// The user-picked stems file is being parsed.
  loading,

  /// A stems file is loaded and ready for lookups.
  ready,

  /// Loading or parsing the stems file failed.
  error,
}

/// State held by [RtlSourceNotifier] for the RTL source-annotation feature.
///
/// Encapsulates: the parsed stems file, the path of the stems file on disk,
/// the currently-displayed RTL source file (loaded into memory), the current
/// jump target (signal ref + line number), and any user-visible error.
@immutable
class RtlSourceState {
  const RtlSourceState({
    this.status = RtlStemsStatus.idle,
    this.stemsPath,
    this.stems,
    this.currentSourceFile,
    this.currentLine,
    this.currentSignalRef,
    this.currentSignalPath,
    this.error,
  });

  final RtlStemsStatus status;
  final String? stemsPath;
  final StemsFile? stems;

  /// The RTL source file currently displayed by the panel (may be null when
  /// no signal has been selected yet).
  final RtlSourceFile? currentSourceFile;

  /// 1-based line number to highlight inside [currentSourceFile].
  final int? currentLine;

  /// Opaque signal ref of the most recent navigation target (used to display
  /// the value column annotation).
  final String? currentSignalRef;

  /// Full hierarchical signal path of the navigation target (e.g. `top.cpu.clk`).
  final String? currentSignalPath;

  /// Human-readable error from the most recent failed operation, or null.
  final String? error;

  /// True when a stems file has been loaded successfully.
  bool get hasStems => stems != null && stems!.isNotEmpty;

  RtlSourceState copyWith({
    RtlStemsStatus? status,
    String? stemsPath,
    StemsFile? stems,
    RtlSourceFile? currentSourceFile,
    int? currentLine,
    String? currentSignalRef,
    String? currentSignalPath,
    String? error,
    bool clearStems = false,
    bool clearSelection = false,
    bool clearError = false,
  }) {
    return RtlSourceState(
      status: status ?? this.status,
      stemsPath: clearStems ? null : (stemsPath ?? this.stemsPath),
      stems: clearStems ? null : (stems ?? this.stems),
      currentSourceFile: clearStems || clearSelection
          ? null
          : (currentSourceFile ?? this.currentSourceFile),
      currentLine: clearStems || clearSelection
          ? null
          : (currentLine ?? this.currentLine),
      currentSignalRef: clearStems || clearSelection
          ? null
          : (currentSignalRef ?? this.currentSignalRef),
      currentSignalPath: clearStems || clearSelection
          ? null
          : (currentSignalPath ?? this.currentSignalPath),
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RtlSourceState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          stemsPath == other.stemsPath &&
          stems == other.stems &&
          currentSourceFile == other.currentSourceFile &&
          currentLine == other.currentLine &&
          currentSignalRef == other.currentSignalRef &&
          currentSignalPath == other.currentSignalPath &&
          error == other.error;

  @override
  int get hashCode => Object.hash(
    status,
    stemsPath,
    stems,
    currentSourceFile,
    currentLine,
    currentSignalRef,
    currentSignalPath,
    error,
  );

  @override
  String toString() =>
      'RtlSourceState($status, '
      'stems: ${stems?.length ?? 0} entries, '
      'source: ${currentSourceFile?.path}, line: $currentLine)';
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// File-IO surface used by [RtlSourceNotifier]; abstracted to support test
/// injection without `dart:io` access.
abstract class StemsFileReader {
  Future<String> readAsString(String path);
}

class _DefaultStemsFileReader implements StemsFileReader {
  const _DefaultStemsFileReader();
  @override
  Future<String> readAsString(String path) => File(path).readAsString();
}

/// Manages the RTL source-annotation feature: which stems file is loaded,
/// which signal is currently being viewed, and which line of which source
/// file should be displayed.
///
/// Held alive across navigations so the loaded stems file persists while the
/// user moves between waveform views.
@Riverpod(keepAlive: true)
class RtlSourceNotifier extends _$RtlSourceNotifier {
  static const _parser = StemsParser();
  StemsFileReader _reader = const _DefaultStemsFileReader();
  RtlSourceLoader _loader = RtlSourceLoader();

  @override
  RtlSourceState build() => const RtlSourceState();

  /// Test/dependency-injection hook.  Replaces the disk-IO surfaces.
  @visibleForTesting
  void overrideForTest({
    StemsFileReader? reader,
    RtlSourceLoader? loader,
  }) {
    if (reader != null) _reader = reader;
    if (loader != null) _loader = loader;
  }

  /// Loads and parses the stems file at [path].
  ///
  /// On success, transitions to [RtlStemsStatus.ready] with the parsed
  /// [StemsFile] available for lookups.  On failure, transitions to
  /// [RtlStemsStatus.error] with [error] set to the failure reason.
  Future<void> loadStemsFile(String path) async {
    state = state.copyWith(
      status: RtlStemsStatus.loading,
      stemsPath: path,
      clearError: true,
    );
    String content;
    try {
      content = await _reader.readAsString(path);
    } on Exception catch (e) {
      state = state.copyWith(
        status: RtlStemsStatus.error,
        error: e.toString(),
      );
      return;
    }
    final StemsFile parsed;
    try {
      parsed = _parser.parse(content);
    } on Exception catch (e) {
      state = state.copyWith(
        status: RtlStemsStatus.error,
        error: e.toString(),
      );
      return;
    }
    _loader.clear();
    state = state.copyWith(
      status: RtlStemsStatus.ready,
      stems: parsed,
      clearSelection: true,
      clearError: true,
    );
  }

  /// Drops the loaded stems file and any displayed source.
  void clearStems() {
    _loader.clear();
    state = const RtlSourceState();
  }

  /// Clears just the displayed source-file selection (the stems file stays).
  void clearSelection() {
    state = state.copyWith(clearSelection: true, clearError: true);
  }

  /// Resolves [signalPath] (e.g. `top.cpu.clk`) against the loaded stems file
  /// and, on a hit, loads the referenced source file and stores the line
  /// number to highlight.
  ///
  /// Stores the [signalRef] alongside the path so the source-panel UI can
  /// look up the live value at the current cursor time.
  ///
  /// On no-match or load failure, sets `error` and leaves the previous
  /// selection intact.  Returns true on a successful navigation.
  Future<bool> showSignal({
    required String signalRef,
    required String signalPath,
  }) async {
    final stems = state.stems;
    if (stems == null) {
      state = state.copyWith(error: 'No stems file loaded.');
      return false;
    }
    final entry = stems.lookup(signalPath);
    if (entry == null) {
      state = state.copyWith(
        error: 'No stems mapping for "$signalPath".',
      );
      return false;
    }
    return await _navigateToEntry(
      entry: entry,
      signalRef: signalRef,
      signalPath: signalPath,
    );
  }

  /// Resolves a free-text signal name (e.g. clicked from the source view)
  /// to a stems entry and loads the file.  The stems lookup falls back to
  /// the local-name suffix tier when only a leaf name is provided.
  ///
  /// Unlike [showSignal] this does not require a known [signalRef]; useful
  /// when the user clicks a bare identifier in the rendered source.
  Future<bool> showByName(String name) async {
    final stems = state.stems;
    if (stems == null) {
      state = state.copyWith(error: 'No stems file loaded.');
      return false;
    }
    final entry = stems.lookup(name);
    if (entry == null) {
      state = state.copyWith(
        error: 'No stems mapping for "$name".',
      );
      return false;
    }
    return await _navigateToEntry(
      entry: entry,
      signalRef: null,
      signalPath: entry.path,
    );
  }

  Future<bool> _navigateToEntry({
    required StemsEntry entry,
    required String? signalRef,
    required String signalPath,
  }) async {
    try {
      final source = await _loader.load(entry.sourceFile);
      state = state.copyWith(
        currentSourceFile: source,
        currentLine: entry.lineNumber,
        currentSignalRef: signalRef,
        currentSignalPath: signalPath,
        clearError: true,
      );
      return true;
    } on RtlSourceLoadException catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    } on Exception catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }
}

// ── Derived providers ─────────────────────────────────────────────────────────

/// Convenience provider returning whether a stems file is currently loaded.
@riverpod
bool rtlStemsLoaded(Ref ref) {
  final s = ref.watch(rtlSourceProvider);
  return s.hasStems;
}
