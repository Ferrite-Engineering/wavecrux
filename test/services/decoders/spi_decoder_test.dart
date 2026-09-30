// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';

// ── test helpers ──────────────────────────────────────────────────────────────

/// Creates a [SignalValueQuery] backed by a per-signal map of
/// `{tick → value}`.  Returns the most-recent value at or before [time].
SignalValueQuery makeQuery(Map<String, Map<int, String>> data) {
  return (name, time) {
    final values = data[name];
    if (values == null) return null;
    int? latest;
    for (final t in values.keys) {
      if (t <= time && (latest == null || t > latest)) latest = t;
    }
    return latest == null ? null : values[latest];
  };
}

/// Creates a [SignalChangesQuery] backed by pre-defined change lists.
/// Filters to `[startTime, endTime)`.
SignalChangesQuery makeChangesQuery(
  Map<String, List<(int, String)>> changes,
) {
  return (name, start, end) {
    final list = changes[name] ?? [];
    return list.where((c) => c.$1 >= start && c.$1 < end).toList();
  };
}

/// Builds an [SpiDecoder] with full-duplex CS-framed Mode-0 config by default.
SpiDecoder makeDecoder({
  String cpol = '0',
  String cpha = '0',
  String bitOrder = 'msb',
  int wordSize = 8,
  String csActiveLevel = '0',
  bool withMiso = true,
  bool withCs = true,
}) {
  return SpiDecoder(
    DecoderConfig(
      signalBindings: {
        'sclk': 'tb.sclk',
        'mosi': 'tb.mosi',
        if (withMiso) 'miso': 'tb.miso',
        if (withCs) 'cs': 'tb.cs',
      },
      parameters: {
        'cpol': cpol,
        'cpha': cpha,
        'bit_order': bitOrder,
        'word_size': wordSize,
        'cs_active_level': csActiveLevel,
      },
    ),
  );
}

// ── helpers to build synthetic signal data ────────────────────────────────────

/// Builds SCLK transitions for [nBits] clock cycles starting at [startTick].
/// Period = [period] ticks; rising edge at startTick + period/2.
List<(int, String)> buildSclk(int nBits, {int startTick = 0, int period = 20}) {
  final changes = <(int, String)>[];
  for (var i = 0; i < nBits; i++) {
    final base = startTick + i * period;
    changes
      ..add((base + period ~/ 2, '1')) // rising
      ..add((base + period, '0')); // falling
  }
  return changes;
}

/// Returns value changes for a serial bit stream on a 1-bit signal.
/// For Mode 0: data driven 5 ticks before each rising edge.
List<(int, String)> buildDataLine(
  List<int> bits, {
  int startTick = 0,
  int period = 20,
  int setupOffset = 5,
}) {
  final changes = <(int, String)>[];
  var prev = '0';
  for (var i = 0; i < bits.length; i++) {
    final driveTime = startTick + i * period + (period ~/ 2) - setupOffset;
    final val = bits[i] == 1 ? '1' : '0';
    if (val != prev) {
      changes.add((driveTime, val));
      prev = val;
    }
  }
  // Return to idle after last bit
  if (prev != '0') {
    changes.add((startTick + bits.length * period - setupOffset, '0'));
  }
  return changes;
}

/// Returns value-at-time map from a changes list (last-value semantics).
Map<int, String> changesToValueMap(
  List<(int, String)> changes, {
  String initial = '0',
}) {
  final map = <int, String>{0: initial};
  for (final (t, v) in changes) {
    map[t] = v;
  }
  return map;
}

/// Converts a byte to MSB-first bit list.
List<int> msbBits(int byte, {int width = 8}) =>
    List.generate(width, (i) => (byte >> (width - 1 - i)) & 1);

/// Converts a byte to LSB-first bit list.
List<int> lsbBits(int byte, {int width = 8}) =>
    List.generate(width, (i) => (byte >> i) & 1);

// ── Signal data from spi_basic.vcd ────────────────────────────────────────────

/// All SCLK changes extracted from spi_basic.vcd.
final _fixtureSclkChanges = <(int, String)>[
  (0, '0'),
  (20, '1'),
  (30, '0'),
  (40, '1'),
  (50, '0'),
  (60, '1'),
  (70, '0'),
  (80, '1'),
  (90, '0'),
  (100, '1'),
  (110, '0'),
  (120, '1'),
  (130, '0'),
  (140, '1'),
  (150, '0'),
  (160, '1'),
  (170, '0'),
  (260, '1'),
  (270, '0'),
  (280, '1'),
  (290, '0'),
  (300, '1'),
  (310, '0'),
  (320, '1'),
  (330, '0'),
  (340, '1'),
  (350, '0'),
  (360, '1'),
  (370, '0'),
  (380, '1'),
  (390, '0'),
  (400, '1'),
  (410, '0'),
  (420, '1'),
  (430, '0'),
  (440, '1'),
  (450, '0'),
  (460, '1'),
  (470, '0'),
  (480, '1'),
  (490, '0'),
  (500, '1'),
  (510, '0'),
  (520, '1'),
  (530, '0'),
  (540, '1'),
  (550, '0'),
  (560, '1'),
  (570, '0'),
];

final _fixtureMosiChanges = <(int, String)>[
  (0, '0'),
  (15, '1'),
  (30, '0'),
  (50, '1'),
  (70, '0'),
  (110, '1'),
  (130, '0'),
  (150, '1'),
  (170, '0'),
  (255, '1'),
  (295, '0'),
  (315, '1'),
  (395, '0'),
  (415, '1'),
  (435, '0'),
  (455, '1'),
  (475, '0'),
  (495, '1'),
  (535, '0'),
  (555, '1'),
  (575, '0'),
];

final _fixtureMisoChanges = <(int, String)>[
  (0, '0'),
  (50, '1'),
  (130, '0'),
  (255, '1'),
  (275, '0'),
  (295, '1'),
  (395, '0'),
  (415, '1'),
  (475, '0'),
  (495, '1'),
  (575, '0'),
];

final _fixtureCsChanges = <(int, String)>[
  (0, '1'),
  (10, '0'),
  (180, '1'),
  (250, '0'),
  (590, '1'),
];

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── definition ──────────────────────────────────────────────────────────────

  group('SpiDecoder.decoderDefinition', () {
    const def = SpiDecoder.decoderDefinition;

    test('id is spi', () => expect(def.id, 'spi'));
    test('displayName is SPI', () => expect(def.displayName, 'SPI'));
    test('description is non-empty', () => expect(def.description, isNotEmpty));

    test('required signals are sclk and mosi', () {
      final names = def.requiredSignals.map((s) => s.name).toList();
      expect(names, containsAll(['sclk', 'mosi']));
      expect(names, hasLength(2));
    });

    test('optional signals are miso and cs', () {
      final names = def.optionalSignals.map((s) => s.name).toList();
      expect(names, containsAll(['miso', 'cs']));
    });

    test(
      'has parameters cpol, cpha, bit_order, word_size, cs_active_level',
      () {
        final names = def.parameters.map((p) => p.name).toList();
        expect(
          names,
          containsAll([
            'cpol',
            'cpha',
            'bit_order',
            'word_size',
            'cs_active_level',
          ]),
        );
      },
    );

    test('cpol parameter is enumeration with values 0 and 1', () {
      final p = def.parameters.firstWhere((p) => p.name == 'cpol');
      expect(p.type, DecoderParameterType.enumeration);
      expect(p.enumValues, containsAll(['0', '1']));
      expect(p.defaultValue, '0');
    });

    test('word_size parameter is integer with default 8', () {
      final p = def.parameters.firstWhere((p) => p.name == 'word_size');
      expect(p.type, DecoderParameterType.integer);
      expect(p.defaultValue, 8);
    });

    test('instance definition matches static decoderDefinition', () {
      final decoder = makeDecoder();
      expect(decoder.definition, SpiDecoder.decoderDefinition);
    });
  });

  // ── Mode 0 single-byte ────────────────────────────────────────────────────

  group('Mode 0 (CPOL=0 CPHA=0) — sample on rising edge', () {
    // 0xA5 = 10100101, 0x3C = 00111100
    // Rising edges at t=10,30,50,70,90,110,130,150 (8 cycles, period=20)
    late SpiDecoder decoder;
    late Map<String, List<(int, String)>> changes;
    late Map<String, Map<int, String>> values;

    setUp(() {
      decoder = makeDecoder();
      final mosiBits = msbBits(0xA5);
      final misoBits = msbBits(0x3C);
      final sclk = buildSclk(8);
      final mosi = buildDataLine(mosiBits);
      final miso = buildDataLine(misoBits);
      changes = {
        'sclk': sclk,
        'mosi': mosi,
        'miso': miso,
        'cs': [(0, '0'), (200, '1')],
      };
      values = {
        'sclk': changesToValueMap(sclk),
        'mosi': changesToValueMap(mosi),
        'miso': changesToValueMap(miso),
        'cs': {0: '0', 200: '1'},
      };
    });

    test('decodes one transaction', () {
      final txs = decoder.decode(
        0,
        200,
        makeQuery(values),
        makeChangesQuery(changes),
      );
      expect(txs, hasLength(1));
    });

    test('transaction label is SPI 0xA5', () {
      final txs = decoder.decode(
        0,
        200,
        makeQuery(values),
        makeChangesQuery(changes),
      );
      expect(txs.first.label, 'SPI 0xA5');
    });

    test('mosi field is 0xA5', () {
      final txs = decoder.decode(
        0,
        200,
        makeQuery(values),
        makeChangesQuery(changes),
      );
      expect(txs.first.fields['mosi'], '0xA5');
    });

    test('miso field is 0x3C', () {
      final txs = decoder.decode(
        0,
        200,
        makeQuery(values),
        makeChangesQuery(changes),
      );
      expect(txs.first.fields['miso'], '0x3C');
    });

    test('no error', () {
      final txs = decoder.decode(
        0,
        200,
        makeQuery(values),
        makeChangesQuery(changes),
      );
      expect(txs.first.isError, isFalse);
    });
  });

  // ── Mode 1 (CPOL=0, CPHA=1): sample on falling edge ──────────────────────

  group('Mode 1 (CPOL=0 CPHA=1) — sample on falling edge', () {
    test('decodes 0x81 on falling edges', () {
      // 0x81 = 10000001
      // CLK: rise at t=10,30,50,70,90,110,130,150; fall at t=20,40,60,80,100,120,140,160
      // For Mode 1, data is changed on rising edge, sampled on falling edge.
      // Drive MOSI before first clock (for CPHA=1, first sample is on fall at t=20).
      final mosiBits = msbBits(0x81);
      // For CPHA=1: data driven ON rising edge, sampled ON falling
      final mosiChanges = <(int, String)>[];
      // Drive before first fall: t=5 for bit0
      var prev = '0';
      for (var i = 0; i < 8; i++) {
        final driveTime = 5 + i * 20; // 5,25,45,65,85,105,125,145
        final val = mosiBits[i] == 1 ? '1' : '0';
        if (val != prev) {
          mosiChanges.add((driveTime, val));
          prev = val;
        }
      }
      if (prev != '0') mosiChanges.add((165, '0'));

      final sclkChanges = <(int, String)>[];
      for (var i = 0; i < 8; i++) {
        sclkChanges
          ..add((10 + i * 20, '1')) // rising
          ..add((20 + i * 20, '0')); // falling
      }

      final mosiValues = changesToValueMap(mosiChanges);
      final sclkValues = changesToValueMap(sclkChanges);

      final decoder = makeDecoder(cpha: '1', withMiso: false);
      final txs = decoder.decode(
        0,
        200,
        makeQuery({
          'mosi': mosiValues,
          'sclk': sclkValues,
          'cs': {0: '0'},
        }),
        makeChangesQuery({
          'sclk': sclkChanges,
          'mosi': mosiChanges,
          'cs': [(0, '0')],
        }),
      );
      expect(txs, hasLength(1));
      expect(txs.first.fields['mosi'], '0x81');
    });
  });

  // ── Mode 2 (CPOL=1, CPHA=0): sample on falling edge ──────────────────────

  group('Mode 2 (CPOL=1 CPHA=0) — sample on falling edge', () {
    test('decodes 0xC3 on falling edges', () {
      // 0xC3 = 11000011
      // CLK idles high; first active edge is falling.
      // Fall at t=10,30,50,70,90,110,130,150 (sample); rise at t=20,40,...
      final mosiBits = msbBits(0xC3);
      final mosiChanges = <(int, String)>[];
      var prev = '0';
      // Drive before first fall (t=10); setup at t=5
      for (var i = 0; i < 8; i++) {
        final driveTime = 5 + i * 20;
        final val = mosiBits[i] == 1 ? '1' : '0';
        if (val != prev) {
          mosiChanges.add((driveTime, val));
          prev = val;
        }
      }
      if (prev != '0') mosiChanges.add((165, '0'));

      final sclkChanges = <(int, String)>[];
      for (var i = 0; i < 8; i++) {
        sclkChanges
          ..add((10 + i * 20, '0')) // falling (sample edge for Mode 2)
          ..add((20 + i * 20, '1')); // rising
      }

      final decoder = makeDecoder(cpol: '1');
      final txs = decoder.decode(
        0,
        200,
        makeQuery({
          'mosi': changesToValueMap(mosiChanges),
          'sclk': {0: '1', ...changesToValueMap(sclkChanges)},
          'cs': {0: '0'},
        }),
        makeChangesQuery({
          'sclk': sclkChanges,
          'mosi': mosiChanges,
          'cs': [(0, '0')],
        }),
      );
      expect(txs, hasLength(1));
      expect(txs.first.fields['mosi'], '0xC3');
    });
  });

  // ── Mode 3 (CPOL=1, CPHA=1): sample on rising edge ───────────────────────

  group('Mode 3 (CPOL=1 CPHA=1) — sample on rising edge', () {
    test('decodes 0x55 on rising edges', () {
      // 0x55 = 01010101
      // CLK idles high; data driven on falling, sampled on rising.
      final mosiBits = msbBits(0x55);
      final mosiChanges = <(int, String)>[];
      var prev = '0';
      for (var i = 0; i < 8; i++) {
        final driveTime = i * 20 + 5; // before falling at t=10,30,...
        final val = mosiBits[i] == 1 ? '1' : '0';
        if (val != prev) {
          mosiChanges.add((driveTime, val));
          prev = val;
        }
      }
      if (prev != '0') mosiChanges.add((165, '0'));

      final sclkChanges = <(int, String)>[];
      for (var i = 0; i < 8; i++) {
        sclkChanges
          ..add((10 + i * 20, '0')) // falling (data change)
          ..add((20 + i * 20, '1')); // rising (sample edge)
      }

      final decoder = makeDecoder(cpol: '1', cpha: '1', withMiso: false);
      final txs = decoder.decode(
        0,
        200,
        makeQuery({
          'mosi': changesToValueMap(mosiChanges),
          'sclk': {0: '1', ...changesToValueMap(sclkChanges)},
          'cs': {0: '0'},
        }),
        makeChangesQuery({
          'sclk': sclkChanges,
          'mosi': mosiChanges,
          'cs': [(0, '0')],
        }),
      );
      expect(txs, hasLength(1));
      expect(txs.first.fields['mosi'], '0x55');
    });
  });

  // ── LSB-first bit order ───────────────────────────────────────────────────

  group('LSB-first bit order', () {
    // Transmit bits of 0x12 = 00010010 LSB first on the wire:
    //   wire bits: 0,1,0,0,1,0,0,0
    // MSB-first decode of wire bits = 0x12 (well, 01001000 = 0x48)
    // LSB-first decode of wire bits = reconstruct bit0..bit7 = 0x12
    test('LSB-first decodes wire bits to correct byte', () {
      final wireBits = lsbBits(0x12); // [0,1,0,0,1,0,0,0]
      final sclk = buildSclk(8);
      final mosi = buildDataLine(wireBits);

      final decoder = makeDecoder(bitOrder: 'lsb', withMiso: false);
      final txs = decoder.decode(
        0,
        200,
        makeQuery({
          'mosi': changesToValueMap(mosi),
          'sclk': changesToValueMap(sclk),
          'cs': {0: '0'},
        }),
        makeChangesQuery({
          'sclk': sclk,
          'mosi': mosi,
          'cs': [(0, '0')],
        }),
      );
      expect(txs, hasLength(1));
      expect(txs.first.fields['mosi'], '0x12');
    });

    test('MSB-first decodes same wire bits to 0x48', () {
      final wireBits = lsbBits(0x12);
      final sclk = buildSclk(8);
      final mosi = buildDataLine(wireBits);

      final decoder = makeDecoder(withMiso: false);
      final txs = decoder.decode(
        0,
        200,
        makeQuery({
          'mosi': changesToValueMap(mosi),
          'sclk': changesToValueMap(sclk),
          'cs': {0: '0'},
        }),
        makeChangesQuery({
          'sclk': sclk,
          'mosi': mosi,
          'cs': [(0, '0')],
        }),
      );
      expect(txs, hasLength(1));
      expect(txs.first.fields['mosi'], '0x48');
    });
  });

  // ── multi-byte ────────────────────────────────────────────────────────────

  group('multi-byte transfer', () {
    test('two bytes produce two hex words in fields', () {
      // 0xAB 0xCD = [10101011, 11001101]
      final mosiBits = [...msbBits(0xAB), ...msbBits(0xCD)];
      final sclk = buildSclk(16);
      final mosi = buildDataLine(mosiBits);

      final decoder = makeDecoder(withMiso: false);
      final txs = decoder.decode(
        0,
        400,
        makeQuery({
          'mosi': changesToValueMap(mosi),
          'sclk': changesToValueMap(sclk),
          'cs': {0: '0'},
        }),
        makeChangesQuery({
          'sclk': sclk,
          'mosi': mosi,
          'cs': [(0, '0')],
        }),
      );
      expect(txs, hasLength(1));
      expect(txs.first.fields['mosi'], '0xAB 0xCD');
      expect(txs.first.fields['words'], '2');
      expect(txs.first.label, 'SPI 2 words');
    });

    test('word count field matches number of words', () {
      final mosiBits = [...msbBits(0x01), ...msbBits(0x02), ...msbBits(0x03)];
      final sclk = buildSclk(24);
      final mosi = buildDataLine(mosiBits);

      final decoder = makeDecoder(withMiso: false);
      final txs = decoder.decode(
        0,
        600,
        makeQuery({
          'mosi': changesToValueMap(mosi),
          'sclk': changesToValueMap(sclk),
          'cs': {0: '0'},
        }),
        makeChangesQuery({
          'sclk': sclk,
          'mosi': mosi,
          'cs': [(0, '0')],
        }),
      );
      expect(txs.first.fields['words'], '3');
    });
  });

  // ── CS framing ────────────────────────────────────────────────────────────

  group('CS framing', () {
    test('two CS assertions produce two transactions', () {
      // Transaction 1: byte 0xAA (t=0..200), Transaction 2: byte 0x55 (t=300..500)
      final mosiBits1 = msbBits(0xAA);
      final mosiBits2 = msbBits(0x55);
      final sclk1 = buildSclk(8);
      final sclk2 = buildSclk(8, startTick: 300);
      final mosi1 = buildDataLine(mosiBits1);
      final mosi2 = buildDataLine(mosiBits2, startTick: 300);

      final decoder = makeDecoder(withMiso: false);
      final txs = decoder.decode(
        0,
        600,
        makeQuery({
          'mosi': {
            ...changesToValueMap(mosi1),
            ...changesToValueMap(mosi2),
          },
          'sclk': {
            ...changesToValueMap(sclk1),
            ...changesToValueMap(sclk2),
          },
          'cs': {0: '1', 10: '0', 200: '1', 310: '0', 500: '1'},
        }),
        makeChangesQuery({
          'sclk': [...sclk1, ...sclk2],
          'mosi': [...mosi1, ...mosi2],
          'cs': [(0, '1'), (10, '0'), (200, '1'), (310, '0'), (500, '1')],
        }),
      );
      expect(txs, hasLength(2));
      expect(txs[0].fields['mosi'], '0xAA');
      expect(txs[1].fields['mosi'], '0x55');
    });

    test('transaction time bounds match CS assertion window', () {
      final sclk = buildSclk(8, startTick: 20);
      final mosi = buildDataLine(msbBits(0xFF), startTick: 20);

      final decoder = makeDecoder(withMiso: false);
      final txs = decoder.decode(
        0,
        300,
        makeQuery({
          'mosi': changesToValueMap(mosi),
          'sclk': changesToValueMap(sclk),
          'cs': {0: '1', 15: '0', 250: '1'},
        }),
        makeChangesQuery({
          'sclk': sclk,
          'mosi': mosi,
          'cs': [(0, '1'), (15, '0'), (250, '1')],
        }),
      );
      expect(txs.first.startTime, 15);
      expect(txs.first.endTime, 250);
    });

    test('no CS binding treats entire range as one transaction', () {
      final sclk = buildSclk(8);
      final mosi = buildDataLine(msbBits(0xF0));

      final decoder = makeDecoder(withMiso: false, withCs: false);
      final txs = decoder.decode(
        0,
        200,
        makeQuery({
          'mosi': changesToValueMap(mosi),
          'sclk': changesToValueMap(sclk),
        }),
        makeChangesQuery({'sclk': sclk, 'mosi': mosi}),
      );
      expect(txs, hasLength(1));
      expect(txs.first.fields['mosi'], '0xF0');
    });

    test('active-high CS framing', () {
      final sclk = buildSclk(8, startTick: 10);
      final mosi = buildDataLine(msbBits(0x42), startTick: 10);

      final decoder = makeDecoder(
        withMiso: false,
        csActiveLevel: '1', // active-high
      );
      final txs = decoder.decode(
        0,
        250,
        makeQuery({
          'mosi': changesToValueMap(mosi),
          'sclk': changesToValueMap(sclk),
          'cs': {0: '0', 5: '1', 230: '0'}, // CS high = active
        }),
        makeChangesQuery({
          'sclk': sclk,
          'mosi': mosi,
          'cs': [(0, '0'), (5, '1'), (230, '0')],
        }),
      );
      expect(txs, hasLength(1));
      expect(txs.first.fields['mosi'], '0x42');
    });
  });

  // ── unidirectional (no MISO) ──────────────────────────────────────────────

  group('MISO absent (unidirectional mode)', () {
    test('miso field absent from results', () {
      final sclk = buildSclk(8);
      final mosi = buildDataLine(msbBits(0xDE));

      final decoder = makeDecoder(withMiso: false);
      final txs = decoder.decode(
        0,
        200,
        makeQuery({
          'mosi': changesToValueMap(mosi),
          'sclk': changesToValueMap(sclk),
          'cs': {0: '0'},
        }),
        makeChangesQuery({
          'sclk': sclk,
          'mosi': mosi,
          'cs': [(0, '0')],
        }),
      );
      expect(txs.first.fields.containsKey('miso'), isFalse);
      expect(txs.first.fields['mosi'], '0xDE');
    });
  });

  // ── empty / no-data edge cases ────────────────────────────────────────────

  group('edge cases', () {
    test('no SCLK changes returns empty list', () {
      final decoder = makeDecoder(withMiso: false, withCs: false);
      final txs = decoder.decode(
        0,
        100,
        makeQuery({
          'mosi': {0: '0'},
          'sclk': {0: '0'},
        }),
        makeChangesQuery({'sclk': [], 'mosi': []}),
      );
      expect(txs, isEmpty);
    });

    test('returns empty list when no sample edges in range', () {
      // Only falling edges for Mode 0 (sampleOnRising=true) → no samples
      final decoder = makeDecoder(withMiso: false, withCs: false);
      final txs = decoder.decode(
        0,
        100,
        makeQuery({
          'mosi': {0: '0'},
          'sclk': {0: '0'},
        }),
        makeChangesQuery({
          'sclk': [(10, '0'), (30, '0'), (50, '0')], // all falling
          'mosi': [],
        }),
      );
      expect(txs, isEmpty);
    });

    test('query returns null for unbound signal — treated as 0', () {
      // MOSI signal is bound but query returns null → treated as 0
      final sclk = buildSclk(8);
      final decoder = makeDecoder(withMiso: false, withCs: false);
      final txs = decoder.decode(
        0,
        200,
        makeQuery({'mosi': {}, 'sclk': changesToValueMap(sclk)}),
        makeChangesQuery({'sclk': sclk, 'mosi': []}),
      );
      expect(txs, hasLength(1));
      expect(txs.first.fields['mosi'], '0x00');
    });
  });

  // ── error detection ───────────────────────────────────────────────────────

  group('error detection', () {
    test('MOSI change at sample edge is flagged as glitch', () {
      // All 8 bits arrive on rising edges simultaneously (data changes at
      // the same tick as the sample edge → glitch for every bit).
      final sclkChanges = <(int, String)>[];
      final mosiChanges = <(int, String)>[];
      // Build clock + simultaneous data changes
      for (var i = 0; i < 8; i++) {
        final rise = 10 + i * 20;
        final fall = 20 + i * 20;
        sclkChanges
          ..add((rise, '1'))
          ..add((fall, '0'));
        mosiChanges.add((rise, i.isEven ? '1' : '0')); // change AT rising edge
      }

      final decoder = makeDecoder(withMiso: false, withCs: false);
      final txs = decoder.decode(
        0,
        200,
        makeQuery({
          'mosi': changesToValueMap(mosiChanges),
          'sclk': changesToValueMap(sclkChanges),
        }),
        makeChangesQuery({'sclk': sclkChanges, 'mosi': mosiChanges}),
      );
      expect(txs.first.isError, isTrue);
      expect(txs.first.errorMessage, contains('MOSI changes at sample edge'));
    });

    test('incomplete word (CS deasserts mid-byte) sets isError', () {
      // Only 4 clock cycles then CS deasserts → partial byte
      final sclkChanges = buildSclk(4); // 4 bits of an 8-bit word
      final mosiChanges = buildDataLine(msbBits(0xF0).sublist(0, 4));

      final decoder = makeDecoder(withMiso: false);
      final txs = decoder.decode(
        0,
        200,
        makeQuery({
          'mosi': changesToValueMap(mosiChanges),
          'sclk': changesToValueMap(sclkChanges),
          'cs': {0: '0', 100: '1'}, // deasserts before 8 bits
        }),
        makeChangesQuery({
          'sclk': sclkChanges,
          'mosi': mosiChanges,
          'cs': [(0, '0'), (100, '1')],
        }),
      );
      expect(txs.first.isError, isTrue);
      expect(txs.first.errorMessage, contains('Incomplete word'));
    });
  });

  // ── fixture test ─────────────────────────────────────────────────────────

  group('spi_basic.vcd fixture', () {
    late Map<String, List<(int, String)>> changes;
    late Map<String, Map<int, String>> values;

    setUp(() {
      changes = {
        'sclk': _fixtureSclkChanges,
        'mosi': _fixtureMosiChanges,
        'miso': _fixtureMisoChanges,
        'cs': _fixtureCsChanges,
      };
      values = {
        'sclk': changesToValueMap(_fixtureSclkChanges),
        'mosi': changesToValueMap(_fixtureMosiChanges),
        'miso': changesToValueMap(_fixtureMisoChanges),
        'cs': changesToValueMap(_fixtureCsChanges, initial: '1'),
      };
    });

    test('decodes two transactions matching expected_transactions.json', () {
      final jsonFile = File(
        'test/fixtures/protocol/spi/generated/spi_basic.expected_transactions.json',
      );
      final expected =
          (jsonDecode(jsonFile.readAsStringSync()) as List<dynamic>)
              .cast<Map<String, dynamic>>();

      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        600,
        makeQuery(values),
        makeChangesQuery(changes),
      );

      expect(txs, hasLength(expected.length));

      for (var i = 0; i < txs.length; i++) {
        final e = expected[i];
        expect(
          txs[i].startTime,
          e['startTime'] as int,
          reason: 'tx[$i] startTime',
        );
        expect(txs[i].endTime, e['endTime'] as int, reason: 'tx[$i] endTime');
        expect(txs[i].label, e['label'] as String, reason: 'tx[$i] label');
        expect(txs[i].isError, e['isError'] as bool, reason: 'tx[$i] isError');
        final expFields = (e['fields'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v as String),
        );
        expect(txs[i].fields, expFields, reason: 'tx[$i] fields');
      }
    });

    test('transaction 1: 0xA5 MOSI, 0x3C MISO', () {
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        600,
        makeQuery(values),
        makeChangesQuery(changes),
      );
      expect(txs[0].fields['mosi'], '0xA5');
      expect(txs[0].fields['miso'], '0x3C');
    });

    test('transaction 2: 0xDE 0xAD MOSI, 0xBE 0xEF MISO', () {
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        600,
        makeQuery(values),
        makeChangesQuery(changes),
      );
      expect(txs[1].fields['mosi'], '0xDE 0xAD');
      expect(txs[1].fields['miso'], '0xBE 0xEF');
    });

    test('no errors in fixture transactions', () {
      final decoder = makeDecoder();
      final txs = decoder.decode(
        0,
        600,
        makeQuery(values),
        makeChangesQuery(changes),
      );
      for (final tx in txs) {
        expect(tx.isError, isFalse);
      }
    });
  });
}
