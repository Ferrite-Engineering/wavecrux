// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/compound_stage_widget.dart';
import 'package:wavecrux/domain/interfaces/stage_auto_bind_service.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/services/stage/board_auto_bind_service.dart';

/// Resolves the [StageAutoBindService] the Stage bindings pane should run for
/// [def], or `null` when the widget offers no auto-bind affordance.
///
/// Resolution order:
///
/// 1. [StageWidget.supportsAutoBind] false → no affordance.
/// 2. An explicitly declared [StageWidget.autoBindService] wins. This is the
///    route a **non-compound** widget takes; before this seam existed the
///    affordance was hard-gated on `CompoundStageWidget`, so a 20-pin RVFI
///    widget had no way to reach it.
/// 3. Otherwise a compound widget falls back to the shared board matcher —
///    which is exactly, and only, what the pane used to do unconditionally.
///    Keeping the fallback here rather than making every board declare it is
///    what makes board auto-bind byte-for-byte unchanged by this seam.
StageAutoBindService? stageAutoBindServiceFor(StageWidget def) {
  if (!def.supportsAutoBind) return null;
  final declared = def.autoBindService;
  if (declared != null) return declared;
  if (def is CompoundStageWidget) return const BoardAutoBindService();
  return null;
}
