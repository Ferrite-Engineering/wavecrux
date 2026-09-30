// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Open-core extension point: widgets injected into the trailing (right) end
/// of the viewer status bar, just before the value-column chevron.
///
/// Open-core returns an empty list, so the status bar renders unchanged. The
/// closed-source Pro overlay overrides this binding to inject
/// Enterprise chrome — currently the collaborative-session status chip
/// (`CollabSessionStatusBar`) — without forking the open-core `StatusBar`
/// widget.
///
/// Injected widgets are responsible for rendering nothing
/// (`SizedBox.shrink()`) when they have nothing to show, so the slot adds no
/// visual weight when idle.
final statusBarTrailingWidgetsProvider = Provider<List<Widget>>(
  (_) => const <Widget>[],
);
