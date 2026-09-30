// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/viewer/providers/lane_geometry_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/value_column_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';
import 'package:wavecrux/services/waveform_geom/lane_geometry.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

// Cosmetic, device-class-independent layout constants for the inline value
// pill. These are not interactive hit targets (the tap surface is sized from
// `MobileMetrics.touchTarget`) nor font sizes (text uses `MobileMetrics.monoText`),
// so they live here as documented constants — mirroring the fixed structural
// heights in `lane_geometry.dart`.

/// Horizontal gap between the cursor x-position and the value pill.
const double _kCursorGap = 6;

/// Horizontal inner padding of the value pill.
const double _kPillPaddingH = 6;

/// Vertical inner padding of the value pill.
const double _kPillPaddingV = 2;

/// Fraction of the viewport width a *collapsed* label may occupy before it
/// truncates with an ellipsis. The same width is the "label-width" used for the
/// right-edge flip decision (flip left within a label-width of the edge).
const double _kCollapsedWidthFraction = 0.42;

/// Non-modal, inline-at-cursor value labels for the phone waveform canvas.
///
/// This is the phone counterpart to the desktop/tablet value pane.
/// Instead of a modal `endDrawer` that freezes the canvas behind a scrim, each
/// visible signal's value at the primary cursor renders **on its own lane**,
/// pinned to the cursor's x-position, as a non-modal overlay layered over the
/// canvas.
///
/// Structured like [CursorOverlay] so scrub / pan / pinch / long-press all pass
/// straight through to [WaveformGestureHandler] underneath: the non-interactive
/// pills are wrapped in [IgnorePointer], and the **only** interactive surface —
/// tap-to-expand on an ellipsis-truncated label — uses
/// [HitTestBehavior.translucent] and registers a tap recognizer only (never a
/// long-press), so horizontal scrub drags and the canvas long-press context
/// menu still win the gesture arena (ARCHITECTURE.md §3.1.8.5 gesture-bubbling
/// rule).
///
/// Lane y-positions come from the shared [LaneGeometry] model (the same source
/// the canvas, signal-names list, and value column consume), so a label can
/// never misalign with the wave it describes. The overlay is positioned at the
/// canvas *viewport* level (a sibling of [CursorOverlay], not inside the
/// vertically-scrolling content), so each lane's content-space `top` is
/// translated by [scrollOffset] to screen space.
///
/// Accessibility: the inline values are exposed as a **single combined
/// cursor-readout** (cursor time + each visible signal's full value) rather than
/// one semantics node per lane — matching how the cursor itself is announced and
/// avoiding flooding the semantics tree. The on-screen truncation + tap-to-expand
/// is a sighted-user affordance; assistive tech always receives the full value.
class InlineCursorValueOverlay extends ConsumerStatefulWidget {
  const InlineCursorValueOverlay({
    required this.scrollOffset,
    super.key,
  });

  /// The waveform canvas's current vertical scroll offset, used to translate a
  /// lane's content-space top into the viewport-space y at which the label is
  /// drawn. Supplied by the canvas (its `_viewportTop`).
  final double scrollOffset;

  @override
  ConsumerState<InlineCursorValueOverlay> createState() =>
      _InlineCursorValueOverlayState();
}

class _InlineCursorValueOverlayState
    extends ConsumerState<InlineCursorValueOverlay> {
  /// The signalRef of the label currently expanded to its full value, or null
  /// when none is expanded. Single-expansion: tapping a truncated label expands
  /// it and collapses any other (tap again, or tap a different label, collapses
  /// the previous — "tap again / tap elsewhere to collapse").
  String? _expandedRef;

  @override
  Widget build(BuildContext context) {
    final cursorTime = ref.watch(
      cursorStateProvider.select((s) => s.primaryCursorTime),
    );
    // Labels appear whenever a primary cursor exists, and disappear when it is
    // cleared. (The value providers fall back to start-time when no cursor is
    // set; the inline overlay deliberately shows nothing in that case.)
    if (cursorTime == null) return const SizedBox.shrink();

    final timeMapper = ref.watch(timeMapperProvider);
    final deviceClass = ref.watch(deviceClassProvider);
    final metrics = MobileMetrics.of(context, deviceClass);
    final laneMetrics = LaneMetrics(minLaneHeight: metrics.minLaneHeight);
    final geometry = ref.watch(laneGeometryProvider(laneMetrics));
    final timescale = ref.watch(currentTimescaleProvider);
    final l10n = L10N.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final textScaler = MediaQuery.textScalerOf(context);

    final baseStyle = TextStyle(
      fontSize: metrics.monoText,
      fontFamily: WavecruxColors.monoFontFamily,
      fontFamilyFallback: WavecruxColors.monoFontFamilyFallback,
      color: colorScheme.onSurface,
    );
    final pillHeight =
        textScaler.scale(metrics.monoText) * 1.4 + _kPillPaddingV * 2 + 2;
    final cursorTimeLabel = TimeFormatService(
      timescale: timescale,
    ).format(cursorTime);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final viewportHeight = constraints.maxHeight;
        if (viewportWidth <= 0 || !viewportWidth.isFinite) {
          return const SizedBox.shrink();
        }

        final cursorX = timeMapper
            .timeToPixel(cursorTime)
            .clamp(0.0, viewportWidth);
        final collapsedMaxWidth = viewportWidth * _kCollapsedWidthFraction;
        // Flip to the left of the cursor when a collapsed label would not fit
        // to the right (within a label-width of the right edge).
        final flip = cursorX + _kCursorGap + collapsedMaxWidth > viewportWidth;
        // Space available on the chosen side for an *expanded* label, so the
        // full value stays on screen (wrapping if needed) rather than spilling
        // past the viewport edge.
        final expandedMaxWidth = flip
            ? cursorX - _kCursorGap
            : viewportWidth - cursorX - _kCursorGap;

        final pills = <Widget>[];
        final readoutParts = <String>[];
        var anyTruncated = false;

        for (final row in geometry.rows) {
          final entry = row.entry;
          if (entry.kind != SignalEntryKind.signal) continue;
          final signalRef = entry.signalRef;
          if (signalRef == null) continue;

          // Cull to the visible band so off-screen lanes do not build a pill
          // (or resolve a value) on every cursor frame.
          final top = row.top - widget.scrollOffset;
          final bottom = row.bottom - widget.scrollOffset;
          if (bottom < 0 || top > viewportHeight) continue;

          final value = ref.watch(
            signalValueAtCursorProvider(
              signalRef,
              entry.format,
              entry.translatorConfig,
            ),
          );
          if (value == null) continue;

          final name = entry.displayName ?? signalRef;
          // The readout always carries the FULL value — assistive tech is never
          // subject to the on-screen truncation.
          readoutParts.add('$name ${value.formatted}');

          final accent = entry.argbColor != null
              ? Color(entry.argbColor!)
              : WavecruxColors.signalGreen;
          final expanded = _expandedRef == signalRef;
          final textWidth = _measureWidth(
            value.formatted,
            baseStyle,
            textScaler,
          );
          final truncated = textWidth > collapsedMaxWidth;
          if (truncated) anyTruncated = true;

          final pill = _ValuePill(
            text: value.formatted,
            style: baseStyle,
            accent: accent,
            background: colorScheme.surface,
            maxWidth: expanded ? expandedMaxWidth : collapsedMaxWidth,
            expanded: expanded,
          );

          // Only a truncated label is interactive (tap-to-expand). The hit
          // surface is padded out to the touch-target floor (44 dp) but the
          // visible pill keeps its natural size, centered within it.
          final content = truncated
              ? GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(
                    () => _expandedRef = expanded ? null : signalRef,
                  ),
                  child: _TouchTarget(
                    size: metrics.touchTarget,
                    child: pill,
                  ),
                )
              : IgnorePointer(child: pill);

          final laneCenterY = top + row.height / 2;
          final boxHeight = truncated
              ? (pillHeight > metrics.touchTarget
                    ? pillHeight
                    : metrics.touchTarget)
              : pillHeight;

          pills.add(
            Positioned(
              top: laneCenterY - boxHeight / 2,
              left: flip ? null : cursorX + _kCursorGap,
              right: flip ? viewportWidth - (cursorX - _kCursorGap) : null,
              child: content,
            ),
          );
        }

        return Semantics(
          container: true,
          label: l10n.accessibilityInlineCursorReadout(
            cursorTimeLabel,
            readoutParts.join(', '),
          ),
          hint: anyTruncated ? l10n.accessibilityInlineCursorExpandHint : null,
          child: ExcludeSemantics(
            child: Stack(children: pills),
          ),
        );
      },
    );
  }

  static double _measureWidth(
    String text,
    TextStyle style,
    TextScaler scaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: scaler,
    )..layout();
    // Account for the pill's horizontal padding so the truncation test matches
    // the rendered pill width.
    return painter.width + _kPillPaddingH * 2;
  }
}

/// Sizes its hit surface to at least [size] in both axes while keeping [child]
/// at its natural size, centered. Paired with [HitTestBehavior.translucent] so
/// the transparent margin around the visible pill is still tappable, giving the
/// tap-to-expand affordance a ≥ 44 dp touch target.
class _TouchTarget extends StatelessWidget {
  const _TouchTarget({required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minWidth: size, minHeight: size),
    child: Center(widthFactor: 1, heightFactor: 1, child: child),
  );
}

/// The legibility scrim/pill behind one inline value. Built-in, not a user knob.
class _ValuePill extends StatelessWidget {
  const _ValuePill({
    required this.text,
    required this.style,
    required this.accent,
    required this.background,
    required this.maxWidth,
    required this.expanded,
  });

  final String text;
  final TextStyle style;
  final Color accent;
  final Color background;
  final double maxWidth;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: accent.withValues(alpha: 0.6)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _kPillPaddingH,
            vertical: _kPillPaddingV,
          ),
          child: Text(
            text,
            style: style,
            maxLines: expanded ? null : 1,
            softWrap: expanded,
            overflow: expanded ? TextOverflow.clip : TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
