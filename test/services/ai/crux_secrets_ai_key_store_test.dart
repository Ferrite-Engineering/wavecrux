// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// WaveCrux's BYO AI key moved off a hand-rolled `flutter_secure_storage`
// wrapper onto the suite's shared `crux_secrets`. The per-provider namespacing
// is the behaviour that had to survive that move, so it is asserted here
// explicitly rather than left implied by the implementation.

import 'package:crux_secrets/crux_secrets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/ai_provider.dart';
import 'package:wavecrux/services/ai/crux_secrets_ai_key_store.dart';

void main() {
  late InMemoryCruxSecretStore secrets;
  late CruxSecretsAiKeyStore store;

  setUp(() {
    secrets = InMemoryCruxSecretStore();
    store = CruxSecretsAiKeyStore(secrets: secrets);
  });

  group('per-provider namespacing', () {
    test('each provider renders its own distinct storage key', () {
      final keys = <String>{
        for (final p in AiProvider.values)
          CruxSecretsAiKeyStore.keyFor(p).storageKey,
      };
      expect(keys.length, AiProvider.values.length);
    });

    test('the rendered key is crux.wavecrux.ai_api_key_<provider>', () {
      expect(
        CruxSecretsAiKeyStore.keyFor(AiProvider.anthropic).storageKey,
        'crux.wavecrux.ai_api_key_anthropic',
      );
      expect(
        CruxSecretsAiKeyStore.keyFor(AiProvider.openai).storageKey,
        'crux.wavecrux.ai_api_key_openai',
      );
      expect(
        CruxSecretsAiKeyStore.keyFor(AiProvider.google).storageKey,
        'crux.wavecrux.ai_api_key_google',
      );
      expect(
        CruxSecretsAiKeyStore.keyFor(AiProvider.ollama).storageKey,
        'crux.wavecrux.ai_api_key_ollama',
      );
    });

    test('every key sits under the shared crux.wavecrux. prefix', () {
      // So `deleteAll('wavecrux')` reaches them, and so they can never collide
      // with another crux product's credentials in the same OS keychain.
      final prefix = CruxSecretKey.prefixFor(CruxSecretsAiKeyStore.product);
      for (final p in AiProvider.values) {
        expect(
          CruxSecretsAiKeyStore.keyFor(p).storageKey,
          startsWith(prefix),
        );
      }
    });

    test('writing one provider never disturbs another', () async {
      await store.writeKey(AiProvider.anthropic, 'anthropic-key');
      await store.writeKey(AiProvider.openai, 'openai-key');

      expect(await store.readKey(AiProvider.anthropic), 'anthropic-key');
      expect(await store.readKey(AiProvider.openai), 'openai-key');

      await store.deleteKey(AiProvider.anthropic);

      expect(await store.readKey(AiProvider.anthropic), isNull);
      expect(await store.readKey(AiProvider.openai), 'openai-key');
    });
  });

  group('store contract', () {
    test('readKey returns null when nothing is stored', () async {
      expect(await store.readKey(AiProvider.google), isNull);
    });

    test('writeKey round-trips', () async {
      await store.writeKey(AiProvider.google, 'sk-xyz');
      expect(await store.readKey(AiProvider.google), 'sk-xyz');
    });

    test('writing an empty key deletes rather than storing ""', () async {
      // Otherwise every `!= null` check downstream reads a blanked field as
      // "still configured".
      await store.writeKey(AiProvider.anthropic, 'sk-abc');
      await store.writeKey(AiProvider.anthropic, '');

      expect(await store.readKey(AiProvider.anthropic), isNull);
      expect(secrets.storedKeys, isEmpty);
    });

    test('deleteKey on an absent provider succeeds silently', () async {
      await expectLater(store.deleteKey(AiProvider.ollama), completes);
    });
  });

  test('the shared default keeps macOS off the data-protection keychain', () {
    // Guards that move itself. The plugin's own default for this flag is
    // `true`, which needs a `keychain-access-groups` entitlement and a real
    // signing certificate — so an ad-hoc-signed CI or contributor build
    // silently loses the stored key. WaveCrux learned that the hard way and
    // the knowledge now lives in `crux_secrets`; assert it still holds, since
    // WaveCrux is the product that pays if it regresses.
    expect(
      kCruxDefaultSecureStorage.mOptions.params['usesDataProtectionKeychain'],
      'false',
    );
  });
}
