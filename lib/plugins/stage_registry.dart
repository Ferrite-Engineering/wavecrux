// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';

/// Global registry for [StageWidget] definitions.
///
/// Built-in widgets register themselves at app startup; user- or vendor-
/// supplied widgets register when their bundles are loaded. The Stage UI
/// queries the registry to populate the Add-Widget picker and to look up
/// the renderer for each [StageInstance.widgetId] at draw time.
///
/// Usage:
/// ```dart
/// StageRegistry.instance.register(const LedStageWidget());
/// ```
///
/// The registry is intentionally a global singleton — the same pattern as
/// [DecoderRegistry] — so built-in widgets can register from a top-level
/// initialiser without threading the instance through the widget tree.
class StageRegistry {
  StageRegistry._();

  static final StageRegistry instance = StageRegistry._();

  final Map<String, StageWidget> _widgets = {};
  final Set<String> _userSuppliedIds = {};

  /// Registers [widget] under its [StageWidget.id]. Replaces any existing
  /// entry with the same id.
  ///
  /// [userSupplied] marks a definition whose id was authored outside this
  /// codebase — a community `.wcrux-widget` bundle. Built-in and Pro-pack
  /// families are ours in both repos; a bundle's reverse-DNS id is its
  /// author's. See [isUserSupplied].
  void register(StageWidget widget, {bool userSupplied = false}) {
    _widgets[widget.id] = widget;
    if (userSupplied) {
      _userSuppliedIds.add(widget.id);
    } else {
      _userSuppliedIds.remove(widget.id);
    }
  }

  /// Whether [id] came from a community bundle rather than the built-in or
  /// Pro-pack widget families.
  ///
  /// Recorded at registration because nothing about the id itself is
  /// decisive: the open-core Tachometer is `wavecrux.pro.tachometer` (a
  /// leftover from its tier flip) while the shipped Rive bundle manifest
  /// declares `com.wavecrux.pro.stage.tachometer`, so neither the `pro`
  /// segment nor the dot count separates ours from theirs. Telemetry uses
  /// this to decide between the family token and a fixed sentinel; an
  /// unregistered id counts as user-supplied.
  bool isUserSupplied(String id) =>
      _userSuppliedIds.contains(id) || !_widgets.containsKey(id);

  /// Removes the registration for [id], if present. No-op when [id] is not
  /// registered.
  ///
  /// Used when a dynamically-loaded definition (e.g. a community
  /// `.wcrux-widget` bundle) is unloaded, replaced, or its watched
  /// directory is removed — the symmetric counterpart of [register] so the
  /// picker and renderer-resolution path stop surfacing a stale widget.
  void unregister(String id) {
    _widgets.remove(id);
    _userSuppliedIds.remove(id);
  }

  /// Returns the widget definition for [id], or null if not registered.
  StageWidget? get(String id) => _widgets[id];

  /// True when a widget with [id] is currently registered.
  bool isRegistered(String id) => _widgets.containsKey(id);

  /// Returns every registered widget, sorted alphabetically by display
  /// name. Used to populate the Add-Widget picker.
  List<StageWidget> listAll() {
    final list = _widgets.values.toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return list;
  }

  /// Returns every registered widget in [category], sorted by display
  /// name.
  List<StageWidget> listByCategory(StageWidgetCategory category) {
    final list = _widgets.values.where((w) => w.category == category).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    return list;
  }

  /// Removes every registration. Intended for use in tests only.
  void clear() {
    _widgets.clear();
    _userSuppliedIds.clear();
  }
}
