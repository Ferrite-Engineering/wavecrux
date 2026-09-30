// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_config_editor.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Builds a [ConfigLabelResolver] for a given [BuildContext].
///
/// The factory takes a `BuildContext` because the resolver needs access
/// to localization classes, which are looked up via inherited widgets
/// (`L10N.of(context)`, `L10NPro.of(context)`).
typedef StageConfigLabelResolverFactory =
    ConfigLabelResolver Function(
      BuildContext context,
    );

/// Open-core extension point that supplies the ARB-key resolver used by
/// [StageWidgetConfigEditor] when rendering a Stage widget's
/// per-instance configuration schema.
///
/// The open-core default resolves the open-core Stage widgets' config
/// keys (currently the Tachometer reference widget — see
/// [_openCoreResolver]) and returns the raw key as a fallback. This
/// avoids leaking Pro pack keys into open-core while still rendering
/// localized labels for the built-in Rive reference widget.
///
/// The Pro overlay overrides this provider with a factory
/// that consults `L10NPro.of(context)` for every Pro widget's
/// declared `labelKey`, falling back to the open-core resolver (and
/// then to the raw key) when a key is not recognised. This keeps the
/// (large) Pro key catalog confined to the overlay.
///
/// Without this provider override, [StageWidgetConfigEditor] would
/// render raw ARB keys (e.g. "characterLcdParamGeometry") in the
/// configuration section of the bindings pane.
///
/// See ARCHITECTURE.md §10 (Pro Overlay Seams).
final stageConfigLabelResolverFactoryProvider =
    Provider<StageConfigLabelResolverFactory>(
      (_) => _openCoreFactory,
    );

/// Public entry point to the open-core resolver.
///
/// Exposed so the Pro overlay's
/// [stageConfigLabelResolverFactoryProvider] override can **chain**
/// unmatched keys back to open-core resolution (open-core Stage widget
/// display names + the Tachometer config labels) instead of falling back
/// to the raw ARB key. Because the Pro override replaces the whole
/// provider value, without this seam every open-core key — e.g.
/// `stageTachometerDisplayName`, `stageLevelBarDisplayName`,
/// `tachometerParamMinRpm` — would render raw in the Pro build's picker,
/// bindings pane, and instance tile. The Pro override therefore does
/// `resolveProConfigKey(...) ?? openCoreStageConfigLabelResolver(context)(key)`.
///
/// Returns the raw [key] for keys it does not recognise (identity
/// fallback), so the Pro override never has to special-case unknown keys.
ConfigLabelResolver openCoreStageConfigLabelResolver(BuildContext context) =>
    _openCoreFactory(context);

ConfigLabelResolver _openCoreFactory(BuildContext context) {
  return (key) {
    // Lazy L10N lookup: only resolve `L10N.of(context)` when the key
    // actually matches one of the open-core ARB-backed labels. Unknown
    // keys fall through to identity without touching the context — this
    // keeps the default factory usable from unit tests that don't run a
    // full widget tree (e.g. the resolver-provider tests).
    final mapped = _openCoreKeyToGetter(key);
    if (mapped == null) return key;
    return mapped(L10N.of(context));
  };
}

/// Returns the [L10N] getter for [key], or `null` when [key] is not a
/// known open-core Stage widget config label.
String Function(L10N l)? _openCoreKeyToGetter(String key) {
  switch (key) {
    // Open-core Stage widget display names (resolved at the picker /
    // bindings-pane / instance-tile render sites via `displayNameKey`).
    case 'stageLedDisplayName':
      return (l) => l.stageLedDisplayName;
    case 'stageBusReadoutDisplayName':
      return (l) => l.stageBusReadoutDisplayName;
    case 'stageLevelBarDisplayName':
      return (l) => l.stageLevelBarDisplayName;
    case 'stageSevenSegmentDisplayName':
      return (l) => l.stageSevenSegmentDisplayName;
    case 'stageSignalGraphDisplayName':
      return (l) => l.stageSignalGraphDisplayName;
    case 'stageStateIndicatorDisplayName':
      return (l) => l.stageStateIndicatorDisplayName;
    case 'stageToggleSwitchDisplayName':
      return (l) => l.stageToggleSwitchDisplayName;
    case 'stageTachometerDisplayName':
      return (l) => l.stageTachometerDisplayName;
    case 'stageRiscvCommitDisplayName':
      return (l) => l.stageRiscvCommitDisplayName;
    case 'stagePipelineDisplayName':
      return (l) => l.stagePipelineDisplayName;
    // Auto-bind dialog title for a non-board subject — the RVFI Commit
    // Inspector binds a riscv-formal channel bundle, not a dev board.
    case 'stageRvfiAutoBindTitle':
      return (l) => l.stageRvfiAutoBindTitle;
    // RVFI Commit Inspector per-instance configuration.
    case 'riscvCommitGroupDisplay':
      return (l) => l.riscvCommitGroupDisplay;
    case 'riscvCommitParamRegisterNaming':
      return (l) => l.riscvCommitParamRegisterNaming;
    case 'riscvCommitChoiceAbi':
      return (l) => l.riscvCommitChoiceAbi;
    case 'riscvCommitChoiceNumeric':
      return (l) => l.riscvCommitChoiceNumeric;
    case 'riscvCommitParamRegisterCount':
      return (l) => l.riscvCommitParamRegisterCount;
    case 'riscvCommitParamMemoryLogDepth':
      return (l) => l.riscvCommitParamMemoryLogDepth;
    // Pipeline Diagram per-instance configuration. The eight stage-name keys
    // are separate rather than one interpolated key because this resolver
    // maps a key to a zero-argument [L10N] getter — the config editor has no
    // way to pass a stage index into a label lookup.
    case 'pipelineGroupPipeline':
      return (l) => l.pipelineGroupPipeline;
    case 'pipelineGroupStages':
      return (l) => l.pipelineGroupStages;
    case 'pipelineParamStageCount':
      return (l) => l.pipelineParamStageCount;
    case 'pipelineParamIdentitySource':
      return (l) => l.pipelineParamIdentitySource;
    case 'pipelineChoiceIdentityPositional':
      return (l) => l.pipelineChoiceIdentityPositional;
    case 'pipelineChoiceIdentityPc':
      return (l) => l.pipelineChoiceIdentityPc;
    case 'pipelineParamWindowCycles':
      return (l) => l.pipelineParamWindowCycles;
    case 'pipelineParamStage1Name':
      return (l) => l.pipelineParamStage1Name;
    case 'pipelineParamStage2Name':
      return (l) => l.pipelineParamStage2Name;
    case 'pipelineParamStage3Name':
      return (l) => l.pipelineParamStage3Name;
    case 'pipelineParamStage4Name':
      return (l) => l.pipelineParamStage4Name;
    case 'pipelineParamStage5Name':
      return (l) => l.pipelineParamStage5Name;
    case 'pipelineParamStage6Name':
      return (l) => l.pipelineParamStage6Name;
    case 'pipelineParamStage7Name':
      return (l) => l.pipelineParamStage7Name;
    case 'pipelineParamStage8Name':
      return (l) => l.pipelineParamStage8Name;
    case 'tachometerGroupRange':
      return (l) => l.tachometerGroupRange;
    case 'tachometerGroupZones':
      return (l) => l.tachometerGroupZones;
    case 'tachometerParamMinRpm':
      return (l) => l.tachometerParamMinRpm;
    case 'tachometerParamMaxRpm':
      return (l) => l.tachometerParamMaxRpm;
    case 'tachometerParamWarningRpm':
      return (l) => l.tachometerParamWarningRpm;
    case 'tachometerParamRedlineRpm':
      return (l) => l.tachometerParamRedlineRpm;
  }
  return null;
}
