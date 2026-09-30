// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Structural guardrail against the ROOT-SCOPED HOST form of the per-tab
// provider scope-leak bug class. Companion to
// `per_tab_provider_scope_leak_test.dart`.
//
// THE TWO FORMS OF THE BUG:
// * Provider→provider (the sibling test): a bare `@riverpod` provider whose
//   BODY reads a per-tab provider but isn't scoped per-tab → hoists to root.
// * Host→provider (THIS test): a widget/State or root-`keepAlive` service that
//   lives ABOVE the per-tab `UncontrolledProviderScope` reads/writes a per-tab
//   provider through its OWN root `ref` / `_ref`. It then targets the empty
//   root-scope instances the UI never updates — a silent no-op or wrong output
//   in every tab. This is the class that broke the RTL source panel, the cocotb
//   log panel, Compare Waveforms (`viewer_screen.dart`), and the CXP emitter +
//   inbound handlers — every one shipped green because flat-container unit
//   tests have no parent scope to fall through, so the leak is invisible to
//   them (see the sibling test's header for why).
//
// THE INVARIANT:
// In a root-scoped host, per-tab provider access MUST be routed through the
// active tab's container — `_activeTabContainer.read(...)`,
// `activeTabContainer(ref)`, a cached `_activeContainer`, or
// `tabContainerManager.containerFor(activeId)` — NOT a bare `ref.`/`_ref.`
// `.read`/`.watch`/`.listen` of a per-tab provider.
//
// This guard scans the curated [_rootHostFiles] for that bare-access signature.
// The per-tab provider set is derived from `wavecrux_tab_overrides.dart` so it
// can't rot. Legitimate exceptions (a per-tab-mounted widget method that takes
// the per-tab Consumer `ref` as a PARAMETER) are pinned by exact source line in
// [_allowlist] — so a *new* bare access on a different line still fails.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Root-scoped host files that sit above the per-tab scope and must route
/// per-tab access through the active tab's container. Extend this list whenever
/// a new root-`keepAlive` service/bridge or above-tab widget is added.
const List<String> _rootHostFiles = [
  'lib/features/viewer/screens/viewer_screen.dart',
  // The shortcut/menu dispatch surface extracted out of `viewer_screen.dart`.
  // It runs entirely on the screen's root-scope `ref`, so it is the largest
  // root-host dispatch surface in the app.
  'lib/features/viewer/screens/viewer_screen_shortcuts.dart',
  'lib/services/remote/cxp/cxp_selection_emitter.dart',
  'lib/services/remote/cxp/cxp_inbound_handlers.dart',
  // RTL annotation: answers the extension host's standing value query
  // from the active tab's waveform/cursor/format state, and re-binds its
  // cursor listen when the active tab changes.
  'lib/services/host_bridge/host_annotation_value_service.dart',
  'lib/services/collaboration/collab_viewer_bridge.dart',
  'lib/services/remote/remote_control_notifier.dart',
  'lib/features/viewer/providers/mobile_memory_guard_provider.dart',
];

/// Exact trimmed source lines that match the bare-access signature but are
/// legitimate. Pinned by full line text so any *new* bare access — on any other
/// line — still fails the guard. Two kinds of legitimate exception:
///   * a per-tab Consumer/builder PARAMETER `ref` (widget mounted UNDER the
///     per-tab scope, so its `ref` IS the tab container), and
///   * the root-FALLBACK branch of an `if (container != null) … else …` (the
///     audit-cleared idiom for unit tests / non-tabbed hosts).
/// Ternary (`: ref.read(…)`) and `??`-fallback branches are recognized
/// structurally below and need no entry here.
const Set<String> _allowlist = {
  // collab_viewer_bridge `} else { // Root fallback (unit tests / non-tabbed
  // host) }` — the active-container path is the sibling `if` branch above.
  '_markerSub = _ref.listen<MarkerState>(markerStateProvider, _onMarkers);',
  '_ref.listen(signalGroupsProvider, (_, _) => onChange()),',
  '_ref.listen(activeDecodersProvider, (_, _) => onChange()),',
  '_ref.listen(stageWorkspaceProvider, (_, _) => onChange()),',
  '_ref.listen(fsmProvider, (_, _) => onChange()),',
  '_ref.listen(panelLayoutProvider, (_, _) => onChange()),',
};

void main() {
  test(
    'no root-scoped host reads/writes a per-tab provider via a bare root ref '
    '(RTL/cocotb/diff/CXP scope-leak class)',
    () {
      final overridesFile = File(
        'lib/services/tabs/wavecrux_tab_overrides.dart',
      );
      expect(
        overridesFile.existsSync(),
        isTrue,
        reason: 'run this test from the package root (flutter test)',
      );

      final perTab =
          RegExp(
                r'([A-Za-z]\w*Provider)\.(?:overrideWith|overrideWithValue)',
              )
              .allMatches(overridesFile.readAsStringSync())
              .map((m) => m.group(1)!)
              .toSet();
      expect(
        perTab.length,
        greaterThan(20),
        reason:
            'sanity: per-tab override set unexpectedly small — did the '
            'override-file shape change?',
      );

      // `ref` / `_ref` . (read|watch|listen) [<T>] ( <perTabProvider>
      final access = RegExp(
        r'\b_?ref\.(?:read|watch|listen)(?:<[^>]*>)?\(\s*([A-Za-z]\w*Provider)\b',
      );

      final violations = <String>[];
      for (final path in _rootHostFiles) {
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'curated root-host file no longer exists: $path — update '
              '_rootHostFiles.',
        );
        final lines = file.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trim();
          // Comments — including doc comments that quote example code.
          if (trimmed.startsWith('//') ||
              trimmed.startsWith('*') ||
              trimmed.startsWith('/*')) {
            continue;
          }
          // Ternary fallback branch: `… ? container.read(x) : ref.read(x)`.
          if (trimmed.startsWith(':')) continue;
          // `??` / multi-line fallback: the active-container path is on the
          // immediately preceding line (`_activeContainer?.read(x) ??`).
          final prev = i > 0 ? lines[i - 1] : '';
          if (prev.contains('_activeContainer') ||
              prev.contains('activeTabContainer')) {
            continue;
          }
          for (final m in access.allMatches(line)) {
            final provider = m.group(1)!;
            if (!perTab.contains(provider)) continue;
            if (_allowlist.contains(trimmed)) continue;
            violations.add('$path:${i + 1}  $trimmed');
          }
        }
      }

      if (violations.isNotEmpty) {
        fail(
          'Root-scoped host reads/writes a per-tab provider via a bare root '
          'ref (issue #44 host form). Route through the active tab container '
          '(`_activeTabContainer` / `activeTabContainer(ref)` / a cached '
          '`_activeContainer` / `containerFor(activeId)`) instead — a bare '
          '`ref.`/`_ref.` hits the dead root-scope instance the UI never '
          'updates. If the `ref` is genuinely a per-tab Consumer PARAMETER, '
          'pin the exact line in _allowlist with a reason.\n\n'
          '${violations.join('\n')}',
        );
      }
    },
  );

  test('root-host scope-leak allowlist entries still match a real line', () {
    // Guard against allowlist rot: every pinned line must still appear verbatim
    // in some curated host file, so an edit forces the entry to be updated.
    final corpus = {
      for (final p in _rootHostFiles)
        if (File(p).existsSync())
          p: File(
            p,
          ).readAsStringSync().split('\n').map((l) => l.trim()).toSet(),
    };
    for (final entry in _allowlist) {
      expect(
        corpus.values.any((lines) => lines.contains(entry)),
        isTrue,
        reason:
            'allowlisted line no longer present in any root-host file — '
            'remove or update it:\n  $entry',
      );
    }
  });
}
