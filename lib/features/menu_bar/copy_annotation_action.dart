// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_menu_bar/crux_menu_bar.dart';
import 'package:flutter/widgets.dart';

/// Copies the selected annotation, bound to Ctrl+C on Windows and Linux.
///
/// The in-window menu there carries no Edit commands (the shared menu bar's
/// `editCommands` are the macOS menu's), so nothing outside the framework
/// catches a Ctrl+C that no focused widget took. [CopyAnnotationAction]
/// answers it, and is enabled only when Copy would copy a rendered note's
/// selection or the selected annotation: with a text field focused it stands
/// aside, and the key goes on to the field's own copy.
class CopyAnnotationIntent extends Intent {
  /// Creates the intent.
  const CopyAnnotationIntent();
}

/// See [CopyAnnotationIntent].
class CopyAnnotationAction extends Action<CopyAnnotationIntent> {
  /// Creates the action; [annotationText] reads the selected annotation's
  /// clipboard text, or null when none is selected.
  CopyAnnotationAction(this.annotationText);

  /// The selected annotation's clipboard text, read when the key is pressed.
  final String? Function() annotationText;

  @override
  bool isEnabled(CopyAnnotationIntent intent) =>
      switch (CruxEditAvailability.current(
        fallbackAvailable: annotationText() != null,
      ).copySource) {
        CruxCopySource.selectedText || CruxCopySource.fallback => true,
        CruxCopySource.focusedText || null => false,
      };

  @override
  Object? invoke(CopyAnnotationIntent intent) => performCruxEditCommand(
    CruxEditCommand.copy,
    fallbackText: annotationText(),
  );
}
