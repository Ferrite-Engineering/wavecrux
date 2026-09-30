// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/editor_host_capability.dart';
import 'package:wavecrux/domain/enums/editor_host_kind.dart';
import 'package:wavecrux/services/host_bridge/capability_nudge_provider.dart';
import 'package:wavecrux/services/host_bridge/editor_host_provider.dart';
import 'package:wavecrux/services/host_bridge/editor_host_session_provider.dart';

/// A container in the state the rules below are about: hosted by an editor,
/// and told whether this installation had opened a file before.
ProviderContainer _container({
  EditorHostKind hostKind = EditorHostKind.vscode,
  bool openedFileBefore = true,
}) {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(editorHostKindProvider.notifier).set(hostKind);
  container
      .read(editorHostSessionProvider.notifier)
      .set(EditorHostSession(openedFileBefore: openedFileBefore));
  return container;
}

const Duration _slow = Duration(seconds: 8);
const Duration _quick = Duration(milliseconds: 400);

void main() {
  // The nudge policy, verbatim: at most one nudge per session,
  // dismissible, and never on the first file the user opens.
  group('mayRaiseCapabilityNudge', () {
    test('permits a nudge under an editor host, after the first file', () {
      expect(
        mayRaiseCapabilityNudge(
          hostKind: EditorHostKind.vscode,
          openedFileBefore: true,
          alreadyNudgedThisSession: false,
        ),
        isTrue,
      );
    });

    test('refuses when nothing is hosting us', () {
      // The sentences describe an editor panel. A desktop window has other
      // limitations, or none, and saying otherwise would be false.
      expect(
        mayRaiseCapabilityNudge(
          hostKind: EditorHostKind.none,
          openedFileBefore: true,
          alreadyNudgedThisSession: false,
        ),
        isFalse,
      );
    });

    test('refuses on the first file this installation has opened', () {
      expect(
        mayRaiseCapabilityNudge(
          hostKind: EditorHostKind.vscode,
          openedFileBefore: false,
          alreadyNudgedThisSession: false,
        ),
        isFalse,
      );
    });

    test('refuses once the session has spent its one nudge', () {
      expect(
        mayRaiseCapabilityNudge(
          hostKind: EditorHostKind.vscode,
          openedFileBefore: true,
          alreadyNudgedThisSession: true,
        ),
        isFalse,
      );
    });
  });

  group('CapabilityNudgeNotifier.offerSlowParse', () {
    test('raises the slow-parse nudge, carrying the measured duration', () {
      final container = _container();
      final notifier = container.read(capabilityNudgeProvider.notifier);

      expect(notifier.offerSlowParse(_slow), isTrue);
      final nudge = container.read(capabilityNudgeProvider);
      expect(nudge?.capability, EditorHostCapability.slowParse);
      // The value the user reads is the value that was measured — not a
      // bucket, not the threshold.
      expect(nudge?.parseDuration, _slow);
    });

    test('a parse under the threshold raises nothing', () {
      final container = _container();
      expect(
        container.read(capabilityNudgeProvider.notifier).offerSlowParse(_quick),
        isFalse,
      );
      expect(container.read(capabilityNudgeProvider), isNull);
    });

    test('the threshold itself is inclusive', () {
      final container = _container();
      expect(
        container
            .read(capabilityNudgeProvider.notifier)
            .offerSlowParse(kEditorHostSlowParseThreshold),
        isTrue,
      );
    });

    test('NEVER on the first file of an installation', () {
      // The rule the plan states most emphatically: "the first experience
      // must be the product working".
      final container = _container(openedFileBefore: false);
      expect(
        container.read(capabilityNudgeProvider.notifier).offerSlowParse(_slow),
        isFalse,
      );
      expect(container.read(capabilityNudgeProvider), isNull);
    });

    test('an absent host-session frame is treated as the first file', () {
      // No `crux.host_session` ever arrived — an older extension, a dropped
      // message, or a plain browser tab. The default is conservative in the
      // direction that matters: silence, not a nudge on the worst occasion.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(editorHostKindProvider.notifier)
          .set(EditorHostKind.vscode);
      expect(
        container.read(editorHostSessionProvider),
        EditorHostSession.unknown,
      );
      expect(
        container.read(capabilityNudgeProvider.notifier).offerSlowParse(_slow),
        isFalse,
      );
    });

    test('nothing is raised when no editor is hosting us', () {
      final container = _container(hostKind: EditorHostKind.none);
      expect(
        container.read(capabilityNudgeProvider.notifier).offerSlowParse(_slow),
        isFalse,
      );
    });

    test('at most ONE nudge per session, however many slow parses', () {
      final container = _container();
      final notifier = container.read(capabilityNudgeProvider.notifier);

      expect(notifier.offerSlowParse(_slow), isTrue);
      expect(notifier.offerSlowParse(_slow), isFalse);
      expect(notifier.offerSlowParse(const Duration(minutes: 2)), isFalse);
      expect(notifier.hasRaisedThisSession, isTrue);
    });

    test('dismissing does not re-arm the session', () {
      // "At most one per session" must not decay into "one at a time".
      final container = _container();
      final notifier = container.read(capabilityNudgeProvider.notifier);

      expect(notifier.offerSlowParse(_slow), isTrue);
      notifier.dismiss();
      expect(container.read(capabilityNudgeProvider), isNull);
      expect(notifier.offerSlowParse(_slow), isFalse);
      expect(container.read(capabilityNudgeProvider), isNull);
    });

    test('dismissing with nothing showing is a no-op', () {
      final container = _container();
      final notifier = container.read(capabilityNudgeProvider.notifier)
        ..dismiss();
      expect(container.read(capabilityNudgeProvider), isNull);
      // Still armed: a dismissal of nothing has not spent anything.
      expect(notifier.hasRaisedThisSession, isFalse);
      expect(notifier.offerSlowParse(_slow), isTrue);
    });
  });

  group('EditorHostSession', () {
    test('defaults to "this may be the first file"', () {
      expect(EditorHostSession.unknown.openedFileBefore, isFalse);
    });

    test('set is idempotent and value-compared', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // The host re-posts the frame after a context release, with the same
      // value; that must not be a state change every tab rebuilds for.
      container
          .read(editorHostSessionProvider.notifier)
          .set(const EditorHostSession(openedFileBefore: true));
      final first = container.read(editorHostSessionProvider);
      container
          .read(editorHostSessionProvider.notifier)
          .set(const EditorHostSession(openedFileBefore: true));
      expect(
        identical(container.read(editorHostSessionProvider), first),
        isTrue,
      );
    });
  });
}
