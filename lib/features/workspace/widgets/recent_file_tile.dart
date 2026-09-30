// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// A single row in the recent files list on the workspace empty-canvas state.
///
/// Displays the file's basename prominently and its full [filePath] in a
/// smaller muted style. Tapping the row calls [onTap]; tapping the trailing
/// remove button calls [onRemove].
class RecentFileTile extends StatelessWidget {
  const RecentFileTile({
    required this.filePath,
    required this.onTap,
    required this.onRemove,
    super.key,
  });

  final String filePath;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  String get _basename {
    final segments = Uri.file(filePath).pathSegments;
    return segments.lastWhere((s) => s.isNotEmpty, orElse: () => filePath);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _basename,
                    style: TextStyle(
                      fontFamily: WavecruxColors.monoFontFamily,
                      fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    filePath,
                    style: TextStyle(
                      fontFamily: WavecruxColors.monoFontFamily,
                      fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Hit area is widened to ≥ 44 dp via the default IconButton padding
            // (48 dp) — meets ARCHITECTURE.md §3.1.8.3 on touch device classes.
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: l10n.emptyCanvasRemoveRecentFile,
              color: colorScheme.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
