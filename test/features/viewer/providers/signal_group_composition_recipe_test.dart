// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/services/collaboration/signal_identity_resolver.dart';

/// A variable whose backend-local ref deliberately differs from its path, so a
/// recipe replayed onto it must go through path-space.
Variable _v(String name, {required String scope, required String ref}) =>
    Variable(
      name: name,
      varType: VarType.wire,
      direction: VarDirection.unknown,
      signalRef: ref,
      scopePath: scope,
      bitWidth: 1,
    );

/// Resolver where the follower's local refs differ from the presenter's.
SignalIdentityResolver _follower() => SignalIdentityResolver(
  pathToRef: const {'top.clk': 'L1', 'top.cpu.data': 'L2'},
  refToPath: const {'L1': 'top.clk', 'L2': 'top.cpu.data'},
);

void main() {
  group('SignalGroupsNotifier view-composition recipe seams', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    SignalGroupsNotifier notifier() => c.read(signalGroupsProvider.notifier);

    test('toCompositionRecipe normalises signalRef to signalPath', () {
      notifier()
        ..addSignal(_v('clk', scope: 'top', ref: 'P7'))
        ..addSignal(_v('data', scope: 'top.cpu', ref: 'P9'));
      // Tweak a format so we can confirm it rides along.
      final id = c.read(signalGroupsProvider).entries.first.id;
      notifier().setSignalFormatById(id, DisplayFormat.binary);

      final recipe = notifier().toCompositionRecipe();
      final entries = recipe.entries;
      expect(entries, hasLength(2));
      // No backend-local refs survive — every ref equals its path.
      expect(entries[0].signalRef, 'top.clk');
      expect(entries[0].signalPath, 'top.clk');
      expect(entries[0].format, DisplayFormat.binary);
      expect(entries[1].signalRef, 'top.cpu.data');
    });

    test('round-trip: serialize → apply yields the follower-local refs', () {
      notifier()
        ..addSignal(_v('clk', scope: 'top', ref: 'P7'))
        ..addSignal(_v('data', scope: 'top.cpu', ref: 'P9'));
      final recipe = notifier().toCompositionRecipe();

      // Fresh follower container with different local refs.
      final follower = ProviderContainer();
      addTearDown(follower.dispose);
      final missing = follower
          .read(signalGroupsProvider.notifier)
          .applyCompositionRecipe(recipe, _follower());

      expect(missing, isEmpty);
      final applied = follower.read(signalGroupsProvider).entries;
      expect(applied.map((e) => e.signalPath), ['top.clk', 'top.cpu.data']);
      // Re-resolved to the *follower's* refs, not the presenter's.
      expect(applied.map((e) => e.signalRef), ['L1', 'L2']);
    });

    test('missing-signal degradation drops the row and reports the path', () {
      notifier()
        ..addSignal(_v('clk', scope: 'top', ref: 'P7'))
        ..addSignal(_v('ghost', scope: 'top', ref: 'P9'));
      final recipe = notifier().toCompositionRecipe();

      final follower = ProviderContainer();
      addTearDown(follower.dispose);
      // Follower's file lacks top.ghost.
      final missing = follower
          .read(signalGroupsProvider.notifier)
          .applyCompositionRecipe(recipe, _follower());

      expect(missing, ['top.ghost']);
      final applied = follower.read(signalGroupsProvider).entries;
      expect(applied.map((e) => e.signalPath), ['top.clk']);
    });
  });
}
