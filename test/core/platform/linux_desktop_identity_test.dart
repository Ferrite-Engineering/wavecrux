// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_linux_integration/crux_linux_integration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/platform/linux_desktop_identity.dart';

String _cmakeSet(String name) {
  final cmake = File('linux/CMakeLists.txt').readAsStringSync();
  final match = RegExp('set\\($name "([^"]+)"\\)').firstMatch(cmake);
  if (match == null) fail('linux/CMakeLists.txt sets no $name');
  return match.group(1)!;
}

void main() {
  test('the open-core identity matches the Linux runner it launches', () {
    // The open-core build used to install the Pro identity, so its window
    // was matched to a `WaveCrux Pro` desktop entry that launched nothing.
    expect(kWaveCruxLinuxDesktopApp.appId, _cmakeSet('APPLICATION_ID'));
    expect(kWaveCruxLinuxDesktopApp.execName, _cmakeSet('BINARY_NAME'));
    expect(kWaveCruxLinuxDesktopApp.name, isNot(contains('Pro')));
  });

  // A file manager types a file first and looks for handlers second. The
  // entry declared no MimeType and installed no mapping, so "Open With" never
  // listed WaveCrux and a double-clicked waveform went somewhere else — the
  // Linux half of the document types the macOS bundle registers.
  group('the file kinds the entry claims', () {
    test('account for every extension the macOS bundle registers', () {
      final coverage = checkLinuxMimeCoverage(
        kWaveCruxLinuxDesktopApp,
        registeredExtensions: _macOsRegisteredExtensions(),
      );
      expect(coverage.problems, isEmpty, reason: coverage.toString());
    });

    test('render as one semicolon-terminated MimeType line', () {
      final entry = buildDesktopEntry(
        kWaveCruxLinuxDesktopApp,
        appImagePath: '/home/e/Downloads/WaveCrux.AppImage',
      );
      final expected = kWaveCruxLinuxFileTypes
          .where((t) => t.isNamed)
          .map((t) => '${t.name};')
          .join();
      expect(entry, contains('MimeType=$expected\n'));
      expect('MimeType='.allMatches(entry), hasLength(1));
      expect(
        entry.indexOf('MimeType='),
        greaterThan(entry.indexOf('Categories=')),
      );
    });

    test('install a package that maps each of them', () {
      final xml = buildMimePackage(kWaveCruxLinuxDesktopApp)!;
      for (final type in kWaveCruxLinuxFileTypes) {
        expect(xml, contains('type="${type.name}"'));
        for (final extension in type.extensions) {
          expect(xml, contains('<glob pattern="*.$extension"'));
        }
      }
    });

    // The one extension a stock database already globs — to a Video CD
    // playlist. Taking it would retype every `.vcd` on the machine; the
    // waveform is recognised by its own header instead.
    test('share .vcd rather than take it', () {
      final xml = buildMimePackage(kWaveCruxLinuxDesktopApp)!;
      final vcd = xml.substring(
        xml.indexOf('type="application/x-vcd-waveform"'),
        xml.indexOf('</mime-type>', xml.indexOf('x-vcd-waveform')),
      );
      expect(vcd, contains('<glob pattern="*.vcd" weight="40"/>'));
      expect(vcd, contains('<magic priority="90">'));
      for (final token in const [r'$date', r'$version', r'$timescale']) {
        expect(vcd, contains('value="$token"'));
      }
      expect(
        kWaveCruxLinuxDesktopApp.fileTypes.map((t) => t.name),
        isNot(contains('application/x-cdlink')),
        reason: 'a Video CD playlist is not a waveform',
      );
    });
  });

  test('bootstrap installs the identity it is given', () {
    final app = File('lib/app.dart').readAsStringSync();
    // The parameter is nullable because a list of declared MIME types cannot
    // be const, so the open-core identity cannot be a default value; the
    // fallback is the same identity, applied inside.
    expect(
      app,
      contains('linuxDesktopApp ?? kWaveCruxLinuxDesktopApp'),
    );
    expect(
      app,
      isNot(contains("appId: 'com.ferriteengineering.wavecrux_pro'")),
    );
  });
}

/// Every extension the macOS bundle claims, read from its document types and
/// its exported/imported UTI declarations — the list the Linux entry mirrors.
Set<String> _macOsRegisteredExtensions() {
  final plist = File('macos/Runner/Info.plist').readAsStringSync();
  final out = <String>{};
  for (final key in const [
    'CFBundleTypeExtensions',
    'public.filename-extension',
  ]) {
    for (final at in _indicesOf(plist, key)) {
      final array = _firstArrayAfter(plist, at);
      out.addAll(
        RegExp(
          '<string>([a-z0-9-]{1,24})</string>',
          caseSensitive: false,
        ).allMatches(array).map((m) => m.group(1)!.toLowerCase()),
      );
    }
  }
  return out;
}

Iterable<int> _indicesOf(String src, String needle) sync* {
  var from = 0;
  while (true) {
    final at = src.indexOf(needle, from);
    if (at == -1) return;
    yield at;
    from = at + needle.length;
  }
}

/// The first `<array>...</array>` following [at], nesting-aware.
String _firstArrayAfter(String src, int at) {
  var i = src.indexOf('<array>', at);
  if (i == -1) return '';
  final start = i;
  var depth = 0;
  while (i < src.length) {
    if (src.startsWith('<array>', i)) {
      depth++;
      i += '<array>'.length;
      continue;
    }
    if (src.startsWith('</array>', i)) {
      depth--;
      i += '</array>'.length;
      if (depth == 0) return src.substring(start, i);
      continue;
    }
    i++;
  }
  return src.substring(start);
}
