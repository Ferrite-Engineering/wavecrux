// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_server.dart';

import '../../../helpers/platform_absolute_path.dart';
import '../../../helpers/wait_for.dart';
import 'cxp_round_trip_barrier.dart';

/// Discovery rescan interval used throughout this file in place of
/// [WaveCruxCxpServer]'s 2-second production default, so discovery-driven
/// assertions poll against real (fast) ticks instead of waiting out a
/// production-scale interval.
const testDiscoveryScanInterval = Duration(milliseconds: 30);

void main() {
  late Directory tempDir;
  late WaveCruxCxpServer server;
  late List<ElementId> highlightCalls;
  late List<(String, int, int?)> openSourceCalls;
  late CxpHandlerResult highlightResult;
  late CxpHandlerResult openSourceResult;

  Future<LocalCxpClient> connectClient() async {
    final client = LocalCxpClient(
      selfIdentity: const PeerIdentity(
        peerId: 'test-client',
        productName: 'test',
        productVersion: '0.0.1',
      ),
    );
    await client.connect(
      host: '127.0.0.1',
      port: server.boundPort!,
      token: cxpProcessAuthToken,
    );
    return client;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wavecrux_cxp_test_');
    highlightCalls = [];
    openSourceCalls = [];
    highlightResult = CxpHandlerResult.honoredOk;
    openSourceResult = CxpHandlerResult.honoredOk;
    server = WaveCruxCxpServer(
      productVersion: '0.1.0',
      manifestDirectory: tempDir.path,
      onHighlight: (element, _, _) async {
        highlightCalls.add(element);
        return highlightResult;
      },
      onOpenSource: (path, line, column) async {
        openSourceCalls.add((path, line, column));
        return openSourceResult;
      },
      port: 0, // OS-assigned
      processId: pid,
      startedAtMillis: 1234567890,
      discoveryScanInterval: testDiscoveryScanInterval,
    );
    expect(await server.start(), isNull);
  });

  tearDown(() async {
    await server.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('lifecycle', () {
    test('start binds a port and writes a manifest', () {
      expect(server.isRunning, isTrue);
      expect(server.boundPort, isNotNull);
      final manifestPath = '${tempDir.path}/${server.selfIdentity.peerId}.json';
      expect(File(manifestPath).existsSync(), isTrue);
    });

    test('stop removes the manifest file', () async {
      final manifestPath = '${tempDir.path}/${server.selfIdentity.peerId}.json';
      expect(File(manifestPath).existsSync(), isTrue);
      await server.stop();
      expect(server.isRunning, isFalse);
      expect(File(manifestPath).existsSync(), isFalse);
    });

    test('peer identity uses wavecrux-<pid>-<startedAt> form', () {
      expect(server.selfIdentity.peerId, 'wavecrux-$pid-1234567890');
      expect(server.selfIdentity.productName, 'wavecrux');
      expect(server.selfIdentity.productVersion, '0.1.0');
    });
  });

  group('handshake', () {
    test(
      'an inbound peer can connect and complete the Hello handshake',
      () async {
        final client = await connectClient();
        addTearDown(client.dispose);
        expect(client.isConnected, isTrue);
        expect(client.remotePeer?.peerId, server.selfIdentity.peerId);
        expect(client.remotePeer?.productName, 'wavecrux');
      },
    );

    test('connectedPeers reflects the live socket peers', () async {
      final client = await connectClient();
      addTearDown(client.dispose);
      await waitFor(
        () => server.connectedPeers
            .map((p) => p.peerId)
            .contains(
              'test-client',
            ),
        reason: 'presence event should flush onto the server peer list',
      );
    });
  });

  group('inbound request_highlight', () {
    test('dispatches to onHighlight and replies with the ack', () async {
      final client = await connectClient();
      addTearDown(client.dispose);
      final inboundStream = client.inbound.asBroadcastStream();
      client.send(
        const RequestHighlight(
          element: ElementId(
            kind: ElementKind.signal,
            path: 'top.cpu.alu.sum',
          ),
        ),
      );
      final ackEvent = await inboundStream.firstWhere(
        (e) => e.message is RequestHighlightAck,
      );
      expect(highlightCalls, hasLength(1));
      expect(highlightCalls.first.path, 'top.cpu.alu.sum');
      final ack = ackEvent.message as RequestHighlightAck;
      expect(ack.honored, isTrue);
    });

    test(
      'marks the ack honored=false when the handler returns failure',
      () async {
        highlightResult = const CxpHandlerResult(
          honored: false,
          reason: 'no such signal',
        );
        final client = await connectClient();
        addTearDown(client.dispose);
        final inboundStream = client.inbound.asBroadcastStream();
        client.send(
          const RequestHighlight(
            element: ElementId(kind: ElementKind.signal, path: 'nope'),
          ),
        );
        final ackEvent = await inboundStream.firstWhere(
          (e) => e.message is RequestHighlightAck,
        );
        final ack = ackEvent.message as RequestHighlightAck;
        expect(ack.honored, isFalse);
        expect(ack.reason, 'no such signal');
      },
    );

    test('handler-thrown exception surfaces as honored=false ack', () async {
      server = WaveCruxCxpServer(
        productVersion: '0.1.0',
        manifestDirectory: tempDir.path,
        onHighlight: (_, _, _) async => throw StateError('boom'),
        onOpenSource: (_, _, _) async => CxpHandlerResult.honoredOk,
        port: 0,
      );
      expect(await server.start(), isNull);
      final client = await connectClient();
      addTearDown(client.dispose);
      final inboundStream = client.inbound.asBroadcastStream();
      client.send(
        const RequestHighlight(
          element: ElementId(kind: ElementKind.signal, path: 'whatever'),
        ),
      );
      final ackEvent = await inboundStream.firstWhere(
        (e) => e.message is RequestHighlightAck,
      );
      final ack = ackEvent.message as RequestHighlightAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('boom'));
    });
  });

  group('inbound request_open_source', () {
    test('dispatches to onOpenSource and replies with the ack', () async {
      final client = await connectClient();
      addTearDown(client.dispose);
      final inboundStream = client.inbound.asBroadcastStream();
      final cpuV = platformAbsolute('/rtl/cpu.v');
      client.send(
        RequestOpenSource(
          filePath: cpuV,
          line: 142,
          column: 7,
        ),
      );
      final ackEvent = await inboundStream.firstWhere(
        (e) => e.message is RequestOpenSourceAck,
      );
      expect(openSourceCalls, [
        (cpuV, 142, 7),
      ]);
      final ack = ackEvent.message as RequestOpenSourceAck;
      expect(ack.honored, isTrue);
    });

    test('marks honored=false when no editor is configured', () async {
      openSourceResult = const CxpHandlerResult(
        honored: false,
        reason: 'no editor configured',
      );
      final client = await connectClient();
      addTearDown(client.dispose);
      final inboundStream = client.inbound.asBroadcastStream();
      client.send(
        RequestOpenSource(filePath: platformAbsolute('/rtl/cpu.v'), line: 1),
      );
      final ackEvent = await inboundStream.firstWhere(
        (e) => e.message is RequestOpenSourceAck,
      );
      final ack = ackEvent.message as RequestOpenSourceAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, 'no editor configured');
    });

    // The wrapper hands `containment` to `LocalCxpServer`, which screens the
    // path BEFORE dispatch: the ack comes back without the product's handler
    // ever being called. The default rule here is the floor (absolute,
    // well-formed) because this test constructs the server without roots —
    // the provider layer is what supplies the open directories.
    //
    // MUTATION: dropping `containment: containment` from the `LocalCxpServer`
    // construction in `WaveCruxCxpServer.start` makes this red.
    test('refuses a relative file_path without dispatching it', () async {
      final client = await connectClient();
      addTearDown(client.dispose);
      final inboundStream = client.inbound.asBroadcastStream();
      client.send(
        const RequestOpenSource(filePath: 'rtl/cpu.v', line: 1),
      );
      final ackEvent = await inboundStream.firstWhere(
        (e) => e.message is RequestOpenSourceAck,
      );
      final ack = ackEvent.message as RequestOpenSourceAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('absolute path'));
      expect(openSourceCalls, isEmpty);
    });

    test('refuses a path outside the roots it was given', () async {
      final rootedTemp = await Directory.systemTemp.createTemp(
        'wavecrux_cxp_root_',
      );
      addTearDown(() => rootedTemp.deleteSync(recursive: true));
      final rooted = WaveCruxCxpServer(
        productVersion: '0.1.0',
        manifestDirectory: rootedTemp.path,
        onHighlight: (element, _, _) async => CxpHandlerResult.honoredOk,
        onOpenSource: (path, line, column) async {
          openSourceCalls.add((path, line, column));
          return CxpHandlerResult.honoredOk;
        },
        port: 0,
        processId: pid,
        startedAtMillis: 1234567891,
        discoveryScanInterval: testDiscoveryScanInterval,
        containment: CxpPathContainment(
          roots: () => <String>[rootedTemp.path],
        ),
      );
      expect(await rooted.start(), isNull);
      addTearDown(rooted.dispose);

      final client = LocalCxpClient(
        selfIdentity: const PeerIdentity(
          peerId: 'rooted-client',
          productName: 'test',
          productVersion: '0.0.1',
        ),
      );
      await client.connect(
        host: '127.0.0.1',
        port: rooted.boundPort!,
        token: cxpProcessAuthToken,
      );
      addTearDown(client.dispose);
      final inboundStream = client.inbound.asBroadcastStream();
      final shadow = platformAbsolute('/etc/shadow');
      client.send(RequestOpenSource(filePath: shadow, line: 1));
      final ackEvent = await inboundStream.firstWhere(
        (e) => e.message is RequestOpenSourceAck,
      );
      final ack = ackEvent.message as RequestOpenSourceAck;
      expect(ack.honored, isFalse);
      expect(ack.reason, contains('outside the directories'));
      expect(ack.reason, isNot(contains(shadow)));
      expect(openSourceCalls, isEmpty);
    });
  });

  group('outbound', () {
    test('broadcast delivers a notify_selection to subscribed peers', () async {
      final client = await connectClient();
      addTearDown(client.dispose);
      // Subscribe to notify_selection, then wait for the server to have
      // processed it (its per-connection read loop is FIFO, so a
      // round-trip on a later probe proves the Subscribe landed first).
      client.send(
        const Subscribe(
          subscriptions: [
            CxpSubscription(messageKind: CxpMessageKind.notifySelection),
          ],
        ),
      );
      await cxpRoundTripBarrier(client);
      final inboundStream = client.inbound.asBroadcastStream();
      server.broadcast(
        const NotifySelection(
          elements: [
            ElementId(kind: ElementKind.signal, path: 'top.cpu.clk'),
          ],
          displayName: 'top.cpu.clk',
          metadata: {'wavecrux.cursor_time_fs': 1000000},
        ),
        summary: 'top.cpu.clk',
      );
      final selectionEvent = await inboundStream.firstWhere(
        (e) => e.message is NotifySelection,
      );
      final selection = selectionEvent.message as NotifySelection;
      expect(selection.elements.single.path, 'top.cpu.clk');
      expect(selection.metadata['wavecrux.cursor_time_fs'], 1000000);
    });

    test(
      'server events stream surfaces an outbound entry on broadcast',
      () async {
        // We need at least one subscribed peer for the broadcast to actually
        // hit the wire — otherwise the server intentionally skips delivery.
        final client = await connectClient();
        addTearDown(client.dispose);
        client.send(
          const Subscribe(
            subscriptions: [
              CxpSubscription(messageKind: CxpMessageKind.notifySelection),
            ],
          ),
        );
        await cxpRoundTripBarrier(client);

        final outboundEvents = <WaveCruxCxpServerEvent>[];
        final sub = server.serverEvents.listen((event) {
          if (event.isOutbound) outboundEvents.add(event);
        });
        addTearDown(sub.cancel);

        server.broadcast(
          const NotifySelection(
            elements: [
              ElementId(kind: ElementKind.signal, path: 'top.cpu.clk'),
            ],
          ),
          summary: 'top.cpu.clk',
        );
        await waitFor(() => outboundEvents.isNotEmpty);
        expect(outboundEvents, hasLength(1));
        expect(outboundEvents.single.kind, CxpMessageKind.notifySelection);
        expect(outboundEvents.single.summary, 'top.cpu.clk');
      },
    );

    test('sendTo returns false for an unknown peerId', () {
      expect(
        server.sendTo(
          'no-such-peer',
          const NotifySelection(
            elements: [
              ElementId(kind: ElementKind.signal, path: 'a'),
            ],
          ),
        ),
        isFalse,
      );
    });
  });

  group('discovery', () {
    test(
      'discovery emits an added event when a peer manifest appears',
      () async {
        // Set up a fake peer's manifest in the same directory.
        final writer = CxpManifestWriter(manifestDirectory: tempDir.path);
        final events = <CxpDiscoveryEvent>[];
        final sub = server.discoveryEvents.listen(events.add);
        addTearDown(sub.cancel);

        await writer.write(
          identity: const PeerIdentity(
            peerId: 'othercrux-1-2',
            productName: 'othercrux',
            productVersion: '0.1.0',
          ),
          host: '127.0.0.1',
          port: 54323,
        );
        // setUp overrides the scan interval to testDiscoveryScanInterval, so
        // this polls real (fast) ticks rather than waiting out a fixed
        // production-scale interval.
        await waitFor(
          () => events.any(
            (e) => e.added && e.manifest.identity.peerId == 'othercrux-1-2',
          ),
          reason: 'discovery should surface the newly written peer manifest',
        );
      },
    );

    test('discovery ignores the self manifest', () async {
      // The server's own manifest was written by start(); discovery should
      // never emit an event for it. This is a true absence assertion —
      // there is no "correctly stayed silent" signal to poll for — so it
      // waits out a handful of the (fast, test-overridden) scan intervals
      // and then checks nothing leaked through.
      final events = <CxpDiscoveryEvent>[];
      final sub = server.discoveryEvents.listen(events.add);
      addTearDown(sub.cancel);
      await Future<void>.delayed(testDiscoveryScanInterval * 5);
      final selfEvents = events.where(
        (e) => e.manifest.identity.peerId == server.selfIdentity.peerId,
      );
      expect(selfEvents, isEmpty);
    });

    test('discoveredPeers excludes the self manifest', () async {
      // The manifest directory is suite-shared, so the raw scan always
      // contains the server's own manifest — the snapshot getter filters
      // it at read time (see WaveCruxCxpServer.discoveredPeers), which is
      // already true the instant start() resolves in setUp: no wait
      // needed, unlike the discoveryEvents stream check above.
      expect(
        server.discoveredPeers.map((m) => m.identity.peerId),
        isNot(contains(server.selfIdentity.peerId)),
      );
    });
  });

  group('peer connector (symmetric connect regression)', () {
    test(
      'two servers sharing one manifest directory END UP CONNECTED — '
      'both sides see the other in connectedPeers',
      () async {
        // Second in-process server: same manifest dir (the suite-shared
        // directory in production), distinct identity. Pre-fix, discovery
        // surfaced the manifests but nothing ever dialed, so BOTH
        // connectedPeers lists stayed empty forever and every cross-probe
        // surface reported "No CXP peers connected".
        final other = WaveCruxCxpServer(
          productVersion: '0.9.9',
          manifestDirectory: tempDir.path,
          onHighlight: (_, _, _) async => CxpHandlerResult.honoredOk,
          onOpenSource: (_, _, _) async => CxpHandlerResult.honoredOk,
          port: 0,
          processId: pid,
          startedAtMillis: 42,
          discoveryScanInterval: testDiscoveryScanInterval,
        );
        expect(await other.start(), isNull);
        addTearDown(other.dispose);

        // The connector dials on discovery's add event.
        // Bounded poll: pass the moment both directions are up.
        bool mutual() =>
            server.connectedPeers.any(
              (p) => p.peerId == other.selfIdentity.peerId,
            ) &&
            other.connectedPeers.any(
              (p) => p.peerId == server.selfIdentity.peerId,
            );
        await waitFor(
          mutual,
          timeout: const Duration(seconds: 15),
          interval: const Duration(milliseconds: 100),
          reason:
              'both servers must see the other CONNECTED (symmetric '
              'connector dials); pre-fix this never happened',
        );

        // And both discovered the other at the manifest level (self
        // excluded).
        expect(
          server.discoveredPeers.map((m) => m.identity.peerId),
          contains(other.selfIdentity.peerId),
        );
        expect(
          other.discoveredPeers.map((m) => m.identity.peerId),
          contains(server.selfIdentity.peerId),
        );
      },
    );

    test(
      'inbound request_highlight over a connector-dialed link reaches the '
      "PEER's WaveCrux handler and its ack routes back — the crux_cxp "
      'e2e conformance case (presence alone is not enough: see '
      'peer_connectivity_test.dart "end-to-end product traffic" in '
      'crux_cxp)',
      () async {
        // Second in-process server sharing the same manifest directory,
        // exactly like the regression test above, but this one probes
        // actual product-level traffic instead of stopping at presence.
        // With two symmetric dialers, `server.sendTo(other, ...)` always
        // travels over the socket OTHER's connector dialed — so this only
        // passes if OTHER's `CxpPeerConnector` is wired with `server:`
        // and routes that inbound frame into its own WaveCruxCxpServer
        // dispatch path (and the ack back the same way).
        final otherHighlightCalls = <ElementId>[];
        final other = WaveCruxCxpServer(
          productVersion: '0.9.9',
          manifestDirectory: tempDir.path,
          onHighlight: (element, _, _) async {
            otherHighlightCalls.add(element);
            return CxpHandlerResult.honoredOk;
          },
          onOpenSource: (_, _, _) async => CxpHandlerResult.honoredOk,
          port: 0,
          processId: pid,
          startedAtMillis: 77,
          discoveryScanInterval: testDiscoveryScanInterval,
        );
        expect(await other.start(), isNull);
        addTearDown(other.dispose);

        await waitFor(
          () =>
              server.connectedPeers.any(
                (p) => p.peerId == other.selfIdentity.peerId,
              ) &&
              other.connectedPeers.any(
                (p) => p.peerId == server.selfIdentity.peerId,
              ),
          timeout: const Duration(seconds: 15),
          reason: 'both servers must be mutually connected before probing',
        );

        final inboundAcks = <WaveCruxCxpServerEvent>[];
        final sub = server.serverEvents.listen((event) {
          if (!event.isOutbound &&
              event.kind == CxpMessageKind.requestHighlightAck) {
            inboundAcks.add(event);
          }
        });
        addTearDown(sub.cancel);

        const element = ElementId(
          kind: ElementKind.signal,
          path: 'top.cpu.pc',
        );
        final delivered = server.sendTo(
          other.selfIdentity.peerId,
          const RequestHighlight(element: element),
        );
        expect(delivered, isTrue);

        await waitFor(
          () => otherHighlightCalls.isNotEmpty,
          reason:
              "the request must reach the peer's onHighlight handler over "
              'the connector-dialed link, not just register as connected',
        );
        expect(otherHighlightCalls.single.path, 'top.cpu.pc');

        await waitFor(
          () => inboundAcks.isNotEmpty,
          reason: "the peer's ack must route back over the same link",
        );
      },
    );
  });

  group('dial failures (unreachable peer)', () {
    test(
      'a manifest pointing at a closed port surfaces on dialFailures and '
      'in unreachablePeers',
      () async {
        // Reserve then release a port so nothing is listening on it: the
        // connector's dial to this manifest is guaranteed to fail, which is
        // the one-way-connectivity case the indicator exists to expose.
        final probe = await ServerSocket.bind('127.0.0.1', 0);
        final deadPort = probe.port;
        await probe.close();

        final failures = <CxpDialFailure>[];
        final sub = server.dialFailures.listen(failures.add);
        addTearDown(sub.cancel);

        final writer = CxpManifestWriter(manifestDirectory: tempDir.path);
        await writer.write(
          identity: const PeerIdentity(
            peerId: 'deadcrux-1-2',
            productName: 'deadcrux',
            productVersion: '0.1.0',
          ),
          host: '127.0.0.1',
          port: deadPort,
        );

        await waitFor(
          () => failures.any((f) => f.peerId == 'deadcrux-1-2'),
          timeout: const Duration(seconds: 15),
          reason:
              'the connector should re-broadcast the failed dial to the '
              'unreachable peer on WaveCruxCxpServer.dialFailures',
        );

        final unreachable = server.unreachablePeers.firstWhere(
          (f) => f.peerId == 'deadcrux-1-2',
        );
        expect(unreachable.host, '127.0.0.1');
        expect(unreachable.port, deadPort);
      },
    );

    test('unreachablePeers is empty once the server is stopped', () async {
      await server.stop();
      expect(server.unreachablePeers, isEmpty);
    });
  });

  group('inbound event log', () {
    test(
      'inbound NotifySelection surfaces on the serverEvents stream',
      () async {
        final inboundEvents = <WaveCruxCxpServerEvent>[];
        final sub = server.serverEvents.listen((event) {
          if (!event.isOutbound && !event.isPresence) {
            inboundEvents.add(event);
          }
        });
        addTearDown(sub.cancel);

        final client = await connectClient();
        addTearDown(client.dispose);
        client.send(
          const NotifySelection(
            elements: [
              ElementId(kind: ElementKind.signal, path: 'top.cpu.alu.sum'),
            ],
            displayName: 'top.cpu.alu.sum',
          ),
        );
        await waitFor(() => inboundEvents.isNotEmpty);
        expect(inboundEvents, hasLength(1));
        expect(inboundEvents.single.kind, CxpMessageKind.notifySelection);
        expect(inboundEvents.single.summary, 'top.cpu.alu.sum');
      },
    );
  });
}
