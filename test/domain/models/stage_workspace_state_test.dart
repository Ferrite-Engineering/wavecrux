// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';

void main() {
  group('StageWorkspaceState', () {
    test('default state is empty', () {
      const w = StageWorkspaceState();
      expect(w.panels, isEmpty);
      expect(w.activePanelId, isNull);
      expect(w.hasPanels, isFalse);
      expect(w.activePanel, isNull);
    });

    test('hasPanels true when panels list is non-empty', () {
      const w = StageWorkspaceState(
        panels: [StagePanelConfig(id: 'p0', name: 'A')],
        activePanelId: 'p0',
      );
      expect(w.hasPanels, isTrue);
    });

    test('activePanel returns the matching panel', () {
      const w = StageWorkspaceState(
        panels: [
          StagePanelConfig(id: 'p0', name: 'A'),
          StagePanelConfig(id: 'p1', name: 'B'),
        ],
        activePanelId: 'p1',
      );
      expect(w.activePanel?.id, 'p1');
      expect(w.activePanel?.name, 'B');
    });

    test('activePanel returns null when activePanelId is unknown', () {
      const w = StageWorkspaceState(
        panels: [StagePanelConfig(id: 'p0', name: 'A')],
        activePanelId: 'missing',
      );
      expect(w.activePanel, isNull);
    });

    test('copyWith no-args returns equal workspace', () {
      const w = StageWorkspaceState(
        panels: [StagePanelConfig(id: 'p0', name: 'A')],
        activePanelId: 'p0',
      );
      expect(w.copyWith(), equals(w));
    });

    test('copyWith can clear activePanelId via explicit null', () {
      const w = StageWorkspaceState(
        panels: [StagePanelConfig(id: 'p0', name: 'A')],
        activePanelId: 'p0',
      );
      final cleared = w.copyWith(activePanelId: null);
      expect(cleared.activePanelId, isNull);
      expect(cleared.panels, hasLength(1));
    });

    test('copyWith replaces panels', () {
      const w = StageWorkspaceState();
      final r = w.copyWith(
        panels: const [StagePanelConfig(id: 'p1', name: 'New')],
        activePanelId: 'p1',
      );
      expect(r.panels, hasLength(1));
      expect(r.activePanelId, 'p1');
    });

    test('equality compares panels list and active id', () {
      const a = StageWorkspaceState(
        panels: [StagePanelConfig(id: 'p0', name: 'A')],
        activePanelId: 'p0',
      );
      const b = StageWorkspaceState(
        panels: [StagePanelConfig(id: 'p0', name: 'A')],
        activePanelId: 'p0',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when active panel id differs', () {
      const a = StageWorkspaceState(
        panels: [
          StagePanelConfig(id: 'p0', name: 'A'),
          StagePanelConfig(id: 'p1', name: 'B'),
        ],
        activePanelId: 'p0',
      );
      const b = StageWorkspaceState(
        panels: [
          StagePanelConfig(id: 'p0', name: 'A'),
          StagePanelConfig(id: 'p1', name: 'B'),
        ],
        activePanelId: 'p1',
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when panel list differs', () {
      const a = StageWorkspaceState(
        panels: [StagePanelConfig(id: 'p0', name: 'A')],
      );
      const b = StageWorkspaceState();
      expect(a, isNot(equals(b)));
    });

    test('toString reports panel count and active id', () {
      const w = StageWorkspaceState(
        panels: [StagePanelConfig(id: 'p0', name: 'A')],
        activePanelId: 'p0',
      );
      expect(w.toString(), allOf(contains('1'), contains('p0')));
    });
  });
}
