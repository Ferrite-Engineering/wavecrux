// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';
import 'package:wavecrux/features/stage/sdk/normalization/linear_normalizer.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';
import 'package:wavecrux/features/stage/sdk/normalization/value_normalizer.dart';
import 'package:wavecrux/features/stage/widgets/tachometer/domain/tachometer_config.dart';

/// Pin names the Tachometer widget binds to, in canonical manifest order.
///
/// The renderer and the mapper iterate over these names to push samples;
/// keeping the list here (rather than as scattered string literals in the
/// renderer) makes the contract explicit and refactor-friendly.
const tachometerBindingNames = <String>['rpm', 'redline', 'shift'];

/// Computed Rive state-machine input payload derived from one frame's
/// worth of signal snapshots.
///
/// One [TachometerInputMapper] invocation produces one [TachometerInputs]
/// instance. Each `*Input` field is `null` when the corresponding pin's
/// snapshot is in a non-value lifecycle state ([StageSignalSnapshotKind]
/// other than `value`) — the renderer interprets `null` as "leave the
/// Rive input alone; hold its prior value" per the Rive binding contract.
///
/// [missingBindings] enumerates bindings whose `signalRef` is empty or
/// absent; the renderer surfaces them via the localized "unbound" panel
/// rather than as a Rive write.
///
/// Pure value type — no Flutter or Rive imports, immutable, equatable.
@immutable
class TachometerInputs {
  /// Constructs a snapshot bundle. `null` per-input means "no fresh value
  /// to write this frame"; `missingBindings` is the set of pin names that
  /// are unbound at the binding-map level.
  const TachometerInputs({
    this.rpmInput,
    this.redlineInput,
    this.shiftInput,
    this.missingBindings = const <String>{},
  });

  /// Normalized payload to write to the Rive `rpm` Number input, or
  /// `null` to hold the prior value.
  final NormalizedValue? rpmInput;

  /// Normalized payload to write to the Rive `redline` Boolean input,
  /// or `null` to hold the prior value.
  final NormalizedValue? redlineInput;

  /// Normalized payload to write to the Rive `shift` Boolean input, or
  /// `null` to hold the prior value.
  final NormalizedValue? shiftInput;

  /// Pin names whose `signalRef` is empty / absent.
  final Set<String> missingBindings;

  /// True when at least one of the three required bindings is missing.
  bool get hasMissingBindings => missingBindings.isNotEmpty;

  /// Convenience accessor — returns the field for [bindingName] or
  /// `null` when no input should be written.
  NormalizedValue? inputFor(String bindingName) {
    switch (bindingName) {
      case 'rpm':
        return rpmInput;
      case 'redline':
        return redlineInput;
      case 'shift':
        return shiftInput;
      default:
        return null;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! TachometerInputs) return false;
    if (rpmInput != other.rpmInput) return false;
    if (redlineInput != other.redlineInput) return false;
    if (shiftInput != other.shiftInput) return false;
    if (missingBindings.length != other.missingBindings.length) return false;
    for (final name in missingBindings) {
      if (!other.missingBindings.contains(name)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    rpmInput,
    redlineInput,
    shiftInput,
    Object.hashAllUnordered(missingBindings),
  );

  @override
  String toString() =>
      'TachometerInputs(rpm: $rpmInput, redline: '
      '$redlineInput, shift: $shiftInput, missing: $missingBindings)';
}

/// Pure-Dart value-mapping layer for the Tachometer Rive reference
/// widget.
///
/// The renderer (`TachometerStageRenderer`) consumes the live providers
/// (signal snapshots, cursor time, the parsed manifest, the per-instance
/// config), constructs a [TachometerInputMapper], and asks for the
/// frame's [TachometerInputs]. The mapper does the work that has no
/// dependency on Rive or Flutter:
///
/// - Identify missing bindings (pin's `signalRef` is empty / null).
/// - Convert each [StageSignalSnapshot] to a [RawSignalSample] (with
///   cursor-time tagging).
/// - Pick the per-binding [ValueNormalizer]:
///   * `rpm` → [LinearNormalizer] built from
///     [TachometerConfig.minRpm] / [TachometerConfig.maxRpm] (overrides
///     the manifest's static 0..8192 declaration).
///   * `redline` / `shift` → whatever the manifest declares for that
///     binding, or the default `_defaultNormalize` path when the
///     manifest is null or has no parameters entry.
/// - Apply the normalizer to produce a [NormalizedValue].
///
/// The mapper is intentionally internal-but-importable — the renderer
/// in the same package consumes it on every frame, and tests construct
/// it directly and assert against the resulting [TachometerInputs]. It
/// is not exported from any public barrel — consumers outside
/// `features/stage/widgets/tachometer/` should not depend on it.
///
/// Pure Dart — no Flutter imports, no Rive imports. Safe to unit-test
/// without a [WidgetTester] or a host app build.
@immutable
class TachometerInputMapper {
  /// Builds a mapper bound to [config] and the optional parsed
  /// [manifest]. Passing `null` for [manifest] is allowed (and tested):
  /// the mapper falls back to [defaultNormalizeSnapshot] for every
  /// non-rpm binding.
  const TachometerInputMapper({
    required this.config,
    required this.manifest,
  });

  /// Per-instance config — sources [LinearNormalizer.inputMin] /
  /// [LinearNormalizer.inputMax] for the rpm binding.
  final TachometerConfig config;

  /// Parsed manifest, or `null` when the renderer never reached the
  /// load-success state (in which case the renderer is already showing
  /// a placeholder and the mapper is never invoked anyway — but the
  /// mapper degrades gracefully rather than throwing).
  final StageWidgetManifest? manifest;

  /// Computes the frame's Rive input payload from the per-pin
  /// snapshots, the [bindings] map (so missing bindings can be
  /// detected), and the current [cursorTicks] (forwarded into each
  /// [RawSignalSample] for time-aware normalizers).
  TachometerInputs map({
    required Map<String, StageSignalBinding> bindings,
    required StageSignalSnapshot rpmSnapshot,
    required StageSignalSnapshot redlineSnapshot,
    required StageSignalSnapshot shiftSnapshot,
    required int cursorTicks,
  }) {
    final missing = missingBindings(bindings);
    return TachometerInputs(
      rpmInput: _inputFor('rpm', rpmSnapshot, cursorTicks),
      redlineInput: _inputFor('redline', redlineSnapshot, cursorTicks),
      shiftInput: _inputFor('shift', shiftSnapshot, cursorTicks),
      missingBindings: missing,
    );
  }

  /// Resolves the [ValueNormalizer] the mapper would use for the given
  /// [bindingName] under the current [config] and [manifest]. Exposed
  /// so renderer + tests can introspect the routing without invoking
  /// [map] (the renderer also calls this in its initial-state push).
  ValueNormalizer? normalizerFor(String bindingName) {
    if (bindingName == 'rpm') {
      // Per-instance override: linear-map the user's configured
      // [minRpm, maxRpm] range onto 0.0..1.0. The manifest's static
      // 0..8192 declaration is the schema default; this override
      // supersedes it whenever the user has tweaked the gauge bounds.
      return LinearNormalizer(
        inputMin: config.minRpm.toDouble(),
        inputMax: config.maxRpm.toDouble(),
      );
    }
    final m = manifest;
    if (m == null) return null;
    for (final p in m.parameters) {
      if (p.binding == bindingName) return p.normalizer;
    }
    return null;
  }

  /// Returns binding names whose [StageSignalBinding.signalRef] is
  /// unset / empty. Order matches [tachometerBindingNames].
  Set<String> missingBindings(Map<String, StageSignalBinding> bindings) {
    final missing = <String>{};
    for (final name in tachometerBindingNames) {
      final ref = bindings[name]?.signalRef;
      if (ref == null || ref.isEmpty) missing.add(name);
    }
    return missing;
  }

  /// Translates a [StageSignalSnapshot] to a [RawSignalSample] tagged
  /// with [cursorTicks]. Returns `null` when the snapshot is in any
  /// non-value lifecycle state — the renderer treats `null` as
  /// "freeze the Rive input at its prior value".
  static RawSignalSample? snapshotToRawSample(
    StageSignalSnapshot snapshot,
    int cursorTicks,
  ) {
    if (snapshot.kind != StageSignalSnapshotKind.value) return null;
    return RawSignalSample(
      rawValue: snapshot.rawValue,
      bitWidth: snapshot.bitWidth,
      timeTicks: cursorTicks,
      isAnalog: snapshot.isReal,
    );
  }

  /// Default normalization mirrors `CustomStageWidgetRenderer`'s logic
  /// (kept in sync with that renderer's `_defaultNormalize`): X/Z →
  /// [NormalizedXZ], scalar 1-bit → [NormalizedBool], wider vector →
  /// [NormalizedDouble] (interpreted as unsigned int).
  ///
  /// Exposed statically so tests can drive it without constructing a
  /// full mapper instance.
  static NormalizedValue defaultNormalize(RawSignalSample raw) {
    if (raw.hasX) return const NormalizedXZ(isX: true);
    if (raw.hasZ) return const NormalizedXZ(isX: false);
    final stripped = raw.rawValue.toLowerCase().startsWith('b')
        ? raw.rawValue.substring(1)
        : raw.rawValue;
    if (raw.bitWidth == 1 && stripped.length == 1) {
      return NormalizedBool(value: stripped == '1');
    }
    final asInt = BigInt.tryParse(stripped, radix: 2);
    if (asInt == null) return const NormalizedXZ(isX: true);
    return NormalizedDouble(asInt.toDouble());
  }

  /// Composes [snapshotToRawSample] and the resolved normalizer (or
  /// [defaultNormalize] when no normalizer applies) into one frame's
  /// payload for [bindingName].
  NormalizedValue? defaultNormalizeSnapshot(
    StageSignalSnapshot snapshot,
    int cursorTicks,
  ) {
    final raw = snapshotToRawSample(snapshot, cursorTicks);
    if (raw == null) return null;
    return defaultNormalize(raw);
  }

  NormalizedValue? _inputFor(
    String bindingName,
    StageSignalSnapshot snapshot,
    int cursorTicks,
  ) {
    final raw = snapshotToRawSample(snapshot, cursorTicks);
    if (raw == null) return null;
    final normalizer = normalizerFor(bindingName);
    return normalizer != null
        ? normalizer.normalize(raw)
        : defaultNormalize(raw);
  }
}
