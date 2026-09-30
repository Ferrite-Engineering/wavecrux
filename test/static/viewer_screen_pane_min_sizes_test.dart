// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Structural guardrail for the IdeLayout pane min-size invariants
// (ARCHITECTURE.md §3.1.8.6): the per-tab `CruxIdeLayout` in
// `lib/features/viewer/screens/viewer_screen.dart` must construct its
// `IdeController` with pane minimums of at least:
//
//   - bottomMinSize ≥ 80 dp  — "The bottom panel must honor its
//     `bottomMinSize` (≥ 80 dp) so it cannot be re-shown at zero height."
//   - leftMinSize / rightMinSize ≥ 150 dp — side-pane minimums (a sub-150 dp
//     side pane crushes the signal tree / value column).
//   - centerMinSize ≥ 120 dp — stops the bottom-panel splitter from crushing
//     the time ruler + signal-list header (RenderFlex overflow in the
//     waveform center).
//
// HISTORY: this invariant used to be guarded by
// `test/shared/layouts/desktop_layout_min_sizes_test.dart`, which pumped the
// `DesktopLayout` widget and read its controller. That widget (and the whole
// AdaptiveScaffold layout family) was DEAD code — reachable only through the
// never-mounted `AdaptiveScaffold` — and has since been deleted. But the
// min-size constants it guarded still live verbatim in the real
// production path (`viewer_screen.dart`'s per-tab `CruxIdeLayout`), so the
// invariant is real; only its former test subject was dead. Isolate-testing
// the live `ViewerScreen` path is heavyweight (the `IdeController` is built
// deep inside a Riverpod-driven per-tab builder), so this replacement is a
// STRUCTURAL guard: it reads the source and asserts each `<pane>MinSize:
// PaneSize.pixel(N)` literal meets its floor.
//
// This mirrors every other guard in `test/static/`: a cheap regex over source
// that catches the common accidental regression (someone lowering a constant),
// not proof against a determined bad-faith bypass. If `viewer_screen.dart`
// ever expresses these minimums through a computed value instead of a literal
// `PaneSize.pixel(N)`, update this guard to match the new shape rather than
// silently letting it fall through.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'viewer_screen.dart CruxIdeLayout honors the ARCHITECTURE §3.1.8.6 pane '
    'min-size floors (bottom ≥ 80, left/right ≥ 150, center ≥ 120 dp)',
    () {
      final file = File(
        'lib/features/viewer/screens/viewer_screen.dart',
      );
      expect(
        file.existsSync(),
        isTrue,
        reason: 'run this test from the package root (flutter test)',
      );
      final src = file.readAsStringSync();

      // Each floor keyed by the exact `<name>:` label used at the
      // IdeController construction site.
      const floors = <String, double>{
        'bottomMinSize': 80,
        'leftMinSize': 150,
        'rightMinSize': 150,
        'centerMinSize': 120,
      };

      final failures = <String>[];
      floors.forEach((label, floor) {
        // Matches e.g. `bottomMinSize: PaneSize.pixel(80)` allowing arbitrary
        // whitespace and an integer or decimal literal.
        final match = RegExp(
          '$label:\\s*PaneSize\\.pixel\\(\\s*([0-9]+(?:\\.[0-9]+)?)\\s*\\)',
        ).firstMatch(src);
        if (match == null) {
          failures.add(
            '$label: no `$label: PaneSize.pixel(N)` literal found — the '
            'invariant site may have moved or changed shape; update this '
            'guard (see the header note).',
          );
          return;
        }
        final value = double.parse(match.group(1)!);
        if (value < floor) {
          failures.add(
            '$label: PaneSize.pixel($value) is below the ${floor.toInt()} dp '
            'floor (ARCHITECTURE.md §3.1.8.6).',
          );
        }
      });

      expect(
        failures,
        isEmpty,
        reason: 'Pane min-size invariant violations:\n${failures.join('\n')}',
      );
    },
  );
}
