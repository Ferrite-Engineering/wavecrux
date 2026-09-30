// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// A Stage widget body made of fixed chrome wrapped around one growable child,
/// laid out so that shrinking the instance never clips anything.
///
/// Stage instances are user-resizable by design and the resizer clamps only to
/// the widget's declared `minSize` — and nothing clamps a rect that arrives in
/// a session file, so "small" has no hard floor. The obvious shape, a `Column`
/// of fixed rows plus an `Expanded`, does not survive that: once the fixed rows
/// are taller than the box it overflows.
///
/// An overflow is a loud striped banner in a debug build and **nothing at all**
/// in a release build, where the content is simply clipped. For the widgets in
/// the RISC-V family — whose entire job is reporting correctness figures — a
/// number quietly cut off the bottom is the one failure mode they must not
/// have. So this widget never clips: when there is not enough room, the body
/// scrolls and everything stays reachable.
///
/// Two layouts, chosen on the available height:
///
/// * **Roomy** (`maxHeight >= chromeHeight + minChildHeight`) — exactly the
///   `Column` it replaces: fixed chrome, [child] in an `Expanded`.
/// * **Tight** — the whole body scrolls and [child] is pinned to
///   [minChildHeight].
///
/// [chromeHeight] is a threshold, not a measurement. It should be an upper
/// bound on how tall [leading] plus [trailing] get at the widget's *declared
/// minimum width* — chrome that wraps gets taller as the panel narrows, and
/// erring high only means the body starts scrolling a little sooner than it
/// strictly had to. Erring low is the bug this widget exists to prevent, so
/// the family's shrink test pins every value here.
class StageResizableBody extends StatelessWidget {
  const StageResizableBody({
    required this.chromeHeight,
    required this.minChildHeight,
    required this.leading,
    required this.child,
    this.trailing = const <Widget>[],
    super.key,
  });

  /// Upper bound on the combined height of [leading] and [trailing].
  final double chromeHeight;

  /// The least height worth giving [child] before the body starts scrolling.
  final double minChildHeight;

  /// Fixed chrome above [child].
  final List<Widget> leading;

  /// The one child that takes the leftover height.
  final Widget child;

  /// Fixed chrome below [child].
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // An unbounded height is never "roomy": `Expanded` has nothing to
      // divide up there and would throw.
      final bounded = constraints.maxHeight.isFinite;
      final roomy =
          bounded && constraints.maxHeight >= chromeHeight + minChildHeight;
      final column = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: roomy ? MainAxisSize.max : MainAxisSize.min,
        children: [
          ...leading,
          if (roomy)
            Expanded(child: child)
          else
            SizedBox(height: minChildHeight, child: child),
          ...trailing,
        ],
      );
      return roomy || !bounded ? column : SingleChildScrollView(child: column);
    },
  );
}
