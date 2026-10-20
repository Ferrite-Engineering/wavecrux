// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:wavecrux/domain/models/q_format_config.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// The fixed-point Q-format knobs: integer bits, fractional bits, signed,
/// and the resulting notation.
///
/// A form, not a host: [value] comes from the host and every change goes
/// back through [onChanged]. The Inspector's signal section hosts it and
/// applies the knobs together on Apply, so signedness is a checkbox.
class QFormatForm extends StatelessWidget {
  /// Creates the form for [value].
  const QFormatForm({required this.value, required this.onChanged, super.key});

  /// The knobs shown.
  final QFormatConfig value;

  /// Called with the knobs after an edit.
  final ValueChanged<QFormatConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _IntSliderRow(
          label: l10n.qFormatConfigIntegerBits,
          value: value.m,
          min: 0,
          max: 63,
          onChanged: (m) =>
              onChanged(QFormatConfig(m: m, n: value.n, signed: value.signed)),
        ),
        const SizedBox(height: 8),
        _IntSliderRow(
          label: l10n.qFormatConfigFractionalBits,
          value: value.n,
          min: 0,
          max: 63,
          onChanged: (n) =>
              onChanged(QFormatConfig(m: value.m, n: n, signed: value.signed)),
        ),
        const SizedBox(height: 8),
        // A checkbox, not a switch: the knobs apply together.
        CruxFormRow.checkbox(
          label: l10n.qFormatConfigSigned,
          value: value.signed,
          onChanged: (signed) =>
              onChanged(QFormatConfig(m: value.m, n: value.n, signed: signed)),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.qFormatConfigPreview(value.notation),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
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
    // One node: the label names the slider for a screen reader.
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 13)),
              ),
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
      ),
    );
  }
}
