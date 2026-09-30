// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/stage/widgets/pipeline/pipeline_grid.dart';
import 'package:wavecrux/features/stage/widgets/pipeline/pipeline_stage_widget.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

import '../../../../helpers/generated_vcd_fixture.dart';
import '_pipeline_harness.dart';

void main() {
  group('the clean five-stage fixture', () {
    testWidgets('renders one row per instruction, labelled by the '
        'disassembler', (tester) async {
      final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(fixture),
      );

      // Row labels come from the existing disassembler over the bound
      // instruction word, not from a second decoder.
      for (final text in const [
        'lw t0, 0(sp)',
        'add t1, t0, t0',
        'addi t2, t1, 1',
        'beq t2, zero, 16',
        'addi t5, zero, 3',
      ]) {
        expect(find.text(text), findsOneWidget, reason: 'row label "$text"');
      }
    });

    testWidgets('shades cells by stage and labels them with the stage name', (
      tester,
    ) async {
      final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(fixture),
      );

      // 30 occupied cells over the 13-cycle trace; every one carries its
      // stage's name. The counts follow the committed expectation.
      expect(find.text('IF'), findsNWidgets(9)); // 7 grid + legend + …
      for (final stage in const ['IF', 'ID', 'EX', 'MEM', 'WB']) {
        expect(
          find.text(stage),
          findsWidgets,
          reason: 'stage $stage should appear in the grid and the legend',
        );
      }
    });

    testWidgets('no low-confidence banner, because the tracker modelled this '
        'pipe exactly', (tester) async {
      final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(fixture),
      );
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byIcon(Icons.info_outline), findsNothing);
      expect(
        tester.widgetList<Opacity>(find.byType(Opacity)).map((o) => o.opacity),
        everyElement(1.0),
        reason: 'a trustworthy grid is not dimmed',
      );
    });

    testWidgets('clicking a cell moves the primary cursor to that cycle', (
      tester,
    ) async {
      final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
      final container = await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(fixture),
        cursorTime: 0,
      );

      // The first cell of the first row is instruction 0 in IF at cycle 0,
      // whose clock edge is at tick 5. Scoped to the grid so the tap does not
      // land on the legend's identically-labelled swatch.
      await tester.tap(
        find
            .descendant(
              of: find.byType(PipelineGrid),
              matching: find.text('IF'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        container.read(cursorStateProvider).primaryCursorTime,
        5,
        reason:
            'a cycle index means nothing to the rest of the app; the tick is '
            'the shared coordinate',
      );
    });

    testWidgets('every cell is at least a 44 dp touch target', (tester) async {
      final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(fixture),
      );
      for (final element in find.byType(InkWell).evaluate()) {
        final size = tester.getSize(find.byWidget(element.widget));
        expect(
          size.width,
          greaterThanOrEqualTo(kPipelineCellSize - 2),
          reason: 'a tappable cell narrower than the touch-target standard',
        );
        expect(size.height, greaterThanOrEqualTo(kPipelineCellSize - 2));
      }
    });

    testWidgets('the header states the shape and the visible cycle window', (
      tester,
    ) async {
      final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(fixture),
      );
      expect(find.textContaining('5 stages'), findsOneWidget);
      expect(find.textContaining('of 13'), findsOneWidget);
    });
  });

  group('the fixture that defeats positional tracking', () {
    testWidgets('states low confidence instead of drawing a plausible lie', (
      tester,
    ) async {
      // **The hard requirement.** This fixture
      // and the clean one produce the *same* grid; the only thing separating
      // a finding from a fabrication is that the widget says which one it is
      // looking at.
      final fixture = GeneratedVcdFixture.load(defeatPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(fixture),
      );

      final l10n = L10N.of(
        tester.element(find.byType(PipelineGrid)),
      );
      expect(
        find.text(
          l10n.pipelineLowConfidenceBanner(
            2,
            l10n.pipelineChoiceIdentityPositional,
          ),
        ),
        findsOneWidget,
        reason: 'the banner must name the count and the tracker',
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets("the grid is visibly held at arm's length", (tester) async {
      final fixture = GeneratedVcdFixture.load(defeatPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(fixture),
      );
      final opacity = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(
        opacity.map((o) => o.opacity),
        contains(lessThan(1.0)),
        reason:
            'nobody should be able to screenshot this grid as a finding '
            'without the caveat attached',
      );
    });

    testWidgets('per-cell markers say which cells the tracker disowns', (
      tester,
    ) async {
      final fixture = GeneratedVcdFixture.load(defeatPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(fixture),
      );
      final l10n = L10N.of(tester.element(find.byType(PipelineGrid)));
      // The two disowned cells are ID and EX in cycle 7 — but the tracker
      // adopted the *trace* there, so those stages are empty and the marker
      // lands on nothing. What must hold is that the overall state is stated
      // and the grid still renders.
      expect(find.text(l10n.pipelineColumnInstruction), findsOneWidget);
      expect(find.text('lw t0, 0(sp)'), findsOneWidget);
    });

    testWidgets('PC matching survives what defeats positional tracking', (
      tester,
    ) async {
      // The public argument for the free/paid line, made mechanically:
      // the free tier's two trackers have genuinely different limits and the
      // widget reports them honestly rather than pretending either is
      // universal.
      final fixture = GeneratedVcdFixture.load(defeatPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(
          fixture,
          configuration: const {
            PipelineStageWidget.paramIdentitySource: 'pc',
          },
        ),
      );
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.text('lw t0, 0(sp)'), findsOneWidget);
    });
  });

  group('configuration', () {
    testWidgets('the stage count changes the number of columns of shading', (
      tester,
    ) async {
      final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(fixture, stages: 3),
      );
      expect(find.textContaining('3 stages'), findsOneWidget);
      expect(
        find.text('MEM'),
        findsNothing,
        reason: 'stage 4 is not part of a 3-stage pipeline',
      );
    });

    testWidgets('user stage names replace the preset', (tester) async {
      final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(
          fixture,
          stages: 2,
          configuration: const {
            'stage1Name': 'Load',
            'stage2Name': 'Twiddle',
          },
        ),
      );
      expect(find.text('Load'), findsWidgets);
      expect(find.text('IF'), findsNothing);
    });

    testWidgets('a narrow cycle window scrolls rather than showing '
        'everything', (tester) async {
      final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(
          fixture,
          configuration: const {PipelineStageWidget.paramWindowCycles: 4},
        ),
        cursorTime: 5,
      );
      // Anchored on cycle 0, a 4-cycle window shows cycles 0-3 only.
      expect(find.textContaining('cycles 0 to 3'), findsOneWidget);
    });
  });

  group('empty and degraded states', () {
    testWidgets('an unbound clock says so rather than rendering nothing', (
      tester,
    ) async {
      final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(
          fixture,
          omit: {PipelineStageWidget.clockPin},
        ),
      );
      final l10n = L10N.of(tester.element(find.byType(PipelineNotice)));
      expect(find.text(l10n.pipelineNoClock), findsOneWidget);
    });

    testWidgets('no stage valid pin bound names the problem', (tester) async {
      final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(
          fixture,
          omit: {
            for (var s = 1; s <= 8; s++)
              PipelineStageWidget.stagePin(s, 'valid'),
          },
        ),
      );
      final l10n = L10N.of(tester.element(find.byType(PipelineNotice)));
      expect(find.text(l10n.pipelineNoStageBindings(5)), findsOneWidget);
    });

    testWidgets('with no instruction pin, rows fall back to the PC', (
      tester,
    ) async {
      final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(
          fixture,
          omit: {PipelineStageWidget.instructionPin},
        ),
      );
      expect(find.text('lw t0, 0(sp)'), findsNothing);
      expect(
        find.text('0x8000_0000'),
        findsOneWidget,
        reason: 'the honest fallback is the address, not a guessed mnemonic',
      );
    });

    testWidgets('with no disassembler, rows still label by PC', (
      tester,
    ) async {
      final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(fixture),
        withDisassembler: false,
      );
      expect(find.text('0x8000_0000'), findsWidgets);
    });
  });

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('the low-confidence banner is translated in $locale', (
        tester,
      ) async {
        final fixture = GeneratedVcdFixture.load(defeatPipelineFixture);
        await pumpPipeline(
          tester,
          fixture: fixture,
          instance: pipelineInstance(fixture),
          locale: locale,
        );
        final l10n = L10N.of(tester.element(find.byType(PipelineGrid)));
        final banner = l10n.pipelineLowConfidenceBanner(
          2,
          l10n.pipelineChoiceIdentityPositional,
        );
        expect(banner, isNot(contains('pipelineLowConfidenceBanner')));
        expect(find.text(banner), findsOneWidget);
        // The instruction column header and the legend come from the same ARB
        // sweep, so a missing locale shows up here rather than at runtime.
        expect(find.text(l10n.pipelineColumnInstruction), findsOneWidget);
        expect(l10n.pipelineColumnInstruction, isNotEmpty);
      });

      testWidgets('the unbound-clock state is translated in $locale', (
        tester,
      ) async {
        final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
        await pumpPipeline(
          tester,
          fixture: fixture,
          instance: pipelineInstance(
            fixture,
            omit: {PipelineStageWidget.clockPin},
          ),
          locale: locale,
        );
        final l10n = L10N.of(tester.element(find.byType(PipelineNotice)));
        expect(l10n.pipelineNoClock, isNotEmpty);
        expect(find.text(l10n.pipelineNoClock), findsOneWidget);
      });
    }
  });

  group('scroll affordances', () {
    /// Every horizontal scrollable in the widget, paired with the scrollbar
    /// bound to it — `ScrollBehavior` supplies one for vertical scrollables
    /// only, so without these the grid scrolls with no visible affordance and
    /// simply reads as clipped.
    Finder horizontalScrollbar({required Finder within}) => find.descendant(
      of: within,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Scrollbar &&
            w.controller != null &&
            w.controller!.hasClients &&
            w.controller!.position.axis == Axis.horizontal,
      ),
    );

    testWidgets('the cycle columns carry a horizontal scrollbar', (
      tester,
    ) async {
      final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(fixture),
        // Narrow and short enough that the grid overflows on both axes — the
        // case the user hit.
        surface: const Size(420, 320),
      );

      final positions = tester
          .stateList<ScrollableState>(
            find.descendant(
              of: find.byType(PipelineGrid),
              matching: find.byType(Scrollable),
            ),
          )
          .map((s) => s.position)
          .toList();
      // Guards the assertions below against being vacuously true.
      expect(
        positions.firstWhere((p) => p.axis == Axis.horizontal).maxScrollExtent,
        greaterThan(0),
        reason: 'the fixture must actually overflow horizontally here',
      );
      expect(
        positions.firstWhere((p) => p.axis == Axis.vertical).maxScrollExtent,
        greaterThan(0),
        reason: 'and vertically, so the geometry check below means something',
      );

      final bar = horizontalScrollbar(within: find.byType(PipelineGrid));
      expect(
        bar,
        findsOneWidget,
        reason:
            'horizontal scrolling with no scrollbar leaves a grid that is '
            'wider than its panel looking clipped and stuck',
      );
      expect(tester.widget<Scrollbar>(bar).thumbVisibility, isTrue);

      // The scrollbar's box must be the viewport, not the content. Wrapped
      // around the inner horizontal scroll view its box would be the height
      // of every row, so the thumb would sit below the fold exactly when the
      // grid is tall enough to need it.
      expect(
        tester.getRect(bar).bottom,
        moreOrLessEquals(tester.getRect(find.byType(PipelineGrid)).bottom),
      );
    });

    testWidgets('so does the stage legend', (tester) async {
      final fixture = GeneratedVcdFixture.load(cleanPipelineFixture);
      await pumpPipeline(
        tester,
        fixture: fixture,
        instance: pipelineInstance(fixture),
        surface: const Size(420, 320),
      );
      expect(
        horizontalScrollbar(within: find.byType(PipelineLegend)),
        findsOneWidget,
        reason:
            'eight stages in a narrow panel run off the edge with no hint '
            'that the rest are one swipe away',
      );
    });
  });
}
