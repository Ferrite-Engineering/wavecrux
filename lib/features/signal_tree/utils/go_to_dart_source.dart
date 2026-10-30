// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/models/rohd_dart_source.dart';
import 'package:wavecrux/services/remote/cxp/cxp_inbound_handlers.dart';

/// How a Go to Dart Source request ended.
enum GoToDartOutcome {
  /// The editor command ran.
  opened,

  /// No editor command is set in Settings > Editors.
  noEditor,

  /// The editor could not be started; see [GoToDartResult.reason].
  failed,
}

/// The outcome of opening a Dart source, with the launcher's reason on a
/// failure.
class GoToDartResult {
  /// Creates a result.
  const GoToDartResult(this.outcome, [this.reason]);

  /// How it ended.
  final GoToDartOutcome outcome;

  /// Why the editor could not be started, when it could not.
  final String? reason;
}

/// Opens [source] in the editor [editorCommand] names (Settings > Editors), at
/// its line and column, through [runner].
///
/// This is the command and the runner the inbound "open source" request uses,
/// because it is the same user setting. Unlike a peer's request, the path is
/// not checked against the folders the user opened: the user chose this one by
/// clicking it, and the path came from a file beside their own waveform.
Future<GoToDartResult> goToDartSource(
  RohdDartSource source, {
  required String editorCommand,
  required CxpEditorCommandRunner runner,
}) async {
  if (editorCommand.trim().isEmpty) {
    return const GoToDartResult(GoToDartOutcome.noEditor);
  }
  final result = await runner(editorCommand, source.primary.target);
  return result.honored
      ? const GoToDartResult(GoToDartOutcome.opened)
      : GoToDartResult(GoToDartOutcome.failed, result.reason);
}
