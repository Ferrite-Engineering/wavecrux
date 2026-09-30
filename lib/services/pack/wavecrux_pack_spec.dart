// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The on-disk contract for a `.wavecruxpack` share bundle.
///
/// A pack is an ordinary ZIP holding four entries — a session document, the
/// waveform subset it references, a rendered preview, and a plain-text README.
/// It exists because a bare `.wavecrux` references a dump the recipient does
/// not have, so it opens to nothing. The pack is the first WaveCrux artifact
/// that is **self-contained and small**, which is precisely the property that
/// lets it travel.
///
/// Both halves of the contract live here so the writer and the reader cannot
/// disagree about entry names, and so the guard limits are stated once.
class WaveCruxPackSpec {
  const WaveCruxPackSpec._();

  /// File extension, dot included, so callers can compose or compare directly.
  static const String fileExtension = '.wavecruxpack';

  /// The session document, with `sourceFilePath` rewritten to
  /// [waveformEntryName] — a *relative* path, which
  /// `SessionService.loadSession` resolves against the extracted directory.
  static const String sessionEntryName = 'session.wavecrux';

  /// The VCD subset the session refers to.
  static const String waveformEntryName = 'waveform.vcd';

  /// The annotated render. Optional: a pack written from a headless context
  /// (or when the capture failed) still opens.
  static const String previewEntryName = 'preview.png';

  /// One paragraph of plain text naming what the file is and where to get the
  /// app. The recipient may have no idea what a `.wavecruxpack` is, and a ZIP
  /// they unpack by hand must still explain itself.
  static const String readmeEntryName = 'README.txt';

  /// The landing page a recipient without WaveCrux is pointed at. Also the
  /// deep-link target the website's `/open` page serves.
  static const String landingPageUrl = 'https://wavecrux.app/open';

  /// Uncompressed-size ceiling enforced while *reading*. Zip-bomb defence,
  /// mirroring `WidgetBundleSpec`: a 4 GB expansion from a 2 MB file is not a
  /// pack anyone produced from this app.
  static const int maxUncompressedBytes = 2 * 1024 * 1024 * 1024;

  /// Path-segment ceiling for an archive entry. A pack is flat by
  /// construction; anything deep is a hand-built archive worth refusing.
  static const int maxPathSegments = 4;

  /// Above this the writer warns before producing the file. Chosen as a
  /// mail-attachment threshold rather than a technical one — the guard exists
  /// because "nobody emails a 4 GB FST", and the moment to say so is before
  /// the write, not after.
  static const int warnAboveBytes = 25 * 1024 * 1024;

  /// Above this the writer refuses outright and asks the user to narrow the
  /// span or the signal list.
  ///
  /// A hard stop rather than a second warning: the estimate is derived from
  /// value-change counts precisely so a multi-GB bundle is caught *before*
  /// anything materialises the document in memory, and a dialog offering
  /// "continue" on a bundle that cannot be built is not a choice.
  static const int refuseAboveBytes = 512 * 1024 * 1024;

  /// Fraction of the annotated span added to each end of the exported window,
  /// so a note about an edge arrives with the context around that edge.
  static const double spanPaddingFraction = 0.2;

  /// True when [path] names a pack (case-insensitive). Does not check that the
  /// file exists or decodes — that is the reader's job, exactly as
  /// `SessionService.isSessionFilePath` leaves parsing to the loader.
  static bool isPackFilePath(String path) =>
      path.toLowerCase().endsWith(fileExtension);

  /// True when an archive entry name is safe to write under an extraction
  /// root: relative, no traversal, no drive letter, no backslash separators,
  /// and not absurdly deep.
  ///
  /// Packs are produced by this app and are still treated as untrusted — the
  /// whole point of the format is that it arrives by email from someone else.
  static bool isSafeEntryName(String name) {
    if (name.isEmpty) return false;
    if (name.startsWith('/') || name.contains(r'\')) return false;
    // Drive-letter and UNC forms, which `path.isRelative` accepts on POSIX.
    if (RegExp('^[a-zA-Z]:').hasMatch(name)) return false;
    final segments = name.split('/');
    if (segments.length > maxPathSegments) return false;
    for (final segment in segments) {
      if (segment == '..') return false;
    }
    return true;
  }
}
