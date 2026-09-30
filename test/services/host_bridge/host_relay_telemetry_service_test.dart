// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/services/host_bridge/host_bridge_messages.dart';
import 'package:wavecrux/services/host_bridge/host_relay_telemetry_service.dart';

import '../../support/fake_host_bridge_transport.dart';

/// The relay's own contract. The *absence of traffic* is asserted one level up,
/// in `test/features/telemetry/wavecrux_telemetry_overrides_test.dart`, against
/// the wiring that actually ships.
void main() {
  group('HostRelayTelemetryService', () {
    test('is a TelemetryService, so no call site changes', () {
      // Instrumentation records unconditionally against the seam; a hosted
      // build must not need a single `if (hosted)` at a call site.
      expect(
        HostRelayTelemetryService(FakeHostBridgeTransport()),
        isA<TelemetryService>(),
      );
    });

    test('hands the event to the host as a descriptor frame', () {
      final transport = FakeHostBridgeTransport();
      HostRelayTelemetryService(transport).record(
        TelemetryEvent(
          'file.opened',
          properties: const <String, Object?>{'format': 'fst'},
        ),
      );

      final frame = transport.posted.single;
      expect(frame['type'], kHostBridgeTelemetryFrameType);
      expect(frame['event'], <String, Object?>{
        'name': 'file.opened',
        'properties': <String, Object?>{'format': 'fst'},
      });
    });

    test('never constructs an envelope', () {
      // `installation_id`, `os`, `form_factor` and the license tier are
      // host-core's to assemble. A webview that never builds one cannot get
      // them wrong or spoof them, which is why the frame carries the descriptor
      // and nothing else.
      final transport = FakeHostBridgeTransport();
      HostRelayTelemetryService(transport).record(TelemetryEvent('app.launch'));

      final frame = transport.posted.single;
      expect(
        frame.keys,
        unorderedEquals(<String>['type', 'protocol', 'event']),
      );
      final event = frame['event']! as Map<String, Object?>;
      for (final envelopeField in <String>[
        'installation_id',
        'os',
        'form_factor',
        'license_tier',
        'app_version',
        'product',
      ]) {
        expect(event.containsKey(envelopeField), isFalse);
      }
    });

    test('drops the event when the host cannot be reached', () {
      // The safe failure. Falling back to this build's own sender is exactly
      // the behaviour the host's `isTelemetryEnabled` gate exists to prevent,
      // and it would only ever appear in the configuration nobody tests.
      final transport = FakeHostBridgeTransport(canPost: false);
      HostRelayTelemetryService(transport).record(TelemetryEvent('app.launch'));
      expect(transport.posted, isEmpty);
    });

    test('never throws, whatever the transport is', () {
      // Telemetry may not break a feature flow, and `record` is called from
      // ordinary UI paths.
      final relay = HostRelayTelemetryService(
        FakeHostBridgeTransport(hostKind: EditorHostKind.none),
      );
      expect(() => relay.record(TelemetryEvent('app.launch')), returnsNormally);
    });
  });
}
