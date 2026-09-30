// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/ai_key_store_provider.dart';
import 'package:wavecrux/domain/enums/ai_provider.dart';
import 'package:wavecrux/domain/interfaces/ai_key_store.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/settings/widgets/ai_settings_section.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/experimental_chip.dart';

class _FakeAppSettingsNotifier extends AppSettingsNotifier {
  _FakeAppSettingsNotifier(this._initial);
  final AppSettings _initial;
  @override
  Future<AppSettings> build() async => _initial;
}

class _FakeKeyStore implements AiKeyStore {
  final Map<AiProvider, String> _keys = {};

  @override
  Future<String?> readKey(AiProvider provider) async => _keys[provider];

  @override
  Future<void> writeKey(AiProvider provider, String key) async {
    if (key.isEmpty) {
      _keys.remove(provider);
    } else {
      _keys[provider] = key;
    }
  }

  @override
  Future<void> deleteKey(AiProvider provider) async => _keys.remove(provider);
}

ProviderContainer _container({
  required bool enabled,
  AppSettings settings = const AppSettings(),
  AiKeyStore? keyStore,
}) {
  final container = ProviderContainer(
    overrides: [
      appSettingsProvider.overrideWith(
        () => _FakeAppSettingsNotifier(settings),
      ),
      aiExperimentalEnabledProvider.overrideWithValue(enabled),
      aiKeyStoreProvider.overrideWithValue(keyStore ?? _FakeKeyStore()),
    ],
  );
  return container;
}

Widget _wrap(
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: const Scaffold(
        body: SizedBox(
          width: 640,
          child: SingleChildScrollView(child: AiSettingsSection()),
        ),
      ),
    ),
  );
}

void main() {
  final toggle = find.byKey(const Key('settingsAiExperimentalToggle'));
  final dropdown = find.byKey(const Key('settingsAiProviderDropdown'));
  final endpoint = find.byKey(const Key('settingsAiEndpointField'));
  final keyField = find.byKey(const Key('settingsAiApiKeyField'));
  final emptyState = find.byKey(const Key('settingsAiNoModelEmptyState'));

  testWidgets('renders the toggle and the Experimental chip always', (
    tester,
  ) async {
    final c = _container(enabled: false);
    addTearDown(c.dispose);
    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    expect(toggle, findsOneWidget);
    expect(find.byType(ExperimentalChip), findsOneWidget);
  });

  testWidgets('toggle OFF hides all provider/endpoint/key configuration', (
    tester,
  ) async {
    final c = _container(enabled: false);
    addTearDown(c.dispose);
    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    expect(dropdown, findsNothing);
    expect(endpoint, findsNothing);
    expect(keyField, findsNothing);
    expect(emptyState, findsNothing);
  });

  testWidgets('toggle ON reveals the configuration + no-model empty state', (
    tester,
  ) async {
    final c = _container(enabled: true);
    addTearDown(c.dispose);
    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    expect(dropdown, findsOneWidget);
    expect(endpoint, findsOneWidget);
    expect(keyField, findsOneWidget);
    // No key entered for the (cloud) Anthropic default → empty state shows.
    expect(emptyState, findsOneWidget);
  });

  testWidgets('a stored key removes the no-model empty state', (tester) async {
    final store = _FakeKeyStore();
    await store.writeKey(AiProvider.anthropic, 'sk-123');
    final c = _container(enabled: true, keyStore: store);
    addTearDown(c.dispose);

    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle(); // lets the async key load settle

    expect(keyField, findsOneWidget);
    expect(emptyState, findsNothing);
  });

  testWidgets('toggle and clear-key controls meet the 44dp touch target', (
    tester,
  ) async {
    final c = _container(enabled: true);
    addTearDown(c.dispose);
    await tester.pumpWidget(_wrap(c));
    await tester.pumpAndSettle();

    final toggleSize = tester.getSize(toggle);
    expect(toggleSize.height, greaterThanOrEqualTo(44));

    final clearSize = tester.getSize(
      find.byKey(const Key('settingsAiApiKeyClear')),
    );
    expect(clearSize.width, greaterThanOrEqualTo(44));
    expect(clearSize.height, greaterThanOrEqualTo(44));
  });

  for (final locale in const [
    Locale('en'),
    Locale('zh', 'CN'),
    Locale('ja'),
    Locale('ko'),
  ]) {
    testWidgets('renders without exception in $locale', (tester) async {
      final c = _container(enabled: true);
      addTearDown(c.dispose);
      await tester.pumpWidget(_wrap(c, locale: locale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
