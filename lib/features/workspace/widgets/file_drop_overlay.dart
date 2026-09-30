// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// The drop affordance shown over the whole window while files are dragged
/// onto the desktop app.
///
/// The browser's drop zone, scaled to the window: the same signal-green
/// 2 dp border and faint green wash `WebDropZone` shows when a file is over
/// it, with one centred card saying what the drop will do. Purely visual —
/// it never takes a pointer, so it cannot interfere with what is under it.
class FileDropOverlay extends StatelessWidget {
  /// Creates the overlay.
  const FileDropOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    // Only ever mounted on a native desktop host, which is always desktop
    // class (see `isDesktopHostPlatform`).
    final metrics = MobileMetrics.of(context, DeviceClass.desktop);
    return IgnorePointer(
      child: DecoratedBox(
        key: const Key('fileDropOverlay'),
        decoration: BoxDecoration(
          color: WavecruxColors.signalGreen.withValues(alpha: 0.06),
          border: Border.all(color: WavecruxColors.signalGreen, width: 2),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Material(
                color: colorScheme.surfaceContainerHigh,
                elevation: 6,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.upload_file_outlined,
                        size: metrics.iconSize * 2,
                        color: WavecruxColors.signalGreen,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.fileDropOverlayTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: metrics.bodyText + 2,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.fileDropOverlayHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: metrics.labelText,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
