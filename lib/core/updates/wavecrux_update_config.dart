// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:wavecrux/core/help_urls.dart';

/// WaveCrux's binding of the cross-suite [CruxUpdateConfig].
///
/// The manifest is a public JSON document served from the release
/// infrastructure; "Update Now" deep-links to the per-platform target
/// resolved by [CruxUpdateConfig.updateTargetFor] rather than downloading in
/// place — the download page on desktop/web, the App Store on iOS/iPadOS, and
/// the Play Store on Android.
///
/// Unlike the desktop-only suite products, **WaveCrux ships iOS and Android and
/// is live in the Apple App Store**, so this config sets the mobile fields the
/// shared `CruxUpdateConfig` exists for:
///
/// * [CruxUpdateConfig.appStoreUri] / [CruxUpdateConfig.playStoreUri] — the
///   store targets for the "Update Now" action, from [HelpUrls].
/// * `checkOnMobile: true` — WaveCrux's desktop AND mobile builds run the
///   check: the manifest's `server_time` hardens the licence and expiry
///   clock against a device clock set back. A store build compares itself
///   with the manifest's `mobile.ios` / `mobile.android` release, the version
///   its store has live, never with `latest` (the desktop release), so the
///   banner appears only when the store has a newer build, and nothing is
///   offered when the manifest lists none for the store. "Update Now" opens
///   the App Store or Play Store.
///
/// The manifest URL (`https://updates.wavecrux.app/manifest.json`) is preserved
/// exactly from the pre-migration in-tree service.
final CruxUpdateConfig wavecruxUpdateConfig = CruxUpdateConfig(
  productName: 'WaveCrux',
  manifestUri: 'https://updates.wavecrux.app/manifest.json',
  downloadPageUri: HelpUrls.download,
  appStoreUri: HelpUrls.appStore,
  playStoreUri: HelpUrls.playStore,
  checkOnMobile: true,
);
