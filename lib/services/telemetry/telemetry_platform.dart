// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart' show kTelemetryFormFactors;
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';

/// Maps the layout idiom the app **already** uses onto the coarse
/// `form_factor` bucket (`crux_telemetry`'s [kTelemetryFormFactors]).
///
/// This is the one half of the telemetry envelope that stayed in WaveCrux
/// after the `crux_telemetry` extraction, and deliberately: the derivation
/// reads [DeviceClass] rather than a new breakpoint set, so telemetry can
/// never disagree with what the user is actually looking at. If the app drew
/// phone chrome, the event says `phone`. A second breakpoint set inside the
/// shared package is exactly how the two would come to disagree, so the
/// package keeps only the closed vocabulary and takes the mapping through
/// `telemetryFormFactorProvider`.
///
/// [DeviceClass.phone] and [DeviceClass.phoneLandscape] both report `phone` —
/// the landscape split exists to decide whether side panels fit, which is a
/// layout question, not a "what kind of device is this" question.
///
/// **[hostKind] is tested first, ahead of [isWeb], and that order is the whole
/// point of the parameter.** `kIsWeb` is **true inside a VSCode webview**, so
/// with the web short-circuit first every EDACrux extension user would report
/// `web` — indistinguishable from wavecrux.app traffic. Two things would break
/// at once: extension adoption, the number the Marketplace channel exists to
/// produce, would be unmeasurable; and the `web`-vs-`desktop` split this
/// function's own doc comment says exists to answer "does the web build earn
/// its maintenance" would quietly count extension traffic as browser traffic.
/// The second is the worse of the two, because a wrong bucket is *accepted* by
/// the ingestion Worker and reads as measurement forever after.
///
/// The editor-host signal comes from the host bridge — the thing that only
/// exists when VSCode is hosting us — and deliberately **not** from the user
/// agent or the URL scheme, either of which would make the bucket a guess. See
/// [EditorHostKind]. `os` stays `web` for an editor-hosted build; that remains
/// honest, and the host OS is not worth a second mechanism to recover.
///
/// `kIsWeb` wins over the device class: a browser tab is a browser tab whatever
/// its width, and `web` vs `desktop` is the split the roadmap question actually
/// needs. No dimensions are sent, and none are derivable from the five buckets.
///
/// **Returns `null` when [deviceClass] is `null`** — "the layout idiom is not
/// knowable yet", which `resolvedDeviceClassForSize` reports before the first
/// display size lands. `crux_telemetry` reads that as "defer": the envelope
/// resolves to `null`, the flush skips, and the events stay queued for the next
/// tick, exactly as they do while `app_version` is still loading. It costs one
/// flush interval and it is the whole point of this signature.
///
/// The alternative — answering `desktop` because nothing better is available
/// yet — is what shipped, and it reported `desktop` from a `w800dp` Pixel
/// Tablet held in portrait on three of four launches. A wrong `form_factor` is
/// worse than an absent one in a way a wrong `app_version` is not: the Worker
/// rejects a bad version and the batch is visibly lost, whereas a bad bucket is
/// accepted and reads as measurement forever after.
///
/// Note what does **not** defer. `isWeb` is a compile-time constant; on a
/// native desktop host `resolvedDeviceClassForSize` answers unconditionally
/// without a size; and [hostKind] is resolved synchronously at startup from a
/// marker the extension's `index.html` shim sets before `main.dart.js` runs.
/// None of the three races anything, so none of them may cost a flush.
String? telemetryFormFactorFor({
  required bool isWeb,
  required DeviceClass? deviceClass,
  EditorHostKind hostKind = EditorHostKind.none,
}) {
  // Ahead of the isWeb branch on purpose — see the doc comment. Not guarded on
  // isWeb: an editor host is an editor host, and a bridge that reports one on a
  // build we thought could not have one is telling us something true.
  if (hostKind == EditorHostKind.vscode) return 'vscode';
  if (isWeb) return 'web';
  if (deviceClass == null) return null;
  return switch (deviceClass) {
    DeviceClass.phone || DeviceClass.phoneLandscape => 'phone',
    DeviceClass.tablet => 'tablet',
    DeviceClass.desktop => 'desktop',
  };
}
