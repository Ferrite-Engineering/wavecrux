// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart' show announceCrux;
import 'package:flutter/widgets.dart';
import 'package:wavecrux/features/annotations/widgets/annotations_panel.dart'
    show showUndoSnack;
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Reports a bulk signal removal and offers to undo it.
///
/// Every bulk removal goes through here — Clear Canvas, Remove All in Scope,
/// Remove Group and Signals, Remove Selected and the Signals list's Delete
/// key — so each is one click to reverse. The viewer has no general undo, and
/// a removal of hundreds of curated rows must not be a one-way door; a
/// confirm dialog on every clear would be the other answer, and it becomes
/// noise the second time.
///
/// The snackbar is silent to a desktop screen reader, so the same message is
/// also announced.
///
/// [notifier] is the active tab's list, captured by the caller before any
/// await: the Undo reaches that tab even if the user has switched tabs since.
void showSignalRemovalUndo(
  BuildContext context, {
  required SignalRemoval removal,
  required SignalGroupsNotifier notifier,
  bool clearedCanvas = false,
}) {
  final l10n = L10N.of(context);
  final message = clearedCanvas
      ? l10n.canvasClearedToast
      : l10n.signalsRemovedToast(removal.signalCount);
  announceCrux(context, message);
  showUndoSnack(
    context,
    message: message,
    undoLabel: l10n.signalRemovalUndo,
    onUndo: () => notifier.undoRemoval(removal),
  );
}
