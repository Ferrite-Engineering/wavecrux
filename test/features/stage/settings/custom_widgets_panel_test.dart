// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_manager.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_provider.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_store.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_failure.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_reader.dart';
import 'package:wavecrux/features/stage/runtime/live_custom_stage_widget_registry.dart';
import 'package:wavecrux/features/stage/settings/custom_widgets_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/custom_stage_widget_registry_provider.dart';

import '_bundle_test_helpers.dart';

/// Constructs a [CustomWidgetBundleManager] for tests. Must be called
/// inside [WidgetTester.runAsync] because it touches `dart:io` file
/// operations (the bundle writer, the bundle reader's `File.readAsBytes`)
/// that do not resolve under the testWidgets fake-async clock.
Future<CustomWidgetBundleManager> _makeManager({
  required Directory tempDir,
  String? preloadedBundlePath,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = CustomWidgetBundleStore(prefs: prefs);
  if (preloadedBundlePath != null) {
    await store.addManualBundle(preloadedBundlePath);
  }
  final registry = LiveCustomStageWidgetRegistry();
  final manager = CustomWidgetBundleManager(
    registry: registry,
    store: store,
  );
  await manager.initialize();
  return manager;
}

Widget _wrap({
  required Widget child,
  required LicenseTier tier,
  Locale? locale,
}) {
  return ProviderScope(
    overrides: [
      licenseTierProvider.overrideWith((_) => tier),
      customStageWidgetRegistryProvider.overrideWith(
        (_) => LiveCustomStageWidgetRegistry(),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        ...L10N.localizationsDelegates,
        ...L10N.localizationsDelegates,
      ],
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

/// Pumps a few frames to give the panel's listeners and any
/// synchronous post-frame callbacks a chance to settle. We deliberately
/// avoid [WidgetTester.pumpAndSettle] — Material's InkWell hover overlay
/// schedules indefinite repaint phases that pumpAndSettle treats as
/// non-idle. Two pumps are sufficient because [overrideManager] removes
/// the FutureProvider transition.
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cwpanel_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('CustomWidgetsPanel locale sweep', () {
    for (final locale in const ['en', 'ja', 'ko', 'zh']) {
      testWidgets('renders empty state without exception in $locale', (
        tester,
      ) async {
        late final CustomWidgetBundleManager manager;
        await tester.runAsync(() async {
          manager = await _makeManager(tempDir: tempDir);
        });
        addTearDown(manager.dispose);
        await tester.pumpWidget(
          _wrap(
            child: CustomWidgetsPanel(overrideManager: manager),
            tier: LicenseTier.pro,
            locale: Locale(locale),
          ),
        );
        await _pumpFrames(tester);
        expect(tester.takeException(), isNull);
        // Both action buttons render in every locale.
        expect(find.byIcon(Icons.folder_open), findsOneWidget);
        expect(find.byIcon(Icons.folder_special), findsOneWidget);
      });
    }
  });

  testWidgets('lists a loaded bundle row when the manager has one', (
    tester,
  ) async {
    final bundlePath = '${tempDir.path}/loaded.wcrux-widget';
    late final CustomWidgetBundleManager manager;
    await tester.runAsync(() async {
      await writeSampleBundle(
        path: bundlePath,
        manifest: sampleManifest(
          id: 'com.acme.row',
          displayName: 'Row Sample',
          version: '7.7.7',
        ),
      );
      manager = await _makeManager(
        tempDir: tempDir,
        preloadedBundlePath: bundlePath,
      );
    });
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      _wrap(
        child: CustomWidgetsPanel(overrideManager: manager),
        tier: LicenseTier.pro,
      ),
    );
    await _pumpFrames(tester);

    expect(find.text('Row Sample'), findsOneWidget);
    expect(find.textContaining('7.7.7'), findsOneWidget);
    expect(find.text(bundlePath), findsOneWidget);
  });

  testWidgets('Load button invokes the override picker and registers the '
      'returned bundle', (tester) async {
    final bundlePath = '${tempDir.path}/picked.wcrux-widget';
    late final CustomWidgetBundleManager manager;
    await tester.runAsync(() async {
      await writeSampleBundle(
        path: bundlePath,
        manifest: sampleManifest(id: 'com.acme.picked', displayName: 'Picked'),
      );
      manager = await _makeManager(tempDir: tempDir);
    });
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      _wrap(
        child: CustomWidgetsPanel(
          overrideManager: manager,
          overridePicker: (_) async => bundlePath,
        ),
        tier: LicenseTier.pro,
      ),
    );
    await _pumpFrames(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.folder_open));
      // Drain the async load (file read + register) before the test
      // exits — otherwise tearDown disposes the manager mid-flight and
      // _refreshState's notifyListeners hits the disposed assert.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await _pumpFrames(tester);
    expect(find.text('Picked'), findsOneWidget);
  });

  testWidgets('panel is open-core — renders the body (no PRO badge, no '
      'gate) even at openCore tier', (tester) async {
    // The Stage widget capability is free (wavecrux/CLAUDE.md), so the
    // panel has NO tier gate: an openCore user sees the full body with
    // action buttons, never a gated placeholder, and there is no PRO
    // badge anywhere. (Regression guard: the panel used to FeatureGate on
    // LicenseTier.pro, contradicting the free-SDK principle.)
    late final CustomWidgetBundleManager manager;
    await tester.runAsync(() async {
      manager = await _makeManager(tempDir: tempDir);
    });
    addTearDown(manager.dispose);
    await tester.pumpWidget(
      _wrap(
        child: CustomWidgetsPanel(overrideManager: manager),
        tier: LicenseTier.openCore,
      ),
    );
    await _pumpFrames(tester);
    // No PRO badge, and the load-bundle action (folder_open) is present —
    // proving the body renders rather than a gated placeholder.
    expect(find.text('PRO'), findsNothing);
    expect(find.byIcon(Icons.folder_open), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'renders the loading spinner while the manager FutureProvider resolves',
    (tester) async {
      // Override the manager provider with a never-completing future so the
      // panel stays in the AsyncValue.loading branch.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            licenseTierProvider.overrideWith((_) => LicenseTier.pro),
            customStageWidgetRegistryProvider.overrideWith(
              (_) => LiveCustomStageWidgetRegistry(),
            ),
            customWidgetBundleManagerProvider.overrideWith(
              (_) => Completer<CustomWidgetBundleManager>().future,
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: CustomWidgetsPanel()),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('renders the error placeholder when the manager future fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          licenseTierProvider.overrideWith((_) => LicenseTier.pro),
          customStageWidgetRegistryProvider.overrideWith(
            (_) => LiveCustomStageWidgetRegistry(),
          ),
          customWidgetBundleManagerProvider.overrideWith(
            (_) => Future<CustomWidgetBundleManager>.error(
              StateError('init blew up'),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(body: CustomWidgetsPanel()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    // The error branch renders the load-failed message containing the
    // thrown error's text.
    expect(find.textContaining('init blew up'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'resolved manager future renders the panel body via the data branch',
    (tester) async {
      // Exercises the FutureProvider data branch (overrideManager bypasses
      // it in the other tests). The default registry override prevents the
      // manager's directory-watch I/O from touching the real filesystem.
      late final CustomWidgetBundleManager manager;
      await tester.runAsync(() async {
        manager = await _makeManager(tempDir: tempDir);
      });
      addTearDown(manager.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            licenseTierProvider.overrideWith((_) => LicenseTier.pro),
            customStageWidgetRegistryProvider.overrideWith(
              (_) => LiveCustomStageWidgetRegistry(),
            ),
            customWidgetBundleManagerProvider.overrideWith(
              (_) async => manager,
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: CustomWidgetsPanel()),
          ),
        ),
      );
      await _pumpFrames(tester);
      expect(find.byIcon(Icons.folder_open), findsOneWidget);
      expect(find.byIcon(Icons.folder_special), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a stale preloaded bundle renders a dismissible error row; tapping '
    'dismiss removes it',
    (tester) async {
      // A persisted path that does not resolve to a real bundle surfaces as
      // an error row in the panel's Errors section.
      final missingPath = '${tempDir.path}/gone.wcrux-widget';
      late final CustomWidgetBundleManager manager;
      await tester.runAsync(() async {
        manager = await _makeManager(
          tempDir: tempDir,
          preloadedBundlePath: missingPath,
        );
      });
      addTearDown(manager.dispose);
      expect(manager.state.errors, hasLength(1));

      await tester.pumpWidget(
        _wrap(
          child: CustomWidgetsPanel(overrideManager: manager),
          tier: LicenseTier.pro,
        ),
      );
      await _pumpFrames(tester);

      final errorRow = find.byKey(ValueKey('custom_widget_error_$missingPath'));
      expect(errorRow, findsOneWidget);
      // The localized failure message for fileMissing renders in the row.
      expect(
        find.descendant(of: errorRow, matching: find.byType(Text)),
        findsWidgets,
      );

      // Tapping the dismiss (close) icon clears the error from the panel.
      await tester.tap(find.byIcon(Icons.close));
      await _pumpFrames(tester);
      expect(
        find.byKey(ValueKey('custom_widget_error_$missingPath')),
        findsNothing,
      );
      expect(manager.state.errors, isEmpty);
    },
  );

  testWidgets(
    'a watched directory renders a removable row; the watch button invokes '
    'the directory picker',
    (tester) async {
      final watchedDir = Directory('${tempDir.path}/watched')..createSync();
      late final CustomWidgetBundleManager manager;
      await tester.runAsync(() async {
        manager = await _makeManager(tempDir: tempDir);
      });
      addTearDown(manager.dispose);

      await tester.pumpWidget(
        _wrap(
          child: CustomWidgetsPanel(
            overrideManager: manager,
            overrideDirectoryPicker: (_) async => watchedDir.path,
          ),
          tier: LicenseTier.pro,
        ),
      );
      await _pumpFrames(tester);

      // Tap the "watch directory" button → the override picker returns a
      // path → the manager registers and persists the watched directory.
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.folder_special));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await _pumpFrames(tester);

      final watchedRow = find.byKey(
        ValueKey('custom_widget_watched_${watchedDir.path}'),
      );
      expect(watchedRow, findsOneWidget);
      expect(find.text(watchedDir.path), findsOneWidget);

      // The remove (visibility_off) icon unwatches the directory.
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.visibility_off_outlined));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await _pumpFrames(tester);
      expect(
        find.byKey(ValueKey('custom_widget_watched_${watchedDir.path}')),
        findsNothing,
      );
    },
  );

  testWidgets('a loaded bundle row remove button unregisters the bundle', (
    tester,
  ) async {
    final bundlePath = '${tempDir.path}/removable.wcrux-widget';
    late final CustomWidgetBundleManager manager;
    await tester.runAsync(() async {
      await writeSampleBundle(
        path: bundlePath,
        manifest: sampleManifest(
          id: 'com.acme.removable',
          displayName: 'Removable',
        ),
      );
      manager = await _makeManager(
        tempDir: tempDir,
        preloadedBundlePath: bundlePath,
      );
    });
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      _wrap(
        child: CustomWidgetsPanel(overrideManager: manager),
        tier: LicenseTier.pro,
      ),
    );
    await _pumpFrames(tester);
    expect(find.text('Removable'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.delete_outline));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await _pumpFrames(tester);
    expect(find.text('Removable'), findsNothing);
    expect(manager.state.loadedBundles, isEmpty);
  });

  testWidgets('Load button no-op when the picker is cancelled (returns null)', (
    tester,
  ) async {
    late final CustomWidgetBundleManager manager;
    await tester.runAsync(() async {
      manager = await _makeManager(tempDir: tempDir);
    });
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      _wrap(
        child: CustomWidgetsPanel(
          overrideManager: manager,
          overridePicker: (_) async => null,
        ),
        tier: LicenseTier.pro,
      ),
    );
    await _pumpFrames(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.folder_open));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await _pumpFrames(tester);
    // Nothing loaded; empty-state hint still present.
    expect(manager.state.loadedBundles, isEmpty);
  });

  testWidgets('each WidgetBundleFailureKind maps to a distinct localized error '
      'message in the error rows', (tester) async {
    // Build a manager whose reader throws a chosen failure kind, then load
    // a path per kind so the panel renders one error row per kind. This
    // exercises the _localizedFailureMessage switch across all arms.
    const kinds = WidgetBundleFailureKind.values;
    late final CustomWidgetBundleManager manager;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = CustomWidgetBundleStore(prefs: prefs);
      var index = 0;
      manager = CustomWidgetBundleManager(
        registry: LiveCustomStageWidgetRegistry(),
        store: store,
        reader: WidgetBundleReader(
          // The fileReader runs before any archive parsing; throwing here
          // surfaces the chosen kind through the manager's typed-exception
          // path. We cycle through the kinds in load order.
          fileReader: (path) async {
            final kind = kinds[index++ % kinds.length];
            throw WidgetBundleException(
              kind: kind,
              diagnostic: 'synthetic $kind',
              bundlePath: path,
            );
          },
        ),
      );
      await manager.initialize();
      for (var i = 0; i < kinds.length; i++) {
        await manager.loadBundle('/synthetic/err_$i.wcrux-widget');
      }
    });
    addTearDown(manager.dispose);
    expect(manager.state.errors, hasLength(kinds.length));

    await tester.pumpWidget(
      _wrap(
        child: CustomWidgetsPanel(overrideManager: manager),
        tier: LicenseTier.pro,
      ),
    );
    await _pumpFrames(tester);

    // Every error path produced a dismissible error row.
    for (var i = 0; i < kinds.length; i++) {
      expect(
        find.byKey(
          ValueKey('custom_widget_error_/synthetic/err_$i.wcrux-widget'),
        ),
        findsOneWidget,
        reason: 'missing row for ${kinds[i]}',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
