// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/features/workspace/providers/recent_lists.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> loaded(
    CruxRecentList list, {
    Map<String, Object> seed = const {},
  }) async {
    SharedPreferences.setMockInitialValues(seed);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(list.provider.notifier).restored;
    return container;
  }

  group('recentFiles', () {
    test('is empty when nothing is stored', () async {
      final container = await loaded(recentFiles);
      expect(container.read(recentFiles.provider), isEmpty);
    });

    test('reads the list the product has always stored', () async {
      final container = await loaded(
        recentFiles,
        seed: {
          'recent_files': ['/a/b.vcd', '/c/d.fst'],
        },
      );
      expect(container.read(recentFiles.provider), ['/a/b.vcd', '/c/d.fst']);
    });

    test('markOpened prepends, deduplicates and caps at ten', () async {
      final container = await loaded(
        recentFiles,
        seed: {
          'recent_files': List.generate(10, (i) => '/file_$i.vcd'),
        },
      );
      final notifier = container.read(recentFiles.provider.notifier)
        ..markOpened('/new.vcd');
      var files = container.read(recentFiles.provider);
      expect(files.length, 10);
      expect(files.first, '/new.vcd');
      expect(files.last, '/file_8.vcd');

      notifier.markOpened('/file_3.vcd');
      files = container.read(recentFiles.provider);
      expect(files.first, '/file_3.vcd');
      expect(files.where((p) => p == '/file_3.vcd'), hasLength(1));
    });

    test('markOpened persists under the recent_files key', () async {
      final container = await loaded(recentFiles);
      container.read(recentFiles.provider.notifier).markOpened('/dump.fst');
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('recent_files'), ['/dump.fst']);
    });

    test('remove drops one row and persists', () async {
      final container = await loaded(
        recentFiles,
        seed: {
          'recent_files': ['/a.vcd', '/b.fst'],
        },
      );
      container.read(recentFiles.provider.notifier).remove('/a.vcd');
      expect(container.read(recentFiles.provider), ['/b.fst']);
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('recent_files'), ['/b.fst']);
    });

    test('clear empties the list and the stored value', () async {
      final container = await loaded(
        recentFiles,
        seed: {
          'recent_files': ['/a.vcd', '/b.fst'],
        },
      );
      container.read(recentFiles.provider.notifier).clear();
      expect(container.read(recentFiles.provider), isEmpty);
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('recent_files'), isEmpty);
    });

    test('opening an entry that does not open drops it', () async {
      final container = await loaded(
        recentFiles,
        seed: {
          'recent_files': ['/gone.vcd', '/here.vcd'],
        },
      );
      final result = await container
          .read(recentFiles.provider.notifier)
          .open('/gone.vcd', (_) async => false);
      expect(result, CruxRecentOpenResult.removed);
      expect(container.read(recentFiles.provider), ['/here.vcd']);
    });

    test('a file that is gone is reported missing', () async {
      final container = await loaded(recentFiles);
      final exists = container.read(recentFiles.existsProvider);
      expect(exists('/definitely/not/a/real/path/nope.vcd'), isFalse);
    });
  });

  group('recentWorkspaces', () {
    test('is its own list under its own key', () async {
      final container = await loaded(
        recentWorkspaces,
        seed: {
          'recent_files': ['/a.vcd'],
          'recent_workspaces': ['/tmp/a.wavecrux-workspace'],
        },
      );
      expect(container.read(recentWorkspaces.provider), [
        '/tmp/a.wavecrux-workspace',
      ]);
      container
          .read(recentWorkspaces.provider.notifier)
          .markOpened('/tmp/b.wavecrux-workspace');
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('recent_workspaces'), [
        '/tmp/b.wavecrux-workspace',
        '/tmp/a.wavecrux-workspace',
      ]);
      expect(prefs.getStringList('recent_files'), ['/a.vcd']);
    });

    test('clear empties the list', () async {
      final container = await loaded(
        recentWorkspaces,
        seed: {
          'recent_workspaces': ['/tmp/a.wavecrux-workspace'],
        },
      );
      container.read(recentWorkspaces.provider.notifier).clear();
      expect(container.read(recentWorkspaces.provider), isEmpty);
    });
  });

  // Per-tab session sidecars live at `{appSupportDir}/sessions/{tab-uuid}.<ext>`.
  // The workspace restore path passes those URLs through the session loader,
  // which records them as opened and previously polluted the Welcome screen's
  // Recent Files list with UUID entries the user never opened.
  //
  // The sidecar guard was originally pinned to the `.wavecrux` extension, but
  // the auto-save writes the sidecar through the base `crux_workspace`
  // WorkspaceService whose default extension is `.json`, so the real files on
  // disk are `{uuid}.json` and leaked straight back into the list. The guard
  // matches any extension on a UUID basename inside a `sessions/` directory.
  group('internal sidecar paths', () {
    const sidecarMac =
        '/Users/u/Library/Application Support/com.ferriteengineering.wavecrux/sessions/3fa85f64-5717-4562-b3fc-2c963f66afa6.wavecrux';
    const sidecarLinux =
        '/home/u/.local/share/com.ferriteengineering.wavecrux/sessions/3fa85f64-5717-4562-b3fc-2c963f66afa6.wavecrux';
    const sidecarWindows =
        r'C:\Users\u\AppData\Roaming\com.ferriteengineering.wavecrux\sessions\3fa85f64-5717-4562-b3fc-2c963f66afa6.wavecrux';
    // The extension actually written on disk (crux_workspace default).
    const sidecarJsonMac =
        '/Users/u/Library/Application Support/com.ferriteengineering.wavecruxPro/sessions/43b549e0-eb98-4668-afe0-2949372d95d2.json';
    const sidecarJsonWindows =
        r'C:\Users\u\AppData\Roaming\com.ferriteengineering.wavecruxPro\sessions\43b549e0-eb98-4668-afe0-2949372d95d2.json';

    test('isInternalSessionSidecarPath matches macOS sidecar', () {
      expect(isInternalSessionSidecarPath(sidecarMac), isTrue);
    });

    test('isInternalSessionSidecarPath matches Linux sidecar', () {
      expect(isInternalSessionSidecarPath(sidecarLinux), isTrue);
    });

    test('isInternalSessionSidecarPath matches Windows sidecar', () {
      expect(isInternalSessionSidecarPath(sidecarWindows), isTrue);
    });

    test('isInternalSessionSidecarPath matches the real .json sidecar', () {
      expect(isInternalSessionSidecarPath(sidecarJsonMac), isTrue);
      expect(isInternalSessionSidecarPath(sidecarJsonWindows), isTrue);
    });

    test('isInternalSessionSidecarPath does NOT match user files', () {
      // A user-saved session file under a project directory.
      expect(
        isInternalSessionSidecarPath('/Users/u/projects/sim_run.wavecrux'),
        isFalse,
      );
      // A file in a sessions/ subdir but with a non-UUID name.
      expect(
        isInternalSessionSidecarPath(
          '/Users/u/projects/sessions/my_run.wavecrux',
        ),
        isFalse,
      );
      // A UUID-named waveform outside any sessions/ directory.
      expect(
        isInternalSessionSidecarPath(
          '/Users/u/dumps/3fa85f64-5717-4562-b3fc-2c963f66afa6.vcd',
        ),
        isFalse,
      );
    });

    test('markOpened silently rejects sidecar paths', () async {
      final container = await loaded(recentFiles);
      container.read(recentFiles.provider.notifier)
        ..markOpened(sidecarJsonMac)
        ..markOpened(sidecarMac);
      expect(container.read(recentFiles.provider), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('recent_files') ?? const <String>[], isEmpty);
    });

    test('a stored list is cleaned of sidecars and rewritten', () async {
      final container = await loaded(
        recentFiles,
        seed: {
          'recent_files': [
            '/Users/u/work/run_a.vcd',
            sidecarMac,
            '/Users/u/work/run_b.fst',
            sidecarLinux,
            sidecarJsonMac,
          ],
        },
      );
      expect(container.read(recentFiles.provider), [
        '/Users/u/work/run_a.vcd',
        '/Users/u/work/run_b.fst',
      ]);
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('recent_files'), [
        '/Users/u/work/run_a.vcd',
        '/Users/u/work/run_b.fst',
      ]);
    });
  });
}
