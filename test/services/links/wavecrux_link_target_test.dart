// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/services/links/wavecrux_link_target.dart';

/// Containment for the file a link names: the CXP receive floor first, by
/// spelling, then the filesystem, with every symbolic link resolved and the
/// waveform-extension rule applied to both the spelled and the resolved path.
/// What is accepted is the resolved path, which is the one opened.

WaveCruxLinkTargetRefusal _refusal(WaveCruxLinkTargetResult result) =>
    switch (result) {
      WaveCruxLinkTargetRefused(:final refusal) => refusal,
      WaveCruxLinkTargetAccepted(:final path) => fail('accepted $path'),
    };

String _accepted(WaveCruxLinkTargetResult result) => switch (result) {
  WaveCruxLinkTargetAccepted(:final path) => path,
  WaveCruxLinkTargetRefused(:final refusal) => fail('refused: $refusal'),
};

void main() {
  late Directory dir;
  late String dump;

  setUp(() {
    // Resolved up front: macOS puts the temp root behind /var -> /private/var,
    // and the accepted path is the resolved one.
    dir = Directory(
      Directory.systemTemp
          .createTempSync('wavecrux_link_target_')
          .resolveSymbolicLinksSync(),
    );
    dump = p.join(dir.path, 'dump.vcd');
    File(dump).writeAsStringSync(r'$timescale 1 ns $end');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('the floor, judged by spelling', () {
    test('relative, empty, padded and NUL paths are refused', () {
      for (final path in [
        'dump.vcd',
        './dump.vcd',
        '../dump.vcd',
        '',
        ' $dump',
        '$dump ',
        '$dump\u0000.vcd',
      ]) {
        expect(
          _refusal(vetWaveCruxLinkTarget(path)),
          WaveCruxLinkTargetRefusal.pathRefused,
          reason: path,
        );
      }
    });

    test('Windows streams and device names are refused by spelling', () {
      expect(isWindowsDeviceOrStreamForTest(r'C:\sim\dump.vcd:hidden'), isTrue);
      expect(isWindowsDeviceOrStreamForTest(r'C:\sim\x:dump.vcd'), isTrue);
      expect(isWindowsDeviceOrStreamForTest(r'C:\sim\NUL.vcd'), isTrue);
      expect(isWindowsDeviceOrStreamForTest(r'C:\sim\con.vcd'), isTrue);
      expect(isWindowsDeviceOrStreamForTest(r'C:\sim\COM1.fst'), isTrue);
      expect(isWindowsDeviceOrStreamForTest(r'C:\sim\lpt9.x.vcd'), isTrue);
      expect(isWindowsDeviceOrStreamForTest(r'C:\sim\dump.vcd'), isFalse);
      expect(isWindowsDeviceOrStreamForTest(r'C:\sim\console.vcd'), isFalse);
      expect(isWindowsDeviceOrStreamForTest('C:/sim/com10.vcd'), isFalse);
    });
  });

  group('what the file is', () {
    test('a waveform that exists is accepted as its resolved path', () {
      expect(_accepted(vetWaveCruxLinkTarget(dump)), dump);
    });

    test('every link format is accepted, in any case', () {
      for (final name in ['a.FST', 'b.ghw', 'c.lxt', 'd.LXT2', 'e.Vcd']) {
        final path = p.join(dir.path, name);
        File(path).writeAsStringSync('x');
        expect(_accepted(vetWaveCruxLinkTarget(path)), path, reason: name);
      }
    });

    test('a file that is not a waveform is refused before it is looked at', () {
      for (final name in [
        'notes.txt',
        'session.wavecrux',
        'share.wavecruxpack',
        'design.crux-project',
        'capture.fsdb',
        'script.sh',
        'dump.vcd.exe',
        'dump',
      ]) {
        final path = p.join(dir.path, name);
        File(path).writeAsStringSync('x');
        expect(
          _refusal(vetWaveCruxLinkTarget(path)),
          WaveCruxLinkTargetRefusal.notAWaveform,
          reason: name,
        );
      }
    });

    test('a missing file, a directory and a dangling link are not found', () {
      expect(
        _refusal(vetWaveCruxLinkTarget(p.join(dir.path, 'gone.vcd'))),
        WaveCruxLinkTargetRefusal.fileNotFound,
      );
      final folder = p.join(dir.path, 'folder.vcd');
      Directory(folder).createSync();
      expect(
        _refusal(vetWaveCruxLinkTarget(folder)),
        WaveCruxLinkTargetRefusal.fileNotFound,
      );
      final dangling = p.join(dir.path, 'dangling.vcd');
      Link(dangling).createSync(p.join(dir.path, 'nowhere.vcd'));
      expect(
        _refusal(vetWaveCruxLinkTarget(dangling)),
        WaveCruxLinkTargetRefusal.fileNotFound,
      );
    }, testOn: '!windows');

    test('a .vcd link to a file that is not a waveform is refused', () {
      final secret = p.join(dir.path, 'id_ed25519');
      File(secret).writeAsStringSync('-----BEGIN OPENSSH PRIVATE KEY-----');
      final bait = p.join(dir.path, 'bait.vcd');
      Link(bait).createSync(secret);
      expect(
        _refusal(vetWaveCruxLinkTarget(bait)),
        WaveCruxLinkTargetRefusal.notAWaveform,
      );
    }, testOn: '!windows');

    test('a link to a waveform is accepted as the file it reaches', () {
      final elsewhere = Directory(p.join(dir.path, 'runs'))..createSync();
      final real = p.join(elsewhere.path, 'real.fst');
      File(real).writeAsStringSync('x');
      final alias = p.join(dir.path, 'alias.vcd');
      Link(alias).createSync(real);
      expect(_accepted(vetWaveCruxLinkTarget(alias)), real);
    }, testOn: '!windows');

    test('dot segments resolve the way the filesystem reads them', () {
      final sub = Directory(p.join(dir.path, 'sub'))..createSync();
      expect(
        _accepted(vetWaveCruxLinkTarget(p.join(sub.path, '..', 'dump.vcd'))),
        dump,
      );
    });

    test('a character device is not a regular file', () {
      expect(
        _refusal(vetWaveCruxLinkTarget('/dev/null')),
        WaveCruxLinkTargetRefusal.notAWaveform,
      );
      final devLink = p.join(dir.path, 'zero.vcd');
      Link(devLink).createSync('/dev/zero');
      expect(
        _refusal(vetWaveCruxLinkTarget(devLink)),
        anyOf(
          WaveCruxLinkTargetRefusal.fileNotFound,
          WaveCruxLinkTargetRefusal.notAWaveform,
        ),
      );
    }, testOn: '!windows');
  });

  group('opened before', () {
    test('matches an open tab or a recent file by file identity', () {
      expect(
        wasOpenedBefore(dump, openTabPaths: [dump], recentPaths: const []),
        isTrue,
      );
      expect(
        wasOpenedBefore(
          dump,
          openTabPaths: const [null, ''],
          recentPaths: [p.join(dir.path, 'sub', '..', 'dump.vcd')],
        ),
        isTrue,
      );
      expect(
        wasOpenedBefore(
          dump,
          openTabPaths: [p.join(dir.path, 'other.vcd')],
          recentPaths: const [],
        ),
        isFalse,
      );
    });

    test('a link through a symbolic link matches the tab of its target', () {
      final alias = p.join(dir.path, 'alias.vcd');
      Link(alias).createSync(dump);
      expect(
        wasOpenedBefore(dump, openTabPaths: [alias], recentPaths: const []),
        isTrue,
      );
    }, testOn: '!windows');
  });
}
