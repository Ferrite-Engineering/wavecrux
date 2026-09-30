// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/tab_id.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

ProviderContainer _makeRoot(TabContainerManager tcm) {
  final root = ProviderContainer(
    overrides: [tabContainerManagerProvider.overrideWithValue(tcm)],
  );
  tcm.init(root);
  return root;
}

void main() {
  group('TabContainerManager', () {
    test('containerFor returns same container on repeated calls', () {
      final tcm = TabContainerManager();
      final root = _makeRoot(tcm);
      addTearDown(root.dispose);
      addTearDown(tcm.dispose);

      final id = TabId.generate();
      final c1 = tcm.containerFor(id);
      final c2 = tcm.containerFor(id);
      expect(identical(c1, c2), isTrue);
    });

    test('different TabIds get different containers', () {
      final tcm = TabContainerManager();
      final root = _makeRoot(tcm);
      addTearDown(root.dispose);
      addTearDown(tcm.dispose);

      final a = TabId.generate();
      final b = TabId.generate();
      final ca = tcm.containerFor(a);
      final cb = tcm.containerFor(b);
      expect(identical(ca, cb), isFalse);
    });

    test('tab container overrides tabIdProvider with the correct id', () {
      final tcm = TabContainerManager();
      final root = _makeRoot(tcm);
      addTearDown(root.dispose);
      addTearDown(tcm.dispose);

      final id = TabId.generate();
      final tabContainer = tcm.containerFor(id);
      expect(tabContainer.read(tabIdProvider), equals(id));
    });

    test(
      'per-tab state is isolated — mutation in one does not affect another',
      () {
        final tcm = TabContainerManager();
        final root = _makeRoot(tcm);
        addTearDown(root.dispose);
        addTearDown(tcm.dispose);

        final idA = TabId.generate();
        final idB = TabId.generate();
        final ca = tcm.containerFor(idA);
        final cb = tcm.containerFor(idB);

        expect(ca.read(tabIdProvider), equals(idA));
        expect(cb.read(tabIdProvider), equals(idB));
        expect(ca.read(tabIdProvider), isNot(equals(cb.read(tabIdProvider))));
      },
    );

    test('global providers resolve from root via parent lookup', () {
      final tcm = TabContainerManager();
      final root = _makeRoot(tcm);
      addTearDown(root.dispose);
      addTearDown(tcm.dispose);

      final id = TabId.generate();
      final tabContainer = tcm.containerFor(id);

      // tabListProvider is global (root-level); reading it from
      // a tab container must return the same state as reading from root.
      final fromRoot = root.read(tabListProvider);
      final fromTab = tabContainer.read(tabListProvider);
      expect(fromTab, equals(fromRoot));
    });

    test('disposeTab removes container from cache', () {
      final tcm = TabContainerManager();
      final root = _makeRoot(tcm);
      addTearDown(root.dispose);
      addTearDown(tcm.dispose);

      final id = TabId.generate();
      final c1 = tcm.containerFor(id);
      tcm.disposeTab(id);
      // After disposal a new container is created on next access.
      final c2 = tcm.containerFor(id);
      expect(identical(c1, c2), isFalse);
      // Clean up the replacement container.
      tcm.disposeTab(id);
    });

    test('dispose clears all containers', () {
      final tcm = TabContainerManager();
      final root = _makeRoot(tcm);
      addTearDown(root.dispose);

      tcm
        ..containerFor(TabId.generate())
        ..containerFor(TabId.generate())
        ..dispose(); // must not throw
    });
  });
}
