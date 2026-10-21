// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// WaveCrux's enablement of the ROUTE-MOUNTED per-tab scope-leak guard.
//
// The rule itself — what it catches, its three accepted forms of re-binding,
// and the seven things it deliberately does NOT catch — lives once in
// crux-shared, next to the scanner it depends on. Read that file first; this
// one only supplies WaveCrux's source roots and per-tab seed list.
//
// Why the rule exists, in WaveCrux's own terms: a dialog route is a child of
// the Navigator, which sits ABOVE the per-tab `UncontrolledProviderScope`. A
// widget mounted from `showDialog` that reads a per-tab provider through
// `WidgetRef` therefore resolves the ROOT container, where no file is loaded.
// The sibling `per_tab_provider_scope_leak_test` cannot see this: it analyses
// the *provider* graph, and this is a *widget*.
//
// WaveCrux had exactly this defect. Reconfiguring a decoder from the
// transaction table wrote the edit to the root notifier — no error, no visible
// change, the active tab silently kept its old configuration (fixed in
// open-core `22231934`, then closed as a class in `a12f5bed` by binding the
// launching container to the dialog subtree). It was invisible in a
// single-tab session, and invisible to the existing tests, because every one
// of them used a single `ProviderScope` so the panel and the dialog shared a
// container.
//
// The allowlist is one entry: the command palette. A violation is otherwise
// fixed, not listed. A dialog that reads a tab's providers is shown on that
// tab's own navigator (`ActiveTab.navigatorFor`), under the tab's one scope;
// it is never wrapped in a second `UncontrolledProviderScope`.

import 'dart:io';

import '../../crux-shared/packages/crux_workspace/test/static/route_mounted_scope_leak_guard.dart';

/// The command palette lists actions from `actionContextProvider`, which is a
/// ROOT provider that follows the active tab through root-scope bridges
/// (`tabListProvider`, `activeTabActionFlagsProvider`, ...). The taint scan
/// reaches a per-tab provider only through its `waveformIsLoadedProvider`
/// fallback, which is false at the root and exists so a widget test can drive
/// the loaded-file branch. In the running app the palette reads no per-tab
/// state, and it is an app-level surface: it covers the window, so it stays on
/// the root navigator.
const Map<String, String> _allowlist = <String, String>{
  'CommandPaletteDialog @ lib/features/command_palette/widgets/command_palette_dialog.dart:64':
      'app-level palette over root-scope action context; the per-tab read is '
      'an inert test-only fallback',
};

void main() {
  defineRouteMountedScopeLeakGuard(
    allowlist: _allowlist,
    sourceRoots: _sourceRoots,
    // Same seed sources as the sibling provider guard: the open-core per-tab
    // override list, unioned with the Pro overlay's when it is present —
    // `bootstrap` spreads both, so a provider re-bound by either is per-tab in
    // a real tab container.
    seedOverrideSpecs: const [
      'lib/services/tabs/wavecrux_tab_overrides.dart',
      '../lib/overrides.dart#proTabOverrides',
    ],
    bootstrapHint: 'run `flutter pub get` in wavecrux/',
  );
}

/// Open-core `lib/`, plus the Pro overlay's `lib/` when this checkout is the
/// Pro overlay's submodule — so a taint chain crossing the repo boundary
/// still resolves. A standalone open-core checkout scans open-core only.
List<Directory> _sourceRoots() {
  final roots = <Directory>[Directory('lib')];
  final proLib = Directory('../lib');
  if (proLib.existsSync() && File('../lib/overrides.dart').existsSync()) {
    roots.add(proLib);
  }
  return roots;
}
