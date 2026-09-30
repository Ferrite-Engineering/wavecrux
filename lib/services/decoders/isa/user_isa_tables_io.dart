// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/services/decoders/isa/instruction_set.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/decoders/isa/isa_decoder_assets.dart';

/// A directory the user named and the loader refused. `developer.log` emits
/// nothing from a release build, so this goes to the product log.
final _log = Logger('wavecrux.decoders.isa');

/// Loads every `*.toml` in the user's ISA table directories.
///
/// Directory precedence is [kIsaTablePathEnvVar] first, then the
/// user-configured [directories]. Relative paths are dropped with a logged
/// warning rather than resolved against the working directory — the same rule
/// `PluginDirectoryResolver` applies, and for the same reason: what a relative
/// path means depends on how the app was launched, which is not something a
/// user can reason about from a settings field.
///
/// A directory that does not exist is skipped silently. A *file* that fails to
/// parse is reported: the table is there, the author meant it to work, and
/// saying nothing would leave them staring at a decoder that ignores it.
Future<UserIsaTableLoadResult> loadUserIsaTables({
  required List<String> directories,
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  final separator = Platform.isWindows ? ';' : ':';

  final candidates = <String>[];
  final raw = env[kIsaTablePathEnvVar];
  if (raw != null && raw.isNotEmpty) {
    for (final entry in raw.split(separator)) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) continue;
      if (!p.isAbsolute(trimmed)) {
        _log.warning(
          'ignoring relative path "$trimmed" in $kIsaTablePathEnvVar (only '
          'absolute paths are allowed)',
        );
        continue;
      }
      candidates.add(p.normalize(trimmed));
    }
  }
  for (final entry in directories) {
    final trimmed = entry.trim();
    if (trimmed.isEmpty) continue;
    if (!p.isAbsolute(trimmed)) {
      _log.warning(
        'ignoring relative ISA table directory "$trimmed" (only absolute '
        'paths are allowed)',
      );
      continue;
    }
    candidates.add(p.normalize(trimmed));
  }

  final seen = <String>{};
  final scanned = <String>[];
  final sets = <String, InstructionSet>{};
  final issues = <IsaTableLoadIssue>[];

  for (final dir in candidates) {
    if (!seen.add(Platform.isLinux ? dir : dir.toLowerCase())) continue;
    final directory = Directory(dir);
    if (!directory.existsSync()) continue;
    scanned.add(dir);

    final files =
        directory
            .listSync(followLinks: false)
            .whereType<File>()
            .where((f) => p.extension(f.path).toLowerCase() == '.toml')
            .toList()
          // Deterministic order so two machines with the same directory load
          // the same way. Discovery order from the filesystem is not stable.
          ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    for (final file in files) {
      final label = p.basename(file.path);
      try {
        final parsed = parseInstructionSetToml(
          file.readAsStringSync(),
          sourceLabel: label,
        );
        // Key on the file's base name, not the `set` field: two tables that
        // happen to declare the same `set` label must not silently collapse
        // into one, and the file name is what the author can actually see and
        // change.
        final name = p.basenameWithoutExtension(file.path);
        sets[name] = parsed;
      } on Object catch (e) {
        issues.add(
          IsaTableLoadIssue(name: label, source: file.path, message: '$e'),
        );
      }
    }
  }

  return UserIsaTableLoadResult(
    sets: sets,
    issues: issues,
    scannedDirectories: scanned,
  );
}
