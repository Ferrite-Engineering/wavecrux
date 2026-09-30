// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/features/signal_tree/providers/parameter_value_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

class _MockSource extends Mock implements WaveformDataSource {}

// WaveformSourceNotifier.build() is synchronous — returns AsyncValue directly.
class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

ProviderContainer _container({WaveformDataSource? source}) => ProviderContainer(
  overrides: [
    waveformSourceProvider.overrideWith(() => _FakeSourceNotifier(source)),
  ],
);

void main() {
  group('parameterValueProvider', () {
    test('returns null when no waveform source is loaded', () async {
      final container = _container();
      addTearDown(container.dispose);

      final value = await container.read(
        parameterValueProvider('ref', 8).future,
      );
      expect(value, isNull);
    });

    test(
      'loads the signal, reads value at startTime, formats decimal',
      () async {
        final source = _MockSource();
        when(() => source.loadSignal('p')).thenAnswer((_) async {});
        when(() => source.startTime).thenReturn(0);
        when(() => source.valueAt('p', 0)).thenReturn('b100000');

        final container = _container(source: source);
        addTearDown(container.dispose);

        final value = await container.read(
          parameterValueProvider('p', 8).future,
        );
        expect(value, '32');
        verify(() => source.loadSignal('p')).called(1);
      },
    );

    test('queries at the source startTime, not hardcoded zero', () async {
      final source = _MockSource();
      when(() => source.loadSignal('p')).thenAnswer((_) async {});
      when(() => source.startTime).thenReturn(500);
      when(() => source.valueAt('p', 500)).thenReturn('b101');

      final container = _container(source: source);
      addTearDown(container.dispose);

      final value = await container.read(parameterValueProvider('p', 3).future);
      expect(value, '5');
    });

    test('returns null when the signal has no value at startTime', () async {
      final source = _MockSource();
      when(() => source.loadSignal('p')).thenAnswer((_) async {});
      when(() => source.startTime).thenReturn(0);
      when(() => source.valueAt('p', 0)).thenReturn(null);

      final container = _container(source: source);
      addTearDown(container.dispose);

      final value = await container.read(parameterValueProvider('p', 8).future);
      expect(value, isNull);
    });

    test(
      'real-valued parameters pass through unchanged (bitWidth 0)',
      () async {
        final source = _MockSource();
        when(() => source.loadSignal('rp')).thenAnswer((_) async {});
        when(() => source.startTime).thenReturn(0);
        when(() => source.valueAt('rp', 0)).thenReturn('3.14');

        final container = _container(source: source);
        addTearDown(container.dispose);

        final value = await container.read(
          parameterValueProvider('rp', 0).future,
        );
        expect(value, '3.14');
      },
    );
  });
}
