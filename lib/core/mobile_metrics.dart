// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/domain/enums/device_class.dart';

/// Sizing, spacing, hit-target, and typography constants for interactive UI.
///
/// Single source of truth for the WaveCrux mobile UI standards defined in
/// ARCHITECTURE.md §3.1.8. Widgets read values from a [MobileMetrics] instance
/// rather than declaring local pixel constants. The [MobileMetrics.of] factory
/// returns the appropriate set for the active [DeviceClass] and host
/// [TargetPlatform] — desktop sizes for `desktop` class on a desktop OS
/// (Linux/macOS/Windows), mobile sizes everywhere else.
///
/// The `touch` set applies to phone, phone-landscape, and tablet device
/// classes — and to any device class running on iOS/iPadOS/Android, including
/// `desktop` (e.g. iPad Pro 12.9" in landscape, which classifies as desktop
/// at ≥ 1200 dp width but has no mouse).
@immutable
class MobileMetrics {
  const MobileMetrics({
    required this.touchTarget,
    required this.iconSize,
    required this.toolbarButton,
    required this.toolbarHeight,
    required this.statusBarHeight,
    required this.panelHeaderHeight,
    required this.splitterHitWidth,
    required this.splitterVisualWidth,
    required this.laneResizeHandle,
    required this.cursorMarkerSize,
    required this.namedMarkerFlag,
    required this.dragHandleHitArea,
    required this.colorSwatch,
    required this.minLaneHeight,
    required this.bodyText,
    required this.labelText,
    required this.monoText,
    required this.statusBarText,
    required this.isTouch,
  });

  /// Touch-first metric set. Applies to phone, tablet, and any device class
  /// running on iOS/Android. Per ARCHITECTURE.md §3.1.8.1.
  const MobileMetrics.touch()
    : touchTarget = 44,
      iconSize = 24,
      toolbarButton = 48,
      toolbarHeight = 48,
      statusBarHeight = 40,
      panelHeaderHeight = 44,
      splitterHitWidth = 32,
      splitterVisualWidth = 6,
      laneResizeHandle = 16,
      cursorMarkerSize = 18,
      namedMarkerFlag = 16,
      dragHandleHitArea = 44,
      colorSwatch = 16,
      minLaneHeight = 44,
      bodyText = 14,
      labelText = 12,
      monoText = 13,
      statusBarText = 13,
      isTouch = true;

  /// Desktop metric set. Applies to `desktop` device class running on a real
  /// desktop OS (Linux, macOS, Windows). Per ARCHITECTURE.md §3.1.8.1.
  ///
  /// `cursorMarkerSize = 10` (10 dp triangle width) preserves the historical
  /// time-ruler visual; the touch set scales it to 18 dp.
  ///
  /// `splitterVisualWidth = 4` matches the panes package default and is the
  /// floor for "I can grab this" affordance — narrower lines (1 dp) are
  /// effectively invisible even with a mouse.
  const MobileMetrics.desktop()
    : touchTarget = 28,
      iconSize = 18,
      toolbarButton = 36,
      toolbarHeight = 40,
      statusBarHeight = 24,
      panelHeaderHeight = 32,
      splitterHitWidth = 12,
      splitterVisualWidth = 6,
      laneResizeHandle = 4,
      cursorMarkerSize = 10,
      namedMarkerFlag = 8,
      dragHandleHitArea = 24,
      colorSwatch = 12,
      minLaneHeight = 16,
      bodyText = 11,
      labelText = 10,
      monoText = 11,
      statusBarText = 11,
      isTouch = false;

  /// Returns the metric set for the given [deviceClass] and host [platform].
  /// Touch metrics apply when:
  /// - [deviceClass] is phone, phone-landscape, or tablet, OR
  /// - the host [platform] is iOS or Android (regardless of device class).
  ///
  /// Desktop metrics apply only when [deviceClass] is desktop AND the host
  /// is a real desktop OS (Linux, macOS, Windows).
  factory MobileMetrics.resolve(
    DeviceClass deviceClass,
    TargetPlatform platform,
  ) {
    final isMobileHost =
        platform == TargetPlatform.iOS ||
        platform == TargetPlatform.android ||
        platform == TargetPlatform.fuchsia;
    final isTouch = deviceClass != DeviceClass.desktop || isMobileHost;
    return isTouch
        ? const MobileMetrics.touch()
        : const MobileMetrics.desktop();
  }

  /// Convenience: reads `Theme.of(context).platform` and resolves the
  /// metric set for the given [deviceClass]. Call from a build method.
  factory MobileMetrics.of(BuildContext context, DeviceClass deviceClass) =>
      MobileMetrics.resolve(deviceClass, Theme.of(context).platform);

  /// Minimum hit area for any tappable element. Per iOS HIG / Material 3.
  final double touchTarget;

  /// Default Material/SF icon size inside a toolbar or list row.
  final double iconSize;

  /// Square hit zone for a toolbar icon button (toolbar / menu / overflow).
  final double toolbarButton;

  /// Height of the [ViewerToolbar] horizontal bar at the top of the viewer.
  final double toolbarHeight;

  /// Height of the [StatusBar] at the bottom of the viewer.
  final double statusBarHeight;

  /// Height of a panel's title bar (signal tree, transaction view, etc.).
  final double panelHeaderHeight;

  /// Total invisible hit zone for the panel-resize splitter line.
  final double splitterHitWidth;

  /// Visible thickness of the panel-resize splitter line. Must be ≥ 4 dp so
  /// users can see and grab it — narrower bars are not discoverable. Per
  /// ARCHITECTURE.md §3.1.8.6.
  final double splitterVisualWidth;

  /// Height of the bottom-edge resize strip on a signal-list row.
  final double laneResizeHandle;

  /// Width of the time-ruler primary/secondary cursor triangle.
  final double cursorMarkerSize;

  /// Width of a named marker flag (a–z) in the time ruler.
  final double namedMarkerFlag;

  /// Hit area for the signal-list reorder drag handle (encloses the icon).
  final double dragHandleHitArea;

  /// Diameter of the color swatch indicator on a signal-list row.
  final double colorSwatch;

  /// Lower bound for a signal-list / canvas / value-column lane height.
  ///
  /// On touch, the lane resize strip is 16 dp tall (see [laneResizeHandle]),
  /// leaving very little room above it for the row content. The previous 30 dp
  /// default left only 14 dp for the signal-name text — text rendered at
  /// `monoText` overflowed the content area downward into the resize strip,
  /// where it sat on top of the grip glyph. The 44 dp touch floor gives at
  /// least 28 dp of content area, so the text and the grip can't collide.
  ///
  /// Render sites enforce this as `max(entry.laneHeight, minLaneHeight)` so
  /// stored desktop sessions (e.g. 24 dp lanes) still open at 24 dp on
  /// desktop; only the touch render path bumps them up. The
  /// [SignalGroupsNotifier.setLaneHeight] clamp also uses this as its lower
  /// bound, so dragging on touch can't drag below the floor.
  final double minLaneHeight;

  /// Default text in lists, dialogs, menus, snackbars. Per
  /// ARCHITECTURE.md §3.1.8.13.
  final double bodyText;

  /// Column headers, axis labels, panel titles, tooltips. Per
  /// ARCHITECTURE.md §3.1.8.13.
  final double labelText;

  /// Signal values, time-ruler labels, hex/dec/bin readouts. Always paired
  /// with [WavecruxColors.monoFontFamily]. Per ARCHITECTURE.md §3.1.8.13.
  final double monoText;

  /// Cursor times, file name, zoom percent — content of the status bar.
  /// Per ARCHITECTURE.md §3.1.8.13.
  final double statusBarText;

  /// True when the active context is touch-first (phone, tablet, or any
  /// iOS/Android host). Widgets use this to render visible drag affordances
  /// and apply the larger sizes.
  final bool isTouch;
}
