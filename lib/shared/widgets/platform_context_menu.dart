// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart' as crux;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// WaveCrux adapter over the shared [crux.PlatformContextMenu], the suite's
/// "long-press = right-click" wrapper (promoted into `crux_ide_layout`).
///
/// The shared widget is domain-neutral and takes its touch-vs-pointer
/// classification as an injected `isTouchLayout` flag; this adapter supplies
/// it from WaveCrux's [deviceClassProvider] (any class other than
/// [DeviceClass.desktop] is a touch-first layout). The behaviour is unchanged
/// from the previous local implementation:
///
/// - **Desktop OS at desktop device class:** [onContextMenu] fires on
///   secondary-button tap-up (right-click). Long-press is not enabled, to
///   avoid a 500 ms delay on pointer devices.
/// - **All other contexts** (phone / phone-landscape / tablet classes, or any
///   iOS / Android host even when the class evaluates to desktop — e.g. iPad
///   Pro 12.9" in landscape): [onContextMenu] fires on long-press start.
///   Right-click still works with an external mouse.
///
/// The callback receives the global [Offset] so callers can position a popup
/// menu or custom overlay at the correct screen location.
class PlatformContextMenu extends ConsumerWidget {
  /// Creates the adapter. See the class docs for the touch-layout mapping.
  const PlatformContextMenu({
    required this.child,
    required this.onContextMenu,
    super.key,
  });

  /// The widget whose area triggers the context menu.
  final Widget child;

  /// Called with the global screen position where the context menu should
  /// appear. On right-click this is the pointer-up location; on long-press
  /// this is the press start location.
  final void Function(Offset globalPosition) onContextMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceClass = ref.watch(deviceClassProvider);
    return crux.PlatformContextMenu(
      isTouchLayout: deviceClass != DeviceClass.desktop,
      onContextMenu: onContextMenu,
      child: child,
    );
  }
}

/// Returns true when long-press should fire a context menu for the given
/// [deviceClass] running on the given [platform].
///
/// WaveCrux adapter over [crux.shouldEnableLongPressContextMenu]: it maps
/// WaveCrux's [DeviceClass] to the shared `isTouchLayout` flag (any class
/// other than [DeviceClass.desktop] is touch-first). Used by the signal-tree
/// rows, which enable the long-press path inline rather than wrapping in the
/// [PlatformContextMenu] widget.
bool shouldEnableLongPressContextMenu(
  DeviceClass deviceClass,
  TargetPlatform platform,
) => crux.shouldEnableLongPressContextMenu(
  isTouchLayout: deviceClass != DeviceClass.desktop,
  platform: platform,
);
