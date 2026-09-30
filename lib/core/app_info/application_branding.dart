// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Branding constants for the running WaveCrux build.
///
/// The open-core default exposes Ferrite Engineering identity. The
/// Pro overlay may override `applicationBrandingProvider` for
/// future white-label deployments; the About dialog pulls everything it
/// displays from this model rather than hardcoding any strings.
@immutable
final class ApplicationBranding {
  const ApplicationBranding({
    required this.companyName,
    required this.logoAsset,
    required this.logoSquareAsset,
    required this.copyrightYear,
    required this.websiteUrl,
  });

  /// Legal entity name displayed in the copyright line, e.g.
  /// `"Ferrite Engineering"`.
  final String companyName;

  /// Asset path for the horizontal logo PNG, e.g.
  /// `"assets/branding/ferrite_engineering_logo.png"`.
  final String logoAsset;

  /// Asset path for the square logo PNG used as a compact icon, e.g.
  /// `"assets/branding/ferrite_engineering_logo_square.png"`.
  final String logoSquareAsset;

  /// Four-digit copyright year string, e.g. `"2025"`.
  final String copyrightYear;

  /// Company website URL string, e.g. `"https://ferriteengineering.com"`.
  final String websiteUrl;

  @override
  bool operator ==(Object other) =>
      other is ApplicationBranding &&
      other.companyName == companyName &&
      other.logoAsset == logoAsset &&
      other.logoSquareAsset == logoSquareAsset &&
      other.copyrightYear == copyrightYear &&
      other.websiteUrl == websiteUrl;

  @override
  int get hashCode => Object.hash(
    companyName,
    logoAsset,
    logoSquareAsset,
    copyrightYear,
    websiteUrl,
  );
}
