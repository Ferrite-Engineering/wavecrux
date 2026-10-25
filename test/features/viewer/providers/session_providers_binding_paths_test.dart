// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Decoder and Stage bindings survive a regenerated dump (#54).
//
// A binding holds a backend-local signal ref, and wellen numbers refs by
// declaration order: add one signal to the testbench and every ref after it
// moves. These tests drive the real SessionNotifier against real VCDs through
// the wellen FFI backend, rewriting the dump between steps the way a re-run
// simulation does, and check that bindings follow their hierarchical paths.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_panel_config.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_workspace_state.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/domain/models/workspace.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/stage/providers/stage_workspace_provider.dart';
import 'package:wavecrux/features/tabs/providers/tab_providers.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/providers/unresolved_bindings_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/workspace/providers/recent_files_provider.dart';
import 'package:wavecrux/features/workspace/providers/workspace_provider.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/session/binding_paths.dart';

import '../../../helpers/product_telemetry_config.dart';
import '../../../helpers/wellen_ffi_library_gate.dart';

const _definition = DecoderDefinition(
  id: 'path_stub',
  displayName: 'Path Stub',
  description: 'Binds two signals and decodes nothing',
  requiredSignals: [
    SignalBinding(name: 'clk', description: 'clock'),
    SignalBinding(name: 'data', description: 'data'),
  ],
);

class _StubDecoder implements ProtocolDecoder {
  const _StubDecoder();

  @override
  DecoderDefinition get definition => _definition;

  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) => const [];
}

class _FakeRecentFiles extends RecentFilesNotifier {
  @override
  Future<List<String>> build() async => [];

  @override
  Future<void> addFile(String path) async {}
}

class _FakeWorkspaceService extends Fake implements WorkspaceService {
  @override
  Future<String?> sidecarPathFor(
    String tabId, {
    String extension = '.json',
  }) async => null;
}

/// A VCD whose `top` scope declares [names] in order, each 1 bit wide.
String _vcd(List<String> names) {
  const codes = r'!"#$%&';
  final decls = [
    for (var i = 0; i < names.length; i++)
      '\$var wire 1 ${codes[i]} ${names[i]} \$end',
  ].join('\n');
  final zeros = [for (var i = 0; i < names.length; i++) '0${codes[i]}'];
  return '''
\$timescale 1 ns \$end
\$scope module top \$end
$decls
\$upscope \$end
\$enddefinitions \$end
#0
${zeros.join('\n')}
#10
''';
}

void main() {
  if (!requireWellenFfiLibrary('session binding paths')) return;

  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String vcdPath;
  late String sessionPath;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('wavecrux_bindpaths_');
    vcdPath = p.join(dir.path, 'tb.vcd');
    sessionPath = p.join(dir.path, 'tb.wavecrux');
    DecoderRegistry.instance.register(
      _definition,
      (_) => const _StubDecoder(),
    );
  });

  tearDown(() async {
    DecoderRegistry.instance.clear();
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  });

  ProviderContainer container() {
    final c =
        ProviderContainer(
            overrides: <Override>[
              productTelemetryConfig,
              recentFilesProvider.overrideWith(_FakeRecentFiles.new),
              tabIdProvider.overrideWithValue(TabId.generate()),
              workspaceServiceProvider.overrideWithValue(
                _FakeWorkspaceService(),
              ),
            ],
          )
          ..listen(waveformSourceProvider, (_, _) {})
          ..listen(activeDecodersProvider, (_, _) {})
          ..listen(stageWorkspaceProvider, (_, _) {})
          ..listen(unresolvedBindingsProvider, (_, _) {});
    addTearDown(() {
      c.read(waveformSourceProvider).value?.close();
      c.dispose();
    });
    return c;
  }

  String refOf(ProviderContainer c, String name) => c
      .read(waveformSourceProvider)
      .value!
      .findVariables(const SignalFilter())
      .singleWhere((v) => v.name == name)
      .signalRef;

  /// Opens the dump, binds the stub decoder to clk + data and a Stage pin to
  /// valid, and saves the session.
  Future<void> bindAndSave(ProviderContainer c) async {
    await c.read(waveformSourceProvider.notifier).openFile(vcdPath);
    c
        .read(activeDecodersProvider.notifier)
        .addDecoder(
          'path_stub',
          DecoderConfig(
            signalBindings: {'clk': refOf(c, 'clk'), 'data': refOf(c, 'data')},
          ),
        );
    c
        .read(stageWorkspaceProvider.notifier)
        .restoreFromSession(
          StageWorkspaceState(
            activePanelId: 'p',
            panels: [
              StagePanelConfig(
                id: 'p',
                name: 'P',
                instances: [
                  StageInstance(
                    id: 'i',
                    widgetId: 'rvfi_inspector',
                    signalBindings: {
                      'valid': StageSignalBinding(signalRef: refOf(c, 'valid')),
                    },
                  ),
                ],
              ),
            ],
          ),
        );
    await c.read(sessionProvider.notifier).saveToPath(sessionPath);
  }

  Map<String, String> decoderBindings(ProviderContainer c) =>
      c.read(activeDecodersProvider).single.config.signalBindings;

  StageSignalBinding stageBinding(ProviderContainer c) => c
      .read(stageWorkspaceProvider)
      .panels
      .single
      .instances
      .single
      .signalBindings['valid']!;

  test("save writes each binding's path beside its ref", () async {
    await File(vcdPath).writeAsString(_vcd(['clk', 'data', 'valid']));
    await bindAndSave(container());

    final doc =
        jsonDecode(await File(sessionPath).readAsString())
            as Map<String, dynamic>;
    final config =
        ((doc['decoders'] as List).single as Map)['config']
            as Map<String, dynamic>;
    expect(config['bindingPaths'], {'clk': 'top.clk', 'data': 'top.data'});
    final instance =
        (((doc['stage'] as Map)['panels'] as List).single as Map)['instances']
            as List;
    expect(
      ((instance.single as Map)['bindings'] as Map)['valid'],
      containsPair('path', 'top.valid'),
    );
  });

  test('load re-resolves bindings when the dump renumbered its refs', () async {
    await File(vcdPath).writeAsString(_vcd(['clk', 'data', 'valid']));
    await bindAndSave(container());

    // The testbench grows two signals ahead of the bound ones; every ref moves.
    await File(
      vcdPath,
    ).writeAsString(_vcd(['rst', 'irq', 'clk', 'data', 'valid']));

    final c = container();
    await c.read(sessionProvider.notifier).loadFromPath(sessionPath);

    expect(decoderBindings(c), {
      'clk': refOf(c, 'clk'),
      'data': refOf(c, 'data'),
    });
    expect(stageBinding(c).signalRef, refOf(c, 'valid'));
    expect(c.read(unresolvedBindingsProvider), isEmpty);
    // Precondition: the refs really did move, or this proves nothing.
    expect(refOf(c, 'clk'), isNot('0'));
  });

  test('a binding whose path is gone is emptied, kept and reported', () async {
    await File(vcdPath).writeAsString(_vcd(['clk', 'data', 'valid']));
    await bindAndSave(container());

    await File(vcdPath).writeAsString(_vcd(['clk', 'valid']));

    final c = container();
    await c.read(sessionProvider.notifier).loadFromPath(sessionPath);

    expect(decoderBindings(c)['clk'], refOf(c, 'clk'));
    expect(decoderBindings(c)['data'], '');
    expect(stageBinding(c).signalRef, refOf(c, 'valid'));
    expect(c.read(unresolvedBindingsProvider), const [
      UnresolvedBinding(owner: 'path_stub #1', slot: 'data', path: 'top.data'),
    ]);

    // Saving again keeps the missing path, so the binding comes back once
    // the signal does.
    await c.read(sessionProvider.notifier).saveToPath(sessionPath);
    await File(vcdPath).writeAsString(_vcd(['valid', 'data', 'clk']));
    final again = container();
    await again.read(sessionProvider.notifier).loadFromPath(sessionPath);
    expect(decoderBindings(again), {
      'clk': refOf(again, 'clk'),
      'data': refOf(again, 'data'),
    });
    expect(again.read(unresolvedBindingsProvider), isEmpty);
  });

  test('reload re-points live bindings at the regenerated dump', () async {
    await File(vcdPath).writeAsString(_vcd(['clk', 'data', 'valid']));
    final c = container();
    await bindAndSave(c);

    await File(vcdPath).writeAsString(_vcd(['valid', 'rst', 'data', 'clk']));
    await c.read(sessionProvider.notifier).reloadCurrentFile();

    expect(decoderBindings(c), {
      'clk': refOf(c, 'clk'),
      'data': refOf(c, 'data'),
    });
    expect(stageBinding(c).signalRef, refOf(c, 'valid'));
    expect(c.read(unresolvedBindingsProvider), isEmpty);
  });

  test('reload reports a binding the regenerated dump dropped', () async {
    await File(vcdPath).writeAsString(_vcd(['clk', 'data', 'valid']));
    final c = container();
    await bindAndSave(c);

    await File(vcdPath).writeAsString(_vcd(['data', 'clk']));
    await c.read(sessionProvider.notifier).reloadCurrentFile();

    expect(stageBinding(c).signalRef, '');
    expect(stageBinding(c).signalPath, 'top.valid');
    expect(c.read(unresolvedBindingsProvider).single.path, 'top.valid');

    // Opening another file retires the notice.
    await c.read(waveformSourceProvider.notifier).openFile(vcdPath);
    expect(c.read(unresolvedBindingsProvider), isEmpty);
  });

  test('a session saved before paths existed still loads by ref', () async {
    await File(vcdPath).writeAsString(_vcd(['clk', 'data', 'valid']));
    // The refs a pre-1.1.1 build would have written for this dump.
    final probe = container();
    await probe.read(waveformSourceProvider.notifier).openFile(vcdPath);
    final clk = refOf(probe, 'clk');
    final data = refOf(probe, 'data');
    final valid = refOf(probe, 'valid');
    await File(sessionPath).writeAsString(
      jsonEncode({
        'version': 4,
        'sourceFilePath': 'tb.vcd',
        'decoders': [
          {
            'decoderId': 'path_stub',
            'instanceNumber': 1,
            'config': {
              'bindings': {'clk': clk, 'data': data},
            },
          },
        ],
        'stage': {
          'panels': [
            {
              'id': 'p',
              'name': 'P',
              'instances': [
                {
                  'id': 'i',
                  'widgetId': 'rvfi_inspector',
                  'bindings': {
                    'valid': {'ref': valid},
                  },
                },
              ],
            },
          ],
        },
      }),
    );

    final c = container();
    await c.read(sessionProvider.notifier).loadFromPath(sessionPath);

    expect(decoderBindings(c), {'clk': clk, 'data': data});
    expect(stageBinding(c).signalRef, valid);
    expect(c.read(unresolvedBindingsProvider), isEmpty);

    // The next save upgrades it: paths are recorded from the refs.
    await c.read(sessionProvider.notifier).saveToPath(sessionPath);
    final saved =
        jsonDecode(await File(sessionPath).readAsString())
            as Map<String, dynamic>;
    final config = ((saved['decoders'] as List).single as Map)['config'] as Map;
    expect(config['bindingPaths'], {'clk': 'top.clk', 'data': 'top.data'});
  });
}
