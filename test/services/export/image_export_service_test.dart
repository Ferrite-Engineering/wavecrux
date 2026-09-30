// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/export/image_export_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

const _service = ImageExportService();
const _fixturePath = 'test/fixtures/vcd/scalar_basics.vcd';

Future<T> _withTempDir<T>(Future<T> Function(String dir) fn) async {
  final dir = await Directory.systemTemp.createTemp('wavecrux_img_test_');
  try {
    return await fn(dir.path);
  } finally {
    await dir.delete(recursive: true);
  }
}

Variable _variable(String name, String ref, {int bitWidth = 1}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: ref,
  scopePath: 'top',
  bitWidth: bitWidth,
);

void main() {
  if (requireWellenFfiLibrary('image export of scalar_basics.vcd')) {
    // ── generateSvg ──────────────────────────────────────────────────────────

    group('ImageExportService.generateSvg', () {
      late WellenProvider source;
      late TimeMapper timeMapper;

      setUp(() async {
        source = WellenProvider();
        await source.openFile(_fixturePath);
        final vars = source.findVariables(const SignalFilter());
        for (final v in vars) {
          await source.loadSignal(v.signalRef);
        }
        timeMapper = TimeMapper.fitAll(
          startTime: source.startTime,
          endTime: source.endTime,
          viewportWidth: 800,
        );
      });

      tearDown(() => source.close());

      test('returns valid SVG string', () {
        const clkRef = '!';
        final group = SignalGroup(
          entries: [
            SignalEntry.signal(signalRef: clkRef, displayName: 'clk'),
          ],
        );
        final signalMap = {clkRef: _variable('clk', clkRef)};

        final svg = _service.generateSvg(
          source: source,
          signalGroup: group,
          signalMap: signalMap,
          timeMapper: timeMapper,
        );

        expect(svg, contains('<svg'));
        expect(svg, contains('</svg>'));
      });

      test('SVG contains signal label', () {
        const clkRef = '!';
        final group = SignalGroup(
          entries: [
            SignalEntry.signal(signalRef: clkRef, displayName: 'clk'),
          ],
        );
        final signalMap = {clkRef: _variable('clk', clkRef)};

        final svg = _service.generateSvg(
          source: source,
          signalGroup: group,
          signalMap: signalMap,
          timeMapper: timeMapper,
        );

        expect(svg, contains('clk'));
      });

      test('SVG with no signals still returns valid XML', () {
        const group = SignalGroup();
        final emptyMap = <String, Variable>{};

        final svg = _service.generateSvg(
          source: source,
          signalGroup: group,
          signalMap: emptyMap,
          timeMapper: timeMapper,
        );

        expect(svg, contains('<svg'));
        expect(svg, contains('</svg>'));
      });

      test('SVG contains time ruler section', () {
        const clkRef = '!';
        final group = SignalGroup(
          entries: [
            SignalEntry.signal(signalRef: clkRef, displayName: 'clk'),
          ],
        );
        final signalMap = {clkRef: _variable('clk', clkRef)};

        final svg = _service.generateSvg(
          source: source,
          signalGroup: group,
          signalMap: signalMap,
          timeMapper: timeMapper,
        );

        expect(svg, contains('<line'));
      });
    });

    // ── exportSvg ────────────────────────────────────────────────────────────

    group('ImageExportService.exportSvg', () {
      late WellenProvider source;
      late TimeMapper timeMapper;

      setUp(() async {
        source = WellenProvider();
        await source.openFile(_fixturePath);
        final vars = source.findVariables(const SignalFilter());
        for (final v in vars) {
          await source.loadSignal(v.signalRef);
        }
        timeMapper = TimeMapper.fitAll(
          startTime: source.startTime,
          endTime: source.endTime,
          viewportWidth: 800,
        );
      });

      tearDown(() => source.close());

      test('creates file at given path', () async {
        await _withTempDir((dir) async {
          final path = '$dir/waveform.svg';
          const clkRef = '!';
          final group = SignalGroup(
            entries: [
              SignalEntry.signal(signalRef: clkRef, displayName: 'clk'),
            ],
          );
          final signalMap = {clkRef: _variable('clk', clkRef)};

          await _service.exportSvg(
            source: source,
            signalGroup: group,
            signalMap: signalMap,
            timeMapper: timeMapper,
            path: path,
          );

          expect(File(path).existsSync(), isTrue);
          expect(File(path).lengthSync(), greaterThan(0));
        });
      });

      test('written file contains valid SVG content', () async {
        await _withTempDir((dir) async {
          final path = '$dir/waveform.svg';
          const group = SignalGroup();

          await _service.exportSvg(
            source: source,
            signalGroup: group,
            signalMap: <String, Variable>{},
            timeMapper: timeMapper,
            path: path,
          );

          final content = await File(path).readAsString();
          expect(content, contains('<svg'));
          expect(content, contains('</svg>'));
        });
      });

      test(
        'throws ImageWriteException on unwritable path',
        () async {
          const group = SignalGroup();
          await expectLater(
            _service.exportSvg(
              source: source,
              signalGroup: group,
              signalMap: <String, Variable>{},
              timeMapper: timeMapper,
              path: '/no_permission/waveform.svg',
            ),
            throwsA(isA<ImageWriteException>()),
          );
        },
        skip: Platform.isWindows,
      );
    });
  }

  // ── capturePng — no RenderRepaintBoundary in headless test ─────────────────

  group('ImageExportService.capturePng', () {
    test('throws ImageCaptureException for unattached GlobalKey', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final key = GlobalKey();
      Object? caught;
      try {
        await _service.capturePng(key);
      } on ImageCaptureException catch (e) {
        caught = e;
      }
      expect(caught, isA<ImageCaptureException>());
    });
  });

  // ── generateSvg — zero visible range ───────────────────────────────────────

  group('ImageExportService.generateSvg — zero range', () {
    test('returns valid SVG when visible range is zero', () {
      // ticksPerPixel so small that visibleEnd rounds to the same tick as
      // visibleStart, giving visibleEnd - visibleStart == 0.
      const zeroMapper = TimeMapper(
        startTime: 0,
        endTime: 100,
        viewportWidth: 1000,
        ticksPerPixel: 1e-8,
        panOffsetTicks: 50,
      );
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: '!', displayName: 'clk'),
        ],
      );
      final signalMap = {'!': _variable('clk', '!')};

      const source = _StubSource(
        start: 0,
        end: 0,
        loaded: {'!'},
        values: {},
        changes: {},
      );

      final svg = _service.generateSvg(
        source: source,
        signalGroup: group,
        signalMap: signalMap,
        timeMapper: zeroMapper,
      );

      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      // Ruler background rect only appears when range > 0.
      expect(svg, isNot(contains('fill="#252540"')));
    });
  });

  // ── generateSvg — vector signal ────────────────────────────────────────────

  group('ImageExportService.generateSvg — vector signal', () {
    test('renders parallelogram path for multi-bit signal', () {
      const busRef = 'bus';
      const source = _StubSource(
        start: 0,
        end: 100,
        loaded: {busRef},
        values: {busRef: 'ff'},
        changes: {
          busRef: [SignalChange(time: 50, value: '00')],
        },
      );
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: busRef, displayName: 'data'),
        ],
      );
      final signalMap = {busRef: _variable('data', busRef, bitWidth: 8)};
      final mapper = TimeMapper.fitAll(
        startTime: 0,
        endTime: 100,
        viewportWidth: 800,
      );

      final svg = _service.generateSvg(
        source: source,
        signalGroup: group,
        signalMap: signalMap,
        timeMapper: mapper,
      );

      expect(svg, contains('<path'));
    });

    test('renders x-value vector segment with red fill', () {
      const busRef = 'xbus';
      // Need at least one change so the trace builder doesn't short-circuit.
      const source = _StubSource(
        start: 0,
        end: 100,
        loaded: {busRef},
        values: {busRef: 'xxxx'},
        changes: {
          busRef: [SignalChange(time: 50, value: '0000')],
        },
      );
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: busRef, displayName: 'xb'),
        ],
      );
      final signalMap = {busRef: _variable('xb', busRef, bitWidth: 4)};
      final mapper = TimeMapper.fitAll(
        startTime: 0,
        endTime: 100,
        viewportWidth: 800,
      );

      final svg = _service.generateSvg(
        source: source,
        signalGroup: group,
        signalMap: signalMap,
        timeMapper: mapper,
      );

      expect(svg, contains('#ff4444'));
    });
  });

  // ── generateSvg — scalar x/z states ────────────────────────────────────────

  group('ImageExportService.generateSvg — scalar x/z states', () {
    test('x value renders dashed red line', () {
      const ref = 'sig';
      const source = _StubSource(
        start: 0,
        end: 100,
        loaded: {ref},
        values: {ref: 'x'},
        changes: {
          ref: [SignalChange(time: 50, value: '1')],
        },
      );
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: ref, displayName: 'sig'),
        ],
      );
      final signalMap = {ref: _variable('sig', ref)};
      final mapper = TimeMapper.fitAll(
        startTime: 0,
        endTime: 100,
        viewportWidth: 800,
      );

      final svg = _service.generateSvg(
        source: source,
        signalGroup: group,
        signalMap: signalMap,
        timeMapper: mapper,
      );

      expect(svg, contains('#ff4444'));
      expect(svg, contains('stroke-dasharray'));
    });

    test('z value renders dashed green line', () {
      const ref = 'zsig';
      const source = _StubSource(
        start: 0,
        end: 100,
        loaded: {ref},
        values: {ref: 'z'},
        changes: {
          ref: [SignalChange(time: 50, value: '1')],
        },
      );
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: ref, displayName: 'zsig'),
        ],
      );
      final signalMap = {ref: _variable('zsig', ref)};
      final mapper = TimeMapper.fitAll(
        startTime: 0,
        endTime: 100,
        viewportWidth: 800,
      );

      final svg = _service.generateSvg(
        source: source,
        signalGroup: group,
        signalMap: signalMap,
        timeMapper: mapper,
      );

      expect(svg, contains('#44ff88'));
      expect(svg, contains('stroke-dasharray'));
    });

    test('1 value renders top-aligned line (no dashes)', () {
      const ref = 'high';
      const source = _StubSource(
        start: 0,
        end: 100,
        loaded: {ref},
        values: {ref: '1'},
        changes: {ref: []},
      );
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: ref, displayName: 'high'),
        ],
      );
      final signalMap = {ref: _variable('high', ref)};
      final mapper = TimeMapper.fitAll(
        startTime: 0,
        endTime: 100,
        viewportWidth: 800,
      );

      final svg = _service.generateSvg(
        source: source,
        signalGroup: group,
        signalMap: signalMap,
        timeMapper: mapper,
      );

      // High line is drawn at laneY + laneHeight * 0.1 (top fraction).
      expect(svg, contains('<line'));
      // No dashes for a clean high signal.
      expect(svg, isNot(contains('stroke-dasharray')));
    });
  });

  // ── generateSvg — unloaded signal ──────────────────────────────────────────

  group('ImageExportService.generateSvg — unloaded signal', () {
    test('renders label but skips trace for unloaded signal', () {
      const ref = 'notloaded';
      const source = _StubSource(
        start: 0,
        end: 100,
        loaded: {},
        values: {},
        changes: {},
      );
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: ref, displayName: 'unloaded_sig'),
        ],
      );
      final signalMap = {ref: _variable('unloaded_sig', ref)};
      final mapper = TimeMapper.fitAll(
        startTime: 0,
        endTime: 100,
        viewportWidth: 800,
      );

      final svg = _service.generateSvg(
        source: source,
        signalGroup: group,
        signalMap: signalMap,
        timeMapper: mapper,
      );

      // Label is truncated to 9 chars + '…' by _sanitizeSvgText.
      expect(svg, contains('unloaded_'));
      // No waveform trace elements — no lines with stroke-width="1.5".
      expect(svg, isNot(contains('stroke-width="1.5"')));
    });
  });

  // ── generateSvg — SVG text sanitization ────────────────────────────────────

  group('ImageExportService.generateSvg — label sanitization', () {
    test('sanitizes HTML entities in signal label', () {
      const ref = 'special';
      const source = _StubSource(
        start: 0,
        end: 100,
        loaded: {},
        values: {},
        changes: {},
      );
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: ref, displayName: 'a&b<c>d'),
        ],
      );
      final signalMap = {ref: _variable('a&b<c>d', ref)};
      final mapper = TimeMapper.fitAll(
        startTime: 0,
        endTime: 100,
        viewportWidth: 800,
      );

      final svg = _service.generateSvg(
        source: source,
        signalGroup: group,
        signalMap: signalMap,
        timeMapper: mapper,
      );

      expect(svg, contains('&amp;'));
      expect(svg, contains('&lt;'));
      expect(svg, contains('&gt;'));
      // Raw unescaped chars must not appear in a text element.
      expect(svg, isNot(contains('>a&b<c>d<')));
    });

    test('truncates label longer than 10 characters with ellipsis', () {
      const ref = 'longname';
      const source = _StubSource(
        start: 0,
        end: 100,
        loaded: {},
        values: {},
        changes: {},
      );
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(
            signalRef: ref,
            displayName: 'very_long_signal_name',
          ),
        ],
      );
      final signalMap = {ref: _variable('very_long_signal_name', ref)};
      final mapper = TimeMapper.fitAll(
        startTime: 0,
        endTime: 100,
        viewportWidth: 800,
      );

      final svg = _service.generateSvg(
        source: source,
        signalGroup: group,
        signalMap: signalMap,
        timeMapper: mapper,
      );

      // The label is truncated to 9 chars + '…' (U+2026).
      expect(svg, contains('very_long'));
      expect(svg, contains('…'));
      expect(svg, isNot(contains('very_long_signal_name')));
    });
  });

  // ── exportSvg — error path ─────────────────────────────────────────────────

  group('ImageExportService.exportSvg — error handling', () {
    test(
      'throws ImageWriteException when parent directory cannot be created',
      () async {
        // Path under /proc is unwritable on Linux; /System is unwritable on macOS.
        const unwritable = '/no_permission_dir_xyz/sub/waveform.svg';
        const source = _StubSource(
          start: 0,
          end: 100,
          loaded: {},
          values: {},
          changes: {},
        );

        await expectLater(
          _service.exportSvg(
            source: source,
            signalGroup: const SignalGroup(),
            signalMap: const {},
            timeMapper: TimeMapper.fitAll(
              startTime: 0,
              endTime: 100,
              viewportWidth: 800,
            ),
            path: unwritable,
          ),
          throwsA(isA<ImageWriteException>()),
        );
      },
      skip: Platform.isWindows,
    );
  });

  // ── generateSvg — nested group signals ─────────────────────────────────────

  group('ImageExportService.generateSvg — nested groups', () {
    test('collects signals from nested groups into SVG', () {
      const ref1 = 'sig1';
      const ref2 = 'sig2';
      const source = _StubSource(
        start: 0,
        end: 100,
        loaded: {},
        values: {},
        changes: {},
      );
      final group = SignalGroup(
        entries: [
          SignalEntry.group(
            groupName: 'Bus',
            children: [
              SignalEntry.signal(signalRef: ref1, displayName: 'first'),
              SignalEntry.signal(signalRef: ref2, displayName: 'second'),
            ],
          ),
        ],
      );
      final signalMap = {
        ref1: _variable('first', ref1),
        ref2: _variable('second', ref2),
      };
      final mapper = TimeMapper.fitAll(
        startTime: 0,
        endTime: 100,
        viewportWidth: 800,
      );

      final svg = _service.generateSvg(
        source: source,
        signalGroup: group,
        signalMap: signalMap,
        timeMapper: mapper,
      );

      expect(svg, contains('first'));
      expect(svg, contains('second'));
    });
  });
}

// ── stub WaveformDataSource ──────────────────────────────────────────────────

class _StubSource implements WaveformDataSource {
  const _StubSource({
    required this.start,
    required this.end,
    required this.loaded,
    required this.values,
    required this.changes,
  });

  final int start;
  final int end;
  final Set<String> loaded;
  final Map<String, String> values;
  final Map<String, List<SignalChange>> changes;

  @override
  int get startTime => start;

  @override
  int get endTime => end;

  @override
  bool isSignalLoaded(String signalRef) => loaded.contains(signalRef);

  @override
  String? valueAt(String signalRef, int time) => values[signalRef];

  @override
  List<SignalChange> changesInRange(String signalRef, int s, int e) =>
      changes[signalRef] ?? const [];

  @override
  Future<void> openFile(String path) async {}

  @override
  void close() {}

  @override
  List<Scope> get rootScopes => const [];

  @override
  List<Variable> findVariables(SignalFilter filter) => const [];

  @override
  Future<void> loadSignal(String signalRef) async {}

  @override
  Future<void> unloadSignal(String signalRef) async {}

  @override
  SignalChange? nextTransition(String signalRef, int afterTime) => null;

  @override
  SignalChange? prevTransition(String signalRef, int beforeTime) => null;

  @override
  Timescale? get timescale => null;

  @override
  String? get date => null;

  @override
  String? get version => null;
}
