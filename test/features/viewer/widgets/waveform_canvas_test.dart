// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/translator_expansion_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_canvas_render_object.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_lane_data.dart';
import 'package:wavecrux/features/viewer/widgets/collaborator_cursor_overlay.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_scroll_modifier_interceptor.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';

// ── fakes ─────────────────────────────────────────────────────────────────────

class _MockSource extends Mock implements WaveformDataSource {}

/// Returns an already-loaded source so the canvas mounts with a non-null source.
class _LoadedSourceNotifier extends WaveformSourceNotifier {
  _LoadedSourceNotifier(this._source);
  final WaveformDataSource _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

/// A source stuck in the loading state, as during a long parse.
class _ParsingSourceNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() => const AsyncLoading();
}

/// Pre-populates signal groups with a single 'clk' signal for refresh tests.
class _PreloadedGroupsNotifier extends SignalGroupsNotifier {
  @override
  SignalGroup build() => SignalGroup(
    entries: [
      SignalEntry.signal(signalRef: 'clk', displayName: 'clk'),
    ],
  );
}

/// Two stacked signals with fixed ids so a test can reserve translator
/// child-row space after the first ([_kExpandedId]) and assert the second is
/// not clipped (issue #43).
const _kExpandedId = 'sig-expanded';
const _kBelowId = 'sig-below';

class _TwoSignalGroupsNotifier extends SignalGroupsNotifier {
  @override
  SignalGroup build() => SignalGroup(
    entries: [
      SignalEntry.signal(
        id: _kExpandedId,
        signalRef: 'expanded',
        displayName: 'expanded',
      ),
      SignalEntry.signal(
        id: _kBelowId,
        signalRef: 'below',
        displayName: 'below',
      ),
    ],
  );
}

/// Pre-populates active decoders with a known [ActiveDecoder] list so the
/// canvas renders transaction lanes without requiring [decodeAll] to run.
class _PreloadedDecodersNotifier extends ActiveDecodersNotifier {
  _PreloadedDecodersNotifier(this._decoders);
  final List<ActiveDecoder> _decoders;

  @override
  List<ActiveDecoder> build() => _decoders;
}

// ── helpers ───────────────────────────────────────────────────────────────────

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Widget _wrap(Widget child, {Locale? locale}) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    locale: locale,
    home: Scaffold(body: child),
  ),
);

void main() {
  group('WaveformCanvas', () {
    for (final locale in _locales) {
      testWidgets(
        'locale sweep — no exceptions with no file loaded ($locale)',
        (tester) async {
          await tester.pumpWidget(
            _wrap(const WaveformCanvas(), locale: locale),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('shows no-file placeholder when source is null', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const WaveformCanvas()));
      await tester.pump();
      // waveformSourceProvider starts as AsyncData(null) → no-file state.
      expect(find.text('Open a waveform file to view signals'), findsOneWidget);
    });

    testWidgets('renders inside a constrained box without overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WaveformCanvas(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // ── TimeMapper initialization on mount ────────────────────────────────────
    //
    // When WaveformCanvas mounts with an already-loaded source (the canvas is
    // hidden behind a loading overlay during file load, so ref.listen never
    // fires with the initial loaded value), initState's postFrameCallback must
    // call TimeMapperNotifier.initialize() so the time ruler has a valid range.

    testWidgets(
      'initializes TimeMapper when canvas mounts with already-loaded source',
      (tester) async {
        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.endTime).thenReturn(10000);
        when(() => source.timescale).thenReturn(null);
        when(() => source.rootScopes).thenReturn([]);
        when(() => source.isSignalLoaded(any())).thenReturn(false);
        when(() => source.changesInRange(any(), any(), any())).thenReturn([]);

        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              waveformSourceProvider.overrideWith(
                () => _LoadedSourceNotifier(source),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const Scaffold(
                    body: SizedBox(
                      width: 800,
                      height: 600,
                      child: WaveformCanvas(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        // One extra pump to flush the postFrameCallback.
        await tester.pump();

        final mapper = container.read(timeMapperProvider);
        expect(
          mapper.isEmpty,
          isFalse,
          reason: 'TimeMapper should be initialized from the loaded source',
        );
        expect(mapper.startTime, equals(0));
        expect(mapper.endTime, equals(10000));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('mounts the collaborator cursor overlay over a loaded canvas', (
      tester,
    ) async {
      // A transaction lane gives the canvas a non-empty lane list so it
      // renders the overlay Stack rather than the empty-state placeholder.
      const tx = DecodedTransaction(
        startTime: 2000,
        endTime: 4000,
        label: 'SPI: 0xAB',
        fields: {'data': '0xAB'},
      );
      const activeDecoder = ActiveDecoder(
        id: 'decoder_0',
        decoderId: 'spi',
        config: DecoderConfig(signalBindings: {}),
        instanceNumber: 1,
        transactions: [tx],
      );

      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(10000);
      when(() => source.timescale).thenReturn(null);
      when(() => source.rootScopes).thenReturn([]);
      when(() => source.isSignalLoaded(any())).thenReturn(false);
      when(() => source.changesInRange(any(), any(), any())).thenReturn([]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            waveformSourceProvider.overrideWith(
              () => _LoadedSourceNotifier(source),
            ),
            activeDecodersProvider.overrideWith(
              () => _PreloadedDecodersNotifier([activeDecoder]),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: WaveformCanvas(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The overlay is always mounted; it renders nothing until a session is
      // active (open-core noop service produces no session state).
      expect(find.byType(CollaboratorCursorOverlay), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('light theme — no exceptions', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.light(),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: const Scaffold(body: WaveformCanvas()),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // ── transaction tap snaps cursor to startTime ─────────────────────────────
    //
    // When the user taps a decoded-transaction block in the overlay lane, the
    // primary cursor must snap to the transaction's startTime rather than the
    // raw tap time.  This verifies the full _onPrimaryTap → placePrimary path.

    testWidgets('tap on transaction block snaps cursor to transaction startTime', (
      tester,
    ) async {
      const txStartTime = 2000;
      const txEndTime = 4000;
      const tx = DecodedTransaction(
        startTime: txStartTime,
        endTime: txEndTime,
        label: 'SPI: 0xAB',
        fields: {'data': '0xAB'},
      );
      const activeDecoder = ActiveDecoder(
        id: 'decoder_0',
        decoderId: 'spi',
        config: DecoderConfig(signalBindings: {}),
        instanceNumber: 1,
        transactions: [tx],
      );

      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(10000);
      when(() => source.timescale).thenReturn(null);
      when(() => source.rootScopes).thenReturn([]);
      when(() => source.isSignalLoaded(any())).thenReturn(false);
      when(() => source.changesInRange(any(), any(), any())).thenReturn([]);

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            waveformSourceProvider.overrideWith(
              () => _LoadedSourceNotifier(source),
            ),
            activeDecodersProvider.overrideWith(
              () => _PreloadedDecodersNotifier([activeDecoder]),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 600,
                    child: WaveformCanvas(),
                  ),
                );
              },
            ),
          ),
        ),
      );
      // Flush postFrameCallback — initialises TimeMapper to [0, 10000].
      await tester.pump();
      // Let _lastLanes be populated with the transaction lane.
      await tester.pump();

      // The transaction lane starts at canvas y=0 (no signal entries above it).
      // With time range [0, 10000] fitted to 800 px:
      //   ticksPerPixel = 12.5 → pixelToTime(240) ≈ 3000 ∈ [2000, 4000].
      // Tapping at viewport (240, 14) is inside the 28 px lane and hits the tx.
      // Cursor must snap to txStartTime = 2000, not the raw tap time (~3000).
      const tapOffset = Offset(240, 14);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(tapOffset);
      await gesture.up();
      await tester.pump();

      final cursor = container.read(cursorStateProvider);
      expect(
        cursor.primaryCursorTime,
        equals(txStartTime),
        reason:
            'Tapping a transaction block must snap the cursor to startTime, '
            'not the raw tap time',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('tap on transaction block snaps cursor when signal lanes are above it', (
      tester,
    ) async {
      // Mirrors the real-app layout: one signal lane (height=30) sits above the
      // transaction lane (y=30, height=28).  The tap must still snap to tx.startTime.
      const txStartTime = 2000;
      const txEndTime = 4000;
      const tx = DecodedTransaction(
        startTime: txStartTime,
        endTime: txEndTime,
        label: 'SPI: 0xAB',
        fields: {'data': '0xAB'},
      );
      const activeDecoder = ActiveDecoder(
        id: 'decoder_0',
        decoderId: 'spi',
        config: DecoderConfig(signalBindings: {}),
        instanceNumber: 1,
        transactions: [tx],
      );

      final source = _MockSource();
      when(() => source.startTime).thenReturn(0);
      when(() => source.endTime).thenReturn(10000);
      when(() => source.timescale).thenReturn(null);
      when(() => source.rootScopes).thenReturn([]);
      when(() => source.isSignalLoaded(any())).thenReturn(true);
      when(() => source.changesInRange(any(), any(), any())).thenReturn([]);
      when(() => source.valueAt(any(), any())).thenReturn(null);

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            waveformSourceProvider.overrideWith(
              () => _LoadedSourceNotifier(source),
            ),
            activeDecodersProvider.overrideWith(
              () => _PreloadedDecodersNotifier([activeDecoder]),
            ),
            signalGroupsProvider.overrideWith(
              _PreloadedGroupsNotifier.new,
            ),
          ],
          child: MaterialApp(
            // Pin to a desktop platform so the canvas applies desktop metrics
            // (minLaneHeight = 16). flutter_test's default Theme.platform is
            // android, which would bump the 30 dp signal lane up to 44 dp
            // and shift the transaction lane out from under the tap point.
            theme: ThemeData(platform: TargetPlatform.macOS),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 600,
                    child: WaveformCanvas(),
                  ),
                );
              },
            ),
          ),
        ),
      );
      // First pump: postFrameCallback initialises TimeMapper + triggers refresh.
      await tester.pump();
      // Second pump: _refresh() setState completes, canvas rebuilds with lanes.
      await tester.pump();

      // Layout after two pumps:
      //   Signal lane ('clk'): y=0,  height=30.
      //   Transaction lane:    y=30, height=28.
      // TimeMapper [0, 10000] on 800 px: ticksPerPixel=12.5.
      //   pixelToTime(240) = round(240 * 12.5) = 3000 ∈ [2000, 4000].
      // Tapping at viewport (240, 40) lands inside the 28 px transaction lane.
      const tapOffset = Offset(240, 40);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.down(tapOffset);
      await gesture.up();
      await tester.pump();

      final cursor = container.read(cursorStateProvider);
      expect(
        cursor.primaryCursorTime,
        equals(txStartTime),
        reason:
            'Tapping a transaction block below signal lanes must snap the '
            'cursor to startTime, not the raw tap time',
      );
      expect(tester.takeException(), isNull);
    });

    // Bug 3: changesInRange must use visibleEnd+1 so transitions at exactly
    // visibleEnd are never silently dropped by floating-point rounding in fitAll.
    testWidgets(
      'changesInRange is called with visibleEnd+1 to include boundary transitions',
      (tester) async {
        const signalRef = 'clk';
        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.endTime).thenReturn(1000);
        when(() => source.timescale).thenReturn(null);
        when(() => source.rootScopes).thenReturn([]);
        when(() => source.isSignalLoaded(any())).thenReturn(true);
        when(() => source.changesInRange(any(), any(), any())).thenReturn([]);
        when(() => source.valueAt(any(), any())).thenReturn(null);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              waveformSourceProvider.overrideWith(
                () => _LoadedSourceNotifier(source),
              ),
              signalGroupsProvider.overrideWith(
                _PreloadedGroupsNotifier.new,
              ),
            ],
            child: const MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: SizedBox(
                  width: 800,
                  height: 600,
                  child: WaveformCanvas(),
                ),
              ),
            ),
          ),
        );
        // First pump flushes the postFrameCallback (TimeMapper init), which changes
        // visibleTimeRangeProvider and triggers _scheduleRefresh().
        await tester.pump();
        // Second pump lets the async _refresh() complete.
        await tester.pump();

        // For range [0, 1000] fit to 800 px: visibleEnd = 1000 = endTime.
        // The fix adds +1, so every call to changesInRange must use end = 1001.
        final captured = verify(
          () => source.changesInRange(signalRef, any(), captureAny()),
        ).captured;
        expect(
          captured,
          isNotEmpty,
          reason:
              'changesInRange should have been called for the loaded signal',
        );
        for (final end in captured) {
          expect(
            end,
            greaterThan(1000),
            reason: 'end must exceed visibleEnd to avoid boundary off-by-one',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );

    // ── cursor-scrub repaint isolation (regression for #cursor-jank) ──────────
    //
    // The dominant cost during cursor scrubbing on a large file (1000+ signals)
    // was that `WaveformCanvas.build()` watched cursorStateProvider and
    // therefore re-ran on every cursor frame. Each rebuild called
    // `_buildLaneData(...)` which produced a fresh `lanes` list. The render
    // object's `lanes` setter then failed reference equality against the new
    // list and called `markNeedsLayout`, forcing a full repaint of every lane.
    //
    // The fix moves cursor watching into an inline Consumer wrapping only
    // [WaveformCanvasView], so cursor changes do NOT rebuild the outer canvas
    // and the lanes list reference stays stable.

    testWidgets(
      'cursor scrub does not rebuild lanes — render object keeps the same '
      'list reference',
      (tester) async {
        const signalRef = 'clk';
        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.endTime).thenReturn(1000);
        when(() => source.timescale).thenReturn(null);
        when(() => source.rootScopes).thenReturn([]);
        when(() => source.isSignalLoaded(signalRef)).thenReturn(true);
        when(
          () => source.changesInRange(signalRef, any(), any()),
        ).thenReturn([]);
        when(() => source.valueAt(signalRef, any())).thenReturn('0');

        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              waveformSourceProvider.overrideWith(
                () => _LoadedSourceNotifier(source),
              ),
              signalGroupsProvider.overrideWith(
                _PreloadedGroupsNotifier.new,
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const Scaffold(
                    body: SizedBox(
                      width: 800,
                      height: 600,
                      child: WaveformCanvas(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        // postFrameCallback initialises TimeMapper.
        await tester.pump();
        // _refresh setState pumps the populated lanes into the render object.
        await tester.pump();

        final ro = tester.renderObject<WaveformCanvasRenderObject>(
          find.byType(WaveformCanvasView),
        );
        final lanesBefore = ro.lanes;
        expect(
          lanesBefore,
          isNotEmpty,
          reason: 'sanity check: lanes should be populated after refresh',
        );

        // Scrub the cursor through several positions. None of these should
        // trigger an outer rebuild → no _buildLaneData → render object's
        // lanes reference must stay identical.
        for (final t in [100, 200, 300, 400, 500]) {
          container.read(cursorStateProvider.notifier).placePrimary(t);
          await tester.pump();
          expect(
            identical(ro.lanes, lanesBefore),
            isTrue,
            reason:
                'cursor scrub at t=$t produced a new lanes list reference — '
                'WaveformCanvas.build() rebuilt on cursor change, defeating '
                'the CursorOverlay layer split. Did someone re-add a '
                'ref.watch(cursorStateProvider) in build()?',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );

    // ── resize guard re-syncs TimeMapper after a stale/dropped width update ────
    //
    // Regression for the secondary-cursor / ruler-marker "bad state" on window
    // shrink. The resize guard in build() defers the TimeMapper.viewportWidth
    // update to a post-frame callback that can be dropped (canvas
    // reparented/unmounted mid-resize during an IdeLayout pane reflow, or a
    // coalesced macOS live-resize frame). Previously the guard compared the
    // layout width only to a local `_viewportWidth` field that had already
    // advanced, so a dropped update left the mapper stuck at a stale width
    // forever — the waveform packed into a strip and the cursor lines / ruler
    // markers landed at the wrong x. The guard now also compares against the
    // watched mapper width, so any divergence self-heals on the next build.
    testWidgets(
      'resize guard re-syncs TimeMapper after a stale/dropped update',
      (tester) async {
        const tx = DecodedTransaction(
          startTime: 2000,
          endTime: 4000,
          label: 'SPI: 0xAB',
          fields: {'data': '0xAB'},
        );
        const activeDecoder = ActiveDecoder(
          id: 'decoder_0',
          decoderId: 'spi',
          config: DecoderConfig(signalBindings: {}),
          instanceNumber: 1,
          transactions: [tx],
        );
        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.endTime).thenReturn(10000);
        when(() => source.timescale).thenReturn(null);
        when(() => source.rootScopes).thenReturn([]);
        when(() => source.isSignalLoaded(any())).thenReturn(false);
        when(() => source.changesInRange(any(), any(), any())).thenReturn([]);

        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              waveformSourceProvider.overrideWith(
                () => _LoadedSourceNotifier(source),
              ),
              activeDecodersProvider.overrideWith(
                () => _PreloadedDecodersNotifier([activeDecoder]),
              ),
            ],
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.macOS),
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const Scaffold(
                    body: SizedBox(
                      width: 800,
                      height: 600,
                      child: WaveformCanvas(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump(); // initialize TimeMapper from source
        await tester.pump(); // apply the initial layout-width update

        expect(
          container.read(timeMapperProvider).viewportWidth,
          equals(800),
          reason: 'sanity: mapper tracks the 800 px canvas after mount',
        );

        // Simulate the end-state of a dropped resize update: the mapper is stuck
        // at a width the canvas no longer has, while the canvas itself stays at
        // its real 800 px layout width.
        container.read(timeMapperProvider.notifier).updateViewportWidth(300);
        expect(container.read(timeMapperProvider).viewportWidth, equals(300));

        // The canvas watches the mapper, so this change rebuilds it; the guard
        // must notice 800 (layout) != 300 (mapper) and reschedule the update.
        await tester.pump(); // rebuild → reschedule
        await tester.pump(); // flush post-frame callback

        expect(
          container.read(timeMapperProvider).viewportWidth,
          equals(800),
          reason:
              'mapper must re-sync to the real 800 px canvas width; staying at '
              '300 is the stuck "bad state" the resize guard regressed into',
        );
        expect(tester.takeException(), isNull);
      },
    );

    // ── issue #43: child-row reservation must extend the canvas height ─────────
    //
    // When a translator-bound signal is expanded, blank child-row space is
    // reserved *after* its lane (advancing the layout y) but adds no lane. The
    // canvas content box height was computed as sum(lane.height), which omits
    // that reserved space, so a signal below the expanded one was painted past
    // the SizedBox boundary and clipped (it "disappeared").
    testWidgets(
      'reserved translator child-row space extends the canvas content height '
      'so a lower signal is not clipped (issue #43)',
      (tester) async {
        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.endTime).thenReturn(10000);
        when(() => source.timescale).thenReturn(null);
        when(() => source.rootScopes).thenReturn([]);
        when(() => source.isSignalLoaded(any())).thenReturn(false);
        when(() => source.changesInRange(any(), any(), any())).thenReturn([]);

        const reservedRows = 3;
        List<WaveformLaneData>? lanes;
        WaveformCanvas.debugOnLanesBuilt = (l) => lanes = l;
        addTearDown(() => WaveformCanvas.debugOnLanesBuilt = null);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              waveformSourceProvider.overrideWith(
                () => _LoadedSourceNotifier(source),
              ),
              signalGroupsProvider.overrideWith(_TwoSignalGroupsNotifier.new),
              // The expanded signal reserves three child rows below its lane.
              signalChildRowCountsProvider.overrideWithValue(const {
                _kExpandedId: reservedRows,
              }),
            ],
            child: const MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              // Tall viewport so the content is not scroll-clamped — the content
              // SizedBox reports its full intrinsic height.
              home: Scaffold(
                body: SizedBox(
                  width: 700,
                  height: 1000,
                  child: WaveformCanvas(),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(lanes, isNotNull);
        expect(lanes!.length, 2);
        final expandedLane = lanes![0];
        final belowLane = lanes![1];

        // The reservation pushed the lower lane down by three child rows.
        expect(
          belowLane.y,
          moreOrLessEquals(
            expandedLane.y +
                expandedLane.height +
                reservedRows * kChildRowHeight,
          ),
          reason: 'lower lane must sit below the reserved child-row space',
        );

        // The canvas content box (child of the scroll-modifier interceptor) must
        // be tall enough to include the lower lane fully — not just sum(heights).
        final contentBox = find
            .descendant(
              of: find.byType(WaveformScrollModifierInterceptor),
              matching: find.byType(SizedBox),
            )
            .first;
        final contentHeight = tester.getSize(contentBox).height;

        expect(
          contentHeight,
          greaterThanOrEqualTo(belowLane.y + belowLane.height),
          reason: 'content box must include the lower lane (issue #43, bug 1)',
        );
        // The pre-fix value (sum of the two lane heights) omitted the reserved
        // space — assert we exceed it, i.e. the reservation is counted.
        expect(
          contentHeight,
          greaterThan(expandedLane.height + belowLane.height),
          reason: 'content height must count the reserved child-row space',
        );
      },
    );

    // ── viewport-gated lane materialization ─────────────────────────────────
    //
    // Rich lane objects are materialized fresh each build from the compact
    // geometry index — all of them for normal files, only the viewport
    // window at gate-level scale. Incremental load batches therefore cost
    // O(visible), never O(all entries): the previous full-list passes (one
    // per 12-signal batch, plus the per-batch patch walk that replaced them)
    // froze the UI for seconds per pass on web/DDC at 1.3M entries.
    testWidgets(
      'incremental load lands changes in the materialized lanes',
      (tester) async {
        const change = SignalChange(time: 5, value: '1');
        final source = _MockSource();
        final loaded = <String>{};
        when(() => source.startTime).thenReturn(0);
        when(() => source.endTime).thenReturn(10000);
        when(() => source.timescale).thenReturn(null);
        when(() => source.rootScopes).thenReturn([]);
        when(
          () => source.isSignalLoaded(any()),
        ).thenAnswer((inv) => loaded.contains(inv.positionalArguments[0]));
        when(() => source.loadSignal(any())).thenAnswer((inv) async {
          final ref = inv.positionalArguments[0] as String;
          // 'stuck' never loads — its lane must survive the patch untouched.
          if (ref == 'stuck') throw StateError('unresolvable ref');
          loaded.add(ref);
        });
        when(
          () => source.changesInRange(any(), any(), any()),
        ).thenReturn(const [change]);
        when(() => source.valueAt(any(), any())).thenReturn('0');

        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              waveformSourceProvider.overrideWith(
                () => _LoadedSourceNotifier(source),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const Scaffold(
                    body: SizedBox(
                      width: 800,
                      height: 600,
                      child: WaveformCanvas(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        List<WaveformLaneData> lanes() => tester
            .widget<WaveformCanvasView>(find.byType(WaveformCanvasView))
            .lanes;
        WaveformLaneData laneFor(String ref) =>
            lanes().singleWhere((l) => l.signalRef == ref);

        container.read(signalGroupsProvider.notifier).addSignals([
          for (final name in ['ok_a', 'ok_b', 'stuck'])
            Variable(
              name: name,
              varType: VarType.wire,
              direction: VarDirection.unknown,
              signalRef: name,
              scopePath: 'top',
            ),
        ]);
        // First frame: lanes materialize with empty data (nothing loaded yet).
        await tester.pump();
        expect(laneFor('ok_a').changes, isEmpty);

        // Let the viewport-gated refresh load the visible signals and land
        // its incremental cache bumps.
        await tester.pumpAndSettle();

        // Loaded lanes carry the fresh data; the unresolvable one stays empty
        // without aborting the batch.
        expect(laneFor('ok_a').changes, const [change]);
        expect(laneFor('ok_b').changes, const [change]);
        expect(laneFor('ok_a').valueAtStart, '0');
        expect(laneFor('stuck').changes, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    // ── parse-in-progress placeholder ────────────────────────────────────────
    testWidgets(
      'loading state shows a spinner and names the file being parsed',
      (tester) async {
        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              waveformSourceProvider.overrideWith(_ParsingSourceNotifier.new),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const Scaffold(
                    body: SizedBox(
                      width: 800,
                      height: 600,
                      child: WaveformCanvas(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        container.read(waveformSourceProvider.notifier).lastAttemptedPath =
            '/sim/runs/luke_wren_gatelevel_netlist_dec_2025.fst';
        await tester.pump();
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final l10n = L10N.of(tester.element(find.byType(Scaffold)));
        expect(
          find.text(
            l10n.waveformCanvasParsing(
              'luke_wren_gatelevel_netlist_dec_2025.fst',
            ),
          ),
          findsOneWidget,
          reason:
              'placeholder must show the basename of the file being '
              'parsed, not the full path',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'above the gating threshold only the viewport window is materialized',
      (tester) async {
        final source = _MockSource();
        when(() => source.startTime).thenReturn(0);
        when(() => source.endTime).thenReturn(10000);
        when(() => source.timescale).thenReturn(null);
        when(() => source.rootScopes).thenReturn([]);
        when(() => source.isSignalLoaded(any())).thenReturn(false);
        when(() => source.loadSignal(any())).thenAnswer((_) async {});
        when(
          () => source.changesInRange(any(), any(), any()),
        ).thenReturn(const []);
        when(() => source.valueAt(any(), any())).thenReturn(null);

        late ProviderContainer container;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              waveformSourceProvider.overrideWith(
                () => _LoadedSourceNotifier(source),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const Scaffold(
                    body: SizedBox(
                      width: 800,
                      height: 600,
                      child: WaveformCanvas(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        const count = WaveformCanvas.fullMaterializeThreshold + 5000;
        container.read(signalGroupsProvider.notifier).addSignals([
          for (var i = 0; i < count; i++)
            Variable(
              name: 's$i',
              varType: VarType.wire,
              direction: VarDirection.unknown,
              signalRef: 's$i',
              scopePath: 'top',
            ),
        ]);
        await tester.pumpAndSettle();

        final view = tester.widget<WaveformCanvasView>(
          find.byType(WaveformCanvasView),
        );
        expect(
          view.lanes.length,
          lessThan(1000),
          reason:
              'a gate-level-sized add must materialize only the viewport '
              'window, not one rich lane object per entry',
        );
        expect(view.lanes, isNotEmpty);
        // Scroll extent still reflects ALL lanes via the geometry bottom.
        final contentBox = find
            .descendant(
              of: find.byType(WaveformScrollModifierInterceptor),
              matching: find.byType(SizedBox),
            )
            .first;
        expect(
          tester.getSize(contentBox).height,
          greaterThan(100000),
          reason: 'content extent must come from the full geometry index',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
