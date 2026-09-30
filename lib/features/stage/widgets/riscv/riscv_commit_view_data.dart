// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_stage_widget.dart';
import 'package:wavecrux/services/riscv/riscv_abi_register_name.dart';
import 'package:wavecrux/services/riscv/riscv_arch_state.dart';
import 'package:wavecrux/services/riscv/riscv_consistency_checker.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';

/// Everything the RVFI Commit Inspector's five views read, assembled once per
/// build by the renderer.
///
/// The split matters for a reason beyond tidiness: the retire stream and the
/// checker run over the **whole trace**, while the architectural state is a
/// fold up to the **cursor**. Violations therefore exist ahead of the cursor
/// and stay clickable — which is the point, since "jump to the retirement
/// that broke" is the workflow the checker exists to serve.
@immutable
class RiscvCommitViewData {
  const RiscvCommitViewData({
    required this.retires,
    required this.violations,
    required this.checkOptions,
    required this.state,
    required this.report,
    required this.cursorTime,
    required this.naming,
    required this.registerCount,
  });

  /// Every retirement in the trace, ordered.
  final List<RiscvRetiredInstruction> retires;

  /// Every violation over the whole trace, in stream order.
  final List<RiscvConsistencyViolation> violations;

  /// Which rules ran, and which could not.
  final RiscvConsistencyCheckOptions checkOptions;

  /// Architectural state folded up to [cursorTime].
  final RiscvArchState state;

  /// What the instance's pins bind and what they do not.
  final RvfiCompletenessReport report;

  /// The primary cursor, in simulation ticks.
  final int cursorTime;

  /// How register indices are labelled.
  final RiscvCommitRegisterNaming naming;

  /// Architectural integer register count (32, or 16 for RV32E).
  final int registerCount;

  /// Retirements at or before the cursor — what the three history views show.
  ///
  /// A view that showed retirements *ahead* of the cursor would be claiming
  /// the core has already executed them, which is exactly the kind of
  /// plausible lie this widget family refuses to tell. The Checks view is
  /// the deliberate exception: a violation you cannot see until you have
  /// already scrubbed past it is useless.
  List<RiscvRetiredInstruction> get retiredSoFar => [
    for (final r in retires)
      if (r.time <= cursorTime) r,
  ];

  /// Violations anchored at [retireIndex], if any.
  List<RiscvConsistencyViolation> violationsAt(int retireIndex) => [
    for (final v in violations)
      if (v.retireIndex == retireIndex) v,
  ];

  /// The label for register [index] under [naming].
  String registerLabel(int index) => switch (naming) {
    RiscvCommitRegisterNaming.abi => riscvAbiRegisterName(index),
    RiscvCommitRegisterNaming.numeric => riscvNumericRegisterName(index),
  };

  /// How many violations are errors.
  int get errorCount => violations
      .where((v) => v.severity == RiscvViolationSeverity.error)
      .length;

  /// How many violations are warnings.
  int get warningCount => violations
      .where((v) => v.severity == RiscvViolationSeverity.warning)
      .length;
}
