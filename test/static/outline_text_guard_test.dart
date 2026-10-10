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
// ## Heuristic, and why
//
// A precise "does this feed a `TextStyle.color`?" check needs a type-aware
// analysis this guard doesn't have. Instead it scans for the bare,
// word-bounded token `.outline` (so `.outlineVariant` never matches — there
// is no word boundary between "e" and "V" — and neither does an `Icons.*`
// name like `help_outline`, since nothing precedes "outline" there with a
// literal `.`) under any receiver: `colorScheme.outline`, `theme.colorScheme
// .outline`, a local `scheme.outline`, `cs.outline`, and so on — the sweep
// that produced this guard found more than one spelling in use across the
// suite, so the token match is deliberately receiver-agnostic.
//
// Every surviving occurrence must be pinned in `_exemptions` with the exact
// file, line, and trimmed line content, plus a reason it is NOT a text-color
// use. If the file changes around that line, the recorded content stops
// matching and the guard re-flags whatever now sits there instead of
// silently carrying the exemption forward — a new, unreviewed use of the
// token (text or not) always fails until someone looks at it.
//
// ## Scope
//
// `lib/` only, this repository. Each of the suite's open cores keeps its
// own copy of this guard, scoped to its own `lib/`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final exemptions = <_Exemption>[
    const _Exemption(
      file: 'lib/core/theme/wavecrux_theme.dart',
      line: 145,
      expectedTrimmed: 'borderSide: BorderSide(color: colorScheme.outline),',
      reason:
          'the default TextField border color (OutlineInputBorder.borderSide) '
          '— a border, not text.',
    ),
    const _Exemption(
      file: 'lib/features/workspace/widgets/web_drop_zone.dart',
      line: 78,
      expectedTrimmed:
          ': Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),',
      reason:
          "Border.all() color for the web drop zone's idle outline — a "
          'border, not text.',
    ),
    const _Exemption(
      file: 'lib/features/viewer/screens/viewer_screen_widgets.dart',
      line: 377,
      expectedTrimmed: 'color: colorScheme.outline.withValues(alpha: 0.4),',
      reason:
          "Border.all() color for a jump-to-marker letter tile's cell "
          'border — a border, not text.',
    ),
    const _Exemption(
      file: 'lib/features/viewer/widgets/fsm_bubble_painter.dart',
      line: 101,
      expectedTrimmed:
          '..color = isActive ? colorScheme.primary : colorScheme.outline;',
      reason:
          "CustomPainter Paint.color for an FSM state bubble's stroke "
          '(PaintingStyle.stroke) — a painter outline, not text.',
    ),
    const _Exemption(
      file: 'lib/features/viewer/widgets/waveform_horizontal_scrollbar.dart',
      line: 159,
      expectedTrimmed: 'color: theme.colorScheme.outline,',
      reason:
          'DecoratedBox fill color for the scrollbar thumb — a fill, not '
          'text.',
    ),
    const _Exemption(
      file: 'lib/features/viewer/widgets/time_ruler_widget.dart',
      line: 482,
      expectedTrimmed: 'borderColor: colorScheme.outline,',
      reason:
          'a CustomPainter constructor argument, assigned to Paint.color '
          "for the ruler's border stroke elsewhere in the same file — a "
          'painter outline, not text.',
    ),
    const _Exemption(
      file: 'lib/features/decoders/widgets/transaction_table_panel.dart',
      line: 500,
      expectedTrimmed: 'color: Theme.of(context).colorScheme.outline,',
      reason:
          "Border.all() color for the decoder filter button's cell border "
          '— a border, not text.',
    ),
    const _Exemption(
      file: 'lib/features/stage/widgets/riscv/riscv_commit_views.dart',
      line: 156,
      expectedTrimmed: 'color: theme.colorScheme.outline,',
      reason:
          'an Icon(Icons.dashboard_customize_outlined, ...) color — icon '
          'tinting, not text. The adjacent Text() in the same Row was fixed '
          'to onSurfaceVariant.',
    ),
    const _Exemption(
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
      reason:
          'lib/ must exist for this guard to mean anything — run from the '
          'repository root',
    );

    // Word-bounded, receiver-agnostic: matches `colorScheme.outline`,
    // `theme.colorScheme.outline`, `scheme.outline`, `cs.outline`, ... but
    // never `.outlineVariant` (no boundary between "e" and "V") and never an
    // `Icons.*_outline` name (no literal "." precedes "outline" there).
    final tokenPattern = RegExp(r'\.outline\b(?!Variant)');

    final exemptByFile = <String, List<_Exemption>>{};
    for (final e in exemptions) {
      exemptByFile.putIfAbsent(e.file, () => []).add(e);
    }

    final offenders = <String>[];
    var filesScanned = 0;
    var tokensSeen = 0;

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relPath = entity.path.replaceAll(r'\', '/');
      filesScanned++;

      final lines = entity.readAsStringSync().split('\n');
      final fileExemptions = exemptByFile[relPath] ?? const [];
      for (var i = 0; i < lines.length; i++) {
        if (!tokenPattern.hasMatch(lines[i])) continue;
        tokensSeen++;

        final lineNo = i + 1;
        final trimmed = lines[i].trim();
        final isExempt = fileExemptions.any(
          (e) => e.line == lineNo && e.expectedTrimmed == trimmed,
        );
        if (isExempt) continue;

        offenders.add('$relPath:$lineNo: $trimmed');
      }
    }

    // Non-vacuity: a broken regex or a wrong working directory would make
    // this guard pass by finding nothing at all.
    expect(
      filesScanned,
      greaterThan(100),
      reason:
          'the source walk collected implausibly few files — check the '
          'working directory (must run from the repository root)',
    );
    expect(
      tokensSeen,
      greaterThanOrEqualTo(exemptions.length),
      reason:
          'expected to see at least the ${exemptions.length} known '
          'exempted outline sites; the scan found $tokensSeen — is the '
          'regex or the file walk broken?',
    );

    expect(
      offenders,
      isEmpty,
      reason:
          'the outline token is used where onSurfaceVariant belongs (or an '
          "unreviewed new use that needs an entry in this guard's "
          'exemption list, with a reason):\n\n${offenders.join('\n')}',
    );
  });

  test('the token pattern matches the shapes it must and none it must not', () {
    final tokenPattern = RegExp(r'\.outline\b(?!Variant)');
    for (final positive in <String>[
      'color: theme.colorScheme.outline,',
      'color: colorScheme.outline,',
      'gridStrong: _hex(scheme.outline),',
      'color: cs.outline,',
    ]) {
      expect(
        tokenPattern.hasMatch(positive),
        isTrue,
        reason: 'should have matched: $positive',
      );
    }
    for (final negative in <String>[
      'theme.colorScheme.outlineVariant',
      'icon: Icons.dashboard_customize_outlined,',
      'icon: Icons.help_outline,',
      'border: const OutlineInputBorder()',
    ]) {
      expect(
        tokenPattern.hasMatch(negative),
        isFalse,
        reason: 'should not have matched: $negative',
      );
    }
  });
}

class _Exemption {
  const _Exemption({
    required this.file,
    required this.line,
    required this.expectedTrimmed,
    required this.reason,
  });

  final String file;
  final int line;
  final String expectedTrimmed;

  /// Not read by the check itself — kept for a human auditing the list.
  final String reason;
}
