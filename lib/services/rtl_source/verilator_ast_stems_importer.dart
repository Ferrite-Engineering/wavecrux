// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/stems_entry.dart';
import 'package:wavecrux/domain/models/stems_file.dart';

/// The outcome of importing a Verilator `--json-only` AST dump.
@immutable
class VerilatorAstImportResult {
  const VerilatorAstImportResult({
    required this.stems,
    required this.resolvedTop,
    required this.availableTops,
    required this.warnings,
  });

  /// The elaborated stems file (empty when no top module could be resolved).
  final StemsFile stems;

  /// The top module the hierarchy was elaborated from, or null when none was
  /// found / resolvable.
  final String? resolvedTop;

  /// All candidate top modules (declared but never instantiated), sorted —
  /// surfaced so the UI can let the user pick when ambiguous.
  final List<String> availableTops;

  /// Human-readable, non-fatal notes (schema surprises, unresolved
  /// instances, no top, …).
  final List<String> warnings;
}

/// Converts a `verilator --json-only` AST dump (`V<top>.tree.json` plus its
/// sibling `V<top>.tree.meta.json`) into the [StemsFile] model, making
/// Verilator's fully elaborated hierarchy a stems source.
///
/// Compared to the best-effort [StemsGenerator] source parse, the Verilator
/// dump is post-elaboration: generate-for loops arrive unrolled as `GENBLOCK`
/// nodes with indexed names (`gen_blink[0]` …), so the emitted paths match
/// the waveform hierarchy exactly.
///
/// The JSON schema is Verilator-internal with no stability contract (written
/// against Verilator 5.048 — see the fixtures README), so this importer is
/// deliberately tolerant: anything unrecognised or unresolvable is skipped
/// and recorded in [VerilatorAstImportResult.warnings], never thrown.
class VerilatorAstStemsImporter {
  const VerilatorAstStemsImporter();

  /// AST `varType` values that never correspond to a waveform signal.
  static const Set<String> _skippedVarTypes = {'GPARAM', 'LPARAM', 'GENVAR'};

  /// Imports from already-read JSON strings. When [topModule] is null, a
  /// unique uninstantiated module is auto-selected as the top.
  VerilatorAstImportResult import({
    required String treeJson,
    required String metaJson,
    String? topModule,
  }) {
    final warnings = <String>[];

    final tree = _decode(treeJson, 'tree JSON', warnings);
    final meta = _decode(metaJson, 'meta JSON', warnings);
    if (tree == null || meta == null) return _empty(warnings);

    // 1. File table: letter code → source path (realpath preferred).
    //    Entries whose filename starts with '<' are Verilator internals
    //    (<verilated_std>, <built-in>, …) and are filtered from the import.
    final files = <String, String>{};
    final internalFiles = <String>{};
    final rawFiles = meta['files'];
    if (rawFiles is Map<String, Object?>) {
      rawFiles.forEach((code, entry) {
        if (entry is! Map<String, Object?>) return;
        final filename = entry['filename'];
        final realpath = entry['realpath'];
        final path = (realpath is String && realpath.isNotEmpty)
            ? realpath
            : (filename is String ? filename : null);
        if (path == null) return;
        if (filename is String && filename.startsWith('<')) {
          internalFiles.add(code);
        }
        files[code] = path;
      });
    } else {
      warnings.add(
        'Meta JSON has no "files" table; source locations cannot be '
        'resolved.',
      );
      return _empty(warnings);
    }

    // 2. Collect MODULE nodes, indexed by both name and addr (CELL nodes
    //    reference their target module via the "modp" pointer, which matches
    //    the module's "addr").
    final modules = <_Module>[];
    final byRef = <String, _Module>{};
    _collectModules(tree, modules, warnings);
    for (final m in modules) {
      final name = m.name;
      final addr = m.addr;
      if (name != null) byRef[name] = m;
      if (addr != null) byRef[addr] = m;
    }

    // Modules that are part of the user design (not @CONST-POOL@ or other
    // compiler-internal modules, not declared in an internal file).
    bool isUserModule(_Module m) {
      final name = m.name;
      if (name == null || name.isEmpty || name.startsWith('@')) return false;
      final code = _fileCodeOf(m.loc);
      return code == null || !internalFiles.contains(code);
    }

    // 3. Candidate tops = user modules never instantiated by any CELL.
    final instantiated = <String>{};
    for (final m in modules) {
      m.root.visitCells((cell) {
        final target = cell.modRef == null ? null : byRef[cell.modRef];
        final targetName = target?.name;
        if (targetName != null) instantiated.add(targetName);
      });
    }
    final tops =
        modules
            .where(isUserModule)
            .map((m) => m.name!)
            .where((n) => !instantiated.contains(n))
            .toList()
          ..sort();

    if (modules.where(isUserModule).isEmpty) {
      warnings.add('No modules were found in the AST dump.');
      return _empty(warnings);
    }

    // 4. Resolve the top to elaborate from (mirrors StemsGenerator).
    final String? top;
    if (topModule != null && byRef.containsKey(topModule)) {
      top = topModule;
    } else if (topModule != null) {
      warnings.add(
        'Requested top "$topModule" not found; '
        'falling back to auto-detection.',
      );
      top = tops.length == 1 ? tops.first : null;
    } else {
      top = tops.length == 1 ? tops.first : null;
    }

    if (top == null) {
      warnings.add(
        tops.isEmpty
            ? 'No top module found (every module is instantiated — the '
                  'design may be cyclic). Pass a top module explicitly.'
            : 'Multiple candidate top modules (${tops.join(', ')}); '
                  'pass one explicitly.',
      );
      return VerilatorAstImportResult(
        stems: const StemsFile(),
        resolvedTop: null,
        availableTops: tops,
        warnings: warnings,
      );
    }

    // 5. Elaborate the instance tree depth-first into stems entries.
    final emitter = _Emitter(byRef, files, internalFiles, warnings)
      ..elaborate(byRef[top]!, top);

    return VerilatorAstImportResult(
      stems: StemsFile(entries: emitter.entries),
      resolvedTop: top,
      availableTops: tops,
      warnings: warnings,
    );
  }

  /// Reads [treePath] (a `V<top>.tree.json`) from disk and imports it. The
  /// sibling `V<top>.tree.meta.json` is auto-located by naming convention
  /// unless [metaPath] is given. Missing or unreadable files produce a
  /// warning result, never a throw. Desktop/IO only.
  Future<VerilatorAstImportResult> importFromPath(
    String treePath, {
    String? metaPath,
    String? topModule,
  }) async {
    final resolvedMetaPath = metaPath ?? _siblingMetaPath(treePath);

    final String treeJson;
    try {
      treeJson = await File(treePath).readAsString();
    } on Object catch (e) {
      return _empty(['Could not read "$treePath": $e']);
    }

    final String metaJson;
    try {
      metaJson = await File(resolvedMetaPath).readAsString();
    } on Object catch (e) {
      final message =
          'Could not read the meta file "$resolvedMetaPath" '
          '(expected next to the tree JSON): $e';
      return _empty([message]);
    }

    return import(
      treeJson: treeJson,
      metaJson: metaJson,
      topModule: topModule,
    );
  }

  /// `V<top>.tree.json` → `V<top>.tree.meta.json` (falls back to inserting
  /// `.meta` before a plain `.json` suffix).
  static String _siblingMetaPath(String treePath) {
    if (treePath.endsWith('.tree.json')) {
      return '${treePath.substring(0, treePath.length - '.json'.length)}'
          '.meta.json';
    }
    if (treePath.endsWith('.json')) {
      return '${treePath.substring(0, treePath.length - '.json'.length)}'
          '.meta.json';
    }
    return '$treePath.meta.json';
  }

  // ── tree walking ───────────────────────────────────────────────────────────

  /// Depth-first scan for MODULE nodes anywhere in the netlist; each found
  /// module gets its member tree (vars, cells, generate scopes) collected.
  static void _collectModules(
    Object? node,
    List<_Module> out,
    List<String> warnings,
  ) {
    if (node is Map<String, Object?>) {
      if (node['type'] == 'MODULE') {
        final root = _Scope();
        _collectMembers(node, root, isModuleRoot: true);
        out.add(
          _Module(
            name: node['name'] is String ? node['name']! as String : null,
            addr: node['addr'] is String ? node['addr']! as String : null,
            loc: node['loc'] is String ? node['loc']! as String : null,
            root: root,
          ),
        );
        return; // members handled; nothing below a MODULE is another module
      }
      for (final value in node.values) {
        _collectModules(value, out, warnings);
      }
    } else if (node is List<Object?>) {
      for (final item in node) {
        _collectModules(item, out, warnings);
      }
    }
  }

  /// Collects a module's members into [scope]. Named GENBLOCK nodes open a
  /// nested scope (their names — including unrolled-loop indices like
  /// `gen_blink[0]` — become path segments); unnamed ones are transparent.
  /// CELL and VAR nodes are leaves (their children are pins / data types,
  /// not members). Unknown node types are descended through silently — the
  /// schema is Verilator-internal and carries many node kinds (ALWAYS,
  /// ASSIGNW, …) that merely contain no members.
  static void _collectMembers(
    Map<String, Object?> node,
    _Scope scope, {
    bool isModuleRoot = false,
  }) {
    if (!isModuleRoot) {
      switch (node['type']) {
        case 'MODULE':
          return; // nested module definitions are collected by the outer scan
        case 'CELL':
          final name = node['name'];
          if (name is String && name.isNotEmpty) {
            final modRef = node['modName'] ?? node['modp'];
            scope.cells.add(
              _Cell(
                name: name,
                loc: node['loc'] is String ? node['loc']! as String : null,
                modRef: modRef is String ? modRef : null,
              ),
            );
          }
          return;
        case 'VAR':
          final name = node['name'];
          final varType = node['varType'];
          if (name is String &&
              name.isNotEmpty &&
              (varType is! String || !_skippedVarTypes.contains(varType))) {
            scope.vars.add(
              _Var(
                name: name,
                loc: node['loc'] is String ? node['loc']! as String : null,
              ),
            );
          }
          return;
        case 'GENBLOCK':
          final name = node['name'];
          if (name is String && name.isNotEmpty) {
            final child = _Scope(
              name: name,
              loc: node['loc'] is String ? node['loc']! as String : null,
            );
            scope.children.add(child);
            for (final value in node.values) {
              _collectValues(value, child);
            }
            return;
          }
        // Unnamed generate block: transparent — handled by the shared
        // descent below the switch.
      }
    }
    for (final value in node.values) {
      _collectValues(value, scope);
    }
  }

  static void _collectValues(Object? value, _Scope scope) {
    if (value is Map<String, Object?>) {
      _collectMembers(value, scope);
    } else if (value is List<Object?>) {
      for (final item in value) {
        _collectValues(item, scope);
      }
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  static Map<String, Object?>? _decode(
    String json,
    String label,
    List<String> warnings,
  ) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      warnings.add('Could not parse the $label: ${e.message}');
      return null;
    }
    if (decoded is Map<String, Object?>) return decoded;
    warnings.add('The $label is not a JSON object.');
    return null;
  }

  static VerilatorAstImportResult _empty(List<String> warnings) =>
      VerilatorAstImportResult(
        stems: const StemsFile(),
        resolvedTop: null,
        availableTops: const [],
        warnings: warnings,
      );

  /// The file-table code of a `loc` string (`"e,63:19,63:34"` → `"e"`).
  static String? _fileCodeOf(String? loc) {
    if (loc == null) return null;
    final comma = loc.indexOf(',');
    return comma <= 0 ? null : loc.substring(0, comma);
  }

  /// The 1-based line number of a `loc` string (`"e,63:19,63:34"` → 63).
  static int? _lineOf(String? loc) {
    if (loc == null) return null;
    final parts = loc.split(',');
    if (parts.length < 2) return null;
    return int.tryParse(parts[1].split(':').first);
  }
}

// ── internal model ───────────────────────────────────────────────────────────

class _Module {
  const _Module({
    required this.name,
    required this.addr,
    required this.loc,
    required this.root,
  });

  final String? name;
  final String? addr;
  final String? loc;
  final _Scope root;

  /// Identity used for cycle detection during elaboration.
  String get identity => addr ?? name ?? '';
}

/// A module body or a named generate block: ordered vars, child instances,
/// and nested generate scopes.
class _Scope {
  _Scope({this.name = '', this.loc});

  final String name;
  final String? loc;
  final vars = <_Var>[];
  final cells = <_Cell>[];
  final children = <_Scope>[];

  bool get hasContent =>
      vars.isNotEmpty || cells.isNotEmpty || children.any((c) => c.hasContent);

  void visitCells(void Function(_Cell) visit) {
    cells.forEach(visit);
    for (final child in children) {
      child.visitCells(visit);
    }
  }
}

class _Var {
  const _Var({required this.name, required this.loc});

  final String name;
  final String? loc;
}

class _Cell {
  const _Cell({required this.name, required this.loc, required this.modRef});

  final String name;
  final String? loc;
  final String? modRef;
}

/// Depth-first elaboration of the instance tree into [StemsEntry]s, with
/// cycle protection and unresolved-instance tolerance (mirrors
/// StemsGenerator's elaboration semantics).
class _Emitter {
  _Emitter(this.byRef, this.files, this.internalFiles, this.warnings);

  final Map<String, _Module> byRef;
  final Map<String, String> files;
  final Set<String> internalFiles;
  final List<String> warnings;
  final entries = <StemsEntry>[];
  final _stack = <String>{};

  void elaborate(_Module module, String path) {
    if (_stack.contains(module.identity)) {
      _addEntry(path, module.loc, StemsEntryKind.scope);
      warnings.add(
        'Cyclic instantiation at "$path" (module "${module.name}"); '
        'branch truncated.',
      );
      return;
    }
    _stack.add(module.identity);
    _addEntry(path, module.loc, StemsEntryKind.scope);
    _emitScope(module.root, path);
    _stack.remove(module.identity);
  }

  void _emitScope(_Scope scope, String path) {
    for (final v in scope.vars) {
      _addEntry('$path.${v.name}', v.loc, StemsEntryKind.variable);
    }
    for (final child in scope.children) {
      // Skip empty generate scopes: the unrolled loop's wrapper block (e.g.
      // "gen_blink" alongside "gen_blink[0]"…) arrives contentless and has
      // no counterpart in the waveform hierarchy.
      if (!child.hasContent) continue;
      final childPath = '$path.${child.name}';
      _addEntry(childPath, child.loc, StemsEntryKind.scope);
      _emitScope(child, childPath);
    }
    for (final cell in scope.cells) {
      final childPath = '$path.${cell.name}';
      final target = cell.modRef == null ? null : byRef[cell.modRef];
      if (target != null) {
        elaborate(target, childPath);
      } else {
        // Unresolved module pointer: still record the instance scope,
        // pointing at the instantiation site.
        _addEntry(childPath, cell.loc, StemsEntryKind.scope);
        warnings.add(
          'Unresolved module reference "${cell.modRef}" for instance '
          '"$childPath" — target module not found in the AST dump.',
        );
      }
    }
  }

  void _addEntry(String path, String? loc, StemsEntryKind kind) {
    final code = VerilatorAstStemsImporter._fileCodeOf(loc);
    final line = VerilatorAstStemsImporter._lineOf(loc);
    if (code == null || line == null) return;
    if (internalFiles.contains(code)) return;
    final sourceFile = files[code];
    if (sourceFile == null) {
      if (_unknownFileCodes.add(code)) {
        warnings.add(
          'Unknown file reference "$code" in AST locations; affected '
          'entries were skipped.',
        );
      }
      return;
    }
    entries.add(
      StemsEntry(
        path: path,
        sourceFile: sourceFile,
        lineNumber: line,
        kind: kind,
      ),
    );
  }

  final _unknownFileCodes = <String>{};
}
