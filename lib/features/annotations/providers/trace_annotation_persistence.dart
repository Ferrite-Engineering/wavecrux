// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_async/crux_async.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/features/annotations/providers/annotation_layers_provider.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/session/trace_annotation_store.dart';

part 'trace_annotation_persistence.g.dart';

/// Where per-trace annotation records live, or `null` when there is nowhere to
/// put them.
///
/// Nullable rather than throwing: `path_provider` is a platform channel and is
/// simply absent under `flutter test`, so a provider that failed here would sit
/// in a permanent loading state and raise "disposed during loading" from every
/// widget test that mounts a tab. Persistence degrades to off; nothing else
/// notices.
@Riverpod(keepAlive: true)
Future<TraceAnnotationStore?> traceAnnotationStore(Ref ref) async {
  try {
    final dir = await getApplicationSupportDirectory();
    return TraceAnnotationStore(
      Directory('${dir.path}${Platform.pathSeparator}trace-annotations'),
    );
  } on Object {
    return null;
  }
}

/// Debounce before writing a trace's notes.
///
/// Longer than the session sidecar's two seconds: this file is per *trace*
/// rather than per tab, so a burst of edits in one tab is the only writer and
/// there is nothing to race.
const Duration kTraceAnnotationSaveDebounce = Duration(seconds: 2);

/// Keeps a trace's annotations alive across tab closes and app restarts.
///
/// **The bug this exists for.** Per-tab state autosaves to
/// `sessions/{tabId}.wavecrux`, and `closeTab` deletes that file. Correct for
/// what it holds — cursor, zoom, panel layout are disposable — but annotations
/// went with them, so closing a tab silently destroyed prose the user had
/// written, and reopening the same waveform started empty.
///
/// Nothing distinguished the two kinds of state. This does: the sidecar keeps
/// the view, the [TraceAnnotationStore] keeps the words, and only the view is
/// thrown away with the tab.
///
/// ### Load happens once per file, and only into an empty tab
///
/// A restored `.wavecrux` session already carries its own annotations, and it
/// is the stronger statement: the user chose to save that document. So this
/// loads only when the tab has none — which is exactly the plain-file-open
/// case, and never overwrites what a session just restored.
@Riverpod(keepAlive: true)
class TraceAnnotationPersistence extends _$TraceAnnotationPersistence {
  final _debounce = Debouncer(duration: kTraceAnnotationSaveDebounce);

  /// The trace whose notes are currently loaded, so a save cannot be attributed
  /// to the wrong file after the tab opens a different one.
  String? _tracePath;

  /// Set while [_restore] writes, so the write does not read as a user edit and
  /// schedule a save of what was just loaded.
  bool _restoring = false;

  @override
  void build() {
    ref
      ..listen(waveformSourceProvider, (previous, next) {
        final path = ref.read(waveformSourceProvider.notifier).currentFilePath;
        if (next.value == null || path == null) return;
        if (path == _tracePath) return; // a reload of the same trace
        _tracePath = path;
        unawaited(_restore(path));
      })
      ..listen<dynamic>(annotationsProvider, (_, _) => _schedule())
      ..listen<dynamic>(annotationLayersProvider, (_, _) => _schedule())
      ..listen<dynamic>(annotationsVisibleProvider, (_, _) => _schedule())
      // Cancelled, not disposed: Riverpod keeps this notifier instance when
      // the provider rebuilds, so the next build schedules through it again.
      ..onDispose(_debounce.cancel);
  }

  Future<void> _restore(String tracePath) async {
    // Only into an empty tab: a `.wavecrux` the user saved outranks this.
    if (ref.read(annotationsProvider).isNotEmpty) return;
    final store = await ref.read(traceAnnotationStoreProvider.future);
    if (store == null) return;
    final record = await store.load(tracePath);
    if (record.annotations.isEmpty && record.layers.isEmpty) return;
    // The tab may have acquired notes while the read was in flight — a session
    // restore, or the user annotating immediately. Theirs win.
    if (ref.read(annotationsProvider).isNotEmpty) return;

    _restoring = true;
    try {
      ref
          .read(annotationsProvider.notifier)
          .restoreFromSession(record.annotations);
      ref
          .read(annotationLayersProvider.notifier)
          .restoreFromSession(record.layers);
      ref.read(annotationsVisibleProvider.notifier).visible = record.visible;
    } finally {
      _restoring = false;
    }
  }

  void _schedule() {
    if (_restoring || _tracePath == null) return;
    _debounce.run(() => unawaited(flush()));
  }

  /// Writes now rather than on the debounce. Exposed for lifecycle handlers,
  /// for the tab-close path, and for tests.
  Future<void> flush() async {
    final tracePath = _tracePath;
    if (tracePath == null) return;
    try {
      final store = await ref.read(traceAnnotationStoreProvider.future);
      if (store == null) return;
      await store.save(
        tracePath,
        TraceAnnotations(
          annotations: ref.read(annotationsProvider.notifier).snapshot(),
          layers: ref.read(annotationLayersProvider),
          visible: ref.read(annotationsVisibleProvider),
        ),
      );
    } on Object {
      // Best-effort, exactly like the session autosave beside it.
    }
  }
}
