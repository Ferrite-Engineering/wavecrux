// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/stage/providers/riscv_commit_landing_provider.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_views.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/remote/cxp/riscv_stream_coordinate_resolver.dart';

import '../../../../helpers/generated_vcd_fixture.dart';
import '_riscv_commit_harness.dart';

/// Every locale the suite ships. `zh` mirrors `zh_CN` and is covered by the
/// same ARB.
const List<Locale> _locales = [
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

/// A `riscv.formal.trace_step` landing carrying the full advisory set SimCrux
/// sends for a failing bounded proof.
void _recordFormalLanding(
  ProviderContainer container, {
  required int time,
  int step = 7,
  int? order = 3,
  String mode = 'live',
  bool withDepth = true,
  bool autoMounted = false,
}) {
  container
      .read(riscvCommitLandingProvider.notifier)
      .record(
        streamId: CxpStreamCoordinate.riscvFormalTraceStepStreamId,
        sequenceIndex: step,
        time: time,
        subId: 'ch0',
        order: order,
        channelIndex: 0,
        autoMounted: autoMounted,
        attributes: {
          RiscvCoordinateAttributes.check: 'insn_sub_ch0',
          RiscvCoordinateAttributes.group: 'insn',
          RiscvCoordinateAttributes.verdict: 'FAIL',
          if (withDepth) RiscvCoordinateAttributes.depthConfigured: '20',
          CxpStreamCoordinate.riscvIsaAttribute: 'rv32i',
          CxpStreamCoordinate.riscvModeAttribute: mode,
        },
      );
}

void main() {
  late GeneratedVcdFixture fixture;

  setUp(() {
    fixture = GeneratedVcdFixture.load(cleanRvfiFixture);
  });

  testWidgets('no landing means no banner', (tester) async {
    await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
    );
    expect(find.byType(RiscvCommitLandingBanner), findsNothing);
  });

  testWidgets('names the check, the step of the depth, and the ISA', (
    tester,
  ) async {
    final container = await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
    );
    _recordFormalLanding(container, time: fixture.source.endTime);
    await tester.pumpAndSettle();

    expect(find.byType(RiscvCommitLandingBanner), findsOneWidget);
    expect(find.textContaining('insn_sub_ch0'), findsOneWidget);
    // "step 7 of 20" — the depth_configured attribute rendered as the plan
    // asked for it.
    expect(find.textContaining('step 7 of 20'), findsOneWidget);
    expect(find.textContaining('rvfi_order 3'), findsOneWidget);
    expect(find.textContaining('rv32i'), findsOneWidget);
  });

  testWidgets('falls back to a bare step when no depth was reported', (
    tester,
  ) async {
    final container = await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
    );
    _recordFormalLanding(
      container,
      time: fixture.source.endTime,
      withDepth: false,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('step 7'), findsOneWidget);
    expect(find.textContaining('of 20'), findsNothing);
  });

  testWidgets('labels a replayed demo fixture as replayed', (tester) async {
    // The provenance rule this whole initiative is built on: a coordinate
    // marked `riscv.mode = demo` came from a committed fixture, and the one
    // surface that repeats the sender's claims must never let it read as a
    // measured solver run.
    final container = await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
    );
    _recordFormalLanding(
      container,
      time: fixture.source.endTime,
      mode: RiscvCoordinateAttributes.demoMode,
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        L10N
            .of(tester.element(find.byType(RiscvCommitLandingBanner)))
            .riscvCommitLandingReplayed,
      ),
      findsOneWidget,
    );
  });

  testWidgets('says nothing about replay when the run was live', (
    tester,
  ) async {
    final container = await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
    );
    _recordFormalLanding(container, time: fixture.source.endTime);
    await tester.pumpAndSettle();
    final l10n = L10N.of(
      tester.element(find.byType(RiscvCommitLandingBanner)),
    );
    expect(find.text(l10n.riscvCommitLandingReplayed), findsNothing);
  });

  testWidgets('accounts for a panel the cross-probe mounted', (tester) async {
    // A Stage panel that appears without the user adding it needs to say who
    // added it. This line is the only place that can.
    final container = await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
    );
    _recordFormalLanding(
      container,
      time: fixture.source.endTime,
      autoMounted: true,
    );
    await tester.pumpAndSettle();
    final l10n = L10N.of(
      tester.element(find.byType(RiscvCommitLandingBanner)),
    );
    expect(find.text(l10n.riscvCommitLandingAutoMounted), findsOneWidget);
  });

  testWidgets('claims nothing when the user already had the inspector open', (
    tester,
  ) async {
    // The default, and the one that must never over-claim: a landing into an
    // inspector the user opened themselves rearranged nothing.
    final container = await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
    );
    _recordFormalLanding(container, time: fixture.source.endTime);
    await tester.pumpAndSettle();
    final l10n = L10N.of(
      tester.element(find.byType(RiscvCommitLandingBanner)),
    );
    expect(find.text(l10n.riscvCommitLandingAutoMounted), findsNothing);
  });

  testWidgets('says so when the step held no retirement', (tester) async {
    final container = await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
    );
    _recordFormalLanding(
      container,
      time: fixture.source.endTime,
      order: null,
    );
    await tester.pumpAndSettle();
    final l10n = L10N.of(
      tester.element(find.byType(RiscvCommitLandingBanner)),
    );
    expect(find.text(l10n.riscvCommitLandingNoRetirement), findsOneWidget);
    // …and no retirement index is claimed.
    expect(find.textContaining('rvfi_order'), findsNothing);
  });

  testWidgets('renders the normative retire binding by its own index', (
    tester,
  ) async {
    final container = await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
    );
    container
        .read(riscvCommitLandingProvider.notifier)
        .record(
          streamId: CxpStreamCoordinate.riscvRvfiRetireStreamId,
          sequenceIndex: 4,
          time: fixture.source.endTime,
          order: 4,
        );
    await tester.pumpAndSettle();
    expect(find.textContaining('rvfi_order 4'), findsOneWidget);
    // A retire coordinate carries no bounded-proof step, so none is shown.
    expect(find.textContaining('step'), findsNothing);
  });

  testWidgets('dismissing hides the caption without moving the cursor', (
    tester,
  ) async {
    final container = await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
    );
    _recordFormalLanding(container, time: fixture.source.endTime);
    await tester.pumpAndSettle();
    expect(find.byType(RiscvCommitLandingBanner), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(RiscvCommitLandingBanner), findsNothing);
    expect(container.read(riscvCommitLandingProvider), isNull);
  });

  testWidgets('a new waveform clears a landing measured in the old one', (
    tester,
  ) async {
    final container = await pumpRiscvCommit(
      tester,
      fixture: fixture,
      instance: riscvCommitInstance(fixture),
    );
    _recordFormalLanding(container, time: fixture.source.endTime);
    expect(container.read(riscvCommitLandingProvider), isNotNull);
    // A landing is a statement about ONE trace. Captioning a different file
    // with the old file's proof is the stale claim this substrate refuses.
    container.read(riscvCommitLandingProvider.notifier).clear();
    await tester.pumpAndSettle();
    expect(find.byType(RiscvCommitLandingBanner), findsNothing);
  });

  group('locale sweep', () {
    for (final locale in _locales) {
      testWidgets('the landing banner is translated in $locale', (
        tester,
      ) async {
        final container = await pumpRiscvCommit(
          tester,
          fixture: fixture,
          instance: riscvCommitInstance(fixture),
          locale: locale,
        );
        _recordFormalLanding(
          container,
          time: fixture.source.endTime,
          order: null,
          mode: RiscvCoordinateAttributes.demoMode,
          autoMounted: true,
        );
        await tester.pumpAndSettle();
        final l10n = L10N.of(
          tester.element(find.byType(RiscvCommitLandingBanner)),
        );
        for (final text in [
          l10n.riscvCommitLandingTitle,
          l10n.riscvCommitLandingNoRetirement,
          l10n.riscvCommitLandingAutoMounted,
          l10n.riscvCommitLandingReplayed,
        ]) {
          expect(text, isNotEmpty);
          expect(text, isNot(startsWith('riscvCommitLanding')));
          expect(find.text(text), findsOneWidget, reason: '$locale: $text');
        }
      });
    }
  });
}
