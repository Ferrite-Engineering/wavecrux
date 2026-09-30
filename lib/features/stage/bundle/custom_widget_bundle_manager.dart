// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/domain/interfaces/custom_stage_widget_registry.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/features/stage/bundle/custom_widget_bundle_store.dart';
import 'package:wavecrux/features/stage/bundle/loaded_widget_bundle.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_failure.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_reader.dart';
import 'package:wavecrux/features/stage/bundle/widget_bundle_spec.dart';
import 'package:wavecrux/features/stage/runtime/community_rive_stage_renderer.dart';
import 'package:wavecrux/features/stage/runtime/manifest_stage_widget.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_enums.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_renderer_registry.dart';
import 'package:wavecrux/plugins/stage_registry.dart';

/// Captures custom Stage-widget bundle load / watch failures into the
/// issue-reporter buffer (otherwise only visible in the Settings panel).
final _log = Logger('wavecrux.stage.bundle');

/// Snapshot of one successfully loaded `.wcrux-widget` bundle.
@immutable
class LoadedBundleEntry {
  const LoadedBundleEntry({
    required this.bundlePath,
    required this.widgetId,
    required this.widgetVersion,
    required this.displayName,
    this.sourceDirectory,
  });

  /// Absolute path of the `.wcrux-widget` file on disk.
  final String bundlePath;

  /// Manifest-declared widget id, also used as the registry key.
  final String widgetId;

  /// Manifest version string.
  final String widgetVersion;

  /// Display name as resolved for the active locale at load time.
  final String displayName;

  /// Watched directory the bundle was discovered in, or null when the
  /// bundle was loaded directly via the file picker.
  final String? sourceDirectory;

  @override
  bool operator ==(Object other) =>
      other is LoadedBundleEntry &&
      bundlePath == other.bundlePath &&
      widgetId == other.widgetId &&
      widgetVersion == other.widgetVersion &&
      displayName == other.displayName &&
      sourceDirectory == other.sourceDirectory;

  @override
  int get hashCode => Object.hash(
    bundlePath,
    widgetId,
    widgetVersion,
    displayName,
    sourceDirectory,
  );
}

/// One bundle whose load attempt failed. Surfaced in the Settings panel
/// as a removable stale entry so the user can dismiss outdated paths
/// without restarting the app.
@immutable
class BundleLoadError {
  const BundleLoadError({
    required this.bundlePath,
    required this.kind,
    required this.diagnostic,
    this.sourceDirectory,
  });

  final String bundlePath;
  final WidgetBundleFailureKind kind;
  final String diagnostic;
  final String? sourceDirectory;

  @override
  bool operator ==(Object other) =>
      other is BundleLoadError &&
      bundlePath == other.bundlePath &&
      kind == other.kind &&
      diagnostic == other.diagnostic &&
      sourceDirectory == other.sourceDirectory;

  @override
  int get hashCode =>
      Object.hash(bundlePath, kind, diagnostic, sourceDirectory);
}

/// Reactive state exposed by [CustomWidgetBundleManager].
@immutable
class CustomWidgetBundleManagerState {
  const CustomWidgetBundleManagerState({
    this.loadedBundles = const [],
    this.errors = const [],
    this.watchedDirectories = const [],
  });

  final List<LoadedBundleEntry> loadedBundles;
  final List<BundleLoadError> errors;
  final List<String> watchedDirectories;

  CustomWidgetBundleManagerState copyWith({
    List<LoadedBundleEntry>? loadedBundles,
    List<BundleLoadError>? errors,
    List<String>? watchedDirectories,
  }) => CustomWidgetBundleManagerState(
    loadedBundles: loadedBundles ?? this.loadedBundles,
    errors: errors ?? this.errors,
    watchedDirectories: watchedDirectories ?? this.watchedDirectories,
  );

  bool get isEmpty => loadedBundles.isEmpty && errors.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is CustomWidgetBundleManagerState &&
      _listEquals(loadedBundles, other.loadedBundles) &&
      _listEquals(errors, other.errors) &&
      _listEquals(watchedDirectories, other.watchedDirectories);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(loadedBundles),
    Object.hashAll(errors),
    Object.hashAll(watchedDirectories),
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Signature for a function that returns a [Stream<FileSystemEvent>] for
/// the contents of [directoryPath].
///
/// Injected in tests to avoid real file-system I/O.
typedef DirectoryWatchFactory =
    Stream<FileSystemEvent> Function(
      String directoryPath,
    );

Stream<FileSystemEvent> _defaultDirectoryWatchFactory(String path) =>
    Directory(path).watch();

/// Signature for a function that lists files inside [directoryPath].
///
/// Injected in tests; production reads the real filesystem.
typedef DirectoryListFactory = List<String> Function(String directoryPath);

List<String> _defaultDirectoryListFactory(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(followLinks: false)
      .whereType<File>()
      .map((f) => f.path)
      .toList();
}

/// Registers a widget [definition] so the Stage picker and render path
/// (`StageInstanceTile`) can resolve it by id. Defaults to
/// `StageRegistry.instance.register`; injected as a seam in tests.
typedef DefinitionRegistrar = void Function(StageWidget definition);

/// The production [DefinitionRegistrar] — see [CustomWidgetBundleManager]'s
/// constructor for why it flags every bundle definition as user-supplied.
///
/// Public so a caller that wants to observe registrations (the audit emitter in
/// `custom_widget_bundle_provider.dart`) can wrap it rather than restate
/// `userSupplied: true`, which is a decision that must live in exactly one
/// place.
void registerUserSuppliedDefinition(StageWidget definition) =>
    StageRegistry.instance.register(definition, userSupplied: true);

/// Removes a previously-registered widget definition by id. Defaults to
/// `StageRegistry.instance.unregister`.
typedef DefinitionUnregistrar = void Function(String widgetId);

/// Registers a Flutter [renderer] for [widgetId] so the panel can paint the
/// bundle's live artboard. Defaults to
/// `StageWidgetRendererRegistry.instance.register`.
typedef RendererRegistrar =
    void Function(String widgetId, StageInstanceRenderer renderer);

/// Removes a previously-registered renderer by id. Defaults to
/// `StageWidgetRendererRegistry.instance.unregister`.
typedef RendererUnregistrar = void Function(String widgetId);

/// Orchestrates the lifetime of every Stage Pro custom-widget bundle
/// loaded into the app.
///
/// Responsibilities:
///
/// - Persists manually-loaded bundle paths and watched-directory paths
///   via [CustomWidgetBundleStore] so they survive app restart.
/// - Loads each persisted entry through [WidgetBundleReader] on
///   [initialize], surfacing per-path failures non-fatally.
/// - Registers loaded descriptors into [CustomStageWidgetRegistry] so the
///   open-core picker dialog can list them.
/// - Watches each registered directory and auto-loads / unloads bundles
///   as files appear, change, or disappear.
///
/// Notifies via [ChangeNotifier]; the Settings panel and any other
/// consumer reads [state] inside their build method.
class CustomWidgetBundleManager extends ChangeNotifier {
  /// Creates a manager wired to a registry and a persistence store.
  ///
  /// [reader] defaults to a stock [WidgetBundleReader]; tests inject a
  /// reader configured against a fake archive decoder. [watchFactory]
  /// and [listFactory] are similarly test seams; production uses the
  /// real `dart:io` `Directory.watch` and `Directory.listSync`.
  CustomWidgetBundleManager({
    required CustomStageWidgetRegistry registry,
    required CustomWidgetBundleStore store,
    WidgetBundleReader? reader,
    DirectoryWatchFactory? watchFactory,
    DirectoryListFactory? listFactory,
    String localeCode = 'en',
    // The Stage widget *capability* is free open-core (wavecrux/CLAUDE.md:
    // lib/features/stage/{sdk,runtime,bundle,settings} is the free SDK).
    // A user-loaded community .wcrux-widget is therefore open-core content
    // and must NOT carry a PRO badge in the picker — only the curated Pro
    // *pack* (registered via a different path) is Pro.
    LicenseTier requiredTier = LicenseTier.openCore,
    DefinitionRegistrar? registerDefinition,
    DefinitionUnregistrar? unregisterDefinition,
    RendererRegistrar? registerRenderer,
    RendererUnregistrar? unregisterRenderer,
  }) : _registry = registry,
       _store = store,
       _reader = reader ?? WidgetBundleReader(),
       _watchFactory = watchFactory ?? _defaultDirectoryWatchFactory,
       _listFactory = listFactory ?? _defaultDirectoryListFactory,
       _localeCode = localeCode,
       _requiredTier = requiredTier,
       // `userSupplied: true` — a bundle's id is authored by whoever wrote the
       // bundle, so it is not vocabulary telemetry may report.
       _registerDefinition =
           registerDefinition ?? registerUserSuppliedDefinition,
       _unregisterDefinition =
           unregisterDefinition ?? StageRegistry.instance.unregister,
       _registerRenderer =
           registerRenderer ?? StageWidgetRendererRegistry.instance.register,
       _unregisterRenderer =
           unregisterRenderer ??
           StageWidgetRendererRegistry.instance.unregister;

  final CustomStageWidgetRegistry _registry;
  final CustomWidgetBundleStore _store;
  final WidgetBundleReader _reader;
  final DirectoryWatchFactory _watchFactory;
  final DirectoryListFactory _listFactory;
  final String _localeCode;
  final LicenseTier _requiredTier;

  // Render-path registration seams. A community bundle is usable only when
  // its definition is resolvable by `StageInstanceTile` (which reads
  // `StageRegistry`) **and** a renderer is registered for its id — mirroring
  // how the Pro pack registers into both registries via
  // `extraStageWidgetsProvider`. The `CustomStageWidgetRegistry`
  // registration below remains the tier-gated picker source; these two add
  // the render path that was previously missing for community bundles.
  final DefinitionRegistrar _registerDefinition;
  final DefinitionUnregistrar _unregisterDefinition;
  final RendererRegistrar _registerRenderer;
  final RendererUnregistrar _unregisterRenderer;

  /// All loaded bundles keyed by absolute file path. Distinct from the
  /// registry's id-based view: two bundles can declare the same widget id
  /// (one wins, the other is reported as an error).
  final Map<String, LoadedBundleEntry> _bundlesByPath = {};

  /// The descriptor that is currently registered for a given widget id.
  /// We track it explicitly so reload-replacement remains symmetric.
  final Map<String, String> _widgetIdToBundlePath = {};

  /// Errors keyed by path.
  final Map<String, BundleLoadError> _errorsByPath = {};

  /// Active directory watch subscriptions, keyed by directory path.
  final Map<String, StreamSubscription<FileSystemEvent>> _dirSubs = {};

  /// Debounce timers keyed by file path so a flurry of write events
  /// (rename + truncate + write) collapses into a single load attempt.
  final Map<String, Timer> _debounceTimers = {};

  /// Tracks which watched directory each bundle path was discovered in,
  /// so removal events know which directory the entry belongs to.
  final Map<String, String> _pathToWatchedDir = {};

  static const _debounceDelay = Duration(milliseconds: 300);

  CustomWidgetBundleManagerState _state =
      const CustomWidgetBundleManagerState();

  /// Current state. The Settings panel reads from here inside `build`.
  CustomWidgetBundleManagerState get state => _state;

  /// Loads every persisted bundle path and starts watching every
  /// persisted directory. Safe to call once at app startup.
  Future<void> initialize() async {
    final persisted = _store.read();
    for (final path in persisted.manualBundlePaths) {
      await _loadAndRegisterBundle(path, sourceDirectory: null);
    }
    for (final dir in persisted.watchedDirectories) {
      await _addWatchedDirectoryInternal(dir, persist: false);
    }
    _refreshState();
  }

  /// Manually loads [bundlePath]. Persists the path so it is reloaded on
  /// next launch. Returns the load error (or null on success) so the UI
  /// can surface it inline.
  Future<BundleLoadError?> loadBundle(String bundlePath) async {
    await _store.addManualBundle(bundlePath);
    final result = await _loadAndRegisterBundle(
      bundlePath,
      sourceDirectory: null,
    );
    _refreshState();
    return result;
  }

  /// Removes the bundle at [bundlePath] from the registry and from
  /// persistent storage. No-op if [bundlePath] is unknown.
  Future<void> removeBundle(String bundlePath) async {
    await _store.removeManualBundle(bundlePath);
    _unregisterBundle(bundlePath);
    _refreshState();
  }

  /// Adds [directoryPath] to the watched-directory list, scans it for
  /// existing `.wcrux-widget` files, and starts a watch subscription.
  Future<void> addWatchedDirectory(String directoryPath) async {
    await _store.addWatchedDirectory(directoryPath);
    await _addWatchedDirectoryInternal(directoryPath, persist: true);
    _refreshState();
  }

  /// Removes [directoryPath] from the watched-directory list, cancels its
  /// watch subscription, and unregisters every bundle that was loaded
  /// from it.
  Future<void> removeWatchedDirectory(String directoryPath) async {
    await _store.removeWatchedDirectory(directoryPath);
    final sub = _dirSubs.remove(directoryPath);
    await sub?.cancel();
    _pathToWatchedDir.entries
        .where((entry) => entry.value == directoryPath)
        .map((entry) => entry.key)
        .toList()
        .forEach(_unregisterBundle);
    _refreshState();
  }

  /// Dismisses a load-error entry without affecting the manual-bundle
  /// list. Use this for stale paths that should not be retried.
  void dismissError(String bundlePath) {
    if (_errorsByPath.remove(bundlePath) != null) {
      _refreshState();
    }
  }

  Future<void> _addWatchedDirectoryInternal(
    String directoryPath, {
    required bool persist,
  }) async {
    if (_dirSubs.containsKey(directoryPath)) return;
    // Initial scan.
    final initial = _safeListDirectory(directoryPath);
    for (final filePath in initial) {
      if (!_isBundlePath(filePath)) continue;
      await _loadAndRegisterBundle(filePath, sourceDirectory: directoryPath);
    }
    // Wire up the watcher, ignoring platform errors (some platforms do
    // not support watching network mounts; the Settings panel keeps the
    // entry as a passive list that re-scans on app restart).
    try {
      // Subscription is owned by the manager and cancelled in [dispose] /
      // [removeWatchedDirectory]; the lint can't follow ownership across
      // the map, so suppress its warning here.
      // ignore: cancel_subscriptions
      final sub = _watchFactory(directoryPath).listen(
        (event) => _onDirectoryEvent(event, directoryPath),
        onError: (Object _) {
          /* silently ignore platform watch errors */
        },
      );
      _dirSubs[directoryPath] = sub;
    } on Object catch (e) {
      // Some filesystems do not support watch (e.g. SMB shares) — leave
      // the directory in the persisted list so the next app launch will
      // re-attempt, but otherwise no-op. Record once so "my custom widgets
      // don't auto-reload" reports show the watch never attached.
      _log.warning('Cannot watch widget directory "$directoryPath": $e');
    }
  }

  void _onDirectoryEvent(FileSystemEvent event, String directoryPath) {
    final filePath = event.path;
    if (!_isBundlePath(filePath)) return;
    final timer = _debounceTimers[filePath];
    timer?.cancel();
    _debounceTimers[filePath] = Timer(_debounceDelay, () async {
      _debounceTimers.remove(filePath);
      switch (event.type) {
        case FileSystemEvent.delete:
        case FileSystemEvent.move:
          _unregisterBundle(filePath);
          _refreshState();
        case FileSystemEvent.create:
        case FileSystemEvent.modify:
        default:
          await _loadAndRegisterBundle(
            filePath,
            sourceDirectory: directoryPath,
          );
          _refreshState();
      }
    });
  }

  /// Loads the bundle at [bundlePath] and registers its descriptor.
  /// Returns null on success or the recorded [BundleLoadError] otherwise.
  Future<BundleLoadError?> _loadAndRegisterBundle(
    String bundlePath, {
    required String? sourceDirectory,
  }) async {
    LoadedWidgetBundle? bundle;
    try {
      bundle = await _reader.read(bundlePath);
    } on WidgetBundleException catch (e) {
      final err = BundleLoadError(
        bundlePath: bundlePath,
        kind: e.kind,
        diagnostic: e.diagnostic,
        sourceDirectory: sourceDirectory,
      );
      _errorsByPath[bundlePath] = err;
      // Drop any prior successful registration if the file became invalid.
      _unregisterBundle(bundlePath);
      _errorsByPath[bundlePath] = err;
      return err;
    } on Object catch (e) {
      _log.warning('Failed to load widget bundle "$bundlePath": $e');
      final err = BundleLoadError(
        bundlePath: bundlePath,
        kind: WidgetBundleFailureKind.ioError,
        diagnostic: '$e',
        sourceDirectory: sourceDirectory,
      );
      _errorsByPath[bundlePath] = err;
      _unregisterBundle(bundlePath);
      _errorsByPath[bundlePath] = err;
      return err;
    }

    final widget = ManifestStageWidget(
      manifest: bundle.manifest,
      localeCode: _localeCode,
    );
    final descriptor = CustomStageWidgetDescriptor(
      widget: widget,
      requiredTier: _requiredTier,
      bundleId: bundle.manifest.id,
      bundleVersion: bundle.manifest.version,
    );

    // If a different bundle is already registered for the same widget id,
    // unregister it first — last-loaded wins, mirroring registry semantics.
    final existingPath = _widgetIdToBundlePath[bundle.manifest.id];
    if (existingPath != null && existingPath != bundlePath) {
      _bundlesByPath.remove(existingPath);
    }

    _registry.register(descriptor);
    // Make the bundle usable in the Stage panel, not just listed in the
    // picker: register the definition (so `StageInstanceTile` resolves it)
    // and — for Rive-runtime bundles — a renderer that decodes the bundle's
    // `.riv` bytes and animates the artboard live. Both are replaced on
    // reload and cleared on removal (see [_unregisterBundle]).
    _registerDefinition(widget);
    _registerRendererForBundle(bundle);
    _widgetIdToBundlePath[bundle.manifest.id] = bundlePath;

    _bundlesByPath[bundlePath] = LoadedBundleEntry(
      bundlePath: bundlePath,
      widgetId: bundle.manifest.id,
      widgetVersion: bundle.manifest.version,
      displayName: widget.displayName,
      sourceDirectory: sourceDirectory,
    );
    if (sourceDirectory != null) {
      _pathToWatchedDir[bundlePath] = sourceDirectory;
    }
    _errorsByPath.remove(bundlePath);
    return null;
  }

  /// Registers a live renderer for [bundle] when its runtime is Rive and its
  /// `.riv` bytes are present. The closure captures the parsed manifest and
  /// the extracted bytes; the [CommunityRiveStageRenderer] decodes them,
  /// resolves the default state machine, and drives its inputs from the
  /// manifest bindings. Painter-runtime bundles register no renderer (the
  /// SDK has no community painter runtime); their tile falls back to the
  /// description text via the registered definition.
  void _registerRendererForBundle(LoadedWidgetBundle bundle) {
    final manifest = bundle.manifest;
    if (manifest.runtime != ManifestRuntime.rive) return;
    final riveBytes = bundle.readAsset(manifest.runtimeAssetPath);
    if (riveBytes == null) return;
    _registerRenderer(
      manifest.id,
      (context, instance) => CommunityRiveStageRenderer(
        instance: instance,
        manifest: manifest,
        riveBytes: riveBytes,
      ),
    );
  }

  void _unregisterBundle(String bundlePath) {
    final entry = _bundlesByPath.remove(bundlePath);
    if (entry != null) {
      // Only unregister from the registry when this exact bundle is the
      // one currently winning the id slot — otherwise we would clear an
      // override the user wanted to keep.
      final winning = _widgetIdToBundlePath[entry.widgetId];
      if (winning == bundlePath) {
        _registry.unregister(entry.widgetId);
        _unregisterDefinition(entry.widgetId);
        _unregisterRenderer(entry.widgetId);
        _widgetIdToBundlePath.remove(entry.widgetId);
      }
    }
    _pathToWatchedDir.remove(bundlePath);
    _errorsByPath.remove(bundlePath);
  }

  void _refreshState() {
    _state = CustomWidgetBundleManagerState(
      loadedBundles: _bundlesByPath.values.toList(growable: false),
      errors: _errorsByPath.values.toList(growable: false),
      watchedDirectories: _store.read().watchedDirectories,
    );
    notifyListeners();
  }

  bool _isBundlePath(String filePath) {
    final ext = p.extension(filePath);
    if (ext.isEmpty) return false;
    return ext.substring(1).toLowerCase() ==
        WidgetBundleSpec.fileExtension.toLowerCase();
  }

  List<String> _safeListDirectory(String path) {
    try {
      return _listFactory(path);
    } on Object catch (_) {
      return const [];
    }
  }

  @override
  void dispose() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    for (final sub in _dirSubs.values) {
      unawaited(sub.cancel());
    }
    _dirSubs.clear();
    super.dispose();
  }
}
