// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/core/updates/wavecrux_update_config.dart';

/// WaveCrux is the suite's reference **mobile** consumer of the shared
/// `CruxUpdateConfig`: it is live in the Apple App Store and ships on Android,
/// so unlike the desktop-only products it must set `appStoreUri`,
/// `playStoreUri` and `checkOnMobile`. These tests pin those WaveCrux-specific
/// values and the per-platform "Update Now" deep-link mapping that the shared
/// `UpdateBanner` drives through `updateTargetFor` — the behavior the
/// pre-migration in-tree `updateNowUrlFor` test guarded.
void main() {
  group('wavecruxUpdateConfig', () {
    test('carries the exact WaveCrux manifest and page targets', () {
      expect(
        wavecruxUpdateConfig.manifestUri,
        Uri.parse('https://updates.wavecrux.app/manifest.json'),
      );
      expect(
        wavecruxUpdateConfig.downloadPageUri,
        Uri.parse(HelpUrls.download),
      );
      expect(wavecruxUpdateConfig.appStoreUri, Uri.parse(HelpUrls.appStore));
      expect(wavecruxUpdateConfig.playStoreUri, Uri.parse(HelpUrls.playStore));
      expect(wavecruxUpdateConfig.productName, 'WaveCrux');
    });

    test('runs the check on mobile (server_time feeds beta-expiry clock)', () {
      // WaveCrux's mobile builds still run the check so the manifest's
      // server_time hardens the beta-expiry clock; the banner itself never
      // renders on a store build (gated separately in the shared UpdateBanner).
      expect(wavecruxUpdateConfig.checkOnMobile, isTrue);
    });

    group('updateTargetFor — per-platform "Update Now" deep-link', () {
      test('desktop and web target the download page', () {
        expect(
          wavecruxUpdateConfig.updateTargetFor(TargetPlatform.macOS),
          Uri.parse(HelpUrls.download),
        );
        expect(
          wavecruxUpdateConfig.updateTargetFor(TargetPlatform.windows),
          Uri.parse(HelpUrls.download),
        );
        expect(
          wavecruxUpdateConfig.updateTargetFor(TargetPlatform.linux),
          Uri.parse(HelpUrls.download),
        );
        expect(
          wavecruxUpdateConfig.updateTargetFor(
            TargetPlatform.android,
            isWeb: true,
          ),
          Uri.parse(HelpUrls.download),
        );
      });

      test('iOS targets the App Store, Android the Play Store', () {
        expect(
          wavecruxUpdateConfig.updateTargetFor(TargetPlatform.iOS),
          Uri.parse(HelpUrls.appStore),
        );
        expect(
          wavecruxUpdateConfig.updateTargetFor(TargetPlatform.android),
          Uri.parse(HelpUrls.playStore),
        );
      });
    });
  });
}
