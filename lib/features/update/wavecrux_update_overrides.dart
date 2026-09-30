// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async' show unawaited;

import 'package:crux_license/crux_license.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:url_launcher/url_launcher.dart';
import 'package:wavecrux/core/app_info/application_build_info_provider.dart';
import 'package:wavecrux/core/app_info/crux_app_info_adapter.dart';
import 'package:wavecrux/core/updates/wavecrux_update_config.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/update/providers/observed_server_time_provider.dart';

/// Root-scope overrides that bind the cross-suite `crux_updates` package to
/// WaveCrux's own configuration, build metadata, persisted settings, URL
/// launcher, and server-time store.
///
/// Spread into the root `ProviderContainer` by `bootstrap`, ahead of the
/// Pro overlay's `proOverrides`, so the overlay can layer its own
/// update configuration on top under the standard later-wins conflict
/// semantics.
///
/// The localized string bundle is deliberately **not** here: it needs a
/// `BuildContext` to resolve `L10N.of(context)`, so `WaveCruxApp` overrides
/// `cruxUpdateStringsProvider` from inside `MaterialApp.builder` instead.
final List<Override> wavecruxUpdateOverrides = <Override>[
  // The one required binding — the package default throws so a product that
  // forgets it fails at wiring rather than silently never checking. Carries
  // the App Store / Play Store targets and `checkOnMobile: true`.
  cruxUpdateConfigProvider.overrideWithValue(wavecruxUpdateConfig),

  // The running version and OS label, used for the semver comparison and the
  // `User-Agent`. WaveCrux keeps its own in-tree `ApplicationBuildInfo`, so
  // the value is mapped onto `crux_app_info`'s shape the package consumes.
  // Until this resolves the package falls back to the no-op service, so a
  // check racing startup reports "current".
  updateBuildInfoProvider.overrideWith(
    (ref) async =>
        (await ref.watch(applicationBuildInfoProvider.future)).toCruxAppInfo(),
  ),

  // Settings → "Automatically check for updates". Gates the launch, periodic
  // and on-resume checks; the manual action ignores it.
  autoUpdateCheckEnabledProvider.overrideWith(
    (ref) async =>
        (await ref.watch(appSettingsProvider.future)).autoCheckForUpdates,
  ),

  // Every successful manifest fetch reports the authoritative `server_time`;
  // route it into the persisted monotonic store. Capturing the notifier here
  // (rather than reading through `ref` inside the callback) keeps the sink
  // valid regardless of the fetch's autoDispose lifetime — the fix that
  // the shipped in-tree service had to make and the shared service preserves.
  observedServerTimeSinkProvider.overrideWith(
    (ref) =>
        (serverTime) => unawaited(
          ref.read(observedServerTimeStoreProvider.notifier).record(serverTime),
        ),
  ),

  // Whether paid features are unlocked, from the same gate the paid features
  // use. A seat without them is offered only releases that changed what it
  // gets (the manifest's `open_core_version`), so a release that touched only
  // Pro features puts no banner in front of free users. The Pro overlay's
  // licence binding drives `licenseTierProvider`; this follows it, and a key
  // entered mid-session re-presents the last check's result at once. Mobile
  // store builds never fetch, so this matters on desktop only.
  updateEditionProvider.overrideWith(
    (ref) => UpdateEdition.of(
      paidFeaturesUnlocked:
          ref.watch(betaPeriodProvider) ||
          FeatureGate.satisfiesTier(
            LicenseTier.pro,
            ref.watch(licenseTierProvider),
          ),
    ),
  ),

  // "Update Now" / "View Changes". The package default throws rather than
  // silently doing nothing when the user taps the button.
  updateUrlLauncherProvider.overrideWithValue(launchUrl),
];
