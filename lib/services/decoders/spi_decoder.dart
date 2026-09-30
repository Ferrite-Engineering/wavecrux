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

/// Decodes SPI (Serial Peripheral Interface) bus transactions.
///
/// Supports all four SPI modes (CPOL 0/1 × CPHA 0/1), MSB- and LSB-first bit
/// order, configurable word size, and optional chip-select framing.
/// Works in full-duplex (MOSI + MISO) and half-duplex (MOSI-only) modes.
class SpiDecoder implements ProtocolDecoder {
  /// Creates an [SpiDecoder] bound to [config].
  const SpiDecoder(this._config);

  final DecoderConfig _config;

  // ── static definition ──────────────────────────────────────────────────────

  /// Static metadata registered with [DecoderRegistry] at app startup.
  static const decoderDefinition = DecoderDefinition(
    id: 'spi',
    displayName: 'SPI',
    description: 'Decodes Serial Peripheral Interface (SPI) bus transactions.',
    category: DecoderCategory.serial,
    requiredSignals: [
      SignalBinding(
        name: 'sclk',
        description: 'Serial clock',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'mosi',
        description: 'Master-Out Slave-In data line',
        bitWidth: 1,
      ),
    ],
    optionalSignals: [
      SignalBinding(
        name: 'miso',
        description: 'Master-In Slave-Out data line',
        bitWidth: 1,
      ),
      SignalBinding(
        name: 'cs',
        description: 'Chip select (active level configurable)',
        bitWidth: 1,
      ),
    ],
    parameters: [
      DecoderParameter(
        name: 'cpol',
        displayName: 'CPOL',
        labelKey: 'spiParamCpol',
        descriptionKey: 'spiParamCpolDescription',
        type: DecoderParameterType.enumeration,
        defaultValue: '0',
        description:
            'Clock polarity: idle state of SCLK '
            '(0 = idle low, 1 = idle high)',
        enumValues: ['0', '1'],
        enumLabels: {'0': '0 (Idle Low)', '1': '1 (Idle High)'},
        enumLabelKeys: {'0': 'spiChoiceCpol0', '1': 'spiChoiceCpol1'},
      ),
      DecoderParameter(
        name: 'cpha',
        displayName: 'CPHA',
        labelKey: 'spiParamCpha',
        descriptionKey: 'spiParamCphaDescription',
        type: DecoderParameterType.enumeration,
        defaultValue: '0',
        description:
            'Clock phase: which edge data is sampled on '
            '(0 = first/leading edge, 1 = second/trailing edge)',
        enumValues: ['0', '1'],
        enumLabels: {'0': '0 (Leading Edge)', '1': '1 (Trailing Edge)'},
        enumLabelKeys: {'0': 'spiChoiceCpha0', '1': 'spiChoiceCpha1'},
      ),
      DecoderParameter(
        name: 'bit_order',
        displayName: 'Bit Order',
        labelKey: 'spiParamBitOrder',
        descriptionKey: 'spiParamBitOrderDescription',
        type: DecoderParameterType.enumeration,
        defaultValue: 'msb',
        description:
            'Bit transmission order '
            '(msb = MSB first, lsb = LSB first)',
        enumValues: ['msb', 'lsb'],
        enumLabels: {'msb': 'MSB First', 'lsb': 'LSB First'},
        enumLabelKeys: {
          'msb': 'spiChoiceBitOrderMsb',
          'lsb': 'spiChoiceBitOrderLsb',
        },
      ),
      DecoderParameter(
        name: 'word_size',
        displayName: 'Word Size',
        labelKey: 'spiParamWordSize',
        descriptionKey: 'spiParamWordSizeDescription',
        type: DecoderParameterType.integer,
        defaultValue: 8,
        description: 'Number of bits per word (1–64)',
      ),
      DecoderParameter(
        name: 'cs_active_level',
        displayName: 'CS Active Level',
        labelKey: 'spiParamCsActiveLevel',
        descriptionKey: 'spiParamCsActiveLevelDescription',
        type: DecoderParameterType.enumeration,
        defaultValue: '0',
        description:
            'CS logic level when chip is selected '
            '(0 = active-low, 1 = active-high)',
        enumValues: ['0', '1'],
        enumLabels: {'0': 'Active Low', '1': 'Active High'},
        enumLabelKeys: {
          '0': 'spiChoiceCsActiveLevel0',
          '1': 'spiChoiceCsActiveLevel1',
        },
      ),
    ],
  );

  @override
  DecoderDefinition get definition => SpiDecoder.decoderDefinition;

  // ── decode ─────────────────────────────────────────────────────────────────

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) {
    final cpol = stringParam(_config.parameters, 'cpol', '0') == '1';
    final cpha = stringParam(_config.parameters, 'cpha', '0') == '1';
    final msbFirst =
        stringParam(_config.parameters, 'bit_order', 'msb') == 'msb';
    final wordSize = intParam(_config.parameters, 'word_size', 8).clamp(1, 64);
    final csActiveLow =
        stringParam(_config.parameters, 'cs_active_level', '0') == '0';

    // Sample on rising edge when CPOL == CPHA (modes 0 and 3).
    // Sample on falling edge when CPOL != CPHA (modes 1 and 2).
    final sampleOnRising = cpol == cpha;

    final hasCs = _config.signalBindings.containsKey('cs');
    final hasMiso = _config.signalBindings.containsKey('miso');

    final sclkChanges = changesQuery('sclk', startTime, endTime);
    if (sclkChanges.isEmpty) return [];

    if (hasCs) {
      final csChanges = changesQuery('cs', startTime, endTime);
      final segments = _csSegments(
        csChanges,
        query,
        startTime,
        endTime,
        csActiveLow,
      );
      return [
        for (final seg in segments)
          ..._decodeSegment(
            seg.$1,
            seg.$2,
            sclkChanges.where((c) => c.$1 >= seg.$1 && c.$1 < seg.$2).toList(),
            query,
            changesQuery,
            sampleOnRising,
            msbFirst,
            wordSize,
            hasMiso,
          ),
      ];
    }

    return _decodeSegment(
      startTime,
      endTime,
      sclkChanges,
      query,
      changesQuery,
      sampleOnRising,
      msbFirst,
      wordSize,
      hasMiso,
    );
  }

  // ── private helpers ────────────────────────────────────────────────────────

  /// Returns time segments `(start, end)` during which CS is asserted.
  List<(int, int)> _csSegments(
    List<(int, String)> csChanges,
    SignalValueQuery query,
    int rangeStart,
    int rangeEnd,
    bool activeLow,
  ) {
    final segments = <(int, int)>[];
    int? segStart;

    if (_csActive(query('cs', rangeStart), activeLow)) segStart = rangeStart;

    for (final (time, value) in csChanges) {
      final active = _csActive(value, activeLow);
      if (active && segStart == null) {
        segStart = time;
      } else if (!active && segStart != null) {
        segments.add((segStart, time));
        segStart = null;
      }
    }
    if (segStart != null) segments.add((segStart, rangeEnd));
    return segments;
  }

  bool _csActive(String? value, bool activeLow) {
    if (value == null) return false;
    final isHigh = _bitValue(value) == 1;
    return activeLow ? !isHigh : isHigh;
  }

  List<DecodedTransaction> _decodeSegment(
    int txStart,
    int txEnd,
    List<(int, String)> sclkInRange,
    SignalValueQuery query,
    SignalChangesQuery changesQuery,
    bool sampleOnRising,
    bool msbFirst,
    int wordSize,
    bool hasMiso,
  ) {
    // Collect timestamps of sample edges.
    final sampleTimes = [
      for (final (time, val) in sclkInRange)
        if (_isSampleEdge(val, sampleOnRising)) time,
    ];
    if (sampleTimes.isEmpty) return [];

    // Detect MOSI glitches: data transition coincides with a sample edge.
    final mosiChangeTimes = changesQuery(
      'mosi',
      txStart,
      txEnd,
    ).map((c) => c.$1).toSet();
    final glitchTimes = sampleTimes.where(mosiChangeTimes.contains).toList();

    // Accumulate sampled bits into words.
    final mosiWords = <int>[];
    final misoWords = <int>[];
    var mosiWord = 0;
    var misoWord = 0;
    var bitCount = 0;

    for (final t in sampleTimes) {
      final mosiBit = _readBit(query('mosi', t));
      final misoBit = hasMiso ? _readBit(query('miso', t)) : 0;

      if (msbFirst) {
        mosiWord = (mosiWord << 1) | mosiBit;
        misoWord = (misoWord << 1) | misoBit;
      } else {
        mosiWord |= mosiBit << bitCount;
        misoWord |= misoBit << bitCount;
      }
      bitCount++;

      if (bitCount == wordSize) {
        mosiWords.add(mosiWord);
        if (hasMiso) misoWords.add(misoWord);
        mosiWord = 0;
        misoWord = 0;
        bitCount = 0;
      }
    }

    // Partial last word → framing error (CS deasserted mid-word).
    final hasPartial = bitCount > 0;
    if (hasPartial) {
      if (msbFirst) {
        mosiWord <<= wordSize - bitCount;
        misoWord <<= wordSize - bitCount;
      }
      mosiWords.add(mosiWord);
      if (hasMiso) misoWords.add(misoWord);
    }

    if (mosiWords.isEmpty) return [];

    final nibbles = (wordSize + 3) ~/ 4;
    String hex(int w) =>
        '0x${w.toRadixString(16).toUpperCase().padLeft(nibbles, '0')}';

    final mosiStr = mosiWords.map(hex).join(' ');
    final misoStr = hasMiso ? misoWords.map(hex).join(' ') : null;
    final wordCount = mosiWords.length;
    final label = wordCount == 1
        ? 'SPI ${hex(mosiWords.first)}'
        : 'SPI $wordCount words';

    final fields = <String, String>{
      'mosi': mosiStr,
      'miso': ?misoStr,
      'words': wordCount.toString(),
    };

    final errors = <String>[
      if (hasPartial) 'Incomplete word: $bitCount of $wordSize bits',
      for (final t in glitchTimes) 'MOSI changes at sample edge t=$t',
    ];

    return [
      DecodedTransaction(
        startTime: txStart,
        endTime: txEnd,
        label: label,
        fields: fields,
        isError: errors.isNotEmpty,
        errorMessage: errors.isNotEmpty ? errors.join('; ') : null,
      ),
    ];
  }

  bool _isSampleEdge(String value, bool sampleOnRising) {
    final isHigh = _bitValue(value) == 1;
    return sampleOnRising ? isHigh : !isHigh;
  }

  int _bitValue(String value) {
    final s = value.startsWith('b') ? value.substring(1) : value;
    return s.trim() == '1' ? 1 : 0;
  }

  int _readBit(String? value) {
    if (value == null) return 0;
    return _bitValue(value);
  }
}
