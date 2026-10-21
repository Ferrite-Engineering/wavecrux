// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/features/viewer/widgets/activity_heatmap_overlay.dart';

/// Hosts the phone signal tree as a start-edge drawer inside one tab's content.
///
/// A `Scaffold.drawer` is mounted by the screen, outside every tab's provider
/// scope, so the signal tree it held needed a second scope over the tab's
/// container. This drawer is a [DrawerController] in the tab's own content
/// instead, so it is built under the tab's one scope. It keeps what the
/// scaffold's drawer gave: the edge swipe, the slide, the scrim. The scrim
/// covers the tab, not the window.
///
/// The status bar's left chevron opens it through [PhoneSignalTreeDrawerHost.maybeOf].
class PhoneSignalTreeDrawerHost extends StatefulWidget {
  /// Creates a host around a tab's [child].
  const PhoneSignalTreeDrawerHost({
    required this.child,
    required this.enabled,
    super.key,
  });

  /// The tab's content.
  final Widget child;

  /// Whether the drawer exists: phone-width layouts only. The host wraps the
  /// content either way, so a device-class flip does not re-parent it.
  final bool enabled;

  /// The drawer host above [context], or null when the tab has none (a widget
  /// test that builds the status bar alone, or a layout wider than a phone).
  static PhoneSignalTreeDrawerHostState? maybeOf(BuildContext context) {
    final host = context
        .getInheritedWidgetOfExactType<_PhoneSignalTreeDrawerScope>()
        ?.host;
    return (host?.widget.enabled ?? false) ? host : null;
  }

  @override
  State<PhoneSignalTreeDrawerHost> createState() =>
      PhoneSignalTreeDrawerHostState();
}

/// State of [PhoneSignalTreeDrawerHost]; opens the drawer.
class PhoneSignalTreeDrawerHostState extends State<PhoneSignalTreeDrawerHost> {
  final GlobalKey<DrawerControllerState> _drawer =
      GlobalKey<DrawerControllerState>();

  /// Slides the signal-tree drawer open.
  void open() => _drawer.currentState?.open();

  /// Slides the signal-tree drawer shut.
  void close() => _drawer.currentState?.close();

  @override
  Widget build(BuildContext context) {
    return _PhoneSignalTreeDrawerScope(
      host: this,
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (widget.enabled)
            DrawerController(
              key: _drawer,
              alignment: DrawerAlignment.start,
              child: const Drawer(
                child: SafeArea(child: ActivityHeatmapOverlay()),
              ),
            ),
        ],
      ),
    );
  }
}

class _PhoneSignalTreeDrawerScope extends InheritedWidget {
  const _PhoneSignalTreeDrawerScope({required this.host, required super.child});

  final PhoneSignalTreeDrawerHostState host;

  @override
  bool updateShouldNotify(_PhoneSignalTreeDrawerScope oldWidget) =>
      !identical(host, oldWidget.host);
}
