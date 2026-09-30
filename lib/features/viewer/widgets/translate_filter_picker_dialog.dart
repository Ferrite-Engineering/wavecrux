// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/help_link.dart';

/// Intermediate dialog shown before the native file picker when the user
/// assigns a GTKWave translate filter to a signal.
///
/// Displays a short explanation of what translate filter files are, a help
/// link to the documentation, and a "Browse…" button that opens the native
/// file picker.  Returns the selected file path, or null if the user cancels.
class TranslateFilterPickerDialog extends StatelessWidget {
  const TranslateFilterPickerDialog({super.key});

  /// Shows the dialog and returns the selected file path (or null).
  static Future<String?> show(BuildContext context) async {
    return showDialog<String?>(
      context: context,
      builder: (_) => const TranslateFilterPickerDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(l10n.translateFilterPickerDialogTitle)),
          HelpLink(
            url: HelpUrls.translateFilters,
            tooltip: l10n.helpLinkTranslateFilters,
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Text(l10n.translateFilterPickerDialogDescription),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.dialogClose),
        ),
        FilledButton(
          onPressed: () async {
            final result = await FilePicker.pickFiles(
              dialogTitle: l10n.translateFilterPickerTitle,
            );
            final path = result?.files.firstOrNull?.path;
            if (context.mounted) Navigator.of(context).pop(path);
          },
          child: Text(l10n.translateFilterPickerBrowseButton),
        ),
      ],
    );
  }
}
