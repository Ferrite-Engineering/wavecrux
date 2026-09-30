// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';

/// A drop-in [IndexedStack] that **lazily mounts** its children: a child's
/// subtree is built only once its slot has been the active [index] at least
/// once. Slots that have never been active render a zero-size placeholder, so
/// their (potentially expensive) subtree is never mounted — no element, no
/// `initState`, no layout, no paint, and crucially no GPU surface/context
/// initialization.
///
/// Once a slot has been activated it stays mounted (kept alive) for the
/// lifetime of this widget — exactly like [IndexedStack] — so switching back to
/// a previously-viewed slot is instant and preserves any element-tree state.
///
/// ## Why this exists
///
/// A plain [IndexedStack] builds and mounts *every* child up front and only
/// *paints* the one at [index]. For cheap children that is fine, but when each
/// slot mounts GPU-backed content (e.g. a Rive animation or a large
/// `CustomPaint`/`RepaintBoundary` canvas), mounting several at once fans out a
/// burst of concurrent GPU surface/context creation. On some Windows + Intel
/// integrated-GPU configurations that burst races the graphics driver's device
/// init and silently terminates the process (`ExitProcess`, no Dart error) —
/// see `docs/flutter-windows-gpu-crash-issue.md` in the Pro overlay. Mounting
/// one slot at a time sidesteps it entirely and is a strict win everywhere
/// (faster startup, lower idle memory) for content the user cannot see.
///
/// ## Contract
///
/// * Every entry in [children] **must** carry a unique non-null [Widget.key].
///   The key is the stable slot identity used to remember which slots have been
///   activated and to keep [IndexedStack] indexing correct across reorders,
///   insertions and removals. A child without a key is treated as never
///   activated (it renders the placeholder) — asserted against in debug.
/// * [index] selects the painted slot, identically to [IndexedStack].
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({
    required this.index,
    required this.children,
    this.sizing = StackFit.loose,
    this.alignment = AlignmentDirectional.topStart,
    super.key,
  });

  /// Index of the child to show, matching [IndexedStack.index]. Clamped to the
  /// valid range; activating an out-of-range index is a no-op.
  final int index;

  /// The candidate children. Each must have a unique non-null key (see the
  /// class contract). Building this list must be cheap — the expensive work has
  /// to live inside each child's own build/mount, which is exactly what this
  /// widget defers.
  final List<Widget> children;

  /// Forwarded to the underlying [IndexedStack.sizing].
  final StackFit sizing;

  /// Forwarded to the underlying [IndexedStack.alignment].
  final AlignmentGeometry alignment;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  /// Stable z-order of slot keys. New keys are appended as they first appear
  /// and removed when their child is gone, but **existing keys never move** —
  /// so reordering [LazyIndexedStack.children] (e.g. drag-to-reorder tabs)
  /// changes only which slot is painted (the [IndexedStack.index]), never the
  /// element order, and therefore never tears down and re-mounts an
  /// already-mounted child. IndexedStack order is pure z-stacking and otherwise
  /// invisible, so keeping it stable is safe.
  final List<Key> _order = <Key>[];

  /// Keys of slots that have been the active [index] at least once and are
  /// therefore mounted.
  final Set<Key> _activated = <Key>{};

  @override
  Widget build(BuildContext context) {
    final children = widget.children;

    assert(
      children.every((c) => c.key != null),
      'LazyIndexedStack children must all have unique non-null keys.',
    );

    if (children.isEmpty) {
      _order.clear();
      _activated.clear();
      return const SizedBox.shrink();
    }

    final byKey = <Key, Widget>{
      for (final c in children)
        if (c.key != null) c.key!: c,
    };

    // Append newly-seen keys to the stable order; drop closed ones. Existing
    // keys keep their position regardless of the incoming display order.
    for (final c in children) {
      final k = c.key;
      if (k != null && !_order.contains(k)) _order.add(k);
    }
    _order.removeWhere((k) => !byKey.containsKey(k));
    _activated.removeWhere((k) => !byKey.containsKey(k));

    // Resolve the active child (in display order) and mark it mounted-from-now.
    final activeKey = children[widget.index.clamp(0, children.length - 1)].key;
    if (activeKey != null) _activated.add(activeKey);

    final stackIndex = (activeKey == null ? 0 : _order.indexOf(activeKey))
        .clamp(
          0,
          _order.length - 1,
        );

    return IndexedStack(
      index: stackIndex,
      sizing: widget.sizing,
      alignment: widget.alignment,
      children: [
        for (final k in _order)
          // Stable-identity slot wrapper (keyed distinctly from the child so
          // `find.byKey(childKey)` still matches exactly one widget). It mounts
          // the real child only once the slot has been activated; before that
          // it is a zero-size placeholder and the child's subtree never builds.
          _LazyStackSlot(
            key: ValueKey<Key>(k),
            mounted: _activated.contains(k),
            child: byKey[k]!,
          ),
      ],
    );
  }
}

/// One slot of a [LazyIndexedStack]: renders its [child] once [mounted] is
/// `true`, and a zero-size placeholder before that. Kept as a stable-identity
/// wrapper so the underlying [IndexedStack] reconciles slots by the wrapper's
/// key across reorders without tearing down already-mounted children.
class _LazyStackSlot extends StatelessWidget {
  const _LazyStackSlot({required this.mounted, required this.child, super.key});

  final bool mounted;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      mounted ? child : const SizedBox.shrink();
}
