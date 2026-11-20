// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_io/crux_io.dart' show SpawnHost;
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

/// A [FsdbProcessRunner] that plays both tools: `fsdb2vcd` prints
/// `vcd-output`, `vcd2fst` writes `converted-fst` to its output argument.
Future<ProcessResult> _fstWriter(String exe, List<String> args) async {
  if (exe == '/fake/vcd2fst') {
    await File(args[1]).writeAsString('converted-fst');
  }
  return ProcessResult(1, 0, 'vcd-output', '');
}

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
    late Directory appCache;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fsdb_test_');
      appCache = await Directory(p.join(tempDir.path, 'app-cache')).create();
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    FsdbConversionService converting() => FsdbConversionService(
      executableLocator: _locator(['fsdb2vcd', 'vcd2fst']),
      processRunner: _fstWriter,
      appCacheDirResolver: () async => appCache,
    );

    test('returns null when no FST file exists', () async {
      final service = converting();
      final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
      expect(await service.getCachedFst(fsdbPath), isNull);
    });

    test('returns null when FST exists but is older than FSDB', () async {
      final service = converting();
      final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
      await File(fsdbPath).writeAsString('fsdb');
      final fstPath = await service.convertFsdbToFst(fsdbPath);

      // Explicitly set timestamps so FST is 1 hour older than FSDB.
      final old = DateTime.now().subtract(const Duration(hours: 1));
      await File(fstPath).setLastModified(old);
      await File(fsdbPath).setLastModified(DateTime.now());

      expect(await service.getCachedFst(fsdbPath), isNull);
    });

    test(
      "returns the FST path for WaveCrux's own current conversion",
      () async {
        final service = converting();
        final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
        await File(fsdbPath).writeAsString('fsdb');
        final fstPath = await service.convertFsdbToFst(fsdbPath);

        // Explicitly set timestamps so FST is 1 hour newer than FSDB.
        await File(fsdbPath).setLastModified(
          DateTime.now().subtract(const Duration(hours: 1)),
        );
        await File(fstPath).setLastModified(DateTime.now());

        expect(fstPath, p.join(tempDir.path, 'sim.fst'));
        expect(await service.getCachedFst(fsdbPath), fstPath);
      },
    );

    test(
      'a newer sibling FST WaveCrux did not write is not a cache',
      () async {
        final service = converting();
        final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
        final fstPath = p.join(tempDir.path, 'sim.fst');

        await File(fsdbPath).writeAsString('fsdb');
        await File(fstPath).writeAsString("the user's own fst");

        // Explicitly set timestamps so FST is 1 hour newer than FSDB.
        await File(fsdbPath).setLastModified(
          DateTime.now().subtract(const Duration(hours: 1)),
        );
        await File(fstPath).setLastModified(DateTime.now());

        expect(await service.getCachedFst(fsdbPath), isNull);
      },
    );

    test(
      'returns null when the FSDB changed size since the conversion',
      () async {
        final service = converting();
        final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
        await File(fsdbPath).writeAsString('fsdb');
        final fstPath = await service.convertFsdbToFst(fsdbPath);

        await File(fsdbPath).writeAsString('a longer fsdb');
        await File(fsdbPath).setLastModified(
          DateTime.now().subtract(const Duration(hours: 1)),
        );
        await File(fstPath).setLastModified(DateTime.now());

        expect(await service.getCachedFst(fsdbPath), isNull);
      },
    );

    test('finds a conversion that went to the app cache', () async {
      final service = converting();
      final fsdbPath = p.join(tempDir.path, 'sim.fsdb');
      await File(fsdbPath).writeAsString('fsdb');
      await File(p.join(tempDir.path, 'sim.fst')).writeAsString('user');
      final fstPath = await service.convertFsdbToFst(fsdbPath);

      await File(fsdbPath).setLastModified(
        DateTime.now().subtract(const Duration(hours: 1)),
      );
      await File(fstPath).setLastModified(DateTime.now());

      expect(p.isWithin(appCache.path, fstPath), isTrue);
      expect(await service.getCachedFst(fsdbPath), fstPath);
    });
  });

  group('FsdbConversionService.convertFsdbToFst never overwrites a file '
      'WaveCrux did not write', () {
    late Directory tempDir;
    late Directory appCache;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fsdb_owner_test_');
      appCache = await Directory(p.join(tempDir.path, 'app-cache')).create();
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    FsdbConversionService service(List<String> tools) => FsdbConversionService(
      executableLocator: _locator(tools),
      processRunner: _fstWriter,
      appCacheDirResolver: () async => appCache,
    );

    test(
      'a sibling .fst stays as it was; the FST goes to the app cache',
      () async {
        final fsdbPath = p.join(tempDir.path, 'run.fsdb');
        await File(fsdbPath).writeAsString('fsdb');
        final userFst = File(p.join(tempDir.path, 'run.fst'));
        await userFst.writeAsString("the user's own fst");

        final result = await service([
          'fsdb2vcd',
          'vcd2fst',
        ]).convertFsdbToFst(fsdbPath);

        expect(await userFst.readAsString(), "the user's own fst");
        expect(p.isWithin(appCache.path, result), isTrue, reason: result);
        expect(p.basename(result), 'run.fst');
        expect(await File(result).readAsString(), 'converted-fst');
      },
    );

    test(
      'a sibling .vcd stays as it was; the VCD goes to the app cache',
      () async {
        final fsdbPath = p.join(tempDir.path, 'run.fsdb');
        await File(fsdbPath).writeAsString('fsdb');
        final userVcd = File(p.join(tempDir.path, 'run.vcd'));
        await userVcd.writeAsString("the user's own vcd");

        final result = await service(['fsdb2vcd']).convertFsdbToFst(fsdbPath);

        expect(await userVcd.readAsString(), "the user's own vcd");
        expect(p.isWithin(appCache.path, result), isTrue, reason: result);
        expect(p.basename(result), 'run.vcd');
        expect(await File(result).readAsString(), 'vcd-output');
      },
    );

    test(
      "WaveCrux's own earlier sibling output is converted in place",
      () async {
        final fsdbPath = p.join(tempDir.path, 'run.fsdb');
        await File(fsdbPath).writeAsString('fsdb');
        final converter = service(['fsdb2vcd', 'vcd2fst']);

        final first = await converter.convertFsdbToFst(fsdbPath);
        final second = await converter.convertFsdbToFst(fsdbPath);

        expect(first, p.join(tempDir.path, 'run.fst'));
        expect(second, first);
        expect(appCache.listSync(), isEmpty);
      },
    );
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

  group('locateFsdbExecutable', () {
    SpawnHost windows(Set<String> files, {String? pathExt}) => SpawnHost(
      windows: true,
      environment: {
        'PATH': r'C:\vendor\bin;C:\tools',
        'PATHEXT': ?pathExt,
      },
      // Windows file names are case-insensitive; PATHEXT spells `.BAT`.
      exists: (path) => files.any((f) => f.toLowerCase() == path.toLowerCase()),
    );

    test('Windows finds a .bat wrapper through PATHEXT', () {
      final host = windows({
        r'C:\vendor\bin\fsdb2vcd.bat',
      }, pathExt: '.COM;.EXE;.BAT;.CMD');
      expect(
        locateFsdbExecutable('fsdb2vcd', host: host)?.toLowerCase(),
        r'c:\vendor\bin\fsdb2vcd.bat',
      );
    });

    test('Windows finds a .cmd wrapper in a later PATH directory', () {
      final host = windows({
        r'C:\tools\vcd2fst.cmd',
      }, pathExt: '.COM;.EXE;.BAT;.CMD');
      expect(
        locateFsdbExecutable('vcd2fst', host: host)?.toLowerCase(),
        r'c:\tools\vcd2fst.cmd',
      );
    });

    test('Windows falls back to the default PATHEXT when it is unset', () {
      final host = windows({r'C:\vendor\bin\fsdb2vcd.exe'});
      expect(
        locateFsdbExecutable('fsdb2vcd', host: host)?.toLowerCase(),
        r'c:\vendor\bin\fsdb2vcd.exe',
      );
    });

    test(
      'Windows reports a tool that nothing on PATH answers to as absent',
      () {
        final host = windows(<String>{}, pathExt: '.COM;.EXE;.BAT;.CMD');
        expect(locateFsdbExecutable('fsdb2vcd', host: host), isNull);
      },
    );

    test('POSIX walks PATH for an existing file', () {
      final host = SpawnHost(
        windows: false,
        environment: const {'PATH': '/opt/synopsys/bin::/usr/local/bin'},
        exists: {'/usr/local/bin/vcd2fst'}.contains,
      );
      expect(
        locateFsdbExecutable('vcd2fst', host: host),
        '/usr/local/bin/vcd2fst',
      );
      expect(locateFsdbExecutable('fsdb2vcd', host: host), isNull);
    });
  });
}
