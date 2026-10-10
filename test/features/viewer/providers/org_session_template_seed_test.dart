// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/license/license_resolved_provider.dart';
import 'package:wavecrux/features/viewer/providers/org_session_template_seed.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/services/policy/org_share_resource.dart';
import 'package:wavecrux/services/policy/org_theme_and_templates.dart';

/// Covers the seam that made the session-template feature exist at all.
///
/// The decoder was written, tested and green (`org_apply_test.dart`) while
/// nothing handed its result to a tab. An administrator could publish a
/// template, `crux-policy lint` would accept it, and no engineer would ever
/// see it — the same defect found in three other places across the suite on
/// 2026-08-24, and invisible for the same reason: the unit worked.
///
/// So the last test here is the important one. It asserts the call sites
/// exist, which no amount of testing this function can.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('org-template'));
  tearDown(() => temp.deleteSync(recursive: true));

  ProviderContainer containerFor(OrgResourceRef? reference) {
    final container = ProviderContainer(
      overrides: [orgSessionTemplateProvider.overrideWithValue(reference)],
    );
    addTearDown(container.dispose);
    return container;
  }

  OrgResourceRef refTo(String path) => OrgResourceRef(
    resource: OrgShareResource.parse(path)!,
    locked: false,
  );

  test('no policy file means nothing happens at all', () async {
    // Every default install takes this path, so it is the one that must not
    // touch the tab: an engineer who has never heard of policy files opens
    // exactly the empty session they always did.
    final outcome = await seedOrgSessionTemplate(containerFor(null));
    expect(outcome.seeded, isFalse);
    expect(outcome.problem, isNull);
  });

  test('a template lands, and the tab stays unsaved', () async {
    // The assertion the other five cannot make between them: that the feature
    // WORKS. Everything else here pins how it fails.
    final template = File('${temp.path}/house.wavecrux')
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'version': 1,
          'panels': <String, Object?>{'signalTree': false, 'stageView': true},
        }),
      );

    final container = containerFor(refTo(template.path));
    final outcome = await seedOrgSessionTemplate(container);
    expect(outcome.seeded, isTrue);
    expect(outcome.problem, isNull);

    expect(
      container.read(sessionProvider),
      isNull,
      reason:
          'A seeded tab must still be UNSAVED. `restoreFromState` is used '
          'rather than `loadFromPath` precisely so the tab does not adopt the '
          'organization’s share as its own session file — otherwise the next '
          'Save would silently write back over the team’s template.',
    );
  });

  test('an unreachable share reports, and does not throw', () async {
    // This runs immediately after a waveform opened successfully. Throwing
    // here would replace the engineer's freshly-loaded waveform with an error
    // because a file share was down — trading a working tab for a convenience.
    final missing = '${temp.path}/nobody-mounted-this.wavecrux';

    // Awaited directly rather than wrapped in `returnsNormally`. That matcher
    // is vacuous against an async function: calling one returns a Future
    // without running far enough to throw, so it passes whatever happens
    // afterwards. Awaiting is the only way this test can see a rejection.
    final outcome = await seedOrgSessionTemplate(containerFor(refTo(missing)));
    expect(outcome.seeded, isFalse);
    expect(
      outcome.problem,
      isNotNull,
      reason:
          'A configured-but-unreachable share must be distinguishable from '
          '"no template configured". An organization that published one and '
          'finds half the team without it needs the app to have said why.',
    );
  });

  test(
    'a document that is not a session reports, and does not throw',
    () async {
      final junk =
          File(
            '${temp.path}/not-a-session.wavecrux',
          )..writeAsStringSync(
            jsonEncode({'version': 1, 'panels': 'not-an-object'}),
          );

      final outcome = await seedOrgSessionTemplate(
        containerFor(refTo(junk.path)),
      );
      expect(outcome.seeded, isFalse);
      expect(
        outcome.problem,
        isNotNull,
        reason:
            'A malformed template must degrade to a plain empty session with a '
            'logged reason, never to an exception thrown over a waveform that '
            'has already loaded successfully.',
      );
    },
  );

  test('the problem names the path, never the contents', () async {
    // An org template is a team's layout, and this string ends up in a log
    // an engineer may paste into a ticket. The path is the actionable half;
    // the contents are the part that is nobody else's business.
    final junk = File('${temp.path}/broken.wavecrux')
      ..writeAsStringSync('{"version": 1, "panels": "not-an-object"}');

    final outcome = await seedOrgSessionTemplate(
      containerFor(refTo(junk.path)),
    );
    expect(outcome.problem, contains('broken.wavecrux'));
    expect(
      outcome.problem,
      isNot(contains('not-an-object')),
      reason: 'the document’s contents must not reach the log',
    );
  });

  group('cold start: the tier resolves after the waveform opened', () {
    // Until the keychain answers every launch reads as Open Core, and the
    // template reference is gated on the tier. A seed that read it at once
    // would see "no template" on an Enterprise seat and never look again.
    late File template;
    setUp(() {
      template = File('${temp.path}/house.wavecrux')
        ..writeAsStringSync(
          jsonEncode(<String, Object?>{
            'version': 1,
            'panels': <String, Object?>{'signalTree': false},
          }),
        );
    });

    test('the seed waits for the licence, then applies the template', () async {
      final resolved = Completer<void>();
      var enterprise = false;
      final container = ProviderContainer(
        overrides: [
          licenseResolvedProvider.overrideWith((ref) => resolved.future),
          orgSessionTemplateProvider.overrideWith(
            (ref) => enterprise ? refTo(template.path) : null,
          ),
        ],
      );
      addTearDown(container.dispose);

      final seeding = seedOrgSessionTemplate(container);
      // The keychain answers: the tier moves to Enterprise, then the
      // licence service reports it has resolved.
      await Future<void>.delayed(Duration.zero);
      enterprise = true;
      container.invalidate(orgSessionTemplateProvider);
      resolved.complete();

      final outcome = await seeding;
      expect(outcome.seeded, isTrue);
      expect(outcome.problem, isNull);
    });

    test('a licence that never resolves does not hold the seed', () async {
      final container = ProviderContainer(
        overrides: [
          licenseResolvedProvider.overrideWith(
            (ref) => Completer<void>().future,
          ),
        ],
      );
      addTearDown(container.dispose);
      final sw = Stopwatch()..start();
      await awaitLicenseResolved(
        container,
        timeout: const Duration(milliseconds: 50),
      );
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('open core is resolved from the start', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await expectLater(
        container.read(licenseResolvedProvider.future),
        completes,
      );
    });
  });

  test('both call sites still seed', () {
    // The guard that would have prevented this feature shipping inert, and
    // the only assertion here that a unit test of the function cannot make.
    //
    // The two sites are the `else` branches of the two places a tab's waveform
    // is loaded — restored-on-launch and opened-now. Being in that branch is
    // what proves the session is new: the sidecar branch above each one
    // returned. If either loses its call, an organization's template silently
    // stops applying to half the ways a tab can open, which is worse than not
    // applying at all — it would look intermittent.
    const sites = <String, String>{
      'lib/app.dart': 'tabs restored on launch (the deferred-load listener)',
      'lib/features/viewer/screens/viewer_screen_file_io.dart':
          'tabs the user opens now',
    };

    for (final MapEntry(key: path, value: which) in sites.entries) {
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason: '$path is missing; if the loader moved, move this entry too.',
      );
      expect(
        file.readAsStringSync(),
        contains('seedOrgSessionTemplateLogging('),
        reason:
            '$path no longer seeds the organization session template, so it '
            'stops applying to $which.\n\n'
            'Every test in this file keeps passing — the function works, '
            'nothing calls it — which is exactly the state the feature was in '
            'before 2026-08-24.',
      );
    }
  });
}
