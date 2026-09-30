// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/var_type.dart';

/// A broad grouping of [VarType]s used in the signal search dialog filter.
///
/// Each category maps to the set of [VarType] values that belong to it.
/// Selecting a category in the UI restricts results to signals whose
/// [VarType] is a member of that category's [varTypes] set.
enum SignalTypeCategory {
  wire,
  reg,
  integer,
  real,
  port;

  /// The [VarType] values that belong to this category.
  Set<VarType> get varTypes => switch (this) {
    SignalTypeCategory.wire => const {
      VarType.wire,
      VarType.logic,
      VarType.bit,
      VarType.tri,
      VarType.triAnd,
      VarType.triOr,
      VarType.triReg,
      VarType.tri0,
      VarType.tri1,
      VarType.wAnd,
      VarType.wOr,
      VarType.supply0,
      VarType.supply1,
      VarType.stdLogic,
      VarType.stdLogicVector,
      VarType.stdULogic,
      VarType.stdULogicVector,
      VarType.bitVector,
      VarType.boolean,
    },
    SignalTypeCategory.reg => const {VarType.reg},
    SignalTypeCategory.integer => const {
      VarType.integer,
      VarType.time,
      VarType.svInt,
      VarType.svShortInt,
      VarType.svLongInt,
      VarType.svByte,
      VarType.svEnum,
    },
    SignalTypeCategory.real => const {
      VarType.real,
      VarType.realTime,
      VarType.svShortReal,
      VarType.realParameter,
    },
    SignalTypeCategory.port => const {VarType.port},
  };
}
