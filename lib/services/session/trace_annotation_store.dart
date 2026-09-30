// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_io/crux_io.dart' show canonicalPathKey;
import 'package:wavecrux/domain/models/annotation.dart';

/// Annotations that belong to a **trace**, not to a tab.
///
/// **Why this exists.** Per-tab session state autosaves to
/// `sessions/{tabId}.wavecrux`, and closing a tab deletes that file — correctly,
/// for what it was designed to hold. Cursor position, zoom and panel layout are
/// disposable: they describe how you were looking at a file, and recreating
/// them costs a second. Annotations are not. They are prose the user wrote, and
/// deleting them because a tab closed is silent loss of authored content.
///
/// Nothing distinguished the two, so both were destroyed together. This store
/// draws that line: the tab sidecar keeps the view, this keeps the words.
///
/// **Keyed by the trace, so reopening a file brings its notes back.** That is
/// what an annotation feature implies, and it is what makes drift work at all —
/// the entire premise is that you return days later, re-simulate, and the
/// claims that no longer hold flag themselves. A note that does not survive
/// until the next session cannot do that.
///
/// **Identity is [canonicalPathKey]**, so `./sim/out.vcd` and
/// `/home/me/sim/out.vcd` are one trace, and a case-insensitive filesystem does
/// not create two. The key is hashed rather than used raw because a path is not
/// a filename: it contains separators, may be longer than a filename may be,
/// and would leak the user's directory layout into a listing.
///
/// **An explicit `.wavecrux` session still wins.** This is the fallback for a
/// plain file open — a session document the user chose to save is a stronger
/// statement about what belongs to that file than an autosave, and restoring
/// both would mean deciding which of two answers is right.
class TraceAnnotationStore {
  const TraceAnnotationStore(this.directory);

  /// Where the per-trace files live, e.g. `{appSupport}/trace-annotations`.
  final Directory directory;

  /// The file holding [tracePath]'s notes.
  ///
  /// Stable across runs, across relative/absolute spellings of the same path,
  /// and across a filesystem that ignores case.
  File fileFor(String tracePath) {
    final digest = _fnv1a64(canonicalPathKey(tracePath));
    return File('${directory.path}${Platform.pathSeparator}$digest.json');
  }

  /// FNV-1a, 64-bit, as a fixed-width hex filename.
  ///
  /// A hash rather than the path itself because a path contains separators, can
  /// exceed the length a single filename may be, and would leak the user's
  /// directory layout into a listing. FNV rather than SHA-256 because `crypto`
  /// is only a transitive dependency here and this is a filename, not a
  /// security boundary — and a collision is harmless anyway: [load] checks the
  /// `tracePath` recorded inside the file and ignores a record written for a
  /// different trace.
  /// Two 32-bit halves rather than one 64-bit accumulator: this package builds
  /// for web, where an int is a double and a 64-bit offset basis cannot be
  /// represented exactly. Splitting keeps every intermediate inside the 53 bits
  /// a double holds precisely, so the filename is the same on every platform —
  /// which it must be, or the same trace would key differently per build.
  static String _fnv1a64(String input) {
    var lo = 0x84222325;
    var hi = 0xcbf29ce4;
    for (final byte in utf8.encode(input)) {
      lo ^= byte;
      // Multiply by the FNV prime 0x100000001b3, carried across the halves.
      final loProd = lo * 0x1b3;
      final hiProd = hi * 0x1b3 + lo;
      lo = loProd & 0xFFFFFFFF;
      hi = (hiProd + (loProd ~/ 0x100000000)) & 0xFFFFFFFF;
    }
    return hi.toRadixString(16).padLeft(8, '0') +
        lo.toRadixString(16).padLeft(8, '0');
  }

  /// Reads the notes recorded for [tracePath], or an empty record.
  ///
  /// Never throws. A store that cannot be read must not stop a waveform
  /// opening — the notes are an enhancement to the file, not a precondition
  /// for it, and a corrupt store that blocked file opening would be a far
  /// worse failure than the one it is guarding against.
  Future<TraceAnnotations> load(String tracePath) async {
    try {
      final file = fileFor(tracePath);
      if (!file.existsSync()) return const TraceAnnotations.empty();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        return const TraceAnnotations.empty();
      }
      // Guards a hash collision, and a file hand-copied between machines: the
      // record names the trace it was written for, and a record for a
      // different one is not this trace's notes.
      final recorded = decoded['tracePath'];
      if (recorded is String &&
          canonicalPathKey(recorded) != canonicalPathKey(tracePath)) {
        return const TraceAnnotations.empty();
      }
      return TraceAnnotations.fromJson(decoded);
    } on Object {
      return const TraceAnnotations.empty();
    }
  }

  /// Writes [record] for [tracePath], or deletes the file when it is empty.
  ///
  /// Deleting on empty is deliberate: a user who removes every note has said
  /// this trace has none, and leaving a file full of empty lists behind would
  /// accumulate one per waveform ever opened.
  Future<void> save(String tracePath, TraceAnnotations record) async {
    try {
      final file = fileFor(tracePath);
      if (record.isEmpty) {
        if (file.existsSync()) await file.delete();
        return;
      }
      await directory.create(recursive: true);
      await file.writeAsString(
        jsonEncode(record.toJson(tracePath)),
        flush: true,
      );
    } on Object {
      // Best-effort, like the session autosave beside it. A failure here is
      // worth nothing to the user mid-edit; the next write retries.
    }
  }
}

/// The durable trio: the notes, their adopted layers, and whether they show.
class TraceAnnotations {
  const TraceAnnotations({
    required this.annotations,
    required this.layers,
    required this.visible,
  });

  const TraceAnnotations.empty()
    : annotations = const [],
      layers = const [],
      visible = true;

  factory TraceAnnotations.fromJson(Map<String, Object?> json) {
    // Tolerant per entry, matching `.wavecrux` v4: one unreadable note must not
    // cost the user the rest of them.
    final notes = <Annotation>[];
    final raw = json['annotations'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map<String, Object?>) continue;
        final note = Annotation.fromJson(entry);
        if (note != null) notes.add(note);
      }
    }
    final layers = <AnnotationLayer>[];
    final rawLayers = json['annotationLayers'];
    if (rawLayers is List) {
      for (final entry in rawLayers) {
        if (entry is! Map<String, Object?>) continue;
        final layer = AnnotationLayer.fromJson(entry);
        if (layer != null) layers.add(layer);
      }
    }
    return TraceAnnotations(
      annotations: List.unmodifiable(notes),
      layers: List.unmodifiable(layers),
      visible: json['annotationsVisible'] != false,
    );
  }

  final List<Annotation> annotations;
  final List<AnnotationLayer> layers;
  final bool visible;

  /// True when there is nothing worth keeping a file for.
  ///
  /// Visibility alone does not count: a hidden-but-empty trace is not something
  /// the user asked to remember.
  bool get isEmpty => annotations.isEmpty && layers.isEmpty;

  /// [tracePath] is recorded for a human reading the directory — the filename
  /// is a hash, so without it the store is unreadable by inspection.
  Map<String, Object?> toJson(String tracePath) => {
    'version': 1,
    'tracePath': tracePath,
    'annotations': [for (final a in annotations) a.toJson()],
    'annotationLayers': [for (final l in layers) l.toJson()],
    'annotationsVisible': visible,
  };
}
