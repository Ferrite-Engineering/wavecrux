// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_auto_bind_service.dart';
import 'package:wavecrux/domain/models/config_param.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';

/// Describes one Stage widget that the user can drop onto a Stage panel.
///
/// A [StageWidget] is the static definition — it declares the widget's
/// identity, its display metadata, and the signal inputs it expects. The
/// concrete Flutter rendering for a definition lives in the feature layer
/// and is looked up at draw time by [StageWidget.id].
///
/// The signal inputs are described as [SignalBinding]s — the same model
/// already used by [ProtocolDecoder]. Each input names a logical pin
/// (`"led0"`, `"value"`, `"sclk"`); the user maps it to a real waveform
/// signal when they configure the widget instance.
///
/// Pure Dart — no Flutter imports. Implementations must be `const`.
@immutable
abstract class StageWidget {
  const StageWidget();

  /// Stable, unique identifier used to look up this widget in the registry
  /// and persist it in `.wavecrux` session files.
  ///
  /// Use lower-snake-case (`"led"`, `"seven_segment"`, `"basys3"`).
  String get id;

  /// Short, user-visible name shown in the Add-Widget picker and in panel
  /// instance headers. Localised strings should be resolved at the call
  /// site — definitions may carry an English fallback here.
  String get displayName;

  /// Optional ARB key for [displayName], resolved at the call site through
  /// `stageConfigLabelResolverFactoryProvider`. When null, the call site uses
  /// the raw [displayName] English fallback. Lets the curated Pro pack localize
  /// widget names without the domain layer depending on any ARB.
  String? get displayNameKey => null;

  /// One-sentence description of what the widget does.
  String get description;

  /// Broad category used to group widgets in the picker.
  StageWidgetCategory get category;

  /// Signal inputs the user **must** bind before the widget can render.
  List<SignalBinding> get requiredSignals;

  /// Signal inputs that improve the visualisation but are not mandatory.
  List<SignalBinding> get optionalSignals => const [];

  /// True when this definition composes other [StageWidget]s onto a
  /// backdrop. Compound widgets implement [CompoundStageWidget].
  bool get isCompound => false;

  /// Whether the Stage bindings pane offers an "Auto-bind" affordance for
  /// instances of this widget.
  ///
  /// Defaults to [isCompound] — every FPGA board widget keeps the affordance
  /// it has always had, resolved to the shared `BoardAutoBindService` by
  /// `stageAutoBindServiceFor`, with no per-board declaration. A
  /// **non-compound** widget opts in by overriding [autoBindService] with its
  /// own matcher (the RISC-V widgets bind ~20 RVFI channels, which is not
  /// usable one pin at a time); overriding this getter alone does nothing,
  /// since a non-compound widget with no service has nothing to run.
  bool get supportsAutoBind => isCompound || autoBindService != null;

  /// The auto-bind matcher for this widget, or `null` to use the default
  /// resolution (the board matcher for compound widgets, nothing otherwise).
  ///
  /// Declared here rather than resolved from a registry so a widget and its
  /// matcher stay a single readable unit. The domain layer only names the
  /// [StageAutoBindService] interface; concrete matchers live in `services/`
  /// and are referenced from the widget definitions in `features/`.
  StageAutoBindService? get autoBindService => null;

  /// Optional ARB key for the auto-bind preview dialog's title, resolved at
  /// the call site through `stageConfigLabelResolverFactoryProvider` exactly
  /// like [displayNameKey].
  ///
  /// Defaults to null, which leaves the dialog on its board-flavoured
  /// heading ("Auto-bind board signals") — correct for every FPGA board
  /// widget and wrong for anything else. A widget with its own matcher names
  /// its own subject: the RVFI Commit Inspector is binding a riscv-formal
  /// channel bundle, not a development board.
  String? get autoBindTitleKey => null;

  /// Default canvas size (in logical pixels) for new instances of this
  /// widget. The Stage panel uses this to position freshly-dropped
  /// widgets; the user can resize afterwards.
  ///
  /// Returns a `(width, height)` record. Subclasses override to suit
  /// their natural aspect ratio.
  (double, double) get defaultSize => (160, 100);

  /// Minimum size (in logical pixels) below which the user cannot
  /// shrink an instance of this widget. The resize handles in
  /// [DraggableResizableInstance] enforce this floor.
  ///
  /// The default keeps the widget legible with a small label and a
  /// visible primitive. Boards and primitives whose visual content
  /// degrades faster (toggle switches collapse vertically, the
  /// seven-segment digit needs height for its segments) override this
  /// with their own intrinsic minimum.
  ///
  /// Returns a `(width, height)` record.
  (double, double) get minSize => (80, 60);

  /// Maximum size (in logical pixels) above which the user cannot
  /// grow an instance of this widget. Returns `null` (the default)
  /// when the widget has no intrinsic ceiling — the resize handles
  /// allow unbounded growth.
  ///
  /// Used by the Stage panel's resize handles to clamp the upper
  /// bound. Widgets whose visualization saturates beyond a certain
  /// size (a 7-segment digit doesn't gain legibility past a point; a
  /// small status indicator looks awkward stretched to a quarter of
  /// the canvas) can return a finite ceiling here.
  ///
  /// Returns a `(width, height)` record or `null`.
  (double, double)? get maxSize => null;

  /// License tier required to instantiate this widget. The picker
  /// dialog renders a [FeatureTierBadge] next to entries whose tier is above
  /// [LicenseTier.openCore], and routes activation through
  /// `FeatureGate.isAvailable` (which short-circuits to allow during
  /// the public-beta period and otherwise denies activation with an
  /// upgrade prompt).
  ///
  /// Defaults to [LicenseTier.openCore] — every existing built-in
  /// primitive and educational FPGA board widget continues to render
  /// without a badge. Pro and Enterprise widgets contributed via
  /// `extraStageWidgetsProvider` (or via custom `.wcrux-widget`
  /// bundles) override this with their required tier so the picker
  /// can surface the correct badge and gate.
  ///
  /// EDU is not a per-widget required tier in itself — features
  /// available to EDU are also available to Pro, so EDU users
  /// satisfy any Pro-tier gate via [LicenseTier.featureEquivalent].
  LicenseTier get requiredTier => LicenseTier.openCore;

  /// Per-instance configuration parameters declared by this widget.
  /// The Stage bindings pane and the workspace-tile "Configure…"
  /// shortcut render a generic editor that reads this schema and
  /// binds it two-way against [StageInstance.configuration].
  ///
  /// Defaults to an empty list — most built-in primitives have no
  /// configurable params and the bindings pane simply omits the
  /// Configuration section. Widgets with configurable behavior (the
  /// Pro pack's audio waveform, framebuffer, character LCD, OLED, …)
  /// declare their schema here.
  ///
  /// See [ConfigParam] for the param shape and the constraints on
  /// stored values (scalars only — JSON-natural). Widgets that need
  /// bespoke editing UI (palette tables, layout grids) can return an
  /// empty schema and supply a custom editor through their renderer
  /// instead — see ARCHITECTURE.md §10 (Pro Overlay Seams).
  List<ConfigParam> get configParams => const [];

  /// Optional named groups for the [configParams] above. The editor
  /// renders one section header per group and packs every param whose
  /// [ConfigParam.groupId] matches the group's [ConfigParamGroup.id]
  /// underneath. Render order is the declaration order of this list;
  /// any params without a `groupId` render at the top of the editor
  /// before the first group header.
  List<ConfigParamGroup> get configGroups => const [];
}
