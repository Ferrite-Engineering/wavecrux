// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/pack/pack_disclosure.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';

/// What the user decided at the disclosure step.
class PackDisclosureResult {
  const PackDisclosureResult({required this.stripAuthorNames});

  /// Replace every annotation's author with an empty name in the bundled
  /// session. The annotations still travel; the attribution does not.
  final bool stripAuthorNames;
}

/// The one moment WaveCrux sends design data off the machine, stated plainly
/// before it happens.
///
/// The suite markets *nothing leaves your machine*. That claim is only worth
/// anything if the exception is conspicuous, so this dialog lists the actual
/// **signal paths** — not a count — alongside the time window, the embedded
/// author names and the predicted size. It is a trust-building moment, not
/// friction: a user who reads this list once will trust the rest of the app
/// more, and a user who spots a signal they cannot send has been saved from
/// sending it.
///
/// Returns null when the user backs out.
class PackDisclosureDialog extends StatefulWidget {
  const PackDisclosureDialog({
    required this.disclosure,
    this.timescale,
    super.key,
  });

  static Future<PackDisclosureResult?> show(
    BuildContext context, {
    required PackDisclosure disclosure,
    Timescale? timescale,
  }) => showDialog<PackDisclosureResult>(
    context: context,
    builder: (_) =>
        PackDisclosureDialog(disclosure: disclosure, timescale: timescale),
  );

  final PackDisclosure disclosure;
  final Timescale? timescale;

  @override
  State<PackDisclosureDialog> createState() => _PackDisclosureDialogState();
}

class _PackDisclosureDialogState extends State<PackDisclosureDialog> {
  bool _stripAuthors = false;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final disclosure = widget.disclosure;
    final formatter = TimeFormatService(timescale: widget.timescale);
    final authors = disclosure.authorNames;

    return AlertDialog(
      title: Text(l10n.packDisclosureTitle),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.packDisclosureIntro,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              _Section(
                label: l10n.packDisclosureTimeRangeLabel,
                child: Text(
                  disclosure.span.derivedFromAnnotations
                      ? l10n.packDisclosureTimeRangeAnnotated(
                          formatter.format(disclosure.span.startTime),
                          formatter.format(disclosure.span.endTime),
                        )
                      : l10n.packDisclosureTimeRangeViewport(
                          formatter.format(disclosure.span.startTime),
                          formatter.format(disclosure.span.endTime),
                        ),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              _Section(
                label: l10n.packDisclosureSignalsLabel(
                  disclosure.signalPaths.length,
                ),
                child: _SignalPathList(paths: disclosure.signalPaths),
              ),
              _Section(
                label: l10n.packDisclosureAuthorsLabel,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authors.isEmpty
                          ? l10n.packDisclosureAuthorsNone
                          : authors.join(', '),
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (authors.isNotEmpty)
                      CheckboxListTile(
                        value: _stripAuthors,
                        onChanged: (v) =>
                            setState(() => _stripAuthors = v ?? false),
                        title: Text(l10n.packDisclosureStripAuthors),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                  ],
                ),
              ),
              _Section(
                label: l10n.packDisclosureSizeLabel,
                child: Text(
                  l10n.packDisclosureSizeApprox(
                    _formatBytes(disclosure.estimatedBytes),
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (disclosure.exceedsWarnThreshold)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_outlined,
                        size: 18,
                        color: theme.colorScheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.packDisclosureSizeWarning,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.tertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            PackDisclosureResult(stripAuthorNames: _stripAuthors),
          ),
          child: Text(l10n.packDisclosureConfirm),
        ),
      ],
    );
  }

  /// Human-readable size. Deliberately coarse — the number is there to answer
  /// "can I email this", not to be audited.
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// The signal paths, scrollable past a handful so a 200-signal view does not
/// produce a dialog taller than the screen — but never truncated to a count.
class _SignalPathList extends StatelessWidget {
  const _SignalPathList({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Scrollbar(
        child: ListView.builder(
          primary: false,
          shrinkWrap: true,
          itemCount: paths.length,
          itemBuilder: (_, i) => Text(
            paths[i],
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}
