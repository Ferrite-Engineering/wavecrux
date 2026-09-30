// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:collection';

import 'package:wavecrux/domain/interfaces/custom_stage_widget_registry.dart';

/// Real implementation of [CustomStageWidgetRegistry] used by the Pro
/// overlay's `customStageWidgetRegistryProvider` override.
///
/// The Stage widget SDK's bundle loader (`bundle/`) calls [register] /
/// [unregister] as bundles are installed, removed, or hot-reloaded; the
/// open-core picker dialog and any other consumer reads [descriptors] /
/// [get] to surface contributed widgets alongside the built-in
/// `StageRegistry` entries.
///
/// **Concurrency.** Bundle loading runs on background isolates for I/O
/// (archive extraction, asset decoding), but Dart isolates do not share
/// memory — descriptors travel back to the main isolate via SendPort
/// messages and are then registered there. The internal map therefore
/// only ever sees calls from the main isolate, and a plain `Map` suffices
/// without explicit locking. The class is documented as thread-safe in
/// that sense: callers may dispatch register / unregister from any
/// isolate, but the contract is "marshal back to the main isolate before
/// invoking" — the isolate boundary itself is the synchronization
/// primitive.
///
/// [descriptors] returns an unmodifiable view backed by the live map; the
/// view tracks subsequent register / unregister calls without copying the
/// snapshot. This matches Riverpod's expectation that downstream watchers
/// observe the latest registrations on the next provider read after a
/// mutation.
class LiveCustomStageWidgetRegistry implements CustomStageWidgetRegistry {
  /// Creates an empty registry. The Pro overlay's `proOverrides` constructs
  /// one of these via `Provider.overrideWithValue`, so the same instance is
  /// shared by every consumer of `customStageWidgetRegistryProvider`.
  LiveCustomStageWidgetRegistry();

  final Map<String, CustomStageWidgetDescriptor> _byId =
      <String, CustomStageWidgetDescriptor>{};

  @override
  void register(CustomStageWidgetDescriptor descriptor) {
    _byId[descriptor.id] = descriptor;
  }

  @override
  void unregister(String id) {
    _byId.remove(id);
  }

  @override
  CustomStageWidgetDescriptor? get(String id) => _byId[id];

  @override
  Iterable<CustomStageWidgetDescriptor> get descriptors =>
      UnmodifiableListView(_byId.values);
}
