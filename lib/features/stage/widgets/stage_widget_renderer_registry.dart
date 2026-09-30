// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';

/// Builds a Flutter widget that renders a [StageInstance] in a Stage panel.
///
/// Built-in renderers register a builder under the same `widgetId` that the
/// corresponding [StageWidget] definition uses, so the panel can look up the
/// renderer via [StageWidgetRendererRegistry.get] when laying out tiles.
typedef StageInstanceRenderer =
    Widget Function(
      BuildContext context,
      StageInstance instance,
    );

/// Global registry mapping `widgetId` → Flutter renderer for Stage widgets.
///
/// The renderer registry is intentionally separate from [StageRegistry]
/// because the [StageWidget] definitions live in the domain layer (no
/// Flutter imports), while renderers are feature-layer Flutter widgets.
///
/// Usage:
/// ```dart
/// StageWidgetRendererRegistry.instance
///     .register('led', (context, instance) => LedStageRenderer(instance: instance));
/// ```
class StageWidgetRendererRegistry {
  StageWidgetRendererRegistry._();

  static final StageWidgetRendererRegistry instance =
      StageWidgetRendererRegistry._();

  final Map<String, StageInstanceRenderer> _renderers = {};

  /// Registers [renderer] for [widgetId]. Replaces any existing entry.
  void register(String widgetId, StageInstanceRenderer renderer) {
    _renderers[widgetId] = renderer;
  }

  /// Removes the renderer registered for [widgetId], if any. No-op when no
  /// renderer is registered.
  ///
  /// The symmetric counterpart of [register], used when a dynamically-loaded
  /// renderer (e.g. a community `.wcrux-widget` bundle) is unloaded or
  /// replaced so the panel stops painting a stale artboard.
  void unregister(String widgetId) {
    _renderers.remove(widgetId);
  }

  /// Returns the renderer for [widgetId] or null when none is registered.
  StageInstanceRenderer? get(String widgetId) => _renderers[widgetId];

  /// True when a renderer is registered for [widgetId].
  bool isRegistered(String widgetId) => _renderers.containsKey(widgetId);

  /// Removes every registration. Test-only.
  void clear() {
    _renderers.clear();
  }
}
