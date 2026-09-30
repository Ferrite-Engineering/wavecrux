// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: pure layout/visibility regression test (restore
// bars appear for hidden regions and reopen them); renders icons and
// keys, no localized copy is asserted.
import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/widgets/dock_restore_bars.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceClassProvider.overrideWithValue(DeviceClass.desktop),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return WaveCruxDockRestoreBars(
                  onLoadStems: () {},
                  child: const ColoredBox(
                    color: Colors.black,
                    child: Center(child: Text('CENTER')),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('visible regions render no restore bars', (tester) async {
    final container = await pump(tester);
    final layout = container.read(panelLayoutProvider);
    // Defaults: signal tree + value column visible; transactions hidden or
    // visible depending on defaults — normalize to all-visible first.
    container.read(panelLayoutProvider.notifier)
      ..setSignalTreeVisible(visible: true)
      ..setValueColumnVisible(visible: true)
      ..setTransactionViewVisible(visible: true);
    await tester.pump();
    expect(find.byType(CruxDockRestoreBar), findsNothing);
    expect(layout, isNotNull);
  });

  testWidgets('hiding all three regions leaves three restore bars, and a '
      'tap restores that region on that tab', (tester) async {
    final container = await pump(tester);
    container.read(panelLayoutProvider.notifier)
      ..setSignalTreeVisible(visible: false)
      ..setValueColumnVisible(visible: false)
      ..setTransactionViewVisible(visible: false);
    await tester.pump();
    expect(find.byType(CruxDockRestoreBar), findsNWidgets(3));

    // Restore the bottom region via the pinned Transactions entry.
    await tester.tap(
      find.byKey(const ValueKey('cruxDockRestore-transactions')),
    );
    await tester.pump();
    expect(
      container.read(panelLayoutProvider).transactionViewVisible,
      isTrue,
    );
    expect(find.byType(CruxDockRestoreBar), findsNWidgets(2));
  });

  testWidgets('a bar appearing or vanishing keeps the wrapped layout mounted', (
    tester,
  ) async {
    // The wrapper used to pick a different widget type for each combination
    // of collapsed regions, so every dock toggle rebuilt the whole IDE layout
    // beneath it. With a screen reader attached that rebuild tripped the
    // framework's semantics assertion, because the canvas came back through
    // a GlobalKey. Every transition below, including several regions flipping
    // in the same frame, must leave the child's element where it is.
    final container = await pump(tester);
    final notifier = container.read(panelLayoutProvider.notifier)
      ..setSignalTreeVisible(visible: true)
      ..setValueColumnVisible(visible: true)
      ..setTransactionViewVisible(visible: true);
    await tester.pump();
    final center = tester.element(find.text('CENTER'));

    final combinations = [
      for (final left in [true, false])
        for (final right in [true, false])
          for (final bottom in [true, false]) (left, right, bottom),
    ];
    for (final (left, right, bottom) in [
      ...combinations,
      ...combinations.reversed,
    ]) {
      notifier
        ..setSignalTreeVisible(visible: left)
        ..setValueColumnVisible(visible: right)
        ..setTransactionViewVisible(visible: bottom);
      await tester.pump();
      expect(
        find.byType(CruxDockRestoreBar),
        findsNWidgets([left, right, bottom].where((v) => !v).length),
      );
      expect(
        tester.element(find.text('CENTER')),
        same(center),
        reason: 'left=$left right=$right bottom=$bottom rebuilt the child',
      );
    }
  });
}
