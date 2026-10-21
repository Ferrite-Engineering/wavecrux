// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/tabs/active_tab_navigator.dart';

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

  /// The picker reads the tab's `signalVariablesByPathProvider` (the bindable
  /// signal list), so it is shown on the tab's own navigator
  /// ([ActiveTab.navigatorFor]) and built under the tab's one scope.
  static Future<SignalBindingPickerResult?> show(
    BuildContext context, {
    required String pinName,
    required String pinDescription,
    String? currentSignalRef,
  }) {
    return showCruxDialog<SignalBindingPickerResult>(
      context: context,
      navigator: ActiveTab.navigatorFor(context),
      builder: (_) => SignalBindingPickerDialog(
        pinName: pinName,
        pinDescription: pinDescription,
        currentSignalRef: currentSignalRef,
      ),
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

    return CruxDialog(
      title: l10n.signalBindingPickerTitle(widget.pinName),
      width: 480,
      scrollable: false,
      content: SizedBox(
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
          CruxDialogAction(
            label: l10n.signalBindingPickerClear,
            role: CruxDialogActionRole.tertiary,
            onPressed: () => Navigator.of(context).pop(
              const SignalBindingPickerResult(),
            ),
          ),
        CruxDialogAction(
          label: MaterialLocalizations.of(context).cancelButtonLabel,
          onPressed: () => Navigator.of(context).pop(),
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
