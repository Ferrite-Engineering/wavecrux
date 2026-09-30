// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

/// Tiny block-style YAML emitter used by [StageWidgetManifest.toYaml].
///
/// `package:yaml` is read-only, and pulling in a dedicated YAML-writer
/// dependency for the few hundred lines of manifest output we need is
/// over-engineered. The output here is the canonical, round-trippable
/// shape — keys in their declared order, two-space indentation, scalar
/// types as YAML literals, strings quoted when they need it.
///
/// Only the subset of YAML this manifest module emits is supported:
/// maps with string keys, lists of maps / scalars, ints, doubles, bools,
/// and nulls. Pure data — no anchors, aliases, or tags.
String emitYaml(Object? root) {
  final buf = StringBuffer();
  _emit(buf, root, 0);
  return buf.toString();
}

void _emit(StringBuffer buf, Object? value, int indent) {
  if (value is Map) {
    _emitMap(buf, value, indent);
  } else if (value is List) {
    _emitList(buf, value, indent);
  } else {
    buf.writeln(_emitScalar(value));
  }
}

void _emitMap(StringBuffer buf, Map<dynamic, dynamic> map, int indent) {
  if (map.isEmpty) {
    buf.writeln('{}');
    return;
  }
  var first = true;
  final pad = ' ' * indent;
  for (final entry in map.entries) {
    final keyText = entry.key.toString();
    final value = entry.value;
    if (!first) {
      buf.write(pad);
    }
    first = false;
    if (value is Map && value.isNotEmpty) {
      buf
        ..write('$keyText:')
        ..writeln()
        ..write(' ' * (indent + 2));
      _emitMap(buf, value, indent + 2);
    } else if (value is List && value.isNotEmpty) {
      buf
        ..write('$keyText:')
        ..writeln();
      _emitListBody(buf, value, indent + 2);
    } else {
      buf.writeln('$keyText: ${_emitScalar(value)}');
    }
  }
}

void _emitList(StringBuffer buf, List<dynamic> list, int indent) {
  if (list.isEmpty) {
    buf.writeln('[]');
    return;
  }
  _emitListBody(buf, list, indent);
}

void _emitListBody(StringBuffer buf, List<dynamic> list, int indent) {
  final pad = ' ' * indent;
  for (final item in list) {
    if (item is Map && item.isNotEmpty) {
      // First key sits on the same line as the dash; subsequent keys
      // indent two further to align under the first.
      final entries = item.entries.toList();
      final firstEntry = entries.first;
      buf.write('$pad- ');
      final firstValue = firstEntry.value;
      if (firstValue is Map && firstValue.isNotEmpty) {
        buf
          ..write('${firstEntry.key}:')
          ..writeln()
          ..write(' ' * (indent + 4));
        _emitMap(buf, firstValue, indent + 4);
      } else if (firstValue is List && firstValue.isNotEmpty) {
        buf
          ..write('${firstEntry.key}:')
          ..writeln();
        _emitListBody(buf, firstValue, indent + 4);
      } else {
        buf.writeln('${firstEntry.key}: ${_emitScalar(firstValue)}');
      }
      for (var i = 1; i < entries.length; i++) {
        final e = entries[i];
        buf.write(' ' * (indent + 2));
        final v = e.value;
        if (v is Map && v.isNotEmpty) {
          buf
            ..write('${e.key}:')
            ..writeln()
            ..write(' ' * (indent + 4));
          _emitMap(buf, v, indent + 4);
        } else if (v is List && v.isNotEmpty) {
          buf
            ..write('${e.key}:')
            ..writeln();
          _emitListBody(buf, v, indent + 4);
        } else {
          buf.writeln('${e.key}: ${_emitScalar(v)}');
        }
      }
    } else {
      buf.writeln('$pad- ${_emitScalar(item)}');
    }
  }
}

String _emitScalar(Object? value) {
  if (value == null) return '~';
  if (value is bool) return value ? 'true' : 'false';
  if (value is int) return value.toString();
  if (value is double) {
    if (value.isFinite) return value.toString();
    if (value.isNaN) return '.nan';
    return value.isNegative ? '-.inf' : '.inf';
  }
  if (value is String) return _quoteString(value);
  return _quoteString(value.toString());
}

bool _needsQuoting(String value) {
  if (value.isEmpty) return true;
  // Reserved indicators / numeric look-alikes / special words.
  const reservedFirst = {
    '-',
    '?',
    ':',
    ',',
    '[',
    ']',
    '{',
    '}',
    '#',
    '&',
    '*',
    '!',
    '|',
    '>',
    "'",
    '"',
    '%',
    '@',
    '`',
  };
  if (reservedFirst.contains(value[0])) return true;
  if (value.contains(': ') || value.contains(' #')) return true;
  final lower = value.toLowerCase();
  if (lower == 'true' ||
      lower == 'false' ||
      lower == 'null' ||
      lower == 'yes' ||
      lower == 'no' ||
      lower == 'on' ||
      lower == 'off' ||
      lower == '~') {
    return true;
  }
  if (RegExp(r'^[+-]?\d').hasMatch(value)) return true;
  if (value.codeUnits.any((c) => c < 0x20 || c == 0x7f)) return true;
  return false;
}

String _quoteString(String value) {
  if (!_needsQuoting(value)) return value;
  // Use JSON encoding for the body — handles escapes and is a strict
  // subset of YAML's double-quoted style.
  return jsonEncode(value);
}
