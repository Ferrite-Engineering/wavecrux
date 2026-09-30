// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/workspace/providers/desktop_file_drop_provider.dart';
import 'package:wavecrux/services/platform/desktop_file_drop_router.dart';

void main() {
  test('one router for the life of the container', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = container.read(desktopFileDropRouterProvider)
      ..attach(
        DesktopFileDropHandler(canAccept: () => true, onDrop: (_) async {}),
      );
    // Keep-alive: with no listener in between, a later read must still be the
    // instance the viewer attached to, or the window target would deliver
    // into a fresh, empty router.
    await container.pump();
    expect(container.read(desktopFileDropRouterProvider), same(router));
    expect(container.read(desktopFileDropRouterProvider).canAccept, isTrue);
  });
}
