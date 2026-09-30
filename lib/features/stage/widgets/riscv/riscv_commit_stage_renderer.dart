// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/stage/providers/riscv_commit_landing_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_messages.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_view_data.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_views.dart';
import 'package:wavecrux/features/stage/widgets/stage_resizable_body.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/translator_registry.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/riscv/riscv_arch_state.dart';
import 'package:wavecrux/services/riscv/riscv_arch_state_service.dart';
import 'package:wavecrux/services/riscv/riscv_consistency_checker.dart';
import 'package:wavecrux/services/riscv/riscv_retire_stream_service.dart';
import 'package:wavecrux/services/riscv/riscv_retired_instruction.dart';
import 'package:wavecrux/services/riscv/rvfi_binding_set.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';

/// Which of the Commit Inspector's five views is showing.
enum RiscvCommitView {
  /// Retired-instruction log with real operand values.
  commits,

  /// Reconstructed architectural register file at the cursor.
  registers,

  /// Memory access log.
  memory,

  /// Trap / handler-entry / halt log.
  traps,

  /// Consistency checker report.
  checks,
}

/// Renders a [RiscvCommitStageWidget] instance.
///
/// **The lazy-load trap, first, because it is the one that silently breaks
/// this widget.** `WaveformDataSource.valueAt` returns `null` both for "this
/// signal is not loaded" and for "this signal has no value yet", and a Stage
/// binding can name a signal the user never added to the viewer. So every
/// bound pin is watched through `stageBoundSignalProvider` — purely for its
/// lazy-load side effect — **before** the substrate is allowed to walk the
/// source. Across ~20 RVFI channels, skipping that produces an empty
/// inspector on a perfectly good trace, which looks like a broken tool
/// rather than a missing `await`. See ARCHITECTURE §6.6.
///
/// **What is computed where.** The retire stream and the consistency checker
/// run over the **whole trace** and are memoized against
/// `(source, bindings, disassembler)`, so scrubbing the cursor does not
/// re-walk the trace. The architectural state is a **fold to the cursor** and
/// is recomputed every build, under the same stateless
/// rebuild-on-backward-seek contract as the Pro register-file snapshot
/// service: a cached incremental fold is only correct forwards, and the
/// cursor is a scrub bar.
class RiscvCommitStageRenderer extends ConsumerStatefulWidget {
  const RiscvCommitStageRenderer({required this.instance, super.key});

  final StageInstance instance;

  @override
  ConsumerState<RiscvCommitStageRenderer> createState() =>
      _RiscvCommitStageRendererState();
}

class _RiscvCommitStageRendererState
    extends ConsumerState<RiscvCommitStageRenderer> {
  RiscvCommitView _view = RiscvCommitView.commits;
  _TraceAnalysis? _analysis;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);

    // ── the lazy-load watch. Unconditional, and before anything else. ────────
    final refs = <RvfiChannel, String>{};
    var loading = false;
    for (final channel in RvfiChannel.values) {
      final binding = widget.instance.signalBindings[channel.signalName];
      final snapshot = ref.watch(stageBoundSignalProvider(binding));
      if (binding == null || binding.signalRef.isEmpty) continue;
      refs[channel] = binding.signalRef;
      if (snapshot.kind == StageSignalSnapshotKind.loading) loading = true;
    }

    final source = ref.watch(waveformSourceProvider).value;
    final cursorState = ref.watch(cursorStateProvider);
    final disassembler = ref.watch(riscvDisassemblerProvider).asData?.value;
    // Where an inbound CXP stream coordinate put the cursor, if one did. Per-tab
    // and self-clearing on a source change, so it never captions a trace it
    // was not measured in.
    final landing = ref.watch(riscvCommitLandingProvider);

    if (refs.isEmpty) {
      return RiscvCommitNotice(message: l10n.riscvCommitUnbound);
    }
    if (source == null) {
      return RiscvCommitNotice(message: l10n.riscvCommitNoFile);
    }
    if (loading) {
      return RiscvCommitNotice(message: l10n.riscvCommitLoading);
    }

    // A bit-sliced binding is meaningless for an RVFI channel — the whole
    // port is the value — so the binding's `bitIndex` is deliberately not
    // consulted here.
    final bindings = RvfiBindingSet(
      refs: {
        for (final entry in refs.entries) entry.key: {0: entry.value},
      },
      channelCount: 1,
    );
    final report = RvfiCompletenessReport.forBindings(bindings);

    if (!report.isUsable) {
      return RiscvCommitNotice(
        message: l10n.riscvCommitMissingRequired(
          riscvChannelList(report.missing.where((c) => c.isRequired)),
        ),
      );
    }

    final analysis = _analyse(source, bindings, disassembler);
    if (analysis.retires.isEmpty) {
      return _Frame(
        report: report,
        view: _view,
        onViewChanged: _select,
        landing: landing,
        onDismissLanding: _dismissLanding,
        child: RiscvCommitNotice(message: l10n.riscvCommitNoRetirements),
      );
    }

    final config = widget.instance.configuration;
    final registerCount =
        (config[RiscvCommitStageWidget.paramRegisterCount] as int?) ?? 32;
    final memoryDepth =
        (config[RiscvCommitStageWidget.paramMemoryLogDepth] as int?) ?? 32;
    final cursorTime = cursorState.primaryCursorTime ?? source.startTime;

    final data = RiscvCommitViewData(
      retires: analysis.retires,
      violations: analysis.violations,
      checkOptions: analysis.checkOptions,
      state: RiscvArchStateService.withDisassembler(null).buildFromRetires(
        retires: analysis.retires,
        cursorTime: cursorTime,
        config: RiscvArchStateConfig(
          registerCount: registerCount,
          memoryEffectDepth: memoryDepth,
        ),
      ),
      report: report,
      cursorTime: cursorTime,
      naming: RiscvCommitRegisterNaming.parse(
        config[RiscvCommitStageWidget.paramRegisterNaming],
      ),
      registerCount: registerCount,
    );

    return _Frame(
      report: report,
      view: _view,
      onViewChanged: _select,
      errorCount: data.errorCount,
      landing: landing,
      onDismissLanding: _dismissLanding,
      child: switch (_view) {
        // The landing token, so the log can scroll the landed retirement into
        // view. A tinted row below the fold is a row the user has to go and
        // find, which is the errand the hand-off exists to save them.
        RiscvCommitView.commits => RiscvCommitLogView(
          data: data,
          onSeek: _seek,
          landingToken: landing?.token,
        ),
        RiscvCommitView.registers => RiscvCommitRegistersView(data: data),
        RiscvCommitView.memory => RiscvCommitMemoryView(
          data: data,
          onSeek: _seek,
        ),
        RiscvCommitView.traps => RiscvCommitTrapsView(
          data: data,
          onSeek: _seek,
        ),
        RiscvCommitView.checks => RiscvCommitChecksView(
          data: data,
          onSeek: _seek,
        ),
      },
    );
  }

  void _select(RiscvCommitView view) => setState(() => _view = view);

  /// Moves the primary cursor to [time] — what a click on a violation, a
  /// commit row, a memory access or a trap does.
  void _seek(int time) =>
      ref.read(cursorStateProvider.notifier).placePrimary(time);

  /// Hides the cross-probe landing caption. The cursor stays where the
  /// landing put it — dismissing the banner is not an undo.
  void _dismissLanding() =>
      ref.read(riscvCommitLandingProvider.notifier).clear();

  /// Rebuilds the whole-trace analysis when, and only when, its inputs
  /// change. Cursor motion is not one of its inputs.
  _TraceAnalysis _analyse(
    WaveformDataSource source,
    RvfiBindingSet bindings,
    InstructionDisassembler? disassembler,
  ) {
    final cached = _analysis;
    if (cached != null &&
        identical(cached.source, source) &&
        cached.bindings == bindings &&
        identical(cached.disassembler, disassembler)) {
      return cached;
    }
    final retires = RiscvRetireStreamService(disassembler).build(
      source: source,
      bindings: bindings,
      startTime: source.startTime,
      endTime: source.endTime,
    );
    final options = RiscvConsistencyCheckOptions.forBindings(bindings);
    final analysis = _TraceAnalysis(
      source: source,
      bindings: bindings,
      disassembler: disassembler,
      retires: retires,
      violations: const RiscvConsistencyChecker().check(
        retires,
        options: options,
      ),
      checkOptions: options,
    );
    _analysis = analysis;
    return analysis;
  }
}

/// Memoized whole-trace analysis, keyed by the three things that can change
/// it.
class _TraceAnalysis {
  const _TraceAnalysis({
    required this.source,
    required this.bindings,
    required this.disassembler,
    required this.retires,
    required this.violations,
    required this.checkOptions,
  });

  final WaveformDataSource source;
  final RvfiBindingSet bindings;
  final InstructionDisassembler? disassembler;
  final List<RiscvRetiredInstruction> retires;
  final List<RiscvConsistencyViolation> violations;
  final RiscvConsistencyCheckOptions checkOptions;
}

/// Header + view selector + body.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.report,
    required this.view,
    required this.onViewChanged,
    required this.child,
    required this.onDismissLanding,
    this.errorCount = 0,
    this.landing,
  });

  final RvfiCompletenessReport report;
  final RiscvCommitView view;
  final void Function(RiscvCommitView) onViewChanged;
  final Widget child;
  final int errorCount;
  final RiscvCommitLanding? landing;
  final VoidCallback onDismissLanding;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final landing = this.landing;
    return StageResizableBody(
      // The banner, the channel count and the reduced-binding notice all wrap,
      // so the chrome is at its tallest when the panel is at its narrowest.
      chromeHeight: 230,
      minChildHeight: 120,
      leading: [
        // Above the channel count, because it explains why the cursor is
        // where it is — the first question a user who did not move it asks.
        if (landing != null)
          RiscvCommitLandingBanner(
            landing: landing,
            onDismiss: onDismissLanding,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Text(
            l10n.riscvCommitBoundChannels(
              report.found.length,
              RvfiChannel.values.length,
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        // The reduced binding set degrades the views; it does not stop them.
        // Saying which channels are missing turns "this panel looks empty"
        // into a checklist against the user's own RTL.
        if (report.reducedBindingSetApplies)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Text(
              l10n.riscvCommitReducedBanner(riscvChannelList(report.missing)),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: _ViewSelector(
            view: view,
            onChanged: onViewChanged,
            errorCount: errorCount,
          ),
        ),
        const Divider(height: 1),
      ],
      child: child,
    );
  }
}

class _ViewSelector extends StatelessWidget {
  const _ViewSelector({
    required this.view,
    required this.onChanged,
    required this.errorCount,
  });

  final RiscvCommitView view;
  final void Function(RiscvCommitView) onChanged;
  final int errorCount;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final labels = <RiscvCommitView, String>{
      RiscvCommitView.commits: l10n.riscvCommitTabCommits,
      RiscvCommitView.registers: l10n.riscvCommitTabRegisters,
      RiscvCommitView.memory: l10n.riscvCommitTabMemory,
      RiscvCommitView.traps: l10n.riscvCommitTabTraps,
      RiscvCommitView.checks: l10n.riscvCommitTabChecks,
    };
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in labels.entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                onTap: () => onChanged(entry.key),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: kRiscvCommitTouchTarget,
                    minWidth: kRiscvCommitTouchTarget,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: entry.key == view
                        ? theme.colorScheme.primary.withValues(alpha: 0.14)
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.value,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: entry.key == view
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: entry.key == view
                              ? FontWeight.w600
                              : null,
                        ),
                      ),
                      // The checker is the reason this widget exists, so an
                      // error count is surfaced on its tab rather than
                      // waiting to be discovered.
                      if (entry.key == RiscvCommitView.checks &&
                          errorCount > 0) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.error_outline,
                          size: 14,
                          color: theme.colorScheme.error,
                        ),
                        Text(
                          '$errorCount',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
