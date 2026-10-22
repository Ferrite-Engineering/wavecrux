// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Static guard for the `wavecrux://` URL scheme: the macOS bundle declares it,
// the native half forwards it on the channel the Dart half listens on, and
// the app actually calls the handler. A scheme that is registered and then
// dropped is worse than none: the link looks like it should work, and the
// failure is indistinguishable from the app hanging. The same reasoning is why
// the iOS and Android builds, which have no handler, must not declare it.
//
// The Windows registration lives with the release packaging and is guarded
// there. The Linux one is the AppImage's installed `.desktop` entry, built from
// the identity checked here; a .deb or .rpm declares it in its own packaging.

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/platform/linux_desktop_identity.dart';
import 'package:wavecrux/services/links/wavecrux_link.dart';

/// The `CFBundleURLSchemes` strings declared in [plist].
List<String> declaredSchemes(File plist) {
  final src = plist.readAsStringSync();
  final at = src.indexOf('<key>CFBundleURLTypes</key>');
  if (at == -1) return const [];
  final schemesAt = src.indexOf('<key>CFBundleURLSchemes</key>', at);
  if (schemesAt == -1) return const [];
  final end = src.indexOf('</array>', schemesAt);
  return RegExp(
    '<string>([^<]*)</string>',
  ).allMatches(src.substring(schemesAt, end)).map((m) => m.group(1)!).toList();
}

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('the macOS bundle declares the wavecrux scheme', () {
    expect(declaredSchemes(File('macos/Runner/Info.plist')), ['wavecrux']);
  });

  test('the macOS app delegate forwards links on the channel Dart reads', () {
    final delegate = _read('macos/Runner/AppDelegate.swift');
    final window = _read('macos/Runner/MainFlutterWindow.swift');
    final dart = _read('lib/services/platform/incoming_link_service.dart');
    expect(delegate, contains('IncomingLinkPlugin.shared.handle(urls: urls)'));
    expect(
      delegate,
      contains(r'!$0.isFileURL && !IncomingLinkPlugin.isLink($0)'),
      reason: 'a link must not also reach super as a deep link',
    );
    expect(window, contains('IncomingLinkPlugin.shared.register('));
    const channel = 'com.wavecrux/incoming_link';
    expect(delegate, contains('"$channel"'));
    expect(dart, contains("EventChannel('$channel')"));
  });

  test('the AppImage identity declares the scheme it hands to the app', () {
    expect(kWaveCruxLinuxDesktopApp.urlSchemes, [kWaveCruxLinkScheme]);
    expect(kWaveCruxLinkScheme, 'wavecrux');
    final identity = _read('lib/core/platform/linux_desktop_identity.dart');
    expect(identity, contains("urlSchemes: const ['wavecrux']"));
  });

  test('Windows and Linux hand a link to the running instance', () {
    final app = _read('lib/app.dart');
    expect(app, contains('claimSingleInstance('));
    expect(app, contains('is SingleInstanceDelivered'));
    expect(app, contains('IncomingLinkService.attachForwardedLinks('));
    expect(app, contains('bringWindowForward()'));
    final handoff = _read('lib/services/platform/single_instance_handoff.dart');
    expect(handoff, contains('schemes: const [kWaveCruxLinkScheme]'));
    expect(handoff, contains('maxLinkBytes: kWaveCruxLinkMaxLength'));
    expect(handoff, contains('desktopApp.appId'));
  });

  test('iOS and Android declare no scheme they do not handle', () {
    expect(
      declaredSchemes(File('ios/Runner/Info.plist')),
      isNot(contains('wavecrux')),
    );
    expect(
      _read('android/app/src/main/AndroidManifest.xml'),
      isNot(contains('android:scheme="wavecrux"')),
    );
  });

  test('the app reaches the link handler from every delivery route', () {
    final app = _read('lib/app.dart');
    // Windows and Linux: the command line, split before anything reads it.
    expect(app, contains('WaveCruxLaunchArgs.split(args)'));
    expect(app, contains('initialWaveCruxLinksProvider.overrideWithValue('));
    expect(app, contains('ref.read(initialWaveCruxLinksProvider)'));
    // macOS: the running instance's channel.
    expect(app, contains('IncomingLinkService.incomingLinks.listen('));
    // Both reach one inbox, which reaches the handler and the confirmation.
    expect(app, contains('WaveCruxLinkInbox(_openLink)'));
    expect(app, contains('await openWaveCruxLink('));
    expect(app, contains('OpenLinkConfirmDialog.show('));
    expect(app, contains('_linkInbox.markReady()'));
    // Nothing downstream of the split may read the raw arguments: a link
    // launch drops them all.
    const marker = 'final argv = launch.args;';
    expect(app, contains(marker));
    final body = app.substring(app.indexOf(marker) + marker.length);
    final rest = body.substring(0, body.indexOf('\nclass WaveCruxApp '));
    expect(
      RegExp(r'(?<![.\w])args\b').hasMatch(rest),
      isFalse,
      reason: 'bootstrap must read argv, not args, after the split',
    );
  });
}
