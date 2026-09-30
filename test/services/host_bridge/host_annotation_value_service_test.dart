// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The app half of the RTL annotation inversion.
//
// What is worth pinning here is not "does it format a number" — the value
// column's tests already own that — but the three behaviours that make the
// query *standing*: it answers now, it answers again when the cursor moves,
// and it stops when cancelled. A regression in any of those is invisible in
// the extension (the decorations simply stop following the cursor, which looks
// like the waveform not having moved) and is exactly what this file exists to
// make loud.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/host_bridge/host_annotation_value_service.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_messages.dart';

import '../../support/fake_waveform_source.dart';

/// Preloads [waveformSourceProvider] with the in-memory reference trace.
class _PreloadedSourceNotifier extends WaveformSourceNotifier {
  _PreloadedSourceNotifier(this._source);
  final WaveformDataSource? _source;
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

final _refProvider = Provider<Ref>((ref) => ref);

Ref _refFor(ProviderContainer container) => container.read(_refProvider);

ProviderContainer _containerWith(WaveformDataSource? source) {
  final container = ProviderContainer(
    overrides: [
      waveformSourceProvider.overrideWith(
        () => _PreloadedSourceNotifier(source),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('HostAnnotationValueService', () {
    late List<HostBridgeValueResponse> posted;

    HostAnnotationValueService serviceFor(ProviderContainer container) {
      final service = HostAnnotationValueService(
        ref: _refFor(container),
        post: posted.add,
        cursorDebounce: Duration.zero,
      );
      addTearDown(service.dispose);
      return service;
    }

    setUp(() => posted = <HostBridgeValueResponse>[]);

    test('answers a query with values for the paths it knows', () async {
      final container = _containerWith(FakeWaveformSource.reference());
      final service = serviceFor(container);

      await service.accept(
        const HostBridgeValueQuery(
          queryId: 'q1',
          paths: ['top.clk', 'top.data'],
        ),
      );

      expect(posted, hasLength(1));
      expect(posted.single.queryId, 'q1');
      // 1-bit signals default to binary, so this one is exact rather than
      // radix-dependent: the point is that the value came from the app's own
      // translator stack and not from a second formatter in the host.
      expect(posted.single.values['top.clk'], '0');
      expect(posted.single.values['top.data'], isNotNull);
      // Formatted with the file's timescale, so a hover can never read an
      // annotation as "now".
      expect(posted.single.cursorLabel, isNotNull);
    });

    test('omits a path the design does not contain rather than failing the '
        'whole viewport', () async {
      final container = _containerWith(FakeWaveformSource.reference());
      final service = serviceFor(container);

      await service.accept(
        const HostBridgeValueQuery(
          queryId: 'q1',
          paths: ['top.nonexistent', 'top.clk'],
        ),
      );

      expect(posted.single.values.containsKey('top.nonexistent'), isFalse);
      expect(posted.single.values['top.clk'], '0');
    });

    test('loads a signal the user never added to the viewer', () async {
      final source = FakeWaveformSource.reference();
      final container = _containerWith(source);
      final service = serviceFor(container);

      expect(source.isSignalLoaded('s_data'), isFalse);
      await service.accept(
        const HostBridgeValueQuery(queryId: 'q1', paths: ['top.data']),
      );

      expect(source.isSignalLoaded('s_data'), isTrue);
      expect(posted.single.values['top.data'], isNotNull);
    });

    test(
      'answers again when the cursor moves, without a second query',
      () async {
        final container = _containerWith(FakeWaveformSource.reference());
        final service = serviceFor(container);
        await service.accept(
          const HostBridgeValueQuery(queryId: 'q1', paths: ['top.clk']),
        );
        expect(posted, hasLength(1));
        expect(posted.single.values['top.clk'], '0');

        container.read(cursorStateProvider.notifier).placePrimary(15);
        await _settle();

        expect(posted.length, greaterThan(1));
        expect(posted.last.queryId, 'q1');
        // `top.clk` rises at tick 10, so a cursor at 15 must read 1. Same query,
        // new answer — the property the whole standing-query design exists for.
        expect(posted.last.values['top.clk'], '1');
      },
    );

    test('an empty query cancels the standing one', () async {
      final container = _containerWith(FakeWaveformSource.reference());
      final service = serviceFor(container);
      await service.accept(
        const HostBridgeValueQuery(queryId: 'q1', paths: ['top.clk']),
      );
      expect(service.isActive, isTrue);

      await service.accept(
        const HostBridgeValueQuery(queryId: 'q2', paths: []),
      );
      // Answered once so a host waiting on a response never hangs...
      expect(posted.last.queryId, 'q2');
      expect(posted.last.values, isEmpty);
      expect(service.isActive, isFalse);

      // ...and then silent, however much the cursor moves.
      final before = posted.length;
      container.read(cursorStateProvider.notifier).placePrimary(15);
      await _settle();
      expect(posted, hasLength(before));
    });

    test('stops answering after dispose', () async {
      final container = _containerWith(FakeWaveformSource.reference());
      final service = HostAnnotationValueService(
        ref: _refFor(container),
        post: posted.add,
        cursorDebounce: Duration.zero,
      );
      await service.accept(
        const HostBridgeValueQuery(queryId: 'q1', paths: ['top.clk']),
      );
      final before = posted.length;

      service.dispose();
      container.read(cursorStateProvider.notifier).placePrimary(15);
      await _settle();

      expect(posted, hasLength(before));
    });

    test('answers with nothing when no waveform is open', () async {
      final container = _containerWith(null);
      final service = serviceFor(container);

      await service.accept(
        const HostBridgeValueQuery(queryId: 'q1', paths: ['top.clk']),
      );

      expect(posted.single.values, isEmpty);
      expect(posted.single.cursorLabel, isNull);
    });
  });
}

/// Lets the zero-duration debounce timer and the async answer complete.
Future<void> _settle() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
