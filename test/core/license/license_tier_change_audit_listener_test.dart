// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_audit/crux_audit.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/license/license_tier_change_audit_listener.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';

/// A settable tier, standing in for the Pro overlay's licence-backed binding.
///
/// Riverpod 3 removed `StateProvider`, and the replacement is what this feature
/// needs anyway: the production binding is a `Provider` derived from licence
/// status, and only the *value* matters to the listener.
class _TierNotifier extends Notifier<LicenseTier> {
  _TierNotifier(this._initial);

  final LicenseTier _initial;

  @override
  LicenseTier build() => _initial;

  LicenseTier get tier => state;

  set tier(LicenseTier next) => state = next;
}

NotifierProvider<_TierNotifier, LicenseTier> _tierProvider(LicenseTier from) =>
    NotifierProvider<_TierNotifier, LicenseTier>(() => _TierNotifier(from));

/// Captures what the recorder writes, in order.
class _CapturingSink implements AuditSink {
  final List<AuditEvent> events = <AuditEvent>[];

  @override
  Future<void> record(AuditEvent event) async => events.add(event);

  @override
  Future<void> close() async {}

  @override
  AuditSinkHealth get health => AuditSinkHealth.healthy;
}

void main() {
  late _CapturingSink sink;

  /// A container whose tier is driven by [tier], with the listener held by a
  /// real subscription — which is what the `eagerStartupProvidersProvider`
  /// host does in production, and without which the listener is paused.
  ProviderContainer boot(NotifierProvider<_TierNotifier, LicenseTier> tier) {
    sink = _CapturingSink();
    final container = ProviderContainer(
      overrides: [
        cruxAuditSinkProvider.overrideWithValue(sink),
        cruxAuditProductIdProvider.overrideWithValue(
          WaveCruxPolicyKeys.productId,
        ),
        licenseTierProvider.overrideWith((ref) => ref.watch(tier)),
      ],
    );
    addTearDown(container.dispose);
    container.listen<void>(licenseTierChangeAuditListenerProvider, (_, _) {});
    return container;
  }

  test('the initial resolution records nothing', () async {
    final tier = _tierProvider(LicenseTier.pro);
    boot(tier);
    await Future<void>.delayed(Duration.zero);

    // Every launch resolves the tier once. A line here would mean a line in
    // the administrator's file on every start saying nothing happened.
    expect(sink.events, isEmpty);
  });

  test('a change records both ends of the transition', () async {
    final tier = _tierProvider(LicenseTier.openCore);
    final container = boot(tier);

    container.read(tier.notifier).tier = LicenseTier.pro;
    await Future<void>.delayed(Duration.zero);

    final event = sink.events.single;
    expect(event.kind, WaveCruxAuditKinds.licenseTierChanged);
    expect(event.product, 'wavecrux');
    // Both ends, because "became Pro" and "stopped being Pro" are different
    // events and a single `tier` field cannot tell them apart.
    expect(event.payload['from'], 'openCore');
    expect(event.payload['to'], 'pro');
  });

  test('a downgrade is recorded the same way an upgrade is', () async {
    final tier = _tierProvider(LicenseTier.enterprise);
    final container = boot(tier);

    container.read(tier.notifier).tier = LicenseTier.openCore;
    await Future<void>.delayed(Duration.zero);

    expect(sink.events.single.payload['from'], 'enterprise');
    expect(sink.events.single.payload['to'], 'openCore');
  });

  test('re-emitting the same tier records nothing', () async {
    final tier = _tierProvider(LicenseTier.pro);
    final container = boot(tier);

    container.read(tier.notifier).tier = LicenseTier.pro;
    await Future<void>.delayed(Duration.zero);

    expect(sink.events, isEmpty);
  });

  test('each real transition is recorded, in order', () async {
    final tier = _tierProvider(LicenseTier.openCore);
    final container = boot(tier);

    // Separated in time, which is what every real journey is: a key pasted,
    // a licence deactivated later, an expiry crossed later still.
    for (final next in <LicenseTier>[
      LicenseTier.edu,
      LicenseTier.pro,
      LicenseTier.enterprise,
    ]) {
      container.read(tier.notifier).tier = next;
      await Future<void>.delayed(Duration.zero);
    }

    expect(
      sink.events.map((e) => '${e.payload['from']}->${e.payload['to']}'),
      <String>['openCore->edu', 'edu->pro', 'pro->enterprise'],
    );
  });

  test('tiers passed through inside one synchronous turn record as one '
      'transition, not three', () async {
    // Riverpod coalesces synchronous writes: a listener sees the net change,
    // never the intermediate values. Asserted rather than worked around,
    // because it is the correct answer for an audit trail — a tier the
    // application never observed is not a tier the installation ever held,
    // and logging it would put entitlements in the file that never existed.
    final tier = _tierProvider(LicenseTier.openCore);
    final container = boot(tier);

    container.read(tier.notifier).tier = LicenseTier.edu;
    container.read(tier.notifier).tier = LicenseTier.pro;
    container.read(tier.notifier).tier = LicenseTier.enterprise;
    await Future<void>.delayed(Duration.zero);

    expect(
      sink.events.map((e) => '${e.payload['from']}->${e.payload['to']}'),
      <String>['openCore->enterprise'],
    );
  });

  test('the payload carries the tiers and nothing else', () async {
    // The suite's payload-withholding rule: an audit line names what happened,
    // never the user's material. There is no credential, no machine id and no
    // path in a tier transition, and there must not be.
    final tier = _tierProvider(LicenseTier.openCore);
    final container = boot(tier);

    container.read(tier.notifier).tier = LicenseTier.pro;
    await Future<void>.delayed(Duration.zero);

    expect(sink.events.single.payload.keys.toSet(), <String>{'from', 'to'});
  });

  test('a merely-read listener observes nothing — the trap the eager-startup '
      'seam exists to prevent', () async {
    // Riverpod pauses a provider with no listener, and the pause propagates
    // into the `ref.listen` this provider installs. Realizing it with a
    // one-shot `read` therefore constructs it and immediately stops it
    // observing, which would look exactly like a working audit trail until
    // somebody went looking for a line.
    sink = _CapturingSink();
    final tier = _tierProvider(LicenseTier.openCore);
    final container = ProviderContainer(
      overrides: [
        cruxAuditSinkProvider.overrideWithValue(sink),
        cruxAuditProductIdProvider.overrideWithValue(
          WaveCruxPolicyKeys.productId,
        ),
        licenseTierProvider.overrideWith((ref) => ref.watch(tier)),
      ],
    );
    addTearDown(container.dispose);

    container.read(licenseTierChangeAuditListenerProvider);
    container.read(tier.notifier).tier = LicenseTier.pro;
    await Future<void>.delayed(Duration.zero);

    expect(sink.events, isEmpty);
  });
}
