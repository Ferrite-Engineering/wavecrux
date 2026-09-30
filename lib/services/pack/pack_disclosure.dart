// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_spec.dart';
import 'package:wavecrux/services/vcd_writer/vcd_writer_service.dart';

/// The time window a pack exports.
@immutable
class PackSpan {
  const PackSpan({
    required this.startTime,
    required this.endTime,
    required this.derivedFromAnnotations,
  });

  final int startTime;
  final int endTime;

  /// True when the window came from the annotated span; false when it fell
  /// back to the visible viewport because nothing is annotated yet. Surfaced
  /// in the disclosure so the user is never guessing which rule applied.
  final bool derivedFromAnnotations;

  int get durationTicks => endTime - startTime;
}

/// Resolves the time window a share bundle should carry.
///
/// The default is the **annotated span**, not the whole dump: the recipient is
/// being sent an argument about a specific window, and a 4 GB attachment is
/// not one anybody opens. Padding gives the annotated edges their context.
class PackSpanResolver {
  const PackSpanResolver();

  /// Annotated span padded by [WaveCruxPackSpec.spanPaddingFraction] at each
  /// end and clamped to the source's own range.
  ///
  /// Falls back to `[fallbackStart, fallbackEnd]` — the caller passes the
  /// visible viewport — when there are no annotations, or when every
  /// annotation is a full-height band with no usable tick.
  PackSpan resolve({
    required List<Annotation> annotations,
    required int sourceStart,
    required int sourceEnd,
    required int fallbackStart,
    required int fallbackEnd,
  }) {
    int? spanStart;
    int? spanEnd;
    for (final annotation in annotations) {
      final (int lo, int hi) = switch (annotation.anchor) {
        PointAnchor(:final time) => (time, time),
        RangeAnchor(earliest: final lo, latest: final hi) => (lo, hi),
      };
      spanStart = spanStart == null ? lo : (lo < spanStart ? lo : spanStart);
      spanEnd = spanEnd == null ? hi : (hi > spanEnd ? hi : spanEnd);
    }

    if (spanStart == null || spanEnd == null) {
      return PackSpan(
        startTime: _clamp(fallbackStart, sourceStart, sourceEnd),
        endTime: _clamp(fallbackEnd, sourceStart, sourceEnd),
        derivedFromAnnotations: false,
      );
    }

    // A single point annotation has a zero-width span, and 20% of nothing is
    // nothing — a pack containing one tick would carry no context at all. Pad
    // from the viewport width in that case, which is what the author was
    // actually looking at when they wrote the note.
    final rawSpan = spanEnd - spanStart;
    final basis = rawSpan > 0 ? rawSpan : (fallbackEnd - fallbackStart).abs();
    final pad = (basis * WaveCruxPackSpec.spanPaddingFraction).round();
    return PackSpan(
      startTime: _clamp(spanStart - pad, sourceStart, sourceEnd),
      endTime: _clamp(spanEnd + pad, sourceStart, sourceEnd),
      derivedFromAnnotations: true,
    );
  }

  static int _clamp(int value, int lo, int hi) =>
      lo <= hi ? value.clamp(lo, hi) : value;
}

/// Exactly what a pack would send off the machine, computed before anything is
/// written.
///
/// The list of **signal paths** is deliberate, and named in the design: a count
/// ("12 signals") is not disclosure. A user who is about to email design data
/// out of a suite that markets the opposite is entitled to read the names.
@immutable
class PackDisclosure {
  const PackDisclosure({
    required this.signalPaths,
    required this.span,
    required this.authorNames,
    required this.annotationCount,
    required this.estimatedBytes,
  });

  /// Every signal path that will appear in the bundled VCD, in export order.
  final List<String> signalPaths;

  /// The time window leaving the machine.
  final PackSpan span;

  /// Distinct author names embedded in the annotations, sorted. Empty when the
  /// notes carry no attribution.
  final List<String> authorNames;

  final int annotationCount;

  /// Predicted uncompressed size, from value-change counts rather than a
  /// rendered document — so a bundle nobody could email is caught *before* the
  /// VCD is materialised in memory, not after.
  final int estimatedBytes;

  bool get exceedsWarnThreshold =>
      estimatedBytes > WaveCruxPackSpec.warnAboveBytes;

  bool get exceedsRefuseThreshold =>
      estimatedBytes > WaveCruxPackSpec.refuseAboveBytes;
}

/// Predicts a pack's uncompressed size without building it.
///
/// The estimate counts value changes and multiplies by the width of the line
/// each one becomes. It is approximate on purpose: the alternative is
/// generating the document to measure it, which is exactly the multi-gigabyte
/// allocation the size guard exists to prevent.
class PackSizeEstimator {
  const PackSizeEstimator();

  /// Bytes the VCD header and `$var` declarations are expected to occupy.
  static const int _headerBytes = 256;
  static const int _declarationBytesPerSignal = 48;

  /// `#<tick>\n` plus the change line's identifier and newline.
  static const int _timestampBytesPerChange = 12;
  static const int _identifierBytesPerChange = 4;

  int estimateBytes({
    required WaveformDataSource source,
    required VcdExportConfig config,
    int sessionBytes = 0,
    int previewBytes = 0,
    int readmeBytes = 0,
  }) {
    var total = _headerBytes + sessionBytes + previewBytes + readmeBytes;
    for (final ref in config.signalRefs) {
      total += _declarationBytesPerSignal;
      final width = config.signalMap[ref]?.bitWidth ?? 1;
      // A scalar renders as `0!`; a vector as `b0101 !`.
      final valueBytes = width <= 1 ? 1 : width + 2;
      final perChange =
          valueBytes + _identifierBytesPerChange + _timestampBytesPerChange;
      // +1 for the signal's line in the opening `$dumpvars` block.
      final changes =
          source
              .changesInRange(ref, config.startTime + 1, config.endTime + 1)
              .length +
          1;
      total += perChange * changes;
    }
    return total;
  }
}
