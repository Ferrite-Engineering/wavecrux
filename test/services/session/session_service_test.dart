// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/cursor_state.dart';
import 'package:wavecrux/domain/models/fsm_annotation.dart';
import 'package:wavecrux/domain/models/marker_state.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';
import 'package:wavecrux/services/session/session_service.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

const _service = SessionService();

/// Creates a temp file path, runs [fn] with it, then cleans up.
Future<T> _withTempFile<T>(Future<T> Function(String path) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_test_');
  final path = p.join(dir.path, 'session.wavecrux');
  try {
    return await fn(path);
  } finally {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  }
}

// ── round-trip ────────────────────────────────────────────────────────────────

void main() {
  group('SessionService — extension helper', () {
    test('matches files with the .wavecrux extension', () {
      expect(SessionService.isSessionFilePath('a.wavecrux'), isTrue);
      expect(SessionService.isSessionFilePath('/abs/path.wavecrux'), isTrue);
      expect(
        SessionService.isSessionFilePath(r'Z:\Win\path.wavecrux'),
        isTrue,
      );
    });

    test('match is case-insensitive on the extension', () {
      expect(SessionService.isSessionFilePath('a.WAVECRUX'), isTrue);
      expect(SessionService.isSessionFilePath('a.WaveCrux'), isTrue);
    });

    test('rejects waveform extensions and the extension-less case', () {
      expect(SessionService.isSessionFilePath('dump.vcd'), isFalse);
      expect(SessionService.isSessionFilePath('dump.fst'), isFalse);
      expect(SessionService.isSessionFilePath('dump.ghw'), isFalse);
      expect(SessionService.isSessionFilePath('session.gtkw'), isFalse);
      expect(SessionService.isSessionFilePath('noext'), isFalse);
      expect(SessionService.isSessionFilePath(''), isFalse);
    });

    test(
      'rejects a file whose stem ends with "wavecrux" but extension differs',
      () {
        expect(SessionService.isSessionFilePath('mywavecrux.txt'), isFalse);
        expect(SessionService.isSessionFilePath('wavecrux.bin'), isFalse);
      },
    );

    test('exposes the canonical fileExtension constant', () {
      expect(SessionService.fileExtension, '.wavecrux');
    });
  });

  group('SessionService — large-session save path', () {
    SessionState largeSession(int count) => SessionState(
      signalGroup: SignalGroup(
        entries: [
          for (var i = 0; i < count; i++)
            SignalEntry.signal(
              signalRef: '$i',
              signalPath: 'top.dut.s$i',
              displayName: 's$i',
              argbColor: 0xFF000000 | i,
            ),
        ],
      ),
    );

    test(
      'at threshold: encodes compact on a worker isolate and round-trips',
      () async {
        await _withTempFile((path) async {
          final s = largeSession(SessionService.largeSessionEntryThreshold);
          await _service.saveSession(s, path);

          // Compact encoding — no pretty-printed indentation.
          final raw = await File(path).readAsString();
          expect(raw.contains('\n  "signals"'), isFalse);

          final loaded = await _service.loadSession(path);
          expect(
            loaded.signalGroup.entries,
            hasLength(SessionService.largeSessionEntryThreshold),
          );
          expect(loaded.signalGroup.entries.first.signalRef, '0');
          expect(
            loaded.signalGroup.entries.last.displayName,
            's${SessionService.largeSessionEntryThreshold - 1}',
          );
        });
      },
    );

    test('below threshold stays pretty-printed', () async {
      await _withTempFile((path) async {
        final s = largeSession(3);
        await _service.saveSession(s, path);
        final raw = await File(path).readAsString();
        expect(raw, contains('\n  "signals"'));
      });
    });
  });

  group('SessionService — round-trip', () {
    test('empty session survives round-trip', () async {
      await _withTempFile((path) async {
        const original = SessionState();
        await _service.saveSession(original, path);
        final loaded = await _service.loadSession(path);
        expect(loaded, equals(original));
      });
    });

    test('sourceFilePath preserved', () async {
      await _withTempFile((path) async {
        const s = SessionState(sourceFilePath: '/sim/dump.vcd');
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.sourceFilePath, '/sim/dump.vcd');
      });
    });

    test('null sourceFilePath preserved', () async {
      await _withTempFile((path) async {
        const s = SessionState();
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.sourceFilePath, isNull);
      });
    });

    test(
      'relative sourceFilePath resolves against the session file directory',
      () async {
        await _withTempFile((path) async {
          // A `.wavecrux` shipped next to its dump (demo pack / EDU session)
          // stores a bare relative name; loading must resolve it to the
          // session's own folder, not the process working directory.
          const s = SessionState(sourceFilePath: 'dump.vcd');
          await _service.saveSession(s, path);
          final loaded = await _service.loadSession(path);
          expect(loaded.sourceFilePath, p.join(p.dirname(path), 'dump.vcd'));
          expect(p.isAbsolute(loaded.sourceFilePath!), isTrue);
        });
      },
    );

    test('relative sourceFilePath in a subdirectory resolves', () async {
      await _withTempFile((path) async {
        const s = SessionState(sourceFilePath: 'data/dump.vcd');
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(
          loaded.sourceFilePath,
          p.normalize(p.join(p.dirname(path), 'data/dump.vcd')),
        );
      });
    });

    test('absolute sourceFilePath is left untouched on load', () async {
      await _withTempFile((path) async {
        // POSIX-absolute path passes through unchanged — a normally-saved
        // session stores the absolute path it was opened from.
        const s = SessionState(sourceFilePath: '/sim/dump.vcd');
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.sourceFilePath, '/sim/dump.vcd');
      });
    }, testOn: 'posix');

    test('zoom and pan state preserved', () async {
      await _withTempFile((path) async {
        const s = SessionState(ticksPerPixel: 4.5, panOffsetTicks: 1234.5);
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.ticksPerPixel, 4.5);
        expect(loaded.panOffsetTicks, 1234.5);
      });
    });

    test('scroll offset preserved (round-trip)', () async {
      await _withTempFile((path) async {
        const s = SessionState(scrollOffset: 612);
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.scrollOffset, 612);
      });
    });

    test(
      'missing scrollOffset falls back to 0 (backwards compatible)',
      () async {
        await _withTempFile((path) async {
          // Write a session JSON without the scrollOffset key — exercises the
          // forward-compatibility fallback path for sessions saved before this
          // field landed.
          await File(path).writeAsString(
            '{"version":1,"view":{"ticksPerPixel":1.0,"panOffsetTicks":0.0}}',
          );
          final s = await _service.loadSession(path);
          expect(s.scrollOffset, 0.0);
        });
      },
    );

    test('cursor state preserved', () async {
      await _withTempFile((path) async {
        const s = SessionState(
          cursorState: CursorState(
            primaryCursorTime: 1000,
            secondaryCursorTime: 2000,
          ),
        );
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.cursorState.primaryCursorTime, 1000);
        expect(loaded.cursorState.secondaryCursorTime, 2000);
      });
    });

    test('null cursor times preserved', () async {
      await _withTempFile((path) async {
        const s = SessionState();
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.cursorState.primaryCursorTime, isNull);
        expect(loaded.cursorState.secondaryCursorTime, isNull);
      });
    });

    test('markers preserved', () async {
      await _withTempFile((path) async {
        final markers = const MarkerState()
            .setMarker('a', 500)
            .setMarker('z', 99999);
        final s = SessionState(markerState: markers);
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.markerState.getMarker('a'), 500);
        expect(loaded.markerState.getMarker('z'), 99999);
        expect(loaded.markerState.getMarker('b'), isNull);
      });
    });

    test('panel visibility preserved', () async {
      await _withTempFile((path) async {
        const s = SessionState(
          signalTreeVisible: false,
          transactionViewVisible: true,
        );
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.signalTreeVisible, isFalse);
        expect(loaded.valueColumnVisible, isTrue);
        expect(loaded.transactionViewVisible, isTrue);
      });
    });

    test('statisticsStripVisible preserved when true', () async {
      await _withTempFile((path) async {
        const s = SessionState(statisticsStripVisible: true);
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.statisticsStripVisible, isTrue);
      });
    });

    test(
      'statisticsStripVisible defaults to false when field absent',
      () async {
        await _withTempFile((path) async {
          // Write a session JSON without the statisticsStrip key to simulate an
          // old session file that predates this field.
          const legacy =
              '{"version":1,"signals":[],"cursor":{"primary":null,'
              '"secondary":null},"markers":{},"view":{"ticksPerPixel":1.0,'
              '"panOffsetTicks":0.0},"panels":{"signalTree":true,'
              '"valueColumn":true,"transactionView":false,"stageView":false},'
              '"translateFilters":{},"stage":{"panels":[]}}';
          await File(path).writeAsString(legacy);
          final loaded = await _service.loadSession(path);
          expect(loaded.statisticsStripVisible, isFalse);
        });
      },
    );

    test('translate filter paths preserved', () async {
      await _withTempFile((path) async {
        const s = SessionState(
          translateFilterPaths: {
            'top.state': '/path/to/filter.txt',
            'top.cmd': '/other/filter.txt',
          },
        );
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.translateFilterPaths['top.state'], '/path/to/filter.txt');
        expect(loaded.translateFilterPaths['top.cmd'], '/other/filter.txt');
      });
    });

    test('fsm annotations preserved', () async {
      await _withTempFile((path) async {
        const s = SessionState(
          fsmAnnotations: {
            'top.fsm.state': FsmAnnotation(
              signalRef: 'top.fsm.state',
              stateLabels: {'0': 'IDLE', '1': 'RUN', '2': 'STOP'},
            ),
            'top.ctrl.phase': FsmAnnotation(
              signalRef: 'top.ctrl.phase',
              stateLabels: {'0': 'FETCH', '1': 'EXEC'},
            ),
          },
        );
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.fsmAnnotations, equals(s.fsmAnnotations));
        expect(
          loaded.fsmAnnotations['top.fsm.state']!.stateLabels['1'],
          'RUN',
        );
      });
    });

    test('fsmAnnotations defaults to empty when field absent', () async {
      await _withTempFile((path) async {
        // A session saved before FSM-annotation persistence omits the key.
        const legacy =
            '{"version":1,"signals":[],"cursor":{"primary":null,'
            '"secondary":null},"markers":{},"view":{"ticksPerPixel":1.0,'
            '"panOffsetTicks":0.0},"panels":{"signalTree":true,'
            '"valueColumn":true,"transactionView":false,"stageView":false},'
            '"translateFilters":{},"stage":{"panels":[]}}';
        await File(path).writeAsString(legacy);
        final loaded = await _service.loadSession(path);
        expect(loaded.fsmAnnotations, isEmpty);
      });
    });

    test(
      'empty fsmAnnotations is omitted from the JSON (byte-stable)',
      () async {
        await _withTempFile((path) async {
          const s = SessionState();
          await _service.saveSession(s, path);
          final raw = await File(path).readAsString();
          expect(raw.contains('fsmAnnotations'), isFalse);
        });
      },
    );

    test('signal entries preserved', () async {
      await _withTempFile((path) async {
        final group = SignalGroup(
          entries: [
            SignalEntry.signal(
              signalRef: 'top.clk',
              displayName: 'Clock',
              argbColor: 0xFF00FF00,
              format: DisplayFormat.binary,
              laneHeight: 40,
            ),
            const SignalEntry.separator(),
            const SignalEntry.comment(text: 'My comment'),
            SignalEntry.group(
              groupName: 'Outputs',
              collapsed: true,
              children: [
                SignalEntry.signal(
                  signalRef: 'top.out',
                  displayName: 'out',
                ),
              ],
            ),
          ],
        );
        final s = SessionState(signalGroup: group);
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        final entries = loaded.signalGroup.entries;
        expect(entries, hasLength(4));

        // Signal
        expect(entries[0].kind, SignalEntryKind.signal);
        expect(entries[0].signalRef, 'top.clk');
        expect(entries[0].displayName, 'Clock');
        expect(entries[0].argbColor, 0xFF00FF00);
        expect(entries[0].format, DisplayFormat.binary);
        expect(entries[0].laneHeight, 40.0);

        // Separator
        expect(entries[1].kind, SignalEntryKind.separator);

        // Comment
        expect(entries[2].kind, SignalEntryKind.comment);
        expect(entries[2].text, 'My comment');

        // Group with child
        expect(entries[3].kind, SignalEntryKind.group);
        expect(entries[3].groupName, 'Outputs');
        expect(entries[3].collapsed, isTrue);
        expect(entries[3].children, hasLength(1));
        expect(entries[3].children[0].signalRef, 'top.out');
      });
    });

    test('null argbColor preserved as absent', () async {
      await _withTempFile((path) async {
        final group = SignalGroup(
          entries: [
            SignalEntry.signal(signalRef: 'r', displayName: 'd'),
          ],
        );
        final s = SessionState(signalGroup: group);
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.signalGroup.entries[0].argbColor, isNull);
      });
    });

    test('all DisplayFormat values round-trip', () async {
      for (final fmt in DisplayFormat.values) {
        await _withTempFile((path) async {
          final group = SignalGroup(
            entries: [
              SignalEntry.signal(
                signalRef: 'r',
                displayName: 'd',
                format: fmt,
              ),
            ],
          );
          final s = SessionState(signalGroup: group);
          await _service.saveSession(s, path);
          final loaded = await _service.loadSession(path);
          expect(
            loaded.signalGroup.entries[0].format,
            fmt,
            reason: 'format $fmt did not round-trip',
          );
        });
      }
    });

    test('written file is valid JSON text', () async {
      await _withTempFile((path) async {
        const s = SessionState(sourceFilePath: '/x.vcd');
        await _service.saveSession(s, path);
        final content = await File(path).readAsString();
        expect(content, contains('"version"'));
        expect(content, contains('"sourceFilePath"'));
        expect(content, contains('/x.vcd'));
      });
    });

    // ── Stage workspace ─────────────────────────────────────────────────────

    test('empty Stage workspace round-trips', () async {
      await _withTempFile((path) async {
        const s = SessionState();
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.stageWorkspace, const StageWorkspaceState());
      });
    });

    test(
      'Stage workspace with one panel, instances, and bindings round-trips',
      () async {
        await _withTempFile((path) async {
          const original = SessionState(
            stageViewVisible: true,
            stageWorkspace: StageWorkspaceState(
              panels: [
                StagePanelConfig(
                  id: 'stagePanel_0',
                  name: 'ECU Dashboard',
                  instances: [
                    StageInstance(
                      id: 'stageInstance_0',
                      widgetId: 'led',
                      signalBindings: {
                        'in': StageSignalBinding(signalRef: 'top.led_out'),
                      },
                      x: 10,
                      y: 20,
                      width: 80,
                      height: 60,
                      label: 'Status',
                    ),
                    StageInstance(
                      id: 'stageInstance_1',
                      widgetId: 'sevenSeg',
                      signalBindings: {
                        'value': StageSignalBinding(signalRef: 'top.cnt'),
                        'enable': StageSignalBinding(signalRef: 'top.en'),
                      },
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
        });
      },
    );

    test('multiple Stage panels with active selection round-trip', () async {
      await _withTempFile((path) async {
        const original = SessionState(
          stageWorkspace: StageWorkspaceState(
            panels: [
              StagePanelConfig(id: 'p0', name: 'Bus Monitor'),
              StagePanelConfig(id: 'p1', name: 'I/O'),
            ],
            activePanelId: 'p1',
          ),
        );
        await _service.saveSession(original, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.stageWorkspace.panels, hasLength(2));
        expect(loaded.stageWorkspace.activePanelId, 'p1');
      });
    });

    test('stageViewVisible flag round-trips', () async {
      await _withTempFile((path) async {
        const s = SessionState(stageViewVisible: true);
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.stageViewVisible, isTrue);
      });
    });

    test('multi-bit slice bindings (DE10-Nano packed ADC bus) round-trip '
        'through saveSession / loadSession', () async {
      // Mirrors the DE10-Nano `adc_ch[95:0]` 96-bit packed bus → 8 ADC
      // slot bindings (12 bits per slot). The slice metadata
      // (`bitIndex` + `bitWidth`) must survive a full round-trip;
      // older single-bit fan-out bindings (no `bitWidth`) and
      // whole-signal bindings (no `bitIndex`) must round-trip unchanged
      // so existing sessions don't drift.
      await _withTempFile((path) async {
        const original = SessionState(
          stageWorkspace: StageWorkspaceState(
            panels: [
              StagePanelConfig(
                id: 'p0',
                name: 'DE10-Nano',
                instances: [
                  StageInstance(
                    id: 'adc_ch0',
                    widgetId: 'signalGraph',
                    signalBindings: {
                      // bits[11:0] of the 96-bit packed bus
                      'value': StageSignalBinding(
                        signalRef: 'top.adc_ch',
                        bitIndex: 0,
                        bitWidth: 12,
                      ),
                    },
                  ),
                  StageInstance(
                    id: 'adc_ch7',
                    widgetId: 'signalGraph',
                    signalBindings: {
                      // bits[95:84] — the highest channel
                      'value': StageSignalBinding(
                        signalRef: 'top.adc_ch',
                        bitIndex: 84,
                        bitWidth: 12,
                      ),
                    },
                  ),
                  StageInstance(
                    id: 'led3',
                    widgetId: 'led',
                    signalBindings: {
                      // Single-bit fan-out (no bitWidth) — must
                      // round-trip exactly without spurious bitWidth
                      // appearing on reload.
                      'in': StageSignalBinding(
                        signalRef: 'top.dut.led',
                        bitIndex: 3,
                      ),
                    },
                  ),
                  StageInstance(
                    id: 'sevenSeg',
                    widgetId: 'sevenSeg',
                    signalBindings: {
                      // Whole-signal binding — neither bitIndex nor
                      // bitWidth set.
                      'value': StageSignalBinding(signalRef: 'top.cnt'),
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

        final instances = loaded.stageWorkspace.panels.first.instances;
        final adcCh0 = instances.firstWhere((i) => i.id == 'adc_ch0');
        expect(adcCh0.signalBindings['value']!.bitIndex, 0);
        expect(adcCh0.signalBindings['value']!.bitWidth, 12);

        final adcCh7 = instances.firstWhere((i) => i.id == 'adc_ch7');
        expect(adcCh7.signalBindings['value']!.bitIndex, 84);
        expect(adcCh7.signalBindings['value']!.bitWidth, 12);

        final led3 = instances.firstWhere((i) => i.id == 'led3');
        expect(led3.signalBindings['in']!.bitIndex, 3);
        expect(
          led3.signalBindings['in']!.bitWidth,
          isNull,
          reason:
              'single-bit fan-out bindings must not gain a spurious '
              'bitWidth on reload',
        );

        final ss = instances.firstWhere((i) => i.id == 'sevenSeg');
        expect(ss.signalBindings['value']!.bitIndex, isNull);
        expect(ss.signalBindings['value']!.bitWidth, isNull);
      });
    });

    test('Stage instance configuration map round-trips', () async {
      await _withTempFile((path) async {
        const original = SessionState(
          stageWorkspace: StageWorkspaceState(
            panels: [
              StagePanelConfig(
                id: 'p0',
                name: 'A',
                instances: [
                  StageInstance(
                    id: 'i0',
                    widgetId: 'audio',
                    configuration: {
                      'fftSize': 2048,
                      'showFft': true,
                      'fftFloorDb': -60.0,
                      'fftWindow': 'hamming',
                      'channelMode': 'stereo',
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
        final inst = loaded.stageWorkspace.panels.first.instances.first;
        expect(inst.configuration['fftSize'], 2048);
        expect(inst.configuration['showFft'], true);
        expect(inst.configuration['fftFloorDb'], -60.0);
        expect(inst.configuration['fftWindow'], 'hamming');
        expect(inst.configuration['channelMode'], 'stereo');
        expect(loaded, equals(original));
      });
    });

    test(
      'pre-config session JSON loads with empty configuration '
      '(forward compatibility)',
      () async {
        await _withTempFile((path) async {
          // Hand-written JSON modeling a session saved before the
          // configuration field existed. The loader must treat the
          // missing 'configuration' key as the empty map and still
          // round-trip the rest of the instance cleanly.
          const json = '''
{
  "version": 1,
  "stage": {
    "panels": [
      {
        "id": "p0",
        "name": "Legacy",
        "instances": [
          {
            "id": "i0",
            "widgetId": "led",
            "bindings": {"in": {"ref": "top.clk"}},
            "x": 0,
            "y": 0,
            "width": 80,
            "height": 60
          }
        ]
      }
    ],
    "activePanelId": "p0"
  }
}
''';
          await File(path).writeAsString(json);
          final loaded = await _service.loadSession(path);
          final inst = loaded.stageWorkspace.panels.first.instances.first;
          expect(inst.id, 'i0');
          expect(inst.widgetId, 'led');
          expect(inst.configuration, isEmpty);
          expect(inst.signalBindings.length, 1);
        });
      },
    );

    test(
      'configuration is omitted from JSON when empty (byte-stable for '
      'pre-config sessions)',
      () async {
        await _withTempFile((path) async {
          const original = SessionState(
            stageWorkspace: StageWorkspaceState(
              panels: [
                StagePanelConfig(
                  id: 'p0',
                  name: 'A',
                  instances: [
                    StageInstance(id: 'i0', widgetId: 'led'),
                  ],
                ),
              ],
            ),
          );
          await _service.saveSession(original, path);
          final raw = await File(path).readAsString();
          expect(raw.contains('"configuration"'), isFalse);
        });
      },
    );

    test('save → load → save produces identical JSON', () async {
      await _withTempFile((path) async {
        const original = SessionState(
          stageWorkspace: StageWorkspaceState(
            panels: [
              StagePanelConfig(
                id: 'p0',
                name: 'A',
                instances: [
                  StageInstance(
                    id: 'i0',
                    widgetId: 'led',
                    signalBindings: {
                      'in': StageSignalBinding(signalRef: 'top.clk'),
                    },
                    x: 12,
                    y: 34,
                    label: 'CLK LED',
                  ),
                ],
              ),
            ],
            activePanelId: 'p0',
          ),
        );
        await _service.saveSession(original, path);
        final firstJson = await File(path).readAsString();
        final loaded = await _service.loadSession(path);
        await _service.saveSession(loaded, path);
        final secondJson = await File(path).readAsString();
        expect(secondJson, firstJson);
      });
    });
  });

  // ── missing / extra fields ────────────────────────────────────────────────────

  group('SessionService — missing fields (forward compatibility)', () {
    Future<SessionState> loadJson(String json) async {
      return await _withTempFile((path) async {
        await File(path).writeAsString(json);
        return await _service.loadSession(path);
      });
    }

    test('empty object uses all defaults', () async {
      final s = await loadJson('{}');
      expect(s, equals(const SessionState()));
    });

    test('missing cursor defaults to nulls', () async {
      final s = await loadJson('{"version":1}');
      expect(s.cursorState.primaryCursorTime, isNull);
    });

    test(
      'missing panels defaults to visible signal tree and value column',
      () async {
        final s = await loadJson('{"version":1}');
        expect(s.signalTreeVisible, isTrue);
        expect(s.valueColumnVisible, isTrue);
        expect(s.transactionViewVisible, isFalse);
      },
    );

    test('missing view defaults to ticksPerPixel=1, panOffset=0', () async {
      final s = await loadJson('{"version":1}');
      expect(s.ticksPerPixel, 1.0);
      expect(s.panOffsetTicks, 0.0);
    });

    test('extra unknown keys are ignored', () async {
      final s = await loadJson(
        '{"version":1,"unknownFutureField":"value","signals":[]}',
      );
      expect(s, equals(const SessionState()));
    });

    test('unknown signal kind degrades to separator', () async {
      final s = await loadJson(
        '{"signals":[{"kind":"unknownFutureKind"}]}',
      );
      expect(s.signalGroup.entries[0].kind, SignalEntryKind.separator);
    });

    test('unknown display format defaults to hexadecimal', () async {
      final s = await loadJson(
        '{"signals":[{"kind":"signal","ref":"r","name":"n","format":"futureFormat"}]}',
      );
      expect(s.signalGroup.entries[0].format, DisplayFormat.hexadecimal);
    });

    test(
      'legacy board_theme:realistic field on a stage instance is ignored',
      () async {
        // The realistic-theme toggle was removed in v0.12.6. Old session
        // files (or third-party tooling) may carry a `board_theme` field
        // on board instances; the loader must not throw and must round-
        // trip the rest of the instance cleanly.
        final s = await loadJson(
          '{"stage":{"activePanelId":"p0","panels":[{"id":"p0","name":"P",'
          '"instances":[{"id":"i0","widgetId":"basys3","x":10,"y":20,'
          '"width":640,"height":360,"bindings":{},'
          '"board_theme":"realistic"}]}]}}',
        );
        expect(s.stageWorkspace.panels, hasLength(1));
        final inst = s.stageWorkspace.panels.first.instances.first;
        expect(inst.id, 'i0');
        expect(inst.widgetId, 'basys3');
        expect(inst.x, 10);
        expect(inst.width, 640);
      },
    );
  });

  // ── activeThemeName ───────────────────────────────────────────────────────────

  group('SessionService — activeThemeName', () {
    test('default theme name round-trips', () async {
      await _withTempFile((path) async {
        await _service.saveSession(const SessionState(), path);
        final loaded = await _service.loadSession(path);
        expect(loaded.activeThemeName, 'wavecrux-dark');
      });
    });

    test('custom theme name round-trips', () async {
      await _withTempFile((path) async {
        await _service.saveSession(
          const SessionState(activeThemeName: 'solarized-dark'),
          path,
        );
        final loaded = await _service.loadSession(path);
        expect(loaded.activeThemeName, 'solarized-dark');
      });
    });

    test('saved file contains activeTheme key', () async {
      await _withTempFile((path) async {
        await _service.saveSession(
          const SessionState(activeThemeName: 'oscilloscope'),
          path,
        );
        final content = await File(path).readAsString();
        expect(content, contains('"activeTheme": "oscilloscope"'));
      });
    });

    test('missing activeTheme key defaults to wavecrux-dark', () async {
      await _withTempFile((path) async {
        await File(path).writeAsString('{}');
        final loaded = await _service.loadSession(path);
        expect(loaded.activeThemeName, 'wavecrux-dark');
      });
    });
  });

  // ── renderAsAnalog ────────────────────────────────────────────────────────────

  group('SessionService — renderAsAnalog', () {
    SignalEntry sig({required bool analog}) => SignalEntry.signal(
      signalRef: 'ref-1',
      signalPath: 'top.dsp.sample_q',
      displayName: 'sample_q',
      format: DisplayFormat.fixedPointQ,
      renderAsAnalog: analog,
    );

    test('an analog row round-trips', () async {
      await _withTempFile((path) async {
        await _service.saveSession(
          SessionState(signalGroup: SignalGroup(entries: [sig(analog: true)])),
          path,
        );
        final loaded = await _service.loadSession(path);
        expect(loaded.signalGroup.entries.single.renderAsAnalog, isTrue);
        // The format is a separate axis and must survive independently.
        expect(
          loaded.signalGroup.entries.single.format,
          DisplayFormat.fixedPointQ,
        );
      });
    });

    test('a digital row round-trips', () async {
      await _withTempFile((path) async {
        await _service.saveSession(
          SessionState(signalGroup: SignalGroup(entries: [sig(analog: false)])),
          path,
        );
        final loaded = await _service.loadSession(path);
        expect(loaded.signalGroup.entries.single.renderAsAnalog, isFalse);
      });
    });

    test(
      'the key is omitted when false, so old sessions stay byte-stable',
      () async {
        await _withTempFile((path) async {
          await _service.saveSession(
            SessionState(
              signalGroup: SignalGroup(entries: [sig(analog: false)]),
            ),
            path,
          );
          final content = await File(path).readAsString();
          expect(content, isNot(contains('"analog"')));
        });
      },
    );

    test('the key is written when true', () async {
      await _withTempFile((path) async {
        await _service.saveSession(
          SessionState(signalGroup: SignalGroup(entries: [sig(analog: true)])),
          path,
        );
        final content = await File(path).readAsString();
        expect(content, contains('"analog": true'));
      });
    });

    test('a session written before the feature loads as digital', () async {
      // Forward-compatibility in the direction that actually happens: every
      // .wavecrux file already in the wild has no "analog" key.
      await _withTempFile((path) async {
        await File(path).writeAsString(
          '{"signals":[{"kind":"signal","ref":"r","name":"n",'
          '"format":"hexadecimal","height":30.0}]}',
        );
        final loaded = await _service.loadSession(path);
        expect(loaded.signalGroup.entries.single.renderAsAnalog, isFalse);
      });
    });
  });

  // ── version field ─────────────────────────────────────────────────────────────

  group('SessionService — version field', () {
    test('saved file contains current schema version', () async {
      // v2 introduced the reserved `extensions` map; v3 added
      // bottom-pane content selection, pane geometry, and signal-tree browser
      // state (session-restore parity); v4 added the `annotations` list.
      // See session_extensions_round_trip_test.dart for the
      // forward-compat policy and v1 read-back coverage, and
      // session_annotations_round_trip_test.dart for the v4 delta.
      await _withTempFile((path) async {
        await _service.saveSession(const SessionState(), path);
        final content = await File(path).readAsString();
        expect(
          content,
          contains('"version": ${SessionService.currentSchemaVersion}'),
        );
      });
    });
  });

  // ── v3: panels content, pane geometry, signal-tree state ──────────────────────

  group('SessionService — v3 session-restore state', () {
    Future<SessionState> loadJson(String json) async {
      return await _withTempFile((path) async {
        await File(path).writeAsString(json);
        return await _service.loadSession(path);
      });
    }

    test('cocotb/RTL panel flags and source paths round-trip', () async {
      const s = SessionState(
        cocotbLogPanelVisible: true,
        rtlSourceVisible: true,
        cocotbLogPath: '/tmp/sim.log',
        rtlStemsPath: '/tmp/stems.json',
      );
      await _withTempFile((path) async {
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.cocotbLogPanelVisible, isTrue);
        expect(loaded.rtlSourceVisible, isTrue);
        expect(loaded.cocotbLogPath, '/tmp/sim.log');
        expect(loaded.rtlStemsPath, '/tmp/stems.json');
      });
    });

    test('pane sizes round-trip', () async {
      const s = SessionState(
        leftPaneSize: 312,
        rightPaneSize: 188,
        bottomPaneSize: 240,
      );
      await _withTempFile((path) async {
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.leftPaneSize, 312);
        expect(loaded.rightPaneSize, 188);
        expect(loaded.bottomPaneSize, 240);
      });
    });

    test('null pane sizes are omitted and read back as null', () async {
      await _withTempFile((path) async {
        await _service.saveSession(const SessionState(), path);
        final content = await File(path).readAsString();
        expect(content, isNot(contains('"sizes"')));
        final loaded = await _service.loadSession(path);
        expect(loaded.leftPaneSize, isNull);
        expect(loaded.bottomPaneSize, isNull);
      });
    });

    test('signal-tree expand/search/selection/scroll round-trip', () async {
      const s = SessionState(
        expandedScopePaths: {'top', 'top.cpu', 'top.cpu.alu'},
        signalTreeSearchQuery: 'clk',
        signalTreeSelectedRefs: {'top.clk', 'top.rst'},
        signalTreeScrollOffset: 144,
      );
      await _withTempFile((path) async {
        await _service.saveSession(s, path);
        final loaded = await _service.loadSession(path);
        expect(loaded.expandedScopePaths, {'top', 'top.cpu', 'top.cpu.alu'});
        expect(loaded.signalTreeSearchQuery, 'clk');
        expect(loaded.signalTreeSelectedRefs, {'top.clk', 'top.rst'});
        expect(loaded.signalTreeScrollOffset, 144);
      });
    });

    test('default signal-tree state is omitted from JSON', () async {
      await _withTempFile((path) async {
        await _service.saveSession(const SessionState(), path);
        final content = await File(path).readAsString();
        expect(content, isNot(contains('"signalTreeState"')));
      });
    });

    test('a v1/v2 document missing all v3 keys loads with defaults', () async {
      final s = await loadJson(
        '{"version":2,"panels":{"signalTree":true,"valueColumn":true}}',
      );
      expect(s.cocotbLogPanelVisible, isFalse);
      expect(s.rtlSourceVisible, isFalse);
      expect(s.cocotbLogPath, isNull);
      expect(s.leftPaneSize, isNull);
      expect(s.expandedScopePaths, isEmpty);
      expect(s.signalTreeSearchQuery, '');
      expect(s.signalTreeSelectedRefs, isEmpty);
      expect(s.signalTreeScrollOffset, 0.0);
    });
  });

  // ── error handling ────────────────────────────────────────────────────────────

  group('SessionService — error handling', () {
    test('invalid JSON throws SessionLoadException', () async {
      await _withTempFile((path) async {
        await File(path).writeAsString('not valid json {{{{');
        expect(
          () => _service.loadSession(path),
          throwsA(isA<SessionLoadException>()),
        );
      });
    });

    test('non-object JSON root throws SessionLoadException', () async {
      await _withTempFile((path) async {
        await File(path).writeAsString('[1, 2, 3]');
        expect(
          () => _service.loadSession(path),
          throwsA(isA<SessionLoadException>()),
        );
      });
    });

    test('missing file throws SessionLoadException', () async {
      expect(
        () => _service.loadSession('/nonexistent/path/session.wavecrux'),
        throwsA(isA<SessionLoadException>()),
      );
    });

    test(
      'save to unwritable path throws SessionSaveException',
      () async {
        expect(
          () => _service.saveSession(
            const SessionState(),
            '/root/cannot_write_here/session.wavecrux',
          ),
          throwsA(isA<SessionSaveException>()),
        );
      },
      skip: Platform.isWindows,
    );

    test('SessionLoadException has filePath and reason', () async {
      await _withTempFile((path) async {
        await File(path).writeAsString('bad');
        try {
          await _service.loadSession(path);
          fail('expected SessionLoadException');
        } on SessionLoadException catch (e) {
          expect(e.filePath, path);
          expect(e.reason, isNotEmpty);
          expect(e.toString(), contains(path));
        }
      });
    });
  });
}
