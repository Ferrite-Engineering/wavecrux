// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/features/stage/widgets/boards/arty_a7_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/boards/basys3_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/boards/de10_lite_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/boards/nexys_a7_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/pipeline/pipeline_stage_renderer.dart';
import 'package:wavecrux/features/stage/widgets/pipeline/pipeline_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/bus_readout_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/led_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/level_bar_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/seven_segment_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/signal_graph_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/state_indicator_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/toggle_switch_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_stage_renderer.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_renderer_registry.dart';
import 'package:wavecrux/features/stage/widgets/tachometer/tachometer_stage_renderer.dart';
import 'package:wavecrux/features/stage/widgets/tachometer/tachometer_stage_widget.dart';
import 'package:wavecrux/plugins/stage_registry.dart';

/// Registers every built-in primitive Stage widget — both the pure-Dart
/// definition (in [StageRegistry]) and the Flutter renderer (in
/// [StageWidgetRendererRegistry]).
///
/// Called once at startup from `main.dart`. Tests that need access to the
/// built-in widgets call this from `setUp` and pair it with `clear()` calls
/// in `tearDown` to avoid cross-test contamination.
void registerBuiltinStageWidgets() {
  final stage = StageRegistry.instance;
  final renderers = StageWidgetRendererRegistry.instance;

  stage.register(const LedStageWidget());
  renderers.register(
    LedStageWidget.widgetId,
    (context, instance) => LedStageRenderer(instance: instance),
  );

  stage.register(const ToggleSwitchStageWidget());
  renderers.register(
    ToggleSwitchStageWidget.widgetId,
    (context, instance) => ToggleSwitchStageRenderer(instance: instance),
  );

  stage.register(const SevenSegmentStageWidget());
  renderers.register(
    SevenSegmentStageWidget.widgetId,
    (context, instance) => SevenSegmentStageRenderer(instance: instance),
  );

  stage.register(const LevelBarStageWidget());
  renderers.register(
    LevelBarStageWidget.widgetId,
    (context, instance) => LevelBarStageRenderer(instance: instance),
  );

  stage.register(const StateIndicatorStageWidget());
  renderers.register(
    StateIndicatorStageWidget.widgetId,
    (context, instance) => StateIndicatorStageRenderer(instance: instance),
  );

  stage.register(const BusReadoutStageWidget());
  renderers.register(
    BusReadoutStageWidget.widgetId,
    (context, instance) => BusReadoutStageRenderer(instance: instance),
  );

  stage.register(const SignalGraphStageWidget());
  renderers.register(
    SignalGraphStageWidget.widgetId,
    (context, instance) => SignalGraphStageRenderer(instance: instance),
  );

  stage.register(const Basys3StageWidget());
  renderers.register(
    Basys3StageWidget.widgetId,
    (context, instance) => Basys3StageRenderer(instance: instance),
  );

  stage.register(const De10LiteStageWidget());
  renderers.register(
    De10LiteStageWidget.widgetId,
    (context, instance) => De10LiteStageRenderer(instance: instance),
  );

  stage.register(const NexysA7StageWidget());
  renderers.register(
    NexysA7StageWidget.widgetId,
    (context, instance) => NexysA7StageRenderer(instance: instance),
  );

  stage.register(const ArtyA7StageWidget());
  renderers.register(
    ArtyA7StageWidget.widgetId,
    (context, instance) => ArtyA7StageRenderer(instance: instance),
  );

  // Open-core Rive reference widget — the canonical example anyone can
  // run that exercises the full custom-widget runtime + manifest +
  // normalizer pipeline. The .riv asset is bundled under
  // assets/stage/widgets/rive/runtime/tachometer.riv. See
  // assets/stage/widgets/rive/README.md.
  stage.register(const TachometerStageWidget());
  renderers.register(
    TachometerStageWidget.widgetId,
    (context, instance) => TachometerStageRenderer(
      instance: instance,
      widget: const TachometerStageWidget(),
    ),
  );

  // RVFI Commit Inspector — open core by a deliberate exception to the
  // "curated widget content is Pro" rule. The tier line for the RISC-V family is
  // "correctness is free, productivity is paid", and this widget — including
  // its consistency checker — is the free half. Do not flip its tier to make
  // the family look uniform.
  stage.register(const RiscvCommitStageWidget());
  renderers.register(
    RiscvCommitStageWidget.widgetId,
    (context, instance) => RiscvCommitStageRenderer(instance: instance),
  );

  // Pipeline Diagram — the second open-core widget of the RISC-V Core
  // Designer family, and the one that is not
  // RISC-V-specific at all: user-named stages plus valid / stall / flush is
  // generic pipeline occupancy, which is why the id is the bare `pipeline`
  // and not `riscv_pipeline`. Same recorded tier exception as the Commit
  // Inspector — do not flip it to make the family look uniform.
  stage.register(const PipelineStageWidget());
  renderers.register(
    PipelineStageWidget.widgetId,
    (context, instance) => PipelineStageRenderer(instance: instance),
  );
}

/// Clears every built-in registration. Test-only.
void clearBuiltinStageWidgets() {
  StageRegistry.instance.clear();
  StageWidgetRendererRegistry.instance.clear();
}
