// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/update/wavecrux_update_overrides.dart';

/// A licence tier a test can change mid-session, the way entering a key does.
class _MutableTier extends Notifier<LicenseTier> {
  @override
  LicenseTier build() => LicenseTier.openCore;

  LicenseTier get value => state;

  set value(LicenseTier tier) => state = tier;
}

final _mutableTierProvider = NotifierProvider<_MutableTier, LicenseTier>(
  _MutableTier.new,
);

/// WaveCrux's binding of the `crux_updates` edition seam, which decides
/// whether a release that changed only paid features is offered (the
/// manifest's `open_core_version`). Left unbound, the package default offers
/// every release to every seat — silently.
void main() {
  ProviderContainer seat(LicenseTier tier, {bool betaPeriod = false}) {
    final container = ProviderContainer(
      overrides: <Override>[
        ...wavecruxUpdateOverrides,
        betaPeriodProvider.overrideWithValue(betaPeriod),
        licenseTierProvider.overrideWithValue(tier),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('updateEditionProvider binding', () {
    test('a seat without a licence is an open-core seat', () {
      expect(
        seat(LicenseTier.openCore).read(updateEditionProvider),
        UpdateEdition.openCore,
      );
    });

    test('every paid tier unlocks', () {
      for (final tier in [
        LicenseTier.edu,
        LicenseTier.pro,
        LicenseTier.enterprise,
      ]) {
        expect(
          seat(tier).read(updateEditionProvider),
          UpdateEdition.unlocked,
          reason: '$tier',
        );
      }
    });

    test('a beta period unlocks every seat, as it opens every gate', () {
      expect(
        seat(
          LicenseTier.openCore,
          betaPeriod: true,
        ).read(updateEditionProvider),
        UpdateEdition.unlocked,
      );
    });

    test('follows a licence entered mid-session', () {
      final container = ProviderContainer(
        overrides: <Override>[
          ...wavecruxUpdateOverrides,
          betaPeriodProvider.overrideWithValue(false),
          licenseTierProvider.overrideWith(
            (ref) => ref.watch(_mutableTierProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(updateEditionProvider), UpdateEdition.openCore);

      container.read(_mutableTierProvider.notifier).value = LicenseTier.pro;

      expect(container.read(updateEditionProvider), UpdateEdition.unlocked);
    });
  });
}
