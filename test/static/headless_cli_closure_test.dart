// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: the headless `wavecrux` binary's import closure never reaches
// Flutter, and never reaches a language-model client.
//
// `bin/wavecrux.dart` is compiled by `dart build cli` (`tool/build_cli.sh`)
// for a plain Dart VM, where `dart:ui` does not exist. One import of
// `package:flutter/...`, or of a package that imports it, anywhere in the
// closure fails that build, and `flutter test` cannot see it: the test VM has
// `dart:ui`. The binary also serves `wavecrux mcp`, whose answers come from
// the waveform alone; no file of the in-app assistant (`lib/services/ai/`,
// the model-client interface) may be reachable from it, so no verdict it
// gives can come from a model.
//
// The walk starts at every `bin/*.dart` and follows `import`, `export` and
// `part` directives through this package and every package in
// `.dart_tool/package_config.json`. A conditional directive follows the
// branch the Dart VM compiles: the first `dart.library.io` /
// `dart.library.ffi` configuration, or the default URI.

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final packages = _loadPackageConfig('.');

  test('the walk is not vacuous', () {
    final entries = _entries();
    expect(entries.map(p.basename), contains('wavecrux.dart'));
    final reached = _walk(entries, packages).reached;
    expect(reached.length, greaterThan(50));
    for (final needed in <String>[
      p.join('lib', 'headless', 'wavecrux_cli.dart'),
      p.join('lib', 'services', 'wave_session', 'wave_queries.dart'),
      p.join('lib', 'services', 'waveform', 'wellen_provider_io.dart'),
      p.join('lib', 'native', 'wellen_ffi_library_io.dart'),
    ]) {
      expect(reached.any((f) => f.endsWith(needed)), isTrue, reason: needed);
    }
    expect(
      reached.any((f) => f.contains('${p.separator}crux_mcp')),
      isTrue,
      reason: 'the walk leaves this package',
    );
  });

  test('bin/ never reaches dart:ui or package:flutter', () {
    final result = _walk(_entries(), packages);
    expect(
      result.describe(result.violations),
      isEmpty,
      reason:
          'The headless binary is compiled for the plain Dart VM, which has '
          'no dart:ui. Move the Flutter-dependent declaration into a file '
          'only the app imports.',
    );
  });

  test('bin/ never reaches the in-app assistant or a model client', () {
    final result = _walk(_entries(), packages);
    final self = p.normalize(p.absolute('lib'));
    final ai = p.join(self, 'services', 'ai');
    final modelFiles = <String>[
      for (final f in result.reached)
        if (p.isWithin(ai, f) || p.basename(f) == 'ai_model_client.dart') f,
    ];
    expect(
      modelFiles.map((f) => result.chainTo(f).map(p.basename).join(' -> ')),
      isEmpty,
      reason:
          'The MCP server answers from the waveform only; nothing of the '
          'assistant may be reachable from bin/.',
    );
  });

  group('the walk resolves the shapes it must', () {
    late Directory root;
    late Map<String, String> fixture;

    setUpAll(() {
      root = Directory.systemTemp.createTempSync('headless_closure_shapes_');
      void write(String path, String body) {
        File(p.join(root.path, path))
          ..createSync(recursive: true)
          ..writeAsStringSync(body);
      }

      write('demo/bin/tool.dart', '''
import 'package:demo/a.dart';
// import 'package:flutter/commented.dart';
const text = "import 'package:flutter/in_a_string.dart';";
''');
      write('demo/lib/a.dart', '''
import 'stub.dart'
    if (dart.library.js_interop) 'web.dart'
    if (dart.library.io) 'io.dart';
export 'package:pure/pure.dart';
part 'a_part.dart';
''');
      write('demo/lib/a_part.dart', "part of 'a.dart';\n");
      write('demo/lib/io.dart', "import 'package:uikit/uikit.dart';\n");
      write('demo/lib/web.dart', "import 'dart:ui';\n");
      write('demo/lib/stub.dart', "import 'package:flutter/widgets.dart';\n");
      write('pure/lib/pure.dart', '');
      write('uikit/lib/uikit.dart', "import 'package:flutter/widgets.dart';\n");
      fixture = <String, String>{
        'demo': p.join(root.path, 'demo'),
        'pure': p.join(root.path, 'pure'),
        'uikit': p.join(root.path, 'uikit'),
      };
    });

    tearDownAll(() => root.deleteSync(recursive: true));

    test('follows only the VM branch, into other packages, through parts', () {
      final result = _walk(<String>[
        p.join(root.path, 'demo', 'bin', 'tool.dart'),
      ], fixture);
      expect(result.violations.map((v) => v.uri), <String>[
        'package:flutter/widgets.dart',
      ]);
      expect(
        result.chainTo(result.violations.single.from).map(p.basename),
        <String>['tool.dart', 'a.dart', 'io.dart', 'uikit.dart'],
      );
      expect(
        result.reached.map(p.basename),
        containsAll(<String>['a_part.dart', 'pure.dart']),
      );
      expect(result.reached.map(p.basename), isNot(contains('web.dart')));
      expect(result.reached.map(p.basename), isNot(contains('stub.dart')));
    });
  });
}

List<String> _entries() => <String>[
  for (final e in Directory('bin').listSync())
    if (e is File && e.path.endsWith('.dart')) p.normalize(p.absolute(e.path)),
];

/// Package name to package root, read from the resolved package config.
Map<String, String> _loadPackageConfig(String packageRoot) {
  final file = File(p.join(packageRoot, '.dart_tool', 'package_config.json'));
  if (!file.existsSync()) {
    throw StateError('run `flutter pub get` first: ${file.path} is missing');
  }
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final base = file.absolute.uri;
  return <String, String>{
    for (final pkg in json['packages'] as List<dynamic>)
      (pkg as Map<String, dynamic>)['name'] as String: base
          .resolve(pkg['rootUri'] as String)
          .toFilePath(),
  };
}

const _flutterPackages = <String>{'flutter', 'sky_engine'};

class _Violation {
  const _Violation(this.uri, this.from);
  final String uri;
  final String from;
}

class _WalkResult {
  _WalkResult(this.parent, this.violations);
  final Map<String, String?> parent;
  final List<_Violation> violations;

  Set<String> get reached => parent.keys.toSet();

  /// The import chain from an entry point to [file].
  List<String> chainTo(String file) {
    final chain = <String>[];
    for (String? f = file; f != null; f = parent[f]) {
      chain.add(f);
    }
    return chain.reversed.toList();
  }

  List<String> describe(List<_Violation> violations) => <String>[
    for (final v in violations)
      '${chainTo(v.from).map(p.basename).join(' -> ')} imports ${v.uri}',
  ];
}

_WalkResult _walk(Iterable<String> entries, Map<String, String> packages) {
  final roots = <String, String>{
    for (final e in packages.entries) e.key: p.normalize(p.absolute(e.value)),
  };
  final parent = <String, String?>{};
  final violations = <_Violation>[];
  final pending = <String>[];
  for (final e in entries) {
    final file = p.normalize(p.absolute(e));
    parent[file] = null;
    pending.add(file);
  }
  while (pending.isNotEmpty) {
    final file = pending.removeLast();
    final source = File(file);
    if (!source.existsSync()) continue;
    final unit = parseString(
      content: source.readAsStringSync(),
      path: file,
      throwIfDiagnostics: false,
    ).unit;
    for (final directive in unit.directives) {
      final uri = switch (directive) {
        NamespaceDirective() => _vmBranch(directive),
        PartDirective() => directive.uri.stringValue,
        _ => null,
      };
      if (uri == null) continue;
      if (uri == 'dart:ui' || uri.startsWith('dart:ui_')) {
        violations.add(_Violation(uri, file));
        continue;
      }
      if (uri.startsWith('dart:')) continue;
      final String target;
      if (uri.startsWith('package:')) {
        final rest = uri.substring('package:'.length);
        final slash = rest.indexOf('/');
        if (slash < 0) continue;
        final package = rest.substring(0, slash);
        if (_flutterPackages.contains(package)) {
          violations.add(_Violation(uri, file));
          continue;
        }
        final root = roots[package];
        if (root == null) continue;
        target = p.normalize(p.join(root, 'lib', rest.substring(slash + 1)));
      } else {
        target = p.normalize(p.join(p.dirname(file), uri));
      }
      if (parent.containsKey(target)) continue;
      parent[target] = file;
      pending.add(target);
    }
  }
  return _WalkResult(parent, violations);
}

/// The URI the Dart VM compiles for [directive]: the first configuration
/// testing `dart.library.io` or `dart.library.ffi`, else the default.
String? _vmBranch(NamespaceDirective directive) {
  for (final c in directive.configurations) {
    final name = c.name.toSource().replaceAll(' ', '');
    if (name == 'dart.library.io' || name == 'dart.library.ffi') {
      return c.uri.stringValue;
    }
  }
  return directive.uri.stringValue;
}
