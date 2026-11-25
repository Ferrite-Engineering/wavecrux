// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The shared CXP lifecycle, the cross-probe send surfaces and the Recent list
// live in `crux-shared` and test themselves there. What the package's green
// suite cannot see is whether this app mounts them: a shared widget or provider
// that nothing here calls is a promise the product is not keeping, and the
// product's own tests can pass around it.
//
// Each claim below is mechanically checkable against `lib/`:
//
//  1. `bootstrap()` installs the CXP overrides (binding, request handler,
//     version, attention, foreground hand-off, server policy, send
//     observer), and every desktop runner answers the hand-off's channel.
//  2. The handler override is WaveCrux's, not the shared do-nothing default,
//     and the server policy override is the organization's rule.
//  3. The shared runtime is started at launch.
//  4. The "Cross-probe to" menu entry, the Cross-probe Selection command and
//     Clear Recent are called from the app.
//  5. The Settings CXP section is the shared one.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _read(String relative) {
  final file = File(relative);
  expect(file.existsSync(), isTrue, reason: '$relative is missing');
  return file.readAsStringSync();
}

/// Every Dart source under `lib/`, by path.
Map<String, String> _libSources() => {
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
    if (f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
      p.normalize(f.path).replaceAll(r'\', '/'): f.readAsStringSync(),
};

void main() {
  test('bootstrap installs the CXP overrides', () {
    expect(
      _read('lib/app.dart'),
      contains('...await wavecruxCxpOverrides()'),
      reason:
          'Without these the shared providers have no binding: the server '
          'never starts, and every surface that reads them throws.',
    );
  });

  test('the overrides bind WaveCrux, not the shared defaults', () {
    final overrides = _read(
      'lib/services/remote/cxp/wavecrux_cxp_overrides.dart',
    );
    for (final required in <String>[
      'cruxCxpProductBindingProvider.overrideWithValue(kWaveCruxCxpBinding)',
      'cruxCxpRequestHandlerProvider.overrideWith(WaveCruxCxpRequestHandler.new)',
      'cruxCxpProductVersionProvider.overrideWith',
      'cruxCxpAttentionRequesterProvider.overrideWithValue',
      'cruxCxpForegroundHandoffProvider.overrideWithValue',
      'windowForegroundHandoff.yieldForegroundTo(',
      'windowForegroundHandoff.takeForeground(',
      'cruxCxpServerPolicyProvider.overrideWith',
      'resolveCxpServerPolicy(',
      'crossProbeSendObserverProvider.overrideWith',
      "'cxp.crossprobe'",
    ]) {
      expect(
        overrides,
        contains(required),
        reason: 'wavecrux_cxp_overrides.dart no longer contains `$required`',
      );
    }
  });

  test('every desktop runner answers the foreground hand-off channel', () {
    // The Dart override hands over through `crux_window_chrome/foreground`;
    // a runner that does not answer it degrades to "no hand-off" in silence.
    for (final runner in <String>[
      'macos/Runner/WindowForegroundPlugin.swift',
      'windows/runner/flutter_window.cpp',
      'linux/runner/my_application.cc',
    ]) {
      final source = _read(runner);
      expect(
        source,
        contains('"crux_window_chrome/foreground"'),
        reason: '$runner does not register the foreground channel',
      );
      expect(source, contains('yieldForeground'), reason: runner);
      expect(source, contains('takeForeground'), reason: runner);
    }
    expect(
      _read('macos/Runner/MainFlutterWindow.swift'),
      contains('WindowForegroundPlugin(messenger:'),
      reason: 'the macOS plugin is written but never registered',
    );
    expect(
      _read('macos/Runner.xcodeproj/project.pbxproj'),
      contains('WindowForegroundPlugin.swift in Sources'),
      reason: 'the macOS plugin is not compiled into the Runner target',
    );
  });

  test('the request handler reaches the inbound dispatchers', () {
    final handler = _read(
      'lib/services/remote/cxp/wavecrux_cxp_request_handler.dart',
    );
    for (final dispatcher in <String>[
      'dispatchCxpHighlight(',
      'dispatchCxpOpenSource(',
      'dispatchCxpOpenArtifact(',
      'handleInboundSelection(',
    ]) {
      expect(handler, contains(dispatcher), reason: dispatcher);
    }
  });

  test('the shared runtime is started at launch', () {
    expect(
      _read('lib/app.dart'),
      contains('..read(cruxCxpRuntimeProvider)'),
      reason:
          'The first reader starts the server; nothing else reads it early.',
    );
  });

  test('the active document is published from launch', () {
    expect(
      _read('lib/app.dart'),
      contains('..read(cxpActiveDocumentPublisherProvider)'),
      reason:
          'Nothing else reads the publisher: without this read no peer ever '
          'sees which waveform this window shows.',
    );
  });

  test('a formal trace step and an EQY pairing reach the inbound path', () {
    final inbound = _read('lib/services/remote/cxp/cxp_inbound_handlers.dart');
    for (final call in <String>[
      'FormalStreamCoordinateResolver.implementsStream(',
      'const FormalStreamCoordinateResolver().resolve(',
      '_highlightSource(ref, element.path, metadata, coordinate)',
      '_applyEqyPairing(container, source, metadata)',
      'EqyTracePairing.arrange(',
      '.prependArrangement(',
    ]) {
      expect(inbound, contains(call), reason: call);
    }
    expect(
      _read('lib/services/remote/cxp/riscv_stream_coordinate_resolver.dart'),
      contains('TraceStepLattice.fromTicks('),
      reason: 'the RVFI grid delegates to the shared lattice, never a copy',
    );
  });

  test('the shared send and Recent surfaces are called from the app', () {
    final sources = _libSources();
    for (final call in <String>[
      'crossProbeMenuEntry(',
      'runCrossProbeSelection(',
      'clearCruxRecentList(',
      'CruxRecentListSection(',
      'CruxCrossProbePanel(',
    ]) {
      final callers = [
        for (final entry in sources.entries)
          if (entry.value.contains(call)) entry.key,
      ];
      expect(
        callers,
        isNotEmpty,
        reason:
            'Nothing under lib/ calls `$call`: the shared surface is built '
            'and tested in crux-shared but never mounted here.',
      );
    }
  });

  test('the Settings CXP section is the shared one', () {
    final settings = _read(
      'lib/features/settings/screens/settings_screen.dart',
    );
    expect(settings, contains('CruxCxpSettingsSection('));
    expect(
      settings,
      isNot(contains('CruxCxpSettingsControls(')),
      reason: 'The controls are bound by the shared section, not rebuilt here.',
    );
  });

  test('the product no longer carries a copy of the lifecycle', () {
    for (final deleted in <String>[
      'lib/features/remote/providers/cxp_server_provider.dart',
      'lib/services/remote/cxp/wavecrux_cxp_server.dart',
      'lib/features/workspace/providers/recent_files_provider.dart',
      'lib/features/workspace/providers/recent_workspaces_provider.dart',
    ]) {
      expect(
        File(deleted).existsSync(),
        isFalse,
        reason: '$deleted is the product copy the shared lifecycle replaced',
      );
    }
  });

  test('every CXP setting has one writer: the shared provider', () {
    final codec = _read('lib/services/settings/settings_service.dart');
    for (final key in <String>[
      'cxpServerEnabled',
      'cxpServerPort',
      'requestAttentionOnCrossProbe',
      'broadcastSelectionOnCrossProbe',
    ]) {
      expect(
        codec,
        isNot(contains(key)),
        reason:
            'WaveCruxSettingsCodec writes `$key`, which would overwrite what '
            'cruxCxpSettingsProvider saved on every unrelated settings change.',
      );
    }
  });
}
