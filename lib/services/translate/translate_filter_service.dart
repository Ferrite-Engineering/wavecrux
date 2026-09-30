// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A parsed GTKWave translate filter: maps integer signal values to
/// human-readable labels.
///
/// The filter file format is one entry per line:
/// ```text
/// # Comment
/// 0   IDLE
/// 1   RUNNING
/// 255 ERROR
/// 0x1f  OVERFLOW
/// ```
///
/// Values are matched by converting the raw bit-string to an unsigned integer
/// and looking it up in the filter map.
@immutable
class TranslateFilter {
  const TranslateFilter(this._map);

  final Map<BigInt, String> _map;

  /// Returns the translated label for [rawBitString], or `null` if no entry
  /// exists or the value contains indeterminate bits (x/z).
  String? translate(String rawBitString) {
    if (rawBitString.contains('x') || rawBitString.contains('z')) return null;
    final value = BigInt.tryParse(rawBitString, radix: 2);
    if (value == null) return null;
    return _map[value];
  }

  /// Total number of entries in this filter.
  int get length => _map.length;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TranslateFilter) return false;
    if (_map.length != other._map.length) return false;
    for (final entry in _map.entries) {
      if (other._map[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hashAll(_map.entries.map((e) => Object.hash(e.key, e.value)));
}

/// Parses GTKWave `.txt` translate filter files and applies them to raw
/// signal values.
///
/// GTKWave translate filter files map integer signal values to label strings.
/// Each non-comment line has the form `value label`, where value is a decimal
/// or hex (0x prefix) integer. Labels may contain spaces.
class TranslateFilterService {
  const TranslateFilterService();

  /// Parses [content] (the text content of a `.txt` translate filter file)
  /// into a [TranslateFilter].
  ///
  /// Lines are ignored if they are empty or start with `#` or `//`.
  /// Values may be decimal integers or hex integers with a `0x`/`0X` prefix.
  TranslateFilter parse(String content) {
    final map = <BigInt, String>{};

    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith('//')) {
        continue;
      }

      // Split on first run of whitespace.
      final spaceIdx = trimmed.indexOf(RegExp(r'\s'));
      if (spaceIdx == -1) continue; // no label — skip

      final keyStr = trimmed.substring(0, spaceIdx);
      final label = trimmed.substring(spaceIdx).trim();
      if (label.isEmpty) continue;

      final key = _parseIntKey(keyStr);
      if (key != null) map[key] = label;
    }

    return TranslateFilter(map);
  }

  /// Applies [filter] to [rawBitString], returning the translated label if one
  /// exists, or [rawBitString] unchanged if no match is found.
  String translateOrRaw(String rawBitString, TranslateFilter filter) {
    return filter.translate(rawBitString) ?? rawBitString;
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  BigInt? _parseIntKey(String s) {
    final lower = s.toLowerCase();
    if (lower.startsWith('0x')) {
      return BigInt.tryParse(lower.substring(2), radix: 16);
    }
    if (lower.startsWith('0b')) {
      return BigInt.tryParse(lower.substring(2), radix: 2);
    }
    return BigInt.tryParse(s);
  }
}
