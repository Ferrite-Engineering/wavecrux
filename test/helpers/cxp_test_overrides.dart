// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_binding.dart';

/// What a root container needs for a surface that reads the shared CXP
/// providers without testing CXP: the toolbar's peer badge, the selection
/// emitter's broadcast gate, a signal row's "Cross-probe to" item.
///
/// The app binds WaveCrux's identity in `bootstrap()`; reading the shared
/// providers without it is a wiring error. The transport is switched off, so a
/// test that pretends to be a desktop (a `TargetPlatformVariant`) never starts
/// a runtime, binds a socket or writes a manifest into the shared directory.
/// A test that is about CXP binds its own transport instead.
final List<Override> cxpTestOverrides = <Override>[
  cruxCxpProductBindingProvider.overrideWithValue(kWaveCruxCxpBinding),
  cruxCxpTransportAvailableProvider.overrideWithValue(false),
  // Settings known up front, so nothing loads in the background and outlives
  // the test's container.
  cruxCxpLaunchSettingsProvider.overrideWithValue(
    const CruxCxpSettings(enabled: false, port: 54322),
  ),
];
