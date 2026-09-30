// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/fsm_annotation.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';

void main() {
  // ── default values ──────────────────────────────────────────────────────────

  group('SessionState — defaults', () {
    test('all fields have expected defaults', () {
      const s = SessionState();
      expect(s.sourceFilePath, isNull);
      expect(s.signalGroup, equals(const SignalGroup()));
      expect(s.cursorState, equals(const CursorState()));
      expect(s.markerState, equals(const MarkerState()));
      expect(s.ticksPerPixel, 1.0);
      expect(s.panOffsetTicks, 0.0);
      expect(s.scrollOffset, 0.0);
      expect(s.signalTreeVisible, isTrue);
      expect(s.valueColumnVisible, isTrue);
      expect(s.transactionViewVisible, isFalse);
      expect(s.stageViewVisible, isFalse);
      expect(s.statisticsStripVisible, isFalse);
      expect(s.translateFilterPaths, isEmpty);
      expect(s.fsmAnnotations, isEmpty);
      expect(s.stageWorkspace, equals(const StageWorkspaceState()));
      expect(s.activeThemeName, 'wavecrux-dark');
      // v3 session-restore fields.
      expect(s.cocotbLogPanelVisible, isFalse);
      expect(s.rtlSourceVisible, isFalse);
      expect(s.cocotbLogPath, isNull);
      expect(s.rtlStemsPath, isNull);
      expect(s.leftPaneSize, isNull);
      expect(s.rightPaneSize, isNull);
      expect(s.bottomPaneSize, isNull);
      expect(s.expandedScopePaths, isEmpty);
      expect(s.signalTreeSearchQuery, '');
      expect(s.signalTreeSelectedRefs, isEmpty);
      expect(s.signalTreeScrollOffset, 0.0);
    });
  });

  // ── fsmAnnotations ──────────────────────────────────────────────────────────

  group('SessionState — fsmAnnotations', () {
    const annotation = FsmAnnotation(
      signalRef: 'top.fsm.state',
      stateLabels: {'0': 'IDLE', '1': 'RUN'},
    );

    test('preserves the annotation map', () {
      const s = SessionState(
        fsmAnnotations: {'top.fsm.state': annotation},
      );
      expect(s.fsmAnnotations['top.fsm.state'], equals(annotation));
    });

    test('copyWith updates fsmAnnotations', () {
      const s = SessionState();
      final updated = s.copyWith(
        fsmAnnotations: const {'r': annotation},
      );
      expect(updated.fsmAnnotations['r'], equals(annotation));
    });

    test('copyWith without fsmAnnotations preserves existing value', () {
      const s = SessionState(fsmAnnotations: {'r': annotation});
      expect(
        s.copyWith(ticksPerPixel: 2).fsmAnnotations['r'],
        equals(annotation),
      );
    });

    test('equality compares fsmAnnotations structurally', () {
      const a = SessionState(fsmAnnotations: {'r': annotation});
      const b = SessionState(fsmAnnotations: {'r': annotation});
      const c = SessionState();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });
  });

  // ── activeThemeName ─────────────────────────────────────────────────────────

  group('SessionState — activeThemeName', () {
    test('default is wavecrux-dark', () {
      expect(const SessionState().activeThemeName, 'wavecrux-dark');
    });

    test('custom theme name is preserved', () {
      const s = SessionState(activeThemeName: 'oscilloscope');
      expect(s.activeThemeName, 'oscilloscope');
    });

    test('copyWith updates activeThemeName', () {
      const s = SessionState();
      expect(
        s.copyWith(activeThemeName: 'solarized-dark').activeThemeName,
        'solarized-dark',
      );
    });

    test('copyWith without activeThemeName preserves existing value', () {
      const s = SessionState(activeThemeName: 'high-contrast-dark');
      expect(
        s.copyWith(ticksPerPixel: 2).activeThemeName,
        'high-contrast-dark',
      );
    });

    test('different activeThemeName are not equal', () {
      const a = SessionState();
      const b = SessionState(activeThemeName: 'oscilloscope');
      expect(a, isNot(equals(b)));
    });

    test('same activeThemeName are equal', () {
      const a = SessionState(activeThemeName: 'solarized-dark');
      const b = SessionState(activeThemeName: 'solarized-dark');
      expect(a, equals(b));
    });

    test('hashCode differs when activeThemeName differs', () {
      const a = SessionState();
      const b = SessionState(activeThemeName: 'oscilloscope');
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });
  });

  group('SessionState — Stage workspace', () {
    test('stageViewVisible can be enabled', () {
      const s = SessionState(stageViewVisible: true);
      expect(s.stageViewVisible, isTrue);
    });

    test('stageWorkspace stores panels', () {
      const s = SessionState(
        stageWorkspace: StageWorkspaceState(
          panels: [StagePanelConfig(id: 'p0', name: 'A')],
          activePanelId: 'p0',
        ),
      );
      expect(s.stageWorkspace.panels, hasLength(1));
      expect(s.stageWorkspace.activePanelId, 'p0');
    });

    test('copyWith updates stageWorkspace independently', () {
      const original = SessionState();
      final updated = original.copyWith(
        stageWorkspace: const StageWorkspaceState(
          panels: [StagePanelConfig(id: 'p0', name: 'A')],
          activePanelId: 'p0',
        ),
      );
      expect(updated.stageWorkspace.panels, hasLength(1));
      // Other fields unchanged.
      expect(updated.signalTreeVisible, original.signalTreeVisible);
    });

    test('not equal when stageWorkspace differs', () {
      const a = SessionState();
      const b = SessionState(
        stageWorkspace: StageWorkspaceState(
          panels: [StagePanelConfig(id: 'p0', name: 'A')],
        ),
      );
      expect(a, isNot(equals(b)));
    });

    test('not equal when stageViewVisible differs', () {
      const a = SessionState();
      const b = SessionState(stageViewVisible: true);
      expect(a, isNot(equals(b)));
    });
  });

  // ── equality ────────────────────────────────────────────────────────────────

  group('SessionState — equality', () {
    test('identical instances are equal', () {
      const a = SessionState();
      const b = SessionState();
      expect(a, equals(b));
    });

    test('same sourceFilePath are equal', () {
      const a = SessionState(sourceFilePath: '/foo.vcd');
      const b = SessionState(sourceFilePath: '/foo.vcd');
      expect(a, equals(b));
    });

    test('different sourceFilePath are not equal', () {
      const a = SessionState(sourceFilePath: '/a.vcd');
      const b = SessionState(sourceFilePath: '/b.vcd');
      expect(a, isNot(equals(b)));
    });

    test('different ticksPerPixel are not equal', () {
      const a = SessionState();
      const b = SessionState(ticksPerPixel: 2);
      expect(a, isNot(equals(b)));
    });

    test('different scrollOffset are not equal', () {
      const a = SessionState();
      const b = SessionState(scrollOffset: 250);
      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    test('copyWith updates scrollOffset', () {
      const s = SessionState();
      expect(s.copyWith(scrollOffset: 99).scrollOffset, 99);
    });

    test('different panOffsetTicks are not equal', () {
      const a = SessionState();
      const b = SessionState(panOffsetTicks: 100);
      expect(a, isNot(equals(b)));
    });

    test('different panel visibility are not equal', () {
      const a = SessionState();
      const b = SessionState(signalTreeVisible: false);
      expect(a, isNot(equals(b)));
    });

    test('different statisticsStripVisible are not equal', () {
      const a = SessionState();
      const b = SessionState(statisticsStripVisible: true);
      expect(a, isNot(equals(b)));
    });

    test('different translateFilterPaths are not equal', () {
      const a = SessionState(translateFilterPaths: {'ref': '/path'});
      const b = SessionState();
      expect(a, isNot(equals(b)));
    });

    test('identical translateFilterPaths are equal', () {
      const a = SessionState(translateFilterPaths: {'r': '/p'});
      const b = SessionState(translateFilterPaths: {'r': '/p'});
      expect(a, equals(b));
    });

    test('hashCode is consistent with equality', () {
      const a = SessionState(sourceFilePath: '/x.vcd', ticksPerPixel: 2.5);
      const b = SessionState(sourceFilePath: '/x.vcd', ticksPerPixel: 2.5);
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  // ── copyWith ────────────────────────────────────────────────────────────────

  group('SessionState — copyWith', () {
    const base = SessionState(
      sourceFilePath: '/dump.vcd',
      ticksPerPixel: 3,
      panOffsetTicks: 50,
    );

    test('no args returns equal instance', () {
      expect(base.copyWith(), equals(base));
    });

    test('sourceFilePath can be updated', () {
      expect(
        base.copyWith(sourceFilePath: '/new.vcd').sourceFilePath,
        '/new.vcd',
      );
    });

    test('sourceFilePath can be cleared to null', () {
      expect(
        base.copyWith(sourceFilePath: null).sourceFilePath,
        isNull,
      );
    });

    test('ticksPerPixel can be updated', () {
      expect(base.copyWith(ticksPerPixel: 10).ticksPerPixel, 10.0);
    });

    test('panOffsetTicks can be updated', () {
      expect(base.copyWith(panOffsetTicks: 200).panOffsetTicks, 200.0);
    });

    test('signalTreeVisible can be toggled', () {
      expect(
        base.copyWith(signalTreeVisible: false).signalTreeVisible,
        isFalse,
      );
    });

    test('statisticsStripVisible can be toggled', () {
      expect(
        base.copyWith(statisticsStripVisible: true).statisticsStripVisible,
        isTrue,
      );
    });

    test('translateFilterPaths can be replaced', () {
      final updated = base.copyWith(translateFilterPaths: {'top.s': '/f.txt'});
      expect(updated.translateFilterPaths, {'top.s': '/f.txt'});
    });

    test('other fields unchanged when only one field updated', () {
      final updated = base.copyWith(ticksPerPixel: 5);
      expect(updated.sourceFilePath, base.sourceFilePath);
      expect(updated.panOffsetTicks, base.panOffsetTicks);
    });
  });

  // ── with signalGroup, cursorState, markerState ──────────────────────────────

  group('SessionState — composite fields', () {
    test('signalGroup carries signals', () {
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(
            signalRef: 'top.clk',
            displayName: 'clk',
            format: DisplayFormat.binary,
          ),
        ],
      );
      final s = SessionState(signalGroup: group);
      expect(s.signalGroup.signalCount, 1);
    });

    test('cursorState with primary time', () {
      const s = SessionState(
        cursorState: CursorState(primaryCursorTime: 500),
      );
      expect(s.cursorState.primaryCursorTime, 500);
    });

    test('markerState with marker a', () {
      final markers = const MarkerState().setMarker('a', 1000);
      final s = SessionState(markerState: markers);
      expect(s.markerState.getMarker('a'), 1000);
    });

    test('equality holds with composite fields', () {
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(
            signalRef: 'top.clk',
            displayName: 'clk',
          ),
        ],
      );
      final a = SessionState(signalGroup: group);
      final b = SessionState(signalGroup: group);
      expect(a, equals(b));
    });
  });

  // ── toString ────────────────────────────────────────────────────────────────

  group('SessionState — toString', () {
    test('includes sourceFilePath and ticksPerPixel', () {
      const s = SessionState(sourceFilePath: '/dump.vcd', ticksPerPixel: 2);
      expect(s.toString(), contains('/dump.vcd'));
      expect(s.toString(), contains('2.0'));
    });
  });

  // ── v3 session-restore fields ───────────────────────────────────────────────
  group('SessionState — v3 fields', () {
    test('copyWith updates pane sizes', () {
      const s = SessionState();
      final updated = s.copyWith(
        leftPaneSize: 300.0,
        rightPaneSize: 200.0,
        bottomPaneSize: 250.0,
      );
      expect(updated.leftPaneSize, 300);
      expect(updated.rightPaneSize, 200);
      expect(updated.bottomPaneSize, 250);
    });

    test('copyWith without pane sizes preserves existing values', () {
      const s = SessionState(leftPaneSize: 300);
      expect(s.copyWith(signalTreeSearchQuery: 'x').leftPaneSize, 300);
    });

    test('copyWith can clear a nullable path back to null', () {
      const s = SessionState(cocotbLogPath: '/tmp/a.log');
      expect(s.copyWith(cocotbLogPath: null).cocotbLogPath, isNull);
    });

    test('copyWith updates signal-tree state', () {
      const s = SessionState();
      final updated = s.copyWith(
        expandedScopePaths: {'top', 'top.cpu'},
        signalTreeSearchQuery: 'clk',
        signalTreeSelectedRefs: {'top.clk'},
        signalTreeScrollOffset: 80,
      );
      expect(updated.expandedScopePaths, {'top', 'top.cpu'});
      expect(updated.signalTreeSearchQuery, 'clk');
      expect(updated.signalTreeSelectedRefs, {'top.clk'});
      expect(updated.signalTreeScrollOffset, 80);
    });

    test('equality compares expanded scopes structurally', () {
      const a = SessionState(expandedScopePaths: {'top', 'top.cpu'});
      const b = SessionState(expandedScopePaths: {'top.cpu', 'top'});
      const c = SessionState(expandedScopePaths: {'top'});
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('different pane size is not equal and changes hashCode', () {
      const a = SessionState(leftPaneSize: 280);
      const b = SessionState(leftPaneSize: 300);
      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    test('different cocotb/rtl flags are not equal', () {
      expect(
        const SessionState(cocotbLogPanelVisible: true),
        isNot(equals(const SessionState())),
      );
      expect(
        const SessionState(rtlSourceVisible: true),
        isNot(equals(const SessionState())),
      );
    });

    test('hashCode is consistent with equality for v3 fields', () {
      const a = SessionState(
        leftPaneSize: 300,
        expandedScopePaths: {'top'},
        signalTreeScrollOffset: 12,
      );
      const b = SessionState(
        leftPaneSize: 300,
        expandedScopePaths: {'top'},
        signalTreeScrollOffset: 12,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
