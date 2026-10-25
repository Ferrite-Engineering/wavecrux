// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/session/binding_paths.dart';

import '../../helpers/fake_waveform_data_source.dart';

Variable _var(String name, String ref) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: ref,
  scopePath: 'top',
);

/// A one-scope hierarchy `top.<name>` with the given name → ref numbering.
FakeWaveformDataSource _source(Map<String, String> refs) =>
    FakeWaveformDataSource(
      scopes: [
        Scope(
          name: 'top',
          type: ScopeType.module,
          path: 'top',
          variables: [for (final e in refs.entries) _var(e.key, e.value)],
        ),
      ],
    );

StageWorkspaceState _stage(Map<String, StageSignalBinding> bindings) =>
    StageWorkspaceState(
      panels: [
        StagePanelConfig(
          id: 'p',
          name: 'P',
          instances: [
            StageInstance(
              id: 'i1',
              widgetId: 'rvfi_inspector',
              signalBindings: bindings,
            ),
          ],
        ),
      ],
    );

Map<String, StageSignalBinding> _bindingsOf(StageWorkspaceState s) =>
    s.panels.single.instances.single.signalBindings;

void main() {
  group('lookups', () {
    final source = _source({'clk': '28', 'data': '1404', 'valid': '7'});

    test('pathsForRefs returns only the refs asked for', () {
      expect(BindingPaths.pathsForRefs(source, {'28', '7', '999'}), {
        '28': 'top.clk',
        '7': 'top.valid',
      });
    });

    test('refsForPaths returns only the paths asked for', () {
      expect(
        BindingPaths.refsForPaths(source, {'top.data', 'top.gone'}),
        {'top.data': '1404'},
      );
    });

    test('an empty request does not scan', () {
      expect(BindingPaths.pathsForRefs(source, {}), isEmpty);
      expect(BindingPaths.refsForPaths(source, {}), isEmpty);
    });
  });

  group('decoder bindings', () {
    const config = DecoderConfig(
      signalBindings: {'clk': '28', 'tlp_data': '1404', 'opt': ''},
      parameters: {'width': 8},
    );

    test("record stores each bound ref's path and keeps parameters", () {
      final recorded = BindingPaths.recordDecoder(config, {
        '28': 'top.clk',
        '1404': 'top.tlp_data',
      });
      expect(recorded.signalPaths, {
        'clk': 'top.clk',
        'tlp_data': 'top.tlp_data',
      });
      expect(recorded.signalBindings, config.signalBindings);
      expect(recorded.parameters, config.parameters);
    });

    test('record keeps a path it cannot look up, drops unbound slots', () {
      const waiting = DecoderConfig(
        signalBindings: {'clk': ''},
        signalPaths: {'clk': 'top.clk', 'removed': 'top.old'},
      );
      expect(
        BindingPaths.recordDecoder(waiting, const {}).signalPaths,
        {'clk': 'top.clk'},
      );
    });

    test('resolve re-points refs that moved, by path', () {
      final saved = BindingPaths.recordDecoder(config, {
        '28': 'top.clk',
        '1404': 'top.tlp_data',
      });
      final missing = <String>[];
      final resolved = BindingPaths.resolveDecoder(
        saved,
        {'top.clk': '3', 'top.tlp_data': '90'},
        onUnresolved: (slot, path) => missing.add('$slot=$path'),
      );
      expect(resolved.signalBindings, {
        'clk': '3',
        'tlp_data': '90',
        'opt': '',
      });
      expect(missing, isEmpty);
      // The paths stay, so the next save writes them again.
      expect(resolved.signalPaths, saved.signalPaths);
    });

    test('resolve empties and reports a slot whose path is gone', () {
      final saved = BindingPaths.recordDecoder(config, {
        '28': 'top.clk',
        '1404': 'top.tlp_data',
      });
      final missing = <String>[];
      final resolved = BindingPaths.resolveDecoder(
        saved,
        {'top.clk': '3'},
        onUnresolved: (slot, path) => missing.add('$slot=$path'),
      );
      expect(resolved.signalBindings['clk'], '3');
      expect(resolved.signalBindings['tlp_data'], '');
      expect(resolved.signalPaths['tlp_data'], 'top.tlp_data');
      expect(missing, ['tlp_data=top.tlp_data']);
    });

    test('resolve leaves a config without paths (an old session) alone', () {
      final resolved = BindingPaths.resolveDecoder(
        config,
        const {},
        onUnresolved: (_, _) => fail('nothing has a path to miss'),
      );
      expect(identical(resolved, config), isTrue);
    });

    test('decoderRefs / decoderPaths list what a lookup needs', () {
      expect(BindingPaths.decoderRefs(config), unorderedEquals(['28', '1404']));
      const withPaths = DecoderConfig(
        signalBindings: {'clk': '28'},
        signalPaths: {'clk': 'top.clk', 'stale': 'top.x'},
      );
      expect(BindingPaths.decoderPaths(withPaths), ['top.clk']);
    });
  });

  group('Stage bindings', () {
    final stage = _stage({
      'valid': const StageSignalBinding(signalRef: '7'),
      'insn': const StageSignalBinding(signalRef: '12', bitIndex: 3),
      'unbound': const StageSignalBinding(signalRef: ''),
    });

    test('record stores paths and keeps bit slices', () {
      final recorded = _bindingsOf(
        BindingPaths.recordStage(stage, {'7': 'top.valid', '12': 'top.insn'}),
      );
      expect(recorded['valid']!.signalPath, 'top.valid');
      expect(recorded['insn']!.signalPath, 'top.insn');
      expect(recorded['insn']!.bitIndex, 3);
      expect(recorded['unbound']!.signalPath, isNull);
    });

    test('resolve re-points by path and reports what is gone', () {
      final saved = BindingPaths.recordStage(stage, {
        '7': 'top.valid',
        '12': 'top.insn',
      });
      final missing = <String>[];
      final resolved = _bindingsOf(
        BindingPaths.resolveStage(
          saved,
          {'top.valid': '70'},
          onUnresolved: (owner, pin, path) => missing.add('$owner.$pin=$path'),
        ),
      );
      expect(resolved['valid']!.signalRef, '70');
      expect(resolved['insn']!.signalRef, '');
      expect(resolved['insn']!.signalPath, 'top.insn');
      expect(resolved['insn']!.bitIndex, 3);
      expect(resolved['unbound']!.signalRef, '');
      expect(missing, ['rvfi_inspector.insn=top.insn']);
    });

    test('resolve keeps the ref of a binding without a path', () {
      final resolved = _bindingsOf(
        BindingPaths.resolveStage(
          stage,
          const {},
          onUnresolved: (_, _, _) => fail('nothing has a path to miss'),
        ),
      );
      expect(resolved['valid']!.signalRef, '7');
    });

    test('stageRefs / stagePaths list what a lookup needs', () {
      expect(BindingPaths.stageRefs(stage), unorderedEquals(['7', '12']));
      final saved = BindingPaths.recordStage(stage, {'7': 'top.valid'});
      expect(BindingPaths.stagePaths(saved), ['top.valid']);
    });
  });

  test('UnresolvedBinding equality and toString', () {
    const a = UnresolvedBinding(owner: 'spi #1', slot: 'clk', path: 'top.c');
    const b = UnresolvedBinding(owner: 'spi #1', slot: 'clk', path: 'top.c');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.toString(), contains('top.c'));
  });
}
