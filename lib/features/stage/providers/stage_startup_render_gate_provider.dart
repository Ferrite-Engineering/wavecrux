// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'stage_startup_render_gate_provider.g.dart';

/// Defers the Stage panel's GPU-heavy instance content out of the cold-start
/// restore burst.
///
/// The Windows/Intel `ExitProcess(0x8F)` crash documented in
/// `docs/flutter-windows-gpu-crash-issue.md` is a concurrency race in GPU
/// device/surface initialization whose probability rises with the number of
/// views that restore their saved content *in the same startup burst* (0–2
/// views: 0 crashes; 4 views: ~50–100%). A single restored tab can already
/// bring up three such views — signal tree, waveform canvas, value column — and
/// a wired Stage board (its bound slots rebuild into board/LED content the
/// moment the restored signals settle, i.e. right as the canvas restoration
/// lands) is a heavy fourth. That is the count the crash data shows tipping into
/// the failure zone, which is why a tab with a Stage board reliably wedges
/// reload while the same tab without one does not.
///
/// `bootstrap()`'s app shell engages this gate at the start of a guarded restore
/// and releases it once the active tab's restore has rendered a content frame
/// (the same point the restore guard stands down). While engaged, the Stage
/// instance canvas paints a lightweight placeholder instead of building its
/// bound board content, so the board's GPU work lands in a later frame, on its
/// own — serialized behind the canvas restoration exactly as the proven
/// mitigation for this crash requires (load/render one view at a time).
///
/// Defaults to `false` (not gated): outside a guarded cold-start restore — and
/// in every test that does not override it — the Stage renders immediately.
@Riverpod(keepAlive: true)
class StageStartupRenderGate extends _$StageStartupRenderGate {
  @override
  bool build() => false;

  /// Engages the gate — the Stage instance canvas defers its board content.
  void engage() => state = true;

  /// Releases the gate — the Stage instance canvas builds its content.
  void release() => state = false;
}
