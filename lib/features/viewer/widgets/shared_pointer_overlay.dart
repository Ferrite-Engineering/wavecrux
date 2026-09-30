// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/providers/collaboration_service_provider.dart';
import 'package:wavecrux/core/theme/collaborator_palette.dart';
import 'package:wavecrux/domain/interfaces/collaboration_service.dart';
import 'package:wavecrux/features/collaboration/providers/collaboration_session_state_provider.dart';
import 'package:wavecrux/features/collaboration/providers/follow_detached_provider.dart';
import 'package:wavecrux/features/viewer/providers/lane_geometry_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// Computes the visible opacity of a [CollabPointerKind.ping] given how long it
/// has been showing ([elapsed]) and its [ttl]. Fades linearly from 1 → 0 over
/// the TTL and clamps to `[0, 1]`. A non-positive [ttl] is treated as already
/// expired (`0`). Pure, so the fade curve is unit-testable without a [Ticker].
double pingOpacity(Duration elapsed, Duration ttl) {
  if (ttl.inMicroseconds <= 0) return 0;
  final remaining = 1 - elapsed.inMicroseconds / ttl.inMicroseconds;
  return remaining.clamp(0.0, 1.0);
}

/// Overlay that renders the session's data-anchored **pointers** — pings and
/// pins — above the waveform canvas.
///
/// Each pointer is anchored in **waveform-data coordinates** — `(time, rowId)`
/// where `rowId` is a signal's stable scope path — never screen pixels. The
/// overlay maps that anchor back to pixels every build through the same
/// [timeMapperProvider] (X) and [laneGeometryProvider] (Y) the canvas uses, so a
/// pointer stays glued to the edge it marks while the presenter pans, zooms, or
/// scrolls. Three behaviors distinguish it from the simpler
/// `CollaboratorCursorOverlay` / `SharedMarkerOverlay`:
///
/// * **Pings fade out** over their [CollabPointer.ttl] (an ephemeral "laser
///   pointer") and are dropped once fully faded; a [Ticker] drives the fade.
/// * **Pins persist** until deleted, and show an **author-only** delete
///   affordance (only the participant who dropped the pin sees it).
/// * A pointer anchored **outside the current viewport** surfaces as a
///   directional edge affordance ("→ Bob is pointing") rather than vanishing.
///
/// [scrollOffset] is the canvas's vertical scroll offset (logical px), supplied
/// by the host so row Y maps from content-space to viewport-space. Renders
/// nothing when there is no active session or no pointers (inert in Open Core
/// and idle Pro builds).
class SharedPointerOverlay extends ConsumerStatefulWidget {
  const SharedPointerOverlay({required this.scrollOffset, super.key});

  /// The canvas's current vertical scroll offset in logical pixels.
  final double scrollOffset;

  @override
  ConsumerState<SharedPointerOverlay> createState() =>
      _SharedPointerOverlayState();
}

class _SharedPointerOverlayState extends ConsumerState<SharedPointerOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// Ticker-relative clock, advanced deterministically by the [Ticker]
  /// callback. Used instead of wall-clock so ping fade is reproducible under
  /// `tester.pump(duration)`.
  Duration _now = Duration.zero;

  /// First-seen [_now] per ping id, recorded the build a ping first appears so
  /// its fade is measured from arrival on *this* client ("start the fade timer
  /// on receipt" — immune to cross-client clock skew).
  final Map<String, Duration> _pingFirstSeen = {};

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      // Only repaint while a ping is mid-fade; pins are static so an idle
      // session never spins frames.
      setState(() => _now = elapsed);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _syncTicker({required bool wantTicking}) {
    if (wantTicking && !_ticker.isActive) {
      // TickerFuture completes only on stop/dispose; frames drive the callback.
      _ticker.start();
    } else if (!wantTicking && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(collaborationSessionStateProvider).value;
    if (sessionState == null || sessionState.pointers.isEmpty) {
      _pingFirstSeen.clear();
      _syncTicker(wantTicking: false);
      return const SizedBox.shrink();
    }

    final l10n = L10N.of(context);
    final timeMapper = ref.watch(timeMapperProvider);
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);
    final geometry = ref.watch(
      laneGeometryProvider(LaneMetrics(minLaneHeight: metrics.minLaneHeight)),
    );
    final myId = sessionState.myParticipantId;

    // Prune fade bookkeeping for pointers that no longer exist.
    final liveIds = {for (final p in sessionState.pointers) p.id};
    _pingFirstSeen.keys.toList().forEach((id) {
      if (!liveIds.contains(id)) _pingFirstSeen.remove(id);
    });

    final children = <Widget>[];
    var anyPingFading = false;

    for (final pointer in sessionState.pointers) {
      final x = timeMapper.timeToPixel(pointer.time);
      // Skip non-finite coordinates (degenerate mapper) — drawing at NaN/∞
      // hard-crashes the Windows renderer, as the cursor overlay guards against.
      if (!x.isFinite) continue;

      final color = collaboratorColor(
        _colorIndexFor(sessionState, pointer.authorId),
      );
      final authorName = _displayNameFor(sessionState, pointer.authorId);

      final offLeft = pointer.time < timeMapper.visibleStartTime;
      final offRight = pointer.time > timeMapper.visibleEndTime;

      if (offLeft || offRight) {
        children.add(
          _OffscreenPointerAffordance(
            key: ValueKey('offscreen-${pointer.id}'),
            color: color,
            pointToRight: offRight,
            label: l10n.collabPointerOffscreen(authorName),
            jumpLabel: l10n.collabPointerJumpTo,
            // "Ask presenter to scroll" is meaningful only when *someone else* is
            // driving — the presenter just jumps there directly (the room
            // follows). Hidden for the presenter's own off-screen pointers.
            askLabel: sessionState.isLocalPresenter
                ? null
                : l10n.collabPointerAskScroll,
            onJump: () => _jumpToPointer(pointer.time),
            onAskScroll: () => ref
                .read(collaborationServiceProvider)
                .requestPresenterScroll(pointer.time, pointer.rowId),
          ),
        );
        continue;
      }

      final y = _rowCenterY(geometry, pointer.rowId);

      if (pointer.kind == CollabPointerKind.ping) {
        final firstSeen = _pingFirstSeen.putIfAbsent(pointer.id, () => _now);
        final ttl = pointer.ttl ?? const Duration(seconds: 4);
        final opacity = pingOpacity(_now - firstSeen, ttl);
        if (opacity <= 0) continue; // Fully faded — stop rendering.
        anyPingFading = true;
        children.add(
          _PingMarker(
            key: ValueKey('ping-${pointer.id}'),
            x: x,
            y: y,
            color: color,
            opacity: opacity,
          ),
        );
      } else {
        children.add(
          _PinMarker(
            key: ValueKey('pin-${pointer.id}'),
            x: x,
            y: y,
            color: color,
            canDelete: pointer.authorId == myId,
            deleteTooltip: l10n.collabPointerDeletePinTooltip,
            touchTarget: metrics.touchTarget,
            onDelete: () => ref
                .read(collaborationServiceProvider)
                .removePointer(pointer.id),
          ),
        );
      }
    }

    // Run the fade ticker only while at least one ping is mid-fade.
    _syncTicker(wantTicking: anyPingFading);

    if (children.isEmpty) return const SizedBox.shrink();

    return RepaintBoundary(
      child: Stack(children: children),
    );
  }

  /// Navigates the local viewport to centre [time], keeping the current zoom
  /// width, and marks the follower locally **detached** so this deliberate jump
  /// is not immediately undone by the presenter's next viewport broadcast
  /// (soft-follow). For the presenter, the jump just scrolls the shared
  /// viewport — the whole room follows — and the detach is a no-op.
  void _jumpToPointer(int time) {
    final mapper = ref.read(timeMapperProvider);
    final width = mapper.visibleRange;
    if (width <= 0) return;
    final start = time - width ~/ 2;
    ref.read(timeMapperProvider.notifier).zoomToRange(start, start + width);
    ref.read(followDetachedProvider.notifier).detach();
  }

  /// Vertical centre (viewport-space, scroll-adjusted) of the signal row whose
  /// stable path is [rowId], or a small top fallback when the row is absent from
  /// the local file (graceful degradation — the signal isn't present in this
  /// participant's capture; the mismatch banner explains why).
  double _rowCenterY(LaneGeometry geometry, String rowId) {
    for (final row in geometry.rows) {
      if (row.entry.signalPath == rowId) {
        return row.top + row.height / 2 - widget.scrollOffset;
      }
    }
    return 12 - widget.scrollOffset;
  }

  int _colorIndexFor(CollabSessionState state, String participantId) {
    for (final p in state.participants) {
      if (p.id == participantId) return p.colorIndex;
    }
    return 0;
  }

  String _displayNameFor(CollabSessionState state, String participantId) {
    for (final p in state.participants) {
      if (p.id == participantId) return p.displayName;
    }
    return participantId;
  }
}

/// An ephemeral ping dot. A filled ring with a soft halo, faded by [opacity].
class _PingMarker extends StatelessWidget {
  const _PingMarker({
    required this.x,
    required this.y,
    required this.color,
    required this.opacity,
    super.key,
  });

  final double x;
  final double y;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    const r = 9.0;
    return Positioned(
      left: x - r,
      top: y - r,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Container(
            width: r * 2,
            height: r * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.35),
              border: Border.all(color: color, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

/// A persistent pin with an author-only delete affordance.
class _PinMarker extends StatelessWidget {
  const _PinMarker({
    required this.x,
    required this.y,
    required this.color,
    required this.canDelete,
    required this.deleteTooltip,
    required this.touchTarget,
    required this.onDelete,
    super.key,
  });

  final double x;
  final double y;
  final Color color;
  final bool canDelete;
  final String deleteTooltip;
  final double touchTarget;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    const iconSize = 20.0;
    return Positioned(
      left: x - iconSize / 2,
      top: y - iconSize,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IgnorePointer(
            child: Icon(Icons.push_pin, size: iconSize, color: color),
          ),
          if (canDelete)
            Semantics(
              label: deleteTooltip,
              button: true,
              child: Tooltip(
                message: deleteTooltip,
                triggerMode: TooltipTriggerMode.manual,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDelete,
                  child: SizedBox(
                    width: touchTarget,
                    height: touchTarget,
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: color.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Which off-screen-affordance action the user picked from its menu.
enum _OffscreenAction {
  /// Scroll the local viewport to the pointer (local navigation; detaches a
  /// follower so the jump sticks).
  jump,

  /// Ask the presenter to bring the pointer into the shared viewport.
  askScroll,
}

/// Edge affordance for a pointer anchored outside the current viewport: a small
/// chip pinned to the left or right edge with a directional arrow and the
/// author's name, so an off-screen pointer is never lost silently.
///
/// Tapping it opens a menu: **Jump to pointer** (always — local
/// navigation) and, for a non-presenter, **Ask presenter to scroll** (nudges the
/// presenter to bring it into the shared view). [askLabel] is `null` for the
/// presenter, which hides the second item.
class _OffscreenPointerAffordance extends StatelessWidget {
  const _OffscreenPointerAffordance({
    required this.color,
    required this.pointToRight,
    required this.label,
    required this.jumpLabel,
    required this.askLabel,
    required this.onJump,
    required this.onAskScroll,
    super.key,
  });

  final Color color;
  final bool pointToRight;
  final String label;
  final String jumpLabel;
  final String? askLabel;
  final VoidCallback onJump;
  final VoidCallback onAskScroll;

  @override
  Widget build(BuildContext context) {
    final askLabel = this.askLabel;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!pointToRight)
            const Text(
              '← ',
              style: TextStyle(color: Colors.white, fontSize: 10),
            ),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
          if (pointToRight)
            const Text(
              ' →',
              style: TextStyle(color: Colors.white, fontSize: 10),
            ),
        ],
      ),
    );
    return Positioned(
      top: 24,
      left: pointToRight ? null : 4,
      right: pointToRight ? 4 : null,
      child: PopupMenuButton<_OffscreenAction>(
        tooltip: label,
        position: PopupMenuPosition.under,
        padding: EdgeInsets.zero,
        onSelected: (action) => switch (action) {
          _OffscreenAction.jump => onJump(),
          _OffscreenAction.askScroll => onAskScroll(),
        },
        itemBuilder: (context) => [
          PopupMenuItem<_OffscreenAction>(
            value: _OffscreenAction.jump,
            child: Text(jumpLabel),
          ),
          if (askLabel != null)
            PopupMenuItem<_OffscreenAction>(
              value: _OffscreenAction.askScroll,
              child: Text(askLabel),
            ),
        ],
        child: chip,
      ),
    );
  }
}
