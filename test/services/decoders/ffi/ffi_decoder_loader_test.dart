// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/decoder_category.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/interfaces/protocol_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_load_status.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/decoders/ffi/ffi_decoder_loader.dart';
import 'package:wavecrux/services/decoders/ffi/plugin_directory_resolver.dart';

const _fixtureSubdirs = <String, String>{
  'passthrough': 'test_plugin',
  'abi_mismatch': 'test_plugin_abi_mismatch',
  'missing_symbol': 'test_plugin_missing_symbol',
  'corrupt_manifest': 'test_plugin_corrupt_manifest',
  'named': 'test_plugin_named',
  'config': 'test_plugin_config',
  'lifecycle': 'test_plugin_lifecycle',
};

const _libraryBasenames = <String, String>{
  'passthrough': 'test_passthrough',
  'abi_mismatch': 'test_abi_mismatch',
  'missing_symbol': 'test_missing_symbol',
  'corrupt_manifest': 'test_corrupt_manifest',
  'named': 'test_named',
  'config': 'test_config',
  'lifecycle': 'test_lifecycle',
};

void main() {
  late Directory pluginRoot;
  late String fixtureExtension;
  late bool toolchainAvailable;

  setUpAll(() {
    final repoRoot = _findRepoRoot();
    pluginRoot = Directory(
      '${repoRoot.path}/test/fixtures/decoder_plugins',
    );
    fixtureExtension = _platformLibraryExtension();
    toolchainAvailable = _ensureToolchainAndBuild(pluginRoot);
  });

  group('FfiDecoderLoader', () {
    test('loads a well-formed plugin and registers its decoder', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;

      final dir = await _stageDirectory(
        sources: {'passthrough': pluginRoot},
        ext: fixtureExtension,
      );
      final registry = DecoderRegistry.forTesting();
      final loader = FfiDecoderLoader(
        resolver: _resolverFor(dir),
        registry: registry,
      );
      addTearDown(loader.dispose);

      final infos = await loader.scan();

      expect(infos, hasLength(1));
      expect(infos.single.loadStatus, DecoderPluginLoadStatus.loaded);
      expect(infos.single.registeredDecoderIds, ['test_passthrough']);
      expect(infos.single.declaredAbiMajor, 1);
      // This fixture exports no ABI 1.1 self-identification symbols, so
      // the plugin name falls back to its first decoder's display name
      // and the description stays null.
      expect(infos.single.displayName, 'Test Passthrough');
      expect(infos.single.pluginDescription, isNull);
      expect(registry.isRegistered('test_passthrough'), isTrue);

      final def = registry.getDefinition('test_passthrough')!;
      expect(def.displayName, 'Test Passthrough');
      expect(def.category, DecoderCategory.userPlugin);
      expect(def.requiredTier, LicenseTier.openCore);
      expect(def.requiredSignals, hasLength(1));
      expect(def.requiredSignals.single.name, 'data');
    });

    test('uses the ABI 1.1 plugin name/description when the plugin '
        'exports them', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;

      final dir = await _stageDirectory(
        sources: {'named': pluginRoot},
        ext: fixtureExtension,
      );
      final registry = DecoderRegistry.forTesting();
      final loader = FfiDecoderLoader(
        resolver: _resolverFor(dir),
        registry: registry,
      );
      addTearDown(loader.dispose);

      final infos = await loader.scan();

      expect(infos, hasLength(1));
      expect(infos.single.loadStatus, DecoderPluginLoadStatus.loaded);
      expect(infos.single.registeredDecoderIds, ['named.demo']);
      // The plugin self-identifies, so its card name comes from
      // wavecrux_decoder_plugin_name — not the first decoder's name
      // ('Named Demo').
      expect(infos.single.displayName, 'Example Plugin Suite');
      expect(
        infos.single.pluginDescription,
        'Fixture plugin exercising ABI 1.1 self-identification.',
      );
    });

    test('create receives decoder_id, bindings and parameter values under '
        'both parameters and options', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;

      final dir = await _stageDirectory(
        sources: {'config': pluginRoot},
        ext: fixtureExtension,
      );
      final registry = DecoderRegistry.forTesting();
      final loader = FfiDecoderLoader(
        resolver: _resolverFor(dir),
        registry: registry,
      );
      addTearDown(loader.dispose);

      final infos = await loader.scan();
      expect(infos.single.loadStatus, DecoderPluginLoadStatus.loaded);

      final decoder = registry.getFactory('test_config_contract')!(
        const DecoderConfig(
          signalBindings: {'data': 'top.dq'},
          parameters: {'baudrate': 115200},
        ),
      );
      final transactions = decoder.decode(
        0,
        100,
        (name, time) => '1',
        (name, start, end) => const <(int, String)>[(0, '1')],
      );

      // The fixture's create() returns NULL without its decoder_id, and
      // a NULL handle yields no transactions at all.
      expect(transactions, hasLength(1));
      final fields = transactions.single.fields;
      expect(fields['decoder_id'], 'test_config_contract');
      expect(fields['signal_bindings'], '{data: top.dq}');
      expect(fields['parameters'], '{baudrate: 115200}');
      expect(fields['options'], '{baudrate: 115200}');
    });

    test('enum_labels loads as an object keyed by value or as an array in '
        'enum_values order', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;

      final dir = await _stageDirectory(
        sources: {'config': pluginRoot},
        ext: fixtureExtension,
      );
      final registry = DecoderRegistry.forTesting();
      final loader = FfiDecoderLoader(
        resolver: _resolverFor(dir),
        registry: registry,
      );
      addTearDown(loader.dispose);

      final infos = await loader.scan();
      expect(infos.single.loadStatus, DecoderPluginLoadStatus.loaded);

      final params = {
        for (final p
            in registry.getDefinition('test_config_contract')!.parameters)
          p.name: p,
      };
      expect(params['parity']!.enumLabels, {'n': 'None', 'e': 'Even'});
      expect(params['direction']!.enumLabels, {
        'tx': 'Downstream',
        'rx': 'Upstream',
      });
    });

    test('reports abiMismatch and does not register the decoder', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;

      final dir = await _stageDirectory(
        sources: {'abi_mismatch': pluginRoot},
        ext: fixtureExtension,
      );
      final registry = DecoderRegistry.forTesting();
      final loader = FfiDecoderLoader(
        resolver: _resolverFor(dir),
        registry: registry,
      );
      addTearDown(loader.dispose);

      final infos = await loader.scan();

      expect(infos, hasLength(1));
      expect(infos.single.loadStatus, DecoderPluginLoadStatus.abiMismatch);
      expect(infos.single.declaredAbiMajor, 99);
      expect(registry.listDecoders(), isEmpty);
      expect(infos.single.errorMessage, contains('99'));
    });

    test('reports missingSymbol when register entry point is absent', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;

      final dir = await _stageDirectory(
        sources: {'missing_symbol': pluginRoot},
        ext: fixtureExtension,
      );
      final registry = DecoderRegistry.forTesting();
      final loader = FfiDecoderLoader(
        resolver: _resolverFor(dir),
        registry: registry,
      );
      addTearDown(loader.dispose);

      // Must not throw.
      final infos = await loader.scan();

      expect(infos, hasLength(1));
      // ffigen's bindings class binds every symbol lazily — the
      // missing register surfaces when the loader actually invokes
      // it, which the loader categorises as either missingSymbol
      // (lookup failure) or loadError (runtime failure). Both
      // outcomes prove the failure was contained.
      expect(
        infos.single.loadStatus,
        anyOf(
          DecoderPluginLoadStatus.missingSymbol,
          DecoderPluginLoadStatus.loadError,
        ),
      );
      expect(registry.listDecoders(), isEmpty);
    });

    test('reports manifestInvalid for malformed JSON', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;

      final dir = await _stageDirectory(
        sources: {'corrupt_manifest': pluginRoot},
        ext: fixtureExtension,
      );
      final registry = DecoderRegistry.forTesting();
      final loader = FfiDecoderLoader(
        resolver: _resolverFor(dir),
        registry: registry,
      );
      addTearDown(loader.dispose);

      // Must not throw.
      final infos = await loader.scan();

      expect(infos, hasLength(1));
      expect(
        infos.single.loadStatus,
        DecoderPluginLoadStatus.manifestInvalid,
      );
      expect(registry.listDecoders(), isEmpty);
    });

    test('isolates per-plugin failures: good and broken plugins in the same '
        'directory both report, only the good one registers', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;

      final dir = await _stageDirectory(
        sources: {
          'passthrough': pluginRoot,
          'corrupt_manifest': pluginRoot,
        },
        ext: fixtureExtension,
      );
      final registry = DecoderRegistry.forTesting();
      final loader = FfiDecoderLoader(
        resolver: _resolverFor(dir),
        registry: registry,
      );
      addTearDown(loader.dispose);

      final infos = await loader.scan();

      expect(infos, hasLength(2));
      final loaded = infos.firstWhere(
        (i) => i.loadStatus == DecoderPluginLoadStatus.loaded,
      );
      final invalid = infos.firstWhere(
        (i) => i.loadStatus == DecoderPluginLoadStatus.manifestInvalid,
      );
      expect(loaded.registeredDecoderIds, ['test_passthrough']);
      expect(invalid.registeredDecoderIds, isEmpty);
      expect(registry.isRegistered('test_passthrough'), isTrue);
      expect(registry.isRegistered('test_corrupt_manifest'), isFalse);
    });

    test(
      'env-var directory override picks up plugins from a custom path',
      () async {
        if (_skipIfToolchainAbsent(toolchainAvailable)) return;

        final envDir = await _stageDirectory(
          sources: {'passthrough': pluginRoot},
          ext: fixtureExtension,
        );
        final ctx = PluginPlatformContext(
          platform: _hostPlatformEnum(),
          appSupportPath: '${envDir.path}/__platform_default_missing__',
        );
        final resolver = PluginDirectoryResolver(context: ctx);
        final registry = DecoderRegistry.forTesting();
        final loader = FfiDecoderLoader(
          resolver: resolver,
          registry: registry,
          envVarRaw: envDir.path,
        );
        addTearDown(loader.dispose);

        final infos = await loader.scan();

        expect(infos, hasLength(1));
        expect(infos.single.loadStatus, DecoderPluginLoadStatus.loaded);
        expect(registry.isRegistered('test_passthrough'), isTrue);
      },
    );

    test('duplicate decoder id across two directories: second registration '
        'is rejected with a clear error', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;

      final dirA = await _stageDirectory(
        sources: {'passthrough': pluginRoot},
        ext: fixtureExtension,
      );
      final dirB = await _stageDirectory(
        sources: {'passthrough': pluginRoot},
        ext: fixtureExtension,
        copyAs: 'test_passthrough_dup',
      );

      final ctx = PluginPlatformContext(
        platform: _hostPlatformEnum(),
        appSupportPath: '${dirA.path}/__missing__',
      );
      final resolver = PluginDirectoryResolver(context: ctx);
      final registry = DecoderRegistry.forTesting();
      final separator = ctx.pathListSeparator;
      final loader = FfiDecoderLoader(
        resolver: resolver,
        registry: registry,
        envVarRaw: '${dirA.path}$separator${dirB.path}',
      );
      addTearDown(loader.dispose);

      final infos = await loader.scan();

      expect(infos, hasLength(2));
      final loaded = infos.where(
        (i) => i.loadStatus == DecoderPluginLoadStatus.loaded,
      );
      final rejected = infos.where(
        (i) => i.loadStatus == DecoderPluginLoadStatus.loadError,
      );
      expect(loaded, hasLength(1));
      expect(rejected, hasLength(1));
      expect(rejected.single.errorMessage, contains('already taken'));
      expect(registry.isRegistered('test_passthrough'), isTrue);
      expect(
        registry.listDecoders().where((d) => d.id == 'test_passthrough').length,
        1,
      );
    });

    test('pluginLoadingDisabled=true returns empty without touching the '
        'filesystem', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;

      final counter = _CountingResolver(
        delegate: _resolverFor(pluginRoot),
      );
      final registry = DecoderRegistry.forTesting();
      final loader = FfiDecoderLoader(
        resolver: counter,
        registry: registry,
        pluginLoadingDisabled: true,
      );
      addTearDown(loader.dispose);

      final infos = await loader.scan();

      expect(infos, isEmpty);
      expect(
        counter.calls,
        0,
        reason:
            'pluginLoadingDisabled must short-circuit before any '
            'filesystem traversal',
      );
      expect(registry.listDecoders(), isEmpty);
    });

    test('perPluginDisabled[id]=true emits a disabled info row and skips '
        'registration', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;

      final dir = await _stageDirectory(
        sources: {'passthrough': pluginRoot},
        ext: fixtureExtension,
      );
      final libraryFile = dir.listSync().whereType<File>().firstWhere(
        (f) => f.path.endsWith('.$fixtureExtension'),
      );
      final registry = DecoderRegistry.forTesting();
      final loader = FfiDecoderLoader(
        resolver: _resolverFor(dir),
        registry: registry,
        perPluginDisabled: <String, bool>{
          libraryFile.absolute.path: true,
        },
      );
      addTearDown(loader.dispose);

      final infos = await loader.scan();

      expect(infos, hasLength(1));
      expect(infos.single.loadStatus, DecoderPluginLoadStatus.disabled);
      expect(registry.listDecoders(), isEmpty);
    });

    test('plugin-contributed decoders surface in listByCategory under '
        'userPlugin without affecting built-ins', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;

      final registry = DecoderRegistry.forTesting()
        ..register(_stubBuiltinDefinition, _StubBuiltinDecoder.factory);
      final dir = await _stageDirectory(
        sources: {'passthrough': pluginRoot},
        ext: fixtureExtension,
      );
      final loader = FfiDecoderLoader(
        resolver: _resolverFor(dir),
        registry: registry,
      );
      addTearDown(loader.dispose);

      await loader.scan();

      final byCategory = registry.listByCategory();
      expect(
        byCategory[DecoderCategory.serial]?.first.id,
        'stub_builtin',
      );
      final userPluginEntries = byCategory[DecoderCategory.userPlugin];
      expect(userPluginEntries, isNotNull);
      expect(
        userPluginEntries!.map((d) => d.id),
        contains('test_passthrough'),
      );
      expect(
        userPluginEntries
            .firstWhere((d) => d.id == 'test_passthrough')
            .requiredTier,
        LicenseTier.openCore,
      );
    });
  });

  // Every handle `create` returns is destroyed exactly once, whichever way the
  // decode ends, and a NULL one never. The ABI forbids touching a handle after
  // `destroy`, so a second call is a double free in any plugin that frees its
  // state there: a feed error used to destroy the instance and then leave it
  // to the `finally`, which destroyed it again. The fixture counts rather
  // than frees, so a regression fails here instead of crashing the run.
  //
  // A plugin "panic" in `create`, `feed` or `flush` has no fixture: a native
  // fault ends the process, so the loader's catch blocks around those calls
  // can only see errors raised on the Dart side of the call.
  group('FfiDecoderLoader — decoder instance lifecycle', () {
    Future<(DecoderFactory, _LifecycleCounts)> loadLifecycle() async {
      final dir = await _stageDirectory(
        sources: {'lifecycle': pluginRoot},
        ext: fixtureExtension,
      );
      final registry = DecoderRegistry.forTesting();
      final loader = FfiDecoderLoader(
        resolver: _resolverFor(dir),
        registry: registry,
      );
      addTearDown(loader.dispose);
      final infos = await loader.scan();
      expect(infos.single.loadStatus, DecoderPluginLoadStatus.loaded);
      return (
        registry.getFactory('test_lifecycle')!,
        _LifecycleCounts('${dir.path}/libtest_lifecycle.$fixtureExtension'),
      );
    }

    DecoderConfig failing(String? step) => DecoderConfig(
      signalBindings: const {'data': 'top.dq'},
      parameters: {'fail': ?step},
    );

    List<DecodedTransaction> decode(
      ProtocolDecoder decoder, {
      SignalValueQuery? query,
      SignalChangesQuery? changes,
    }) => decoder.decode(
      0,
      100,
      query ?? (name, time) => '1',
      changes ??
          (name, start, end) => const <(int, String)>[(0, '1'), (10, '0')],
    );

    for (final step in <String?>[null, 'feed', 'flush']) {
      test(
        '${step == null ? 'a clean decode' : 'a $step error'} destroys the '
        'instance exactly once',
        () async {
          if (_skipIfToolchainAbsent(toolchainAvailable)) return;
          final (factory, counts) = await loadLifecycle();

          decode(factory(failing(step)));

          expect(counts.created, 1);
          expect(counts.destroyed, 1);
          expect(counts.destroyedTwice, 0);
          expect(counts.destroyedUnknown, 0);
        },
      );
    }

    test('a NULL create is never destroyed', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;
      final (factory, counts) = await loadLifecycle();

      expect(decode(factory(failing('create'))), isEmpty);

      expect(counts.created, 0);
      expect(counts.destroyed, 0);
    });

    test('a value query that throws mid-decode still destroys the '
        'instance', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;
      final (factory, counts) = await loadLifecycle();

      expect(
        () => decode(
          factory(failing(null)),
          query: (name, time) => throw StateError('waveform closed'),
        ),
        throwsStateError,
      );

      expect(counts.created, 1);
      expect(counts.destroyed, 1);
      expect(counts.destroyedTwice, 0);
    });

    test('a timeline query that throws is skipped, and the instance is still '
        'destroyed once', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;
      final (factory, counts) = await loadLifecycle();

      // A signal whose changes cannot be read is dropped from the timeline;
      // the decode runs from the start time alone.
      decode(
        factory(failing(null)),
        changes: (name, start, end) => throw StateError('waveform closed'),
      );

      expect(counts.created, 1);
      expect(counts.destroyed, 1);
      expect(counts.destroyedTwice, 0);
    });
  });

  // The plugin sees and returns femtoseconds; the viewer places
  // transactions in ticks. The passthrough fixture echoes each sample's
  // `timestamp_fs` back as the transaction's start and end, so a
  // transaction must land on the tick of the sample it came from. A
  // 1 fs timescale hides a missing conversion (the factor is 1), so
  // every case here uses a coarser one.
  group('FfiDecoderLoader — transaction times', () {
    Future<DecoderFactory> loadPassthrough() async {
      final dir = await _stageDirectory(
        sources: {'passthrough': pluginRoot},
        ext: fixtureExtension,
      );
      final registry = DecoderRegistry.forTesting();
      final loader = FfiDecoderLoader(
        resolver: _resolverFor(dir),
        registry: registry,
      );
      addTearDown(loader.dispose);
      final infos = await loader.scan();
      expect(infos.single.loadStatus, DecoderPluginLoadStatus.loaded);
      return registry.getFactory('test_passthrough')!;
    }

    List<int> startTimes(ProtocolDecoder decoder, Timescale? timescale) {
      // A 1 ps trace with edges at 225 us and 2 ms, the shape of the
      // openPCIE co-simulation that reported the defect.
      const edges = <(int, String)>[(225000000, '1'), (2000000000, '0')];
      final txs = decoder.decode(
        0,
        2000000001,
        (name, time) => '1',
        (name, start, end) => edges,
        timescale: timescale,
      );
      for (final tx in txs) {
        expect(tx.endTime, tx.startTime, reason: 'zero-width echo');
      }
      return [for (final tx in txs) tx.startTime];
    }

    test('a 1 ps trace places transactions on their sample ticks', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;
      final factory = await loadPassthrough();

      expect(
        startTimes(
          factory(const DecoderConfig(signalBindings: {'data': 'top.d'})),
          const Timescale(factor: 1, unit: TimescaleUnit.picoSeconds),
        ),
        [225000000, 2000000000],
      );
    });

    test('a 10 ns trace places transactions on their sample ticks', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;
      final factory = await loadPassthrough();

      expect(
        startTimes(
          factory(const DecoderConfig(signalBindings: {'data': 'top.d'})),
          const Timescale(factor: 10, unit: TimescaleUnit.nanoSeconds),
        ),
        [225000000, 2000000000],
      );
    });

    test('a trace with no timescale round-trips through the 1 ns '
        'fallback', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;
      final factory = await loadPassthrough();

      expect(
        startTimes(
          factory(const DecoderConfig(signalBindings: {'data': 'top.d'})),
          null,
        ),
        [225000000, 2000000000],
      );
    });
  });
}

/// The lifecycle fixture's counters, read through the test's own handle on
/// the library the loader opened. Opening the same path again returns the
/// already-loaded image, so these are the counters the loader's calls moved.
class _LifecycleCounts {
  _LifecycleCounts(String path) : _lib = ffi.DynamicLibrary.open(path);

  final ffi.DynamicLibrary _lib;

  int _read(String symbol) =>
      _lib.lookupFunction<ffi.Int32 Function(), int Function()>(symbol)();

  int get created => _read('wcx_test_lifecycle_created');
  int get destroyed => _read('wcx_test_lifecycle_destroyed');
  int get destroyedTwice => _read('wcx_test_lifecycle_destroyed_twice');
  int get destroyedUnknown => _read('wcx_test_lifecycle_destroyed_unknown');
}

PluginDirectoryResolver _resolverFor(Directory dir) {
  // Treat the staging directory itself as the "platform default" so
  // we don't have to plumb env-var paths through every test.
  return _OverrideResolver(directory: dir);
}

/// Resolver that ignores the appSupport+default-path computation and
/// just returns one fixed directory. Used by tests that want to stage
/// their own plugin layout without depending on platform paths.
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

PluginHostPlatform _hostPlatformEnum() {
  if (Platform.isLinux) return PluginHostPlatform.linux;
  if (Platform.isMacOS) return PluginHostPlatform.macos;
  if (Platform.isWindows) return PluginHostPlatform.windows;
  return PluginHostPlatform.linux;
}

String _platformLibraryExtension() {
  if (Platform.isLinux) return 'so';
  if (Platform.isMacOS) return 'dylib';
  if (Platform.isWindows) return 'dll';
  return 'so';
}

Directory _findRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  throw StateError('cannot find pubspec.yaml from ${Directory.current.path}');
}

bool _ensureToolchainAndBuild(Directory pluginRoot) {
  // Pre-built libraries already in place from a prior run / manual
  // build? No compiler is needed. We must check *every* fixture, not just
  // one sentinel — when a new fixture directory is added, an older fixture's
  // library still on disk would otherwise short-circuit the build and the
  // new library would never get compiled (the test would then throw
  // "missing pre-built fixture").
  final ext = _platformLibraryExtension();
  final allBuilt = _fixtureSubdirs.entries.every((entry) {
    final subdir = entry.value;
    final libname = _libraryBasenames[entry.key]!;
    return File('${pluginRoot.path}/$subdir/lib$libname.$ext').existsSync();
  });
  if (allBuilt) return true;

  final cc =
      Platform.environment['CC'] ?? (Platform.isWindows ? 'cl.exe' : 'cc');
  if (_which(cc) == null) return false;

  if (Platform.isWindows) {
    final result = Process.runSync(
      'cmd',
      ['/c', '${pluginRoot.path}\\build_test_plugins.bat'],
      runInShell: true,
    );
    return result.exitCode == 0;
  }
  final result = Process.runSync(
    'bash',
    ['${pluginRoot.path}/build_test_plugins.sh'],
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

// TODO(windows-plugin-port): these decoder-plugin loader tests currently SKIP
// on Windows CI (no cl.exe on PATH). They are fully covered on Linux/macOS.
// To run them on Windows (CI "Option B"), three things are needed together:
//   1. Put MSVC on PATH in the Windows test leg (ilammy/msvc-dev-cmd in
//      .github/workflows/ci.yml) so build_test_plugins.bat can compile.
//   2. Export the plugin entry point from the DLL: the C fixtures
//      (test/fixtures/decoder_plugins/test_plugin*/test_plugin.c) need
//      __declspec(dllexport) on the register symbol (via a cross-platform
//      EXPORT macro), else every load reports missingSymbol on Windows.
//   3. Make _stageDirectory's addTearDown tolerate a locked DLL: Windows
//      keeps a loaded .dll locked, so deleteSync(recursive:true) throws
//      PathAccessException (Access is denied). Catch/ignore on Windows, or
//      close the FFI handle before deleting.
// The build_test_plugins.bat lib<name>.dll naming fix is already in place.
//
// Returns true (and marks the test skipped) when no C toolchain is present.
// markTestSkipped() alone does NOT abort the test body, so callers must
// `return` on a true result — otherwise the staging code below runs and
// throws "missing pre-built fixture" on platforms without a compiler
// (e.g. a Windows runner with cl.exe off PATH).
bool _skipIfToolchainAbsent(bool toolchainAvailable) {
  if (!toolchainAvailable) {
    markTestSkipped('C toolchain unavailable; cannot build plugin fixtures');
    return true;
  }
  return false;
}

Future<Directory> _stageDirectory({
  required Map<String, Directory> sources,
  required String ext,
  String? copyAs,
}) async {
  final stage = await Directory.systemTemp.createTemp('wc_plugin_test_');
  addTearDown(() async {
    if (stage.existsSync()) {
      stage.deleteSync(recursive: true);
    }
  });
  for (final entry in sources.entries) {
    final variant = entry.key;
    final root = entry.value;
    final subdir = _fixtureSubdirs[variant]!;
    final libname = _libraryBasenames[variant]!;
    final src = File('${root.path}/$subdir/lib$libname.$ext');
    if (!src.existsSync()) {
      throw StateError('missing pre-built fixture: ${src.path}');
    }
    final dst = File('${stage.path}/lib${copyAs ?? libname}.$ext');
    await src.copy(dst.path);
  }
  return stage;
}

class _CountingResolver extends PluginDirectoryResolver {
  _CountingResolver({required this.delegate})
    : super(context: delegate.context);

  final PluginDirectoryResolver delegate;
  int calls = 0;

  @override
  List<Directory> resolveDirectories({
    List<String> userConfigured = const <String>[],
    String? envVarRaw,
    bool Function(String path)? exists,
  }) {
    calls += 1;
    return delegate.resolveDirectories(
      userConfigured: userConfigured,
      envVarRaw: envVarRaw,
      exists: exists,
    );
  }
}

// Stand-in built-in registered alongside the plugin in the
// registry-visibility test.
const _stubBuiltinDefinition = DecoderDefinition(
  id: 'stub_builtin',
  displayName: 'Stub Built-In',
  description: 'Test stub used to assert built-ins are unaffected by plugins.',
  requiredSignals: <SignalBinding>[],
  category: DecoderCategory.serial,
);

class _StubBuiltinDecoder implements ProtocolDecoder {
  const _StubBuiltinDecoder();
  static ProtocolDecoder factory(DecoderConfig _) =>
      const _StubBuiltinDecoder();
  @override
  DecoderDefinition get definition => _stubBuiltinDefinition;
  @override
  List<DecodedTransaction> decode(
    int startTime,
    int endTime,
    SignalValueQuery query,
    SignalChangesQuery changesQuery, {
    Timescale? timescale,
  }) => const <DecodedTransaction>[];
}
