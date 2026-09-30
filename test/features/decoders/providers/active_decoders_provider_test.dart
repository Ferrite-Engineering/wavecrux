// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';
import 'package:wavecrux/services/decoders/spi_flash/spi_flash_decoder.dart';

import '../../../helpers/product_telemetry_config.dart';

// ── fakes ─────────────────────────────────────────────────────────────────────

class _MockSource extends Mock implements WaveformDataSource {}

/// Minimal WaveformSourceNotifier override that exposes a fixed source.
class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(WaveformDataSource? source) : _source = source;

  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

// ── helpers ───────────────────────────────────────────────────────────────────

ProviderContainer _makeContainer({WaveformDataSource? source}) {
  final container = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      waveformSourceProvider.overrideWith(
        () => _FakeSourceNotifier(source),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

const _spiConfig = DecoderConfig(
  signalBindings: {
    'sclk': 'top.sclk',
    'mosi': 'top.mosi',
  },
);

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(DecoderRegistry.instance.clear);
  tearDown(DecoderRegistry.instance.clear);

  group('ActiveDecodersNotifier — initial state', () {
    test('starts empty', () {
      final c = _makeContainer();
      expect(c.read(activeDecodersProvider), isEmpty);
    });
  });

  group('ActiveDecodersNotifier — addDecoder', () {
    test('appends one decoder', () {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier).addDecoder('spi', _spiConfig);
      final state = c.read(activeDecodersProvider);
      expect(state, hasLength(1));
      expect(state.first.decoderId, 'spi');
      expect(state.first.config, _spiConfig);
      expect(state.first.transactions, isEmpty);
    });

    test('assigns unique ids', () {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier)
        ..addDecoder('spi', _spiConfig)
        ..addDecoder(
          'uart',
          const DecoderConfig(signalBindings: {'tx': 'top.tx'}),
        );
      final ids = c.read(activeDecodersProvider).map((d) => d.id).toList();
      expect(ids.toSet(), hasLength(2));
    });

    test('assigns instanceNumber 1 to first instance of a decoder type', () {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier).addDecoder('spi', _spiConfig);
      expect(c.read(activeDecodersProvider).first.instanceNumber, 1);
    });

    test('increments instanceNumber per decoder type', () {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier)
        ..addDecoder('spi', _spiConfig)
        ..addDecoder('spi', _spiConfig)
        ..addDecoder(
          'uart',
          const DecoderConfig(signalBindings: {'tx': 'top.tx'}),
        );
      final decoders = c.read(activeDecodersProvider);
      expect(decoders[0].instanceNumber, 1); // SPI #1
      expect(decoders[1].instanceNumber, 2); // SPI #2
      expect(decoders[2].instanceNumber, 1); // UART #1
    });

    test('instanceNumber is not reused after removeDecoder', () {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier)
        ..addDecoder('spi', _spiConfig)
        ..addDecoder('spi', _spiConfig);
      final first = c.read(activeDecodersProvider).first.id;
      c.read(activeDecodersProvider.notifier).removeDecoder(first);
      // Adding a third SPI should get #3, not reuse #1.
      c.read(activeDecodersProvider.notifier).addDecoder('spi', _spiConfig);
      final last = c.read(activeDecodersProvider).last;
      expect(last.instanceNumber, 3);
    });

    test('appends multiple decoders in order', () {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier)
        ..addDecoder('spi', _spiConfig)
        ..addDecoder(
          'uart',
          const DecoderConfig(signalBindings: {'tx': 'top.tx'}),
        );
      final decoderIds = c
          .read(activeDecodersProvider)
          .map((d) => d.decoderId)
          .toList();
      expect(decoderIds, ['spi', 'uart']);
    });
  });

  group('ActiveDecodersNotifier — removeDecoder', () {
    test('removes the matching decoder', () {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier).addDecoder('spi', _spiConfig);
      final id = c.read(activeDecodersProvider).first.id;

      c.read(activeDecodersProvider.notifier).removeDecoder(id);

      expect(c.read(activeDecodersProvider), isEmpty);
    });

    test('only removes the specified decoder', () {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier)
        ..addDecoder('spi', _spiConfig)
        ..addDecoder(
          'uart',
          const DecoderConfig(signalBindings: {'tx': 'top.tx'}),
        );
      final first = c.read(activeDecodersProvider).first.id;

      c.read(activeDecodersProvider.notifier).removeDecoder(first);

      final remaining = c.read(activeDecodersProvider);
      expect(remaining, hasLength(1));
      expect(remaining.first.decoderId, 'uart');
    });

    test('no-op for unknown id', () {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier)
        ..addDecoder('spi', _spiConfig)
        ..removeDecoder('nonexistent');
      expect(c.read(activeDecodersProvider), hasLength(1));
    });
  });

  group('ActiveDecodersNotifier — updateConfig', () {
    test('replaces config for matching id', () {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier).addDecoder('spi', _spiConfig);
      final id = c.read(activeDecodersProvider).first.id;

      const newConfig = DecoderConfig(
        signalBindings: {'sclk': 'top.clk', 'mosi': 'top.data'},
      );
      c.read(activeDecodersProvider.notifier).updateConfig(id, newConfig);

      expect(c.read(activeDecodersProvider).first.config, newConfig);
    });

    test('leaves other decoders unchanged', () {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier)
        ..addDecoder('spi', _spiConfig)
        ..addDecoder(
          'uart',
          const DecoderConfig(signalBindings: {'tx': 'top.tx'}),
        );
      final firstId = c.read(activeDecodersProvider).first.id;

      const newConfig = DecoderConfig(signalBindings: {'sclk': 'top.clk'});
      c.read(activeDecodersProvider.notifier).updateConfig(firstId, newConfig);

      expect(
        c.read(activeDecodersProvider).last.config,
        const DecoderConfig(signalBindings: {'tx': 'top.tx'}),
      );
    });
  });

  group('ActiveDecodersNotifier — decodeAll', () {
    test('no-op when no waveform loaded', () async {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier).addDecoder('spi', _spiConfig);
      await c.read(activeDecodersProvider.notifier).decodeAll();
      expect(
        c.read(activeDecodersProvider).first.transactions,
        isEmpty,
      );
    });

    test('no-op when state is empty', () async {
      final source = _MockSource();
      final c = _makeContainer(source: source);
      await c.read(activeDecodersProvider.notifier).decodeAll();
      verifyNever(() => source.startTime);
    });

    test('populates transactions for registered decoder', () async {
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );

      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(10000);
      when(() => source.timescale).thenReturn(null);
      when(() => source.isSignalLoaded(any())).thenReturn(true);
      when(() => source.valueAt(any(), any())).thenReturn('0');
      when(
        () => source.changesInRange(any(), any(), any()),
      ).thenReturn(<SignalChange>[]);

      final c = _makeContainer(source: source);
      c
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            SpiDecoder.decoderDefinition.id,
            const DecoderConfig(
              signalBindings: {'sclk': 'top.sclk', 'mosi': 'top.mosi'},
            ),
          );

      await c.read(activeDecodersProvider.notifier).decodeAll();

      final active = c.read(activeDecodersProvider).first;
      expect(active.transactions, isA<List<DecodedTransaction>>());
    });

    test('loads unloaded signals before decoding', () async {
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );

      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(1000);
      when(() => source.timescale).thenReturn(null);
      when(() => source.isSignalLoaded(any())).thenReturn(false);
      when(() => source.loadSignal(any())).thenAnswer((_) async {});
      when(() => source.valueAt(any(), any())).thenReturn('0');
      when(
        () => source.changesInRange(any(), any(), any()),
      ).thenReturn(<SignalChange>[]);

      final c = _makeContainer(source: source);
      c
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            SpiDecoder.decoderDefinition.id,
            const DecoderConfig(
              signalBindings: {'sclk': 'top.sclk', 'mosi': 'top.mosi'},
            ),
          );

      await c.read(activeDecodersProvider.notifier).decodeAll();

      verify(() => source.loadSignal(any())).called(greaterThan(0));
    });

    test('skips decoder with unregistered id', () async {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(1000);
      when(() => source.timescale).thenReturn(null);

      final c = _makeContainer(source: source);
      c
          .read(activeDecodersProvider.notifier)
          .addDecoder('unknown_decoder', _spiConfig);

      await c.read(activeDecodersProvider.notifier).decodeAll();

      expect(c.read(activeDecodersProvider), hasLength(1));
      expect(
        c.read(activeDecodersProvider).first.transactions,
        isEmpty,
      );
    });

    test('stacked decoder without an active parent decodes to empty, '
        'not a crash', () async {
      // Regression: a StackedDecoder whose parent is not active falls back to
      // a `const []` parent-transaction list. Sorting that unmodifiable list
      // threw `Unsupported operation: Cannot modify an unmodifiable list` in
      // decodeAll's Pass 2. The fix copies into a growable list first.
      DecoderRegistry.instance.register(
        SpiFlashDecoder.decoderDefinition,
        SpiFlashDecoder.new,
      );

      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(1000);
      when(() => source.timescale).thenReturn(null);
      when(() => source.isSignalLoaded(any())).thenReturn(true);
      when(() => source.valueAt(any(), any())).thenReturn('0');
      when(
        () => source.changesInRange(any(), any(), any()),
      ).thenReturn(<SignalChange>[]);

      final c = _makeContainer(source: source);
      // Add ONLY the stacked child — its parent `spi` is deliberately absent.
      c
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            SpiFlashDecoder.decoderDefinition.id,
            const DecoderConfig(signalBindings: {}),
          );

      await expectLater(
        c.read(activeDecodersProvider.notifier).decodeAll(),
        completes,
      );
      expect(
        c.read(activeDecodersProvider).single.transactions,
        isEmpty,
      );
    });
  });

  group('ActiveDecodersNotifier — clearAll', () {
    test('removes all decoders', () {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier)
        ..addDecoder('spi', _spiConfig)
        ..addDecoder(
          'uart',
          const DecoderConfig(signalBindings: {'tx': 'top.tx'}),
        );

      c.read(activeDecodersProvider.notifier).clearAll();

      expect(c.read(activeDecodersProvider), isEmpty);
    });

    test('no-op when already empty', () {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier).clearAll();
      expect(c.read(activeDecodersProvider), isEmpty);
    });

    test(
      'does not notify listeners when clearing an already-empty list '
      '(regression: mobile ValueColumnPanel markNeedsBuild-during-build on '
      'file open — openFile() calls clearAll() while the drawer scope builds)',
      () {
        final c = _makeContainer();
        c.read(activeDecodersProvider.notifier).addDecoder('spi', _spiConfig);
        // removeDecoder leaves state as a fresh `.toList()` empty list — NOT the
        // canonical `const []` — so a subsequent unconditional `state = const []`
        // is a non-identical write that WOULD notify. The guard must suppress it.
        final id = c.read(activeDecodersProvider).first.id;
        c.read(activeDecodersProvider.notifier).removeDecoder(id);
        expect(c.read(activeDecodersProvider), isEmpty);

        var notifications = 0;
        c.listen(activeDecodersProvider, (_, _) => notifications++);
        c.read(activeDecodersProvider.notifier).clearAll(); // empty → no emit
        expect(notifications, 0);
      },
    );

    test('resets instanceNumber counter so new decoders start from 1', () {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier)
        ..addDecoder('spi', _spiConfig) // SPI #1
        ..addDecoder('spi', _spiConfig); // SPI #2

      c.read(activeDecodersProvider.notifier).clearAll();

      c.read(activeDecodersProvider.notifier).addDecoder('spi', _spiConfig);
      expect(c.read(activeDecodersProvider).first.instanceNumber, 1);
    });

    test('resets id counter so new decoders start from decoder_0', () {
      final c = _makeContainer();
      c.read(activeDecodersProvider.notifier)
        ..addDecoder('spi', _spiConfig) // decoder_0
        ..addDecoder('spi', _spiConfig); // decoder_1

      c.read(activeDecodersProvider.notifier).clearAll();

      c.read(activeDecodersProvider.notifier).addDecoder('spi', _spiConfig);
      final id = c.read(activeDecodersProvider).first.id;
      expect(id, 'decoder_0');
    });

    test('clears decoded transactions along with decoder instances', () async {
      const definition = DecoderDefinition(
        id: 'stub',
        displayName: 'Stub',
        description: 'Test stub',
        requiredSignals: [
          SignalBinding(name: 'sig', description: 'test signal'),
        ],
      );
      DecoderRegistry.instance.register(definition, _StubDecoder.new);

      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(1000);
      when(() => source.timescale).thenReturn(null);
      when(() => source.isSignalLoaded(any())).thenReturn(true);
      when(() => source.valueAt(any(), any())).thenReturn('0');
      when(
        () => source.changesInRange(any(), any(), any()),
      ).thenReturn(<SignalChange>[]);

      final c = _makeContainer(source: source);
      c
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            'stub',
            const DecoderConfig(signalBindings: {'sig': 'top.sig'}),
          );
      await c.read(activeDecodersProvider.notifier).decodeAll();

      // Confirm transactions were populated.
      expect(
        c.read(activeDecodersProvider).first.transactions,
        isNotEmpty,
      );

      c.read(activeDecodersProvider.notifier).clearAll();

      expect(c.read(activeDecodersProvider), isEmpty);
    });

    test('remove + re-add decoder → same transactions on second add '
        '(closes verification gap §12 — Remove + re-add decoder: same '
        'transactions on second add)', () async {
      const definition = DecoderDefinition(
        id: 'stub',
        displayName: 'Stub',
        description: 'Test stub',
        requiredSignals: [
          SignalBinding(name: 'sig', description: 'test signal'),
        ],
      );
      DecoderRegistry.instance.register(definition, _StubDecoder.new);

      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(1000);
      when(() => source.timescale).thenReturn(null);
      when(() => source.isSignalLoaded(any())).thenReturn(true);
      when(() => source.valueAt(any(), any())).thenReturn('0');
      when(
        () => source.changesInRange(any(), any(), any()),
      ).thenReturn(<SignalChange>[]);

      final c = _makeContainer(source: source);
      const config = DecoderConfig(signalBindings: {'sig': 'top.sig'});

      // First add → decode → capture transactions.
      c.read(activeDecodersProvider.notifier).addDecoder('stub', config);
      await c.read(activeDecodersProvider.notifier).decodeAll();
      final firstTransactions = List.of(
        c.read(activeDecodersProvider).first.transactions,
      );
      expect(firstTransactions, isNotEmpty);

      // Remove → state empty.
      final firstId = c.read(activeDecodersProvider).first.id;
      c.read(activeDecodersProvider.notifier).removeDecoder(firstId);
      expect(c.read(activeDecodersProvider), isEmpty);

      // Re-add same decoder type with same config → decode again →
      // transactions match the first add's output (deterministic decoder
      // against the same fake source).
      c.read(activeDecodersProvider.notifier).addDecoder('stub', config);
      await c.read(activeDecodersProvider.notifier).decodeAll();
      final secondTransactions = c
          .read(activeDecodersProvider)
          .first
          .transactions;

      expect(
        secondTransactions,
        equals(firstTransactions),
        reason:
            'a deterministic decoder run against the same source data '
            'should produce the same DecodedTransaction list on the second '
            'add — guards against stale signal-load caches or stateful '
            'decoder instances leaking across remove/re-add cycles',
      );
    });

    test(
      'load source A with decoder, clear (simulating file close), empty',
      () {
        final c = _makeContainer();
        c.read(activeDecodersProvider.notifier)
          ..addDecoder('spi', _spiConfig)
          ..addDecoder(
            'uart',
            const DecoderConfig(signalBindings: {'tx': 'top.tx'}),
          );
        expect(c.read(activeDecodersProvider), hasLength(2));

        // Simulate WaveformSourceNotifier.close() clearing decoders.
        c.read(activeDecodersProvider.notifier).clearAll();

        expect(c.read(activeDecodersProvider), isEmpty);
      },
    );
  });

  group('decodeAll', () {
    test('stores the decoded transactions on the instance', () async {
      const definition = DecoderDefinition(
        id: 'stub',
        displayName: 'Stub',
        description: 'Test stub',
        requiredSignals: [
          SignalBinding(name: 'sig', description: 'test signal'),
        ],
      );
      DecoderRegistry.instance.register(
        definition,
        _StubDecoder.new,
      );

      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(1000);
      when(() => source.timescale).thenReturn(null);
      when(() => source.isSignalLoaded(any())).thenReturn(true);
      when(() => source.valueAt(any(), any())).thenReturn('0');
      when(
        () => source.changesInRange(any(), any(), any()),
      ).thenReturn(<SignalChange>[]);

      final c = _makeContainer(source: source);
      c
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            'stub',
            const DecoderConfig(signalBindings: {'sig': 'top.sig'}),
          );

      await c.read(activeDecodersProvider.notifier).decodeAll();

      final txns = c.read(activeDecodersProvider).first.transactions;
      expect(txns, hasLength(1));
      expect(txns.first.label, 'Stub TX');
    });
  });

  group('ActiveDecodersNotifier — provider-boundary sort', () {
    test(
      'decodeAll sorts a completion-order decoder ascending by startTime',
      () async {
        // Regression: AXI-family decoders emit at completion time, so their
        // transactions arrive unsorted. TransactionPainter's binary-searched
        // visible window requires ascending startTime; the sort belongs at the
        // provider boundary, not per-frame in the painter.
        const definition = DecoderDefinition(
          id: 'unsorted',
          displayName: 'Unsorted',
          description: 'Emits out-of-order transactions',
          requiredSignals: [
            SignalBinding(name: 'sig', description: 'test signal'),
          ],
        );
        DecoderRegistry.instance.register(definition, _UnsortedDecoder.new);

        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.endTime).thenReturn(1000);
        when(() => source.timescale).thenReturn(null);
        when(() => source.isSignalLoaded(any())).thenReturn(true);
        when(() => source.valueAt(any(), any())).thenReturn('0');
        when(
          () => source.changesInRange(any(), any(), any()),
        ).thenReturn(<SignalChange>[]);

        final c = _makeContainer(source: source);
        c
            .read(activeDecodersProvider.notifier)
            .addDecoder(
              'unsorted',
              const DecoderConfig(signalBindings: {'sig': 'top.sig'}),
            );

        await c.read(activeDecodersProvider.notifier).decodeAll();

        final txns = c.read(activeDecodersProvider).single.transactions;
        final starts = txns.map((t) => t.startTime).toList();
        expect(starts, orderedEquals(<int>[100, 300, 500, 700]));
      },
    );
  });
}

// ── unsorted stub decoder ──────────────────────────────────────────────────────

/// Emits transactions in completion order (out of startTime order), like an
/// AXI-family decoder that appends a burst when its last beat retires.
class _UnsortedDecoder implements ProtocolDecoder {
  // Config is unused: this stub emits a fixed transaction list.
  // ignore: avoid_unused_constructor_parameters
  const _UnsortedDecoder(DecoderConfig config);

  @override
  DecoderDefinition get definition => const DecoderDefinition(
    id: 'unsorted',
    displayName: 'Unsorted',
    description: 'Emits out-of-order transactions',
    requiredSignals: [
      SignalBinding(name: 'sig', description: 'test signal'),
    ],
  );

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) => const [
    DecodedTransaction(startTime: 500, endTime: 560, label: 'C'),
    DecodedTransaction(startTime: 100, endTime: 900, label: 'A'),
    DecodedTransaction(startTime: 700, endTime: 760, label: 'D'),
    DecodedTransaction(startTime: 300, endTime: 360, label: 'B'),
  ];
}

// ── stub decoder ──────────────────────────────────────────────────────────────

class _StubDecoder implements ProtocolDecoder {
  const _StubDecoder(DecoderConfig config) : _config = config;

  // Stored to satisfy the ProtocolDecoder factory signature; not used in stub.
  // ignore: unused_field
  final DecoderConfig _config;

  @override
  DecoderDefinition get definition => const DecoderDefinition(
    id: 'stub',
    displayName: 'Stub',
    description: 'Test stub',
    requiredSignals: [
      SignalBinding(name: 'sig', description: 'test signal'),
    ],
  );

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) => const [
    DecodedTransaction(
      startTime: 0,
      endTime: 100,
      label: 'Stub TX',
    ),
  ];
}
