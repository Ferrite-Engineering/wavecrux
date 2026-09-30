// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/interfaces/collaboration_service.dart';
import 'package:wavecrux/services/collaboration/noop_collaboration_service.dart';

/// Open-core extension point exposing the active [CollaborationService].
///
/// Open-core default returns a singleton [NoopCollaborationService] that
/// makes no network calls and returns neutral values for every query.
/// The closed-source Pro overlay replaces this binding with
/// `CollaborationServiceImpl` (hybrid LAN mDNS + WAN relay), gated behind
/// `FeatureGate.isAvailable(LicenseTier.enterprise, ref)`.
///
/// Callers must never assume the active implementation is network-capable.
final collaborationServiceProvider = Provider<CollaborationService>(
  (_) => const NoopCollaborationService(),
);
