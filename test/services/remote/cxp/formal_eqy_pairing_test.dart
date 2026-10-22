// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/viewer/providers/signal_group_providers.dart';
import 'package:wavecrux/services/remote/cxp/formal_eqy_pairing.dart';
import 'package:wavecrux/services/waveform/streaming_vcd_service.dart';

/// The EQY pairing: an equivalence trace's gold and gate halves arranged as a
/// pair, with the miter's outputs first, from the sender's
/// `formal.eqy.gold_scope` / `formal.eqy.gate_scope` keys (CXP §9.3.1).
///
/// The counts below are read off the trace's own `$scope` / `$var` header by
/// eye (`alu_fail`, partition `alu.z`): fourteen variables under
/// `miter.gold`, a hundred and nineteen under `miter.gate`, six `__po_z__*`
/// wires and the four of the `__po_z__assert` scope beside them, and six
/// `__pi_*` inputs that are not outputs.
void main() {
  final trace = p.join(
    Directory.current.path,
    'test/fixtures/formal/captured/eqy/captured/alu_fail/strategies/alu.z/sby/'
    'trace.vcd',
  );

  Future<List<Variable>> variablesOf(String path) async {
    final source = StreamingVcdService();
    await source.openFile(path);
    await source.streamEndedFuture;
    addTearDown(source.close);
    return source.findVariables(const SignalFilter());
  }

  group('EqyTracePairing.scopesFrom', () {
    test('reads both keys', () {
      expect(
        EqyTracePairing.scopesFrom(const <String, Object?>{
          cxpFormalEqyGoldScopeMetadataKey: 'gold',
          cxpFormalEqyGateScopeMetadataKey: 'gate',
        }),
        (gold: 'gold', gate: 'gate'),
      );
    });

    test('needs both, distinct and non-empty', () {
      expect(
        EqyTracePairing.scopesFrom(const <String, Object?>{
          cxpFormalEqyGoldScopeMetadataKey: 'gold',
        }),
        isNull,
      );
      expect(
        EqyTracePairing.scopesFrom(const <String, Object?>{
          cxpFormalEqyGoldScopeMetadataKey: 'gold',
          cxpFormalEqyGateScopeMetadataKey: ' ',
        }),
        isNull,
      );
      expect(
        EqyTracePairing.scopesFrom(const <String, Object?>{
          cxpFormalEqyGoldScopeMetadataKey: 'gold',
          cxpFormalEqyGateScopeMetadataKey: 'gold',
        }),
        isNull,
      );
      expect(
        EqyTracePairing.scopesFrom(const <String, Object?>{
          cxpFormalEqyGoldScopeMetadataKey: 3,
          cxpFormalEqyGateScopeMetadataKey: 'gate',
        }),
        isNull,
      );
    });
  });

  group('EqyTracePairing.arrange on a real EQY trace', () {
    test('pairs miter.gold with miter.gate and puts the miter outputs '
        'first', () async {
      final arrangement = EqyTracePairing.arrange(
        await variablesOf(trace),
        goldScope: 'gold',
        gateScope: 'gate',
      );
      expect(arrangement, isNotNull);
      expect(arrangement!.goldScope, 'miter.gold');
      expect(arrangement.gateScope, 'miter.gate');
      expect(arrangement.gold, hasLength(14));
      expect(arrangement.gate, hasLength(119));
      expect(
        arrangement.gold.every((v) => v.scopePath == 'miter.gold'),
        isTrue,
      );
      expect(
        arrangement.miterOutputs.map((v) => v.fullPath),
        unorderedEquals(<String>[
          'miter.__po_z__assert.i',
          'miter.__po_z__assert.in_gate',
          'miter.__po_z__assert.in_gold',
          'miter.__po_z__assert.okay',
          'miter.__po_z__gate',
          'miter.__po_z__gate_d',
          'miter.__po_z__gate_x',
          'miter.__po_z__gold',
          'miter.__po_z__gold_d',
          'miter.__po_z__gold_x',
        ]),
      );
    });

    test('a full scope path works as well as its last segment', () async {
      final arrangement = EqyTracePairing.arrange(
        await variablesOf(trace),
        goldScope: 'miter.gold',
        gateScope: 'miter.gate',
      );
      expect(arrangement?.goldScope, 'miter.gold');
    });

    test('a scope the trace does not hold arranges nothing', () async {
      expect(
        EqyTracePairing.arrange(
          await variablesOf(trace),
          goldScope: 'reference',
          gateScope: 'gate',
        ),
        isNull,
      );
    });
  });

  group('EqyTracePairing.arrange, the edges', () {
    Variable v(String scope, String name) => Variable(
      name: name,
      varType: VarType.wire,
      direction: VarDirection.unknown,
      signalRef: '$scope.$name',
      scopePath: scope,
      bitWidth: 1,
    );

    test('two scopes ending in the same name are ambiguous, so nothing is '
        'arranged rather than the wrong one', () {
      expect(
        EqyTracePairing.arrange(
          [v('a.gold', 'x'), v('b.gold', 'x'), v('a.gate', 'x')],
          goldScope: 'gold',
          gateScope: 'gate',
        ),
        isNull,
      );
    });

    test('a gate scope nested inside the gold scope is not a pair', () {
      expect(
        EqyTracePairing.arrange(
          [v('m.gold', 'x'), v('m.gold.gate', 'y')],
          goldScope: 'gold',
          gateScope: 'gate',
        ),
        isNull,
      );
    });

    test('the shortest match wins', () {
      final arrangement = EqyTracePairing.arrange(
        [v('m.gold', 'x'), v('m.gate', 'y'), v('m.gate.sub.gate', 'z')],
        goldScope: 'gold',
        gateScope: 'gate',
      );
      expect(arrangement?.gateScope, 'm.gate');
      expect(arrangement?.gate.map((x) => x.name), ['y', 'z']);
    });
  });

  group('SignalGroupsNotifier.prependArrangement', () {
    test('puts the lead first, then the groups, and never shows a signal '
        'twice', () async {
      final variables = await variablesOf(trace);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(signalGroupsProvider.notifier);
      final unrelated = variables.firstWhere(
        (x) => x.fullPath == 'miter.__pi_a',
      );
      final okay = variables.firstWhere(
        (x) => x.fullPath == 'miter.__po_z__assert.okay',
      );
      // What a hand-off's suggested signals may already have put there.
      notifier.addSignals([unrelated, okay]);

      final arrangement = EqyTracePairing.arrange(
        variables,
        goldScope: 'gold',
        gateScope: 'gate',
      )!;
      notifier.prependArrangement(
        lead: arrangement.miterOutputs,
        groups: [
          (name: arrangement.goldScope, signals: arrangement.gold),
          (name: arrangement.gateScope, signals: arrangement.gate),
        ],
      );

      final entries = container.read(signalGroupsProvider).entries;
      final lead = arrangement.miterOutputs.length;
      expect(
        entries.take(lead).map((e) => e.signalPath),
        arrangement.miterOutputs.map((x) => x.fullPath),
      );
      expect(entries[lead].kind, SignalEntryKind.group);
      expect(entries[lead].groupName, 'miter.gold');
      expect(entries[lead].children, hasLength(14));
      expect(entries[lead + 1].groupName, 'miter.gate');
      expect(entries[lead + 1].children, hasLength(119));
      // The unrelated row stays, below; the duplicate `okay` row is gone.
      expect(entries.skip(lead + 2).map((e) => e.signalPath), [
        'miter.__pi_a',
      ]);
    });

    test('an empty arrangement changes nothing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(signalGroupsProvider.notifier)
          .prependArrangement(lead: const [], groups: const []);
      expect(container.read(signalGroupsProvider).entries, isEmpty);
    });
  });
}
