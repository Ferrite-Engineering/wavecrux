// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/interfaces/ai_model_client.dart';
import 'package:wavecrux/services/ai/noop_ai_model_client.dart';

/// Open-core extension point exposing the active [AiModelClient].
///
/// The open-core default is a singleton [NoopAiModelClient] that reports
/// [AiUnavailableReason.notConfigured]. The closed-source Pro
/// overlay overrides this binding with a concrete multi-provider client
/// (Anthropic / OpenAI / Google / local Ollama) driven by the user's
/// bring-your-own-key configuration.
///
/// The AI Waveform Assistant ships **Experimental** during the public beta
/// (gated by `kAiExperimental` + an off-by-default Settings → AI toggle); this
/// seam is the model-transport half of it. See `docs/ARCHITECTURE.md` §10.
final aiModelClientProvider = Provider<AiModelClient>(
  (_) => const NoopAiModelClient(),
);
