// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard for what WaveCrux claims about macOS document types: which
// double-click it answers, and which formats it says it defines.
//
// `LSHandlerRank` decides who wins when several installed applications
// declare the same document type. Omitted, an application that declares the
// type ranks as its owner — right for WaveCrux's own formats, wrong for the
// suite design manifest, which is not any one product's file. All four
// products register `<design>.crux-project` so that opening one opens the
// part that product owns, and while more than one claimed to own the type,
// which one a double-click reached was arbitrary. All four now defer, so the
// manifest opens in whichever product the user picked.
//
// The second claim is the UTI declaration. An exported type says this
// application defines the format; an imported one says it reads a format
// someone else defined. WaveCrux exported all nine, including VCD
// (IEEE 1364), FST and the GTKWave save file (GTKWave's), GHW (GHDL's) and
// the LXT/LXT2 legacy dumps (GTKWave's again) — the same overclaim in a
// different field. Only the session and the pack are ours.

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The UTIs WaveCrux declares it defines. Everything else it registers is
/// another project's format, read but not defined here.
const _exportedTypes = {'com.wavecrux.session', 'com.wavecrux.pack'};

/// The `CFBundleDocumentTypes` entries of [plist], as key → text maps.
///
/// Values are read as plain text: a `<string>` yields its contents, an
/// `<array>` the strings inside it joined by `,`. Enough for the scalar
/// fields this guard reads, and it avoids a plist parser in a static test.
List<Map<String, String>> documentTypes(File plist) =>
    _entriesUnder(plist, 'CFBundleDocumentTypes');

/// The UTI declarations of [plist] under [key], as key → text maps.
List<Map<String, String>> typeDeclarations(File plist, {required String key}) =>
    _entriesUnder(plist, key);

List<Map<String, String>> _entriesUnder(File plist, String key) {
  final src = plist.readAsStringSync();
  final at = src.indexOf('<key>$key</key>');
  if (at == -1) {
    throw StateError('${plist.path} has no $key');
  }
  final array = _firstArrayAfter(src, at);
  return _dictsOf(array).map(_entriesOf).toList();
}

Map<String, String> _entriesOf(String dict) {
  final out = <String, String>{};
  final key = RegExp('<key>([^<]+)</key>');
  for (final match in key.allMatches(dict)) {
    final rest = dict.substring(match.end).trimLeft();
    if (rest.startsWith('<string>')) {
      out[match.group(1)!] = RegExp(
        '<string>([^<]*)</string>',
      ).firstMatch(rest)!.group(1)!;
    } else if (rest.startsWith('<array>')) {
      out[match.group(1)!] = RegExp(
        '<string>([^<]*)</string>',
      ).allMatches(_firstArrayAfter(rest, 0)).map((m) => m.group(1)!).join(',');
    }
  }
  return out;
}

/// The top-level `<dict>` elements of an `<array>` body, nesting-aware.
List<String> _dictsOf(String array) {
  final out = <String>[];
  var i = 0;
  while (true) {
    i = array.indexOf('<dict>', i);
    if (i == -1) return out;
    var depth = 0;
    var j = i;
    while (j < array.length) {
      if (array.startsWith('<dict>', j)) {
        depth++;
        j += '<dict>'.length;
        continue;
      }
      if (array.startsWith('</dict>', j)) {
        depth--;
        j += '</dict>'.length;
        if (depth == 0) break;
        continue;
      }
      j++;
    }
    out.add(array.substring(i, j));
    i = j;
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

void main() {
  final plist = File('macos/Runner/Info.plist');
  final iosPlist = File('ios/Runner/Info.plist');
  late List<Map<String, String>> types;
  setUpAll(() => types = documentTypes(plist));

  test('the suite design manifest is handled as an alternate', () {
    final manifest = types.singleWhere(
      (t) => t['CFBundleTypeExtensions'] == 'crux-project',
      orElse: () => fail('${plist.path} registers no .crux-project'),
    );
    expect(
      manifest['LSHandlerRank'],
      'Alternate',
      reason:
          'no product owns the suite manifest. With more than one claiming '
          'to, which product a double-clicked .crux-project reaches is '
          'arbitrary; deferring leaves it to the user (Get Info -> Open '
          'with -> Change All).',
    );
  });

  test("WaveCrux's own formats keep the owner rank", () {
    // The waveform and session formats are what this application is for, so
    // it answers for them by default. Only the shared manifest defers.
    for (final type in types) {
      final extensions = type['CFBundleTypeExtensions'];
      if (extensions == 'crux-project') continue;
      expect(
        type['LSHandlerRank'],
        isNull,
        reason: '$extensions should rank as owner (no LSHandlerRank key)',
      );
    }
  });

  test("only WaveCrux's own formats are declared as exported", () {
    final exported = typeDeclarations(
      plist,
      key: 'UTExportedTypeDeclarations',
    ).map((t) => t['UTTypeIdentifier']).toSet();
    expect(
      exported,
      _exportedTypes,
      reason:
          'an exported declaration says WaveCrux defines the format. VCD, '
          'FST, GHW, the GTKWave save file and the LXT/LXT2 dumps belong to '
          'IEEE 1364, GTKWave and GHDL; WaveCrux reads them, so it imports '
          'them.',
    );
  });

  test(
    'every other registered type is imported, with what it opens intact',
    () {
      final imported = {
        for (final t in typeDeclarations(
          plist,
          key: 'UTImportedTypeDeclarations',
        ))
          t['UTTypeIdentifier']!: t,
      };
      // Every content type a document type names is declared exactly once, on
      // whichever side owns it — otherwise Finder knows the extension but not
      // the type, or the app claims a format twice.
      final declared = imported.keys.toSet().union(_exportedTypes);
      for (final type in types) {
        expect(
          declared,
          contains(type['LSItemContentTypes']),
          reason: '${type['CFBundleTypeName']} names an undeclared type',
        );
      }
      expect(
        imported.keys,
        containsAll(<String>[
          'app.edacrux.project',
          'com.wavecrux.vcd',
          'com.wavecrux.fst',
          'com.wavecrux.ghw',
          'com.wavecrux.gtkw',
          'com.wavecrux.lxt',
          'com.wavecrux.lxt2',
        ]),
      );
      // Importing changes who declares, not what opens: the extension and the
      // conformance stay as they were.
      expect(
        imported['com.wavecrux.vcd']!['UTTypeConformsTo'],
        'public.plain-text',
      );
      expect(imported['com.wavecrux.vcd']!['public.filename-extension'], 'vcd');
      expect(imported['com.wavecrux.fst']!['public.filename-extension'], 'fst');
    },
  );

  test('iOS declares the same formats on the same side', () {
    // The share sheet reads these the way Finder does, and the claim is the
    // same one: the session is ours, the waveform formats are not.
    expect(
      typeDeclarations(
        iosPlist,
        key: 'UTExportedTypeDeclarations',
      ).map((t) => t['UTTypeIdentifier']),
      ['com.wavecrux.session'],
      reason: 'iOS ships no pack target, so the session is the only own type',
    );
    expect(
      typeDeclarations(
        iosPlist,
        key: 'UTImportedTypeDeclarations',
      ).map((t) => t['UTTypeIdentifier']),
      containsAll(<String>[
        'com.wavecrux.vcd',
        'com.wavecrux.fst',
        'com.wavecrux.ghw',
        'com.wavecrux.lxt',
        'com.wavecrux.lxt2',
      ]),
    );
  });
}
