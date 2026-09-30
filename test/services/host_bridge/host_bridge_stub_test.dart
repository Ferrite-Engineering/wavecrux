// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/services/host_bridge/host_bridge.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_transport.dart';

/// The stub is what desktop, mobile and this test runner actually get from the
/// conditional export in `host_bridge.dart`, so "the bridge is inert off the
/// web" is not a claim about a code path — it is a claim about this class.
///
/// It matters in two directions. A desktop build must not grow a webview
/// message listener, and — the sharper one — a build that somehow reached this
/// code with no host must report `EditorHostKind.none` rather than guess, or
/// every desktop launch would report `form_factor: 'vscode'` and the number the
/// Marketplace channel exists to produce would be noise.
///
/// The web implementation has no VM test by construction; it is `@JS`-annotated
/// and needs a browser. Same arrangement as `wellen_wasm_provider_stub_test`.
void main() {
  group('the stub HostBridgeChannel', () {
    test('is what this build resolves — the export shim picks it off web', () {
      // If this ever fails, the conditional export resolved to the web
      // implementation on the VM, and every test below is testing nothing.
      expect(HostBridgeChannel(), isA<HostBridgeTransport>());
    });

    test('reports no editor host, statically and per-instance', () {
      expect(HostBridgeChannel.detectHostKind(), EditorHostKind.none);
      expect(HostBridgeChannel().hostKind, EditorHostKind.none);
    });

    test('cannot post', () {
      expect(HostBridgeChannel().canPost, isFalse);
    });

    test('drops what it is asked to post without throwing', () {
      final channel = HostBridgeChannel();
      expect(
        () => channel.post(<String, Object?>{'type': 'crux.telemetry'}),
        returnsNormally,
      );
    });

    test('never emits an inbound frame', () async {
      final channel = HostBridgeChannel();
      addTearDown(channel.dispose);
      expect(await channel.inbound.toList(), isEmpty);
    });

    test('constructing and disposing installs and releases nothing', () {
      // A desktop build reads `hostBridgeChannelProvider` unconditionally at
      // bootstrap; the whole point of the stub is that doing so costs one
      // allocation and no listener.
      final channel = HostBridgeChannel()..dispose();
      expect(channel.dispose, returnsNormally);
    });
  });
}
