// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/models/stage_signal_binding.dart';
import 'package:wavecrux/domain/models/stage_signal_snapshot.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';

part 'stage_signal_provider.g.dart';

/// Tracks which Stage-bound signals have *settled* a lazy-load attempt against
/// the [WaveformDataSource] — i.e. the load either succeeded (the source now
/// holds the data) or failed (a bad ref / missing signal).
///
/// Stage widgets bind any signal — including signals the user has not added
/// to the viewer — so the workspace cannot rely on the value-column code
/// path to populate signal data. This notifier owns the small bookkeeping
/// state needed to load a signal once per session and to invalidate the
/// settled set when a new waveform replaces the current one.
///
/// [state] is the set of refs whose load attempt has *settled*, not just
/// succeeded: a failed ref is in [state] too, with its error recorded in
/// [errorFor]. The provider distinguishes the two by re-checking
/// [WaveformDataSource.isSignalLoaded]. This is deliberate — a binding to a
/// signal that is not in the current trace (a stale workspace, a different
/// VCD, or a path mistakenly used as a ref) must NOT throw an uncaught async
/// error out of the [ensureLoaded] future: under the test binding that lands
/// non-deterministically in whichever test is pumping; in production it is a
/// zone crash. Instead it settles to an [StageSignalSnapshotKind.error]
/// snapshot the renderer can show.
///
/// Mutating [state] when [ensureLoaded] settles triggers any
/// [stageBoundSignalProvider] watchers to rebuild and pick up the value (or
/// the error).
@Riverpod(keepAlive: true)
class StageLoadedSignals extends _$StageLoadedSignals {
  /// Diagnostic messages for refs whose load attempt *failed*. Keyed by ref;
  /// only populated for failures. Reads are always gated by the reactive
  /// [state] set (a ref is added to [state] in the same step its error is
  /// recorded), so this plain map never needs to drive rebuilds on its own.
  final Map<String, String> _errors = {};

  @override
  Set<String> build() {
    // Reset the settled-signal set whenever a new file is opened so we don't
    // hold stale refs (loaded or errored) that point to a previous waveform's
    // variables.
    ref.listen(waveformSourceProvider, (prev, next) {
      if (prev == null) return;
      if (prev.value != next.value &&
          (state.isNotEmpty || _errors.isNotEmpty)) {
        _errors.clear();
        state = const {};
      }
    });
    return const {};
  }

  /// The recorded error message for [signalRef] if its load attempt failed,
  /// or `null` if it has not failed (not yet attempted, or loaded fine).
  String? errorFor(String signalRef) => _errors[signalRef];

  /// Loads [signalRef] into the active waveform source if it is not already
  /// loaded, then records that the attempt has settled. A load failure is
  /// caught and recorded (never rethrown) so it cannot escape as an uncaught
  /// async error. Safe to call multiple times.
  Future<void> ensureLoaded(String signalRef) async {
    if (signalRef.isEmpty) return;
    if (state.contains(signalRef)) return;
    final source = ref.read(waveformSourceProvider).value;
    if (source == null) return;
    if (!source.isSignalLoaded(signalRef)) {
      try {
        await source.loadSignal(signalRef);
      } on Object catch (error) {
        // Settle as a failure: record the diagnostic and add the ref to the
        // reactive set so watchers rebuild into the error snapshot and we do
        // not re-kick the load every frame.
        _errors[signalRef] = error.toString();
        state = {...state, signalRef};
        return;
      }
    }
    _errors.remove(signalRef);
    state = {...state, signalRef};
  }

  /// Test hook: drops the settled-signal set and recorded errors without
  /// touching the source.
  void reset() {
    _errors.clear();
    state = const {};
  }
}

/// Synchronous snapshot of one Stage-bound signal at the current cursor time.
///
/// Returns [StageSignalSnapshot.unbound] when [binding] is null,
/// [StageSignalSnapshot.noFile] when no waveform is loaded,
/// [StageSignalSnapshot.loading] while lazy loading is in flight,
/// [StageSignalSnapshot.unknown] when the signal is loaded but has no value
/// at or before the cursor, and [StageSignalSnapshot.value] otherwise.
///
/// When [StageSignalBinding.bitIndex] is non-null the snapshot is sliced
/// down to that single bit — this is how multi-bit vectors get bound to
/// 1-bit slots like an LED on the Basys 3 board widget. Out-of-range bit
/// indices render as `x`.
///
/// Each Stage widget renderer watches this provider per pin so it rebuilds
/// automatically when the cursor moves or a new file loads.
@riverpod
StageSignalSnapshot stageBoundSignal(
  Ref ref,
  StageSignalBinding? binding,
) {
  if (binding == null || binding.signalRef.isEmpty) {
    return const StageSignalSnapshot.unbound();
  }
  final signalRef = binding.signalRef;

  final source = ref.watch(waveformSourceProvider).value;
  if (source == null) {
    return const StageSignalSnapshot.noFile();
  }

  final settled = ref.watch(stageLoadedSignalsProvider);
  // Capture the (keepAlive) loader notifier synchronously during build so the
  // deferred load below never touches `ref` across an async gap — using `ref`
  // after the provider rebuilt/disposed throws "Ref used after dispose".
  final loader = ref.read(stageLoadedSignalsProvider.notifier);
  final isLoaded = source.isSignalLoaded(signalRef);
  if (!isLoaded && !settled.contains(signalRef)) {
    // Kick off load — when the attempt settles the loader notifier flips state
    // which triggers this provider to rebuild and read the new value (or the
    // error). The future never throws out of here: ensureLoaded catches a
    // failed load and settles it as an error instead.
    unawaited(Future<void>(() => loader.ensureLoaded(signalRef)));
    return const StageSignalSnapshot.loading();
  }
  if (!isLoaded) {
    // The load attempt settled but the source still doesn't hold this ref —
    // the load failed (bad ref / signal not in this trace). Surface it as an
    // error snapshot rather than spinning on `loading` forever.
    return StageSignalSnapshot.error(loader.errorFor(signalRef) ?? '');
  }

  final cursorState = ref.watch(cursorStateProvider);
  final variablesMap = ref.watch(signalVariablesMapProvider);
  final variable = variablesMap[signalRef];
  final bitWidth = variable?.bitWidth ?? 1;
  final isReal = variable?.isReal ?? false;
  final time = cursorState.primaryCursorTime ?? source.startTime;
  final raw = source.valueAt(signalRef, time);
  if (raw == null) {
    return const StageSignalSnapshot.unknown();
  }

  if (binding.bitIndex == null) {
    return StageSignalSnapshot.value(
      rawValue: raw,
      bitWidth: bitWidth,
      isReal: isReal,
    );
  }

  // Bit-sliced binding. Two cases:
  //   - bitWidth null/1 → single-bit slice (fan-out per LED bit)
  //   - bitWidth > 1    → multi-bit slice (e.g. ADC channel out of a
  //                       packed N-channel bus)
  final sliceWidth = (binding.bitWidth ?? 1).clamp(1, bitWidth);
  if (sliceWidth == 1) {
    final sliced = sliceBitsForTesting(
      raw,
      bitWidth: bitWidth,
      bitIndex: binding.bitIndex!,
      sliceWidth: 1,
    );
    return StageSignalSnapshot.value(
      rawValue: sliced,
      bitWidth: 1,
    );
  }
  final slicedRange = sliceBitsForTesting(
    raw,
    bitWidth: bitWidth,
    bitIndex: binding.bitIndex!,
    sliceWidth: sliceWidth,
  );
  return StageSignalSnapshot.value(
    rawValue: slicedRange,
    bitWidth: sliceWidth,
  );
}

/// Returns a [sliceWidth]-bit VCD value drawn from [rawValue] starting
/// at LSB position [bitIndex]. When `sliceWidth == 1` this returns a
/// single bit (back-compat with the original `_sliceBit` semantics);
/// when `sliceWidth > 1` it returns the full slice as a bit string in
/// MSB-first order, suitable for direct hand-off to a downstream
/// renderer that expects a vector value.
///
/// Out-of-range bits (extending past the signal's MSB) render as
/// `'x'` per VCD convention. The input may be `b`-prefixed.
///
/// Exposed via `@visibleForTesting` so the slice math can be unit-tested
/// independently of the full Riverpod provider — a meaningful test
/// surface that would otherwise require a mock `WaveformDataSource`.
@visibleForTesting
String sliceBitsForTesting(
  String rawValue, {
  required int bitWidth,
  required int bitIndex,
  required int sliceWidth,
}) {
  if (sliceWidth <= 0) return 'x';
  if (bitIndex < 0 || bitIndex >= bitWidth) {
    return 'x' * sliceWidth;
  }
  var bits = rawValue.toLowerCase();
  if (bits.startsWith('b')) bits = bits.substring(1);
  // VCD shorthand: a value shorter than the declared width is left-padded
  // with the leftmost bit (0 by default, x or z if those appear in the
  // leftmost slot — same rule wellen and the open-core Dart parser apply).
  if (bits.length < bitWidth) {
    final pad = bits.isEmpty
        ? '0'
        : (bits[0] == 'x' || bits[0] == 'z' ? bits[0] : '0');
    bits = pad * (bitWidth - bits.length) + bits;
  }
  // Walk from MSB of slice down to LSB. `pos` is the offset into
  // [bits] for each slice bit; LSB of slice sits at `bits[bitWidth-1-bitIndex]`.
  final buffer = StringBuffer();
  for (var i = sliceWidth - 1; i >= 0; i--) {
    final absoluteIndex = bitIndex + i;
    if (absoluteIndex < 0 || absoluteIndex >= bitWidth) {
      buffer.write('x');
      continue;
    }
    final pos = bitWidth - 1 - absoluteIndex;
    if (pos < 0 || pos >= bits.length) {
      buffer.write('x');
    } else {
      buffer.write(bits[pos]);
    }
  }
  return buffer.toString();
}
