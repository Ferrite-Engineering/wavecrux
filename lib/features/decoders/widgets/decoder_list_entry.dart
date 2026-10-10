// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/license/tier_unlocked_provider.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/core/theme/wavecrux_theme.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/features/decoders/constants/transaction_lane_constants.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/providers/transaction_table_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_config_dialog.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/shared/widgets/platform_context_menu.dart';
import 'package:wavecrux/shared/widgets/wavecrux_withheld_notice.dart';

/// One row representing an active protocol decoder in the
/// [SignalListPanel]'s bottom band, vertically aligned with the
/// corresponding transaction lane painted on the [WaveformCanvas].
///
/// Replaces the per-lane decoder name label that used to be painted at the
/// left edge of each transaction lane on the canvas. Moving it here removes
/// the visual conflict where a transaction starting at t=0 rendered under
/// the label, and gives long-press / right-click a natural anchor for the
/// Configure / Remove actions.
///
/// Height matches [transactionLaneHeight] so this row + its sibling
/// transaction lane stay in sync as the user vertically scrolls.
///
/// A decoder this seat's tier does not include (a Pro decoder a restored
/// session brought back after the beta) is not run, so its lane is empty; the
/// row says why in place of its label, "“USB 2.0 #1” requires WaveCrux Pro.",
/// and a tap opens the upgrade dialog. Configure and Remove still work: the
/// decoder is the user's, and stays in the session until they remove it.
class DecoderListEntry extends ConsumerWidget {
  const DecoderListEntry({
    required this.decoder,
    required this.index,
    super.key,
  });

  /// The active decoder this row represents.
  final ActiveDecoder decoder;

  /// Position of [decoder] in [activeDecodersProvider]'s list. Used
  /// to look up the lane color via [transactionLaneColorForIndex] so the
  /// row matches the canvas's transaction-lane background.
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);
    final colors =
        Theme.of(context).extension<WavecruxColorExtension>() ??
        const WavecruxColorExtension.dark();

    final definition = DecoderRegistry.instance.getDefinition(
      decoder.decoderId,
    );
    final baseName = definition?.displayName ?? decoder.decoderId;
    final displayName = l10n.decoderInstanceLabel(
      baseName,
      decoder.instanceNumber,
    );

    final laneColor = transactionLaneColorForIndex(index);
    final requiredTier = definition?.requiredTier ?? LicenseTier.openCore;
    final unlocked = ref.watch(tierUnlockedProvider(requiredTier));

    return PlatformContextMenu(
      onContextMenu: (pos) => _showContextMenu(
        context,
        ref,
        pos,
        displayName: displayName,
      ),
      child: Container(
        // Subtle tint of the lane color so the row reads as belonging to
        // the matching transaction lane on the canvas. Mirrors the alpha
        // used by the canvas's transaction-lane background paint.
        color: laneColor.withValues(alpha: 0.06),
        height: transactionLaneHeight,
        child: Row(
          children: [
            // ── Color swatch (44 dp hit on touch, even though the swatch
            // itself is non-interactive: the surrounding hit area keeps
            // the decoder row visually consistent with the signal rows
            // above it without introducing a tap action that doesn't
            // exist for canvas transaction lanes).
            SizedBox(
              width: metrics.touchTarget,
              height: transactionLaneHeight,
              child: Center(
                child: Container(
                  width: metrics.colorSwatch,
                  height: metrics.colorSwatch,
                  decoration: BoxDecoration(
                    color: laneColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            // ── Decoder instance label (e.g. "SPI #1"). Per
            // ARCHITECTURE.md §3.1.8.14 the truncated text pairs with a
            // tooltip (desktop hover) AND the long-press / right-click
            // context menu's path-header item below.
            Expanded(
              child: unlocked
                  ? Tooltip(
                      message: displayName,
                      waitDuration: const Duration(milliseconds: 600),
                      triggerMode: TooltipTriggerMode.manual,
                      child: Text(
                        displayName,
                        style: TextStyle(
                          fontFamily: WavecruxColors.monoFontFamily,
                          fontFamilyFallback:
                              WavecruxColors.monoFontFamilyFallback,
                          fontSize: metrics.monoText,
                          color: laneColor,
                          fontWeight: FontWeight.w600,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                  : WaveCruxWithheldNotice(
                      featureLabel: displayName,
                      requiredTier: requiredTier,
                      // The decoder picker's id: the same pack, reached
                      // through a restore instead of the picker.
                      gateFeatureId: 'decoder_pack',
                      layout: WithheldNoticeLayout.row,
                    ),
            ),
            // ── Remove button (desktop only).
            //
            // The decoder row's intrinsic height is fixed at
            // [transactionLaneHeight] (28 dp) so it stays aligned with the
            // canvas transaction lane. On touch device classes the
            // 44 dp `touchTarget` floor (ARCHITECTURE.md §3.1.8.3) cannot
            // fit inside a 28 dp row. Rather than expand the lane (which
            // would propagate to the canvas + value column), the remove
            // affordance is gated to desktop where `touchTarget` = 28 dp.
            // On touch, removal happens via the long-press context menu
            // (Remove item) which the entire row dispatches via
            // [PlatformContextMenu] — no visible affordance lost, since
            // the canvas lane has no remove affordance either.
            if (!metrics.isTouch)
              Tooltip(
                message: l10n.decoderLaneRemove,
                triggerMode: TooltipTriggerMode.manual,
                child: Semantics(
                  button: true,
                  label: l10n.accessibilityRemoveSignal(displayName),
                  child: GestureDetector(
                    onTap: () => _removeDecoder(ref),
                    behavior: HitTestBehavior.translucent,
                    child: SizedBox(
                      width: metrics.touchTarget,
                      height: metrics.touchTarget,
                      child: Center(
                        child: Icon(
                          Icons.close,
                          size: metrics.iconSize * 0.7,
                          color: colors.timeRulerTick,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position, {
    required String displayName,
  }) async {
    final l10n = L10N.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;

    final items = <PopupMenuEntry<_DecoderRowMenuAction>>[
      // Path-header item per ARCHITECTURE.md §3.1.8.14 — the truncated
      // row label is always revealed in full the moment the menu opens.
      PopupMenuItem<_DecoderRowMenuAction>(
        enabled: false,
        height: 28,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(
            displayName,
            style: TextStyle(
              fontFamily: WavecruxColors.monoFontFamily,
              fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            softWrap: true,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<_DecoderRowMenuAction>(
        value: _DecoderRowMenuAction.configure,
        child: Row(
          children: [
            Icon(
              Icons.settings_outlined,
              size: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              l10n.decoderLaneConfigure,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
      PopupMenuItem<_DecoderRowMenuAction>(
        value: _DecoderRowMenuAction.remove,
        child: Row(
          children: [
            Icon(
              Icons.close,
              size: 13,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 6),
            Text(l10n.decoderLaneRemove, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    ];

    final result = await showMenu<_DecoderRowMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
    if (!context.mounted) return;
    switch (result) {
      case _DecoderRowMenuAction.configure:
        await _configureDecoder(context, ref);
      case _DecoderRowMenuAction.remove:
        _removeDecoder(ref);
      case null:
        break;
    }
  }

  Future<void> _configureDecoder(BuildContext context, WidgetRef ref) async {
    final definition = DecoderRegistry.instance.getDefinition(
      decoder.decoderId,
    );
    if (definition == null) return;
    final signalMap = ref.read(signalVariablesByPathProvider);
    // Read the notifier via ref (which resolves from the nearest ancestor scope
    // — the tab's UncontrolledProviderScope) BEFORE pushing the dialog route.
    // The dialog context is a child of the Navigator (above the tab scope), so
    // ref.read inside the dialog would resolve from the root container instead.
    final decodersNotifier = ref.read(activeDecodersProvider.notifier);
    await DecoderConfigDialog.showEdit(
      context,
      definition: definition,
      instanceId: decoder.id,
      instanceNumber: decoder.instanceNumber,
      initialConfig: decoder.config,
      signalMap: signalMap,
      decodersNotifier: decodersNotifier,
    );
  }

  void _removeDecoder(WidgetRef ref) {
    // Mirror the transaction-table behavior: if this decoder is the
    // active filter, clear the filter so the table doesn't end up showing
    // "no transactions" when the user wasn't expecting it.
    final filter = ref.read(transactionTableFilterProvider);
    if (filter.decoderIdFilter == decoder.id) {
      ref.read(transactionTableFilterProvider.notifier).setDecoderFilter(null);
    }
    ref.read(activeDecodersProvider.notifier).removeDecoder(decoder.id);
  }
}

enum _DecoderRowMenuAction { configure, remove }
