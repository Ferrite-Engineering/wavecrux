// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/signal_tree/utils/signal_tree_rows.dart';
import 'package:wavecrux/features/signal_tree/widgets/signal_tree_menu_anchor.dart';

void main() {
  test('a pointer menu is anchored at the pointer', () {
    expect(
      signalTreePointerMenuAnchor(const Offset(40, 70)),
      const RelativeRect.fromLTRB(40, 70, 41, 71),
    );
  });

  testWidgets('a keyboard menu is anchored over the row, after scrolling', (
    tester,
  ) async {
    final listKey = GlobalKey();
    final overlayKey = GlobalKey();
    tester.view
      ..physicalSize = const Size(800, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          key: overlayKey,
          width: 800,
          height: 600,
          child: Padding(
            padding: const EdgeInsets.only(left: 30, top: 100),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(key: listKey, width: 300, height: 400),
            ),
          ),
        ),
      ),
    );

    final list = tester.renderObject<RenderBox>(find.byKey(listKey));
    final overlay = tester.renderObject<RenderBox>(find.byKey(overlayKey));

    final anchor = signalTreeRowMenuAnchor(
      list: list,
      overlay: overlay,
      index: 5,
      scrollOffset: 2 * kSignalTreeRowHeight,
    );

    // Row 5 with two rows scrolled away sits three rows below the list top.
    const top = 100 + 3 * kSignalTreeRowHeight;
    expect(
      anchor,
      RelativeRect.fromRect(
        const Rect.fromLTWH(30, top, 300, kSignalTreeRowHeight),
        const Rect.fromLTWH(0, 0, 800, 600),
      ),
    );
  });
}
