// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The Rive runtime exposes input mutation through `StateMachine.number /
// boolean / trigger`, which the SDK marks `@Deprecated` in favor of data
// binding. The Stage Pro SDK contract is built on
// state-machine inputs by name — see RiveRuntimeStateMachineHost for the
// rationale. The deprecation is suppressed at file scope.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/features/stage/runtime/bundled_stage_asset_loader.dart';
import 'package:wavecrux/features/stage/runtime/custom_stage_widget_runtime_descriptor.dart';
import 'package:wavecrux/features/stage/runtime/manifest_state_machine_validator.dart';
import 'package:wavecrux/features/stage/runtime/rive_backed_animation_controller.dart';
import 'package:wavecrux/features/stage/runtime/rive_runtime_state_machine_host.dart';
import 'package:wavecrux/features/stage/sdk/manifest/manifest_yaml_parser.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';
import 'package:wavecrux/features/stage/widgets/tachometer/domain/tachometer_config.dart';
import 'package:wavecrux/features/stage/widgets/tachometer/tachometer_input_mapper.dart';
import 'package:wavecrux/features/stage/widgets/tachometer/tachometer_stage_widget.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Asset-bundle path of the manifest the renderer parses on first build.
/// Mirrors `pubspec.yaml`'s asset declaration for the Rive runtime.
const _manifestAssetPath = 'assets/stage/widgets/rive/manifest.yaml';

/// Asset-bundle prefix prepended to the manifest's
/// `runtime_asset_path`. The manifest's path is bundle-archive-relative
/// (`runtime/tachometer.riv`); the curated Pro pack ships the same
/// payload under `assets/stage/widgets/rive/` in the Flutter asset
/// bundle, so the runtime path resolves identically with this prefix.
const _runtimeAssetPrefix = 'assets/stage/widgets/rive/';

/// Where a widget that failed to load says why. The placeholder the user sees
/// names no cause, and `developer.log` emits nothing from a release build.
final _log = Logger('wavecrux.stage.tachometer');

/// Renders an instance of [TachometerStageWidget] in the Stage panel.
///
/// Loads the bundled manifest + Rive runtime asset on the first build,
/// constructs a [rive.StateMachinePainter] that drives the state machine
/// per frame, wraps the resulting state machine in a
/// [RiveRuntimeStateMachineHost] / [RiveBackedAnimationController], and
/// pushes normalized values through the controller whenever the cursor
/// or bound signal data changes. The artboard is mounted via
/// [rive.RiveArtboardWidget] so the actual painting happens inside the
/// Rive widget tree (the controller's role is input routing, not
/// rendering).
///
/// The value-mapping layer — normalization, full-scale clamping,
/// X/Z handling, missing-binding detection — lives in
/// [TachometerInputMapper]. The renderer is the thin Rive-coupled glue
/// that owns asset loading, state-machine wiring, controller lifetime,
/// and the per-frame `controller.setInput` writes.
///
/// Failure modes (placeholder `.riv`, missing state machine, missing
/// declared input, malformed manifest) all surface the localized
/// "Widget failed to load" placeholder. The first failure on a given
/// instance also logs once to [_log] so developers
/// running the Pro overlay see why the gauge isn't rendering — the
/// most common case during development is the zero-byte placeholder
/// the designer hasn't replaced yet.
class TachometerStageRenderer extends ConsumerStatefulWidget {
  /// Wraps an instance dropped onto a Stage panel. [widget] is the
  /// const [TachometerStageWidget] definition the picker registered;
  /// the renderer only consults it for the schema declaration the
  /// bindings pane has already applied to [instance.configuration].
  const TachometerStageRenderer({
    required this.instance,
    required this.widget,
    super.key,
  });

  /// The session-persisted [StageInstance] carrying signal bindings
  /// and per-instance configuration.
  final StageInstance instance;

  /// The const definition. Held for parity with sibling Pro pack
  /// renderers; the renderer reads from [instance].
  final TachometerStageWidget widget;

  @override
  ConsumerState<TachometerStageRenderer> createState() =>
      _TachometerStageRendererState();
}

class _TachometerStageRendererState
    extends ConsumerState<TachometerStageRenderer> {
  StageWidgetManifest? _manifest;
  rive.File? _file;
  rive.Artboard? _artboard;
  rive.StateMachinePainter? _painter;
  // The host wraps the resolved Rive state machine and is consumed by
  // the controller. Disposing the controller drops the host's
  // input-handle cache. We don't keep a renderer-local reference to
  // the host because every read/write the renderer performs goes
  // through [_controller] — the controller's setInput is the
  // type-routing surface of the Rive binding contract.
  RiveBackedAnimationController? _controller;
  StageWidgetRuntimeException? _loadError;
  bool _loading = true;
  bool _warningLogged = false;

  /// Last samples we pushed for each binding. Lets us skip redundant
  /// writes when build runs but the cursor / signal data is unchanged.
  final Map<String, RawSignalSample?> _lastPushedSamples = {};

  @override
  void initState() {
    super.initState();
    unawaited(_initializeRuntime());
  }

  Future<void> _initializeRuntime() async {
    try {
      // Parse the manifest from the Flutter asset bundle. The manifest
      // is the source of truth for state-machine name, signal bindings,
      // and the default normalizer pipeline.
      final manifestSource = await loadBundledStageAssetString(
        _manifestAssetPath,
      );
      final manifest = parseStageWidgetManifest(manifestSource);
      // Resolve the runtime asset relative to the same asset prefix the
      // pubspec wires up. The manifest's `runtime_asset_path` mirrors
      // the bundle-archive layout (`runtime/tachometer.riv`), so the
      // committed `.wcrux-widget` artifact and the live curated path
      // share one set of relative paths.
      final assetPath = '$_runtimeAssetPrefix${manifest.runtimeAssetPath}';
      final loaded = await loadRiveFileForStageWidget(assetPath: assetPath);
      // Mount a StateMachinePainter that resolves the named state
      // machine and provides it back via the withStateMachine
      // callback. The callback owns the host + controller wiring; if
      // the named state machine doesn't exist on the artboard, the
      // callback never fires and the renderer surfaces the fallback
      // placeholder via the StateMachinePainter's internal null state.
      final painter = rive.RivePainter.stateMachine(
        stateMachineName: 'Tachometer',
        withStateMachine: _onStateMachineReady,
      );

      if (!mounted) {
        loaded.file.dispose();
        painter.dispose();
        return;
      }
      setState(() {
        _manifest = manifest;
        _file = loaded.file;
        _artboard = loaded.artboard;
        _painter = painter;
        _loading = false;
      });
    } on StageWidgetRuntimeException catch (e) {
      _surfaceLoadError(e);
    } on Object catch (e, stack) {
      _surfaceLoadError(
        StageWidgetRuntimeException(
          userMessageKey: StageWidgetRuntimeFailureKind.generic,
          diagnostic: 'Tachometer init failed: $e',
        ),
        stack: stack,
      );
    }
  }

  /// StateMachinePainter callback. Wraps the resolved state machine in
  /// the production host + the SDK's input-routing controller, then
  /// validates that every required manifest binding has a matching
  /// state-machine input. A misbinding turns the renderer into the
  /// "Widget failed to load" placeholder rather than silently dropping
  /// inputs.
  void _onStateMachineReady(rive.StateMachine stateMachine) {
    final manifest = _manifest;
    if (manifest == null) return;
    final host = RiveRuntimeStateMachineHost(stateMachine: stateMachine);
    final controller = RiveBackedAnimationController(host: host);
    // Delegate the required-binding check to the pure-Dart
    // manifest-vs-host validator. The validator handles per-binding
    // iteration and the StageWidgetRuntimeException construction so the
    // renderer only deals with the success / failure dichotomy.
    final validation = validateManifestAgainstHost(
      manifest: manifest,
      host: host,
    );
    if (validation is ManifestHostValidationMismatch) {
      controller.dispose();
      _surfaceLoadError(validation.exception);
      return;
    }
    controller.play();
    if (!mounted) {
      controller.dispose();
      return;
    }
    _controller = controller;
    // Push initial samples so the gauge starts at the right needle
    // position even before the user moves the cursor.
    _pushSamplesForCurrentState();
  }

  void _surfaceLoadError(
    StageWidgetRuntimeException error, {
    StackTrace? stack,
  }) {
    if (!_warningLogged) {
      _warningLogged = true;
      _log.severe(
        'Tachometer widget failed to initialize: ${error.diagnostic}',
        error,
        stack,
      );
    }
    if (!mounted) return;
    setState(() {
      _loadError = error;
      _loading = false;
    });
  }

  @override
  void dispose() {
    // Dispose order matters: the controller owns the host (drops cached
    // input handles) and the painter owns the state machine. Disposing
    // the controller first ensures we don't leave dangling handles into
    // a state machine the painter is about to dispose.
    _controller?.dispose();
    _painter?.dispose();
    _file?.dispose();
    _controller = null;
    _painter = null;
    _file = null;
    _artboard = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);

    if (_loading) {
      return _buildPadded(const Center(child: SizedBox.shrink()));
    }
    if (_loadError != null) {
      return _buildPadded(
        _Placeholder(message: _failureMessage(l10n, _loadError!)),
      );
    }
    final artboard = _artboard;
    final painter = _painter;
    if (artboard == null || painter == null) {
      return _buildPadded(
        _Placeholder(message: l10n.tachometerNotReady),
      );
    }
    // Watch cursor + bindings; rebuilds whenever the user scrubs or a
    // new file loads. The provider watches are side-effect-free — the
    // values they return are also consulted further down to build the
    // RawSignalSample we push to the controller.
    final config = TachometerConfig.fromMap(widget.instance.configuration);
    final bindings = widget.instance.signalBindings;
    final rpmSnapshot = ref.watch(stageBoundSignalProvider(bindings['rpm']));
    final redlineSnapshot = ref.watch(
      stageBoundSignalProvider(bindings['redline']),
    );
    final shiftSnapshot = ref.watch(
      stageBoundSignalProvider(bindings['shift']),
    );
    final source = ref.watch(waveformSourceProvider).value;
    final cursorState = ref.watch(cursorStateProvider);

    // Pure-Dart value mapping. Returns the per-input NormalizedValues
    // (or `null` for held-stale pins) and the set of missing bindings.
    final mapper = TachometerInputMapper(config: config, manifest: _manifest);
    final missing = mapper.missingBindings(bindings);
    if (missing.isNotEmpty) {
      return _buildPadded(
        _Placeholder(
          message: l10n.tachometerUnbound(missing.join(', ')),
        ),
      );
    }
    if (source == null) {
      return _buildPadded(
        _Placeholder(message: l10n.tachometerNoFile),
      );
    }

    // Push the latest values into the Rive state machine. Driven from
    // build (rather than from a post-frame callback) because the writes
    // are cheap, idempotent against duplicate samples, and the painter
    // handles the resulting onInputChanged → notifyListeners → repaint
    // cascade itself.
    final cursorTicks = cursorState.primaryCursorTime ?? source.startTime;
    _pushSnapshot(
      bindingName: 'rpm',
      snapshot: rpmSnapshot,
      cursorTicks: cursorTicks,
      mapper: mapper,
    );
    _pushSnapshot(
      bindingName: 'redline',
      snapshot: redlineSnapshot,
      cursorTicks: cursorTicks,
      mapper: mapper,
    );
    _pushSnapshot(
      bindingName: 'shift',
      snapshot: shiftSnapshot,
      cursorTicks: cursorTicks,
      mapper: mapper,
    );

    return _buildPadded(
      RepaintBoundary(
        child: rive.RiveArtboardWidget(
          artboard: artboard,
          painter: painter,
        ),
      ),
    );
  }

  /// Same write path used at startup — pushes whatever samples the
  /// providers already have. Called once after the controller is built
  /// so the gauge starts in the right place before the next build.
  void _pushSamplesForCurrentState() {
    if (!mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final config = TachometerConfig.fromMap(widget.instance.configuration);
    final bindings = widget.instance.signalBindings;
    final source = container.read(waveformSourceProvider).value;
    if (source == null) return;
    final cursorTicks =
        container.read(cursorStateProvider).primaryCursorTime ??
        source.startTime;
    final mapper = TachometerInputMapper(config: config, manifest: _manifest);
    for (final name in tachometerBindingNames) {
      final snapshot = container.read(stageBoundSignalProvider(bindings[name]));
      _pushSnapshot(
        bindingName: name,
        snapshot: snapshot,
        cursorTicks: cursorTicks,
        mapper: mapper,
      );
    }
  }

  /// Translates a [StageSignalSnapshot] to a [RawSignalSample] via the
  /// pure-Dart mapper, then routes the result through the controller.
  /// Skipping logic: identical samples are not re-pushed.
  void _pushSnapshot({
    required String bindingName,
    required StageSignalSnapshot snapshot,
    required int cursorTicks,
    required TachometerInputMapper mapper,
  }) {
    final controller = _controller;
    if (controller == null) return;
    final raw = TachometerInputMapper.snapshotToRawSample(
      snapshot,
      cursorTicks,
    );
    if (raw == null) {
      // Unbound / loading / unknown — leave the input alone. The Rive
      // state machine retains the last value we pushed (or the
      // artboard's authoring default if we've never pushed).
      _lastPushedSamples[bindingName] = null;
      return;
    }
    if (_lastPushedSamples[bindingName] == raw) return;
    _lastPushedSamples[bindingName] = raw;
    final normalizer = mapper.normalizerFor(bindingName);
    final value = normalizer != null
        ? normalizer.normalize(raw)
        : TachometerInputMapper.defaultNormalize(raw);
    controller.setInput(bindingName, value);
  }

  String _failureMessage(L10N l10n, StageWidgetRuntimeException error) {
    switch (error.userMessageKey) {
      case StageWidgetRuntimeFailureKind.assetMissing:
        return l10n.tachometerAssetMissing;
      case StageWidgetRuntimeFailureKind.assetMalformed:
        return l10n.tachometerAssetMalformed;
      case StageWidgetRuntimeFailureKind.stateMachineMissing:
        return l10n.tachometerStateMachineMissing;
      case StageWidgetRuntimeFailureKind.inputUndeclared:
        return l10n.tachometerInputUndeclared;
      case StageWidgetRuntimeFailureKind.generic:
        return l10n.tachometerLoadFailed;
    }
  }

  Widget _buildPadded(Widget body) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: body,
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
