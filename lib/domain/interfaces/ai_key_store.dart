// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/ai_provider.dart';

/// Secure, per-provider storage for the user's bring-your-own AI API keys.
///
/// Keys are sensitive credentials and are kept in **platform secure storage**
/// (Keychain / Keystore / libsecret / DPAPI) — never in `shared_preferences`,
/// never written to a session file, never logged. The non-secret AI
/// configuration (selected provider, endpoint) lives in `AppSettings`; only the
/// key itself routes through this store.
///
/// Keys are scoped per [AiProvider] so switching providers in the Settings → AI
/// panel preserves each provider's key independently.
abstract class AiKeyStore {
  /// Persists [key] for [provider]. An empty [key] deletes the stored key
  /// (equivalent to [deleteKey]) so clearing the field clears the secret.
  Future<void> writeKey(AiProvider provider, String key);

  /// Returns the stored key for [provider], or `null` if none is set.
  Future<String?> readKey(AiProvider provider);

  /// Removes any stored key for [provider]. A no-op when none is set.
  Future<void> deleteKey(AiProvider provider);
}
