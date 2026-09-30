// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/stems_entry.dart';
import 'package:wavecrux/domain/models/stems_file.dart';
import 'package:wavecrux/services/rtl_source/hdl_declaration_parser.dart';
import 'package:wavecrux/services/rtl_source/hdl_module.dart';

/// The outcome of a stems-generation pass.
@immutable
class StemsGenerationResult {
  const StemsGenerationResult({
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

  /// All candidate top modules (declared but never instantiated by another
  /// module), sorted — surfaced so the UI can let the user pick when ambiguous.
  final List<String> availableTops;

  /// Human-readable, non-fatal notes (unresolved instance types, no top, …).
  final List<String> warnings;
}

/// Generates a GTKWave-compatible stems file by parsing an HDL source tree and
/// elaborating the module hierarchy from a top module.
///
/// This is the in-app replacement for GTKWave's `xml2stems` / `vermin`, so a
/// WaveCrux-only user can produce stems without installing GTKWave. It uses the
/// best-effort [HdlDeclarationParser]; see that class for the recognised subset
/// and limitations. Anything unresolved is recorded in
/// [StemsGenerationResult.warnings] and simply omitted — never fatal.
class StemsGenerator {
  const StemsGenerator({
    HdlDeclarationParser parser = const HdlDeclarationParser(),
  }) : _parser = parser;

  final HdlDeclarationParser _parser;

  /// Generates from already-read [sources] (path → content). When [topModule]
  /// is null, a unique uninstantiated module is auto-selected as the top.
  StemsGenerationResult generate({
    required Map<String, String> sources,
    String? topModule,
  }) {
    // 1. Parse every file and merge modules that share a name (e.g. a VHDL
    //    entity + its architecture, or a module split across files).
    final byName = <String, HdlModule>{};
    sources.forEach((path, content) {
      for (final m in _parser.parse(sourceFile: path, content: content)) {
        final existing = byName[m.name];
        byName[m.name] = existing == null ? m : existing.mergedWith(m);
      }
    });

    final warnings = <String>[];
    if (byName.isEmpty) {
      return const StemsGenerationResult(
        stems: StemsFile(),
        resolvedTop: null,
        availableTops: [],
        warnings: ['No modules or entities were found in the selected files.'],
      );
    }

    // 2. Candidate tops = modules never instantiated by any other module.
    final instantiated = <String>{
      for (final m in byName.values)
        for (final inst in m.instances) inst.moduleType,
    };
    final tops = byName.keys.where((n) => !instantiated.contains(n)).toList()
      ..sort();

    // 3. Resolve the top to elaborate from.
    final String? top;
    if (topModule != null && byName.containsKey(topModule)) {
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
            ? 'No top module found (every module is instantiated — the design '
                  'may be cyclic). Pass a top module explicitly.'
            : 'Multiple candidate top modules (${tops.join(', ')}); '
                  'pass one explicitly.',
      );
      return StemsGenerationResult(
        stems: const StemsFile(),
        resolvedTop: null,
        availableTops: tops,
        warnings: warnings,
      );
    }

    // 4. Elaborate the hierarchy depth-first into stems entries.
    final entries = <StemsEntry>[];
    final stack = <String>{};
    void elaborate(String moduleName, String scopePath) {
      final module = byName[moduleName];
      if (module == null) return;
      if (stack.contains(moduleName)) {
        // Cycle: record the node so the hierarchy is complete, but stop
        // descending to keep elaboration finite.
        entries.add(
          StemsEntry(
            path: scopePath,
            sourceFile: module.sourceFile,
            lineNumber: module.declarationLine,
            kind: StemsEntryKind.scope,
          ),
        );
        warnings.add(
          'Cyclic instantiation at "$scopePath" '
          '(module "$moduleName"); branch truncated.',
        );
        return;
      }
      stack.add(moduleName);
      entries.add(
        StemsEntry(
          path: scopePath,
          sourceFile: module.sourceFile,
          lineNumber: module.declarationLine,
          kind: StemsEntryKind.scope,
        ),
      );
      for (final sig in module.signals) {
        entries.add(
          StemsEntry(
            path: '$scopePath.${sig.name}',
            sourceFile: module.sourceFile,
            lineNumber: sig.lineNumber,
            kind: StemsEntryKind.variable,
          ),
        );
      }
      for (final inst in module.instances) {
        final childPath = '$scopePath.${inst.instanceName}';
        if (byName.containsKey(inst.moduleType)) {
          elaborate(inst.moduleType, childPath);
        } else {
          // Unresolved type (library cell, missing file): still record the
          // instance scope, pointing at the instantiation site.
          entries.add(
            StemsEntry(
              path: childPath,
              sourceFile: module.sourceFile,
              lineNumber: inst.lineNumber,
              kind: StemsEntryKind.scope,
            ),
          );
          warnings.add(
            'Unresolved module type "${inst.moduleType}" for '
            'instance "$childPath" — source not found among selected files.',
          );
        }
      }
      stack.remove(moduleName);
    }

    elaborate(top, top);

    return StemsGenerationResult(
      stems: StemsFile(entries: entries),
      resolvedTop: top,
      availableTops: tops,
      warnings: warnings,
    );
  }

  /// Reads [paths] from disk and generates a stems file. Files that cannot be
  /// read are skipped with a warning. Desktop/IO only.
  Future<StemsGenerationResult> generateFromPaths(
    List<String> paths, {
    String? topModule,
  }) async {
    final sources = <String, String>{};
    final readWarnings = <String>[];
    for (final path in paths) {
      try {
        sources[path] = await File(path).readAsString();
      } on Object catch (e) {
        readWarnings.add('Could not read "$path": $e');
      }
    }
    final result = generate(sources: sources, topModule: topModule);
    if (readWarnings.isEmpty) return result;
    return StemsGenerationResult(
      stems: result.stems,
      resolvedTop: result.resolvedTop,
      availableTops: result.availableTops,
      warnings: [...readWarnings, ...result.warnings],
    );
  }
}
