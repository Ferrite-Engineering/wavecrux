// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Why reading a `.wavecruxpack` failed.
///
/// A closed set rather than a message string so the UI can map each case to a
/// localized explanation. The distinction matters: "this file is not a pack"
/// and "this pack is missing its session" send the recipient to different
/// places, and a single generic error would send them nowhere.
enum WaveCruxPackFailureKind {
  /// No file at the given path.
  fileMissing,

  /// The file could not be read or the extraction directory not written.
  ioError,

  /// The bytes are not a ZIP archive, or the archive is corrupt.
  notAnArchive,

  /// An entry is a symbolic link. Refused rather than followed.
  symlinkRejected,

  /// An entry name escapes the extraction root or is implausibly deep.
  unsafeEntryName,

  /// The archive expands past [WaveCruxPackSpec.maxUncompressedBytes].
  tooLarge,

  /// A ZIP that decoded fine but carries no `session.wavecrux`. Almost
  /// certainly a different archive that happens to have been renamed.
  missingSession,
}

/// Thrown by `WaveCruxPackReader` on every failure path.
class WaveCruxPackException implements Exception {
  const WaveCruxPackException({
    required this.kind,
    required this.diagnostic,
    this.packPath,
  });

  final WaveCruxPackFailureKind kind;

  /// Developer-facing detail. Never shown raw to a user — the UI selects a
  /// localized string from [kind] — but carried into logs and bug reports.
  final String diagnostic;

  final String? packPath;

  @override
  String toString() =>
      'WaveCruxPackException(${kind.name}${packPath == null ? '' : ', $packPath'}): '
      '$diagnostic';
}
