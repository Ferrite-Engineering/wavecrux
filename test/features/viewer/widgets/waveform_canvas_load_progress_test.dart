// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: progress-state timing test (when the canvas publishes
// its loading batch); no localized text is asserted.

// When the canvas's loading batch shows the progress indicator.
//
// Signal count alone used to decide, so a handful of signals with millions of
// transitions each decompressed for seconds with nothing on screen. A batch
// under the count threshold now shows the indicator once it has run past a
// short delay, a fast one never shows it, and a batch that follows "Add All in
// Scope" takes over that flow's indicator at once rather than leaving a gap.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_load_progress_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '../../../helpers/fake_waveform_data_source.dart';

const _refs = ['a', 'b', 'c'];

extension on SignalLoadProgress {
  /// An "Add All in Scope" adding phase of [total] with [loaded] built.
  void hold(int total, {required int loaded}) {
    begin(total, phase: SignalLoadPhase.adding);
    setLoaded(loaded);
  }
}

/// A source whose signals start unloaded and take [loadTime] each to load, the
/// way a dense signal decompresses on the worker isolate.
class _SlowSource extends FakeWaveformDataSource {
  _SlowSource(this.loadTime)
    : super(
        signals: {
          for (final r in _refs)
            r: const [
              SignalChange(time: 0, value: '0'),
              SignalChange(time: 500, value: '1'),
            ],
        },
      );

  final Duration loadTime;
  final Set<String> _ready = {};

  @override
  bool isSignalLoaded(String signalRef) => _ready.contains(signalRef);

  @override
  Future<void> loadSignal(String signalRef) async {
    if (loadTime > Duration.zero) await Future<void>.delayed(loadTime);
    _ready.add(signalRef);
  }
}

class _LoadedSourceNotifier extends WaveformSourceNotifier {
  _LoadedSourceNotifier(this._source);
  final WaveformDataSource _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

class _ThreeSignals extends SignalGroupsNotifier {
  @override
  SignalGroup build() => SignalGroup(
    entries: [
      for (final r in _refs) SignalEntry.signal(signalRef: r, displayName: r),
    ],
  );
}

/// Mounts the canvas over [source] and records every active progress state it
/// publishes. [before] runs against the container before the first frame.
Future<(ProviderContainer, List<SignalLoadProgressState>)> _mount(
  WidgetTester tester,
  _SlowSource source, {
  void Function(ProviderContainer)? before,
}) async {
  final container = ProviderContainer(
    overrides: [
      waveformSourceProvider.overrideWith(() => _LoadedSourceNotifier(source)),
      signalGroupsProvider.overrideWith(_ThreeSignals.new),
    ],
  );
  addTearDown(container.dispose);
  final seen = <SignalLoadProgressState>[];
  container.listen(signalLoadProgressProvider, (_, next) {
    if (next.active) seen.add(next);
  }, fireImmediately: true);
  before?.call(container);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: SizedBox(width: 800, height: 400, child: WaveformCanvas()),
        ),
      ),
    ),
  );
  return (container, seen);
}

void main() {
  testWidgets('a slow batch below the count threshold shows the indicator '
      'once it passes the delay', (tester) async {
    final (container, seen) = await _mount(
      tester,
      _SlowSource(const Duration(seconds: 2)),
    );

    // The refresh starts after the first frame. Inside the delay: nothing.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(signalLoadProgressProvider).active, isFalse);

    // Past it, with the loads still running: the loading indicator is up for
    // the whole batch.
    await tester.pump(const Duration(milliseconds: 300));
    final shown = container.read(signalLoadProgressProvider);
    expect(shown.active, isTrue);
    expect(shown.phase, SignalLoadPhase.loading);
    expect(shown.total, _refs.length);

    // The loads finish; the indicator goes away.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(container.read(signalLoadProgressProvider).active, isFalse);
    expect(seen, isNotEmpty);
  });

  testWidgets('a fast batch never shows the indicator', (tester) async {
    final (container, seen) = await _mount(tester, _SlowSource(Duration.zero));

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(seen, isEmpty, reason: 'a fast load must not flash the indicator');
    expect(container.read(signalLoadProgressProvider).active, isFalse);
  });

  testWidgets('a batch that follows Add All in Scope takes over its indicator '
      'at once', (tester) async {
    final (container, seen) = await _mount(
      tester,
      _SlowSource(const Duration(seconds: 2)),
      // "Add All in Scope" holding after building every entry.
      before: (c) => c
          .read(signalLoadProgressProvider.notifier)
          .hold(_refs.length, loaded: _refs.length),
    );

    // The refresh runs after the first frame; well inside the delay.
    await tester.pump();
    final state = container.read(signalLoadProgressProvider);
    expect(state.active, isTrue);
    expect(state.phase, SignalLoadPhase.loading);

    // The add flow's own release is phase-scoped and leaves it alone.
    container
        .read(signalLoadProgressProvider.notifier)
        .finishPhase(SignalLoadPhase.adding);
    expect(container.read(signalLoadProgressProvider).active, isTrue);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(container.read(signalLoadProgressProvider).active, isFalse);
    expect(seen.map((s) => s.phase), contains(SignalLoadPhase.loading));
  });

  testWidgets('an add still building its entries keeps the indicator past '
      'the delay', (tester) async {
    final (container, _) = await _mount(
      tester,
      _SlowSource(const Duration(seconds: 2)),
      // A chunked add part-way through building: not a hold.
      before: (c) =>
          c.read(signalLoadProgressProvider.notifier).hold(10000, loaded: 4000),
    );

    await tester.pump(const Duration(milliseconds: 300));
    final state = container.read(signalLoadProgressProvider);
    expect(state.phase, SignalLoadPhase.adding);
    expect(state.loaded, 4000);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
  });
}
