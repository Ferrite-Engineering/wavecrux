// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The Rive 0.14 SDK marks the input-routing API
// (`StateMachine.number/boolean/trigger`) `@Deprecated` in favor of data
// binding. The Stage Pro SDK contract is built on
// state-machine inputs by name — the documented binding contract that
// widget authors target. We deliberately consume the still-supported input
// API and accept the deprecation warning at file scope.
// ignore_for_file: deprecated_member_use

import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle;
import 'package:rive/rive.dart' as rive;
import 'package:wavecrux/features/stage/runtime/bundled_stage_asset_loader.dart';
import 'package:wavecrux/features/stage/runtime/custom_stage_widget_runtime_descriptor.dart';
import 'package:wavecrux/features/stage/runtime/rive_state_machine_host.dart';

/// Production [RiveStateMachineHost] backed by the `rive` package's
/// `StateMachine` runtime.
///
/// `RiveBackedAnimationController` (the type-routing layer that consumes
/// `StageWidgetAnimationController.setInput`) is library-agnostic — it
/// delegates every read/write to the [RiveStateMachineHost] interface.
/// Tests inject a fake host. Production wires this class, which wraps a
/// real `rive.StateMachine` obtained from a loaded `.riv` file.
///
/// Lifetime model:
///
/// - The Rive runtime owns the `StateMachine` object only as long as the
///   `StateMachinePainter` that created it is alive. Disposing the painter
///   disposes the state machine. This host therefore does **not** call
///   `_stateMachine.dispose()` from its own [dispose] — doing so would
///   double-free the same native handle when the painter is disposed
///   moments later. The renderer that wires both is responsible for
///   ordering: dispose the host first (drops cached input handles), then
///   dispose the painter (which disposes the state machine).
/// - [play] / [pause] are no-ops. Playback in Rive 0.14 is driven by the
///   widget tree's ticker (see `StateMachinePainter.advance` in the rive
///   package), not by the state machine itself. The renderer mounts a
///   `RiveArtboardWidget` whose painter ticks the state machine; the host
///   only routes input writes.
class RiveRuntimeStateMachineHost implements RiveStateMachineHost {
  /// Wraps an existing [stateMachine]. The caller retains ownership of the
  /// state machine's lifecycle — see the class doc for why the host does
  /// not dispose it.
  RiveRuntimeStateMachineHost({required rive.StateMachine stateMachine})
    : _stateMachine = stateMachine;

  final rive.StateMachine _stateMachine;
  final Map<String, _CachedInput> _cache = {};
  bool _disposed = false;

  @override
  String get stateMachineName => _stateMachine.name;

  @override
  bool hasInput(String name) => _resolve(name) != null;

  @override
  RiveInputType? inputType(String name) => _resolve(name)?.type;

  @override
  bool setNumber(String name, double value) {
    final entry = _resolve(name);
    final n = entry?.number;
    if (n == null) return false;
    n.value = value;
    return true;
  }

  @override
  bool setBoolean(String name, {required bool value}) {
    final entry = _resolve(name);
    final b = entry?.boolean;
    if (b == null) return false;
    b.value = value;
    return true;
  }

  @override
  bool fireTrigger(String name) {
    final entry = _resolve(name);
    final t = entry?.trigger;
    if (t == null) return false;
    t.fire();
    return true;
  }

  @override
  void play() {
    // Playback (advance/draw cycle) is owned by the Rive widget tree's
    // ticker. The host has nothing to play — it only writes inputs.
  }

  @override
  void pause() {
    // See [play].
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Drop our handle references. The Input objects are owned by the
    // state machine; disposing them here would double-free when the
    // painter that created the state machine disposes itself.
    _cache.clear();
  }

  _CachedInput? _resolve(String name) {
    if (_disposed) return null;
    final cached = _cache[name];
    if (cached != null) return cached;
    final number = _stateMachine.number(name);
    if (number != null) {
      final entry = _CachedInput.number(number);
      _cache[name] = entry;
      return entry;
    }
    final boolean = _stateMachine.boolean(name);
    if (boolean != null) {
      final entry = _CachedInput.boolean(boolean);
      _cache[name] = entry;
      return entry;
    }
    final trigger = _stateMachine.trigger(name);
    if (trigger != null) {
      final entry = _CachedInput.trigger(trigger);
      _cache[name] = entry;
      return entry;
    }
    return null;
  }
}

/// Loads bytes for the `.riv` asset declared by a manifest's
/// `runtime_asset_path`, decodes the Rive file, and resolves the named
/// state machine on the named (or default) artboard.
///
/// Throws [StageWidgetRuntimeException] with a discriminator the renderer
/// maps to a localized "Widget failed to load" placeholder:
///
/// - [StageWidgetRuntimeFailureKind.assetMissing] — asset bytes could not
///   be loaded, or the loaded bytes are empty (the placeholder-`.riv`
///   case during development before a designer has authored the file).
/// - [StageWidgetRuntimeFailureKind.assetMalformed] — bytes did not decode
///   as a Rive file.
/// - [StageWidgetRuntimeFailureKind.stateMachineMissing] — the named
///   artboard or state machine is absent from the file.
///
/// Returns the parsed [LoadedRiveFile] which carries the [rive.File] (so
/// the caller can dispose it), the [rive.Artboard], and lookup metadata.
/// The caller is responsible for constructing the `StateMachinePainter`
/// (or equivalent) that drives the state machine from the artboard, then
/// wrapping the resulting state machine in [RiveRuntimeStateMachineHost].
Future<LoadedRiveFile> loadRiveFileForStageWidget({
  required String assetPath,
  String? artboardName,
  AssetBundle? bundle,
}) async {
  final ByteData byteData;
  try {
    // Resolve the open-core (bare key) vs. Pro-overlay
    // (packages/wavecrux/) asset-key difference — see
    // [loadBundledStageAssetBytes].
    byteData = await loadBundledStageAssetBytes(assetPath, bundle: bundle);
  } on Object catch (e) {
    throw StageWidgetRuntimeException(
      userMessageKey: StageWidgetRuntimeFailureKind.assetMissing,
      diagnostic: 'Failed to load Rive asset "$assetPath": $e',
    );
  }
  final bytes = byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );
  return decodeRiveFileForStageWidget(
    bytes: bytes,
    artboardName: artboardName,
    sourceLabel: assetPath,
    emptyHint:
        'Rive asset "$assetPath" is empty. This is the placeholder '
        'shipped with the Pro overlay; the .riv must be authored in the '
        'Rive editor (see assets/stage/widgets/rive/README.md).',
  );
}

/// Decodes an in-memory `.riv` byte buffer (e.g. the runtime asset extracted
/// from a community `.wcrux-widget` bundle, which lives on the filesystem
/// rather than in `rootBundle`) and resolves its artboard.
///
/// This is the filesystem / bytes-based counterpart of
/// [loadRiveFileForStageWidget]: the asset-bundle loader resolves bytes from
/// `rootBundle` (curated, pubspec-declared assets), while community bundles
/// already hold their extracted `.riv` bytes in memory
/// (`LoadedWidgetBundle.readAsset`) and feed them here directly.
///
/// The empty-bytes guard runs **before** `RiveNative.init()` so a malformed /
/// placeholder bundle surfaces [StageWidgetRuntimeFailureKind.assetMissing]
/// without engaging the native runtime — that path is unit-testable in
/// headless `flutter test` where the rive_native FFI symbols are unavailable.
/// Everything past the guard requires the native runtime and therefore only
/// runs under `integration_test` / on a real device.
///
/// Throws [StageWidgetRuntimeException] with the same discriminators as
/// [loadRiveFileForStageWidget]. [sourceLabel] names the byte source in
/// diagnostics (a bundle path or asset key); [emptyHint], when supplied,
/// overrides the default empty-buffer diagnostic.
Future<LoadedRiveFile> decodeRiveFileForStageWidget({
  required Uint8List bytes,
  String? artboardName,
  String sourceLabel = 'bundle .riv',
  String? emptyHint,
}) async {
  if (bytes.isEmpty) {
    throw StageWidgetRuntimeException(
      userMessageKey: StageWidgetRuntimeFailureKind.assetMissing,
      diagnostic: emptyHint ?? 'Rive runtime asset "$sourceLabel" is empty.',
    );
  }
  final initialized = await rive.RiveNative.init();
  if (!initialized) {
    throw const StageWidgetRuntimeException(
      userMessageKey: StageWidgetRuntimeFailureKind.generic,
      diagnostic:
          'RiveNative failed to initialize; Stage Pro Rive widgets cannot '
          'load on this platform.',
    );
  }
  final file = await _decodeRiveBytes(bytes, sourceLabel);
  if (file == null) {
    throw StageWidgetRuntimeException(
      userMessageKey: StageWidgetRuntimeFailureKind.assetMalformed,
      diagnostic: 'Rive asset "$sourceLabel" did not decode as a Rive file.',
    );
  }
  final artboard = artboardName != null
      ? file.artboard(artboardName)
      : file.defaultArtboard();
  if (artboard == null) {
    file.dispose();
    throw StageWidgetRuntimeException(
      userMessageKey: StageWidgetRuntimeFailureKind.stateMachineMissing,
      diagnostic: artboardName == null
          ? 'Rive file "$sourceLabel" has no default artboard.'
          : 'Rive file "$sourceLabel" has no artboard named '
                '"$artboardName".',
    );
  }
  return LoadedRiveFile(file: file, artboard: artboard, assetPath: sourceLabel);
}

Future<rive.File?> _decodeRiveBytes(Uint8List bytes, String assetPath) async {
  try {
    return await rive.File.decode(bytes, riveFactory: rive.Factory.flutter);
  } on Object catch (e) {
    throw StageWidgetRuntimeException(
      userMessageKey: StageWidgetRuntimeFailureKind.assetMalformed,
      diagnostic: 'Rive asset "$assetPath" did not decode: $e',
    );
  }
}

/// Bundle of resources produced by [loadRiveFileForStageWidget]. The
/// renderer keeps a reference to [file] so it can dispose it on widget
/// teardown; the state machine itself is created via the painter the
/// renderer mounts on [artboard].
class LoadedRiveFile {
  /// Constructs a bundle carrying the parsed Rive file, the resolved
  /// artboard, and the asset path used to produce them (handy for
  /// diagnostics).
  const LoadedRiveFile({
    required this.file,
    required this.artboard,
    required this.assetPath,
  });

  /// The decoded Rive file. Caller must dispose it when teardown.
  final rive.File file;

  /// The artboard the renderer should mount.
  final rive.Artboard artboard;

  /// Source asset path, retained for log messages.
  final String assetPath;
}

class _CachedInput {
  _CachedInput.number(rive.NumberInput n)
    : type = RiveInputType.number,
      number = n,
      boolean = null,
      trigger = null;

  _CachedInput.boolean(rive.BooleanInput b)
    : type = RiveInputType.boolean,
      number = null,
      boolean = b,
      trigger = null;

  _CachedInput.trigger(rive.TriggerInput t)
    : type = RiveInputType.trigger,
      number = null,
      boolean = null,
      trigger = t;

  final RiveInputType type;
  final rive.NumberInput? number;
  final rive.BooleanInput? boolean;
  final rive.TriggerInput? trigger;
}
