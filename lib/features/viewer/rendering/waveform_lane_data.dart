// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';
import 'package:wavecrux/domain/enums/analog_interpolation.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/services/translate/translate_filter_service.dart';
import 'package:wavecrux/services/value_format/analog_value_extractor.dart';

/// The kind of a rendered row in the waveform canvas.
///
/// Mirrors [SignalEntryKind] for the user-managed signal entries and adds
/// [transaction] for the auto-generated protocol-decoder overlay lanes.
/// [WaveformLaneData] uses this enum while [SignalEntry] continues to use
/// [SignalEntryKind] — the canvas converts between the two when building lanes.
enum WaveformLaneKind {
  /// A bound signal with a waveform trace.
  signal,

  /// A named group header. Child signals are in [WaveformLaneData.groupName].
  group,

  /// A blank horizontal separator line (GTKWave compat).
  separator,

  /// A non-signal text comment row (GTKWave compat).
  comment,

  /// A protocol-decoder transaction overlay lane (auto-generated, not
  /// persisted in the session file).
  transaction,

  /// An XOR diff trace lane showing value differences between two waveform
  /// files (auto-generated when diff mode is active, not persisted).
  xorDiff,
}

/// Layout and pre-fetched data for one rendered row in the waveform canvas.
///
/// Built by [WaveformCanvas] before each paint pass by combining the ordered
/// [SignalEntry] list with cached visible signal changes.  One
/// [WaveformLaneData] is produced per visible entry (signal, group header,
/// separator, comment, or transaction overlay).
@immutable
class WaveformLaneData {
  const WaveformLaneData({
    required this.kind,
    required this.y,
    required this.height,
    this.signalRef,
    this.rowPath,
    this.displayName = '',
    this.signalColor = const Color(0xFF4CAF50),
    this.format = DisplayFormat.hexadecimal,
    this.isScalar = false,
    this.isAnalog = false,
    this.bitWidth = 1,
    this.changes = const [],
    this.valueAtStart,
    this.analogValueExtractor,
    this.analogInterpolation = AnalogInterpolation.linear,
    this.analogRangeMin,
    this.analogRangeMax,
    this.groupName,
    this.commentText,
    this.translateFilter,
    this.translatorConfig,
    this.decoderInstanceId,
    this.decoderDisplayName,
    this.transactions = const [],
    this.transactionColor = const Color(0xFF1565C0),
    this.xorChanges = const [],
    this.xorValueAtStart,
  });

  // ── row identity ─────────────────────────────────────────────────────────────

  /// Row type — determines which painter is used.
  final WaveformLaneKind kind;

  /// Top y-coordinate of this lane in the full-height canvas coordinate space.
  final double y;

  /// Lane height in logical pixels.
  final double height;

  // ── signal fields (kind == signal) ───────────────────────────────────────────

  /// Opaque signal reference used with [WaveformDataSource] queries.
  final String? signalRef;

  /// The row's own hierarchical path ([SignalEntry.signalPath]), which is
  /// what the per-tab selection holds. Distinct from [signalRef]: aliased
  /// variables (`top.down.clk`, `top.up.clk`) share one ref, so a selection
  /// matched by ref would light every alias lane at once. Null for a lane
  /// built without one, which then matches by [signalRef].
  final String? rowPath;

  /// Human-readable signal label shown inside each lane.
  final String displayName;

  /// Per-signal waveform color from the auto-palette or a user override.
  final Color signalColor;

  /// Display format applied when generating formatted value labels for bus
  /// signals (e.g. hexadecimal, binary, decimal).
  final DisplayFormat format;

  /// True for 1-bit digital signals; false for multi-bit buses and real-valued
  /// (analog) signals.
  final bool isScalar;

  /// True when this lane is drawn by [AnalogSignalPainter] rather than
  /// [ScalarSignalPainter] or [VectorSignalPainter].
  ///
  /// Two things set it: a real-valued signal ([VarType.real] /
  /// [VarType.realTime] / [VarType.svShortReal]), which has no digital
  /// rendering, and a digital signal whose [SignalEntry.renderAsAnalog] the
  /// user turned on. The painter does not distinguish them — the difference
  /// lives entirely in [analogValueExtractor].
  final bool isAnalog;

  /// Declared bit-width of the signal.  0 for real/analog signals that have no
  /// fixed width.
  final int bitWidth;

  /// Value changes covering the visible time range, in time order. The canvas
  /// passes a range wider than the view, reduced to the zoom's pixel columns
  /// (`changesForDisplay`); the painters skip what lies left of the viewport.
  /// The canvas passes a `DisplayChanges`, which the painters read by index
  /// without building a [SignalChange] per change; any other list is copied
  /// into one once.
  final List<SignalChange> changes;

  /// Signal value just before the first of [changes], returned by
  /// [WaveformDataSource.valueAt]. Null when the signal has no recorded
  /// value that early.
  final String? valueAtStart;

  // ── analog display options (kind == signal && isAnalog) ──────────────────────

  /// How this lane's raw value strings become plottable numbers.
  ///
  /// Null means the lane is a genuine real-valued signal and the painter's
  /// default ([AnalogValueExtractors.real]) applies. A digital bus rendered as
  /// analog carries an extractor built from its own [format] /
  /// [translatorConfig], so the same bits plot as 1.5 under Q4.12 and 6144
  /// under hex.
  final AnalogValueExtractor? analogValueExtractor;

  /// How to interpolate between recorded real-valued data points.
  final AnalogInterpolation analogInterpolation;

  /// Manual Y-axis minimum override.  Null means auto-range from visible data.
  final double? analogRangeMin;

  /// Manual Y-axis maximum override.  Null means auto-range from visible data.
  final double? analogRangeMax;

  // ── group fields (kind == group) ─────────────────────────────────────────────

  /// User-defined group name (kind == group).
  final String? groupName;

  // ── comment fields (kind == comment) ─────────────────────────────────────────

  /// Comment text displayed in the lane (kind == comment).
  final String? commentText;

  // ── translate filter (kind == signal, non-scalar) ─────────────────────────────

  /// Optional GTKWave translate filter applied when rendering bus-value labels.
  ///
  /// When non-null, [VectorSignalPainter] uses this to translate raw binary
  /// values to human-readable labels before falling back to the numeric format.
  final TranslateFilter? translateFilter;

  /// Per-signal translator configuration map (from [SignalEntry.translatorConfig]).
  ///
  /// Required for [DisplayFormat.fixedPointQ] and [DisplayFormat.namedEnum];
  /// ignored for all other formats.
  final Map<String, Object?>? translatorConfig;

  // ── transaction fields (kind == transaction) ─────────────────────────────────

  /// Unique ID of the [ActiveDecoder] instance this lane belongs to.
  final String? decoderInstanceId;

  /// Human-readable name of the decoder (e.g. "SPI", "I²C").  Shown at the
  /// left edge of the lane as a header label.
  final String? decoderDisplayName;

  /// All decoded transactions for this decoder instance.  The painter clips
  /// to the visible time range itself so it is fine to pass the full list.
  final List<DecodedTransaction> transactions;

  /// Base fill/border color used when drawing transaction blocks.
  final Color transactionColor;

  // ── xorDiff fields (kind == xorDiff) ─────────────────────────────────────────

  /// Pre-computed XOR changes for a diff trace lane (kind == xorDiff).
  ///
  /// Each entry has value '1' where the two waveforms diverge, '0' where they
  /// agree.  Rendered as an amber/orange scalar trace.
  final List<SignalChange> xorChanges;

  /// Value of the XOR signal at the left edge of the visible viewport.
  final String? xorValueAtStart;
}
