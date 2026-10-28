// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crux_single_instance/crux_single_instance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/app.dart';
import 'package:wavecrux/core/platform/linux_desktop_identity.dart';
import 'package:wavecrux/services/links/wavecrux_link.dart';
import 'package:wavecrux/services/platform/incoming_link_service.dart';
import 'package:wavecrux/services/platform/single_instance_handoff.dart';

const _link = 'wavecrux://open?file=a.vcd';

/// A claim in a private directory of its own, on the transport this host has.
/// The id is short because a Unix socket path must fit `sun_path`.
SingleInstance _instance(String directory) => SingleInstance(
  appId: 'wc.test',
  policy: waveCruxSingleInstancePolicy(),
  directory: directory,
  transport: Platform.isWindows
      ? SingleInstanceTransport.loopbackTcp
      : SingleInstanceTransport.unixSocket,
);

void main() {
  late Directory tmp;
  late String dir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wcsi');
    dir = '${tmp.path}${Platform.pathSeparator}d';
  });

  tearDown(() {
    IncomingLinkService.detachForwardedLinks();
    debugDefaultTargetPlatformOverride = null;
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // A socket still closing; the directory is in the system temp.
    }
  });

  test('the policy is the scheme and the length the parser enforces', () {
    final policy = waveCruxSingleInstancePolicy();
    expect(policy.schemes, {kWaveCruxLinkScheme});
    expect(policy.maxLinkBytes, kWaveCruxLinkMaxLength);
    expect(policy.accepts(_link), isTrue);
    expect(policy.accepts('https://example.com/'), isFalse);
  });

  test(
    'a delivered claim ends the launch: bootstrap reports it headless',
    () async {
      final running = await _instance(dir).claim() as SingleInstancePrimary;
      addTearDown(running.close);
      final received = <String>[];
      final sub = running.links.listen(received.add);
      addTearDown(sub.cancel);

      final ended = await bootstrap(
        args: const [_link],
        singleInstance: _instance(dir),
      );

      expect(
        ended,
        isTrue,
        reason: 'runWaveCrux exits on true, before a window',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, [_link]);
    },
  );

  test('runWaveCrux exits the process when the link was delivered', () async {
    final running = await _instance(dir).claim() as SingleInstancePrimary;
    addTearDown(running.close);
    final sub = running.links.listen((_) {});
    addTearDown(sub.cancel);

    int? exitedWith;
    await runWaveCrux(
      args: const [_link],
      singleInstance: _instance(dir),
      exitProcess: (code) async => exitedWith = code,
    );

    expect(exitedWith, 0);
  });

  test('a launch with no link is not delivered anywhere', () async {
    final running = await _instance(dir).claim() as SingleInstancePrimary;
    addTearDown(running.close);

    final claim = await claimSingleInstance(
      desktopApp: kWaveCruxLinuxDesktopApp,
      launchLinks: const [],
      singleInstance: _instance(dir),
    );

    expect(claim, isA<SingleInstanceStandalone>());
  });

  test('two links on one command line are not forwarded', () async {
    final running = await _instance(dir).claim() as SingleInstancePrimary;
    addTearDown(running.close);

    final claim = await claimSingleInstance(
      desktopApp: kWaveCruxLinuxDesktopApp,
      launchLinks: const [_link, _link],
      singleInstance: _instance(dir),
    );

    expect(claim, isA<SingleInstanceStandalone>());
  });

  test('macOS, the web and mobile make no claim', () async {
    // On a Windows or Linux host the real claim would take this machine's
    // lock, so only a host that opens links itself runs the check.
    if (handsLinksToRunningInstance) return;
    expect(
      await claimSingleInstance(
        desktopApp: kWaveCruxLinuxDesktopApp,
        launchLinks: const [_link],
      ),
      isNull,
    );
  });

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    test(
      'a link forwarded to the primary reaches incomingLinks on $platform',
      () async {
        final claim = await _instance(dir).claim();
        expect(claim, isA<SingleInstancePrimary>());
        final primary = claim as SingleInstancePrimary;
        addTearDown(primary.close);

        debugDefaultTargetPlatformOverride = platform;
        IncomingLinkService.attachForwardedLinks(primary.links);
        final arrived = IncomingLinkService.incomingLinks.first;

        final second = await claimSingleInstance(
          desktopApp: kWaveCruxLinuxDesktopApp,
          launchLinks: const [_link],
          singleInstance: _instance(dir),
        );

        expect(second, isA<SingleInstanceDelivered>());
        expect(await arrived.timeout(const Duration(seconds: 5)), _link);
      },
    );
  }

  test('a link forwarded before anyone listens is held, not lost', () async {
    final primary = await _instance(dir).claim() as SingleInstancePrimary;
    addTearDown(primary.close);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    IncomingLinkService.attachForwardedLinks(primary.links);

    final delivered = await claimSingleInstance(
      desktopApp: kWaveCruxLinuxDesktopApp,
      launchLinks: const [_link],
      singleInstance: _instance(dir),
    );

    expect(delivered, isA<SingleInstanceDelivered>());
    expect(
      await IncomingLinkService.incomingLinks.first.timeout(
        const Duration(seconds: 5),
      ),
      _link,
    );
  });

  test('incomingLinks can be listened to again after the first listener '
      'goes, as a second mount of the app does', () async {
    final primary = await _instance(dir).claim() as SingleInstancePrimary;
    addTearDown(primary.close);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    IncomingLinkService.attachForwardedLinks(primary.links);

    // The first app's state listens and is disposed.
    final first = IncomingLinkService.incomingLinks.listen((_) {});
    await first.cancel();

    // The next app's state listens to the same stream: this threw "Stream
    // has already been listened to" while the claim's single-subscription
    // stream was handed out as it was.
    final arrived = IncomingLinkService.incomingLinks.first;
    final delivered = await claimSingleInstance(
      desktopApp: kWaveCruxLinuxDesktopApp,
      launchLinks: const [_link],
      singleInstance: _instance(dir),
    );

    expect(delivered, isA<SingleInstanceDelivered>());
    expect(await arrived.timeout(const Duration(seconds: 5)), _link);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('incomingLinks stays empty on $platform', () async {
      debugDefaultTargetPlatformOverride = platform;
      IncomingLinkService.attachForwardedLinks(Stream.value(_link));
      expect(await IncomingLinkService.incomingLinks.toList(), isEmpty);
    });
  }

  test('macOS reads the native channel, never the forwarded stream', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('com.wavecrux/incoming_link');
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    IncomingLinkService.attachForwardedLinks(Stream.value(_link));

    final seen = <String>[];
    final sub = IncomingLinkService.incomingLinks.listen(seen.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    expect(calls, contains('listen'));
    expect(seen, isEmpty);
  });
}
