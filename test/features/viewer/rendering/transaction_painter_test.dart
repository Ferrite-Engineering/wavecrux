// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' hide TextStyle;

import 'package:flutter/painting.dart' show TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/features/viewer/rendering/transaction_painter.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

// 1 tick = 1 pixel, viewport 0..1000 ticks.
const _mapper = TimeMapper(
  startTime: 0,
  endTime: 1000,
  viewportWidth: 1000,
  ticksPerPixel: 1,
  panOffsetTicks: 0,
);

const _laneBounds = Rect.fromLTWH(0, 0, 1000, 28);
const _laneColor = Color(0xFF1565C0);
const _labelStyle = TextStyle(fontSize: 10);

Canvas _makeCanvas() => Canvas(PictureRecorder());

void _paint(
  Canvas canvas, {
  List<DecodedTransaction> transactions = const [],
  DecodedTransaction? selectedTransaction,
  TimeMapper mapper = _mapper,
}) {
  TransactionPainter.paint(
    canvas: canvas,
    laneBounds: _laneBounds,
    transactions: transactions,
    timeMapper: mapper,
    laneColor: _laneColor,
    labelStyle: _labelStyle,
    selectedTransaction: selectedTransaction,
  );
}

List<TransactionBlock> _blocks({
  List<DecodedTransaction> transactions = const [],
  DecodedTransaction? selectedTransaction,
  TimeMapper mapper = _mapper,
  Rect laneBounds = _laneBounds,
}) => TransactionPainter.buildBlocks(
  laneBounds: laneBounds,
  transactions: transactions,
  timeMapper: mapper,
  selectedTransaction: selectedTransaction,
);

/// Builds [count] non-overlapping transactions spanning [0, count * period).
List<DecodedTransaction> _burst(int count, {int period = 4, int width = 2}) => [
  for (var i = 0; i < count; i++)
    DecodedTransaction(
      startTime: i * period,
      endTime: i * period + width,
      label: 'T$i',
    ),
];

void main() {
  group('TransactionPainter.paint', () {
    test('no-op with empty transaction list', () {
      _paint(_makeCanvas());
    });

    test('paints single normal transaction without throwing', () {
      _paint(
        _makeCanvas(),
        transactions: const [
          DecodedTransaction(startTime: 100, endTime: 300, label: 'Write 0xFF'),
        ],
      );
    });

    test('paints error and normal transactions in same lane', () {
      _paint(
        _makeCanvas(),
        transactions: const [
          DecodedTransaction(startTime: 0, endTime: 200, label: 'OK'),
          DecodedTransaction(
            startTime: 300,
            endTime: 500,
            label: 'ERR',
            isError: true,
          ),
          DecodedTransaction(startTime: 600, endTime: 800, label: 'OK2'),
        ],
      );
    });

    test('no-op when timeMapper is empty (zero-duration)', () {
      const emptyMapper = TimeMapper(
        startTime: 0,
        endTime: 0,
        viewportWidth: 1000,
        ticksPerPixel: 1,
        panOffsetTicks: 0,
      );
      _paint(
        _makeCanvas(),
        transactions: const [
          DecodedTransaction(startTime: 0, endTime: 0, label: 'X'),
        ],
        mapper: emptyMapper,
      );
    });

    test('lane with zero height does not crash', () {
      TransactionPainter.paint(
        canvas: _makeCanvas(),
        laneBounds: const Rect.fromLTWH(0, 0, 1000, 0),
        transactions: const [
          DecodedTransaction(startTime: 0, endTime: 500, label: 'X'),
        ],
        timeMapper: _mapper,
        laneColor: _laneColor,
        labelStyle: _labelStyle,
      );
    });

    test('overlapping transactions render without throwing', () {
      // AXI-family decoders emit at completion time, so overlapping (in-flight)
      // transactions are expected input — see the buildBlocks overlap tests.
      _paint(
        _makeCanvas(),
        transactions: const [
          DecodedTransaction(startTime: 100, endTime: 600, label: 'A'),
          DecodedTransaction(startTime: 300, endTime: 700, label: 'B'),
        ],
      );
    });

    test('transaction with fields paints without throwing', () {
      _paint(
        _makeCanvas(),
        transactions: const [
          DecodedTransaction(
            startTime: 100,
            endTime: 400,
            label: 'I2C Write',
            fields: {
              'address': '0x50',
              'rw': 'W',
              'data': '0xFF',
              'ack': 'ACK',
            },
          ),
        ],
      );
    });
  });

  group('TransactionPainter.buildBlocks — visible window', () {
    test('empty list and empty mapper produce no blocks', () {
      expect(_blocks(), isEmpty);
      expect(
        _blocks(
          transactions: const [
            DecodedTransaction(startTime: 0, endTime: 10, label: 'A'),
          ],
          mapper: const TimeMapper(
            startTime: 0,
            endTime: 0,
            viewportWidth: 1000,
            ticksPerPixel: 1,
            panOffsetTicks: 0,
          ),
        ),
        isEmpty,
      );
    });

    test('transactions entirely before visible range are skipped', () {
      // Mapper starts visible range at time 500.
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 500,
        ticksPerPixel: 1,
        panOffsetTicks: 500,
      );
      expect(
        _blocks(
          transactions: const [
            DecodedTransaction(startTime: 0, endTime: 200, label: 'Old'),
          ],
          mapper: mapper,
        ),
        isEmpty,
      );
    });

    test('transactions entirely after visible range are skipped', () {
      // Mapper only shows times 0..500.
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 500,
        ticksPerPixel: 1,
        panOffsetTicks: 0,
      );
      expect(
        _blocks(
          transactions: const [
            DecodedTransaction(startTime: 600, endTime: 900, label: 'Future'),
          ],
          mapper: mapper,
        ),
        isEmpty,
      );
    });

    test('a transaction straddling the left edge is still drawn', () {
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 1000,
        viewportWidth: 500,
        ticksPerPixel: 1,
        panOffsetTicks: 500,
      );
      final blocks = _blocks(
        transactions: const [
          DecodedTransaction(startTime: 400, endTime: 700, label: 'Straddle'),
        ],
        mapper: mapper,
      );
      expect(blocks, hasLength(1));
      expect(blocks.single.label, 'Straddle');
    });

    test('only the visible slice of a long trace is materialized', () {
      // 10k transactions across 0..40000 ticks; the mapper shows 0..1000.
      final blocks = _blocks(transactions: _burst(10000));
      // Everything past tick 1000 is excluded by the binary-searched window.
      expect(blocks.length, lessThan(300));
      for (final block in blocks) {
        expect(block.xStart, lessThanOrEqualTo(_laneBounds.right));
      }
    });

    test(
      'an early long transaction overlapping the window is not dropped',
      () {
        // Regression: the old walk-back left bound scanned only immediate
        // predecessors' endTime, so an early long transaction (A) whose window
        // overlap was masked by a shorter intervening transaction (B) that ends
        // before the window silently vanished. The prefix-max left bound keeps
        // it. Window is [500, 1000].
        const mapper = TimeMapper(
          startTime: 0,
          endTime: 1000,
          viewportWidth: 500,
          ticksPerPixel: 1,
          panOffsetTicks: 500,
        );
        final blocks = _blocks(
          transactions: const [
            // Sorted by startTime, as the provider boundary guarantees.
            DecodedTransaction(startTime: 0, endTime: 900, label: 'A'),
            DecodedTransaction(startTime: 100, endTime: 200, label: 'B'),
          ],
          mapper: mapper,
        );
        expect(blocks.map((b) => b.label), contains('A'));
      },
    );

    test('every overlapping transaction is accounted for in the blocks', () {
      // Many staggered transactions of mixed durations, all sorted by
      // startTime but heavily overlapping with out-of-order endTimes (mirrors
      // the forencich_axi_register fixture shape). The blocks account for
      // exactly the transactions that intersect the window — no drops (the old
      // walk-back dropped early long ones), no spurious extras.
      final txs = <DecodedTransaction>[
        for (var i = 0; i < 200; i++)
          DecodedTransaction(
            startTime: i * 10,
            endTime: i * 10 + (i.isEven ? 800 : 30),
            label: 'T$i',
          ),
      ];
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 2000,
        viewportWidth: 500,
        ticksPerPixel: 1,
        panOffsetTicks: 700,
      );
      const visStart = 700;
      const visEnd = 1200;
      final overlappingCount = txs
          .where((t) => t.endTime >= visStart && t.startTime <= visEnd)
          .length;
      final blocks = _blocks(transactions: txs, mapper: mapper);
      final accounted = blocks.fold<int>(0, (s, b) => s + b.coalescedCount);
      expect(accounted, overlappingCount);
    });
  });

  group('TransactionPainter.buildBlocks — density coalescing', () {
    test('block count stays bounded by lane width at extreme zoom-out', () {
      // 200k transactions compressed into a 1000 px lane: every block is far
      // narrower than a pixel column, so they must coalesce rather than
      // producing one draw per transaction.
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 800000,
        viewportWidth: 1000,
        ticksPerPixel: 800,
        panOffsetTicks: 0,
      );
      final blocks = _blocks(transactions: _burst(200000), mapper: mapper);
      expect(blocks, isNotEmpty);
      expect(blocks.length, lessThanOrEqualTo(_laneBounds.width + 1));
      expect(blocks.every((b) => b.isDensityBar), isTrue);
      // Every source transaction is accounted for by exactly one bar.
      expect(
        blocks.fold<int>(0, (sum, b) => sum + b.coalescedCount),
        200000,
      );
    });

    test('a density bar inherits error and selection from its members', () {
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 4000,
        viewportWidth: 1000,
        ticksPerPixel: 100,
        panOffsetTicks: 0,
      );
      const selected = DecodedTransaction(
        startTime: 10,
        endTime: 12,
        label: 'B',
      );
      final blocks = _blocks(
        transactions: const [
          DecodedTransaction(startTime: 0, endTime: 2, label: 'A'),
          selected,
          DecodedTransaction(
            startTime: 20,
            endTime: 22,
            label: 'C',
            isError: true,
          ),
        ],
        selectedTransaction: selected,
        mapper: mapper,
      );
      expect(blocks, hasLength(1));
      expect(blocks.single.isDensityBar, isTrue);
      expect(blocks.single.coalescedCount, 3);
      expect(blocks.single.isError, isTrue);
      expect(blocks.single.isSelected, isTrue);
    });

    test('wide transactions are never coalesced', () {
      final blocks = _blocks(
        transactions: const [
          DecodedTransaction(startTime: 0, endTime: 100, label: 'A'),
          DecodedTransaction(startTime: 200, endTime: 400, label: 'B'),
          DecodedTransaction(startTime: 500, endTime: 700, label: 'C'),
        ],
      );
      expect(blocks, hasLength(3));
      expect(blocks.every((b) => !b.isDensityBar), isTrue);
    });
  });

  group('TransactionPainter.buildBlocks — labels and selection', () {
    test('label is dropped below the 24 px threshold and kept above it', () {
      final narrow = _blocks(
        transactions: const [
          DecodedTransaction(startTime: 400, endTime: 420, label: 'TXT'),
        ],
      );
      expect(narrow.single.label, isNull);

      final wide = _blocks(
        transactions: const [
          DecodedTransaction(startTime: 100, endTime: 300, label: 'SPI Write'),
        ],
      );
      expect(wide.single.label, 'SPI Write');
    });

    test(
      'selection matches by startTime/endTime/label, not object identity',
      () {
        const tx1 = DecodedTransaction(
          startTime: 100,
          endTime: 300,
          label: 'Frame',
        );
        const tx2 = DecodedTransaction(
          startTime: 100,
          endTime: 300,
          label: 'Frame',
        );
        expect(
          _blocks(
            transactions: const [tx1],
            selectedTransaction: tx2,
          ).single.isSelected,
          isTrue,
        );
      },
    );

    test('a same-span transaction with a different label is not selected', () {
      const drawn = DecodedTransaction(
        startTime: 100,
        endTime: 300,
        label: 'Frame',
      );
      const other = DecodedTransaction(
        startTime: 100,
        endTime: 300,
        label: 'Other',
      );
      expect(
        _blocks(
          transactions: const [drawn],
          selectedTransaction: other,
        ).single.isSelected,
        isFalse,
      );
    });

    test('no selection means no block is marked selected', () {
      expect(
        _blocks(
          transactions: const [
            DecodedTransaction(startTime: 100, endTime: 300, label: 'A'),
          ],
        ).single.isSelected,
        isFalse,
      );
    });
  });

  group('TransactionPainter — label paragraph cache', () {
    setUp(TransactionPainter.clearParagraphCache);

    test('repeated labels reuse one laid-out paragraph', () {
      // 200 blocks, 2 distinct labels, all at the same width.
      final transactions = [
        for (var i = 0; i < 200; i++)
          DecodedTransaction(
            startTime: i * 40,
            endTime: i * 40 + 30,
            label: i.isEven ? 'Read' : 'Write',
          ),
      ];
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 8000,
        viewportWidth: 8000,
        ticksPerPixel: 1,
        panOffsetTicks: 0,
      );
      TransactionPainter.paint(
        canvas: _makeCanvas(),
        laneBounds: const Rect.fromLTWH(0, 0, 8000, 28),
        transactions: transactions,
        timeMapper: mapper,
        laneColor: _laneColor,
        labelStyle: _labelStyle,
      );
      expect(TransactionPainter.debugParagraphCacheSize, 2);
    });

    test('cache never grows past its capacity', () {
      final transactions = [
        for (var i = 0; i < 400; i++)
          DecodedTransaction(
            startTime: i * 40,
            endTime: i * 40 + 30,
            label: 'Label $i',
          ),
      ];
      const mapper = TimeMapper(
        startTime: 0,
        endTime: 16000,
        viewportWidth: 16000,
        ticksPerPixel: 1,
        panOffsetTicks: 0,
      );
      TransactionPainter.paint(
        canvas: _makeCanvas(),
        laneBounds: const Rect.fromLTWH(0, 0, 16000, 28),
        transactions: transactions,
        timeMapper: mapper,
        laneColor: _laneColor,
        labelStyle: _labelStyle,
      );
      expect(
        TransactionPainter.debugParagraphCacheSize,
        lessThanOrEqualTo(256),
      );
    });
  });
}
