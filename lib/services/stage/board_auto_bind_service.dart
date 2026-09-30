// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/compound_stage_widget.dart';
import 'package:wavecrux/domain/interfaces/stage_auto_bind_service.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/board_auto_bind_candidate.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_widget_slot.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/auto_bind/auto_bind_text.dart';
import 'package:wavecrux/services/stage/stage_slot_family.dart';

/// Common-synonym table for board slot names.
///
/// Used by the alias tier when direct matching fails. Each canonical
/// slot prefix maps to the alternative names that real designs commonly
/// use. Matches are case-insensitive on the leaf signal name.
const Map<String, List<String>> _knownAliases = {
  // LEDs / lights
  'led': ['leds', 'ld', 'light', 'lights'],
  'ld': ['led', 'leds'],
  'ledr': ['led', 'leds', 'red_led'],
  'ledg': ['led', 'leds', 'green_led'],

  // Switches / DIP / slide
  'sw': ['sws', 'switch', 'dip', 'slide_switch'],
  'switch': ['sw', 'sws'],

  // Buttons / keys
  'btn': ['key', 'button', 'push'],
  'key': ['btn', 'button', 'push'],

  // Seven-segment digits / hex displays
  'digit': ['seg', 'hex', 'sevenseg'],
  'hex': ['seg', 'digit', 'sevenseg'],
  'seg': ['digit', 'hex', 'sevenseg'],
  'an': ['anode', 'an_n', 'sevenseg_an'],
};

/// Computes a best-guess auto-binding of every slot on a compound
/// board widget against the signals available in the loaded waveform.
///
/// The algorithm walks four tiers per family / slot:
///
/// - **Vector fan-out** (strongest) — find a vector signal whose
///   bitWidth equals the family's size and whose leaf name (or a
///   known alias) matches the family's prefix. Every member of the
///   family is bound to the matching bit of the vector. This is
///   what makes "drop one signal, bind 16 LEDs" feel magic.
/// - **Exact / alias** — one 1-bit signal matched directly or via the
///   alias table. Used for individual-bit signal layouts and for
///   non-family slots like `btnC`.
/// - **Fuzzy** — Levenshtein distance ≤ 2 against the slot name.
/// - **No match** — slot is left unbound; the user can still drag the
///   signal manually.
///
/// Pure Dart, no Flutter imports. The UI layer
/// ([BoardAutoBindPreviewDialog]) sits on top of this.
///
/// This is the first of the two open-core [StageAutoBindService]
/// implementations, and the one the bindings pane resolves for every
/// [CompoundStageWidget] — [autoBind] is a thin adapter that unpacks the
/// widget's slots and delegates to the unchanged [computeBindings], so the
/// board matching behavior is identical to what it was before the interface
/// existed.
class BoardAutoBindService implements StageAutoBindService {
  const BoardAutoBindService();

  /// Interface adapter. Non-compound widgets have no slots to match, so they
  /// get an empty result rather than a wrong one — a non-compound widget
  /// reaching this implementation means the resolver was bypassed.
  @override
  BoardAutoBindResult autoBind({
    required StageWidget widget,
    required Map<String, Variable> availableSignals,
    Map<String, StageSignalBinding> existingBindings = const {},
    Map<String, Object?> configuration = const {},
  }) {
    if (widget is! CompoundStageWidget) {
      return const BoardAutoBindResult(candidates: {});
    }
    return computeBindings(
      slots: widget.slots,
      availableSignals: availableSignals,
      existingBindings: existingBindings,
    );
  }

  /// Computes auto-bind candidates for every slot in [slots] given the
  /// signals available in [availableSignals] and any [existingBindings]
  /// the user has already created. Existing manual bindings are
  /// preserved as passthrough candidates with a `manually bound` reason.
  BoardAutoBindResult computeBindings({
    required List<StageWidgetSlot> slots,
    required Map<String, Variable> availableSignals,
    Map<String, StageSignalBinding> existingBindings = const {},
  }) {
    final variablesByRef = <String, Variable>{
      for (final v in availableSignals.values) v.signalRef: v,
    };
    final candidates = <String, BoardAutoBindCandidate>{};

    // Honor manual bindings as passthroughs.
    for (final slot in slots) {
      final existing = existingBindings[slot.name];
      if (existing != null && variablesByRef.containsKey(existing.signalRef)) {
        candidates[slot.name] = BoardAutoBindCandidate(
          confidence: BoardAutoBindConfidence.exactMatch,
          matchReason: 'manually bound',
          binding: existing,
        );
      }
    }

    final variables = availableSignals.values.toList();

    // ── Family-aware tiers ──────────────────────────────────────────
    final families = StageSlotFamilyResolver.groupFamilies(slots);
    final consumedSlots = <String>{};

    for (final family in families.values) {
      // Skip singletons — they're handled by the per-slot tier below.
      if (family.size <= 1) continue;
      // Skip families where every member is already manually bound.
      final allBound = family.members.every(
        (m) => candidates.containsKey(m.slot.name),
      );
      if (allBound) {
        for (final m in family.members) {
          consumedSlots.add(m.slot.name);
        }
        continue;
      }

      // Vector fan-out match.
      final vectorMatch = _vectorMatchForFamily(
        family.prefix,
        family.size,
        variables,
      );
      if (vectorMatch != null) {
        for (final m in family.members) {
          // Skip slots that already have a manual binding — don't
          // overwrite the user's choice.
          if (candidates.containsKey(m.slot.name)) {
            consumedSlots.add(m.slot.name);
            continue;
          }
          candidates[m.slot.name] = BoardAutoBindCandidate(
            confidence: BoardAutoBindConfidence.vectorFanOut,
            matchReason:
                "vector match: '${vectorMatch.name}' is "
                '${family.size} bits wide; bit ${m.index - family.minIndex} '
                "→ slot '${m.slot.name}'",
            binding: StageSignalBinding(
              signalRef: vectorMatch.signalRef,
              bitIndex: m.index - family.minIndex,
            ),
            familyPrefix: family.prefix,
          );
          consumedSlots.add(m.slot.name);
        }
        continue;
      }

      // Per-bit match: find one 1-bit signal per family member
      // (e.g. led0/led1/.../led15 OR led[0]/led[1]/...).
      final perBitMatches = _perBitMatchesForFamily(
        family.prefix,
        family.members.map((m) => m.index).toList(),
        variables,
      );
      if (perBitMatches.length == family.size) {
        for (final m in family.members) {
          if (candidates.containsKey(m.slot.name)) {
            consumedSlots.add(m.slot.name);
            continue;
          }
          final matched = perBitMatches[m.index]!;
          candidates[m.slot.name] = BoardAutoBindCandidate(
            confidence: BoardAutoBindConfidence.exactMatch,
            matchReason:
                "per-bit match: '${matched.name}' → slot '${m.slot.name}'",
            binding: StageSignalBinding(signalRef: matched.signalRef),
          );
          consumedSlots.add(m.slot.name);
        }
        continue;
      }
      // Fall through to per-slot tier for individual fuzzy / alias /
      // no-match handling on the slots that the family-level tiers
      // could not resolve.
    }

    // ── Per-slot tier ───────────────────────────────────────────────
    for (final slot in slots) {
      if (candidates.containsKey(slot.name)) continue;
      final match = _matchSingleSlot(slot.name, variables);
      candidates[slot.name] = match;
    }

    return BoardAutoBindResult(candidates: candidates);
  }

  /// Returns a vector signal whose bitWidth is exactly [familySize]
  /// and whose leaf name matches [prefix] (case-insensitive, plus the
  /// known alias table). When multiple are found, prefers the one
  /// whose name is shorter (closer to a pure prefix match).
  Variable? _vectorMatchForFamily(
    String prefix,
    int familySize,
    List<Variable> variables,
  ) {
    final lowerPrefix = prefix.toLowerCase();
    final aliases = _knownAliases[lowerPrefix] ?? const <String>[];
    final candidates = <String>{
      lowerPrefix,
      ...aliases.map((a) => a.toLowerCase()),
    };

    Variable? best;
    var bestNameLength = 1 << 30;
    for (final v in variables) {
      if (v.bitWidth != familySize) continue;
      final leaf = v.name.toLowerCase();
      // Accept: leaf == prefix (e.g. 'leds'), or leaf endsWith prefix
      // (e.g. 'gpio_leds'), or alias variants.
      if (!candidates.any(
        (cand) =>
            leaf == cand || leaf.endsWith('_$cand') || leaf.endsWith(cand),
      )) {
        continue;
      }
      if (v.name.length < bestNameLength) {
        bestNameLength = v.name.length;
        best = v;
      }
    }
    return best;
  }

  /// Looks for one 1-bit signal per requested [indices] under [prefix]
  /// (e.g. led0, led1, led[0], led[1], …). Returns a map from index
  /// to matched [Variable]; missing indices are simply absent.
  Map<int, Variable> _perBitMatchesForFamily(
    String prefix,
    List<int> indices,
    List<Variable> variables,
  ) {
    final lowerPrefix = prefix.toLowerCase();
    final result = <int, Variable>{};
    for (final i in indices) {
      Variable? hit;
      for (final v in variables) {
        if (v.bitWidth != 1) continue;
        final leaf = v.name.toLowerCase();
        if (leaf == '$lowerPrefix$i' || leaf == '$lowerPrefix[$i]') {
          hit = v;
          break;
        }
      }
      if (hit != null) result[i] = hit;
    }
    return result;
  }

  BoardAutoBindCandidate _matchSingleSlot(
    String slotName,
    List<Variable> variables,
  ) {
    final lowerSlot = slotName.toLowerCase();

    // Exact / case-insensitive match on the leaf name.
    for (final v in variables) {
      if (v.name.toLowerCase() == lowerSlot) {
        return BoardAutoBindCandidate(
          confidence: BoardAutoBindConfidence.exactMatch,
          matchReason: "leaf name '${v.name}' matches '$slotName'",
          binding: StageSignalBinding(signalRef: v.signalRef),
        );
      }
    }

    // Alias match.
    final aliases = _knownAliases[lowerSlot] ?? const <String>[];
    for (final alias in aliases) {
      final lowerAlias = alias.toLowerCase();
      for (final v in variables) {
        if (v.name.toLowerCase() == lowerAlias) {
          return BoardAutoBindCandidate(
            confidence: BoardAutoBindConfidence.knownAlias,
            matchReason: "matched alias '$alias' for slot '$slotName'",
            binding: StageSignalBinding(signalRef: v.signalRef),
          );
        }
      }
    }

    // Fuzzy match.
    Variable? best;
    var bestDistance = 3;
    for (final v in variables) {
      final distance = AutoBindText.levenshtein(
        lowerSlot,
        v.name.toLowerCase(),
      );
      if (distance < bestDistance && distance > 0 && distance <= 2) {
        bestDistance = distance;
        best = v;
      }
    }
    if (best != null) {
      return BoardAutoBindCandidate(
        confidence: BoardAutoBindConfidence.fuzzyMatch,
        matchReason:
            "fuzzy match: '${best.name}' is $bestDistance edit(s) "
            "from '$slotName'",
        binding: StageSignalBinding(signalRef: best.signalRef),
      );
    }

    return BoardAutoBindCandidate(
      confidence: BoardAutoBindConfidence.noMatch,
      matchReason: "no plausible signal for slot '$slotName'",
    );
  }
}
