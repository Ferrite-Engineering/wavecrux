// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/services/waveform/fsdb_conversion_service.dart';

// ── helpers ──────────────────────────────────────────────────────────────────

/// Creates a [FsdbProcessRunner] that always succeeds with [stdout].
FsdbProcessRunner _successRunner(String stdout) =>
    (_, _) async => ProcessResult(1, 0, stdout, '');

/// Creates a [FsdbProcessRunner] that fails with [exitCode] and [stderr].
FsdbProcessRunner _failRunner({int exitCode = 1, String stderr = 'error'}) =>
    (_, _) async => ProcessResult(1, exitCode, '', stderr);

/// An [FsdbExecutableLocator] that always reports the given executables
/// as present, returning `/fake/<name>` for each one listed.
FsdbExecutableLocator _locator(List<String> available) =>
    (name) => available.contains(name) ? '/fake/$name' : null;

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('FsdbConversionException', () {
    test('message is stored and surfaced in toString', () {
      const ex = FsdbConversionException('oops');
      expect(ex.message, 'oops');
      expect(ex.toString(), contains('oops'));
    });
  });

  group('FsdbConversionService.isFsdbFile', () {
    const service = FsdbConversionService();

    test('returns true for .fsdb extension', () {
      expect(service.isFsdbFile('/home/user/sim.fsdb'), isTrue);
    });

    test('returns true for uppercase .FSDB extension', () {
      expect(service.isFsdbFile('/home/user/sim.FSDB'), isTrue);
    });

    test('returns true for mixed-case .Fsdb', () {
      expect(service.isFsdbFile('/home/user/sim.Fsdb'), isTrue);
    });

    test('returns false for .vcd extension', () {
      expect(service.isFsdbFile('/home/user/sim.vcd'), isFalse);
    });

    test('returns false for .fst extension', () {
      expect(service.isFsdbFile('/home/user/sim.fst'), isFalse);
    });

    test('returns false for path containing fsdb in directory name', () {
      expect(service.isFsdbFile('/fsdb/sim.vcd'), isFalse);
    });

    test('returns false for empty string', () {
      expect(service.isFsdbFile(''), isFalse);
    });
  });

  group('FsdbConversionService.findFsdb2Vcd / findVcd2Fst', () {
    test('returns path when locator finds fsdb2vcd', () {
      final service = FsdbConversionService(
        executableLocator: _locator(['fsdb2vcd', 'vcd2fst']),
      );
      expect(service.findFsdb2Vcd(), '/fake/fsdb2vcd');
    });

    test('returns path when locator finds vcd2fst', () {
      final service = FsdbConversionService(
        executableLocator: _locator(['fsdb2vcd', 'vcd2fst']),
      );
      expect(service.findVcd2Fst(), '/fake/vcd2fst');
    });

    test('returns null when locator cannot find fsdb2vcd', () {
      final service = FsdbConversionService(
        executableLocator: _locator([]),
      );
      expect(service.findFsdb2Vcd(), isNull);
    });

    test('returns null when locator cannot find vcd2fst', () {
      final service = FsdbConversionService(
        executableLocator: _locator(['fsdb2vcd']), // vcd2fst absent
      );
      expect(service.findVcd2Fst(), isNull);
    });
  });

  group('FsdbConversionService.getCachedFst', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fsdb_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('returns null when no FST file exists', () {
      const service = FsdbConversionService();
      final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
      expect(service.getCachedFst(fsdbPath), isNull);
    });

    test('returns null when FST exists but is older than FSDB', () async {
      const service = FsdbConversionService();
      final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
      final fstPath = p.join(tempDir.path, 'sim.fst');

      await File(fstPath).writeAsString('fst');
      await File(fsdbPath).writeAsString('fsdb');

      // Explicitly set timestamps so FST is 1 hour older than FSDB.
      final old = DateTime.now().subtract(const Duration(hours: 1));
      await File(fstPath).setLastModified(old);
      await File(fsdbPath).setLastModified(DateTime.now());

      expect(service.getCachedFst(fsdbPath), isNull);
    });

    test('returns FST path when FST is newer than FSDB', () async {
      const service = FsdbConversionService();
      final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
      final fstPath = p.join(tempDir.path, 'sim.fst');

      await File(fsdbPath).writeAsString('fsdb');
      await File(fstPath).writeAsString('fst');

      // Explicitly set timestamps so FST is 1 hour newer than FSDB.
      await File(fsdbPath).setLastModified(
        DateTime.now().subtract(const Duration(hours: 1)),
      );
      await File(fstPath).setLastModified(DateTime.now());

      expect(service.getCachedFst(fsdbPath), fstPath);
    });
  });

  group('FsdbConversionService.convertFsdbToFst', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fsdb_conv_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('throws FsdbConversionException when fsdb2vcd is not in PATH', () {
      final service = FsdbConversionService(
        executableLocator: _locator([]), // neither tool found
        processRunner: _successRunner(''),
      );
      expect(
        () => service.convertFsdbToFst(p.join(tempDir.path, 'sim.fsdb')),
        throwsA(isA<FsdbConversionException>()),
      );
    });

    test('passes FSDB path as argument to fsdb2vcd', () async {
      final capturedArgs = <List<String>>[];
      final service = FsdbConversionService(
        executableLocator: _locator(['fsdb2vcd', 'vcd2fst']),
        processRunner: (exe, args) async {
          capturedArgs.add(args);
          if (exe == '/fake/vcd2fst') {
            await File(args[1]).writeAsString('fst');
          }
          return ProcessResult(1, 0, 'vcd-output', '');
        },
      );

      final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
      await File(fsdbPath).writeAsString('dummy');

      await service.convertFsdbToFst(fsdbPath);

      // First call is fsdb2vcd; its only argument is the FSDB path.
      expect(capturedArgs.first, [fsdbPath]);
    });

    test('returns FST path when both tools are available', () async {
      final service = FsdbConversionService(
        executableLocator: _locator(['fsdb2vcd', 'vcd2fst']),
        processRunner: (exe, args) async {
          if (exe == '/fake/vcd2fst') {
            // Simulate vcd2fst creating the output FST file.
            await File(args[1]).writeAsString('fst-data');
          }
          return ProcessResult(1, 0, 'vcd-output', '');
        },
      );

      final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
      await File(fsdbPath).writeAsString('dummy');

      final result = await service.convertFsdbToFst(fsdbPath);
      expect(result, endsWith('.fst'));
      expect(File(result).existsSync(), isTrue);
    });

    test('returns VCD path when only fsdb2vcd is available', () async {
      final service = FsdbConversionService(
        executableLocator: _locator(['fsdb2vcd']), // no vcd2fst
        processRunner: _successRunner(r'$var clk ...'), // fake VCD content
      );

      final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
      await File(fsdbPath).writeAsString('dummy');

      final result = await service.convertFsdbToFst(fsdbPath);
      expect(result, endsWith('.vcd'));
      expect(File(result).existsSync(), isTrue);
    });

    test('respects outputDir when provided', () async {
      final outputDir = await Directory(p.join(tempDir.path, 'out')).create();
      final service = FsdbConversionService(
        executableLocator: _locator(['fsdb2vcd']),
        processRunner: _successRunner('vcd'),
      );

      final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
      await File(fsdbPath).writeAsString('dummy');

      final result = await service.convertFsdbToFst(
        fsdbPath,
        outputDir: outputDir.path,
      );
      expect(result, startsWith(outputDir.path));
    });

    test('throws FsdbConversionException when fsdb2vcd exits non-zero', () {
      final service = FsdbConversionService(
        executableLocator: _locator(['fsdb2vcd']),
        processRunner: _failRunner(stderr: 'license error'),
      );

      expect(
        () => service.convertFsdbToFst(p.join(tempDir.path, 'sim.fsdb')),
        throwsA(
          isA<FsdbConversionException>().having(
            (e) => e.message,
            'message',
            contains('fsdb2vcd failed'),
          ),
        ),
      );
    });

    test(
      'throws FsdbConversionException when vcd2fst exits non-zero',
      () async {
        var callCount = 0;
        final service = FsdbConversionService(
          executableLocator: _locator(['fsdb2vcd', 'vcd2fst']),
          processRunner: (exe, args) async {
            callCount++;
            if (callCount == 1) {
              // fsdb2vcd succeeds.
              return ProcessResult(1, 0, 'vcd-content', '');
            }
            // vcd2fst fails.
            return ProcessResult(1, 2, '', 'vcd2fst internal error');
          },
        );

        final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
        await File(fsdbPath).writeAsString('dummy');

        await expectLater(
          service.convertFsdbToFst(fsdbPath),
          throwsA(
            isA<FsdbConversionException>().having(
              (e) => e.message,
              'message',
              contains('vcd2fst failed'),
            ),
          ),
        );
      },
    );

    test('cleans up temp VCD file on success', () async {
      final service = FsdbConversionService(
        executableLocator: _locator(['fsdb2vcd', 'vcd2fst']),
        processRunner: (exe, args) async {
          if (exe == '/fake/vcd2fst') {
            await File(args[1]).writeAsString('fst');
          }
          return ProcessResult(1, 0, 'vcd', '');
        },
      );

      final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
      await File(fsdbPath).writeAsString('dummy');

      await service.convertFsdbToFst(fsdbPath);

      // Temp file should be gone.
      expect(File(p.join(tempDir.path, 'sim.vcd.tmp')).existsSync(), isFalse);
    });

    test('cleans up temp VCD file on fsdb2vcd failure', () async {
      // The temp file is written before the exit-code check, but since
      // fsdb2vcd fails here we verify the finally block still deletes it.
      var firstCall = true;
      final service = FsdbConversionService(
        executableLocator: _locator(['fsdb2vcd']),
        processRunner: (exe, args) async {
          if (firstCall) {
            firstCall = false;
            // Write something to simulate partial output.
            await File(
              p.join(tempDir.path, 'sim.vcd.tmp'),
            ).writeAsString('partial');
            return ProcessResult(1, 1, '', 'failed');
          }
          return ProcessResult(1, 0, '', '');
        },
      );

      final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
      await File(fsdbPath).writeAsString('dummy');

      await expectLater(
        service.convertFsdbToFst(fsdbPath),
        throwsA(isA<FsdbConversionException>()),
      );
      expect(File(p.join(tempDir.path, 'sim.vcd.tmp')).existsSync(), isFalse);
    });
  });
}
