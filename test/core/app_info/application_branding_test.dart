// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/app_info/application_branding.dart';

void main() {
  const ferrite = ApplicationBranding(
    companyName: 'Ferrite Engineering',
    logoAsset: 'assets/branding/ferrite_engineering_logo.png',
    logoSquareAsset: 'assets/branding/ferrite_engineering_logo_square.png',
    copyrightYear: '2025',
    websiteUrl: 'https://ferriteengineering.com',
  );

  const ferriteB = ApplicationBranding(
    companyName: 'Ferrite Engineering',
    logoAsset: 'assets/branding/ferrite_engineering_logo.png',
    logoSquareAsset: 'assets/branding/ferrite_engineering_logo_square.png',
    copyrightYear: '2025',
    websiteUrl: 'https://ferriteengineering.com',
  );

  const other = ApplicationBranding(
    companyName: 'Acme Corp',
    logoAsset: 'assets/branding/acme_logo.png',
    logoSquareAsset: 'assets/branding/acme_logo_square.png',
    copyrightYear: '2026',
    websiteUrl: 'https://acme.example.com',
  );

  group('ApplicationBranding', () {
    group('equality', () {
      test('identical objects are equal', () {
        expect(ferrite, equals(ferrite));
      });

      test('objects with same fields are equal', () {
        expect(ferrite, equals(ferriteB));
      });

      test('objects with different fields are not equal', () {
        expect(ferrite, isNot(equals(other)));
      });

      test('different companyName yields inequality', () {
        const d = ApplicationBranding(
          companyName: 'Other',
          logoAsset: 'assets/branding/ferrite_engineering_logo.png',
          logoSquareAsset:
              'assets/branding/ferrite_engineering_logo_square.png',
          copyrightYear: '2025',
          websiteUrl: 'https://ferriteengineering.com',
        );
        expect(ferrite, isNot(equals(d)));
      });

      test('different websiteUrl yields inequality', () {
        const d = ApplicationBranding(
          companyName: 'Ferrite Engineering',
          logoAsset: 'assets/branding/ferrite_engineering_logo.png',
          logoSquareAsset:
              'assets/branding/ferrite_engineering_logo_square.png',
          copyrightYear: '2025',
          websiteUrl: 'https://other.example.com',
        );
        expect(ferrite, isNot(equals(d)));
      });
    });

    group('hashCode', () {
      test('equal objects have the same hashCode', () {
        expect(ferrite.hashCode, equals(ferriteB.hashCode));
      });

      test('unequal objects have different hashCode (very likely)', () {
        expect(ferrite.hashCode, isNot(equals(other.hashCode)));
      });
    });

    group('fields', () {
      test('companyName is accessible', () {
        expect(ferrite.companyName, equals('Ferrite Engineering'));
      });

      test('logoAsset is accessible', () {
        expect(
          ferrite.logoAsset,
          equals('assets/branding/ferrite_engineering_logo.png'),
        );
      });

      test('logoSquareAsset is accessible', () {
        expect(
          ferrite.logoSquareAsset,
          equals('assets/branding/ferrite_engineering_logo_square.png'),
        );
      });

      test('copyrightYear is accessible', () {
        expect(ferrite.copyrightYear, equals('2025'));
      });

      test('websiteUrl is accessible', () {
        expect(ferrite.websiteUrl, equals('https://ferriteengineering.com'));
      });
    });
  });
}
