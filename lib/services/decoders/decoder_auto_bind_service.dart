// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/auto_bind_candidate.dart';
import 'package:wavecrux/domain/models/auto_bind_result.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/auto_bind/auto_bind_text.dart';

/// Common-synonym table for decoder binding names.
///
/// Used by Tier C (see [DecoderAutoBindService.computeBindings]) only when
/// Tiers A and B both fail. Each canonical binding name maps to a list of
/// alternative leaf names that designs commonly use for the same logical
/// signal (e.g. SPI's `mosi` is often called `sdo`).
///
/// Match is case-insensitive on the leaf name.
const Map<String, List<String>> _knownAliases = {
  'aclk': ['clk', 'clock', 'sysclk'],
  'pclk': ['clk', 'clock'],
  'aresetn': ['reset_n', 'rst_n', 'nreset', 'nrst', 'presetn'],
  'presetn': ['reset_n', 'rst_n', 'nreset', 'nrst', 'aresetn'],
  'mosi': ['sdo', 'do', 'tx', 'data_out'],
  'miso': ['sdi', 'di', 'rx', 'data_in'],
  'sclk': ['spi_clk', 'sck', 'clk'],
  'cs': ['ss', 'csn', 'cs_n', 'ss_n', 'chip_select'],
  'sda': ['i2c_sda', 'data'],
  'scl': ['i2c_scl', 'clk', 'clock'],
  'tx': ['txd', 'uart_tx', 'data_tx'],
  'rx': ['rxd', 'uart_rx', 'data_rx'],
  'dp': ['d_p', 'dplus', 'usb_dp'],
  'dm': ['d_m', 'dminus', 'usb_dm'],
};

/// Computes a best-guess auto-binding of decoder signal inputs against the
/// signals available in the loaded waveform.
///
/// The algorithm walks five tiers from strongest to weakest evidence:
///
/// - **Tier A** — exact suffix match in a shared scope and shared prefix.
///   The strongest signal of correctness: most real designs put every signal
///   of one bus on a single shared prefix (e.g. `m_axi_aclk`, `m_axi_awvalid`,
///   …) inside a single scope (e.g. `tb.dut`). The algorithm groups
///   candidates by `(scope, prefix)`, scores each group by how many decoder
///   bindings it can resolve, and picks the highest-scoring group.
/// - **Tier B** — case-insensitive direct suffix match without prefix
///   detection. For bindings that Tier A could not resolve, look for any
///   signal whose leaf name equals the binding name (case-insensitive).
/// - **Tier C** — known-alias fallback. Uses [_knownAliases] to handle the
///   industry conventions that are not direct suffix matches (e.g.
///   `aclk` ↔ `clk`, `mosi` ↔ `sdo`, `dp` ↔ `d_p`).
/// - **Tier D** — Levenshtein-distance-≤-2 fuzzy match against the binding
///   name on the leaf signal name. Handles typos and abbreviations.
/// - **Tier E** — no match. Returns an [AutoBindCandidate] with
///   [AutoBindConfidence.noMatch].
class DecoderAutoBindService {
  const DecoderAutoBindService();

  /// Computes a best-guess binding for every required and optional signal
  /// in [definition] given the [availableSignals] in the loaded waveform
  /// and the user's current [currentParameters] (which may constrain the
  /// expected bit-width of width-parameterized bindings).
  ///
  /// [existingBindings] is honored: any logical name that is already
  /// non-null in this map is left untouched in the returned candidates
  /// (its candidate is a passthrough with confidence
  /// [AutoBindConfidence.exactSuffix] and `matchReason: 'manually bound'`).
  /// The algorithm uses already-bound signals as additional anchors for
  /// prefix/scope detection.
  ///
  /// [forcedPrefix] disambiguates the Tier A scoring when the user has
  /// already picked one of several equally viable bus prefixes from the
  /// preview dialog's dropdown. When non-null, only Tier A groups whose
  /// prefix matches (case-insensitive) are eligible to win. The other
  /// tiers (B/C/D/E) are unaffected and still run on bindings that
  /// Tier A could not resolve.
  AutoBindResult computeBindings({
    required DecoderDefinition definition,
    required Map<String, Variable> availableSignals,
    required Map<String, dynamic> currentParameters,
    Map<String, String?> existingBindings = const {},
    String? forcedPrefix,
  }) {
    final allBindings = <SignalBinding>[
      ...definition.requiredSignals,
      ...definition.optionalSignals,
    ];

    if (allBindings.isEmpty) {
      return const AutoBindResult(candidates: {});
    }

    // Build a fast lookup from signalRef → Variable so passthrough candidates
    // for manual bindings can be validated.
    final variablesByRef = <String, Variable>{
      for (final v in availableSignals.values) v.signalRef: v,
    };

    // Bindings the user has not yet bound. Tier A/B/C/D/E run only on these.
    final unbound = allBindings.where((b) {
      final existing = existingBindings[b.name];
      return existing == null || !variablesByRef.containsKey(existing);
    }).toList();

    final candidates = <String, AutoBindCandidate>{};

    // Honor manual bindings up-front: passthrough candidates.
    for (final binding in allBindings) {
      final existing = existingBindings[binding.name];
      if (existing != null && variablesByRef.containsKey(existing)) {
        candidates[binding.name] = AutoBindCandidate(
          signalRef: existing,
          confidence: AutoBindConfidence.exactSuffix,
          matchReason: 'manually bound',
        );
      }
    }

    // ── Tier A: shared (scope, prefix) ───────────────────────────────────────

    final tierAOutcome = _runTierA(
      bindings: unbound,
      availableSignals: availableSignals.values,
      currentParameters: currentParameters,
      definition: definition,
      manuallyBoundAnchors: _manualAnchorsForTierA(
        existingBindings: existingBindings,
        variablesByRef: variablesByRef,
        allBindings: allBindings,
      ),
      forcedPrefix: forcedPrefix,
    );

    candidates.addAll(tierAOutcome.candidates);

    // Bindings still unresolved after Tier A.
    final stillUnbound = unbound
        .where((b) => !candidates.containsKey(b.name))
        .toList();

    // ── Tier B: case-insensitive direct suffix ───────────────────────────────

    for (final binding in stillUnbound) {
      final match = _tierBMatch(
        binding: binding,
        availableSignals: availableSignals.values,
        currentParameters: currentParameters,
        definition: definition,
      );
      if (match != null) {
        candidates[binding.name] = match;
      }
    }

    final stillUnboundAfterB = stillUnbound
        .where((b) => !candidates.containsKey(b.name))
        .toList();

    // ── Tier C: known aliases ───────────────────────────────────────────────

    for (final binding in stillUnboundAfterB) {
      final match = _tierCMatch(
        binding: binding,
        availableSignals: availableSignals.values,
        currentParameters: currentParameters,
        definition: definition,
      );
      if (match != null) {
        candidates[binding.name] = match;
      }
    }

    final stillUnboundAfterC = stillUnboundAfterB
        .where((b) => !candidates.containsKey(b.name))
        .toList();

    // ── Tier D: Levenshtein fuzzy ───────────────────────────────────────────
    // Exclude signals already claimed by Tiers A–C so that optional signals
    // cannot fuzzy-match to the same signalRef as a required binding.
    // Without this guard, e.g. TRST (optional) matches TMS (required) when
    // the fixture has no TRST signal and levenshtein("trst","tms") == 2.
    final claimedRefsBeforeD = {
      for (final c in candidates.values)
        if (c.signalRef != null) c.signalRef!,
    };
    // Bus-coherence guard: once Tier A has locked onto a bus (a winning
    // (scope, prefix) group), confine fuzzy matching to that SAME scope.
    // Fuzzy is the weakest tier; letting it reach into a different scope
    // produces incoherent cross-bus bindings — e.g. a trace that carries the
    // master interface as `tb.M_HBURST` *and* the DUT internals as
    // `tb.DUV.HADDR` would bind addr/data from `DUV` (Tier A) but pull
    // `hburst`/`hresp` from `tb` via fuzzy, mixing two buses and decoding to
    // zero transactions. Exact (Tier B) and alias (Tier C) matches are NOT
    // confined — a legitimate parent-scope clock (`tb.clk` while data is in
    // `tb.dut`) still binds via its exact-leaf match.
    final detectedScope = tierAOutcome.detectedScopePath;
    final signalsForTierD = availableSignals.values
        .where((v) => !claimedRefsBeforeD.contains(v.signalRef))
        .where((v) => detectedScope == null || v.scopePath == detectedScope)
        .toList(growable: false);

    for (final binding in stillUnboundAfterC) {
      final match = _tierDMatch(
        binding: binding,
        availableSignals: signalsForTierD,
        currentParameters: currentParameters,
        definition: definition,
      );
      if (match != null) {
        candidates[binding.name] = match;
      }
    }

    // ── Tier E: no match ────────────────────────────────────────────────────

    for (final binding in allBindings) {
      candidates.putIfAbsent(
        binding.name,
        () => const AutoBindCandidate(
          signalRef: null,
          confidence: AutoBindConfidence.noMatch,
          matchReason: 'no plausible signal in the loaded design',
        ),
      );
    }

    return AutoBindResult(
      candidates: candidates,
      detectedPrefix: tierAOutcome.detectedPrefix,
      detectedScopePath: tierAOutcome.detectedScopePath,
      ambiguousPrefixes: tierAOutcome.ambiguousPrefixes,
    );
  }

  // ── Tier A ────────────────────────────────────────────────────────────────

  /// Runs Tier A: group candidates by `(scopePath, prefix)` and pick the
  /// highest-scoring group. Returns the winning candidates plus detection
  /// metadata for the [AutoBindResult].
  _TierAOutcome _runTierA({
    required List<SignalBinding> bindings,
    required Iterable<Variable> availableSignals,
    required Map<String, dynamic> currentParameters,
    required DecoderDefinition definition,
    required List<_PrefixAnchor> manuallyBoundAnchors,
    String? forcedPrefix,
  }) {
    if (bindings.isEmpty) {
      // Even if no unbound bindings, manual anchors may still report a
      // prefix/scope so the UI can display "Detected bus: m_axi_".
      if (manuallyBoundAnchors.length == 1) {
        final anchor = manuallyBoundAnchors.first;
        return _TierAOutcome(
          candidates: const {},
          detectedPrefix: anchor.prefix.isEmpty ? null : anchor.prefix,
          detectedScopePath: anchor.scopePath.isEmpty ? null : anchor.scopePath,
        );
      }
      return const _TierAOutcome(candidates: {});
    }

    // For each binding, find every (scope, prefix, signal) tuple that could
    // legitimately resolve it (case-insensitive suffix, width-compatible).
    final perBindingHits = <String, List<_TierAHit>>{};

    for (final binding in bindings) {
      final hits = <_TierAHit>[];
      final expectedWidth = _expectedWidthFor(
        binding: binding,
        currentParameters: currentParameters,
        definition: definition,
      );
      final lowerName = binding.name.toLowerCase();

      for (final variable in availableSignals) {
        if (!_widthCompatible(variable, expectedWidth)) continue;
        final leafLower = variable.name.toLowerCase();
        if (!leafLower.endsWith(lowerName)) continue;
        final prefix = variable.name.substring(
          0,
          variable.name.length - lowerName.length,
        );
        hits.add(
          _TierAHit(
            bindingName: binding.name,
            scopePath: variable.scopePath,
            prefix: prefix,
            signalRef: variable.signalRef,
          ),
        );
      }

      if (hits.isNotEmpty) perBindingHits[binding.name] = hits;
    }

    // Score every (scope, prefix-lower) group by the count of distinct
    // bindings it can resolve. We compare prefixes case-insensitively for
    // grouping but keep the first-seen casing for display.
    final groupScores = <_GroupKey, _GroupInfo>{};

    for (final hits in perBindingHits.values) {
      final seenInThisBinding = <_GroupKey>{};
      for (final hit in hits) {
        final key = _GroupKey(
          scopePath: hit.scopePath,
          prefixLower: hit.prefix.toLowerCase(),
        );
        final info = groupScores.putIfAbsent(
          key,
          () => _GroupInfo(displayPrefix: hit.prefix),
        );
        if (seenInThisBinding.add(key)) info.score++;
        info.hits.putIfAbsent(hit.bindingName, () => hit);
      }
    }

    // Boost groups that match a manually-bound anchor's (scope, prefix).
    for (final anchor in manuallyBoundAnchors) {
      final key = _GroupKey(
        scopePath: anchor.scopePath,
        prefixLower: anchor.prefix.toLowerCase(),
      );
      final info = groupScores[key];
      if (info != null) {
        info.score += anchor.weight;
      }
    }

    if (groupScores.isEmpty) {
      return const _TierAOutcome(candidates: {});
    }

    // If the user forced a specific bus prefix from the disambiguation
    // dropdown, restrict scoring to groups whose prefix matches.
    var rankingPool = groupScores;
    if (forcedPrefix != null) {
      final forcedLower = forcedPrefix.toLowerCase();
      final filtered = <_GroupKey, _GroupInfo>{
        for (final entry in groupScores.entries)
          if (entry.key.prefixLower == forcedLower) entry.key: entry.value,
      };
      if (filtered.isNotEmpty) {
        rankingPool = filtered;
      }
    }

    final ranked = rankingPool.entries.toList()
      ..sort((a, b) => b.value.score.compareTo(a.value.score));

    final winnerEntry = ranked.first;
    final winner = winnerEntry.value;

    // Ambiguity detection: any other group with score within 20% of winner.
    final ambiguousPrefixes = <String>[];
    if (ranked.length > 1) {
      final threshold = winner.score * 0.8;
      for (final entry in ranked) {
        if (entry == winnerEntry) continue;
        if (entry.value.score >= threshold && entry.value.score > 0) {
          final prefix = entry.value.displayPrefix;
          if (prefix.isNotEmpty && !ambiguousPrefixes.contains(prefix)) {
            ambiguousPrefixes.add(prefix);
          }
        }
      }
      if (ambiguousPrefixes.isNotEmpty &&
          winner.displayPrefix.isNotEmpty &&
          !ambiguousPrefixes.contains(winner.displayPrefix)) {
        ambiguousPrefixes.insert(0, winner.displayPrefix);
      }
    }

    final candidates = <String, AutoBindCandidate>{};
    for (final entry in winner.hits.entries) {
      final hit = entry.value;
      final reasonParts = <String>[
        if (winner.displayPrefix.isNotEmpty)
          "shared prefix '${winner.displayPrefix}'",
        if (hit.scopePath.isNotEmpty) 'in scope ${hit.scopePath}',
      ];
      final reason = reasonParts.isEmpty
          ? 'exact suffix match'
          : 'exact suffix match (${reasonParts.join(', ')})';
      candidates[entry.key] = AutoBindCandidate(
        signalRef: hit.signalRef,
        confidence: AutoBindConfidence.exactSuffix,
        matchReason: reason,
      );
    }

    return _TierAOutcome(
      candidates: candidates,
      detectedPrefix: winner.displayPrefix.isEmpty
          ? null
          : winner.displayPrefix,
      detectedScopePath: winnerEntry.key.scopePath.isEmpty
          ? null
          : winnerEntry.key.scopePath,
      ambiguousPrefixes: ambiguousPrefixes,
    );
  }

  /// Builds a list of anchor (scope, prefix) tuples derived from
  /// already-bound signals so Tier A can use them to score groups.
  List<_PrefixAnchor> _manualAnchorsForTierA({
    required Map<String, String?> existingBindings,
    required Map<String, Variable> variablesByRef,
    required List<SignalBinding> allBindings,
  }) {
    final anchors = <_PrefixAnchor>[];
    final bindingsByName = {for (final b in allBindings) b.name: b};
    for (final entry in existingBindings.entries) {
      final ref = entry.value;
      if (ref == null) continue;
      final variable = variablesByRef[ref];
      if (variable == null) continue;
      final binding = bindingsByName[entry.key];
      if (binding == null) continue;
      final lowerName = binding.name.toLowerCase();
      final leafLower = variable.name.toLowerCase();
      // The user may have bound a signal whose leaf name does NOT end with
      // the canonical binding name (the whole point of "manual bindings as
      // unconventional anchors"). Fall back to using the entire leaf as the
      // candidate prefix in that case.
      final prefix = leafLower.endsWith(lowerName)
          ? variable.name.substring(0, variable.name.length - lowerName.length)
          : variable.name;
      anchors.add(
        _PrefixAnchor(
          scopePath: variable.scopePath,
          prefix: prefix,
          // Manual anchors carry strong weight: the user told us this is the
          // bus they want, so any group that overlaps with it should win.
          weight: 100,
        ),
      );
    }
    return anchors;
  }

  // ── Tier B ────────────────────────────────────────────────────────────────

  AutoBindCandidate? _tierBMatch({
    required SignalBinding binding,
    required Iterable<Variable> availableSignals,
    required Map<String, dynamic> currentParameters,
    required DecoderDefinition definition,
  }) {
    final expectedWidth = _expectedWidthFor(
      binding: binding,
      currentParameters: currentParameters,
      definition: definition,
    );
    final lowerName = binding.name.toLowerCase();
    Variable? best;
    for (final variable in availableSignals) {
      if (variable.name.toLowerCase() != lowerName) continue;
      if (!_widthCompatible(variable, expectedWidth)) continue;
      best = variable;
      break;
    }
    if (best == null) return null;
    return AutoBindCandidate(
      signalRef: best.signalRef,
      confidence: AutoBindConfidence.caseInsensitive,
      matchReason:
          "leaf name '${best.name}' matches binding '${binding.name}' "
          '(case-insensitive)',
    );
  }

  // ── Tier C ────────────────────────────────────────────────────────────────

  AutoBindCandidate? _tierCMatch({
    required SignalBinding binding,
    required Iterable<Variable> availableSignals,
    required Map<String, dynamic> currentParameters,
    required DecoderDefinition definition,
  }) {
    final aliases = _knownAliases[binding.name.toLowerCase()];
    if (aliases == null || aliases.isEmpty) return null;

    final expectedWidth = _expectedWidthFor(
      binding: binding,
      currentParameters: currentParameters,
      definition: definition,
    );

    for (final alias in aliases) {
      final aliasLower = alias.toLowerCase();
      for (final variable in availableSignals) {
        if (variable.name.toLowerCase() != aliasLower) continue;
        if (!_widthCompatible(variable, expectedWidth)) continue;
        return AutoBindCandidate(
          signalRef: variable.signalRef,
          confidence: AutoBindConfidence.knownAlias,
          matchReason: "matched alias '$alias' for binding '${binding.name}'",
        );
      }
    }
    return null;
  }

  // ── Tier D ────────────────────────────────────────────────────────────────

  AutoBindCandidate? _tierDMatch({
    required SignalBinding binding,
    required Iterable<Variable> availableSignals,
    required Map<String, dynamic> currentParameters,
    required DecoderDefinition definition,
  }) {
    final expectedWidth = _expectedWidthFor(
      binding: binding,
      currentParameters: currentParameters,
      definition: definition,
    );
    final target = binding.name.toLowerCase();

    final ranked = <_FuzzyHit>[];
    for (final variable in availableSignals) {
      if (!_widthCompatible(variable, expectedWidth)) continue;
      final candidate = variable.name.toLowerCase();
      final distance = AutoBindText.levenshtein(target, candidate);
      if (distance <= 2 && distance > 0) {
        ranked.add(_FuzzyHit(variable: variable, distance: distance));
      }
    }
    if (ranked.isEmpty) return null;
    ranked.sort((a, b) => a.distance.compareTo(b.distance));

    final best = ranked.first.variable;
    final alternatives = ranked
        .skip(1)
        .take(3)
        .map((h) => h.variable.signalRef)
        .toList(growable: false);

    return AutoBindCandidate(
      signalRef: best.signalRef,
      confidence: AutoBindConfidence.fuzzyMatch,
      matchReason:
          "fuzzy match: '${best.name}' is "
          "${ranked.first.distance} edit(s) from '${binding.name}'",
      alternatives: alternatives,
    );
  }

  // ── width helpers ─────────────────────────────────────────────────────────

  /// Resolves the expected bit-width for [binding], factoring in
  /// parameter-driven widths (`addr_width`, `data_width`, `wstrb` →
  /// `data_width / 8`).
  ///
  /// Parameter-driven widths take precedence over the binding's literal
  /// [SignalBinding.bitWidth] when the binding name matches one of the
  /// parameterized patterns and the corresponding parameter is available
  /// — otherwise an AXI4-Lite definition's literal `bitWidth: 32` would
  /// reject 64-bit address signals on a wider bus.
  ///
  /// Falls back to the literal [SignalBinding.bitWidth] when no parameter
  /// pattern applies, and to `null` (any width) when neither applies.
  int? _expectedWidthFor({
    required SignalBinding binding,
    required Map<String, dynamic> currentParameters,
    required DecoderDefinition definition,
  }) {
    final lower = binding.name.toLowerCase();
    final isAddr =
        lower.endsWith('addr') &&
        (lower.startsWith('aw') ||
            lower.startsWith('ar') ||
            lower.startsWith('p'));
    final isData =
        lower.endsWith('data') &&
        (lower.startsWith('w') ||
            lower.startsWith('r') ||
            lower.startsWith('pw') ||
            lower.startsWith('pr'));
    final isStrb = lower == 'wstrb';

    if (isStrb) {
      final dataWidth = _intParam('data_width', currentParameters, definition);
      if (dataWidth != null) return dataWidth ~/ 8;
      return binding.bitWidth;
    }
    if (isData) {
      final dataWidth = _intParam('data_width', currentParameters, definition);
      if (dataWidth != null) return dataWidth;
      return binding.bitWidth;
    }
    if (isAddr) {
      final addrWidth = _intParam('addr_width', currentParameters, definition);
      if (addrWidth != null) return addrWidth;
      return binding.bitWidth;
    }
    return binding.bitWidth;
  }

  int? _intParam(
    String name,
    Map<String, dynamic> currentParameters,
    DecoderDefinition definition,
  ) {
    final v = currentParameters[name];
    if (v is int) return v;
    if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed != null) return parsed;
    }
    for (final p in definition.parameters) {
      if (p.name == name) {
        final dv = p.defaultValue;
        if (dv is int) return dv;
        if (dv is String) {
          final parsed = int.tryParse(dv);
          if (parsed != null) return parsed;
        }
      }
    }
    return null;
  }

  bool _widthCompatible(Variable variable, int? expectedWidth) {
    if (expectedWidth == null) return true;
    final actual = variable.bitWidth;
    if (actual == null) return true;
    return actual == expectedWidth;
  }

  // Levenshtein distance lives in the shared [AutoBindText] helper so the
  // board auto-bind algorithm can use the same implementation.
}

// ── private types ──────────────────────────────────────────────────────────

class _TierAOutcome {
  const _TierAOutcome({
    required this.candidates,
    this.detectedPrefix,
    this.detectedScopePath,
    this.ambiguousPrefixes = const [],
  });

  final Map<String, AutoBindCandidate> candidates;
  final String? detectedPrefix;
  final String? detectedScopePath;
  final List<String> ambiguousPrefixes;
}

class _TierAHit {
  const _TierAHit({
    required this.bindingName,
    required this.scopePath,
    required this.prefix,
    required this.signalRef,
  });

  final String bindingName;
  final String scopePath;
  final String prefix;
  final String signalRef;
}

@immutable
class _GroupKey {
  const _GroupKey({required this.scopePath, required this.prefixLower});

  final String scopePath;
  final String prefixLower;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _GroupKey &&
          scopePath == other.scopePath &&
          prefixLower == other.prefixLower;

  @override
  int get hashCode => Object.hash(scopePath, prefixLower);
}

class _GroupInfo {
  _GroupInfo({required this.displayPrefix});

  final String displayPrefix;
  int score = 0;
  final Map<String, _TierAHit> hits = {};
}

class _PrefixAnchor {
  const _PrefixAnchor({
    required this.scopePath,
    required this.prefix,
    required this.weight,
  });

  final String scopePath;
  final String prefix;
  final int weight;
}

class _FuzzyHit {
  const _FuzzyHit({required this.variable, required this.distance});

  final Variable variable;
  final int distance;
}
