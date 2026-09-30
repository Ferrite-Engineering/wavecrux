// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';

/// Dispatches collaboration shortcut actions to the active Enterprise
/// implementation. The five collaboration [ShortcutAction] values
/// (`shareSession`, `joinSession`, `stopSharing`, `leaveSession`,
/// `exportSessionRecording`) are routed here from
/// [ViewerScreen._handleShortcut].
///
/// The open-core default is a no-op so Open Core builds — which include
/// these actions in their menu bar / overflow menu / command palette for
/// discoverability — silently absorb them without error. The Enterprise
/// overlay overrides this provider with a callback that
/// opens the appropriate dialog or calls the active [CollaborationService].
typedef CollaborationCommandHandler =
    void Function(
      BuildContext context,
      ShortcutAction action,
    );

/// Open-core extension point through which the Enterprise overlay registers
/// a handler for collaboration shortcut commands.
final collaborationCommandHandlerProvider = Provider<CollaborationCommandHandler>(
  (_) => (context, action) {
    // Open-core no-op. The Enterprise overlay overrides this with a callback
    // that routes share/join/stop/leave/export commands to the collaboration
    // service and its dialogs.
  },
);
