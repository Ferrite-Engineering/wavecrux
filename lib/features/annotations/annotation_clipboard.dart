// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';

/// An annotation's time as the Annotations panel shows it: the anchor time,
/// or `start – end` for a range.
///
/// One function for the panel row and for Copy, so what lands on the
/// clipboard reads exactly as the row the user selected it from.
String annotationTimeLabel(Annotation a, TimeFormatService formatter) =>
    switch (a.anchor) {
      PointAnchor(:final time) => formatter.format(time),
      RangeAnchor(:final earliest, :final latest) =>
        '${formatter.format(earliest)} – ${formatter.format(latest)}',
    };

/// The plain text Copy puts on the clipboard for selected [annotations].
///
/// Each annotation is a block: one header line with its time (as
/// [annotationTimeLabel] formats it) and, when it is on a signal, the
/// signal's path two spaces after it; then the note as written, Markdown
/// included. Several blocks are in time order (anchor time, then creation),
/// the order the panel lists them in, separated by a blank line. The author
/// is left out: the clipboard carries what the note says and where, not who
/// wrote it.
///
/// ```text
/// 200 ns  top.req
/// req asserts here, one clock before the bus is driven
/// ```
///
/// A note with no text yields the header alone. Returns an empty string for
/// no annotations.
String annotationClipboardText(
  Iterable<Annotation> annotations,
  TimeFormatService formatter,
) {
  final ordered = [...annotations]
    ..sort((a, b) {
      final byTime = a.sortTime.compareTo(b.sortTime);
      return byTime != 0 ? byTime : a.createdAt.compareTo(b.createdAt);
    });
  return [
    for (final a in ordered)
      [
        [annotationTimeLabel(a, formatter), ?a.rowId].join('  '),
        if (a.text.isNotEmpty) a.text,
      ].join('\n'),
  ].join('\n\n');
}
