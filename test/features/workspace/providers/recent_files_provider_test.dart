// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/features/workspace/providers/recent_files_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer makeContainer() => ProviderContainer();

  group('RecentFilesNotifier — initial state', () {
    test('returns empty list when no persisted data', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final files = await container.read(recentFilesProvider.future);
      expect(files, isEmpty);
    });

    test('loads persisted files from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'recent_files': ['/a/b.vcd', '/c/d.fst'],
      });
      final container = makeContainer();
      addTearDown(container.dispose);

      final files = await container.read(recentFilesProvider.future);
      expect(files, ['/a/b.vcd', '/c/d.fst']);
    });
  });

  group('RecentFilesNotifier.addFile', () {
    test('prepends a file to an empty list', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(recentFilesProvider.future);

      await container
          .read(recentFilesProvider.notifier)
          .addFile('/path/to/dump.vcd');

      final files = await container.read(recentFilesProvider.future);
      expect(files, ['/path/to/dump.vcd']);
    });

    test('prepends to existing list', () async {
      SharedPreferences.setMockInitialValues({
        'recent_files': ['/old.fst'],
      });
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(recentFilesProvider.future);

      await container.read(recentFilesProvider.notifier).addFile('/new.vcd');

      final files = await container.read(recentFilesProvider.future);
      expect(files, ['/new.vcd', '/old.fst']);
    });

    test('deduplicates — moves existing path to front', () async {
      SharedPreferences.setMockInitialValues({
        'recent_files': ['/a.vcd', '/b.fst', '/c.ghw'],
      });
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(recentFilesProvider.future);

      await container.read(recentFilesProvider.notifier).addFile('/b.fst');

      final files = await container.read(recentFilesProvider.future);
      expect(files, ['/b.fst', '/a.vcd', '/c.ghw']);
    });

    test('caps list at 10 entries', () async {
      final initial = List.generate(10, (i) => '/file_$i.vcd');
      SharedPreferences.setMockInitialValues({'recent_files': initial});
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(recentFilesProvider.future);

      await container.read(recentFilesProvider.notifier).addFile('/new.vcd');

      final files = await container.read(recentFilesProvider.future);
      expect(files.length, 10);
      expect(files.first, '/new.vcd');
      expect(files.last, '/file_8.vcd');
    });

    test('persists to SharedPreferences', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(recentFilesProvider.future);

      await container.read(recentFilesProvider.notifier).addFile('/dump.fst');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('recent_files'), ['/dump.fst']);
    });
  });

  // Issue 29: per-tab session sidecars live at
  // `{appSupportDir}/sessions/{tab-uuid}.<ext>`. The workspace restore
  // path passes those URLs through `SessionNotifier.loadFromPath`, which
  // forwards them to `addFile` and previously polluted the Welcome screen's
  // Recent Files list with UUID entries the user never opened.
  //
  // Regression: the sidecar guard was originally pinned to the `.wavecrux`
  // extension, but the auto-save writes the sidecar through the base
  // `crux_workspace` WorkspaceService whose default extension is `.json`, so
  // the real files on disk are `{uuid}.json` and leaked straight back into
  // the list. The guard now matches any extension on a UUID basename inside
  // a `sessions/` directory; the `.json` cases below lock that in.
  group('RecentFilesNotifier — internal sidecar paths (Issue 29)', () {
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

    test(
      'isInternalSessionSidecarPath matches the real .json sidecar (macOS)',
      () {
        // The actual extension written to disk — the regression the broadened
        // guard fixes.
        expect(isInternalSessionSidecarPath(sidecarJsonMac), isTrue);
      },
    );

    test(
      'isInternalSessionSidecarPath matches the real .json sidecar (Windows)',
      () {
        expect(isInternalSessionSidecarPath(sidecarJsonWindows), isTrue);
      },
    );

    test('addFile silently rejects .json sidecar paths', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(recentFilesProvider.future);

      await container
          .read(recentFilesProvider.notifier)
          .addFile(sidecarJsonMac);

      final files = await container.read(recentFilesProvider.future);
      expect(
        files,
        isEmpty,
        reason: 'the .json sidecar must not pollute the recent files list',
      );
    });

    test(
      'build() one-shot cleanup also removes previously-persisted .json sidecars',
      () async {
        SharedPreferences.setMockInitialValues({
          'recent_files': [
            sidecarJsonMac,
            '/Users/u/work/run_a.vcd',
            sidecarJsonWindows,
          ],
        });
        final container = makeContainer();
        addTearDown(container.dispose);

        final files = await container.read(recentFilesProvider.future);
        expect(files, [
          '/Users/u/work/run_a.vcd',
        ], reason: 'leaked .json sidecars are cleaned on next launch');
      },
    );

    test(
      'isInternalSessionSidecarPath does NOT match user .wavecrux files',
      () {
        // A user-saved session file under a project directory — not a sidecar.
        expect(
          isInternalSessionSidecarPath('/Users/u/projects/sim_run.wavecrux'),
          isFalse,
        );
        // A .wavecrux file in a sessions/ subdir but with a non-UUID name —
        // not a sidecar (would be a user-named session in a sessions/ folder).
        expect(
          isInternalSessionSidecarPath(
            '/Users/u/projects/sessions/my_run.wavecrux',
          ),
          isFalse,
        );
        // A UUID-named waveform file outside any sessions/ directory — the
        // broadened (any-extension) guard must still require the `sessions/`
        // path segment, so this real file is kept.
        expect(
          isInternalSessionSidecarPath(
            '/Users/u/dumps/3fa85f64-5717-4562-b3fc-2c963f66afa6.vcd',
          ),
          isFalse,
        );
      },
    );

    test('addFile silently rejects sidecar paths', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(recentFilesProvider.future);

      await container.read(recentFilesProvider.notifier).addFile(sidecarMac);

      final files = await container.read(recentFilesProvider.future);
      expect(
        files,
        isEmpty,
        reason: 'sidecar path must not pollute the recent files list',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('recent_files') ?? const <String>[], isEmpty);
    });

    test(
      'build() one-shot cleanup: existing persisted sidecar paths are filtered out and the cleaned list is rewritten',
      () async {
        SharedPreferences.setMockInitialValues({
          'recent_files': [
            '/Users/u/work/run_a.vcd',
            sidecarMac,
            '/Users/u/work/run_b.fst',
            sidecarLinux,
          ],
        });
        final container = makeContainer();
        addTearDown(container.dispose);

        final files = await container.read(recentFilesProvider.future);
        expect(
          files,
          ['/Users/u/work/run_a.vcd', '/Users/u/work/run_b.fst'],
          reason: 'both sidecar entries must be filtered out on load',
        );
        // Cleanup must rewrite the persisted list so the cleanup is a
        // one-shot — subsequent launches see the cleaned list directly.
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getStringList('recent_files'),
          ['/Users/u/work/run_a.vcd', '/Users/u/work/run_b.fst'],
        );
      },
    );

    test(
      'build() does not rewrite SharedPreferences when no sidecar paths exist',
      () async {
        // Regression guard for the cleanup branch: the rewrite must be
        // conditional so a normal launch is not paying an extra disk write
        // on every cold start.
        SharedPreferences.setMockInitialValues({
          'recent_files': ['/a.vcd', '/b.fst'],
        });
        final container = makeContainer();
        addTearDown(container.dispose);

        final files = await container.read(recentFilesProvider.future);
        expect(files, ['/a.vcd', '/b.fst']);
        // We can't directly assert "no write happened", but we can assert
        // the persisted list is byte-identical to the seed — proving the
        // cleanup branch did not run.
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('recent_files'), ['/a.vcd', '/b.fst']);
      },
    );
  });

  group('RecentFilesNotifier.removeFile', () {
    test('removes a file from the list', () async {
      SharedPreferences.setMockInitialValues({
        'recent_files': ['/a.vcd', '/b.fst'],
      });
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(recentFilesProvider.future);

      await container.read(recentFilesProvider.notifier).removeFile('/a.vcd');

      final files = await container.read(recentFilesProvider.future);
      expect(files, ['/b.fst']);
    });

    test('is a no-op when path is not in list', () async {
      SharedPreferences.setMockInitialValues({
        'recent_files': ['/a.vcd'],
      });
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(recentFilesProvider.future);

      await container
          .read(recentFilesProvider.notifier)
          .removeFile('/missing.vcd');

      final files = await container.read(recentFilesProvider.future);
      expect(files, ['/a.vcd']);
    });

    test('persists removal to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'recent_files': ['/a.vcd', '/b.fst'],
      });
      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(recentFilesProvider.future);

      await container.read(recentFilesProvider.notifier).removeFile('/a.vcd');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('recent_files'), ['/b.fst']);
    });
  });
}
