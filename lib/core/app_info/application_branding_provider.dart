// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/app_info/application_branding.dart';

part 'application_branding_provider.g.dart';

/// Provides [ApplicationBranding] for the running WaveCrux build.
///
/// The open-core default exposes Ferrite Engineering identity. The
/// Pro overlay may override this provider for white-label
/// deployments that need a different company name, logo, or website URL.
@Riverpod(keepAlive: true)
ApplicationBranding applicationBranding(Ref ref) {
  return const ApplicationBranding(
    companyName: 'Ferrite Engineering',
    logoAsset: 'assets/branding/ferrite_engineering_logo.png',
    logoSquareAsset: 'assets/branding/ferrite_engineering_logo_square.png',
    copyrightYear: '2025',
    websiteUrl: 'https://ferriteengineering.com',
  );
}
