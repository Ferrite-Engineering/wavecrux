// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/core/theme/wavecrux_theme.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';

/// Renders a collapsible named group header row in the signal list panel.
///
/// Displays a chevron icon, the group name, and a signal-count badge. Tapping
/// anywhere on the row calls [onToggleCollapsed].
class SignalGroupHeader extends StatelessWidget {
  const SignalGroupHeader({
    required this.groupName,
    required this.signalCount,
    required this.collapsed,
    required this.onToggleCollapsed,
    super.key,
  });

  /// Display name of the group.
  final String groupName;

  /// Number of signal entries in this group (recursive).
  final int signalCount;

  /// Whether the group is currently collapsed (children hidden).
  final bool collapsed;

  /// Called when the user taps the row to toggle collapsed state.
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final colors =
        theme.extension<WavecruxColorExtension>() ??
        const WavecruxColorExtension.dark();

    return GestureDetector(
      onTap: onToggleCollapsed,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: kGroupHeaderHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Tooltip(
                message: collapsed
                    ? l10n.signalGroupHeaderExpandTooltip
                    : l10n.signalGroupHeaderCollapseTooltip,
                child: Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 14,
                  color: colors.timeRulerMajorTick,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  groupName,
                  style: TextStyle(
                    fontFamily: WavecruxColors.monoFontFamily,
                    fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
                    fontSize: 11,
                    color: colors.timeRulerMajorTick,
                    fontWeight: FontWeight.w600,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l10n.signalGroupHeaderSignalCount(signalCount),
                  style: TextStyle(
                    fontSize: 9,
                    color: colors.timeRulerMajorTick,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
