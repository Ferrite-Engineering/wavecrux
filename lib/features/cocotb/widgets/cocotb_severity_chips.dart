// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_filter_provider.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_severity_style.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Row of [FilterChip]s — one per severity — that toggle the active
/// severity filter on the cocotb log.
///
/// An empty severity filter set is treated as "show all severities" (no
/// chip selected = unfiltered). Each chip displays the severity's icon, its
/// localized name, and a count badge from
/// [CocotbLogFile.severityCounts]. Chips for severities not present in the
/// loaded log show `0` and remain interactive (so the user can pre-toggle
/// before reloading).
class CocotbSeverityChips extends ConsumerWidget {
  const CocotbSeverityChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final log = ref.watch(cocotbLogProvider);
    final filter = ref.watch(cocotbFilterProvider);
    final notifier = ref.read(cocotbFilterProvider.notifier);

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final severity in CocotbLogSeverity.values)
          _SeverityChip(
            severity: severity,
            count: log?.severityCounts[severity] ?? 0,
            selected: filter.severityFilter.contains(severity),
            label: CocotbSeverityStyle.labelFor(severity, l10n),
            onSelected: (_) => notifier.toggleSeverity(severity),
          ),
      ],
    );
  }
}

class _SeverityChip extends StatelessWidget {
  const _SeverityChip({
    required this.severity,
    required this.count,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final CocotbLogSeverity severity;
  final int count;
  final bool selected;
  final String label;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final style = CocotbSeverityStyle.of(severity);
    return FilterChip(
      avatar: Icon(style.icon, color: style.color, size: 14),
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: onSelected,
      selectedColor: style.color.withValues(alpha: 0.25),
      checkmarkColor: style.color,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelStyle: const TextStyle(fontSize: 12),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
