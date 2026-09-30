// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The RVFI consistency checker — the reason the Commit Inspector exists.
///
/// A commit log is a viewer. A commit log that tells you *your core just did
/// something the ISA does not permit, here, at this retirement* is a tool.
/// This file is the second thing, and it is **open core on purpose**: the
/// tier line for the RISC-V family is "correctness is free, productivity is
/// paid", and gating the checker would
/// invert it.
///
/// Six rules, each a separate, individually testable top-level function over
/// a decoded retire stream:
///
/// | Rule | Function |
/// |---|---|
/// | `pc_wdata(n)` ≠ `pc_rdata(n+1)` | [riscvCheckControlFlow] |
/// | `rd_addr == 0` with non-zero `rd_wdata` | [riscvCheckX0Write] |
/// | `rd_addr` vs the decoded instruction's rd | [riscvCheckDestinationRegister] |
/// | `mem_rmask`/`wmask` vs decoded size / alignment | [riscvCheckMemoryAccess] |
/// | `rvfi_order` gaps and regressions | [riscvCheckRetireOrder] |
/// | trap retire without a consistent privilege/PC change | [riscvCheckTrapConsistency] |
///
/// Two design commitments run through all six:
///
/// 1. **A rule that cannot run says so; it does not pass.** Each rule needs
///    specific RVFI channels, and a partially-instrumented core simply does
///    not carry some of them. [RiscvConsistencyCheckOptions.forBindings]
///    computes which rules the bound channel set supports, and the consumer
///    is expected to *show the user which checks were skipped*. Silently
///    reporting "no violations" for a check that never ran is the one
///    failure mode that would make the whole widget untrustworthy.
/// 2. **Messages are specific.** Every violation carries the concrete values
///    that disagree — the two PCs, the two register indices, the mask and the
///    size — both as a non-localized [RiscvConsistencyViolation.detail] for
///    logs and tooltips and as [RiscvConsistencyViolation.args] for the
///    localized surface. "Inconsistency detected" is not an actionable
///    engineering message.
///
/// Pure Dart — no Flutter imports.
library;

import 'package:meta/meta.dart';
import 'package:wavecrux/services/riscv/riscv_abi_register_name.dart';
import 'package:wavecrux/services/riscv/riscv_instruction_fields.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';

/// The six checker rules.
enum RiscvCheckRule {
  /// `rvfi_pc_wdata` of one retirement must equal `rvfi_pc_rdata` of the
  /// next: a core's own claim about where it goes next has to match where it
  /// actually went — unless the next retirement asserts `rvfi_intr`, which
  /// is precisely how RVFI marks a sanctioned discontinuity into a trap
  /// handler. See [riscvCheckControlFlow].
  controlFlow({RvfiChannel.pcRdata, RvfiChannel.pcWdata}),

  /// `x0` is hardwired zero, so a retirement reporting `rd_addr == 0` with a
  /// non-zero `rd_wdata` is describing a write that cannot have happened.
  x0Write({RvfiChannel.rdAddr, RvfiChannel.rdWdata}),

  /// `rvfi_rd_addr` must name the same register the retired encoding does.
  destinationRegister({RvfiChannel.insn, RvfiChannel.rdAddr}),

  /// The memory byte masks must describe an access of the size the encoding
  /// asks for, contiguous, at a natural alignment.
  memoryAccess({
    RvfiChannel.insn,
    RvfiChannel.memAddr,
    RvfiChannel.memRmask,
    RvfiChannel.memWmask,
  }),

  /// `rvfi_order` is the core's own retirement counter — gaps mean lost
  /// retirements, regressions mean the stream is not a stream.
  retireOrder({RvfiChannel.order}),

  /// A retirement that raised a trap has to show the architectural effects
  /// of one.
  trapConsistency({RvfiChannel.trap, RvfiChannel.pcRdata, RvfiChannel.pcWdata});

  const RiscvCheckRule(this.requiredChannels);

  /// Channels that must be bound for this rule to be able to run at all.
  final Set<RvfiChannel> requiredChannels;

  /// Whether [bindings] carries everything this rule needs.
  bool isSupportedBy(RvfiBindingSet bindings) {
    final found = bindings.foundChannels;
    return requiredChannels.every(found.contains);
  }
}

/// How seriously to take a violation.
enum RiscvViolationSeverity {
  /// The trace states something the ISA does not permit. A correct core
  /// cannot produce this.
  error,

  /// The trace states something legal but suspicious, which a core designer
  /// usually wants to know about — a misaligned access, for example, is
  /// permitted but implementation-defined.
  warning,
}

/// The specific finding, one level finer than [RiscvCheckRule].
///
/// A rule can fail in more than one way and the user is owed the specific
/// one; "memory access inconsistent" is not something an engineer can act
/// on, while "`sw` needs 4 bytes, the masks cover 2" is.
enum RiscvViolationKind {
  /// `pc_wdata(n)` disagrees with `pc_rdata(n+1)`.
  /// Args: previous `pc_wdata`, this `pc_rdata`, previous retirement label.
  controlFlowDiscontinuity(RiscvCheckRule.controlFlow, 3),

  /// `rd_addr == 0` with a non-zero `rd_wdata`.
  /// Args: the reported `rd_wdata`.
  x0NonZeroWrite(RiscvCheckRule.x0Write, 1),

  /// `rd_addr` names a different register than the encoding does.
  /// Args: mnemonic (or raw word), the encoding's rd, the reported rd.
  destinationRegisterMismatch(RiscvCheckRule.destinationRegister, 3),

  /// The masks cover a different number of bytes than the encoding needs.
  /// Args: mnemonic, required byte count, mask byte count.
  memorySizeMismatch(RiscvCheckRule.memoryAccess, 3),

  /// The access is not naturally aligned for its width. Legal but
  /// implementation-defined, so this is a warning.
  /// Args: byte count, effective address.
  memoryMisaligned(RiscvCheckRule.memoryAccess, 2),

  /// The union of the byte masks has a hole in it, so it cannot describe one
  /// load or store.
  /// Args: the combined mask.
  memoryMaskNotContiguous(RiscvCheckRule.memoryAccess, 1),

  /// A load or store retired with no byte mask asserted.
  /// Args: mnemonic, required byte count.
  memoryAccessMissing(RiscvCheckRule.memoryAccess, 2),

  /// A non-memory encoding retired with a byte mask asserted.
  /// Args: mnemonic, read mask, write mask.
  memoryAccessUnexpected(RiscvCheckRule.memoryAccess, 3),

  /// `rvfi_order` skipped forward, so retirements are missing from the trace.
  /// Args: previous order, this order, how many are missing.
  orderGap(RiscvCheckRule.retireOrder, 3),

  /// `rvfi_order` went backwards or repeated.
  /// Args: previous order, this order.
  orderRegression(RiscvCheckRule.retireOrder, 2),

  /// A trapping retirement whose `pc_wdata` is just the sequential next PC,
  /// with no redirect to a trap vector *and* no `rvfi_intr` on the successor
  /// to mark the handler entry that would license it.
  /// Args: `pc_rdata`, `pc_wdata`.
  trapNoRedirect(RiscvCheckRule.trapConsistency, 2),

  /// A trapping retirement whose successor does not assert `rvfi_intr`, so
  /// the trace does not show the handler being entered.
  /// Args: `pc_wdata` of the trapping retirement.
  trapNoHandlerEntry(RiscvCheckRule.trapConsistency, 1),

  /// A trap that lands at a *lower* privilege than it was taken from. Traps
  /// are only ever delegated upward or sideways.
  /// Args: privilege before, privilege after.
  trapPrivilegeDrop(RiscvCheckRule.trapConsistency, 2);

  const RiscvViolationKind(this.rule, this.argCount);

  /// The rule that produces this finding.
  final RiscvCheckRule rule;

  /// How many entries [RiscvConsistencyViolation.args] carries for this
  /// kind. Asserted at construction, so a localized formatter that indexes
  /// past the end fails in a test rather than in front of a user.
  final int argCount;
}

/// One thing the trace says that a correct core could not have done.
@immutable
class RiscvConsistencyViolation {
  RiscvConsistencyViolation({
    required this.kind,
    required this.severity,
    required this.retireIndex,
    required this.time,
    required this.detail,
    required this.args,
    this.order,
    this.pc,
  }) : assert(
         args.length == kind.argCount,
         "violation args do not match the kind's declared argCount",
       );

  /// The specific finding.
  final RiscvViolationKind kind;

  /// The rule that produced it.
  RiscvCheckRule get rule => kind.rule;

  /// How seriously to take it.
  final RiscvViolationSeverity severity;

  /// Index into the retire stream the check ran over. The consumer uses this
  /// to scroll the commit log to the offending row.
  final int retireIndex;

  /// Simulation tick of the offending retirement — what a click on the
  /// violation places the cursor at.
  final int time;

  /// `rvfi_order` of the offending retirement, when the trace carries one.
  final int? order;

  /// `rvfi_pc_rdata` of the offending retirement, when known.
  final int? pc;

  /// Non-localized, fully specific diagnostic. Written for an engineer
  /// reading a log or a tooltip; the localized surface uses [kind] + [args].
  final String detail;

  /// Values the localized message interpolates. See each
  /// [RiscvViolationKind] for what its entries mean.
  final List<String> args;

  @override
  String toString() => 'RiscvConsistencyViolation($kind @ t=$time: $detail)';
}

/// Which rules to run.
@immutable
class RiscvConsistencyCheckOptions {
  const RiscvConsistencyCheckOptions({
    this.enabledRules = const {
      RiscvCheckRule.controlFlow,
      RiscvCheckRule.x0Write,
      RiscvCheckRule.destinationRegister,
      RiscvCheckRule.memoryAccess,
      RiscvCheckRule.retireOrder,
      RiscvCheckRule.trapConsistency,
    },
  });

  /// Derives the runnable rule set from what the trace actually binds, and
  /// reports the rest as [skippedRules] so the consumer can say which checks
  /// did not run instead of implying they passed.
  factory RiscvConsistencyCheckOptions.forBindings(RvfiBindingSet bindings) {
    return RiscvConsistencyCheckOptions(
      enabledRules: {
        for (final rule in RiscvCheckRule.values)
          if (rule.isSupportedBy(bindings)) rule,
      },
    );
  }

  /// Rules that will run.
  final Set<RiscvCheckRule> enabledRules;

  /// Rules that will not run, because the binding set cannot support them.
  Set<RiscvCheckRule> get skippedRules =>
      RiscvCheckRule.values.toSet().difference(enabledRules);

  /// Whether [rule] runs.
  bool isEnabled(RiscvCheckRule rule) => enabledRules.contains(rule);
}

/// Runs the six rules over a decoded retire stream.
class RiscvConsistencyChecker {
  const RiscvConsistencyChecker();

  /// Runs every enabled rule and returns the violations in stream order.
  ///
  /// The stream is expected to be the one
  /// `RiscvRetireStreamService.build` produced — ordered, one entry per
  /// observed retirement. Indices in the result are indices into it.
  List<RiscvConsistencyViolation> check(
    List<RiscvRetiredInstruction> retires, {
    RiscvConsistencyCheckOptions options = const RiscvConsistencyCheckOptions(),
  }) {
    final out = <RiscvConsistencyViolation>[];
    for (final rule in RiscvCheckRule.values) {
      if (!options.isEnabled(rule)) continue;
      out.addAll(checkRule(rule, retires));
    }
    out.sort((a, b) {
      final byIndex = a.retireIndex.compareTo(b.retireIndex);
      if (byIndex != 0) return byIndex;
      return a.kind.index.compareTo(b.kind.index);
    });
    return List.unmodifiable(out);
  }

  /// Runs exactly one rule. Every rule is independently addressable so a
  /// corrupted fixture can assert *that rule and no other* fires.
  List<RiscvConsistencyViolation> checkRule(
    RiscvCheckRule rule,
    List<RiscvRetiredInstruction> retires,
  ) => switch (rule) {
    RiscvCheckRule.controlFlow => riscvCheckControlFlow(retires),
    RiscvCheckRule.x0Write => riscvCheckX0Write(retires),
    RiscvCheckRule.destinationRegister => riscvCheckDestinationRegister(
      retires,
    ),
    RiscvCheckRule.memoryAccess => riscvCheckMemoryAccess(retires),
    RiscvCheckRule.retireOrder => riscvCheckRetireOrder(retires),
    RiscvCheckRule.trapConsistency => riscvCheckTrapConsistency(retires),
  };
}

// ── rule 1 — control-flow continuity ─────────────────────────────────────────

/// `rvfi_pc_wdata` of retirement *n* must equal `rvfi_pc_rdata` of *n+1*.
///
/// The violation is anchored at *n+1* — the retirement that fetched from
/// somewhere its predecessor did not send it — because that is the row a user
/// wants the cursor on. The predecessor's claim is named in the message.
///
/// **`rvfi_intr` exempts the discontinuity, and must.** RVFI defines
/// `rvfi_intr` as marking "the first instruction that is part of a trap
/// handler, i.e. an instruction that has a `rvfi_pc_rdata` that does not
/// match the `rvfi_pc_wdata` of the previous instruction" — the mismatch is
/// the *definition*, not a defect, and riscv-formal's own
/// `checks/rvfi_pc_fwd_check.sv` guards its continuity assertion with
/// `if (expect_pc_valid && !rvfi_intr)` for exactly this reason. A core is
/// therefore free to report the sequential next PC on a trapping
/// instruction provided it flags the handler entry. This rule used to fire
/// there, and against a real Ibex trace those were false positives.
///
/// When `rvfi_intr` is unbound the discontinuity is unverifiable either way
/// and is still reported — the trace carries no evidence of handler entry,
/// and silently passing an unrunnable check is the one outcome this file
/// refuses (see the header).
List<RiscvConsistencyViolation> riscvCheckControlFlow(
  List<RiscvRetiredInstruction> retires,
) {
  final out = <RiscvConsistencyViolation>[];
  for (var i = 1; i < retires.length; i++) {
    final previous = retires[i - 1];
    final current = retires[i];
    final expected = previous.pcNext;
    final actual = current.pc;
    if (expected == null || actual == null) continue;
    if (expected == actual) continue;
    // Handler entry: RVFI sanctions the discontinuity that `rvfi_intr` marks.
    if (current.intr ?? false) continue;
    final expectedHex = _hex(expected);
    final actualHex = _hex(actual);
    final previousLabel = _retireLabel(previous);
    out.add(
      RiscvConsistencyViolation(
        kind: RiscvViolationKind.controlFlowDiscontinuity,
        severity: RiscvViolationSeverity.error,
        retireIndex: i,
        time: current.time,
        order: current.order,
        pc: current.pc,
        detail:
            'control-flow discontinuity: $previousLabel set '
            'rvfi_pc_wdata=$expectedHex, but this retirement fetched from '
            'rvfi_pc_rdata=$actualHex',
        args: [expectedHex, actualHex, previousLabel],
      ),
    );
  }
  return out;
}

// ── rule 2 — x0 is hardwired zero ────────────────────────────────────────────

/// `rd_addr == 0` with a non-zero `rd_wdata`.
///
/// RVFI reports "writes no register" as `rd_addr == 0`, and `x0` reads as
/// zero unconditionally, so a non-zero `rd_wdata` alongside it is a claim
/// about architectural state that cannot be true. It is also the single
/// cheapest sign that a core's write-back mux is picking up a stale value.
List<RiscvConsistencyViolation> riscvCheckX0Write(
  List<RiscvRetiredInstruction> retires,
) {
  final out = <RiscvConsistencyViolation>[];
  for (var i = 0; i < retires.length; i++) {
    final r = retires[i];
    final value = r.rdValue;
    if (r.rdAddr != 0 || value == null || value == 0) continue;
    final valueHex = _hex(value);
    out.add(
      RiscvConsistencyViolation(
        kind: RiscvViolationKind.x0NonZeroWrite,
        severity: RiscvViolationSeverity.error,
        retireIndex: i,
        time: r.time,
        order: r.order,
        pc: r.pc,
        detail:
            'rvfi_rd_addr=0 (x0) with rvfi_rd_wdata=$valueHex — x0 is '
            'hardwired zero, so a write to it can never take effect',
        args: [valueHex],
      ),
    );
  }
  return out;
}

// ── rule 3 — reported rd vs the encoding's rd ────────────────────────────────

/// `rvfi_rd_addr` must name the register the retired encoding names.
///
/// Skipped for encodings [riscvDecodedIntegerRd] declines (compressed forms,
/// floating point, unallocated space) and for **trapping** retirements: a
/// trapped instruction commits no register write, and RVFI convention is to
/// report `rd_addr == 0` for it, which is not a disagreement with the
/// encoding but the correct description of what happened.
List<RiscvConsistencyViolation> riscvCheckDestinationRegister(
  List<RiscvRetiredInstruction> retires,
) {
  final out = <RiscvConsistencyViolation>[];
  for (var i = 0; i < retires.length; i++) {
    final r = retires[i];
    if (r.trap ?? false) continue;
    final insn = r.insnWord;
    final reported = r.rdAddr;
    if (insn == null || reported == null) continue;
    final encoded = riscvDecodedIntegerRd(insn);
    if (encoded == null || encoded == reported) continue;
    final encodedName = riscvRegisterNameWithIndex(encoded);
    final reportedName = riscvRegisterNameWithIndex(reported);
    final what = r.mnemonic ?? _hex(insn);
    out.add(
      RiscvConsistencyViolation(
        kind: RiscvViolationKind.destinationRegisterMismatch,
        severity: RiscvViolationSeverity.error,
        retireIndex: i,
        time: r.time,
        order: r.order,
        pc: r.pc,
        detail:
            'retired ${_hex(insn)} ($what) encodes rd=$encodedName, but '
            'rvfi_rd_addr reports $reportedName',
        args: [what, encodedName, reportedName],
      ),
    );
  }
  return out;
}

// ── rule 4 — memory masks vs the encoding ────────────────────────────────────

/// The RVFI memory channels must describe the access the encoding asks for.
///
/// Four distinct findings, because they have four distinct causes:
///
/// - **size mismatch** — the masks cover a different number of bytes than the
///   width in the encoding's `funct3`;
/// - **non-contiguous mask** — a hole in `rmask | wmask`, which no single
///   load or store can produce;
/// - **misaligned** — the effective address is not a multiple of the access
///   width. Legal in RISC-V but implementation-defined, so a *warning*: many
///   cores trap instead, and the ones that do not usually want to know;
/// - **missing / unexpected** — a load or store with no mask asserted, or a
///   non-memory encoding with one.
///
/// The effective address is `rvfi_mem_addr` plus the offset of the lowest set
/// mask bit, which makes the rule correct under both conventions found in the
/// wild: cores that report the exact access address with a mask starting at
/// bit 0, and cores that report the containing word address with the mask
/// shifted into place.
List<RiscvConsistencyViolation> riscvCheckMemoryAccess(
  List<RiscvRetiredInstruction> retires,
) {
  final out = <RiscvConsistencyViolation>[];
  for (var i = 0; i < retires.length; i++) {
    final r = retires[i];
    // A trapping access never completed; its masks describe nothing.
    if (r.trap ?? false) continue;
    final insn = r.insnWord;
    if (insn == null) continue;
    final access = riscvDecodedAccess(insn);
    if (access == null) continue;

    final effect = r.memory;
    final what = r.mnemonic ?? _hex(insn);

    if (access.kind == RiscvAccessKind.none) {
      if (effect == null) continue;
      final rmaskHex = _maskHex(effect.rmask);
      final wmaskHex = _maskHex(effect.wmask);
      out.add(
        RiscvConsistencyViolation(
          kind: RiscvViolationKind.memoryAccessUnexpected,
          severity: RiscvViolationSeverity.error,
          retireIndex: i,
          time: r.time,
          order: r.order,
          pc: r.pc,
          detail:
              '$what performs no memory access, but the trace reports '
              'rvfi_mem_rmask=$rmaskHex rvfi_mem_wmask=$wmaskHex',
          args: [what, rmaskHex, wmaskHex],
        ),
      );
      continue;
    }

    if (effect == null) {
      out.add(
        RiscvConsistencyViolation(
          kind: RiscvViolationKind.memoryAccessMissing,
          severity: RiscvViolationSeverity.error,
          retireIndex: i,
          time: r.time,
          order: r.order,
          pc: r.pc,
          detail:
              '$what performs a ${access.sizeBytes}-byte '
              '${access.kind == RiscvAccessKind.load ? 'load' : 'store'}, '
              'but no rvfi_mem_rmask / rvfi_mem_wmask bit is asserted',
          args: [what, '${access.sizeBytes}'],
        ),
      );
      continue;
    }

    final mask = effect.rmask | effect.wmask;
    if (!riscvMaskIsContiguous(mask)) {
      final maskHex = _maskHex(mask);
      out.add(
        RiscvConsistencyViolation(
          kind: RiscvViolationKind.memoryMaskNotContiguous,
          severity: RiscvViolationSeverity.error,
          retireIndex: i,
          time: r.time,
          order: r.order,
          pc: r.pc,
          detail:
              'rvfi_mem_rmask | rvfi_mem_wmask = $maskHex is not a '
              'contiguous byte range, so it cannot describe one access',
          args: [maskHex],
        ),
      );
      continue;
    }

    final covered = riscvPopCount(mask);
    if (covered != access.sizeBytes) {
      out.add(
        RiscvConsistencyViolation(
          kind: RiscvViolationKind.memorySizeMismatch,
          severity: RiscvViolationSeverity.error,
          retireIndex: i,
          time: r.time,
          order: r.order,
          pc: r.pc,
          detail:
              '$what needs ${access.sizeBytes} bytes, but '
              'rvfi_mem_rmask | rvfi_mem_wmask = ${_maskHex(mask)} covers '
              '$covered',
          args: [what, '${access.sizeBytes}', '$covered'],
        ),
      );
      continue;
    }

    final effectiveAddress = effect.address + riscvLowestSetBit(mask);
    if (access.sizeBytes > 1 && effectiveAddress % access.sizeBytes != 0) {
      final addressHex = _hex(effectiveAddress);
      out.add(
        RiscvConsistencyViolation(
          kind: RiscvViolationKind.memoryMisaligned,
          severity: RiscvViolationSeverity.warning,
          retireIndex: i,
          time: r.time,
          order: r.order,
          pc: r.pc,
          detail:
              'a ${access.sizeBytes}-byte access at $addressHex is not '
              'naturally aligned — legal only if the core implements '
              'misaligned accesses rather than trapping them',
          args: ['${access.sizeBytes}', addressHex],
        ),
      );
    }
  }
  return out;
}

// ── rule 5 — rvfi_order continuity ───────────────────────────────────────────

/// `rvfi_order` must advance by exactly one per retirement.
///
/// A gap means retirements happened that the trace does not carry — usually a
/// dump filter or a `valid` strobe that is narrower than the retirement. A
/// regression (or a repeat) means the stream is not a stream at all, which
/// invalidates every fold built on it, including the architectural state.
List<RiscvConsistencyViolation> riscvCheckRetireOrder(
  List<RiscvRetiredInstruction> retires,
) {
  final out = <RiscvConsistencyViolation>[];
  for (var i = 1; i < retires.length; i++) {
    final previous = retires[i - 1].order;
    final current = retires[i].order;
    if (previous == null || current == null) continue;
    if (current == previous + 1) continue;

    final r = retires[i];
    if (current <= previous) {
      out.add(
        RiscvConsistencyViolation(
          kind: RiscvViolationKind.orderRegression,
          severity: RiscvViolationSeverity.error,
          retireIndex: i,
          time: r.time,
          order: current,
          pc: r.pc,
          detail:
              'rvfi_order went from $previous to $current — the retirement '
              'counter must increase by exactly one per retirement',
          args: ['$previous', '$current'],
        ),
      );
      continue;
    }
    final missing = current - previous - 1;
    out.add(
      RiscvConsistencyViolation(
        kind: RiscvViolationKind.orderGap,
        severity: RiscvViolationSeverity.error,
        retireIndex: i,
        time: r.time,
        order: current,
        pc: r.pc,
        detail:
            'rvfi_order jumped from $previous to $current — $missing '
            'retirement(s) are missing from the trace',
        args: ['$previous', '$current', '$missing'],
      ),
    );
  }
  return out;
}

// ── rule 6 — a trap must look like a trap ────────────────────────────────────

/// A retirement with `rvfi_trap` must show the architectural effects of one.
///
/// Three independent conditions, each reported separately because each has a
/// different cause:
///
/// - `pc_wdata` is the sequential next PC (`pc + 4`, or `pc + 2` for a
///   compressed encoding) **and the following retirement does not assert
///   `rvfi_intr`**, so the core neither redirected to a trap vector nor
///   flagged the handler entry that would license reporting the sequential
///   PC. Reporting `pc + 4` is legal on its own — see [riscvCheckControlFlow]
///   for the spec text and the riscv-formal check that says so;
/// - the following retirement does not assert `rvfi_intr`, so the trace does
///   not show the handler being entered (checked only when `rvfi_intr` is
///   bound and there *is* a following retirement);
/// - the following retirement runs at a **lower** privilege than the trapping
///   one. Traps are delivered to the same or a higher privilege level; only
///   an explicit `*ret` drops privilege, and that is not a trap.
List<RiscvConsistencyViolation> riscvCheckTrapConsistency(
  List<RiscvRetiredInstruction> retires,
) {
  final out = <RiscvConsistencyViolation>[];
  for (var i = 0; i < retires.length; i++) {
    final r = retires[i];
    if (!(r.trap ?? false)) continue;
    final pc = r.pc;
    final pcNext = r.pcNext;
    final next = i + 1 < retires.length ? retires[i + 1] : null;

    // A trapping retirement may report the sequential next PC provided the
    // successor asserts `rvfi_intr`; that pairing is what RVFI defines as
    // handler entry. Only the unflagged case is a violation.
    final handlerEntryFlagged = next?.intr ?? false;

    if (pc != null && pcNext != null && !handlerEntryFlagged) {
      final insn = r.insnWord;
      // Compressed encodings advance by 2, everything else by 4. When the
      // word is unavailable, assume 4 — the base-ISA case.
      final step = (insn != null && !riscvIsUncompressed(insn)) ? 2 : 4;
      if (pcNext == pc + step) {
        final pcHex = _hex(pc);
        final pcNextHex = _hex(pcNext);
        out.add(
          RiscvConsistencyViolation(
            kind: RiscvViolationKind.trapNoRedirect,
            severity: RiscvViolationSeverity.error,
            retireIndex: i,
            time: r.time,
            order: r.order,
            pc: pc,
            detail:
                'rvfi_trap is set at $pcHex, but rvfi_pc_wdata=$pcNextHex is '
                'just the sequential next PC — the core did not redirect to '
                'a trap vector',
            args: [pcHex, pcNextHex],
          ),
        );
      }
    }

    if (next != null && next.intr != null && !next.intr!) {
      final pcNextHex = pcNext == null ? '?' : _hex(pcNext);
      out.add(
        RiscvConsistencyViolation(
          kind: RiscvViolationKind.trapNoHandlerEntry,
          severity: RiscvViolationSeverity.error,
          retireIndex: i,
          time: r.time,
          order: r.order,
          pc: pc,
          detail:
              'rvfi_trap is set and rvfi_pc_wdata=$pcNextHex, but the next '
              'retirement does not assert rvfi_intr — the trace never shows '
              'the handler being entered',
          args: [pcNextHex],
        ),
      );
    }

    final mode = r.mode;
    final nextMode = next?.mode;
    if (mode != null && nextMode != null && nextMode < mode) {
      final from = riscvPrivilegeModeName(mode);
      final to = riscvPrivilegeModeName(nextMode);
      out.add(
        RiscvConsistencyViolation(
          kind: RiscvViolationKind.trapPrivilegeDrop,
          severity: RiscvViolationSeverity.error,
          retireIndex: i,
          time: r.time,
          order: r.order,
          pc: pc,
          detail:
              'rvfi_trap taken at privilege $from, but the next retirement '
              'runs at $to — a trap is never delivered to a lower privilege',
          args: [from, to],
        ),
      );
    }
  }
  return out;
}

// ── shared formatting ────────────────────────────────────────────────────────

/// `rvfi_mode` as its architectural letter (`M`, `S`, `U`), or the raw value
/// for the reserved encoding.
String riscvPrivilegeModeName(int mode) => switch (mode) {
  0 => 'U',
  1 => 'S',
  3 => 'M',
  _ => 'mode $mode',
};

/// `0x8000_0004` — grouped hex, which is how a core designer reads an
/// address. Widths below 32 bits are padded to 8 nibbles so a column of them
/// lines up.
String riscvHexWord(int value) => _hex(value);

String _hex(int value) {
  final raw = value.toUnsigned(64).toRadixString(16).padLeft(8, '0');
  final buffer = StringBuffer('0x');
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 4 == 0) buffer.write('_');
    buffer.write(raw[i]);
  }
  return buffer.toString();
}

String _maskHex(int mask) => '0x${mask.toRadixString(16)}';

String _retireLabel(RiscvRetiredInstruction r) {
  final order = r.order;
  if (order != null) return 'retirement #$order';
  return 'the retirement at t=${r.time}';
}
