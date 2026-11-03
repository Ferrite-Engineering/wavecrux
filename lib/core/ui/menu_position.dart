// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// Where a `showMenu` call places a menu, so it opens where the user asked.
///
/// Each file tab has its own `Navigator`, whose overlay starts below the
/// toolbar and tab bar. `showMenu` lays its menu out in the overlay of the
/// navigator it pushes onto, so a position in global coordinates handed to
/// the nearest navigator's menu lands that offset too low. These helpers
/// resolve positions against the root overlay, and the call must then push
/// onto the root navigator: use [showRootMenu], which does both. The root
/// overlay is itself offset when a strip sits above the navigator, so a
/// position is converted with `globalToLocal` rather than used as is.

/// The root overlay's render box, the one a menu pushed onto the root
/// navigator is laid out in. Null before it has been laid out.
RenderBox? rootOverlayBox(BuildContext context) {
  final box = Overlay.maybeOf(
    context,
    rootOverlay: true,
  )?.context.findRenderObject();
  return box is RenderBox && box.hasSize ? box : null;
}

/// The position of a menu that opens with its top-left corner at the global
/// [rect]'s top-left, laid out in the root overlay.
///
/// Returns null before the root overlay has been laid out.
RelativeRect? rootMenuPositionForRect(BuildContext context, Rect rect) {
  final overlay = rootOverlayBox(context);
  if (overlay == null) return null;
  final local = Rect.fromPoints(
    overlay.globalToLocal(rect.topLeft),
    overlay.globalToLocal(rect.bottomRight),
  );
  return RelativeRect.fromRect(local, Offset.zero & overlay.size);
}

/// The position of a menu that opens at the global point [globalPosition],
/// laid out in the root overlay.
///
/// Returns null before the root overlay has been laid out.
RelativeRect? rootMenuPositionForPoint(
  BuildContext context,
  Offset globalPosition,
) => rootMenuPositionForRect(context, globalPosition & const Size(1, 1));

/// The position of a menu anchored at [box], a widget's own render box
/// (a button, say): it opens over the box, laid out in the root overlay.
///
/// Returns null when [box] has no size yet or is detached.
RelativeRect? rootMenuPositionForBox(BuildContext context, RenderBox box) {
  if (!box.attached || !box.hasSize) return null;
  return rootMenuPositionForRect(
    context,
    box.localToGlobal(Offset.zero) & box.size,
  );
}

/// `showMenu` on the root navigator, with [position] already resolved
/// against the root overlay by one of the helpers above.
Future<T?> showRootMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
}) => showMenu<T>(
  context: context,
  position: position,
  items: items,
  useRootNavigator: true,
);
