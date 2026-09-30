// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_manager.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_store.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_failure.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_reader.dart';
import 'package:wavecrux/features/stage/runtime/live_custom_stage_widget_registry.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_enums.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_renderer_registry.dart';
import 'package:wavecrux/plugins/stage_registry.dart';

import '_bundle_test_helpers.dart';

late Directory _tempDir;

Future<CustomWidgetBundleStore> _newStore() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return CustomWidgetBundleStore(prefs: prefs);
}

void main() {
  setUp(() {
    _tempDir = Directory.systemTemp.createTempSync('wcwm_');
  });

  tearDown(() {
    if (_tempDir.existsSync()) {
      _tempDir.deleteSync(recursive: true);
    }
    // Tests using the default registration seams mutate the process-global
    // StageRegistry / renderer registry; clear them so cases don't leak.
    StageRegistry.instance.clear();
    StageWidgetRendererRegistry.instance.clear();
  });

  group('CustomWidgetBundleManager', () {
    test('loadBundle registers the descriptor and persists the path', () async {
      final bundlePath = p.join(_tempDir.path, 'sample.wcrux-widget');
      await writeSampleBundle(path: bundlePath);
      final registry = LiveCustomStageWidgetRegistry();
      final store = await _newStore();
      final manager = CustomWidgetBundleManager(
        registry: registry,
        store: store,
      );
      addTearDown(manager.dispose);

      final err = await manager.loadBundle(bundlePath);
      expect(err, isNull);
      expect(registry.descriptors, hasLength(1));
      expect(registry.descriptors.first.widget.id, 'com.acme.test');
      expect(manager.state.loadedBundles, hasLength(1));
      expect(manager.state.loadedBundles.first.bundlePath, bundlePath);

      // Persisted on disk.
      expect(store.read().manualBundlePaths, contains(bundlePath));
    });

    test('loadBundle registers a definition + renderer for the render path '
        'and removeBundle clears both', () async {
      final bundlePath = p.join(_tempDir.path, 'render.wcrux-widget');
      await writeSampleBundle(
        path: bundlePath,
        manifest: sampleManifest(id: 'com.acme.render'),
      );
      final definitions = <String>{};
      final renderers = <String>{};
      final store = await _newStore();
      final manager = CustomWidgetBundleManager(
        registry: LiveCustomStageWidgetRegistry(),
        store: store,
        registerDefinition: (def) => definitions.add(def.id),
        unregisterDefinition: definitions.remove,
        registerRenderer: (id, _) => renderers.add(id),
        unregisterRenderer: renderers.remove,
      );
      addTearDown(manager.dispose);

      await manager.loadBundle(bundlePath);
      // Definition resolvable by the tile, and a live renderer for the Rive
      // runtime — the two halves the render path needs.
      expect(definitions, contains('com.acme.render'));
      expect(renderers, contains('com.acme.render'));

      await manager.removeBundle(bundlePath);
      expect(definitions, isEmpty);
      expect(renderers, isEmpty);
    });

    test(
      'painter-runtime bundle registers a definition but no renderer',
      () async {
        final bundlePath = p.join(_tempDir.path, 'painter.wcrux-widget');
        await writeSampleBundle(
          path: bundlePath,
          manifest: sampleManifest(
            id: 'com.acme.painter',
            runtime: ManifestRuntime.painter,
            runtimeAssetPath: 'runtime/painter.bin',
          ),
        );
        final definitions = <String>{};
        final renderers = <String>{};
        final store = await _newStore();
        final manager = CustomWidgetBundleManager(
          registry: LiveCustomStageWidgetRegistry(),
          store: store,
          registerDefinition: (def) => definitions.add(def.id),
          unregisterDefinition: definitions.remove,
          registerRenderer: (id, _) => renderers.add(id),
          unregisterRenderer: renderers.remove,
        );
        addTearDown(manager.dispose);

        await manager.loadBundle(bundlePath);
        expect(definitions, contains('com.acme.painter'));
        // No community painter runtime — tile falls back to description text.
        expect(renderers, isEmpty);
      },
    );

    test('initialize re-loads every persisted bundle on startup', () async {
      final bundlePath = p.join(_tempDir.path, 'persisted.wcrux-widget');
      await writeSampleBundle(
        path: bundlePath,
        manifest: sampleManifest(id: 'com.acme.persisted'),
      );
      final store = await _newStore();
      await store.addManualBundle(bundlePath);
      final registry = LiveCustomStageWidgetRegistry();
      final manager = CustomWidgetBundleManager(
        registry: registry,
        store: store,
      );
      addTearDown(manager.dispose);

      await manager.initialize();
      expect(registry.descriptors, hasLength(1));
      expect(registry.descriptors.first.widget.id, 'com.acme.persisted');
    });

    test('initialize surfaces stale paths as non-fatal errors', () async {
      final missingPath = p.join(_tempDir.path, 'missing.wcrux-widget');
      final store = await _newStore();
      await store.addManualBundle(missingPath);
      final registry = LiveCustomStageWidgetRegistry();
      final manager = CustomWidgetBundleManager(
        registry: registry,
        store: store,
      );
      addTearDown(manager.dispose);

      await manager.initialize();
      expect(registry.descriptors, isEmpty);
      expect(manager.state.errors, hasLength(1));
      expect(manager.state.errors.first.bundlePath, missingPath);
    });

    test('removeBundle unregisters and removes from persistence', () async {
      final bundlePath = p.join(_tempDir.path, 'rm.wcrux-widget');
      await writeSampleBundle(path: bundlePath);
      final registry = LiveCustomStageWidgetRegistry();
      final store = await _newStore();
      final manager = CustomWidgetBundleManager(
        registry: registry,
        store: store,
      );
      addTearDown(manager.dispose);
      await manager.loadBundle(bundlePath);
      expect(registry.descriptors, hasLength(1));

      await manager.removeBundle(bundlePath);
      expect(registry.descriptors, isEmpty);
      expect(store.read().manualBundlePaths, isEmpty);
      expect(manager.state.loadedBundles, isEmpty);
    });

    test(
      'addWatchedDirectory scans existing files and registers them',
      () async {
        final watchedDir = Directory(p.join(_tempDir.path, 'watched'))
          ..createSync();
        final bundlePath = p.join(watchedDir.path, 'scan.wcrux-widget');
        await writeSampleBundle(
          path: bundlePath,
          manifest: sampleManifest(id: 'com.acme.scan'),
        );
        final registry = LiveCustomStageWidgetRegistry();
        final store = await _newStore();
        final manager = CustomWidgetBundleManager(
          registry: registry,
          store: store,
          // Suppress the live FS watch in tests; we are exercising the
          // initial scan only here.
          watchFactory: (_) => const Stream<FileSystemEvent>.empty(),
        );
        addTearDown(manager.dispose);

        await manager.addWatchedDirectory(watchedDir.path);
        expect(registry.descriptors, hasLength(1));
        expect(registry.descriptors.first.widget.id, 'com.acme.scan');
        expect(store.read().watchedDirectories, contains(watchedDir.path));
        expect(manager.state.watchedDirectories, contains(watchedDir.path));
      },
    );

    test('directory watch: file added → descriptor registered; '
        'file removed → descriptor unregistered', () async {
      final watchedDir = Directory(p.join(_tempDir.path, 'live'))..createSync();
      final bundlePath = p.join(watchedDir.path, 'live.wcrux-widget');
      final controller = StreamController<FileSystemEvent>.broadcast();
      addTearDown(controller.close);

      final registry = LiveCustomStageWidgetRegistry();
      final store = await _newStore();
      final manager = CustomWidgetBundleManager(
        registry: registry,
        store: store,
        watchFactory: (_) => controller.stream,
      );
      addTearDown(manager.dispose);

      await manager.addWatchedDirectory(watchedDir.path);
      expect(registry.descriptors, isEmpty);

      // Simulate a file appearing on disk.
      await writeSampleBundle(
        path: bundlePath,
        manifest: sampleManifest(id: 'com.acme.live'),
      );
      controller.add(FileSystemCreateEvent(bundlePath, false));
      // Allow the manager's debounce timer to fire.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(registry.descriptors, hasLength(1));
      expect(registry.descriptors.first.widget.id, 'com.acme.live');

      // Simulate the file being removed.
      File(bundlePath).deleteSync();
      controller.add(FileSystemDeleteEvent(bundlePath, false));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(registry.descriptors, isEmpty);
    });

    test(
      'removeWatchedDirectory unregisters every descriptor it contributed',
      () async {
        final watchedDir = Directory(p.join(_tempDir.path, 'scoped'))
          ..createSync();
        final bundlePath = p.join(watchedDir.path, 'scoped.wcrux-widget');
        await writeSampleBundle(
          path: bundlePath,
          manifest: sampleManifest(id: 'com.acme.scoped'),
        );
        final registry = LiveCustomStageWidgetRegistry();
        final store = await _newStore();
        final manager = CustomWidgetBundleManager(
          registry: registry,
          store: store,
          watchFactory: (_) => const Stream<FileSystemEvent>.empty(),
        );
        addTearDown(manager.dispose);
        await manager.addWatchedDirectory(watchedDir.path);
        expect(registry.descriptors, hasLength(1));

        await manager.removeWatchedDirectory(watchedDir.path);
        expect(registry.descriptors, isEmpty);
        expect(store.read().watchedDirectories, isEmpty);
      },
    );

    test('listeners receive notifications when state mutates', () async {
      final bundlePath = p.join(_tempDir.path, 'notify.wcrux-widget');
      await writeSampleBundle(path: bundlePath);
      final manager = CustomWidgetBundleManager(
        registry: LiveCustomStageWidgetRegistry(),
        store: await _newStore(),
      );
      addTearDown(manager.dispose);

      var notifications = 0;
      manager.addListener(() => notifications++);
      await manager.loadBundle(bundlePath);
      expect(notifications, greaterThanOrEqualTo(1));
    });

    test(
      'dismissError removes a stale entry without touching persistence',
      () async {
        final missingPath = p.join(_tempDir.path, 'dismiss.wcrux-widget');
        final store = await _newStore();
        await store.addManualBundle(missingPath);
        final manager = CustomWidgetBundleManager(
          registry: LiveCustomStageWidgetRegistry(),
          store: store,
        );
        addTearDown(manager.dispose);
        await manager.initialize();
        expect(manager.state.errors, hasLength(1));

        manager.dismissError(missingPath);
        expect(manager.state.errors, isEmpty);
        // The path stays persisted so the next launch re-attempts and the
        // user can recover by restoring the file. Removing the path from
        // storage requires a deliberate removeBundle.
        expect(store.read().manualBundlePaths, contains(missingPath));
      },
    );

    test('dismissError on an unknown path does not notify', () async {
      final manager = CustomWidgetBundleManager(
        registry: LiveCustomStageWidgetRegistry(),
        store: await _newStore(),
      );
      addTearDown(manager.dispose);
      var notifications = 0;
      manager
        ..addListener(() => notifications++)
        ..dismissError(p.join(_tempDir.path, 'never-existed.wcrux-widget'));
      expect(notifications, 0);
      expect(manager.state.errors, isEmpty);
    });

    test(
      'loadBundle records a structured WidgetBundleException as an error',
      () async {
        final bundlePath = p.join(_tempDir.path, 'corrupt.wcrux-widget');
        // A non-empty, non-ZIP file: the reader surfaces notAZipArchive.
        File(bundlePath).writeAsStringSync('this is not a zip archive at all');
        final registry = LiveCustomStageWidgetRegistry();
        final manager = CustomWidgetBundleManager(
          registry: registry,
          store: await _newStore(),
        );
        addTearDown(manager.dispose);

        final err = await manager.loadBundle(bundlePath);
        expect(err, isNotNull);
        // A malformed bundle surfaces a structured (non-ioError) failure
        // kind — the exact kind depends on how far the reader gets before
        // rejecting; here it is a typed WidgetBundleException, not the
        // generic fallback.
        expect(err!.kind, isNot(WidgetBundleFailureKind.ioError));
        expect(registry.descriptors, isEmpty);
        expect(manager.state.errors, hasLength(1));
        expect(manager.state.errors.first.bundlePath, bundlePath);
      },
    );

    test('loadBundle maps a generic (non-WidgetBundleException) reader failure '
        'to an ioError', () async {
      final registry = LiveCustomStageWidgetRegistry();
      final manager = CustomWidgetBundleManager(
        registry: registry,
        store: await _newStore(),
        // Inject a reader whose fileReader throws a plain exception, so the
        // manager's `on Object catch` fallback runs (not the typed
        // WidgetBundleException path).
        reader: WidgetBundleReader(
          fileReader: (_) async => throw StateError('disk on fire'),
        ),
      );
      addTearDown(manager.dispose);

      final err = await manager.loadBundle('/tmp/whatever.wcrux-widget');
      expect(err, isNotNull);
      expect(err!.kind, WidgetBundleFailureKind.ioError);
      expect(err.diagnostic, contains('disk on fire'));
      expect(manager.state.errors, hasLength(1));
    });

    test('reloading a once-valid bundle that became invalid drops it from the '
        'registry and surfaces an error', () async {
      final bundlePath = p.join(_tempDir.path, 'flips.wcrux-widget');
      await writeSampleBundle(
        path: bundlePath,
        manifest: sampleManifest(id: 'com.acme.flips'),
      );
      final registry = LiveCustomStageWidgetRegistry();
      final manager = CustomWidgetBundleManager(
        registry: registry,
        store: await _newStore(),
      );
      addTearDown(manager.dispose);

      await manager.loadBundle(bundlePath);
      expect(registry.descriptors, hasLength(1));
      expect(manager.state.errors, isEmpty);

      // Corrupt the file in place, then reload the same path.
      File(bundlePath).writeAsStringSync('no longer a zip');
      final err = await manager.loadBundle(bundlePath);
      expect(err, isNotNull);
      // The prior successful registration was dropped.
      expect(registry.descriptors, isEmpty);
      expect(manager.state.loadedBundles, isEmpty);
      expect(manager.state.errors, hasLength(1));
    });

    test('a second bundle declaring the same widget id replaces the first '
        '(last-loaded wins)', () async {
      final firstPath = p.join(_tempDir.path, 'first.wcrux-widget');
      final secondPath = p.join(_tempDir.path, 'second.wcrux-widget');
      await writeSampleBundle(
        path: firstPath,
        manifest: sampleManifest(id: 'com.acme.dup', displayName: 'First'),
      );
      await writeSampleBundle(
        path: secondPath,
        manifest: sampleManifest(id: 'com.acme.dup', displayName: 'Second'),
      );
      final registry = LiveCustomStageWidgetRegistry();
      final manager = CustomWidgetBundleManager(
        registry: registry,
        store: await _newStore(),
      );
      addTearDown(manager.dispose);

      await manager.loadBundle(firstPath);
      await manager.loadBundle(secondPath);

      // Registry has exactly one descriptor for the shared id; the
      // first bundle's path entry was evicted in favour of the second.
      expect(registry.descriptors, hasLength(1));
      expect(registry.descriptors.first.widget.id, 'com.acme.dup');
      final paths = manager.state.loadedBundles
          .map((e) => e.bundlePath)
          .toList();
      expect(paths, contains(secondPath));
      expect(paths, isNot(contains(firstPath)));
    });

    test(
      'directory watch: a modify event reloads the bundle at the path',
      () async {
        final watchedDir = Directory(p.join(_tempDir.path, 'mod'))
          ..createSync();
        final bundlePath = p.join(watchedDir.path, 'mod.wcrux-widget');
        final controller = StreamController<FileSystemEvent>.broadcast();
        addTearDown(controller.close);
        final registry = LiveCustomStageWidgetRegistry();
        final manager = CustomWidgetBundleManager(
          registry: registry,
          store: await _newStore(),
          watchFactory: (_) => controller.stream,
        );
        addTearDown(manager.dispose);

        await manager.addWatchedDirectory(watchedDir.path);
        expect(registry.descriptors, isEmpty);

        await writeSampleBundle(
          path: bundlePath,
          manifest: sampleManifest(id: 'com.acme.mod'),
        );
        controller.add(FileSystemModifyEvent(bundlePath, false, false));
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(registry.descriptors, hasLength(1));
        expect(registry.descriptors.first.widget.id, 'com.acme.mod');
      },
    );

    test(
      'directory watch ignores events for non-bundle file extensions',
      () async {
        final watchedDir = Directory(p.join(_tempDir.path, 'noise'))
          ..createSync();
        final controller = StreamController<FileSystemEvent>.broadcast();
        addTearDown(controller.close);
        final registry = LiveCustomStageWidgetRegistry();
        final manager = CustomWidgetBundleManager(
          registry: registry,
          store: await _newStore(),
          watchFactory: (_) => controller.stream,
        );
        addTearDown(manager.dispose);

        await manager.addWatchedDirectory(watchedDir.path);
        controller.add(
          FileSystemCreateEvent(p.join(watchedDir.path, 'README.txt'), false),
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(registry.descriptors, isEmpty);
        expect(manager.state.errors, isEmpty);
      },
    );

    test(
      'addWatchedDirectory is idempotent for an already-watched path',
      () async {
        final watchedDir = Directory(p.join(_tempDir.path, 'idem'))
          ..createSync();
        var watchCalls = 0;
        final manager = CustomWidgetBundleManager(
          registry: LiveCustomStageWidgetRegistry(),
          store: await _newStore(),
          watchFactory: (_) {
            watchCalls++;
            return const Stream<FileSystemEvent>.empty();
          },
        );
        addTearDown(manager.dispose);

        await manager.addWatchedDirectory(watchedDir.path);
        await manager.addWatchedDirectory(watchedDir.path);
        // The second add short-circuits because a subscription already
        // exists for the directory.
        expect(watchCalls, 1);
      },
    );
  });

  group('CustomWidgetBundleManager model value types', () {
    test('LoadedBundleEntry equality and hashCode are field-based', () {
      const a = LoadedBundleEntry(
        bundlePath: '/a.wcrux-widget',
        widgetId: 'id',
        widgetVersion: '1.0.0',
        displayName: 'Name',
      );
      const same = LoadedBundleEntry(
        bundlePath: '/a.wcrux-widget',
        widgetId: 'id',
        widgetVersion: '1.0.0',
        displayName: 'Name',
      );
      const differentVersion = LoadedBundleEntry(
        bundlePath: '/a.wcrux-widget',
        widgetId: 'id',
        widgetVersion: '2.0.0',
        displayName: 'Name',
      );
      const withSource = LoadedBundleEntry(
        bundlePath: '/a.wcrux-widget',
        widgetId: 'id',
        widgetVersion: '1.0.0',
        displayName: 'Name',
        sourceDirectory: '/watched',
      );
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a, isNot(differentVersion));
      expect(a, isNot(withSource));
      expect(a, isNot('not an entry'));
    });

    test('BundleLoadError equality and hashCode are field-based', () {
      const a = BundleLoadError(
        bundlePath: '/x.wcrux-widget',
        kind: WidgetBundleFailureKind.manifestInvalid,
        diagnostic: 'bad yaml',
      );
      const same = BundleLoadError(
        bundlePath: '/x.wcrux-widget',
        kind: WidgetBundleFailureKind.manifestInvalid,
        diagnostic: 'bad yaml',
      );
      const differentKind = BundleLoadError(
        bundlePath: '/x.wcrux-widget',
        kind: WidgetBundleFailureKind.oversize,
        diagnostic: 'bad yaml',
      );
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a, isNot(differentKind));
      expect(a, isNot('not an error'));
    });

    test('CustomWidgetBundleManagerState equality, copyWith, and isEmpty', () {
      const empty = CustomWidgetBundleManagerState();
      expect(empty.isEmpty, isTrue);
      expect(empty, const CustomWidgetBundleManagerState());
      expect(empty.hashCode, const CustomWidgetBundleManagerState().hashCode);

      const entry = LoadedBundleEntry(
        bundlePath: '/a.wcrux-widget',
        widgetId: 'id',
        widgetVersion: '1.0.0',
        displayName: 'Name',
      );
      final withBundle = empty.copyWith(loadedBundles: [entry]);
      expect(withBundle.isEmpty, isFalse);
      expect(withBundle.loadedBundles, [entry]);
      // copyWith preserves untouched fields and differs from the original.
      expect(withBundle, isNot(empty));
      expect(withBundle.watchedDirectories, isEmpty);

      // A length difference and a per-element difference are both caught.
      expect(
        empty.copyWith(errors: const []),
        empty,
      );
      const otherEntry = LoadedBundleEntry(
        bundlePath: '/b.wcrux-widget',
        widgetId: 'id2',
        widgetVersion: '1.0.0',
        displayName: 'Other',
      );
      expect(
        withBundle,
        isNot(empty.copyWith(loadedBundles: const [otherEntry])),
      );
      expect(withBundle, isNot('not a state'));
    });
  });

  group('CustomWidgetBundleStore', () {
    test('round-trips manual bundle paths and watched directories', () async {
      final store = await _newStore();
      await store.addManualBundle('/tmp/a.wcrux-widget');
      await store.addManualBundle('/tmp/b.wcrux-widget');
      await store.addWatchedDirectory('/tmp/dir');
      // Adding the same path is idempotent.
      await store.addManualBundle('/tmp/a.wcrux-widget');

      final read = store.read();
      expect(read.manualBundlePaths, [
        '/tmp/a.wcrux-widget',
        '/tmp/b.wcrux-widget',
      ]);
      expect(read.watchedDirectories, ['/tmp/dir']);

      await store.removeManualBundle('/tmp/a.wcrux-widget');
      expect(store.read().manualBundlePaths, ['/tmp/b.wcrux-widget']);
    });
  });
}
