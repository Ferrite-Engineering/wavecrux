// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_audit/crux_audit.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_policy/crux_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';

import '../../helpers/product_telemetry_config.dart';

class _CapturingSink implements AuditSink {
  final List<AuditEvent> events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async => events.add(event);

  @override
  Future<void> close() async {}

  @override
  AuditSinkHealth get health => AuditSinkHealth.healthy;
}

(ProviderContainer, _CapturingSink) _container() {
  final sink = _CapturingSink();
  final container = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      cruxAuditSinkProvider.overrideWithValue(sink),
      cruxAuditProductIdProvider.overrideWithValue(
        WaveCruxPolicyKeys.productId,
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container, sink);
}

void main() {
  final spiId = SpiDecoder.decoderDefinition.id;

  void registerSpi() => DecoderRegistry.instance.register(
    SpiDecoder.decoderDefinition,
    SpiDecoder.new,
  );

  group('decoder activation', () {
    test("records the real decoder id, not telemetry's redaction", () async {
      registerSpi();
      final (container, sink) = _container();

      container
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            spiId,
            const DecoderConfig(signalBindings: <String, String>{}),
          );
      await pumpEventQueue();

      final event = sink.events.single;
      expect(event.product, 'wavecrux');
      expect(event.kind, WaveCruxAuditKinds.decoderActivated);
      // The AUDIT event carries the real id, unlike the telemetry event beside
      // it, which maps a user plugin to the literal `plugin`. This file is the
      // organization's record of its own machine, and "which decoder ran
      // against our bus traces" is precisely what `plugin` refuses to answer.
      expect(event.payload['decoder'], spiId);
      expect(event.payload['userSupplied'], isFalse);
    });

    test(
      'an unregistered id is flagged user-supplied, conservatively',
      () async {
        final (container, sink) = _container();

        container
            .read(activeDecodersProvider.notifier)
            .addDecoder(
              'not-a-registered-decoder',
              const DecoderConfig(signalBindings: <String, String>{}),
            );
        await pumpEventQueue();

        // `DecoderRegistry.isUserSupplied` treats an unregistered id as
        // user-supplied by design — a decoder it did not register is one whose
        // provenance it cannot vouch for. The audit flag inherits that default
        // rather than second-guessing it, so the log never claims we shipped
        // something we did not.
        expect(
          sink.events.single.payload['decoder'],
          'not-a-registered-decoder',
        );
        expect(sink.events.single.payload['userSupplied'], isTrue);
      },
    );

    test('every activation is one event', () async {
      final (container, sink) = _container();
      final notifier = container.read(activeDecodersProvider.notifier)
        ..addDecoder(
          spiId,
          const DecoderConfig(signalBindings: <String, String>{}),
        )
        ..addDecoder(
          spiId,
          const DecoderConfig(signalBindings: <String, String>{}),
        )
        ..addDecoder(
          'i2c',
          const DecoderConfig(signalBindings: <String, String>{}),
        );
      await pumpEventQueue();

      expect(sink.events, hasLength(3));
      expect(
        sink.events.map((e) => e.payload['decoder']),
        <String>[spiId, spiId, 'i2c'],
      );
      // Removing is not activating.
      notifier.removeDecoder(notifier.state.first.id);
      await pumpEventQueue();
      expect(sink.events, hasLength(3));
    });

    test('a session restore is not an activation', () async {
      final (container, sink) = _container();
      // `restoreDecoders` reaches the same state without anyone choosing a
      // decoder — the same reason the telemetry counter lives in `addDecoder`
      // and not at the config dialog.
      container.read(activeDecodersProvider.notifier).restoreDecoders(const []);
      await pumpEventQueue();
      expect(sink.events, isEmpty);
    });
  });

  group('the registered vocabulary', () {
    test('every emitted kind is one this product registered', () async {
      final (container, sink) = _container();
      container
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            'uart',
            const DecoderConfig(signalBindings: <String, String>{}),
          );
      await pumpEventQueue();

      for (final event in sink.events) {
        expect(
          WaveCruxAuditKinds.all,
          contains(event.kind),
          reason: '${event.kind} is not in WaveCruxAuditKinds.all',
        );
      }
    });
  });

  group('the default sink', () {
    test('emission is inert until an administrator configures a path', () {
      // The gate is the SINK, never the emission — a product that only emitted
      // when configured would have call sites that go stale unnoticed.
      final container = ProviderContainer(overrides: [productTelemetryConfig]);
      addTearDown(container.dispose);
      expect(container.read(cruxAuditSinkProvider), isA<NoopAuditSink>());
      expect(
        () => container
            .read(activeDecodersProvider.notifier)
            .addDecoder(
              spiId,
              const DecoderConfig(signalBindings: <String, String>{}),
            ),
        returnsNormally,
      );
    });
  });

  group('the policy load is reported — spec §9.2', () {
    // `bootstrap` calls `reportPolicyLoad` with the same two providers this
    // reads. What is asserted here is the WIRING contract: that the shared
    // reporter, given what this product's container holds, produces the event
    // and that the event is one this product's sink accepts.
    //
    // The producer itself is unit-tested in crux_license. What was missing
    // before 2026-08-24 was not the mechanism — it was any call to it, in any
    // product, which is why a bad signature was refused in silence.

    test('an honoured file records policy.loaded to the sink', () async {
      final (container, sink) = _container();

      reportPolicyLoad(
        result: PolicyLoadResult(
          document: PolicyDocument.parse('{"schema":1}'),
          discovery: PolicyDiscovery.wellKnownPath,
          signed: true,
        ),
        recorder: container.read(cruxAuditRecorderProvider),
      );
      await pumpEventQueue();

      final event = sink.events.single;
      expect(event.kind, CruxSharedAuditKinds.policyLoaded);
      // Stamped with THIS product, which is what makes a four-product file
      // filterable.
      expect(event.product, WaveCruxPolicyKeys.productId);
      expect(event.payload['discovery'], 'wellKnownPath');
    });

    test('a refusal reaches the process log and never the sink', () async {
      final (container, sink) = _container();
      final log = <String>[];

      reportPolicyLoad(
        result: const PolicyLoadResult(
          document: PolicyDocument.absent,
          rejection: PolicyRejection.badSignature,
          discovery: PolicyDiscovery.wellKnownPath,
          signed: true,
        ),
        recorder: container.read(cruxAuditRecorderProvider),
        onDiagnostic: log.add,
      );
      await pumpEventQueue();

      expect(sink.events, isEmpty);
      expect(log.single, contains('policy.rejected'));
    });

    test('no policy file records nothing at all', () async {
      final (container, sink) = _container();
      final log = <String>[];

      reportPolicyLoad(
        result: const PolicyLoadResult(document: PolicyDocument.absent),
        recorder: container.read(cruxAuditRecorderProvider),
        onDiagnostic: log.add,
      );
      await pumpEventQueue();

      // Every unmanaged installation takes this path. A line on every launch
      // of every free copy trains an administrator to ignore the one that
      // matters.
      expect(sink.events, isEmpty);
      expect(log, isEmpty);
    });

    test("the shared kinds are not this product's own vocabulary", () {
      // `policy.loaded` is deliberately NOT in WaveCruxAuditKinds.all — it
      // describes the shared machinery rather than anything WaveCrux does, so
      // giving each product its own spelling would make a shared file
      // unfilterable for exactly the events an administrator most wants.
      expect(
        WaveCruxAuditKinds.all,
        isNot(contains(CruxSharedAuditKinds.policyLoaded)),
      );
      expect(
        CruxSharedAuditKinds.all,
        contains(CruxSharedAuditKinds.policyRejected),
      );
    });
  });
}
