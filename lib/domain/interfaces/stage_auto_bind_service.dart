// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/board_auto_bind_candidate.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/variable.dart';

/// Computes a best-guess binding of a Stage widget's pins against the
/// signals available in the loaded waveform.
///
/// The Stage bindings pane offers an "Auto-bind" affordance for any widget
/// whose definition resolves to one of these; the resulting candidate set is
/// rendered in the preview dialog before anything is applied, so an
/// implementation is free to guess as long as every candidate carries an
/// honest confidence tier and a human-readable reason.
///
/// Two implementations ship in open core:
///
/// - `BoardAutoBindService` — the family/vector-fan-out matcher behind the
///   FPGA board widgets. It is selected for every [StageWidget] that is a
///   `CompoundStageWidget`, which is how the affordance behaved before this
///   interface existed.
/// - `RvfiDetectionService` — recognizes the riscv-formal RVFI bundle by
///   name pattern for the RISC-V Core Designer widgets, which are not
///   compound and so had no route to the affordance at all.
///
/// Pure Dart — no Flutter imports. Implementations must be `const`.
// An extension point, not a callback: implementations are `const` values
// referenced from widget definitions, and the interface is the seam the Pro
// overlay implements. Same rationale as TelemetryService / DebugAdvisorService.
abstract class StageAutoBindService {
  const StageAutoBindService();

  /// Proposes bindings for [widget]'s pins.
  ///
  /// [availableSignals] is the loaded design's variable map keyed the same
  /// way `signalVariablesMapProvider` keys it. [existingBindings] are the
  /// instance's current bindings — an implementation must not silently
  /// overwrite a binding the user made by hand. [configuration] is the
  /// instance's live config map, which widgets with a configurable pin count
  /// need in order to know how many pins actually exist.
  ///
  /// The returned map is keyed by pin name. A pin an implementation cannot
  /// place should be returned with a `noMatch` candidate rather than omitted,
  /// so the preview dialog can show the user what was *not* found.
  BoardAutoBindResult autoBind({
    required StageWidget widget,
    required Map<String, Variable> availableSignals,
    Map<String, StageSignalBinding> existingBindings = const {},
    Map<String, Object?> configuration = const {},
  });
}
