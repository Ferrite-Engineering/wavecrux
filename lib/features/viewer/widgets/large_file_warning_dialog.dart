// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Dialog shown before loading a waveform file that exceeds the recommended
/// size limit for the current device class.
///
/// Returns `true` when the user chooses "Load Anyway" and `false` (or `null`)
/// when they cancel.  Call [show] to display the dialog and await the result.
class LargeFileWarningDialog extends StatelessWidget {
  const LargeFileWarningDialog({
    required this.fileSizeMb,
    required this.thresholdMb,
    super.key,
  });

  /// Actual file size in megabytes (displayed to the user).
  final String fileSizeMb;

  /// Recommended maximum size for this device class in megabytes.
  final String thresholdMb;

  /// Displays the dialog and returns `true` if the user chooses to load the
  /// file anyway, or `false` / `null` when they cancel.
  static Future<bool> show(
    BuildContext context, {
    required int fileSizeBytes,
    required int thresholdBytes,
  }) async {
    final fileSizeMb = (fileSizeBytes / (1024 * 1024)).toStringAsFixed(1);
    final thresholdMb = (thresholdBytes / (1024 * 1024)).toStringAsFixed(0);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => LargeFileWarningDialog(
        fileSizeMb: fileSizeMb,
        thresholdMb: thresholdMb,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return AlertDialog(
      title: Text(l10n.largeFileWarningTitle),
      content: Text(
        l10n.largeFileWarningBody(fileSizeMb, thresholdMb),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.largeFileWarningLoadAnyway),
        ),
      ],
    );
  }
}
