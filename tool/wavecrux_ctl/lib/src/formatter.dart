// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

/// Formats WCP response data maps into human-readable CLI output.
class Formatter {
  const Formatter._();

  /// Formats a `wavecrux.getState` response data map.
  static String formatState(Map<String, dynamic> result) {
    final file = result['file'] as String?;
    final isLoaded = result['is_loaded'] as bool? ?? false;
    final cursor = result['cursor'];
    final secondary = result['secondary_cursor'];
    final tpp = result['ticks_per_pixel'];
    final signalCount = result['signal_count'] as int? ?? 0;

    final sb = StringBuffer()
      ..writeln('File:      ${file ?? '(none)'}')
      ..writeln('Loaded:    $isLoaded')
      ..writeln('Cursor:    ${cursor != null ? '$cursor ticks' : '(none)'}');
    if (secondary != null) sb.writeln('Cursor 2:  $secondary ticks');
    sb
      ..writeln(
        'Zoom:      ${tpp != null ? (tpp as num).toStringAsFixed(4) : '?'}'
        ' ticks/px',
      )
      ..write('Signals:   $signalCount');
    return sb.toString();
  }

  /// Formats a `get_item_list` response data map.
  static String formatItems(Map<String, dynamic> result) {
    final items = result['items'] as List<dynamic>? ?? [];
    if (items.isEmpty) return '(no signals displayed)';

    const idWidth = 4;
    final sb = StringBuffer()..writeln('${'ID'.padLeft(idWidth)}  PATH');
    for (final i in items) {
      final item = i as Map<String, dynamic>;
      final id = (item['id'] as int? ?? 0).toString().padLeft(idWidth);
      final path = item['path'] as String? ?? '';
      sb.writeln('$id  $path');
    }
    return sb.toString().trimRight();
  }

  /// Formats a `wavecrux.getHierarchy` response data map as a tree.
  static String formatHierarchy(Map<String, dynamic> result) {
    final scopes = result['scopes'] as List<dynamic>? ?? [];
    if (scopes.isEmpty) return '(no hierarchy — is a file loaded?)';

    final sb = StringBuffer();
    for (var i = 0; i < scopes.length; i++) {
      _printScope(
        sb,
        scopes[i] as Map<String, dynamic>,
        '',
        i == scopes.length - 1,
      );
    }
    return sb.toString().trimRight();
  }

  static void _printScope(
    StringBuffer sb,
    Map<String, dynamic> scope,
    String prefix,
    bool isLast,
  ) {
    final connector = isLast ? '└── ' : '├── ';
    final extension = isLast ? '    ' : '│   ';
    final name = scope['name'] as String? ?? '';
    final type = scope['type'] as String? ?? '';
    sb.writeln('$prefix$connector$name ($type)');

    final variables = scope['variables'] as List<dynamic>? ?? [];
    final children = scope['children'] as List<dynamic>? ?? [];
    final total = variables.length + children.length;
    var index = 0;

    for (final v in variables) {
      final vConn = index == total - 1 ? '└── ' : '├── ';
      final variable = v as Map<String, dynamic>;
      final vName = variable['name'] as String? ?? '';
      final vType = variable['var_type'] as String? ?? '';
      final width = variable['bit_width'] as int?;
      final widthStr = width != null ? ', ${width}b' : '';
      sb.writeln('$prefix$extension$vConn$vName [$vType$widthStr]');
      index++;
    }
    for (var i = 0; i < children.length; i++) {
      _printScope(
        sb,
        children[i] as Map<String, dynamic>,
        '$prefix$extension',
        index == total - 1,
      );
      index++;
    }
  }

  /// Formats a `wavecrux.getValueAt` response data map.
  static String formatValue(Map<String, dynamic> result) {
    final path = result['signal_path'] as String? ?? '';
    final time = result['time'];
    final value = result['value'] as String? ?? '(null)';
    return '$path @ tick $time: $value';
  }

  /// Returns the raw JSON of [result], for use with --json.
  static String rawJson(Map<String, dynamic> result) => jsonEncode(result);
}
