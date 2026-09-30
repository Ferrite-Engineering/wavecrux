// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Result of the slot-family fan-out prompt.
enum FanOutPromptChoice {
  /// Bind every slot in the family to its matching bit (or
  /// matching multi-bit slice) of the vector.
  bindAll,

  /// Bind only the dropped slot. Caller falls back to the bit picker.
  bindOne,

  /// User dismissed the prompt — abort the drop entirely.
  cancel,
}

/// Modal dialog asking whether to fan out a multi-bit vector signal
/// across an entire family of board slots (e.g. all 16 LEDs of the
/// Basys 3, all 8 ADC channels of the DE10-Nano) or to bind only the
/// slot that received the drop.
///
/// Two body variants:
///
/// - **Single-bit** ([sliceWidth] `null` or 1): the dropped signal's
///   width matches the family size exactly; each slot binds one bit.
///   Body reads "Bind every slot to its matching bit".
/// - **Multi-bit slice** ([sliceWidth] > 1): the dropped signal is an
///   exact integer multiple of the family size; each slot binds an
///   `sliceWidth`-bit chunk. Body reads "Bind every slot to its
///   matching N-bit slice". Example: DE10-Nano `adc_ch[95:0]` 96-bit
///   bus across 8 ADC slots → 12 bits per slot.
///
/// Shown by `applyBoardSlotDrop` when the dropped signal can be
/// fanned out across a slot family.
class FanOutPromptDialog extends StatelessWidget {
  const FanOutPromptDialog({
    required this.signalRef,
    required this.signalWidth,
    required this.familyPrefix,
    required this.familySize,
    required this.familyMinIndex,
    this.sliceWidth,
    super.key,
  });

  final String signalRef;
  final int signalWidth;
  final String familyPrefix;
  final int familySize;
  final int familyMinIndex;

  /// When non-null and > 1, render the multi-bit-slice body variant
  /// with the slice width inlined into the message.
  final int? sliceWidth;

  static Future<FanOutPromptChoice> show(
    BuildContext context, {
    required String signalRef,
    required int signalWidth,
    required String familyPrefix,
    required int familySize,
    required int familyMinIndex,
    int? sliceWidth,
  }) async {
    final result = await showDialog<FanOutPromptChoice>(
      context: context,
      builder: (_) => FanOutPromptDialog(
        signalRef: signalRef,
        signalWidth: signalWidth,
        familyPrefix: familyPrefix,
        familySize: familySize,
        familyMinIndex: familyMinIndex,
        sliceWidth: sliceWidth,
      ),
    );
    return result ?? FanOutPromptChoice.cancel;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final body = sliceWidth != null && sliceWidth! > 1
        ? l10n.stageFanOutPromptBodySlice(
            signalRef,
            signalWidth,
            familyPrefix,
            familySize,
            familyMinIndex,
            sliceWidth!,
          )
        : l10n.stageFanOutPromptBody(
            signalRef,
            signalWidth,
            familyPrefix,
            familySize,
            familyMinIndex,
          );
    return AlertDialog(
      title: Text(l10n.stageFanOutPromptTitle(familySize)),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(FanOutPromptChoice.cancel),
          child: Text(l10n.stageBitPickerCancel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(FanOutPromptChoice.bindOne),
          child: Text(l10n.stageFanOutPromptBindOne),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(FanOutPromptChoice.bindAll),
          child: Text(l10n.stageFanOutPromptBindAll),
        ),
      ],
    );
  }
}
