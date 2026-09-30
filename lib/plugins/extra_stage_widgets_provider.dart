// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_renderer_registry.dart';

/// One additional Stage-widget registration contributed by an overlay build
/// (typically the closed-source Pro overlay registering curated
/// Pro-pack widgets such as the framebuffer, audio waveform, and other
/// advanced peripheral primitives).
///
/// Each registration carries both the pure-Dart [StageWidget] definition
/// (registered into [StageRegistry]) and the Flutter [StageInstanceRenderer]
/// that draws an instance in the panel (registered into
/// [StageWidgetRendererRegistry]). The two halves live in different layers —
/// the definition is domain-only, the renderer is Flutter — and overlay code
/// must contribute both at once for a widget to be usable, so this typedef
/// pairs them.
typedef ExtraStageWidgetRegistration = ({
  StageWidget definition,
  StageInstanceRenderer renderer,
});

/// Open-core extension point through which the Pro/Enterprise overlay
/// contributes additional built-in Stage widgets without forking
/// [StageRegistry], [StageWidgetRendererRegistry], or `bootstrap`.
///
/// The open-core default returns an empty list — `bootstrap` registers the
/// open-core primitives (LED, seven-segment, level bar, etc.) and educational
/// FPGA board widgets directly via [registerBuiltinStageWidgets], and the
/// overlay's `proOverrides` replaces this provider with one that returns the
/// curated Pro pack registrations. `WaveCruxApp.initState` reads the active
/// provider once at app startup and registers each contributed widget into
/// both [StageRegistry.instance] and [StageWidgetRendererRegistry.instance].
///
/// This mirrors the [`extraDecodersProvider`] pattern: the open-core picker
/// surfaces every registered widget and routes activation through
/// `FeatureGate.isAvailable`, so Pro widgets pick up tier badging via the
/// same channel that gates everything else. See ARCHITECTURE.md §10
/// (Extension Points).
final extraStageWidgetsProvider = Provider<List<ExtraStageWidgetRegistration>>(
  (_) => const [],
);
