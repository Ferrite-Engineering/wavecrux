// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/interfaces/debug_advisor_service.dart';
import 'package:wavecrux/services/debug_advisor/noop_debug_advisor_service.dart';

/// Open-core extension point exposing the active [DebugAdvisorService].
///
/// Open-core default returns a singleton [NoopDebugAdvisorService] that
/// always reports zero suggestions. The closed-source Pro
/// overlay overrides this binding with a heuristic rule engine
/// implementing the four Debug Advisor rule families
/// (X-propagation chain, clock-domain crossing, stuck-at, timing
/// violation).
///
/// The "Debug Advisor" name is load-bearing — never "AI Debug" — and
/// open-core ships every gate primitive needed to render the panel
/// (interface, model, no-op service, this provider) without coupling Open
/// Core to the Pro implementation.
final debugAdvisorServiceProvider = Provider<DebugAdvisorService>(
  (_) => const NoopDebugAdvisorService(),
);
