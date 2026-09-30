// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Localized rendering of the pure-Dart consistency checker's output.
///
/// The checker is Flutter-free and produces a non-localized
/// [RiscvConsistencyViolation.detail] plus the interpolation
/// [RiscvConsistencyViolation.args]. This file is the one place that maps
/// those onto ARB messages, so the checker never grows a dependency on the
/// localization layer and the localization layer never grows a copy of the
/// rules.
///
/// The `args[n]` indexing below is checked two ways: the violation
/// constructor asserts `args.length == kind.argCount`, and a test formats one
/// synthetic violation of **every** kind in **every** locale. An index error
/// therefore fails a test rather than a user's session.
library;

import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/riscv/riscv_consistency_checker.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';

/// The localized, specific sentence for [violation].
///
/// Specific is the point. "Inconsistency detected" tells a core designer
/// nothing; "`sw` accesses 4 bytes, but the rvfi_mem byte masks cover 2" is
/// something they can go and fix.
String riscvViolationMessage(L10N l10n, RiscvConsistencyViolation violation) {
  final a = violation.args;
  return switch (violation.kind) {
    RiscvViolationKind.controlFlowDiscontinuity =>
      l10n.riscvCommitViolationControlFlow(a[0], a[1], a[2]),
    RiscvViolationKind.x0NonZeroWrite => l10n.riscvCommitViolationX0Write(a[0]),
    RiscvViolationKind.destinationRegisterMismatch =>
      l10n.riscvCommitViolationRdMismatch(a[0], a[1], a[2]),
    RiscvViolationKind.memorySizeMismatch =>
      l10n.riscvCommitViolationMemorySize(a[0], a[1], a[2]),
    RiscvViolationKind.memoryMisaligned =>
      l10n.riscvCommitViolationMemoryMisaligned(a[0], a[1]),
    RiscvViolationKind.memoryMaskNotContiguous =>
      l10n.riscvCommitViolationMemoryMaskHole(a[0]),
    RiscvViolationKind.memoryAccessMissing =>
      l10n.riscvCommitViolationMemoryMissing(a[0], a[1]),
    RiscvViolationKind.memoryAccessUnexpected =>
      l10n.riscvCommitViolationMemoryUnexpected(a[0], a[1], a[2]),
    RiscvViolationKind.orderGap => l10n.riscvCommitViolationOrderGap(
      a[0],
      a[1],
      a[2],
    ),
    RiscvViolationKind.orderRegression =>
      l10n.riscvCommitViolationOrderRegression(a[0], a[1]),
    RiscvViolationKind.trapNoRedirect =>
      l10n.riscvCommitViolationTrapNoRedirect(a[0], a[1]),
    RiscvViolationKind.trapNoHandlerEntry =>
      l10n.riscvCommitViolationTrapNoHandler(a[0]),
    RiscvViolationKind.trapPrivilegeDrop =>
      l10n.riscvCommitViolationTrapPrivilegeDrop(a[0], a[1]),
  };
}

/// The localized name of a checker rule, for the "not checked" line and the
/// per-violation label.
String riscvRuleName(L10N l10n, RiscvCheckRule rule) => switch (rule) {
  RiscvCheckRule.controlFlow => l10n.riscvCommitRuleControlFlow,
  RiscvCheckRule.x0Write => l10n.riscvCommitRuleX0Write,
  RiscvCheckRule.destinationRegister => l10n.riscvCommitRuleDestinationRegister,
  RiscvCheckRule.memoryAccess => l10n.riscvCommitRuleMemoryAccess,
  RiscvCheckRule.retireOrder => l10n.riscvCommitRuleRetireOrder,
  RiscvCheckRule.trapConsistency => l10n.riscvCommitRuleTrapConsistency,
};

/// The localized severity label.
String riscvSeverityLabel(L10N l10n, RiscvViolationSeverity severity) =>
    switch (severity) {
      RiscvViolationSeverity.error => l10n.riscvCommitSeverityError,
      RiscvViolationSeverity.warning => l10n.riscvCommitSeverityWarning,
    };

/// `rvfi_trap, rvfi_mode, rvfi_ixl` — the canonical port names of a channel
/// set, comma-joined, for the "which channels are missing" banner.
///
/// Deliberately **not** localized: these are Verilog port names on the user's
/// own design, and translating them would make the banner unusable as a
/// checklist against the RTL.
String riscvChannelList(Iterable<RvfiChannel> channels) {
  final names = [for (final c in channels) c.signalName]..sort();
  return names.join(', ');
}
