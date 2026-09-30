// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'waveform_identity_provider.g.dart';

/// The SHA-256 content hash of the currently loaded waveform file, or `null`
/// when no file is open (or the source has no hashable bytes, e.g. a streaming
/// stdin/pipe source).
///
/// This is the reactive surface the collaborative-viewing bridge watches to
/// announce *which waveform* the local participant has open. [WaveformSourceNotifier]
/// publishes into it: it [set]s `null` synchronously when a load starts or the
/// file closes, then [set]s the computed digest once hashing completes. Keeping
/// the hash in a dedicated notifier — rather than on the
/// `AsyncValue<WaveformDataSource?>` source state — lets the digest land
/// *after* the source is already `AsyncData`, so watchers (the collab bridge)
/// react to the hash arriving without the source state having to change again.
///
/// Hashing is computed off the UI thread (see `WaveformContentHash.ofFile`), so
/// for a large file this provider transiently stays `null` after the file opens
/// and flips to the digest a moment later — the identity check tolerates that
/// window (a not-yet-reported hash is never a mismatch).
@Riverpod(keepAlive: true)
class WaveformIdentity extends _$WaveformIdentity {
  @override
  String? build() => null;

  /// Replace the published content hash. Pass `null` to clear it.
  ///
  /// A named mutator (rather than a setter) keeps the call site explicit at the
  /// publish points in `WaveformSourceNotifier`.
  // ignore: use_setters_to_change_properties
  void set(String? contentHash) => state = contentHash;
}
