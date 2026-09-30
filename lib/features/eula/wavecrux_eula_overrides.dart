// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show exit;

import 'package:crux_eula/crux_eula.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:url_launcher/url_launcher.dart';
import 'package:wavecrux/core/eula/wavecrux_eula_storage.dart';

/// Where the published agreement lives. The dialog carries the full text
/// already; this is for a user who wants it in a browser tab, to print or to
/// send to someone.
const String kWavecruxEulaUrl = 'https://edacrux.app/eula';

/// Root-scope overrides binding the cross-suite `crux_eula` package to
/// WaveCrux's persistence and its quit path.
///
/// Spread into the root `ProviderContainer` by `bootstrap`, ahead of the Pro
/// overlay's `proOverrides` under the standard later-wins semantics. The
/// overlay adds nothing here today: acceptance is required at every edition,
/// so there is no Pro-only behaviour to layer on.
final List<Override> wavecruxEulaOverrides = <Override>[
  // Where `eula.acceptedVersion` lives. The package default is an in-memory
  // store, which would present the agreement on every launch.
  cruxEulaStorageProvider.overrideWithValue(const WavecruxEulaStorage()),

  // "Read it on edacrux.app". Unbound, the package hides the link rather than
  // rendering one that does nothing.
  cruxEulaOpenOnlineProvider.overrideWithValue(
    () => launchUrl(Uri.parse(kWavecruxEulaUrl)),
  ),

  // Decline ends the session, because EULA section 2.1 leaves no third
  // outcome — the application does not proceed until the agreement is
  // accepted.
  //
  // Not bound on the web, where there is no process to exit and closing the
  // tab is the browser's affordance, not ours. The package hides the button
  // when this is null, which is the honest surface there: a "quit" that
  // cannot quit would be worse than no button.
  //
  // `exit(0)` rather than a graceful pop, matching what the File → Quit menu
  // action does — there is no unsaved user work at this point in startup,
  // because nothing has been opened yet.
  if (!kIsWeb) cruxEulaOnDeclineProvider.overrideWithValue(() => exit(0)),
];
