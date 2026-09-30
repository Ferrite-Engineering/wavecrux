// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/workspace/window_bounds_store.dart';

void main() {
  group('windowBoundsFromExtras / extrasWithWindowBounds', () {
    test('reads bounds stored under the extras key', () {
      const bounds = WindowBounds(left: 10, top: 20, width: 1400, height: 900);
      final extras = extrasWithWindowBounds(const {}, bounds);
      expect(windowBoundsFromExtras(extras), bounds);
    });

    test('returns null when the key is absent', () {
      expect(windowBoundsFromExtras(const {'other': 1}), isNull);
    });

    test('returns null when the value is not a map', () {
      expect(
        windowBoundsFromExtras(const {kWindowBoundsExtrasKey: 'nope'}),
        isNull,
      );
    });

    test('preserves sibling extras entries when writing', () {
      const bounds = WindowBounds(width: 800, height: 600);
      final extras = extrasWithWindowBounds(
        const {'panelVisible': true},
        bounds,
      );
      expect(extras['panelVisible'], isTrue);
      expect(extras[kWindowBoundsExtrasKey], bounds.toJson());
    });
  });

  group('peekPersistedWindowBounds', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wc_window_bounds_test');
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    Future<Directory> factory() async => tempDir;

    Future<WindowBounds?> peek() =>
        peekPersistedWindowBounds(directoryFactory: factory);

    void writeWorkspace(Object? json) {
      File(
        '${tempDir.path}/$kWorkspaceFileName',
      ).writeAsStringSync(jsonEncode(json));
    }

    test('returns null when no workspace file exists', () async {
      expect(await peek(), isNull);
    });

    test('reads bounds from the workspace extras', () async {
      const bounds = WindowBounds(left: 64, top: 48, width: 1600, height: 1000);
      writeWorkspace({
        'version': 1,
        'extras': {kWindowBoundsExtrasKey: bounds.toJson()},
      });
      expect(await peek(), bounds);
    });

    test('returns null when extras has no bounds', () async {
      writeWorkspace({'version': 1, 'extras': <String, Object?>{}});
      expect(await peek(), isNull);
    });

    test('returns null when there is no extras object', () async {
      writeWorkspace({'version': 1, 'tabs': <Object?>[]});
      expect(await peek(), isNull);
    });

    test('returns null on malformed JSON without throwing', () async {
      File(
        '${tempDir.path}/$kWorkspaceFileName',
      ).writeAsStringSync('{ not valid json');
      expect(await peek(), isNull);
    });

    test(
      'does not mutate or delete the workspace file (side-effect free)',
      () async {
        writeWorkspace({'version': 1, 'extras': <String, Object?>{}});
        final file = File('${tempDir.path}/$kWorkspaceFileName');
        final before = file.readAsStringSync();
        await peek();
        expect(file.existsSync(), isTrue);
        expect(file.readAsStringSync(), before);
      },
    );
  });
}
