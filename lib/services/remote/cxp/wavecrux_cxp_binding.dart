// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:wavecrux/services/remote/cxp/cxp_workspace_link.dart'
    show kCxpOpenArtifactContainment;
import 'package:wavecrux/services/remote/cxp/wavecrux_name_resolver.dart';

/// Who WaveCrux is on CXP: its wire name, default port, the preference-key
/// prefix its saved settings have always used, the capabilities it advertises,
/// the element kinds a peer's highlight can land on, and how received paths
/// are screened.
///
/// The shared runtime does the rest (start and stop, discovery, peers,
/// settings persistence, acknowledgements).
const CruxCxpProductBinding kWaveCruxCxpBinding = CruxCxpProductBinding(
  productName: 'wavecrux',
  defaultPort: 54322,
  prefsPrefix: 'settings.',
  capabilities: <String>{'wavecrux.signal_value', 'wavecrux.cursor_time_fs'},
  acceptedKinds: <ElementKind>[
    ElementKind.signal,
    ElementKind.instance,
    ElementKind.net,
    ElementKind.port,
    ElementKind.scope,
    ElementKind.marker,
    ElementKind.source,
  ],
  // The floor, not the directories the user has opened. One rule screens both
  // `request_open_source` and `request_open_artifact`, and a rooted one strips
  // the path hint from a `request_open_artifact` for a waveform WaveCrux has
  // never opened, the very request that route exists to honour. A
  // `request_open_source` keeps its roots: `dispatchCxpOpenSource` applies the
  // rooted rule to the path it is about to hand an editor.
  // Named although it is the binding's default, so the decision is visible
  // where the binding is built.
  // ignore: avoid_redundant_argument_values
  containment: kCxpOpenArtifactContainment,
  nameResolver: WaveCruxNameResolver(),
);
