// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/models/config_param.dart';
import 'package:wavecrux/features/stage/widgets/pipeline/pipeline_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/builtin_stage_widgets.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_renderer_registry.dart';
import 'package:wavecrux/plugins/stage_registry.dart';
import 'package:wavecrux/services/riscv/riscv_instruction_identity.dart';

void main() {
  const widget = PipelineStageWidget();

  group('identity', () {
    test('the id is the bare architecture-neutral `pipeline`', () {
      // Deliberately **not** `riscv_pipeline`. There is no ISA content in this
      // widget — user-named stages plus valid / stall / flush is generic
      // pipeline occupancy, and the id lands in shipped `.wavecrux` sessions
      // where a rename becomes a migration.
      expect(PipelineStageWidget.widgetId, 'pipeline');
      expect(widget.id, 'pipeline');
    });

    test('open core, instrument category, localizable name', () {
      expect(widget.requiredTier, LicenseTier.openCore);
      expect(widget.category, StageWidgetCategory.instrument);
      expect(widget.displayNameKey, 'stagePipelineDisplayName');
      expect(widget.displayName, isNotEmpty);
    });

    test('carries no ISA vocabulary in its own surface', () {
      // The RISC-V flavour belongs to the preset (the default stage names and
      // the bundled fixture), never to the widget's declared strings — the
      // moment it does, an FFT or packet-pipeline user reads this as "not for
      // me".
      final surface = <String>[
        widget.id,
        widget.description,
        widget.displayName,
        widget.displayNameKey!,
        for (final b in [...widget.requiredSignals, ...widget.optionalSignals])
          '${b.name} ${b.description}',
        for (final p in widget.configParams) '${p.id} ${p.labelKey}',
        for (final g in widget.configGroups) '${g.id} ${g.labelKey}',
      ].join(' ').toLowerCase();
      for (final term in const ['riscv', 'risc-v', 'rvfi', 'rv32', 'rv64']) {
        expect(
          surface.contains(term),
          isFalse,
          reason: '"$term" leaked into an architecture-neutral widget',
        );
      }
    });

    test('offers no auto-bind — there are no canonical pin names to match', () {
      // Unlike the RVFI bundle, per-stage control signals have no standard
      // naming, so an auto-binder would be guessing. `autoBindTitleKey` stays
      // null with it.
      expect(widget.supportsAutoBind, isFalse);
      expect(widget.autoBindService, isNull);
      expect(widget.autoBindTitleKey, isNull);
    });
  });

  group('pins', () {
    test('the clock is the only required pin', () {
      expect(widget.requiredSignals.map((b) => b.name), ['clk']);
    });

    test('four pins per stage for eight stages, plus the instruction word', () {
      final names = widget.optionalSignals.map((b) => b.name).toList();
      expect(names.first, 'instruction');
      for (var s = 1; s <= kPipelineMaxStages; s++) {
        for (final role in const ['valid', 'pc', 'stall', 'flush']) {
          expect(names, contains('stage${s}_$role'));
        }
      }
      expect(names, hasLength(1 + kPipelineMaxStages * 4));
      expect(names.toSet(), hasLength(names.length));
    });

    test('per-stage pins are visible only for stage counts that reach '
        'them', () {
      // Without this, 2–8 configurable stages would mean 32 permanently
      // listed pins in the bindings pane. This is the seam A2 added
      // (`SignalBinding.visibleWhenValues`) doing the job it was added for.
      for (final binding in widget.optionalSignals) {
        if (binding.name == 'instruction') {
          expect(binding.visibleWhenKey, isNull);
          continue;
        }
        final stage = int.parse(binding.name.substring(5).split('_').first);
        expect(binding.visibleWhenKey, PipelineStageWidget.paramStageCount);
        for (var n = kPipelineMinStages; n <= kPipelineMaxStages; n++) {
          expect(
            binding.isVisibleIn({PipelineStageWidget.paramStageCount: n}),
            n >= stage,
            reason: '${binding.name} at a stage count of $n',
          );
        }
      }
    });

    test('a never-configured instance shows the default pipeline, not an '
        'empty pane', () {
      // The bindings pane tests the instance's **raw** configuration map, and
      // a freshly dropped instance has an empty one — declared defaults are
      // only applied on read. A predicate that did not admit `null` would
      // leave a new instance showing a clock pin and nothing else.
      final visible = <String>[
        for (final b in [...widget.requiredSignals, ...widget.optionalSignals])
          if (b.isVisibleIn(const {})) b.name,
      ];
      expect(visible, contains('clk'));
      expect(visible, contains('instruction'));
      for (var s = 1; s <= kPipelineDefaultStages; s++) {
        expect(visible, contains('stage${s}_valid'));
      }
      for (var s = kPipelineDefaultStages + 1; s <= kPipelineMaxStages; s++) {
        expect(visible, isNot(contains('stage${s}_valid')));
      }
    });

    test('the clock pin is a scalar', () {
      expect(widget.requiredSignals.single.bitWidth, 1);
      for (final b in widget.optionalSignals) {
        if (b.name.endsWith('_pc') || b.name == 'instruction') {
          expect(b.bitWidth, isNull, reason: '${b.name} accepts any width');
        }
      }
    });
  });

  group('configuration', () {
    test('stage count is a 2-8 slider', () {
      final param = widget.configParams.firstWhere(
        (p) => p.id == PipelineStageWidget.paramStageCount,
      );
      expect(param.type, ConfigParamType.integer);
      expect(param.min, kPipelineMinStages);
      expect(param.max, kPipelineMaxStages);
      expect(param.defaultValue, kPipelineDefaultStages);
    });

    test('the identity source offers positional and pc, and nothing else', () {
      // `tag` is the Pro capability. Offering it in a build with no tag
      // tracker would be a menu item that produces a blank panel, which is
      // exactly the "plausible lie" this family refuses to tell.
      final param = widget.configParams.firstWhere(
        (p) => p.id == PipelineStageWidget.paramIdentitySource,
      );
      expect(param.choices!.map((c) => c.id), ['positional', 'pc']);
      expect(param.defaultValue, 'positional');
      expect(
        param.choices!.map((c) => c.id),
        isNot(contains(RiscvIdentitySource.tag.name)),
      );
    });

    test('no config param or choice is named for the tag source', () {
      // Matched on whole tokens, not substrings — "stage" contains "tag".
      final tokens = widget.configParams
          .expand((p) => [p.id, p.labelKey, ...?p.choices?.map((c) => c.id)])
          .expand((s) => s.toLowerCase().split(RegExp('[^a-z0-9]+')))
          .toSet();
      expect(tokens, isNot(contains('tag')));
      expect(tokens, isNot(contains('tags')));
      expect(
        widget.configParams.map((p) => p.id),
        isNot(contains('tagSignal')),
      );
    });

    test('no pin is declared for a per-stage instruction tag', () {
      final pins = [
        ...widget.requiredSignals,
        ...widget.optionalSignals,
      ].map((b) => b.name);
      expect(pins.where((n) => n.endsWith('_tag')), isEmpty);
    });

    test('there is no cap-shaped or upsell-shaped parameter', () {
      // Open core here is not a demo: no row cap,
      // no watermark, no in-view nag. The cycle window is a *view* control
      // with a real ceiling, not a licence gate.
      for (final p in widget.configParams) {
        final id = p.id.toLowerCase();
        expect(id.contains('limit'), isFalse);
        expect(id.contains('watermark'), isFalse);
        expect(id.contains('pro'), isFalse);
      }
    });

    test('eight stage-name params, each gated by the stage count', () {
      for (var s = 1; s <= kPipelineMaxStages; s++) {
        final param = widget.configParams.firstWhere(
          (p) => p.id == PipelineStageWidget.stageNameParam(s),
        );
        expect(param.type, ConfigParamType.text);
        expect(param.defaultValue, kPipelineDefaultStageNames[s - 1]);
        expect(param.labelKey, 'pipelineParamStage${s}Name');
        expect(param.visibleWhenKey, PipelineStageWidget.paramStageCount);
        expect(param.isVisibleIn({'stageCount': s}), isTrue);
        if (s > kPipelineMinStages) {
          expect(param.isVisibleIn({'stageCount': s - 1}), isFalse);
        }
      }
    });

    test('every param and group belongs to a declared group', () {
      final groups = widget.configGroups.map((g) => g.id).toSet();
      for (final p in widget.configParams) {
        expect(groups, contains(p.groupId));
      }
    });
  });

  group('parsers', () {
    test('stage count clamps into range and survives junk', () {
      expect(parsePipelineStageCount(5), 5);
      expect(parsePipelineStageCount(1), kPipelineMinStages);
      expect(parsePipelineStageCount(99), kPipelineMaxStages);
      expect(parsePipelineStageCount(null), kPipelineDefaultStages);
      expect(parsePipelineStageCount('five'), kPipelineDefaultStages);
    });

    test('identity source falls back to positional, never to tag', () {
      expect(parsePipelineIdentitySource('pc'), RiscvIdentitySource.pc);
      expect(
        parsePipelineIdentitySource('positional'),
        RiscvIdentitySource.positional,
      );
      expect(
        parsePipelineIdentitySource('tag'),
        RiscvIdentitySource.positional,
        reason:
            'a session written by a Pro build must not select a source this '
            'build has no tracker for',
      );
      expect(
        parsePipelineIdentitySource(null),
        RiscvIdentitySource.positional,
      );
    });

    test('window cycles clamp', () {
      expect(parsePipelineWindowCycles(32), 32);
      expect(parsePipelineWindowCycles(1), 4);
      expect(parsePipelineWindowCycles(9999), 128);
      expect(parsePipelineWindowCycles(null), 24);
    });

    test('stage names fall back to the preset and trim', () {
      expect(pipelineStageName(const {}, 0), 'IF');
      expect(pipelineStageName(const {'stage1Name': '  Fetch '}, 0), 'Fetch');
      expect(pipelineStageName(const {'stage1Name': '   '}, 0), 'IF');
      expect(pipelineStageName(const {'stage1Name': 7}, 0), 'IF');
      expect(pipelineStageName(const {}, 4), 'WB');
    });
  });

  group('registration', () {
    setUp(registerBuiltinStageWidgets);
    tearDown(clearBuiltinStageWidgets);

    test('both the definition and the renderer are registered', () {
      expect(
        StageRegistry.instance.get(PipelineStageWidget.widgetId),
        isA<PipelineStageWidget>(),
      );
      expect(
        StageWidgetRendererRegistry.instance.get(
          PipelineStageWidget.widgetId,
        ),
        isNotNull,
      );
    });
  });

  test('open core registers exactly the two trackers this widget offers', () {
    expect(
      RiscvIdentityTrackerRegistry.availableSources,
      kPipelineIdentitySources.toSet(),
    );
    expect(
      RiscvIdentityTrackerRegistry.create(RiscvIdentitySource.tag),
      isNull,
      reason:
          'the honest open-core answer to "can you track this superscalar '
          'core" is no, not a plausible-looking lie',
    );
  });
}
