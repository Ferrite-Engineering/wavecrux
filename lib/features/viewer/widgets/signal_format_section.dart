// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/named_enum_config.dart';
import 'package:wavecrux/domain/models/q_format_config.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/viewer/providers/inspector_providers.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/named_enum_table_form.dart';
import 'package:wavecrux/shared/widgets/q_format_form.dart';

/// The viewer row [entryId] of [entries], searching groups, or null.
SignalEntry? findSignalEntry(List<SignalEntry> entries, String entryId) {
  for (final entry in entries) {
    if (entry.kind == SignalEntryKind.signal && entry.id == entryId) {
      return entry;
    }
    if (entry.children.isNotEmpty) {
      final found = findSignalEntry(entry.children, entryId);
      if (found != null) return found;
    }
  }
  return null;
}

/// The Inspector's sections for a signal row ([InspectedSignal]): the row's
/// name, path and display format, then the part of the format it uses: the
/// Q-format knobs for a fixed-point row, the label table for a named-enum
/// row. Null when [target] is not a signal row or the row is gone.
Widget? signalInspectorSection(
  BuildContext context,
  WaveCruxInspectable target,
) => target is InspectedSignal
    ? SignalFormatSection(entryId: target.entryId)
    : null;

/// See [signalInspectorSection].
///
/// The format's knobs apply together on Apply (Enter in a field applies
/// too). The draft lives in the tab's [signalFormatDraftsProvider]; while it
/// holds unapplied edits the Inspector keeps showing this row.
class SignalFormatSection extends ConsumerStatefulWidget {
  /// Creates the sections for the viewer row [entryId].
  const SignalFormatSection({required this.entryId, super.key});

  /// The viewer row's id.
  final String entryId;

  @override
  ConsumerState<SignalFormatSection> createState() =>
      _SignalFormatSectionState();
}

class _SignalFormatSectionState extends ConsumerState<SignalFormatSection> {
  /// Bumped on Revert, so the label table rebuilds its fields.
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    // A section remounted over a kept draft must hold the row again.
    CruxInspector.markDirty(
      context,
      dirty:
          ref.read(signalFormatDraftsProvider)[widget.entryId]?.isDirty ??
          false,
    );
  }

  SignalFormatDraft _seedFor(SignalEntry entry) {
    final config = entry.translatorConfig;
    switch (entry.format) {
      case DisplayFormat.fixedPointQ:
        final q = config != null
            ? QFormatConfig.fromMap(config)
            : const QFormatConfig();
        return SignalFormatDraft(qFormat: q, initialQFormat: q);
      case DisplayFormat.namedEnum:
        final rows = namedEnumRowsOf(
          config != null
              ? NamedEnumConfig.fromMap(config)
              : const NamedEnumConfig(),
        );
        return SignalFormatDraft(enumRows: rows, initialEnumRows: rows);
      case _:
        return const SignalFormatDraft();
    }
  }

  void _put(SignalFormatDraft draft) =>
      ref.read(signalFormatDraftsProvider.notifier).put(widget.entryId, draft);

  void _apply(SignalFormatDraft draft) {
    final Map<String, Object?>? config;
    if (draft.qFormat case final q?) {
      config = q.toMap();
    } else if (draft.enumRows case final rows?) {
      config = namedEnumConfigOf(rows)?.toMap();
    } else {
      config = null;
    }
    if (config == null) return;
    ref
        .read(signalGroupsProvider.notifier)
        .setSignalTranslatorConfigById(widget.entryId, config);
    ref.read(signalFormatDraftsProvider.notifier).discard(widget.entryId);
  }

  void _revert() {
    ref.read(signalFormatDraftsProvider.notifier).discard(widget.entryId);
    setState(() => _revision++);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    ref.listen<SignalFormatDraft?>(
      signalFormatDraftsProvider.select((d) => d[widget.entryId]),
      (_, next) =>
          CruxInspector.markDirty(context, dirty: next?.isDirty ?? false),
    );
    final entry = findSignalEntry(
      ref.watch(signalGroupsProvider).entries,
      widget.entryId,
    );
    if (entry == null) return const SizedBox.shrink();
    final draft =
        ref.watch(
          signalFormatDraftsProvider.select((d) => d[widget.entryId]),
        ) ??
        _seedFor(entry);
    final dirty = draft.isDirty;

    final children = <Widget>[
      CruxInspectorSection(
        title: l10n.inspectorSignalSection,
        children: <Widget>[
          CruxInspectorValueRow(
            label: l10n.inspectorSignalName,
            value: entry.displayName ?? entry.signalRef ?? '',
          ),
          if (entry.signalPath case final path?)
            CruxInspectorValueRow(label: l10n.inspectorSignalPath, value: path),
          CruxInspectorValueRow(
            label: l10n.valueColumnFormatHeader,
            value: displayFormatLabel(l10n, entry.format),
          ),
        ],
      ),
    ];

    Widget applyBar({required bool valid}) => CruxInspectorApplyBar(
      applyLabel: l10n.inspectorApply,
      revertLabel: l10n.inspectorRevert,
      onApply: dirty && valid ? () => _apply(draft) : null,
      onRevert: dirty ? _revert : null,
    );

    if (draft.qFormat case final q?) {
      children.add(
        CruxInspectorSection(
          title: l10n.qFormatConfigTitle,
          onSubmit: dirty ? () => _apply(draft) : null,
          footer: applyBar(valid: true),
          children: <Widget>[
            QFormatForm(
              value: q,
              onChanged: (next) => _put(draft.copyWith(qFormat: next)),
            ),
          ],
        ),
      );
    }
    if (draft.enumRows case final rows?) {
      final valid = rows.every((r) => r.isValid);
      children.add(
        CruxInspectorSection(
          title: l10n.namedEnumEditorTitle,
          onSubmit: dirty && valid ? () => _apply(draft) : null,
          footer: applyBar(valid: valid),
          children: <Widget>[
            NamedEnumTableForm(
              rows: rows,
              revision: draft.revision + _revision,
              onChanged: (next) => _put(draft.copyWith(enumRows: next)),
              onReplaced: (next) =>
                  _put(draft.copyWith(enumRows: next, bumpRevision: true)),
            ),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0) const Divider(height: 24),
          children[i],
        ],
      ],
    );
  }
}

/// The localized name of a display format.
String displayFormatLabel(L10N l10n, DisplayFormat format) => switch (format) {
  DisplayFormat.binary => l10n.displayFormatBinary,
  DisplayFormat.hexadecimal => l10n.displayFormatHexadecimal,
  DisplayFormat.octal => l10n.displayFormatOctal,
  DisplayFormat.unsignedDecimal => l10n.displayFormatUnsignedDecimal,
  DisplayFormat.signedDecimal => l10n.displayFormatSignedDecimal,
  DisplayFormat.ascii => l10n.displayFormatAscii,
  DisplayFormat.ieee754Single => l10n.displayFormatIeee754Single,
  DisplayFormat.ieee754Double => l10n.displayFormatIeee754Double,
  DisplayFormat.fixedPointQ => l10n.displayFormatFixedPointQ,
  DisplayFormat.signedMagnitude => l10n.displayFormatSignedMagnitude,
  DisplayFormat.grayCode => l10n.displayFormatGrayCode,
  DisplayFormat.namedEnum => l10n.displayFormatNamedEnum,
};
