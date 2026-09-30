// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Regression guard for the structural scope-eviction seam
// (`crux_workspace`'s `WorkspaceScopeReconciler`).
//
// `bootstrap()` registers both container managers with the workspace notifier
// via `addScopeReconciler`. Nothing fails to compile if that wiring is
// deleted — which is exactly why it needs a test. Without it:
//
//   1. Every tab ever opened keeps its `ProviderContainer` (and therefore its
//      providers, subscriptions and timers) alive for the process lifetime.
//   2. Worse: `TabId`s round-trip through the workspace JSON document, so a
//      workspace reload that revives an id hands the "new" tab the DEAD tab's
//      container. That presents as cross-tab state bleed, not memory growth.
//
// The second failure is the one these tests pin.

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/pane_id.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/features/panes/providers/pane_id_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

ProviderContainer _makeRoot(TabContainerManager tcm, PaneContainerManager pcm) {
  final root = ProviderContainer(
    overrides: [
      tabContainerManagerProvider.overrideWithValue(tcm),
      paneContainerManagerProvider.overrideWithValue(pcm),
    ],
  );
  tcm.init(root);
  pcm.init(root);
  return root;
}

void main() {
  group('TabContainerManager as a WorkspaceScopeReconciler', () {
    test('implements the package interface', () {
      expect(TabContainerManager(), isA<crux.WorkspaceScopeReconciler>());
    });

    test('evicts the container of a tab absent from the live snapshot', () {
      final tcm = TabContainerManager();
      final pcm = PaneContainerManager();
      final root = _makeRoot(tcm, pcm);
      addTearDown(root.dispose);
      addTearDown(tcm.dispose);
      addTearDown(pcm.dispose);

      final kept = TabId.generate();
      final closed = TabId.generate();
      final keptContainer = tcm.containerFor(kept);
      final closedContainer = tcm.containerFor(closed);

      tcm.reconcileScopes(
        crux.WorkspaceScopeSnapshot(
          tabIds: {kept},
          paneIds: const <PaneId>{},
        ),
      );

      // The surviving tab keeps the very same container instance…
      expect(identical(tcm.containerFor(kept), keptContainer), isTrue);
      // …and the closed tab's container was actually disposed, not merely
      // dropped from a map.
      expect(
        () => closedContainer.read(tabIdProvider),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'a closed-then-revived tab id gets a FRESH container, not the dead one',
      () {
        // This is the resurrection failure mode. `TabId`s persist in the
        // workspace document, so loading a saved workspace can revive an id
        // the manager still holds a container for.
        final tcm = TabContainerManager();
        final pcm = PaneContainerManager();
        final root = _makeRoot(tcm, pcm);
        addTearDown(root.dispose);
        addTearDown(tcm.dispose);
        addTearDown(pcm.dispose);

        final id = TabId.generate();
        final before = tcm.containerFor(id);

        // Workspace replaced wholesale: the notifier emits the empty snapshot
        // first precisely so a reused id cannot inherit the old scope.
        tcm
          ..reconcileScopes(const crux.WorkspaceScopeSnapshot.empty())
          // …then the incoming document, which declares the same id.
          ..reconcileScopes(
            crux.WorkspaceScopeSnapshot(
              tabIds: {id},
              paneIds: const <PaneId>{},
            ),
          );

        final after = tcm.containerFor(id);
        expect(
          identical(before, after),
          isFalse,
          reason:
              "The revived tab inherited the dead tab's ProviderContainer — "
              'this is cross-tab state bleed.',
        );
        expect(after.read(tabIdProvider), id);
      },
    );

    test('reconciling with everything alive evicts nothing', () {
      final tcm = TabContainerManager();
      final pcm = PaneContainerManager();
      final root = _makeRoot(tcm, pcm);
      addTearDown(root.dispose);
      addTearDown(tcm.dispose);
      addTearDown(pcm.dispose);

      final a = TabId.generate();
      final b = TabId.generate();
      final ca = tcm.containerFor(a);
      final cb = tcm.containerFor(b);

      tcm.reconcileScopes(
        crux.WorkspaceScopeSnapshot(
          tabIds: {a, b},
          paneIds: const <PaneId>{},
        ),
      );

      expect(identical(tcm.containerFor(a), ca), isTrue);
      expect(identical(tcm.containerFor(b), cb), isTrue);
    });
  });

  group('PaneContainerManager as a WorkspaceScopeReconciler', () {
    test('implements the package interface', () {
      expect(PaneContainerManager(), isA<crux.WorkspaceScopeReconciler>());
    });

    test('evicts the container of a pane absent from the live snapshot', () {
      final tcm = TabContainerManager();
      final pcm = PaneContainerManager();
      final root = _makeRoot(tcm, pcm);
      addTearDown(root.dispose);
      addTearDown(tcm.dispose);
      addTearDown(pcm.dispose);

      final kept = PaneId.generate();
      final closed = PaneId.generate();
      final keptContainer = pcm.containerFor(kept);
      final closedContainer = pcm.containerFor(closed);

      pcm.reconcileScopes(
        crux.WorkspaceScopeSnapshot(
          tabIds: const <TabId>{},
          paneIds: {kept},
        ),
      );

      expect(identical(pcm.containerFor(kept), keptContainer), isTrue);
      expect(
        () => closedContainer.read(paneIdProvider),
        throwsA(isA<StateError>()),
      );
    });

    test('a closed-then-revived pane id gets a FRESH container', () {
      final tcm = TabContainerManager();
      final pcm = PaneContainerManager();
      final root = _makeRoot(tcm, pcm);
      addTearDown(root.dispose);
      addTearDown(tcm.dispose);
      addTearDown(pcm.dispose);

      final id = PaneId.generate();
      final before = pcm.containerFor(id);

      pcm
        ..reconcileScopes(const crux.WorkspaceScopeSnapshot.empty())
        ..reconcileScopes(
          crux.WorkspaceScopeSnapshot(
            tabIds: const <TabId>{},
            paneIds: {id},
          ),
        );

      final after = pcm.containerFor(id);
      expect(identical(before, after), isFalse);
      expect(after.read(paneIdProvider), id);
    });
  });
}
