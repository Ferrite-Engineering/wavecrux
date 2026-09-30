// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_views.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';

import '../../../../helpers/generated_vcd_fixture.dart';
import '_riscv_commit_harness.dart';

/// Every locale the suite ships. Every user-visible surface sweeps all of
/// them; `zh` mirrors `zh_CN` and is covered by the same ARB.
const List<Locale> _locales = [
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  late GeneratedVcdFixture fixture;

  setUp(() {
    fixture = GeneratedVcdFixture.load(cleanRvfiFixture);
  });

  group('binding states', () {
    testWidgets('unbound instance explains how to bind', (tester) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: const StageInstance(
          id: 'rvfi0',
          widgetId: RiscvCommitStageWidget.widgetId,
        ),
      );
      expect(find.textContaining('rvfi_*'), findsOneWidget);
    });

    testWidgets('missing a required channel names the missing one', (
      tester,
    ) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(
          fixture,
          omit: const {RvfiChannel.pcRdata},
        ),
      );
      expect(find.textContaining('rvfi_pc_rdata'), findsOneWidget);
    });

    testWidgets('a fully bound instance reports 21 of 21 channels', (
      tester,
    ) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(fixture),
      );
      expect(
        find.text(
          '${RvfiChannel.values.length} of '
          '${RvfiChannel.values.length} RVFI channels bound',
        ),
        findsOneWidget,
      );
    });
  });

  group('commit log', () {
    testWidgets('shows the retired instructions with real operand values', (
      tester,
    ) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(fixture),
      );
      expect(find.text('addi t0, zero, 5'), findsOneWidget);
      expect(find.text('add t2, t0, t1'), findsOneWidget);
      expect(find.text('sw t2, 0(sp)'), findsOneWidget);
      // Real value, ABI-named destination — not an inference from RF ports.
      expect(find.textContaining('t0 = 0x0000_0005'), findsOneWidget);
      // The store's memory effect renders on its row.
      expect(find.textContaining('[0x0000_1000] ← 0x0000_000c'), findsWidgets);
    });

    testWidgets('numeric naming renames the destination register', (
      tester,
    ) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(
          fixture,
          configuration: const {
            RiscvCommitStageWidget.paramRegisterNaming: 'numeric',
          },
        ),
      );
      expect(find.textContaining('x5 = 0x0000_0005'), findsOneWidget);
      expect(find.textContaining('t0 = 0x0000_0005'), findsNothing);
    });

    testWidgets('shows nothing retired before the first retirement', (
      tester,
    ) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(fixture),
        cursorTime: 0,
      );
      expect(
        find.text('No instruction has retired at or before the cursor.'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a commit row moves the cursor to that retirement', (
      tester,
    ) async {
      final container = await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(fixture),
      );
      await tester.tap(find.text('addi t0, zero, 5'));
      await tester.pumpAndSettle();
      expect(container.read(cursorStateProvider).primaryCursorTime, 4);
    });
  });

  group('register file', () {
    testWidgets('reconstructs the architectural state at the cursor', (
      tester,
    ) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(fixture),
      );
      await _tapTab(tester, 'Registers');
      // t0 = 5, t1 = 7, t2 = 12, s0 = 12 by the end of the program.
      expect(find.text('t0'), findsOneWidget);
      expect(find.text('0x0000_0005'), findsWidgets);
      expect(find.text('0x0000_000c'), findsWidgets);
      // x0 always reads zero; an unwritten register reads em-dash, not zero.
      expect(find.text('zero'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('says so when the destination channels are unbound', (
      tester,
    ) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(
          fixture,
          omit: const {RvfiChannel.rdAddr, RvfiChannel.rdWdata},
        ),
      );
      await _tapTab(tester, 'Registers');
      expect(
        find.textContaining('Bind rvfi_rd_addr and rvfi_rd_wdata'),
        findsOneWidget,
      );
    });
  });

  group('memory log', () {
    testWidgets('lists the store and the load', (tester) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(fixture),
      );
      await _tapTab(tester, 'Memory');
      expect(find.text('write'), findsOneWidget);
      expect(find.text('read'), findsOneWidget);
      expect(find.text('4 bytes'), findsNWidgets(2));
    });

    testWidgets('says so when the memory channels are unbound', (tester) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(
          fixture,
          omit: const {
            RvfiChannel.memAddr,
            RvfiChannel.memRmask,
            RvfiChannel.memWmask,
            RvfiChannel.memRdata,
            RvfiChannel.memWdata,
          },
        ),
      );
      await _tapTab(tester, 'Memory');
      expect(find.textContaining('rvfi_mem_*'), findsWidgets);
    });
  });

  group('trap log', () {
    testWidgets('lists the trapping ecall with its privilege', (tester) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(fixture),
      );
      await _tapTab(tester, 'Traps');
      expect(find.text('Trap'), findsOneWidget);
      expect(find.text('privilege M'), findsOneWidget);
    });

    testWidgets('says so when no trap channel is bound', (tester) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(
          fixture,
          omit: const {
            RvfiChannel.trap,
            RvfiChannel.intr,
            RvfiChannel.halt,
          },
        ),
      );
      await _tapTab(tester, 'Traps');
      expect(find.textContaining('Bind rvfi_trap'), findsOneWidget);
    });
  });

  group('consistency checker', () {
    testWidgets('the clean fixture reports a clean result', (tester) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(fixture),
      );
      await _tapTab(tester, 'Checks');
      expect(
        find.text('8 retirements checked, no inconsistency found.'),
        findsOneWidget,
      );
      // No error badge on the Checks tab when nothing fired.
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    testWidgets('a corrupted fixture renders a specific, actionable message', (
      tester,
    ) async {
      final bad = GeneratedVcdFixture.load(
        '$riscvFixtureDir/riscv_rvfi_bad_mem_mask.vcd',
      );
      await pumpRiscvCommit(
        tester,
        fixture: bad,
        instance: riscvCommitInstance(bad),
      );
      await _tapTab(tester, 'Checks');
      expect(find.text('Memory access'), findsOneWidget);
      expect(
        find.textContaining('accesses 4 bytes'),
        findsOneWidget,
      );
      expect(find.textContaining('masks cover 2'), findsOneWidget);
    });

    testWidgets('violations render inline on the offending commit row', (
      tester,
    ) async {
      final bad = GeneratedVcdFixture.load(
        '$riscvFixtureDir/riscv_rvfi_bad_x0_write.vcd',
      );
      await pumpRiscvCommit(
        tester,
        fixture: bad,
        instance: riscvCommitInstance(bad),
      );
      // Still on the commit log — the message shows there, not only in a
      // separate report tab.
      expect(
        find.textContaining('x0 is hardwired zero'),
        findsOneWidget,
      );
    });

    testWidgets('clicking a violation moves the cursor to the offending '
        'retirement', (tester) async {
      final bad = GeneratedVcdFixture.load(
        '$riscvFixtureDir/riscv_rvfi_bad_trap.vcd',
      );
      final container = await pumpRiscvCommit(
        tester,
        fixture: bad,
        instance: riscvCommitInstance(bad),
      );
      await _tapTab(tester, 'Checks');
      await tester.tap(find.textContaining('the sequential next PC'));
      await tester.pumpAndSettle();
      // The trapping ecall retires in cycle 11 → tick 4 + 11*10 = 114.
      expect(container.read(cursorStateProvider).primaryCursorTime, 114);
    });

    testWidgets('the Checks tab carries an error count when a rule fires', (
      tester,
    ) async {
      final bad = GeneratedVcdFixture.load(
        '$riscvFixtureDir/riscv_rvfi_bad_order.vcd',
      );
      await pumpRiscvCommit(
        tester,
        fixture: bad,
        instance: riscvCommitInstance(bad),
      );
      expect(find.byIcon(Icons.error_outline), findsWidgets);
    });
  });

  group('reduced binding set — degrade, do not refuse', () {
    /// Exactly the reduced set: retire valid + pc + insn + rd.
    Set<RvfiChannel> reducedOmissions() => {
      for (final c in RvfiChannel.values)
        if (!c.isReducedSetMember) c,
    };

    testWidgets('still renders a commit log', (tester) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(fixture, omit: reducedOmissions()),
      );
      expect(find.text('addi t0, zero, 5'), findsOneWidget);
    });

    testWidgets('says which channels are missing', (tester) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(fixture, omit: reducedOmissions()),
      );
      expect(find.textContaining('Reduced binding set'), findsOneWidget);
      expect(find.textContaining('rvfi_mem_addr'), findsOneWidget);
    });

    testWidgets('names the checks that could not run', (tester) async {
      await pumpRiscvCommit(
        tester,
        fixture: fixture,
        instance: riscvCommitInstance(fixture, omit: reducedOmissions()),
      );
      await _tapTab(tester, 'Checks');
      expect(
        find.textContaining('Not checked'),
        findsOneWidget,
        reason:
            'a quiet result from a rule that never ran is the one way this '
            'widget could mislead someone',
      );
      expect(find.textContaining('Control-flow continuity'), findsOneWidget);
      expect(find.textContaining('Retirement order'), findsOneWidget);
    });
  });

  group('touch targets', () {
    testWidgets('every tappable row and tab is at least 44 dp tall', (
      tester,
    ) async {
      final bad = GeneratedVcdFixture.load(
        '$riscvFixtureDir/riscv_rvfi_bad_rd_addr.vcd',
      );
      await pumpRiscvCommit(
        tester,
        fixture: bad,
        instance: riscvCommitInstance(bad),
      );
      for (final tab in ['Commits', 'Registers', 'Memory', 'Traps', 'Checks']) {
        await _tapTab(tester, tab);
        for (final element in find.byType(InkWell).evaluate()) {
          final size = tester.getSize(find.byWidget(element.widget));
          expect(
            size.height,
            greaterThanOrEqualTo(kRiscvCommitTouchTarget),
            reason: 'a tappable row in the $tab view is ${size.height} dp tall',
          );
        }
      }
    });
  });

  group('locale sweep', () {
    for (final locale in _locales) {
      testWidgets('renders every view in $locale', (tester) async {
        final bad = GeneratedVcdFixture.load(
          '$riscvFixtureDir/riscv_rvfi_bad_pc_wdata.vcd',
        );
        await pumpRiscvCommit(
          tester,
          fixture: bad,
          instance: riscvCommitInstance(bad),
          locale: locale,
        );
        expect(tester.takeException(), isNull);

        final l10n = await L10N.delegate.load(locale);
        for (final tab in [
          l10n.riscvCommitTabCommits,
          l10n.riscvCommitTabRegisters,
          l10n.riscvCommitTabMemory,
          l10n.riscvCommitTabTraps,
          l10n.riscvCommitTabChecks,
        ]) {
          expect(find.text(tab), findsOneWidget, reason: '$locale: $tab');
          await _tapTab(tester, tab);
          expect(tester.takeException(), isNull, reason: '$locale: $tab');
        }
        // The violation message is localized, not left in English.
        expect(
          find.textContaining(l10n.riscvCommitRuleControlFlow),
          findsWidgets,
        );
      });
    }
  });
}
