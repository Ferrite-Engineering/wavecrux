// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/interfaces/custom_stage_widget_registry.dart';
import 'package:wavecrux/features/stage/runtime/live_custom_stage_widget_registry.dart';

/// Open-core extension-point provider that exposes the runtime
/// [CustomStageWidgetRegistry] used by the Stage widget SDK's bundle loader
/// to contribute `.wcrux-widget` custom-widget registrations into the
/// picker.
///
/// The open-core default returns a fresh, mutable
/// [LiveCustomStageWidgetRegistry] — the registry is part of the
/// open-core platform (the capability to build and load custom Stage
/// widgets is free; only the curated Pro widget pack lives in the
/// closed-source Pro overlay — see ARCHITECTURE §10).
///
/// Overlay builds (e.g. the Pro overlay running with `proOverrides`) and
/// tests may still override this provider to substitute a fake or to
/// pre-populate the registry; the open-core default is the production
/// implementation rather than a no-op stub.
///
/// Picker UI watches this provider and merges its
/// [CustomStageWidgetRegistry.descriptors] iterable with the built-in
/// widgets sourced from `StageRegistry.instance` —
/// ARCHITECTURE.md §10 (Extension Points).
final customStageWidgetRegistryProvider = Provider<CustomStageWidgetRegistry>((
  _,
) {
  return LiveCustomStageWidgetRegistry();
});
