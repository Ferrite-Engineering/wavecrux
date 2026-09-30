// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Immutable snapshot of all named markers in the waveform viewport.
///
/// Markers are identified by a single lowercase letter (`a`–`z`), matching
/// GTKWave's named-marker convention. Each marker stores a simulation tick.
@immutable
class MarkerState {
  const MarkerState({Map<String, int>? markers})
    : markers = markers ?? const {};

  /// Map from marker name (single char `a`–`z`) to simulation tick.
  final Map<String, int> markers;

  /// Returns a new state with marker [name] placed at [time].
  ///
  /// [name] must be a single character in the range `a`–`z`. Setting a marker
  /// that already exists overwrites the previous position.
  MarkerState setMarker(String name, int time) {
    assert(
      name.length == 1 &&
          name.codeUnitAt(0) >= 0x61 &&
          name.codeUnitAt(0) <= 0x7A,
      'Marker name must be a single lowercase letter a–z, got "$name"',
    );
    return MarkerState(markers: {...markers, name: time});
  }

  /// Returns a new state with marker [name] removed.
  ///
  /// Returns [this] unchanged if [name] is not set.
  MarkerState removeMarker(String name) {
    if (!markers.containsKey(name)) return this;
    final updated = Map<String, int>.from(markers)..remove(name);
    return MarkerState(markers: Map.unmodifiable(updated));
  }

  /// The simulation tick of marker [name], or null if not set.
  int? getMarker(String name) => markers[name];

  /// All markers sorted by name (alphabetical).
  List<MapEntry<String, int>> getAllMarkers() {
    final entries = markers.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  /// Returns a copy with [markers] replaced.
  MarkerState copyWith({Map<String, int>? markers}) =>
      MarkerState(markers: markers ?? this.markers);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerState &&
          runtimeType == other.runtimeType &&
          _mapsEqual(markers, other.markers);

  @override
  int get hashCode => Object.hashAll(
    markers.entries.map((e) => Object.hash(e.key, e.value)),
  );

  @override
  String toString() => 'MarkerState(markers: $markers)';

  static bool _mapsEqual(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
