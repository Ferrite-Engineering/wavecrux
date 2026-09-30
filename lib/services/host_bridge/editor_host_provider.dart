// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';

part 'editor_host_provider.g.dart';

/// Which editor host, if any, is driving this build.
///
/// Defaults to [EditorHostKind.none] — "not hosted" — so every platform that
/// has no bridge at all (desktop, mobile, a plain browser tab) reports honestly
/// without wiring anything. The host bridge's web implementation calls
/// [EditorHostKindNotifier.set] during bootstrap when it finds an extension host
/// on the other end.
///
/// **The bridge must set this before the first telemetry flush**, and can:
/// the marker it reads is placed by the extension's `index.html` shim before
/// `main.dart.js` executes, so the answer is available synchronously at
/// startup. That is the contract that lets `telemetryFormFactorFor` treat the
/// editor-host answer as non-deferring, exactly as it treats `kIsWeb`.
///
/// Contrast `displaySizeProvider`, which genuinely cannot answer until the
/// first frame and therefore makes telemetry defer. This one has no such race,
/// so making it defer would cost a flush for a question that is already
/// answered.
@Riverpod(keepAlive: true)
class EditorHostKindNotifier extends _$EditorHostKindNotifier {
  @override
  EditorHostKind build() => EditorHostKind.none;

  /// Records the editor host driving this build. Idempotent.
  void set(EditorHostKind kind) {
    if (state == kind) return;
    state = kind;
  }
}
