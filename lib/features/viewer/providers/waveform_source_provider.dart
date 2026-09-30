// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
// Used only behind kIsWeb guards (stat-based staleness detection); the web
// build compiles dart:io as unsupported stubs, matching viewer_screen.dart.
import 'dart:io' show File, FileSystemEntityType;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/enums/waveform_format.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/providers/process_filter_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/switching_activity_provider.dart';
import 'package:wavecrux/features/viewer/providers/translate_filter_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_identity_provider.dart';
import 'package:wavecrux/features/viewer/providers/x_trace_provider.dart';
import 'package:wavecrux/services/collaboration/waveform_content_hash.dart';
import 'package:wavecrux/services/platform/security_scoped_bookmark_service.dart';
import 'package:wavecrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:wavecrux/services/waveform/legacy_conversion_controller.dart';
import 'package:wavecrux/services/waveform/legacy_format_detector.dart';
import 'package:wavecrux/services/waveform/lxt2fst_conversion_types.dart';
import 'package:wavecrux/services/waveform/lxt2fst_providers.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';
import 'package:wavecrux/services/waveform/wellen_wasm_provider.dart';

part 'waveform_source_provider.g.dart';

/// Captures waveform open/parse failures into the issue-reporter ring buffer.
final _log = Logger('wavecrux.waveform');

/// Marker error raised when the Flutter Web build attempts to load a file
/// but the WellenWasm module is not available (e.g. CSP blocks WebAssembly
/// or the user is on a browser without WASM support).
///
/// The viewer's error-state UI matches on this type to render a
/// "WebAssembly is required" message instead of a generic parse error.
class WebAssemblyRequiredError implements Exception {
  const WebAssemblyRequiredError();

  @override
  String toString() => 'WebAssembly is required';
}

/// The currently loaded [WaveformDataSource], or null when no file is open.
///
/// Call [WaveformSourceNotifier.openFile] to load a file and [close] to
/// release it. Kept alive across navigations so the loaded waveform persists.
///
/// One backend per platform — no fallback:
///  - Desktop / mobile (`dart:io` hosts): [WellenProvider] (Rust via FFI).
///  - Flutter Web: [WellenWasmProvider] (the same `wellen` crate compiled to
///    WebAssembly via wasm-bindgen). If the WASM module cannot load,
///    [openFromBytes] raises [WebAssemblyRequiredError] and the viewer's
///    error UI prompts the user to use a current browser.
@Riverpod(keepAlive: true)
class WaveformSourceNotifier extends _$WaveformSourceNotifier {
  WaveformDataSource? _activeSource;

  // Source currently being opened (not yet committed to _activeSource).
  // Stored so cancelLoad() can kill its isolate while openFile() is awaiting.
  WaveformDataSource? _pendingSource;

  // Incremented on every openFile() call and on cancelLoad(). Lets each
  // in-flight openFile() detect that it has been superseded and abort cleanly
  // without updating state.
  int _loadToken = 0;

  // Path for which security-scoped access is currently held (macOS sandbox).
  String? _accessingPath;

  /// The absolute file path of the currently loaded waveform, or null.
  ///
  /// Set synchronously when [openFile] is called; cleared on [close] or on
  /// parse failure. Read by session providers to capture the current source
  /// path when saving a session.
  String? currentFilePath;

  /// The last path passed to [openFile], regardless of whether loading succeeded.
  ///
  /// Retained even after a parse failure so that error-state UI can offer a
  /// "Try Again" action without the user having to re-select the file.
  String? lastAttemptedPath;

  /// Wall-clock duration of the most recent successful parse operation.
  ///
  /// Measured from just before the backend's [openFile] / [openBytes] call to
  /// just after it returns. Null until the first successful open. Reset to null
  /// when [close] is called.
  Duration? lastParseTime;

  /// The on-disk format of the file the user actually picked, *before* any
  /// convert-on-open routing.
  ///
  /// For VCD / FST / GHW this equals the wellen-reported format of the
  /// active source. For LXT / LXT2 it records the legacy origin even
  /// though the in-memory backing store is FST (the result of the
  /// `lxt2fst` conversion). Null when no file is open. Read by the
  /// Diagnostics → File Info pane to render the "Original format" row.
  WaveformFormat? originalFormat;

  /// Wall-clock time at which the `lxt2fst` convert-on-open path finished
  /// producing the cached FST for the currently loaded file. Null for native
  /// formats and null when a cache hit reused an already-converted FST
  /// (i.e. the conversion didn't run for *this* open). Surfaced by the
  /// Diagnostics → File Info "Original format" row as the date in
  /// "LXT2 (converted to FST on …)".
  DateTime? convertedAt;

  /// Modification time and size of [currentFilePath] captured when [openFile]
  /// started reading it. Read by [isSourceFileReplacedOnDisk] so the
  /// open-path dedupe in ViewerScreen can detect that the on-disk file was
  /// REPLACED since this parse — the iOS/Android share sheet imports every
  /// incoming file to `Documents/SharedImports/<name>`, so sharing a
  /// same-named file overwrites the previous import's path in place. Null on
  /// web, for byte-backed opens ([openBytes]), and when the stat fails.
  DateTime? sourceFileModifiedAt;

  /// See [sourceFileModifiedAt].
  int? sourceFileSizeBytes;

  @override
  AsyncValue<WaveformDataSource?> build() => const AsyncData(null);

  /// Records `file.opened` for a load that has already committed to [state].
  ///
  /// Called from the three commit points rather than from the entry points,
  /// because the catalog counts opens that *worked*: an unreadable file, a
  /// failed conversion, and a load superseded by a newer one are all attempts,
  /// and counting them would answer "which formats do users try" when the
  /// question the telemetry answers is which formats the reader must be good at.
  ///
  /// [format] is a [WaveformFormat] name or the literal `streaming` — both
  /// closed application vocabulary, never anything derived from the file.
  /// [WaveformFormat]'s constants are already lowercase, so they need no
  /// snake-casing pass to satisfy the ingestion Worker's value class; the
  /// catalog-conformance test pins that fact so a camelCase addition to the
  /// enum fails a build rather than losing the property at the edge.
  void _recordFileOpened(String format) {
    ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'file.opened',
            properties: <String, Object?>{'format': format},
          ),
        );
  }

  /// Opens [path] using the desktop / mobile [WellenProvider] (Rust FFI).
  ///
  /// Closes any previously loaded file first. Sets state to [AsyncLoading]
  /// during parsing and [AsyncError] if parsing fails.
  ///
  /// On macOS, resolves a stored security-scoped bookmark for [path] before
  /// reading (enabling access to recent files across app launches in the
  /// sandbox). After a successful open, saves a fresh bookmark so access is
  /// retained for future launches.
  ///
  /// When [preserveDecoders] is `true`, the call site has already
  /// captured the persisted decoder set (or is about to re-add one via
  /// [ActiveDecodersNotifier.restoreDecoders]) and does NOT want the
  /// default `clearAll()` on `activeDecodersProvider`. This is the
  /// explicit seam used by [SessionNotifier.loadFromPath] / the
  /// per-tab autosave-restore path to avoid the `clearAll()`-then-
  /// re-add flicker that would otherwise emit a transient empty state.
  /// Everything else — signals, cursors, markers, Stage
  /// workspace — is still reset; only the decoders escape the wipe.
  Future<void> openFile(String path, {bool preserveDecoders = false}) async {
    // Stamp this load so cancelLoad() can invalidate it.
    final token = ++_loadToken;

    // Re-opening the SAME path is a reload, not a new file: the file watcher's
    // auto-reload runs through here every time a simulation rewrites the dump.
    // Annotations must survive that, because surviving it *is* the feature —
    // re-simulate, and the notes that no longer hold flag themselves as
    // drifted. Wiping them on reload would delete the user's work at the exact
    // moment it became most useful.
    final isReloadOfSameFile = currentFilePath == path;

    // Clear viewer state from the previous file before loading the new one.
    ref.read(signalGroupsProvider.notifier).clear();
    ref.read(cursorStateProvider.notifier).clearAll();
    ref.invalidate(markerStateProvider);
    if (!isReloadOfSameFile) {
      ref.invalidate(annotationsProvider);
    }
    if (!preserveDecoders) {
      ref.read(activeDecodersProvider.notifier).clearAll();
    }
    ref.read(xTraceProvider.notifier).clearTrace();
    ref.read(diffProvider.notifier).clearDiff();
    ref.read(patternSearchProvider.notifier).clearSearch();
    ref.read(switchingActivityProvider.notifier).clear();
    ref.read(processFilterProvider.notifier).clearAll();
    ref.read(translateFilterProvider.notifier).clearAll();
    ref.read(fsmProvider.notifier).clearFsm();
    ref.read(fsmAnnotationProvider.notifier).clearAll();
    // Stage panels and bindings reference signal refs from the
    // previous file's namespace and become invalid the moment a new
    // file is loaded. Reset alongside the other viewer state.
    ref.read(stageWorkspaceProvider.notifier).clear();

    _activeSource?.close();
    _activeSource = null;
    _pendingSource?.close();
    _pendingSource = null;
    if (_accessingPath != null) {
      await SecurityScopedBookmarkService.stopAccessing(_accessingPath!);
      _accessingPath = null;
    }
    currentFilePath = path;
    lastAttemptedPath = path;
    originalFormat = null;
    convertedAt = null;
    _captureSourceFileStat(path);
    // Clear the published content hash up front; it is recomputed off-thread
    // after a successful parse (see _publishContentHash). A collaborator who is
    // mid-load thus reports "no waveform" rather than the previous file's hash.
    ref.read(waveformIdentityProvider.notifier).set(null);
    state = const AsyncLoading();
    try {
      // Restore sandbox access for files from the recent files list.
      // If there is no bookmark (first open via picker), the picker already
      // granted access for this session so the read succeeds anyway.
      await SecurityScopedBookmarkService.resolveAndStartAccessing(path);
      _accessingPath = path;

      final parseStopwatch = Stopwatch()..start();

      // Probe the first bytes of the file to identify GTKWave's
      // legacy LXT / LXT2 formats and route them through the lxt2fst
      // converter (with sibling/app-cache reuse) before the wellen backend
      // touches the file. Magic-byte detection is used, NOT extension, so
      // archives whose `.lxt2` extension was stripped at some point still
      // route correctly.
      var openPath = path;
      final legacyOrigin = await LegacyFormatDetector.detectFile(path);
      if (legacyOrigin.isLegacy) {
        openPath = await _convertLegacyToFst(
          sourcePath: path,
          origin: legacyOrigin,
        );
        if (_loadToken != token) return;
        // Record the legacy origin as soon as the conversion has produced
        // the cached FST. This keeps the Diagnostics → File Info "Original
        // format" row faithful to the user's pick even if the subsequent
        // wellen open fails — the next openFile call resets it to null
        // before the new attempt starts.
        originalFormat = legacyOrigin;
      }

      final wellenSource = WellenProvider();
      _pendingSource = wellenSource;
      await wellenSource.openFile(openPath);
      _pendingSource = null;

      // Abort if cancelLoad() was called while we were awaiting.
      if (_loadToken != token) return;

      parseStopwatch.stop();
      lastParseTime = parseStopwatch.elapsed;
      _activeSource = wellenSource;
      if (!legacyOrigin.isLegacy) {
        originalFormat = WaveformFormat.fromWellenLabel(
          wellenSource.fileFormat,
        );
      }

      // Persist/refresh the bookmark now that we have confirmed access.
      await SecurityScopedBookmarkService.saveBookmark(path);

      state = AsyncData(wellenSource);
      _recordFileOpened(originalFormat?.name ?? WaveformFormat.unknown.name);

      // Hash the *original* picked file (not the convert-on-open derivative) so
      // collaborators who opened the same source match regardless of any local
      // LXT2→FST conversion. Runs off-thread; the result lands a moment later.
      unawaited(_publishContentHash(path, token));

      // Cross-probe producer: record this waveform in the shared cross-probe workspace
      // (keyed by its containing-directory design id) so a peer that receives a
      // cross-probe with no matching waveform open can resolve and open it —
      // even when the producing app (SimCrux/NetCrux) isn't running. Best-effort
      // and gated on the CXP server being enabled, so it is inert for ordinary
      // opens and in tests that don't stand up CXP.
      unawaited(publishWaveformWorkspaceArtifact(ref, path, wellenSource));
    } on Object catch (e, st) {
      _pendingSource = null;
      // Abort if cancelLoad() was called — state is already reset.
      if (_loadToken != token) return;
      if (_accessingPath != null) {
        await SecurityScopedBookmarkService.stopAccessing(_accessingPath!);
        _accessingPath = null;
      }
      currentFilePath = null;
      _log.severe('Failed to open waveform "$path": $e', e, st);
      state = AsyncError(e, st);
    }
  }

  /// Records mtime + size of [path] for [isSourceFileReplacedOnDisk].
  /// Best-effort: a stat failure (or web) just disables staleness detection
  /// for this open.
  void _captureSourceFileStat(String path) {
    sourceFileModifiedAt = null;
    sourceFileSizeBytes = null;
    if (kIsWeb) return;
    try {
      final stat = File(path).statSync();
      if (stat.type != FileSystemEntityType.notFound) {
        sourceFileModifiedAt = stat.modified;
        sourceFileSizeBytes = stat.size;
      }
    } on Object {
      // Non-fatal — see doc comment.
    }
  }

  /// Whether the on-disk file at [currentFilePath] differs (mtime or size)
  /// from the stat captured when the current parse read it — i.e. the file
  /// was replaced or rewritten after this source was loaded.
  ///
  /// Used by ViewerScreen's open-path dedupe: focusing an already-open tab
  /// for a path whose contents changed must RELOAD instead of silently
  /// showing the previous parse (the iOS/Android share sheet overwrites
  /// `Documents/SharedImports/<name>` in place for same-named incoming
  /// files, which is routine for HDL dumps that are all called `dump.vcd`).
  /// Returns false on web, when nothing is loaded, when no stat was captured,
  /// or when the file is currently missing (the deleted-file case is the
  /// file watcher's to report, not the open path's).
  bool isSourceFileReplacedOnDisk() {
    final path = currentFilePath;
    if (kIsWeb || path == null || sourceFileModifiedAt == null) return false;
    try {
      final stat = File(path).statSync();
      if (stat.type == FileSystemEntityType.notFound) return false;
      return stat.modified != sourceFileModifiedAt ||
          stat.size != sourceFileSizeBytes;
    } on Object {
      return false;
    }
  }

  /// Cancels a pending [openFile] operation and returns to the no-file state.
  ///
  /// Safe to call when no load is in progress — it is a no-op in that case.
  /// Kills the background wellen isolate if one is running so it does not
  /// linger after the user cancels.
  void cancelLoad() {
    if (state is! AsyncLoading) return;
    _loadToken++; // Invalidate any in-flight openFile().
    _pendingSource?.close();
    _pendingSource = null;
    currentFilePath = null;
    ref.read(waveformIdentityProvider.notifier).set(null);
    state = const AsyncData(null);
  }

  /// Opens a waveform from raw [bytes] on Flutter Web.
  ///
  /// Uses [WellenWasmProvider] (the `wellen` crate compiled to WebAssembly)
  /// for VCD/FST/GHW. If the WASM module fails to load (CSP blocks
  /// WebAssembly, ancient browser, etc.), the open fails with
  /// [WebAssemblyRequiredError] — there is no Dart-side fallback.
  ///
  /// Skips macOS sandbox bookmarks (not applicable on web). [displayName] is
  /// the file's basename and is used as [lastAttemptedPath] for error-state
  /// retry UI and as the format-detection hint passed to the WASM parser.
  Future<void> openFromBytes(Uint8List bytes, String displayName) async {
    assert(kIsWeb, 'openFromBytes is only for Flutter Web');
    ref.read(signalGroupsProvider.notifier).clear();
    ref.read(cursorStateProvider.notifier).clearAll();
    ref
      ..invalidate(markerStateProvider)
      ..invalidate(annotationsProvider);
    ref.read(activeDecodersProvider.notifier).clearAll();
    ref.read(xTraceProvider.notifier).clearTrace();
    ref.read(diffProvider.notifier).clearDiff();
    ref.read(patternSearchProvider.notifier).clearSearch();
    ref.read(switchingActivityProvider.notifier).clear();
    ref.read(processFilterProvider.notifier).clearAll();
    ref.read(translateFilterProvider.notifier).clearAll();
    ref.read(fsmProvider.notifier).clearFsm();
    ref.read(fsmAnnotationProvider.notifier).clearAll();
    ref.read(stageWorkspaceProvider.notifier).clear();

    _activeSource?.close();
    _activeSource = null;
    currentFilePath = null;
    lastAttemptedPath = displayName;
    originalFormat = null;
    convertedAt = null;
    ref.read(waveformIdentityProvider.notifier).set(null);
    state = const AsyncLoading();
    // Let the loading state actually PAINT before the parse begins. The web
    // WASM parse runs synchronously on the main thread; without a real frame
    // here, the freshly-created tab and its "Parsing…" placeholder never
    // render — the user stares at an unchanged screen for the entire parse
    // (several seconds on a gate-level FST). endOfFrame schedules a frame
    // and waits it out. Web-only in effect (this method asserts kIsWeb); the
    // guard also keeps VM provider tests — which never pump frames — from
    // hanging on a frame that will never come.
    if (kIsWeb) {
      await WidgetsBinding.instance.endOfFrame;
    }
    try {
      // Initialize the WASM module on first use. Subsequent calls await the
      // same future. Any failure here means the browser cannot run WebAssembly
      // (or the module load itself failed) — surface a clear error.
      try {
        await WellenWasmProvider.ensureInitialized();
      } on Object {
        throw const WebAssemblyRequiredError();
      }
      if (!WellenWasmProvider.isAvailable) {
        throw const WebAssemblyRequiredError();
      }

      // Same magic-byte probe as the desktop/mobile path — if
      // the buffer is LXT/LXT2, convert it to FST in-memory via the WASM
      // converter before handing the bytes to wellen. The web build has
      // no filesystem-sibling cache; future work can layer an
      // IndexedDB-keyed cache on top of [convertBytes].
      var openBytes = bytes;
      var openName = displayName;
      final legacyOrigin = LegacyFormatDetector.detectBytes(bytes);
      if (legacyOrigin.isLegacy) {
        final converter = ref.read(lxt2FstConverterProvider);
        final controller = ref.read(legacyConversionControllerProvider.notifier)
          ..begin(sourcePath: displayName, origin: legacyOrigin);
        try {
          openBytes = await converter.convertBytes(bytes);
          controller.completeSuccess();
        } on Object {
          controller.completeWithError();
          rethrow;
        }
        convertedAt = DateTime.now();
        ref
            .read(legacyConversionEventProvider.notifier)
            .emit(
              origin: legacyOrigin,
              fstPath: displayName,
              completedAt: convertedAt,
            );
        // Rename for the wellen FFI-format hint so it picks the FST path.
        openName = _replaceExtension(displayName, '.fst');
      }

      final parseStopwatch = Stopwatch()..start();
      final wasmSource = WellenWasmProvider();
      await wasmSource.openBytes(openBytes, openName);
      parseStopwatch.stop();
      lastParseTime = parseStopwatch.elapsed;
      _activeSource = wasmSource;
      originalFormat = legacyOrigin.isLegacy
          ? legacyOrigin
          : WaveformFormat.fromWellenLabel(wasmSource.fileFormat);
      state = AsyncData(wasmSource);
      _recordFileOpened(originalFormat?.name ?? WaveformFormat.unknown.name);

      // Hash the original picked bytes (synchronous on web — they are already
      // in memory) so this participant's waveform identity matches a desktop
      // peer who opened the same source file.
      ref
          .read(waveformIdentityProvider.notifier)
          .set(WaveformContentHash.ofBytes(bytes));
    } on Object catch (e, st) {
      currentFilePath = null;
      _log.severe(
        'Failed to open waveform from bytes "$displayName": $e',
        e,
        st,
      );
      state = AsyncError(e, st);
    }
  }

  /// Runs an LXT/LXT2 → FST conversion (cached when possible) and returns
  /// the path the wellen backend should actually open.
  ///
  /// Uses [Lxt2FstCache] to find a fresh sibling-of-source `.fst` first,
  /// falling back to `${appCacheDir}/legacy_conversions/<hash>.fst` when
  /// the sibling directory is not writable. Skips reconversion when the
  /// cached file's mtime ≥ source mtime AND its sidecar records the same
  /// source size.
  ///
  /// Drives [legacyConversionControllerProvider] for the progress dialog
  /// and emits a [legacyConversionEventProvider] event
  /// when a fresh conversion completes — that event is what the
  /// "Opened from legacy …" banner listens for. Cache hits skip both: no
  /// dialog flash, no banner.
  Future<String> _convertLegacyToFst({
    required String sourcePath,
    required WaveformFormat origin,
  }) async {
    final cache = ref.read(lxt2FstCacheProvider);
    final decision = await cache.resolve(sourcePath);
    if (decision.fromCache) {
      // Cache hit: skip the converter entirely. No dialog, no banner.
      return decision.fstPath;
    }
    final converter = ref.read(lxt2FstConverterProvider);
    final controller = ref.read(legacyConversionControllerProvider.notifier);
    final eventSink = ref.read(legacyConversionEventProvider.notifier);

    final progress = converter.convertPath(
      inPath: sourcePath,
      outPath: decision.fstPath,
    );

    final completer = Completer<void>();
    late final StreamSubscription<ConversionProgress> sub;
    sub = progress.listen(
      controller.updateProgress,
      onError: (Object e, StackTrace st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
    );

    controller
      ..begin(sourcePath: sourcePath, origin: origin)
      ..cancelHook = () {
        unawaited(sub.cancel());
        if (!completer.isCompleted) {
          completer.completeError(const LegacyConversionCancelledException());
        }
      };

    try {
      await completer.future;
      controller.completeSuccess();
    } on Object {
      controller.completeWithError();
      rethrow;
    } finally {
      await sub.cancel();
    }

    await cache.recordSuccess(
      sourcePath: sourcePath,
      fstPath: decision.fstPath,
    );
    convertedAt = DateTime.now();
    eventSink.emit(
      origin: origin,
      fstPath: decision.fstPath,
      completedAt: convertedAt,
    );
    return decision.fstPath;
  }

  /// Replace the extension of [name] with [newExt] (which must begin with
  /// a `.`). Used to give the wellen WASM backend the right format hint
  /// for the converted-FST bytes.
  String _replaceExtension(String name, String newExt) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return '$name$newExt';
    return '${name.substring(0, dot)}$newExt';
  }

  /// Injects [source] as the active waveform source without going through the
  /// normal [openFile] / file-picker path.
  ///
  /// Used by [StreamingSourceNotifier] to register a [StreamingVcdService]
  /// once its VCD header has been parsed. Closes any previously loaded file,
  /// clears viewer state (signal groups, cursors, markers), and exposes
  /// [source] to all watchers of this provider.
  ///
  /// [currentFilePath] is set to null because streaming sources have no
  /// on-disk path (stdin / named pipe).
  void attachStreamingSource(WaveformDataSource source) {
    ref.read(signalGroupsProvider.notifier).clear();
    ref.read(cursorStateProvider.notifier).clearAll();
    ref
      ..invalidate(markerStateProvider)
      ..invalidate(annotationsProvider);
    ref.read(activeDecodersProvider.notifier).clearAll();
    ref.read(xTraceProvider.notifier).clearTrace();
    ref.read(diffProvider.notifier).clearDiff();
    ref.read(patternSearchProvider.notifier).clearSearch();
    ref.read(switchingActivityProvider.notifier).clear();
    ref.read(processFilterProvider.notifier).clearAll();
    ref.read(translateFilterProvider.notifier).clearAll();
    ref.read(fsmProvider.notifier).clearFsm();
    ref.read(fsmAnnotationProvider.notifier).clearAll();
    ref.read(stageWorkspaceProvider.notifier).clear();

    _activeSource?.close();
    if (_accessingPath != null) {
      // Fire-and-forget: sandbox bookmark release is best-effort here.
      unawaited(SecurityScopedBookmarkService.stopAccessing(_accessingPath!));
      _accessingPath = null;
    }
    _activeSource = source;
    currentFilePath = null;
    lastAttemptedPath = null;
    originalFormat = null;
    convertedAt = null;
    // A stream has no container format to resolve — `originalFormat` is
    // deliberately null above — so it reports the transport instead. It is
    // still a `file.opened`: the roadmap question is which ways of getting
    // waveform data into the viewer are used, and stdin is one of them.
    _recordFileOpened('streaming');
    // Streaming sources (stdin / named pipe) have no on-disk bytes to hash, so
    // the local participant reports no waveform identity — excluded from the
    // collaborative-viewing mismatch check rather than counted as a difference.
    ref.read(waveformIdentityProvider.notifier).set(null);
    state = AsyncData(source);
  }

  /// Closes the current file and resets all viewer state to the no-file state.
  ///
  /// Clears signal groups, cursors, and markers — mirrors the cleanup that
  /// [openFile] performs before loading a new file so that all derived
  /// providers (diagnostics, value column, canvas) see a clean empty state.
  Future<void> close() async {
    ref.read(signalGroupsProvider.notifier).clear();
    ref.read(cursorStateProvider.notifier).clearAll();
    ref
      ..invalidate(markerStateProvider)
      ..invalidate(annotationsProvider);
    ref.read(activeDecodersProvider.notifier).clearAll();
    ref.read(xTraceProvider.notifier).clearTrace();
    ref.read(diffProvider.notifier).clearDiff();
    ref.read(patternSearchProvider.notifier).clearSearch();
    ref.read(switchingActivityProvider.notifier).clear();
    ref.read(processFilterProvider.notifier).clearAll();
    ref.read(translateFilterProvider.notifier).clearAll();
    ref.read(fsmProvider.notifier).clearFsm();
    ref.read(fsmAnnotationProvider.notifier).clearAll();
    ref.read(stageWorkspaceProvider.notifier).clear();

    _activeSource?.close();
    _activeSource = null;
    if (_accessingPath != null) {
      await SecurityScopedBookmarkService.stopAccessing(_accessingPath!);
      _accessingPath = null;
    }
    currentFilePath = null;
    lastParseTime = null;
    originalFormat = null;
    convertedAt = null;
    ref.read(waveformIdentityProvider.notifier).set(null);
    state = const AsyncData(null);
  }

  /// Computes the SHA-256 content hash of [path] off the UI thread and publishes
  /// it to [waveformIdentityProvider] — but only while this load ([token]) is
  /// still current, so a superseded or cancelled load never clobbers a newer
  /// file's identity. A read failure publishes `null` (no reported identity).
  Future<void> _publishContentHash(String path, int token) async {
    final hash = await WaveformContentHash.ofFile(path);
    // The container can be torn down while the hash is still in flight
    // (app shutdown, test dispose) — using ref past that point throws.
    if (!ref.mounted || _loadToken != token) return;
    ref.read(waveformIdentityProvider.notifier).set(hash);
  }
}

/// Convenience provider that exposes whether a waveform file is currently open.
@riverpod
bool waveformIsLoaded(Ref ref) {
  final source = ref.watch(waveformSourceProvider);
  return source.value != null;
}
