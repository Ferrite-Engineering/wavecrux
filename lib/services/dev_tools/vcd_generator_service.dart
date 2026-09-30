// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:math';

/// Configuration for the synthetic VCD generator.
class VcdGeneratorConfig {
  const VcdGeneratorConfig({
    this.signalCount = 10,
    this.duration = 10000,
    this.includeAnalog = false,
    this.includeXz = false,
    this.seed = 42,
  });

  /// Number of signals to generate (clamped to 1–500).
  final int signalCount;

  /// Simulation duration in timesteps (clamped to 100–1,000,000).
  final int duration;

  /// Whether to include real-valued (analog) signals.
  final bool includeAnalog;

  /// Whether to include unknown (X) and high-impedance (Z) values.
  final bool includeXz;

  /// Random seed for deterministic generation.
  final int seed;
}

/// Generates synthetic, valid VCD (Value Change Dump) content for dev/test use.
///
/// Output is always a valid VCD that can be parsed by [WellenProvider].
/// Generation is deterministic: the same [VcdGeneratorConfig] always produces
/// the same output.
class VcdGeneratorService {
  // VCD identifier codes use printable ASCII 33–126 (94 characters).
  static const int _idOffset = 33;
  static const int _idBase = 94;

  // VCD keyword constants — using raw strings to avoid escape issues.
  static const _kDate = r'$date';
  static const _kVersion = r'$version';
  static const _kTimescale = r'$timescale';
  static const _kScope = r'$scope';
  static const _kUpscope = r'$upscope';
  static const _kVar = r'$var';
  static const _kEnddefs = r'$enddefinitions';
  static const _kDumpvars = r'$dumpvars';
  static const _kEnd = r'$end';

  /// Maps a zero-based signal index to a unique VCD identifier code string.
  static String _idCode(int index) {
    assert(index >= 0, 'index must be non-negative');
    if (index < _idBase) return String.fromCharCode(_idOffset + index);
    return String.fromCharCode(_idOffset + index ~/ _idBase) +
        String.fromCharCode(_idOffset + index % _idBase);
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Generates a complete VCD string for the given [config].
  String generate(VcdGeneratorConfig config) {
    final random = Random(config.seed);
    final signals = _buildSignals(config, random);
    final buf = StringBuffer();
    _writeHeader(buf, config);
    _writeHierarchy(buf, signals);
    buf.writeln('$_kEnddefs $_kEnd');
    _writeDumpvars(buf, signals);
    _writeTransitions(buf, signals, config, random);
    return buf.toString();
  }

  /// Generates VCD content and writes it to a temp file.
  ///
  /// Returns the absolute path to the written file.
  Future<String> generateToTempFile(VcdGeneratorConfig config) async {
    final content = generate(config);
    final file = File(
      '${Directory.systemTemp.path}/wavecrux_sample_s${config.signalCount}_d${config.duration}_seed${config.seed}.vcd',
    );
    await file.writeAsString(content);
    return file.path;
  }

  // ── Signal list ─────────────────────────────────────────────────────────────

  List<_Signal> _buildSignals(VcdGeneratorConfig cfg, Random r) {
    // Upper bound raised from 500 to 10000 to support performance-benchmark
    // scenarios (1000+ visible signals on desktop). The UI
    // slider still tops out at 500 — only programmatic callers see the larger
    // range.
    final count = cfg.signalCount.clamp(1, 10000);
    final signals = <_Signal>[];

    // Scope layout: always 'top'; add child scopes when signal count is large.
    final List<String> scopes;
    if (count <= 4) {
      scopes = ['top'];
    } else if (count <= 20) {
      scopes = ['top', 'top.ctrl', 'top.dpath'];
    } else {
      scopes = ['top', 'top.ctrl', 'top.dpath', 'top.mem', 'top.io'];
    }

    // Signal 0: always a 1-bit clock in the top scope.
    signals.add(
      _Signal(
        id: _idCode(0),
        name: 'clk',
        scope: 'top',
        kind: _Kind.scalar,
        width: 1,
      ),
    );

    const busSizes = [4, 8, 16, 32];

    for (var i = 1; i < count; i++) {
      final scope = scopes[i % scopes.length];
      final roll = r.nextDouble();

      final _Kind kind;
      final int width;
      final String name;

      if (cfg.includeAnalog && roll < 0.10) {
        kind = _Kind.real;
        width = 1; // VCD requires width=1 for real variables
        name = 'analog$i';
      } else if (roll < 0.45) {
        kind = _Kind.scalar;
        width = 1;
        name = 'sig$i';
      } else {
        kind = _Kind.bus;
        width = busSizes[r.nextInt(busSizes.length)];
        name = 'bus${width}_$i';
      }

      signals.add(
        _Signal(
          id: _idCode(i),
          name: name,
          scope: scope,
          kind: kind,
          width: width,
        ),
      );
    }

    return signals;
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  void _writeHeader(StringBuffer buf, VcdGeneratorConfig cfg) {
    buf
      ..writeln('$_kDate 2026-01-01 00:00:00 $_kEnd')
      ..writeln(
        '$_kVersion WaveCrux Sample Generator (signals=${cfg.signalCount} seed=${cfg.seed}) $_kEnd',
      )
      ..writeln('$_kTimescale 1ns $_kEnd');
  }

  // ── Hierarchy ───────────────────────────────────────────────────────────────

  void _writeHierarchy(StringBuffer buf, List<_Signal> signals) {
    final byScope = <String, List<_Signal>>{};
    for (final s in signals) {
      byScope.putIfAbsent(s.scope, () => []).add(s);
    }

    final tops = byScope.keys.where((s) => !s.contains('.')).toList()..sort();

    for (final top in tops) {
      buf.writeln('$_kScope module $top $_kEnd');
      for (final sig in byScope[top] ?? <_Signal>[]) {
        _writeVarDecl(buf, sig, indent: 1);
      }
      final children =
          byScope.keys
              .where(
                (s) =>
                    s.startsWith('$top.') &&
                    !s.substring(top.length + 1).contains('.'),
              )
              .toList()
            ..sort();
      for (final child in children) {
        final childName = child.substring(top.length + 1);
        buf.writeln('  $_kScope module $childName $_kEnd');
        for (final sig in byScope[child] ?? <_Signal>[]) {
          _writeVarDecl(buf, sig, indent: 2);
        }
        buf.writeln('  $_kUpscope $_kEnd');
      }
      buf.writeln('$_kUpscope $_kEnd');
    }
  }

  void _writeVarDecl(StringBuffer buf, _Signal sig, {required int indent}) {
    final pad = '  ' * indent;
    final typeStr = sig.kind == _Kind.real ? 'real' : 'wire';
    final range = sig.kind == _Kind.bus ? ' [${sig.width - 1}:0]' : '';
    buf.writeln(
      '$pad$_kVar $typeStr ${sig.width} ${sig.id} ${sig.name}$range $_kEnd',
    );
  }

  // ── Initial values ──────────────────────────────────────────────────────────

  void _writeDumpvars(StringBuffer buf, List<_Signal> signals) {
    buf.writeln(_kDumpvars);
    for (final sig in signals) {
      switch (sig.kind) {
        case _Kind.scalar:
          buf.writeln('0${sig.id}');
        case _Kind.bus:
          buf.writeln('b${'0' * sig.width} ${sig.id}');
        case _Kind.real:
          buf.writeln('r0.0 ${sig.id}');
      }
    }
    buf.writeln(_kEnd);
  }

  // ── Value changes ────────────────────────────────────────────────────────────

  void _writeTransitions(
    StringBuffer buf,
    List<_Signal> signals,
    VcdGeneratorConfig cfg,
    Random r,
  ) {
    if (cfg.duration <= 0 || signals.isEmpty) return;

    final events = <(int time, String change)>[];

    // Clock (signal 0): toggle at a regular period.
    final clk = signals.first;
    final period = (cfg.duration / 100).clamp(2.0, cfg.duration / 2.0).round();
    var clkState = 0;
    for (var t = period; t <= cfg.duration; t += period) {
      clkState ^= 1;
      events.add((t, '$clkState${clk.id}'));
    }

    for (var i = 1; i < signals.length; i++) {
      final sig = signals[i];
      final count = 5 + r.nextInt(16); // 5–20 transitions
      _addEvents(events, sig, count, cfg, r);
    }

    events.sort((a, b) => a.$1.compareTo(b.$1));

    var lastTime = -1;
    for (final (time, change) in events) {
      if (time != lastTime) {
        lastTime = time;
        buf.writeln('#$time');
      }
      buf.writeln(change);
    }
  }

  void _addEvents(
    List<(int, String)> events,
    _Signal sig,
    int count,
    VcdGeneratorConfig cfg,
    Random r,
  ) {
    final times = List.generate(count, (_) => 1 + r.nextInt(cfg.duration))
      ..sort();

    switch (sig.kind) {
      case _Kind.scalar:
        final states = cfg.includeXz
            ? const ['0', '1', 'x', 'z']
            : const ['0', '1'];
        var prev = '0';
        for (final t in times) {
          String next;
          do {
            next = states[r.nextInt(states.length)];
          } while (next == prev);
          prev = next;
          events.add((t, '$next${sig.id}'));
        }

      case _Kind.bus:
        for (final t in times) {
          final val = _busValue(sig.width, cfg.includeXz, r);
          events.add((t, 'b$val ${sig.id}'));
        }

      case _Kind.real:
        var val = 0.0;
        for (final t in times) {
          val += (r.nextDouble() - 0.5) * 10.0;
          events.add((t, 'r${val.toStringAsFixed(4)} ${sig.id}'));
        }
    }
  }

  String _busValue(int width, bool includeXz, Random r) {
    if (includeXz && r.nextDouble() < 0.15) {
      return List.generate(width, (_) {
        const chars = ['0', '1', 'x', 'z'];
        return chars[r.nextInt(4)];
      }).join();
    }
    return List.generate(width, (_) => r.nextBool() ? '1' : '0').join();
  }
}

// ── Internal signal model ────────────────────────────────────────────────────

enum _Kind { scalar, bus, real }

class _Signal {
  const _Signal({
    required this.id,
    required this.name,
    required this.scope,
    required this.kind,
    required this.width,
  });

  final String id;
  final String name;
  final String scope;
  final _Kind kind;
  final int width;
}
