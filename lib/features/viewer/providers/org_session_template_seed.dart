// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Seeding the organization's session template into a tab.
///
/// `org_session_template.dart` decodes one and strips its source file;
/// `org_theme_and_templates.dart` reads the policy reference. Neither hands the
/// result to a tab, which is why the whole feature was inert: an administrator
/// could publish a template, `crux-policy lint` would accept it, and no
/// engineer would ever see it.
///
/// ### The two call sites, and why there are exactly two
///
/// A tab's waveform is loaded in one of two places — `app.dart`'s deferred-load
/// listener for tabs restored on launch, and `viewer_screen_file_io.dart` for
/// tabs the user opens now. They partition the work between them ("deferred-load
/// listener owns this load"), and both have the same shape:
///
/// ```text
/// sidecar exists → sessionProvider.loadFromPath(sidecar)  → return
/// otherwise      → waveformSource.openFile(path)          → SEED HERE
/// ```
///
/// The `else` branch is the definition of a new session, so that is where this
/// is called from. It is not a heuristic about timing: being in that branch is
/// positive proof that nothing is restoring a session over the top.
///
/// ### Why not somewhere more central
///
/// Two seams were tried first and both were wrong, recorded here so the third
/// person does not try them again:
///
/// * **`workspace_provider.dart`**, where `openFile` and `openSession` already
///   distinguish the two cases perfectly. Importing the session providers there
///   makes the root `workspaceProvider` reach the per-tab `timeMapperProvider`,
///   which the per-tab scope-leak guard rejects — correctly. Allowlisting it
///   would blind the guard to the one provider most worth watching.
/// * **A listener on "the waveform finished loading."** It races: a sidecar
///   restore opens the waveform *inside* `loadFromPath`, before that method
///   sets the session path, so the listener cannot tell a fresh open from a
///   restore in flight. It would seed a template over the session the user is
///   in the middle of restoring — the exact thing
///   `org_session_template.dart` says must never happen.
///
/// ### Why this lives under `features/`, not `services/policy/`
///
/// Its siblings do: `org_session_template.dart` decodes, `org_share_resource`
/// reads, `org_theme_and_templates` resolves the policy reference — all pure,
/// all under `services/`. This one drives `sessionProvider`, and the §6.2
/// import-layering guard rejects a `services/` file importing `features/`.
///
/// That rejection is correct and the fix was to move, not to allowlist. The
/// precedent is `applyOrgSignalGroups`: the pure resolution lives in
/// `services/policy/org_signal_groups.dart` and the application happens in
/// `features/viewer/providers/signal_group_providers.dart`. Same split, same
/// reason — policy *resolution* is a service, policy *application* is whatever
/// layer owns the thing being changed.
///
/// ### Why it seeds after the waveform, not before
///
/// A template's `sourceFilePath` is stripped on the way in, by design. Seeding
/// before a waveform exists would leave every signal reference unresolved
/// against a backend that is not there yet, and the layout would be inert. The
/// restore path re-resolves refs against the *active* source, so the waveform
/// has to be open first.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/services/policy/org_session_template.dart';
import 'package:wavecrux/services/policy/org_share_resource.dart';
import 'package:wavecrux/services/policy/org_theme_and_templates.dart';

/// A template the organization set and the user did not get. `developer.log`
/// emits nothing from a release build, so this goes to the product log.
final _log = Logger('wavecrux.policy');

/// What happened when a tab asked for the organization's session template.
@immutable
final class OrgSessionTemplateOutcome {
  /// Creates an [OrgSessionTemplateOutcome].
  const OrgSessionTemplateOutcome({required this.seeded, this.problem});

  /// The organization configured none — every default install.
  static const OrgSessionTemplateOutcome none = OrgSessionTemplateOutcome(
    seeded: false,
  );

  /// Whether a template was decoded and replayed into the tab.
  final bool seeded;

  /// Why it did not seed, when one was configured. A path, never a value.
  final String? problem;
}

/// Seeds the organization's session template into [tab].
///
/// [tab] is that tab's own [ProviderContainer] — the callers already hold one,
/// and taking it explicitly is what keeps this off the root container and out
/// of the scope-leak guard's way.
///
/// Returns [OrgSessionTemplateOutcome.none] when no policy file names a
/// template, so a default install opens exactly the empty session it always
/// did.
///
/// **Never throws.** This runs immediately after a waveform opened
/// successfully, and a template is a convenience: an unreachable share must
/// leave the engineer with a working tab, not an error where their waveform
/// should be. Failures are returned so the caller can log them, and every
/// caller does — an organization that published a template and finds half the
/// team without it needs the application to have said why.
Future<OrgSessionTemplateOutcome> seedOrgSessionTemplate(
  ProviderContainer tab,
) async {
  final reference = tab.read(orgSessionTemplateProvider);
  if (reference == null) return OrgSessionTemplateOutcome.none;

  final load = loadOrgShareResource(reference.resource);
  if (!load.isOk) {
    return OrgSessionTemplateOutcome(seeded: false, problem: load.detail);
  }

  // Re-encoded because the two halves of this feature never composed: the
  // share loader parses to a Map, and the template decoder takes the raw
  // document so it can own the "is this even JSON" diagnostic. Nothing called
  // both until now, so the mismatch had never surfaced. Bridged here rather
  // than by widening `SessionService.decodeDocument` for one caller — the
  // round trip is on a small file read once per tab open, and it keeps the
  // decoder's error messages the ones a person actually sees.
  final template = decodeOrgSessionTemplate(
    jsonEncode(load.contents),
    diagnosticName: reference.resource.path,
  );
  if (template.problem case final problem?) {
    return OrgSessionTemplateOutcome(seeded: false, problem: problem);
  }
  final state = template.state;
  if (state == null) return OrgSessionTemplateOutcome.none;

  // `restoreFromState`, not `loadFromPath`: it replays the layout without
  // touching the tab's session file path or the recent-files list. A seeded
  // tab must still be "unsaved" — the template is a starting point, and
  // recording it as the file this tab came from would make the next Save
  // silently target the organization's share.
  await tab.read(sessionProvider.notifier).restoreFromState(state);
  return const OrgSessionTemplateOutcome(seeded: true);
}

/// Seeds and logs, for the two call sites that want exactly that.
///
/// Kept beside the function it wraps rather than copied into both callers,
/// because "log the problem" is the half most likely to be dropped in one of
/// them and never noticed — the feature would still work for everybody whose
/// share is reachable, which is everybody who tests it.
Future<void> seedOrgSessionTemplateLogging(ProviderContainer tab) async {
  final outcome = await seedOrgSessionTemplate(tab);
  if (outcome.problem case final problem?) {
    _log.warning('Organization session template not applied: $problem');
  }
}
