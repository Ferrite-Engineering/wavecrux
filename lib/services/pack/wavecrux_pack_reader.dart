// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/services/pack/wavecrux_pack_failure.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_spec.dart';

/// A `.wavecruxpack` unpacked onto disk, ready to be opened as a session.
@immutable
class ExtractedPack {
  const ExtractedPack({
    required this.directory,
    required this.sessionPath,
    this.previewPath,
    this.readme,
  });

  /// Where the pack was expanded. Under the app's cache directory, so the OS
  /// may reclaim it — the pack file itself remains the durable copy.
  final String directory;

  /// Absolute path of the extracted `session.wavecrux`. Loading this restores
  /// the whole annotated view: its `sourceFilePath` is relative, so
  /// `SessionService.loadSession` resolves it against [directory] and finds the
  /// bundled dump rather than a path on the sender's machine.
  final String sessionPath;

  /// Absolute path of the extracted preview, when the pack carried one.
  final String? previewPath;

  /// The README text, when present.
  final String? readme;
}

/// Reads a `.wavecruxpack` and expands it into a cache directory.
///
/// Every pack is treated as untrusted — this is the format designed to arrive
/// by email — so the reader refuses symlinks, escaping entry names and
/// oversized expansions before writing a single byte, exactly as
/// `WidgetBundleReader` does for community widget bundles.
class WaveCruxPackReader {
  /// Creates a reader. The default decoder is `package:archive`'s ZIP decoder;
  /// tests inject a stub to exercise failure paths without crafting bytes.
  WaveCruxPackReader({
    Archive Function(List<int> bytes)? archiveDecoder,
    Future<List<int>> Function(String path)? fileReader,
  }) : _archiveDecoder = archiveDecoder ?? _defaultDecoder,
       _fileReader = fileReader ?? _defaultFileReader;

  final Archive Function(List<int> bytes) _archiveDecoder;
  final Future<List<int>> Function(String path) _fileReader;

  static Archive _defaultDecoder(List<int> bytes) =>
      ZipDecoder().decodeBytes(bytes, verify: true);

  static Future<List<int>> _defaultFileReader(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw WaveCruxPackException(
        kind: WaveCruxPackFailureKind.fileMissing,
        diagnostic: 'Pack file does not exist',
        packPath: path,
      );
    }
    try {
      return await file.readAsBytes();
    } on FileSystemException catch (e) {
      throw WaveCruxPackException(
        kind: WaveCruxPackFailureKind.ioError,
        diagnostic: 'Failed to read pack: ${e.message}',
        packPath: path,
      );
    }
  }

  /// Expands the pack at [packPath] under [cacheRoot] and returns the result.
  ///
  /// The destination is `<cacheRoot>/<pack basename>` and is **cleared first**,
  /// so reopening an updated pack of the same name never leaves a previous
  /// version's dump behind for the session to resolve against — the failure
  /// that would produce is a waveform silently one revision old.
  Future<ExtractedPack> extract({
    required String packPath,
    required String cacheRoot,
  }) async {
    final bytes = await _fileReader(packPath);
    final entries = readEntries(bytes: bytes, diagnosticName: packPath);

    final destination = p.join(
      cacheRoot,
      p.basenameWithoutExtension(packPath),
    );
    try {
      final dir = Directory(destination);
      if (dir.existsSync()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      for (final entry in entries.entries) {
        final file = File(p.join(destination, entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }
    } on FileSystemException catch (e) {
      throw WaveCruxPackException(
        kind: WaveCruxPackFailureKind.ioError,
        diagnostic: 'Failed to extract pack: ${e.message}',
        packPath: packPath,
      );
    }

    final readmeBytes = entries[WaveCruxPackSpec.readmeEntryName];
    return ExtractedPack(
      directory: destination,
      sessionPath: p.join(destination, WaveCruxPackSpec.sessionEntryName),
      previewPath: entries.containsKey(WaveCruxPackSpec.previewEntryName)
          ? p.join(destination, WaveCruxPackSpec.previewEntryName)
          : null,
      readme: readmeBytes == null
          ? null
          : utf8.decode(readmeBytes, allowMalformed: true),
    );
  }

  /// Decodes and **validates** [bytes], returning the pack's entries in memory.
  ///
  /// This is where every safety rule lives — symlinks, escaping entry names,
  /// the uncompressed-size cap, and the required `session.wavecrux` — so that
  /// [extract] and the byte-only web path cannot diverge on what they accept.
  /// A pack is the format designed to arrive by email; a second reader with
  /// its own idea of "safe" would be a second attack surface.
  ///
  /// Nothing is written to disk. [diagnosticName] labels failures: a path on
  /// desktop, an upload's filename on web.
  Map<String, Uint8List> readEntries({
    required List<int> bytes,
    required String diagnosticName,
  }) {
    final archive = _decodeOrThrow(bytes, diagnosticName);

    final entries = <String, Uint8List>{};
    var totalSize = 0;
    for (final entry in archive) {
      if (entry.isSymbolicLink) {
        throw WaveCruxPackException(
          kind: WaveCruxPackFailureKind.symlinkRejected,
          diagnostic: 'Archive entry is a symlink: ${entry.name}',
          packPath: diagnosticName,
        );
      }
      if (!WaveCruxPackSpec.isSafeEntryName(entry.name)) {
        throw WaveCruxPackException(
          kind: WaveCruxPackFailureKind.unsafeEntryName,
          diagnostic: 'Unsafe archive entry name: ${entry.name}',
          packPath: diagnosticName,
        );
      }
      if (entry.isDirectory) continue;

      totalSize += entry.size;
      if (totalSize > WaveCruxPackSpec.maxUncompressedBytes) {
        throw WaveCruxPackException(
          kind: WaveCruxPackFailureKind.tooLarge,
          diagnostic:
              'Uncompressed size exceeds '
              '${WaveCruxPackSpec.maxUncompressedBytes} bytes',
          packPath: diagnosticName,
        );
      }
      entries[entry.name] = Uint8List.fromList(entry.content as List<int>);
    }

    if (!entries.containsKey(WaveCruxPackSpec.sessionEntryName)) {
      throw WaveCruxPackException(
        kind: WaveCruxPackFailureKind.missingSession,
        diagnostic: 'Archive has no ${WaveCruxPackSpec.sessionEntryName} entry',
        packPath: diagnosticName,
      );
    }
    return entries;
  }

  Archive _decodeOrThrow(List<int> bytes, String packPath) {
    // Check the local-file-header signature ourselves. `ZipDecoder` returns an
    // EMPTY archive for bytes that are not a zip at all rather than throwing,
    // which would surface downstream as "this pack has no session inside it" —
    // a message that sends someone looking for a corrupted bundle when what
    // they actually have is a text file with the wrong extension.
    if (bytes.length < 4 ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4B ||
        bytes[2] != 0x03 ||
        bytes[3] != 0x04) {
      throw WaveCruxPackException(
        kind: WaveCruxPackFailureKind.notAnArchive,
        diagnostic: 'Missing ZIP local-file-header signature',
        packPath: packPath,
      );
    }
    try {
      return _archiveDecoder(bytes);
    } on WaveCruxPackException {
      rethrow;
    } on Object catch (e) {
      throw WaveCruxPackException(
        kind: WaveCruxPackFailureKind.notAnArchive,
        diagnostic: 'Not a readable ZIP archive: $e',
        packPath: packPath,
      );
    }
  }
}
