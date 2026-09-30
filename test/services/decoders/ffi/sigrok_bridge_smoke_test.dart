// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/decoder_parameter_type.dart';
import 'package:wavecrux/domain/enums/timescale_unit.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_info.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_load_status.dart';
import 'package:wavecrux/domain/models/timescale.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/services/decoders/ffi/ffi_decoder_loader.dart';
import 'package:wavecrux/services/decoders/ffi/plugin_directory_resolver.dart';

/// Smoke test for the SigRok bridge plugin, which lives in the separate
/// `wavecrux/wavecrux-sigrok-bridge` repository.
///
/// The bridge is downloaded by users who want the SigRok decoder
/// ecosystem; it is not a built-in WaveCrux feature, not bundled with
/// the WaveCrux installer, and not auto-discovered. WaveCrux's plugin
/// loader sees it as one more native plugin alongside the 1-Wire
/// demonstrator covered by `onewire_demo_integration_test.dart`.
///
/// This test:
///
/// * skips when the bridge shim binary is not installed in any
///   directory the [PluginDirectoryResolver] would scan;
/// * when the bridge IS present, asserts that:
///   - [FfiDecoderLoader.scan] returns a [DecoderPluginInfo] for the
///     bridge with status [DecoderPluginLoadStatus.loaded];
///   - the declared ABI MAJOR matches the open-core ABI (1);
///   - the bridge advertises the reference decoders the bridge repo's
///     acceptance criteria require: `sigrok.jtag`, `sigrok.pwm`,
///     `sigrok.dmx512`, `sigrok.modbus`, plus a 1-Wire decoder. The
///     mock backend exposes `sigrok.onewire`; the real libsigrokdecode
///     corpus splits it into `sigrok.onewire_link` /
///     `sigrok.onewire_network`, so the 1-Wire check accepts any
///     `sigrok.onewire*` id.
///
/// The bridge's own end-to-end correctness — i.e. that each advertised
/// decoder produces the right annotations — is verified by tests in
/// the bridge repo itself (`crates/bridge/tests/end_to_end.rs`). This
/// smoke test is purely the WaveCrux-side load contract.
///
/// See `verification/VERIFICATION_GUIDE.md` §22.5.4.1 for the full
/// manual verification walkthrough.
void main() {
  group('SigRok bridge smoke test', () {
    test('shim loads cleanly and advertises the reference decoders', () async {
      final shim = _findInstalledShim();
      if (shim == null) {
        markTestSkipped(
          'wavecrux-sigrok-bridge shim not installed — skipping smoke test. '
          'Install per github.com/wavecrux/wavecrux-sigrok-bridge#installation '
          'to exercise.',
        );
        return;
      }

      // Point the resolver exclusively at the directory containing the
      // shim so the smoke test never picks up a stale demonstrator
      // plugin from a different install. The resolver normally walks
      // the per-user plugin directory plus user-configured paths plus
      // WAVECRUX_DECODER_PATH; we override the user-configured list to
      // the shim's own dir and rely on the resolver's filesystem-
      // existence check to drop everything else.
      //
      // shim path structure: <appSupport>/wavecrux/decoders/<lib>
      // so parent.parent.parent == appSupport root.
      final resolver = PluginDirectoryResolver(
        context: PluginPlatformContext(
          platform: _hostPlatform(),
          appSupportPath: shim.parent.parent.parent.path,
        ),
      );
      final loader = FfiDecoderLoader(
        resolver: resolver,
        userConfiguredDirectories: <String>[shim.parent.path],
      );
      final results = await loader.scan();

      final bridge = results.firstWhere(
        (p) =>
            p.filePath == shim.path ||
            p.filePath.endsWith('/${shim.uri.pathSegments.last}'),
        orElse: () => fail(
          'shim ${shim.path} did not appear in scan result '
          '(${results.length} plugins discovered)',
        ),
      );

      expect(
        bridge.loadStatus,
        DecoderPluginLoadStatus.loaded,
        reason:
            'bridge plugin failed to load: '
            "${bridge.errorMessage ?? '<no error message>'}",
      );
      expect(
        bridge.declaredAbiMajor,
        equals(1),
        reason: 'bridge ABI MAJOR mismatch with WaveCrux open-core',
      );

      final decoderIds = bridge.registeredDecoderIds.toSet();
      const required = <String>{
        'sigrok.jtag',
        'sigrok.pwm',
        'sigrok.dmx512',
        'sigrok.modbus',
      };
      for (final id in required) {
        expect(
          decoderIds,
          contains(id),
          reason:
              'bridge advertised ${decoderIds.length} decoders, '
              'but did not include reference decoder $id (per '
              'VERIFICATION_GUIDE §22.5.4.1 and the bridge repo '
              'acceptance criteria).',
        );
      }
      // 1-Wire: the mock backend exposes `sigrok.onewire`; the real
      // libsigrokdecode corpus splits it into onewire_link /
      // onewire_network. Accept any onewire-family id.
      expect(
        decoderIds.any((id) => id.startsWith('sigrok.onewire')),
        isTrue,
        reason:
            'bridge advertised ${decoderIds.length} decoders, but none '
            'were a 1-Wire decoder (expected sigrok.onewire or '
            'sigrok.onewire_link / sigrok.onewire_network).',
      );
    });

    test('a bridged decoder instance opens and decodes', () async {
      final shim = _findInstalledShim();
      if (shim == null) {
        markTestSkipped('wavecrux-sigrok-bridge shim not installed.');
        return;
      }
      final registry = DecoderRegistry.forTesting();
      final loader = FfiDecoderLoader(
        resolver: PluginDirectoryResolver(
          context: PluginPlatformContext(
            platform: _hostPlatform(),
            appSupportPath: shim.parent.parent.parent.path,
          ),
        ),
        registry: registry,
        userConfiguredDirectories: <String>[shim.parent.path],
      );
      addTearDown(loader.dispose);
      await loader.scan();

      const id = 'sigrok.pwm';
      final definition = registry.getDefinition(id);
      expect(definition, isNotNull, reason: 'bridge did not register $id');
      // An enumeration with no values leaves its picker empty.
      for (final p in definition!.parameters) {
        if (p.type != DecoderParameterType.enumeration) continue;
        expect(p.enumValues, isNotEmpty, reason: '${p.name} has no values');
      }
      // Bind every declared signal to the same square wave, whatever the
      // backend names the channels.
      final bindings = <String, String>{
        for (final s in definition.requiredSignals) s.name: 'top.pwm',
      };
      // Ten 1000-tick periods at 25 % duty.
      final changes = <(int, String)>[
        for (var period = 0; period < 10; period++) ...[
          (period * 1000, '1'),
          (period * 1000 + 250, '0'),
        ],
      ];
      String valueAt(String name, int time) {
        var value = '0';
        for (final (t, v) in changes) {
          if (t > time) break;
          value = v;
        }
        return value;
      }

      final decoder = registry.getFactory(id)!(
        DecoderConfig(signalBindings: bindings),
      );
      final transactions = decoder.decode(
        0,
        10000,
        valueAt,
        (name, start, end) =>
            changes.where((c) => c.$1 >= start && c.$1 < end).toList(),
        timescale: const Timescale(
          factor: 1,
          unit: TimescaleUnit.nanoSeconds,
        ),
      );

      // A decoder instance the bridge refuses to open yields nothing.
      expect(transactions, isNotEmpty);
    });
  });
}

/// Look for the shim binary in the conventional install locations.
/// Returns null if no shim is found — the test skips, not fails.
File? _findInstalledShim() {
  final platform = _hostPlatform();
  // Post-v0.1.0 releases ship the shim as
  // libwavecrux_sigrok_bridge_shim.{so,dylib} /
  // wavecrux_sigrok_bridge_shim.dll (the lib target was renamed to
  // avoid a Windows PDB collision with the bridge binary); v0.1.0
  // shipped the un-suffixed name. Accept both — the real loader scans
  // by extension and doesn't care.
  final fileNames = switch (platform) {
    PluginHostPlatform.linux => [
      'libwavecrux_sigrok_bridge_shim.so',
      'libwavecrux_sigrok_bridge.so',
    ],
    PluginHostPlatform.macos => [
      'libwavecrux_sigrok_bridge_shim.dylib',
      'libwavecrux_sigrok_bridge.dylib',
    ],
    PluginHostPlatform.windows => [
      'wavecrux_sigrok_bridge_shim.dll',
      'wavecrux_sigrok_bridge.dll',
    ],
  };

  // 1. WAVECRUX_DECODER_PATH (any entry).
  final envOverride = Platform.environment['WAVECRUX_DECODER_PATH'];
  if (envOverride != null && envOverride.isNotEmpty) {
    final separator = platform == PluginHostPlatform.windows ? ';' : ':';
    for (final dir in envOverride.split(separator)) {
      for (final fileName in fileNames) {
        final candidate = File('${dir.trim()}/$fileName');
        if (candidate.existsSync()) return candidate;
      }
    }
  }

  // 2. Per-platform default plugin directory.
  //    On macOS getApplicationSupportDirectory() returns a bundle-ID
  //    scoped path, not a generic app-name path. Check both known
  //    bundle IDs (Pro and open-core) so the test works against either
  //    build without requiring WAVECRUX_DECODER_PATH to be set.
  final home = Platform.environment['HOME'] ?? '';
  final defaultCandidateDirs = switch (platform) {
    PluginHostPlatform.macos => [
      '$home/Library/Application Support/com.ferriteengineering.wavecruxPro/wavecrux/decoders',
      '$home/Library/Application Support/com.ferriteengineering.wavecrux/wavecrux/decoders',
    ],
    PluginHostPlatform.linux => [
      if (Platform.environment['XDG_CONFIG_HOME'] != null)
        '${Platform.environment['XDG_CONFIG_HOME']}/wavecrux/decoders'
      else
        '$home/.local/share/wavecrux/decoders',
    ],
    PluginHostPlatform.windows => [
      '${Platform.environment['APPDATA'] ?? ''}\\WaveCrux\\decoders',
    ],
  };
  for (final dir in defaultCandidateDirs) {
    for (final fileName in fileNames) {
      final candidate = File('$dir/$fileName');
      if (candidate.existsSync()) return candidate;
    }
  }

  return null;
}

PluginHostPlatform _hostPlatform() {
  if (Platform.isMacOS) return PluginHostPlatform.macos;
  if (Platform.isWindows) return PluginHostPlatform.windows;
  return PluginHostPlatform.linux;
}
