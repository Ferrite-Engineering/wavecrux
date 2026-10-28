// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';

/// The transaction under a hovering pointer, and where the pointer is in
/// viewport-local coordinates.
@immutable
class TransactionHover {
  const TransactionHover(this.transaction, this.position);

  final DecodedTransaction transaction;
  final Offset position;
}

/// The full label of the decoder transaction under the mouse, drawn beside
/// the pointer over the waveform canvas.
///
/// A decoder lane truncates a label that does not fit its block, or draws
/// the decoder's short label instead, so this is where the whole label is
/// read without opening the transaction table. An error transaction adds its
/// error message on a second line. Never takes pointer events: it sits above
/// the gesture handler's child and must not steal its clicks.
class TransactionHoverTooltip extends StatelessWidget {
  const TransactionHoverTooltip({required this.hover, super.key});

  /// What to show; null hides the tooltip.
  final ValueListenable<TransactionHover?> hover;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: ValueListenableBuilder<TransactionHover?>(
        valueListenable: hover,
        builder: (context, value, _) {
          if (value == null) return const SizedBox.shrink();
          return CustomSingleChildLayout(
            delegate: _NearPointerLayout(value.position),
            child: _TooltipBody(transaction: value.transaction),
          );
        },
      ),
    ),
  );
}

class _TooltipBody extends StatelessWidget {
  const _TooltipBody({required this.transaction});

  final DecodedTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tooltipTheme = TooltipTheme.of(context);
    final textStyle =
        tooltipTheme.textStyle ??
        theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onInverseSurface,
        );
    final error = transaction.isError ? transaction.errorMessage : null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: DecoratedBox(
        key: const ValueKey('transaction-hover-tooltip'),
        decoration:
            tooltipTheme.decoration ??
            BoxDecoration(
              color: theme.colorScheme.inverseSurface.withValues(alpha: 0.95),
              borderRadius: const BorderRadius.all(Radius.circular(4)),
            ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(transaction.label, style: textStyle),
              if (error != null && error.isNotEmpty)
                Text(
                  error,
                  style: textStyle?.copyWith(fontStyle: FontStyle.italic),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Places the tooltip below and to the right of the pointer, flipped to the
/// other side of it where it would run off the viewport.
class _NearPointerLayout extends SingleChildLayoutDelegate {
  const _NearPointerLayout(this.pointer);

  final Offset pointer;

  static const Offset _gap = Offset(12, 18);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = pointer.dx + _gap.dx;
    if (x + childSize.width > size.width) {
      x = pointer.dx - _gap.dx - childSize.width;
    }
    var y = pointer.dy + _gap.dy;
    if (y + childSize.height > size.height) {
      y = pointer.dy - _gap.dy - childSize.height;
    }
    return Offset(
      x.clamp(0, (size.width - childSize.width).clamp(0, double.infinity)),
      y.clamp(0, (size.height - childSize.height).clamp(0, double.infinity)),
    );
  }

  @override
  bool shouldRelayout(_NearPointerLayout oldDelegate) =>
      oldDelegate.pointer != pointer;
}
