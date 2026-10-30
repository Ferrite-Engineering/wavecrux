// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Reader for the source-trace sidecar ROHD writes beside generated
/// SystemVerilog: `<Top>.flc.json`, "FLC" for file, line, column.
///
/// ROHD 0.7 or later writes it when `SourceTracer.activate()` ran before the
/// design was built and `TraceService(...).write(dir)` ran after. The waveform
/// ROHD's WaveDumper writes carries no source data itself; the sidecar is how
/// a signal in the waveform is joined to the Dart line that created it. This
/// reader understands **version 6**; any other version is refused with a
/// reason and nothing is mapped.
///
/// What WaveCrux needs from it:
///
/// - `files`: the Dart files frames refer to, as `.dart_tool/../lib/x.dart`;
/// - each module's `sourceOccurrences`: the hierarchy paths that share the
///   module (`top`, `top.reg`, `top.adder.add`), which are the instance names
///   the waveform's scopes carry;
/// - each module's `tree`: a trie of Dart frames, outermost first, whose
///   leaves are the module's signals. A leaf reads `[*]name[@pos...][~orig]`,
///   `~orig` being the Dart name before SystemVerilog renaming.
///
/// **Never throws.** Wrong types and unknown shapes are skipped.
library;

import 'dart:convert';

import 'package:meta/meta.dart';

/// A Dart frame: `fileIndex:line:column`.
@immutable
class RohdFrame {
  /// Creates a frame.
  const RohdFrame(this.fileIndex, this.line, this.column);

  /// Parses `0:26:18` (or `0:26`), or returns `null`.
  static RohdFrame? parse(String text) {
    final parts = text.split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final file = int.tryParse(parts[0]);
    final line = int.tryParse(parts[1]);
    final column = parts.length == 3 ? int.tryParse(parts[2]) : 1;
    if (file == null || line == null || column == null) return null;
    if (file < 0 || line < 1 || column < 1) return null;
    return RohdFrame(file, line, column);
  }

  /// Index into the sidecar's `files`.
  final int fileIndex;

  /// 1-based line.
  final int line;

  /// 1-based column.
  final int column;

  @override
  bool operator ==(Object other) =>
      other is RohdFrame &&
      other.fileIndex == fileIndex &&
      other.line == line &&
      other.column == column;

  @override
  int get hashCode => Object.hash(fileIndex, line, column);

  @override
  String toString() => '$fileIndex:$line:$column';
}

/// One traced name in a generated module.
@immutable
class RohdLeaf {
  /// Creates a leaf.
  const RohdLeaf({
    required this.name,
    required this.frames,
    this.original,
    this.isInstance = false,
  });

  /// The SystemVerilog name.
  final String name;

  /// The Dart name before renaming (`~data`), when it differs.
  final String? original;

  /// Whether this is a submodule instance or a block, not a signal.
  final bool isInstance;

  /// The Dart frames that created it, **outermost first**; the last is the
  /// innermost, the line that made the signal.
  final List<RohdFrame> frames;
}

/// One generated module.
@immutable
class RohdModule {
  /// Creates a module.
  const RohdModule({
    required this.name,
    required this.instancePaths,
    required this.leaves,
  });

  /// The module's key in the sidecar.
  final String name;

  /// Every hierarchy path that shares this module, in the sidecar's order. A
  /// path can appear more than once: ROHD lists each bus slice of a signal as
  /// its own occurrence, all under the same path.
  final List<String> instancePaths;

  /// Every traced name, in tree order.
  final List<RohdLeaf> leaves;
}

/// A parsed sidecar.
@immutable
class RohdSidecar {
  /// Creates a sidecar.
  const RohdSidecar({
    required this.files,
    required this.modules,
    this.packageRoot,
  });

  /// The only version this reader understands.
  static const int supportedVersion = 6;

  /// The Dart files frames refer to, as written.
  final List<String> files;

  /// The generated modules.
  final List<RohdModule> modules;

  /// The absolute package root on the machine that generated it, if recorded.
  final String? packageRoot;
}

/// The result of reading a sidecar: the sidecar, or why there is none.
@immutable
class RohdSidecarResult {
  const RohdSidecarResult._(this.sidecar, this.problem);

  /// A readable sidecar.
  const RohdSidecarResult.ok(RohdSidecar sidecar) : this._(sidecar, null);

  /// A sidecar that cannot be used, with a sentence saying why.
  const RohdSidecarResult.unusable(String problem) : this._(null, problem);

  /// The sidecar, or `null`.
  final RohdSidecar? sidecar;

  /// Why [sidecar] is null.
  final String? problem;
}

/// Parses sidecar [text].
RohdSidecarResult parseRohdSidecar(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return const RohdSidecarResult.unusable('it is not valid JSON');
  }
  if (decoded is! Map<String, Object?>) {
    return const RohdSidecarResult.unusable('it is not a JSON object');
  }
  final version = decoded['version'];
  if (version != RohdSidecar.supportedVersion) {
    return RohdSidecarResult.unusable(
      version is int
          ? 'it is version $version and WaveCrux reads version '
                '${RohdSidecar.supportedVersion}'
          : 'it has no version number and WaveCrux reads version '
                '${RohdSidecar.supportedVersion}',
    );
  }
  final filesRaw = decoded['files'];
  final modules = <RohdModule>[];
  final modulesRaw = decoded['modules'];
  if (modulesRaw is Map<String, Object?>) {
    for (final entry in modulesRaw.entries) {
      final module = entry.value;
      if (module is! Map<String, Object?>) continue;
      modules.add(
        RohdModule(
          name: entry.key,
          instancePaths: _instancePaths(module['sourceOccurrences']),
          leaves: _leaves(module['tree']),
        ),
      );
    }
  }
  final root = decoded['packageRoot'];
  return RohdSidecarResult.ok(
    RohdSidecar(
      files: <String>[
        if (filesRaw is List<Object?>)
          for (final f in filesRaw)
            if (f is String) f,
      ],
      modules: modules,
      packageRoot: root is String && root.isNotEmpty ? root : null,
    ),
  );
}

List<String> _instancePaths(Object? occurrences) {
  if (occurrences is! List<Object?>) return const <String>[];
  return <String>[
    for (final o in occurrences)
      if (o is Map<String, Object?> && o['path'] is String)
        o['path']! as String,
  ];
}

const int _maxDepth = 64;

List<RohdLeaf> _leaves(Object? tree) {
  final out = <RohdLeaf>[];
  if (tree is List<Object?>) {
    for (final node in tree) {
      _walk(node, const <RohdFrame>[], out, 0);
    }
  }
  return out;
}

void _walk(
  Object? node,
  List<RohdFrame> outer,
  List<RohdLeaf> out,
  int depth,
) {
  if (node is! List<Object?> || node.isEmpty || depth > _maxDepth) return;
  final head = node.first;
  if (head is! String) return;
  final frame = RohdFrame.parse(head);
  if (frame == null) return;
  final frames = <RohdFrame>[...outer, frame];
  for (final child in node.skip(1)) {
    if (child is String) {
      final leaf = _leaf(child, frames);
      if (leaf != null) out.add(leaf);
    } else {
      _walk(child, frames, out, depth + 1);
    }
  }
}

RohdLeaf? _leaf(String text, List<RohdFrame> frames) {
  var body = text;
  final isInstance = body.startsWith('*');
  if (isInstance) body = body.substring(1);
  String? original;
  final tilde = body.indexOf('~');
  if (tilde >= 0) {
    original = body.substring(tilde + 1);
    body = body.substring(0, tilde);
    if (original.isEmpty) original = null;
  }
  final at = body.indexOf('@');
  final name = at >= 0 ? body.substring(0, at) : body;
  if (name.isEmpty) return null;
  return RohdLeaf(
    name: name,
    original: original,
    isInstance: isInstance,
    frames: frames,
  );
}
