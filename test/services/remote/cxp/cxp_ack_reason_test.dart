// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_io/crux_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/enums/scope_type.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/domain/models/scope.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/services/remote/cxp/cxp_inbound_handlers.dart';
import 'package:wavecrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:wavecrux/services/settings/settings_service.dart';
import 'package:wavecrux/services/tabs/tab_container_manager.dart';

import '../../../helpers/fake_waveform_data_source.dart';
import '../../../helpers/in_memory_workspace_service.dart';
import '../../../helpers/platform_absolute_path.dart';
import '../../../helpers/product_telemetry_config.dart';

/// CXP 1.3 section 9.11 and conformance item 22: the `reason` of a refusal
/// names the kind of refusal and nothing the sender supplied. Every refusal
/// path of WaveCrux's request handlers is driven here with a request whose
/// path, design id, file name and kind name are unmistakable, and the reason
/// is searched for each of them.
///
/// MUTATION: interpolating a path, a design id, an element or artifact kind,
/// or an exception into any reason in `cxp_inbound_handlers.dart` turns the
/// matching case red.
const String _editorCommand = 'zqeditor -g';

class _FakeSettingsService implements WaveCruxSettingsService {
  const _FakeSettingsService(this._settings);
  final AppSettings _settings;
  @override
  Future<AppSettings> load() async => _settings;
  @override
  Future<void> save(AppSettings settings) async {}
}

class _PreloadedSourceNotifier extends WaveformSourceNotifier {
  _PreloadedSourceNotifier(this._source);
  final FakeWaveformDataSource _source;
  @override
  AsyncValue<FakeWaveformDataSource> build() => AsyncData(_source);
}

final Provider<Ref> _refProvider = Provider<Ref>((ref) => ref);

/// A per-tab source notifier whose reader fails, with the path in the error.
class _FailingOpenNotifier extends WaveformSourceNotifier {
  @override
  AsyncValue<WaveformDataSource?> build() =>
      const AsyncData<WaveformDataSource?>(null);

  @override
  Future<void> openFile(String path, {bool preserveDecoders = false}) async {
    currentFilePath = path;
    state = AsyncError<WaveformDataSource?>(
      FormatException('cannot parse $path'),
      StackTrace.current,
    );
  }
}

/// The sentinel segments of [value] read as a path in either separator style:
/// the ones this test minted, which start with `zq`.
Iterable<String> _segments(String value) =>
    value.split(RegExp(r'[/\\]')).where((s) => s.startsWith('zq'));

/// Fails when [result] is not a refusal or when its reason contains any of
/// [sent], whole or by path segment.
void _expectNothingEchoed(CruxCxpHandlerResult result, List<String> sent) {
  expect(result.honored, isFalse);
  final reason = result.reason;
  expect(reason, isNotNull);
  expect(reason, isNotEmpty);
  for (final value in sent) {
    expect(reason, isNot(contains(value)), reason: 'echoes "$value"');
    for (final segment in _segments(value)) {
      expect(reason, isNot(contains(segment)), reason: 'echoes "$segment"');
    }
  }
}

void main() {
  late Directory records;
  late List<ProviderContainer> containers;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    records = await Directory.systemTemp.createTemp('zqwavecrux_reason_ws_');
    containers = <ProviderContainer>[];
  });

  tearDown(() async {
    for (final c in containers) {
      c.dispose();
    }
    if (records.existsSync()) await records.delete(recursive: true);
  });

  /// A root container with WaveCrux's handlers' collaborators faked: a loaded
  /// waveform when [withWaveform], an editor command when [withEditor], and
  /// `/zqrtl` as the one directory the user has open.
  Future<Ref> makeRef({
    bool withWaveform = true,
    bool withEditor = true,
  }) async {
    final overrides = <Override>[
      productTelemetryConfig,
      cxpPathContainmentProvider.overrideWithValue(
        CxpPathContainment(roots: () => <String>[platformAbsolute('/zqrtl')]),
      ),
      cxpWorkspaceStoreProvider.overrideWithValue(
        CxpWorkspaceStore(workspaceDirectory: records.path),
      ),
      settingsServiceProvider.overrideWithValue(
        _FakeSettingsService(
          AppSettings(cxpEditorCommand: withEditor ? _editorCommand : ''),
        ),
      ),
      if (withWaveform)
        waveformSourceProvider.overrideWith(
          () => _PreloadedSourceNotifier(
            FakeWaveformDataSource(
              scopes: const <Scope>[
                Scope(
                  name: 'zqtop',
                  path: 'zqtop',
                  type: ScopeType.module,
                  variables: <Variable>[
                    Variable(
                      name: 'zqclk',
                      varType: VarType.wire,
                      direction: VarDirection.input,
                      signalRef: 'zqtop.zqclk',
                      scopePath: 'zqtop',
                      bitWidth: 1,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ];
    final container = ProviderContainer(overrides: overrides);
    containers.add(container);
    await container.read(appSettingsProvider.future);
    final ref = container.read(_refProvider);
    return ref;
  }

  group('request_highlight refusals', () {
    test('a signal-like element that is not in the open waveform', () async {
      final ref = await makeRef();
      for (final kind in <ElementKind>[
        ElementKind.signal,
        ElementKind.instance,
        ElementKind.net,
        ElementKind.port,
      ]) {
        const path = 'zqtop.zqsub.zqsig_missing';
        final result = await dispatchCxpHighlight(
          ref,
          ElementId(kind: kind, path: path),
        );
        _expectNothingEchoed(result, <String>[path]);
      }
    });

    test('a signal-like element when no waveform is open', () async {
      final ref = await makeRef(withWaveform: false);
      const path = 'zqtop.zqsig';
      final result = await dispatchCxpHighlight(
        ref,
        const ElementId(kind: ElementKind.signal, path: path),
      );
      _expectNothingEchoed(result, <String>[path]);
    });

    test('a signal-like element whose design id names no waveform', () async {
      final ref = await makeRef();
      const path = 'zqtop.zqsub.zqsig_missing';
      const designId = 'zqdesign-id-0123456789abcdef';
      final result = await dispatchCxpHighlight(
        ref,
        const ElementId(kind: ElementKind.signal, path: path),
        <String, Object?>{cxpDesignIdMetadataKey: designId},
      );
      _expectNothingEchoed(result, <String>[path, designId]);
    });

    test('a scope that is not in the open waveform', () async {
      final ref = await makeRef();
      const path = 'zqscope.zqsub';
      final result = await dispatchCxpHighlight(
        ref,
        const ElementId(kind: ElementKind.scope, path: path),
      );
      _expectNothingEchoed(result, <String>[path]);
    });

    test('a scope when no waveform is open', () async {
      final ref = await makeRef(withWaveform: false);
      const path = 'zqscope.zqsub';
      final result = await dispatchCxpHighlight(
        ref,
        const ElementId(kind: ElementKind.scope, path: path),
      );
      _expectNothingEchoed(result, <String>[path]);
    });

    test('a marker that is malformed and a marker that is not set', () async {
      final ref = await makeRef();
      for (final path in <String>['zqmarker_name', 'z']) {
        final result = await dispatchCxpHighlight(
          ref,
          ElementId(kind: ElementKind.marker, path: path),
        );
        _expectNothingEchoed(result, <String>[path]);
      }
    });

    test(
      'a kind WaveCrux does not handle and a kind it never heard of',
      () async {
        final ref = await makeRef();
        const path = 'zqrule/zqpath.v:3';
        for (final kind in <ElementKind>[
          ElementKind.rule,
          ElementKind.test,
          ElementKind.breakpoint,
          ElementKind('zqkind_unheard'),
        ]) {
          final result = await dispatchCxpHighlight(
            ref,
            ElementId(kind: kind, path: path),
          );
          _expectNothingEchoed(result, <String>[path, 'zqkind_unheard']);
        }
      },
    );

    test('a source citation that is not a waveform', () async {
      final ref = await makeRef();
      final path = platformAbsolute('/zqrtl/zqalu.v:42:1');
      final result = await dispatchCxpHighlight(
        ref,
        ElementId(kind: ElementKind.source, path: path),
      );
      _expectNothingEchoed(result, <String>[path]);
    });

    test('a waveform path that is not absolute', () async {
      final ref = await makeRef();
      const path = 'zqwaves/zqrun.vcd';
      final result = await dispatchCxpHighlight(
        ref,
        const ElementId(kind: ElementKind.source, path: path),
      );
      _expectNothingEchoed(result, <String>[path]);
    });
  });

  group('request_open_artifact refusals', () {
    test('a kind WaveCrux does not open', () async {
      final ref = await makeRef();
      const designId = 'zqdesign-kind-0123456789abcdef';
      const kind = 'zqkind_artifact';
      final hint = platformAbsolute('/zqdir/zqrun.vcd');
      final result = await dispatchCxpOpenArtifact(ref, designId, kind, hint);
      _expectNothingEchoed(result, <String>[designId, kind, hint]);
    });

    test('a design with no recorded waveform and no hint', () async {
      final ref = await makeRef();
      const designId = 'zqdesign-unrecorded-0123456789';
      final result = await dispatchCxpOpenArtifact(
        ref,
        designId,
        kCxpWaveformArtifactKind,
        null,
      );
      _expectNothingEchoed(result, <String>[designId]);
    });

    test('a hint that is not an absolute path', () async {
      final ref = await makeRef();
      const designId = 'zqdesign-relative-0123456789a';
      const hint = 'zqrelative/zqrun.vcd';
      final result = await dispatchCxpOpenArtifact(
        ref,
        designId,
        kCxpWaveformArtifactKind,
        hint,
      );
      _expectNothingEchoed(result, <String>[designId, hint]);
    });

    test('a hint that names no file here', () async {
      final ref = await makeRef();
      const designId = 'zqdesign-missing-0123456789ab';
      final hint = platformAbsolute('/zqnowhere/zqdir/zqrun.vcd');
      final result = await dispatchCxpOpenArtifact(
        ref,
        designId,
        kCxpWaveformArtifactKind,
        hint,
      );
      _expectNothingEchoed(result, <String>[designId, hint]);
    });
  });

  group('a waveform that fails to open', () {
    /// Runs [body] against a root container whose tabs open nothing: the
    /// reader raises an error that names the path it was given, the way a
    /// real parse failure does.
    Future<CruxCxpHandlerResult> failingOpen(
      WidgetTester tester,
      Future<CruxCxpHandlerResult> Function(Ref ref) body,
    ) async {
      final tcm = TabContainerManager(
        extraTabOverrides: <Override>[
          waveformSourceProvider.overrideWith(_FailingOpenNotifier.new),
        ],
      );
      final root = ProviderContainer(
        overrides: <Override>[
          productTelemetryConfig,
          ...testWorkspaceOverrides(),
          tabContainerManagerProvider.overrideWithValue(tcm),
        ],
      );
      tcm.init(root);
      addTearDown(() {
        tcm.dispose();
        root.dispose();
      });
      final result = await tester.runAsync(() async {
        final result = await body(root.read(_refProvider));
        await root.wavecruxWorkspace.flushPendingSave();
        return result;
      });
      return result!;
    }

    testWidgets('a source highlight naming a waveform', (tester) async {
      final path = platformAbsolute('/zqwaves/zqdir/zqrun.vcd');
      final result = await failingOpen(
        tester,
        (ref) => dispatchCxpHighlight(
          ref,
          ElementId(kind: ElementKind.source, path: path),
        ),
      );
      _expectNothingEchoed(result, <String>[path]);
    });

    testWidgets('an artifact open naming a waveform', (tester) async {
      final dir = Directory.systemTemp.createTempSync('zqwavecrux_reason_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/zqrun.vcd')..writeAsStringSync('zqjunk\n');
      const designId = 'zqdesign-broken-0123456789abc';
      final result = await failingOpen(
        tester,
        (ref) => dispatchCxpOpenArtifact(
          ref,
          designId,
          kCxpWaveformArtifactKind,
          file.path,
        ),
      );
      _expectNothingEchoed(result, <String>[designId, file.path]);
    });
  });

  group('request_open_source refusals', () {
    test('no editor command configured', () async {
      final ref = await makeRef(withEditor: false);
      final file = platformAbsolute('/zqrtl/zqdir/zqalu.sv');
      final result = await dispatchCxpOpenSource(ref, file, 3, 1);
      _expectNothingEchoed(result, <String>[file]);
    });

    test('a file outside the directories the user has opened', () async {
      final ref = await makeRef();
      final file = platformAbsolute('/zqoutside/zqdir/zqpasswd.sv');
      final result = await dispatchCxpOpenSource(ref, file, 3, 1);
      _expectNothingEchoed(result, <String>[file]);
    });

    test('a file that is not an absolute path', () async {
      final ref = await makeRef();
      const file = 'zqrelative/zqalu.sv';
      final result = await dispatchCxpOpenSource(ref, file, 3, 1);
      _expectNothingEchoed(result, <String>[file]);
    });
  });

  group('the editor command runner', () {
    const host = SpawnHost(windows: false);
    final target = platformAbsolute('/zqrtl/zqdir/zqalu.sv:3:1');

    test('an empty command', () async {
      final result = await runEditorCommand('   ', target, host: host);
      _expectNothingEchoed(result, <String>[target]);
    });

    test('an editor that exits non-zero', () async {
      final result = await runEditorCommand(
        _editorCommand,
        target,
        host: host,
        run: (executable, arguments) async =>
            ProcessResult(0, 7, 'zqstdout', 'zqstderr'),
      );
      _expectNothingEchoed(result, <String>[target, 'zqeditor']);
    });

    test('an editor that cannot be started', () async {
      final result = await runEditorCommand(
        _editorCommand,
        target,
        host: host,
        run: (executable, arguments) async => throw ProcessException(
          executable,
          arguments,
          'No such file: $target',
        ),
      );
      _expectNothingEchoed(result, <String>[target, 'zqeditor']);
    });

    test('an editor that fails in any other way', () async {
      final result = await runEditorCommand(
        _editorCommand,
        target,
        host: host,
        run: (executable, arguments) async =>
            throw StateError('failed on $target via zqeditor'),
      );
      _expectNothingEchoed(result, <String>[target, 'zqeditor']);
    });
  });
}
