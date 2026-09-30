// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/config_param.dart';
import 'package:wavecrux/features/stage/widgets/primitives/builtin_stage_widgets.dart';
import 'package:wavecrux/features/stage/widgets/riscv/riscv_commit_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_renderer_registry.dart';
import 'package:wavecrux/plugins/stage_registry.dart';
import 'package:wavecrux/services/riscv/rvfi_channel.dart';
import 'package:wavecrux/services/riscv/rvfi_detection_service.dart';
import 'package:wavecrux/services/stage/stage_auto_bind_resolver.dart';

void main() {
  const widget = RiscvCommitStageWidget();

  group('definition', () {
    test('uses the bare open-core id convention', () {
      expect(widget.id, 'riscv_commit');
      expect(RiscvCommitStageWidget.widgetId, 'riscv_commit');
    });

    test('is open core, and stays open core', () {
      // The tier line for this family is "correctness is free, productivity
      // is paid". Flipping this to Pro to make the family look uniform inverts
      // that line — do not revert it.
      expect(widget.requiredTier, LicenseTier.openCore);
    });

    test('reuses the instrument category rather than adding one', () {
      expect(widget.category, StageWidgetCategory.instrument);
    });

    test('declares a localized display name', () {
      expect(widget.displayNameKey, 'stageRiscvCommitDisplayName');
      expect(widget.displayName, isNotEmpty);
    });
  });

  group('pins', () {
    test('declares exactly one pin per RVFI channel', () {
      final names = <String>[
        for (final b in widget.requiredSignals) b.name,
        for (final b in widget.optionalSignals) b.name,
      ];
      expect(names, hasLength(RvfiChannel.values.length));
      expect(names.toSet(), hasLength(names.length));
    });

    test('pin names are the canonical riscv-formal port names', () {
      // Auto-bind resolves pins by parsing their names as RVFI ports, so a
      // pin named anything else silently stops being auto-bindable.
      final names = <String>[
        for (final b in widget.requiredSignals) b.name,
        for (final b in widget.optionalSignals) b.name,
      ];
      for (final channel in RvfiChannel.values) {
        expect(
          names,
          contains(channel.signalName),
          reason: 'no pin for ${channel.signalName}',
        );
      }
      for (final name in names) {
        expect(
          RvfiDetectionService.parseName(name)?.channel.signalName,
          name,
          reason: '"$name" does not parse back to itself as an RVFI channel',
        );
      }
    });

    test('required pins are exactly the three the substrate cannot work '
        'without', () {
      expect(
        widget.requiredSignals.map((b) => b.name).toSet(),
        {'rvfi_valid', 'rvfi_insn', 'rvfi_pc_rdata'},
      );
      for (final channel in RvfiChannel.values.where((c) => c.isRequired)) {
        expect(
          widget.requiredSignals.map((b) => b.name),
          contains(channel.signalName),
        );
      }
    });

    test('every pin carries a description', () {
      for (final b in [...widget.requiredSignals, ...widget.optionalSignals]) {
        expect(b.description, isNotEmpty, reason: b.name);
      }
    });

    test('no pin is conditionally hidden — every RVFI channel is bindable', () {
      for (final b in [...widget.requiredSignals, ...widget.optionalSignals]) {
        expect(b.isVisibleIn(const {}), isTrue, reason: b.name);
      }
    });
  });

  group('auto-bind wiring', () {
    test('declares the RVFI matcher and therefore supports auto-bind', () {
      expect(widget.autoBindService, isA<RvfiDetectionService>());
      expect(widget.supportsAutoBind, isTrue);
      expect(widget.isCompound, isFalse);
    });

    test('the resolver picks the declared matcher, not the board one', () {
      expect(stageAutoBindServiceFor(widget), isA<RvfiDetectionService>());
    });

    test('declares its own dialog title instead of the board heading', () {
      // The default title reads "Auto-bind board signals", which is wrong for
      // a riscv-formal channel bundle.
      expect(widget.autoBindTitleKey, 'stageRvfiAutoBindTitle');
    });
  });

  group('configuration', () {
    test('every param and group declares an ARB key', () {
      for (final p in widget.configParams) {
        expect(p.labelKey, isNotEmpty, reason: p.id);
        for (final c in p.choices ?? const <ConfigParamChoice>[]) {
          expect(c.labelKey, isNotEmpty, reason: '${p.id}.${c.id}');
        }
      }
      for (final g in widget.configGroups) {
        expect(g.labelKey, isNotEmpty, reason: g.id);
      }
    });

    test('register-count offers only the two legal architectural values', () {
      final p = widget.configParams.firstWhere(
        (p) => p.id == RiscvCommitStageWidget.paramRegisterCount,
      );
      expect(p.min, 16); // RV32E
      expect(p.max, 32); // RV32I / RV64I
      expect(p.step, 16);
      expect(p.defaultValue, 32);
    });

    test('there is no row cap, watermark or upsell knob', () {
      // A crippled free widget lands worse than an omitted feature.
      final ids = widget.configParams.map((p) => p.id).toList();
      expect(
        ids.any(
          (id) =>
              id.toLowerCase().contains('limit') ||
              id.toLowerCase().contains('max') && id != 'maxSize',
        ),
        isFalse,
        reason: 'configuration hints at a cap: $ids',
      );
    });
  });

  group('RiscvCommitRegisterNaming', () {
    test('round-trips its stored ids', () {
      for (final v in RiscvCommitRegisterNaming.values) {
        expect(RiscvCommitRegisterNaming.parse(v.id), v);
      }
    });

    test('defaults to ABI for unknown or missing values', () {
      expect(
        RiscvCommitRegisterNaming.parse(null),
        RiscvCommitRegisterNaming.abi,
      );
      expect(
        RiscvCommitRegisterNaming.parse('nonsense'),
        RiscvCommitRegisterNaming.abi,
      );
    });

    test('the config param default matches the enum default', () {
      final p = const RiscvCommitStageWidget().configParams.firstWhere(
        (p) => p.id == RiscvCommitStageWidget.paramRegisterNaming,
      );
      expect(
        RiscvCommitRegisterNaming.parse(p.defaultValue),
        RiscvCommitRegisterNaming.abi,
      );
    });
  });

  group('registration', () {
    setUp(registerBuiltinStageWidgets);
    tearDown(clearBuiltinStageWidgets);

    test('is a built-in open-core Stage widget', () {
      final registered = StageRegistry.instance.get(
        RiscvCommitStageWidget.widgetId,
      );
      expect(registered, isA<RiscvCommitStageWidget>());
    });

    test('has a renderer registered under the same id', () {
      expect(
        StageWidgetRendererRegistry.instance.get(
          RiscvCommitStageWidget.widgetId,
        ),
        isNotNull,
      );
    });
  });
}
