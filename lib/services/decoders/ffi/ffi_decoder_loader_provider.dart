// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io' show Platform;
import 'package:crux_audit/crux_audit.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_policy/crux_policy.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';
import 'package:wavecrux/domain/interfaces/decoder_plugin_loader.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/domain/models/decoder_plugin/decoder_plugin_info.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/services/decoders/ffi/ffi_decoder_loader.dart';
import 'package:wavecrux/services/decoders/ffi/plugin_allowlist.dart';
import 'package:wavecrux/services/decoders/ffi/plugin_allowlist_provider.dart';
import 'package:wavecrux/services/decoders/ffi/plugin_directory_resolver.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

part 'ffi_decoder_loader_provider.g.dart';

/// Cache populated by [scanPluginsOnStartup] during `bootstrap` and
/// consumed by [DecoderPluginList]'s first build. Lets bootstrap perform
/// the canonical "register decoders before runApp" pass while the
/// Settings UI still gets a live AsyncNotifier-backed list.
List<DecoderPluginInfo>? _startupScanCache;

/// The loader instance created by [scanPluginsOnStartup]. Handed to
/// [decoderPluginLoaderProvider] so the provider's loader IS the one
/// that already has correct [_loadedPlugins] state. Without this,
/// [decoderPluginLoaderProvider] would create a second loader with
/// empty state, and [DecoderPluginList.refresh] would fail to
/// unregister the startup-scan decoders before re-registering them.
FfiDecoderLoader? _startupLoader;

/// Test-only escape hatch to clear the startup cache between cases.
@visibleForTesting
void resetStartupScanCacheForTesting() {
  _startupScanCache = null;
  _startupLoader = null;
}

/// Runs the one-time decoder-plugin scan at app startup.
///
/// Loads [AppSettings] via [WaveCruxSettingsService] (no provider container is
/// available this early in `bootstrap`), gates the scan on
/// [AppSettings.pluginSafetyAcknowledged], and — when permitted —
/// constructs a desktop loader and registers every successfully loaded
/// plugin's decoders into `DecoderRegistry.instance`.
///
/// Failures inside the loader are surfaced as [DecoderPluginInfo] rows
/// with a non-`loaded` status and never thrown past this function — a
/// broken plugin must not be able to block app startup.
///
/// The returned list is cached so [DecoderPluginList] can surface it
/// without re-scanning on first read.
Future<List<DecoderPluginInfo>> scanPluginsOnStartup({
  WaveCruxSettingsService? settingsService,
}) async {
  if (kIsWeb) {
    _startupScanCache = const <DecoderPluginInfo>[];
    return _startupScanCache!;
  }

  final AppSettings settings;
  try {
    final svc = settingsService ?? const WaveCruxSettingsService();
    settings = await svc.load();
  } on Object {
    // SharedPreferences not yet ready (e.g. test host without the
    // platform channel registered). Skip the scan; the AsyncNotifier
    // will run a real scan once settings are available later.
    _startupScanCache = const <DecoderPluginInfo>[];
    return _startupScanCache!;
  }

  if (!settings.pluginSafetyAcknowledged) {
    _startupScanCache = const <DecoderPluginInfo>[];
    return _startupScanCache!;
  }

  final ctx = PluginPlatformContext(
    platform: _hostPlatform(),
    appSupportPath: await _appSupportPath(),
    environment: Platform.environment,
  );
  final resolver = PluginDirectoryResolver(context: ctx);
  // The policy file is read HERE rather than through `pluginAllowlistProvider`,
  // because there is no Riverpod container this early — and the refusal cannot
  // wait for one. A plugin loaded before the allowlist is consulted is a
  // plugin loaded regardless of the allowlist, which is the whole thing this
  // feature exists to prevent. `PolicyLoader.load` degrades to an absent
  // document rather than throwing, so a machine with no policy file takes the
  // same path it always did.
  final allowlist = PluginAllowlist.fromPolicyValue(
    const PolicyLoader().load().document.products[WaveCruxPolicyKeys
        .productId]?[WaveCruxPolicyKeys.approvedPlugins],
  );
  final loader = FfiDecoderLoader(
    resolver: resolver,
    userConfiguredDirectories: settings.userPluginDirectories,
    envVarRaw: Platform.environment['WAVECRUX_DECODER_PATH'],
    pluginLoadingDisabled: settings.pluginLoadingDisabled,
    perPluginDisabled: settings.perPluginDisabled,
    allowlist: allowlist,
    // Buffered, not dropped. The audit recorder does not exist yet either, and
    // a refusal at startup is precisely the one worth recording — it is the
    // moment an unapproved plugin would otherwise have been loaded.
    // `flushStartupPluginAuditEvents` drains this once the container is up.
    onPluginLoad: _startupPluginEvents.add,
  );

  try {
    final infos = await loader.scan();
    _startupScanCache = infos;
    // Keep the loader alive so decoderPluginLoaderProvider can adopt it.
    // That way the provider's loader already has the correct _loadedPlugins
    // state and refresh() can unregister startup decoders before re-scanning.
    _startupLoader = loader;
    return infos;
  } on Object {
    // The loader itself is supposed to swallow per-plugin errors and
    // never throw past scan(); this catch is a defence-in-depth layer
    // so an unexpected exception in the loader does not block startup.
    loader.dispose();
    _startupScanCache = const <DecoderPluginInfo>[];
    return _startupScanCache!;
  }
}

/// Holds the platform-appropriate [DecoderPluginLoader] instance.
///
/// On desktop (`dart:io`) this is the real `dart:ffi`-backed
/// [FfiDecoderLoader] wired up with the user's
/// `WAVECRUX_DECODER_PATH` env var, configured directories, and
/// per-plugin disable map. On Flutter Web it is a loader that finds no
/// plugins — runtime native code loading is unavailable there.
///
/// The loader rebuilds whenever [AppSettings] changes (so adding a
/// directory or toggling the master switch immediately takes effect
/// on the next scan). Tests override this provider to inject a fake
/// loader without touching the real filesystem.
@Riverpod(keepAlive: true)
Future<DecoderPluginLoader> decoderPluginLoader(
  Ref ref,
) async {
  // A browser cannot load native code. Hand back a loader that finds nothing
  // without building the FFI loader, whose setup reads dart:io `Platform`
  // and the policy file — both unavailable on the web.
  if (kIsWeb) return const _NoNativePluginsLoader();

  final settings = await ref.watch(appSettingsProvider.future);

  // Adopt the startup loader when available so the provider's loader IS
  // the one that already ran scan() and has correct _loadedPlugins state.
  // Without this, refresh() would create a second loader with empty state,
  // fail to unregister the startup decoders, and hit "id already taken".
  // Consume the reference once — subsequent rebuilds (settings changed)
  // fall through to create a fresh loader with the updated settings.
  final adopted = _startupLoader;
  if (adopted != null) {
    _startupLoader = null;
    ref.onDispose(adopted.dispose);
    return adopted;
  }

  final platform = _hostPlatform();
  final appSupportPath = await _appSupportPath();
  final environment = Platform.environment;
  final ctx = PluginPlatformContext(
    platform: platform,
    appSupportPath: appSupportPath,
    environment: environment,
  );
  final resolver = PluginDirectoryResolver(context: ctx);

  final loader = FfiDecoderLoader(
    resolver: resolver,
    userConfiguredDirectories: settings.userPluginDirectories,
    envVarRaw: environment['WAVECRUX_DECODER_PATH'],
    pluginLoadingDisabled: settings.pluginLoadingDisabled,
    perPluginDisabled: settings.perPluginDisabled,
    allowlist: ref.watch(pluginAllowlistProvider),
    onPluginLoad: _auditObserver(ref.watch(cruxAuditRecorderProvider)),
  );
  ref.onDispose(loader.dispose);
  return loader;
}

/// Holds the most recent decoder-plugin scan result.
///
/// First read triggers a scan via [DecoderPluginLoader.scan]. Settings
/// → Decoders → Plugins reads this provider to render one
/// row per discovered plugin and calls [refresh] to re-run discovery
/// after the user installs or removes a plugin.
///
/// During the public beta the bootstrap path
/// gates first-load on [AppSettings.pluginSafetyAcknowledged]; until
/// the user acknowledges, the build returns an empty list without
/// touching the filesystem. The Settings panel surfaces the
/// acknowledgment prompt and then calls [refresh] to materialise
/// plugins.
@Riverpod(keepAlive: true)
class DecoderPluginList extends _$DecoderPluginList {
  bool _consumedStartupCache = false;

  @override
  Future<List<DecoderPluginInfo>> build() async {
    final settings = await ref.watch(appSettingsProvider.future);
    if (!settings.pluginSafetyAcknowledged) {
      return const <DecoderPluginInfo>[];
    }
    if (!_consumedStartupCache && _startupScanCache != null) {
      _consumedStartupCache = true;
      return _startupScanCache!;
    }
    final loader = await ref.watch(decoderPluginLoaderProvider.future);
    return await loader.scan();
  }

  /// Re-runs plugin discovery, replacing the cached scan result. The
  /// "Reload plugins" button in the Settings UI calls this.
  Future<void> refresh() async {
    state = const AsyncLoading<List<DecoderPluginInfo>>();
    state = await AsyncValue.guard(() async {
      final loader = await ref.read(decoderPluginLoaderProvider.future);
      return await loader.scan();
    });
  }
}

/// The web's plugin loader: there are no native plugins to find.
class _NoNativePluginsLoader implements DecoderPluginLoader {
  const _NoNativePluginsLoader();

  @override
  Future<List<DecoderPluginInfo>> scan() async => const <DecoderPluginInfo>[];

  @override
  void dispose() {}
}

PluginHostPlatform _hostPlatform() {
  if (Platform.isLinux) return PluginHostPlatform.linux;
  if (Platform.isMacOS) return PluginHostPlatform.macos;
  if (Platform.isWindows) return PluginHostPlatform.windows;
  // iOS / Android / Fuchsia and any future host fall through to the
  // closest semantic match. Mobile is not a supported plugin host —
  // the resolver still works but the underlying loader is the stub
  // unless overridden in tests.
  return PluginHostPlatform.linux;
}

Future<String> _appSupportPath() async {
  try {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  } on Object {
    // path_provider unavailable (e.g. unit-test host without the
    // platform channel registered). Fall back to a sentinel that the
    // resolver will surface as "directory does not exist" rather than
    // crashing the loader at startup.
    return '';
  }
}

/// Records `plugin.load.attempted` and, on a refusal,
/// `plugin.load.refused`.
///
/// **A plugin PATH never reaches a payload**, so this carries the file's name
/// and its SHA-256 and nothing else. A path carries a username, and this file
/// is read by whoever runs the organization's log shipper. The digest is the
/// better identifier anyway: it is exactly what an administrator compares
/// against their own list.
///
/// `pluginLoadRefused` is `crux_audit`'s shared kind rather than a WaveCrux
/// one — a refusal by the organization's policy is the same event in any
/// product that grows a plugin surface, and it is distinct from this
/// product's own *attempt* kind.
/// Plugin-load events observed by [scanPluginsOnStartup], before any recorder
/// exists.
///
/// Module-level and drained exactly once. A list rather than a stream because
/// there is no listener to miss an event: the drain happens after the fact, by
/// definition.
final List<PluginLoadEvent> _startupPluginEvents = <PluginLoadEvent>[];

/// Records everything [scanPluginsOnStartup] saw, and empties the buffer.
///
/// Called from the app's bootstrap once the container exists. **Idempotent by
/// draining**: a second call records nothing, so a hot reload or a re-entrant
/// bootstrap cannot double-count a refusal.
void flushStartupPluginAuditEvents(CruxAuditRecorder recorder) {
  if (_startupPluginEvents.isEmpty) return;
  final observer = _auditObserver(recorder);
  final pending = List<PluginLoadEvent>.of(_startupPluginEvents);
  _startupPluginEvents.clear();
  pending.forEach(observer);
}

PluginLoadObserver _auditObserver(CruxAuditRecorder recorder) => (event) {
  recorder.record(
    WaveCruxAuditKinds.pluginLoadAttempted,
    payload: <String, Object?>{
      'plugin': event.displayName,
      'sha256': ?event.digest,
      'refused': event.refused,
    },
  );
  if (!event.refused) return;
  recorder.record(
    CruxSharedAuditKinds.pluginLoadRefused,
    payload: <String, Object?>{
      'plugin': event.displayName,
      'sha256': ?event.digest,
      'reason': 'not-allowlisted',
    },
  );
};
