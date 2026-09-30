// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/ai_model_client.dart';

/// Open-core default [AiModelClient]: reports that no model is configured.
///
/// Open Core ships the bring-your-own-key settings UI and the request/response
/// seam, but no concrete provider client — that lives in the closed-source
/// Pro overlay. With this default in place, [isConfigured] is
/// `false` and [send] yields a single terminal
/// [AiClientUnavailable]([AiUnavailableReason.notConfigured]) event so the UI
/// can render its "configure your AI key" empty state. It never throws.
class NoopAiModelClient implements AiModelClient {
  /// Const constructor so the open-core provider returns a singleton.
  const NoopAiModelClient();

  @override
  bool get isConfigured => false;

  @override
  Stream<AiStreamEvent> send(AiRequest request) async* {
    yield const AiClientUnavailable(AiUnavailableReason.notConfigured);
  }
}
