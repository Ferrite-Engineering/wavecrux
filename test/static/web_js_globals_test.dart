// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: every `globalThis.waveCrux*` object the Dart web build binds
// with `@JS(...)` is installed by a script that `web/index.html` loads.
//
// `dart:js_interop` binds a global lazily and reads it as `null` when nothing
// set it, so a missing loader is not a build error — it is a runtime failure
// on the first use. The LXT/LXT2 converter shipped exactly that way: Dart bound
// `waveCruxLxt2Fst`, no script published it, and every browser LXT open failed
// with "loader not present". (`cruxHostBridge` is out of scope: the VS Code
// webview host installs it, not this page.)
//
// For the lxt2fst loader, which forwards to wasm-bindgen glue, the guard also
// checks that each glue function it calls is really exported, so renaming a
// `js_name` in `native/lxt2fst/src/wasm.rs` cannot silently break it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final indexHtml = File('web/index.html').readAsStringSync();
  final loadedScripts = {
    for (final m in RegExp(
      r'<script[^>]*\btype="module"[^>]*\bsrc="(wasm/[^"]+\.js)"',
    ).allMatches(indexHtml))
      m.group(1)!,
  };

  Map<String, String> boundGlobals() {
    final globals = <String, String>{};
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final m in RegExp(
        r"""@JS\(['"](waveCrux\w+)['"]\)""",
      ).allMatches(file.readAsStringSync())) {
        globals[m.group(1)!] = file.path;
      }
    }
    return globals;
  }

  test('web/index.html loads the wasm loaders as ES modules', () {
    expect(
      loadedScripts,
      containsAll(<String>[
        'wasm/wellen_wasm_loader.js',
        'wasm/lxt2fst_loader.js',
      ]),
    );
  });

  test('every @JS waveCrux* global is published by a loaded script', () {
    final globals = boundGlobals();
    expect(
      globals.keys,
      containsAll(<String>['waveCruxWellen', 'waveCruxLxt2Fst']),
      reason: 'the scan no longer finds the known bindings — fix the pattern',
    );

    final published = <String, String>{};
    for (final script in loadedScripts) {
      final source = File('web/$script');
      expect(
        source.existsSync(),
        isTrue,
        reason:
            'web/index.html loads '
            'web/$script, which does not exist',
      );
      for (final m in RegExp(
        r'globalThis\.(waveCrux\w+)\s*=',
      ).allMatches(source.readAsStringSync())) {
        published[m.group(1)!] = script;
      }
    }

    for (final MapEntry(key: global, value: dartFile) in globals.entries) {
      expect(
        published.keys,
        contains(global),
        reason:
            '$dartFile binds globalThis.$global, but no script loaded by '
            'web/index.html assigns it — the web build would read null.',
      );
    }
  });

  test('lxt2fst_loader.js calls only functions the wasm-bindgen glue '
      'exports', () {
    final loader = File('web/wasm/lxt2fst_loader.js').readAsStringSync();
    final glue = File('web/wasm/lxt2fst.js').readAsStringSync();

    expect(loader, contains("import('./lxt2fst.js')"));
    final exported = {
      for (final m in RegExp(r'export function (\w+)\(').allMatches(glue))
        m.group(1)!,
    };
    final called = {
      for (final m in RegExp(r'loaded\(\)\.(\w+)\(').allMatches(loader))
        m.group(1)!,
    };

    expect(
      called,
      containsAll(<String>['lxt2fstConvert', 'lxt2fstAbiVersion']),
    );
    for (final name in called) {
      expect(
        exported,
        contains(name),
        reason:
            'lxt2fst_loader.js calls $name, which web/wasm/lxt2fst.js '
            'does not export — rebuild with tool/build_lxt2fst_wasm.dart or '
            'fix the loader',
      );
    }
    // The shape lxt2fst_converter_web.dart binds.
    for (final member in ['ensureReady', 'convert', 'abiVersion']) {
      expect(loader, contains(RegExp('\\b$member\\b')));
    }
  });
}
