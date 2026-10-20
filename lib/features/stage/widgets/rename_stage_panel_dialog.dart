// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Modal dialog used both to name a brand-new Stage panel and to
/// rename an existing one. Returns the trimmed name on confirm, or
/// null when the user cancels (or submits an empty / whitespace-only
/// value).
class RenameStagePanelDialog extends StatefulWidget {
  const RenameStagePanelDialog({
    required this.initialName,
    required this.titleText,
    super.key,
  });

  final String initialName;

  /// Localized dialog title — the host picks the wording (Create vs
  /// Rename) so we don't bake either into the dialog itself.
  final String titleText;

  /// Convenience: pushes this dialog and returns the chosen name (or
  /// null if cancelled). Selects the entire initial text on open so
  /// the user can type-to-replace.
  static Future<String?> show(
    BuildContext context, {
    required String initialName,
    required String titleText,
  }) {
    return showCruxDialog<String>(
      context: context,
      builder: (context) => RenameStagePanelDialog(
        initialName: initialName,
        titleText: titleText,
      ),
    );
  }

  @override
  State<RenameStagePanelDialog> createState() => _RenameStagePanelDialogState();
}

class _RenameStagePanelDialogState extends State<RenameStagePanelDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialName.length,
      );
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return CruxDialog(
      title: widget.titleText,
      width: 360,
      content: CruxFormRow(
        label: l10n.stageRenamePanelLabel,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.stageRenamePanelHint),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        CruxDialogAction(
          label: MaterialLocalizations.of(context).cancelButtonLabel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        CruxDialogAction(
          label: MaterialLocalizations.of(context).okButtonLabel,
          role: CruxDialogActionRole.primary,
          onPressed: _submit,
        ),
      ],
    );
  }
}
