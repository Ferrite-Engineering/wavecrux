// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_widget_slot.dart';

/// A [StageWidget] that composes one or more child primitive widgets onto
/// a backdrop illustration.
///
/// Compound widgets describe FPGA development boards (Basys 3, DE10-Lite,
/// Nexys A7) and dashboards (gauge cluster, register-file viewer). Each
/// child is a [StageWidgetSlot] pinned to a normalised position on the
/// backdrop and bound to one signal input of the compound.
///
/// The compound's [requiredSignals] / [optionalSignals] are derived from
/// the child slots: each slot contributes one [SignalBinding] whose name
/// equals [StageWidgetSlot.name]. Subclasses are free to add extra
/// bindings beyond the slot set if a child needs more than one signal.
///
/// Pure Dart — no Flutter imports. Implementations must be `const`.
abstract class CompoundStageWidget extends StageWidget {
  const CompoundStageWidget();

  @override
  bool get isCompound => true;

  /// Ordered list of child-widget slots that make up this compound.
  ///
  /// Slot positions are normalised (`0..1`) so the compound scales when
  /// resized inside a Stage panel.
  List<StageWidgetSlot> get slots;

  /// Default `requiredSignals` derived from the slots. Subclasses may
  /// override to add extra bindings or to mark some slots as optional.
  @override
  List<SignalBinding> get requiredSignals => [
    for (final slot in slots)
      SignalBinding(
        name: slot.name,
        description: slot.label ?? slot.name,
      ),
  ];
}
