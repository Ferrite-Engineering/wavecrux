// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart' show Color, ColorScheme;

/// The colours an SVG export draws with.
///
/// **Why this exists.** The emitter used to bake ten hex literals, so an export
/// never looked like the app it came from — a blue-tinted document out of a
/// neutral-dark viewer, with every annotation in one fixed blue. The last of
/// those is the one that mattered: an annotation's colour *is* its author in a
/// collaborative session, so a single baked accent flattens a room's worth of
/// attribution into one indistinguishable hue the moment it is exported.
///
/// Defaults reproduce the old literals exactly, so a caller that supplies
/// nothing — a test, or a headless path with no theme in scope — emits the
/// document it always did.
///
/// Its own file because it is the one piece of the SVG emitter a caller
/// builds (from the theme); `image_export_service.dart` re-exports it, so an
/// import of the service still brings the palette with it.
class SvgExportPalette {
  const SvgExportPalette({
    this.background = '#1a1a2e',
    this.rulerBand = '#252540',
    this.laneBand = '#1e1e32',
    this.gridStrong = '#555577',
    this.gridWeak = '#333355',
    this.mutedText = '#8888bb',
    this.text = '#e6e6f0',
    this.annotationDefault = '#7AA2F7',
  });

  /// Builds a palette from the live theme, so the document matches the viewer.
  ///
  /// [annotationDefault] takes the theme's primary because that is exactly what
  /// the canvas gives a note carrying no colour of its own — see
  /// `AnnotationOverlay._colorFor`. A note that *does* carry one keeps it; this
  /// only decides the fallback.
  factory SvgExportPalette.fromScheme(ColorScheme scheme) => SvgExportPalette(
    background: _hex(scheme.surface),
    rulerBand: _hex(scheme.surfaceContainerHighest),
    laneBand: _hex(scheme.surfaceContainerHigh),
    gridStrong: _hex(scheme.outline),
    gridWeak: _hex(scheme.outlineVariant),
    mutedText: _hex(scheme.onSurfaceVariant),
    text: _hex(scheme.onSurface),
    annotationDefault: _hex(scheme.primary),
  );

  final String background;
  final String rulerBand;
  final String laneBand;
  final String gridStrong;
  final String gridWeak;
  final String mutedText;
  final String text;
  final String annotationDefault;

  static String _hex(Color c) {
    final argb = c.toARGB32();
    final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '#$rgb';
  }
}
