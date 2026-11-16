// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/fold_state.dart';
import 'package:wavecrux/shared/layouts/fold_state_provider.dart';

/// Keeps a bar's content clear of a camera the hardware puts on the screen,
/// while its [decoration] still runs to the screen edge.
///
/// Meant for a bar at the top of the screen (the viewer's toolbar). On the
/// iPhone Duo's cover screen the safe area claims a whole edge for the camera
/// corner; the viewer drops that side inset, and this widget avoids only the
/// corner itself. For each reported occlusion that starts within the bar:
///
/// - when the occlusion reaches below the bar, a band of [decoration] is added
///   above the content so the bar's bottom edge clears it (the cover camera
///   region is 82 pt deep, the toolbar about 46);
/// - the content is inset on the side the occlusion is on, by its width.
///
/// The insets come from the box's own measured position, one frame after
/// layout. Without occlusions (every device but the closed iPhone Duo) it
/// adds nothing, paints nothing and measures nothing.
class FoldOcclusionClear extends ConsumerStatefulWidget {
  /// Creates the wrapper.
  const FoldOcclusionClear({
    required this.child,
    required this.decoration,
    super.key,
  });

  /// The bar.
  final Widget child;

  /// Painted behind the whole box, the added band and side insets included.
  /// Match the bar's own background so the band reads as part of it.
  final Decoration decoration;

  @override
  ConsumerState<FoldOcclusionClear> createState() => _FoldOcclusionClearState();
}

class _FoldOcclusionClearState extends ConsumerState<FoldOcclusionClear> {
  EdgeInsets _insets = EdgeInsets.zero;

  @override
  Widget build(BuildContext context) {
    final occlusions = ref.watch(foldOcclusionsProvider);
    final none = occlusions.isEmpty;
    if (none) {
      _insets = EdgeInsets.zero;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure(occlusions));
    }
    // One tree shape either way, so folding or unfolding the phone never
    // remounts the bar (its scroll position and focus survive).
    return DecoratedBox(
      decoration: none ? const BoxDecoration() : widget.decoration,
      child: Padding(padding: _insets, child: widget.child),
    );
  }

  void _measure(FoldOcclusions occlusions) {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final next = occlusionInsets(
      boxSize: box.size,
      contentHeight: box.size.height - _insets.top,
      occlusions: [
        for (final r in occlusions.rects) box.globalToLocal(r.topLeft) & r.size,
      ],
    );
    if ((next.top - _insets.top).abs() < 0.5 &&
        (next.left - _insets.left).abs() < 0.5 &&
        (next.right - _insets.right).abs() < 0.5) {
      return;
    }
    setState(() => _insets = next);
  }
}

/// The insets that keep a bar's content clear of [occlusions], all in the
/// bar's local coordinates.
///
/// [boxSize] is the bar as laid out, [contentHeight] the content's own height
/// (the box minus any band already added). Only occlusions that start above
/// the content's natural bottom and overlap the box horizontally count. The
/// top inset lowers the content until its bottom clears the deepest of them;
/// the side insets move it off them, left or right by which half of the box
/// each occlusion's centre is in.
@visibleForTesting
EdgeInsets occlusionInsets({
  required Size boxSize,
  required double contentHeight,
  required List<Rect> occlusions,
}) {
  final relevant = [
    for (final o in occlusions)
      if (o.top < contentHeight &&
          o.bottom > 0 &&
          o.right > 0 &&
          o.left < boxSize.width)
        o,
  ];
  if (relevant.isEmpty) return EdgeInsets.zero;
  var top = 0.0;
  for (final o in relevant) {
    top = math.max(top, o.bottom - contentHeight);
  }
  var left = 0.0;
  var right = 0.0;
  for (final o in relevant) {
    if (o.bottom <= top || o.top >= top + contentHeight) continue;
    if (o.center.dx > boxSize.width / 2) {
      right = math.max(right, boxSize.width - o.left);
    } else {
      left = math.max(left, o.right);
    }
  }
  return EdgeInsets.fromLTRB(left, top, right, 0);
}
