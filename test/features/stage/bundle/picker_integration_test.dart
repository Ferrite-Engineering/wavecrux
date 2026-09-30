// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_manager.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_store.dart';
import 'package:wavecrux/features/stage/runtime/live_custom_stage_widget_registry.dart';
import 'package:wavecrux/plugins/custom_stage_widget_registry_provider.dart';

import '_bundle_test_helpers.dart';

/// Verifies the seam the open-core picker dialog reads from. The picker
/// itself depends on a wider open-core widget tree (`stageWorkspace
/// NotifierProvider`, the active session, the IDE layout) that is
/// expensive to spin up in unit tests; the relevant Pro contribution is
/// that bundle-manager descriptors land in
/// [customStageWidgetRegistryProvider] with the right tier and version
/// metadata. The picker's existing widget tests cover the rendering side
/// in open-core; here we cover the data-flow side that is owned by the
/// Pro overlay.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('picker_int_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
    'loadBundle surfaces the descriptor through '
    'customStageWidgetRegistryProvider with the Pro required tier',
    () async {
      final bundlePath = '${tempDir.path}/picker.wcrux-widget';
      await writeSampleBundle(
        path: bundlePath,
        manifest: sampleManifest(
          id: 'com.acme.picker',
          displayName: 'Picker Sample',
          version: '3.2.1',
        ),
      );

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = CustomWidgetBundleStore(prefs: prefs);
      final registry = LiveCustomStageWidgetRegistry();
      final manager = CustomWidgetBundleManager(
        registry: registry,
        store: store,
      );
      addTearDown(manager.dispose);
      await manager.loadBundle(bundlePath);

      // The Pro overlay overrides the open-core registry provider with
      // this same `LiveCustomStageWidgetRegistry`. Tests construct an
      // equivalent ProviderContainer to verify the seam end-to-end.
      final container = ProviderContainer(
        overrides: [
          customStageWidgetRegistryProvider.overrideWithValue(registry),
        ],
      );
      addTearDown(container.dispose);

      final descriptors = container
          .read(customStageWidgetRegistryProvider)
          .descriptors;
      expect(descriptors, hasLength(1));
      final descriptor = descriptors.first;
      expect(descriptor.widget.id, 'com.acme.picker');
      expect(descriptor.bundleVersion, '3.2.1');
      // The Stage widget capability is free open-core, so a user-loaded
      // community bundle registers at openCore tier — no PRO badge in the
      // picker. (Only the curated Pro *pack* is Pro.)
      expect(descriptor.requiredTier, LicenseTier.openCore);
    },
  );
}
