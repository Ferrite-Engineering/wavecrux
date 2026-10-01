// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/cocotb_log_file.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/domain/models/playback_state.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/cocotb/providers/cocotb_log_provider.dart';
import 'package:wavecrux/features/comparison/providers/diff_provider.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/cursors/providers/playback_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/pattern_search_provider.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// Root-scope mirror of the **active tab's** per-tab gating flags consumed by
/// [ActionContext]. The action-discovery surfaces (menu bar, overflow menu,
/// command palette, toolbar) build [ActionContext] at the root scope and cannot
/// `ref.watch` a tab container's providers, so — exactly like
/// `ActiveTabHasSelection` — this re-emits the active tab's cursor / marker /
/// diff / cocotb-log / pattern-match state up to the root.
///
/// Bundled into one record rather than one provider per flag to keep the
/// root-scope mirror surface small; reads go through the resolved `container`,
/// not `ref`, so the per-tab scope-leak guard does not flag it.
@immutable
class ActiveTabActionFlags {
  const ActiveTabActionFlags({
    this.cursorPresent = false,
    this.markersPresent = false,
    this.annotationsPresent = false,
    this.signalsDisplayed = false,
    this.diffActive = false,
    this.cocotbLogLoaded = false,
    this.patternMatchesPresent = false,
    this.playbackActive = false,
    this.canZoomOut = true,
    this.canZoomIn = true,
  });

  /// Whether the active tab has a primary cursor placed.
  final bool cursorPresent;

  /// Whether the active tab has at least one named marker set.
  final bool markersPresent;

  /// Whether the active tab has at least one annotation. Gates the walkthrough
  /// actions, which have nothing to step through without one.
  final bool annotationsPresent;

  /// Whether the active tab's signal list has at least one row. Gates Clear
  /// Canvas.
  final bool signalsDisplayed;

  /// Whether the active tab has a comparison (diff) file loaded.
  final bool diffActive;

  /// Whether the active tab has a cocotb log loaded.
  final bool cocotbLogLoaded;

  /// Whether the active tab's pattern search has at least one match.
  final bool patternMatchesPresent;

  /// Whether the active tab's Stage Playback transport is currently playing.
  /// Drives the toolbar button's play/pause glyph — the transport inside the
  /// Stage panel already flips its own icon, and the toolbar button used to
  /// stay on `play` even mid-playback.
  final bool playbackActive;

  /// Whether the active tab's viewport can still zoom out — false at fit-all,
  /// which is the most zoomed-out state there is.
  final bool canZoomOut;

  /// Whether the active tab's viewport can still zoom in — false once it spans
  /// the timescale's one-tick resolution.
  final bool canZoomIn;

  ActiveTabActionFlags copyWith({
    bool? cursorPresent,
    bool? markersPresent,
    bool? annotationsPresent,
    bool? signalsDisplayed,
    bool? diffActive,
    bool? cocotbLogLoaded,
    bool? patternMatchesPresent,
    bool? playbackActive,
    bool? canZoomOut,
    bool? canZoomIn,
  }) => ActiveTabActionFlags(
    cursorPresent: cursorPresent ?? this.cursorPresent,
    markersPresent: markersPresent ?? this.markersPresent,
    annotationsPresent: annotationsPresent ?? this.annotationsPresent,
    signalsDisplayed: signalsDisplayed ?? this.signalsDisplayed,
    diffActive: diffActive ?? this.diffActive,
    cocotbLogLoaded: cocotbLogLoaded ?? this.cocotbLogLoaded,
    patternMatchesPresent: patternMatchesPresent ?? this.patternMatchesPresent,
    playbackActive: playbackActive ?? this.playbackActive,
    canZoomOut: canZoomOut ?? this.canZoomOut,
    canZoomIn: canZoomIn ?? this.canZoomIn,
  );

  @override
  bool operator ==(Object other) =>
      other is ActiveTabActionFlags &&
      other.cursorPresent == cursorPresent &&
      other.markersPresent == markersPresent &&
      other.annotationsPresent == annotationsPresent &&
      other.signalsDisplayed == signalsDisplayed &&
      other.diffActive == diffActive &&
      other.cocotbLogLoaded == cocotbLogLoaded &&
      other.patternMatchesPresent == patternMatchesPresent &&
      other.playbackActive == playbackActive &&
      other.canZoomOut == canZoomOut &&
      other.canZoomIn == canZoomIn;

  @override
  int get hashCode => Object.hash(
    cursorPresent,
    markersPresent,
    annotationsPresent,
    signalsDisplayed,
    diffActive,
    cocotbLogLoaded,
    patternMatchesPresent,
    playbackActive,
    canZoomOut,
    canZoomIn,
  );
}

/// See [ActiveTabActionFlags]. Plain [NotifierProvider] (not codegen) so the
/// state class keeps a clean name; the cross-container subscription pattern
/// mirrors `ActiveTabHasSelection`.
final activeTabActionFlagsProvider =
    NotifierProvider<ActiveTabActionFlagsNotifier, ActiveTabActionFlags>(
      ActiveTabActionFlagsNotifier.new,
    );

class ActiveTabActionFlagsNotifier extends Notifier<ActiveTabActionFlags> {
  @override
  ActiveTabActionFlags build() {
    final tabId = ref.watch(activeTabIdProvider);

    final ProviderContainer container;
    try {
      container = ref.watch(tabContainerManagerProvider).containerFor(tabId);
    } on Object {
      return const ActiveTabActionFlags();
    }

    final subs = <ProviderSubscription<Object?>>[
      container.listen<CursorState>(
        cursorStateProvider,
        (_, next) => state = state.copyWith(
          cursorPresent: next.primaryCursorTime != null,
        ),
      ),
      container.listen<MarkerState>(
        markerStateProvider,
        (_, next) =>
            state = state.copyWith(markersPresent: next.markers.isNotEmpty),
      ),
      container.listen<List<Annotation>>(
        annotationsProvider,
        (_, next) =>
            state = state.copyWith(annotationsPresent: next.isNotEmpty),
      ),
      // `.select` so only an empty/non-empty flip reaches the action
      // surfaces, not every reorder or colour change of the list.
      container.listen<bool>(
        signalGroupsProvider.select((g) => g.entries.isNotEmpty),
        (_, next) => state = state.copyWith(signalsDisplayed: next),
      ),
      container.listen<DiffState>(
        diffProvider,
        (_, next) => state = state.copyWith(diffActive: next.isActive),
      ),
      container.listen<CocotbLogFile?>(
        cocotbLogProvider,
        (_, next) => state = state.copyWith(cocotbLogLoaded: next != null),
      ),
      container.listen<PatternSearchState>(
        patternSearchProvider,
        (_, next) =>
            state = state.copyWith(patternMatchesPresent: next.hasMatches),
      ),
      container.listen<PlaybackState>(
        playbackProvider,
        (_, next) => state = state.copyWith(playbackActive: next.isPlaying),
      ),
      // The zoom bounds. Watched as the whole mapper rather than a `.select`
      // of the two booleans because both derive from `ticksPerPixel` against
      // the viewport width, and the record's own equality already stops a
      // pan-only change from rebuilding the action surfaces.
      container.listen<TimeMapper>(
        timeMapperProvider,
        (_, next) => state = state.copyWith(
          canZoomOut: next.canZoomOut,
          canZoomIn: next.canZoomIn,
        ),
      ),
    ];
    for (final sub in subs) {
      ref.onDispose(sub.close);
    }

    return ActiveTabActionFlags(
      cursorPresent:
          container.read(cursorStateProvider).primaryCursorTime != null,
      markersPresent: container.read(markerStateProvider).markers.isNotEmpty,
      annotationsPresent: container.read(annotationsProvider).isNotEmpty,
      signalsDisplayed: container.read(signalGroupsProvider).entries.isNotEmpty,
      diffActive: container.read(diffProvider).isActive,
      cocotbLogLoaded: container.read(cocotbLogProvider) != null,
      patternMatchesPresent: container.read(patternSearchProvider).hasMatches,
      playbackActive: container.read(playbackProvider).isPlaying,
      canZoomOut: container.read(timeMapperProvider).canZoomOut,
      canZoomIn: container.read(timeMapperProvider).canZoomIn,
    );
  }
}
