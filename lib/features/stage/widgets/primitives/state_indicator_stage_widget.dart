// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// One row in a [StateIndicatorStageRenderer]'s state map.
@immutable
class StateIndicatorEntry {
  const StateIndicatorEntry({required this.label, required this.color});

  final String label;
  final Color color;
}

/// Result of resolving a snapshot against a state map.
@immutable
class StateIndicatorReading {
  const StateIndicatorReading({required this.label, required this.color});

  final String label;
  final Color color;
}

/// Default visual when nothing matches: a neutral grey badge with `'??'`.
const _kUnknownState = StateIndicatorReading(
  label: '??',
  color: Color(0xFF455A64),
);

const _kUnboundState = StateIndicatorReading(
  label: '–',
  color: Color(0xFF263238),
);

const _kErrorState = StateIndicatorReading(
  label: 'X',
  color: Color(0xFFE53935),
);

/// Pure logic: pick a [StateIndicatorReading] for a snapshot.
///
/// [stateMap] keys are unsigned-decimal interpretations of the bound signal.
/// When the value falls outside the map, [_kUnknownState] is returned.
StateIndicatorReading resolveStateIndicatorReading(
  StageSignalSnapshot snapshot,
  Map<int, StateIndicatorEntry> stateMap,
) {
  if (!snapshot.hasValue) return _kUnboundState;
  if (snapshot.hasX || snapshot.hasZ) return _kErrorState;
  final intValue = snapshot.intValue;
  if (intValue == null) return _kUnknownState;
  // Larger-than-int values cannot be enum keys.
  if (!intValue.isValidInt) return _kUnknownState;
  final entry = stateMap[intValue.toInt()];
  if (entry == null) return _kUnknownState;
  return StateIndicatorReading(label: entry.label, color: entry.color);
}

/// Definition for the state-indicator primitive.
class StateIndicatorStageWidget extends StageWidget {
  const StateIndicatorStageWidget();

  static const String widgetId = 'state_indicator';

  @override
  String get id => widgetId;

  @override
  String get displayName => 'State Indicator';

  @override
  String? get displayNameKey => 'stageStateIndicatorDisplayName';

  @override
  String get description =>
      'Labeled colored badge for enum signals — IDLE / RUNNING / ERROR / etc.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;

  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(
      name: 'state',
      description: 'Enum / state signal to display',
    ),
  ];

  @override
  (double, double) get defaultSize => (160, 80);

  @override
  (double, double) get minSize => (90, 40);
}

/// Renders a [StateIndicatorStageWidget] instance.
class StateIndicatorStageRenderer extends ConsumerWidget {
  const StateIndicatorStageRenderer({
    required this.instance,
    this.stateMap = _defaultStates,
    super.key,
  });

  final StageInstance instance;
  final Map<int, StateIndicatorEntry> stateMap;

  /// Default mapping used when the user has not defined their own —
  /// the canonical IDLE / RUNNING / ERROR example.
  static const Map<int, StateIndicatorEntry> _defaultStates = {
    0: StateIndicatorEntry(label: 'IDLE', color: Color(0xFF43A047)),
    1: StateIndicatorEntry(label: 'RUNNING', color: Color(0xFF1E88E5)),
    2: StateIndicatorEntry(label: 'WAIT', color: Color(0xFFFFB300)),
    3: StateIndicatorEntry(label: 'ERROR', color: Color(0xFFE53935)),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10N.of(context);
    final binding = instance.signalBindings['state'];
    final snapshot = ref.watch(stageBoundSignalProvider(binding));
    final reading = resolveStateIndicatorReading(snapshot, stateMap);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: reading.color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white24),
            boxShadow: [
              BoxShadow(
                color: reading.color.withValues(alpha: 0.4),
                blurRadius: 8,
              ),
            ],
          ),
          child: Semantics(
            label: l10n.stageStateIndicatorSemanticLabel(reading.label),
            child: Text(
              reading.label,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
