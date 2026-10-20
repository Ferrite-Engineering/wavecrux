// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard: a ColorScheme's `outline` token never colors TEXT.
//
// `outline` is a Material 3 BORDER token — the hairline around an
// `OutlineInputBorder`, a card edge, a divider, a painter's stroke. The
// suite's UI conventions are explicit that de-emphasised text must use
// `onSurfaceVariant` instead: `outline` was never chosen against WCAG
// text-contrast minimums, only against adjacent surface colors, so using it
// to color text reads as a contrast failure. A paid accessibility re-check
// is the reason this sweep happened now; this guard is what keeps a new
// violation from shipping quietly afterward.
//
// A 2026-09 sweep of this repository found the token used as a text color
// in 29 places — mostly de-emphasised labels (`labelSmall`/`bodySmall`
// `copyWith(color: ...)`), a monospace helper (`_mono`), and two places
// where a shared `(label, Color)` record fed both a status chip's fill and
// its own label `Text`. All 29 are fixed to `onSurfaceVariant` below this
// guard's write date. What remains, and is pinned in `_exemptions`, is a
// border, three painter strokes, two fills, an SVG-export grid-line hex
// value, and one icon tint — none of them text.
//
// ## Scanner
//
// The scan is crux_guards' `cruxAuditOutlineText` (shared by the four
// products, crux-shared#18): it parses the source, so a mention in a comment
// or string is not a use, and it matches every `.outline` / `?.outline`
// member access under any receiver but never `.outlineVariant` or an
// `Icons.*_outline` name.
//
// Every surviving occurrence must be pinned in `exemptions` with the exact
// file, line, and trimmed line content, plus a reason it is NOT a text-color
// use. If the file changes around that line, the recorded content stops
// matching and the guard re-flags whatever now sits there; an exemption that
// matches nothing is a finding too, so the list cannot outlive the code.
//
// ## Scope
//
// `lib/` only, this repository.

import 'dart:io';

import 'package:crux_guards/crux_guards.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final exemptions = <CruxOutlineExemption>[
    const CruxOutlineExemption(
      file: 'lib/core/theme/wavecrux_theme.dart',
      line: 215,
      expectedTrimmed: 'borderSide: BorderSide(color: colorScheme.outline),',
      reason:
          'the default TextField border color (OutlineInputBorder.borderSide) '
          '— a border, not text.',
    ),
    const CruxOutlineExemption(
      file: 'lib/features/workspace/widgets/web_drop_zone.dart',
      line: 78,
      expectedTrimmed:
          ': Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),',
      reason:
          "Border.all() color for the web drop zone's idle outline — a "
          'border, not text.',
    ),
    const CruxOutlineExemption(
      file: 'lib/features/viewer/screens/viewer_screen_widgets.dart',
      line: 375,
      expectedTrimmed: 'color: colorScheme.outline.withValues(alpha: 0.4),',
      reason:
          "Border.all() color for a jump-to-marker letter tile's cell "
          'border — a border, not text.',
    ),
    const CruxOutlineExemption(
      file: 'lib/features/viewer/widgets/fsm_bubble_painter.dart',
      line: 101,
      expectedTrimmed:
          '..color = isActive ? colorScheme.primary : colorScheme.outline;',
      reason:
          "CustomPainter Paint.color for an FSM state bubble's stroke "
          '(PaintingStyle.stroke) — a painter outline, not text.',
    ),
    const CruxOutlineExemption(
      file: 'lib/features/viewer/widgets/waveform_horizontal_scrollbar.dart',
      line: 159,
      expectedTrimmed: 'color: theme.colorScheme.outline,',
      reason:
          'DecoratedBox fill color for the scrollbar thumb — a fill, not '
          'text.',
    ),
    const CruxOutlineExemption(
      file: 'lib/features/viewer/widgets/time_ruler_widget.dart',
      line: 482,
      expectedTrimmed: 'borderColor: colorScheme.outline,',
      reason:
          'a CustomPainter constructor argument, assigned to Paint.color '
          "for the ruler's border stroke elsewhere in the same file — a "
          'painter outline, not text.',
    ),
    const CruxOutlineExemption(
      file: 'lib/features/decoders/widgets/transaction_table_panel.dart',
      line: 500,
      expectedTrimmed: 'color: Theme.of(context).colorScheme.outline,',
      reason:
          "Border.all() color for the decoder filter button's cell border "
          '— a border, not text.',
    ),
    const CruxOutlineExemption(
      file: 'lib/features/stage/widgets/riscv/riscv_commit_views.dart',
      line: 156,
      expectedTrimmed: 'color: theme.colorScheme.outline,',
      reason:
          'an Icon(Icons.dashboard_customize_outlined, ...) color — icon '
          'tinting, not text. The adjacent Text() in the same Row was fixed '
          'to onSurfaceVariant.',
    ),
    const CruxOutlineExemption(
      file: 'lib/services/export/image_export_service.dart',
      line: 73,
      expectedTrimmed: 'gridStrong: _hex(scheme.outline),',
      reason:
          'the strong grid-line hex value in the SVG export palette, paired '
          'with a separate mutedText/text hex pair for actual label text in '
          'the same palette — a stroke color, not text.',
    ),
  ];

  test('the outline token is never used to color text', () {
    final root = Directory('lib');
    expect(
      root.existsSync(),
      isTrue,
      reason: 'lib/ must exist; run from the repository root',
    );
    final sources = [
      for (final f in root.listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart'))
          CruxGuardSource(
            path: f.path.replaceAll(r'\', '/'),
            source: f.readAsStringSync(),
          ),
    ];

    final result = cruxAuditOutlineText(
      sources: sources,
      exemptions: exemptions,
    );

    // Non-vacuity: a wrong working directory would pass by finding nothing.
    expect(result.filesScanned, greaterThan(100));
    expect(
      result.isClean,
      isTrue,
      reason:
          'the outline token is used where onSurfaceVariant belongs (or an '
          'unreviewed new use that needs an exemption, with a reason):\n\n'
          '${result.describe()}',
    );
  });
}
