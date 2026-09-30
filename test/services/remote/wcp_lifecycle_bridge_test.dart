// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/services/remote/remote_control_notifier.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

class _MockSettingsService extends Mock implements WaveCruxSettingsService {}

/// Builds a container whose persisted settings are exactly [settings].
ProviderContainer _containerWith(AppSettings settings) {
  final mock = _MockSettingsService();
  when(mock.load).thenAnswer((_) async => settings);
  when(() => mock.save(any())).thenAnswer((_) async {});
  return ProviderContainer(
    overrides: [settingsServiceProvider.overrideWithValue(mock)],
  );
}

/// Instantiates the bridge the way `bootstrap()` does — a single read of the
/// keepAlive provider — then waits for the persisted settings to land, which is
/// what the bridge's `fireImmediately` listener reacts to.
Future<void> _boot(ProviderContainer container) async {
  container.read(wcpLifecycleBridgeProvider);
  await container.read(appSettingsProvider.future);
}

/// Binds an ephemeral port, notes the number the OS handed out, and releases
/// it — a concrete port the bridge can then bind for real.
Future<int> _freePort() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  return port;
}

/// Polls until [predicate] holds or the timeout elapses. The bridge fires
/// `unawaited(startServer(...))`, so the socket bind lands a microtask-plus
/// after the settings future resolves.
Future<void> _until(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUpAll(() => registerFallbackValue(const AppSettings()));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('WcpLifecycleBridge', () {
    late ProviderContainer container;

    tearDown(() async {
      await container.read(remoteControlProvider.notifier).stopServer();
      container.dispose();
    });

    // The beta issue #9 regression: before the bridge existed, the
    // persisted `remoteControlEnabled` flag was inert at launch — the settings
    // screen was the only caller of startServer, so a scripted client hit a
    // stopped server on every relaunch.
    test('auto-starts the server at launch when the setting is on', () async {
      // Port 0 → OS-assigned ephemeral port, so the test never collides with a
      // real WaveCrux (or a parallel test shard) holding 9473.
      container = _containerWith(
        const AppSettings(remoteControlEnabled: true, remoteControlPort: 0),
      );

      await _boot(container);
      await _until(() => container.read(remoteControlProvider).isRunning);

      final state = container.read(remoteControlProvider);
      expect(state.isRunning, isTrue);
      // The bound port is reported back, not the requested 0.
      expect(state.port, greaterThan(0));
    });

    test('stays stopped at launch when the setting is off', () async {
      container = _containerWith(const AppSettings());

      await _boot(container);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(remoteControlProvider).isRunning, isFalse);
    });

    test('toggling the setting on starts the server', () async {
      container = _containerWith(const AppSettings(remoteControlPort: 0));

      await _boot(container);
      expect(container.read(remoteControlProvider).isRunning, isFalse);

      await container
          .read(appSettingsProvider.notifier)
          .setRemoteControlEnabled(enabled: true);
      await _until(() => container.read(remoteControlProvider).isRunning);
    });

    test('toggling the setting off stops the server', () async {
      container = _containerWith(
        const AppSettings(remoteControlEnabled: true, remoteControlPort: 0),
      );

      await _boot(container);
      await _until(() => container.read(remoteControlProvider).isRunning);

      await container
          .read(appSettingsProvider.notifier)
          .setRemoteControlEnabled(enabled: false);
      await _until(() => !container.read(remoteControlProvider).isRunning);
    });

    test('changing the port rebinds the running server', () async {
      // Two concrete free ports, so the assertion is on the exact bound port
      // rather than on "some ephemeral port changed".
      final portA = await _freePort();
      final portB = await _freePort();

      container = _containerWith(
        AppSettings(remoteControlEnabled: true, remoteControlPort: portA),
      );

      await _boot(container);
      await _until(() => container.read(remoteControlProvider).isRunning);
      expect(container.read(remoteControlProvider).port, portA);

      // The pre-fix settings screen persisted a new port without ever touching
      // the live server, so the running server kept the old binding until the
      // next manual toggle.
      await container
          .read(appSettingsProvider.notifier)
          .setRemoteControlPort(portB);
      await _until(() => container.read(remoteControlProvider).port == portB);
      expect(container.read(remoteControlProvider).isRunning, isTrue);
    });

    // `startServer` reports a failed bind by returning the error rather than
    // throwing, and the bridge fires it unawaited — so before the result was
    // read, a port held by another process left the server silently stopped,
    // with nothing in the log to say why a scripted client was refused.
    test('a port it cannot bind is logged, not dropped', () async {
      final squatter = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(squatter.close);
      final records = <LogRecord>[];
      Logger.root.level = Level.ALL;
      final sub = Logger.root.onRecord
          .where((r) => r.loggerName == 'wavecrux.wcp')
          .listen(records.add);
      addTearDown(sub.cancel);

      container = _containerWith(
        AppSettings(
          remoteControlEnabled: true,
          remoteControlPort: squatter.port,
        ),
      );

      await _boot(container);
      await _until(() => records.isNotEmpty);

      expect(container.read(remoteControlProvider).isRunning, isFalse);
      expect(records.single.level, Level.WARNING);
      expect(records.single.message, contains('${squatter.port}'));
    });
  });
}
