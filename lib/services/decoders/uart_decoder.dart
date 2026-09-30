// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/decoder_parameter.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/services/decoders/decoder_value_helpers.dart';

/// Decodes UART (Universal Asynchronous Receiver-Transmitter) serial frames.
///
/// Detects start bits (falling edge from idle-high), samples [dataBits] data
/// bits at baud-rate intervals centered on each bit period, checks optional
/// parity, and verifies stop bit(s).  Consecutive bytes on the same channel
/// within [group_gap_bits] bit-periods are merged into a single
/// [DecodedTransaction] with concatenated data.
///
/// Supports TX-only, RX-only, and full-duplex (TX + RX) configurations.
/// Errors detected: framing error (stop bit not high), parity error, and
/// break condition (line held low longer than one full frame).
class UartDecoder implements ProtocolDecoder {
  /// Creates a [UartDecoder] bound to [config].
  const UartDecoder(this._config);

  final DecoderConfig _config;

  // ── static definition ──────────────────────────────────────────────────────

  /// Static metadata registered with [DecoderRegistry] at app startup.
  static const decoderDefinition = DecoderDefinition(
    id: 'uart',
    displayName: 'UART',
    description:
        'Decodes UART serial frames (start bit, data bits, optional parity, stop bit).',
    category: DecoderCategory.serial,
    requiredSignals: [
      SignalBinding(
        name: 'tx',
        description:
            'Transmit data line. Omit and provide rx for RX-only mode.',
        bitWidth: 1,
      ),
    ],
    optionalSignals: [
      SignalBinding(
        name: 'rx',
        description: 'Receive data line.',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'clk',
        description:
            'Design clock. Bind this and set Bit Timing to "Clocks per bit" '
            'to describe the baud the way an HDL testbench does.',
        bitWidth: 1,
      ),
    ],
    parameters: [
      DecoderParameter(
        name: 'timing_mode',
        displayName: 'Bit Timing',
        type: DecoderParameterType.enumeration,
        defaultValue: 'baud',
        description:
            'How the bit period is determined. Baud rate suits a captured '
            'trace with a real time base; clocks per bit suits an HDL '
            'simulation, where the design is written against a clock and a '
            'CLKS_PER_BIT constant rather than a baud number.',
        enumValues: ['baud', 'clocks_per_bit', 'auto'],
        enumLabels: {
          'baud': 'Baud rate',
          'clocks_per_bit': 'Clocks per bit',
          'auto': 'Auto-detect from the line',
        },
      ),
      DecoderParameter(
        name: 'baud_rate',
        displayName: 'Baud Rate',
        type: DecoderParameterType.integer,
        defaultValue: 9600,
        description:
            'Baud rate in bits per second (e.g. 9600, 115200). Used when Bit '
            'Timing is "Baud rate".',
      ),
      DecoderParameter(
        name: 'clocks_per_bit',
        displayName: 'Clocks per Bit',
        type: DecoderParameterType.integer,
        defaultValue: 16,
        description:
            "Clock cycles per bit — the design's CLKS_PER_BIT. Used when "
            'Bit Timing is "Clocks per bit"; requires the clk signal.',
      ),
      DecoderParameter(
        name: 'data_bits',
        displayName: 'Data Bits',
        type: DecoderParameterType.integer,
        defaultValue: 8,
        description: 'Number of data bits per frame (5–9)',
      ),
      DecoderParameter(
        name: 'parity',
        displayName: 'Parity',
        type: DecoderParameterType.enumeration,
        defaultValue: 'none',
        description: 'Parity mode',
        enumValues: ['none', 'even', 'odd'],
        enumLabels: {'none': 'None', 'even': 'Even', 'odd': 'Odd'},
      ),
      DecoderParameter(
        name: 'stop_bits',
        displayName: 'Stop Bits',
        type: DecoderParameterType.enumeration,
        defaultValue: '1',
        description: 'Number of stop bits',
        enumValues: ['1', '2'],
        enumLabels: {'1': '1', '2': '2'},
      ),
      DecoderParameter(
        name: 'bit_order',
        displayName: 'Bit Order',
        type: DecoderParameterType.enumeration,
        defaultValue: 'lsb',
        description:
            'Bit transmission order (lsb = LSB first, per UART convention)',
        enumValues: ['lsb', 'msb'],
        enumLabels: {'lsb': 'LSB First', 'msb': 'MSB First'},
      ),
      DecoderParameter(
        name: 'group_gap_bits',
        displayName: 'Group Gap (bits)',
        type: DecoderParameterType.integer,
        defaultValue: 10,
        description:
            'Consecutive bytes with inter-frame gaps smaller than this many '
            'bit-periods are merged into one transaction',
      ),
    ],
  );

  @override
  DecoderDefinition get definition => UartDecoder.decoderDefinition;

  // ── decode ─────────────────────────────────────────────────────────────────

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) {
    final baudRate = intParam(_config.parameters, 'baud_rate', 9600);
    final dataBits = intParam(_config.parameters, 'data_bits', 8).clamp(5, 9);
    final parity = stringParam(_config.parameters, 'parity', 'none');
    final stopBits = stringParam(_config.parameters, 'stop_bits', '1') == '2'
        ? 2
        : 1;
    final lsbFirst =
        stringParam(_config.parameters, 'bit_order', 'lsb') == 'lsb';
    final groupGapBits = intParam(_config.parameters, 'group_gap_bits', 10);

    final hasTx = _config.signalBindings.containsKey('tx');
    final hasRx = _config.signalBindings.containsKey('rx');
    if (!hasTx && !hasRx) return [];

    final bitPeriod = _resolveBitPeriod(
      startTime: startTime,
      endTime: endTime,
      changesQuery: changesQuery,
      timescale: timescale,
      baudRate: baudRate,
      dataLine: hasTx ? 'tx' : 'rx',
    );
    if (bitPeriod < 1) return [];

    final gapThreshold = groupGapBits * bitPeriod;

    final txTxs = hasTx
        ? _decodeChannel(
            'TX',
            'tx',
            startTime,
            endTime,
            query,
            changesQuery,
            dataBits,
            parity,
            stopBits,
            lsbFirst,
            bitPeriod,
            gapThreshold,
          )
        : <DecodedTransaction>[];

    final rxTxs = hasRx
        ? _decodeChannel(
            'RX',
            'rx',
            startTime,
            endTime,
            query,
            changesQuery,
            dataBits,
            parity,
            stopBits,
            lsbFirst,
            bitPeriod,
            gapThreshold,
          )
        : <DecodedTransaction>[];

    return [...txTxs, ...rxTxs]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  // ── private: bit-period resolution ─────────────────────────────────────────

  /// Resolves the bit period in ticks under the configured `timing_mode`.
  ///
  /// Returns 0 when the mode's inputs are unusable, which the caller treats as
  /// "decode nothing" — the same outcome an impossible baud already produced.
  ///
  /// **Why this is not just a baud number.** A UART in an HDL testbench is
  /// written against a clock and a `CLKS_PER_BIT` constant; nobody picks a
  /// baud. A design at `always #5 clk` with `CLKS_PER_BIT = 8` is running at
  /// 12.5 Mbaud, and a decoder defaulting to 9600 finds nothing at all — no
  /// error, no transactions, no hint about why. Expressing the timing the way
  /// the design expresses it removes the arithmetic and the failure mode.
  int _resolveBitPeriod({
    required int startTime,
    required int endTime,
    required SignalChangesQuery changesQuery,
    required Timescale? timescale,
    required int baudRate,
    required String dataLine,
  }) {
    final mode = stringParam(_config.parameters, 'timing_mode', 'baud');

    switch (mode) {
      case 'clocks_per_bit':
        final clocksPerBit = intParam(_config.parameters, 'clocks_per_bit', 16);
        if (clocksPerBit < 1) return 0;
        if (!_config.signalBindings.containsKey('clk')) return 0;
        final clockPeriod = _measureClockPeriod(
          changesQuery('clk', startTime, endTime),
        );
        if (clockPeriod < 1) return 0;
        return clocksPerBit * clockPeriod;

      case 'auto':
        return _autoDetectBitPeriod(
          changesQuery(dataLine, startTime, endTime),
        );

      case 'baud':
      default:
        // ticksPerSecond = 1 / secondsPerTick; fall back to 1 ns/tick when the
        // trace carries no timescale.
        final secondsPerTick = timescale?.secondsPerTick ?? 1e-9;
        if (baudRate < 1) return 0;
        return (1.0 / (baudRate * secondsPerTick)).round();
    }
  }

  /// Full clock period in ticks, measured from the clock's own transitions.
  ///
  /// Uses the **median** gap between consecutive edges rather than the mean or
  /// the first: a testbench clock is uniform, but a trace may open or close
  /// mid-cycle, and a gated clock has long idle stretches that would drag a
  /// mean upward. Two edges make one half period, so the result is doubled.
  ///
  /// Returns 0 when there are too few edges to measure.
  static int _measureClockPeriod(List<(int, String)> clockChanges) {
    if (clockChanges.length < 3) return 0;
    final gaps = <int>[];
    for (var i = 1; i < clockChanges.length; i++) {
      final gap = clockChanges[i].$1 - clockChanges[i - 1].$1;
      if (gap > 0) gaps.add(gap);
    }
    if (gaps.isEmpty) return 0;
    gaps.sort();
    return gaps[gaps.length ~/ 2] * 2;
  }

  /// Best-effort bit period measured from the data line itself.
  ///
  /// The greatest common divisor of the inter-edge gaps is the bit period:
  /// every gap on a UART line is a whole number of bit times, so their GCD is
  /// the bit time itself unless every run length happens to share a factor.
  ///
  /// **Honest about its limits.** GCD collapses toward 1 under jitter, so a
  /// captured (rather than simulated) trace can defeat it. When the GCD comes
  /// out implausibly small relative to the shortest gap, this falls back to
  /// that shortest gap — which is the bit period whenever the traffic contains
  /// any isolated single-bit pulse, and most traffic does. Neither estimate is
  /// a substitute for saying what the timing actually is, which is why this is
  /// the third mode and not the default.
  static int _autoDetectBitPeriod(List<(int, String)> dataChanges) {
    if (dataChanges.length < 2) return 0;
    final gaps = <int>[];
    for (var i = 1; i < dataChanges.length; i++) {
      final gap = dataChanges[i].$1 - dataChanges[i - 1].$1;
      if (gap > 0) gaps.add(gap);
    }
    if (gaps.isEmpty) return 0;

    var divisor = gaps.first;
    for (final gap in gaps.skip(1)) {
      divisor = _gcd(divisor, gap);
      if (divisor == 1) break;
    }

    final shortest = gaps.reduce((a, b) => a < b ? a : b);
    // A GCD below a sixteenth of the shortest gap is the signature of jitter,
    // not of a genuinely fine bit time.
    if (divisor * 16 < shortest) return shortest;
    return divisor;
  }

  static int _gcd(int a, int b) {
    var x = a;
    var y = b;
    while (y != 0) {
      final t = y;
      y = x % y;
      x = t;
    }
    return x;
  }

  // ── private: channel decode ────────────────────────────────────────────────

  List<DecodedTransaction> _decodeChannel(
    String channelName,
    String signalName,
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery,
    int dataBits,
    String parity,
    int stopBits,
    bool lsbFirst,
    int bitPeriod,
    int gapThreshold,
  ) {
    final changes = changesQuery(signalName, startTime, endTime);
    if (changes.isEmpty) return [];

    final parityOffset = parity != 'none' ? 1 : 0;
    // Ticks from the start-bit falling edge to the end of the last stop bit.
    final frameTicks = bitPeriod * (1 + dataBits + parityOffset + stopBits);

    final decodedBytes = <_UartByte>[];
    var lastFrameEnd = startTime - 1;

    for (final (edgeTime, edgeVal) in changes) {
      // Only falling edges (line goes low) are candidate start bits.
      if (!isVcdLow(edgeVal)) continue;
      // Skip edges inside the previous frame.
      if (edgeTime < lastFrameEnd) continue;

      // Verify start bit at its center.
      final startCenter = edgeTime + bitPeriod ~/ 2;
      if (startCenter >= endTime) break;
      if (!isVcdLow(query(signalName, startCenter))) continue;

      // Sample data bits.
      var byteValue = 0;
      var parityCount = 0;
      var samplesOk = true;

      for (var i = 0; i < dataBits; i++) {
        final sampleTime = edgeTime + bitPeriod * (i + 1) + bitPeriod ~/ 2;
        if (sampleTime >= endTime) {
          samplesOk = false;
          break;
        }
        final bit = isVcdHigh(query(signalName, sampleTime)) ? 1 : 0;
        if (lsbFirst) {
          byteValue |= bit << i;
        } else {
          byteValue = (byteValue << 1) | bit;
        }
        parityCount += bit;
      }
      if (!samplesOk) break;

      // Check optional parity bit.
      var parityError = false;
      if (parity != 'none') {
        final parityTime =
            edgeTime + bitPeriod * (dataBits + 1) + bitPeriod ~/ 2;
        if (parityTime < endTime) {
          final parityBit = isVcdHigh(query(signalName, parityTime)) ? 1 : 0;
          // Even parity: bit count + parity bit must be even.
          // Odd parity:  bit count + parity bit must be odd.
          final expectedParity = parity == 'even'
              ? parityCount % 2
              : 1 - (parityCount % 2);
          parityError = parityBit != expectedParity;
        }
      }

      // Check stop bit(s).
      var framingError = false;
      for (var s = 0; s < stopBits; s++) {
        final stopTime =
            edgeTime +
            bitPeriod * (dataBits + parityOffset + s + 1) +
            bitPeriod ~/ 2;
        if (stopTime >= endTime) break;
        if (!isVcdHigh(query(signalName, stopTime))) {
          framingError = true;
        }
      }

      // Detect break condition: line still low two full frames after the start.
      // A normal framing error recovers within one frame; a break holds longer.
      var breakCondition = false;
      if (framingError) {
        final breakCheckTime = edgeTime + frameTicks * 2;
        if (breakCheckTime < endTime &&
            isVcdLow(query(signalName, breakCheckTime))) {
          breakCondition = true;
        }
      }

      final frameEnd = edgeTime + frameTicks;
      decodedBytes.add(
        _UartByte(
          byteValue: byteValue,
          startTime: edgeTime,
          endTime: frameEnd,
          framingError: framingError,
          parityError: parityError,
          breakCondition: breakCondition,
        ),
      );
      lastFrameEnd = frameEnd;
    }

    if (decodedBytes.isEmpty) return [];
    return _groupBytes(decodedBytes, channelName, gapThreshold);
  }

  // ── private: grouping ──────────────────────────────────────────────────────

  List<DecodedTransaction> _groupBytes(
    List<_UartByte> bytes,
    String channelName,
    int gapThreshold,
  ) {
    final transactions = <DecodedTransaction>[];
    var i = 0;

    while (i < bytes.length) {
      final first = bytes[i];

      if (first.framingError || first.parityError) {
        transactions.add(_makeTransaction([first], channelName));
        i++;
        continue;
      }

      final group = [first];
      var j = i + 1;
      while (j < bytes.length) {
        final next = bytes[j];
        if (next.framingError || next.parityError) break;
        final gap = next.startTime - group.last.endTime;
        if (gap >= gapThreshold) break;
        group.add(next);
        j++;
      }

      transactions.add(_makeTransaction(group, channelName));
      i = j;
    }

    return transactions;
  }

  // ── private: transaction construction ─────────────────────────────────────

  DecodedTransaction _makeTransaction(
    List<_UartByte> group,
    String channelName,
  ) {
    final byteVals = group.map((b) => b.byteValue).toList();
    final hexStr = byteVals
        .map((b) => '0x${b.toRadixString(16).toUpperCase().padLeft(2, '0')}')
        .join(' ');
    final asciiStr = String.fromCharCodes(
      byteVals.map((b) => _isPrintable(b) ? b : 0x2E),
    );

    final allPrintable = byteVals.every(_isPrintable);
    final label = allPrintable
        ? 'UART $channelName: $asciiStr'
        : 'UART $channelName: $hexStr';

    final errors = <String>[
      for (final b in group) ...[
        if (b.breakCondition) 'Break condition',
        if (b.framingError && !b.breakCondition) 'Framing error: stop bit low',
        if (b.parityError) 'Parity error',
      ],
    ];

    return DecodedTransaction(
      startTime: group.first.startTime,
      endTime: group.last.endTime,
      label: label,
      fields: {
        'channel': channelName,
        'data': hexStr,
        'ascii': asciiStr,
        'bytes': byteVals.length.toString(),
      },
      isError: errors.isNotEmpty,
      errorMessage: errors.isNotEmpty ? errors.join('; ') : null,
    );
  }

  // ── private: helpers ───────────────────────────────────────────────────────

  bool _isPrintable(int b) => b >= 0x20 && b <= 0x7E;
}

// ── internal byte record ───────────────────────────────────────────────────

class _UartByte {
  const _UartByte({
    required this.byteValue,
    required this.startTime,
    required this.endTime,
    required this.framingError,
    required this.parityError,
    required this.breakCondition,
  });

  final int byteValue;
  final int startTime;
  final int endTime;
  final bool framingError;
  final bool parityError;
  final bool breakCondition;
}
