// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/compound_stage_widget.dart';
import 'package:wavecrux/domain/interfaces/stage_auto_bind_service.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/board_auto_bind_candidate.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_widget_slot.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/riscv/rvfi_detection_service.dart';
import 'package:wavecrux/services/stage/board_auto_bind_service.dart';
import 'package:wavecrux/services/stage/stage_auto_bind_resolver.dart';

/// A compound board — the pre-existing shape of an auto-bindable widget.
class _BoardStub extends CompoundStageWidget {
  const _BoardStub();
  @override
  String get id => 'board_stub';
  @override
  String get displayName => 'Board';
  @override
  String get description => '';
  @override
  StageWidgetCategory get category => StageWidgetCategory.board;
  @override
  List<StageWidgetSlot> get slots => const [
    StageWidgetSlot(
      name: 'led0',
      childWidgetId: 'led',
      x: 0,
      y: 0,
      width: 0.1,
      height: 0.1,
    ),
  ];
}

/// A plain primitive — no slots, no auto-bind.
class _PrimitiveStub extends StageWidget {
  const _PrimitiveStub();
  @override
  String get id => 'primitive_stub';
  @override
  String get displayName => 'Primitive';
  @override
  String get description => '';
  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;
  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(name: 'value', description: 'Value'),
  ];
}

/// A non-compound widget that declares its own matcher — the seam this test
/// exists for.
class _RvfiWidgetStub extends StageWidget {
  const _RvfiWidgetStub();
  @override
  String get id => 'rvfi_stub';
  @override
  String get displayName => 'RVFI';
  @override
  String get description => '';
  @override
  StageWidgetCategory get category => StageWidgetCategory.instrument;
  @override
  List<SignalBinding> get requiredSignals => const [
    SignalBinding(name: 'rvfi_valid', description: 'valid'),
  ];
  @override
  StageAutoBindService? get autoBindService => const RvfiDetectionService();
}

/// A widget that explicitly declines the affordance.
class _OptedOutStub extends CompoundStageWidget {
  const _OptedOutStub();
  @override
  String get id => 'opted_out';
  @override
  String get displayName => 'Opted out';
  @override
  String get description => '';
  @override
  StageWidgetCategory get category => StageWidgetCategory.board;
  @override
  bool get supportsAutoBind => false;
  @override
  List<StageWidgetSlot> get slots => const [];
}

void main() {
  group('StageWidget.supportsAutoBind', () {
    test('defaults to true for a compound widget', () {
      expect(const _BoardStub().supportsAutoBind, isTrue);
      expect(const _BoardStub().autoBindService, isNull);
    });

    test('defaults to false for a plain primitive', () {
      expect(const _PrimitiveStub().supportsAutoBind, isFalse);
    });

    test('is true for a non-compound widget that declares a service', () {
      expect(const _RvfiWidgetStub().supportsAutoBind, isTrue);
    });
  });

  group('stageAutoBindServiceFor', () {
    test('resolves a compound widget to the board matcher', () {
      expect(
        stageAutoBindServiceFor(const _BoardStub()),
        isA<BoardAutoBindService>(),
      );
    });

    test('resolves a declared service ahead of the compound fallback', () {
      expect(
        stageAutoBindServiceFor(const _RvfiWidgetStub()),
        isA<RvfiDetectionService>(),
      );
    });

    test('resolves nothing for a plain primitive', () {
      expect(stageAutoBindServiceFor(const _PrimitiveStub()), isNull);
    });

    test('honors an explicit opt-out', () {
      expect(stageAutoBindServiceFor(const _OptedOutStub()), isNull);
    });
  });

  group('BoardAutoBindService as a StageAutoBindService', () {
    const service = BoardAutoBindService();

    Variable led(String name, int width) => Variable(
      name: name,
      varType: VarType.wire,
      direction: VarDirection.unknown,
      signalRef: 'ref_$name',
      scopePath: 'top',
      bitWidth: width,
    );

    test('autoBind delegates to computeBindings unchanged', () {
      final signals = {'ref_led0': led('led0', 1)};
      final viaInterface = service.autoBind(
        widget: const _BoardStub(),
        availableSignals: signals,
      );
      final direct = service.computeBindings(
        slots: const _BoardStub().slots,
        availableSignals: signals,
      );
      expect(viaInterface.candidates.keys, direct.candidates.keys);
      for (final key in direct.candidates.keys) {
        expect(
          viaInterface.candidates[key]!.confidence,
          direct.candidates[key]!.confidence,
        );
        expect(
          viaInterface.candidates[key]!.binding,
          direct.candidates[key]!.binding,
        );
        expect(
          viaInterface.candidates[key]!.matchReason,
          direct.candidates[key]!.matchReason,
        );
      }
    });

    test('passes existing bindings through as manual candidates', () {
      final result = service.autoBind(
        widget: const _BoardStub(),
        availableSignals: {'ref_led0': led('led0', 1)},
        existingBindings: const {
          'led0': StageSignalBinding(signalRef: 'ref_led0'),
        },
      );
      expect(result.candidates['led0']!.matchReason, 'manually bound');
    });

    test('returns nothing for a non-compound widget', () {
      final result = service.autoBind(
        widget: const _PrimitiveStub(),
        availableSignals: const {},
      );
      expect(result.candidates, isEmpty);
    });

    test('still reports a no-match slot rather than omitting it', () {
      final result = service.autoBind(
        widget: const _BoardStub(),
        availableSignals: const {},
      );
      expect(
        result.candidates['led0']!.confidence,
        BoardAutoBindConfidence.noMatch,
      );
    });
  });
}
