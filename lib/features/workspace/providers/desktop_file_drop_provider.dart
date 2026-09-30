// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/services/platform/desktop_file_drop_router.dart';

part 'desktop_file_drop_provider.g.dart';

/// The app-wide [DesktopFileDropRouter].
///
/// Root scope and keep-alive: the window-level drop target
/// (`DesktopFileDropTarget`, mounted in `MaterialApp.builder`) and the viewer
/// that attaches the handler must reach the same instance for the life of the
/// app. Tests deliver drops through it directly — the routing seam that needs
/// no platform channel.
@Riverpod(keepAlive: true)
DesktopFileDropRouter desktopFileDropRouter(Ref ref) => DesktopFileDropRouter();
