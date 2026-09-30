// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Result returned from [BitPickerDialog].
@immutable
class BitPickerResult {
  const BitPickerResult.bit(int index) : bitIndex = index, bindWhole = false;

  /// The user opted to bind the whole multi-bit signal as-is to the
  /// 1-bit slot (escape hatch — the rendered value will probably be
  /// "unknown" but we don't pretend to know better than the user).
  const BitPickerResult.whole() : bitIndex = null, bindWhole = true;

  final int? bitIndex;
  final bool bindWhole;
}

/// Modal dialog asking which bit of a multi-bit vector signal to bind
/// to a 1-bit Stage slot.
///
/// Shown by the drag/drop handlers in [DraggableResizableInstance] and
/// the board slot drop targets when the user drops a vector signal
/// (e.g. `top.dut.led[15:0]`) onto a 1-bit primitive (LED, switch).
///
/// Returns `null` if cancelled, or a [BitPickerResult] carrying either
/// a chosen bit index (LSB = 0) or the "bind whole" escape hatch.
class BitPickerDialog extends StatelessWidget {
  const BitPickerDialog({
    required this.signalRef,
    required this.bitWidth,
    super.key,
  });

  final String signalRef;
  final int bitWidth;

  /// Shows the dialog. Returns `null` if cancelled.
  static Future<BitPickerResult?> show(
    BuildContext context, {
    required String signalRef,
    required int bitWidth,
  }) {
    return showDialog<BitPickerResult>(
      context: context,
      builder: (_) => BitPickerDialog(
        signalRef: signalRef,
        bitWidth: bitWidth,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return AlertDialog(
      title: Text(l10n.stageBitPickerTitle(signalRef)),
      content: SizedBox(
        width: 320,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l10n.stageBitPickerBody(signalRef, bitWidth)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: bitWidth,
                itemBuilder: (context, index) {
                  // Display MSB-first to match how engineers think about
                  // bit ordering on a vector — bit 15 at the top, bit 0
                  // at the bottom.
                  final bit = bitWidth - 1 - index;
                  return ListTile(
                    dense: true,
                    title: Text(
                      l10n.stageBitPickerBitLabel(bit),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    onTap: () =>
                        Navigator.of(context).pop(BitPickerResult.bit(bit)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.stageBitPickerCancel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(const BitPickerResult.whole()),
          child: Text(l10n.stageBitPickerBindWholeSignal),
        ),
      ],
    );
  }
}
