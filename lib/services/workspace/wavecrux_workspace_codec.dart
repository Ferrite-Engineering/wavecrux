// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart';
import 'package:wavecrux/domain/models/wavecrux_tab_payload.dart';

/// WaveCrux-specific [WorkspaceCodec] for [WaveCruxTabPayload].
///
/// Serializes [WaveCruxTabPayload]'s `filePath` and `sessionExportPath`
/// directly as top-level keys in the per-tab JSON map. The framework keys
/// (`id`, `displayName`, `paneId`) are emitted by the package, so this
/// codec only handles the payload portion.
///
/// **Graceful handling of corrupt / legacy documents.** Both [payloadToJson]
/// and [payloadFromJson] accept any JSON-natural input without raising.
/// Unknown extra keys are silently ignored for forward compatibility, and
/// wrong-typed values (e.g. a numeric `filePath`) fall through to `null`
/// rather than throwing. A legacy `workspace.json` written by an older
/// build is therefore loaded as a workspace with empty payloads rather than
/// crashing the app; structural violations (missing `id` / `paneId`,
/// duplicate ids, dangling pane references) still raise inside the
/// framework, where `WorkspaceService.load` catches them and falls back to
/// `Workspace.empty()`.
///
/// Stateless — instantiate once per app and reuse.
class WaveCruxWorkspaceCodec extends WorkspaceCodec<WaveCruxTabPayload> {
  /// Creates a codec.
  const WaveCruxWorkspaceCodec();

  /// Payload-internal schema version. Bumped when [WaveCruxTabPayload]
  /// gains a non-backward-compatible field; the framework-level
  /// `kWorkspaceSchemaVersion` is independent.
  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(WaveCruxTabPayload payload) => {
    if (payload.filePath != null) 'filePath': payload.filePath,
    if (payload.sessionFilePath != null)
      'sessionFilePath': payload.sessionFilePath,
    if (payload.sessionExportPath != null)
      'sessionExportPath': payload.sessionExportPath,
    if (payload.isDetached) 'isDetached': true,
  };

  @override
  WaveCruxTabPayload payloadFromJson(Map<String, Object?> json) {
    final filePath = json['filePath'];
    final sessionFilePath = json['sessionFilePath'];
    final sessionExportPath = json['sessionExportPath'];
    final isDetached = json['isDetached'];
    return WaveCruxTabPayload(
      filePath: filePath is String ? filePath : null,
      sessionFilePath: sessionFilePath is String ? sessionFilePath : null,
      sessionExportPath: sessionExportPath is String ? sessionExportPath : null,
      isDetached: isDetached is bool && isDetached,
    );
  }

  @override
  String displayNameFor(WaveCruxTabPayload payload) {
    final path = payload.filePath;
    if (path == null || path.isEmpty) return 'Untitled';
    final separatorIndex = path.lastIndexOf(RegExp(r'[/\\]'));
    return separatorIndex == -1 ? path : path.substring(separatorIndex + 1);
  }
}
