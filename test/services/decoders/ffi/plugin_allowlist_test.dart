// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/services/decoders/ffi/plugin_allowlist.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('wavecrux_allowlist'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best-effort.
    }
  });

  File writePlugin(String name, String contents) =>
      File('${dir.path}/$name')..writeAsStringSync(contents);

  String digestOf(String contents) =>
      sha256.convert(contents.codeUnits).toString();

  group('the default', () {
    test('no policy file means no allowlist, and everything loads', () {
      final file = writePlugin('libfoo.so', 'anything');
      expect(PluginAllowlist.absent.isConfigured, isFalse);
      expect(
        PluginAllowlist.absent.allowsFile(file.path),
        isTrue,
        reason:
            'refusing everything by default would break every existing user '
            'the first time they updated, the SigRok bridge included',
      );
    });

    test('a missing key is absent, not an empty list', () {
      expect(PluginAllowlist.fromPolicyValue(null).isConfigured, isFalse);
    });

    test('a malformed key is absent, not the strictest possible policy', () {
      expect(
        PluginAllowlist.fromPolicyValue('not-a-list').isConfigured,
        isFalse,
        reason:
            'a typo must not silently stop every plugin in the fleet — that '
            'is the loudest possible wrong answer',
      );
      expect(PluginAllowlist.fromPolicyValue(42).isConfigured, isFalse);
    });
  });

  group('an administrator’s list', () {
    test('an approved digest loads', () {
      final file = writePlugin('libfoo.so', 'approved bytes');
      final list = PluginAllowlist.fromPolicyValue(<Object?>[
        digestOf('approved bytes'),
      ]);
      expect(list.isConfigured, isTrue);
      expect(list.allowsFile(file.path), isTrue);
    });

    test('an unlisted file is refused', () {
      final file = writePlugin('libevil.so', 'not approved');
      final list = PluginAllowlist.fromPolicyValue(<Object?>[
        digestOf('approved bytes'),
      ]);
      expect(list.allowsFile(file.path), isFalse);
    });

    test('a modified approved file is refused', () {
      final file = writePlugin('libfoo.so', 'approved bytes');
      final list = PluginAllowlist.fromPolicyValue(<Object?>[
        digestOf('approved bytes'),
      ]);
      expect(list.allowsFile(file.path), isTrue);

      file.writeAsStringSync('approved bytes plus a backdoor');
      expect(
        list.allowsFile(file.path),
        isFalse,
        reason:
            'vetting a binary once and having a substituted one stop loading '
            'is the whole of what a content hash buys',
      );
    });

    test('an EMPTY list is honoured — it means no plugins are approved', () {
      final file = writePlugin('libfoo.so', 'anything');
      final list = PluginAllowlist.fromPolicyValue(const <Object?>[]);
      expect(list.isConfigured, isTrue);
      expect(
        list.allowsFile(file.path),
        isFalse,
        reason:
            'refusing to honour it would make the strictest posture the one '
            'thing the key cannot express',
      );
    });

    test('a file that cannot be read is refused, not admitted', () {
      final list = PluginAllowlist.fromPolicyValue(<Object?>[
        digestOf('approved bytes'),
      ]);
      expect(
        list.allowsFile('${dir.path}/does-not-exist.so'),
        isFalse,
        reason:
            'admitting what this process cannot verify would make the '
            'allowlist advisory',
      );
    });
  });

  group('digest parsing', () {
    final digest = digestOf('x');

    test('case and whitespace do not matter', () {
      final list = PluginAllowlist.fromPolicyValue(<Object?>[
        '  ${digest.toUpperCase()}  ',
      ]);
      expect(list.allowsDigest(digest), isTrue);
    });

    test('a sha256: prefix is tolerated', () {
      final list = PluginAllowlist.fromPolicyValue(<Object?>['sha256:$digest']);
      expect(list.allowsDigest(digest), isTrue);
    });

    test('anything that is not a 64-char hex digest is dropped', () {
      final list = PluginAllowlist.fromPolicyValue(<Object?>[
        'deadbeef',
        'z' * 64,
        '',
        digest,
      ]);
      expect(
        list.length,
        1,
        reason:
            'a truncated or mistyped digest that silently matched nothing '
            'would look configured and approve nothing',
      );
      expect(list.allowsDigest(digest), isTrue);
    });

    test('a non-string entry is dropped rather than crashing the scan', () {
      final list = PluginAllowlist.fromPolicyValue(<Object?>[42, digest]);
      expect(list.length, 1);
    });
  });

  test('the digest is what an administrator would compute', () {
    final file = writePlugin('libfoo.so', 'bytes');
    expect(
      PluginAllowlist.digestOfFile(file.path),
      digestOf('bytes'),
      reason:
          'if this disagreed with `shasum -a 256`, every list an '
          'administrator wrote by hand would refuse everything',
    );
  });
}
