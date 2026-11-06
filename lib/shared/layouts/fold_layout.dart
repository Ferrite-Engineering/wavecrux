// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show Rect;

/// The waveform needs at least this much height above a tabletop crease.
const double kTabletopMinUpperHeight = 120;

/// The bottom dock needs at least this much height below a tabletop crease.
const double kTabletopMinLowerHeight = 80;

/// How the viewer's dock area splits around a horizontal (tabletop) crease.
typedef TabletopSplit = ({double bottomSize, double inset});

/// The bottom-dock height that puts the dock boundary on the crease's centre
/// line, and the inset each side keeps clear of the crease band.
///
/// [crease] is in the dock area's own coordinates and [height] is that
/// area's height. Null (lay out as usual) when there is no crease, when it
/// runs vertically, or when either side would be too short to use, which is
/// what happens if the dock area does not straddle the fold at all.
TabletopSplit? tabletopSplit(Rect? crease, double height) {
  if (crease == null || crease.width < crease.height) return null;
  final centre = crease.center.dy;
  final inset = crease.height / 2;
  final bottomSize = height - centre;
  if (centre - inset < kTabletopMinUpperHeight) return null;
  if (bottomSize - inset < kTabletopMinLowerHeight) return null;
  return (bottomSize: bottomSize, inset: inset);
}

/// A side-by-side pane needs at least this much width beside a book crease.
const double kBookMinPaneWidth = 200;

/// How a two-pane row splits around a vertical (book) crease.
typedef BookSplit = ({double leftWidth, double gap, double rightWidth});

/// Widths that put each pane on its own side of a vertical crease, with the
/// crease band as the gap between them.
///
/// [crease] is in the row's coordinates and [width] is the row's width. Null
/// (keep the user's split) when there is no crease, it runs horizontally, or
/// either pane would be narrower than [kBookMinPaneWidth].
BookSplit? bookSplit(Rect? crease, double width) {
  if (crease == null || crease.height < crease.width) return null;
  final left = crease.left;
  final right = width - crease.right;
  if (left < kBookMinPaneWidth || right < kBookMinPaneWidth) return null;
  return (leftWidth: left, gap: crease.width, rightWidth: right);
}
