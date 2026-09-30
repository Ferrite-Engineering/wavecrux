// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_menu_bar/crux_menu_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/license/wavecrux_edition_line_strings.dart';
import 'package:wavecrux/core/shortcuts/action_category.dart';
import 'package:wavecrux/core/shortcuts/action_context_provider.dart';
import 'package:wavecrux/core/shortcuts/action_descriptor.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/action_tier_label.dart';
import 'package:wavecrux/core/shortcuts/menu_layout.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/wavecrux_icon_image.dart';

/// WaveCrux's binding of the shared [CruxDesktopMenuBar] to its own action
/// catalog.
///
/// Everything structural — the two renderers (native macOS [PlatformMenuBar]
/// vs. the in-window VS Code-style menu bar on Windows/Linux), separator
/// grouping, the platform-idiomatic placement of About / Check for Updates /
/// Settings / Quit, the standard macOS application-menu tail and Window menu,
/// and the guard that keeps typing-hostile accelerators out of native key
/// equivalents — lives in `crux_menu_bar` so all four products behave
/// identically. This widget supplies only what is WaveCrux's own:
///
/// - **order and grouping** from [kMenuLayout];
/// - **membership and enablement** from `action_descriptors.dart` via the
///   shared [actionContextProvider] — `isActionVisibleIn(…, ActionSurface.menu,
///   …)` and `isActionEnabled`;
/// - **labels**, with the localized tier suffix Pro/Enterprise items carry
///   because a menu can render only a string, not a badge widget.
///
/// ## Not gated on device class
///
/// On Windows/Linux the frameless window's title bar — and with it the
/// min/maximize/close caption buttons — is drawn by the shared menu bar. An
/// earlier device-class gate here hid the whole widget below 1200 dp, which
/// on those platforms left a window with no way to close it. Small-window
/// behaviour belongs to the *layout*, never to the chrome; phone and tablet
/// reach these commands through the overflow menu at the trailing edge of
/// `ViewerToolbar`, which the descriptors' `overflow` surface feeds.
class DesktopMenuBar extends ConsumerWidget {
  /// Creates the WaveCrux desktop menu bar.
  const DesktopMenuBar({
    required this.onAction,
    required this.child,
    super.key,
  });

  /// Called when the user selects a menu item.
  final void Function(ShortcutAction) onAction;

  /// The widget tree below the menu bar.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final ctx = ref.watch(actionContextProvider);
    final bindings = ref.watch(shortcutBindingsProvider);
    final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;

    return CruxDesktopMenuBar<ShortcutAction>(
      layout: kMenuLayout,
      appActions: kAppMenuActions,
      categoryLabel: (category) => category.label(l10n),
      categoryAcceleratorLabel: (category) => category.acceleratorLabel(l10n),
      windowMenuLabel: l10n.menuWindow,
      labelOf: (action) =>
          _label(action, l10n, isMacOS: isMacOS) +
          tierLabelSuffix(descriptorFor(action).requiredTier, l10n),
      shortcutOf: (action) => bindings[action],
      isVisible: (action) => isActionVisibleIn(action, ActionSurface.menu, ctx),
      isEnabled: (action) => isActionEnabled(action, ctx),
      onAction: onAction,
      // States the edition in force, disabled, above `About WaveCrux`.
      // Null at Open Core, so this is safe to pass unconditionally: the
      // Pro overlay supplies the licence status that gives it a value.
      editionLine: cruxLicenseEditionLine(
        ref.watch(licenseStatusProvider),
        WaveCruxEditionLineStrings(l10n),
      ),
      logo: const WaveCruxIconImage(size: 18),
      child: child,
    );
  }

  /// The action's localized label, with the one platform-dependent override.
  ///
  /// Quit reads "Quit WaveCrux" in the macOS application menu and "Exit" at
  /// the bottom of the Windows/Linux File menu — the native wording on each,
  /// and what VS Code does.
  static String _label(
    ShortcutAction action,
    L10N l10n, {
    required bool isMacOS,
  }) => action == ShortcutAction.quit && !isMacOS
      ? l10n.shortcutActionExit
      : action.label(l10n);
}
