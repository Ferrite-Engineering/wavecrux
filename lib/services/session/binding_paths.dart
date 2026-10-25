// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';

/// A saved decoder or Stage binding whose hierarchical path names no signal
/// in the opened waveform.
@immutable
class UnresolvedBinding {
  const UnresolvedBinding({
    required this.owner,
    required this.slot,
    required this.path,
  });

  /// What held the binding: `"<decoderId> #<instanceNumber>"` for a decoder,
  /// the instance label (or widget id) for a Stage widget.
  final String owner;

  /// The decoder's logical signal name or the Stage widget's pin name.
  final String slot;

  /// The saved hierarchical path that matched nothing.
  final String path;

  @override
  bool operator ==(Object other) =>
      other is UnresolvedBinding &&
      other.owner == owner &&
      other.slot == slot &&
      other.path == path;

  @override
  int get hashCode => Object.hash(owner, slot, path);

  @override
  String toString() => 'UnresolvedBinding($owner.$slot -> $path)';
}

/// Records and resolves the hierarchical path behind every decoder and Stage
/// binding.
///
/// Bindings hold backend-local signal refs, and a ref only identifies a signal
/// within the file it came from: regenerate the dump and the numbering moves,
/// so a session restored by ref alone binds nothing (or the wrong signal).
/// Signal rows have always been re-resolved by path for this reason
/// (`SignalGroupsNotifier.reresolveSignalRefs`); this does the same for
/// bindings.
///
/// * On save, [recordDecoder] / [recordStage] store each bound ref's path.
/// * On load and on reload, [resolveDecoder] / [resolveStage] look each path
///   up in the opened waveform. A binding with no recorded path (a session
///   written before paths were saved) keeps its ref. A path that matches
///   nothing leaves the binding with an empty ref, keeps the path so the
///   binding returns when the signal does, and is reported.
///
/// The lookups take only the refs or paths a session actually uses
/// ([pathsForRefs], [refsForPaths]): a gate-level hierarchy can hold more than
/// a million variables, and a full index of it on every autosave would cost far
/// more than the handful of bindings it serves.
abstract final class BindingPaths {
  // ── lookups ────────────────────────────────────────────────────────────────

  /// `ref → fullPath` in [source] for each of [refs] that exists there.
  static Map<String, String> pathsForRefs(
    WaveformDataSource source,
    Set<String> refs,
  ) {
    final out = <String, String>{};
    if (refs.isEmpty) return out;
    for (final v in source.findVariables(const SignalFilter())) {
      if (refs.contains(v.signalRef)) {
        out.putIfAbsent(v.signalRef, () => v.fullPath);
        if (out.length == refs.length) break;
      }
    }
    return out;
  }

  /// `fullPath → ref` in [source] for each of [paths] that exists there.
  static Map<String, String> refsForPaths(
    WaveformDataSource source,
    Set<String> paths,
  ) {
    final out = <String, String>{};
    if (paths.isEmpty) return out;
    for (final v in source.findVariables(const SignalFilter())) {
      final path = v.fullPath;
      if (paths.contains(path)) {
        out.putIfAbsent(path, () => v.signalRef);
        if (out.length == paths.length) break;
      }
    }
    return out;
  }

  // ── what a config or workspace refers to ───────────────────────────────────

  /// The non-empty refs bound in [config].
  static Iterable<String> decoderRefs(DecoderConfig config) =>
      config.signalBindings.values.where((r) => r.isNotEmpty);

  /// The non-empty refs bound anywhere in [workspace].
  static Iterable<String> stageRefs(StageWorkspaceState workspace) => [
    for (final panel in workspace.panels)
      for (final instance in panel.instances)
        for (final b in instance.signalBindings.values)
          if (b.signalRef.isNotEmpty) b.signalRef,
  ];

  /// The paths recorded for [config]'s bound slots.
  static Iterable<String> decoderPaths(DecoderConfig config) => [
    for (final slot in config.signalBindings.keys) ?config.signalPaths[slot],
  ];

  /// The paths recorded on [workspace]'s bindings.
  static Iterable<String> stagePaths(StageWorkspaceState workspace) => [
    for (final panel in workspace.panels)
      for (final instance in panel.instances)
        for (final b in instance.signalBindings.values) ?b.signalPath,
  ];

  // ── record (save) ──────────────────────────────────────────────────────────

  /// [config] with the path of every bound slot recorded from [pathByRef].
  ///
  /// A slot whose ref is empty or not in [pathByRef] keeps the path it already
  /// had (an unresolved binding waiting for its signal). Paths for slots that
  /// are no longer bound are dropped.
  static DecoderConfig recordDecoder(
    DecoderConfig config,
    Map<String, String> pathByRef,
  ) {
    final paths = <String, String>{
      for (final e in config.signalBindings.entries)
        e.key: ?(pathByRef[e.value] ?? config.signalPaths[e.key]),
    };
    return config.copyWith(signalPaths: paths);
  }

  /// [workspace] with the path of every binding recorded from [pathByRef].
  ///
  /// A binding whose ref is empty or not in [pathByRef] keeps the path it
  /// already had.
  static StageWorkspaceState recordStage(
    StageWorkspaceState workspace,
    Map<String, String> pathByRef,
  ) => workspace.copyWith(
    panels: [
      for (final panel in workspace.panels)
        panel.copyWith(
          instances: [
            for (final instance in panel.instances)
              instance.copyWith(
                signalBindings: {
                  for (final e in instance.signalBindings.entries)
                    e.key: switch (pathByRef[e.value.signalRef]) {
                      final path? => e.value.copyWith(signalPath: path),
                      null => e.value,
                    },
                },
              ),
          ],
        ),
    ],
  );

  // ── resolve (load / reload) ────────────────────────────────────────────────

  /// [config] with every slot that has a recorded path re-pointed at
  /// [refByPath]'s ref for it.
  ///
  /// A slot without a recorded path keeps its ref. A path missing from
  /// [refByPath] leaves the slot with an empty ref (the decoder sees no
  /// signal, as for an unbound optional pin) and is passed to [onUnresolved].
  static DecoderConfig resolveDecoder(
    DecoderConfig config,
    Map<String, String> refByPath, {
    required void Function(String slot, String path) onUnresolved,
  }) {
    if (config.signalPaths.isEmpty) return config;
    final bindings = <String, String>{};
    for (final e in config.signalBindings.entries) {
      final path = config.signalPaths[e.key];
      if (path == null) {
        bindings[e.key] = e.value;
        continue;
      }
      final ref = refByPath[path];
      if (ref == null) onUnresolved(e.key, path);
      bindings[e.key] = ref ?? '';
    }
    return config.copyWith(signalBindings: bindings);
  }

  /// [workspace] with every binding that has a recorded path re-pointed at
  /// [refByPath]'s ref for it; see [resolveDecoder]. [onUnresolved] receives
  /// the owning instance's label (or widget id), the pin and the path.
  static StageWorkspaceState resolveStage(
    StageWorkspaceState workspace,
    Map<String, String> refByPath, {
    required void Function(String owner, String pin, String path) onUnresolved,
  }) {
    StageSignalBinding resolve(
      StageInstance instance,
      String pin,
      StageSignalBinding binding,
    ) {
      final path = binding.signalPath;
      if (path == null) return binding;
      final ref = refByPath[path];
      if (ref == null) {
        onUnresolved(instance.label ?? instance.widgetId, pin, path);
      }
      return binding.copyWith(signalRef: ref ?? '');
    }

    return workspace.copyWith(
      panels: [
        for (final panel in workspace.panels)
          panel.copyWith(
            instances: [
              for (final instance in panel.instances)
                instance.copyWith(
                  signalBindings: {
                    for (final e in instance.signalBindings.entries)
                      e.key: resolve(instance, e.key, e.value),
                  },
                ),
            ],
          ),
      ],
    );
  }
}
