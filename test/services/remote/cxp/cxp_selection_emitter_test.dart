// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/remote/cxp/cxp_selection_emitter.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_server.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';

import '../../../support/fake_waveform_source.dart';
import 'cxp_round_trip_barrier.dart';

// The reference fake source keys signals by an OPAQUE `signalRef` distinct from
// the hierarchical name — `top.clk` has ref `s_clk`, `top.data` has ref
// `s_data`. `selectedSignalProvider` stores that backend-local ref, so the
// emitter MUST translate it to the fullPath before broadcasting (P42/B→A fix):
// a peer can only leaf-match a path, never a per-process ref.
Override _sourceOverride() => waveformSourceProvider.overrideWith(
  () => _PreloadedSourceNotifier(FakeWaveformSource.reference()),
);

void main() {
  late Directory tempDir;
  late WaveCruxCxpServer server;
  late LocalCxpClient subscriber;
  late Stream<CxpClientInbound> inboundStream;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wavecrux_cxp_emit_');
    server = WaveCruxCxpServer(
      productVersion: '0.1.0',
      manifestDirectory: tempDir.path,
      onHighlight: (_, _, _) async => CxpHandlerResult.honoredOk,
      onOpenSource: (_, _, _) async => CxpHandlerResult.honoredOk,
      port: 0,
      processId: 88888,
      startedAtMillis: 100,
    );
    expect(await server.start(), isNull);
    subscriber = LocalCxpClient(
      selfIdentity: const PeerIdentity(
        peerId: 'subscriber',
        productName: 'test',
        productVersion: '0.0.1',
      ),
    );
    await subscriber.connect(
      host: '127.0.0.1',
      port: server.boundPort!,
      token: cxpProcessAuthToken,
    );
    inboundStream = subscriber.inbound.asBroadcastStream();
    subscriber.send(
      const Subscribe(
        subscriptions: [
          CxpSubscription(messageKind: CxpMessageKind.notifySelection),
        ],
      ),
    );
    await cxpRoundTripBarrier(subscriber);
  });

  tearDown(() async {
    await subscriber.dispose();
    await server.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('CxpSelectionEmitter', () {
    test('emits NotifySelection carrying the fullPath, not the signalRef, '
        'when the selection changes', () async {
      final container = ProviderContainer(overrides: [_sourceOverride()]);
      addTearDown(container.dispose);
      final emitter = CxpSelectionEmitter(
        ref: _refFor(container),
        sink: server.broadcast,
      )..start();
      addTearDown(emitter.dispose);

      // Select by the backend-local ref `s_data`; the emitter must broadcast
      // the canonical path `top.data` so a peer can resolve it.
      container.read(selectedSignalProvider.notifier).select('s_data');

      final event = await inboundStream
          .firstWhere((e) => e.message is NotifySelection)
          .timeout(const Duration(seconds: 2));
      final ns = event.message as NotifySelection;
      expect(ns.elements.single.kind, ElementKind.signal);
      expect(ns.elements.single.path, 'top.data');
      expect(ns.displayName, 'top.data');
    });

    test('does NOT broadcast when the selected ref has no matching variable '
        '(would be an unresolvable ref on the wire)', () async {
      final container = ProviderContainer(overrides: [_sourceOverride()]);
      addTearDown(container.dispose);
      final emitter = CxpSelectionEmitter(
        ref: _refFor(container),
        sink: server.broadcast,
      )..start();
      addTearDown(emitter.dispose);

      var received = false;
      final sub = inboundStream
          .where((e) => e.message is NotifySelection)
          .listen((_) => received = true);
      addTearDown(sub.cancel);

      // A ref absent from the source resolves to no path — the emitter must
      // stay silent rather than put a meaningless ref on the wire.
      container.read(selectedSignalProvider.notifier).select('no_such_ref');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(received, isFalse);
    });

    test('does not emit when the selection clears to null', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedSignalProvider.notifier).select('top.clk');
      final emitter = CxpSelectionEmitter(
        ref: _refFor(container),
        sink: server.broadcast,
      )..start();
      addTearDown(emitter.dispose);

      var received = false;
      final sub = inboundStream
          .where((e) => e.message is NotifySelection)
          .listen((_) => received = true);
      addTearDown(sub.cancel);

      // The selection-clear path should produce no broadcast. True-absence
      // assertion: there is no "correctly stayed silent" event to poll
      // for, so this waits out a fixed window and then checks nothing
      // arrived.
      container.read(selectedSignalProvider.notifier).select(null);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(received, isFalse);
    });

    test(
      'cursor moves emit a debounced NotifySelection with cursor_time_fs',
      () async {
        final container = ProviderContainer(overrides: [_sourceOverride()]);
        addTearDown(container.dispose);
        // Pre-set the selection BEFORE constructing the emitter so its
        // initial-snapshot read captures the selection; start() does not
        // broadcast on construction. Select by the backend-local ref `s_clk`.
        container.read(selectedSignalProvider.notifier).select('s_clk');
        final emitter = CxpSelectionEmitter(
          ref: _refFor(container),
          sink: server.broadcast,
          cursorDebounce: const Duration(milliseconds: 50),
        )..start();
        addTearDown(emitter.dispose);

        // Fire several cursor moves in quick succession — only the last
        // should produce a broadcast after the debounce.
        container.read(cursorStateProvider.notifier).placePrimary(1);
        container.read(cursorStateProvider.notifier).placePrimary(2);
        container.read(cursorStateProvider.notifier).placePrimary(12345);

        final event = await inboundStream
            .firstWhere((e) => e.message is NotifySelection)
            .timeout(const Duration(seconds: 2));
        final ns = event.message as NotifySelection;
        expect(ns.metadata['wavecrux.cursor_time_fs'], 12345);
        // The cursor broadcast carries the selected signal's fullPath.
        expect(ns.elements.single.path, 'top.clk');
      },
    );

    test('marker create emits NotifySelection of kind marker', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final emitter = CxpSelectionEmitter(
        ref: _refFor(container),
        sink: server.broadcast,
      )..start();
      addTearDown(emitter.dispose);

      container.read(markerStateProvider.notifier).setMarker('a', 555);
      final event = await inboundStream
          .firstWhere((e) => e.message is NotifySelection)
          .timeout(const Duration(seconds: 2));
      final ns = event.message as NotifySelection;
      expect(ns.elements.single.kind, ElementKind.marker);
      expect(ns.elements.single.path, 'a');
      expect(ns.metadata['wavecrux.cursor_time_fs'], 555);
    });

    test('marker removal does not broadcast', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(markerStateProvider.notifier).setMarker('b', 100);
      final emitter = CxpSelectionEmitter(
        ref: _refFor(container),
        sink: server.broadcast,
      )..start();
      addTearDown(emitter.dispose);

      // After start the snapshot is already {b: 100}; removing it should
      // produce no broadcast (marker-removal is a no-op for now).
      // True-absence assertion: see the selection-clear-to-null test above
      // for why this stays a fixed window rather than a condition poll.
      container.read(markerStateProvider.notifier).removeMarker('b');
      var received = false;
      final sub = inboundStream
          .where((e) => e.message is NotifySelection)
          .listen((_) => received = true);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(received, isFalse);
    });

    test(
      'does not auto-broadcast when broadcastSelectionOnCrossProbe is false',
      () async {
        final container = ProviderContainer(
          overrides: [
            appSettingsProvider.overrideWith(
              () => _FakeAppSettings(
                const AppSettings(broadcastSelectionOnCrossProbe: false),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        // Resolve the async settings build so `.value` is populated before the
        // emitter reads the gate.
        await container.read(appSettingsProvider.future);
        final emitter = CxpSelectionEmitter(
          ref: _refFor(container),
          sink: server.broadcast,
        )..start();
        addTearDown(emitter.dispose);

        var received = false;
        final sub = inboundStream
            .where((e) => e.message is NotifySelection)
            .listen((_) => received = true);
        addTearDown(sub.cancel);

        // A selection change would broadcast with the gate on; with it off the
        // emitter must stay silent. True-absence assertion: wait out a fixed
        // window and confirm nothing arrived.
        container.read(selectedSignalProvider.notifier).select('top.clk');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(received, isFalse);
      },
    );

    test(
      'auto-broadcasts when broadcastSelectionOnCrossProbe is true',
      () async {
        final container = ProviderContainer(
          overrides: [
            _sourceOverride(),
            appSettingsProvider.overrideWith(
              () => _FakeAppSettings(
                const AppSettings(),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(appSettingsProvider.future);
        final emitter = CxpSelectionEmitter(
          ref: _refFor(container),
          sink: server.broadcast,
        )..start();
        addTearDown(emitter.dispose);

        container.read(selectedSignalProvider.notifier).select('s_clk');
        final event = await inboundStream
            .firstWhere((e) => e.message is NotifySelection)
            .timeout(const Duration(seconds: 2));
        expect((event.message as NotifySelection).displayName, 'top.clk');
      },
    );

    test('dispose stops broadcasting on subsequent changes', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      CxpSelectionEmitter(ref: _refFor(container), sink: server.broadcast)
        ..start()
        ..dispose();
      container.read(selectedSignalProvider.notifier).select('top.x');
      // True-absence assertion: a disposed emitter must never broadcast
      // again, so this waits out a fixed window and checks nothing
      // arrived (same reasoning as the selection-clear test above).
      var received = false;
      final sub = inboundStream
          .where((e) => e.message is NotifySelection)
          .listen((_) => received = true);
      addTearDown(sub.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(received, isFalse);
    });
  });
}

// Helper: expose a [Ref] for the [CxpSelectionEmitter] without
// requiring it to participate in the provider graph itself.
Ref _refFor(ProviderContainer container) {
  return container.read(_refProvider);
}

final _refProvider = Provider<Ref>((ref) => ref);

/// Overrides [appSettingsProvider] with a fixed [AppSettings] so the emitter's
/// auto-broadcast gate can be exercised without a SharedPreferences backend.
class _FakeAppSettings extends AppSettingsNotifier {
  _FakeAppSettings(this._settings);
  final AppSettings _settings;
  @override
  Future<AppSettings> build() async => _settings;
}

/// Preloads [waveformSourceProvider] with an in-memory source so the emitter
/// can translate a selected `signalRef` to its `fullPath`.
class _PreloadedSourceNotifier extends WaveformSourceNotifier {
  _PreloadedSourceNotifier(this._source);
  final WaveformDataSource _source;
  @override
  AsyncValue<WaveformDataSource> build() => AsyncData(_source);
}
