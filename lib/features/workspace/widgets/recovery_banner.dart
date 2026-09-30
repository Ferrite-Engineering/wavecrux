// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/workspace/providers/startup_recovery_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Dismissible strip rendered above the routed app content when a launch is in
/// a recovery posture (see [StartupRecoveryReason]):
///
/// * [StartupRecoveryReason.interrupted] — the previous launch crashed or hung
///   while reopening a waveform, so this launch held the auto-load back. When
///   the held-back session can be reopened ([canResume]) the strip offers an
///   "Open last session" action alongside "Reset".
/// * [StartupRecoveryReason.workspaceCorrupt] — the saved workspace was
///   unreadable and was reset (the original kept with a `.corrupt` suffix).
///   There is nothing to reopen, so only "Reset" / dismiss are shown.
///
/// A dumb leaf widget: it takes the reason, the resume capability, and three
/// callbacks and renders the strip. The hosting `RecoveryBannerHost` owns the
/// providers, the dismissal state, and the reset flow — so this widget stays
/// trivially testable without platform channels.
class RecoveryBanner extends StatelessWidget {
  /// Creates the recovery strip.
  const RecoveryBanner({
    required this.reason,
    required this.deviceClass,
    required this.canResume,
    required this.onResume,
    required this.onReset,
    required this.onDismiss,
    super.key,
  });

  /// Why this launch is recovering — drives the message and whether a resume
  /// action is meaningful. [StartupRecoveryReason.none] is never passed (the
  /// host renders nothing in that case).
  final StartupRecoveryReason reason;

  /// Active device class — drives touch-target and typography sizing via
  /// [MobileMetrics].
  final DeviceClass deviceClass;

  /// Whether a held-back session can be reopened. When false the "Open last
  /// session" action is hidden (e.g. the workspace-corrupt case, where there is
  /// nothing to reopen).
  final bool canResume;

  /// Invoked when the user taps "Open last session" (reopens the held-back
  /// session). Only reachable when [canResume] is true.
  final VoidCallback onResume;

  /// Invoked when the user taps "Reset" (clears the saved session/workspace).
  final VoidCallback onReset;

  /// Invoked when the user taps the trailing close button to dismiss the strip
  /// for the session.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final scheme = Theme.of(context).colorScheme;
    final metrics = MobileMetrics.of(context, deviceClass);

    final message = switch (reason) {
      StartupRecoveryReason.workspaceCorrupt =>
        l10n.recoveryBannerCorruptMessage,
      // `interrupted` (and the defensive default) share the crash-loop copy.
      StartupRecoveryReason.interrupted ||
      StartupRecoveryReason.none => l10n.recoveryBannerInterruptedMessage,
    };

    return Material(
      color: scheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: metrics.iconSize,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: metrics.bodyText,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (canResume)
                TextButton(
                  onPressed: onResume,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onErrorContainer,
                    minimumSize: Size(metrics.touchTarget, metrics.touchTarget),
                  ),
                  child: Text(l10n.recoveryBannerResumeAction),
                ),
              TextButton(
                onPressed: onReset,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onErrorContainer,
                  minimumSize: Size(metrics.touchTarget, metrics.touchTarget),
                ),
                child: Text(l10n.recoveryBannerResetAction),
              ),
              // No Tooltip here: this strip renders *above* the app's
              // Navigator (it's a sibling of the routed content in
              // `MaterialApp.builder`), so the Navigator's Overlay is not an
              // ancestor and a Tooltip would throw "No Overlay widget found"
              // the moment the recovery banner appears. The accessible name is
              // preserved via Semantics; the close glyph is conventional and the
              // strip's other actions carry visible text labels.
              Semantics(
                label: l10n.recoveryBannerDismissLabel,
                button: true,
                child: IconButton(
                  onPressed: onDismiss,
                  iconSize: metrics.iconSize,
                  color: scheme.onErrorContainer,
                  constraints: BoxConstraints(
                    minWidth: metrics.touchTarget,
                    minHeight: metrics.touchTarget,
                  ),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
