// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/fsm_annotation.dart';
import 'package:wavecrux/domain/models/fsm_model.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/confirm_discard_changes.dart';

/// Dialog that lets the user attach human-readable names to numeric FSM
/// state values for the active signal.
///
/// Pre-populates the form with: (a) labels from any existing
/// [FsmAnnotation], plus (b) the numeric ids discovered by the most recent
/// FSM analysis. The user can leave a row blank to fall back to the raw
/// numeric label.
///
/// On save, the new annotation is stored via [FsmAnnotationNotifier] and
/// the FSM analysis is refreshed so the diagram updates immediately.
class FsmAnnotateDialog extends ConsumerStatefulWidget {
  const FsmAnnotateDialog({
    required this.signalRef,
    required this.knownStateIds,
    super.key,
  });

  /// Signal ref for which annotations are being edited.
  final String signalRef;

  /// Numeric state ids discovered by analysis (and any user-typed extras).
  final List<String> knownStateIds;

  @override
  ConsumerState<FsmAnnotateDialog> createState() => _FsmAnnotateDialogState();

  /// Convenience static helper. Builds the dialog from the current FSM
  /// model, if any. Returns null when no FSM is active.
  /// Pass [tabContainer] so the dialog reads and writes the active tab's
  /// `fsmAnnotationProvider` / `fsmProvider`. The dialog is pushed by the root
  /// navigator, outside the per-tab [UncontrolledProviderScope], so without
  /// this it reads/writes the empty root FSM state instead of the tab's.
  static Future<void> show(
    BuildContext context, {
    required String signalRef,
    required FsmModel? model,
    ProviderContainer? tabContainer,
  }) {
    final ids = model != null
        ? [for (final s in model.states) s.id]
        : const <String>[];
    return showDialog<void>(
      context: context,
      // Editor dialogs hold in-progress user input: closing must be a
      // deliberate act (Cancel / Save), never a stray scrim click — the
      // suite-wide dialog rule. Note this
      // also disables Escape (Flutter routes DismissIntent through the
      // barrier flag).
      barrierDismissible: false,
      builder: (ctx) {
        final dialog = FsmAnnotateDialog(
          signalRef: signalRef,
          knownStateIds: ids,
        );
        return tabContainer != null
            ? UncontrolledProviderScope(container: tabContainer, child: dialog)
            : dialog;
      },
    );
  }
}

class _FsmAnnotateDialogState extends ConsumerState<FsmAnnotateDialog> {
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, String> _initialTexts;

  @override
  void initState() {
    super.initState();
    final existing =
        ref.read(fsmAnnotationProvider)[widget.signalRef]?.stateLabels ??
        const <String, String>{};
    final allIds = <String>{...widget.knownStateIds, ...existing.keys}.toList()
      ..sort(_compareIds);
    _controllers = {
      for (final id in allIds)
        id: TextEditingController(text: existing[id] ?? ''),
    };
    _initialTexts = {
      for (final entry in _controllers.entries) entry.key: entry.value.text,
    };
  }

  /// Whether any state-label field differs from the value it opened
  /// with. Clean forms close without a prompt; dirty ones confirm
  /// first (suite unsaved-changes canon — see [confirmDiscardChanges]).
  bool get _isDirty => _controllers.entries.any(
    (e) => e.value.text != _initialTexts[e.key],
  );

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
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final labels = <String, String>{};
    for (final entry in _controllers.entries) {
      final text = entry.value.text.trim();
      if (text.isNotEmpty) labels[entry.key] = text;
    }
    final notifier = ref.read(fsmAnnotationProvider.notifier);
    if (labels.isEmpty) {
      notifier.removeAnnotation(widget.signalRef);
    } else {
      notifier.setAnnotation(
        widget.signalRef,
        FsmAnnotation(signalRef: widget.signalRef, stateLabels: labels),
      );
    }
    // Refresh the FSM diagram so labels update immediately.
    await ref.read(fsmProvider.notifier).refresh();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return AlertDialog(
      title: Text(l10n.fsmAnnotateDialogTitle),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.fsmAnnotateDialogHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final id in _controllers.keys)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(
                          l10n.fsmAnnotateStateLabel(id),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controllers[id],
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
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
          onPressed: _onCancel,
          child: Text(l10n.fsmAnnotateCancel),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(l10n.fsmAnnotateSave),
        ),
      ],
    );
  }
}

int _compareIds(String a, String b) {
  final ai = BigInt.tryParse(a);
  final bi = BigInt.tryParse(b);
  if (ai != null && bi != null) return ai.compareTo(bi);
  return a.compareTo(b);
}
