// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/models/rohd_dart_source.dart';
import 'package:wavecrux/services/rohd/rohd_sidecar.dart';

/// Joins a waveform signal to the Dart line that created it, through a ROHD
/// source-trace sidecar (ROHD 0.7 or later, source tracing).
///
/// The waveform ROHD writes (`WaveDumper`) holds a `$scope module` per module
/// instance, named by the instance's unique name, and a `$var` per signal. It
/// carries no source data. The sidecar lists, per generated module, the
/// hierarchy paths that share it (`sourceOccurrences`) and its traced signals.
/// Joining the two is: the signal's scope path to an occurrence path, then its
/// name to a leaf of that module.
///
/// **Names the join has to bridge**
///
/// - *Keyword renames.* ROHD names an instance `reg` in the sidecar and writes
///   `reg_` into the SystemVerilog and the waveform, because `reg` is a
///   SystemVerilog keyword. A scope path is tried as written first, then with
///   a trailing `_` dropped from any subset of its parts, fewest drops first.
/// - *Renamed fields.* A struct field is `inner_pkt_data` in the SystemVerilog
///   and `data` in the waveform; the sidecar keeps both (`name~data`). A name
///   matches a leaf's own name first and its original name second.
/// - *Bus slices.* Two slices of one signal are separate occurrences under one
///   path, each tracing a copy of the signal's name. When those names trace to
///   different Dart lines the choice between them cannot be made from the
///   waveform; the first the sidecar listed is returned and
///   [RohdDartSource.candidates] says how many there were.
///
/// A signal with no leaf (a whole-struct aggregate, a scope the design did not
/// trace) resolves to `null`: the caller offers nothing.
class RohdWaveMap {
  RohdWaveMap._(this._sidecar, this._byPath, this._resolveFile);

  /// Builds a map from [sidecar].
  ///
  /// [resolveFile] turns a path as the sidecar spells it
  /// (`.dart_tool/../lib/design.dart`) into the file on this machine.
  factory RohdWaveMap.fromSidecar(
    RohdSidecar sidecar, {
    required String Function(String) resolveFile,
  }) {
    final byPath = <String, List<RohdModule>>{};
    for (final module in sidecar.modules) {
      for (final path in module.instancePaths) {
        final list = byPath.putIfAbsent(path, () => <RohdModule>[]);
        // A module listed twice under one path (two bus slices) is searched
        // once; its leaves already include both slices.
        if (!list.contains(module)) list.add(module);
      }
    }
    return RohdWaveMap._(sidecar, byPath, resolveFile);
  }

  final RohdSidecar _sidecar;
  final Map<String, List<RohdModule>> _byPath;
  final String Function(String) _resolveFile;

  /// Whether [path] is a hierarchy path the sidecar describes (as written, or
  /// by the keyword rename).
  bool knowsPath(String path) => _pathsFor(path).any(_byPath.containsKey);

  /// The Dart source for the signal [name] in the scope [scopePath], or `null`.
  RohdDartSource? resolve(String scopePath, String name) {
    for (final path in _pathsFor(scopePath)) {
      final modules = _byPath[path];
      if (modules == null) continue;
      final leaves = <RohdLeaf>[
        for (final m in modules) ...m.leaves.where((l) => l.name == name),
      ];
      if (leaves.isEmpty) {
        leaves.addAll([
          for (final m in modules) ...m.leaves.where((l) => l.original == name),
        ]);
      }
      if (leaves.isEmpty) continue;
      return _source(leaves);
    }
    return null;
  }

  RohdDartSource? _source(List<RohdLeaf> leaves) {
    // Distinct by the innermost frame: two leaves that trace to one Dart line
    // are one answer, not a choice.
    final distinct = <RohdFrame, RohdLeaf>{};
    for (final leaf in leaves) {
      if (leaf.frames.isEmpty) continue;
      distinct.putIfAbsent(leaf.frames.last, () => leaf);
    }
    if (distinct.isEmpty) return null;
    final chosen = distinct.values.first;
    RohdDartLocation? locate(RohdFrame f) {
      if (f.fileIndex >= _sidecar.files.length) return null;
      return RohdDartLocation(
        file: _resolveFile(_sidecar.files[f.fileIndex]),
        line: f.line,
        column: f.column,
      );
    }

    final frames = <RohdDartLocation>[
      for (final f in chosen.frames.reversed)
        if (locate(f) case final RohdDartLocation l) l,
    ];
    if (frames.isEmpty) return null;
    return RohdDartSource(
      primary: frames.first,
      calledFrom: frames.skip(1).toList(growable: false),
      candidates: distinct.length,
    );
  }

  /// The scope path as written, then with a trailing `_` dropped from each
  /// subset of the parts that have one, fewest drops first.
  static List<String> _pathsFor(String scopePath) {
    final parts = scopePath.split('.');
    final renamed = <int>[
      for (var i = 0; i < parts.length; i++)
        if (parts[i].length > 1 && parts[i].endsWith('_')) i,
    ];
    // A hierarchy deep in keyword-named instances is not a thing; the cap
    // keeps a pathological scope from producing a million candidates.
    final usable = renamed.take(8).toList(growable: false);
    final out = <String>[scopePath];
    final masks = <int>[for (var m = 1; m < (1 << usable.length); m++) m]
      ..sort((a, b) {
        final byCount = _bits(a).compareTo(_bits(b));
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    for (final mask in masks) {
      final copy = List<String>.of(parts);
      for (var b = 0; b < usable.length; b++) {
        if (mask & (1 << b) != 0) {
          final i = usable[b];
          copy[i] = copy[i].substring(0, copy[i].length - 1);
        }
      }
      out.add(copy.join('.'));
    }
    return out;
  }

  static int _bits(int v) {
    var n = 0;
    for (var x = v; x != 0; x &= x - 1) {
      n++;
    }
    return n;
  }
}
