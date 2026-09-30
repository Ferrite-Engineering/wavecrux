// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_command_palette/crux_command_palette.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart' show ModalGuard;
import 'package:crux_keybindings/crux_keybindings.dart'
    show formatShortcutLabel;
import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/shortcuts/action_context_provider.dart';
import 'package:wavecrux/core/shortcuts/action_descriptors.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/trackpad_scroll_listener.dart';
import 'package:wavecrux/shared/widgets/wavecrux_feature_tier_badge.dart';

/// VS Code-style command palette overlay (Ctrl/Cmd+Shift+P).
///
/// Thin wavecrux-flavoured wrapper over the cross-suite
/// [CommandPalette]`<ShortcutAction>` widget from `crux_command_palette`.
/// The wrapper is responsible for everything wavecrux-specific:
///
/// - Computing the visible action list from the single source of truth
///   ([paletteActionsFor], fed by [actionContextProvider]) — which already
///   hides keyboard-only / context-only actions and omits actions disabled in
///   the current app state (e.g. file-dependent actions with no file loaded).
/// - Rendering a [WaveCruxFeatureTierBadge] on Pro/Enterprise commands via the
///   palette's `trailingBuilder`.
/// - Resolving labels via wavecrux's `L10N` extension.
/// - Wrapping the inner list with [TrackpadScrollListener] so iPad Magic
///   Keyboard trackpad scrolls flip through long lists.
///
/// The widget tree (search field, fuzzy filter, results list, keyboard
/// navigation, modal dialog framing) is provided by the cross-suite
/// `crux_command_palette` package and is reusable verbatim by every
/// other Crux product.
class CommandPaletteDialog extends ConsumerWidget {
  const CommandPaletteDialog({required this.onAction, super.key});

  /// Called when the user picks a command. Invoked after the dialog closes.
  final void Function(ShortcutAction) onAction;

  /// Opens the command palette overlay.
  ///
  /// [onAction] will be called (after the dialog is dismissed) with the
  /// [ShortcutAction] the user selected.
  ///
  /// Pass [tabContainer] so the palette runs inside the active tab's
  /// [ProviderScope]; the dialog is pushed by the root navigator, outside the
  /// per-tab [UncontrolledProviderScope], and this keeps any per-tab providers
  /// it touches resolved against the focused tab.
  static Future<void> show(
    BuildContext context, {
    required void Function(ShortcutAction) onAction,
    ProviderContainer? tabContainer,
  }) {
    // Re-entrancy guard: Cmd/Ctrl+Shift+P auto-repeat or a double-press must
    // not stack multiple palettes. Covers both the app.dart global handler and
    // the ViewerScreen dispatch path.
    return ModalGuard.run(
      'commandPalette',
      () => showDialog<void>(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) {
          final dialog = CommandPaletteDialog(onAction: onAction);
          return tabContainer != null
              ? UncontrolledProviderScope(
                  container: tabContainer,
                  child: dialog,
                )
              : dialog;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final bindings = ref.watch(shortcutBindingsProvider);
    final actions = paletteActionsFor(ref.watch(actionContextProvider));

    return CommandPalette<ShortcutAction>(
      actions: actions,
      labelFor: (a) => a.label(l10n),
      onAction: onAction,
      hintText: l10n.commandPaletteSearchHint,
      noResultsLabel: l10n.commandPaletteNoResults,
      bindings: bindings,
      activatorLabel: formatShortcutLabel,
      trailingBuilder: (a) {
        final tier = descriptorFor(a).requiredTier;
        return tier == LicenseTier.openCore
            ? null
            : WaveCruxFeatureTierBadge(requiredTier: tier);
      },
      scrollWrapperBuilder: (ctx, ctrl, child) => TrackpadScrollListener(
        controller: ctrl,
        // Opt the list OUT of the app-wide `trackpad` dragDevice (see
        // [kTrackpadOwnedDragDevices]) so its own Scrollable doesn't
        // double-drive the offset that [TrackpadScrollListener] already scrolls
        // from the two-finger pan-zoom.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(ctx).copyWith(
            dragDevices: kTrackpadOwnedDragDevices,
          ),
          child: child,
        ),
      ),
    );
  }
}
