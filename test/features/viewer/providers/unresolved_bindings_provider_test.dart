// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/providers/unresolved_bindings_provider.dart';
import 'package:wavecrux/services/session/binding_paths.dart';

void main() {
  const missing = UnresolvedBinding(owner: 'spi #1', slot: 'clk', path: 'a.b');

  test('starts empty', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(unresolvedBindingsProvider), isEmpty);
  });

  test('report replaces the set; clear empties it', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notifier = c.read(unresolvedBindingsProvider.notifier)
      ..report(const [missing, missing]);
    expect(c.read(unresolvedBindingsProvider), hasLength(2));

    notifier.report(const [missing]);
    expect(c.read(unresolvedBindingsProvider), const [missing]);

    notifier.clear();
    expect(c.read(unresolvedBindingsProvider), isEmpty);
  });

  test('clear on an empty notice does not notify', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    var notified = 0;
    c.listen(unresolvedBindingsProvider, (_, _) => notified++);
    c.read(unresolvedBindingsProvider.notifier).clear();
    expect(notified, 0);
  });
}
