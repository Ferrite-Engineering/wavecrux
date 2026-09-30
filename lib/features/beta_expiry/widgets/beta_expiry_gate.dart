// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;
import 'dart:io' show exit;

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/features/beta_expiry/widgets/beta_expiry_blocking_overlay.dart';
import 'package:wavecrux/features/beta_expiry/widgets/beta_expiry_strings.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Seam for opening the "download the latest build" page. Overridable in tests
/// so the banner / modal actions can be exercised without the url_launcher
/// platform channel. Mirrors `decoderPluginsLaunchUrl`.
Future<bool> Function(Uri uri) betaExpiryLaunchUrl = launchUrl;

/// Seam for terminating the process from the expired modal's quit action.
/// Overridable in tests (calling the real `exit` would kill the test runner).
/// Defaults to the same immediate `exit(0)` the menu-bar quit action uses —
/// the expired modal only ever renders on native desktop beta builds
/// (mobile/web ship no `BETA_EXPIRY`), so the `dart:io` stub-on-web caveat
/// never fires in practice.
void Function() betaExpiryExitApp = () => exit(0);

/// Startup/resume gate that enforces the per-release hard beta build-expiry.
///
/// Wraps the routed app content ([child]) and, based on
/// [betaExpiryStatusProvider]:
///
/// - [BetaExpiryStatus.expiringSoon] → renders a dismissible
///   [CruxBetaExpiryBanner] above [child].
/// - [BetaExpiryStatus.expired] → renders the blocking, non-dismissable
///   [BetaExpiryBlockingOverlay] over [child].
/// - [BetaExpiryStatus.active] / [BetaExpiryStatus.notApplicable] → renders
///   [child] unchanged (the common case, and every developer / post-beta
///   build).
///
/// The status is read at startup (first build) and re-evaluated on app resume:
/// [didChangeAppLifecycleState] invalidates the expiry providers so they
/// re-read the wall clock, and clears the session dismissal so a warning the
/// user dismissed earlier re-surfaces when they return. The check never runs
/// mid-session — only on the resume lifecycle edge — so an in-progress session
/// is never interrupted.
///
/// Sits inside `MaterialApp` (so `L10N.of` resolves) but above the viewer
/// routes — see `app.dart`'s `MaterialApp.builder`.
class BetaExpiryGate extends ConsumerStatefulWidget {
  /// Creates the gate wrapping [child].
  const BetaExpiryGate({required this.child, super.key});

  /// The routed app content the gate wraps.
  final Widget child;

  @override
  ConsumerState<BetaExpiryGate> createState() => _BetaExpiryGateState();
}

class _BetaExpiryGateState extends ConsumerState<BetaExpiryGate>
    with WidgetsBindingObserver {
  /// Whether the user dismissed the "expires soon" banner this session. Reset
  /// on app resume so a returning user is reminded again.
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Re-evaluate expiry against the latest wall-clock reading. The providers
    // capture DateTime.now() when first read, so invalidation forces a fresh
    // read — a build that was still inside its window at launch can cross into
    // expiringSoon / expired while the app was suspended.
    ref
      ..invalidate(betaExpiryStatusProvider)
      ..invalidate(betaExpiryDaysRemainingProvider);
    if (_bannerDismissed && mounted) {
      setState(() => _bannerDismissed = false);
    }
  }

  void _download() {
    unawaited(betaExpiryLaunchUrl(Uri.parse(HelpUrls.download)));
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(betaExpiryStatusProvider);
    final deviceClass = ref.watch(deviceClassProvider);

    switch (status) {
      case BetaExpiryStatus.expired:
        return BetaExpiryBlockingOverlay(
          deviceClass: deviceClass,
          onDownload: _download,
          onQuit: betaExpiryExitApp,
          child: widget.child,
        );
      case BetaExpiryStatus.expiringSoon:
        if (_bannerDismissed) return widget.child;
        final days = ref.watch(betaExpiryDaysRemainingProvider) ?? 0;
        // WaveCrux is the one product with a device-class metrics system, so
        // it feeds the shared banner a sizing derived from `MobileMetrics`
        // rather than taking the desktop defaults the other three use.
        final metrics = MobileMetrics.of(context, deviceClass);
        return Column(
          children: [
            CruxBetaExpiryBanner(
              daysRemaining: days,
              onDownload: _download,
              onDismiss: () => setState(() => _bannerDismissed = true),
              strings: WavecruxBetaExpiryStrings(L10N.of(context)),
              sizing: CruxBetaExpirySizing(
                iconSize: metrics.iconSize,
                touchTarget: metrics.touchTarget,
                bodyTextSize: metrics.bodyText,
              ),
            ),
            Expanded(child: widget.child),
          ],
        );
      case BetaExpiryStatus.active:
      case BetaExpiryStatus.notApplicable:
        return widget.child;
    }
  }
}
