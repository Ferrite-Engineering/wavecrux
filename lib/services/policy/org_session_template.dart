// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Applying the organization's session template — the other half
/// `org_theme_and_templates` deliberately left out.
///
/// ### One moment, and only one
///
/// A template seeds a **new** session. It never touches an open one, and it
/// never applies over a session the user opened from a file: somebody who
/// double-clicked a `.wavecrux` wants *that* session, and a template landing on
/// top would be the feature destroying the thing the user asked for.
///
/// ### The source file is dropped, always
///
/// A `.wavecrux` document records the waveform it was saved against. A template
/// is a **layout**, not a pointer to somebody's capture — an org template
/// carrying `/home/alice/dump.vcd` would have every engineer's fresh session
/// trying to open Alice's file, which is at best a missing-file error and at
/// worst somebody else's data. The path is stripped on the way in, and that is
/// not a sanitisation nicety: it is what makes the same document usable by a
/// hundred people.
///
/// What a template legitimately carries is what a team standardises on — the
/// arranged signal list, cursor and marker placement, zoom, and which panels
/// are open.
library;

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/services/session/session_service.dart';

/// A template that loaded, or the reason one did not.
@immutable
final class OrgSessionTemplate {
  /// Creates an [OrgSessionTemplate].
  const OrgSessionTemplate({this.state, this.problem});

  /// The organization configured none.
  static const OrgSessionTemplate none = OrgSessionTemplate();

  /// The seed state, with its source file stripped.
  final SessionState? state;

  /// Why there is none, when one was configured. A path, never a value.
  final String? problem;

  /// Whether a template is available to seed a new session.
  bool get isAvailable => state != null;
}

/// Decodes [document] as a session template.
///
/// [SessionService.decodeDocument] is reused rather than a second parser
/// written, for the reason its own doc comment gives: parsing a `.wavecrux` a
/// second way is how one copy comes to disagree with the other about a field.
OrgSessionTemplate decodeOrgSessionTemplate(
  String document, {
  required String diagnosticName,
  SessionService service = const SessionService(),
}) {
  try {
    final decoded = service.decodeDocument(
      document,
      diagnosticName: diagnosticName,
    );
    return OrgSessionTemplate(state: stripSourceFile(decoded));
  } on Object catch (error) {
    return OrgSessionTemplate(
      problem: '$diagnosticName is not a usable session template: $error',
    );
  }
}

/// Removes the waveform the template was saved against.
///
/// See the library doc: a template is a layout, and a layout that names
/// somebody's capture is a layout only that person can use.
SessionState stripSourceFile(SessionState state) =>
    state.copyWith(sourceFilePath: null);
