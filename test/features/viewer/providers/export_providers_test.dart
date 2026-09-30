// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/core/providers/browser_download_provider.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/export_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/export/image_export_service.dart';
import 'package:wavecrux/services/vcd_writer/vcd_writer_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

import '../../../helpers/product_telemetry_config.dart';
import '../../../helpers/wellen_ffi_library_gate.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

Variable _v(
  String name,
  String ref, {
  int bitWidth = 1,
  String scope = 'top',
}) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: ref,
  scopePath: scope,
  bitWidth: bitWidth,
);

ProviderContainer _makeContainer({
  SignalGroup? signalGroup,
  Map<String, Variable>? variableMap,
}) {
  final container = ProviderContainer(
    overrides: [
      productTelemetryConfig,
      if (signalGroup != null)
        signalGroupsProvider.overrideWith(
          () => _FakeSignalGroupsNotifier(signalGroup),
        ),
      if (variableMap != null)
        signalVariablesMapProvider.overrideWithValue(variableMap),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _FakeSignalGroupsNotifier extends SignalGroupsNotifier {
  _FakeSignalGroupsNotifier(this._group);
  final SignalGroup _group;

  @override
  SignalGroup build() => _group;
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  if (!requireWellenFfiLibrary('export providers')) return;

  group('exportSignalMapProvider', () {
    test('re-exports signalVariablesMapProvider value', () {
      final variables = {
        'ref_clk': _v('clk', 'ref_clk'),
        'ref_rst': _v('rst', 'ref_rst'),
      };
      final container = _makeContainer(variableMap: variables);

      final result = container.read(exportSignalMapProvider);
      expect(result, equals(variables));
    });

    test('returns empty map when no signals loaded', () {
      final container = _makeContainer(variableMap: {});
      expect(container.read(exportSignalMapProvider), isEmpty);
    });
  });

  group('ExportNotifier — build', () {
    test('builds without error', () {
      final container = ProviderContainer(overrides: [productTelemetryConfig]);
      addTearDown(container.dispose);
      expect(
        () => container.read(exportProvider.notifier),
        returnsNormally,
      );
    });

    test('state is void (no persistent state)', () {
      final container = ProviderContainer(overrides: [productTelemetryConfig]);
      addTearDown(container.dispose);
      // Reading the provider should not throw; the notifier holds no state.
      container.read(exportProvider);
    });
  });

  group('VcdExportConfig.fromSignalGroup', () {
    test('flat signal group extracts all refs', () {
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: 'top.clk', displayName: 'clk'),
          SignalEntry.signal(signalRef: 'top.rst', displayName: 'rst'),
        ],
      );
      final config = VcdExportConfig.fromSignalGroup(
        signalGroup: group,
        signalMap: const {},
        startTime: 0,
        endTime: 100,
      );
      expect(config.signalRefs, containsAll(['top.clk', 'top.rst']));
      expect(config.startTime, 0);
      expect(config.endTime, 100);
    });

    test('nested groups are flattened', () {
      final group = SignalGroup(
        entries: [
          SignalEntry.group(
            groupName: 'CPU',
            children: [
              SignalEntry.signal(signalRef: 'cpu.clk', displayName: 'clk'),
              SignalEntry.signal(signalRef: 'cpu.data', displayName: 'data'),
            ],
          ),
          SignalEntry.signal(signalRef: 'top.rst', displayName: 'rst'),
        ],
      );
      final config = VcdExportConfig.fromSignalGroup(
        signalGroup: group,
        signalMap: const {},
        startTime: 0,
        endTime: 200,
      );
      expect(
        config.signalRefs,
        containsAll(['cpu.clk', 'cpu.data', 'top.rst']),
      );
    });

    test('empty group yields empty signalRefs', () {
      const group = SignalGroup();
      final config = VcdExportConfig.fromSignalGroup(
        signalGroup: group,
        signalMap: const {},
        startTime: 0,
        endTime: 100,
      );
      expect(config.signalRefs, isEmpty);
    });

    test('separators and comments are skipped', () {
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: 'top.clk', displayName: 'clk'),
          const SignalEntry.separator(),
          const SignalEntry.comment(text: 'note'),
        ],
      );
      final config = VcdExportConfig.fromSignalGroup(
        signalGroup: group,
        signalMap: const {},
        startTime: 0,
        endTime: 50,
      );
      expect(config.signalRefs, ['top.clk']);
    });
  });

  group('VcdExportConfig — equality', () {
    test('configs with same data are equal', () {
      const a = VcdExportConfig(
        signalRefs: ['a', 'b'],
        signalMap: {},
        startTime: 0,
        endTime: 100,
      );
      const b = VcdExportConfig(
        signalRefs: ['a', 'b'],
        signalMap: {},
        startTime: 0,
        endTime: 100,
      );
      expect(a, equals(b));
    });

    test('configs with different time range are not equal', () {
      const a = VcdExportConfig(
        signalRefs: ['a'],
        signalMap: {},
        startTime: 0,
        endTime: 100,
      );
      const b = VcdExportConfig(
        signalRefs: ['a'],
        signalMap: {},
        startTime: 0,
        endTime: 200,
      );
      expect(a, isNot(equals(b)));
    });
  });

  _widgetTests();
}

// ── widget-test infrastructure ────────────────────────────────────────────────

/// Builds a [SaveFilePicker] stub that ignores its arguments and resolves to
/// [path]. `file_picker` 12's `saveFile` is a static method and can no longer
/// be replaced via `FilePicker.platform = mock`, so the export flows are
/// tested by overriding [saveFilePickerProvider] with one of these.
SaveFilePicker _stubSavePicker(String? path) =>
    ({
      required dialogTitle,
      required fileName,
      required allowedExtensions,
      required type,
    }) async => path;

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._src);
  final WaveformDataSource? _src;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_src);
}

class _FakeTimeMapperNotifier extends TimeMapperNotifier {
  _FakeTimeMapperNotifier(this._mapper);
  final TimeMapper _mapper;

  @override
  TimeMapper build() => _mapper;
}

class _MockVcdWriterService extends Mock implements VcdWriterService {}

class _MockImageExportService extends Mock implements ImageExportService {}

// Fake stubs used only to satisfy registerFallbackValue().
class _FakeWds extends Fake implements WaveformDataSource {}

class _FakeSignalGroupFallback extends Fake implements SignalGroup {}

/// Wraps [child] in a [ProviderScope] + localized [MaterialApp] + [Scaffold].
Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [productTelemetryConfig, ...overrides],
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

// ── ExportNotifier widget tests ───────────────────────────────────────────────

void _widgetTests() {
  // Load the VCD fixture in setUp (outside FakeAsync) so that dart:io calls
  // don't leave lingering I/O handles that prevent pump() from settling.
  late WellenProvider source;

  setUpAll(() {
    registerFallbackValue(_FakeWds());
    registerFallbackValue(_FakeSignalGroupFallback());
    registerFallbackValue(
      const VcdExportConfig(
        signalRefs: [],
        signalMap: {},
        startTime: 0,
        endTime: 0,
      ),
    );
    registerFallbackValue(
      const TimeMapper(
        startTime: 0,
        endTime: 100,
        viewportWidth: 800,
        ticksPerPixel: 1,
        panOffsetTicks: 0,
      ),
    );
    registerFallbackValue(<String, Variable>{});
    registerFallbackValue(const SvgExportPalette());
  });

  setUp(() async {
    source = WellenProvider();
    await source.openFile('test/fixtures/vcd/scalar_basics.vcd');
    // WellenProvider assigns its own integer-keyed signal refs; eagerly load
    // every variable so the export tests can copy values regardless of which
    // signal they target.
    for (final v in source.findVariables(const SignalFilter())) {
      await source.loadSignal(v.signalRef);
    }
  });

  tearDown(() => source.close());

  group('ExportNotifier.copySignalValue', () {
    testWidgets('copies formatted value to system clipboard', (tester) async {
      // Intercept Clipboard.setData to capture the written text.
      String? capturedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            capturedText = ((call.arguments as Map)['text']) as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        _wrap(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => ref
                  .read(exportProvider.notifier)
                  .copySignalValue(context, 'top.clk', '0xFF'),
              child: const Text('Copy'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Copy'));
      await tester.pump();

      expect(capturedText, '0xFF');
    });

    testWidgets('shows snackbar after copy', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => ref
                  .read(exportProvider.notifier)
                  .copySignalValue(context, 'ref', 'val'),
              child: const Text('Copy'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Copy'));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('ExportNotifier.copySignalPath', () {
    testWidgets('copies path to system clipboard', (tester) async {
      String? capturedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            capturedText = ((call.arguments as Map)['text']) as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        _wrap(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => ref
                  .read(exportProvider.notifier)
                  .copySignalPath(context, 'top.cpu.clk'),
              child: const Text('Copy'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Copy'));
      await tester.pump();

      expect(capturedText, 'top.cpu.clk');
    });

    testWidgets('shows snackbar after copy', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => ref
                  .read(exportProvider.notifier)
                  .copySignalPath(context, 'some.path'),
              child: const Text('Copy'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Copy'));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('ExportNotifier.showExportDialog — no source loaded', () {
    testWidgets('shows error snackbar when no waveform is open', (
      tester,
    ) async {
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
            waveformSourceProvider.overrideWith(
              () => _FakeSourceNotifier(null),
            ),
          ],
        ),
      );

      await tester.tap(find.text('Export'));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      // No export dialog should open.
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('ExportNotifier.showExportDialog — dialog dismissed', () {
    testWidgets('no export happens when user cancels the dialog', (
      tester,
    ) async {
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
            waveformSourceProvider.overrideWith(
              () => _FakeSourceNotifier(source),
            ),
          ],
        ),
      );

      await tester.tap(find.text('Export'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // dialog entrance

      // Export dialog is open.
      expect(find.byType(AlertDialog), findsOneWidget);

      // User taps Cancel (exact localized string).
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // dialog exit

      // No snackbar, no crash.
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('ExportNotifier._exportPng — null repaintKey', () {
    testWidgets('shows error snackbar when no RepaintBoundary key is supplied', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => ref
                  .read(exportProvider.notifier)
                  // waveformRepaintKey deliberately omitted → null
                  .showExportDialog(context),
              child: const Text('Export'),
            ),
          ),
          overrides: [
            waveformSourceProvider.overrideWith(
              () => _FakeSourceNotifier(source),
            ),
          ],
        ),
      );

      await tester.tap(find.text('Export'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // dialog entrance

      // Select PNG format (exact localized string from exportDialogFormatPng).
      await tester.tap(find.text('PNG Image'));
      await tester.pump();

      // Confirm export using dialog's Export… button (not the TextButton behind it).
      await tester.tap(find.text('Export\u2026'));
      await tester.pump();
      await tester.pump(
        const Duration(milliseconds: 300),
      ); // let snackbar appear

      // Error snackbar must appear because repaintKey is null.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ExportNotifier._exportVcd — successful write', () {
    testWidgets('calls writeVcd and shows success snackbar', (tester) async {
      const fakePath = '/tmp/export.vcd';
      final mockVcd = _MockVcdWriterService();
      when(
        () => mockVcd.writeVcd(any(), any(), any()),
      ).thenAnswer((_) async {});

      final mapper = TimeMapper.fitAll(
        startTime: source.startTime,
        endTime: source.endTime,
        viewportWidth: 800,
      );
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: '!', displayName: 'clk'),
        ],
      );
      final signalMap = {'!': _v('clk', '!')};

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
            saveFilePickerProvider.overrideWithValue(_stubSavePicker(fakePath)),
            waveformSourceProvider.overrideWith(
              () => _FakeSourceNotifier(source),
            ),
            signalGroupsProvider.overrideWith(
              () => _FakeSignalGroupsNotifier(group),
            ),
            signalVariablesMapProvider.overrideWithValue(signalMap),
            timeMapperProvider.overrideWith(
              () => _FakeTimeMapperNotifier(mapper),
            ),
            vcdWriterServiceProvider.overrideWithValue(mockVcd),
          ],
        ),
      );

      await tester.tap(find.text('Export'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // dialog entrance
      // VCD is selected by default — tap the dialog's Export… button.
      await tester.tap(find.text('Export\u2026'));
      await tester.pump();
      await tester.pump(
        const Duration(milliseconds: 300),
      ); // dialog exit + async chain
      await tester.pump(); // snackbar

      verify(() => mockVcd.writeVcd(any(), any(), fakePath)).called(1);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('file picker cancel returns silently without snackbar', (
      tester,
    ) async {
      // User cancels the save dialog → null returned.
      final mapper = TimeMapper.fitAll(
        startTime: source.startTime,
        endTime: source.endTime,
        viewportWidth: 800,
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
            saveFilePickerProvider.overrideWithValue(_stubSavePicker(null)),
            waveformSourceProvider.overrideWith(
              () => _FakeSourceNotifier(source),
            ),
            timeMapperProvider.overrideWith(
              () => _FakeTimeMapperNotifier(mapper),
            ),
          ],
        ),
      );

      await tester.tap(find.text('Export'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // dialog entrance
      await tester.tap(find.text('Export\u2026'));
      await tester.pump();
      await tester.pump(
        const Duration(milliseconds: 300),
      ); // dialog exit + picker returns null
      await tester.pump(); // _exportVcd returns early, nothing more to process

      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('in the browser the VCD downloads, with no save dialog', (
      tester,
    ) async {
      final mockVcd = _MockVcdWriterService();
      when(() => mockVcd.generateVcd(any(), any())).thenReturn('VCD BODY');
      final downloads = <String, List<int>>{};
      final mapper = TimeMapper.fitAll(
        startTime: source.startTime,
        endTime: source.endTime,
        viewportWidth: 800,
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
            browserDownloadProvider.overrideWithValue(({
              required fileName,
              required bytes,
            }) async {
              downloads[fileName] = bytes;
            }),
            // A save dialog in the browser build is the bug: it threw on the
            // empty placeholder bytes, so the export did nothing.
            saveFilePickerProvider.overrideWithValue(
              ({
                required dialogTitle,
                required fileName,
                required allowedExtensions,
                required type,
              }) => fail('the browser build opened a save dialog'),
            ),
            waveformSourceProvider.overrideWith(
              () => _FakeSourceNotifier(source),
            ),
            signalGroupsProvider.overrideWith(
              () => _FakeSignalGroupsNotifier(
                SignalGroup(
                  entries: [
                    SignalEntry.signal(signalRef: '!', displayName: 'clk'),
                  ],
                ),
              ),
            ),
            signalVariablesMapProvider.overrideWithValue({
              '!': _v('clk', '!'),
            }),
            timeMapperProvider.overrideWith(
              () => _FakeTimeMapperNotifier(mapper),
            ),
            vcdWriterServiceProvider.overrideWithValue(mockVcd),
          ],
        ),
      );

      await tester.tap(find.text('Export'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Export…'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(downloads.keys, ['export.vcd']);
      expect(utf8.decode(downloads['export.vcd']!), 'VCD BODY');
      verifyNever(() => mockVcd.writeVcd(any(), any(), any()));
      expect(find.text('VCD exported to export.vcd'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ExportNotifier._exportSvg — successful write', () {
    testWidgets('calls exportSvg and shows success snackbar', (tester) async {
      const fakePath = '/tmp/export.svg';
      final mockImg = _MockImageExportService();
      when(
        () => mockImg.exportSvg(
          source: any(named: 'source'),
          signalGroup: any(named: 'signalGroup'),
          signalMap: any(named: 'signalMap'),
          timeMapper: any(named: 'timeMapper'),
          path: any(named: 'path'),
          // SVG export takes these three. A stub that omits them stops matching the
          // real call and mocktail returns null for a Future<void>, which
          // surfaces as a type error rather than as "your stub is stale".
          svgHeight: any(named: 'svgHeight'),
          annotations: any(named: 'annotations'),
          annotationStatuses: any(named: 'annotationStatuses'),
          // And these two, for the same reason: the document now takes the
          // viewer's palette and its time formatter.
          palette: any(named: 'palette'),
          formatTime: any(named: 'formatTime'),
        ),
      ).thenAnswer((_) async {});

      final mapper = TimeMapper.fitAll(
        startTime: source.startTime,
        endTime: source.endTime,
        viewportWidth: 800,
      );
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: '!', displayName: 'clk'),
        ],
      );
      final signalMap = {'!': _v('clk', '!')};

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
            saveFilePickerProvider.overrideWithValue(_stubSavePicker(fakePath)),
            waveformSourceProvider.overrideWith(
              () => _FakeSourceNotifier(source),
            ),
            signalGroupsProvider.overrideWith(
              () => _FakeSignalGroupsNotifier(group),
            ),
            signalVariablesMapProvider.overrideWithValue(signalMap),
            timeMapperProvider.overrideWith(
              () => _FakeTimeMapperNotifier(mapper),
            ),
            imageExportServiceProvider.overrideWithValue(mockImg),
          ],
        ),
      );

      await tester.tap(find.text('Export'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // dialog entrance
      // Select SVG format (exact localized string from exportDialogFormatSvg).
      await tester.tap(find.text('SVG Vector'));
      await tester.pump();
      await tester.tap(find.text('Export\u2026'));
      await tester.pump();
      await tester.pump(
        const Duration(milliseconds: 300),
      ); // dialog exit + async chain
      await tester.pump(); // snackbar

      verify(
        () => mockImg.exportSvg(
          source: any(named: 'source'),
          signalGroup: any(named: 'signalGroup'),
          signalMap: any(named: 'signalMap'),
          timeMapper: any(named: 'timeMapper'),
          path: fakePath,
          // Sized from the lane count, and carrying the annotation
          // layer. Matched loosely here — the values themselves are asserted
          // in `svg_export_selectors_test.dart`, which is about that decision.
          svgHeight: any(named: 'svgHeight'),
          annotations: any(named: 'annotations'),
          annotationStatuses: any(named: 'annotationStatuses'),
          // And these two, for the same reason: the document now takes the
          // viewer's palette and its time formatter.
          palette: any(named: 'palette'),
          formatTime: any(named: 'formatTime'),
        ),
      ).called(1);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ExportNotifier._buildVcdConfig — time range', () {
    testWidgets('full time range passes source start/end to writeVcd', (
      tester,
    ) async {
      VcdExportConfig? capturedConfig;
      final mockVcd = _MockVcdWriterService();
      when(() => mockVcd.writeVcd(any(), any(), any())).thenAnswer((inv) async {
        capturedConfig = inv.positionalArguments[1] as VcdExportConfig;
      });

      // A zoomed-in mapper — source full range is 0..100, visible is subset.
      const zoomed = TimeMapper(
        startTime: 0,
        endTime: 100,
        viewportWidth: 800,
        ticksPerPixel: 0.05, // visible ~40 ticks
        panOffsetTicks: 30,
      );
      final group = SignalGroup(
        entries: [
          SignalEntry.signal(signalRef: '!', displayName: 'clk'),
        ],
      );
      final signalMap = {'!': _v('clk', '!')};

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
            saveFilePickerProvider.overrideWithValue(
              _stubSavePicker('/tmp/full.vcd'),
            ),
            waveformSourceProvider.overrideWith(
              () => _FakeSourceNotifier(source),
            ),
            signalGroupsProvider.overrideWith(
              () => _FakeSignalGroupsNotifier(group),
            ),
            signalVariablesMapProvider.overrideWithValue(signalMap),
            timeMapperProvider.overrideWith(
              () => _FakeTimeMapperNotifier(zoomed),
            ),
            vcdWriterServiceProvider.overrideWithValue(mockVcd),
          ],
        ),
      );

      await tester.tap(find.text('Export'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // dialog entrance
      // Select Full time range.
      await tester.tap(find.text('Full Simulation'));
      await tester.pump();
      await tester.tap(find.text('Export\u2026'));
      await tester.pump();
      await tester.pump(
        const Duration(milliseconds: 300),
      ); // dialog exit + async chain
      await tester.pump(); // snackbar

      expect(capturedConfig, isNotNull);
      expect(capturedConfig!.startTime, equals(source.startTime));
      expect(capturedConfig!.endTime, equals(source.endTime));
      expect(tester.takeException(), isNull);
    });
  });
}
