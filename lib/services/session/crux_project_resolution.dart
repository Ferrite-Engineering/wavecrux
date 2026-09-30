// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_project/crux_project.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

/// The `<design>.crux-project` `artifacts:` key WaveCrux consumes.
///
/// The key lives here rather than in `crux_project` on purpose: artifact kinds
/// are opaque strings in the shared package, because "waveform" is WaveCrux's
/// domain vocabulary and crux-shared's domain-neutrality charter keeps
/// single-product nouns out of shared code.
const String kWaveformArtifactKind = 'waveform';

/// The outcome of pointing WaveCrux at a path that might be a design manifest
/// (`<design>.crux-project`) or a design directory holding one.
///
/// "Not a manifest" and "a manifest that names no waveform" must lead to
/// different behaviour, and collapsing them loses the only useful message —
/// which is why this type exists rather than a nullable String.
sealed class CruxProjectResolution {
  const CruxProjectResolution();
}

/// The path was not a manifest — open it as an ordinary file.
class NotAManifest extends CruxProjectResolution {
  /// Creates the pass-through outcome.
  const NotAManifest(this.path);

  /// The path, unchanged.
  final String path;
}

/// The manifest named a waveform and it is on disk.
class ManifestWaveform extends CruxProjectResolution {
  /// Creates the success outcome.
  const ManifestWaveform({
    required this.waveformPath,
    required this.designId,
    required this.displayName,
    this.warnings = const <String>[],
    this.legacySuggestedFileName,
  });

  /// The waveform to open.
  final String waveformPath;

  /// CXP design id, derived from the manifest's directory.
  final String designId;

  /// The manifest's human label, for the message shown on open.
  final String displayName;

  /// Non-fatal parse warnings worth surfacing once.
  final List<String> warnings;

  /// The file name to rename a legacy bare `.crux-project` manifest to, or
  /// null when the manifest is already named `<design>.crux-project`.
  ///
  /// The shared parser also records an English deprecation warning first in
  /// [warnings]; this field exists so the viewer can say it in the user's
  /// language instead.
  final String? legacySuggestedFileName;
}

/// The path was a manifest but there is nothing here for WaveCrux to open.
///
/// Carries a phrased [message] rather than a code, because every caller does
/// the same thing with it — shows it — and three call sites phrasing it three
/// ways is how a user learns the products disagree.
class ManifestUnusable extends CruxProjectResolution {
  /// Creates the refusal outcome.
  const ManifestUnusable(this.message);

  /// User-facing explanation.
  final String message;
}

/// A design directory holds more than one manifest, so there is no telling
/// which design the user meant.
///
/// Carries the raw [directory] and [candidates] rather than a phrased message,
/// so the viewer can name them in the user's language.
class ManifestAmbiguous extends CruxProjectResolution {
  /// Creates the ambiguity outcome.
  const ManifestAmbiguous({required this.directory, required this.candidates});

  /// The directory that was opened.
  final String directory;

  /// Every manifest found in [directory], sorted.
  final List<String> candidates;
}

/// Resolves a path that might designate a design manifest to the waveform
/// WaveCrux opens.
///
/// A manifest is `<design>.crux-project`; the legacy bare `.crux-project`
/// still opens. A directory opens the single manifest inside it.
///
/// Sits in front of the ordinary open flow rather than inside it: a manifest is
/// swapped for its waveform *before* anything else runs, so tab reuse, the
/// large-file warning, format conversion and session restore all behave
/// exactly as they do for a directly-opened dump. Nothing downstream needs to
/// know a manifest was involved.
class CruxProjectResolver {
  /// Creates a resolver.
  const CruxProjectResolver({
    CruxProjectParser parser = const CruxProjectParser(),
    CruxProjectOpenPlanner planner = const CruxProjectOpenPlanner(),
  }) : _parser = parser,
       _planner = planner;

  final CruxProjectParser _parser;
  final CruxProjectOpenPlanner _planner;

  /// Resolves [path].
  ///
  /// [exists] is injectable for tests; production uses the planner's default.
  CruxProjectResolution resolve(
    String path, {
    bool Function(String path)? exists,
  }) {
    // The web build has no filesystem to read a manifest from, and a URL is
    // fetched rather than read from disk on every platform.
    if (kIsWeb || path.startsWith('http://') || path.startsWith('https://')) {
      return NotAManifest(path);
    }

    final String? manifestPath;
    try {
      manifestPath = CruxProjectParser.locate(path);
    } on CruxProjectAmbiguousException catch (e) {
      return ManifestAmbiguous(
        directory: e.directory,
        candidates: e.candidates,
      );
    }
    if (manifestPath == null) return NotAManifest(path);

    final CruxProjectManifest manifest;
    try {
      manifest = _parser.parseFile(manifestPath);
    } on CruxProjectFormatException catch (e) {
      return ManifestUnusable('Not a valid .crux-project file — ${e.message}');
    }

    final plan = _planner.plan(
      manifest,
      kind: kWaveformArtifactKind,
      exists: exists,
    );

    final artifact = plan.artifactPath;
    if (artifact != null) {
      return ManifestWaveform(
        waveformPath: artifact,
        designId: plan.designId,
        displayName: manifest.displayName,
        warnings: manifest.warnings,
        legacySuggestedFileName:
            CruxProjectParser.isLegacyManifestPath(manifestPath)
            ? '${p.basename(manifest.directory)}.$kCruxProjectExtension'
            : null,
      );
    }

    return ManifestUnusable(
      switch (plan.refusal) {
        CruxOpenRefusal.pathMissing =>
          'The waveform this project names is missing: '
              '${manifest.rawArtifacts[kWaveformArtifactKind]}',
        CruxOpenRefusal.kindAbsent || null =>
          '${manifest.displayName} does not name a waveform yet. '
              'Add a `waveform:` entry under `artifacts:` in its '
              '.crux-project file.',
      },
    );
  }
}
