// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/config_param.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';

/// Pro-tier "Tachometer" Stage widget — the curated reference Rive
/// widget for the Stage custom-widget SDK.
///
/// Renders an animated tachometer-style gauge driven by an RPM bus
/// signal, with a redline indicator and a shift-pulse animation
/// triggered by a separate boolean signal. The widget body is composed
/// in the Rive editor; the Pro overlay supplies the manifest, the
/// runtime asset, and the renderer that wires the bound signals to the
/// state machine's named inputs.
///
/// This widget exists primarily as the worked example for community
/// widget authors targeting the Rive binding contract:
///
///  - Three signal bindings (`rpm` vector, `redline` scalar, `shift`
///    scalar) whose names match the Rive state machine's named inputs
///    verbatim.
///  - A linear normalizer maps the bound `rpm` signal from raw 0..8192
///    to 0.0..1.0 by default; per-instance config knobs override the
///    input range without re-authoring the manifest.
///  - The renderer mounts the Rive `StateMachinePainter` directly and
///    feeds normalized values through the `RiveBackedAnimationController`
///    routing layer — exactly the path third-party widget bundles
///    follow once installed.
///
/// Configuration is **per-instance**, declared via [configParams] /
/// [configGroups]. The `minRpm` / `maxRpm`
/// knobs override the manifest's static normalizer at render time so a
/// single Tachometer artboard can drive any RPM range without a
/// rebuild. The `warningRpm` / `redlineRpm` knobs are decorative
/// metadata persisted on the instance, reserved for an overlay painter.
///
/// Required signal bindings:
///   - `rpm`     — RPM bus signal (vector). Linearly mapped to
///                 0.0..1.0 and written to the Rive state machine's
///                 `rpm` Number input.
///   - `redline` — boolean indicator that the configured redline
///                 threshold has been exceeded. Written to the Rive
///                 state machine's `redline` Boolean input.
///   - `shift`   — boolean rising-edge signal that pulses the
///                 redline-pulse animation. Written to the Rive
///                 state machine's `shift` Boolean input; edge
///                 detection lives in the state machine itself.
///
/// See `assets/stage/widgets/rive/README.md` for the editor contract a
/// designer follows when authoring `runtime/tachometer.riv`.
class TachometerStageWidget extends StageWidget {
  /// Constructs the const definition. The widget has no per-instance
  /// state in the definition — instance state lives on
  /// `StageInstance.configuration`.
  const TachometerStageWidget();

  /// Stable id used by the Stage registry, the picker, session files,
  /// and the per-instance lookup the renderer factory consults.
  static const String widgetId = 'wavecrux.pro.tachometer';

  @override
  String get id => widgetId;

  @override
  String get displayName => 'Tachometer';

  @override
  String? get displayNameKey => 'stageTachometerDisplayName';

  @override
  String get description =>
      'Animated tachometer gauge with redline indicator and shift-pulse '
      'animation, driven by RPM and boolean signals.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.instrument;

  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(
      name: 'rpm',
      description:
          'RPM bus signal driving the gauge needle. Mapped from the '
          'configured RPM range to the Rive state-machine input named '
          'rpm (Number).',
    ),
    SignalBinding(
      name: 'redline',
      description:
          'Boolean indicator that the configured redline threshold '
          'has been exceeded. Written to the Rive state-machine input '
          'named redline (Boolean).',
      bitWidth: 1,
    ),
    SignalBinding(
      name: 'shift',
      description:
          'Boolean rising-edge signal that pulses the redline-pulse '
          'animation. Written to the Rive state-machine input named '
          'shift (Boolean); edge detection lives in the state machine.',
      bitWidth: 1,
    ),
  ];

  @override
  List<SignalBinding> get optionalSignals => const [];

  @override
  (double, double) get defaultSize => (320, 220);

  @override
  (double, double) get minSize => (200, 160);

  @override
  LicenseTier get requiredTier => LicenseTier.openCore;

  // ── per-instance configuration schema ────────────────────────────────────

  /// Group ids — kept stable across versions so saved sessions and
  /// localization-key lookups remain valid.
  static const String _rangeGroup = 'tachometer.range';
  static const String _zonesGroup = 'tachometer.zones';

  @override
  List<ConfigParamGroup> get configGroups => const [
    ConfigParamGroup(
      id: _rangeGroup,
      labelKey: 'tachometerGroupRange',
    ),
    ConfigParamGroup(
      id: _zonesGroup,
      labelKey: 'tachometerGroupZones',
    ),
  ];

  @override
  List<ConfigParam> get configParams => const [
    // ── RPM range — drives the renderer's per-instance LinearNormalizer
    ConfigParam(
      id: 'minRpm',
      labelKey: 'tachometerParamMinRpm',
      type: ConfigParamType.integer,
      defaultValue: 0,
      min: 0,
      max: 30000,
      step: 100,
      groupId: _rangeGroup,
    ),
    ConfigParam(
      id: 'maxRpm',
      labelKey: 'tachometerParamMaxRpm',
      type: ConfigParamType.integer,
      defaultValue: 8000,
      min: 100,
      max: 30000,
      step: 100,
      groupId: _rangeGroup,
    ),
    // ── Decorative threshold metadata — persisted on the instance
    //    for a future overlay painter to consume.
    ConfigParam(
      id: 'warningRpm',
      labelKey: 'tachometerParamWarningRpm',
      type: ConfigParamType.integer,
      defaultValue: 6500,
      min: 0,
      max: 30000,
      step: 100,
      groupId: _zonesGroup,
    ),
    ConfigParam(
      id: 'redlineRpm',
      labelKey: 'tachometerParamRedlineRpm',
      type: ConfigParamType.integer,
      defaultValue: 7500,
      min: 0,
      max: 30000,
      step: 100,
      groupId: _zonesGroup,
    ),
  ];
}
