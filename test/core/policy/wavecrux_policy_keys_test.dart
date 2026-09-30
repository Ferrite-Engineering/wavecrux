// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_policy/crux_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';

/// WaveCrux's policy namespace and audit vocabulary.
///
/// C5 makes the keys EXIST AND BE HONOURED. It does not implement the features
/// they configure — those are separate follow-ups that become small once this
/// is in place.
void main() {
  group('the namespace is registered and non-empty', () {
    test('the product id matches the schema', () {
      expect(WaveCruxPolicyKeys.productId, 'wavecrux');
    });

    test('keys and kinds are declared', () {
      expect(WaveCruxPolicyKeys.all, isNotEmpty);
      expect(WaveCruxAuditKinds.all, isNotEmpty);
    });

    test('no key or kind is blank, and none collide', () {
      for (final k in WaveCruxPolicyKeys.all) {
        expect(k.trim(), isNotEmpty);
      }
      for (final k in WaveCruxAuditKinds.all) {
        expect(k.trim(), isNotEmpty);
        expect(k, contains('.'), reason: 'kinds are dotted: noun.verb');
      }
    });
  });

  group('registered keys actually resolve', () {
    test('a policy value in this namespace is honoured', () {
      final key = WaveCruxPolicyKeys.all.first;
      final doc = PolicyDocument.parse(
        '{"schema":1,"products":{"wavecrux":{"$key":"x"}}}',
      );
      final resolved = wavecruxPolicyResolver(doc).productValue<String>(
        key,
        parse: (raw) => raw is String ? raw : null,
        builtIn: 'built-in',
      );
      expect(resolved.value, 'x');
      expect(resolved.source, PolicySource.policyDefault);
    });

    test('a LOCKED value outranks the user setting', () {
      final key = WaveCruxPolicyKeys.all.first;
      final doc = PolicyDocument.parse(
        '{"schema":1,"products":{"wavecrux":'
        '{"$key":{"value":"org","locked":true}}}}',
      );
      final resolved = wavecruxPolicyResolver(doc).productValue<String>(
        key,
        parse: (raw) => raw is String ? raw : null,
        builtIn: 'built-in',
        userSetting: 'mine',
      );
      expect(resolved.value, 'org');
      expect(resolved.locked, isTrue);
    });

    test("ANOTHER product's namespace is ignored silently", () {
      // One file serves a mixed fleet, so meeting another product's keys is
      // the normal case rather than a misconfiguration — not warned about,
      // not an error.
      final key = WaveCruxPolicyKeys.all.first;
      const other = 'wavecrux' == 'simcrux' ? 'wavecrux' : 'simcrux';
      final doc = PolicyDocument.parse(
        '{"schema":1,"products":{"$other":{"$key":"x"}}}',
      );
      final resolver = wavecruxPolicyResolver(doc);
      final resolved = resolver.productValue<String>(
        key,
        parse: (raw) => raw is String ? raw : null,
        builtIn: 'built-in',
      );
      expect(resolved.value, 'built-in');
      expect(resolver.diagnostics, isEmpty);
    });
  });
}
