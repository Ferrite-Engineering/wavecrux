// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/stage_widget_slot.dart';

/// One slot in a numbered family — `led0`, `led1`, ... — used by
/// [StageSlotFamilyResolver] to group slots whose names share a prefix
/// and end with a numeric suffix.
///
/// A family of size N (e.g. all 16 LEDs of a Basys 3) is a candidate
/// for vector-fan-out: dropping a 16-bit signal onto any one slot can
/// auto-bind every slot in the family to the matching bit of the
/// vector. See `applyDropBinding` in
/// `lib/features/stage/widgets/draggable_resizable_instance.dart`.
///
/// Pure Dart — no Flutter imports.
@immutable
class StageSlotFamilyMember {
  const StageSlotFamilyMember({required this.slot, required this.index});

  final StageWidgetSlot slot;
  final int index;
}

/// A coherent slot family, e.g. `led0` … `led15`.
@immutable
class StageSlotFamily {
  const StageSlotFamily({
    required this.prefix,
    required this.members,
  });

  /// Common name prefix (e.g. `'led'`, `'sw'`).
  final String prefix;

  /// Members ordered by their numeric suffix, ascending.
  final List<StageSlotFamilyMember> members;

  /// Number of distinct indices in the family.
  int get size => members.length;

  /// The smallest numeric suffix that appears in the family.
  int get minIndex => members.first.index;

  /// The largest numeric suffix that appears in the family.
  int get maxIndex => members.last.index;
}

/// Static helpers for detecting slot families and locating which family
/// a given slot belongs to.
class StageSlotFamilyResolver {
  const StageSlotFamilyResolver._();

  /// Splits a slot name into `(prefix, index)` for slots whose name
  /// ends in a contiguous run of digits, or returns `null` for slots
  /// without a numeric suffix (`btnC`, `clk_50`, `JA`, …).
  ///
  /// Bracketed forms like `led[0]` are also recognised.
  static ({String prefix, int index})? parseName(String name) {
    // led[0] / sw[15] form.
    final bracket = RegExp(r'^(.+)\[(\d+)\]$').firstMatch(name);
    if (bracket != null) {
      return (
        prefix: bracket.group(1)!,
        index: int.parse(bracket.group(2)!),
      );
    }
    // led0 / sw15 form (digits only at the very end). Reject names
    // that are entirely digits.
    final trail = RegExp(r'^([A-Za-z_][A-Za-z_0-9]*?)(\d+)$').firstMatch(name);
    if (trail != null) {
      return (
        prefix: trail.group(1)!,
        index: int.parse(trail.group(2)!),
      );
    }
    return null;
  }

  /// Groups [slots] into families by shared prefix and numeric suffix.
  /// Slots whose names don't fit the `(prefix, index)` shape are
  /// dropped from the result.
  ///
  /// Families with only one member are still returned — callers
  /// typically filter for `size > 1` before treating a drop as a
  /// fan-out candidate.
  static Map<String, StageSlotFamily> groupFamilies(
    List<StageWidgetSlot> slots,
  ) {
    final byPrefix = <String, List<StageSlotFamilyMember>>{};
    for (final slot in slots) {
      final parsed = parseName(slot.name);
      if (parsed == null) continue;
      byPrefix
          .putIfAbsent(parsed.prefix, () => [])
          .add(StageSlotFamilyMember(slot: slot, index: parsed.index));
    }
    final result = <String, StageSlotFamily>{};
    for (final entry in byPrefix.entries) {
      final members = [...entry.value]
        ..sort((a, b) => a.index.compareTo(b.index));
      result[entry.key] = StageSlotFamily(
        prefix: entry.key,
        members: members,
      );
    }
    return result;
  }

  /// Returns the family containing [slotName], or `null` when [slotName]
  /// has no numeric suffix or no other slots share its prefix.
  static StageSlotFamily? familyOf(
    List<StageWidgetSlot> slots,
    String slotName,
  ) {
    final parsed = parseName(slotName);
    if (parsed == null) return null;
    final all = groupFamilies(slots);
    final family = all[parsed.prefix];
    if (family == null || family.size <= 1) return null;
    return family;
  }
}
