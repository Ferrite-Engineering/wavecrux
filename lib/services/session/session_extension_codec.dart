// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Captures a Pro-side payload from the live Riverpod graph at session
/// snapshot time. Return `null` to opt out (the codec's namespace is left
/// untouched in the in-memory extensions map — any prior unknown payload
/// under the same key survives the snapshot).
typedef SessionExtensionCapture = Object? Function(Ref ref);

/// Restores a Pro-side payload back into the live Riverpod graph after a
/// `.wavecrux` document is loaded. [payload] is the JSON-decoded value the
/// codec previously returned from its [SessionExtensionCapture]; codecs are
/// responsible for validating shape and falling back gracefully on
/// unexpected values.
typedef SessionExtensionRestore = void Function(Ref ref, Object? payload);

/// Pair of capture / restore callbacks that owns a single namespace under
/// the reserved top-level `extensions` map on a `.wavecrux` document.
///
/// Codecs are registered through [extraSessionPayloadCodecsProvider]. The
/// open-core default registry is empty; the Pro overlay's `proOverrides`
/// list contributes per-feature codecs (decoder runtime, SVA results,
/// future Debug Advisor pins, …). See `docs/ARCHITECTURE.md` §10 — Session
/// per-tab extension payload — for the contract.
class SessionExtensionCodec {
  const SessionExtensionCodec({
    required this.capture,
    required this.restore,
  });

  final SessionExtensionCapture capture;
  final SessionExtensionRestore restore;
}

/// Registry of `.wavecrux` session-extension codecs keyed by namespace
/// (`"pro.sva"`, `"pro.debug_advisor"`, …). The open-core default returns
/// an empty map; the Pro overlay replaces this provider in its
/// `proOverrides` with a populated registry.
///
/// Namespaces present in a loaded document but absent from this registry
/// are PRESERVED-BUT-INERT: they ride through on
/// [SessionState.extensions] and are re-emitted verbatim on the next save
/// (the preserve-unknown invariant). This is the same fail-safe the
/// `extensions` map provides for newer-schema documents opened on a
/// slightly-older Pro / open-core build.
///
/// The first production subscriber is the Pro overlay's `"pro.sva"` codec; the live
/// capture/restore wiring lives in `SessionNotifier._snapshot` / `_restore`.
final extraSessionPayloadCodecsProvider =
    Provider<Map<String, SessionExtensionCodec>>((_) => const {});

/// Helpers that run the registered codec set against the live provider
/// graph. Kept separate from [SessionService] so the serializer stays
/// `Ref`-free and the codec runtime can be exercised in tests without
/// pulling in the full per-tab provider scope.
class SessionExtensions {
  const SessionExtensions._();

  /// Captures every registered codec's payload and overlays the results
  /// onto [base] (typically the previously-loaded session's extensions
  /// map). Unknown-namespace entries in [base] are preserved untouched so
  /// the round-trip invariant survives a snapshot taken on a build that
  /// does not understand them.
  static Map<String, Object?> capture(Ref ref, Map<String, Object?> base) {
    final codecs = ref.read(extraSessionPayloadCodecsProvider);
    if (codecs.isEmpty) return Map<String, Object?>.from(base);
    final out = Map<String, Object?>.from(base);
    for (final entry in codecs.entries) {
      final captured = entry.value.capture(ref);
      if (captured != null) out[entry.key] = captured;
    }
    return out;
  }

  /// Invokes [SessionExtensionCodec.restore] for each registered codec
  /// whose namespace appears in [extensions]. Codecs for namespaces not
  /// present in the document are skipped. Unknown-namespace entries (no
  /// codec registered) are ignored here and survive on the
  /// [SessionState.extensions] map for the next save.
  static void restore(Ref ref, Map<String, Object?> extensions) {
    if (extensions.isEmpty) return;
    final codecs = ref.read(extraSessionPayloadCodecsProvider);
    if (codecs.isEmpty) return;
    for (final entry in codecs.entries) {
      if (!extensions.containsKey(entry.key)) continue;
      entry.value.restore(ref, extensions[entry.key]);
    }
  }
}
