// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/services/session/crux_project_resolution.dart';

/// WaveCrux's half of the `<design>.crux-project` contract: given a path that
/// might be a manifest (or a design directory holding one), produce the
/// waveform to open — or a message saying why there isn't one.
///
/// The shared package owns parsing and the design-id rule; this covers the
/// decisions that are WaveCrux's own, which are all about what the user is
/// told when there is nothing to open.
void main() {
  const resolver = CruxProjectResolver();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('wc_crux_project'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String writeManifest(
    String yaml, {
    String design = 'cdc_capture',
    String? fileName,
  }) {
    final dir = Directory(p.join(tmp.path, design))
      ..createSync(recursive: true);
    final path = p.join(dir.path, fileName ?? '$design.crux-project');
    File(path).writeAsStringSync(yaml);
    return path;
  }

  group('pass-through', () {
    test('an ordinary waveform path is untouched', () {
      final r = resolver.resolve('/traces/dump.vcd');
      expect(r, isA<NotAManifest>());
      expect((r as NotAManifest).path, '/traces/dump.vcd');
    });

    test('a file whose extension is not crux-project is not a manifest', () {
      expect(
        resolver.resolve(p.join(tmp.path, 'notes.crux-project.txt')),
        isA<NotAManifest>(),
      );
    });

    test('a URL is never read as a manifest', () {
      const url = 'https://ci.example.com/uart_tx.crux-project';
      expect(resolver.resolve(url), isA<NotAManifest>());
    });

    test('a directory with no manifest passes through unchanged', () {
      final r = resolver.resolve(tmp.path);
      expect(r, isA<NotAManifest>());
      expect((r as NotAManifest).path, tmp.path);
    });

    test('a non-existent named manifest is still a manifest attempt', () {
      // Named `<design>.crux-project`, so the user meant a manifest; the
      // failure must explain that rather than open it as a waveform.
      final r = resolver.resolve(p.join(tmp.path, 'my.crux-project'));
      expect(r, isA<ManifestUnusable>());
    });
  });

  group('resolution', () {
    test('names the waveform and carries the design id', () {
      final designDir = Directory(p.join(tmp.path, 'uart'))
        ..createSync(recursive: true);
      final sim = Directory(p.join(designDir.path, 'sim'))
        ..createSync(recursive: true);
      File(p.join(sim.path, 'uart.vcd')).writeAsStringSync('');
      final manifest = p.join(designDir.path, 'uart.crux-project');
      File(manifest).writeAsStringSync(
        'version: 1\nname: uart_tx\nartifacts:\n  waveform: sim/uart.vcd\n',
      );

      final r = resolver.resolve(manifest);
      expect(r, isA<ManifestWaveform>());
      final w = r as ManifestWaveform;
      expect(w.legacySuggestedFileName, isNull);
      expect(w.warnings, isEmpty);
      // p.join, not a POSIX literal: this is a host-resolved absolute path, so
      // on a Windows runner the tail legitimately uses backslashes.
      expect(w.waveformPath, endsWith(p.join('sim', 'uart.vcd')));
      expect(w.displayName, 'uart_tx');
      // The identity that makes cross-probe join: derived from the design
      // directory, not from the dump inside it.
      expect(w.designId, cxpDesignIdForPath(designDir.path));
    });

    test('the extension matches case-insensitively, as pickers do', () {
      final manifest = writeManifest(
        'version: 1\nartifacts:\n  waveform: d.vcd\n',
        fileName: 'SoC.CRUX-PROJECT',
      );
      File(p.join(p.dirname(manifest), 'd.vcd')).writeAsStringSync('');
      expect(resolver.resolve(manifest), isA<ManifestWaveform>());
    });

    test('a design directory opens the one manifest inside it', () {
      final manifest = writeManifest(
        'version: 1\nartifacts:\n  waveform: d.vcd\n',
        design: 'spi',
      );
      final dir = p.dirname(manifest);
      File(p.join(dir, 'd.vcd')).writeAsStringSync('');

      final byDir = resolver.resolve(dir) as ManifestWaveform;
      final byFile = resolver.resolve(manifest) as ManifestWaveform;
      // Same design either way: the identity is the manifest's directory.
      expect(byDir.designId, byFile.designId);
      expect(byDir.waveformPath, byFile.waveformPath);
    });

    test(
      'the legacy bare name still opens and names the file to rename to',
      () {
        final manifest = writeManifest(
          'version: 1\nartifacts:\n  waveform: d.vcd\n',
          design: 'uart_tx',
          fileName: '.crux-project',
        );
        File(p.join(p.dirname(manifest), 'd.vcd')).writeAsStringSync('');

        final r = resolver.resolve(manifest) as ManifestWaveform;
        expect(r.legacySuggestedFileName, 'uart_tx.crux-project');
        // The shared parser's English notice stays first in the warnings.
        expect(r.warnings.first, contains('deprecated'));
      },
    );

    test('a directory holding two manifests is ambiguous, not a guess', () {
      final first = writeManifest(
        'version: 1\nartifacts:\n  waveform: d.vcd\n',
        design: 'soc',
        fileName: 'a.crux-project',
      );
      final dir = p.dirname(first);
      File(p.join(dir, 'b.crux-project')).writeAsStringSync('version: 1\n');

      final r = resolver.resolve(dir);
      expect(r, isA<ManifestAmbiguous>());
      final a = r as ManifestAmbiguous;
      expect(a.candidates.map(p.basename), [
        'a.crux-project',
        'b.crux-project',
      ]);
    });

    test('parse warnings ride along rather than being swallowed', () {
      final manifest = writeManifest(
        'version: 99\nartifacts:\n  waveform: d.vcd\n',
      );
      File(p.join(p.dirname(manifest), 'd.vcd')).writeAsStringSync('');
      final r = resolver.resolve(manifest) as ManifestWaveform;
      expect(r.warnings.single, contains('99'));
    });
  });

  group('the messages are the feature', () {
    test('a manifest with no waveform says what to add', () {
      // The common case for a design whose dump has not been generated yet.
      // "Nothing happened" would be the worst possible response.
      final manifest = writeManifest(
        'version: 1\nname: cdc_capture\nartifacts:\n  lint: project.lintcrux\n',
      );
      final r = resolver.resolve(manifest);
      expect(r, isA<ManifestUnusable>());
      final m = (r as ManifestUnusable).message;
      expect(m, contains('cdc_capture'));
      expect(m, contains('waveform'));
      expect(m, contains('.crux-project'));
    });

    test('a named-but-missing waveform names the path, not the design', () {
      // Distinguishable from the case above on purpose: "you never named one"
      // and "the one you named moved" are different problems.
      final manifest = writeManifest(
        'version: 1\nartifacts:\n  waveform: sim/gone.vcd\n',
      );
      final r = resolver.resolve(manifest);
      expect(r, isA<ManifestUnusable>());
      expect((r as ManifestUnusable).message, contains('sim/gone.vcd'));
      expect(r.message, contains('missing'));
    });

    test('an invalid manifest says so instead of failing to open a file', () {
      final manifest = writeManifest('name: no version here\n');
      final r = resolver.resolve(manifest);
      expect(r, isA<ManifestUnusable>());
      expect((r as ManifestUnusable).message, contains('version'));
    });
  });

  group('injection', () {
    test('existence is injectable so the decision is testable', () {
      final manifest = writeManifest(
        'version: 1\nartifacts:\n  waveform: sim/never.vcd\n',
      );
      final ok = resolver.resolve(manifest, exists: (_) => true);
      expect(ok, isA<ManifestWaveform>());
      final bad = resolver.resolve(manifest, exists: (_) => false);
      expect(bad, isA<ManifestUnusable>());
    });
  });
}
