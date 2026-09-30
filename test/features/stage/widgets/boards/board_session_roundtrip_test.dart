// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';
import 'package:wavecrux/features/stage/widgets/boards/basys3_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/boards/de10_lite_stage_widget.dart';
import 'package:wavecrux/services/session/session_service.dart';

const _service = SessionService();

Future<T> _withTempFile<T>(Future<T> Function(String path) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_board_test_');
  final path = '${dir.path}/session.wavecrux';
  try {
    return await fn(path);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }
}

void main() {
  group('Board widget session round-trip', () {
    test('Basys 3 instance with multiple bound slots round-trips', () async {
      await _withTempFile((path) async {
        const original = SessionState(
          stageViewVisible: true,
          stageWorkspace: StageWorkspaceState(
            panels: [
              StagePanelConfig(
                id: 'stagePanel_0',
                name: 'Basys 3 Eval',
                instances: [
                  StageInstance(
                    id: 'stageInstance_0',
                    widgetId: Basys3StageWidget.widgetId,
                    signalBindings: {
                      'led0': StageSignalBinding(signalRef: 'top.led[0]'),
                      'led1': StageSignalBinding(signalRef: 'top.led[1]'),
                      'sw0': StageSignalBinding(signalRef: 'top.sw[0]'),
                      'btnC': StageSignalBinding(signalRef: 'top.btnC'),
                      'digit0': StageSignalBinding(
                        signalRef: 'top.digit0_value',
                      ),
                    },
                    width: 640,
                    height: 360,
                    label: 'Basys 3',
                  ),
                ],
              ),
            ],
            activePanelId: 'stagePanel_0',
          ),
        );
        await _service.saveSession(original, path);
        final loaded = await _service.loadSession(path);
        expect(loaded, equals(original));

        final loadedInstance =
            loaded.stageWorkspace.panels.single.instances.single;
        expect(loadedInstance.widgetId, Basys3StageWidget.widgetId);
        expect(
          loadedInstance.signalBindings['led0'],
          const StageSignalBinding(signalRef: 'top.led[0]'),
        );
        expect(
          loadedInstance.signalBindings['btnC'],
          const StageSignalBinding(signalRef: 'top.btnC'),
        );
        expect(
          loadedInstance.signalBindings['digit0'],
          const StageSignalBinding(signalRef: 'top.digit0_value'),
        );
      });
    });

    test('DE10-Lite instance with multiple bound slots round-trips', () async {
      await _withTempFile((path) async {
        const original = SessionState(
          stageWorkspace: StageWorkspaceState(
            panels: [
              StagePanelConfig(
                id: 'p0',
                name: 'DE10-Lite Eval',
                instances: [
                  StageInstance(
                    id: 'i0',
                    widgetId: De10LiteStageWidget.widgetId,
                    signalBindings: {
                      'ledr0': StageSignalBinding(signalRef: 'top.LEDR[0]'),
                      'ledr9': StageSignalBinding(signalRef: 'top.LEDR[9]'),
                      'sw5': StageSignalBinding(signalRef: 'top.SW[5]'),
                      'key0': StageSignalBinding(signalRef: 'top.KEY[0]'),
                      'hex0': StageSignalBinding(signalRef: 'top.HEX0'),
                      'hex5': StageSignalBinding(signalRef: 'top.HEX5'),
                    },
                  ),
                ],
              ),
            ],
            activePanelId: 'p0',
          ),
        );
        await _service.saveSession(original, path);
        final loaded = await _service.loadSession(path);
        expect(loaded, equals(original));
        final inst = loaded.stageWorkspace.panels.single.instances.single;
        expect(inst.widgetId, De10LiteStageWidget.widgetId);
        expect(inst.signalBindings, hasLength(6));
        expect(
          inst.signalBindings['hex5'],
          const StageSignalBinding(signalRef: 'top.HEX5'),
        );
      });
    });

    test('mixed Basys 3 + DE10-Lite panel round-trips', () async {
      await _withTempFile((path) async {
        const original = SessionState(
          stageWorkspace: StageWorkspaceState(
            panels: [
              StagePanelConfig(
                id: 'p0',
                name: 'Boards',
                instances: [
                  StageInstance(
                    id: 'b1',
                    widgetId: Basys3StageWidget.widgetId,
                    signalBindings: {
                      'led0': StageSignalBinding(signalRef: 'a'),
                    },
                  ),
                  StageInstance(
                    id: 'b2',
                    widgetId: De10LiteStageWidget.widgetId,
                    signalBindings: {
                      'ledr0': StageSignalBinding(signalRef: 'b'),
                    },
                  ),
                ],
              ),
            ],
            activePanelId: 'p0',
          ),
        );
        await _service.saveSession(original, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.stageWorkspace.panels.single.instances, hasLength(2));
        expect(
          loaded.stageWorkspace.panels.single.instances[0].widgetId,
          Basys3StageWidget.widgetId,
        );
        expect(
          loaded.stageWorkspace.panels.single.instances[1].widgetId,
          De10LiteStageWidget.widgetId,
        );
      });
    });
  });
}
