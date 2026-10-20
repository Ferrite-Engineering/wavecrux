// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:wavecrux/domain/models/q_format_config.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/confirm_discard_changes.dart';

/// Dialog for editing [QFormatConfig] knobs (m, n, signed).
///
/// Returns the updated config map on OK or null if dismissed.
class QFormatConfigDialog extends StatefulWidget {
  const QFormatConfigDialog._({required this.initial});

  final QFormatConfig initial;

  static Future<Map<String, Object?>?> show(
    BuildContext context, {
    Map<String, Object?>? config,
  }) async {
    final initial = config != null
        ? QFormatConfig.fromMap(config)
        : const QFormatConfig();
    final result = await showCruxDialog<QFormatConfig>(
      context: context,
      // Editor dialogs hold in-progress user input: closing must be a
      // deliberate act (Cancel / Save, or Escape, which asks first), never a
      // stray scrim click — the suite-wide dialog rule.
      barrierDismissible: false,
      builder: (_) => QFormatConfigDialog._(initial: initial),
    );
    return result?.toMap();
  }

  @override
  State<QFormatConfigDialog> createState() => _QFormatConfigDialogState();
}

class _QFormatConfigDialogState extends State<QFormatConfigDialog> {
  late int _m;
  late int _n;
  late bool _signed;

  @override
  void initState() {
    super.initState();
    _m = widget.initial.m;
    _n = widget.initial.n;
    _signed = widget.initial.signed;
  }

  QFormatConfig get _current => QFormatConfig(m: _m, n: _n, signed: _signed);

  /// Whether any knob differs from the config the dialog opened with.
  /// Clean forms close without a prompt; dirty ones confirm first
  /// (suite unsaved-changes canon — see [confirmDiscardChanges]).
  bool get _isDirty =>
      _m != widget.initial.m ||
      _n != widget.initial.n ||
      _signed != widget.initial.signed;

  Future<void> _onCancel() async {
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final confirmed = await confirmDiscardChanges(context);
    if (!confirmed || !mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);

    // Escape asks to discard unsaved changes, as Cancel does.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_onCancel());
      },
      child: CruxDialog(
        title: l10n.qFormatConfigTitle,
        width: 320,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _IntSliderRow(
              label: l10n.qFormatConfigIntegerBits,
              value: _m,
              min: 0,
              max: 63,
              onChanged: (v) => setState(() => _m = v),
            ),
            const SizedBox(height: 8),
            _IntSliderRow(
              label: l10n.qFormatConfigFractionalBits,
              value: _n,
              min: 0,
              max: 63,
              onChanged: (v) => setState(() => _n = v),
            ),
            const SizedBox(height: 8),
            // A checkbox, not a switch: this form applies on OK.
            CruxFormRow.checkbox(
              label: l10n.qFormatConfigSigned,
              value: _signed,
              onChanged: (v) => setState(() => _signed = v),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.qFormatConfigPreview(_current.notation),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        actions: [
          CruxDialogAction(
            label: MaterialLocalizations.of(context).cancelButtonLabel,
            onPressed: _onCancel,
          ),
          CruxDialogAction(
            label: MaterialLocalizations.of(context).okButtonLabel,
            role: CruxDialogActionRole.primary,
            onPressed: () => Navigator.of(context).pop(_current),
          ),
        ],
      ),
    );
  }
}

class _IntSliderRow extends StatelessWidget {
  const _IntSliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            SizedBox(
              width: 32,
              child: Text(
                '$value',
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        CruxSlider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: max - min,
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}
