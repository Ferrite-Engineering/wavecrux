// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_secrets/crux_secrets.dart';
import 'package:wavecrux/domain/enums/ai_provider.dart';
import 'package:wavecrux/domain/interfaces/ai_key_store.dart';

/// [AiKeyStore] backed by the suite's shared [CruxSecretStore].
///
/// Replaces the retired `SecureStorageAiKeyStore`, which wrapped
/// `flutter_secure_storage` directly — a local re-implementation of exactly
/// what `crux_secrets` exists to provide, on a credential surface, which the
/// suite forbids: a credential surface is shared infrastructure, never an
/// app-local copy. The macOS keychain configuration that
/// class had learned the hard way now lives in `crux_secrets` as
/// `kCruxDefaultSecureStorage`, where all four products get it instead of
/// only this one.
///
/// What stays WaveCrux's is the [AiProvider]-typed interface: which providers
/// exist is product domain, not shared infrastructure.
///
/// ### Per-provider namespacing
///
/// Each provider keeps its own credential under its own key, so configuring
/// Anthropic never disturbs a stored OpenAI key. The rendered keys are
/// `crux.wavecrux.ai_api_key_<provider>`, from [CruxSecretKey]'s
/// `crux.<product>.<name>` scheme.
///
/// **This is not the key the retired store used.** It wrote
/// `wavecrux.ai.apiKey.<provider>`, which [CruxSecretKey] cannot render — it
/// restricts both halves to `[a-z0-9_]` because the key reaches platform
/// credential APIs whose escaping rules differ. There is deliberately no
/// migration: a key stored by an earlier build is orphaned in the keychain and
/// the user re-enters it once in Settings → AI. Writing a migration would
/// mean keeping a direct `flutter_secure_storage` dependency alive to read the
/// old key — reinstating the violation being closed — to rescue a credential
/// that only exists on builds where the experimental AI assistant was
/// explicitly switched on.
///
/// The plaintext key is held only transiently while reading/writing — it is
/// never copied into `AppSettings`, a session document, or a log line.
class CruxSecretsAiKeyStore implements AiKeyStore {
  /// Creates a store over [secrets], defaulting to the real platform-backed
  /// implementation. Inject [InMemoryCruxSecretStore] in tests so the
  /// developer's own keychain is never touched.
  const CruxSecretsAiKeyStore({
    CruxSecretStore secrets = const FlutterSecureStorageSecretStore(),
  }) : _secrets = secrets;

  final CruxSecretStore _secrets;

  /// The `product` half of every key this store writes.
  static const String product = 'wavecrux';

  /// Prefix of the `name` half, so the AI keys are distinguishable from any
  /// other WaveCrux secret sharing the `crux.wavecrux.` namespace.
  static const String namePrefix = 'ai_api_key_';

  /// The namespaced key for [provider]. Exposed so a test can assert the
  /// namespacing without reaching into the backing store.
  static CruxSecretKey keyFor(AiProvider provider) =>
      CruxSecretKey(product: product, name: '$namePrefix${provider.name}');

  @override
  // `write` with an empty value deletes rather than storing "" — the
  // `CruxSecretStore` contract, and the same behaviour the retired store
  // implemented by hand.
  Future<void> writeKey(AiProvider provider, String key) =>
      _secrets.write(keyFor(provider), key);

  @override
  Future<String?> readKey(AiProvider provider) =>
      _secrets.read(keyFor(provider));

  @override
  Future<void> deleteKey(AiProvider provider) =>
      _secrets.delete(keyFor(provider));
}
