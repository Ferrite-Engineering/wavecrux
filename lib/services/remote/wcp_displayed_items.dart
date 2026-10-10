// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The WCP view of what a tab displays, extracted from
// remote_control_notifier.dart: the item registry that gives each displayed
// row and marker its integer id, and the colour names `set_item_color`
// accepts. A part file, so the members stay private to the notifier that
// owns them.

part of 'remote_control_notifier.dart';

// ── Private registry helpers ──────────────────────────────────────────────────

/// Item type labels reported by `get_item_info`, matching the upstream WCP
/// reference implementation's capitalization.
const String _kTypeVariable = 'Variable';
const String _kTypeMarker = 'Marker';

/// Registry key prefix for marker items.
const String _kMarkerRefPrefix = 'marker:';

/// Colour names `set_item_color` accepts besides hex, keyed lower case: the
/// CSS basic colours plus the other everyday names WCP clients send.
const Map<String, int> _kNamedColors = {
  'black': 0xFF000000,
  'white': 0xFFFFFFFF,
  'gray': 0xFF808080,
  'grey': 0xFF808080,
  'silver': 0xFFC0C0C0,
  'red': 0xFFFF0000,
  'maroon': 0xFF800000,
  'green': 0xFF00FF00,
  'lime': 0xFF00FF00,
  'olive': 0xFF808000,
  'blue': 0xFF0000FF,
  'navy': 0xFF000080,
  'yellow': 0xFFFFFF00,
  'orange': 0xFFFFA500,
  'purple': 0xFF800080,
  'violet': 0xFFEE82EE,
  'pink': 0xFFFFC0CB,
  'magenta': 0xFFFF00FF,
  'fuchsia': 0xFFFF00FF,
  'cyan': 0xFF00FFFF,
  'aqua': 0xFF00FFFF,
  'teal': 0xFF008080,
  'brown': 0xFFA52A2A,
};

class _WcpItem {
  const _WcpItem({
    required this.id,
    required this.name,
    required this.path,
    required this.key,
    required this.type,
  });

  final int id;
  final String name;
  final String path;

  /// What this item is in the tab: a variable's [SignalEntry.id], so each
  /// displayed row is its own item even when one signal is shown twice, or
  /// `marker:<letter>` for a marker.
  final String key;

  /// [_kTypeVariable] or [_kTypeMarker].
  final String type;
}

/// Assigns stable monotonic integer IDs to all displayed items visible over
/// WCP (`DisplayedItemRef` in the upstream spec), one per displayed row. IDs
/// are never reused: an item that is removed and re-added receives a fresh
/// id.
class _DisplayedItemRegistry {
  int _nextId = 1;
  final Map<int, _WcpItem> _byId = {};
  final Map<String, int> _byKey = {};

  _WcpItem register(
    String key,
    String name,
    String path, {
    required String type,
  }) {
    final existingId = _byKey[key];
    if (existingId != null) return _byId[existingId]!;
    final id = _nextId++;
    final item = _WcpItem(
      id: id,
      name: name,
      path: path,
      key: key,
      type: type,
    );
    _byId[id] = item;
    _byKey[key] = id;
    return item;
  }

  _WcpItem? byId(int id) => _byId[id];

  int? idFor(String key) => _byKey[key];

  bool remove(int id) {
    final item = _byId.remove(id);
    if (item == null) return false;
    _byKey.remove(item.key);
    return true;
  }

  List<_WcpItem> get allItems => List.unmodifiable(_byId.values);

  void clear() {
    _byId.clear();
    _byKey.clear();
  }
}
