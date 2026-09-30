// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/features/stage/widgets/pipeline/pipeline_grid.dart';
import 'package:wavecrux/features/stage/widgets/pipeline/pipeline_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/pipeline/pipeline_view_data.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/translator_registry.dart';
import 'package:wavecrux/services/decoders/isa/instruction_disassembler.dart';
import 'package:wavecrux/services/riscv/riscv_instruction_identity.dart';
import 'package:wavecrux/services/riscv/riscv_pipeline_observation_service.dart';
import 'package:wavecrux/services/riscv/riscv_trace_values.dart';

/// Renders a [PipelineStageWidget] instance.
///
/// **The lazy-load trap, first.** `WaveformDataSource.valueAt` returns `null`
/// both for "this signal is not loaded" and for "this signal has no value
/// yet", and a Stage binding can name a signal the user never added to the
/// viewer. So every declared pin — the clock, the instruction word and all
/// four pins of all eight stages — is watched through
/// `stageBoundSignalProvider` for its lazy-load side effect **before** the
/// observation service is allowed to walk the source. Skipping that produces
/// an empty diagram on a perfectly good trace. See ARCHITECTURE §6.6 rule 1.
///
/// **There is no cycle domain.** `startTime` / `endTime` / `placePrimary` are
/// simulation *ticks*. Every "cycle" here is an index into the rising edges
/// of the bound clock, and every seek converts back through
/// `RiscvPipelineObservationResult.cycleTicks`.
///
/// **What is computed where.** The observation and the tracking run over the
/// whole trace and are memoized against `(source, bindings, stageCount,
/// identity source)`, so scrubbing the cursor does not re-walk the trace. The
/// window and the rows are recomputed per build, because the window is a
/// function of the cursor.
class PipelineStageRenderer extends ConsumerStatefulWidget {
  const PipelineStageRenderer({required this.instance, super.key});

  final StageInstance instance;

  @override
  ConsumerState<PipelineStageRenderer> createState() =>
      _PipelineStageRendererState();
}

class _PipelineStageRendererState extends ConsumerState<PipelineStageRenderer> {
  _PipelineAnalysis? _analysis;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final config = widget.instance.configuration;
    final stageCount = parsePipelineStageCount(
      config[PipelineStageWidget.paramStageCount],
    );
    final identitySource = parsePipelineIdentitySource(
      config[PipelineStageWidget.paramIdentitySource],
    );
    final windowCycles = parsePipelineWindowCycles(
      config[PipelineStageWidget.paramWindowCycles],
    );

    // ── the lazy-load watch. Unconditional, and before anything else. ────────
    //
    // Every *declared* pin is watched, not only the pins of the currently
    // enabled stages: a user who drops from 8 stages to 4 leaves four stages'
    // worth of bindings in the instance, and an unwatched ref that later
    // becomes visible again would read as unloaded.
    var loading = false;
    String? watch(String pin) {
      final binding = widget.instance.signalBindings[pin];
      final snapshot = ref.watch(stageBoundSignalProvider(binding));
      if (snapshot.kind == StageSignalSnapshotKind.loading) loading = true;
      final r = binding?.signalRef;
      return (r == null || r.isEmpty) ? null : r;
    }

    final clockRef = watch(PipelineStageWidget.clockPin);
    final instructionRef = watch(PipelineStageWidget.instructionPin);
    final allStages = <RiscvPipelineStageBinding>[
      for (var s = 1; s <= kPipelineMaxStages; s++)
        RiscvPipelineStageBinding(
          validRef: watch(PipelineStageWidget.stagePin(s, 'valid')),
          pcRef: watch(PipelineStageWidget.stagePin(s, 'pc')),
          stallRef: watch(PipelineStageWidget.stagePin(s, 'stall')),
          flushRef: watch(PipelineStageWidget.stagePin(s, 'flush')),
        ),
    ];
    final stages = allStages.take(stageCount).toList();

    final source = ref.watch(waveformSourceProvider).value;
    final cursorState = ref.watch(cursorStateProvider);
    final disassembler = ref.watch(riscvDisassemblerProvider).asData?.value;

    if (source == null) return PipelineNotice(message: l10n.pipelineNoFile);
    if (loading) return PipelineNotice(message: l10n.pipelineLoading);
    if (clockRef == null) return PipelineNotice(message: l10n.pipelineNoClock);
    if (!stages.any((s) => s.validRef != null)) {
      return PipelineNotice(message: l10n.pipelineNoStageBindings(stageCount));
    }

    // Open core has no `tag` tracker and must not pretend otherwise; the
    // config cannot select one, but a session written by a Pro build could.
    final tracker = RiscvIdentityTrackerRegistry.create(identitySource);
    if (tracker == null) {
      return PipelineNotice(
        message: l10n.pipelineTrackerUnavailable(identitySource.name),
      );
    }

    final analysis = _analyse(
      source: source,
      clockRef: clockRef,
      instructionRef: instructionRef,
      stages: stages,
      tracker: tracker,
      identitySource: identitySource,
      disassembler: disassembler,
    );

    if (analysis.cycleTicks.isEmpty) {
      return PipelineNotice(message: l10n.pipelineNoCycles);
    }

    final cursorTime = cursorState.primaryCursorTime ?? source.startTime;
    final anchor = _cycleAt(analysis.cycleTicks, cursorTime);

    final data = buildPipelineViewData(
      result: analysis.result,
      cycleTicks: analysis.cycleTicks,
      stageCount: stageCount,
      stageNames: [
        for (var s = 0; s < stageCount; s++) pipelineStageName(config, s),
      ],
      windowCycles: windowCycles,
      anchorCycle: anchor,
      disassembler: disassembler,
      instructionWordAtCycle: analysis.instructionWordAtCycle,
    );

    return _Frame(
      data: data,
      onSeekCycle: _seekCycle,
      child: data.rows.isEmpty
          ? PipelineNotice(message: l10n.pipelineNoOccupancy)
          : PipelineGrid(data: data, onSeekCycle: _seekCycle),
    );
  }

  /// Moves the primary cursor to the tick that opens [cycleIndex] — what a
  /// click on a cell does. The cycle index means nothing to the rest of the
  /// app; the tick is the shared coordinate.
  void _seekCycle(int cycleIndex) {
    final ticks = _analysis?.cycleTicks;
    if (ticks == null || cycleIndex < 0 || cycleIndex >= ticks.length) return;
    ref.read(cursorStateProvider.notifier).placePrimary(ticks[cycleIndex]);
  }

  /// Rebuilds the whole-trace analysis when, and only when, its inputs
  /// change. Cursor motion is not one of its inputs.
  _PipelineAnalysis _analyse({
    required WaveformDataSource source,
    required String clockRef,
    required String? instructionRef,
    required List<RiscvPipelineStageBinding> stages,
    required RiscvInstructionIdentityTracker tracker,
    required RiscvIdentitySource identitySource,
    required InstructionDisassembler? disassembler,
  }) {
    final cached = _analysis;
    if (cached != null &&
        identical(cached.source, source) &&
        cached.clockRef == clockRef &&
        cached.instructionRef == instructionRef &&
        cached.identitySource == identitySource &&
        _stagesEqual(cached.stages, stages)) {
      return cached;
    }

    final observed = const RiscvPipelineObservationService().build(
      source: source,
      clockRef: clockRef,
      stages: stages,
      startTime: source.startTime,
      endTime: source.endTime,
    );
    final analysis = _PipelineAnalysis(
      source: source,
      clockRef: clockRef,
      instructionRef: instructionRef,
      stages: List.unmodifiable(stages),
      identitySource: identitySource,
      cycleTicks: observed.cycleTicks,
      result: observed.cycleTicks.isEmpty
          ? const RiscvIdentityTrackResult(
              source: RiscvIdentitySource.positional,
              occupancy: [],
              confidence: RiscvIdentityConfidence.high,
              warnings: [],
            )
          : tracker.track(observed.observation),
      instructionWords: <int, int?>{},
      instructionRefResolver: instructionRef == null
          ? null
          : (tick) =>
                riscvDecodeUint(source.valueAt(instructionRef, tick)).value,
    );
    _analysis = analysis;
    return analysis;
  }

  static bool _stagesEqual(
    List<RiscvPipelineStageBinding> a,
    List<RiscvPipelineStageBinding> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int _cycleAt(List<int> ticks, int tick) {
    if (ticks.isEmpty) return 0;
    if (tick < ticks.first) return 0;
    var lo = 0;
    var hi = ticks.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (ticks[mid] <= tick) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

/// Memoized whole-trace analysis, keyed by everything that can change it.
class _PipelineAnalysis {
  _PipelineAnalysis({
    required this.source,
    required this.clockRef,
    required this.instructionRef,
    required this.stages,
    required this.identitySource,
    required this.cycleTicks,
    required this.result,
    required this.instructionWords,
    required this.instructionRefResolver,
  });

  final WaveformDataSource source;
  final String clockRef;
  final String? instructionRef;
  final List<RiscvPipelineStageBinding> stages;
  final RiscvIdentitySource identitySource;
  final List<int> cycleTicks;
  final RiscvIdentityTrackResult result;

  /// Memoized `cycle → instruction word` samples. Only the cycles a row
  /// actually entered the pipe in are ever sampled, so this stays a handful
  /// of entries rather than one per cycle.
  final Map<int, int?> instructionWords;

  final int? Function(int tick)? instructionRefResolver;

  /// The instruction word observed entering the front stage at [cycleIndex].
  int? instructionWordAtCycle(int cycleIndex) {
    if (instructionRefResolver == null) return null;
    if (cycleIndex < 0 || cycleIndex >= cycleTicks.length) return null;
    return instructionWords.putIfAbsent(
      cycleIndex,
      () => instructionRefResolver!(cycleTicks[cycleIndex]),
    );
  }
}

/// Header + confidence banner + legend + body.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.data,
    required this.onSeekCycle,
    required this.child,
  });

  final PipelineViewData data;
  final void Function(int cycleIndex) onSeekCycle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Text(
            l10n.pipelineHeader(
              data.stageCount,
              data.windowStart,
              data.windowEnd - 1,
              data.totalCycles,
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _ConfidenceBanner(data: data),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: PipelineLegend(data: data),
        ),
        const Divider(height: 1),
        // The whole point of the widget: at low confidence the grid is
        // visibly held at arm's length rather than presented as fact. The
        // cells stay legible (and clickable) because the tracker adopted the
        // trace where it disagreed with its own model — but nobody should be
        // able to screenshot this as a finding without the caveat attached.
        Expanded(
          child: data.confidence == RiscvIdentityConfidence.low
              ? Opacity(opacity: 0.55, child: child)
              : child,
        ),
      ],
    );
  }
}

/// States the tracker's verdict, loudly when it has to.
class _ConfidenceBanner extends StatelessWidget {
  const _ConfidenceBanner({required this.data});

  final PipelineViewData data;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    if (data.confidence == RiscvIdentityConfidence.high) {
      return const SizedBox.shrink();
    }
    final low = data.confidence == RiscvIdentityConfidence.low;
    final colour = low ? theme.colorScheme.error : theme.colorScheme.tertiary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            low ? Icons.error_outline : Icons.info_outline,
            size: 16,
            color: colour,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              low
                  ? l10n.pipelineLowConfidenceBanner(
                      data.mismatchCount,
                      _sourceLabel(l10n, data.source),
                    )
                  : l10n.pipelineDegradedBanner(
                      data.warnings.length,
                      _sourceLabel(l10n, data.source),
                    ),
              style: theme.textTheme.labelSmall?.copyWith(color: colour),
            ),
          ),
        ],
      ),
    );
  }
}

String _sourceLabel(L10N l10n, RiscvIdentitySource source) => switch (source) {
  RiscvIdentitySource.pc => l10n.pipelineChoiceIdentityPc,
  RiscvIdentitySource.positional => l10n.pipelineChoiceIdentityPositional,
  // Unreachable in an open-core build — there is no `tag` tracker to have
  // produced a result — but a Pro build shares this renderer's frame.
  RiscvIdentitySource.tag => l10n.pipelineIdentityTag,
};
