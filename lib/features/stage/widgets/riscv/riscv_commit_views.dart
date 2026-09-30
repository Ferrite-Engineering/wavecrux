// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/features/stage/providers/riscv_commit_landing_provider.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_messages.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_view_data.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/riscv/riscv_consistency_checker.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';

/// Minimum height of anything tappable in the Commit Inspector.
///
/// The widget is a dense engineering table, but a table row that moves the
/// cursor is a touch target and the app's mobile standard (ARCHITECTURE
/// §3.1.8) applies to it like any other.
const double kRiscvCommitTouchTarget = 44;

/// Monospace type for hex, disassembly and register names — the only way a
/// column of addresses stays readable.
TextStyle? _mono(BuildContext context, {Color? color, FontWeight? weight}) =>
    Theme.of(context).textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      color: color,
      fontWeight: weight,
    );

/// A centred, wrapped message — every empty and degraded state.
class RiscvCommitNotice extends StatelessWidget {
  const RiscvCommitNotice({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

// ── cross-probe landing ──────────────────────────────────────────────────────

/// Caption for an inbound CXP stream coordinate that moved the cursor
/// into this trace — *"insn_sub_ch0 · step 7 of 20 · rv32i"*.
///
/// **This banner is the only surface in WaveCrux that repeats a peer's claims
/// about a proof**, which is why it carries the provenance obligation. When
/// the sender marked the coordinate `riscv.mode = demo` the evidence came
/// from a replayed committed fixture rather than a solver run, and
/// [RiscvCommitLanding.isReplayedFixture] puts that on screen next to the
/// claim. Suppressing the label — or reporting the check and the step without
/// it — would let a screenshot of a rehearsed demo read as a measured result,
/// which is the failure this whole hand-off is built to refuse.
///
/// Everything shown here is **advisory**
/// (https://edacrux.app/cxp#sec-9-9, rule 2): none of it was
/// needed to resolve the coordinate, and a landing with no attributes at all
/// still renders its step.
class RiscvCommitLandingBanner extends StatelessWidget {
  const RiscvCommitLandingBanner({
    required this.landing,
    required this.onDismiss,
    super.key,
  });

  /// Where the coordinate landed, and what the sender said about it.
  final RiscvCommitLanding landing;

  /// Hides the banner. The cursor stays where the landing put it.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final depth = landing.depthConfigured;
    // The producer's own tokens — the riscv-formal check name, the group, the
    // ISA string — are reported verbatim and are deliberately not localized,
    // exactly like the `rvfi_*` port names and the hex values.
    final parts = <String>[
      ?landing.check,
      ?landing.group,
      if (landing.isFormalStep)
        if (depth == null)
          l10n.riscvCommitLandingStep(landing.sequenceIndex)
        else
          l10n.riscvCommitLandingStepOf(landing.sequenceIndex, depth),
      if (landing.order != null)
        l10n.riscvCommitLandingOrder(landing.order!)
      else if (!landing.isFormalStep)
        l10n.riscvCommitLandingOrder(landing.sequenceIndex),
      ?landing.isa,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      color: theme.colorScheme.primary.withValues(alpha: 0.08),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.my_location_outlined,
            size: 14,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.riscvCommitLandingTitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (parts.isNotEmpty)
                  Text(
                    parts.join('  ·  '),
                    style: _mono(context, color: theme.colorScheme.onSurface),
                  ),
                // The addressed step exists but nothing retired there. Said
                // plainly, because the sender asked for an instruction.
                if (!landing.selectedRetirement)
                  Text(
                    l10n.riscvCommitLandingNoRetirement,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                // Why this panel is here at all. The cross-probe mounted it —
                // the user did not — and a panel that appears unbidden with no
                // explanation is worse than no panel. Only shown when the
                // hand-off actually did the mounting; an inspector the user
                // already had open has nothing to account for.
                if (landing.autoMounted)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.dashboard_customize_outlined,
                          size: 13,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            l10n.riscvCommitLandingAutoMounted,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (landing.isReplayedFixture)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.history_outlined,
                          size: 13,
                          color: theme.colorScheme.tertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            l10n.riscvCommitLandingReplayed,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.tertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: l10n.riscvCommitLandingDismiss,
            onPressed: onDismiss,
            constraints: const BoxConstraints(
              minWidth: kRiscvCommitTouchTarget,
              minHeight: kRiscvCommitTouchTarget,
            ),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

// ── commits ──────────────────────────────────────────────────────────────────

/// How many post-frame passes [_RiscvCommitLogViewState._revealLandedRow] will
/// take before it stops chasing the end of the list.
///
/// `ListView.builder` *estimates* `maxScrollExtent` from the children it has
/// actually laid out, so on a long log one jump can land short of the true
/// end; each jump lays out more rows and sharpens the estimate. Bounded
/// because a converging loop that cannot terminate is not a loop worth having.
const int _kLandingScrollPasses = 5;

/// The retired-instruction log: order, PC, disassembly, and the real
/// architectural effect — `a0 = 0x0000_1004`, `[0x0000_1000] ← 0x0000_000c`.
///
/// **Stateful for one reason: it scrolls the landed retirement into view.** A
/// CXP stream-coordinate cross-probe lands the cursor on the retirement a proof failed at,
/// and the whole promise of the hand-off is that the user *sees* that row. A
/// panel showing four rows of a six-row log delivers a tinted current row that
/// exists and is off the fold — the user's first act is then to hunt for it,
/// which is precisely the work the hand-off was supposed to do. The panel is
/// also legitimately small sometimes (the user's own layout, a phone, a
/// session file), so sizing alone cannot be the answer: the row has to be
/// brought to them.
class RiscvCommitLogView extends StatefulWidget {
  const RiscvCommitLogView({
    required this.data,
    required this.onSeek,
    this.landingToken,
    super.key,
  });

  final RiscvCommitViewData data;

  /// Moves the primary cursor to a simulation tick.
  final void Function(int time) onSeek;

  /// [RiscvCommitLanding.token] of the cross-probe landing currently
  /// captioning this inspector, or null when no landing is showing.
  ///
  /// The token — not the landing itself — because the token is exactly the
  /// "this is a *new* landing" signal: a repeat cross-probe onto the same
  /// element bumps it, and ordinary cursor scrubbing does not. Scrolling on
  /// every rebuild would fight the user's own scrolling on every seek.
  final int? landingToken;

  @override
  State<RiscvCommitLogView> createState() => _RiscvCommitLogViewState();
}

class _RiscvCommitLogViewState extends State<RiscvCommitLogView> {
  final ScrollController _controller = ScrollController();

  /// The last landing token this view has already scrolled for.
  int? _scrolledToken;

  @override
  void initState() {
    super.initState();
    // Not only `didUpdateWidget`: the auto-mount records the landing *before*
    // it creates the panel, so the inspector's very first build already
    // carries the token and there is no change to react to. That is the exact
    // path the SimCrux hand-off takes.
    _scheduleLandingScroll();
  }

  @override
  void didUpdateWidget(RiscvCommitLogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.landingToken != oldWidget.landingToken) _scheduleLandingScroll();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scheduleLandingScroll() {
    final token = widget.landingToken;
    if (token == null || token == _scrolledToken) return;
    _scrolledToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealLandedRow());
  }

  /// Brings the landed retirement — the tinted *current* row — into the
  /// viewport.
  ///
  /// The landed row is the **last** row of [RiscvCommitViewData.retiredSoFar]
  /// by construction: the list is every retirement at or before the cursor,
  /// and the landing is what put the cursor there. So the end of the scroll
  /// extent *is* the landed row, which is also the only target that stays
  /// exact for rows of unequal height (a violation renders inline and makes
  /// its row taller).
  ///
  /// Deliberately a jump rather than an animation: on the auto-mount path the
  /// panel did not exist a frame ago, so there is no scroll position to
  /// animate away from, and a jump behaves identically under every test
  /// harness.
  void _revealLandedRow([int pass = 0]) {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    if (!position.hasContentDimensions) return;
    final target = position.maxScrollExtent;
    // Both quiet cases, and neither may produce a visible twitch: a log
    // shorter than its viewport has a zero extent, and a landing on the first
    // retirement (the only one at or before the cursor) is already on screen.
    if (target <= position.pixels) return;
    _controller.jumpTo(target);
    if (pass >= _kLandingScrollPasses) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _revealLandedRow(pass + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final data = widget.data;
    final rows = data.retiredSoFar;
    if (rows.isEmpty) {
      return RiscvCommitNotice(message: l10n.riscvCommitLogEmpty);
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  l10n.riscvCommitColumnOrder,
                  style: theme.textTheme.labelSmall,
                ),
              ),
              SizedBox(
                width: 96,
                child: Text(
                  l10n.riscvCommitColumnPc,
                  style: theme.textTheme.labelSmall,
                ),
              ),
              Expanded(
                child: Text(
                  l10n.riscvCommitColumnInstruction,
                  style: theme.textTheme.labelSmall,
                ),
              ),
              Expanded(
                child: Text(
                  l10n.riscvCommitColumnEffect,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: _controller,
            itemCount: rows.length,
            itemBuilder: (context, i) => _CommitRow(
              retire: rows[i],
              violations: data.violationsAt(i),
              data: data,
              isCurrent: i == rows.length - 1,
              onSeek: widget.onSeek,
            ),
          ),
        ),
      ],
    );
  }
}

class _CommitRow extends StatelessWidget {
  const _CommitRow({
    required this.retire,
    required this.violations,
    required this.data,
    required this.isCurrent,
    required this.onSeek,
  });

  final RiscvRetiredInstruction retire;
  final List<RiscvConsistencyViolation> violations;
  final RiscvCommitViewData data;
  final bool isCurrent;
  final void Function(int time) onSeek;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final worst = violations.isEmpty
        ? null
        : violations.any((v) => v.severity == RiscvViolationSeverity.error)
        ? RiscvViolationSeverity.error
        : RiscvViolationSeverity.warning;

    return InkWell(
      onTap: () => onSeek(retire.time),
      child: Container(
        constraints: const BoxConstraints(minHeight: kRiscvCommitTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: isCurrent
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    retire.order?.toString() ?? '—',
                    style: _mono(
                      context,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    retire.pc == null ? '—' : riscvHexWord(retire.pc!),
                    style: _mono(context),
                  ),
                ),
                Expanded(
                  child: Text(
                    retire.disassembly ?? l10n.riscvCommitNoDisassembly,
                    style: _mono(
                      context,
                      color: retire.disassembly == null
                          ? theme.colorScheme.onSurfaceVariant
                          : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Text(
                    _effectText(l10n, retire, data),
                    style: _mono(context),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            // Violations render **inline**, on the retirement they belong to,
            // rather than only in a separate report — the whole value of the
            // checker is seeing the bad row in context.
            for (final v in violations)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      worst == RiscvViolationSeverity.error
                          ? Icons.error_outline
                          : Icons.warning_amber_outlined,
                      size: 14,
                      color: v.severity == RiscvViolationSeverity.error
                          ? theme.colorScheme.error
                          : theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Tooltip(
                        message: v.detail,
                        child: Text(
                          riscvViolationMessage(l10n, v),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: v.severity == RiscvViolationSeverity.error
                                ? theme.colorScheme.error
                                : theme.colorScheme.tertiary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `t0 = 0x0000_0005   [0x0000_1000] ← 0x0000_000c` — the real architectural
/// effect, from the values the core reported, not from inference.
String _effectText(
  L10N l10n,
  RiscvRetiredInstruction r,
  RiscvCommitViewData data,
) {
  final parts = <String>[];
  final rd = r.rdAddr;
  final value = r.rdValue;
  if (rd != null && rd != 0 && value != null) {
    parts.add('${data.registerLabel(rd)} = ${riscvHexWord(value)}');
  }
  final memory = r.memory;
  if (memory != null) {
    final address = riscvHexWord(memory.address);
    if (memory.isWrite && memory.wdata != null) {
      parts.add('[$address] ← ${riscvHexWord(memory.wdata!)}');
    } else if (memory.isRead && memory.rdata != null) {
      parts.add('[$address] → ${riscvHexWord(memory.rdata!)}');
    } else {
      parts.add('[$address]');
    }
  }
  if (r.trap ?? false) parts.add(l10n.riscvCommitTrapLabel);
  if (r.halt ?? false) parts.add(l10n.riscvCommitHaltLabel);
  return parts.isEmpty ? '—' : parts.join('   ');
}

// ── registers ────────────────────────────────────────────────────────────────

/// The reconstructed architectural register file at the cursor.
///
/// Correct by construction: every value here was *reported by the core as
/// retired*, not inferred from physical register-file port activity. A
/// register the replay never saw written reads `—`, not `0` — "unknown" and
/// "zero" are different statements and the widget refuses to conflate them.
class RiscvCommitRegistersView extends StatelessWidget {
  const RiscvCommitRegistersView({required this.data, super.key});

  final RiscvCommitViewData data;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    if (!data.report.found.contains(RvfiChannel.rdAddr) ||
        !data.report.found.contains(RvfiChannel.rdWdata)) {
      return RiscvCommitNotice(message: l10n.riscvCommitRegistersUnavailable);
    }
    final state = data.state;
    if (state.registers.isEmpty && state.pc == null) {
      return RiscvCommitNotice(message: l10n.riscvCommitRegistersEmpty);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      children: [
        if (state.pc != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Text(
                  l10n.riscvCommitPcLabel,
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(width: 8),
                Text(
                  riscvHexWord(state.pc!),
                  style: _mono(context, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
        Text(
          l10n.riscvCommitRegistersHeader(
            state.registers.length,
            data.registerCount,
          ),
          style: theme.textTheme.labelSmall,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 2,
          children: [
            for (var i = 0; i < data.registerCount; i++)
              _RegisterCell(index: i, data: data),
          ],
        ),
      ],
    );
  }
}

class _RegisterCell extends StatelessWidget {
  const _RegisterCell({required this.index, required this.data});

  final int index;
  final RiscvCommitViewData data;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    // x0 is architecturally zero at all times; every other register is
    // unknown until the replay observes a write to it.
    final value = index == 0 ? 0 : data.state.registers[index]?.value;
    final unknown = value == null;
    final row = Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            data.registerLabel(index),
            style: _mono(context, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            unknown ? '—' : riscvHexWord(value),
            style: _mono(
              context,
              color: unknown ? theme.colorScheme.onSurfaceVariant : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    return SizedBox(
      width: 150,
      // Only the unknown cells need explaining — the difference between "the
      // core never wrote this" and "the core wrote zero" is the whole point
      // of the em-dash. A written cell speaks for itself, and a tooltip on
      // all 32 would be noise.
      child: unknown
          ? Tooltip(message: l10n.riscvCommitRegisterUnwritten, child: row)
          : row,
    );
  }
}

// ── memory ───────────────────────────────────────────────────────────────────

/// The memory access log — every access the core reported, up to the cursor.
class RiscvCommitMemoryView extends StatelessWidget {
  const RiscvCommitMemoryView({
    required this.data,
    required this.onSeek,
    super.key,
  });

  final RiscvCommitViewData data;
  final void Function(int time) onSeek;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    if (!data.report.found.contains(RvfiChannel.memAddr)) {
      return RiscvCommitNotice(message: l10n.riscvCommitMemoryUnavailable);
    }
    final effects = data.state.memoryEffects;
    if (effects.isEmpty) {
      return RiscvCommitNotice(message: l10n.riscvCommitMemoryEmpty);
    }
    return ListView.builder(
      itemCount: effects.length,
      itemBuilder: (context, i) {
        // Newest first — the access you just scrubbed past is the one you
        // are looking for.
        final e = effects[effects.length - 1 - i];
        return _MemoryRow(effect: e, onSeek: onSeek);
      },
    );
  }
}

class _MemoryRow extends StatelessWidget {
  const _MemoryRow({required this.effect, required this.onSeek});

  final RiscvMemoryEffect effect;
  final void Function(int time) onSeek;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final kind = effect.isRead && effect.isWrite
        ? l10n.riscvCommitMemoryReadWrite
        : effect.isWrite
        ? l10n.riscvCommitMemoryWrite
        : l10n.riscvCommitMemoryRead;
    final value = effect.isWrite ? effect.wdata : effect.rdata;
    return InkWell(
      onTap: () => onSeek(effect.time),
      child: Container(
        constraints: const BoxConstraints(minHeight: kRiscvCommitTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                effect.order?.toString() ?? '—',
                style: _mono(
                  context,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(kind, style: theme.textTheme.labelSmall),
            ),
            SizedBox(
              width: 104,
              child: Text(riscvHexWord(effect.address), style: _mono(context)),
            ),
            Expanded(
              child: Text(
                value == null ? '—' : riscvHexWord(value),
                style: _mono(context),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              l10n.riscvCommitMemoryBytes(effect.byteCount),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── traps ────────────────────────────────────────────────────────────────────

/// The trap / exception log — traps taken, handler entries, and the halt.
class RiscvCommitTrapsView extends StatelessWidget {
  const RiscvCommitTrapsView({
    required this.data,
    required this.onSeek,
    super.key,
  });

  final RiscvCommitViewData data;
  final void Function(int time) onSeek;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final found = data.report.found;
    if (!found.contains(RvfiChannel.trap) &&
        !found.contains(RvfiChannel.intr) &&
        !found.contains(RvfiChannel.halt)) {
      return RiscvCommitNotice(message: l10n.riscvCommitTrapsUnavailable);
    }
    final rows = [
      for (final r in data.retiredSoFar)
        if ((r.trap ?? false) || (r.intr ?? false) || (r.halt ?? false)) r,
    ];
    if (rows.isEmpty) {
      return RiscvCommitNotice(message: l10n.riscvCommitTrapsEmpty);
    }
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) => _TrapRow(retire: rows[i], onSeek: onSeek),
    );
  }
}

class _TrapRow extends StatelessWidget {
  const _TrapRow({required this.retire, required this.onSeek});

  final RiscvRetiredInstruction retire;
  final void Function(int time) onSeek;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final kinds = <String>[
      if (retire.trap ?? false) l10n.riscvCommitTrapLabel,
      if (retire.intr ?? false) l10n.riscvCommitIntrLabel,
      if (retire.halt ?? false) l10n.riscvCommitHaltLabel,
    ];
    final mode = retire.mode;
    return InkWell(
      onTap: () => onSeek(retire.time),
      child: Container(
        constraints: const BoxConstraints(minHeight: kRiscvCommitTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                retire.order?.toString() ?? '—',
                style: _mono(
                  context,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            SizedBox(
              width: 104,
              child: Text(
                retire.pc == null ? '—' : riscvHexWord(retire.pc!),
                style: _mono(context),
              ),
            ),
            Expanded(
              child: Text(
                kinds.join(', '),
                style: theme.textTheme.labelSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (mode != null)
              Text(
                l10n.riscvCommitPrivilegeLabel(riscvPrivilegeModeName(mode)),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── checks ───────────────────────────────────────────────────────────────────

/// The consistency checker's report.
///
/// Two things this view does that a naive one would not. It lists violations
/// **across the whole trace**, not up to the cursor, because the workflow is
/// "find the bad retirement, then go to it". And it names the rules that
/// **did not run** for lack of bound channels — a quiet result from a check
/// that never executed is the one way this widget could mislead someone.
class RiscvCommitChecksView extends StatelessWidget {
  const RiscvCommitChecksView({
    required this.data,
    required this.onSeek,
    super.key,
  });

  final RiscvCommitViewData data;
  final void Function(int time) onSeek;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final skipped = data.checkOptions.skippedRules;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.violations.isEmpty
                    ? l10n.riscvCommitChecksClean(data.retires.length)
                    : l10n.riscvCommitChecksSummary(
                        data.errorCount,
                        data.warningCount,
                        data.retires.length,
                      ),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: data.errorCount > 0 ? theme.colorScheme.error : null,
                ),
              ),
              if (skipped.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l10n.riscvCommitChecksSkipped(
                      [for (final r in skipped) riscvRuleName(l10n, r)].join(
                        ', ',
                      ),
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (data.violations.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l10n.riscvCommitChecksJumpHint,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: data.violations.length,
            itemBuilder: (context, i) =>
                _ViolationRow(violation: data.violations[i], onSeek: onSeek),
          ),
        ),
      ],
    );
  }
}

class _ViolationRow extends StatelessWidget {
  const _ViolationRow({required this.violation, required this.onSeek});

  final RiscvConsistencyViolation violation;
  final void Function(int time) onSeek;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final isError = violation.severity == RiscvViolationSeverity.error;
    final color = isError
        ? theme.colorScheme.error
        : theme.colorScheme.tertiary;
    return InkWell(
      // Clicking a violation moves the cursor to the offending retirement.
      onTap: () => onSeek(violation.time),
      child: Container(
        constraints: const BoxConstraints(minHeight: kRiscvCommitTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.warning_amber_outlined,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        riscvRuleName(l10n, violation.rule),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        riscvSeverityLabel(l10n, violation.severity),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (violation.pc != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          riscvHexWord(violation.pc!),
                          style: _mono(
                            context,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Tooltip(
                    message: violation.detail,
                    child: Text(
                      riscvViolationMessage(l10n, violation),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
