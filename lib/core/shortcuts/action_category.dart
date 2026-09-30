// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_shortcut_action/crux_shortcut_action.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// Re-export ActionCategory so existing consumer imports of
// `package:wavecrux/core/shortcuts/action_category.dart` continue to work
// unchanged after the enum moved to crux_shortcut_action. New code is
// equally welcome to import directly from the cross-suite package.
export 'package:crux_shortcut_action/crux_shortcut_action.dart'
    show ActionCategory;

/// Localized display name for each [ActionCategory].
///
/// The [ActionCategory] enum itself lives in
/// `package:crux_shortcut_action` so it can be shared across the suite;
/// the wavecrux-specific localized labels live here because they reference
/// wavecrux's `L10N` class. Each Crux product writes a parallel extension
/// against its own L10N.
///
/// Which actions appear in which surface (menu bar, overflow menu, command
/// palette), grouped by category, is no longer derived here — it comes from
/// the single source of truth in `action_descriptors.dart`
/// (`groupedActionsFor` / `paletteActionsFor` / `isActionEnabled`).
extension ActionCategoryLabel on ActionCategory {
  /// Returns the localized human-readable name for this category.
  String label(L10N l10n) => switch (this) {
    ActionCategory.app => l10n.actionCategoryApp,
    ActionCategory.file => l10n.actionCategoryFile,
    ActionCategory.edit => l10n.actionCategoryEdit,
    ActionCategory.view => l10n.actionCategoryView,
    ActionCategory.navigate => l10n.actionCategoryNavigate,
    ActionCategory.search => l10n.actionCategorySearch,
    ActionCategory.tools => l10n.actionCategoryTools,
    ActionCategory.help => l10n.actionCategoryHelp,
  };

  /// The localized top-level menu title with an Alt-accelerator mnemonic
  /// marker (`&`), for use as a [MenuAcceleratorLabel] in the Windows/Linux
  /// in-window menu bar. The `&` precedes the underlined accelerator key
  /// (e.g. `&File` → Alt+F); Flutter strips it from the displayed text and
  /// disables accelerators on macOS/iOS automatically.
  ///
  /// The [app] category is never a top-level Material menu (it is hoisted into
  /// the macOS application menu and folded into File on Windows/Linux), so it
  /// has no mnemonic and falls back to its plain [label].
  String acceleratorLabel(L10N l10n) => switch (this) {
    ActionCategory.app => l10n.actionCategoryApp,
    ActionCategory.file => l10n.actionCategoryFileMnemonic,
    ActionCategory.edit => l10n.actionCategoryEditMnemonic,
    ActionCategory.view => l10n.actionCategoryViewMnemonic,
    ActionCategory.navigate => l10n.actionCategoryNavigateMnemonic,
    ActionCategory.search => l10n.actionCategorySearchMnemonic,
    ActionCategory.tools => l10n.actionCategoryToolsMnemonic,
    ActionCategory.help => l10n.actionCategoryHelpMnemonic,
  };
}
