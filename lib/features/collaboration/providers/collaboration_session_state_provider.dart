// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/providers/collaboration_service_provider.dart';
import 'package:wavecrux/domain/interfaces/collaboration_service.dart';

/// Live stream of [CollabSessionState] from the active [CollaborationService].
///
/// Consumers that render collaborator cursors or session indicators use
/// `.value` and treat `null` as "no session". `.value` is `null` in three
/// cases that all mean the same thing at the call site:
///
/// * the provider is still in [AsyncLoading] (the no-op default service's
///   [CollaborationService.sessionState] is `Stream.empty()` and never emits);
/// * a session is active but no state has arrived yet;
/// * **a session just ended** — the Pro service emits `null` on leave / stop /
///   transport drop, so the provider returns to `AsyncData(null)` and every
///   session-chrome surface (status chip, mismatch banner, action-context
///   `inSession`/`isHost` gating) clears. Without this terminal `null` the
///   provider would keep its last non-null value forever and the UI would look
///   like the session was still live.
///
/// The Pro overlay's `CollaborationServiceImpl` returns a broadcast stream that
/// emits a new [CollabSessionState] on every participant or cursor change, so
/// the provider stays live for the duration of the session.
final collaborationSessionStateProvider = StreamProvider<CollabSessionState?>(
  (ref) => ref.watch(collaborationServiceProvider).sessionState,
  // Riverpod 3 retries failed providers by default. Suppress here so a
  // session-stream error surfaces immediately to the UI (which renders the
  // error and lets the user decide whether to reconnect). The
  // `CollaborationServiceImpl` in the Pro overlay is responsible for any
  // transport-level reconnect logic — Riverpod retry would mask that.
  retry: (_, _) => null,
);
