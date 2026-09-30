// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/workspace/providers/other_tabs_from_last_session_provider.dart';

WorkspaceTab _tab(String name) => buildWorkspaceTab(
  id: TabId.generate(),
  displayName: name,
  paneId: PaneId.fromString('00000000-0000-0000-0000-000000000001'),
  filePath: '/tmp/$name',
);

void main() {
  group('OtherTabsFromLastSession notifier', () {
    test('initial state is an empty list', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(otherTabsFromLastSessionProvider), isEmpty);
    });

    test('set replaces the state with the provided tabs', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final a = _tab('a.vcd');
      final b = _tab('b.vcd');
      c.read(otherTabsFromLastSessionProvider.notifier).set([a, b]);
      expect(c.read(otherTabsFromLastSessionProvider), [a, b]);
    });

    test('set with empty input clears the state', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(otherTabsFromLastSessionProvider.notifier).set([_tab('x.vcd')]);
      c.read(otherTabsFromLastSessionProvider.notifier).set(const []);
      expect(c.read(otherTabsFromLastSessionProvider), isEmpty);
    });

    test('remove drops the matching tab and leaves the rest in order', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final a = _tab('a.vcd');
      final b = _tab('b.vcd');
      final cTab = _tab('c.vcd');
      c.read(otherTabsFromLastSessionProvider.notifier).set([a, b, cTab]);
      c.read(otherTabsFromLastSessionProvider.notifier).remove(b);
      expect(c.read(otherTabsFromLastSessionProvider), [a, cTab]);
    });

    test('remove on a non-member is a no-op', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final a = _tab('a.vcd');
      final unknown = _tab('z.vcd');
      c.read(otherTabsFromLastSessionProvider.notifier).set([a]);
      c.read(otherTabsFromLastSessionProvider.notifier).remove(unknown);
      expect(c.read(otherTabsFromLastSessionProvider), [a]);
    });

    test('clear empties the list', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(otherTabsFromLastSessionProvider.notifier).set([
        _tab('a.vcd'),
        _tab('b.vcd'),
      ]);
      c.read(otherTabsFromLastSessionProvider.notifier).clear();
      expect(c.read(otherTabsFromLastSessionProvider), isEmpty);
    });
  });
}
