// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_about_dialog/crux_about_dialog.dart';
import 'package:crux_app_info/crux_app_info.dart' as app_info;
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wavecrux/core/about/wavecrux_about_strings.dart';
import 'package:wavecrux/core/app_info/application_branding_provider.dart';
import 'package:wavecrux/core/app_info/application_build_info_provider.dart';
import 'package:wavecrux/core/app_info/application_edition_provider.dart';
import 'package:wavecrux/core/help_urls.dart';
import 'package:wavecrux/features/about/widgets/about_acknowledgments_screen.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/glowing_app_icon.dart';

/// The WaveCrux About dialog.
///
/// A thin builder over the cross-suite [CruxAboutDialog] (from
/// `crux_about_dialog`): it maps WaveCrux's branding / build-info / edition
/// providers and ARB strings onto the shared surface and supplies the
/// WaveCrux-specific pieces — the glowing app icon, the wellen attribution
/// section, and the action buttons (including the in-app Beta Issue Reporter
/// and the acknowledgments screen). Tier and beta-period chips are driven by
/// `crux_license` providers inside the shared widget.
abstract final class WaveCruxAboutDialog {
  /// Opens the About box: a modal dialog on desktop, a pushed route on mobile.
  static Future<void> openAdaptive(BuildContext context, WidgetRef ref) async {
    final l10n = L10N.of(context);

    final localBranding = ref.read(applicationBrandingProvider);
    final branding = app_info.ApplicationBranding(
      companyName: localBranding.companyName,
      // The branding assets live in the `wavecrux` package; address them with
      // the cross-package `packages/wavecrux/…` form so the shared banner can
      // load them without a `package:` argument.
      logoAssetPath: 'packages/wavecrux/${localBranding.logoAsset}',
      squareLogoAssetPath: 'packages/wavecrux/${localBranding.logoSquareAsset}',
      copyrightYear: localBranding.copyrightYear,
      websiteUrl: localBranding.websiteUrl,
    );

    // Resolve build info up front so the version section renders data rather
    // than a perpetual spinner — the provider is keepAlive and resolves in
    // milliseconds. On failure the shared widget hides the section.
    app_info.ApplicationBuildInfo? pkgInfo;
    AsyncValue<app_info.ApplicationBuildInfo> buildInfo;
    try {
      final info = await ref.read(applicationBuildInfoProvider.future);
      pkgInfo = app_info.ApplicationBuildInfo(
        version: info.version,
        buildNumber: info.buildNumber,
        gitShortSha: info.gitSha,
        os: info.os,
        architecture: info.architecture,
        flutterSdkVersion: info.flutterVersion,
        dartSdkVersion: info.dartVersion,
      );
      buildInfo = AsyncValue.data(pkgInfo);
    } on Object catch (error, stackTrace) {
      buildInfo = AsyncValue.error(error, stackTrace);
    }

    if (!context.mounted) return;

    final edition = ref.read(applicationEditionProvider(l10n));
    // A non-null capture so the Copy Version Info closure stays type-promoted.
    final info = pkgInfo;

    await CruxAboutDialog.show(
      context,
      title: l10n.aboutDialogTitle,
      tagline: l10n.aboutTagline,
      companyTagline: l10n.aboutCompanyName,
      appIcon: const GlowingAppIcon(size: 80),
      branding: branding,
      buildInfo: buildInfo,
      // Hide the edition chip for the open-core edition.
      editionLabel: edition == l10n.aboutEditionOpenCore ? '' : edition,
      strings: WaveCruxAboutStrings(l10n),
      attributions: [
        AboutAttributionSection(
          title: l10n.aboutSectionWellen,
          description: l10n.aboutWellenDescription,
          licenseHeader: l10n.aboutWellenLicenseHeader,
          licenseText: _wellenLicenseText,
        ),
      ],
      actions: [
        AboutAction(
          label: l10n.aboutButtonVisitWebsite,
          icon: Icons.language_outlined,
          onTap: (_) => unawaited(launchUrl(Uri.parse(branding.websiteUrl))),
        ),
        AboutAction(
          label: l10n.aboutButtonDocs,
          icon: Icons.menu_book_outlined,
          onTap: (_) => unawaited(launchUrl(Uri.parse(HelpUrls.docs))),
        ),
        AboutAction(
          label: l10n.aboutButtonReportIssue,
          icon: Icons.bug_report_outlined,
          // Promoted from a bare issue-tracker URL launch to the in-app Beta
          // Issue Reporter, which collects structured diagnostic context and
          // opens a pre-filled GitHub new-issue page.
          onTap: (ctx) => unawaited(CruxIssueReporterDialog.openAdaptive(ctx)),
        ),
        AboutAction(
          label: l10n.shortcutActionCheckForUpdates,
          icon: Icons.system_update_alt_outlined,
          // Same manual-check path as the Help-menu / palette action: runs
          // checkNow() and surfaces the banner / "up to date" / error result.
          onTap: (ctx) => unawaited(runManualUpdateCheck(ctx, ref)),
        ),
        AboutAction(
          label: l10n.aboutButtonPrivacy,
          icon: Icons.privacy_tip_outlined,
          onTap: (_) => unawaited(launchUrl(Uri.parse(HelpUrls.privacyPolicy))),
        ),
        AboutAction(
          label: l10n.aboutButtonTerms,
          icon: Icons.description_outlined,
          onTap: (_) =>
              unawaited(launchUrl(Uri.parse(HelpUrls.termsOfService))),
        ),
        AboutAction(
          label: l10n.aboutButtonCopyVersionInfo,
          icon: Icons.copy_outlined,
          onTap: info == null
              ? null
              : (ctx) => unawaited(_copyVersionInfo(ctx, l10n, edition, info)),
        ),
        AboutAction(
          label: l10n.aboutButtonAcknowledgments,
          icon: Icons.favorite_border_outlined,
          onTap: (ctx) =>
              unawaited(AboutAcknowledgmentsScreen.openAdaptive(ctx)),
        ),
      ],
    );
  }

  static Future<void> _copyVersionInfo(
    BuildContext context,
    L10N l10n,
    String edition,
    app_info.ApplicationBuildInfo info,
  ) async {
    await Clipboard.setData(
      ClipboardData(
        text: aboutVersionInfoText(
          appName: 'WaveCrux',
          editionLabel: edition,
          info: info,
        ),
      ),
    );
    if (context.mounted) {
      showCruxInfoSnack(context, l10n.aboutCopiedConfirmation);
    }
  }

  static const _wellenLicenseText = '''
Copyright (c) 2023, Kevin Laeufer
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.''';
}
