// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Result returned from [SignalBindingPickerDialog].
///
/// `signalRef` is null when the user cleared the binding, or the
/// waveform signal ref the user picked.
@immutable
class SignalBindingPickerResult {
  const SignalBindingPickerResult({this.signalRef});

  final String? signalRef;
}

/// Modal dialog that lists every signal in the loaded waveform and lets
/// the user pick one to bind to a Stage widget pin.
///
/// Used as a fallback to (or in tandem with) drag-and-drop from the
/// signal tree. Filters by substring match on the full hierarchical
/// path. Returns `null` if cancelled, a [SignalBindingPickerResult]
/// with `signalRef == null` if cleared, or with the chosen signalRef.
class SignalBindingPickerDialog extends ConsumerStatefulWidget {
  const SignalBindingPickerDialog({
    required this.pinName,
    required this.pinDescription,
    this.currentSignalRef,
    super.key,
  });

  final String pinName;
  final String pinDescription;
  final String? currentSignalRef;

  /// Pass [tabContainer] so the picker reads the active tab's
  /// `signalVariablesByPathProvider` (the bindable signal list). The dialog is
  /// pushed by the root navigator, outside the per-tab
  /// [UncontrolledProviderScope], so without this the signal list is empty.
  static Future<SignalBindingPickerResult?> show(
    BuildContext context, {
    required String pinName,
    required String pinDescription,
    String? currentSignalRef,
    ProviderContainer? tabContainer,
  }) {
    return showDialog<SignalBindingPickerResult>(
      context: context,
      builder: (_) {
        final dialog = SignalBindingPickerDialog(
          pinName: pinName,
          pinDescription: pinDescription,
          currentSignalRef: currentSignalRef,
        );
        return tabContainer != null
            ? UncontrolledProviderScope(container: tabContainer, child: dialog)
            : dialog;
      },
    );
  }

  @override
  ConsumerState<SignalBindingPickerDialog> createState() =>
      _SignalBindingPickerDialogState();
}

class _SignalBindingPickerDialogState
    extends ConsumerState<SignalBindingPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    // One row per name: aliased names share a signalRef, and a ref-keyed map
    // would list only one of them.
    final variables = ref.watch(signalVariablesByPathProvider);

    final entries = variables.entries.toList()
      ..sort(
        (a, b) => a.value.fullPath.compareTo(b.value.fullPath),
      );

    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? entries
        : entries
              .where((e) => e.value.fullPath.toLowerCase().contains(query))
              .toList();

    return AlertDialog(
      title: Text(l10n.signalBindingPickerTitle(widget.pinName)),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.pinDescription,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.signalBindingPickerSearchHint,
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: variables.isEmpty
                  ? Center(
                      child: Text(
                        l10n.signalBindingPickerEmptyNoFile,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : filtered.isEmpty
                  ? Center(
                      child: Text(
                        l10n.signalBindingPickerEmptyNoMatch,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ScrollConfiguration(
                      // Re-enable trackpad two-finger scroll: the app-wide
                      // ScrollConfiguration restricts dragDevices to
                      // {touch} (so a mouse drift can't steal a tap),
                      // which also drops trackpad pan-zoom. Add trackpad
                      // back (keep touch for tablet); mouse is left out —
                      // mouse-wheel scroll uses PointerScrollEvent and is
                      // unaffected. Mirrors the widget picker dialog.
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: const <PointerDeviceKind>{
                          PointerDeviceKind.touch,
                          PointerDeviceKind.trackpad,
                        },
                      ),
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemExtent: 36,
                        itemBuilder: (_, i) =>
                            _SignalRow(entry: filtered[i].value),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.currentSignalRef != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              const SignalBindingPickerResult(),
            ),
            child: Text(l10n.signalBindingPickerClear),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
      ],
    );
  }
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.entry});

  final Variable entry;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(
        SignalBindingPickerResult(signalRef: entry.signalRef),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                entry.fullPath,
                style: const TextStyle(fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (entry.bitWidth != null)
              Text(
                '[${entry.bitWidth}]',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
      ),
    );
  }
}
