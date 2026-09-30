// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The share flow as a user drives it: invoke, read the disclosure, decide.
//
// These are widget tests because the disclosure step is the feature. B4's
// whole reason to exist as designed — rather than as a silent "write a zip"
// command — is that the app names what leaves the machine before it leaves,
// and an assertion that the dialog LISTS THE SIGNAL PATHS is the only thing
// stopping that degrading into a count in some later refactor.

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/browser_download_provider.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/pack/providers/pack_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/export_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/pack/pack_disclosure.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_spec.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_writer.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

import '../../helpers/fake_waveform_data_source.dart';
import '../../helpers/product_telemetry_config.dart';

// ── doubles ───────────────────────────────────────────────────────────────────

class _RecordingTelemetry implements TelemetryService {
  final events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);

  List<TelemetryEvent> named(String name) =>
      events.where((e) => e.name == name).toList();
}

/// Captures what would have been written without touching disk.
///
/// Returns a `File` handle for a path it never creates: the notifier only
/// needs the write to complete, and a test that actually wrote would be
/// asserting on `dart:io` rather than on what the share flow assembled.
class _CapturingPackWriter implements WaveCruxPackWriter {
  WaveCruxPackContents? captured;
  String? capturedPath;
  String? capturedPreviewPath;

  @override
  Uint8List buildBytes(WaveCruxPackContents contents) => Uint8List(0);

  @override
  Future<File> writeToFile({
    required String path,
    required WaveCruxPackContents contents,
  }) async {
    captured = contents;
    capturedPath = path;
    return File(path);
  }

  @override
  Future<File?> writePreviewBeside({
    required String packPath,
    required WaveCruxPackContents contents,
  }) async {
    if (contents.previewPng == null) return null;
    capturedPreviewPath = '$packPath.png';
    return File(capturedPreviewPath!);
  }
}

class _StubEstimator implements PackSizeEstimator {
  const _StubEstimator(this.bytes);
  final int bytes;

  @override
  int estimateBytes({
    required WaveformDataSource source,
    required covariant Object config,
    int sessionBytes = 0,
    int previewBytes = 0,
    int readmeBytes = 0,
  }) => bytes;
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

// ── fixtures ──────────────────────────────────────────────────────────────────

Variable _v(String name, String ref) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: ref,
  scopePath: 'top.core',
  bitWidth: 1,
);

final _source = FakeWaveformDataSource(
  signals: {
    'ref_clk': const [
      SignalChange(time: 0, value: '0'),
      SignalChange(time: 500, value: '1'),
    ],
    'ref_ack': const [
      SignalChange(time: 0, value: '0'),
      SignalChange(time: 600, value: '1'),
    ],
  },
  endTime: 2000,
);

final _group = SignalGroup(
  entries: [
    SignalEntry.signal(
      signalRef: 'ref_clk',
      signalPath: 'top.core.clk',
      displayName: 'clk',
    ),
    SignalEntry.signal(
      signalRef: 'ref_ack',
      signalPath: 'top.core.ack',
      displayName: 'ack',
    ),
  ],
);

const _mapper = TimeMapper(
  startTime: 0,
  endTime: 2000,
  viewportWidth: 800,
  ticksPerPixel: 2.5,
  panOffsetTicks: 0,
);

Annotation _note({String author = 'Dana', String id = 'n1', int time = 600}) =>
    Annotation(
      id: id,
      shape: AnnotationShape.callout,
      anchor: PointAnchor(time: time, rowId: 'top.core.ack'),
      text: 'ack never asserts here',
      authorName: author,
      createdAt: DateTime.utc(2026, 8, 13),
    );

// ── harness ───────────────────────────────────────────────────────────────────

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
  Locale? locale,
}) => ProviderScope(
  overrides: [productTelemetryConfig, ...overrides],
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: child),
  ),
);

List<Override> _baseOverrides({
  WaveformDataSource? source,
  SignalGroup? group,
  List<Annotation> annotations = const [],
  TelemetryService? telemetry,
  WaveCruxPackWriter? writer,
  PackSizeEstimator? estimator,
  String? savePath = '/tmp/out.wavecruxpack',
  BrowserDownload? browserDownload,
}) => [
  waveformSourceProvider.overrideWith(() => _FakeSourceNotifier(source)),
  signalGroupsProvider.overrideWith(
    () => _FakeSignalGroupsNotifier(group ?? _group),
  ),
  signalVariablesMapProvider.overrideWithValue({
    'ref_clk': _v('clk', 'ref_clk'),
    'ref_ack': _v('ack', 'ref_ack'),
  }),
  timeMapperProvider.overrideWith(() => _FakeTimeMapperNotifier(_mapper)),
  annotationsProvider.overrideWith(() => _SeededAnnotations(annotations)),
  saveFilePickerProvider.overrideWithValue(
    ({
      required dialogTitle,
      required fileName,
      required allowedExtensions,
      required type,
    }) async {
      // A save dialog in the browser build is the bug: it threw on the empty
      // placeholder bytes, so sharing did nothing.
      if (browserDownload != null) fail('the browser opened a save dialog');
      return savePath;
    },
  ),
  if (browserDownload != null)
    browserDownloadProvider.overrideWithValue(browserDownload),
  if (telemetry != null) telemetryServiceProvider.overrideWithValue(telemetry),
  if (writer != null) packWriterProvider.overrideWithValue(writer),
  if (estimator != null) packSizeEstimatorProvider.overrideWithValue(estimator),
];

Widget _trigger() => Consumer(
  builder: (context, ref, _) => TextButton(
    onPressed: () =>
        ref.read(sharePackProvider.notifier).shareAnnotatedWaveform(context),
    child: const Text('Share'),
  ),
);

Future<void> _tapShare(WidgetTester tester) async {
  await tester.tap(find.text('Share'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('preconditions', () {
    testWidgets('no waveform open — explains, and opens no dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_trigger(), overrides: _baseOverrides()),
      );
      await _tapShare(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('no signals in the view — explains, and opens no dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _trigger(),
          overrides: _baseOverrides(
            source: _source,
            group: const SignalGroup(),
          ),
        ),
      );
      await _tapShare(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a bundle past the hard ceiling is refused, not offered', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _trigger(),
          overrides: _baseOverrides(
            source: _source,
            annotations: [_note()],
            estimator: const _StubEstimator(
              WaveCruxPackSpec.refuseAboveBytes + 1,
            ),
          ),
        ),
      );
      await _tapShare(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('the disclosure', () {
    testWidgets('names every signal path, not a count', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _trigger(),
          overrides: _baseOverrides(source: _source, annotations: [_note()]),
        ),
      );
      await _tapShare(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('top.core.clk'), findsOneWidget);
      expect(find.text('top.core.ack'), findsOneWidget);
    });

    testWidgets('names the authors embedded in the annotations', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          _trigger(),
          overrides: _baseOverrides(
            source: _source,
            annotations: [
              _note(),
              _note(author: 'Ravi', id: 'n2'),
            ],
          ),
        ),
      );
      await _tapShare(tester);

      expect(find.text('Dana, Ravi'), findsOneWidget);
    });

    testWidgets(
      'offers no strip-authors control when nothing is attributed',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            _trigger(),
            overrides: _baseOverrides(
              source: _source,
              annotations: [_note(author: '')],
            ),
          ),
        );
        await _tapShare(tester);

        expect(find.byType(CheckboxListTile), findsNothing);
      },
    );

    testWidgets('warns when the bundle is too big to email', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _trigger(),
          overrides: _baseOverrides(
            source: _source,
            annotations: [_note()],
            estimator: const _StubEstimator(
              WaveCruxPackSpec.warnAboveBytes + 1,
            ),
          ),
        ),
      );
      await _tapShare(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
    });

    testWidgets('cancelling writes nothing', (tester) async {
      final writer = _CapturingPackWriter();
      await tester.pumpWidget(
        _wrap(
          _trigger(),
          overrides: _baseOverrides(
            source: _source,
            annotations: [_note()],
            writer: writer,
          ),
        ),
      );
      await _tapShare(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(writer.captured, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('what gets written', () {
    Future<_CapturingPackWriter> runShare(
      WidgetTester tester, {
      bool stripAuthors = false,
      TelemetryService? telemetry,
    }) async {
      final writer = _CapturingPackWriter();
      await tester.pumpWidget(
        _wrap(
          _trigger(),
          overrides: _baseOverrides(
            source: _source,
            annotations: [_note()],
            writer: writer,
            telemetry: telemetry,
          ),
        ),
      );
      await _tapShare(tester);
      if (stripAuthors) {
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
      }
      await tester.tap(find.text('Share…'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return writer;
    }

    testWidgets(
      'the bundled session points at the bundled dump, relatively',
      (tester) async {
        final writer = await runShare(tester);
        final contents = writer.captured;

        expect(contents, isNotNull);
        expect(
          contents!.sessionJson,
          contains('"sourceFilePath": "${WaveCruxPackSpec.waveformEntryName}"'),
        );
        // Never the sender's own path — that is the bug the whole rewrite
        // exists to prevent, and it is invisible on the sender's machine.
        expect(contents.sessionJson, isNot(contains('/Users/')));
        expect(writer.capturedPath, endsWith(WaveCruxPackSpec.fileExtension));
      },
    );

    testWidgets('the bundle carries the annotations and the waveform', (
      tester,
    ) async {
      final contents = (await runShare(tester)).captured!;

      expect(contents.sessionJson, contains('ack never asserts here'));
      expect(contents.waveformVcd, contains(r'$timescale'));
      expect(contents.waveformVcd, contains(r'$dumpvars'));
      expect(contents.readme, contains(WaveCruxPackSpec.landingPageUrl));
    });

    testWidgets('strip author names removes the name, keeps the note', (
      tester,
    ) async {
      final contents = (await runShare(tester, stripAuthors: true)).captured!;

      expect(contents.sessionJson, isNot(contains('Dana')));
      expect(contents.sessionJson, contains('ack never asserts here'));
    });

    testWidgets('records pack.exported once, with no properties', (
      tester,
    ) async {
      final telemetry = _RecordingTelemetry();
      await runShare(tester, telemetry: telemetry);

      // Counts only. A property here would be design data, and the event
      // exists to answer "does the loop work", which needs no dimension.
      expect(telemetry.named('pack.exported'), hasLength(1));
      expect(telemetry.named('pack.exported').single.properties, isEmpty);
    });

    testWidgets('in the browser the pack downloads, with no save dialog', (
      tester,
    ) async {
      final downloads = <String, List<int>>{};
      await tester.pumpWidget(
        _wrap(
          _trigger(),
          overrides: [
            ..._baseOverrides(
              source: _source,
              annotations: [_note()],
              browserDownload: ({required fileName, required bytes}) async {
                downloads[fileName] = bytes;
              },
            ),
          ],
        ),
      );
      await _tapShare(tester);
      await tester.tap(find.text('Share…'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(downloads, hasLength(1));
      final name = downloads.keys.single;
      expect(name, endsWith(WaveCruxPackSpec.fileExtension));
      final archive = ZipDecoder().decodeBytes(downloads[name]!);
      expect(
        archive.files.map((f) => f.name),
        containsAll(<String>[
          WaveCruxPackSpec.sessionEntryName,
          WaveCruxPackSpec.waveformEntryName,
        ]),
      );
      expect(find.text('Pack written to $name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('the disclosure renders in $locale', (tester) async {
        await tester.pumpWidget(
          _wrap(
            _trigger(),
            locale: locale,
            overrides: _baseOverrides(
              source: _source,
              annotations: [_note()],
            ),
          ),
        );
        await _tapShare(tester);

        expect(find.byType(AlertDialog), findsOneWidget);
        // The signal paths are data, not copy — they must survive every
        // locale, including the ones that wrap differently.
        expect(find.text('top.core.ack'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
