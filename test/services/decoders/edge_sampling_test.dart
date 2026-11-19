// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Regression tests for the sampling instant of every clocked open-core
// decoder.
//
// Registered RTL outputs change at the rising clock edge's own timestamp, and
// `SignalValueQuery` returns the value AFTER a change at the queried time. A
// decoder that reads a signal at the edge therefore reads the next cycle's
// value: transactions land one clock early, a beat accepted on the first edge
// is lost, and the values launched by the last edge are read as one more cycle.
// Each decoder must read the value in effect just before the edge.
//
// Every bus below is built by [EdgeBus] (or by hand for the serial buses) so
// that data and control change exactly at rising-edge timestamps.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/services/decoders/ahb_lite_decoder.dart';
import 'package:wavecrux/services/decoders/apb_decoder.dart';
import 'package:wavecrux/services/decoders/axi4lite_decoder.dart';
import 'package:wavecrux/services/decoders/decoder_value_helpers.dart';
import 'package:wavecrux/services/decoders/i2c_decoder.dart';
import 'package:wavecrux/services/decoders/isa/instruction_set_toml_loader.dart';
import 'package:wavecrux/services/decoders/isa/isa_decoder_assets.dart';
import 'package:wavecrux/services/decoders/isa/riscv_decoder.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';
import 'package:wavecrux/services/decoders/wishbone_decoder.dart';

import 'edge_sampling_bus.dart';

String v32(int value) => EdgeBus.bin(value, 32);

void main() {
  group('sampleBefore', () {
    test('reads the value in effect just before the edge', () {
      final changes = {
        'x': [(0, '0'), (20, '1')],
      };
      final query = queryOf(changes);
      // The query itself is "last change at or before t": a read at the
      // change's own tick returns the new value.
      expect(query('x', 20), '1');
      expect(sampleBefore(query, 'x', 20), '0');
      expect(sampleBefore(query, 'x', 21), '1');
      expect(preEdgeTime(20), 19);
    });

    test('is null before the first change', () {
      final query = queryOf({
        'x': [(10, '1')],
      });
      expect(sampleBefore(query, 'x', 10), isNull);
    });
  });

  // ── APB ───────────────────────────────────────────────────────────────────

  group('APB, signals that change on the rising edge', () {
    const apbBindings = {
      'pclk': 'tb.pclk',
      'presetn': 'tb.presetn',
      'psel': 'tb.psel',
      'penable': 'tb.penable',
      'pwrite': 'tb.pwrite',
      'paddr': 'tb.paddr',
      'pwdata': 'tb.pwdata',
      'prdata': 'tb.prdata',
      'pready': 'tb.pready',
    };

    // c0 write SETUP (the first edge), c1 ACCESS; c3 read SETUP, c4 ACCESS
    // with a wait state, c5 ACCESS completes on the last edge. Cycle 7 (past
    // the last edge) drops PSEL, which a decoder reading at the edge would see
    // at edge 6 and abort the read.
    EdgeBus bus() {
      final b = EdgeBus(cycles: 6, clock: 'pclk')
        ..set('presetn', {}, fill: '1')
        ..set('psel', {0: '1', 1: '1', 3: '1', 4: '1', 5: '1'})
        ..set('penable', {1: '1', 4: '1', 5: '1'})
        ..set('pwrite', {0: '1', 1: '1'})
        ..set(
          'paddr',
          {
            0: EdgeBus.bin(0x10, 32),
            1: EdgeBus.bin(0x10, 32),
            3: EdgeBus.bin(0x20, 32),
            4: EdgeBus.bin(0x20, 32),
            5: EdgeBus.bin(0x20, 32),
          },
          fill: EdgeBus.bin(0, 32),
        )
        ..set('pwdata', {0: v32(0xAB), 1: v32(0xAB)}, fill: v32(0))
        ..set('prdata', {4: v32(0xDEAD), 5: v32(0xCAFE)}, fill: v32(0))
        ..set('pready', {1: '1', 5: '1'});
      return b;
    }

    test('decodes a write SETUP on the very first rising edge', () {
      final b = bus();
      final txs = const ApbDecoder(
        DecoderConfig(signalBindings: apbBindings),
      ).decode(0, b.endTime, b.query, b.changesQuery);
      expect(txs, hasLength(2));
      final write = txs[0];
      expect(write.startTime, EdgeBus.edge(0));
      expect(write.endTime, EdgeBus.edge(1));
      expect(write.fields['type'], 'Write');
      expect(write.fields['address'], '0x00000010');
      expect(write.fields['data'], '0x000000AB');
      expect(write.isError, isFalse);
    });

    test('reads PRDATA of the cycle PREADY completes, wait state included', () {
      final b = bus();
      final txs = const ApbDecoder(
        DecoderConfig(signalBindings: apbBindings),
      ).decode(0, b.endTime, b.query, b.changesQuery);
      final read = txs[1];
      expect(read.startTime, EdgeBus.edge(3));
      expect(read.fields['type'], 'Read');
      expect(read.fields['data'], '0x0000CAFE');
      expect(read.isError, isFalse);
    });

    test('a transfer that completes on the very last edge is kept', () {
      final b = bus();
      final txs = const ApbDecoder(
        DecoderConfig(signalBindings: apbBindings),
      ).decode(0, b.endTime, b.query, b.changesQuery);
      expect(txs.last.endTime, EdgeBus.edge(5));
      expect(txs.any((t) => t.isError), isFalse);
    });
  });

  // ── AXI4-Lite ─────────────────────────────────────────────────────────────

  group('AXI4-Lite, signals that change on the rising edge', () {
    const axiBindings = {
      'aclk': 'tb.aclk',
      'aresetn': 'tb.aresetn',
      'awaddr': 'tb.awaddr',
      'awvalid': 'tb.awvalid',
      'awready': 'tb.awready',
      'wdata': 'tb.wdata',
      'wvalid': 'tb.wvalid',
      'wready': 'tb.wready',
      'bresp': 'tb.bresp',
      'bvalid': 'tb.bvalid',
      'bready': 'tb.bready',
      'araddr': 'tb.araddr',
      'arvalid': 'tb.arvalid',
      'arready': 'tb.arready',
      'rdata': 'tb.rdata',
      'rresp': 'tb.rresp',
      'rvalid': 'tb.rvalid',
      'rready': 'tb.rready',
    };

    // c0: AW and W both accepted on the very first edge; c1: B. c3: AR; c4: R,
    // the last edge. Cycle 5, past the last edge, launches a fresh AW and W
    // handshake that no edge ever captures.
    EdgeBus bus() => EdgeBus(cycles: 5, clock: 'aclk')
      ..set('aresetn', {}, fill: '1')
      ..set('awvalid', {0: '1', 5: '1'})
      ..set('awready', {0: '1', 5: '1'})
      ..set('awaddr', {0: v32(0x1000), 5: v32(0x7777)}, fill: v32(0))
      ..set('wvalid', {0: '1', 5: '1'})
      ..set('wready', {0: '1', 5: '1'})
      ..set('wdata', {0: v32(0xDEADBEEF), 5: v32(0x1)}, fill: v32(0))
      ..set('bvalid', {1: '1'})
      ..set('bready', {1: '1'})
      ..set('bresp', {}, fill: 'b00')
      ..set('arvalid', {3: '1'})
      ..set('arready', {3: '1'})
      ..set('araddr', {3: v32(0x2000)}, fill: v32(0))
      ..set('rvalid', {4: '1'})
      ..set('rready', {4: '1'})
      ..set('rdata', {4: v32(0x1234)}, fill: v32(0))
      ..set('rresp', {}, fill: 'b00');

    test('a write accepted on the very first edge decodes at that edge', () {
      final b = bus();
      final txs = const Axi4LiteDecoder(
        DecoderConfig(signalBindings: axiBindings),
      ).decode(0, b.endTime, b.query, b.changesQuery);
      final write = txs.firstWhere((t) => t.fields['type'] == 'Write');
      expect(write.startTime, EdgeBus.edge(0));
      expect(write.endTime, EdgeBus.edge(1));
      expect(write.fields['address'], '0x00001000');
      expect(write.fields['data'], '0xDEADBEEF');
      expect(write.isError, isFalse);
    });

    test("a read response on the last edge carries that edge's data", () {
      final b = bus();
      final txs = const Axi4LiteDecoder(
        DecoderConfig(signalBindings: axiBindings),
      ).decode(0, b.endTime, b.query, b.changesQuery);
      final read = txs.firstWhere((t) => t.fields['type'] == 'Read');
      expect(read.startTime, EdgeBus.edge(3));
      expect(read.endTime, EdgeBus.edge(4));
      expect(read.fields['data'], '0x00001234');
    });

    test('values launched by the last edge are not read as one more cycle', () {
      final b = bus();
      final txs = const Axi4LiteDecoder(
        DecoderConfig(signalBindings: axiBindings),
      ).decode(0, b.endTime, b.query, b.changesQuery);
      // One write, one read; the AW/W launched at the last edge are not an
      // unanswered write.
      expect(txs, hasLength(2));
      expect(txs.any((t) => t.isError), isFalse);
    });
  });

  // ── AHB-Lite ──────────────────────────────────────────────────────────────

  group('AHB-Lite, signals that change on the rising edge', () {
    const ahbBindings = {
      'hclk': 'tb.hclk',
      'hresetn': 'tb.hresetn',
      'haddr': 'tb.haddr',
      'htrans': 'tb.htrans',
      'hwrite': 'tb.hwrite',
      'hsize': 'tb.hsize',
      'hburst': 'tb.hburst',
      'hwdata': 'tb.hwdata',
      'hrdata': 'tb.hrdata',
      'hready': 'tb.hready',
      'hresp': 'tb.hresp',
    };

    // c0: write address phase on the very first edge; c1: its data phase.
    // c3: read address phase; c4: its data phase, on the last edge. Cycle 5,
    // past the last edge, holds HREADY low: a decoder reading at the edge
    // would see a wait state on the last edge and never complete the read.
    EdgeBus bus() => EdgeBus(cycles: 5, clock: 'hclk')
      ..set('hresetn', {}, fill: '1')
      ..set('htrans', {0: 'b10', 3: 'b10'}, fill: 'b00')
      ..set('hwrite', {0: '1', 1: '1'})
      ..set('haddr', {0: v32(0x40), 3: v32(0x80)}, fill: v32(0))
      ..set('hsize', {}, fill: 'b010')
      ..set('hburst', {}, fill: 'b000')
      ..set('hwdata', {1: v32(0xCAFEBABE)}, fill: v32(0))
      ..set('hrdata', {4: v32(0x11223344)}, fill: v32(0))
      ..set('hready', {5: '0'}, fill: '1')
      ..set('hresp', {});

    test('an address phase on the very first edge is captured', () {
      final b = bus();
      final txs = const AhbLiteDecoder(
        DecoderConfig(signalBindings: ahbBindings),
      ).decode(0, b.endTime, b.query, b.changesQuery);
      final write = txs.firstWhere((t) => t.fields['type'] == 'Write');
      expect(write.startTime, EdgeBus.edge(0));
      expect(write.endTime, EdgeBus.edge(1));
      expect(write.fields['address'], '0x00000040');
      expect(write.fields['data'], '0xCAFEBABE');
      expect(write.isError, isFalse);
    });

    test('a data phase that completes on the very last edge is kept', () {
      final b = bus();
      final txs = const AhbLiteDecoder(
        DecoderConfig(signalBindings: ahbBindings),
      ).decode(0, b.endTime, b.query, b.changesQuery);
      final read = txs.firstWhere((t) => t.fields['type'] == 'Read');
      expect(read.startTime, EdgeBus.edge(3));
      expect(read.endTime, EdgeBus.edge(4));
      expect(read.fields['data'], '0x11223344');
      expect(txs.any((t) => t.isError), isFalse);
    });
  });

  // ── Wishbone ──────────────────────────────────────────────────────────────

  group('Wishbone, signals that change on the rising edge', () {
    const baseBindings = {
      'clk': 'tb.clk',
      'rst': 'tb.rst',
      'cyc': 'tb.cyc',
      'stb': 'tb.stb',
      'we': 'tb.we',
      'adr': 'tb.adr',
      'dat_o': 'tb.dat_o',
      'dat_i': 'tb.dat_i',
      'ack': 'tb.ack',
    };

    test('a classic beat acknowledged on the very first edge is decoded', () {
      // c0: write acked at once; c1: CYC drops; c2: read acked at once. Cycle
      // 4, past the last edge (cycles: 4), launches another acked beat that
      // nothing captures.
      final b = EdgeBus(cycles: 4)
        ..set('rst', {})
        ..set('cyc', {0: '1', 2: '1', 4: '1'})
        ..set('stb', {0: '1', 2: '1', 4: '1'})
        ..set('we', {0: '1'})
        ..set('adr', {0: v32(0x100), 2: v32(0x104), 4: v32(0x108)})
        ..set('dat_o', {0: v32(0xA5)}, fill: v32(0))
        ..set('dat_i', {2: v32(0x77)}, fill: v32(0))
        ..set('ack', {0: '1', 2: '1', 4: '1'});
      final txs = const WishboneDecoder(
        DecoderConfig(
          signalBindings: baseBindings,
          parameters: {'revision': 'b3'},
        ),
      ).decode(0, b.endTime, b.query, b.changesQuery);
      expect(txs, hasLength(2));
      expect(txs[0].startTime, EdgeBus.edge(0));
      expect(txs[0].fields['type'], 'Write');
      expect(txs[0].fields['address'], '0x00000100');
      expect(txs[0].fields['data'], '0x000000A5');
      expect(txs[1].startTime, EdgeBus.edge(2));
      expect(txs[1].fields['type'], 'Read');
      expect(txs[1].fields['data'], '0x00000077');
      expect(txs.any((t) => t.isError), isFalse);
    });

    test('a pipelined request accepted on the very first edge is decoded', () {
      // c0: request accepted (STALL low); c1: its ACK, carrying the read data.
      final b = EdgeBus(cycles: 4)
        ..set('rst', {})
        ..set('cyc', {0: '1', 1: '1', 4: '1'})
        ..set('stb', {0: '1', 4: '1'})
        ..set('stall', {})
        ..set('we', {})
        ..set('adr', {0: v32(0x200), 4: v32(0x204)})
        ..set('dat_o', {})
        ..set('dat_i', {1: v32(0xBEEF)}, fill: v32(0))
        ..set('ack', {1: '1'});
      final txs = const WishboneDecoder(
        DecoderConfig(
          signalBindings: {...baseBindings, 'stall': 'tb.stall'},
          parameters: {'revision': 'b4'},
        ),
      ).decode(0, b.endTime, b.query, b.changesQuery);
      expect(txs, hasLength(1));
      expect(txs.single.startTime, EdgeBus.edge(0));
      expect(txs.single.endTime, EdgeBus.edge(1));
      expect(txs.single.fields['address'], '0x00000200');
      expect(txs.single.fields['data'], '0x0000BEEF');
      expect(txs.single.isError, isFalse);
    });
  });

  // ── RISC-V instruction trace ──────────────────────────────────────────────

  group('RISC-V trace, signals that change on the rising edge', () {
    IsaDecoderAssets assets() => IsaDecoderAssets.fromMap({
      for (final name in [
        'RV32I',
        'RV32M',
        'RV32A',
        'RV32F',
        'RV32C-lower',
        'RV64I',
        'RV64M',
        'RV64A',
        'RV64D',
        'RV64C-lower',
      ])
        name: parseInstructionSetToml(
          File('assets/decoders/isa/riscv/$name.toml').readAsStringSync(),
          sourceLabel: '$name.toml',
        ),
    });

    RiscvDecoder decoder(Map<String, String> bindings) => RiscvDecoder(
      DecoderConfig(
        signalBindings: bindings,
        parameters: const {'xlen': '32'},
      ),
      assets(),
    );

    test(
      'the instruction on the first edge and no extra one after the last',
      () {
        // Two edges. The value launched at the last edge (cycle 2) is never
        // retired.
        final b = EdgeBus(cycles: 2)
          ..set(
            'instruction',
            {0: v32(0x00612423), 1: v32(0x00c12503), 2: v32(0x00000073)},
          );
        final txs = decoder({
          'clk': 'tb.clk',
          'instruction': 'tb.instruction',
        }).decode(0, b.endTime, b.query, b.changesQuery);
        expect(txs.map((t) => t.label), ['sw t1, 8(sp)', 'lw a0, 12(sp)']);
        expect(txs.map((t) => t.startTime), [EdgeBus.edge(0), EdgeBus.edge(1)]);
      },
    );

    test('a valid strobe is read before the edge too', () {
      // valid high only on cycle 0: the instruction on the first edge is
      // retired, the one on cycle 1 (valid low) is not, and the valid that
      // rises at cycle 2 (past the last edge) is not read.
      final b = EdgeBus(cycles: 2)
        ..set(
          'instruction',
          {0: v32(0x00612423), 1: v32(0x00c12503), 2: v32(0x00000073)},
        )
        ..set('valid', {0: '1', 2: '1'});
      final txs = decoder({
        'clk': 'tb.clk',
        'instruction': 'tb.instruction',
        'valid': 'tb.valid',
      }).decode(0, b.endTime, b.query, b.changesQuery);
      expect(txs.map((t) => t.label), ['sw t1, 8(sp)']);
      expect(txs.single.startTime, EdgeBus.edge(0));
    });
  });

  // ── SPI ───────────────────────────────────────────────────────────────────

  group('SPI, data that changes on the sampling edge', () {
    // Mode 0, MSB first, 8 bits. SCLK rises at 20, 40, ... 160. MOSI/MISO hold
    // bit i at the rising edge of bit i and change to bit i+1 either exactly
    // at that rising edge (a simulator launching the next bit with the clock)
    // or at the falling edge (the textbook arrangement).
    Map<String, List<(int, String)>> frame(
      int mosi,
      int miso, {
      required bool changeOnSampleEdge,
    }) {
      String bit(int byte, int i) => ((byte >> (7 - i)) & 1).toString();
      final sclk = <(int, String)>[(0, '0')];
      final mosiCh = <(int, String)>[(0, bit(mosi, 0))];
      final misoCh = <(int, String)>[(0, bit(miso, 0))];
      for (var i = 0; i < 8; i++) {
        final rise = 20 * (i + 1);
        sclk
          ..add((rise, '1'))
          ..add((rise + 10, '0'));
        final next = rise + (changeOnSampleEdge ? 0 : 10);
        // The bit after the last one is a distinct value no edge captures.
        mosiCh.add((next, i < 7 ? bit(mosi, i + 1) : bit(~mosi & 0xFF, 7)));
        misoCh.add((next, i < 7 ? bit(miso, i + 1) : bit(~miso & 0xFF, 7)));
      }
      return {
        'sclk': sclk,
        'mosi': mosiCh,
        'miso': misoCh,
        'cs': [(0, '1'), (1, '0'), (180, '1')],
      };
    }

    List<DecodedTransaction> run(Map<String, List<(int, String)>> changes) =>
        const SpiDecoder(
          DecoderConfig(
            signalBindings: {
              'sclk': 'tb.sclk',
              'mosi': 'tb.mosi',
              'miso': 'tb.miso',
              'cs': 'tb.cs',
            },
          ),
        ).decode(0, 200, queryOf(changes), changesQueryOf(changes));

    test('MOSI and MISO that change at the sampling edge decode correctly', () {
      final txs = run(frame(0xA5, 0x3C, changeOnSampleEdge: true));
      expect(txs, hasLength(1));
      expect(txs.single.fields['mosi'], '0xA5');
      expect(txs.single.fields['miso'], '0x3C');
      expect(txs.single.isError, isFalse);
    });

    test('data that changes on the opposite edge still decodes', () {
      final txs = run(frame(0xA5, 0x3C, changeOnSampleEdge: false));
      expect(txs, hasLength(1));
      expect(txs.single.fields['mosi'], '0xA5');
      expect(txs.single.fields['miso'], '0x3C');
      expect(txs.single.isError, isFalse);
    });

    test('the first bit, set before the first edge, is the first bit read', () {
      // 0x80 differs from its neighbours only in the first bit: a decoder
      // reading after the edge sees 0x00.
      final txs = run(frame(0x80, 0x01, changeOnSampleEdge: true));
      expect(txs.single.fields['mosi'], '0x80');
      expect(txs.single.fields['miso'], '0x01');
    });
  });

  // ── I2C ───────────────────────────────────────────────────────────────────

  group('I2C, SDA that changes on the SCL rising edge', () {
    // Address 0x48 write (ACK), data 0x55 (ACK). SCL rises at 20 + 20k and
    // falls 10 later. START is SDA falling at t=10 with SCL high; STOP is SDA
    // rising with SCL high after the last bit. Bit k+1 is launched at the
    // rising edge that samples bit k (or, when [onFalling], at the falling
    // edge), so SDA changes while SCL is high in the first arrangement.
    Map<String, List<(int, String)>> frame({required bool onFalling}) {
      const bits = [
        // 0x48 << 1 | W = 0x90
        1, 0, 0, 1, 0, 0, 0, 0, 0,
        // 0x55, ACK
        0, 1, 0, 1, 0, 1, 0, 1, 0,
      ];
      final scl = <(int, String)>[(0, '1'), (15, '0')];
      // Bit 0 is set at the falling edge after START.
      final sda = <(int, String)>[(0, '1'), (10, '0'), (15, '${bits[0]}')];
      for (var k = 0; k < bits.length; k++) {
        final rise = 20 + 20 * k;
        scl
          ..add((rise, '1'))
          ..add((rise + 10, '0'));
        final next = k + 1 < bits.length ? bits[k + 1] : 0;
        sda.add((rise + (onFalling ? 10 : 0), '$next'));
      }
      // One more rising edge, SDA low, then STOP: SDA rises with SCL high.
      final stopRise = 20 + 20 * bits.length;
      scl.add((stopRise, '1'));
      sda.add((stopRise + 10, '1'));
      // Drop consecutive duplicates, as a waveform would.
      List<(int, String)> dedupe(List<(int, String)> list) {
        final out = <(int, String)>[];
        for (final e in list) {
          if (out.isNotEmpty && out.last.$2 == e.$2) continue;
          if (out.isNotEmpty && out.last.$1 == e.$1) {
            out.last = e;
            continue;
          }
          out.add(e);
        }
        return out;
      }

      return {'sda': dedupe(sda), 'scl': dedupe(scl)};
    }

    List<DecodedTransaction> run(Map<String, List<(int, String)>> changes) =>
        const I2cDecoder(
          DecoderConfig(
            signalBindings: {'sda': 'tb.sda', 'scl': 'tb.scl'},
          ),
        ).decode(0, 500, queryOf(changes), changesQueryOf(changes));

    test('bits launched at the rising edge are read as the edge captures', () {
      final txs = run(frame(onFalling: false));
      expect(txs, hasLength(1));
      expect(txs.single.fields['address'], '0x48');
      expect(txs.single.fields['rw'], 'W');
      expect(txs.single.fields['data'], '0x55');
      expect(txs.single.fields['ack'], 'ACK');
      expect(txs.single.isError, isFalse);
    });

    test('SDA that changes at the falling edge still decodes', () {
      final txs = run(frame(onFalling: true));
      expect(txs, hasLength(1));
      expect(txs.single.fields['address'], '0x48');
      expect(txs.single.fields['data'], '0x55');
      expect(txs.single.isError, isFalse);
    });

    test('SDA changing as SCL rises is not a START or STOP', () {
      // Only one START and one STOP in the frame, so one transaction (not a
      // chain of repeated starts) comes out of it.
      final txs = run(frame(onFalling: false));
      expect(txs.single.errorMessage, isNull);
    });
  });
}
