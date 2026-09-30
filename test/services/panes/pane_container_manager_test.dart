// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/pane_id.dart';
import 'package:wavecrux/domain/models/render_pipeline_stats.dart';
import 'package:wavecrux/features/diagnostics/providers/render_pipeline_stats_provider.dart';
import 'package:wavecrux/features/panes/providers/pane_id_provider.dart';
import 'package:wavecrux/features/panes/providers/pane_render_stats_provider.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';

void main() {
  group('PaneContainerManager', () {
    late ProviderContainer root;
    late PaneContainerManager pcm;

    setUp(() {
      pcm = PaneContainerManager();
      root = ProviderContainer(
        overrides: [paneContainerManagerProvider.overrideWithValue(pcm)],
      );
      pcm.init(root);
    });

    tearDown(() {
      pcm.dispose();
      root.dispose();
    });

    test('containerFor returns the same container on repeat calls', () {
      final id = PaneId.generate();
      final first = pcm.containerFor(id);
      final second = pcm.containerFor(id);
      expect(identical(first, second), isTrue);
    });

    test('containerFor returns distinct containers per PaneId', () {
      final a = pcm.containerFor(PaneId.generate());
      final b = pcm.containerFor(PaneId.generate());
      expect(identical(a, b), isFalse);
    });

    test('paneIdProvider resolves to the overriding pane id', () {
      final id = PaneId.generate();
      final container = pcm.containerFor(id);
      expect(container.read(paneIdProvider), equals(id));
    });

    test('paneRenderStatsProvider is per-pane (independent notifiers)', () {
      final a = pcm.containerFor(PaneId.generate());
      final b = pcm.containerFor(PaneId.generate());
      final notifierA = a.read(paneRenderStatsProvider.notifier);
      final notifierB = b.read(paneRenderStatsProvider.notifier);
      expect(identical(notifierA, notifierB), isFalse);
    });

    test(
      'panelLayoutProvider is NOT isolated per-pane — panel visibility is '
      'per-tab, overridden in wavecruxTabOverrides, not in the pane container',
      () {
        // The pane container deliberately does NOT override
        // panelLayoutProvider: panel visibility moved from per-pane to
        // per-tab. Two pane containers therefore resolve panelLayoutProvider
        // to the SAME (root) instance — proof the per-pane override is gone.
        // Per-tab isolation is covered by the per-tab override list
        // (wavecrux_tab_overrides) and tab_container_manager tests.
        final paneA = pcm.containerFor(PaneId.generate());
        final paneB = pcm.containerFor(PaneId.generate());
        expect(
          identical(
            paneA.read(panelLayoutProvider.notifier),
            paneB.read(panelLayoutProvider.notifier),
          ),
          isTrue,
          reason:
              'pane containers must not shadow panelLayoutProvider; it is '
              'per-tab now',
        );
      },
    );

    test(
      'Issue 6 / Issue 7: renderStatsCollectorProvider is per-pane — '
      'painting in pane A publishes only to pane A pane notifier',
      () async {
        final paneA = pcm.containerFor(PaneId.generate());
        final paneB = pcm.containerFor(PaneId.generate());

        final collectorA = paneA.read(renderStatsCollectorProvider);
        final collectorB = paneB.read(renderStatsCollectorProvider);
        // Distinct collector instances per pane.
        expect(identical(collectorA, collectorB), isFalse);

        // Simulate paint in pane A: record a viewport and end a frame.
        collectorA
          ..beginFrame()
          ..recordScalarPaint(500, 10)
          ..endFrame();
        // The collector→notifier bridge is intentionally deferred via
        // Future.microtask so it doesn't mutate Riverpod state during the
        // paint pass (Flutter's `_debugCanModifyProviders` assertion). Yield
        // a microtask here so the test sees the post-bridge state.
        await Future<void>.delayed(Duration.zero);

        // Pane A's render-stats notifier has the snapshot in its history.
        final statsA = paneA.read(paneRenderStatsProvider);
        expect(statsA.latest, isA<RenderPipelineStats>());
        expect(statsA.latest!.totalPaintTimeUs, equals(500));
        // Sparkline buffer has exactly one sample.
        expect(statsA.paintTimesMs.length, equals(1));

        // Pane B's notifier is untouched.
        final statsB = paneB.read(paneRenderStatsProvider);
        expect(statsB.latest, isNull);
        expect(statsB.paintTimesMs, isEmpty);
      },
    );

    test('disposePane removes and disposes the container', () {
      final id = PaneId.generate();
      final container = pcm.containerFor(id);
      // Sanity: read a provider so the container is alive.
      expect(container.read(paneIdProvider), equals(id));
      pcm.disposePane(id);
      // Subsequent containerFor returns a fresh instance, not the disposed one.
      final replacement = pcm.containerFor(id);
      expect(identical(replacement, container), isFalse);
    });

    test('dispose tears down every cached container', () {
      pcm
        ..containerFor(PaneId.generate())
        ..containerFor(PaneId.generate())
        ..containerFor(PaneId.generate())
        // Should not throw — the test's tearDown will dispose again, which
        // is tolerated because dispose clears the cache.
        ..dispose();
    });
  });

  group('paneContainerManagerProvider', () {
    test('throws when read without an override', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Riverpod 3 wraps provider build errors in `ProviderException`; the
      // original `UnimplementedError` lives on `.exception`. Walk through the
      // wrapper by capturing the thrown object and asserting on its cause.
      Object? captured;
      try {
        container.read(paneContainerManagerProvider);
      } on Object catch (e) {
        captured = e;
      }
      expect(captured, isNotNull);
      final cause = captured is ProviderException
          ? captured.exception
          : captured;
      expect(cause, isA<UnimplementedError>());
    });
  });
}
