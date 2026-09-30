// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_policy/crux_policy.dart';

/// WaveCrux's namespace in `.crux-policy.json`, and its audit event kinds.
///
/// **These declare the keys; they do not implement the features the keys
/// configure.** Theme packs, workspace templates, symbol libraries, the
/// retention policy and the CI gate threshold are separate follow-ups that
/// become small once this exists. What this file buys is that a key an
/// administrator writes is a key the application honours, with the shared
/// precedence and the shared diagnostics.
///
/// The normative key reference is published at
/// `https://edacrux.app/policy-reference`. Register against **its** names: it
/// unifies several keys the four products once named differently, so older
/// wording elsewhere is not authoritative here.
abstract final class WaveCruxPolicyKeys {
  /// The product id this namespace lives under.
  static const String productId = 'wavecrux';

  /// `products.wavecrux.signalGroups` — org-standard signal groupings.
  static const String signalGroups = 'signalGroups';

  /// `products.wavecrux.decoderSettings` — default protocol-decoder configuration.
  static const String decoderSettings = 'decoderSettings';

  /// `products.wavecrux.sessionTemplates` — a workspace-template reference on the org's share.
  static const String sessionTemplates = 'sessionTemplates';

  /// `products.wavecrux.themePacks` — a theme pack by path or content hash.
  static const String themePacks = 'themePacks';

  /// `products.wavecrux.wcpServer` — whether the WCP remote-API server may run.
  static const String wcpServer = 'wcpServer';

  /// `products.wavecrux.cxpServer` — whether the CXP peer server may run.
  static const String cxpServer = 'cxpServer';

  /// `products.wavecrux.approvedPlugins` — decoder plugins approved by SHA-256.
  ///
  /// **The one key here whose absence is load-bearing.** No key means no
  /// constraint and every plugin loads as before; an *empty list* means no
  /// plugins are approved and is honoured; a malformed value degrades to
  /// absent rather than to empty, because a typo must not stop every plugin in
  /// the fleet. See `services/decoders/ffi/plugin_allowlist.dart` and
  /// `https://edacrux.app/policy-reference`.
  static const String approvedPlugins = 'approvedPlugins';

  /// Every key this product registers, for the conformance test.
  static const Set<String> all = <String>{
    signalGroups,
    decoderSettings,
    sessionTemplates,
    themePacks,
    wcpServer,
    cxpServer,
    approvedPlugins,
  };
}

/// The audit events WaveCrux records.
///
/// **Kinds are per-product on purpose.** The envelope is shared; a shared enum
/// of kinds would need editing in `crux-shared` every time any one of four
/// products learned a new event.
abstract final class WaveCruxAuditKinds {
  /// `session.saved`
  static const String sessionSaved = 'session.saved';

  /// `decoder.activated`
  static const String decoderActivated = 'decoder.activated';

  /// `stage.widget.loaded`
  static const String stageWidgetLoaded = 'stage.widget.loaded';

  /// `plugin.load.attempted`
  static const String pluginLoadAttempted = 'plugin.load.attempted';

  /// `pro.feature.activated`
  static const String proFeatureActivated = 'pro.feature.activated';

  /// `license.tier.changed`
  static const String licenseTierChanged = 'license.tier.changed';

  /// Every kind this product registers, for the conformance test.
  static const Set<String> all = <String>{
    sessionSaved,
    decoderActivated,
    stageWidgetLoaded,
    pluginLoadAttempted,
    proFeatureActivated,
    licenseTierChanged,
  };
}

/// A resolver scoped to this product's namespace.
///
/// A key naming a *different* product is ignored silently — one file serves a
/// mixed fleet, so a WaveCrux install meeting another product's keys is the
/// normal case rather than a misconfiguration.
PolicyResolver wavecruxPolicyResolver(PolicyDocument document) =>
    PolicyResolver(document: document, productId: WaveCruxPolicyKeys.productId);
