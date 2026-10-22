// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show Platform;

import 'package:crux_linux_integration/crux_linux_integration.dart'
    show LinuxDesktopApp;
import 'package:crux_single_instance/crux_single_instance.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:wavecrux/services/links/wavecrux_link.dart';

/// Whether this host opens a link by starting a new process: Windows and
/// Linux. macOS hands the link to the running application itself, and the web,
/// iOS and Android register no scheme.
bool get handsLinksToRunningInstance =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux);

/// The `wavecrux://` link policy the running instance enforces: one URL of our
/// scheme, no white space or control characters, no longer than the app's own
/// parser accepts. The parser still decides what a link asks for.
SingleInstanceLinkPolicy waveCruxSingleInstancePolicy() =>
    SingleInstanceLinkPolicy(
      schemes: const [kWaveCruxLinkScheme],
      // Tied to the parser's bound, not to the package's default, which
      // happens to be the same number today.
      // ignore: avoid_redundant_argument_values
      maxLinkBytes: kWaveCruxLinkMaxLength,
    );

/// Claims the single running instance, or hands this launch's link to it.
///
/// Returns null on a host that opens a link in the running application
/// already (macOS, the web and mobile), where nothing is claimed. Otherwise
/// the claim: [SingleInstanceDelivered] means the running instance has the
/// link and this process should exit; [SingleInstancePrimary] means this is
/// the running instance; [SingleInstanceStandalone] means carry on as a
/// launch that knows nothing of any other.
///
/// A launch carries a link only when [launchLinks] holds exactly one; more
/// than one is refused as a whole by the app's own parser, so it is not
/// forwarded.
///
/// [singleInstance] replaces the platform's claim and, being given, switches
/// the claim on for any host; it exists for tests.
Future<SingleInstanceClaim?> claimSingleInstance({
  required LinuxDesktopApp desktopApp,
  required List<String> launchLinks,
  SingleInstance? singleInstance,
}) async {
  if (singleInstance == null && !handsLinksToRunningInstance) return null;
  final instance =
      singleInstance ??
      SingleInstance(
        appId: desktopApp.appId,
        policy: waveCruxSingleInstancePolicy(),
      );
  final claim = await instance.claim(
    link: launchLinks.length == 1 ? launchLinks.single : null,
  );
  return claim;
}
