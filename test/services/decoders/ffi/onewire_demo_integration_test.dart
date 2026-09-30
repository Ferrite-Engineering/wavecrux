// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_load_status.dart';
import 'package:wavecrux/domain/models/signal_filter.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/decoders/ffi/ffi_decoder_loader.dart';
import 'package:wavecrux/services/decoders/ffi/plugin_directory_resolver.dart';
import 'package:wavecrux/services/waveform/wellen_provider.dart';

import '../../../helpers/wellen_ffi_library_gate.dart';

/// End-to-end round-trip integration test for the WaveCrux user-
/// contributed decoder plugin C ABI.
///
/// Builds the 1-Wire demonstrator plugin at
/// `examples/decoder-plugin-demo/`, loads the resulting shared library
/// through [FfiDecoderLoader], parses the canonical fixture VCD via
/// [WellenProvider], invokes the decoder factory the loader installed
/// in [DecoderRegistry], and asserts the decoder's output matches
/// `examples/decoder-plugin-demo/fixtures/onewire_basic.expected_transactions.json`
/// byte-for-byte (after canonicalisation).
///
/// Skips on hosts without a C toolchain — the demonstrator is built
/// fresh in `setUpAll` to guarantee the integration test follows
/// whatever ABI the open-core repo currently exposes. CI runners
/// without a compiler still pass; the test reports `skipped`.
void main() {
  late Directory pluginRoot;
  late Directory fixtureRoot;
  late String libraryExtension;
  late bool toolchainAvailable;

  setUpAll(() {
    final repoRoot = _findRepoRoot();
    pluginRoot = Directory('${repoRoot.path}/examples/decoder-plugin-demo');
    fixtureRoot = Directory(
      '${repoRoot.path}/test/fixtures/decoder_plugins/onewire',
    );
    libraryExtension = _platformLibraryExtension();
    toolchainAvailable = _ensureDemonstratorBuilt(pluginRoot);
  });

  group('FfiDecoderLoader + 1-Wire demonstrator', () {
    test(
      'loads the plugin and registers the examples.onewire decoder',
      () async {
        if (_skipIfToolchainAbsent(toolchainAvailable)) return;

        final stage = await _stageDemonstrator(pluginRoot, libraryExtension);
        final registry = DecoderRegistry.forTesting();
        final loader = FfiDecoderLoader(
          resolver: _OverrideResolver(directory: stage),
          registry: registry,
        );
        addTearDown(loader.dispose);

        final infos = await loader.scan();

        expect(infos, hasLength(1));
        expect(infos.single.loadStatus, DecoderPluginLoadStatus.loaded);
        expect(infos.single.registeredDecoderIds, ['examples.onewire']);
        expect(registry.isRegistered('examples.onewire'), isTrue);

        final def = registry.getDefinition('examples.onewire')!;
        expect(def.displayName, '1-Wire (demo plugin)');
        expect(def.requiredSignals, hasLength(1));
        expect(def.requiredSignals.single.name, 'dq');
        expect(def.requiredSignals.single.bitWidth, 1);
      },
    );

    if (requireWellenFfiLibrary('1-Wire demonstrator decode')) {
      test(
        'decoded transactions match onewire_basic.expected_transactions.json',
        () async {
          if (_skipIfToolchainAbsent(toolchainAvailable)) return;

          // Stage the demonstrator and load it.
          final stage = await _stageDemonstrator(pluginRoot, libraryExtension);
          final registry = DecoderRegistry.forTesting();
          final loader = FfiDecoderLoader(
            resolver: _OverrideResolver(directory: stage),
            registry: registry,
          );
          addTearDown(loader.dispose);
          await loader.scan();

          // Parse the fixture VCD via the open-core Dart provider — the
          // same parser the host uses on Web. Using the real parser
          // (rather than hand-translated change lists) makes this a true
          // round-trip: any encoding-level discrepancy between the
          // generator and the parser shows up here.
          final source = WellenProvider();
          await source.openFile('${fixtureRoot.path}/onewire_basic.vcd');
          final dq = source
              .findVariables(const SignalFilter())
              .firstWhere((v) => v.name == 'dq');
          await source.loadSignal(dq.signalRef);

          // Build the host's query callbacks against the parser. Logical
          // name `dq` (declared in the manifest) maps to the actual VCD
          // signal path via `config.signalBindings`.
          const bindings = <String, String>{'dq': 'dut.dq'};
          String? query(String logical, int time) {
            final ref = bindings[logical];
            if (ref == null) return null;
            // Parser stored the variable under `dq.signalRef`; the
            // integration test uses the human-readable path key when
            // possible.
            return source.valueAt(dq.signalRef, time);
          }

          List<(int, String)> changesQuery(String logical, int start, int end) {
            if (!bindings.containsKey(logical)) return const <(int, String)>[];
            final list = source.changesInRange(dq.signalRef, start, end);
            return [for (final c in list) (c.time, c.value)];
          }

          // Construct the plugin decoder via the factory the loader
          // installed and run decode() over the file's full time range.
          final factory = registry.getFactory('examples.onewire')!;
          final decoder = factory(
            const DecoderConfig(signalBindings: bindings),
          );
          final txs = decoder.decode(
            source.startTime,
            source.endTime + 1,
            query,
            changesQuery,
            timescale: source.timescale,
          );

          // Compare against the canonical expected JSON byte-for-byte.
          final expectedJsonFile = File(
            '${fixtureRoot.path}/onewire_basic.expected_transactions.json',
          );
          final expected =
              (jsonDecode(expectedJsonFile.readAsStringSync()) as List<dynamic>)
                  .cast<Map<String, dynamic>>();

          expect(
            txs,
            hasLength(expected.length),
            reason:
                'transaction count mismatch — '
                'actual: ${txs.map((t) => t.label).toList()}',
          );
          for (var i = 0; i < txs.length; i++) {
            final e = expected[i];
            expect(
              txs[i].startTime,
              e['startTime'] as int,
              reason: 'tx[$i] startTime',
            );
            expect(
              txs[i].endTime,
              e['endTime'] as int,
              reason: 'tx[$i] endTime',
            );
            expect(txs[i].label, e['label'] as String, reason: 'tx[$i] label');
            expect(
              txs[i].isError,
              e['isError'] as bool,
              reason: 'tx[$i] isError',
            );
            final expFields = (e['fields'] as Map<String, dynamic>).map(
              (k, v) => MapEntry(k, v as String),
            );
            expect(txs[i].fields, expFields, reason: 'tx[$i] fields');
          }
        },
      );
    }

    test('starting the loader with the demonstrator marked disabled '
        'reports it as disabled and never registers it', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;

      final stage = await _stageDemonstrator(pluginRoot, libraryExtension);
      final libraryFile = stage.listSync().whereType<File>().firstWhere(
        (f) => f.path.endsWith('.$libraryExtension'),
      );

      final registry = DecoderRegistry.forTesting();
      final loader = FfiDecoderLoader(
        resolver: _OverrideResolver(directory: stage),
        registry: registry,
        perPluginDisabled: <String, bool>{
          libraryFile.absolute.path: true,
        },
      );
      addTearDown(loader.dispose);

      final infos = await loader.scan();

      expect(infos, hasLength(1));
      expect(infos.single.loadStatus, DecoderPluginLoadStatus.disabled);
      expect(
        registry.isRegistered('examples.onewire'),
        isFalse,
        reason: 'disabled plugin must never be registered',
      );
    });
  });
}

// ── helpers ───────────────────────────────────────────────────────────────

Directory _findRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  throw StateError('cannot find pubspec.yaml from ${Directory.current.path}');
}

String _platformLibraryExtension() {
  if (Platform.isLinux) return 'so';
  if (Platform.isMacOS) return 'dylib';
  if (Platform.isWindows) return 'dll';
  return 'so';
}

PluginHostPlatform _hostPlatformEnum() {
  if (Platform.isLinux) return PluginHostPlatform.linux;
  if (Platform.isMacOS) return PluginHostPlatform.macos;
  if (Platform.isWindows) return PluginHostPlatform.windows;
  return PluginHostPlatform.linux;
}

bool _ensureDemonstratorBuilt(Directory pluginRoot) {
  final ext = _platformLibraryExtension();
  final artifact = File('${pluginRoot.path}/libwavecrux_onewire.$ext');
  if (artifact.existsSync()) return true;

  // Try `make` on Unix-like hosts. Windows requires CMake; integration
  // tests on Windows assume the artifact has been pre-built.
  if (Platform.isWindows) {
    return false;
  }
  final cc = Platform.environment['CC'] ?? 'cc';
  if (_which(cc) == null || _which('make') == null) return false;

  final result = Process.runSync(
    'make',
    const <String>[],
    workingDirectory: pluginRoot.path,
  );
  return result.exitCode == 0;
}

String? _which(String tool) {
  final pathSep = Platform.isWindows ? ';' : ':';
  final extensions = Platform.isWindows
      ? <String>['.exe', '.bat', '.cmd', '']
      : <String>[''];
  for (final dir in (Platform.environment['PATH'] ?? '').split(pathSep)) {
    for (final ext in extensions) {
      final candidate = File('$dir/$tool$ext');
      if (candidate.existsSync()) return candidate.path;
    }
  }
  return null;
}

// Returns true (and marks the test skipped) when no C toolchain is present.
// markTestSkipped() does not abort the test body, so callers must `return`
// on a true result — otherwise _stageDemonstrator throws "demonstrator
// artifact not found" on platforms without a compiler (e.g. a Windows runner
// with cl.exe off PATH).
bool _skipIfToolchainAbsent(bool toolchainAvailable) {
  if (!toolchainAvailable) {
    markTestSkipped(
      'C toolchain unavailable; cannot build the 1-Wire demonstrator',
    );
    return true;
  }
  return false;
}

Future<Directory> _stageDemonstrator(
  Directory pluginRoot,
  String ext,
) async {
  final stage = await Directory.systemTemp.createTemp('wc_onewire_demo_test_');
  addTearDown(() async {
    if (stage.existsSync()) {
      stage.deleteSync(recursive: true);
    }
  });
  final src = File('${pluginRoot.path}/libwavecrux_onewire.$ext');
  if (!src.existsSync()) {
    throw StateError('demonstrator artifact not found at ${src.path}');
  }
  final dst = File('${stage.path}/libwavecrux_onewire.$ext');
  await src.copy(dst.path);
  return stage;
}

class _OverrideResolver extends PluginDirectoryResolver {
  _OverrideResolver({required this.directory})
    : super(
        context: PluginPlatformContext(
          platform: _hostPlatformEnum(),
          appSupportPath: directory.path,
        ),
      );

  final Directory directory;

  @override
  List<Directory> resolveDirectories({
    List<String> userConfigured = const <String>[],
    String? envVarRaw,
    bool Function(String path)? exists,
  }) {
    return <Directory>[directory];
  }
}
