// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform/fsdb_conversion_service.dart';

enum _ConversionState { confirm, converting, error }

/// Dialog that confirms and performs FSDB → FST conversion.
///
/// Shows a confirmation view explaining that FSDB is a proprietary Synopsys
/// format and which `fsdb2vcd` executable will be invoked.  On confirmation it
/// runs the conversion and shows a progress indicator.  On failure the error is
/// displayed with a Retry option.
///
/// Returns the path to the converted FST (or VCD if `vcd2fst` is not found)
/// when dismissed successfully, or null if the user cancelled.
class FsdbConversionDialog extends StatefulWidget {
  const FsdbConversionDialog({
    required this.fsdbPath,
    required this.toolPath,
    required this.service,
    super.key,
  });

  final String fsdbPath;
  final String toolPath;
  final FsdbConversionService service;

  /// Shows the conversion dialog for [fsdbPath].
  ///
  /// [toolPath] is the absolute path to `fsdb2vcd` that will be displayed to
  /// the user before they confirm.  [service] performs the actual conversion.
  ///
  /// Returns the converted file path on success, or null if the user cancelled.
  static Future<String?> show(
    BuildContext context, {
    required String fsdbPath,
    required String toolPath,
    required FsdbConversionService service,
  }) {
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FsdbConversionDialog(
        fsdbPath: fsdbPath,
        toolPath: toolPath,
        service: service,
      ),
    );
  }

  /// Shows a dialog explaining that FSDB cannot be opened in the web build —
  /// conversion needs the local `fsdb2vcd` tool, which the browser can't run.
  /// Used by the web file-open paths to replace the confusing generic
  /// "unsupported format" failure a raw `.fsdb` would otherwise produce.
  static Future<void> showWebUnsupported(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        final l10n = L10N.of(context);
        return AlertDialog(
          title: Text(l10n.fsdbWebUnsupportedTitle),
          content: Text(l10n.fsdbWebUnsupportedMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.fsdbNotFoundDialogClose),
            ),
          ],
        );
      },
    );
  }

  /// Shows a simple dialog informing the user that `fsdb2vcd` is not in PATH.
  static Future<void> showNotFound(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        final l10n = L10N.of(context);
        return AlertDialog(
          title: Text(l10n.fsdbNotFoundDialogTitle),
          content: Text(l10n.fsdbNotFoundDialogMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.fsdbNotFoundDialogClose),
            ),
          ],
        );
      },
    );
  }

  @override
  State<FsdbConversionDialog> createState() => _FsdbConversionDialogState();
}

class _FsdbConversionDialogState extends State<FsdbConversionDialog> {
  _ConversionState _state = _ConversionState.confirm;
  String _errorMessage = '';

  Future<void> _startConversion() async {
    setState(() => _state = _ConversionState.converting);
    try {
      final result = await widget.service.convertFsdbToFst(widget.fsdbPath);
      if (mounted) Navigator.of(context).pop(result);
    } on FsdbConversionException catch (e) {
      if (mounted) {
        setState(() {
          _state = _ConversionState.error;
          _errorMessage = e.message;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _state = _ConversionState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return switch (_state) {
      _ConversionState.confirm => _buildConfirm(l10n),
      _ConversionState.converting => _buildConverting(l10n),
      _ConversionState.error => _buildError(l10n),
    };
  }

  Widget _buildConfirm(L10N l10n) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.fsdbConversionDialogTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.fsdbConversionMessage),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                l10n.fsdbConversionToolInfo(widget.toolPath),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.fsdbConversionCancel),
        ),
        FilledButton(
          onPressed: _startConversion,
          child: Text(l10n.fsdbConversionConfirm),
        ),
      ],
    );
  }

  Widget _buildConverting(L10N l10n) {
    return AlertDialog(
      title: Text(l10n.fsdbConversionDialogTitle),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.fsdbConversionProgress),
          ],
        ),
      ),
    );
  }

  Widget _buildError(L10N l10n) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.fsdbConversionDialogTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.fsdbConversionError(_errorMessage),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.fsdbConversionCancel),
        ),
        FilledButton(
          onPressed: _startConversion,
          child: Text(l10n.fsdbConversionRetry),
        ),
      ],
    );
  }
}
