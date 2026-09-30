// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:url_launcher/url_launcher.dart';
import 'package:wavecrux/core/app_info/application_build_info_provider.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_config.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_storage.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/services/host_bridge/editor_host_provider.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_provider.dart';
import 'package:wavecrux/services/host_bridge/host_relay_telemetry_service.dart';
import 'package:wavecrux/services/telemetry/telemetry_platform.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Root-scope overrides binding the cross-suite `crux_telemetry` package to
/// WaveCrux's own configuration, persistence, build metadata, layout idiom,
/// locale, and URL launcher.
///
/// Spread into the root `ProviderContainer` by `bootstrap`, ahead of the
/// Pro overlay's `proOverrides` so the overlay can layer on top
/// under the standard later-wins conflict semantics — that is where the
/// Enterprise `.crux-policy.json` `telemetry: allow | deny` key binds. The
/// overlay overrides `crux_telemetry`'s `telemetryPolicyProvider` from
/// `crux_license`'s `dayOnePolicyProvider`, which reads the file through
/// `crux_policy`'s signature-checking `PolicyLoader`. Open core binds no
/// telemetry policy, so the policy resolves `absent` here. The seam and the
/// whole precedence it selects (the beta gate beats the policy, the policy
/// beats the individual's stored consent, and neither consent surface mounts
/// under a policy) ship and are tested in `crux_telemetry`.
///
/// The localized string bundle is deliberately **not** here: it needs a
/// `BuildContext` to resolve `L10N.of(context)`, so `WaveCruxApp` overrides
/// `cruxTelemetryStringsProvider` from inside `MaterialApp.builder` instead —
/// exactly as it does for `cruxUpdateStringsProvider`.
final List<Override> wavecruxTelemetryOverrides = <Override>[
  // The one binding with no working default. A product that forgets it throws
  // at wiring rather than reporting somebody else's product slug on every
  // batch — and a wrong slug is rejected by the Worker with a 400 the client
  // never sees.
  cruxTelemetryConfigProvider.overrideWithValue(wavecruxTelemetryConfig),

  // Where `telemetry.consent` and `telemetry.installationId` live. The package
  // default is an in-memory store, which would re-prompt the disclosure every
  // launch and re-mint the installation id every session.
  telemetryStorageProvider.overrideWithValue(const WavecruxTelemetryStorage()),

  // "Learn more" on both consent surfaces. The package default throws rather
  // than silently doing nothing when the user taps a link on a privacy notice.
  telemetryUrlLauncherProvider.overrideWithValue(launchUrl),

  // The `app_version` envelope field. Until this resolves the package's
  // envelope resolver returns null and the flush skips — a version we do not
  // have must not be invented, because a bad `app_version` rejects the whole
  // batch at the Worker.
  telemetryAppVersionProvider.overrideWith(
    (ref) async =>
        (await ref.watch(applicationBuildInfoProvider.future)).version,
  ),

  // The `form_factor` bucket, derived from the layout idiom the app actually
  // drew. This stays in WaveCrux on purpose: a second breakpoint set inside
  // `crux_telemetry` is how telemetry would come to disagree with what the
  // user is looking at.
  //
  // Reads `displaySizeProvider` through `resolvedDeviceClassForSize` rather
  // than `deviceClassProvider`, and the difference is the whole fix: the latter
  // answers `desktop` when no size has been reported yet, which is right for a
  // layout consumer (they build inside the tree, after the first size) and
  // wrong here. Telemetry resolves its envelope from a service on the launch
  // flush — ahead of `DisplaySizeFeed` in `MaterialApp.builder` — so it is the
  // one reader that observes the pre-layout window, and it did: a Pixel Tablet
  // in portrait reported `desktop` on three of four launches. `null` tells
  // `crux_telemetry` to skip this flush and ask again on the next tick.
  //
  // `hostKind` comes from the host bridge and is read here rather than sniffed,
  // because `kIsWeb` is true inside a VSCode webview: without it every
  // extension user would report `web`, losing the adoption signal the
  // Marketplace channel exists to produce AND folding extension traffic into
  // the web build's own numbers. It defaults to "not hosted", so desktop,
  // mobile and browser builds need no wiring at all.
  telemetryFormFactorProvider.overrideWith(
    (ref) => telemetryFormFactorFor(
      isWeb: kIsWeb,
      deviceClass: resolvedDeviceClassForSize(ref.watch(displaySizeProvider)),
      hostKind: ref.watch(editorHostKindProvider),
    ),
  ),

  // The display language actually in effect — the field that answers whether
  // the zh/zh_CN/ja/ko localizations earn their maintenance cost. Falls back to
  // the seam default while settings are still loading; a flush that early has
  // nothing queued to send anyway.
  telemetryLocaleProvider.overrideWith(
    (ref) => ref.watch(appSettingsProvider).value?.locale ?? 'en',
  ),
];

/// The one override a build with an editor host on the other end adds: **this
/// process is not the sender**.
///
/// Spread by `bootstrap` after [wavecruxTelemetryOverrides], and only when
/// [hostKind] is not [EditorHostKind.none]. Returns an empty list otherwise, so
/// desktop, mobile and a plain browser tab keep the pipeline they have.
///
/// A *startup* decision rather than a `ref.watch` inside the override, because
/// the answer cannot change: the marker the host bridge reads is set by the
/// extension's `index.html` shim before `main.dart.js` runs, and nothing later
/// can make a hosted build unhosted or the reverse. Deciding it once also means
/// the live service is never even constructed in a hosted build — there is no
/// window in which the on-disk queue exists or the ingestion endpoint has been
/// resolved.
///
/// **Why replace the whole service rather than tighten the gate.** A VSCode
/// extension answers to `vscode.env.isTelemetryEnabled`, which host-core
/// applies at send time; host-core is the pack's only sender. A Dart half that
/// kept its own pipeline would answer to `crux_telemetry`'s consent store
/// instead, and a user who turned telemetry off in VSCode would still be
/// reported on by the panel inside it. Setting `TelemetryPolicy.deny` would
/// silence this half but *discard* the events rather than hand them over,
/// losing the extension's usage signal entirely — which is the one number the
/// Marketplace channel exists to produce.
///
/// See [HostRelayTelemetryService] for what crosses (the `{name, properties}`
/// descriptor, never an envelope) and why the host treats it as untrusted.
List<Override> wavecruxHostRelayTelemetryOverrides(EditorHostKind hostKind) =>
    hostKind == EditorHostKind.none
    ? const <Override>[]
    : <Override>[
        telemetryServiceProvider.overrideWith(
          (ref) =>
              HostRelayTelemetryService(ref.watch(hostBridgeChannelProvider)),
        ),
      ];
