// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/interfaces/ai_key_store.dart';
import 'package:wavecrux/services/ai/crux_secrets_ai_key_store.dart';

/// The active [AiKeyStore] — the suite's shared secret store by default.
///
/// The Settings → AI panel reads/writes the user's BYO API key through this
/// provider. Tests override it with an in-memory fake so the secure-storage
/// platform channel is never touched. The store is intentionally open-core: it
/// holds the *user's own* credential, not any WaveCrux license-key material
/// (which is forbidden in open-core and lives in the Pro overlay).
final aiKeyStoreProvider = Provider<AiKeyStore>(
  (_) => const CruxSecretsAiKeyStore(),
);
