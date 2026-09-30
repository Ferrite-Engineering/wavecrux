// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/x_trace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/signal_query/x_trace_service.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';

/// Panel showing the X-origin causal chain for a traced signal.
///
/// Displayed in the bottom pane when an X-trace is active. Each row in the
/// tree shows the signal path, the tick at which it became X, and its
/// previous value. Tapping any row jumps the primary cursor to that node's
/// X-start time.
///
/// Shows an empty-state prompt when no trace is active.
class XTracePanel extends ConsumerWidget {
  const XTracePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final traceState = ref.watch(xTraceProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final timescale = ref.watch(currentTimescaleProvider);
    final formatter = TimeFormatService(timescale: timescale);

    if (!traceState.isActive) {
      return _buildEmpty(context, l10n, traceState.error, colorScheme);
    }

    final root = traceState.rootNode!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── header bar (fixed height) ────────────────────────────────────────
        _PanelHeader(
          title: l10n.xTracePanelTitle,
          onClear: () => ref.read(xTraceProvider.notifier).clearTrace(),
          clearLabel: l10n.xTraceClearButton,
        ),
        // ── scrollable content (root + optional siblings) ────────────────────
        // Root tile, section header, and children list are all inside one
        // Expanded ListView so the panel never overflows regardless of how
        // many lines the root node occupies or how tight the panel height is.
        Expanded(
          child: ListView(
            children: [
              // root node
              _NodeTile(
                node: root,
                formatter: formatter,
                isRoot: true,
                originLabel: l10n.xTraceOriginTime(
                  formatter.format(root.xStartTime),
                ),
                previousLabel: root.previousValue != null
                    ? l10n.xTracePreviousValue(root.previousValue!)
                    : null,
                onTap: () => ref.read(xTraceProvider.notifier).jumpToNode(root),
              ),
              // sibling section (only when co-temporal X signals exist)
              if (root.children.isNotEmpty) ...[
                _SectionHeader(label: l10n.xTraceSiblingHeader),
                ...root.children.map(
                  (child) => _NodeTile(
                    node: child,
                    formatter: formatter,
                    isRoot: false,
                    originLabel: l10n.xTraceSiblingTime(
                      formatter.format(child.xStartTime),
                    ),
                    previousLabel: child.previousValue != null
                        ? l10n.xTracePreviousValue(child.previousValue!)
                        : null,
                    onTap: () =>
                        ref.read(xTraceProvider.notifier).jumpToNode(child),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(
    BuildContext context,
    L10N l10n,
    String? error,
    ColorScheme colorScheme,
  ) {
    return ColoredBox(
      color: colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            error ?? l10n.xTracePanelEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: error != null
                  ? colorScheme.error
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ── _PanelHeader ──────────────────────────────────────────────────────────────

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.title,
    required this.onClear,
    required this.clearLabel,
  });

  final String title;
  final VoidCallback onClear;
  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            Icons.search_off,
            size: 14,
            color: colorScheme.error,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 11),
            ),
            child: Text(clearLabel),
          ),
        ],
      ),
    );
  }
}

// ── _SectionHeader ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

// ── _NodeTile ─────────────────────────────────────────────────────────────────

/// A single row in the X-trace tree.
///
/// Tapping the row jumps the primary cursor to [XCausalNode.xStartTime].
class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.node,
    required this.formatter,
    required this.isRoot,
    required this.originLabel,
    required this.onTap,
    this.previousLabel,
  });

  final XCausalNode node;
  final TimeFormatService formatter;
  final bool isRoot;
  final String originLabel;
  final String? previousLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final indent = isRoot ? 0.0 : 20.0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(8 + indent, 4, 8, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // X-marker icon
            Padding(
              padding: const EdgeInsets.only(top: 1, right: 6),
              child: Icon(
                isRoot ? Icons.gps_fixed : Icons.subdirectory_arrow_right,
                size: 12,
                color: isRoot
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Signal path
                  Text(
                    node.signalPath,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: isRoot ? FontWeight.w600 : FontWeight.normal,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Origin time
                  Text(
                    originLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.error.withValues(alpha: 0.85),
                    ),
                  ),
                  // Previous value
                  if (previousLabel != null)
                    Text(
                      previousLabel!,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
