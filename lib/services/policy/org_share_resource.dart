// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// A file on the organization's own share, named by the policy file and
/// optionally pinned by content hash.
///
/// Two of WaveCrux's C5 keys reference one — `themePacks` and
/// `sessionTemplates` — and the plan's wording for both is the same: *"by path
/// or content hash, distributed on the organization's own share"*. This is that
/// mechanism, once.
///
/// ### Nothing is hosted, and nothing is fetched
///
/// A "share" is a path the customer already has: an NFS mount, a mapped drive,
/// a synced folder, a git checkout. There is no download, no URL and no
/// caching layer, because every one of those would be a thing Ferrite has to
/// run or a thing that fails differently on an airgapped machine. If the
/// organization can put a file where every engineer can read it — which is the
/// premise of the whole Enterprise-without-servers position — this works.
///
/// ### The hash is a pin, not a permission
///
/// `sha256` is **optional** and its absence is not laxity: a theme pack the
/// organization edits weekly should not need a policy-file commit each time.
/// When it *is* present the file must match, and a mismatch is a refusal
/// rather than a warning — a pinned resource that silently loaded something
/// else would be worse than one that did not load.
///
/// This is the same distinction the decoder-plugin allowlist draws, and worth
/// repeating because the two look similar and are not: **the plugin allowlist
/// decides whether to execute code**, so it refuses what it cannot verify. This
/// decides whether to apply a *preference*, so an unpinned resource is a
/// legitimate configuration rather than a hole.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// One resource reference from the policy file.
@immutable
final class OrgShareResource {
  /// Creates an [OrgShareResource].
  const OrgShareResource({required this.path, this.sha256Digest});

  /// Parses `{"path": …, "sha256": …}`, or a bare path string.
  ///
  /// The bare-string form exists because it is what an administrator writes
  /// first, and refusing it would make the simplest case the one that needs
  /// the manual.
  static OrgShareResource? parse(Object? raw) {
    if (raw is String) {
      final path = raw.trim();
      return path.isEmpty ? null : OrgShareResource(path: path);
    }
    if (raw is! Map<String, Object?>) return null;
    final path = raw['path'];
    if (path is! String || path.trim().isEmpty) return null;
    final digest = raw['sha256'];
    return OrgShareResource(
      path: path.trim(),
      sha256Digest: digest is String && digest.trim().isNotEmpty
          ? digest.trim().toLowerCase()
          : null,
    );
  }

  /// Where the file is, on a path the customer already has.
  final String path;

  /// The digest the file must match, or `null` to accept whatever is there.
  final String? sha256Digest;

  /// Whether this reference pins a specific content.
  bool get isPinned => sha256Digest != null;
}

/// Why a resource could not be used.
enum OrgShareFailure {
  /// Nothing at that path.
  missing,

  /// There, but unreadable — permissions, a dead mount, a directory.
  unreadable,

  /// There and readable, but not the pinned content.
  digestMismatch,

  /// There, readable, matching, and not the format it claims to be.
  malformed,
}

/// A loaded resource, or the reason there is not one.
@immutable
final class OrgShareLoad {
  /// A successful load.
  const OrgShareLoad.ok(this.contents) : failure = null, detail = null;

  /// A failure, with a sentence for whoever has to fix it.
  const OrgShareLoad.failed(this.failure, {this.detail}) : contents = null;

  /// The file's decoded JSON, when it loaded.
  final Map<String, Object?>? contents;

  /// Why it did not, when it did not.
  final OrgShareFailure? failure;

  /// The detail an administrator needs — a path, never a value.
  final String? detail;

  /// Whether the resource loaded.
  bool get isOk => contents != null;
}

/// Reads [resource] from the organization's share.
///
/// **Synchronous, and that is a constraint on where it may be called.** These
/// are read at startup and on a settings open, never on a frame, and a
/// synchronous read keeps the "no policy, no cost" path a single `existsSync`.
/// A caller on a hot path is a caller in the wrong place.
///
/// Every failure is reported rather than swallowed. An organization that
/// pointed at a share nobody can reach must find out from the application, not
/// from an engineer noticing their theme never changed.
OrgShareLoad loadOrgShareResource(OrgShareResource resource) {
  final file = File(resource.path);
  if (!file.existsSync()) {
    return OrgShareLoad.failed(
      OrgShareFailure.missing,
      detail: 'no file at ${resource.path}',
    );
  }

  final List<int> bytes;
  try {
    bytes = file.readAsBytesSync();
  } on Object catch (error) {
    return OrgShareLoad.failed(
      OrgShareFailure.unreadable,
      detail: 'could not read ${resource.path}: $error',
    );
  }

  final pinned = resource.sha256Digest;
  if (pinned != null) {
    final actual = sha256.convert(bytes).toString();
    if (actual != pinned) {
      return OrgShareLoad.failed(
        OrgShareFailure.digestMismatch,
        // Both digests, because the fix is either "update the file" or "update
        // the policy" and the administrator cannot tell which without seeing
        // what is actually there.
        detail:
            '${resource.path} is pinned to $pinned but is currently $actual',
      );
    }
  }

  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, Object?>) {
      return OrgShareLoad.failed(
        OrgShareFailure.malformed,
        detail: '${resource.path} is not a JSON object',
      );
    }
    return OrgShareLoad.ok(decoded);
  } on FormatException catch (error) {
    return OrgShareLoad.failed(
      OrgShareFailure.malformed,
      detail: '${resource.path} is not valid JSON: ${error.message}',
    );
  }
}
