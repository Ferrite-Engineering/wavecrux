// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/services/value_format/value_format_service.dart';

part 'parameter_value_provider.g.dart';

/// Resolves the constant value of an HDL parameter for inline display in the
/// signal tree (`p_data_width = 32` style badges on parameter leaves).
///
/// Parameters carry a single value at the start of the trace, so the value at
/// [WaveformDataSource.startTime] *is* the parameter's value. The lookup uses
/// the same lazy [WaveformDataSource.loadSignal] + `valueAt` primitives the
/// viewer uses, entirely decoupled from the displayed-signal list — reading a
/// parameter's value never adds it to the timeline. The loaded signal data
/// for a parameter is a single change record, so the per-signal load cost is
/// negligible and the signal is left loaded (no unload bookkeeping).
///
/// Values format as unsigned decimal — the natural reading for widths,
/// depths, and counts. Real-valued parameters pass through the formatter
/// unchanged (e.g. `3.14`).
///
/// [bitWidth] is the variable's declared width (0 when null / real-valued);
/// it is part of the family key so the formatter can zero-extend correctly.
///
/// `dependencies` is declared so Riverpod auto-scopes this family to the
/// per-tab container (the `signalValueAtCursor` pattern) — without it the
/// family would hoist to the root container and read the empty root-scope
/// waveform source (the issue #44 scope-leak class).
@Riverpod(dependencies: [WaveformSourceNotifier])
Future<String?> parameterValue(
  Ref ref,
  String signalRef,
  int bitWidth,
) async {
  final source = ref.watch(waveformSourceProvider).value;
  if (source == null) return null;
  await source.loadSignal(signalRef);
  final raw = source.valueAt(signalRef, source.startTime);
  if (raw == null) return null;
  return const ValueFormatService().format(
    raw,
    bitWidth,
    DisplayFormat.unsignedDecimal,
  );
}
