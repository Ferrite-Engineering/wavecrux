// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/services/rohd/rohd_sidecar.dart';
import 'package:wavecrux/services/rohd/rohd_wave_map.dart';

final Logger _log = Logger('wavecrux.rohd');

/// Finds and reads the ROHD source-trace sidecar for an open waveform.
///
/// Where it looks, in order:
///
/// 1. the path in Settings > Editors (a `.flc.json` file, or a folder holding
///    some), when one is set;
/// 2. `<waveform name>.flc.json` beside the waveform;
/// 3. every `*.flc.json` beside the waveform, by name.
///
/// Of the readable candidates the first that describes one of
/// [topScopes] wins, so a folder holding the sidecars of several designs gives
/// each waveform its own; when none does, the first readable one is used. A
/// sidecar that cannot be read, or has a version other than 6, is logged once
/// and skipped. **Never throws**: no sidecar is a `null`.
Future<RohdWaveMap?> loadRohdWaveMap({
  required String waveformPath,
  String configured = '',
  Set<String> topScopes = const <String>{},
}) async {
  final dir = p.dirname(waveformPath);
  final stem = p.basenameWithoutExtension(waveformPath);
  final candidates = <String>[
    ..._configured(configured),
    p.join(dir, '$stem.flc.json'),
    ..._flcIn(dir),
  ];

  final seen = <String>{};
  RohdWaveMap? first;
  for (final path in candidates) {
    // Case-folded: `top.flc.json` and `Top.flc.json` are one file on macOS and
    // Windows, and must not be read, or warned about, twice.
    if (!seen.add(p.normalize(path).toLowerCase())) continue;
    final RohdSidecar? sidecar;
    try {
      final file = File(path);
      if (!file.existsSync()) continue;
      final result = parseRohdSidecar(await file.readAsString());
      sidecar = result.sidecar;
      if (sidecar == null) {
        _log.warning(
          'The ROHD source-trace file $path was not used: ${result.problem}.',
        );
        continue;
      }
    } on Object {
      _log.warning('The ROHD source-trace file $path could not be read.');
      continue;
    }
    final resolver = _DartPathResolver(
      packageRoot: sidecar.packageRoot,
      sidecarDir: p.dirname(path),
      waveformDir: dir,
    );
    final map = RohdWaveMap.fromSidecar(sidecar, resolveFile: resolver.resolve);
    if (topScopes.isEmpty || topScopes.any(map.knowsPath)) return map;
    first ??= map;
  }
  return first;
}

List<String> _configured(String configured) {
  final value = configured.trim();
  if (value.isEmpty) return const <String>[];
  return FileSystemEntity.isDirectorySync(value) ? _flcIn(value) : [value];
}

List<String> _flcIn(String dir) {
  try {
    return <String>[
      for (final e in Directory(dir).listSync(followLinks: false))
        if (e is File && e.path.toLowerCase().endsWith('.flc.json')) e.path,
    ]..sort();
  } on Object {
    return const <String>[];
  }
}

/// Finds the Dart file a sidecar names on this machine.
///
/// A path in a sidecar is relative to the Dart package that generated it
/// (`.dart_tool/../lib/design.dart`), and that package is not necessarily
/// where the files now are. The package root is tried in this order, taking
/// the first that holds the file: the `packageRoot` the sidecar recorded, each
/// folder above the sidecar, each above the waveform. If none holds it, the
/// nearest of those with a `pubspec.yaml` is used, so the answer is still a
/// usable path; failing that, the sidecar's own folder.
class _DartPathResolver {
  _DartPathResolver({
    required this.packageRoot,
    required this.sidecarDir,
    required this.waveformDir,
  });

  final String? packageRoot;
  final String sidecarDir;
  final String waveformDir;

  String resolve(String raw) {
    final normalized = p.posix.normalize(raw.replaceAll(r'\', '/'));
    if (p.isAbsolute(normalized)) return p.normalize(normalized);
    final roots = <String>[
      ?packageRoot,
      ..._ancestors(sidecarDir),
      ..._ancestors(waveformDir),
    ];
    for (final root in roots) {
      final candidate = p.normalize(p.join(root, normalized));
      if (File(candidate).existsSync()) return candidate;
    }
    for (final root in roots) {
      if (File(p.join(root, 'pubspec.yaml')).existsSync()) {
        return p.normalize(p.join(root, normalized));
      }
    }
    return p.normalize(p.join(sidecarDir, normalized));
  }

  static List<String> _ancestors(String dir) {
    final out = <String>[];
    var current = p.absolute(dir);
    for (var i = 0; i < 8; i++) {
      out.add(current);
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }
    return out;
  }
}
