// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart' show NotifySelection;
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/services/remote/cxp/cxp_selection_emitter.dart';

/// Bridges WaveCrux's per-tab selection providers (signal, cursor, markers) to
/// outbound CXP `notify_selection` broadcasts.
///
/// Built once and kept for the life of the app; it does not watch the runtime.
/// The app reads this provider a single time at launch, and nothing reads it
/// again, so a provider that watched the runtime would be marked dirty when the
/// server came up and, with no listener to rebuild it, would stay disposed: no
/// selection would ever be broadcast. Instead the sink looks up the running
/// runtime at send time (`broadcastCruxCxpSelection`), so a selection reaches
/// peers whenever a server is up, across restarts, and is dropped while it is
/// stopped or the user has the broadcast off.
final Provider<CxpSelectionEmitter> cxpSelectionEmitterProvider =
    Provider<CxpSelectionEmitter>((ref) {
      final emitter = CxpSelectionEmitter(
        ref: ref,
        sink: (message, {summary}) {
          if (message is NotifySelection) {
            broadcastCruxCxpSelection(ref.read, message);
          }
        },
      )..start();
      ref.onDispose(emitter.dispose);
      return emitter;
    }, name: 'cxpSelectionEmitterProvider');
