// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: data-refresh counting regression test (how often a
// pan reads signal data); no localized text is asserted.

// A horizontal pan must not re-read signal data on every frame.
//
// The canvas used to refresh its change caches on every visible-range change,
// so each pan or zoom frame re-read every loaded lane's changes in the visible
// range. The caches now cover a band either side of the view: a pan inside it
// repaints from the caches, and only leaving it (or zooming) refreshes,
// through the same throttle + trailing debounce the vertical scroll uses.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '../../../helpers/fake_waveform_data_source.dart';

/// Counts the range reads the canvas makes.
class _CountingSource extends FakeWaveformDataSource {
  _CountingSource()
    : super(
        endTime: 100000,
        signals: {
          'clk': [
            for (var t = 0; t < 100000; t += 50)
              SignalChange(time: t, value: t % 100 == 0 ? '1' : '0'),
          ],
        },
      );

  int rangeReads = 0;

  @override
  List<SignalChange> changesInRange(String signalRef, int start, int end) {
    rangeReads++;
    return super.changesInRange(signalRef, start, end);
  }
}

class _LoadedSourceNotifier extends WaveformSourceNotifier {
  _LoadedSourceNotifier(this._source);
  final WaveformDataSource _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

class _ClkGroupsNotifier extends SignalGroupsNotifier {
  @override
  SignalGroup build() => SignalGroup(
    entries: [SignalEntry.signal(signalRef: 'clk', displayName: 'clk')],
  );
}

Future<(ProviderContainer, _CountingSource)> _mount(WidgetTester tester) async {
  final source = _CountingSource();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        waveformSourceProvider.overrideWith(
          () => _LoadedSourceNotifier(source),
        ),
        signalGroupsProvider.overrideWith(_ClkGroupsNotifier.new),
      ],
      child: const MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SizedBox(width: 800, height: 400, child: WaveformCanvas()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final container = ProviderScope.containerOf(
    tester.element(find.byType(WaveformCanvas)),
  );
  // Zoom in so there is room to pan, and let the refresh it causes land.
  container.read(timeMapperProvider.notifier).zoomToRange(40000, 50000);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  return (container, source);
}

void main() {
  testWidgets('a pan inside the cached band reads no signal data', (
    tester,
  ) async {
    final (container, source) = await _mount(tester);
    final before = source.rangeReads;
    expect(before, greaterThan(0), reason: 'the initial refresh read data');

    // 30 frames of a slow drag, 60 px in all: inside the half-view (400 px)
    // band either side of an 800 px view.
    for (var frame = 0; frame < 30; frame++) {
      container.read(timeMapperProvider.notifier).pan(2);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      source.rangeReads - before,
      0,
      reason:
          '${source.rangeReads - before} range reads for 30 pan frames; '
          'a pan inside the band repaints from the caches',
    );
  });

  testWidgets('a pan out of the band refreshes, throttled', (tester) async {
    final (container, source) = await _mount(tester);
    final before = source.rangeReads;

    // 30 frames of a fast fling: 60 px a frame, 1800 px in all — well past
    // the half-view band either side.
    for (var frame = 0; frame < 30; frame++) {
      container.read(timeMapperProvider.notifier).pan(60);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final reads = source.rangeReads - before;
    expect(reads, greaterThan(0), reason: 'the band has to follow the view');
    // At most one refresh per 150 ms of wall time while the fling lasts,
    // plus the trailing one — against one per frame before.
    expect(reads, lessThanOrEqualTo(6), reason: '$reads reads for 30 frames');
  });

  testWidgets('a zoom refreshes the caches at the new resolution', (
    tester,
  ) async {
    final (container, source) = await _mount(tester);
    final before = source.rangeReads;
    container
        .read(timeMapperProvider.notifier)
        .zoomIn(focalPixel: 400, factor: 4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(source.rangeReads - before, greaterThan(0));
  });
}
