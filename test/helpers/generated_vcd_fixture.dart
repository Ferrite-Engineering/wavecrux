// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/variable.dart';

import 'fake_waveform_data_source.dart';

/// Reads one of the VCDs emitted by `tool/generate_riscv_fixtures.dart` into
/// an in-memory [FakeWaveformDataSource] plus the `signalRef → Variable` map
/// that `signalVariablesMapProvider` supplies at runtime.
///
/// This is **not** a VCD parser and must not grow into one — the production
/// parser is wellen, and re-introducing a Dart one is a documented
/// regression. It reads exactly the restricted subset our own generator
/// writes (`$timescale`, nested `$scope module`, `$var wire`, `$upscope`,
/// `$enddefinitions`, `$dumpvars`, `#<tick>`, scalar and `b…` vector
/// changes) so the substrate tests run against the committed fixture bytes
/// rather than a parallel hand-maintained copy of them.
class GeneratedVcdFixture {
  GeneratedVcdFixture._({
    required this.source,
    required this.variables,
    required this.variablesByPath,
  });

  /// Loads the fixture at [path] (repo-relative).
  factory GeneratedVcdFixture.load(String path) {
    final lines = File(path).readAsLinesSync();

    final scopeStack = <String>[];
    final variables = <String, Variable>{};
    final variablesByPath = <String, Variable>{};
    final changes = <String, List<SignalChange>>{};
    final widths = <String, int>{};
    var inDefinitions = true;
    var time = 0;
    var maxTime = 0;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (inDefinitions) {
        if (line.startsWith(r'$scope')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 3) scopeStack.add(parts[2]);
          continue;
        }
        if (line.startsWith(r'$upscope')) {
          if (scopeStack.isNotEmpty) scopeStack.removeLast();
          continue;
        }
        if (line.startsWith(r'$var')) {
          // $var wire <width> <id> <name> $end
          final parts = line.split(RegExp(r'\s+'));
          final width = int.parse(parts[2]);
          final id = parts[3];
          final name = parts[4];
          final scopePath = scopeStack.join('.');
          final v = Variable(
            name: name,
            varType: VarType.wire,
            direction: VarDirection.unknown,
            signalRef: id,
            scopePath: scopePath,
            bitWidth: width,
          );
          variables[id] = v;
          variablesByPath[v.fullPath] = v;
          widths[id] = width;
          changes[id] = <SignalChange>[];
          continue;
        }
        if (line.startsWith(r'$enddefinitions')) {
          inDefinitions = false;
          continue;
        }
        continue;
      }

      if (line.startsWith(r'$dumpvars') || line == r'$end') continue;
      if (line.startsWith('#')) {
        time = int.parse(line.substring(1));
        if (time > maxTime) maxTime = time;
        continue;
      }
      if (line.startsWith('b')) {
        // b<bits> <id>
        final sep = line.indexOf(' ');
        final bits = line.substring(1, sep);
        final id = line.substring(sep + 1).trim();
        changes[id]?.add(SignalChange(time: time, value: bits));
        continue;
      }
      // Scalar: <level><id>
      final level = line.substring(0, 1);
      final id = line.substring(1).trim();
      changes[id]?.add(SignalChange(time: time, value: level));
    }

    // Rebuild a single flat scope tree matching the declared hierarchy. The
    // substrate reads names and scope paths off the Variable map, so a flat
    // root scope carrying every variable is sufficient for the fake.
    final scope = Scope(
      name: 'root',
      type: ScopeType.module,
      path: '',
      variables: variables.values.toList(),
    );

    return GeneratedVcdFixture._(
      source: FakeWaveformDataSource(
        scopes: [scope],
        signals: changes,
        endTime: maxTime,
      ),
      variables: Map.unmodifiable(variables),
      variablesByPath: Map.unmodifiable(variablesByPath),
    );
  }

  /// In-memory data source over the fixture's value changes.
  final FakeWaveformDataSource source;

  /// `signalRef → Variable`, keyed exactly as `signalVariablesMapProvider`.
  final Map<String, Variable> variables;

  /// `fullPath → Variable`, for tests that want to name a signal.
  final Map<String, Variable> variablesByPath;

  /// The signal ref declared for [fullPath].
  String refFor(String fullPath) => variablesByPath[fullPath]!.signalRef;
}
