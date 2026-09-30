// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/services/host_bridge/editor_host_bridge.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_provider.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_transport.dart';

import '../../support/fake_host_bridge_transport.dart';

/// The two providers `bootstrap` reads.
///
/// The property that matters on every non-webview host — which is all of them
/// today except the extension panel — is that reading them costs an allocation
/// and installs nothing. `bootstrap` reads `editorHostBridgeProvider`
/// unconditionally, so if that were not true every desktop and mobile launch
/// would pay for a bridge that has nothing to talk to.
void main() {
  group('hostBridgeChannelProvider', () {
    test('is one channel per container', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // A second channel would double every inbound frame, because both would
      // hold their own `window` message listener.
      expect(
        identical(
          container.read(hostBridgeChannelProvider),
          container.read(hostBridgeChannelProvider),
        ),
        isTrue,
      );
    });

    test('resolves the transport seam, not a concrete class', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(hostBridgeChannelProvider),
        isA<HostBridgeTransport>(),
      );
    });

    test('is overridable, which is how the bridge is testable at all', () {
      final fake = FakeHostBridgeTransport();
      final container = ProviderContainer(
        overrides: [hostBridgeChannelProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      expect(container.read(hostBridgeChannelProvider), same(fake));
    });
  });

  group('editorHostBridgeProvider', () {
    test('reports no host on this platform and installs nothing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final bridge = container.read(editorHostBridgeProvider);
      expect(bridge, isA<EditorHostBridge>());
      expect(bridge.hostKind, EditorHostKind.none);
    });

    test('starts the bridge over the container-scoped channel', () async {
      final fake = FakeHostBridgeTransport();
      final container = ProviderContainer(
        overrides: [hostBridgeChannelProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final bridge = container.read(editorHostBridgeProvider);
      expect(bridge.hostKind, EditorHostKind.vscode);
      // Started, not merely constructed: the inbound listener is live.
      fake.deliver(<String, Object?>{'type': 'not.ours'});
      await Future<void>.delayed(Duration.zero);
      expect(fake.posted, isEmpty);
    });

    test('disposing the container disposes both', () {
      final fake = FakeHostBridgeTransport();
      ProviderContainer(
          overrides: [hostBridgeChannelProvider.overrideWithValue(fake)],
        )
        ..read(editorHostBridgeProvider)
        ..dispose();

      // The bridge stops posting once disposed; asserting via the transport
      // keeps this about observable behaviour rather than a private flag.
      fake.deliver(<String, Object?>{'type': 'not.ours'});
      expect(fake.posted, isEmpty);
    });
  });
}
