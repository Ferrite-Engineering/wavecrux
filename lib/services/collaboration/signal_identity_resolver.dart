// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';

/// Bidirectional map between a waveform's **canonical hierarchical paths**
/// (e.g. `"top.cpu.clk"`) and the **backend-local `signalRef`s** the active
/// [WaveformDataSource] queries with (a stringified wellen `u32` for FFI, a VCD
/// idcode for the pure-Dart parser).
///
/// View-composition sync crosses machines: the presenter and follower
/// may run different waveform backends, so the same signal has *different*
/// `signalRef`s on each. The recipe therefore travels in **path space** only —
/// the serialize seams translate live `signalRef`s to paths via [refToPath],
/// and the apply seams translate paths back to the follower's local
/// `signalRef`s via [pathToRef]. A path the follower's file lacks resolves to
/// `null`, which the apply seams degrade into a placeholder rather than a
/// crash.
///
/// Built once per serialize / apply pass from the source's full variable list —
/// the same `findVariables(SignalFilter())` sweep
/// [SignalGroupsNotifier.reresolveSignalRefs] already uses for the cross-backend
/// session-restore path.
class SignalIdentityResolver {
  SignalIdentityResolver({
    required Map<String, String> pathToRef,
    required Map<String, String> refToPath,
  }) : _pathToRef = pathToRef,
       _refToPath = refToPath;

  /// Build a resolver from the active [source]'s full hierarchy.
  factory SignalIdentityResolver.fromSource(WaveformDataSource source) {
    final pathToRef = <String, String>{};
    final refToPath = <String, String>{};
    for (final v in source.findVariables(const SignalFilter())) {
      pathToRef[v.fullPath] = v.signalRef;
      refToPath[v.signalRef] = v.fullPath;
    }
    return SignalIdentityResolver(pathToRef: pathToRef, refToPath: refToPath);
  }

  final Map<String, String> _pathToRef;
  final Map<String, String> _refToPath;

  /// The local `signalRef` for canonical [path], or `null` when no variable in
  /// the hierarchy matches it (a missing reference).
  String? refForPath(String path) => _pathToRef[path];

  /// The canonical path for backend-local [signalRef], or [signalRef] verbatim
  /// when it does not resolve (best-effort: keeps the recipe self-describing
  /// even for an unexpected ref).
  String pathForRef(String signalRef) => _refToPath[signalRef] ?? signalRef;

  /// Read-only view of the path → ref map (for the signal-list re-resolve seam,
  /// which already walks entries against such a map).
  Map<String, String> get pathToRef => _pathToRef;
}

/// Best-effort single lookup of the canonical hierarchical `fullPath` for a
/// backend-local [signalRef] in [source], without building the full
/// bidirectional [SignalIdentityResolver] map.
///
/// A `signalRef` is a per-process/per-backend handle (a wellen `u32` for FFI, a
/// VCD idcode for the Dart parser) — it means nothing to any OTHER process, so
/// it must never travel on the wire. Cross-tool cross-probe (WaveCrux → NetCrux
/// / peers) has to send the signal in PATH space; this resolves the selected
/// ref to that path. Returns `null` when no variable matches (an empty or stale
/// selection), so the caller can skip rather than emit an unresolvable ref.
String? fullPathForSignalRef(WaveformDataSource source, String signalRef) {
  for (final v in source.findVariables(const SignalFilter())) {
    if (v.signalRef == signalRef) return v.fullPath;
  }
  return null;
}
