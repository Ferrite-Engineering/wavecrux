// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Suite-standard unsaved-changes prompt for editor dialogs.
///
/// Shown when the user cancels a *dirty* editor form. "Keep editing"
/// sits in the cancel slot and the error-colored "Discard" verb
/// confirms — mirroring NetCrux's symbol editor and LintCrux's
/// bookmark dialog. Any non-button dismissal (scrim, Escape) resolves
/// `false`, i.e. keeps editing, so in-progress input is never lost by
/// a stray click — the suite-wide rule for dialogs that hold input.
///
/// Returns `true` when the user confirmed discarding the changes.
Future<bool> confirmDiscardChanges(BuildContext context) {
  final l10n = L10N.of(context);
  return confirmCruxDestructiveAction(
    context,
    title: l10n.editorDiscardConfirmTitle,
    body: l10n.editorDiscardConfirmBody,
    confirmLabel: l10n.editorDiscardConfirmDiscard,
    cancelLabel: l10n.editorDiscardConfirmKeepEditing,
    dialogKey: const ValueKey('editorDiscardConfirmDialog'),
    cancelKey: const ValueKey('editorDiscardConfirmKeepEditing'),
    confirmKey: const ValueKey('editorDiscardConfirmDiscard'),
  );
}
