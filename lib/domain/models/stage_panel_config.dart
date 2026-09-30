// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';

/// One Stage panel — a named tab containing zero or more [StageInstance]s.
///
/// Users create multiple panels to organise widgets by purpose
/// (e.g. `"ECU Dashboard"`, `"SPI Bus Monitor"`). The Stage workspace is
/// a list of [StagePanelConfig]s plus an `activePanelId`.
///
/// Pure Dart — no Flutter imports.
@immutable
class StagePanelConfig {
  const StagePanelConfig({
    required this.id,
    required this.name,
    this.instances = const [],
  });

  /// Unique id within the workspace. Stable across save/load.
  final String id;

  /// User-visible panel name. Editable through the panel header.
  final String name;

  /// Ordered list of widget instances on this panel.
  final List<StageInstance> instances;

  StagePanelConfig copyWith({
    String? id,
    String? name,
    List<StageInstance>? instances,
  }) => StagePanelConfig(
    id: id ?? this.id,
    name: name ?? this.name,
    instances: instances ?? this.instances,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! StagePanelConfig) return false;
    if (id != other.id) return false;
    if (name != other.name) return false;
    if (instances.length != other.instances.length) return false;
    for (var i = 0; i < instances.length; i++) {
      if (instances[i] != other.instances[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(instances));

  @override
  String toString() =>
      'StagePanelConfig(id: $id, name: $name, instances: ${instances.length})';
}
