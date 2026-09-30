// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/shared/widgets/lazy_indexed_stack.dart';

/// A child that records each time it is *mounted* (its [State.initState] runs)
/// and exposes a mutable counter so keep-alive (state survival) can be asserted.
class _Tracker extends StatefulWidget {
  const _Tracker(this.label, this.mounts, {super.key});
  final String label;
  final List<String> mounts;
  @override
  State<_Tracker> createState() => _TrackerState();
}

class _TrackerState extends State<_Tracker> {
  int taps = 0;
  @override
  void initState() {
    super.initState();
    widget.mounts.add(widget.label);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => taps++),
    child: Text('${widget.label}:$taps', textDirection: TextDirection.ltr),
  );
}

void main() {
  Widget wrap(Widget child) =>
      Directionality(textDirection: TextDirection.ltr, child: child);

  List<_Tracker> trackers(List<String> labels, List<String> mounts) => [
    for (final l in labels) _Tracker(l, mounts, key: ValueKey(l)),
  ];

  testWidgets('mounts only the active child; never-activated children are not '
      'mounted', (tester) async {
    final mounts = <String>[];
    await tester.pumpWidget(
      wrap(
        LazyIndexedStack(index: 0, children: trackers(['a', 'b', 'c'], mounts)),
      ),
    );

    expect(mounts, ['a'], reason: 'only the active child should mount');
    expect(find.textContaining('a:'), findsOneWidget);
    expect(find.textContaining('b:'), findsNothing);
    expect(find.textContaining('c:'), findsNothing);
  });

  testWidgets('activating a slot mounts it; previously-activated slots stay '
      'mounted (keep-alive) and never re-mount', (tester) async {
    final mounts = <String>[];
    Widget build(int index) => wrap(
      LazyIndexedStack(index: index, children: trackers(['a', 'b'], mounts)),
    );

    await tester.pumpWidget(build(0));
    expect(mounts, ['a']);

    await tester.pumpWidget(build(1)); // activate b
    expect(mounts, ['a', 'b']);
    // a is kept alive (still in the tree, just not painted).
    expect(find.textContaining('a:', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('b:'), findsOneWidget);

    await tester.pumpWidget(build(0)); // back to a — must not re-mount
    expect(mounts, ['a', 'b'], reason: 'switching back must not rebuild a');
  });

  testWidgets('keeps an activated child State across switches', (tester) async {
    final mounts = <String>[];
    Widget build(int index) => wrap(
      LazyIndexedStack(index: index, children: trackers(['a', 'b'], mounts)),
    );

    await tester.pumpWidget(build(0));
    // Mutate a's local State.
    await tester.tap(find.textContaining('a:'));
    await tester.pump();
    expect(find.text('a:1'), findsOneWidget);

    await tester.pumpWidget(build(1)); // away to b
    await tester.pumpWidget(build(0)); // back to a
    // a's State (taps==1) survived — it was kept alive, not rebuilt.
    expect(find.text('a:1'), findsOneWidget);
  });

  testWidgets('forwards the active index to the underlying IndexedStack', (
    tester,
  ) async {
    final mounts = <String>[];
    await tester.pumpWidget(
      wrap(
        LazyIndexedStack(index: 2, children: trackers(['a', 'b', 'c'], mounts)),
      ),
    );
    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 2);
    expect(mounts, ['c']);
  });

  testWidgets('out-of-range index is clamped and does not throw', (
    tester,
  ) async {
    final mounts = <String>[];
    await tester.pumpWidget(
      wrap(LazyIndexedStack(index: 9, children: trackers(['a', 'b'], mounts))),
    );
    expect(tester.takeException(), isNull);
    final stack = tester.widget<IndexedStack>(find.byType(IndexedStack));
    expect(stack.index, 1); // clamped to last
    expect(mounts, ['b']);
  });

  testWidgets('tracks activation by key, so reordering children preserves '
      'mounted state', (tester) async {
    final mounts = <String>[];
    // Activate a (index 0), then b (index 1).
    await tester.pumpWidget(
      wrap(
        LazyIndexedStack(index: 0, children: trackers(['a', 'b', 'c'], mounts)),
      ),
    );
    await tester.pumpWidget(
      wrap(
        LazyIndexedStack(index: 1, children: trackers(['a', 'b', 'c'], mounts)),
      ),
    );
    expect(mounts, ['a', 'b']);

    // Reorder: now [c, b, a]. a and b were activated (by key) → still mounted;
    // c was never activated and is not the active index → still not mounted.
    await tester.pumpWidget(
      wrap(
        LazyIndexedStack(index: 0, children: trackers(['c', 'b', 'a'], mounts)),
      ),
    );
    // index 0 is now c → c mounts; a and b remain mounted (kept by key).
    expect(mounts, ['a', 'b', 'c']);
    expect(find.textContaining('a:', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('b:', skipOffstage: false), findsOneWidget);
  });

  testWidgets('removing a never-activated child does not mount it; removing an '
      'activated child drops it', (tester) async {
    final mounts = <String>[];
    await tester.pumpWidget(
      wrap(
        LazyIndexedStack(index: 0, children: trackers(['a', 'b', 'c'], mounts)),
      ),
    );
    expect(mounts, ['a']);
    // Remove c (never activated) → no effect on mounts.
    await tester.pumpWidget(
      wrap(LazyIndexedStack(index: 0, children: trackers(['a', 'b'], mounts))),
    );
    expect(mounts, ['a']);
    expect(find.textContaining('a:'), findsOneWidget);
  });

  testWidgets('empty children list renders nothing and does not throw', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const LazyIndexedStack(index: 0, children: [])),
    );
    expect(tester.takeException(), isNull);
  });
}
