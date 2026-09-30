// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `products.wavecrux.wcpServer` and `cxpServer` were registered, documented on
// administration.html, and read by nothing: an administrator could set either
// to false, restart every seat, and the server came up anyway. These assert the
// precedence that makes the keys mean something.

import 'package:crux_policy/crux_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/policy/org_server_policy.dart';

PolicyDocument _doc(String json) => PolicyDocument.parse(json);

void main() {
  group('org server policy', () {
    test('no policy file leaves the decision with the engineer', () {
      final r = resolveWcpServerPolicy(_doc('{"schema":1}'), userSetting: true);
      expect(r.value, isTrue);
      expect(r.source, PolicySource.userSetting);
    });

    test('nothing set anywhere is off — the compiled-in default', () {
      final r = resolveWcpServerPolicy(
        _doc('{"schema":1}'),
        userSetting: null,
      );
      expect(r.value, isFalse);
      expect(r.source, PolicySource.builtIn);
    });

    test('a LOCKED false beats the engineer switching it on', () {
      // The case the key exists for. Before this the switch won and the
      // administrator was never told otherwise.
      final r = resolveWcpServerPolicy(
        _doc(
          '{"schema":1,"products":{"wavecrux":'
          '{"wcpServer":{"value":false,"locked":true}}}}',
        ),
        userSetting: true,
      );
      expect(r.value, isFalse);
      expect(r.source, PolicySource.policyLocked);
    });

    test('a LOCKED true turns it on for the fleet', () {
      final r = resolveCxpServerPolicy(
        _doc(
          '{"schema":1,"products":{"wavecrux":'
          '{"cxpServer":{"value":true,"locked":true}}}}',
        ),
        userSetting: false,
      );
      expect(r.value, isTrue);
      expect(r.source, PolicySource.policyLocked);
    });

    test('an UNLOCKED value is a suggestion the engineer outranks', () {
      // A bare bool is what an administrator writes first, and it must not
      // silently mean "locked".
      final r = resolveWcpServerPolicy(
        _doc('{"schema":1,"products":{"wavecrux":{"wcpServer":true}}}'),
        userSetting: false,
      );
      expect(r.value, isFalse);
      expect(r.source, PolicySource.userSetting);
    });

    test('an UNLOCKED value applies when the engineer has not chosen', () {
      final r = resolveWcpServerPolicy(
        _doc('{"schema":1,"products":{"wavecrux":{"wcpServer":true}}}'),
        userSetting: null,
      );
      expect(r.value, isTrue);
      expect(r.source, PolicySource.policyDefault);
    });

    test('a non-boolean value is refused, and does not open a port', () {
      // Fail closed: a policy file that does not parse must never be the thing
      // that starts a listening server.
      final r = resolveWcpServerPolicy(
        _doc('{"schema":1,"products":{"wavecrux":{"wcpServer":"yes please"}}}'),
        userSetting: null,
      );
      expect(r.value, isFalse);
      expect(r.source, PolicySource.builtIn);
    });

    test('the two keys are independent', () {
      const json =
          '{"schema":1,"products":{"wavecrux":'
          '{"wcpServer":{"value":false,"locked":true},"cxpServer":true}}}';
      expect(
        resolveWcpServerPolicy(_doc(json), userSetting: true).value,
        isFalse,
      );
      expect(
        resolveCxpServerPolicy(_doc(json), userSetting: null).value,
        isTrue,
      );
    });
  });
}
