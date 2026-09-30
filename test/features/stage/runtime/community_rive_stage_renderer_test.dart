// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/features/stage/runtime/community_rive_stage_renderer.dart';
import 'package:wavecrux/features/stage/sdk/manifest/localized_string.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_enums.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_signal_binding.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

const _manifest = StageWidgetManifest(
  id: 'com.acme.gauge',
  version: '1.0.0',
  displayName: LocalizedString.single('Community Gauge'),
  category: StageWidgetCategory.instrument,
  runtime: ManifestRuntime.rive,
  runtimeAssetPath: 'runtime/gauge.riv',
  requiredApiVersion: 1,
  signalBindings: [
    ManifestSignalBinding(
      name: 'value',
      description: 'gauge value',
      signalType: SignalType.vector,
    ),
  ],
);

const _instance = StageInstance(
  id: 'i_community',
  widgetId: 'com.acme.gauge',
  signalBindings: {'value': StageSignalBinding(signalRef: 'top.value')},
);

Widget _wrap({required Widget child, Locale locale = const Locale('en')}) {
  return ProviderScope(
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: SizedBox(width: 320, height: 220, child: child),
      ),
    ),
  );
}

void main() {
  // The live-render path (artboard mount + animation) requires the
  // rive_native FFI runtime, which is unavailable in headless `flutter test`
  // (RiveNative.init cannot resolve its `init` symbol). That coverage lives
  // in integration_test + the manual verification pass (Open Core §10).
  //
  // These headless tests deliberately feed an EMPTY `.riv` buffer, which the
  // bytes-decoder rejects with `assetMissing` BEFORE it ever calls
  // RiveNative.init — so the localized "Widget failed to load" placeholder is
  // exercised across every locale without engaging the native runtime.
  group('CommunityRiveStageRenderer — failure-placeholder locale sweep', () {
    const locales = [
      Locale('en'),
      Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
      Locale('ja'),
      Locale('ko'),
    ];

    for (final locale in locales) {
      testWidgets('empty .riv → localized failure placeholder in $locale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            locale: locale,
            child: CommunityRiveStageRenderer(
              instance: _instance,
              manifest: _manifest,
              riveBytes: Uint8List(0),
            ),
          ),
        );
        // Drain the async init: empty bytes resolve to the assetMissing
        // placeholder. The pump must not throw on any locale.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
        // The failure placeholder headline renders.
        final l10n = await L10N.delegate.load(locale);
        expect(find.text(l10n.customStageWidgetLoadFailed), findsOneWidget);
      });
    }
  });
}
