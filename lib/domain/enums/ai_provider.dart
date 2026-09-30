// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The bring-your-own-key model providers the AI Waveform Assistant can target.
///
/// WaveCrux runs no model — the user supplies their own API key (or points at a
/// local endpoint). Open Core ships the configuration surface; the concrete
/// client that actually talks to each provider lives in the Pro
/// overlay (see `AiModelClient`).
///
/// Persisted by [index] in settings, so the order is **append-only** — never
/// reorder or remove a value without a migration.
enum AiProvider {
  /// Anthropic Claude (the default).
  anthropic,

  /// OpenAI / Azure OpenAI-compatible endpoints.
  openai,

  /// Google Gemini.
  google,

  /// A local Ollama server (no key required; key field may stay empty).
  ollama;

  /// Whether this provider talks to a local endpoint and therefore does not
  /// require an API key.
  bool get isLocal => this == AiProvider.ollama;

  /// A sensible default endpoint to pre-fill when the user has not entered one.
  /// Empty for cloud providers whose endpoint is implied by the client.
  String get defaultEndpoint => switch (this) {
    AiProvider.ollama => 'http://localhost:11434',
    AiProvider.anthropic || AiProvider.openai || AiProvider.google => '',
  };
}
