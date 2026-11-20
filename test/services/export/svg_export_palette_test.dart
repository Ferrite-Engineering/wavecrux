// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/export/image_export_service.dart' as service;
import 'package:wavecrux/services/export/svg_export_palette.dart';

void main() {
  group('SvgExportPalette', () {
    test('defaults reproduce the historical literals', () {
      const p = SvgExportPalette();

      expect(p.background, '#1a1a2e');
      expect(p.gridStrong, '#555577');
      expect(p.mutedText, '#8888bb');
      expect(p.text, '#e6e6f0');
      expect(p.annotationDefault, '#7AA2F7');
    });

    test('fromScheme takes the theme colours as #rrggbb', () {
      const scheme = ColorScheme.light(
        surface: Color(0xFF102030),
        outline: Color(0xFFAABBCC),
        onSurfaceVariant: Color(0xFF445566),
        onSurface: Color(0xFF010203),
        primary: Color(0x80FF0000),
      );
      final p = SvgExportPalette.fromScheme(scheme);

      expect(p.background, '#102030');
      expect(p.gridStrong, '#aabbcc');
      expect(p.mutedText, '#445566');
      expect(p.text, '#010203');
      // Alpha is dropped: SVG colours here are opaque hex.
      expect(p.annotationDefault, '#ff0000');
    });

    test('is re-exported by the image export service', () {
      // The service library's export keeps every existing import working.
      expect(const service.SvgExportPalette(), isA<SvgExportPalette>());
    });
  });
}
