// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/rendering.dart';
import 'package:wavecrux/features/signal_tree/utils/signal_tree_rows.dart';

/// Where a row's context menu opens when a right-click or long-press asks for
/// it: at the pointer.
RelativeRect signalTreePointerMenuAnchor(Offset globalPosition) =>
    RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      globalPosition.dx + 1,
      globalPosition.dy + 1,
    );

/// Where a row's context menu opens when the keyboard asks for it: over the
/// row at [index] of the tree's list.
///
/// [list] is the render box of the list's viewport and [overlay] the box the
/// menu is positioned in. The row's rect is computed from the list's fixed row
/// height and [scrollOffset] rather than from the row's own render object,
/// which the lazy list may not have built. Returns null before layout.
RelativeRect? signalTreeRowMenuAnchor({
  required RenderBox list,
  required RenderBox overlay,
  required int index,
  required double scrollOffset,
}) {
  if (!list.hasSize || !overlay.hasSize) return null;
  final top = index * kSignalTreeRowHeight - scrollOffset;
  final origin = list.localToGlobal(Offset(0, top), ancestor: overlay);
  final row = origin & Size(list.size.width, kSignalTreeRowHeight);
  return RelativeRect.fromRect(row, Offset.zero & overlay.size);
}
