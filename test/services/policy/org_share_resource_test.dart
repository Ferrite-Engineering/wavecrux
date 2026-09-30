// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/policy/org_object_policy_key.dart';
import 'package:wavecrux/services/policy/org_share_resource.dart';
import 'package:wavecrux/services/policy/org_theme_and_templates.dart';

void main() {
  late Directory share;

  setUp(() => share = Directory.systemTemp.createTempSync('wavecrux_share'));
  tearDown(() {
    try {
      share.deleteSync(recursive: true);
    } on FileSystemException {
      // Best-effort.
    }
  });

  File write(String name, Object? json) =>
      File('${share.path}/$name')..writeAsStringSync(jsonEncode(json));

  String digestOfFile(File file) =>
      sha256.convert(file.readAsBytesSync()).toString();

  group('parsing a reference', () {
    test('a bare path string works — the simplest case needs no manual', () {
      final resource = OrgShareResource.parse('/share/house.crux-theme.json');
      expect(resource?.path, '/share/house.crux-theme.json');
      expect(resource?.isPinned, isFalse);
    });

    test('the object form carries an optional pin', () {
      final resource = OrgShareResource.parse(<String, Object?>{
        'path': '/share/house.crux-theme.json',
        'sha256': 'ABC123',
      });
      expect(resource?.sha256Digest, 'abc123');
      expect(resource?.isPinned, isTrue);
    });

    test('a blank or missing path is not a reference', () {
      expect(OrgShareResource.parse('   '), isNull);
      expect(OrgShareResource.parse(<String, Object?>{'sha256': 'x'}), isNull);
      expect(OrgShareResource.parse(42), isNull);
    });
  });

  group('loading', () {
    test('an unpinned resource loads whatever is there', () {
      final file = write('theme.json', <String, Object?>{'name': 'House'});
      final load = loadOrgShareResource(OrgShareResource(path: file.path));
      expect(load.isOk, isTrue);
      expect(load.contents?['name'], 'House');
    });

    test('a pinned resource loads when it matches', () {
      final file = write('theme.json', <String, Object?>{'name': 'House'});
      final load = loadOrgShareResource(
        OrgShareResource(path: file.path, sha256Digest: digestOfFile(file)),
      );
      expect(load.isOk, isTrue);
    });

    test(
      'a pinned resource refuses when it does not, and names both digests',
      () {
        final file = write('theme.json', <String, Object?>{'name': 'House'});
        final pinned = digestOfFile(file);
        file.writeAsStringSync(jsonEncode(<String, Object?>{'name': 'Other'}));

        final load = loadOrgShareResource(
          OrgShareResource(path: file.path, sha256Digest: pinned),
        );
        expect(load.isOk, isFalse);
        expect(load.failure, OrgShareFailure.digestMismatch);
        expect(
          load.detail,
          contains(pinned),
          reason:
              'the fix is either "update the file" or "update the policy", and '
              'an administrator cannot tell which without seeing both',
        );
      },
    );

    test('a missing file is reported, not silently skipped', () {
      final load = loadOrgShareResource(
        const OrgShareResource(path: '/nowhere/at/all.json'),
      );
      expect(load.failure, OrgShareFailure.missing);
      expect(
        load.detail,
        contains('/nowhere/at/all.json'),
        reason:
            'an organization pointing at a share nobody can reach must find '
            'out from the application, not from an engineer noticing their '
            'theme never changed',
      );
    });

    test('malformed JSON is its own failure, not "missing"', () {
      final file = File('${share.path}/broken.json')
        ..writeAsStringSync('{ not json');
      final load = loadOrgShareResource(OrgShareResource(path: file.path));
      expect(load.failure, OrgShareFailure.malformed);
    });

    test('a JSON array is malformed for this purpose', () {
      final file = write('array.json', <Object?>[1, 2, 3]);
      final load = loadOrgShareResource(OrgShareResource(path: file.path));
      expect(load.failure, OrgShareFailure.malformed);
    });
  });

  group('the policy references', () {
    OrgResourceRef? refOf(Object? raw, {bool locked = false}) =>
        OrgResourceRef.fromPolicyEntry(
          raw == null ? null : OrgPolicyEntry(value: raw, locked: locked),
        );

    test('an absent key configures nothing', () {
      expect(refOf(null), isNull);
    });

    test('a one-element list takes its element', () {
      final ref = refOf(<Object?>['/share/house.crux-theme.json']);
      expect(ref?.resource.path, '/share/house.crux-theme.json');
    });

    test('an empty list is not a reference', () {
      expect(refOf(<Object?>[]), isNull);
    });

    test('the lock flag rides through — this is the mandatory-pack case', () {
      final ref = refOf(
        <String, Object?>{'path': '/share/house.crux-theme.json'},
        locked: true,
      );
      expect(ref?.locked, isTrue);
    });

    test('a configured-but-broken reference reports, rather than reading as '
        'unconfigured', () {
      final ref = refOf('/nowhere/at/all.json');
      expect(ref, isNotNull);
      final load = loadOrgShareResource(ref!.resource);
      expect(
        load.isOk,
        isFalse,
        reason:
            '"not configured" and "configured and pointing at a share nobody '
            'can reach" need different fixes, so they must stay '
            'distinguishable',
      );
    });
  });
}
