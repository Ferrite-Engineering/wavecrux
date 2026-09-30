// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/services/host_bridge/host_bridge.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_transport.dart';

import '../../support/fake_host_bridge_transport.dart';

/// The seam both halves of the bridge are written against.
///
/// It exists so `EditorHostBridge` and `HostRelayTelemetryService` can be
/// driven from the VM suite: the concrete `HostBridgeChannel` is chosen by a
/// conditional export and cannot be substituted, which would otherwise make
/// every inbound-dispatch test a browser test.
void main() {
  group('HostBridgeTransport', () {
    test('the shipped channel satisfies it', () {
      // Guards the seam itself: if the stub or the web channel stopped
      // implementing the interface, the consumers would still compile against
      // whichever one their build resolved and diverge silently.
      expect(HostBridgeChannel(), isA<HostBridgeTransport>());
    });

    test('the fake can stand in wherever the app depends on it', () {
      final fake = FakeHostBridgeTransport();
      expect(fake, isA<HostBridgeTransport>());
      expect(fake.hostKind, EditorHostKind.vscode);
    });

    test('a transport that cannot post records nothing', () {
      // The documented contract: `canPost == false` means frames are dropped,
      // never that the caller should find another route.
      final fake = FakeHostBridgeTransport(canPost: false)
        ..post(<String, Object?>{'type': 'crux.telemetry'});
      expect(fake.posted, isEmpty);
    });
  });
}
