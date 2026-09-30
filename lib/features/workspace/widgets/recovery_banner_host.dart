// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/router.dart' show rootNavigatorKey;
import 'package:wavecrux/features/workspace/commands/reset_workspace_command.dart';
import 'package:wavecrux/features/workspace/providers/startup_recovery_providers.dart';
import 'package:wavecrux/features/workspace/widgets/recovery_banner.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Hosts the startup [RecoveryBanner] above the routed app content.
///
/// Reads the launch recovery posture set by `bootstrap()`
/// ([startupRecoveryProvider]) and renders nothing in the common
/// [StartupRecoveryReason.none] case (every normal launch). When recovering, it
/// shows the strip with the right actions:
///
/// * "Open last session" — only when a held-back session can be reopened
///   ([startupRestoreResumeProvider] is true). Calls `resume()` to perform the
///   load that was suppressed after an interrupted previous launch.
/// * "Reset" — runs [runResetWorkspaceCommand] (confirmation dialog → clears
///   the live workspace and all on-disk session state).
/// * Dismiss — hides the strip for this session.
///
/// Sits inside `MaterialApp` (so `L10N.of` resolves) but above the viewer
/// routes — mirrors `BetaExpiryGate`'s placement in `app.dart`'s
/// `MaterialApp.builder`.
class RecoveryBannerHost extends ConsumerStatefulWidget {
  /// Creates the host wrapping [child].
  const RecoveryBannerHost({required this.child, super.key});

  /// The routed app content the host wraps.
  final Widget child;

  @override
  ConsumerState<RecoveryBannerHost> createState() => _RecoveryBannerHostState();
}

class _RecoveryBannerHostState extends ConsumerState<RecoveryBannerHost> {
  /// Whether the user dismissed (or acted on) the banner this session.
  bool _dismissed = false;

  Future<void> _reset() async {
    // This host renders *above* the app's Navigator (it wraps the routed
    // content in `MaterialApp.builder`), so our own `context` has no Navigator
    // ancestor — `runResetWorkspaceCommand`'s confirmation `showDialog` would
    // throw "Navigator operation requested with a context that does not include
    // a Navigator". Drive the command from the root navigator's context
    // instead, which is inside the Navigator and still under the root
    // ProviderScope (so the command resolves the same root workspace container).
    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) return;
    final didReset = await runResetWorkspaceCommand(
      context: navContext,
      ref: ref,
    );
    if (didReset && mounted) setState(() => _dismissed = true);
  }

  void _resume() {
    ref.read(startupRestoreResumeProvider.notifier).resume();
    setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    final reason = ref.watch(startupRecoveryProvider.select((s) => s.reason));
    if (_dismissed || reason == StartupRecoveryReason.none) {
      return widget.child;
    }
    final canResume = ref.watch(startupRestoreResumeProvider);
    final deviceClass = ref.watch(deviceClassProvider);
    return Column(
      children: [
        RecoveryBanner(
          reason: reason,
          deviceClass: deviceClass,
          canResume: canResume,
          onResume: _resume,
          onReset: () => unawaited(_reset()),
          onDismiss: () => setState(() => _dismissed = true),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
