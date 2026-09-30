// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';

/// True when running on a desktop platform (Linux, macOS, or Windows).
bool get isDesktopPlatform =>
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows;

/// True when running on a mobile OS (iOS or Android) — and not in a mobile
/// *browser*, which is web and reports the underlying OS.
///
/// This is a **host-platform** question, not a layout one. Do not reach for it
/// to make sizing or pane decisions: `deviceClassProvider` owns those, so a
/// narrow desktop window and a tablet in split-screen behave correctly. Use
/// this only where the distinction genuinely is "which OS is this build
/// running on" — currently, whether app-store distribution rules apply.
bool get isMobileHostPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);
