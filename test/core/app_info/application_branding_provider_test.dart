// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/app_info/application_branding.dart';
import 'package:wavecrux/core/app_info/application_branding_provider.dart';

void main() {
  group('applicationBrandingProvider', () {
    test('default returns Ferrite Engineering branding', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final branding = container.read(applicationBrandingProvider);

      expect(branding.companyName, equals('Ferrite Engineering'));
    });

    test('default logo asset path is non-empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final branding = container.read(applicationBrandingProvider);

      expect(branding.logoAsset, isNotEmpty);
      expect(branding.logoSquareAsset, isNotEmpty);
    });

    test('default website URL points to ferriteengineering.com', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final branding = container.read(applicationBrandingProvider);

      expect(branding.websiteUrl, contains('ferriteengineering.com'));
    });

    test('default copyright year is non-empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final branding = container.read(applicationBrandingProvider);

      expect(branding.copyrightYear, isNotEmpty);
    });

    test('overrideWith replaces branding (white-label override pattern)', () {
      const whiteLabel = ApplicationBranding(
        companyName: 'Acme Corp',
        logoAsset: 'assets/branding/acme_logo.png',
        logoSquareAsset: 'assets/branding/acme_logo_square.png',
        copyrightYear: '2026',
        websiteUrl: 'https://acme.example.com',
      );
      final container = ProviderContainer(
        overrides: [
          applicationBrandingProvider.overrideWith((_) => whiteLabel),
        ],
      );
      addTearDown(container.dispose);

      final branding = container.read(applicationBrandingProvider);

      expect(branding, equals(whiteLabel));
      expect(branding.companyName, equals('Acme Corp'));
    });
  });
}
