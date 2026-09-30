// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// Hard upper bound on an annotation's body text, enforced at the model
/// boundary.
///
/// Not fussiness: annotation bodies are written into `.wavecrux` documents and,
/// under Enterprise collaboration, onto the session wire. An unbounded body is
/// a file-bloat and payload-size problem. The authoring field caps input at
/// the same length; this is the backstop that also protects against a
/// hand-edited or hostile document.
const int kAnnotationTextMaxLength = 1000;

/// The drawn form of an [Annotation].
enum AnnotationShape {
  /// A balloon of text with a leader line back to its anchor.
  callout,

  /// A leader line and arrowhead with no balloon — "this edge, here".
  arrow,

  /// A shaded time span, optionally confined to one signal lane.
  band,
}

/// Where an [Annotation] is attached, in **waveform-data coordinates**.
///
/// Never screen pixels, and never a row *index*: rows reorder, get grouped and
/// get hidden. The vertical identity is a signal's stable scope path, exactly
/// as [CollabPointer.rowId] uses it (`SignalEntry.signalPath`), so the same
/// resolution logic serves both.
sealed class AnnotationAnchor {
  const AnnotationAnchor();

  /// Decodes an anchor, or returns `null` when the payload is unusable.
  ///
  /// Returning `null` rather than throwing is deliberate: a single malformed
  /// annotation must never take a whole session load down with it. The caller
  /// ([Annotation.fromJson]) drops the annotation and logs.
  static AnnotationAnchor? fromJson(Object? json) {
    if (json is! Map) return null;
    final rowId = json['rowId'];
    switch (json['kind']) {
      case 'point':
        final time = json['time'];
        if (time is! int || rowId is! String || rowId.isEmpty) return null;
        return PointAnchor(time: time, rowId: rowId);
      case 'range':
        final start = json['start'];
        final end = json['end'];
        if (start is! int || end is! int) return null;
        if (rowId != null && rowId is! String) return null;
        return RangeAnchor(
          startTime: start,
          endTime: end,
          rowId: rowId as String?,
        );
      default:
        return null;
    }
  }

  Map<String, Object?> toJson();
}

/// A single point in `(tick, signal row)` space.
@immutable
final class PointAnchor extends AnnotationAnchor {
  const PointAnchor({required this.time, required this.rowId});

  /// The waveform **tick** this annotation marks. A tick, never a formatted
  /// time and never seconds — the timescale is a rendering concern, and a
  /// persisted `"1.25 us"` is wrong the moment the timescale changes.
  final int time;

  /// Stable identity of the signal row: `SignalEntry.signalPath`.
  final String rowId;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'point',
    'time': time,
    'rowId': rowId,
  };

  @override
  bool operator ==(Object other) =>
      other is PointAnchor && other.time == time && other.rowId == rowId;

  @override
  int get hashCode => Object.hash('point', time, rowId);

  @override
  String toString() => 'PointAnchor($rowId @ $time)';
}

/// A time span, either across the whole canvas or confined to one lane.
@immutable
final class RangeAnchor extends AnnotationAnchor {
  const RangeAnchor({
    required this.startTime,
    required this.endTime,
    this.rowId,
  });

  final int startTime;
  final int endTime;

  /// The lane this band is confined to, or `null` for a full-height band
  /// across every row — the common "this whole transaction is wrong" case.
  final String? rowId;

  /// Span in ticks, always non-negative regardless of which end was authored
  /// first.
  int get durationTicks => (endTime - startTime).abs();

  /// The earlier of the two ends, so callers never have to normalise.
  int get earliest => startTime <= endTime ? startTime : endTime;

  /// The later of the two ends.
  int get latest => startTime <= endTime ? endTime : startTime;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'range',
    'start': startTime,
    'end': endTime,
    if (rowId != null) 'rowId': rowId,
  };

  @override
  bool operator ==(Object other) =>
      other is RangeAnchor &&
      other.startTime == startTime &&
      other.endTime == endTime &&
      other.rowId == rowId;

  @override
  int get hashCode => Object.hash('range', startTime, endTime, rowId);

  @override
  String toString() => 'RangeAnchor($rowId @ $startTime..$endTime)';
}

/// What the annotated signal was *doing* when the annotation was written.
///
/// This is the mechanism that separates a WaveCrux annotation from a callout
/// drawn on a screenshot. The value is captured once at creation and compared
/// against the live signal on every load: when they disagree, the annotation
/// renders **drifted** rather than silently continuing to assert something the
/// design no longer does. Re-simulate, reopen the session, and the notes that
/// no longer hold flag themselves.
@immutable
final class AnnotationWitness {
  const AnnotationWitness({required this.bits, this.edgeOrdinal});

  /// Reconstructs a witness, or `null` when the payload is unusable.
  static AnnotationWitness? fromJson(Object? json) {
    if (json is! Map) return null;
    final value = json['bits'];
    if (value is! String) return null;
    final ordinal = json['edgeOrdinal'];
    return AnnotationWitness(
      bits: value,
      edgeOrdinal: ordinal is int ? ordinal : null,
    );
  }

  /// The signal's value at the anchored tick as a **canonical bit string**,
  /// left-padded to the signal's declared width (e.g. `"10100011"`).
  ///
  /// Canonical bits rather than a formatted string, and the distinction is
  /// load-bearing. A formatted witness would make drift depend on the *display
  /// format*: flip the row from hex to decimal and every note on it would
  /// report drift while the design underneath had not moved. A badge that
  /// fires on a display preference is a badge users learn to ignore, which
  /// costs more than the feature is worth.
  ///
  /// Padding matters too — VCD writes `b0` where the reader may later see
  /// `00000000`, and comparing those two raw strings would drift on a
  /// difference of notation alone.
  ///
  /// The drift message formats these bits through the row's *current* display
  /// format at render time, so the reader still sees the radix they are
  /// working in.
  final String bits;

  /// Index of the transition at or immediately before the anchored tick.
  ///
  /// Unused in the first release. Stored because it is one integer and because
  /// it is what a future "re-anchor to the corresponding edge" repair needs
  /// when a re-run shifts timing but preserves behaviour — information that
  /// cannot be recovered retroactively once the original dump is gone.
  final int? edgeOrdinal;

  Map<String, Object?> toJson() => {
    'bits': bits,
    if (edgeOrdinal != null) 'edgeOrdinal': edgeOrdinal,
  };

  @override
  bool operator ==(Object other) =>
      other is AnnotationWitness &&
      other.bits == bits &&
      other.edgeOrdinal == edgeOrdinal;

  @override
  int get hashCode => Object.hash(bits, edgeOrdinal);

  @override
  String toString() => 'AnnotationWitness($bits, edge: $edgeOrdinal)';
}

/// A user-authored note drawn on the waveform, anchored to waveform data.
///
/// ### Two coordinate spaces, deliberately separate
///
/// [anchor] is data coordinates — it survives pan, zoom and row reordering.
/// [labelDx] / [labelDy] are **logical pixels relative to the anchor's
/// projected position**, so the balloon stays beside its edge at any zoom
/// without ever being expressed in data space. Dragging a balloon changes the
/// offset; only an explicit re-anchor gesture changes the anchor. Conflating
/// the two is the classic failure of annotation systems — the label either
/// drifts away from what it describes, or cannot be moved out of the way.
///
/// ### No `dart:ui` here
///
/// The offset is two doubles and the colour is a packed int, matching
/// `ParticipantInfo.colorIndex` and `SignalEntry.argbColor`: the domain layer
/// stays free of `dart:ui` so it remains testable without a binding and
/// reusable from non-widget code.
@immutable
final class Annotation {
  const Annotation({
    required this.id,
    required this.shape,
    required this.anchor,
    required this.authorName,
    required this.createdAt,
    this.text = '',
    this.labelDx = 0,
    this.labelDy = -32,
    this.colorRgb,
    this.witness,
    this.layerId,
    this.collapsed = false,
  });

  /// Reconstructs an annotation from [toJson], or returns `null` when the
  /// payload cannot yield a usable annotation (unknown shape, unusable anchor,
  /// missing id).
  ///
  /// Every other field degrades to a default rather than failing, and [text]
  /// is defensively truncated — a hand-edited or hostile document must not be
  /// able to smuggle an unbounded body past the model boundary.
  static Annotation? fromJson(Object? json) {
    if (json is! Map) return null;

    final id = json['id'];
    if (id is! String || id.isEmpty) return null;

    final anchor = AnnotationAnchor.fromJson(json['anchor']);
    if (anchor == null) return null;

    final shapeName = json['shape'];
    final shape = AnnotationShape.values.cast<AnnotationShape?>().firstWhere(
      (s) => s?.name == shapeName,
      orElse: () => null,
    );
    if (shape == null) return null;

    final rawText = json['text'];
    final text = rawText is String ? rawText : '';

    final createdRaw = json['createdAt'];
    final created = createdRaw is String ? DateTime.tryParse(createdRaw) : null;

    return Annotation(
      id: id,
      shape: shape,
      anchor: anchor,
      text: text.length > kAnnotationTextMaxLength
          ? text.substring(0, kAnnotationTextMaxLength)
          : text,
      authorName: json['author'] is String ? json['author'] as String : '',
      createdAt: created ?? DateTime.fromMillisecondsSinceEpoch(0),
      labelDx: (json['labelDx'] as num?)?.toDouble() ?? 0,
      labelDy: (json['labelDy'] as num?)?.toDouble() ?? -32,
      colorRgb: json['colorRgb'] is int ? json['colorRgb'] as int : null,
      witness: AnnotationWitness.fromJson(json['witness']),
      layerId: json['layerId'] is String ? json['layerId'] as String : null,
      collapsed: json['collapsed'] == true,
    );
  }

  /// Stable identity, assigned by the author. Used for de-duplication when the
  /// same annotation arrives from a collaborative session's full-state
  /// rebroadcast.
  final String id;

  final AnnotationShape shape;
  final AnnotationAnchor anchor;

  /// Body text. Empty for [AnnotationShape.arrow].
  final String text;

  /// Display name of whoever wrote it. Travels in the session document and in
  /// any shared bundle — see the share-time disclosure, which offers to strip
  /// it.
  final String authorName;

  /// Local wall-clock creation time. Ordering *within* the waveform is by
  /// anchor tick, not by this; this exists for attribution and for review
  /// minutes.
  final DateTime createdAt;

  /// Label position in logical pixels from the anchor's projected position.
  /// Defaults place the balloon slightly above the anchor.
  final double labelDx;
  final double labelDy;

  /// Packed ARGB colour, or `null` to use the theme's annotation colour.
  ///
  /// Stored as a resolved colour rather than a palette index on purpose. A
  /// collaborator's `colorIndex` is a per-session 0–7 slot that the next
  /// session reassigns; storing the index would silently recolour and
  /// misattribute last week's notes.
  final int? colorRgb;

  /// What the signal was doing at capture time. `null` for annotations created
  /// where no value could be read (an unresolved row).
  final AnnotationWitness? witness;

  /// Owning layer, or `null` for the implicit local "My notes" layer. Set when
  /// a set of annotations is adopted from a collaborative session so the whole
  /// group can be toggled or discarded as a unit.
  final String? layerId;

  /// Whether the canvas draws this as a numbered dot rather than an expanded
  /// balloon. A fold, not a hide — the annotation is still listed, still
  /// exported, still navigable.
  final bool collapsed;

  /// Whether this annotation carries body text worth rendering.
  bool get hasText => text.trim().isNotEmpty;

  /// The tick this annotation sorts by in time order — the anchor point for a
  /// [PointAnchor], the earlier end for a [RangeAnchor]. Walkthrough order and
  /// review-minutes order both use this.
  int get sortTime => switch (anchor) {
    PointAnchor(:final time) => time,
    RangeAnchor(:final earliest) => earliest,
  };

  /// The signal row this annotation is attached to, or `null` for a
  /// full-height band that belongs to no single row.
  String? get rowId => switch (anchor) {
    PointAnchor(:final rowId) => rowId,
    RangeAnchor(:final rowId) => rowId,
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'shape': shape.name,
    'anchor': anchor.toJson(),
    if (text.isNotEmpty) 'text': text,
    if (authorName.isNotEmpty) 'author': authorName,
    'createdAt': createdAt.toIso8601String(),
    if (labelDx != 0) 'labelDx': labelDx,
    if (labelDy != -32) 'labelDy': labelDy,
    if (colorRgb != null) 'colorRgb': colorRgb,
    if (witness != null) 'witness': witness!.toJson(),
    if (layerId != null) 'layerId': layerId,
    if (collapsed) 'collapsed': true,
  };

  Annotation copyWith({
    String? id,
    AnnotationShape? shape,
    AnnotationAnchor? anchor,
    String? text,
    String? authorName,
    DateTime? createdAt,
    double? labelDx,
    double? labelDy,
    int? colorRgb,
    bool clearColor = false,
    AnnotationWitness? witness,
    bool clearWitness = false,
    String? layerId,
    bool clearLayer = false,
    bool? collapsed,
  }) => Annotation(
    id: id ?? this.id,
    shape: shape ?? this.shape,
    anchor: anchor ?? this.anchor,
    text: text ?? this.text,
    authorName: authorName ?? this.authorName,
    createdAt: createdAt ?? this.createdAt,
    labelDx: labelDx ?? this.labelDx,
    labelDy: labelDy ?? this.labelDy,
    colorRgb: clearColor ? null : (colorRgb ?? this.colorRgb),
    witness: clearWitness ? null : (witness ?? this.witness),
    layerId: clearLayer ? null : (layerId ?? this.layerId),
    collapsed: collapsed ?? this.collapsed,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Annotation &&
          other.id == id &&
          other.shape == shape &&
          other.anchor == anchor &&
          other.text == text &&
          other.authorName == authorName &&
          other.createdAt == createdAt &&
          other.labelDx == labelDx &&
          other.labelDy == labelDy &&
          other.colorRgb == colorRgb &&
          other.witness == witness &&
          other.layerId == layerId &&
          other.collapsed == collapsed;

  @override
  int get hashCode => Object.hash(
    id,
    shape,
    anchor,
    text,
    authorName,
    createdAt,
    labelDx,
    labelDy,
    colorRgb,
    witness,
    layerId,
    collapsed,
  );

  @override
  String toString() => 'Annotation($id, ${shape.name}, $anchor)';
}

/// A named, disposable group of annotations adopted from one collaborative
/// session.
///
/// **What makes "keep all" safe a week later.** Twelve notes by three people
/// dropped loose into somebody's document are twelve notes they will never
/// confidently delete, because they cannot tell which ones came from where. As
/// a named unit — *"Design review · its date · 3 participants"* — the same
/// twelve toggle out of sight with one control and delete with one more.
///
/// `null` is the implicit **"My notes"** layer: everything the user wrote
/// themselves, which has no registry entry and cannot be hidden or deleted as a
/// unit. That asymmetry is deliberate — your own notes are not a thing that
/// arrived, so there is nothing to dispose of.
///
/// ### Why the colour is not here
///
/// A layer has no colour. Each adopted annotation carries its author's colour
/// **frozen into [Annotation.colorRgb]** at adoption, because a layer holds
/// notes by several people and the point of the colour is telling them apart.
/// Freezing the resolved value rather than a `colorIndex` is the rule the whole
/// feature turns on: an index is a per-session 0–7 slot, and next week's
/// session reassigns it — storing one would silently recolour and misattribute
/// last week's notes.
@immutable
final class AnnotationLayer {
  const AnnotationLayer({
    required this.id,
    required this.label,
    this.sourceSessionId,
    this.visible = true,
  });

  /// Reconstructs a layer from [toJson], or `null` when the payload cannot
  /// yield a usable one. Tolerant on decode like [Annotation.fromJson]: a
  /// malformed entry is dropped, never thrown, so one bad layer cannot take a
  /// session load down with it.
  static AnnotationLayer? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final label = json['label'];
    if (label is! String) return null;
    return AnnotationLayer(
      id: id,
      label: label,
      sourceSessionId: json['sourceSessionId'] is String
          ? json['sourceSessionId'] as String
          : null,
      // Absent means visible. A layer that defaulted to hidden would make a
      // document quietly lose notes on the first save by an older build.
      visible: json['visible'] != false,
    );
  }

  /// Stable identity, referenced by [Annotation.layerId].
  final String id;

  /// What the panel calls the group — the session's label, its date, and how
  /// many people were in it.
  final String label;

  /// The collaborative session it came from, kept for provenance. Not used for
  /// lookup: a session id means nothing once the session has ended, which is
  /// precisely when this record starts to matter.
  final String? sourceSessionId;

  /// Whether its annotations are drawn. Hiding a layer is not deleting it —
  /// the panel still lists the group so it can be brought back.
  final bool visible;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    if (sourceSessionId != null) 'sourceSessionId': sourceSessionId,
    if (!visible) 'visible': false,
  };

  AnnotationLayer copyWith({
    String? id,
    String? label,
    String? sourceSessionId,
    bool? visible,
  }) => AnnotationLayer(
    id: id ?? this.id,
    label: label ?? this.label,
    sourceSessionId: sourceSessionId ?? this.sourceSessionId,
    visible: visible ?? this.visible,
  );

  @override
  bool operator ==(Object other) =>
      other is AnnotationLayer &&
      other.id == id &&
      other.label == label &&
      other.sourceSessionId == sourceSessionId &&
      other.visible == visible;

  @override
  int get hashCode => Object.hash(id, label, sourceSessionId, visible);

  @override
  String toString() => 'AnnotationLayer($id, "$label", visible: $visible)';
}
