// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Canonical URLs for WaveCrux documentation pages.
///
/// Documentation links point at `https://docs.wavecrux.app/<page>#<anchor>`,
/// where `<page>` is a `docs-site/docs/<page>.md` file and `<anchor>` an id on
/// that page (`test/core/help_urls_test.dart` checks both). Define every
/// help-link destination here so the full URL list is maintainable in one
/// place.
abstract final class HelpUrls {
  static const _base = 'https://docs.wavecrux.app';

  /// Decoder ids with their own entry on the Protocol decoders page, across
  /// every tier (the page documents Open Core, Pro and Enterprise decoders).
  static const documentedDecoderIds = <String>{
    'spi',
    'spi_flash',
    'i2c',
    'uart',
    'axi4_lite',
    'apb',
    'ahb_lite',
    'wishbone',
    'riscv',
    'microblaze',
    'lm32',
    'axi4_full',
    'can',
    'usb2',
    'pcie_tlp',
    'jtag',
    'mdio',
    'axi_stream',
    'avalon_mm',
    'avalon_st',
    'ethernet_axis',
    'ethernet_mii',
    'ethernet_rmii',
    'ethernet_gmii',
    'ethernet_rgmii',
  };

  /// Returns the documentation URL for a decoder's help link.
  ///
  /// A documented decoder links to its entry on the Protocol decoders page, a
  /// `sigrok.*` decoder to the Sigrok bridge page, and any other id — a native
  /// plugin's — to the plugin authoring guide.
  static String decoder(String decoderId) {
    if (decoderId.startsWith('sigrok.')) return sigrokDecoders;
    if (documentedDecoderIds.contains(decoderId)) {
      return '$_base/protocol-decoders#$decoderId';
    }
    return decoderPlugins;
  }

  /// Using a decoder that comes from the Sigrok bridge.
  static const sigrokDecoders = '$_base/sigrok-bridge#decode';

  /// The decoder plugin authoring guide.
  static const decoderPlugins = '$_base/authoring-custom-decoders';

  /// Building a decoder plugin and installing it into a plugin directory.
  static const decoderPluginsInstall =
      '$_base/authoring-custom-decoders#install';

  /// What loading a native decoder plugin means for security.
  static const decoderPluginsSecurity =
      '$_base/authoring-custom-decoders#security';

  /// Overview of the WaveCrux Stage animated-signal panel system.
  static const stage = '$_base/stage';

  /// GTKWave-compatible translate filter files and processes.
  static const translateFilters = '$_base/working-with-signals#filters';

  /// Connecting to the WCP remote control server.
  static const remoteApi = '$_base/automation-and-collaboration#wcp-connect';

  /// Multi-signal pattern search expression syntax.
  static const patternSearch = '$_base/analysis#pattern-search';

  /// Waveform comparison / diff feature guide.
  static const diff = '$_base/analysis#diff';

  /// WaveCrux marketing / home page.
  static const website = 'https://wavecrux.app';

  /// Download page for the latest build — surfaced by the beta build-expiry
  /// banner / blocking modal so an expiring or expired beta sends the user
  /// straight to the current release. Also the desktop/web target of the
  /// update banner's "Update Now" action.
  static const download = 'https://wavecrux.app/download';

  /// Apple App Store listing — the iOS/iPadOS target of the update banner's
  /// "Update Now" action.
  static const appStore = 'https://apps.apple.com/app/wavecrux/id6787506007';

  /// Google Play listing — the Android target of the update banner's
  /// "Update Now" action.
  static const playStore =
      'https://play.google.com/store/apps/details?id=com.ferriteengineering.wavecrux';

  /// WaveCrux documentation home.
  static const String docs = _base;

  /// Privacy policy, shared by every EDACrux product.
  static const privacyPolicy = 'https://edacrux.app/privacy';

  /// Suite-wide telemetry disclosure — the exact field list, the never-collect
  /// list, and the source links.
  ///
  /// Deliberately **not** under `docs.wavecrux.app`: the four products share
  /// one client pipeline, one ingestion Worker, and one dataset, so four
  /// per-product copies of the same page would be four places for the same
  /// promise to drift. Linked from the first-launch disclosure and from
  /// Settings → Privacy.
  static const telemetry = 'https://edacrux.app/telemetry';

  /// Terms of service, shared by every EDACrux product.
  static const termsOfService = 'https://edacrux.app/terms';

  /// Suite home — the target of the welcome screen's suite-membership line.
  ///
  /// A per-product path rather than the shared `/products` page, and that is
  /// the whole point: the site's page-view beacon records the path and
  /// deliberately drops the query string, so `?from=wavecrux` would be
  /// invisible and a desktop app sends no referrer. The path is how the visit
  /// is attributed to the app that sent it.
  static const suiteHome = 'https://edacrux.app/from/wavecrux';

  /// The suite landing path, scrolled to one peer product's card.
  ///
  /// The fragment is free: the site's beacon drops it before sending, so this
  /// is still recorded as `/from/wavecrux` and the per-product attribution is
  /// unaffected — while the reader still lands on the product the row named
  /// rather than at the top of a page listing three.
  static String suitePeer(String slug) => '$suiteHome#$slug';

  /// Support email — report a bug or feature request.
  static const reportIssue = 'mailto:support@ferriteengineering.com';
}
