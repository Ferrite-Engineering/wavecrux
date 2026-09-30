// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_manager.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_store.dart';
import 'package:wavecrux/plugins/custom_stage_widget_registry_provider.dart';

/// Async provider that builds (and asynchronously initializes) the
/// singleton [CustomWidgetBundleManager] for the current app session.
///
/// The provider is `keepAlive` because the manager owns long-lived
/// `dart:io` directory-watch subscriptions; allowing it to be torn down
/// and rebuilt on every UI rebuild would leak file-handle resources on
/// every settings-screen open.
///
/// Tests may override the store and the manager itself via
/// [customWidgetBundleStoreProvider] and [customWidgetBundleManagerProvider].
final customWidgetBundleStoreProvider = FutureProvider<CustomWidgetBundleStore>(
  (ref) async {
    return CustomWidgetBundleStore.load();
  },
);

/// Provider for the live [CustomWidgetBundleManager]. Returns an
/// [AsyncValue] because constructing the manager requires reading
/// platform [SharedPreferences] and validating every persisted bundle.
final customWidgetBundleManagerProvider =
    FutureProvider<CustomWidgetBundleManager>((ref) async {
      // Read before the first await — a `Ref` reached for after an async gap
      // is the recurring defect `lifecycle_ref_use_test` exists to catch.
      final audit = ref.read(cruxAuditRecorderProvider);
      final store = await ref.watch(customWidgetBundleStoreProvider.future);
      final registry = ref.read(customStageWidgetRegistryProvider);
      final manager = CustomWidgetBundleManager(
        registry: registry,
        store: store,
        // `stage.widget.loaded`. Wraps the production registrar rather than
        // replacing it, so `userSupplied: true` stays a decision made in one
        // place. The widget id is authored by whoever wrote the bundle, and it
        // goes in verbatim: this is the organization's record of code loaded on
        // their own machine, and "which third-party widget ran here" is exactly
        // what it is for. Contrast telemetry, which must not carry ids we did
        // not author.
        registerDefinition: (definition) {
          audit.record(
            WaveCruxAuditKinds.stageWidgetLoaded,
            payload: <String, Object?>{
              'widget': definition.id,
              'userSupplied': true,
            },
          );
          registerUserSuppliedDefinition(definition);
        },
      );
      ref.onDispose(manager.dispose);
      await manager.initialize();
      return manager;
    });
