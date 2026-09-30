// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wavecrux/domain/models/stage_instance.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/stage/providers/stage_signal_provider.dart';
import 'package:wavecrux/features/stage/runtime/custom_stage_widget_runtime_descriptor.dart';
import 'package:wavecrux/features/stage/runtime/generic_manifest_input_mapper.dart';
import 'package:wavecrux/features/stage/runtime/manifest_state_machine_validator.dart';
import 'package:wavecrux/features/stage/runtime/rive_backed_animation_controller.dart';
import 'package:wavecrux/features/stage/runtime/rive_runtime_state_machine_host.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Where a widget that failed to load says why. The placeholder the user sees
/// names no cause, and `developer.log` emits nothing from a release build.
final _log = Logger('wavecrux.stage.community');

/// Renders a live, animating instance of a community `.wcrux-widget` Rive
/// bundle in a Stage panel.
///
/// This is the generic counterpart of `TachometerStageRenderer`: where the
/// Tachometer hard-codes its state-machine name (`"Tachometer"`) and its
/// `rpm`/`redline`/`shift` pins, this renderer drives **any** manifest. It:
///
/// - Decodes the bundle's extracted `.riv` [riveBytes] (which come from the
///   filesystem-loaded archive, not `rootBundle`) via
///   [decodeRiveFileForStageWidget].
/// - Mounts the artboard's **default** state machine (the manifest has no
///   state-machine-name field; the author may name it anything).
/// - Wraps the resolved state machine in [RiveRuntimeStateMachineHost] +
///   [RiveBackedAnimationController] and validates every required manifest
///   binding against the host's inputs via [validateManifestAgainstHost].
/// - Drives `setInput` per frame from the manifest's signal bindings and
///   (optional) normalizer parameters via [GenericManifestInputMapper].
///
/// Failure modes (empty/malformed `.riv`, missing default state machine,
/// a required input the state machine does not expose) all surface the
/// localized "Widget failed to load" placeholder — never a crash. The first
/// failure on a given instance logs once to [_log].
///
/// **Headless note:** the rive_native FFI runtime is unavailable in
/// `flutter test`, so `RiveNative.init()` (inside [decodeRiveFileForStageWidget])
/// cannot resolve its `init` symbol and the artboard never mounts there.
/// Real live-render coverage is `integration_test` + the manual verification
/// pass (Open Core verification §10); the pure-Dart mapping / validation /
/// registration pieces are unit-tested directly.
class CommunityRiveStageRenderer extends ConsumerStatefulWidget {
  /// Wraps a [StageInstance] dropped onto a Stage panel together with the
  /// [manifest] parsed from its bundle and the bundle's extracted Rive
  /// runtime [riveBytes].
  const CommunityRiveStageRenderer({
    required this.instance,
    required this.manifest,
    required this.riveBytes,
    super.key,
  });

  /// The session-persisted instance carrying signal bindings and config.
  final StageInstance instance;

  /// Parsed bundle manifest — source of truth for the binding list and the
  /// per-binding normalizer pipeline.
  final StageWidgetManifest manifest;

  /// The bundle's extracted `.riv` bytes (from `LoadedWidgetBundle.readAsset`).
  final Uint8List riveBytes;

  @override
  ConsumerState<CommunityRiveStageRenderer> createState() =>
      _CommunityRiveStageRendererState();
}

class _CommunityRiveStageRendererState
    extends ConsumerState<CommunityRiveStageRenderer> {
  rive.File? _file;
  rive.Artboard? _artboard;
  rive.StateMachinePainter? _painter;
  RiveBackedAnimationController? _controller;
  StageWidgetRuntimeException? _loadError;
  bool _loading = true;
  bool _warningLogged = false;

  /// Last raw sample pushed per binding — lets us skip redundant writes when
  /// build re-runs but the cursor / signal data is unchanged.
  final Map<String, RawSignalSample?> _lastPushedSamples = {};

  @override
  void initState() {
    super.initState();
    unawaited(_initializeRuntime());
  }

  Future<void> _initializeRuntime() async {
    try {
      final loaded = await decodeRiveFileForStageWidget(
        bytes: widget.riveBytes,
        sourceLabel: widget.manifest.id,
      );
      // Resolve the artboard's DEFAULT state machine — the manifest declares
      // no state-machine name, so the author may name it anything. Passing a
      // null name selects the default (see StateMachinePainter).
      final painter = rive.RivePainter.stateMachine(
        withStateMachine: _onStateMachineReady,
      );
      if (!mounted) {
        loaded.file.dispose();
        painter.dispose();
        return;
      }
      setState(() {
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
          diagnostic:
              'Community widget "${widget.manifest.id}" init failed: $e',
        ),
        stack: stack,
      );
    }
  }

  /// StateMachinePainter callback. Wraps the resolved state machine in the
  /// production host + the SDK's input-routing controller, then validates
  /// that every required manifest binding has a matching state-machine
  /// input. A misbinding turns the renderer into the localized
  /// "Widget failed to load" placeholder rather than silently dropping
  /// inputs.
  void _onStateMachineReady(rive.StateMachine stateMachine) {
    final host = RiveRuntimeStateMachineHost(stateMachine: stateMachine);
    final controller = RiveBackedAnimationController(host: host);
    final validation = validateManifestAgainstHost(
      manifest: widget.manifest,
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
    _pushSamplesForCurrentState();
  }

  void _surfaceLoadError(
    StageWidgetRuntimeException error, {
    StackTrace? stack,
  }) {
    if (!_warningLogged) {
      _warningLogged = true;
      _log.severe(
        'Community widget "${widget.manifest.id}" failed to initialize: '
        '${error.diagnostic}',
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
    // Dispose order matters: the controller owns the host (drops cached input
    // handles) and the painter owns the state machine. Dispose the controller
    // first so we don't leave dangling handles into a state machine the
    // painter is about to dispose.
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
      return _padded(_Placeholder(message: l10n.customStageWidgetInitializing));
    }
    if (_loadError != null) {
      return _padded(_FailedPlaceholder(error: _loadError!));
    }
    final artboard = _artboard;
    final painter = _painter;
    if (artboard == null || painter == null) {
      return _padded(
        _Placeholder(message: l10n.customStageWidgetInitializing),
      );
    }

    final mapper = GenericManifestInputMapper(manifest: widget.manifest);
    final bindings = widget.instance.signalBindings;

    // Watch every bound signal + source + cursor up front so the tile
    // rebuilds whenever the user scrubs or a new file loads.
    final snapshots = <String, StageSignalSnapshot>{
      for (final binding in widget.manifest.signalBindings)
        binding.name: ref.watch(
          stageBoundSignalProvider(bindings[binding.name]),
        ),
    };
    final source = ref.watch(waveformSourceProvider).value;
    final cursorState = ref.watch(cursorStateProvider);

    final missing = mapper.missingRequiredBindings(bindings);
    if (missing.isNotEmpty) {
      return _padded(
        _Placeholder(
          message: l10n.customStageWidgetUnbound(missing.join(', ')),
        ),
      );
    }
    if (source == null) {
      return _padded(
        _Placeholder(message: l10n.customStageWidgetNoFile),
      );
    }

    final cursorTicks = cursorState.primaryCursorTime ?? source.startTime;
    for (final binding in widget.manifest.signalBindings) {
      _pushSnapshot(
        bindingName: binding.name,
        snapshot: snapshots[binding.name]!,
        cursorTicks: cursorTicks,
        mapper: mapper,
      );
    }

    return _padded(
      RepaintBoundary(
        child: rive.RiveArtboardWidget(artboard: artboard, painter: painter),
      ),
    );
  }

  /// Same write path used at startup — pushes whatever samples the providers
  /// already have so the artboard starts in the right state before the next
  /// build.
  void _pushSamplesForCurrentState() {
    if (!mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final bindings = widget.instance.signalBindings;
    final source = container.read(waveformSourceProvider).value;
    if (source == null) return;
    final cursorTicks =
        container.read(cursorStateProvider).primaryCursorTime ??
        source.startTime;
    final mapper = GenericManifestInputMapper(manifest: widget.manifest);
    for (final binding in widget.manifest.signalBindings) {
      final snapshot = container.read(
        stageBoundSignalProvider(bindings[binding.name]),
      );
      _pushSnapshot(
        bindingName: binding.name,
        snapshot: snapshot,
        cursorTicks: cursorTicks,
        mapper: mapper,
      );
    }
  }

  void _pushSnapshot({
    required String bindingName,
    required StageSignalSnapshot snapshot,
    required int cursorTicks,
    required GenericManifestInputMapper mapper,
  }) {
    final controller = _controller;
    if (controller == null) return;
    final raw = GenericManifestInputMapper.snapshotToRawSample(
      snapshot,
      cursorTicks,
    );
    if (raw == null) {
      // Unbound / loading / unknown — hold the Rive input's prior value.
      _lastPushedSamples[bindingName] = null;
      return;
    }
    if (_lastPushedSamples[bindingName] == raw) return;
    _lastPushedSamples[bindingName] = raw;
    final value = mapper.inputFor(bindingName, snapshot, cursorTicks);
    if (value == null) return;
    controller.setInput(bindingName, value);
  }

  Widget _padded(Widget body) =>
      Padding(padding: const EdgeInsets.all(6), child: body);
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

class _FailedPlaceholder extends StatelessWidget {
  const _FailedPlaceholder({required this.error});

  final StageWidgetRuntimeException error;

  @override
  Widget build(BuildContext context) {
    final l10n = L10N.of(context);
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: l10n.customStageWidgetLoadFailedTooltip(
                error.diagnostic,
              ),
              triggerMode: TooltipTriggerMode.manual,
              child: Icon(
                Icons.info_outline,
                color: theme.colorScheme.error,
                size: 18,
                semanticLabel: l10n.customStageWidgetLoadFailedTooltip(
                  error.diagnostic,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.customStageWidgetLoadFailed,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
