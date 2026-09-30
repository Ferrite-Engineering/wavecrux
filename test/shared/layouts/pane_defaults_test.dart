// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/shared/layouts/pane_defaults.dart';

/// The iPhone Duo's two displays in logical points. The cover display is
/// exactly its 1398×2034 panel at 3x; the inner display's panel (1878×2670) is
/// downsampled, so 669×951 is the reported logical size rather than a simple
/// division. Both are here because the *inner* one is the reason the narrow
/// arm exists — see `paneDefaultsForViewport`.
const _duoInnerPortrait = Size(669, 951);
const _duoInnerLandscape = Size(951, 669);
const _duoCoverPortrait = Size(466, 678);

/// `CruxIdeLayout`'s per-region floors, as wired in `viewer_screen.dart`.
/// A default below these would simply be clamped back up, which would make the
/// narrow arm a no-op.
const _kPaneMinSize = 150.0;
const _kCentreMinSize = 120.0;

/// Two splitters, at the touch-metric visual width (`MobileMetrics.touch`).
const _kSplitters = 12.0;

void main() {
  group('paneDefaultsForViewport — standard', () {
    test('standard aspect ratios keep the 280 / 220 defaults', () {
      // 16:9 laptop, 16:10, 4:3 tablet, 3:2, a portrait tablet — all standard.
      for (final size in const [
        Size(1920, 1080), // 16:9
        Size(1440, 900), // 16:10
        Size(1024, 768), // 4:3
        Size(1200, 800), // 3:2
        Size(800, 1280), // portrait, exactly at the narrow threshold
        Size(2560, 1440), // 16:9 QHD
      ]) {
        final d = paneDefaultsForViewport(size);
        expect(d.left, 280, reason: 'left for $size');
        expect(d.right, 220, reason: 'right for $size');
      }
    });
  });

  group('paneDefaultsForViewport — ultrawide', () {
    test('21:9 ultrawide widens the side panes', () {
      final d = paneDefaultsForViewport(const Size(2560, 1080)); // ≈21.3:9
      expect(d.left, 360);
      expect(d.right, 280);
    });

    test('32:9 super-ultrawide widens them further', () {
      // The Viture Beast / ultrawide-monitor 32:9 productivity mode.
      final d = paneDefaultsForViewport(const Size(5120, 1440));
      expect(d.left, 420);
      expect(d.right, 320);
    });

    test('exact 21:9 threshold is inclusive', () {
      final d = paneDefaultsForViewport(const Size(21 / 9 * 1080, 1080));
      expect(d.left, 360);
      expect(d.right, 280);
    });

    test('just below 21:9 stays standard', () {
      final d = paneDefaultsForViewport(const Size(2300, 1080)); // ≈19.2:9
      expect(d.left, 280);
      expect(d.right, 220);
    });
  });

  group('paneDefaultsForViewport — narrow (width < 800)', () {
    test('iPhone Duo inner display, portrait → narrow', () {
      final d = paneDefaultsForViewport(_duoInnerPortrait);
      expect(d.left, 220);
      expect(d.right, 160);
    });

    test('iPad mini portrait (744 dp) → narrow', () {
      final d = paneDefaultsForViewport(const Size(744, 1133));
      expect(d.left, 220);
      expect(d.right, 160);
    });

    test('width just below the threshold → narrow', () {
      final d = paneDefaultsForViewport(const Size(799, 1000));
      expect(d.left, 220);
      expect(d.right, 160);
    });

    test('exactly at the threshold (800) → standard, not narrow', () {
      final d = paneDefaultsForViewport(const Size(800, 1000));
      expect(d.left, 280);
      expect(d.right, 220);
    });

    test('the narrow arm ignores aspect ratio', () {
      // A 700-dp-wide viewport that is also technically ultrawide (700×200)
      // is narrow first — there is no width to widen panes into.
      final d = paneDefaultsForViewport(const Size(700, 200));
      expect(d.left, 220);
      expect(d.right, 160);
    });

    test('narrow defaults clear CruxIdeLayout per-pane minimums', () {
      // Below the 150 dp floor the layout would clamp them back up and the
      // narrow arm would silently do nothing.
      final d = paneDefaultsForViewport(_duoInnerPortrait);
      expect(d.left, greaterThanOrEqualTo(_kPaneMinSize));
      expect(d.right, greaterThanOrEqualTo(_kPaneMinSize));
    });
  });

  group('paneDefaultsForViewport — canvas budget', () {
    /// Width left for the waveform canvas once both docks and the two
    /// splitters have taken their share, with both docks visible (the shipped
    /// default: `signalTreeVisible` and `valueColumnVisible` both start true).
    double canvasWidth(Size viewport) {
      final d = paneDefaultsForViewport(viewport);
      return viewport.width - d.left - d.right - _kSplitters;
    }

    test('Duo inner portrait gets a canvas worth looking at', () {
      final canvas = canvasWidth(_duoInnerPortrait);
      // Was ~157 dp (23% of the width) under the flat 280 / 220 defaults.
      expect(canvas, greaterThan(250));
      expect(canvas / _duoInnerPortrait.width, greaterThan(0.35));
    });

    test('Duo inner landscape is unaffected — it was never starved', () {
      // 951 dp is above the narrow threshold, so it keeps 280 / 220 and still
      // leaves the canvas the majority of the width.
      final d = paneDefaultsForViewport(_duoInnerLandscape);
      expect(d.left, 280);
      expect(d.right, 220);
      expect(
        canvasWidth(_duoInnerLandscape) / _duoInnerLandscape.width,
        greaterThan(0.45),
      );
    });

    test('unfolding never shrinks the canvas below the folded cover screen', () {
      // The regression this whole arm exists to prevent: on the cover display
      // the device is phone-class and both docks are force-hidden, so the
      // canvas is the full width. Opening the device must not hand the
      // waveform *less* room than the smaller screen did.
      expect(
        canvasWidth(_duoInnerPortrait),
        lessThan(_duoCoverPortrait.width),
        reason:
            'sanity: a 669 dp multi-pane canvas is still narrower than '
            'the 466 dp single-pane one — this test is about the ratio below',
      );
      // It cannot reach parity (the docks are the point of the tablet layout),
      // but it must be well over half, not the ~34% the flat defaults gave.
      expect(
        canvasWidth(_duoInnerPortrait) / _duoCoverPortrait.width,
        greaterThan(0.55),
      );
    });

    test('every narrow viewport clears the centre floor without clamping', () {
      for (final size in const [
        _duoInnerPortrait,
        Size(744, 1133), // iPad mini portrait
        Size(600, 1000), // the phone/tablet breakpoint itself
        Size(799, 1000),
      ]) {
        expect(
          canvasWidth(size),
          greaterThan(_kCentreMinSize),
          reason: 'canvas for $size must not need clamping',
        );
      }
    });
  });

  group('paneDefaultsForViewport — defensive inputs', () {
    test('degenerate zero height falls back to standard', () {
      final d = paneDefaultsForViewport(const Size(2560, 0));
      expect(d.left, 280);
      expect(d.right, 220);
    });

    test('degenerate zero width falls back to standard, not narrow', () {
      // A pre-layout zero width is "not known yet", not evidence of a narrow
      // display — answering `narrow` would be a guess.
      final d = paneDefaultsForViewport(const Size(0, 1000));
      expect(d.left, 280);
      expect(d.right, 220);
    });

    test('negative dimensions fall back to standard', () {
      final d = paneDefaultsForViewport(const Size(-100, -100));
      expect(d.left, 280);
      expect(d.right, 220);
    });
  });
}
