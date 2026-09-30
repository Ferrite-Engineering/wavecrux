// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_load_status.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/decoders/ffi/ffi_decoder_loader.dart';
import 'package:wavecrux/services/decoders/ffi/ffi_decoder_loader_provider.dart';
import 'package:wavecrux/services/decoders/ffi/plugin_directory_resolver.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

class _MockSettingsService extends Mock implements WaveCruxSettingsService {}

/// Integration test for the Settings → Decoders → Plugins data flow
/// against the real 1-Wire demonstrator plugin.
///
/// Pumps the panel's exact provider chain
/// (`appSettingsNotifier → decoderPluginLoader → DecoderPluginList`)
/// through a real `ProviderContainer` rather than `pumpWidget` — the
/// panel's own widget tests in `decoder_plugins_panel_test.dart`
/// already cover rendering of every load-status; what this test adds
/// is the end-to-end check that a real `FfiDecoderLoader` against the
/// committed demonstrator artifact lands in the panel's data list with
/// status `loaded`, and that toggling per-plugin disable keeps the
/// demonstrator out of the host registry.
///
/// Skips on hosts without a C toolchain — the demonstrator is built
/// fresh in `setUpAll` so the integration test follows whatever ABI
/// the open-core repo currently exposes.
void main() {
  late Directory pluginRoot;
  late String libraryExtension;
  late bool toolchainAvailable;

  setUpAll(() {
    registerFallbackValue(const AppSettings());
    final repoRoot = _findRepoRoot();
    pluginRoot = Directory('${repoRoot.path}/examples/decoder-plugin-demo');
    libraryExtension = _platformLibraryExtension();
    toolchainAvailable = _ensureDemonstratorBuilt(pluginRoot);
  });

  setUp(resetStartupScanCacheForTesting);

  group('DecoderPluginList provider + 1-Wire demonstrator', () {
    test('lists the demonstrator with status `loaded` and registers '
        'examples.onewire in the host registry', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;

      final stage = await _stageDemonstrator(pluginRoot, libraryExtension);
      final registry = DecoderRegistry.forTesting();
      final loader = FfiDecoderLoader(
        resolver: _OverrideResolver(directory: stage),
        registry: registry,
      );
      addTearDown(loader.dispose);

      final container = _container(
        initialSettings: const AppSettings().copyWith(
          pluginSafetyAcknowledged: true,
        ),
        loader: loader,
      );
      addTearDown(container.dispose);

      final infos = await container.read(decoderPluginListProvider.future);

      expect(infos, hasLength(1));
      final entry = infos.single;
      expect(entry.loadStatus, DecoderPluginLoadStatus.loaded);
      expect(entry.displayName, '1-Wire (demo plugin)');
      expect(entry.declaredAbiMajor, 1);
      expect(entry.registeredDecoderIds, ['examples.onewire']);

      // Same data the panel will render via `_PluginRow`.
      expect(registry.isRegistered('examples.onewire'), isTrue);
      final def = registry.getDefinition('examples.onewire')!;
      expect(def.requiredSignals.single.name, 'dq');
    });

    test('with the demonstrator marked disabled in AppSettings, the '
        'panel data shows the disabled row and the host registry is '
        'untouched', () async {
      if (_skipIfToolchainAbsent(toolchainAvailable)) return;

      final stage = await _stageDemonstrator(pluginRoot, libraryExtension);
      final libraryFile = stage.listSync().whereType<File>().firstWhere(
        (f) => f.path.endsWith('.$libraryExtension'),
      );

      final registry = DecoderRegistry.forTesting();
      final disabledMap = <String, bool>{
        libraryFile.absolute.path: true,
      };
      final loader = FfiDecoderLoader(
        resolver: _OverrideResolver(directory: stage),
        registry: registry,
        perPluginDisabled: disabledMap,
      );
      addTearDown(loader.dispose);

      final container = _container(
        initialSettings: const AppSettings().copyWith(
          pluginSafetyAcknowledged: true,
          perPluginDisabled: disabledMap,
        ),
        loader: loader,
      );
      addTearDown(container.dispose);

      final infos = await container.read(decoderPluginListProvider.future);

      expect(infos, hasLength(1));
      expect(infos.single.loadStatus, DecoderPluginLoadStatus.disabled);
      expect(infos.single.registeredDecoderIds, isEmpty);

      // Decoder must not have been registered.
      expect(registry.isRegistered('examples.onewire'), isFalse);
    });
  });
}

// ── helpers ───────────────────────────────────────────────────────────────

ProviderContainer _container({
  required AppSettings initialSettings,
  required FfiDecoderLoader loader,
}) {
  final settingsService = _MockSettingsService();
  when(settingsService.load).thenAnswer((_) async => initialSettings);
  when(() => settingsService.save(any())).thenAnswer((_) async {});
  return ProviderContainer(
    overrides: [
      settingsServiceProvider.overrideWithValue(settingsService),
      decoderPluginLoaderProvider.overrideWith((_) async => loader),
    ],
  );
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
  if (Platform.isWindows) return false;
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
  final stage = await Directory.systemTemp.createTemp('wc_onewire_panel_test_');
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
