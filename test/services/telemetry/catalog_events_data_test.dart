// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Guards the five catalog events that carry a property, on the real code
/// paths that emit them: `file.opened`, `export.completed`,
/// `session.gtkw_imported`, `decoder.opened`, and `stage.widget_added`.
///
/// Two things are asserted for every event: that it fires from the production
/// seam (no re-implementation of the instrumentation is tested here), and that
/// its property value is drawn from the closed application vocabulary — every
/// value is checked against [_kPropertyValueClass], the class the ingestion
/// Worker enforces. A value outside that class is dropped at the edge, which
/// reads downstream as "nobody used the feature" rather than as an error.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/core/shortcuts/shortcut_action.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/persisted_decoder.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/stage/widgets/boards/nexys_a7_stage_widget.dart';
import 'package:wavecrux/features/stage/widgets/primitives/led_stage_widget.dart';
import 'package:wavecrux/features/viewer/providers/export_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_identity_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/screens/viewer_screen.dart';
import 'package:wavecrux/features/viewer/widgets/gtkw_import_result_dialog.dart';
import 'package:wavecrux/features/viewer/widgets/viewer_toolbar.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/plugins/stage_registry.dart';
import 'package:wavecrux/services/decoders/spi_decoder.dart';
import 'package:wavecrux/services/panes/pane_container_manager.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';
import 'package:wavecrux/services/vcd_writer/vcd_writer_service.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

import '../../helpers/wellen_ffi_library_gate.dart';

// ── recording telemetry ───────────────────────────────────────────────────────

/// Captures every recorded [TelemetryEvent] in memory for assertions.
class _RecordingTelemetryService implements TelemetryService {
  final List<TelemetryEvent> events = [];

  @override
  void record(TelemetryEvent event) {
    events.add(event);
  }

  Iterable<String> get names => events.map((e) => e.name);

  List<TelemetryEvent> named(String name) =>
      events.where((e) => e.name == name).toList();
}

/// The ingestion Worker's property-value class, mirrored here so a value that
/// would be silently dropped at the edge fails the build instead.
final RegExp _kPropertyValueClass = RegExp(r'^[a-z0-9_]{1,64}$');

/// Asserts [event] reports [key] as exactly [expected] *and* that the value is
/// inside the Worker's property-value class — the point of this file.
void _expectProperty(TelemetryEvent event, String key, String expected) {
  final value = event.properties[key];
  expect(value, expected);
  expect(
    value,
    isA<String>().having(
      _kPropertyValueClass.hasMatch,
      'matches the ingestion property-value class',
      isTrue,
    ),
  );
}

/// Asserts exactly one [name] event was recorded and returns it.
TelemetryEvent _single(_RecordingTelemetryService telemetry, String name) {
  final matches = telemetry.named(name);
  expect(matches, hasLength(1), reason: 'recorded: ${telemetry.names}');
  return matches.single;
}

// ── shared fakes ──────────────────────────────────────────────────────────────

class _MockSource extends Mock implements WaveformDataSource {}

class _MockVcdWriterService extends Mock implements VcdWriterService {}

class _FakeWaveformDataSource extends Fake implements WaveformDataSource {}

class _FakeSignalGroup extends Fake implements SignalGroup {}

class _FakeSourceNotifier extends WaveformSourceNotifier {
  _FakeSourceNotifier(this._source);
  final WaveformDataSource? _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
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

/// Stub [OpenFilePicker] resolving to a single-file result at [path].
OpenFilePicker _stubOpenPicker(String path) =>
    ({dialogTitle, type = FileType.any, allowedExtensions}) async =>
        FilePickerResult([
          PlatformFile(name: path.split('/').last, size: 0, path: path),
        ]);

Variable _variable(String name, String ref) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: ref,
  scopePath: 'top',
  bitWidth: 1,
);

// ── file.opened ───────────────────────────────────────────────────────────────

void _fileOpenedTests() {
  const fixture = 'test/fixtures/vcd/scalar_basics.vcd';

  // openFile fires an unawaited off-thread content-hash computation that ends
  // in `ref.read(...)`; disposing the container first throws "Ref after
  // dispose". Poll until the hash lands so it finishes while the container is
  // alive.
  Future<void> settleContentHash(ProviderContainer c) async {
    for (var i = 0; i < 100; i++) {
      if (c.read(waveformIdentityProvider) != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  group('file.opened', () {
    // The macOS security-scoped bookmark service dispatches through
    // SharedPreferences on the real open path.
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test(
      'a real desktop VCD open reports the container format',
      () async {
        final telemetry = _RecordingTelemetryService();
        final container = ProviderContainer(
          overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
        );
        addTearDown(container.dispose);
        final notifier = container.read(waveformSourceProvider.notifier);

        await notifier.openFile(fixture);
        expect(container.read(waveformSourceProvider).value, isNotNull);

        _expectProperty(_single(telemetry, 'file.opened'), 'format', 'vcd');

        await settleContentHash(container);
        await notifier.close();
      },
      skip: !File(fixture).existsSync(),
    );

    test('attachStreamingSource reports the transport, not a format', () {
      final telemetry = _RecordingTelemetryService();
      final container = ProviderContainer(
        overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(waveformSourceProvider.notifier);

      final streaming = _MockSource();
      when(streaming.close).thenReturn(null);
      notifier.attachStreamingSource(streaming);

      expect(container.read(waveformSourceProvider).value, same(streaming));
      _expectProperty(_single(telemetry, 'file.opened'), 'format', 'streaming');
    });
  });
}

// ── export.completed ──────────────────────────────────────────────────────────

Widget _wrapExport(Widget child, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: child),
  ),
);

void _exportCompletedTests() {
  late WellenProvider source;

  setUpAll(() {
    registerFallbackValue(_FakeWaveformDataSource());
    registerFallbackValue(_FakeSignalGroup());
    registerFallbackValue(
      const VcdExportConfig(
        signalRefs: [],
        signalMap: {},
        startTime: 0,
        endTime: 0,
      ),
    );
  });

  // Load the fixture outside FakeAsync so no dart:io handle outlives pump().
  setUp(() async {
    source = WellenProvider();
    await source.openFile('test/fixtures/vcd/scalar_basics.vcd');
  });

  tearDown(() => source.close());

  /// Drives the export dialog through to its default (VCD) writer, with the
  /// save picker resolving to [savePath] — pass null to model a cancel.
  ///
  /// Returns the recorder alongside the save-picker call count, so a test that
  /// asserts "nothing recorded" can also show the flow actually ran.
  Future<({_RecordingTelemetryService telemetry, int pickerCalls})>
  runVcdExport(
    WidgetTester tester, {
    required String? savePath,
  }) async {
    final telemetry = _RecordingTelemetryService();
    var pickerCalls = 0;
    final writer = _MockVcdWriterService();
    when(() => writer.writeVcd(any(), any(), any())).thenAnswer((_) async {});

    final group = SignalGroup(
      entries: [SignalEntry.signal(signalRef: '!', displayName: 'clk')],
    );

    await tester.pumpWidget(
      _wrapExport(
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () =>
                ref.read(exportProvider.notifier).showExportDialog(context),
            child: const Text('Export'),
          ),
        ),
        [
          telemetryServiceProvider.overrideWithValue(telemetry),
          saveFilePickerProvider.overrideWithValue(
            ({
              required dialogTitle,
              required fileName,
              required allowedExtensions,
              required type,
            }) async {
              pickerCalls++;
              return savePath;
            },
          ),
          waveformSourceProvider.overrideWith(
            () => _FakeSourceNotifier(source),
          ),
          signalGroupsProvider.overrideWith(
            () => _FakeSignalGroupsNotifier(group),
          ),
          signalVariablesMapProvider.overrideWithValue({
            '!': _variable('clk', '!'),
          }),
          timeMapperProvider.overrideWith(
            () => _FakeTimeMapperNotifier(
              TimeMapper.fitAll(
                startTime: source.startTime,
                endTime: source.endTime,
                viewportWidth: 800,
              ),
            ),
          ),
          vcdWriterServiceProvider.overrideWithValue(writer),
        ],
      ),
    );

    await tester.tap(find.text('Export'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // dialog entrance
    // VCD is the dialog's default format — confirm straight away.
    await tester.tap(find.text('Export…'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // exit + async chain
    await tester.pump();

    return (telemetry: telemetry, pickerCalls: pickerCalls);
  }

  group('export.completed', () {
    testWidgets('a completed VCD export reports its kind', (tester) async {
      final run = await runVcdExport(tester, savePath: '/tmp/e.vcd');

      _expectProperty(
        _single(run.telemetry, 'export.completed'),
        'kind',
        'vcd',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cancelled save picker records nothing', (tester) async {
      final run = await runVcdExport(tester, savePath: null);

      expect(run.pickerCalls, 1, reason: 'the export flow must have run');
      expect(run.telemetry.named('export.completed'), isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
}

// ── session.gtkw_imported ─────────────────────────────────────────────────────

/// In-memory [WorkspaceService]: production `load()` goes through
/// `path_provider`, which has no test implementation and leaves
/// [WorkspaceNotifier] hung in [AsyncLoading].
class _InMemoryWorkspaceService implements WorkspaceService {
  @override
  Future<Workspace> load() async {
    // The seeded tab carries PaneId.primary; PaneHost filters tabs by pane id,
    // so the workspace must declare a pane with the same id for it to render.
    const pane = WorkspacePane(id: PaneId.primary);
    return Workspace(
      tabs: const [],
      panes: const [pane],
      activePaneId: PaneId.primary,
    );
  }

  @override
  Future<void> save(Workspace workspace) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Hosts [ViewerScreen] in a container with the tab/pane managers initialised,
/// which the screen reads at build time.
class _ViewerHost extends StatefulWidget {
  const _ViewerHost({required this.overrides});

  final List<Override> overrides;

  @override
  State<_ViewerHost> createState() => _ViewerHostState();
}

class _ViewerHostState extends State<_ViewerHost> {
  late final TabContainerManager _tcm;
  late final PaneContainerManager _pcm;
  late final ProviderContainer _container;

  @override
  void initState() {
    super.initState();
    _tcm = TabContainerManager();
    _pcm = PaneContainerManager();
    _container = ProviderContainer(
      overrides: [
        tabContainerManagerProvider.overrideWithValue(_tcm),
        paneContainerManagerProvider.overrideWithValue(_pcm),
        workspaceServiceProvider.overrideWithValue(_InMemoryWorkspaceService()),
        ...widget.overrides,
      ],
    );
    _tcm.init(_container);
    _pcm.init(_container);
    unawaited(_container.wavecruxWorkspace.newTab(displayName: 'New Tab'));
  }

  @override
  void dispose() {
    _tcm.dispose();
    _pcm.dispose();
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: _container,
    child: MaterialApp(
      theme: ThemeData(platform: TargetPlatform.macOS),
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: const ViewerScreen(),
    ),
  );
}

void _gtkwImportedTests() {
  const gtkw = 'test/fixtures/gtkw/generated/simple_signals.gtkw';

  group('session.gtkw_imported', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    testWidgets(
      'a completed GTKWave import records the event with no properties',
      (tester) async {
        final telemetry = _RecordingTelemetryService();
        await tester.pumpWidget(
          _ViewerHost(
            overrides: [
              telemetryServiceProvider.overrideWithValue(telemetry),
              openFilePickerProvider.overrideWithValue(_stubOpenPicker(gtkw)),
            ],
          ),
        );
        await tester.pumpAndSettle();

        // Invoked through the Actions entry the menu, palette and shortcut all
        // share — the picker stub stands in only for the OS dialog. The
        // invocation runs inside runAsync because the import reads the `.gtkw`
        // through `dart:io`, whose completion never arrives under the widget
        // test's fake clock.
        final toolbar = tester.element(find.byType(ViewerToolbar));
        await tester.runAsync(() async {
          Actions.invoke(
            toolbar,
            const ShortcutActionIntent(ShortcutAction.importGtkwSession),
          );
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();

        // The summary dialog is the import's own success signal.
        expect(find.byType(GtkwImportResultDialog), findsOneWidget);
        final event = _single(telemetry, 'session.gtkw_imported');
        expect(event.properties, isEmpty);
      },
      skip: !File(gtkw).existsSync(),
    );
  });
}

// ── decoder.opened ────────────────────────────────────────────────────────────

const _spiConfig = DecoderConfig(
  signalBindings: {'sclk': 'top.sclk', 'mosi': 'top.mosi'},
);

const _pluginDefinition = DecoderDefinition(
  id: 'acme_widgetbus',
  displayName: 'Acme WidgetBus',
  description: 'Runtime-loaded plugin decoder.',
  requiredSignals: [SignalBinding(name: 'clk', description: 'Clock')],
);

class _StubDecoder implements ProtocolDecoder {
  _StubDecoder(this.config);

  final DecoderConfig config;

  @override
  DecoderDefinition get definition => _pluginDefinition;

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery valueAt,
    SignalChangesQuery changesInRange, {
    Timescale? timescale,
  }) => const [];
}

void _decoderOpenedTests() {
  ProviderContainer containerFor(_RecordingTelemetryService telemetry) {
    final container = ProviderContainer(
      overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('decoder.opened', () {
    // The registry is a process-global singleton; clear on both sides so no
    // registration leaks into the rest of the suite.
    setUp(DecoderRegistry.instance.clear);
    tearDown(DecoderRegistry.instance.clear);

    test('a built-in decoder reports its own id', () {
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      final telemetry = _RecordingTelemetryService();
      final container = containerFor(telemetry);

      container
          .read(activeDecodersProvider.notifier)
          .addDecoder(SpiDecoder.decoderDefinition.id, _spiConfig);

      _expectProperty(_single(telemetry, 'decoder.opened'), 'decoder', 'spi');
    });

    test('a user-supplied decoder reports plugin, never its own id', () {
      DecoderRegistry.instance.register(
        _pluginDefinition,
        _StubDecoder.new,
        userSupplied: true,
      );
      final telemetry = _RecordingTelemetryService();
      final container = containerFor(telemetry);

      container
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            _pluginDefinition.id,
            const DecoderConfig(
              signalBindings: {},
            ),
          );

      final event = _single(telemetry, 'decoder.opened');
      _expectProperty(event, 'decoder', 'plugin');
      expect(event.properties.values, isNot(contains(_pluginDefinition.id)));
    });

    test('an unregistered id reports plugin', () {
      final telemetry = _RecordingTelemetryService();
      final container = containerFor(telemetry);

      container
          .read(activeDecodersProvider.notifier)
          .addDecoder(
            'never_registered',
            const DecoderConfig(
              signalBindings: {},
            ),
          );

      _expectProperty(
        _single(telemetry, 'decoder.opened'),
        'decoder',
        'plugin',
      );
    });

    test('restoreDecoders and updateConfig record nothing', () {
      DecoderRegistry.instance.register(
        SpiDecoder.decoderDefinition,
        SpiDecoder.new,
      );
      final telemetry = _RecordingTelemetryService();
      final container = containerFor(telemetry);
      final notifier = container.read(activeDecodersProvider.notifier)
        ..restoreDecoders(const [
          PersistedDecoder(
            decoderId: 'spi',
            instanceNumber: 1,
            config: _spiConfig,
          ),
        ]);

      final restoredId = container.read(activeDecodersProvider).single.id;
      notifier.updateConfig(
        restoredId,
        const DecoderConfig(signalBindings: {'sclk': 'top.other'}),
      );

      expect(telemetry.named('decoder.opened'), isEmpty);
    });
  });
}

// ── stage.widget_added ────────────────────────────────────────────────────────

/// Minimal registrable definition — the family id is the only field the
/// `stage.widget_added` derivation reads.
class _TestStageWidget extends StageWidget {
  const _TestStageWidget(this.id);

  @override
  final String id;

  @override
  String get displayName => id;

  @override
  String get description => 'Test stage widget.';

  @override
  StageWidgetCategory get category => StageWidgetCategory.primitive;

  @override
  List<SignalBinding> get requiredSignals => const [];
}

void _stageWidgetAddedTests() {
  // A workspace with one panel selected — addInstance returns null and records
  // nothing when there is no active panel.
  StageWorkspaceNotifier workspaceFor(_RecordingTelemetryService telemetry) {
    final container = ProviderContainer(
      overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
    );
    addTearDown(container.dispose);
    return container.read(stageWorkspaceProvider.notifier)..addPanel('Panel 1');
  }

  group('stage.widget_added', () {
    // The registry is a process-global singleton; clear on both sides so no
    // registration leaks into the rest of the suite.
    setUp(StageRegistry.instance.clear);
    tearDown(StageRegistry.instance.clear);

    test('a built-in family id is reported verbatim', () {
      StageRegistry.instance.register(const LedStageWidget());
      final telemetry = _RecordingTelemetryService();

      workspaceFor(telemetry).addInstance(LedStageWidget.widgetId);

      _expectProperty(
        _single(telemetry, 'stage.widget_added'),
        'widget',
        'led',
      );
    });

    test('a namespaced Pro family id is reported as its last segment', () {
      const proId = 'wavecrux.pro.dsp_eye';
      StageRegistry.instance.register(const _TestStageWidget(proId));
      final telemetry = _RecordingTelemetryService();

      workspaceFor(telemetry).addInstance(proId);

      _expectProperty(
        _single(telemetry, 'stage.widget_added'),
        'widget',
        'dsp_eye',
      );
    });

    test('a camelCase board id is lowercased', () {
      StageRegistry.instance.register(const NexysA7StageWidget());
      final telemetry = _RecordingTelemetryService();

      workspaceFor(telemetry).addInstance(NexysA7StageWidget.widgetId);

      _expectProperty(
        _single(telemetry, 'stage.widget_added'),
        'widget',
        'nexysa7',
      );
    });

    test('a user-supplied bundle reports custom, never its own id', () {
      const bundleId = 'com.acme.stage.oscilloscope';
      StageRegistry.instance.register(
        const _TestStageWidget(bundleId),
        userSupplied: true,
      );
      final telemetry = _RecordingTelemetryService();

      workspaceFor(telemetry).addInstance(bundleId);

      final event = _single(telemetry, 'stage.widget_added');
      _expectProperty(event, 'widget', 'custom');
      expect(event.properties.values, isNot(contains('oscilloscope')));
    });

    test('addInstanceAt records nothing', () {
      StageRegistry.instance.register(const LedStageWidget());
      final telemetry = _RecordingTelemetryService();

      final id = workspaceFor(telemetry).addInstanceAt(
        LedStageWidget.widgetId,
        x: 10,
        y: 20,
      );

      expect(id, isNotNull, reason: 'the instance must actually be added');
      expect(telemetry.named('stage.widget_added'), isEmpty);
    });
  });
}

// ── entry point ───────────────────────────────────────────────────────────────

void main() {
  if (!requireWellenFfiLibrary('catalog events data')) return;

  TestWidgetsFlutterBinding.ensureInitialized();

  _fileOpenedTests();
  _exportCompletedTests();
  _gtkwImportedTests();
  _decoderOpenedTests();
  _stageWidgetAddedTests();
}
