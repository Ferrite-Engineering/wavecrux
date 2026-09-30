// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Blocking, non-dismissable modal rendered over the routed app content when
/// the public-beta build has reached or passed its hard expiry date
/// (`BetaExpiryStatus.expired`).
///
/// Stacks a non-dismissable [ModalBarrier] over [child] and centers a card
/// with the expiry message, a "Download latest build" action, and a
/// "Quit WaveCrux" action. A [PopScope] with `canPop: false` blocks the
/// system back gesture so the modal cannot be escaped. A dumb leaf widget:
/// the hosting [BetaExpiryGate] owns the status provider, the URL launch,
/// and the app exit.
///
/// The quit action is load-bearing on Windows/Linux: those platforms draw
/// custom window chrome, so the in-app close caption button sits *behind*
/// the [ModalBarrier] and the modal would otherwise leave no visible way to
/// exit the app (macOS's native traffic lights are unaffected).
class BetaExpiryBlockingOverlay extends StatelessWidget {
  /// Creates the blocking beta-expiry modal wrapping [child].
  const BetaExpiryBlockingOverlay({
    required this.child,
    required this.deviceClass,
    required this.onDownload,
    required this.onQuit,
    super.key,
  });

  /// The routed app content rendered (dimmed and input-blocked) behind the
  /// modal.
  final Widget child;

  /// Active device class — drives touch-target and typography sizing via
  /// [MobileMetrics].
  final DeviceClass deviceClass;

  /// Invoked when the user taps the "Download latest build" action.
  final VoidCallback onDownload;

  /// Invoked when the user taps the "Quit WaveCrux" action.
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = MobileMetrics.of(context, deviceClass);

    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          child,
          const ModalBarrier(dismissible: false, color: Colors.black54),
          Center(
            child: SafeArea(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hourglass_disabled_outlined,
                          size: metrics.iconSize * 2,
                          color: scheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.betaExpiryExpiredTitle,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.betaExpiryExpiredBody,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: metrics.bodyText,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: metrics.touchTarget,
                          child: FilledButton.icon(
                            onPressed: onDownload,
                            icon: const Icon(Icons.download_outlined),
                            label: Text(l10n.betaExpiryExpiredAction),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: metrics.touchTarget,
                          child: TextButton(
                            onPressed: onQuit,
                            child: Text(l10n.betaExpiryExpiredQuit),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
