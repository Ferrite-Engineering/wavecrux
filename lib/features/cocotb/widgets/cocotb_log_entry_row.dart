// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/domain/enums/cocotb_log_severity.dart';
import 'package:wavecrux/domain/models/cocotb_log_entry.dart';
import 'package:wavecrux/features/cocotb/widgets/cocotb_severity_style.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/navigation_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';

/// Single row in the cocotb log panel list.
///
/// Tap places the primary cursor at the entry's simulation time and pans the
/// waveform there. Long-press / right-click reveals a context menu with
/// Jump-to-Time / Copy-Message / Copy-Timestamp actions.
///
/// Test-start entries (`isTestStart`) render with bold text and a subtle
/// accent so test boundaries are visually obvious as the user scrolls.
/// Test-result entries display a small "Passed" / "Failed" pill.
/// Error/Critical entries get a tinted background so problems stand out.
///
/// Touch targets are 44 pt minimum on mobile and small touch surfaces.
class CocotbLogEntryRow extends ConsumerWidget {
  const CocotbLogEntryRow({required this.entry, super.key});

  final CocotbLogEntry entry;

  void _onTap(WidgetRef ref) {
    final ticks = entry.simTimeTicks;
    if (ticks == null) return;
    ref.read(cursorStateProvider.notifier).placePrimary(ticks);
    ref.read(navigationProvider.notifier).jumpToTime(ticks);
  }

  Future<void> _onContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset globalPosition,
  ) async {
    final l10n = L10N.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final canJump = entry.simTimeTicks != null;
    final canCopyTimestamp = entry.simTimeString != null;

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        if (canJump)
          PopupMenuItem<String>(
            value: 'jump',
            child: Text(l10n.cocotbLogJumpToTime),
          ),
        PopupMenuItem<String>(
          value: 'copyMessage',
          child: Text(l10n.cocotbLogCopyMessage),
        ),
        if (canCopyTimestamp)
          PopupMenuItem<String>(
            value: 'copyTimestamp',
            child: Text(l10n.cocotbLogCopyTimestamp),
          ),
      ],
    );
    if (action == null) return;
    switch (action) {
      case 'jump':
        _onTap(ref);
      case 'copyMessage':
        await Clipboard.setData(ClipboardData(text: entry.message));
      case 'copyTimestamp':
        final ts = entry.simTimeString;
        if (ts != null) {
          await Clipboard.setData(ClipboardData(text: ts));
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final style = CocotbSeverityStyle.of(entry.severity);
    final timescale = ref.watch(currentTimescaleProvider);
    final formatter = TimeFormatService(timescale: timescale);
    final timestamp = entry.simTimeTicks != null
        ? formatter.format(entry.simTimeTicks!)
        : '—';

    final isError =
        entry.severity == CocotbLogSeverity.error ||
        entry.severity == CocotbLogSeverity.critical;
    final backgroundColor = isError
        ? style.color.withValues(alpha: 0.08)
        : (entry.isTestStart
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.18)
              : null);

    final messageStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: entry.isTestStart ? FontWeight.bold : FontWeight.normal,
      color: theme.colorScheme.onSurface,
    );
    final monoStyle = TextStyle(
      fontFamily: WavecruxColors.monoFontFamily,
      fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
      fontSize: 11,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return InkWell(
      onTap: entry.simTimeTicks != null ? () => _onTap(ref) : null,
      onLongPress: () {
        // Use the row's centre as a fallback long-press menu position when
        // we don't have access to the actual touch global position.
        final box = context.findRenderObject() as RenderBox?;
        final origin = box != null
            ? box.localToGlobal(box.size.center(Offset.zero))
            : Offset.zero;
        unawaited(_onContextMenu(context, ref, origin));
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (d) => _onContextMenu(context, ref, d.globalPosition),
        child: Container(
          color: backgroundColor,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // Timestamp.
              SizedBox(
                width: 88,
                child: Text(
                  timestamp,
                  style: monoStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Severity icon.
              Tooltip(
                message: CocotbSeverityStyle.labelFor(entry.severity, l10n),
                child: Icon(style.icon, color: style.color, size: 16),
              ),
              const SizedBox(width: 6),
              // Logger (abbreviated to last segment to save space).
              SizedBox(
                width: 90,
                child: Text(
                  _abbreviateLogger(entry.loggerName),
                  style: monoStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Message.
              Expanded(
                child: Text(
                  entry.message,
                  style: messageStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Test-result pill.
              if (entry.isTestResult && entry.testPassed != null) ...[
                const SizedBox(width: 6),
                _ResultBadge(
                  passed: entry.testPassed!,
                  passedLabel: l10n.cocotbLogTestPassed,
                  failedLabel: l10n.cocotbLogTestFailed,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Abbreviates a Python logger like `cocotb.test_basic.module` to its
  /// final segment so the column stays compact. Whole names shorter than the
  /// column width pass through unchanged.
  static String _abbreviateLogger(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return name;
    return name.substring(dot + 1);
  }
}

class _ResultBadge extends StatelessWidget {
  const _ResultBadge({
    required this.passed,
    required this.passedLabel,
    required this.failedLabel,
  });

  final bool passed;
  final String passedLabel;
  final String failedLabel;

  @override
  Widget build(BuildContext context) {
    final color = passed ? const Color(0xFF43A047) : const Color(0xFFE53935);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color),
      ),
      child: Text(
        passed ? passedLabel : failedLabel,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
