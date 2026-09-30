// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_policy/crux_policy.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';

/// Whether WaveCrux's two listening servers may run on this seat.
///
/// Both open a socket on the engineer's machine, and both are the kind of
/// thing an organization turns off centrally rather than asking each engineer
/// to. `products.wavecrux.wcpServer` and `products.wavecrux.cxpServer` are the
/// keys for that, and until this existed they were registered, documented on
/// `administration.html`, and read by nothing: an administrator could set
/// either to `false`, restart every seat, and the server would still come up.
///
/// **A silently ignored restriction is worse than no key at all**, because the
/// administrator believes the control is in force. That is the whole reason
/// this exists rather than the keys being deleted.
///
/// Precedence is the suite's, not a private one
/// (`https://edacrux.app/policy-reference#precedence`):
///
/// ```text
/// 1. a LOCKED policy value    the organization decided, and said so
/// 2. the engineer's setting   the Remote Control / CXP switch
/// 3. an unlocked default      the organization's starting point
/// 4. off                      the compiled-in default for both
/// ```
///
/// The built-in is `false` for both, because neither server has ever started
/// itself on a fresh install and a policy file that fails to parse must not be
/// the thing that opens a port.
///
/// **A plain function taking [userSetting], not a provider reading it.** This
/// lives in `core/`, which `import_layering_test` forbids from reaching into
/// `features/` — and `appSettingsProvider` is a feature. Every caller already
/// holds the settings object, so passing the one field costs nothing and keeps
/// the layering honest.
ResolvedSetting<bool> resolveServerPolicy(
  PolicyDocument policy, {
  required String key,
  required bool? userSetting,
}) => wavecruxPolicyResolver(policy).productValue<bool>(
  key,
  parse: (raw) => raw is bool ? raw : null,
  userSetting: userSetting,
  builtIn: false,
);

/// Whether the WCP remote-control server may run, and who decided.
ResolvedSetting<bool> resolveWcpServerPolicy(
  PolicyDocument policy, {
  required bool? userSetting,
}) => resolveServerPolicy(
  policy,
  key: WaveCruxPolicyKeys.wcpServer,
  userSetting: userSetting,
);

/// Whether the CXP peer server may run, and who decided.
ResolvedSetting<bool> resolveCxpServerPolicy(
  PolicyDocument policy, {
  required bool? userSetting,
}) => resolveServerPolicy(
  policy,
  key: WaveCruxPolicyKeys.cxpServer,
  userSetting: userSetting,
);
