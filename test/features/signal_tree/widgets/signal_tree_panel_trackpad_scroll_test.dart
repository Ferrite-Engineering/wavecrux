// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// LOCALE_SWEEP_EXEMPT: pure gesture-math test (trackpad pan-zoom scroll-
// offset assertions). No text is rendered or asserted; the tree's row
// content (scope names) is not locale-sensitive.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/app.dart' show kAppScrollDragDevices;
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// The signal tree (SST) is a bare [ListView] and therefore relies on the
/// app-wide [kAppScrollDragDevices] (which includes `trackpad`) to scroll under
/// a two-finger trackpad pan-zoom. This test reproduces that composition and
/// asserts the tree actually scrolls — the regression that shipped as "the
/// signal list won't two-finger scroll, only the scrollbar works" on macOS.
Scope _scope(int i) => Scope(
  name: 'mod_$i',
  type: ScopeType.module,
  path: 'top.mod_$i',
);

Widget _wrap(List<Scope> scopes) => ProviderScope(
  overrides: [hierarchyProvider.overrideWith((_) => AsyncData(scopes))],
  child: MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    // Mirror the app's root ScrollConfiguration so the ListView inherits the
    // trackpad-inclusive dragDevices, exactly like the running app.
    home: ScrollConfiguration(
      behavior: const MaterialScrollBehavior().copyWith(
        dragDevices: kAppScrollDragDevices,
      ),
      child: const Scaffold(
        // Constrain height so the scope list overflows and is scrollable.
        body: SizedBox(height: 260, width: 280, child: SignalTreePanel()),
      ),
    ),
  ),
);

void main() {
  testWidgets('SST scrolls under a two-finger trackpad pan-zoom', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap([for (var i = 0; i < 60; i++) _scope(i)]));
    await tester.pumpAndSettle();

    // Target the ListView's own Scrollable — not the header search field's
    // internal EditableText Scrollable, which `.first` would otherwise match.
    final scrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    double offset() =>
        tester.state<ScrollableState>(scrollable.first).position.pixels;

    expect(offset(), 0);

    // Two-finger trackpad swipe up = a stream of PointerPanZoom updates with a
    // (cumulative) negative vertical pan → scrolls the list down.
    final center = tester.getCenter(find.byType(SignalTreePanel));
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    await tester.pump();
    for (var dy = -40.0; dy >= -200; dy -= 40) {
      await tester.sendEventToBinding(
        pointer.panZoomUpdate(center, pan: Offset(0, dy)),
      );
      await tester.pump();
    }
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pump();

    expect(
      offset(),
      greaterThan(0),
      reason: 'trackpad pan-zoom must scroll the signal tree',
    );
  });

  testWidgets('SST does NOT scroll on trackpad when dragDevices omit it', (
    tester,
  ) async {
    // Control: the pre-fix configuration ({ touch } only) leaves the tree
    // un-scrollable by trackpad — proving the dragDevices set is what matters.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hierarchyProvider.overrideWith(
            (_) => AsyncData([for (var i = 0; i < 60; i++) _scope(i)]),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: ScrollConfiguration(
            behavior: const MaterialScrollBehavior().copyWith(
              dragDevices: const {PointerDeviceKind.touch},
            ),
            child: const Scaffold(
              body: SizedBox(height: 260, width: 280, child: SignalTreePanel()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Target the ListView's own Scrollable — not the header search field's
    // internal EditableText Scrollable, which `.first` would otherwise match.
    final scrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    double offset() =>
        tester.state<ScrollableState>(scrollable.first).position.pixels;

    final center = tester.getCenter(find.byType(SignalTreePanel));
    final pointer = TestPointer(1, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(pointer.panZoomStart(center));
    await tester.pump();
    await tester.sendEventToBinding(
      pointer.panZoomUpdate(center, pan: const Offset(0, -100)),
    );
    await tester.pump();
    await tester.sendEventToBinding(pointer.panZoomEnd());
    await tester.pump();

    expect(offset(), 0, reason: 'without trackpad in dragDevices it stays put');
  });
}
