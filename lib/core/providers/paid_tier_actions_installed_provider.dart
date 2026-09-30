// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether this build carries the handlers for the Pro and Enterprise actions.
///
/// **Open-core default: false.** Open core lists those actions — with their
/// tier badge, so the capability is discoverable — but their extension points
/// default to no-ops. Firing one then says "requires WaveCrux Pro" (or
/// Enterprise) instead of doing nothing.
///
/// **Pro override: true.** The Pro overlay wires every one of those extension
/// points, and its handlers apply the licence gate themselves.
final paidTierActionsInstalledProvider = Provider<bool>(
  (ref) => false,
  name: 'paidTierActionsInstalledProvider',
);
