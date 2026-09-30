// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/debug_advisor_service.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';

/// Open-core default [DebugAdvisorService]: returns no suggestions.
///
/// The Pro overlay swaps this implementation for a heuristic rule engine.
/// Open-core ships the no-op so Open Core builds can render the panel
/// (with an empty state) without depending on the Pro implementation.
class NoopDebugAdvisorService implements DebugAdvisorService {
  /// Const constructor so the open-core provider returns a singleton.
  const NoopDebugAdvisorService();

  @override
  List<DebugAdvisorSuggestion> analyze({
    required WaveformDataSource source,
    required List<Scope> hierarchy,
    required int cursorTime,
    String? focusSignalRef,
  }) => const <DebugAdvisorSuggestion>[];
}
