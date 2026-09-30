// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// A slim horizontal scrollbar that tracks and controls the time-axis
/// pan/zoom state of the waveform canvas.
///
/// The scrollbar's track represents the full simulation time range
/// `[startTime, endTime]`. The thumb represents the visible window
/// `[visibleStartTime, visibleEndTime]`. Dragging the thumb pans the
/// canvas; tapping on the track jumps the thumb (and the canvas) to
/// the tapped position.
///
/// The widget collapses to a zero-height [SizedBox.shrink] when:
/// - no waveform file is loaded, or
/// - the simulation range is empty, or
/// - the entire simulation fits in the viewport (no need to scroll).
///
/// Sizing: 12 dp visible height on touch (24 dp interactive band so a
/// fingertip can grab the thumb reliably), 8 dp visible / 16 dp band on
/// desktop. Per ARCHITECTURE.md §3.1.8.1 — uses [MobileMetrics] rather
/// than literal pixel constants.
class WaveformHorizontalScrollbar extends ConsumerStatefulWidget {
  const WaveformHorizontalScrollbar({super.key});

  @override
  ConsumerState<WaveformHorizontalScrollbar> createState() =>
      _WaveformHorizontalScrollbarState();
}

class _WaveformHorizontalScrollbarState
    extends ConsumerState<WaveformHorizontalScrollbar> {
  /// Pan offset (in ticks) at the moment a drag began. Used to compute
  /// new offsets as a function of cumulative drag pixels rather than
  /// per-frame deltas, which avoids drift from rounding errors.
  double? _dragStartOffsetTicks;

  /// Track width (in pixels) at the moment a drag began.
  double? _dragStartTrackWidth;

  /// Pointer x coordinate at the moment a drag began.
  double? _dragStartPointerX;

  @override
  Widget build(BuildContext context) {
    final hasFile = ref.watch(waveformIsLoadedProvider);
    final mapper = ref.watch(timeMapperProvider);
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);

    final fullRange = mapper.endTime - mapper.startTime;
    final visibleRange = mapper.visibleRange;
    // The band always reserves `bandHeight` in the column flow even when there
    // is nothing to scroll. Three sibling columns (signal list, canvas, value
    // column) bind their bottom edges to this same height so their viewport
    // extents — and therefore their maxScrollExtents — stay identical. If we
    // returned SizedBox.shrink here when there is nothing to scroll, the
    // canvas's Expanded would be 16/24 dp taller than the other two columns,
    // their maxScrollExtents would diverge, and the bidirectional vertical
    // scroll sync would drift apart at the bottom of the list — exactly the
    // "value moves from top of lane to bottom of lane near the last row"
    // symptom the user reported.
    final bandHeight = metrics.isTouch ? 24.0 : 16.0;
    if (!hasFile || fullRange <= 0 || visibleRange <= 0) {
      return SizedBox(height: bandHeight);
    }
    if (visibleRange >= fullRange) {
      // Fully zoomed out — nothing to scroll, but keep the reserved band so
      // sibling columns stay aligned.
      return SizedBox(height: bandHeight);
    }

    final theme = Theme.of(context);
    final l10n = L10N.of(context);
    final visualHeight = metrics.isTouch ? 12.0 : 8.0;

    return Semantics(
      container: true,
      label: l10n.waveformHorizontalScrollbarLabel,
      value: _semanticValue(mapper),
      child: SizedBox(
        height: bandHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            if (trackWidth <= 0) return const SizedBox.shrink();
            final thumbFraction = visibleRange / fullRange;
            // Enforce a small minimum so the thumb stays grabbable even
            // when zoomed in by a factor of millions — but never let the
            // thumb exceed the track width. Mid-resize the track can drop
            // below `minThumbWidth`; without the cap, `maxThumbLeft` goes
            // negative and `clamp(0.0, negative)` throws.
            const minThumbWidth = 24.0;
            final thumbWidth = math.min(
              trackWidth,
              math.max(minThumbWidth, trackWidth * thumbFraction),
            );
            final maxThumbLeft = math.max<double>(0, trackWidth - thumbWidth);
            final fractionAlong = fullRange == visibleRange
                ? 0.0
                : (mapper.panOffsetTicks - mapper.startTime) /
                      (fullRange - visibleRange);
            final thumbLeft = (fractionAlong * maxThumbLeft).clamp(
              0.0,
              maxThumbLeft,
            );

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _handleTrackTap(
                tapX: details.localPosition.dx,
                trackWidth: trackWidth,
                thumbWidth: thumbWidth,
                thumbLeft: thumbLeft,
                mapper: mapper,
              ),
              onPanStart: (details) {
                _dragStartOffsetTicks = mapper.panOffsetTicks;
                _dragStartTrackWidth = trackWidth;
                _dragStartPointerX = details.localPosition.dx;
              },
              onPanUpdate: (details) => _handleDragUpdate(
                pointerX: details.localPosition.dx,
                mapper: mapper,
              ),
              onPanEnd: (_) {
                _dragStartOffsetTicks = null;
                _dragStartTrackWidth = null;
                _dragStartPointerX = null;
              },
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Track
                  Container(
                    height: visualHeight,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(visualHeight / 2),
                    ),
                  ),
                  // Thumb
                  Positioned(
                    left: thumbLeft,
                    width: thumbWidth,
                    height: visualHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outline,
                        borderRadius: BorderRadius.circular(visualHeight / 2),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Tap-on-track: jump the thumb so its center sits at the tap, unless
  /// the tap is already inside the thumb (then it's a no-op — the
  /// follow-up drag handles repositioning).
  void _handleTrackTap({
    required double tapX,
    required double trackWidth,
    required double thumbWidth,
    required double thumbLeft,
    required TimeMapper mapper,
  }) {
    if (tapX >= thumbLeft && tapX <= thumbLeft + thumbWidth) return;
    final desiredThumbLeft = (tapX - thumbWidth / 2).clamp(
      0.0,
      trackWidth - thumbWidth,
    );
    final fullRange = mapper.endTime - mapper.startTime;
    final visibleRange = mapper.visibleRange;
    final maxThumbLeft = trackWidth - thumbWidth;
    if (maxThumbLeft <= 0 || fullRange == visibleRange) return;
    final fractionAlong = desiredThumbLeft / maxThumbLeft;
    final newOffset =
        mapper.startTime + fractionAlong * (fullRange - visibleRange);
    ref.read(timeMapperProvider.notifier).setPanOffsetTicks(newOffset);
  }

  void _handleDragUpdate({
    required double pointerX,
    required TimeMapper mapper,
  }) {
    final startOffset = _dragStartOffsetTicks;
    final startWidth = _dragStartTrackWidth;
    final startPointer = _dragStartPointerX;
    if (startOffset == null || startWidth == null || startPointer == null) {
      return;
    }
    final fullRange = mapper.endTime - mapper.startTime;
    final visibleRange = mapper.visibleRange;
    if (fullRange <= 0 || visibleRange <= 0 || visibleRange >= fullRange) {
      return;
    }
    final thumbFraction = visibleRange / fullRange;
    const minThumbWidth = 24.0;
    final thumbWidth = math.max(minThumbWidth, startWidth * thumbFraction);
    final maxThumbLeft = startWidth - thumbWidth;
    if (maxThumbLeft <= 0) return;

    final pixelDelta = pointerX - startPointer;
    final fractionDelta = pixelDelta / maxThumbLeft;
    final newOffset = startOffset + fractionDelta * (fullRange - visibleRange);
    ref.read(timeMapperProvider.notifier).setPanOffsetTicks(newOffset);
  }

  String _semanticValue(TimeMapper mapper) {
    final fullRange = mapper.endTime - mapper.startTime;
    if (fullRange <= 0) return '';
    final percent =
        ((mapper.panOffsetTicks - mapper.startTime) / fullRange * 100)
            .clamp(0, 100)
            .round();
    return '$percent%';
  }
}
