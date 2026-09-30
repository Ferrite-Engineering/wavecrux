// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Decoder edge-case robustness sweep.
//
// For every registered open-core decoder, this file throws ~20 pathological
// inputs at `decode()` and asserts the call returns within the timeout
// without throwing. The decoder is allowed to return any output — empty,
// error-tagged, even nonsensical — but it must NOT crash. Real-world VCDs
// arrive with missing signals, X/Z values, dumpoff gaps, simultaneous
// transitions, and timestamps that overflow 32-bit assumptions; the goal
// here is to catch decoders that fall over on those shapes before users do.
//
// New decoder → add an entry to `buildDecoders()`. The shape-driven
// `_edgeCases` list applies uniformly; no per-decoder branching.
//
// New edge case → append to `_edgeCases`. Each case constructs its own
// `SignalValueQuery` / `SignalChangesQuery` synthetically (no wellen FFI),
// so the sweep stays fast and pure-Dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/services/decoders/ahb_lite_decoder.dart';
import 'package:wavecrux/services/decoders/apb_decoder.dart';
import 'package:wavecrux/services/decoders/axi4lite_decoder.dart';
import 'package:wavecrux/services/decoders/i2c_decoder.dart';
import 'package:wavecrux/services/decoders/isa/isa_decoder_assets.dart';
import 'package:wavecrux/services/decoders/isa/riscv_decoder.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';
import 'package:wavecrux/services/decoders/spi_flash/spi_flash_decoder.dart';
import 'package:wavecrux/services/decoders/uart_decoder.dart';
import 'package:wavecrux/services/decoders/wishbone_decoder.dart';

class _DecoderEntry {
  const _DecoderEntry(this.definition, this.build);
  final DecoderDefinition definition;
  final ProtocolDecoder Function(DecoderConfig config) build;
}

class _EdgeCase {
  const _EdgeCase(this.name, this.apply);
  final String name;
  final void Function(_DecoderEntry entry) apply;
}

// ── helpers ──────────────────────────────────────────────────────────────────

Map<String, String> _dummyBindings(_DecoderEntry e) {
  final out = <String, String>{};
  for (final s in e.definition.requiredSignals) {
    out[s.name] = 'top.dut.${s.name}';
  }
  for (final s in e.definition.optionalSignals) {
    out[s.name] = 'top.dut.${s.name}';
  }
  return out;
}

ProtocolDecoder _withBindings(
  _DecoderEntry e,
  Map<String, String> bindings, {
  Map<String, Object?> parameters = const {},
}) => e.build(
  DecoderConfig(
    signalBindings: bindings,
    parameters: parameters,
  ),
);

SignalValueQuery _constQuery(String? value) =>
    (_, _) => value;

SignalChangesQuery _emptyChanges() =>
    (_, _, _) => const [];

SignalChangesQuery _heldConstantChanges(String value) =>
    (_, start, end) => 0 >= start && 0 < end ? [(0, value)] : const [];

SignalChangesQuery _changesList(List<(int, String)> all) =>
    (_, start, end) => [
      for (final c in all)
        if (c.$1 >= start && c.$1 < end) c,
    ];

void _runDecode(
  ProtocolDecoder decoder, {
  required SignalValueQuery query,
  required SignalChangesQuery changesQuery,
  int startTime = 0,
  int endTime = 1000,
  Timescale? timescale,
}) {
  decoder.decode(
    startTime,
    endTime,
    query,
    changesQuery,
    timescale: timescale,
  );
}

// ── edge cases ───────────────────────────────────────────────────────────────

final List<_EdgeCase> _edgeCases = <_EdgeCase>[
  _EdgeCase('emptyBindings', (e) {
    final d = e.build(const DecoderConfig(signalBindings: {}));
    _runDecode(d, query: _constQuery(null), changesQuery: _emptyChanges());
  }),

  _EdgeCase('bindingsPresentButSignalsAbsent', (e) {
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(d, query: _constQuery(null), changesQuery: _emptyChanges());
  }),

  _EdgeCase('constantZero', (e) {
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(
      d,
      query: _constQuery('0'),
      changesQuery: _heldConstantChanges('0'),
    );
  }),

  _EdgeCase('constantOne', (e) {
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(
      d,
      query: _constQuery('1'),
      changesQuery: _heldConstantChanges('1'),
    );
  }),

  _EdgeCase('constantX', (e) {
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(
      d,
      query: _constQuery('x'),
      changesQuery: _heldConstantChanges('x'),
    );
  }),

  _EdgeCase('constantZ', (e) {
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(
      d,
      query: _constQuery('z'),
      changesQuery: _heldConstantChanges('z'),
    );
  }),

  _EdgeCase('zeroDurationRange', (e) {
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(
      d,
      endTime: 0,
      query: _constQuery(null),
      changesQuery: _emptyChanges(),
    );
  }),

  _EdgeCase('singleChangeAtZero', (e) {
    final d = _withBindings(e, _dummyBindings(e));
    final changes = _changesList(const [(0, '0')]);
    _runDecode(d, query: _constQuery('0'), changesQuery: changes);
  }),

  _EdgeCase('clockTogglesNothingElseMoves', (e) {
    // 20 clock edges, every other signal returns held constant 0. Decoders
    // that walk clock edges will iterate; those that look for other
    // protocol-specific transitions will see no traffic.
    final ticks = <(int, String)>[
      for (var i = 0; i < 20; i++) (i * 10, i.isEven ? '0' : '1'),
    ];
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(
      d,
      endTime: 200,
      query: (name, t) {
        // Crude: return clock-edge value for any name; constant 0 for
        // everything else. Decoders that have a 'clk'/'sclk'/'pclk'/
        // 'hclk' binding will see edges; the rest see constant 0.
        if (name == 'clk' ||
            name == 'sclk' ||
            name == 'pclk' ||
            name == 'hclk' ||
            name == 'aclk' ||
            name == 'scl') {
          final phase = t ~/ 10;
          return phase.isEven ? '0' : '1';
        }
        return '0';
      },
      changesQuery: (name, s, end) {
        if (name == 'clk' ||
            name == 'sclk' ||
            name == 'pclk' ||
            name == 'hclk' ||
            name == 'aclk' ||
            name == 'scl') {
          return [
            for (final c in ticks)
              if (c.$1 >= s && c.$1 < end) c,
          ];
        }
        return const [];
      },
    );
  }),

  _EdgeCase('emptyValueString', (e) {
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(
      d,
      query: _constQuery(''),
      changesQuery: _heldConstantChanges(''),
    );
  }),

  _EdgeCase('invalidValueCharacter', (e) {
    // '@' is not a legal VCD value (only 0/1/x/z, plus binary/hex strings).
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(
      d,
      query: _constQuery('@'),
      changesQuery: _heldConstantChanges('@'),
    );
  }),

  _EdgeCase('decimalValueCharacter', (e) {
    // '5' is not a legal 4-state value either.
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(
      d,
      query: _constQuery('5'),
      changesQuery: _heldConstantChanges('5'),
    );
  }),

  _EdgeCase('simultaneousChangesAtSameTick', (e) {
    final d = _withBindings(e, _dummyBindings(e));
    // Two transitions at t=100 — a "race". A robust decoder collapses or
    // picks one; it must not throw on a multi-value timestamp.
    final changes = _changesList(const [
      (50, '0'),
      (100, '0'),
      (100, '1'),
      (100, '0'),
      (200, '1'),
    ]);
    _runDecode(
      d,
      endTime: 300,
      query: (_, t) => t < 100 ? '0' : '1',
      changesQuery: changes,
    );
  }),

  _EdgeCase('subCycleFlicker', (e) {
    // Toggle on every single tick — sub-cycle flicker. Decoders that
    // sample at a slower rate must still terminate.
    final flicker = <(int, String)>[
      for (var i = 0; i < 500; i++) (i, i.isEven ? '0' : '1'),
    ];
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(
      d,
      endTime: 500,
      query: (_, t) => t.isEven ? '0' : '1',
      changesQuery: _changesList(flicker),
    );
  }),

  _EdgeCase('dumpoffMidStream', (e) {
    // Signal goes 0 → x (dumpoff) → 1. Decoders walking the trace must
    // tolerate a temporary X gap without crashing on int-parse attempts.
    final changes = _changesList(const [
      (0, '0'),
      (100, 'x'),
      (200, '1'),
    ]);
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(
      d,
      endTime: 300,
      query: (_, t) {
        if (t < 100) return '0';
        if (t < 200) return 'x';
        return '1';
      },
      changesQuery: changes,
    );
  }),

  _EdgeCase('timescaleFs', (e) {
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(
      d,
      query: _constQuery(null),
      changesQuery: _emptyChanges(),
      timescale: const Timescale(factor: 1, unit: TimescaleUnit.femtoSeconds),
    );
  }),

  _EdgeCase('timescaleSeconds', (e) {
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(
      d,
      query: _constQuery(null),
      changesQuery: _emptyChanges(),
      timescale: const Timescale(factor: 1, unit: TimescaleUnit.seconds),
    );
  }),

  _EdgeCase('timescaleUnknown', (e) {
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(
      d,
      query: _constQuery(null),
      changesQuery: _emptyChanges(),
      timescale: const Timescale(factor: 1, unit: TimescaleUnit.unknown),
    );
  }),

  _EdgeCase('hugeTickRange', (e) {
    // 5_000_000_000 > 2^32 — catches per-tick `for (var t = startTime;
    // t < endTime; t++)` loops that would never terminate within the
    // test timeout.
    final d = _withBindings(e, _dummyBindings(e));
    _runDecode(
      d,
      endTime: 5000000000,
      query: _constQuery(null),
      changesQuery: _emptyChanges(),
    );
  }),

  _EdgeCase('nonMonotonicChanges', (e) {
    // Out-of-order changes — a buggy upstream that hands us a non-sorted
    // list. The decoder may produce garbage but must not throw.
    final d = _withBindings(e, _dummyBindings(e));
    final changes = _changesList(const [
      (300, '1'),
      (100, '0'),
      (200, '1'),
      (50, '0'),
    ]);
    _runDecode(
      d,
      endTime: 400,
      query: (_, t) => t.isEven ? '0' : '1',
      changesQuery: changes,
    );
  }),

  _EdgeCase('deeplyNestedSignalPath', (e) {
    final bindings = <String, String>{};
    final deep = List.generate(15, (i) => 'level$i').join('.');
    for (final s in e.definition.requiredSignals) {
      bindings[s.name] = '$deep.${s.name}';
    }
    for (final s in e.definition.optionalSignals) {
      bindings[s.name] = '$deep.${s.name}';
    }
    final d = e.build(DecoderConfig(signalBindings: bindings));
    _runDecode(d, query: _constQuery(null), changesQuery: _emptyChanges());
  }),
];

// ── main ─────────────────────────────────────────────────────────────────────

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final riscvAssets = await IsaDecoderAssets.loadFromBundle();
  final decoders = <_DecoderEntry>[
    const _DecoderEntry(AhbLiteDecoder.decoderDefinition, AhbLiteDecoder.new),
    const _DecoderEntry(ApbDecoder.decoderDefinition, ApbDecoder.new),
    const _DecoderEntry(Axi4LiteDecoder.decoderDefinition, Axi4LiteDecoder.new),
    const _DecoderEntry(I2cDecoder.decoderDefinition, I2cDecoder.new),
    _DecoderEntry(
      RiscvDecoder.decoderDefinition,
      (c) => RiscvDecoder(c, riscvAssets),
    ),
    const _DecoderEntry(SpiDecoder.decoderDefinition, SpiDecoder.new),
    const _DecoderEntry(SpiFlashDecoder.decoderDefinition, SpiFlashDecoder.new),
    const _DecoderEntry(UartDecoder.decoderDefinition, UartDecoder.new),
    const _DecoderEntry(WishboneDecoder.decoderDefinition, WishboneDecoder.new),
  ];

  group('decoder edge-case sweep — every decoder must not crash', () {
    test('sweep covers every open-core decoder', () {
      // Bump this count and add the new decoder above when a new
      // open-core decoder lands in `app.dart`'s registration block.
      expect(
        decoders.length,
        9,
        reason: 'add new decoders to the sweep and bump the count',
      );
    });

    for (final entry in decoders) {
      group(entry.definition.id, () {
        for (final edgeCase in _edgeCases) {
          test(edgeCase.name, () {
            edgeCase.apply(entry);
          }, timeout: const Timeout(Duration(seconds: 5)));
        }
      });
    }
  });
}
