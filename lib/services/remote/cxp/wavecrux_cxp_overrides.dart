// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_license/crux_license.dart' show cruxPolicyProvider;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wavecrux/core/app_info/application_build_info_provider.dart';
import 'package:wavecrux/core/policy/org_server_policy.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_binding.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_request_handler.dart';

/// What `bootstrap()` hands the root container to run WaveCrux's side of CXP
/// on the shared lifecycle.
///
/// On a desktop it loads the saved CXP settings first, so a launch with CXP
/// off never starts the server or writes a manifest, even briefly. On the web
/// and on a phone no CXP code runs, and the settings are left to load lazily.
///
/// The organization's policy still decides whether the server may run: the
/// shared runtime asks [cruxCxpServerPolicyProvider], answered here by
/// `resolveCxpServerPolicy` (a locked org value beats the engineer's own
/// setting).
Future<List<Override>> wavecruxCxpOverrides() async {
  final launch = cruxCxpDesktopHost()
      ? await loadCruxCxpLaunchSettings(kWaveCruxCxpBinding)
      : null;
  return <Override>[
    cruxCxpProductBindingProvider.overrideWithValue(kWaveCruxCxpBinding),
    if (launch != null) cruxCxpLaunchSettingsProvider.overrideWithValue(launch),
    cruxCxpRequestHandlerProvider.overrideWith(WaveCruxCxpRequestHandler.new),
    cruxCxpProductVersionProvider.overrideWith((ref) async {
      try {
        return (await ref.watch(applicationBuildInfoProvider.future)).version;
      } on Object {
        return 'dev';
      }
    }),
    cruxCxpAttentionRequesterProvider.overrideWithValue(
      () => unawaited(requestUserAttention()),
    ),
    cruxCxpServerPolicyProvider.overrideWith((ref) {
      final policy = ref.watch(cruxPolicyProvider).document;
      return ({required bool userEnabled}) =>
          resolveCxpServerPolicy(policy, userSetting: userEnabled).value;
    }),
    crossProbeSendObserverProvider.overrideWith(
      (ref) => (record) {
        // Only a send that left this process is a cross-probe; a gate that
        // refused, an empty selection, a server that is off and an empty peer
        // list never reached a peer.
        final kind = record.outcome.kind;
        if (kind == CrossProbeOutcomeKind.denied ||
            kind == CrossProbeOutcomeKind.nothingSelected ||
            kind == CrossProbeOutcomeKind.serverOff ||
            kind == CrossProbeOutcomeKind.noPeers) {
          return;
        }
        ref
            .read(telemetryServiceProvider)
            .record(
              TelemetryEvent(
                'cxp.crossprobe',
                properties: <String, Object?>{
                  'direction': 'outbound',
                  'honored': kind == CrossProbeOutcomeKind.sent,
                },
              ),
            );
      },
    ),
  ];
}
