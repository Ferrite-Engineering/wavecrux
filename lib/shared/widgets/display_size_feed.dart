// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Pushes the current `MediaQuery.sizeOf(context)` into
/// [displaySizeProvider] whenever the size changes, so any widget
/// in the tree can read [deviceClassProvider] and get an accurate value.
///
/// Place this once near the app root (inside `MaterialApp.builder`) — every
/// route then sees a live device class without having to wire the size feed
/// itself. Without this widget, [deviceClassProvider] returns its default
/// [DeviceClass.desktop] for the entire run, defeating any width-based
/// layout decision (force-hide-side-panes-on-phone, status-bar chevrons,
/// adaptive toolbar).
///
/// Mutating the provider during build is forbidden by Riverpod, so the
/// update runs in `addPostFrameCallback`.
class DisplaySizeFeed extends ConsumerStatefulWidget {
  const DisplaySizeFeed({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DisplaySizeFeed> createState() => _DisplaySizeFeedState();
}

class _DisplaySizeFeedState extends ConsumerState<DisplaySizeFeed> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(displaySizeProvider.notifier).set(size);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
