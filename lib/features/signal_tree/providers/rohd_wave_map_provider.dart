// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/rohd/rohd_sidecar_locator.dart';
import 'package:wavecrux/services/rohd/rohd_wave_map.dart';

part 'rohd_wave_map_provider.g.dart';

/// The ROHD source map for the open waveform, or `null` when there is no
/// waveform or no usable source-trace file for it (ROHD 0.7 or later, source
/// tracing).
///
/// Read when the signal tree opens a signal's context menu, so a waveform that
/// was not written by ROHD costs one directory listing and shows nothing.
/// Rebuilds when the waveform, its hierarchy or the sidecar setting changes.
///
/// `dependencies` is declared so this follows the per-tab container, as the
/// other providers over the waveform source do.
@Riverpod(dependencies: [WaveformSourceNotifier, hierarchy])
Future<RohdWaveMap?> rohdWaveMap(Ref ref) {
  ref.watch(waveformSourceProvider);
  final path = ref.read(waveformSourceProvider.notifier).currentFilePath;
  if (path == null) return Future<RohdWaveMap?>.value();
  final configured =
      ref.watch(appSettingsProvider).value?.rohdSidecarPath ?? '';
  final scopes = ref.watch(hierarchyProvider).value ?? const [];
  return loadRohdWaveMap(
    waveformPath: path,
    configured: configured,
    topScopes: {for (final s in scopes) s.path},
  );
}
