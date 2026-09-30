// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/providers/riscv_commit_landing_provider.dart';

import '../../../../helpers/generated_vcd_fixture.dart';
import '_riscv_commit_harness.dart';

/// **The landed retirement has to be on screen, not merely in the list.**
///
/// The cross-probe hand-off's own end-to-end test asserted that exactly one
/// commit row was tinted as *current* and that it held the instruction the
/// proof failed on. It passed while the user saw two `addi` rows and had to
/// enlarge the panel by hand to find the row the jump was about — because it
/// pumped the inspector into a full-screen `Scaffold` body, where the whole
/// log fits and the question never arises. Existence was asserted at a size
/// the panel does not have.
///
/// So every assertion here is about **geometry** at a panel size the user
/// really gets: the landed row's painted rectangle against the commits list's
/// painted rectangle. A panel can always be smaller than the log — the user
/// owns their layout, and a phone owns it more — so the row is brought to the
/// user rather than the panel being grown until it happens to fit.
void main() {
  late GeneratedVcdFixture fixture;

  setUp(() {
    fixture = GeneratedVcdFixture.load(cleanRvfiFixture);
  });

  /// The tinted *current* row — the landed retirement — inside the log.
  final currentRow = find.descendant(
    of: find.byType(ListView),
    matching: find.byWidgetPredicate((w) => w is Container && w.color != null),
  );

  /// Records a `riscv.formal.trace_step` landing at [time], the way an inbound
  /// CXP stream coordinate does.
  void recordLanding(ProviderContainer container, int time) {
    container
        .read(riscvCommitLandingProvider.notifier)
        .record(
          streamId: CxpStreamCoordinate.riscvFormalTraceStepStreamId,
          sequenceIndex: 7,
          time: time,
          subId: 'ch0',
          order: 7,
          channelIndex: 0,
        );
  }

  /// The commits list's scroll offset.
  ///
  /// Read off the `Scrollable`'s position rather than the view's controller,
  /// so the assertions below describe *what the list did* and stay meaningful
  /// against an implementation that has no controller at all.
  double logOffset(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .pixels;

  /// Asserts [row] is inside the commits list's viewport — the whole point.
  void expectVisible(WidgetTester tester, Finder row) {
    final list = tester.getRect(find.byType(ListView));
    final rect = tester.getRect(row);
    expect(
      rect.top >= list.top - 0.5 && rect.bottom <= list.bottom + 0.5,
      isTrue,
      reason:
          'the landed retirement is at $rect, outside the commits list '
          'viewport $list — it exists, it is tinted, and the user cannot '
          'see it',
    );
  }

  testWidgets('a landing scrolls the landed retirement into view on a panel '
      'too small to hold the log', (tester) async {
    // 380 px is the Commit Inspector's own declared default height, and the
    // size the cross-probe used to mount at. The chrome — landing banner,
    // bound-channel count, view selector, column header — leaves ~230 px for
    // five 44 px rows; the fixture retires eight.
    //
    // MUTATION: drop the scroll in `RiscvCommitLogView` and this fails — the
    // landed row is the eighth, below the fold and (at this size) not even
    // laid out.
    final container = await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
      surface: const Size(720, 380),
    );
    recordLanding(container, fixture.source.endTime);
    await tester.pumpAndSettle();

    // The assertion the old end-to-end test made…
    expect(currentRow, findsOneWidget);
    // …and the one it did not, which is the whole difference: a row can be in
    // the list, tinted and correct, and painted below its bottom edge.
    expectVisible(tester, currentRow);
    expect(
      logOffset(tester),
      greaterThan(0),
      reason:
          'the log overflows its viewport, so reaching the last '
          'retirement must have taken a scroll',
    );
  });

  testWidgets('a landing on the FIRST retirement does not scroll', (
    tester,
  ) async {
    // Same cramped panel, but the cursor is on the first retirement, so the
    // log holds exactly one row. There is nothing below the fold and nothing
    // to scroll to — a jump here would be a visible twitch answering a
    // question nobody asked.
    final container = await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
      cursorTime: 4,
      surface: const Size(720, 380),
    );
    recordLanding(container, 4);
    await tester.pumpAndSettle();

    expect(currentRow, findsOneWidget);
    expect(logOffset(tester), 0);
    expectVisible(tester, currentRow);
  });

  testWidgets('a log shorter than its viewport does not scroll', (
    tester,
  ) async {
    // Three retirements in a tall panel: the list fits, its scroll extent is
    // zero, and the landing must leave it exactly where it is.
    final container = await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
      cursorTime: 24,
      surface: const Size(720, 800),
    );
    recordLanding(container, 24);
    await tester.pumpAndSettle();

    expect(currentRow, findsOneWidget);
    expect(logOffset(tester), 0);
    expectVisible(tester, currentRow);
  });

  testWidgets('no landing, no scroll — the log opens at the top', (
    tester,
  ) async {
    // The ordinary case this must not disturb. Opening the inspector by hand
    // on a scrubbed trace shows the log from its beginning; only a cross-probe
    // landing moves it.
    await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
      surface: const Size(720, 380),
    );
    expect(logOffset(tester), 0);
  });

  testWidgets('a REPEAT landing on the same element scrolls again', (
    tester,
  ) async {
    // `RiscvCommitLanding.token` is what makes this work: the second
    // cross-probe carries an identical coordinate and differs only in its
    // token, so a view that compared landings rather than tokens would sit
    // still the second time.
    final container = await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
      surface: const Size(720, 380),
    );
    recordLanding(container, fixture.source.endTime);
    await tester.pumpAndSettle();
    final landed = logOffset(tester);
    expect(landed, greaterThan(0));

    // The user scrolls away to read the history…
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(logOffset(tester), lessThan(landed));

    // …and the same cross-probe arrives again.
    recordLanding(container, fixture.source.endTime);
    await tester.pumpAndSettle();
    expect(logOffset(tester), landed);
    expectVisible(tester, currentRow);
  });
}
