// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/stage/sdk/manifest/stage_widget_manifest.dart';
import 'package:wavecrux/features/stage/sdk/normalization/normalized_value.dart';
import 'package:wavecrux/features/stage/sdk/normalization/raw_signal_sample.dart';
import 'package:wavecrux/features/stage/sdk/normalization/value_normalizer.dart';

/// Pure-Dart value-mapping layer that drives a community `.wcrux-widget`
/// Rive artboard's state-machine inputs from the manifest's declared signal
/// bindings and (optional) normalizer parameters.
///
/// This generalizes the Tachometer reference widget's bespoke
/// `TachometerInputMapper` — which hard-codes the `rpm`/`redline`/`shift`
/// pins and a per-instance RPM linear override — to *any* manifest. The
/// community renderer iterates over [StageWidgetManifest.signalBindings]
/// rather than a fixed pin list, and resolves each binding's normalizer from
/// [StageWidgetManifest.parameters] (falling back to [defaultNormalize] when
/// the manifest declares none for that binding).
///
/// The mapper does the work that has no dependency on Rive or Flutter:
///
/// - Identify which **required** bindings the user has not wired
///   ([missingRequiredBindings]) so the renderer can show the localized
///   "bind these signals" placeholder rather than pushing garbage.
/// - Convert each [StageSignalSnapshot] to a [RawSignalSample]
///   ([snapshotToRawSample]) — returning `null` for any non-`value`
///   lifecycle state so the renderer holds the Rive input's prior value.
/// - Resolve and apply the per-binding [ValueNormalizer] ([inputFor]).
///
/// Pure Dart — no Flutter, no Rive imports. Fully unit-testable without a
/// `WidgetTester`, a Riverpod container, or an FFI-loaded `.riv` (the
/// rive_native runtime is unavailable in headless `flutter test`).
@immutable
class GenericManifestInputMapper {
  /// Builds a mapper bound to the parsed [manifest].
  const GenericManifestInputMapper({required this.manifest});

  /// The parsed bundle manifest — source of truth for the binding list and
  /// the per-binding normalizer pipeline.
  final StageWidgetManifest manifest;

  /// Names of every **required** binding whose [StageSignalBinding.signalRef]
  /// is unset / empty in [instanceBindings]. Order follows the manifest's
  /// declaration order. Optional bindings are never reported — an unbound
  /// optional pin simply holds its artboard default.
  Set<String> missingRequiredBindings(
    Map<String, StageSignalBinding> instanceBindings,
  ) {
    final missing = <String>{};
    for (final binding in manifest.signalBindings) {
      if (!binding.required) continue;
      final ref = instanceBindings[binding.name]?.signalRef;
      if (ref == null || ref.isEmpty) missing.add(binding.name);
    }
    return missing;
  }

  /// Resolves the [ValueNormalizer] declared for [bindingName] in the
  /// manifest's `parameters` block, or `null` when the manifest declares
  /// none (in which case the renderer applies [defaultNormalize]).
  ValueNormalizer? normalizerFor(String bindingName) {
    for (final parameter in manifest.parameters) {
      if (parameter.binding == bindingName) return parameter.normalizer;
    }
    return null;
  }

  /// Computes the [NormalizedValue] to write for [bindingName] this frame,
  /// or `null` when the snapshot carries no fresh value (the renderer holds
  /// the Rive input's prior value). Applies the manifest normalizer when one
  /// is declared, otherwise [defaultNormalize].
  NormalizedValue? inputFor(
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

  /// Translates a [StageSignalSnapshot] to a [RawSignalSample] tagged with
  /// [cursorTicks]. Returns `null` for any snapshot whose kind is not
  /// [StageSignalSnapshotKind.value] — the renderer treats `null` as
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

  /// Default normalization used when the manifest declares no parameter for
  /// a binding. Mirrors `CustomStageWidgetRenderer._defaultNormalize` and
  /// `TachometerInputMapper.defaultNormalize`: X/Z → [NormalizedXZ];
  /// 1-bit scalar → [NormalizedBool]; wider vector → [NormalizedDouble]
  /// (the bit-string parsed as an unsigned integer); analog → the parsed
  /// double.
  ///
  /// Exposed statically so the mapping can be unit-tested without building a
  /// mapper instance.
  static NormalizedValue defaultNormalize(RawSignalSample raw) {
    if (raw.hasX) return const NormalizedXZ(isX: true);
    if (raw.hasZ) return const NormalizedXZ(isX: false);
    if (raw.isAnalog) {
      final parsed = double.tryParse(raw.rawValue);
      if (parsed == null) return const NormalizedXZ(isX: true);
      return NormalizedDouble(parsed);
    }
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
}
