// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_theme/crux_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/time_range.dart';
import 'package:wavecrux/domain/models/time_selection.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_canvas_render_object.dart';
import 'package:wavecrux/features/viewer/rendering/waveform_lane_data.dart';
import 'package:wavecrux/features/viewer/widgets/render_stats_collector.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

const _mapper = TimeMapper(
  startTime: 0,
  endTime: 1000,
  viewportWidth: 800,
  ticksPerPixel: 1,
  panOffsetTicks: 0,
);

final CruxColorTheme _colorTheme = defaultBuiltinPreset();
const _cursorState = CursorState();

Widget _buildCanvas({
  List<WaveformLaneData> lanes = const [],
  CursorState cursorState = _cursorState,
  DecodedTransaction? selectedTransaction,
  TimeSelection? selectionRange,
  List<TimeRange> divergenceRegions = const [],
  List<TimeRange> patternMatchRegions = const [],
  int? xOriginTime,
  Set<String> xOriginSignalRefs = const {},
  RenderStatsCollector? statsCollector,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 400,
        child: WaveformCanvasView(
          lanes: lanes,
          timeMapper: _mapper,
          cursorState: cursorState,
          colorTheme: _colorTheme,
          selectedTransaction: selectedTransaction,
          selectionRange: selectionRange,
          divergenceRegions: divergenceRegions,
          patternMatchRegions: patternMatchRegions,
          xOriginTime: xOriginTime,
          xOriginSignalRefs: xOriginSignalRefs,
          statsCollector: statsCollector,
        ),
      ),
    ),
  );
}

/// Wraps the canvas in a [SingleChildScrollView] so the render object receives
/// unbounded vertical constraints and can size itself to the total lane height.
Widget _buildCanvasScrollable({List<WaveformLaneData> lanes = const []}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 600,
        child: SingleChildScrollView(
          child: WaveformCanvasView(
            lanes: lanes,
            timeMapper: _mapper,
            cursorState: _cursorState,
            colorTheme: _colorTheme,
          ),
        ),
      ),
    ),
  );
}

WaveformCanvasRenderObject _getRo(WidgetTester tester) =>
    tester.renderObject<WaveformCanvasRenderObject>(
      find.byType(WaveformCanvasView),
    );

void main() {
  group('WaveformCanvasView / WaveformCanvasRenderObject', () {
    // ── rendering smoke tests ──────────────────────────────────────────────

    testWidgets('renders with empty lanes without throwing', (tester) async {
      await tester.pumpWidget(_buildCanvas());
      expect(tester.takeException(), isNull);
    });

    testWidgets('locale sweep — no exceptions', (tester) async {
      await tester.pumpWidget(
        Localizations(
          locale: const Locale('en'),
          delegates: const [
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          child: _buildCanvas(),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a signal lane', (tester) async {
      const lanes = [
        WaveformLaneData(
          kind: WaveformLaneKind.signal,
          y: 0,
          height: 30,
          signalRef: 'top.clk',
          displayName: 'clk',
          signalColor: Colors.green,
          isScalar: true,
        ),
      ];
      await tester.pumpWidget(_buildCanvas(lanes: lanes));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a group header lane', (tester) async {
      const lanes = [
        WaveformLaneData(
          kind: WaveformLaneKind.group,
          y: 0,
          height: 22,
          groupName: 'Bus Signals',
          displayName: 'Bus Signals',
        ),
      ];
      await tester.pumpWidget(_buildCanvas(lanes: lanes));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a separator lane', (tester) async {
      const lanes = [
        WaveformLaneData(
          kind: WaveformLaneKind.separator,
          y: 0,
          height: 10,
        ),
      ];
      await tester.pumpWidget(_buildCanvas(lanes: lanes));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a comment lane', (tester) async {
      const lanes = [
        WaveformLaneData(
          kind: WaveformLaneKind.comment,
          y: 0,
          height: 22,
          commentText: 'Clock domain A',
          displayName: 'Clock domain A',
        ),
      ];
      await tester.pumpWidget(_buildCanvas(lanes: lanes));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a transaction lane with no transactions', (
      tester,
    ) async {
      const lanes = [
        WaveformLaneData(
          kind: WaveformLaneKind.transaction,
          y: 0,
          height: 28,
          decoderInstanceId: 'decoder_0',
          decoderDisplayName: 'SPI',
        ),
      ];
      await tester.pumpWidget(_buildCanvas(lanes: lanes));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a transaction lane with transactions', (tester) async {
      const txs = [
        DecodedTransaction(startTime: 100, endTime: 300, label: 'Write 0xFF'),
        DecodedTransaction(startTime: 400, endTime: 600, label: 'Read 0x50'),
        DecodedTransaction(
          startTime: 700,
          endTime: 800,
          label: 'ERR',
          isError: true,
        ),
      ];
      const lanes = [
        WaveformLaneData(
          kind: WaveformLaneKind.transaction,
          y: 0,
          height: 28,
          decoderInstanceId: 'decoder_0',
          decoderDisplayName: 'SPI',
          transactions: txs,
        ),
      ];
      await tester.pumpWidget(_buildCanvas(lanes: lanes));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders selected transaction highlight', (tester) async {
      const tx = DecodedTransaction(
        startTime: 100,
        endTime: 300,
        label: 'Write 0xFF',
      );
      const lanes = [
        WaveformLaneData(
          kind: WaveformLaneKind.transaction,
          y: 0,
          height: 28,
          decoderInstanceId: 'decoder_0',
          decoderDisplayName: 'UART',
          transactions: [tx],
        ),
      ];
      await tester.pumpWidget(
        _buildCanvas(lanes: lanes, selectedTransaction: tx),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders primary cursor overlay', (tester) async {
      await tester.pumpWidget(
        _buildCanvas(
          cursorState: const CursorState(primaryCursorTime: 500),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders both cursors without throwing', (tester) async {
      // The render object no longer paints the cursor lines or delta chip
      // (those moved to the sibling CursorOverlay layer). We still pump a
      // populated CursorState here to verify the render object handles a
      // non-null cursor without exception — it is read by AnalogSignalPainter
      // for inline analog cursor labels.
      await tester.pumpWidget(
        _buildCanvas(
          cursorState: const CursorState(
            primaryCursorTime: 200,
            secondaryCursorTime: 600,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders mixed lane types including transaction', (
      tester,
    ) async {
      const txs = [
        DecodedTransaction(startTime: 50, endTime: 200, label: 'Frame 1'),
      ];
      const lanes = [
        WaveformLaneData(
          kind: WaveformLaneKind.group,
          y: 0,
          height: 22,
          groupName: 'Clocks',
          displayName: 'Clocks',
        ),
        WaveformLaneData(
          kind: WaveformLaneKind.signal,
          y: 22,
          height: 30,
          signalRef: 'top.clk',
          displayName: 'clk',
          signalColor: Colors.green,
          isScalar: true,
        ),
        WaveformLaneData(
          kind: WaveformLaneKind.separator,
          y: 52,
          height: 10,
        ),
        WaveformLaneData(
          kind: WaveformLaneKind.comment,
          y: 62,
          height: 22,
          commentText: 'end of clocks',
          displayName: 'end of clocks',
        ),
        WaveformLaneData(
          kind: WaveformLaneKind.transaction,
          y: 84,
          height: 28,
          decoderInstanceId: 'decoder_0',
          decoderDisplayName: 'SPI',
          transactions: txs,
        ),
      ];
      await tester.pumpWidget(_buildCanvas(lanes: lanes));
      expect(tester.takeException(), isNull);
    });

    testWidgets('updates when lanes change', (tester) async {
      await tester.pumpWidget(_buildCanvas());

      const updatedLanes = [
        WaveformLaneData(
          kind: WaveformLaneKind.signal,
          y: 0,
          height: 30,
          signalRef: 'top.data',
          displayName: 'data',
          signalColor: Colors.cyan,
          bitWidth: 8,
        ),
      ];
      await tester.pumpWidget(_buildCanvas(lanes: updatedLanes));
      expect(tester.takeException(), isNull);
    });

    // ── layout ────────────────────────────────────────────────────────────

    group('layout', () {
      testWidgets('sizes to total lane height with loose constraints', (
        tester,
      ) async {
        const lanes = [
          WaveformLaneData(kind: WaveformLaneKind.separator, y: 0, height: 30),
          WaveformLaneData(kind: WaveformLaneKind.separator, y: 30, height: 40),
        ];
        await tester.pumpWidget(_buildCanvasScrollable(lanes: lanes));
        expect(tester.takeException(), isNull);
        final ro = _getRo(tester);
        expect(ro.size.height, 70.0);
        expect(ro.size.width, 800.0);
      });

      testWidgets('zero lanes gives zero height with loose constraints', (
        tester,
      ) async {
        await tester.pumpWidget(_buildCanvasScrollable());
        expect(tester.takeException(), isNull);
        final ro = _getRo(tester);
        expect(ro.size.height, 0.0);
        expect(ro.size.width, 800.0);
      });

      testWidgets('height sums across all lane kinds', (tester) async {
        // 22 + 30 + 10 + 22 = 84
        const lanes = [
          WaveformLaneData(
            kind: WaveformLaneKind.group,
            y: 0,
            height: 22,
            displayName: 'G',
          ),
          WaveformLaneData(
            kind: WaveformLaneKind.signal,
            y: 22,
            height: 30,
            signalRef: 'a',
            displayName: 'a',
            isScalar: true,
          ),
          WaveformLaneData(kind: WaveformLaneKind.separator, y: 52, height: 10),
          WaveformLaneData(
            kind: WaveformLaneKind.comment,
            y: 62,
            height: 22,
            commentText: 'c',
            displayName: 'c',
          ),
        ];
        await tester.pumpWidget(_buildCanvasScrollable(lanes: lanes));
        final ro = _getRo(tester);
        expect(ro.size.height, 84.0);
      });

      testWidgets('width always fills parent regardless of lane count', (
        tester,
      ) async {
        const lanes = [
          WaveformLaneData(
            kind: WaveformLaneKind.signal,
            y: 0,
            height: 30,
            signalRef: 'x',
            displayName: 'x',
            isScalar: true,
          ),
        ];
        await tester.pumpWidget(_buildCanvasScrollable(lanes: lanes));
        final ro = _getRo(tester);
        expect(ro.size.width, 800.0);
      });

      testWidgets('single tall lane gives correct height', (tester) async {
        const lanes = [
          WaveformLaneData(
            kind: WaveformLaneKind.signal,
            y: 0,
            height: 200,
            signalRef: 'big',
            displayName: 'big',
            isScalar: true,
          ),
        ];
        await tester.pumpWidget(_buildCanvasScrollable(lanes: lanes));
        final ro = _getRo(tester);
        expect(ro.size.height, 200.0);
      });
    });

    // ── intrinsic sizes ───────────────────────────────────────────────────

    group('intrinsic sizes', () {
      testWidgets('getMinIntrinsicHeight equals total lane height', (
        tester,
      ) async {
        const lanes = [
          WaveformLaneData(kind: WaveformLaneKind.separator, y: 0, height: 30),
          WaveformLaneData(kind: WaveformLaneKind.separator, y: 30, height: 50),
        ];
        await tester.pumpWidget(_buildCanvasScrollable(lanes: lanes));
        final ro = _getRo(tester);
        expect(ro.getMinIntrinsicHeight(800), 80.0);
      });

      testWidgets('getMaxIntrinsicHeight equals total lane height', (
        tester,
      ) async {
        const lanes = [
          WaveformLaneData(kind: WaveformLaneKind.separator, y: 0, height: 30),
          WaveformLaneData(kind: WaveformLaneKind.separator, y: 30, height: 50),
        ];
        await tester.pumpWidget(_buildCanvasScrollable(lanes: lanes));
        final ro = _getRo(tester);
        expect(ro.getMaxIntrinsicHeight(800), 80.0);
      });

      testWidgets('intrinsic height is zero for empty lanes', (tester) async {
        await tester.pumpWidget(_buildCanvasScrollable());
        final ro = _getRo(tester);
        expect(ro.getMinIntrinsicHeight(double.infinity), 0.0);
        expect(ro.getMaxIntrinsicHeight(double.infinity), 0.0);
      });

      testWidgets('min and max intrinsic heights are equal', (tester) async {
        const lanes = [
          WaveformLaneData(kind: WaveformLaneKind.separator, y: 0, height: 44),
        ];
        await tester.pumpWidget(_buildCanvasScrollable(lanes: lanes));
        final ro = _getRo(tester);
        expect(ro.getMinIntrinsicHeight(800), ro.getMaxIntrinsicHeight(800));
      });
    });

    // ── property setter equality guards ───────────────────────────────────

    group('property setter equality guards', () {
      testWidgets('setting same lanes instance does not mark needs-layout', (
        tester,
      ) async {
        final lanes = [
          const WaveformLaneData(
            kind: WaveformLaneKind.separator,
            y: 0,
            height: 20,
          ),
        ];
        await tester.pumpWidget(_buildCanvas(lanes: lanes));
        // Cascade setter onto _getRo so ro is declared in one expression.
        final ro = _getRo(tester)..lanes = lanes; // same identity
        expect(ro.debugNeedsLayout, isFalse);
      });

      testWidgets('setting new lanes list instance marks needs-layout', (
        tester,
      ) async {
        final lanes1 = [
          const WaveformLaneData(
            kind: WaveformLaneKind.separator,
            y: 0,
            height: 20,
          ),
        ];
        // Build lanes2 before pumping so we can cascade it directly.
        final lanes2 = List<WaveformLaneData>.from(lanes1);
        await tester.pumpWidget(_buildCanvas(lanes: lanes1));
        final ro = _getRo(tester)..lanes = lanes2; // different instance
        expect(ro.debugNeedsLayout, isTrue);
      });

      testWidgets('setting identical timeMapper does not mark needs-paint', (
        tester,
      ) async {
        await tester.pumpWidget(_buildCanvas());
        final ro = _getRo(tester)..timeMapper = _mapper; // same value
        expect(ro.debugNeedsPaint, isFalse);
      });

      testWidgets('setting different timeMapper marks needs-paint', (
        tester,
      ) async {
        await tester.pumpWidget(_buildCanvas());
        final ro = _getRo(tester)
          ..timeMapper = const TimeMapper(
            startTime: 0,
            endTime: 2000,
            viewportWidth: 800,
            ticksPerPixel: 2,
            panOffsetTicks: 0,
          );
        expect(ro.debugNeedsPaint, isTrue);
      });

      testWidgets('setting identical cursorState does not mark needs-paint', (
        tester,
      ) async {
        await tester.pumpWidget(_buildCanvas());
        final ro = _getRo(tester)..cursorState = _cursorState; // same value
        expect(ro.debugNeedsPaint, isFalse);
      });

      testWidgets(
        'setting different cursorState does NOT mark needs-paint when no '
        'analog lanes (digital-only canvas)',
        (tester) async {
          // The lane painter does not depend on cursor position when only
          // scalar / vector / transaction lanes are visible — the cursor
          // line and delta chip are now drawn by the sibling CursorOverlay
          // RepaintBoundary. This is the dominant performance win for the
          // 1000+-signal scrubbing case.
          const lanes = [
            WaveformLaneData(
              kind: WaveformLaneKind.signal,
              y: 0,
              height: 30,
              signalRef: 'top.clk',
              displayName: 'clk',
              signalColor: Colors.green,
              isScalar: true,
            ),
          ];
          await tester.pumpWidget(_buildCanvas(lanes: lanes));
          final ro = _getRo(tester)
            ..cursorState = const CursorState(primaryCursorTime: 100);
          expect(ro.debugNeedsPaint, isFalse);
        },
      );

      testWidgets(
        'setting different cursorState marks needs-paint when at least '
        'one analog lane is visible',
        (tester) async {
          // AnalogSignalPainter draws an inline value dot + label at the
          // cursor position on each analog trace, so a cursor change must
          // invalidate the lane painter for canvases that contain at least
          // one analog signal.
          const lanes = [
            WaveformLaneData(
              kind: WaveformLaneKind.signal,
              y: 0,
              height: 60,
              signalRef: 'top.vout',
              displayName: 'vout',
              signalColor: Colors.cyan,
              isAnalog: true,
            ),
          ];
          await tester.pumpWidget(_buildCanvas(lanes: lanes));
          final ro = _getRo(tester)
            ..cursorState = const CursorState(primaryCursorTime: 100);
          expect(ro.debugNeedsPaint, isTrue);
        },
      );

      testWidgets('setting identical colorTheme does not mark needs-paint', (
        tester,
      ) async {
        await tester.pumpWidget(_buildCanvas());
        // Same preset instance — equality check suppresses repaint.
        final ro = _getRo(tester)..colorTheme = defaultBuiltinPreset();
        expect(ro.debugNeedsPaint, isFalse);
      });

      testWidgets('setting different colorTheme marks needs-paint', (
        tester,
      ) async {
        await tester.pumpWidget(_buildCanvas());
        // A different preset changes the token values — should trigger repaint.
        final ro = _getRo(tester)
          ..colorTheme = builtinPresets()[cruxLightPresetId]!;
        expect(ro.debugNeedsPaint, isTrue);
      });

      testWidgets(
        'setting null selectionRange when already null does not mark needs-paint',
        (tester) async {
          await tester.pumpWidget(_buildCanvas());
          final ro = _getRo(tester)..selectionRange = null;
          expect(ro.debugNeedsPaint, isFalse);
        },
      );

      testWidgets('setting non-null selectionRange marks needs-paint', (
        tester,
      ) async {
        await tester.pumpWidget(_buildCanvas());
        final ro = _getRo(tester)
          ..selectionRange = const TimeSelection(startTime: 100, endTime: 200);
        expect(ro.debugNeedsPaint, isTrue);
      });

      testWidgets(
        'setting same-value selectionRange does not mark needs-paint',
        (tester) async {
          const sel = TimeSelection(startTime: 100, endTime: 200);
          await tester.pumpWidget(_buildCanvas(selectionRange: sel));
          final ro = _getRo(
            tester,
          )..selectionRange = const TimeSelection(startTime: 100, endTime: 200);
          expect(ro.debugNeedsPaint, isFalse);
        },
      );

      testWidgets('setting different selectionRange marks needs-paint', (
        tester,
      ) async {
        const sel = TimeSelection(startTime: 100, endTime: 200);
        await tester.pumpWidget(_buildCanvas(selectionRange: sel));
        final ro = _getRo(tester)
          ..selectionRange = const TimeSelection(startTime: 300, endTime: 500);
        expect(ro.debugNeedsPaint, isTrue);
      });

      testWidgets(
        'setting null selectedTransaction when already null does not mark needs-paint',
        (tester) async {
          await tester.pumpWidget(_buildCanvas());
          final ro = _getRo(tester)..selectedTransaction = null;
          expect(ro.debugNeedsPaint, isFalse);
        },
      );

      testWidgets(
        'setting same-value selectedTransaction does not mark needs-paint',
        (tester) async {
          const tx = DecodedTransaction(
            startTime: 100,
            endTime: 300,
            label: 'A',
          );
          await tester.pumpWidget(_buildCanvas(selectedTransaction: tx));
          final ro = _getRo(tester)
            ..selectedTransaction = const DecodedTransaction(
              startTime: 100,
              endTime: 300,
              label: 'A',
            );
          expect(ro.debugNeedsPaint, isFalse);
        },
      );

      testWidgets('setting different selectedTransaction marks needs-paint', (
        tester,
      ) async {
        await tester.pumpWidget(_buildCanvas());
        final ro = _getRo(tester)
          ..selectedTransaction = const DecodedTransaction(
            startTime: 100,
            endTime: 300,
            label: 'B',
          );
        expect(ro.debugNeedsPaint, isTrue);
      });

      testWidgets(
        'setting same divergenceRegions instance does not mark needs-paint',
        (tester) async {
          final regions = [const TimeRange(start: 100, end: 200)];
          await tester.pumpWidget(_buildCanvas(divergenceRegions: regions));
          final ro = _getRo(tester)
            ..divergenceRegions = regions; // same instance
          expect(ro.debugNeedsPaint, isFalse);
        },
      );

      testWidgets('setting new divergenceRegions list marks needs-paint', (
        tester,
      ) async {
        final regions = [const TimeRange(start: 100, end: 200)];
        await tester.pumpWidget(_buildCanvas(divergenceRegions: regions));
        // New list instance even with equal content triggers repaint.
        final ro = _getRo(tester)
          ..divergenceRegions = [const TimeRange(start: 100, end: 200)];
        expect(ro.debugNeedsPaint, isTrue);
      });

      testWidgets(
        'setting same patternMatchRegions instance does not mark needs-paint',
        (tester) async {
          final regions = [const TimeRange(start: 50, end: 150)];
          await tester.pumpWidget(_buildCanvas(patternMatchRegions: regions));
          final ro = _getRo(tester)
            ..patternMatchRegions = regions; // same instance
          expect(ro.debugNeedsPaint, isFalse);
        },
      );

      testWidgets('setting new patternMatchRegions list marks needs-paint', (
        tester,
      ) async {
        final regions = [const TimeRange(start: 50, end: 150)];
        await tester.pumpWidget(_buildCanvas(patternMatchRegions: regions));
        // New list instance triggers repaint.
        final ro = _getRo(tester)
          ..patternMatchRegions = [const TimeRange(start: 50, end: 150)];
        expect(ro.debugNeedsPaint, isTrue);
      });

      testWidgets('setting same xOriginTime does not mark needs-paint', (
        tester,
      ) async {
        await tester.pumpWidget(_buildCanvas(xOriginTime: 300));
        final ro = _getRo(tester)..xOriginTime = 300;
        expect(ro.debugNeedsPaint, isFalse);
      });

      testWidgets('setting different xOriginTime marks needs-paint', (
        tester,
      ) async {
        await tester.pumpWidget(_buildCanvas(xOriginTime: 300));
        final ro = _getRo(tester)..xOriginTime = 400;
        expect(ro.debugNeedsPaint, isTrue);
      });

      testWidgets('clearing xOriginTime (null) marks needs-paint', (
        tester,
      ) async {
        await tester.pumpWidget(_buildCanvas(xOriginTime: 300));
        final ro = _getRo(tester)..xOriginTime = null;
        expect(ro.debugNeedsPaint, isTrue);
      });

      testWidgets(
        'setting same xOriginSignalRefs instance does not mark needs-paint',
        (tester) async {
          const refs = {'top.clk'};
          await tester.pumpWidget(_buildCanvas(xOriginSignalRefs: refs));
          final ro = _getRo(tester)..xOriginSignalRefs = refs;
          expect(ro.debugNeedsPaint, isFalse);
        },
      );

      testWidgets('setting new xOriginSignalRefs set marks needs-paint', (
        tester,
      ) async {
        const refs = {'top.clk'};
        await tester.pumpWidget(_buildCanvas(xOriginSignalRefs: refs));
        final ro = _getRo(tester)..xOriginSignalRefs = {'top.clk'};
        expect(ro.debugNeedsPaint, isTrue);
      });
    });

    // ── hit testing ───────────────────────────────────────────────────────

    group('hit testing', () {
      testWidgets('hitTestSelf returns true at origin', (tester) async {
        await tester.pumpWidget(_buildCanvas());
        final ro = _getRo(tester);
        expect(ro.hitTestSelf(Offset.zero), isTrue);
      });

      testWidgets('hitTestSelf returns true at centre of canvas', (
        tester,
      ) async {
        await tester.pumpWidget(_buildCanvas());
        final ro = _getRo(tester);
        expect(ro.hitTestSelf(const Offset(400, 200)), isTrue);
      });

      testWidgets('hitTestSelf returns true at far corner', (tester) async {
        await tester.pumpWidget(_buildCanvas());
        final ro = _getRo(tester);
        expect(ro.hitTestSelf(const Offset(799, 399)), isTrue);
      });

      testWidgets('tap on canvas does not throw', (tester) async {
        const lanes = [
          WaveformLaneData(
            kind: WaveformLaneKind.signal,
            y: 0,
            height: 100,
            signalRef: 'top.clk',
            displayName: 'clk',
            isScalar: true,
          ),
        ];
        await tester.pumpWidget(_buildCanvas(lanes: lanes));
        await tester.tapAt(const Offset(400, 50));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    });

    // ── additional paint paths ────────────────────────────────────────────

    group('additional paint paths', () {
      testWidgets('renders xorDiff lane without throwing', (tester) async {
        const lanes = [
          WaveformLaneData(
            kind: WaveformLaneKind.xorDiff,
            y: 0,
            height: 30,
            displayName: 'XOR diff',
            signalColor: Colors.orange,
          ),
        ];
        await tester.pumpWidget(_buildCanvas(lanes: lanes));
        expect(tester.takeException(), isNull);
      });

      testWidgets('renders non-empty selectionRange overlay without throwing', (
        tester,
      ) async {
        const sel = TimeSelection(startTime: 200, endTime: 500);
        await tester.pumpWidget(_buildCanvas(selectionRange: sel));
        expect(tester.takeException(), isNull);
      });

      testWidgets('zero-width selectionRange does not throw', (tester) async {
        // isEmpty == true → overlay branch skipped
        const sel = TimeSelection(startTime: 300, endTime: 300);
        await tester.pumpWidget(_buildCanvas(selectionRange: sel));
        expect(tester.takeException(), isNull);
      });

      testWidgets('renders divergenceRegions overlay without throwing', (
        tester,
      ) async {
        const regions = [
          TimeRange(start: 100, end: 400),
          TimeRange(start: 600, end: 800),
        ];
        await tester.pumpWidget(_buildCanvas(divergenceRegions: regions));
        expect(tester.takeException(), isNull);
      });

      testWidgets('renders patternMatchRegions overlay without throwing', (
        tester,
      ) async {
        const regions = [
          TimeRange(start: 50, end: 200),
          TimeRange(start: 500, end: 700),
        ];
        await tester.pumpWidget(_buildCanvas(patternMatchRegions: regions));
        expect(tester.takeException(), isNull);
      });

      testWidgets('renders all overlays together without throwing', (
        tester,
      ) async {
        const sel = TimeSelection(startTime: 100, endTime: 300);
        const divergence = [TimeRange(start: 400, end: 600)];
        const pattern = [TimeRange(start: 700, end: 900)];
        const lanes = [
          WaveformLaneData(
            kind: WaveformLaneKind.signal,
            y: 0,
            height: 30,
            signalRef: 'x',
            displayName: 'x',
            isScalar: true,
          ),
          WaveformLaneData(
            kind: WaveformLaneKind.xorDiff,
            y: 30,
            height: 30,
            displayName: 'diff',
          ),
        ];
        await tester.pumpWidget(
          _buildCanvas(
            lanes: lanes,
            selectionRange: sel,
            divergenceRegions: divergence,
            patternMatchRegions: pattern,
            cursorState: const CursorState(
              primaryCursorTime: 500,
              secondaryCursorTime: 700,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'zero-duration divergence region (start==end) does not throw',
        (tester) async {
          // x2 <= x1 → branch skipped without drawing
          const regions = [TimeRange(start: 500, end: 500)];
          await tester.pumpWidget(_buildCanvas(divergenceRegions: regions));
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'zero-duration patternMatch region (start==end) does not throw',
        (tester) async {
          const regions = [TimeRange(start: 300, end: 300)];
          await tester.pumpWidget(_buildCanvas(patternMatchRegions: regions));
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('comment lane with null commentText does not throw', (
        tester,
      ) async {
        const lanes = [
          WaveformLaneData(
            kind: WaveformLaneKind.comment,
            y: 0,
            height: 22,
            // commentText intentionally omitted (null)
          ),
        ];
        await tester.pumpWidget(_buildCanvas(lanes: lanes));
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'transaction lane with empty decoderDisplayName does not throw',
        (tester) async {
          const lanes = [
            WaveformLaneData(
              kind: WaveformLaneKind.transaction,
              y: 0,
              height: 28,
              decoderInstanceId: 'dec_1',
              // decoderDisplayName intentionally omitted (null)
            ),
          ];
          await tester.pumpWidget(_buildCanvas(lanes: lanes));
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'xOriginTime with matching signalRef paints markers without throwing',
        (tester) async {
          const lanes = [
            WaveformLaneData(
              kind: WaveformLaneKind.signal,
              y: 0,
              height: 30,
              signalRef: '#',
              displayName: 'data',
              isScalar: true,
            ),
          ];
          await tester.pumpWidget(
            _buildCanvas(
              lanes: lanes,
              xOriginTime: 400,
              xOriginSignalRefs: {'#'},
            ),
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'xOriginTime with no matching signalRefs paints no markers and does not throw',
        (tester) async {
          const lanes = [
            WaveformLaneData(
              kind: WaveformLaneKind.signal,
              y: 0,
              height: 30,
              signalRef: '#',
              displayName: 'data',
              isScalar: true,
            ),
          ];
          // xOriginSignalRefs defaults to empty — no markers should be drawn.
          await tester.pumpWidget(
            _buildCanvas(
              lanes: lanes,
              xOriginTime: 400,
            ),
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('null xOriginTime paints no markers and does not throw', (
        tester,
      ) async {
        const lanes = [
          WaveformLaneData(
            kind: WaveformLaneKind.signal,
            y: 0,
            height: 30,
            signalRef: '#',
            displayName: 'data',
            isScalar: true,
          ),
        ];
        await tester.pumpWidget(_buildCanvas(lanes: lanes));
        expect(tester.takeException(), isNull);
      });

      testWidgets('xOriginTime outside visible pixel range does not throw', (
        tester,
      ) async {
        // _mapper has endTime=1000, viewportWidth=800. Time 2000 maps to x>800.
        const lanes = [
          WaveformLaneData(
            kind: WaveformLaneKind.signal,
            y: 0,
            height: 30,
            signalRef: '#',
            displayName: 'data',
            isScalar: true,
          ),
        ];
        await tester.pumpWidget(
          _buildCanvas(
            lanes: lanes,
            xOriginTime: 2000,
            xOriginSignalRefs: {'#'},
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'xOriginMarkers painted alongside other overlays without throwing',
        (tester) async {
          const sel = TimeSelection(startTime: 100, endTime: 300);
          const divergence = [TimeRange(start: 400, end: 600)];
          const pattern = [TimeRange(start: 700, end: 900)];
          const lanes = [
            WaveformLaneData(
              kind: WaveformLaneKind.signal,
              y: 0,
              height: 30,
              signalRef: '#',
              displayName: 'data',
              isScalar: true,
            ),
          ];
          await tester.pumpWidget(
            _buildCanvas(
              lanes: lanes,
              selectionRange: sel,
              divergenceRegions: divergence,
              patternMatchRegions: pattern,
              xOriginTime: 500,
              xOriginSignalRefs: {'#'},
            ),
          );
          expect(tester.takeException(), isNull);
        },
      );
    });

    // ── stats collector ───────────────────────────────────────────────────

    group('RenderStatsCollector integration', () {
      testWidgets('visibleTransitions counts only the visible slice', (
        tester,
      ) async {
        final collector = RenderStatsCollector();
        addTearDown(collector.dispose);
        // 1 tick per pixel on an 800 px canvas: ticks 800 and up are the
        // off-screen band the canvas caches for panning.
        const lane = WaveformLaneData(
          kind: WaveformLaneKind.signal,
          y: 0,
          height: 30,
          signalRef: 'top.clk',
          displayName: 'clk',
          isScalar: true,
          changes: [
            SignalChange(time: 100, value: '1'),
            SignalChange(time: 500, value: '0'),
            SignalChange(time: 900, value: '1'),
            SignalChange(time: 950, value: '0'),
          ],
        );
        await tester.pumpWidget(
          _buildCanvas(lanes: [lane], statsCollector: collector),
        );
        await tester.pump();

        expect(collector.stats?.visibleTransitions, 2);
        expect(collector.stats?.lineSegmentsDrawn, 2);
      });

      testWidgets('empty lanes zeros all stats counters', (tester) async {
        final collector = RenderStatsCollector();
        addTearDown(collector.dispose);

        // First, paint a frame with one signal lane so the collector has
        // non-zero values.
        const signalLane = WaveformLaneData(
          kind: WaveformLaneKind.signal,
          y: 0,
          height: 30,
          signalRef: 'top.clk',
          displayName: 'clk',
          isScalar: true,
          changes: [
            SignalChange(time: 100, value: '1'),
            SignalChange(time: 200, value: '0'),
          ],
        );
        await tester.pumpWidget(
          _buildCanvas(lanes: [signalLane], statsCollector: collector),
        );
        await tester.pump();

        expect(collector.stats?.visibleSignalRows, greaterThan(0));

        // Now switch to empty lanes — the early return in paint() should zero
        // the stats even though no signal loop iterations run.
        await tester.pumpWidget(_buildCanvas(statsCollector: collector));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(collector.stats?.visibleSignalRows, 0);
        expect(collector.stats?.visibleTransitions, 0);
        expect(collector.stats?.lineSegmentsDrawn, 0);
      });

      testWidgets(
        'stats report the actual canvas size for empty lanes (Issue 26)',
        (tester) async {
          // Issue 26: empty lanes previously recorded `Size.zero`, which
          // surfaced as the misleading "0×0 px" canvas size in the Pane
          // Render Stats popover even though the empty-state placeholder
          // occupies the pane's real on-screen dimensions. The fix records
          // the render object's actual `size` instead so the popover reflects
          // the canvas extent the user is actually looking at.
          final collector = RenderStatsCollector();
          addTearDown(collector.dispose);

          await tester.pumpWidget(_buildCanvas(statsCollector: collector));
          await tester.pump();

          expect(tester.takeException(), isNull);
          // `_buildCanvas` wraps the canvas in `SizedBox(width: 800, height: 400)`.
          expect(collector.stats?.canvasWidth, equals(800.0));
          expect(collector.stats?.canvasHeight, equals(400.0));
        },
      );

      testWidgets('non-empty lanes report correct visible signal row count', (
        tester,
      ) async {
        final collector = RenderStatsCollector();
        addTearDown(collector.dispose);

        const lanes = [
          WaveformLaneData(
            kind: WaveformLaneKind.signal,
            y: 0,
            height: 30,
            signalRef: 'a',
            displayName: 'a',
            isScalar: true,
          ),
          WaveformLaneData(
            kind: WaveformLaneKind.group,
            y: 30,
            height: 22,
            displayName: 'G',
          ),
          WaveformLaneData(
            kind: WaveformLaneKind.signal,
            y: 52,
            height: 30,
            signalRef: 'b',
            displayName: 'b',
            isScalar: true,
          ),
        ];
        await tester.pumpWidget(
          _buildCanvas(lanes: lanes, statsCollector: collector),
        );
        await tester.pump();

        // Only signal-kind lanes increment visibleSignalRows.
        expect(collector.stats?.visibleSignalRows, 2);
      });
    });
  });

  group('lifecycle', () {
    testWidgets('lastPaintCommands is released when the render object is '
        'disposed', (tester) async {
      await tester.pumpWidget(_buildCanvas());
      final ro = _getRo(tester);
      final notifier = ro.lastPaintCommands;

      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pump();

      // A disposed ValueNotifier rejects new listeners; an undisposed one
      // would silently accept them and stay reachable for the app's lifetime.
      expect(() => notifier.addListener(() {}), throwsFlutterError);
    });
  });
}
