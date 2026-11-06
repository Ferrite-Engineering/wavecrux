// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/fold_state.dart';
import 'package:wavecrux/shared/layouts/fold_state_provider.dart';

/// Builds with the crease in this widget's own coordinates.
///
/// The crease arrives in global logical pixels; a layout needs it relative to
/// the box it is laying out (the viewer's dock area sits below the toolbar,
/// a split pane row starts after the left inset). The local rect is measured
/// after layout and the builder runs again when it moves, so the first frame
/// of a new posture draws without the crease and the next one with it: one
/// frame, at a moment the hinge is physically moving.
///
/// [builder] gets null when the device is not half-folded, when the posture
/// is not [posture] (if given), or when the crease does not cross this box.
/// That null path is the only one a device without a hinge ever takes.
class FoldLocalCrease extends ConsumerStatefulWidget {
  /// Creates the builder.
  const FoldLocalCrease({required this.builder, this.posture, super.key});

  /// Only report the crease in this posture; any posture when null.
  final FoldPosture? posture;

  /// Builds the child with the local crease, or null.
  final Widget Function(BuildContext context, Rect? localCrease) builder;

  @override
  ConsumerState<FoldLocalCrease> createState() => _FoldLocalCreaseState();
}

class _FoldLocalCreaseState extends ConsumerState<FoldLocalCrease> {
  Rect? _local;

  @override
  Widget build(BuildContext context) {
    final fold = ref.watch(foldStateProvider);
    final posture = fold.posture;
    final wanted =
        posture != FoldPosture.none &&
        (widget.posture == null || widget.posture == posture);
    final global = wanted ? fold.crease : null;
    if (global == null) {
      _local = null;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure(global));
    }
    return widget.builder(context, global == null ? null : _local);
  }

  void _measure(Rect global) {
    if (!mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final topLeft = box.globalToLocal(global.topLeft);
    final local = topLeft & global.size;
    final bounds = Offset.zero & box.size;
    final next = local.overlaps(bounds) ? local : null;
    if (_close(next, _local)) return;
    setState(() => _local = next);
  }

  static bool _close(Rect? a, Rect? b) {
    if (a == null || b == null) return a == b;
    return (a.left - b.left).abs() < 0.5 &&
        (a.top - b.top).abs() < 0.5 &&
        (a.width - b.width).abs() < 0.5 &&
        (a.height - b.height).abs() < 0.5;
  }
}
