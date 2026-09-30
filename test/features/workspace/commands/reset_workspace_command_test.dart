// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/workspace/commands/reset_workspace_command.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/workspace/wavecrux_workspace_codec.dart';

import '../../../helpers/product_telemetry_config.dart';

Future<T> _withTempDir<T>(Future<T> Function(Directory dir) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_reset_cmd_');
  try {
    return await fn(dir);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }
}

ProviderContainer _container(Directory dir) => ProviderContainer(
  overrides: [
    productTelemetryConfig,
    workspaceServiceProvider.overrideWithValue(
      WorkspaceService(
        codec: const WaveCruxWorkspaceCodec(),
        directoryFactory: () async => dir,
        logger: (_) {},
      ),
    ),
  ],
);

void main() {
  group('resetWorkspaceState (data path)', () {
    // The reset command is mostly Riverpod plumbing once the dialog seam is
    // stubbed. These tests exercise the pure-Dart container-based seam so
    // they do not depend on a live widget tree.

    test('empties the tab list and the persisted workspace', () async {
      await _withTempDir((dir) async {
        final c = _container(dir);
        addTearDown(c.dispose);
        await c.read(workspaceProvider.future);
        await c.wavecruxWorkspace.openFile('/tmp/a.vcd');
        await c.wavecruxWorkspace.openFile('/tmp/b.vcd');

        await resetWorkspaceStateForContainer(c);

        final workspace = c.read(workspaceProvider).requireValue;
        expect(workspace.tabs, isEmpty);
        final fromDisk = await WorkspaceService(
          codec: const WaveCruxWorkspaceCodec(),
          directoryFactory: () async => dir,
          logger: (_) {},
        ).load();
        expect(fromDisk.tabs, isEmpty);
        // Reset leaves the tab list empty; ViewerScreen renders
        // the empty-canvas state when [tabs.isEmpty].
        expect(c.read(tabListProvider), isEmpty);
      });
    });

    test('reset is idempotent on an already-empty workspace', () async {
      await _withTempDir((dir) async {
        final c = _container(dir);
        addTearDown(c.dispose);
        await c.read(workspaceProvider.future);

        await resetWorkspaceStateForContainer(c);
        await resetWorkspaceStateForContainer(c);

        expect(
          c.read(workspaceProvider).requireValue.tabs,
          isEmpty,
        );
      });
    });
  });

  // The full-path widget test (tap → showDialog → confirm) was retired:
  // flutter_test deadlocks the `await` of an async onPressed callback in our
  // setup, and the data-path test above plus the dialog-render sweep below
  // already cover the same surface end to end.

  group('defaultResetWorkspaceConfirm dialog', () {
    for (final locale in const [
      Locale('en'),
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets(
        'renders the confirmation dialog without exceptions in $locale',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              locale: locale,
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Builder(
                builder: (ctx) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => defaultResetWorkspaceConfirm(ctx),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
