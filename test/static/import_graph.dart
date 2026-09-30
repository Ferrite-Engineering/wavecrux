// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The import graph of `lib/`, walked from the program's real entry points.
// Identical in shape to the Pro overlay's copy, which also walks across into
// this package through its path dependency.
//
// Backs `import_reachability_guard_test.dart` (every `lib/` file is reached or
// explains why not) and `action_reachability_guard_test.dart` (every declared
// action surface is consumed by a file the program actually loads).
//
// It reads directives, not symbols: a file is reached when a chain of
// `import`, `export` or `part` directives leads to it from an entry point.
// Every branch of a conditional import counts (`import 'a.dart' if
// (dart.library.io) 'b.dart'` reaches both), because each branch is the
// program on some platform. A file that is imported but whose symbols are all
// unused is still "reached" here; `flutter analyze` owns that case through
// `unused_import`.
//
// Deliberately a text scan rather than a resolved analysis. Directives sit at
// the head of a file in a fixed grammar, the walk has to see generated files
// (`.g.dart`, `l10n/generated/`) whether or not codegen has run, and it has to
// stay fast enough to run on every push.
//
// Every path the graph holds is spelled with `/`, whatever the host: the
// guards compare them to `/`-spelled constants (`lib/main.dart`), and on
// Windows a path built by the platform reads `lib\main.dart`, which matches
// none of them. Paths are converted once, where they enter, and only opening
// a file goes back through the host's `path` context.

import 'dart:io';

import 'package:path/path.dart' as p;

/// The directive-level import graph of one package's `lib/` tree.
class ImportGraph {
  ImportGraph._(this.root, this.packageName, this.dependencies);

  /// Walks `lib/` of the package at [root], named [packageName] in `pubspec`,
  /// from [entryPoints] (paths relative to [root], e.g. `lib/main.dart`).
  ///
  /// `package:` URIs are followed into [dependencies] — package name to that
  /// package's root, relative to [root] — and nowhere else: a package the walk
  /// is not told about is outside the program being checked.
  factory ImportGraph.walk({
    required String root,
    required String packageName,
    required List<String> entryPoints,
    Map<String, String> dependencies = const <String, String>{},
  }) {
    final graph = ImportGraph._(root, packageName, dependencies);
    final pending = <String>[...entryPoints.map(_portable)];
    while (pending.isNotEmpty) {
      final file = pending.removeLast();
      if (!graph.reached.add(file)) continue;
      final source = File(p.join(root, file));
      if (!source.existsSync()) {
        graph.missing.add(file);
        continue;
      }
      final targets = <String>[];
      for (final uri in directiveUris(source.readAsStringSync())) {
        final target = graph._resolve(file, uri);
        if (target != null) targets.add(target);
      }
      graph.edges[file] = targets;
      pending.addAll(targets.where((t) => !graph.reached.contains(t)));
    }
    return graph;
  }

  /// The package root every path in this graph is relative to.
  final String root;

  /// The package's own name, as `package:<name>/` URIs spell it.
  final String packageName;

  /// Other packages the walk follows into, by name, each mapped to its root
  /// relative to [root]. A file reached there is named `<that root>/lib/…`.
  final Map<String, String> dependencies;

  /// Every file reached from the entry points, relative to [root], spelled
  /// with `/`.
  final Set<String> reached = <String>{};

  /// Files a directive names that do not exist on disk. Expected only for
  /// generated code before codegen has run.
  final Set<String> missing = <String>{};

  /// Outgoing directive targets per reached file.
  final Map<String, List<String>> edges = <String, List<String>>{};

  /// Every `.dart` file under `lib/`, relative to [root], excluding parts.
  ///
  /// A `part of` file shares its library's fate: it is reached exactly when
  /// its library is, and a stale part left behind by a deleted library (a
  /// `.g.dart` codegen will never rewrite) is build output, not source.
  List<String> libraryFiles() => [
    for (final file in sourceFiles())
      if (!isPartFile(File(p.join(root, file)).readAsStringSync())) file,
  ];

  /// Every `.dart` file under `lib/`, relative to [root], parts included.
  List<String> sourceFiles() {
    final lib = Directory(p.join(root, 'lib'));
    return [
      for (final entity in lib.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          _portable(p.relative(entity.path, from: root)),
    ]..sort();
  }

  String? _resolve(String from, String uri) {
    if (uri.startsWith('dart:')) return null;
    if (uri.startsWith('package:')) {
      final path = uri.substring('package:'.length);
      final slash = path.indexOf('/');
      if (slash < 0) return null;
      final name = path.substring(0, slash);
      final inLib = path.substring(slash + 1);
      if (name == packageName) return _url.normalize(_url.join('lib', inLib));
      final dependency = dependencies[name];
      if (dependency == null) return null;
      return _url.normalize(_url.join(_portable(dependency), 'lib', inLib));
    }
    return _url.normalize(_url.join(_url.dirname(from), uri));
  }
}

/// The `/`-separated context every graph path is spelled in. Directive URIs
/// already use `/`, on every host.
final p.Context _url = p.url;

/// [path], a host-spelled relative path, normalised and spelled with `/`.
String _portable(String path) => _url.joinAll(p.split(p.normalize(path)));

final _directiveStart = RegExp(r'^(import|export|part)\s');
final _libraryDirective = RegExp(r'^library\b');
final _partOf = RegExp(r'^part\s+of\b');
final _stringLiteral = RegExp('''['"]([^'"]+)['"]''');

/// The `.dart` URIs named by the directives at the head of [source], including
/// every branch of a conditional import or export.
///
/// Stops at the first line that is not a directive, a comment, an annotation
/// or `library`: directives cannot follow a declaration, and a later line that
/// merely looks like one (a multi-line string holding generated Dart source)
/// must not be read as a dependency.
List<String> directiveUris(String source) {
  final uris = <String>[];
  final lines = source.split('\n');
  var inBlockComment = false;
  var i = 0;
  while (i < lines.length) {
    final line = lines[i].trim();
    if (inBlockComment) {
      if (line.contains('*/')) inBlockComment = false;
      i++;
      continue;
    }
    if (line.startsWith('/*')) {
      inBlockComment = !line.contains('*/');
      i++;
      continue;
    }
    if (line.isEmpty || line.startsWith('//') || line.startsWith('@')) {
      i++;
      continue;
    }
    final isLibrary = _libraryDirective.hasMatch(line);
    final isDirective =
        _directiveStart.hasMatch(line) && !_partOf.hasMatch(line);
    if (!isLibrary && !isDirective && !_partOf.hasMatch(line)) break;
    final statement = StringBuffer(line);
    while (!statement.toString().contains(';') && i + 1 < lines.length) {
      i++;
      statement.write(' ${lines[i].trim()}');
    }
    if (isDirective) {
      final text = statement.toString();
      final body = text.substring(0, text.indexOf(';'));
      for (final match in _stringLiteral.allMatches(body)) {
        final uri = match.group(1)!;
        if (uri.endsWith('.dart')) uris.add(uri);
      }
    }
    i++;
  }
  return uris;
}

/// Whether [source] is a `part of` file.
bool isPartFile(String source) {
  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('//')) continue;
    return _partOf.hasMatch(line);
  }
  return false;
}

/// [source] with `//` and `/* */` comments removed, string contents kept.
///
/// For the guards that ask whether a file *uses* a name rather than mentions
/// it: a doc comment that still names a deleted widget is exactly the prose
/// the reachability guards exist to stop believing.
String stripComments(String source) {
  final out = StringBuffer();
  var i = 0;
  String? quote;
  var raw = false;
  while (i < source.length) {
    final c = source[i];
    if (quote != null) {
      out.write(c);
      if (!raw && c == r'\' && i + 1 < source.length) {
        out.write(source[i + 1]);
        i += 2;
        continue;
      }
      if (source.startsWith(quote, i)) {
        out.write(source.substring(i + 1, i + quote.length));
        i += quote.length;
        quote = null;
        continue;
      }
      i++;
      continue;
    }
    if (source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      i = end < 0 ? source.length : end;
      continue;
    }
    if (source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      i = end < 0 ? source.length : end + 2;
      continue;
    }
    if (c == "'" || c == '"') {
      raw = i > 0 && source[i - 1] == 'r';
      quote = source.startsWith(c * 3, i) ? c * 3 : c;
      out.write(quote);
      i += quote.length;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}
