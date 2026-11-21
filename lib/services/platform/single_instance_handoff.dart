// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;

import 'package:crux_linux_integration/crux_linux_integration.dart'
    show LinuxDesktopApp;
import 'package:crux_single_instance/crux_single_instance.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
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

/// How long an exit request waits for the claim to be released.
const Duration _releaseBudget = Duration(seconds: 2);

/// Releases [primary] when the app is asked to exit, then lets the exit go
/// ahead. Never vetoes.
///
/// An orderly quit (a window close, a quit from the system, and on Linux
/// SIGTERM and SIGHUP, which `routeTerminationSignalsThroughExitRequest`
/// turns into the same request) reaches Dart as an exit request; closing the
/// claim there removes the socket, the advert and the lock file instead of
/// leaving them for the next launch to clear.
///
/// The close must stay reachable from the running app. The claim holds its
/// lock through an open file that only [SingleInstancePrimary.close] reads,
/// so an ahead-of-time build in which nothing calls close drops that file
/// as unused: its finalizer closes the descriptor, the lock goes with it,
/// and every later launch becomes a second running instance instead of
/// handing its link over.
///
/// Needs the widgets binding. Returns the listener, which stays registered
/// with the binding until disposed.
AppLifecycleListener releaseSingleInstanceOnExit(
  SingleInstancePrimary primary,
) => AppLifecycleListener(
  onExitRequested: () async {
    try {
      await primary.close().timeout(_releaseBudget);
    } on Object {
      // Best effort: the process ending releases the lock as well.
    }
    return AppExitResponse.exit;
  },
);
