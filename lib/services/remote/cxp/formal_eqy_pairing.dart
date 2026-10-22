// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart'
    show cxpFormalEqyGateScopeMetadataKey, cxpFormalEqyGoldScopeMetadataKey;
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/variable.dart';

/// How an equivalence-check trace is laid out on the tab a hand-off opened:
/// the miter's outputs first, then the gold design and the gate design as two
/// groups side by side.
@immutable
class EqyTraceArrangement {
  /// Creates an arrangement.
  const EqyTraceArrangement({
    required this.miterOutputs,
    required this.goldScope,
    required this.gold,
    required this.gateScope,
    required this.gate,
  });

  /// The miter's comparison outputs (`__po_*`), in hierarchy order. They come
  /// first because they are where the two designs disagree.
  final List<Variable> miterOutputs;

  /// The gold design's scope path in this trace (`miter.gold`).
  final String goldScope;

  /// Every variable under [goldScope], in hierarchy order.
  final List<Variable> gold;

  /// The gate design's scope path in this trace (`miter.gate`).
  final String gateScope;

  /// Every variable under [gateScope], in hierarchy order.
  final List<Variable> gate;
}

/// Pairs the gold and gate halves of an EQY trace from the sender's
/// `formal.eqy.gold_scope` and `formal.eqy.gate_scope` metadata (CXP
/// §9.3.1).
///
/// EQY writes each partition's witness as one miter: the gold and gate copies
/// of the partition sit in sibling scopes, and the miter's own comparison
/// signals (`__po_<output>__gold`, `__po_<output>__gate`, the
/// `__po_<output>__assert` scope) sit beside them. Read flat, the two copies
/// interleave by name and the disagreement is lost in hundreds of gate-level
/// wires; arranged, the outputs that differ are on top and each design is one
/// collapsible group.
///
/// WaveCrux has no notion of a pinned row, so "on top" means inserted first.
/// Pure Dart: no providers, no IO.
abstract final class EqyTracePairing {
  /// The two scope names [metadata] carries, or null when either is missing
  /// or empty. The keys are advisory: a sender without them gets the trace
  /// unarranged.
  static ({String gold, String gate})? scopesFrom(
    Map<String, Object?> metadata,
  ) {
    final gold = metadata[cxpFormalEqyGoldScopeMetadataKey];
    final gate = metadata[cxpFormalEqyGateScopeMetadataKey];
    if (gold is! String || gate is! String) return null;
    final goldName = gold.trim();
    final gateName = gate.trim();
    if (goldName.isEmpty || gateName.isEmpty || goldName == gateName) {
      return null;
    }
    return (gold: goldName, gate: gateName);
  }

  /// Arranges [variables] around the scopes named [goldScope] and
  /// [gateScope], or returns null when the trace does not hold both as
  /// distinct, non-nested scopes with signals in them.
  ///
  /// A name is matched against the trace's scope paths as a whole path or as
  /// a trailing part of one (`gold` matches `miter.gold`); the shortest match
  /// wins, and two matches of the same length are ambiguous, so nothing is
  /// arranged rather than the wrong scope.
  static EqyTraceArrangement? arrange(
    List<Variable> variables, {
    required String goldScope,
    required String gateScope,
  }) {
    final scopes = <String>{};
    for (final variable in variables) {
      final segments = variable.scopePath.split('.');
      for (var i = 1; i <= segments.length; i++) {
        final prefix = segments.sublist(0, i).join('.');
        if (prefix.isNotEmpty) scopes.add(prefix);
      }
    }
    final gold = _resolveScope(goldScope, scopes);
    final gate = _resolveScope(gateScope, scopes);
    if (gold == null || gate == null || gold == gate) return null;
    if (_within(gold, gate) || _within(gate, gold)) return null;

    final goldVars = <Variable>[];
    final gateVars = <Variable>[];
    final outputs = <Variable>[];
    final parent = _parentOf(gold) == _parentOf(gate) ? _parentOf(gold) : null;
    for (final variable in variables) {
      if (_within(variable.scopePath, gold)) {
        goldVars.add(variable);
      } else if (_within(variable.scopePath, gate)) {
        gateVars.add(variable);
      } else if (parent != null && _isMiterOutput(variable, parent)) {
        outputs.add(variable);
      }
    }
    if (goldVars.isEmpty || gateVars.isEmpty) return null;
    return EqyTraceArrangement(
      miterOutputs: outputs,
      goldScope: gold,
      gold: goldVars,
      gateScope: gate,
      gate: gateVars,
    );
  }

  static String? _resolveScope(String name, Set<String> scopes) {
    String? best;
    var ambiguous = false;
    for (final scope in scopes) {
      if (scope != name && !scope.endsWith('.$name')) continue;
      if (best == null || scope.length < best.length) {
        best = scope;
        ambiguous = false;
      } else if (scope.length == best.length && scope != best) {
        ambiguous = true;
      }
    }
    return ambiguous ? null : best;
  }

  /// Whether [scopePath] is [scope] or lies under it.
  static bool _within(String scopePath, String scope) =>
      scopePath == scope || scopePath.startsWith('$scope.');

  static String _parentOf(String scope) {
    final dot = scope.lastIndexOf('.');
    return dot < 0 ? '' : scope.substring(0, dot);
  }

  /// Whether [variable] is one of the miter's comparison signals: directly
  /// under [parent], or in a scope directly under it, whose first segment
  /// below [parent] starts with `__po_`.
  static bool _isMiterOutput(Variable variable, String parent) {
    final String relative;
    if (parent.isEmpty) {
      relative = variable.fullPath;
    } else if (variable.fullPath.startsWith('$parent.')) {
      relative = variable.fullPath.substring(parent.length + 1);
    } else {
      return false;
    }
    return relative.split('.').first.startsWith('__po_');
  }
}
