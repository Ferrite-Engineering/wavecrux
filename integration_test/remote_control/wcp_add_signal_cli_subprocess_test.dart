// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// integration_test/remote_control/wcp_add_signal_cli_subprocess_test.dart
//
// `wavecrux-ctl` CLI subprocess integration test.
//
// wcp_add_signal_test.dart proves the WCP `add_items` RPC at the socket
// level with a hand-rolled test client. Nothing in the suite actually spawns
// the real `tool/wavecrux_ctl` CLI as an OS subprocess — this test closes
// that gap by driving it with `Process.run` against a live running app
// instance, exercising the full path a real user's terminal invocation
// takes: process spawn -> CLI arg parsing -> `WcpClient` TCP connect ->
// greeting handshake -> command frame -> server handler -> provider state
// -> process exit code + stdout, for both `wavecrux-ctl load <file>` and
// `wavecrux-ctl add <signal>`.
//
// Prerequisite: `tool/wavecrux_ctl` is its own Dart package with its own
// `.dart_tool/` (gitignored) — it must be resolved once via
// `dart pub get --directory tool/wavecrux_ctl` before this test can spawn
// it. See the "Resolve tool/wavecrux_ctl deps" step in ci.yml (Analyze job)
// and the matching step added to integration.yml / integration-desktop.yml
// alongside this test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';

import '../helpers/app_driver.dart';

final String _repoRoot = Directory.current.path;

String _fixturePath(String relative) => [
  _repoRoot,
  'verification',
  'fixtures',
  relative,
].join(Platform.pathSeparator);

final String _ctlDir = [
  _repoRoot,
  'tool',
  'wavecrux_ctl',
].join(Platform.pathSeparator);

/// Runs `wavecrux-ctl <args>` as a real OS subprocess via `dart run`,
/// waiting for it to exit and capturing its output.
Future<ProcessResult> _runCtl(List<String> args) => Process.run(
  'dart',
  ['run', 'bin/wavecrux_ctl.dart', ...args],
  workingDirectory: _ctlDir,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  suppressPlatformSemanticsLeak();

  testWidgets(
    'wavecrux-ctl CLI subprocess: load + add reach a running app over WCP',
    (tester) async {
      await loadFixtureVcd(tester, 'vcd/scalar_basics.vcd');

      final container = rootContainer(tester);
      // add_items (like every other WCP handler) routes through the active
      // tab's container (issue #44 — `RemoteControlNotifier._activeTab`).
      final activeTab = activeTabContainer(tester);

      final startError = await container
          .read(remoteControlProvider.notifier)
          .startServer(0);
      expect(
        startError,
        isNull,
        reason: 'WCP server failed to start: $startError',
      );

      final port = container.read(remoteControlProvider).port;
      expect(port, isPositive);

      try {
        final fixturePath = _fixturePath('vcd/scalar_basics.vcd');

        // `wavecrux-ctl load <file>` — real subprocess, real TCP connection,
        // real CLI argument parsing.
        final loadResult = await _runCtl([
          '--port',
          '$port',
          'load',
          fixturePath,
        ]);
        expect(
          loadResult.exitCode,
          0,
          reason:
              'wavecrux-ctl load exited non-zero: '
              'stdout=${loadResult.stdout} stderr=${loadResult.stderr}',
        );
        expect(loadResult.stdout.toString(), contains('Loaded'));

        // `wavecrux-ctl add <signal_path>` — the subject of this test.
        const signalPath = 'top.clk';
        final addResult = await _runCtl(['--port', '$port', 'add', signalPath]);
        expect(
          addResult.exitCode,
          0,
          reason:
              'wavecrux-ctl add exited non-zero: '
              'stdout=${addResult.stdout} stderr=${addResult.stderr}',
        );
        expect(addResult.stdout.toString(), contains('Added'));

        // Bounded poll: the subprocess has already exited by the time we get
        // here, but the app-side provider update happens on the app's own
        // event loop, so give it a moment to observe.
        final added = await pumpUntil(
          tester,
          () => activeTab.read(signalGroupsProvider).signalCount > 0,
        );
        expect(
          added,
          isTrue,
          reason:
              'the signal added via the real wavecrux-ctl subprocess must '
              'land in signalGroupsProvider (the canvas lane source)',
        );
      } finally {
        await container.read(remoteControlProvider.notifier).stopServer();
      }

      expect(tester.takeException(), isNull);
    },
    // `dart run` cold-starts the CLI's own package graph twice (load + add);
    // give it more headroom than the default test timeout.
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
