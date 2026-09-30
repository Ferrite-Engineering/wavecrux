// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

class _MockSource extends Mock implements WaveformDataSource {}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

ProviderContainer _container({WaveformDataSource? source}) {
  final c = ProviderContainer(
    overrides: [
      if (source != null)
        waveformSourceProvider.overrideWith(() => _FakeSourceNotifier(source)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('stageBoundSignalProvider — empty cases', () {
    test('null signalRef returns unbound', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final snapshot = container.read(stageBoundSignalProvider(null));
      expect(snapshot.kind, StageSignalSnapshotKind.unbound);
    });

    test('binding with empty signalRef returns unbound', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final snapshot = container.read(
        stageBoundSignalProvider(const StageSignalBinding(signalRef: '')),
      );
      expect(snapshot.kind, StageSignalSnapshotKind.unbound);
    });

    test('binding with non-empty ref but no source returns noFile', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final snapshot = container.read(
        stageBoundSignalProvider(
          const StageSignalBinding(signalRef: 'top.x'),
        ),
      );
      expect(snapshot.kind, StageSignalSnapshotKind.noFile);
    });
  });

  group('StageLoadedSignals notifier', () {
    test('starts empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(stageLoadedSignalsProvider), isEmpty);
    });

    test('reset clears state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Force build, then reset.
      container
        ..read(stageLoadedSignalsProvider)
        ..read(stageLoadedSignalsProvider.notifier).reset();
      expect(container.read(stageLoadedSignalsProvider), isEmpty);
    });

    test('ensureLoaded with no source is no-op', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(stageLoadedSignalsProvider.notifier)
          .ensureLoaded('top.clk');
      // Source is null so the signal cannot be marked loaded.
      expect(container.read(stageLoadedSignalsProvider), isEmpty);
    });

    test('ensureLoaded with empty ref is no-op', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(stageLoadedSignalsProvider.notifier)
          .ensureLoaded('');
      expect(container.read(stageLoadedSignalsProvider), isEmpty);
    });
  });

  group('StageLoadedSignals — failed load is contained, not thrown', () {
    test('ensureLoaded catches a loadSignal failure, settles the ref, records '
        'the error — never rethrows', () async {
      final source = _MockSource();
      when(() => source.isSignalLoaded('bad.ref')).thenReturn(false);
      when(
        () => source.loadSignal('bad.ref'),
      ).thenThrow(ArgumentError('Invalid signalRef: "bad.ref"'));
      final container = _container(source: source);
      final notifier = container.read(stageLoadedSignalsProvider.notifier);

      // The regression guard: this must complete normally, NOT rethrow the
      // ArgumentError as an uncaught async error.
      await expectLater(notifier.ensureLoaded('bad.ref'), completes);

      // The ref is settled (so the load isn't re-kicked every frame) and its
      // error is recorded for the snapshot.
      expect(container.read(stageLoadedSignalsProvider), contains('bad.ref'));
      expect(notifier.errorFor('bad.ref'), contains('Invalid signalRef'));
    });

    test('a binding whose load failed resolves to an error snapshot', () async {
      final source = _MockSource();
      when(() => source.isSignalLoaded('bad.ref')).thenReturn(false);
      when(
        () => source.loadSignal('bad.ref'),
      ).thenThrow(ArgumentError('Invalid signalRef: "bad.ref"'));
      final container = _container(source: source);

      const binding = StageSignalBinding(signalRef: 'bad.ref');

      // An unsettled binding reports loading.
      expect(
        container.read(stageBoundSignalProvider(binding)).kind,
        StageSignalSnapshotKind.loading,
      );

      // Settle the failed load. (Reading the provider above already kicked off
      // the same load; awaiting here both lets that future settle and is
      // idempotent — ensureLoaded early-returns once the ref is settled.)
      await container
          .read(stageLoadedSignalsProvider.notifier)
          .ensureLoaded('bad.ref');
      // Drain any deferred load future kicked by the first provider read so it
      // can't fire into the disposed container after the test ends.
      await pumpEventQueue();

      final snapshot = container.read(stageBoundSignalProvider(binding));
      expect(snapshot.kind, StageSignalSnapshotKind.error);
      expect(snapshot.isError, isTrue);
      expect(snapshot.errorMessage, contains('Invalid signalRef'));
    });

    test('reset clears recorded errors', () async {
      final source = _MockSource();
      when(() => source.isSignalLoaded('bad.ref')).thenReturn(false);
      when(() => source.loadSignal('bad.ref')).thenThrow(ArgumentError('boom'));
      final container = _container(source: source);
      final notifier = container.read(stageLoadedSignalsProvider.notifier);

      await notifier.ensureLoaded('bad.ref');
      expect(notifier.errorFor('bad.ref'), isNotNull);

      notifier.reset();
      expect(container.read(stageLoadedSignalsProvider), isEmpty);
      expect(notifier.errorFor('bad.ref'), isNull);
    });
  });

  group('sliceBitsForTesting — single-bit', () {
    test('returns the single bit at the requested LSB index', () {
      // Raw value 8'b10110010, bit 0 = LSB = 0, bit 7 = MSB = 1.
      const raw = '10110010';
      expect(
        sliceBitsForTesting(raw, bitWidth: 8, bitIndex: 0, sliceWidth: 1),
        '0',
      );
      expect(
        sliceBitsForTesting(raw, bitWidth: 8, bitIndex: 1, sliceWidth: 1),
        '1',
      );
      expect(
        sliceBitsForTesting(raw, bitWidth: 8, bitIndex: 7, sliceWidth: 1),
        '1',
      );
    });

    test('handles b-prefixed VCD raw values', () {
      expect(
        sliceBitsForTesting('b1010', bitWidth: 4, bitIndex: 0, sliceWidth: 1),
        '0',
      );
      expect(
        sliceBitsForTesting('b1010', bitWidth: 4, bitIndex: 3, sliceWidth: 1),
        '1',
      );
    });

    test('out-of-range bit indices return x', () {
      expect(
        sliceBitsForTesting('1010', bitWidth: 4, bitIndex: 4, sliceWidth: 1),
        'x',
      );
      expect(
        sliceBitsForTesting('1010', bitWidth: 4, bitIndex: -1, sliceWidth: 1),
        'x',
      );
    });

    test('left-pads short raw values with leading 0 (or x/z if leading)', () {
      // 4-bit signal, raw is just '1' — should pad to '0001'.
      expect(
        sliceBitsForTesting('1', bitWidth: 4, bitIndex: 0, sliceWidth: 1),
        '1',
      );
      expect(
        sliceBitsForTesting('1', bitWidth: 4, bitIndex: 3, sliceWidth: 1),
        '0',
      );
      // x-leading short raw extends with 'x'.
      expect(
        sliceBitsForTesting('x', bitWidth: 4, bitIndex: 3, sliceWidth: 1),
        'x',
      );
    });
  });

  group('sliceBitsForTesting — multi-bit slice', () {
    test('extracts a contiguous range, MSB-first', () {
      // 12-bit raw: bits[11:0] = 0xABC = 1010_1011_1100
      const raw = '101010111100';
      // Slice bits[11:0] = the whole thing
      expect(
        sliceBitsForTesting(raw, bitWidth: 12, bitIndex: 0, sliceWidth: 12),
        '101010111100',
      );
      // Slice bits[3:0] = lower nibble = 1100
      expect(
        sliceBitsForTesting(raw, bitWidth: 12, bitIndex: 0, sliceWidth: 4),
        '1100',
      );
      // Slice bits[7:4] = middle nibble = 1011
      expect(
        sliceBitsForTesting(raw, bitWidth: 12, bitIndex: 4, sliceWidth: 4),
        '1011',
      );
      // Slice bits[11:8] = upper nibble = 1010
      expect(
        sliceBitsForTesting(raw, bitWidth: 12, bitIndex: 8, sliceWidth: 4),
        '1010',
      );
    });

    test('DE10-Nano 96-bit ADC bus across 8 channels (12 bits each)', () {
      // Build a 96-bit raw bit string: channel i has bit pattern
      // representing decimal i in its 12-bit slice.
      // adc_ch[11:0]   = ch0 = 0
      // adc_ch[23:12]  = ch1 = 1
      // ...
      // adc_ch[95:84]  = ch7 = 7
      final buffer = StringBuffer();
      for (var i = 7; i >= 0; i--) {
        buffer.write(i.toRadixString(2).padLeft(12, '0'));
      }
      final raw = buffer.toString(); // 96 chars
      expect(raw.length, 96);

      // Each ADC channel slot binds bits [(i+1)*12-1 : i*12].
      for (var i = 0; i < 8; i++) {
        final slice = sliceBitsForTesting(
          raw,
          bitWidth: 96,
          bitIndex: i * 12,
          sliceWidth: 12,
        );
        expect(
          slice,
          i.toRadixString(2).padLeft(12, '0'),
          reason: 'ADC channel $i should hold the value $i in its 12-bit slice',
        );
      }
    });

    test('slice extending past the MSB renders missing bits as x', () {
      // Slice bits[7:4] of an 8-bit signal at bitIndex 4, sliceWidth 8 →
      // would extend to bits[11:4], but signal is only 8 bits wide. The
      // bits past the MSB (bits[11:8]) render as 'x'.
      expect(
        sliceBitsForTesting(
          '11110000',
          bitWidth: 8,
          bitIndex: 4,
          sliceWidth: 8,
        ),
        'xxxx1111',
      );
    });

    test('slice with bitIndex past MSB returns all x', () {
      expect(
        sliceBitsForTesting('1010', bitWidth: 4, bitIndex: 4, sliceWidth: 4),
        'xxxx',
      );
    });

    test('preserves x and z bits within a slice', () {
      // 8-bit signal: 1x0z1100 (bit 7 = 1, bit 6 = x, bit 5 = 0, bit 4 = z).
      const raw = '1x0z1100';
      // Slice bits[7:4] = 1x0z
      expect(
        sliceBitsForTesting(raw, bitWidth: 8, bitIndex: 4, sliceWidth: 4),
        '1x0z',
      );
    });
  });
}
