// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Approved decoder plugins, by content hash.
///
/// ### Why this is a security item rather than an Enterprise nicety
///
/// Before this, `FfiDecoderLoader` performed **no signature check and no
/// allowlist**: it opened a native library from a path and registered whatever
/// the manifest declared. For a buyer whose whole posture is *"design IP does
/// not leave the building"*, *"any `.so` on the path is loaded into the tool
/// that reads our RTL"* is a question they will ask, and the honest answer was
/// uncomfortable.
///
/// ### The default is the decision to get right
///
/// **With no policy file there is no allowlist, and every plugin loads exactly
/// as it did before.** Refusing everything by default would break every
/// existing user — including the SigRok bridge, which is a shipped, supported
/// integration — the first time they updated. An allowlist constrains only
/// once an administrator has written one, which is also what makes it
/// meaningful: a list somebody chose beats a list that appeared.
///
/// ### Hashing is not signing
///
/// This is SHA-256 over the file's bytes, compared against a list. It answers
/// *"is this the exact binary the organization approved?"* and nothing else.
/// It does **not** establish who built the plugin, and it cannot: a hash has no
/// author. Ed25519 plugin signing and a `wavecrux-sign` CLI are the feature
/// that would, and they are deliberately **not built** — they need a customer
/// with their own plugin pipeline, and building a signing story blind builds
/// the wrong one.
///
/// What the hash does buy is the property that actually matters here: an
/// administrator vets a binary once, records its digest, and a substituted or
/// modified file stops loading. That is the whole of the threat this addresses,
/// and it is worth stating that it is not more.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// The organization's approved-plugin list, or the absence of one.
@immutable
final class PluginAllowlist {
  const PluginAllowlist._(this._digests, {required this.isConfigured});

  /// An administrator's list, even when it is empty.
  factory PluginAllowlist.configured(Iterable<String> digests) =>
      PluginAllowlist._(
        Set<String>.unmodifiable(<String>{
          for (final digest in digests) ?_normalize(digest),
        }),
        isConfigured: true,
      );

  /// Parses the policy value: a list of hex digests.
  ///
  /// Returns [absent] for a missing key, so the caller's "no policy, no
  /// allowlist" path needs no null check. A value of the wrong *shape* is also
  /// [absent] rather than an empty list — a malformed key must not silently
  /// become the strictest possible policy and stop every plugin in the fleet.
  factory PluginAllowlist.fromPolicyValue(Object? raw) {
    if (raw is! List) return absent;
    return PluginAllowlist.configured(<String>[
      for (final entry in raw)
        if (entry is String) entry,
    ]);
  }

  /// No administrator has written a list. **Everything loads.**
  static const PluginAllowlist absent = PluginAllowlist._(
    <String>{},
    isConfigured: false,
  );

  final Set<String> _digests;

  /// Whether an administrator has configured a list at all.
  ///
  /// The distinction this whole class turns on: an **empty** list is not the
  /// same as **no** list. No list means the key is absent and nothing is
  /// constrained. An empty list means an administrator wrote
  /// `"approvedPlugins": []`, which says *no plugins are approved* — and that
  /// is honoured, because refusing to honour it would make the strictest
  /// posture the one thing the key cannot express.
  final bool isConfigured;

  /// How many digests are approved.
  int get length => _digests.length;

  /// Whether [digest] is approved. Case- and whitespace-insensitive.
  bool allowsDigest(String digest) {
    final normalized = _normalize(digest);
    return normalized != null && _digests.contains(normalized);
  }

  /// Whether the file at [path] is approved.
  ///
  /// **A file that cannot be read is refused**, not admitted. An unreadable
  /// plugin is one this process cannot hash, and admitting what it cannot
  /// verify would make the allowlist advisory. The loader reports the refusal
  /// with the reason, so a permissions problem does not present as a policy
  /// one.
  bool allowsFile(String path) {
    if (!isConfigured) return true;
    final digest = digestOfFile(path);
    return digest != null && allowsDigest(digest);
  }

  /// SHA-256 of the file at [path] as lowercase hex, or `null` when it cannot
  /// be read.
  ///
  /// Read whole rather than streamed: a decoder plugin is a shared library of
  /// a few hundred kilobytes, this runs once per file per scan, and a chunked
  /// read would add a failure mode (a partial read hashing to something
  /// plausible) for no measurable gain.
  static String? digestOfFile(String path) {
    try {
      return sha256.convert(File(path).readAsBytesSync()).toString();
    } on Object {
      // `on Object`: a missing file, a permissions error and a path that is
      // actually a directory all mean the same thing here — this process
      // cannot verify it.
      return null;
    }
  }

  /// Lowercases, trims, and rejects anything that is not a SHA-256 hex digest.
  ///
  /// Tolerates a `sha256:` prefix, because that is how a digest is written in
  /// most other tools an administrator will have copied one out of.
  static String? _normalize(String raw) {
    var value = raw.trim().toLowerCase();
    if (value.startsWith('sha256:')) value = value.substring(7);
    if (value.length != 64) return null;
    for (final unit in value.codeUnits) {
      final isDigit = unit >= 0x30 && unit <= 0x39;
      final isHex = unit >= 0x61 && unit <= 0x66;
      if (!isDigit && !isHex) return null;
    }
    return value;
  }

  @override
  String toString() => isConfigured
      ? 'PluginAllowlist($length approved)'
      : 'PluginAllowlist(not configured)';
}

/// Encodes a digest the way the policy file writes it, for docs and for the
/// message the loader prints when it refuses one.
String formatPluginDigest(String digest) => 'sha256:$digest';

/// What the loader decided about one candidate plugin.
///
/// **Carries a display name and a digest, never a path.** A plugin path is a
/// filesystem path and carries a username; the audit rule every emitter in the
/// suite follows is that a payload never holds one. The digest is what
/// identifies the binary, and it is exactly what an administrator compares
/// against their own list — which makes it the more useful field as well as the
/// safe one.
@immutable
class PluginLoadEvent {
  /// Creates a [PluginLoadEvent].
  const PluginLoadEvent({
    required this.displayName,
    required this.digest,
    required this.refused,
  });

  /// The plugin's file name — user vocabulary, not a path.
  final String displayName;

  /// SHA-256 of the file, or `null` when it could not be read.
  final String? digest;

  /// Whether the organization's allowlist refused it.
  final bool refused;
}

/// Notified once per candidate plugin the loader considers.
typedef PluginLoadObserver = void Function(PluginLoadEvent event);
