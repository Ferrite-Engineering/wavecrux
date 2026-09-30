// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/domain/models/board_auto_bind_candidate.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Result of [BoardAutoBindPreviewDialog].
@immutable
class BoardAutoBindApplyResult {
  const BoardAutoBindApplyResult(this.bindings);

  /// Map of slot name → binding to apply. Pass-through to
  /// `StageWorkspaceNotifier.setBindings`.
  final Map<String, StageSignalBinding> bindings;
}

/// Modal dialog showing the [BoardAutoBindResult] produced by any
/// `StageAutoBindService`. Lists every pin, groups vector-fan-out candidates
/// by their family, and lets the user pick between applying every candidate
/// or only the high-confidence ones (skipping fuzzy matches).
///
/// The dialog reads nothing board-specific: it renders whatever
/// [BoardAutoBindCandidate]s it is handed, which is what lets the RVFI
/// detection service reuse it unchanged. The only board-shaped thing left is
/// the default [title], which callers with a different subject override.
class BoardAutoBindPreviewDialog extends StatelessWidget {
  const BoardAutoBindPreviewDialog({
    required this.result,
    this.title,
    super.key,
  });

  final BoardAutoBindResult result;

  /// Dialog title. Defaults to the board auto-bind heading when null —
  /// callers that are not binding a board pass their own localized string.
  final String? title;

  static Future<BoardAutoBindApplyResult?> show(
    BuildContext context, {
    required BoardAutoBindResult result,
    String? title,
  }) {
    return showDialog<BoardAutoBindApplyResult>(
      context: context,
      builder: (_) => BoardAutoBindPreviewDialog(result: result, title: title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);

    final entries = _groupForDisplay(result.candidates);

    return AlertDialog(
      title: Text(title ?? l10n.stageBoardAutoBindTitle),
      content: SizedBox(
        width: 520,
        height: 480,
        child: entries.isEmpty
            ? Center(
                child: Text(
                  l10n.stageBoardAutoBindEmpty,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              )
            : ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return _PreviewRow(entry: entry);
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.stageBoardAutoBindCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            BoardAutoBindApplyResult(_collectBindings(confirmedOnly: true)),
          ),
          child: Text(l10n.stageBoardAutoBindApplyConfirmed),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            BoardAutoBindApplyResult(_collectBindings(confirmedOnly: false)),
          ),
          child: Text(l10n.stageBoardAutoBindApplyAll),
        ),
      ],
    );
  }

  /// Collects the bindings to apply. When [confirmedOnly] is true, the
  /// fuzzy-match tier is filtered out (the user said "I trust the
  /// strong matches but want to review the rest").
  Map<String, StageSignalBinding> _collectBindings({
    required bool confirmedOnly,
  }) {
    final out = <String, StageSignalBinding>{};
    for (final entry in result.candidates.entries) {
      final c = entry.value;
      if (c.binding == null) continue;
      if (confirmedOnly && c.confidence == BoardAutoBindConfidence.fuzzyMatch) {
        continue;
      }
      out[entry.key] = c.binding!;
    }
    return out;
  }

  /// Collapses fan-out candidates that share a family prefix into a
  /// single display row so the dialog doesn't overwhelm the user with
  /// 16 nearly-identical rows for a Basys 3 LED column.
  static List<_DisplayEntry> _groupForDisplay(
    Map<String, BoardAutoBindCandidate> candidates,
  ) {
    final byFamily = <String, List<MapEntry<String, BoardAutoBindCandidate>>>{};
    final ordered = <_DisplayEntry>[];
    final seenFamilies = <String>{};

    for (final entry in candidates.entries) {
      final c = entry.value;
      final family = c.familyPrefix;
      if (family != null &&
          c.confidence == BoardAutoBindConfidence.vectorFanOut) {
        byFamily.putIfAbsent(family, () => []).add(entry);
        continue;
      }
      ordered.add(_DisplayEntry.single(entry));
    }

    // Insert family entries in the order their first member appeared.
    final familyOrder = <String>[];
    for (final entry in candidates.entries) {
      final f = entry.value.familyPrefix;
      if (f != null &&
          entry.value.confidence == BoardAutoBindConfidence.vectorFanOut &&
          !seenFamilies.contains(f)) {
        seenFamilies.add(f);
        familyOrder.add(f);
      }
    }
    for (final f in familyOrder) {
      ordered.insert(0, _DisplayEntry.family(prefix: f, members: byFamily[f]!));
    }
    return ordered;
  }
}

class _DisplayEntry {
  _DisplayEntry.single(MapEntry<String, BoardAutoBindCandidate> entry)
    : isFamily = false,
      familyPrefix = null,
      familyMembers = null,
      slotName = entry.key,
      candidate = entry.value;

  _DisplayEntry.family({
    required String prefix,
    required List<MapEntry<String, BoardAutoBindCandidate>> members,
  }) : isFamily = true,
       familyPrefix = prefix,
       familyMembers = members,
       slotName = null,
       candidate = members.first.value;

  final bool isFamily;
  final String? familyPrefix;
  final List<MapEntry<String, BoardAutoBindCandidate>>? familyMembers;
  final String? slotName;
  final BoardAutoBindCandidate candidate;
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.entry});

  final _DisplayEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final c = entry.candidate;

    final String label;
    if (entry.isFamily) {
      // Compute min/max from indices in the slot family by counting
      // the matching tail digits on each member name. The family
      // prefix already holds the canonical name, so the indices are
      // exactly the bit indices on the bindings.
      final indices =
          entry.familyMembers!
              .map((m) => m.value.binding?.bitIndex ?? 0)
              .toList()
            ..sort();
      label = l10n.stageBoardAutoBindFamilyHeader(
        entry.familyPrefix!,
        indices.first,
        indices.last,
      );
    } else {
      label = entry.slotName!;
    }

    final String signalLabel;
    if (c.binding == null) {
      signalLabel = '—';
    } else if (c.binding!.bitIndex == null) {
      signalLabel = c.binding!.signalRef;
    } else if (c.binding!.bitWidth != null && c.binding!.bitWidth! > 1) {
      // Multi-bit slice: render as `signalRef[msb:lsb]` (Verilog
      // notation) so the user sees the full slice extent at a glance.
      final lsb = c.binding!.bitIndex!;
      final msb = lsb + c.binding!.bitWidth! - 1;
      signalLabel = '${c.binding!.signalRef}[$msb:$lsb]';
    } else {
      signalLabel = '${c.binding!.signalRef}[${c.binding!.bitIndex}]';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: c.matchReason,
              child: Text(
                signalLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: c.binding == null
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _ConfidenceChip(confidence: c.confidence),
        ],
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence});

  final BoardAutoBindConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);

    final (label, color) = switch (confidence) {
      BoardAutoBindConfidence.vectorFanOut => (
        l10n.stageBoardAutoBindConfidenceVector,
        theme.colorScheme.primary,
      ),
      BoardAutoBindConfidence.exactMatch => (
        l10n.stageBoardAutoBindConfidenceExact,
        theme.colorScheme.primary,
      ),
      BoardAutoBindConfidence.knownAlias => (
        l10n.stageBoardAutoBindConfidenceAlias,
        theme.colorScheme.tertiary,
      ),
      BoardAutoBindConfidence.fuzzyMatch => (
        l10n.stageBoardAutoBindConfidenceFuzzy,
        theme.colorScheme.secondary,
      ),
      BoardAutoBindConfidence.noMatch => (
        l10n.stageBoardAutoBindConfidenceNoMatch,
        theme.colorScheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
