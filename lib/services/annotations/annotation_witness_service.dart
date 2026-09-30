// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/services/value_format/value_format_service.dart';

/// How an [Annotation] relates to the waveform currently loaded.
///
/// Computed fresh on every load rather than stored: the whole point is that
/// the answer can change when the design does.
enum AnnotationStatus {
  /// The annotated row is displayed and the signal still reads what it read
  /// when the note was written.
  resolved,

  /// The annotated row is displayed, but the signal's value at the anchored
  /// tick no longer matches the witness.
  ///
  /// **Not an error.** The note is intact and the user's claim may still be
  /// worth reading — what changed is the design underneath it. Drift is the
  /// feature working: it is the signal that a claim needs re-checking, which
  /// a callout drawn on a screenshot can never give.
  drifted,

  /// The signal exists in this waveform but is not currently on screen, so
  /// there is no lane to draw against.
  orphaned,

  /// No such signal in this waveform at all — a note written against a
  /// different design, or a signal that has since been renamed or removed.
  unresolved,

  /// A full-height band, which belongs to no single row and therefore cannot
  /// drift or orphan.
  unanchoredToRow,
}

/// Captures and evaluates [AnnotationWitness] values.
///
/// Deliberately a plain class over explicit inputs rather than a Riverpod
/// consumer: witness capture has to be exercisable in a unit test against a
/// fake data source, without a provider container or a loaded file.
class AnnotationWitnessService {
  const AnnotationWitnessService({
    this.valueFormatter = const ValueFormatService(),
  });

  final ValueFormatService valueFormatter;

  /// Reads what [signalRef] is doing at [time] and packages it as a witness.
  ///
  /// Returns `null` when no value can be read — before the signal's first
  /// transition, or when it is not loaded. A null witness is a legitimate
  /// state: the annotation simply has nothing to drift against, and
  /// [statusOf] reports it as [AnnotationStatus.resolved] rather than
  /// inventing a mismatch.
  AnnotationWitness? capture({
    required WaveformDataSource source,
    required String signalRef,
    required int time,
    required int bitWidth,
  }) {
    final bits = currentBits(
      source: source,
      signalRef: signalRef,
      time: time,
      bitWidth: bitWidth,
    );
    if (bits == null) return null;
    return AnnotationWitness(
      bits: bits,
      edgeOrdinal: _edgeOrdinalAt(source, signalRef, time),
    );
  }

  /// The signal's value at [time] as a canonical, width-padded bit string —
  /// the form both sides of a drift comparison are expressed in.
  ///
  /// Normalising through [DisplayFormat.binary] rather than comparing the raw
  /// reader output is what makes `b0` and `00000000` compare equal: VCD elides
  /// leading zeros, and a comparison on notation would drift on files that
  /// differ only in how compactly they were written.
  String? currentBits({
    required WaveformDataSource source,
    required String signalRef,
    required int time,
    required int bitWidth,
  }) {
    final raw = source.valueAt(signalRef, time);
    if (raw == null) return null;
    return valueFormatter.format(raw, bitWidth, DisplayFormat.binary);
  }

  /// Renders witness [bits] in the display format the reader is currently
  /// working in, so a drift message speaks their radix rather than the one
  /// that happened to be active when the note was written.
  String describe(
    String bits, {
    required int bitWidth,
    DisplayFormat format = DisplayFormat.hexadecimal,
    Map<String, Object?>? config,
  }) => valueFormatter.format(bits, bitWidth, format, config);

  /// Classifies [annotation] given what the viewer currently knows.
  ///
  /// [isDisplayed] — the annotated row is in the visible signal list.
  /// [existsInFile] — a signal with that path exists in the loaded waveform.
  /// [currentBits] — the canonical bits now, or `null` if unreadable.
  ///
  /// Pure, and separated from the provider wiring on purpose: this is the
  /// decision table the whole feature rests on, and it should be testable
  /// without a widget tree.
  static AnnotationStatus statusOf(
    Annotation annotation, {
    required bool isDisplayed,
    required bool existsInFile,
    String? currentBits,
  }) {
    if (annotation.rowId == null) return AnnotationStatus.unanchoredToRow;
    if (!existsInFile) return AnnotationStatus.unresolved;
    if (!isDisplayed) return AnnotationStatus.orphaned;

    final witness = annotation.witness;
    // No witness (or nothing readable now) means there is nothing to compare.
    // Reporting drift here would flag every annotation made before its
    // signal's first transition, which is noise, not information.
    if (witness == null || currentBits == null) {
      return AnnotationStatus.resolved;
    }
    return witness.bits == currentBits
        ? AnnotationStatus.resolved
        : AnnotationStatus.drifted;
  }

  /// Index of the transition at or immediately before [time], or `null` when
  /// the signal has none.
  ///
  /// Counted from the start of the waveform, so it is stable under a re-run
  /// that shifts timing but preserves the sequence of edges — which is what
  /// makes it useful to a future re-anchor repair.
  int? _edgeOrdinalAt(WaveformDataSource source, String signalRef, int time) {
    final changes = source.changesInRange(
      signalRef,
      source.startTime,
      time + 1,
    );
    if (changes.isEmpty) return null;
    return changes.length - 1;
  }
}
