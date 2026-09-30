// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/diagnostics/providers/memory_stats_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/features/viewer/providers/export_providers.dart';
import 'package:wavecrux/features/viewer/providers/fsm_provider.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/services/tabs/wavecrux_tab_overrides.dart';

void main() {
  group('wavecruxTabOverrides', () {
    test('returns a non-empty list of overrides for a fresh TabId', () {
      final overrides = wavecruxTabOverrides(crux.TabId.generate());
      expect(overrides, isA<List<Override>>());
      expect(overrides, isNotEmpty);
    });

    test('returned list length is stable across calls (pure factory)', () {
      // Sanity check: the factory is pure — different TabIds produce
      // override lists of identical length. Catches a future regression
      // where TabId is accidentally branched on inside the factory body.
      final a = wavecruxTabOverrides(crux.TabId.generate());
      final b = wavecruxTabOverrides(crux.TabId.generate());
      expect(a.length, equals(b.length));
    });

    test('factory signature matches crux.TabOverridesFactory', () {
      // Compile-time check: `wavecruxTabOverrides` is assignable to the
      // package's `TabOverridesFactory` typedef, which is what the
      // package's `TabContainerManager.overridesFactory` parameter accepts.
      crux.TabOverridesFactory asFactory() => wavecruxTabOverrides;
      final list = asFactory()(crux.TabId.generate());
      expect(list, isA<List<Override>>());
    });

    test('Issue 17 regression: exportProvider is overridden per-tab '
        'so the notifier resolves per-tab waveformSourceProvider', () {
      // Pre-fix, `exportProvider` was `@Riverpod(keepAlive: true)` at root
      // scope only. Reading the notifier from the active tab's container
      // resolved to the root-scope instance, whose internal `ref.read`
      // returned the empty root-scope waveform source — surfacing the
      // "no waveform loaded" snackbar even when the focused tab had a
      // file open. Asserting the override is in the per-tab list pins the
      // architectural decision: the notifier MUST live per-tab.
      final overrides = wavecruxTabOverrides(crux.TabId.generate());
      final origins = overrides.map((o) => o.origin).toList();
      expect(origins, contains(exportProvider));
    });

    test('Issue 20 regression: memoryStatsProvider is overridden per-tab '
        'so each tab polls its own waveform source', () {
      // Pre-fix, `memoryStatsProvider` lived at the root scope. The App
      // Diagnostics dialog's `container.read(memoryStatsProvider)` calls
      // (one per tab) all resolved to the same root-scope notifier whose
      // `ref.read(waveformSourceProvider)` returned the empty default,
      // leaving the dialog's RSS / wellen-DB / per-tab table permanently
      // showing "—" / "0 B" / "—". Asserting the override is in the
      // per-tab list pins the architectural decision: each tab polls
      // its own source.
      final overrides = wavecruxTabOverrides(crux.TabId.generate());
      final origins = overrides.map((o) => o.origin).toList();
      expect(origins, contains(memoryStatsProvider));
    });

    test('Issue 44 regression: stageBoundSignalProvider is overridden per-tab '
        'so Stage widget bindings resolve against the focused tab source', () {
      // Pre-fix, `stageBoundSignalProvider` (a bare `@riverpod` family with no
      // declared dependencies) was missing from this list, so it hoisted to
      // the root container and read the empty root `waveformSourceProvider` —
      // returning `StageSignalSnapshot.noFile()` for every binding. Every
      // Stage widget then rendered "–" (inactive) regardless of cursor
      // position. See `per_tab_scope_behavior_test.dart` for the behavioral
      // proof and `static/per_tab_provider_scope_leak_test.dart` for the
      // structural guard against the whole bug class.
      final overrides = wavecruxTabOverrides(crux.TabId.generate());
      final origins = overrides.map((o) => o.origin).toList();
      expect(origins, contains(stageBoundSignalProvider));
    });

    test('FSM derived providers are overridden per-tab so the bubble diagram '
        'highlights state/transitions for the focused tab', () {
      // Same scope-leak class as issue #44, surfaced by the per-tab scope-leak
      // guardrail: both are bare `@riverpod` functions reading per-tab
      // `fsmProvider` / `cursorStateProvider` / `waveformSourceProvider`.
      // Without these overrides they read the never-analyzed root `fsmProvider`
      // and always return null.
      final overrides = wavecruxTabOverrides(crux.TabId.generate());
      final origins = overrides.map((o) => o.origin).toList();
      expect(origins, contains(fsmCurrentStateIdProvider));
      expect(origins, contains(fsmRecentTransitionProvider));
    });

    test('timeRulerDataProvider is overridden per-tab so the ruler reads the '
        'focused tab timescale', () {
      // Latent member of the issue #44 class (no production consumer yet, but
      // reads per-tab `currentTimescaleProvider` + `timeMapperProvider`).
      final overrides = wavecruxTabOverrides(crux.TabId.generate());
      final origins = overrides.map((o) => o.origin).toList();
      expect(origins, contains(timeRulerDataProvider));
    });
  });
}
