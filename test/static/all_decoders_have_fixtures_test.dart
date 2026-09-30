// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Guardrail: every decoder shipped in lib/services/decoders/ must have a
// matching fixture directory under test/fixtures/protocol/ with at least
// one fixture in generated/. Catches the failure mode "added a decoder
// without adding fixtures" — the snapshot sweep can't catch that on its
// own because an empty directory passes trivially.
//
// The decoder name is derived from the source filename: lib/services/
// decoders/<name>_decoder.dart → test/fixtures/protocol/<name>/. Decoders
// in subdirectories follow the same rule (riscv/, spi_flash/, …).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Decoder names we know about that live in subdirectories rather than
/// directly under lib/services/decoders/. Each entry maps the file
/// basename (without `_decoder.dart`) to the fixture-dir name.
const _subdirDecoders = <String, String>{
  'riscv': 'riscv',
  'spi_flash': 'spi_flash',
};

/// Source files under lib/services/decoders/ that are NOT decoder
/// implementations and should be skipped.
const _nonDecoderFiles = <String>{
  'decoder_auto_bind_service.dart',
  // Abstract base for the instruction-trace decoders (RISC-V in open core;
  // MicroBlaze and LM32 in the Pro pack). It registers no decoder id and
  // decodes no trace of its own, so it has nothing to hold a fixture for —
  // its subclasses carry theirs.
  'isa_trace_decoder.dart',
};

void main() {
  test(
    'every decoder in lib/services/decoders/ has fixtures in generated/',
    () {
      final decoderNames = _discoverDecoderNames();
      expect(decoderNames, isNotEmpty, reason: 'no decoders found');

      final missing = <String>[];
      for (final name in decoderNames) {
        final generated = Directory('test/fixtures/protocol/$name/generated');
        if (!generated.existsSync()) {
          missing.add('$name: missing test/fixtures/protocol/$name/generated/');
          continue;
        }
        final vcds = generated.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.vcd') || f.path.endsWith('.fst'),
        );
        if (vcds.isEmpty) {
          missing.add(
            '$name: test/fixtures/protocol/$name/generated/ is empty',
          );
        }
      }

      expect(
        missing,
        isEmpty,
        reason:
            'decoders without fixtures — every decoder MUST have at '
            'least one generated/ fixture:\n  ${missing.join('\n  ')}',
      );
    },
  );
}

Set<String> _discoverDecoderNames() {
  final names = <String>{};
  final root = Directory('lib/services/decoders');
  if (!root.existsSync()) return names;
  _walk(root, names);
  return names;
}

void _walk(Directory dir, Set<String> names) {
  for (final entity in dir.listSync()) {
    if (entity is Directory) {
      // Skip ffi/ — that's the plugin loader, not a decoder.
      if (p.basename(entity.path) == 'ffi') continue;
      _walk(entity, names);
      continue;
    }
    if (entity is! File) continue;
    final basename = p.basename(entity.path);
    if (_nonDecoderFiles.contains(basename)) continue;
    if (!basename.endsWith('_decoder.dart')) continue;
    final stem = basename.substring(
      0,
      basename.length - '_decoder.dart'.length,
    );
    names.add(_subdirDecoders[stem] ?? stem);
  }
}
