// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/models/playback_state.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/cursors/providers/playback_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Duration-mode speed presets surfaced in the playback actions (wall-clock
/// seconds to play the active range). Power mode is implemented in the engine
/// but not exposed here.
const List<int> kStagePlaybackSpeedPresets = [5, 10, 30];

/// The Stage Playback controls as dock-strip actions: play/pause · speed ·
/// loop · follow-viewport, rendered in the active Stage tab's action cluster.
///
/// This replaces the retired `StagePlaybackTransport` row that docked at the
/// bottom of the Stage panel (and the main toolbar's play/pause glyph): one
/// transport surface, living where the rest of the Stage tab's controls
/// already are. A single play/pause toggle stands in for the old play + stop
/// pair.
///
/// It owns **no** ticker — it only reads [playbackProvider] and calls
/// notifier methods. The playback engine lives at the cursor layer; advancing
/// the primary cursor re-animates every signal-bound Stage widget for free.
/// [PlaybackState] carries no ticking position, so watching it here is cheap;
/// the secondary-cursor gate for A–B loop uses a `select` so playhead ticks
/// never rebuild the dock.
List<Widget> stagePlaybackDockActions(BuildContext context, WidgetRef ref) {
  final l10n = L10N.of(context);
  final playback = ref.watch(playbackProvider);
  final notifier = ref.read(playbackProvider.notifier);

  // Offer the A–B loop only when a secondary cursor is set (it defines the
  // B bound). Without it, A–B falls back to whole-range at play() time.
  final hasSecondaryCursor = ref.watch(
    cursorStateProvider.select((s) => s.secondaryCursorTime != null),
  );

  return <Widget>[
    _PlaybackAction(
      buttonKey: const ValueKey('stagePlaybackPlayPause'),
      icon: playback.isPlaying ? Icons.pause : Icons.play_arrow,
      tooltip: playback.isPlaying
          ? l10n.stagePlaybackPause
          : l10n.stagePlaybackPlay,
      onPressed: notifier.toggle,
      highlighted: playback.isPlaying,
    ),
    _SpeedSelector(
      speed: playback.speed,
      onSelected: (seconds) =>
          notifier.setSpeed(PlaybackSpeed.duration(seconds.toDouble())),
    ),
    _LoopSelector(
      loopMode: playback.loopMode,
      offerAToB: hasSecondaryCursor,
      onSelected: notifier.setLoopMode,
    ),
    _PlaybackAction(
      buttonKey: const ValueKey('stagePlaybackFollow'),
      icon: playback.followViewport
          ? Icons.center_focus_strong
          : Icons.center_focus_weak,
      tooltip: l10n.stagePlaybackFollow,
      onPressed: () =>
          notifier.setFollowViewport(value: !playback.followViewport),
      highlighted: playback.followViewport,
    ),
  ];
}

/// A dock-strip-sized playback icon button (28×28, [kCruxDockIconSize]),
/// matching the rename/add actions beside it.
class _PlaybackAction extends StatelessWidget {
  const _PlaybackAction({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.highlighted = false,
  });

  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      key: buttonKey,
      icon: Icon(icon, size: kCruxDockIconSize),
      tooltip: tooltip,
      color: highlighted ? theme.colorScheme.primary : null,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
    );
  }
}

/// Popup selector for the duration-mode playback speed presets.
class _SpeedSelector extends StatelessWidget {
  const _SpeedSelector({required this.speed, required this.onSelected});

  final PlaybackSpeed speed;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    return SizedBox(
      key: const ValueKey('stagePlaybackSpeed'),
      width: 28,
      height: 28,
      child: PopupMenuButton<int>(
        tooltip: l10n.stagePlaybackSpeed,
        icon: const Icon(Icons.speed, size: kCruxDockIconSize),
        padding: EdgeInsets.zero,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final seconds in kStagePlaybackSpeedPresets)
            CheckedPopupMenuItem<int>(
              value: seconds,
              checked: speed.playSeconds == seconds.toDouble(),
              child: Text(l10n.stagePlaybackSpeedSeconds(seconds)),
            ),
        ],
      ),
    );
  }
}

/// Popup selector for the loop mode. The A–B entry is offered only when a
/// secondary cursor is present (otherwise it has no B bound).
class _LoopSelector extends StatelessWidget {
  const _LoopSelector({
    required this.loopMode,
    required this.offerAToB,
    required this.onSelected,
  });

  final PlaybackLoopMode loopMode;
  final bool offerAToB;
  final ValueChanged<PlaybackLoopMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    final active = loopMode != PlaybackLoopMode.none;
    return SizedBox(
      key: const ValueKey('stagePlaybackLoop'),
      width: 28,
      height: 28,
      child: PopupMenuButton<PlaybackLoopMode>(
        tooltip: l10n.stagePlaybackLoop,
        icon: Icon(
          active ? Icons.repeat_on : Icons.repeat,
          size: kCruxDockIconSize,
          color: active ? theme.colorScheme.primary : null,
        ),
        padding: EdgeInsets.zero,
        onSelected: onSelected,
        itemBuilder: (context) => [
          CheckedPopupMenuItem<PlaybackLoopMode>(
            value: PlaybackLoopMode.none,
            checked: loopMode == PlaybackLoopMode.none,
            child: Text(l10n.stagePlaybackLoopNone),
          ),
          CheckedPopupMenuItem<PlaybackLoopMode>(
            value: PlaybackLoopMode.wholeRange,
            checked: loopMode == PlaybackLoopMode.wholeRange,
            child: Text(l10n.stagePlaybackLoop),
          ),
          if (offerAToB)
            CheckedPopupMenuItem<PlaybackLoopMode>(
              value: PlaybackLoopMode.aToB,
              checked: loopMode == PlaybackLoopMode.aToB,
              child: Text(l10n.stagePlaybackLoopAToB),
            ),
        ],
      ),
    );
  }
}
