// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/features/telemetry/wavecrux_telemetry_overrides.dart';
import 'package:wavecrux/services/host_bridge/editor_host_provider.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_messages.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_provider.dart';
import 'package:wavecrux/services/host_bridge/host_relay_telemetry_service.dart';

import '../../support/fake_host_bridge_transport.dart';

/// **A webview that reports independently of its host's gate is the finding
/// that gets an extension pulled from the Marketplace.**
///
/// So the assertion here is about *traffic*, not about a class name. The gate
/// is forced wide open — no beta period, dev flag on, an Enterprise `allow`
/// policy on top — which is the only configuration in which this build would
/// transmit at all; then an event is recorded and the HTTP client is asked
/// whether anything left. Nothing may.
///
/// The class-name check is kept alongside, but as the *weaker* of the two: a
/// future refactor could plausibly keep the name and reintroduce a sender, and
/// the traffic assertion is what would catch it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// The overrides `bootstrap` assembles, for a given host, with the network
  /// replaced by a client that fails the test if it is ever called.
  ///
  /// `telemetryHttpClientProvider` is the *only* way an event can leave this
  /// process: `LiveTelemetryService` is the sole sender and it POSTs through
  /// this client. A MockClient that fails on invocation is therefore an exact
  /// "nothing transmitted" assertion, not a proxy for one.
  ({ProviderContainer container, List<http.Request> requests}) hostedContainer(
    EditorHostKind hostKind, {
    required FakeHostBridgeTransport transport,
  }) {
    final requests = <http.Request>[];
    final container = ProviderContainer(
      overrides: <Override>[
        ...wavecruxTelemetryOverrides,
        ...wavecruxHostRelayTelemetryOverrides(hostKind),
        hostBridgeChannelProvider.overrideWithValue(transport),
        telemetryHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            requests.add(request);
            return http.Response('{}', 202);
          }),
        ),
        // Force the gate OPEN. Every one of these is the shipped default's
        // opposite: no beta, dev flag on, and an org-wide `allow` that beats
        // any stored consent. If a hosted build can transmit at all, it
        // transmits here.
        telemetryBetaPeriodProvider.overrideWithValue(false),
        telemetryDevModeProvider.overrideWithValue(true),
        telemetryPolicyProvider.overrideWithValue(TelemetryPolicy.allow),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, requests: requests);
  }

  group('THE HOST-GATE TEST — a hosted build is not a sender', () {
    test('the gate really is open in this fixture', () async {
      // Guards the guard. Without this, an accidentally-closed gate would make
      // every "nothing transmitted" assertion below pass for the wrong reason.
      final fixture = hostedContainer(
        EditorHostKind.none,
        transport: FakeHostBridgeTransport(),
      );
      expect(fixture.container.read(telemetryEnabledProvider), isTrue);
      expect(
        fixture.container.read(telemetryServiceProvider),
        isA<LiveTelemetryService>(),
      );
    });

    test('under a VSCode host the live sender is never constructed', () {
      final fixture = hostedContainer(
        EditorHostKind.vscode,
        transport: FakeHostBridgeTransport(),
      );
      final service = fixture.container.read(telemetryServiceProvider);
      expect(service, isA<HostRelayTelemetryService>());
      expect(service, isNot(isA<LiveTelemetryService>()));
    });

    test('under a VSCode host, recording transmits nothing', () async {
      final transport = FakeHostBridgeTransport();
      final fixture = hostedContainer(
        EditorHostKind.vscode,
        transport: transport,
      );

      fixture.container
          .read(telemetryServiceProvider)
          .record(TelemetryEvent('file.opened'));
      // Generously past any flush the live service would have scheduled — it
      // flushes on construction, and there is no construction to flush.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        fixture.requests,
        isEmpty,
        reason:
            'a webview that reports independently of the host gate '
            '(vscode.env.isTelemetryEnabled) is the finding that pulls an '
            'extension from the Marketplace',
      );
      // …and the event is not lost either: it went to the host, which applies
      // its own gate at send time and is the pack's only sender.
      expect(transport.posted.single['type'], kHostBridgeTelemetryFrameType);
      expect(
        (transport.posted.single['event']! as Map<String, Object?>)['name'],
        'file.opened',
      );
    });

    test(
      'a hosted build whose shim has no outbound seam still transmits nothing',
      () async {
        // The configuration that would tempt a fallback: hosted, gate open, and
        // the host unreachable. Dropping the event is the correct answer;
        // sending it ourselves is the one that ships undeclared collection.
        final transport = FakeHostBridgeTransport(canPost: false);
        final fixture = hostedContainer(
          EditorHostKind.vscode,
          transport: transport,
        );

        fixture.container
            .read(telemetryServiceProvider)
            .record(TelemetryEvent('file.opened'));
        await Future<void>.delayed(const Duration(milliseconds: 200));

        expect(fixture.requests, isEmpty);
        expect(transport.posted, isEmpty);
      },
    );
  });

  group('wavecruxHostRelayTelemetryOverrides', () {
    test('contributes nothing when nothing is hosting this build', () {
      // Desktop, mobile and a plain browser tab keep the pipeline they have —
      // the override list is empty, so there is no behaviour to regress.
      expect(
        wavecruxHostRelayTelemetryOverrides(EditorHostKind.none),
        isEmpty,
      );
      expect(
        wavecruxHostRelayTelemetryOverrides(EditorHostKind.vscode),
        hasLength(1),
      );
    });

    test('leaves the unhosted build sending through the live service', () {
      final fixture = hostedContainer(
        EditorHostKind.none,
        transport: FakeHostBridgeTransport(),
      );
      expect(
        fixture.container.read(telemetryServiceProvider),
        isNot(isA<HostRelayTelemetryService>()),
      );
    });
  });

  group('form_factor stays consistent with the host', () {
    test('an editor-hosted build reports vscode, not web', () {
      // Belt and braces: the host stamps `form_factor: 'vscode'` on the
      // envelope it assembles, and this is the same answer for any envelope
      // this build ever assembles itself. The two agree by construction.
      final fixture = hostedContainer(
        EditorHostKind.vscode,
        transport: FakeHostBridgeTransport(),
      );
      fixture.container
          .read(editorHostKindProvider.notifier)
          .set(EditorHostKind.vscode);
      expect(fixture.container.read(telemetryFormFactorProvider), 'vscode');
    });
  });
}
