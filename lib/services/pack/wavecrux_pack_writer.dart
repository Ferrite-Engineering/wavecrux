// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_spec.dart';

/// The four pieces that make up a `.wavecruxpack`, already rendered.
///
/// A value object rather than a set of writer arguments so the caller can
/// measure the exact bundle before deciding to write it — the disclosure step
/// shows a size, and a size derived from anything other than the bytes about
/// to be zipped is a number that can be wrong.
@immutable
class WaveCruxPackContents {
  const WaveCruxPackContents({
    required this.sessionJson,
    required this.waveformVcd,
    required this.readme,
    this.previewPng,
  });

  /// The `.wavecrux` document text, with `sourceFilePath` already rewritten to
  /// [WaveCruxPackSpec.waveformEntryName].
  final String sessionJson;

  /// The VCD subset the session references.
  final String waveformVcd;

  /// Plain-text explanation plus the download URL.
  final String readme;

  /// The annotated render. Null when no capture was available — the pack is
  /// still valid and still opens; it just has no thumbnail to show.
  final Uint8List? previewPng;

  /// Total uncompressed size of every entry. The disclosure step reports this
  /// rather than the compressed size, which is not known until the zip is
  /// built and which a recipient's mail client will not see either.
  int get uncompressedBytes =>
      utf8.encode(sessionJson).length +
      utf8.encode(waveformVcd).length +
      utf8.encode(readme).length +
      (previewPng?.length ?? 0);
}

/// Builds `.wavecruxpack` archives.
///
/// Deliberately mirrors `WidgetBundleWriter`: entries are added flat under the
/// names in [WaveCruxPackSpec], the whole archive is built in memory, and the
/// file write is a thin wrapper so tests can assert on bytes without touching
/// disk.
class WaveCruxPackWriter {
  const WaveCruxPackWriter();

  /// Encodes [contents] into ZIP bytes.
  Uint8List buildBytes(WaveCruxPackContents contents) {
    final archive = Archive()
      ..addFile(
        _textFile(WaveCruxPackSpec.sessionEntryName, contents.sessionJson),
      )
      ..addFile(
        _textFile(WaveCruxPackSpec.waveformEntryName, contents.waveformVcd),
      )
      ..addFile(_textFile(WaveCruxPackSpec.readmeEntryName, contents.readme));
    final preview = contents.previewPng;
    if (preview != null) {
      archive.addFile(
        ArchiveFile(WaveCruxPackSpec.previewEntryName, preview.length, preview),
      );
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// Writes [contents] to [path]. Creates parent directories and overwrites.
  ///
  /// Throws [WaveCruxPackWriteException] on I/O failure — the same shape as
  /// `VcdWriteException` so the export call sites all read alike.
  Future<File> writeToFile({
    required String path,
    required WaveCruxPackContents contents,
  }) async {
    final bytes = buildBytes(contents);
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } on IOException catch (e) {
      throw WaveCruxPackWriteException(path, e.toString());
    }
  }

  /// Also writes the preview as `<pack stem>.png` next to the pack, returning
  /// its path — or null when there was no preview, or writing it failed.
  ///
  /// **Why a second copy of bytes already inside the archive.** The preview is
  /// the image the sender wants: it is the annotated render, framed by the app,
  /// and it is what goes in the email body, the post, or the ticket beside the
  /// attachment. Sealed inside the zip, getting it out means unzipping your own
  /// share bundle — so in practice people take a screenshot instead and the
  /// render the app already made is wasted.
  ///
  /// Best-effort by design: the user asked for a pack, and the pack is written
  /// by the time this runs. A failure here must not turn a successful share
  /// into an error, so it reports by returning null rather than throwing.
  Future<File?> writePreviewBeside({
    required String packPath,
    required WaveCruxPackContents contents,
  }) async {
    final preview = contents.previewPng;
    if (preview == null) return null;
    try {
      final dot = packPath.lastIndexOf('.');
      final separator = packPath.lastIndexOf(Platform.pathSeparator);
      // Only strip a real extension — a dot in a directory name is not one.
      final stem = dot > separator ? packPath.substring(0, dot) : packPath;
      final file = File('$stem.png');
      await file.writeAsBytes(preview, flush: true);
      return file;
    } on IOException {
      return null;
    }
  }

  static ArchiveFile _textFile(String name, String content) {
    final bytes = utf8.encode(content);
    return ArchiveFile(name, bytes.length, bytes);
  }
}

/// Thrown when a pack cannot be written to disk.
class WaveCruxPackWriteException implements Exception {
  const WaveCruxPackWriteException(this.path, this.reason);

  final String path;
  final String reason;

  @override
  String toString() => 'WaveCruxPackWriteException($path): $reason';
}
