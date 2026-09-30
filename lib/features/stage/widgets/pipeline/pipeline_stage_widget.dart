// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/config_param.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/services/riscv/riscv_instruction_identity.dart';

/// Smallest pipeline the widget will draw.
const int kPipelineMinStages = 2;

/// Largest pipeline the widget will draw.
///
/// Eight is the point at which per-stage pins (4 each) stop being bindable by
/// hand and the grid stops being readable at a Stage-panel size. A deeper
/// pipe is a Pro `wavecrux.pro.riscv_pipeline_adv` question, not a bigger
/// slider.
const int kPipelineMaxStages = 8;

/// Stage count assumed when the instance has never been configured.
///
/// The classic in-order five-stage pipeline — which is what an
/// RVFI-instrumented teaching core looks like, and what the bundled fixture
/// traces.
const int kPipelineDefaultStages = 5;

/// Default per-stage names, index 0 first.
///
/// `IF` / `ID` / `EX` / `MEM` / `WB` are the standard abbreviations for a
/// classic in-order pipeline. They are not ISA vocabulary — no RISC-V term
/// appears anywhere in this widget — and every one of them is a free-text
/// config param the user overwrites for their own design. They are the
/// flagship preset, not a hardwired assumption.
const List<String> kPipelineDefaultStageNames = <String>[
  'IF',
  'ID',
  'EX',
  'MEM',
  'WB',
  'S6',
  'S7',
  'S8',
];

/// Which identity sources this widget offers.
///
/// **`RiscvIdentitySource.tag` is deliberately absent.** Tag-based tracking
/// is the Pro capability (`wavecrux.pro.riscv_pipeline_adv`), and offering a
/// choice this build has no tracker for would be a menu item that produces a
/// blank panel.
const List<RiscvIdentitySource> kPipelineIdentitySources =
    <RiscvIdentitySource>[
      RiscvIdentitySource.positional,
      RiscvIdentitySource.pc,
    ];

/// **Pipeline Diagram** — instructions × cycles, cells shaded by stage.
///
/// Rows are in-flight instructions, columns are clock cycles, and each cell
/// says which stage that instruction occupied in that cycle. The cycle window
/// is anchored on the cursor and clicking a cell moves the cursor to that
/// cycle's tick.
///
/// **Architecture-neutral, on purpose.** The widget id is the bare
/// `pipeline`, not `riscv_pipeline`: there is zero ISA content here — user-
/// named stages plus `valid` / `stall` / `flush` / `pc` bindings is generic
/// pipeline occupancy, and it applies unchanged to an FFT engine, a video
/// pipeline, a crypto core, a systolic array or a packet processor. A
/// `riscv_` prefix would have hidden it from an audience far larger than
/// RISC-V core designers, and widget ids land in shipped `.wavecrux` sessions
/// and five locales of ARB where a rename is a migration. It ships with the
/// classic five-stage in-order pipeline as its flagship configuration, so
/// nothing about the RISC-V story changes.
///
/// **Open core, and not crippled.** The tier line for this family is
/// *correctness is free, productivity is paid*. There is no cycle cap, no
/// watermark and no in-view upsell, and there must not be one added.
///
/// **Honesty is the load-bearing feature.** Positional tracking is a shift-
/// register model of the pipe; it is correct for a single-issue in-order core
/// and wrong for anything else. The tracker self-checks its model against the
/// observed `valid` bits every cycle and reports
/// [RiscvIdentityConfidence.low] on any disagreement — and the renderer must
/// state that rather than drawing a plausible lie. A pipeline diagram that
/// silently mis-attributes is worse than no diagram.
///
/// **Pins.** One clock, plus four per stage for up to eight stages. Thirty-
/// three declared pins would be unusable if they were all listed at once, so
/// every per-stage pin carries a [SignalBinding.visibleWhenValues] predicate
/// keyed off [paramStageCount] and the bindings pane shows only the stages
/// the user has enabled.
class PipelineStageWidget extends StageWidget {
  const PipelineStageWidget();

  /// Stable id used by the Stage registry, the picker, session files and the
  /// renderer factory. Bare, per the open-core widget-id convention.
  static const String widgetId = 'pipeline';

  /// Config key: how many stages the pipeline has (2–8).
  static const String paramStageCount = 'stageCount';

  /// Config key: [RiscvIdentitySource] id — `positional` or `pc`.
  static const String paramIdentitySource = 'identitySource';

  /// Config key: how many cycles the window shows.
  static const String paramWindowCycles = 'windowCycles';

  /// Config key prefix for the per-stage name; `stage1Name` … `stage8Name`.
  static String stageNameParam(int stage) => 'stage${stage}Name';

  /// Pin name for stage [stage] (1-based) — `stage3_valid`, `stage3_pc`, …
  static String stagePin(int stage, String role) => 'stage${stage}_$role';

  /// The clock pin. Cycles are its rising edges; there is no cycle domain in
  /// a waveform, so without this pin there is no diagram.
  static const String clockPin = 'clk';

  /// Optional instruction-word pin, sampled at the front stage.
  static const String instructionPin = 'instruction';

  static const String _groupPipeline = 'pipeline.pipeline';
  static const String _groupStages = 'pipeline.stages';

  @override
  String get id => widgetId;

  @override
  String get displayName => 'Pipeline Diagram';

  @override
  String? get displayNameKey => 'stagePipelineDisplayName';

  @override
  String get description =>
      'Instructions against cycles, shaded by pipeline stage, over a '
      'cursor-anchored cycle window. Two to eight user-named stages driven '
      'by per-stage valid / stall / flush signals.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.instrument;

  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(
      name: clockPin,
      description:
          'Pipeline clock. Cycles are its rising edges — a waveform has no '
          'cycle domain of its own, so without this pin there is nothing to '
          'index the columns by.',
      bitWidth: 1,
    ),
  ];

  @override
  List<SignalBinding> get optionalSignals => <SignalBinding>[
    const SignalBinding(
      name: instructionPin,
      description:
          'Instruction word entering the first stage. Optional: when bound, '
          'rows are labelled with the disassembly; otherwise they fall back '
          'to the PC and then to a row number.',
    ),
    for (var stage = 1; stage <= kPipelineMaxStages; stage++) ...[
      SignalBinding(
        name: stagePin(stage, 'valid'),
        description:
            'Stage $stage holds an instruction this cycle. The one signal '
            'the occupancy grid cannot be drawn without.',
        bitWidth: 1,
        visibleWhenKey: paramStageCount,
        visibleWhenValues: _visibleFrom(stage),
      ),
      SignalBinding(
        name: stagePin(stage, 'pc'),
        description:
            'PC of the instruction in stage $stage. Required by the PC '
            'identity source; used for row labels by both sources.',
        visibleWhenKey: paramStageCount,
        visibleWhenValues: _visibleFrom(stage),
      ),
      SignalBinding(
        name: stagePin(stage, 'stall'),
        description:
            'Stage $stage will not release its occupant at the end of this '
            'cycle. Optional — unbound means "this stage never stalls".',
        bitWidth: 1,
        visibleWhenKey: paramStageCount,
        visibleWhenValues: _visibleFrom(stage),
      ),
      SignalBinding(
        name: stagePin(stage, 'flush'),
        description:
            'The contents of stage $stage were killed this cycle. Optional — '
            'unbound means "this stage is never flushed", and a pipe that '
            'flushes anyway shows up as a tracking mismatch rather than as a '
            'quietly wrong grid.',
        bitWidth: 1,
        visibleWhenKey: paramStageCount,
        visibleWhenValues: _visibleFrom(stage),
      ),
    ],
  ];

  @override
  (double, double) get defaultSize => (620, 340);

  @override
  (double, double) get minSize => (320, 200);

  @override
  List<ConfigParamGroup> get configGroups => const [
    ConfigParamGroup(id: _groupPipeline, labelKey: 'pipelineGroupPipeline'),
    ConfigParamGroup(id: _groupStages, labelKey: 'pipelineGroupStages'),
  ];

  @override
  List<ConfigParam> get configParams => <ConfigParam>[
    const ConfigParam(
      id: paramStageCount,
      labelKey: 'pipelineParamStageCount',
      type: ConfigParamType.integer,
      defaultValue: kPipelineDefaultStages,
      min: kPipelineMinStages,
      max: kPipelineMaxStages,
      groupId: _groupPipeline,
    ),
    const ConfigParam(
      id: paramIdentitySource,
      labelKey: 'pipelineParamIdentitySource',
      type: ConfigParamType.enumChoice,
      defaultValue: 'positional',
      choices: [
        ConfigParamChoice(
          id: 'positional',
          labelKey: 'pipelineChoiceIdentityPositional',
        ),
        ConfigParamChoice(id: 'pc', labelKey: 'pipelineChoiceIdentityPc'),
      ],
      groupId: _groupPipeline,
    ),
    const ConfigParam(
      id: paramWindowCycles,
      labelKey: 'pipelineParamWindowCycles',
      type: ConfigParamType.integer,
      defaultValue: 24,
      min: 4,
      max: 128,
      step: 4,
      groupId: _groupPipeline,
    ),
    for (var stage = 1; stage <= kPipelineMaxStages; stage++)
      ConfigParam(
        id: stageNameParam(stage),
        labelKey: 'pipelineParamStage${stage}Name',
        type: ConfigParamType.text,
        defaultValue: kPipelineDefaultStageNames[stage - 1],
        groupId: _groupStages,
        visibleWhenKey: paramStageCount,
        visibleWhenValues: _visibleFrom(stage),
      ),
  ];

  /// The stage-count values for which stage [stage]'s pins and name are
  /// shown: every count from [stage] up to [kPipelineMaxStages].
  ///
  /// `null` is a member for the stages inside the default pipeline because
  /// the bindings pane and the config editor both test the instance's **raw**
  /// configuration map, and a freshly-dropped instance has an empty one — the
  /// declared `defaultValue` is only applied when a field is read. Without
  /// `null` in the set, a new instance would show a clock pin and nothing
  /// else.
  static Set<Object?> _visibleFrom(int stage) => <Object?>{
    if (stage <= kPipelineDefaultStages) null,
    for (var n = stage; n <= kPipelineMaxStages; n++) n,
  };
}

/// Parses the stored [PipelineStageWidget.paramIdentitySource] value.
///
/// Anything unrecognised — including a `tag` written by a session saved from
/// a Pro build whose widget was later opened in open core — falls back to
/// [RiscvIdentitySource.positional] rather than resolving to a source this
/// build has no tracker for.
RiscvIdentitySource parsePipelineIdentitySource(Object? raw) {
  for (final source in kPipelineIdentitySources) {
    if (source.name == raw) return source;
  }
  return RiscvIdentitySource.positional;
}

/// Clamps the stored [PipelineStageWidget.paramStageCount] into 2–8.
int parsePipelineStageCount(Object? raw) {
  final value = raw is int ? raw : kPipelineDefaultStages;
  return value.clamp(kPipelineMinStages, kPipelineMaxStages);
}

/// Clamps the stored [PipelineStageWidget.paramWindowCycles].
int parsePipelineWindowCycles(Object? raw) {
  final value = raw is int ? raw : 24;
  return value.clamp(4, 128);
}

/// The user-facing name of stage [index] (0-based) from a configuration map.
String pipelineStageName(Map<String, Object?> config, int index) {
  final raw = config[PipelineStageWidget.stageNameParam(index + 1)];
  if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  return kPipelineDefaultStageNames[index.clamp(
    0,
    kPipelineDefaultStageNames.length - 1,
  )];
}
