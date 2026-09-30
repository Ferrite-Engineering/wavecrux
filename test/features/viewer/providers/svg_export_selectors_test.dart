// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// SVG export honours the export dialog's range and signal selectors.
//
// The export dialog offers "Time range" (visible / full) and "Signals"
// (visible / all) for every format, and until now `_exportSvg` read the LIVE
// providers and ignored both. Pick "Full simulation + All signals + SVG" and
// you silently got the current viewport — the same class of quiet lie the dialog
// disabled the selectors for on PNG.
//
// PNG genuinely cannot honour them: it is a capture of what is on screen.
// SVG can, because `exportSvg` is a parameterised emitter, so here the fix is
// to make it obey rather than to grey the controls out. These tests are what
// stop it silently regressing to reading the live state again.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/export_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';
import 'package:wavecrux/services/export/image_export_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

import '../../../helpers/product_telemetry_config.dart';
import '../../../helpers/wellen_ffi_library_gate.dart';

const _fixturePath = 'test/fixtures/vcd/scalar_basics.vcd';

/// Captures what `_exportSvg` decided to hand the emitter.
class _CapturingImageExportService implements ImageExportService {
  SignalGroup? signalGroup;
  TimeMapper? timeMapper;
  List<Annotation>? annotations;
  double? svgHeight;
  SvgExportPalette? palette;
  String Function(int)? formatTime;

  @override
  Future<void> exportSvg({
    required WaveformDataSource source,
    required SignalGroup signalGroup,
    required Map<String, Variable> signalMap,
    required TimeMapper timeMapper,
    required String path,
    double svgWidth = 1200,
    double svgHeight = 600,
    double laneHeight = 30,
    double labelWidth = 160,
    double rulerHeight = 24,
    List<Annotation> annotations = const <Annotation>[],
    Map<String, AnnotationStatus> annotationStatuses =
        const <String, AnnotationStatus>{},
    SvgExportPalette palette = const SvgExportPalette(),
    String Function(int tick)? formatTime,
  }) async {
    this.palette = palette;
    this.formatTime = formatTime;
    this.signalGroup = signalGroup;
    this.timeMapper = timeMapper;
    this.annotations = annotations;
    this.svgHeight = svgHeight;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._src);
  final WaveformDataSource? _src;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_src);
}

class _FakeSignalGroupsNotifier extends SignalGroupsNotifier {
  _FakeSignalGroupsNotifier(this._group);
  final SignalGroup _group;

  @override
  SignalGroup build() => _group;
}

class _FakeTimeMapperNotifier extends TimeMapperNotifier {
  _FakeTimeMapperNotifier(this._mapper);
  final TimeMapper _mapper;

  @override
  TimeMapper build() => _mapper;
}

class _SeededAnnotations extends AnnotationsNotifier {
  _SeededAnnotations(this._seed);
  final List<Annotation> _seed;

  @override
  List<Annotation> build() => _seed;
}

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [productTelemetryConfig, ...overrides],
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

SaveFilePicker _stubPicker(String path) =>
    ({
      required dialogTitle,
      required fileName,
      required allowedExtensions,
      required type,
    }) async => path;

void main() {
  if (!requireWellenFfiLibrary('SVG export selectors')) return;

  late WellenProvider source;
  late List<Variable> variables;

  setUp(() async {
    source = WellenProvider();
    await source.openFile(_fixturePath);
    variables = source.findVariables(const SignalFilter());
    for (final v in variables) {
      await source.loadSignal(v.signalRef);
    }
  });

  tearDown(() => source.close());

  /// Drives the dialog to SVG with the requested selectors and returns what the
  /// emitter was handed.
  Future<_CapturingImageExportService> exportSvg(
    WidgetTester tester, {
    required bool fullRange,
    required bool allSignals,
    List<Annotation> annotations = const [],
    bool annotationsVisible = true,
    bool includeAnnotations = true,
  }) async {
    final capture = _CapturingImageExportService();
    // Zoomed in: the live mapper shows a slice, so "Full simulation" has
    // something to be different from.
    final zoomed = TimeMapper(
      startTime: source.startTime,
      endTime: source.endTime,
      viewportWidth: 800,
      ticksPerPixel: (source.endTime - source.startTime) / 8000,
      panOffsetTicks: source.startTime.toDouble(),
    );
    // One lane displayed, though the file holds several.
    final displayed = SignalGroup(
      entries: [
        SignalEntry.signal(
          signalRef: variables.first.signalRef,
          signalPath: variables.first.fullPath,
          displayName: variables.first.name,
        ),
      ],
    );

    await tester.pumpWidget(
      _wrap(
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () =>
                ref.read(exportProvider.notifier).showExportDialog(context),
            child: const Text('Export'),
          ),
        ),
        overrides: [
          saveFilePickerProvider.overrideWithValue(_stubPicker('/tmp/o.svg')),
          waveformSourceProvider.overrideWith(
            () => _FakeSourceNotifier(source),
          ),
          signalGroupsProvider.overrideWith(
            () => _FakeSignalGroupsNotifier(displayed),
          ),
          signalVariablesMapProvider.overrideWithValue({
            for (final v in variables) v.signalRef: v,
          }),
          timeMapperProvider.overrideWith(
            () => _FakeTimeMapperNotifier(zoomed),
          ),
          annotationsProvider.overrideWith(
            () => _SeededAnnotations(annotations),
          ),
          annotationStatusesProvider.overrideWithValue({
            for (final a in annotations) a.id: AnnotationStatus.resolved,
          }),
          imageExportServiceProvider.overrideWithValue(capture),
        ],
      ),
    );

    await tester.tap(find.text('Export'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The dialog's content scrolls; the lower options sit off the 600 px test
    // surface until scrolled to, and a tap that misses is only a warning.
    Future<void> choose(String label) async {
      final finder = find.text(label);
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
    }

    await choose('SVG Vector');
    if (fullRange) await choose('Full Simulation');
    if (allSignals) await choose('All Loaded Signals');
    if (!includeAnnotations) await choose('Include annotations');
    if (!annotationsVisible) {
      final scope = ProviderScope.containerOf(
        tester.element(find.text('Export')),
      );
      scope.read(annotationsVisibleProvider.notifier).visible = false;
    }

    final exportButton = find.text('Export…');
    await tester.ensureVisible(exportButton);
    await tester.pump();
    await tester.tap(exportButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    return capture;
  }

  group('the Time range selector', () {
    testWidgets('"Visible" hands the emitter the live viewport', (
      tester,
    ) async {
      final capture = await exportSvg(
        tester,
        fullRange: false,
        allSignals: false,
      );

      expect(capture.timeMapper, isNotNull);
      expect(
        capture.timeMapper!.visibleRange,
        lessThan(source.endTime - source.startTime),
      );
    });

    testWidgets('"Full Simulation" really covers the whole trace', (
      tester,
    ) async {
      final capture = await exportSvg(
        tester,
        fullRange: true,
        allSignals: false,
      );

      expect(capture.timeMapper!.visibleStartTime, source.startTime);
      expect(capture.timeMapper!.visibleEndTime, source.endTime);
    });
  });

  group('the Signals selector', () {
    testWidgets('"Visible" hands the emitter the displayed lanes only', (
      tester,
    ) async {
      final capture = await exportSvg(
        tester,
        fullRange: false,
        allSignals: false,
      );

      expect(capture.signalGroup!.entries, hasLength(1));
    });

    testWidgets('"All Signals" reaches beyond what is on screen', (
      tester,
    ) async {
      final capture = await exportSvg(
        tester,
        fullRange: false,
        allSignals: true,
      );

      expect(
        capture.signalGroup!.entries.length,
        greaterThan(1),
        reason: 'the fixture holds more signals than the one displayed',
      );
      expect(capture.signalGroup!.entries.length, variables.length);
    });

    testWidgets('"All Signals" keeps every lane its own colour', (
      tester,
    ) async {
      // This branch synthesises entries for signals that are loaded rather than
      // displayed, and it used to build them bare — no `argbColor` at all. The
      // emitter then fell through to its single fallback and the whole document
      // came out uniformly green, whatever the viewer was showing.
      final capture = await exportSvg(
        tester,
        fullRange: false,
        allSignals: true,
      );

      final colours = capture.signalGroup!.entries
          .map((e) => e.argbColor)
          .toList();

      expect(
        colours.any((c) => c == null),
        isFalse,
        reason: 'every lane must carry a colour, or it takes the fallback',
      );
      expect(
        colours.toSet().length,
        colours.length,
        reason: 'lanes must be told apart, exactly as they are on the canvas',
      );
    });
  });

  group('document height', () {
    testWidgets('grows with the lane count rather than clipping them', (
      tester,
    ) async {
      // Overlapping lanes are wrong at every zoom. A fixed *width* is fine —
      // an SVG reader zooms — but height has to fit what is drawn.
      final visibleOnly = await exportSvg(
        tester,
        fullRange: false,
        allSignals: false,
      );
      final everything = await exportSvg(
        tester,
        fullRange: false,
        allSignals: true,
      );

      expect(
        everything.svgHeight,
        greaterThanOrEqualTo(visibleOnly.svgHeight!),
      );
      // And never below the floor, so a one-signal export is not a sliver.
      expect(visibleOnly.svgHeight, greaterThanOrEqualTo(200));
    });
  });

  group('annotations', () {
    Annotation note() => Annotation(
      id: 'n1',
      shape: AnnotationShape.callout,
      anchor: PointAnchor(time: 10, rowId: variables.first.fullPath),
      authorName: '',
      createdAt: DateTime.utc(2026, 8, 13),
      text: 'here',
    );

    testWidgets('ride along by default', (tester) async {
      final capture = await exportSvg(
        tester,
        fullRange: false,
        allSignals: false,
        annotations: [note()],
      );

      expect(capture.annotations, hasLength(1));
    });

    testWidgets('unticking "Include annotations" leaves them out', (
      tester,
    ) async {
      final capture = await exportSvg(
        tester,
        fullRange: false,
        allSignals: false,
        annotations: [note()],
        includeAnnotations: false,
      );

      expect(capture.annotations, isEmpty);
    });

    testWidgets('the session visibility toggle is honoured too', (
      tester,
    ) async {
      // Same rule PNG follows: what you exported is what you were looking at.
      final capture = await exportSvg(
        tester,
        fullRange: false,
        allSignals: false,
        annotations: [note()],
        annotationsVisible: false,
      );

      expect(capture.annotations, isEmpty);
    });
  });
}
