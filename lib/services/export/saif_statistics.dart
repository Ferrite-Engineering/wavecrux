// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';

/// Dwell times and toggle count for **one bit** of one signal.
///
/// SAIF is a per-bit format: a 16-bit bus contributes sixteen of these, because
/// power tools weight each bit's capacitance separately. The four time fields
/// partition the analysis window exactly — `t0 + t1 + tx + tz == duration` —
/// which is the invariant the writer's tests assert and the one a consuming
/// tool will notice first if it is wrong.
@immutable
class SaifBitActivity {
  /// Creates a per-bit record.
  const SaifBitActivity({
    this.t0 = 0,
    this.t1 = 0,
    this.tx = 0,
    this.tz = 0,
    this.toggleCount = 0,
  });

  /// Ticks spent at logic 0.
  final int t0;

  /// Ticks spent at logic 1.
  final int t1;

  /// Ticks spent unknown (`x`).
  final int tx;

  /// Ticks spent high-impedance (`z`).
  final int tz;

  /// Number of 0↔1 transitions.
  ///
  /// Transitions **into or out of** `x`/`z` are deliberately not counted: a
  /// power tool multiplies this by capacitance to get switching energy, and an
  /// unknown-to-known settle is not a physical toggle. Ignoring it here is the
  /// conservative choice — over-counting would inflate an energy estimate,
  /// which is the direction that misleads.
  final int toggleCount;

  /// Total ticks accounted for. Equals the window duration for a well-formed
  /// record.
  int get total => t0 + t1 + tx + tz;

  @override
  String toString() =>
      'SaifBitActivity(T0 $t0, T1 $t1, TX $tx, TZ $tz, TC $toggleCount)';
}

/// Per-bit activity for one signal, plus the identity a SAIF writer needs.
@immutable
class SaifSignalActivity {
  /// Creates a signal record.
  const SaifSignalActivity({
    required this.fullPath,
    required this.name,
    required this.bits,
  });

  /// Hierarchical path, e.g. `top.dsp.sample_q`. Used to build the SAIF
  /// instance tree.
  final String fullPath;

  /// Leaf name, e.g. `sample_q`.
  final String name;

  /// One entry per bit, index 0 = LSB. A scalar has exactly one.
  final List<SaifBitActivity> bits;

  /// Declared width.
  int get width => bits.length;
}

/// Computes the dwell times SAIF needs from a loaded waveform.
///
/// **Why this is not `SwitchingActivityService`.** That service answers "how
/// busy is this signal" — transition counts, toggle rates, a duty-cycle
/// fraction for scalars. SAIF needs something different in kind: absolute time
/// *per logic state, per bit*, summing exactly to the window. A fraction cannot
/// be turned back into a duration without re-walking the trace, and a
/// whole-signal count cannot be split across bits at all, so the two
/// computations genuinely differ rather than one being a rounding of the other.
class SaifStatisticsService {
  /// Creates the service.
  const SaifStatisticsService();

  /// Computes per-bit activity for [signalPath] over `[startTime, endTime)`.
  ///
  /// [width] is the signal's declared bit width; pass 1 for a scalar. Real
  /// signals have no bit-level activity and must not be passed here — the
  /// caller filters them out, because SAIF has nothing to say about a real.
  SaifSignalActivity analyze({
    required String signalPath,
    required String name,
    required int width,
    required WaveformDataSource source,
    required int startTime,
    required int endTime,
  }) {
    final duration = endTime - startTime;
    final effectiveWidth = width < 1 ? 1 : width;

    final t0 = List<int>.filled(effectiveWidth, 0);
    final t1 = List<int>.filled(effectiveWidth, 0);
    final tx = List<int>.filled(effectiveWidth, 0);
    final tz = List<int>.filled(effectiveWidth, 0);
    final tc = List<int>.filled(effectiveWidth, 0);

    if (duration <= 0) {
      return SaifSignalActivity(
        fullPath: signalPath,
        name: name,
        bits: [
          for (var i = 0; i < effectiveWidth; i++) const SaifBitActivity(),
        ],
      );
    }

    // The state held at the left edge. A signal with no recorded value before
    // the window starts is unknown, not zero — reporting it as 0 would invent
    // a full window of settled-low time.
    var currentBits = _bitsOf(
      source.valueAt(signalPath, startTime),
      effectiveWidth,
    );
    var lastTime = startTime;

    for (final change in source.changesInRange(
      signalPath,
      startTime,
      endTime,
    )) {
      final at = change.time;
      if (at > lastTime) {
        _accumulate(currentBits, at - lastTime, t0, t1, tx, tz);
        lastTime = at;
      }
      final next = _bitsOf(change.value, effectiveWidth);
      for (var i = 0; i < effectiveWidth; i++) {
        final a = currentBits[i];
        final b = next[i];
        // Only 0↔1 counts as a toggle — see SaifBitActivity.toggleCount.
        if ((a == _b0 && b == _b1) || (a == _b1 && b == _b0)) tc[i]++;
      }
      currentBits = next;
    }

    if (endTime > lastTime) {
      _accumulate(currentBits, endTime - lastTime, t0, t1, tx, tz);
    }

    return SaifSignalActivity(
      fullPath: signalPath,
      name: name,
      bits: [
        for (var i = 0; i < effectiveWidth; i++)
          SaifBitActivity(
            t0: t0[i],
            t1: t1[i],
            tx: tx[i],
            tz: tz[i],
            toggleCount: tc[i],
          ),
      ],
    );
  }

  static const int _b0 = 0;
  static const int _b1 = 1;
  static const int _bx = 2;
  static const int _bz = 3;

  static void _accumulate(
    List<int> bits,
    int ticks,
    List<int> t0,
    List<int> t1,
    List<int> tx,
    List<int> tz,
  ) {
    for (var i = 0; i < bits.length; i++) {
      switch (bits[i]) {
        case _b0:
          t0[i] += ticks;
        case _b1:
          t1[i] += ticks;
        case _bz:
          tz[i] += ticks;
        default:
          tx[i] += ticks;
      }
    }
  }

  /// Decodes a raw value string to per-bit states, index 0 = LSB.
  ///
  /// A shorter-than-declared bit string is zero-extended, matching the VCD
  /// rule; a null or unparseable value is all-unknown, which is the honest
  /// reading of "we have no value here".
  static List<int> _bitsOf(String? raw, int width) {
    if (raw == null || raw.isEmpty) {
      return List<int>.filled(width, _bx);
    }
    var s = raw.toLowerCase();
    if (s.startsWith('b')) s = s.substring(1);
    if (s.startsWith('r')) {
      // A real value has no bit-level meaning; the caller should have filtered
      // it out, so treat it as unknown rather than guessing.
      return List<int>.filled(width, _bx);
    }
    if (s.length < width) s = s.padLeft(width, '0');

    final out = List<int>.filled(width, _bx);
    for (var i = 0; i < width; i++) {
      // MSB-first string, LSB-first output.
      final ch = s.codeUnitAt(s.length - 1 - i);
      out[i] = switch (ch) {
        0x30 => _b0, // '0'
        0x31 => _b1, // '1'
        0x7a => _bz, // 'z'
        _ => _bx,
      };
    }
    return out;
  }
}
