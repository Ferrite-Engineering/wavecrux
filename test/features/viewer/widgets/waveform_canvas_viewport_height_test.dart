// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: pure layout/geometry regression test (canvas viewport
// height republishing on constraint change). No text is asserted; the test
// is render-object/geometry, not locale-sensitive.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

class _MockSource extends Mock implements WaveformDataSource {}

class _LoadedSourceNotifier extends WaveformSourceNotifier {
  _LoadedSourceNotifier(this._source);
  final WaveformDataSource _source;
  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

class _PreloadedGroupsNotifier extends SignalGroupsNotifier {
  @override
  SignalGroup build() => SignalGroup(
    entries: [SignalEntry.signal(signalRef: 'clk', displayName: 'clk')],
  );
}

void main() {
  // Regression: the value column (a full-height right pane) sizes its scroll
  // body to canvasViewportHeightProvider. That height was only republished when
  // WaveformViewCenter rebuilt; a bottom-panel toggle / splitter drag changes
  // the canvas height via constraints WITHOUT rebuilding it, so the published
  // height went stale and the value column painted an uncolored gap over its
  // lower values. The canvas now republishes from its own LayoutBuilder, which
  // does rebuild on the constraint change.
  testWidgets(
    'canvas republishes canvasViewportHeight when its viewport height changes',
    (tester) async {
      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(10000);
      when(() => source.timescale).thenReturn(null);
      when(() => source.rootScopes).thenReturn([]);
      when(() => source.isSignalLoaded(any())).thenReturn(true);
      when(() => source.changesInRange(any(), any(), any())).thenReturn([]);
      when(() => source.valueAt(any(), any())).thenReturn(null);

      final height = ValueNotifier<double>(600);
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            waveformSourceProvider.overrideWith(
              () => _LoadedSourceNotifier(source),
            ),
            signalGroupsProvider.overrideWith(_PreloadedGroupsNotifier.new),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return Scaffold(
                  body: ValueListenableBuilder<double>(
                    valueListenable: height,
                    builder: (context, h, _) => Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: 800,
                        height: h,
                        child: const WaveformCanvas(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump(); // flush the post-frame republish
      await tester.pump();

      final tall = container.read(canvasViewportHeightProvider);
      expect(tall, greaterThan(0), reason: 'height published on first layout');
      expect(tall, closeTo(600, 1));

      // Shrink the pane (as closing→opening the bottom panel would) and verify
      // the published height follows instead of going stale.
      height.value = 400;
      await tester.pump();
      await tester.pump();

      final short = container.read(canvasViewportHeightProvider);
      expect(short, closeTo(400, 1));
      expect(short, lessThan(tall));
    },
  );
}
