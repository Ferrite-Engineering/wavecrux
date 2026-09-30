// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show ColorScheme;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:wavecrux/core/theme/annotation_colors.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/signal_change.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

/// Radius of an annotation's numbered dot in an exported SVG.
const double _kSvgDotRadius = 9;

/// Balloon geometry in an exported SVG. The character budget is derived from
/// the width at 11 px monospace — SVG has no text flow, so the wrap is
/// computed rather than delegated.
const double _kSvgBalloonWidth = 190;
const int _kSvgBalloonChars = 26;
const int _kSvgBalloonLines = 4;
const double _kSvgLineHeight = 13;

/// Breathing room below the lowest thing an SVG draws.
///
/// The document is sized to its content rather than to its lane count, so a
/// balloon dragged below the last lane ends flush with the viewBox without it.
const double _kSvgDocumentMargin = 8;

/// The colours an SVG export draws with.
///
/// **Why this exists.** The emitter used to bake ten hex literals, so an export
/// never looked like the app it came from — a blue-tinted document out of a
/// neutral-dark viewer, with every annotation in one fixed blue. The last of
/// those is the one that mattered: an annotation's colour *is* its author in a
/// collaborative session, so a single baked accent flattens a room's worth of
/// attribution into one indistinguishable hue the moment it is exported.
///
/// Defaults reproduce the old literals exactly, so a caller that supplies
/// nothing — a test, or a headless path with no theme in scope — emits the
/// document it always did.
class SvgExportPalette {
  const SvgExportPalette({
    this.background = '#1a1a2e',
    this.rulerBand = '#252540',
    this.laneBand = '#1e1e32',
    this.gridStrong = '#555577',
    this.gridWeak = '#333355',
    this.mutedText = '#8888bb',
    this.text = '#e6e6f0',
    this.annotationDefault = '#7AA2F7',
  });

  /// Builds a palette from the live theme, so the document matches the viewer.
  ///
  /// [annotationDefault] takes the theme's primary because that is exactly what
  /// the canvas gives a note carrying no colour of its own — see
  /// `AnnotationOverlay._colorFor`. A note that *does* carry one keeps it; this
  /// only decides the fallback.
  factory SvgExportPalette.fromScheme(ColorScheme scheme) => SvgExportPalette(
    background: _hex(scheme.surface),
    rulerBand: _hex(scheme.surfaceContainerHighest),
    laneBand: _hex(scheme.surfaceContainerHigh),
    gridStrong: _hex(scheme.outline),
    gridWeak: _hex(scheme.outlineVariant),
    mutedText: _hex(scheme.onSurfaceVariant),
    text: _hex(scheme.onSurface),
    annotationDefault: _hex(scheme.primary),
  );

  final String background;
  final String rulerBand;
  final String laneBand;
  final String gridStrong;
  final String gridWeak;
  final String mutedText;
  final String text;
  final String annotationDefault;

  static String _hex(Color c) {
    final argb = c.toARGB32();
    final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return '#$rgb';
  }
}

/// Exports the waveform view as a raster (PNG) or vector (SVG) image.
///
/// **PNG export** captures the live Flutter widget tree using a
/// [RenderRepaintBoundary] key and encodes the result to PNG bytes.
///
/// **SVG export** generates a standalone SVG document from waveform data.
/// It does not require a widget tree — only a [WaveformDataSource], a
/// [SignalGroup], and a [TimeMapper] describing the visible viewport.
class ImageExportService {
  const ImageExportService();

  // ── PNG ──────────────────────────────────────────────────────────────────────

  /// Captures the widget identified by [boundaryKey] as raw PNG bytes.
  ///
  /// [boundaryKey] must be attached to a [RepaintBoundary] widget in the live
  /// widget tree. Throws [ImageCaptureException] if the boundary is not found
  /// or rendering fails.
  ///
  /// [background] is painted underneath the capture. **Not optional in
  /// practice.** Parts of the waveform view do not paint a background of their
  /// own — the signal-list header among them — and rely on an ancestor that
  /// sits *outside* the boundary. `toImage` leaves those pixels fully
  /// transparent, so a measured export came back with 82,190 alpha-0 pixels
  /// concentrated in the top strip, which reads as white boxes anywhere the
  /// image lands on a light ground. Passing the viewer's own surface colour
  /// keeps a dark-theme export dark.
  Future<Uint8List> capturePng(
    GlobalKey boundaryKey, {
    double pixelRatio = 2.0,
    Color? background,
  }) async {
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw const ImageCaptureException(
        'RepaintBoundary not found — ensure the key is attached to a '
        'RepaintBoundary widget that is currently mounted.',
      );
    }
    var image = await renderObject.toImage(pixelRatio: pixelRatio);
    if (background != null) {
      final flattened = _composite(image, background);
      image.dispose();
      image = flattened;
    }
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) {
      throw const ImageCaptureException('toByteData returned null');
    }
    return byteData.buffer.asUint8List();
  }

  /// Captures the widget identified by [boundaryKey] and writes PNG to [path].
  ///
  /// Throws [ImageCaptureException] on render failure or [ImageWriteException]
  /// on I/O failure.
  Future<void> exportPng(
    GlobalKey boundaryKey,
    String path, {
    double pixelRatio = 2.0,
    Color? background,
  }) async {
    final bytes = await capturePng(
      boundaryKey,
      pixelRatio: pixelRatio,
      background: background,
    );
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } on IOException catch (e) {
      throw ImageWriteException(path, e.toString());
    }
  }

  /// Draws [image] over an opaque [background] of the same size.
  ///
  /// Synchronous `Picture` rasterisation rather than a second async hop: the
  /// caller is already awaiting, and `toImageSync` keeps the whole capture on
  /// one frame's worth of GPU work.
  ui.Image _composite(ui.Image image, Color background) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas
      ..drawRect(size, Paint()..color = background)
      ..drawImage(image, Offset.zero, Paint());
    final picture = recorder.endRecording();
    final out = picture.toImageSync(image.width, image.height);
    picture.dispose();
    return out;
  }

  // ── SVG ──────────────────────────────────────────────────────────────────────

  /// Generates an SVG document representing the waveform view.
  ///
  /// [signalGroup] determines which signals appear; [signalMap] provides
  /// Variable metadata (name, bitWidth) for each signal ref. [timeMapper]
  /// defines the visible time window and x-coordinate mapping.
  ///
  /// [svgWidth] and [svgHeight] are the document dimensions in SVG user units
  /// (equivalent to CSS px). [laneHeight] is the per-signal row height.
  String generateSvg({
    required WaveformDataSource source,
    required SignalGroup signalGroup,
    required Map<String, Variable> signalMap,
    required TimeMapper timeMapper,
    double svgWidth = 1200,
    double svgHeight = 600,
    double laneHeight = 30,
    double labelWidth = 160,
    double rulerHeight = 24,
    List<Annotation> annotations = const <Annotation>[],
    Map<String, AnnotationStatus> annotationStatuses =
        const <String, AnnotationStatus>{},
    SvgExportPalette palette = const SvgExportPalette(),
    String Function(int tick)? formatTime,
  }) {
    final visibleStart = timeMapper.visibleStartTime;
    final visibleEnd = timeMapper.visibleEndTime;
    final waveWidth = svgWidth - labelWidth;

    final signals = <SignalEntry>[];
    void collectSignals(List<SignalEntry> entries) {
      for (final e in entries) {
        if (e.kind == SignalEntryKind.signal) {
          signals.add(e);
        } else if (e.kind == SignalEntryKind.group) {
          collectSignals(e.children);
        }
      }
    }

    collectSignals(signalGroup.entries);

    // The lane area is what the signals occupy. Annotations are laid out
    // against it, and the document then grows to whatever they reach — a
    // balloon dragged below the last lane used to be clipped by a viewBox
    // sized from the lane count alone.
    final laneAreaHeight = rulerHeight + signals.length * laneHeight;

    // Built before the header on purpose: the emitter reports how far down it
    // actually drew, and only then can the document be sized to contain it.
    // Written last, so annotations still paint over the traces.
    final (annotationSvg, annotationBottom) = _buildSvgAnnotations(
      annotations,
      annotationStatuses,
      signals,
      visibleStart,
      visibleEnd,
      labelWidth,
      waveWidth,
      rulerHeight,
      laneHeight,
      laneAreaHeight,
      palette,
    );
    final documentHeight = math.max(
      svgHeight,
      annotationBottom + _kSvgDocumentMargin,
    );

    final buf = StringBuffer()
      ..write(_buildSvgHeader(svgWidth, documentHeight, palette))
      ..write(
        _buildSvgRuler(
          visibleStart,
          visibleEnd,
          labelWidth,
          waveWidth,
          rulerHeight,
          palette,
          formatTime,
        ),
      )
      ..write(
        _buildSvgSignals(
          signals,
          signalMap,
          source,
          visibleStart,
          visibleEnd,
          labelWidth,
          waveWidth,
          rulerHeight,
          laneHeight,
          palette,
        ),
      )
      ..write(annotationSvg)
      ..writeln('</svg>');
    return buf.toString();
  }

  /// Generates SVG and writes it to [path].
  Future<void> exportSvg({
    required WaveformDataSource source,
    required SignalGroup signalGroup,
    required Map<String, Variable> signalMap,
    required TimeMapper timeMapper,
    required String path,
    double svgWidth = 1200,
    double svgHeight = 600,
    double laneHeight = 30,
    double labelWidth = 160,
    double rulerHeight = 24,
    List<Annotation> annotations = const <Annotation>[],
    Map<String, AnnotationStatus> annotationStatuses =
        const <String, AnnotationStatus>{},
    SvgExportPalette palette = const SvgExportPalette(),
    String Function(int tick)? formatTime,
  }) async {
    final content = generateSvg(
      source: source,
      signalGroup: signalGroup,
      signalMap: signalMap,
      timeMapper: timeMapper,
      svgWidth: svgWidth,
      svgHeight: svgHeight,
      laneHeight: laneHeight,
      labelWidth: labelWidth,
      rulerHeight: rulerHeight,
      annotations: annotations,
      annotationStatuses: annotationStatuses,
      palette: palette,
      formatTime: formatTime,
    );
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(content, flush: true);
    } on IOException catch (e) {
      throw ImageWriteException(path, e.toString());
    }
  }

  // ── SVG builders ──────────────────────────────────────────────────────────────

  String _buildSvgHeader(double width, double height, SvgExportPalette p) =>
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<svg xmlns="http://www.w3.org/2000/svg"'
      ' width="$width" height="$height"'
      ' viewBox="0 0 $width $height">\n'
      '<rect width="$width" height="$height" fill="${p.background}"/>\n'
      '<style>text {'
      ' font-family: "JetBrains Mono","Fira Code",monospace;'
      ' }</style>\n';

  String _buildSvgRuler(
    int visibleStart,
    int visibleEnd,
    double labelWidth,
    double waveWidth,
    double rulerHeight,
    SvgExportPalette p,
    String Function(int tick)? formatTime,
  ) {
    final range = visibleEnd - visibleStart;
    if (range <= 0) return '';

    final buf = StringBuffer()
      ..writeln(
        '<rect x="$labelWidth" y="0"'
        ' width="$waveWidth" height="$rulerHeight"'
        ' fill="${p.rulerBand}"/>',
      );

    const tickCount = 8;
    final tickInterval = range ~/ tickCount;
    if (tickInterval <= 0) return buf.toString();

    for (var i = 0; i <= tickCount; i++) {
      final tickTime = visibleStart + i * tickInterval;
      final x = labelWidth + (tickTime - visibleStart) / range * waveWidth;
      buf
        ..writeln(
          '<line x1="$x" y1="0" x2="$x" y2="$rulerHeight"'
          ' stroke="${p.gridStrong}" stroke-width="1"/>',
        )
        ..writeln(
          '<text x="$x" y="${rulerHeight - 4}"'
          ' font-size="9" fill="${p.mutedText}"'
          ' text-anchor="middle">'
          '${_escapeXml(formatTime?.call(tickTime) ?? '$tickTime')}</text>',
        );
    }
    return buf.toString();
  }

  String _buildSvgSignals(
    List<SignalEntry> signals,
    Map<String, Variable> signalMap,
    WaveformDataSource source,
    int visibleStart,
    int visibleEnd,
    double labelWidth,
    double waveWidth,
    double rulerHeight,
    double laneHeight,
    SvgExportPalette p,
  ) {
    final range = visibleEnd - visibleStart;
    if (range <= 0) return '';

    final buf = StringBuffer();

    for (var i = 0; i < signals.length; i++) {
      final entry = signals[i];
      final ref = entry.signalRef;
      if (ref == null) continue;

      final y = rulerHeight + i * laneHeight;
      final signalColor = _argbToSvgColor(entry.argbColor ?? 0xff00ff88);
      final label = entry.displayName ?? signalMap[ref]?.name ?? ref;

      if (i.isOdd) {
        buf.writeln(
          '<rect x="0" y="$y"'
          ' width="${labelWidth + waveWidth}" height="$laneHeight"'
          ' fill="${p.laneBand}"/>',
        );
      }

      buf
        ..writeln(
          '<line x1="0" y1="${y + laneHeight}"'
          ' x2="${labelWidth + waveWidth}" y2="${y + laneHeight}"'
          ' stroke="${p.gridWeak}" stroke-width="0.5"/>',
        )
        ..writeln(
          '<text x="${labelWidth - 6}" y="${y + laneHeight / 2 + 4}"'
          ' font-size="11" fill="$signalColor" text-anchor="end">'
          '${_sanitizeSvgText(label)}</text>',
        );

      if (source.isSignalLoaded(ref)) {
        final variable = signalMap[ref];
        final bitWidth = variable?.bitWidth ?? 1;
        final isReal = variable?.isReal ?? false;
        buf.write(
          _buildSvgTrace(
            source,
            ref,
            visibleStart,
            visibleEnd,
            range,
            labelWidth,
            waveWidth,
            y,
            laneHeight,
            signalColor,
            bitWidth,
            isReal,
          ),
        );
      }
    }

    buf.writeln(
      '<defs><clipPath id="label-clip">'
      ' <rect x="0" y="0" width="$labelWidth" height="100%"/></clipPath></defs>',
    );
    return buf.toString();
  }

  String _buildSvgTrace(
    WaveformDataSource source,
    String ref,
    int visibleStart,
    int visibleEnd,
    int range,
    double labelWidth,
    double waveWidth,
    double laneY,
    double laneHeight,
    String color,
    int bitWidth,
    bool isReal,
  ) {
    final changes = source.changesInRange(ref, visibleStart, visibleEnd + 1);
    if (changes.isEmpty) return '';

    final startValue = source.valueAt(ref, visibleStart);

    double timeToX(int t) =>
        labelWidth + (t - visibleStart).toDouble() / range * waveWidth;

    if (bitWidth == 1 && !isReal) {
      return _buildSvgScalarTrace(
        changes,
        startValue,
        visibleStart,
        visibleEnd,
        laneY,
        laneHeight,
        color,
        timeToX,
      );
    }
    return _buildSvgVectorTrace(
      changes,
      startValue,
      visibleStart,
      visibleEnd,
      laneY,
      laneHeight,
      color,
      timeToX,
    );
  }

  String _buildSvgScalarTrace(
    List<SignalChange> changes,
    String? startValue,
    int visibleStart,
    int visibleEnd,
    double laneY,
    double laneHeight,
    String color,
    double Function(int) timeToX,
  ) {
    var currentValue = startValue ?? 'x';
    var currentTime = visibleStart;
    final top = laneY + laneHeight * 0.1;
    final bot = laneY + laneHeight * 0.9;
    final mid = laneY + laneHeight / 2;

    String segmentSvg(int fromTime, int toTime, String value) {
      final x1 = timeToX(fromTime);
      final x2 = timeToX(toTime);
      final v = value.toLowerCase();
      if (v == '1') {
        return '<line x1="$x1" y1="$top" x2="$x2" y2="$top"'
            ' stroke="$color" stroke-width="1.5"/>\n';
      }
      if (v == '0') {
        return '<line x1="$x1" y1="$bot" x2="$x2" y2="$bot"'
            ' stroke="$color" stroke-width="1.5"/>\n';
      }
      final xColor = v == 'x' ? '#ff4444' : '#44ff88';
      return '<line x1="$x1" y1="$mid" x2="$x2" y2="$mid"'
          ' stroke="$xColor" stroke-width="1.5" stroke-dasharray="4 2"/>\n';
    }

    final buf = StringBuffer();
    for (final change in changes) {
      buf.write(segmentSvg(currentTime, change.time, currentValue));
      final x = timeToX(change.time);
      buf.writeln(
        '<line x1="$x" y1="$top" x2="$x" y2="$bot"'
        ' stroke="$color" stroke-width="1"/>',
      );
      currentValue = change.value;
      currentTime = change.time;
    }
    buf.write(segmentSvg(currentTime, visibleEnd, currentValue));
    return buf.toString();
  }

  String _buildSvgVectorTrace(
    List<SignalChange> changes,
    String? startValue,
    int visibleStart,
    int visibleEnd,
    double laneY,
    double laneHeight,
    String color,
    double Function(int) timeToX,
  ) {
    var currentValue = startValue ?? 'x';
    var currentTime = visibleStart;
    final top = laneY + laneHeight * 0.1;
    final bot = laneY + laneHeight * 0.9;
    final mid = laneY + laneHeight / 2;
    const slant = 4.0;

    String boxSvg(int fromTime, int toTime, String value) {
      final x1 = timeToX(fromTime);
      final x2 = timeToX(toTime);
      if (x2 - x1 < 2) return '';
      final v = value.toLowerCase();
      final fillColor = v.contains('x') ? '#440000' : '#001a00';
      final strokeColor = v.contains('x') ? '#ff4444' : color;
      final path =
          'M ${x1 + slant},$top'
          ' L ${x2 - slant},$top'
          ' L $x2,$mid'
          ' L ${x2 - slant},$bot'
          ' L ${x1 + slant},$bot'
          ' L $x1,$mid Z';
      return '<path d="$path" fill="$fillColor"'
          ' stroke="$strokeColor" stroke-width="1"/>\n'
          '<text x="${(x1 + x2) / 2}" y="${mid + 4}"'
          ' font-size="9" fill="$strokeColor" text-anchor="middle">'
          '${_sanitizeSvgText(v)}</text>\n';
    }

    final buf = StringBuffer();
    for (final change in changes) {
      buf.write(boxSvg(currentTime, change.time, currentValue));
      currentValue = change.value;
      currentTime = change.time;
    }
    buf.write(boxSvg(currentTime, visibleEnd, currentValue));
    return buf.toString();
  }

  // ── utilities ─────────────────────────────────────────────────────────────────

  // ── SVG annotations ───────────────────────────────────────────────────────────

  /// Emits the annotation layer.
  ///
  /// Unlike PNG — a `RepaintBoundary` capture that gets the overlay for free —
  /// SVG is hand-written, so every shape has to be stated here. The rules
  /// mirror the canvas overlay deliberately: an exported vector that disagreed
  /// with the screen about which notes are drawn, or about which ones have
  /// drifted, would be worse than one that omitted them.
  ///
  /// Orphaned and unresolved annotations draw NOTHING, exactly as on canvas.
  /// The panel owns them; piling them on an edge of a static document that has
  /// no panel would be noise a reader cannot resolve.
  /// Emits the annotation layer, and reports the lowest y it drew to.
  ///
  /// The second element is what lets the document be sized to contain its own
  /// content: a balloon hangs below the lane it points at, so the lane count
  /// alone cannot say how tall the document needs to be.
  (String, double) _buildSvgAnnotations(
    List<Annotation> annotations,
    Map<String, AnnotationStatus> statuses,
    List<SignalEntry> signals,
    int visibleStart,
    int visibleEnd,
    double labelWidth,
    double waveWidth,
    double rulerHeight,
    double laneHeight,
    double laneAreaHeight,
    SvgExportPalette p,
  ) {
    if (annotations.isEmpty) return ('', laneAreaHeight);
    final range = visibleEnd - visibleStart;
    if (range <= 0) return ('', laneAreaHeight);

    // Grows as balloons are placed; seeded with the lanes so a document with no
    // annotation below them keeps exactly the height it had before.
    var bottom = laneAreaHeight;

    double timeToX(int t) =>
        labelWidth + (t - visibleStart).toDouble() / range * waveWidth;

    // Row index by stable path, so a note follows its signal's position in the
    // exported document the same way it follows the lane on screen.
    final rowIndex = <String, int>{};
    for (var i = 0; i < signals.length; i++) {
      final path = signals[i].signalPath;
      if (path != null) rowIndex[path] = i;
    }

    // Ordered by tick so the numbering in the document matches the panel's.
    final ordered = [...annotations]
      ..sort((a, b) {
        final byTime = a.sortTime.compareTo(b.sortTime);
        return byTime != 0 ? byTime : a.createdAt.compareTo(b.createdAt);
      });

    final buf = StringBuffer();
    for (var i = 0; i < ordered.length; i++) {
      final annotation = ordered[i];
      final status = statuses[annotation.id];
      if (status == AnnotationStatus.orphaned ||
          status == AnnotationStatus.unresolved) {
        continue;
      }
      final drifted = status == AnnotationStatus.drifted;
      // Both values come from `core/theme/annotation_colors.dart` so the
      // document and the canvas cannot drift apart about which notes have.
      final color = drifted
          ? _argbToSvgColor(kAnnotationDriftedColor.toARGB32())
          : _argbToSvgColor(
              annotation.colorRgb,
              fallback: p.annotationDefault,
            );

      final rowId = annotation.rowId;
      final row = rowId == null ? null : rowIndex[rowId];
      // A note on a row that is not in this export has nothing to attach to.
      if (rowId != null && row == null) continue;

      switch (annotation.anchor) {
        case RangeAnchor(:final earliest, :final latest):
          final x0 = timeToX(earliest.clamp(visibleStart, visibleEnd));
          final x1 = timeToX(latest.clamp(visibleStart, visibleEnd));
          if (latest < visibleStart || earliest > visibleEnd) continue;
          final top = row == null
              ? rulerHeight
              : rulerHeight + row * laneHeight;
          final height = row == null
              ? laneAreaHeight - rulerHeight
              : laneHeight;
          buf.write(
            _svgBand(
              x0: x0,
              x1: x1,
              top: top,
              height: height,
              color: color,
              label: annotation.hasText ? annotation.text : null,
            ),
          );

        case PointAnchor(:final time):
          if (time < visibleStart || time > visibleEnd) continue;
          final anchorX = timeToX(time);
          final anchorY = rulerHeight + row! * laneHeight + laneHeight / 2;
          final labelX = anchorX + annotation.labelDx;
          // Only a floor. The old ceiling clamped the balloon's TOP to the
          // document height, which says nothing about where its BOTTOM lands —
          // a 62 px balloon pinned at `height - 2` drew 60 px past the viewBox
          // and was silently cut off. The document grows to fit instead, so a
          // note stays where the author dragged it.
          final labelY = math.max<double>(2, anchorY + annotation.labelDy);
          bottom = math.max(bottom, labelY + _svgBalloonHeight(annotation));
          buf.write(
            _svgLeader(
              fromX: anchorX,
              fromY: anchorY,
              toX: labelX,
              toY: labelY,
              color: color,
              dashed: drifted,
              arrowhead: annotation.shape == AnnotationShape.arrow,
            ),
          );
          if (annotation.shape == AnnotationShape.arrow) continue;

          final collapsed = annotation.collapsed || !annotation.hasText;
          buf.write(
            collapsed
                ? _svgCollapsedDot(labelX, labelY, color, i + 1, p)
                : _svgBalloon(
                    x: labelX,
                    y: labelY,
                    color: color,
                    number: i + 1,
                    text: annotation.text,
                    drifted: drifted,
                    p: p,
                  ),
          );
      }
    }
    return (buf.toString(), bottom);
  }

  /// How tall [annotation] will draw, matching [_svgBalloon]'s own arithmetic.
  double _svgBalloonHeight(Annotation annotation) {
    if (annotation.shape == AnnotationShape.arrow) return _kSvgDotRadius * 2;
    if (annotation.collapsed || !annotation.hasText) return _kSvgDotRadius * 2;
    final lines = _wrapSvgText(
      annotation.text,
      _kSvgBalloonChars,
      _kSvgBalloonLines,
    );
    return 10 + lines.length * _kSvgLineHeight;
  }

  String _svgBand({
    required double x0,
    required double x1,
    required double top,
    required double height,
    required String color,
    required String? label,
  }) {
    final width = math.max<double>(1, x1 - x0);
    final buf = StringBuffer()
      ..writeln(
        '<rect x="$x0" y="$top" width="$width" height="$height"'
        ' fill="$color" fill-opacity="0.14"'
        ' stroke="$color" stroke-width="1.5"/>',
      );
    if (label != null) {
      buf.writeln(
        '<text x="${x0 + width / 2}" y="${top + 12}"'
        ' font-size="10" font-weight="600" fill="$color"'
        ' text-anchor="middle">${_escapeXml(label)}</text>',
      );
    }
    return buf.toString();
  }

  String _svgLeader({
    required double fromX,
    required double fromY,
    required double toX,
    required double toY,
    required String color,
    required bool dashed,
    required bool arrowhead,
  }) {
    final dash = dashed ? ' stroke-dasharray="4 3"' : '';
    final buf = StringBuffer()
      ..writeln(
        '<line x1="$fromX" y1="$fromY" x2="$toX" y2="$toY"'
        ' stroke="$color" stroke-width="1.2"$dash/>',
      )
      ..writeln(
        '<circle cx="$fromX" cy="$fromY" r="3" fill="$color"/>',
      );
    if (arrowhead) {
      // Pointing back at the anchor: an arrow annotation means "this edge,
      // here", so the head belongs on the waveform end rather than on the
      // label end the user dragged.
      final dx = fromX - toX;
      final dy = fromY - toY;
      final length = math.sqrt(dx * dx + dy * dy);
      if (length > 0) {
        const size = 7;
        final ux = dx / length;
        final uy = dy / length;
        final baseX = fromX - ux * size;
        final baseY = fromY - uy * size;
        // Perpendicular, half the head's width either side of the shaft.
        final px = -uy * size * 0.45;
        final py = ux * size * 0.45;
        buf.writeln(
          '<path d="M $fromX $fromY'
          ' L ${baseX + px} ${baseY + py}'
          ' L ${baseX - px} ${baseY - py} Z" fill="$color"/>',
        );
      }
    }
    return buf.toString();
  }

  String _svgCollapsedDot(
    double x,
    double y,
    String color,
    int number,
    SvgExportPalette p,
  ) =>
      '<circle cx="$x" cy="$y" r="$_kSvgDotRadius" fill="$color"/>\n'
      '<text x="$x" y="${y + 3.5}" font-size="10" font-weight="600"'
      ' fill="${p.background}" text-anchor="middle">$number</text>\n';

  /// A balloon: box, number dot, and the body wrapped by hand.
  ///
  /// SVG has no text flow, so the wrap is computed here rather than left to
  /// the renderer. The same four-line cap the canvas applies is kept, so a
  /// long note reads identically in both.
  String _svgBalloon({
    required double x,
    required double y,
    required String color,
    required int number,
    required String text,
    required bool drifted,
    required SvgExportPalette p,
  }) {
    final lines = _wrapSvgText(text, _kSvgBalloonChars, _kSvgBalloonLines);
    final height = 10.0 + lines.length * _kSvgLineHeight;
    final style = drifted ? ' font-style="italic"' : '';

    final buf = StringBuffer()
      ..writeln(
        '<rect x="$x" y="$y" width="$_kSvgBalloonWidth" height="$height"'
        ' rx="4" fill="${p.background}" fill-opacity="0.92"'
        ' stroke="$color" stroke-width="1.5"/>',
      )
      ..writeln(
        '<circle cx="${x + 11}" cy="${y + 11}" r="$_kSvgDotRadius"'
        ' fill="$color"/>',
      )
      ..writeln(
        '<text x="${x + 11}" y="${y + 14.5}" font-size="10" font-weight="600"'
        ' fill="${p.background}" text-anchor="middle">$number</text>',
      );
    for (var i = 0; i < lines.length; i++) {
      buf.writeln(
        '<text x="${x + 24}" y="${y + 14 + i * _kSvgLineHeight}"'
        ' font-size="11" fill="${p.text}"$style>${_escapeXml(lines[i])}</text>',
      );
    }
    return buf.toString();
  }

  /// Greedy word wrap to [charsPerLine], capped at [maxLines] with an ellipsis.
  static List<String> _wrapSvgText(
    String text,
    int charsPerLine,
    int maxLines,
  ) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length <= charsPerLine) {
        current = candidate;
        continue;
      }
      if (current.isNotEmpty) lines.add(current);
      // A single word longer than the line is hard-split rather than allowed
      // to overflow the balloon it is supposed to sit inside.
      current = word;
      while (current.length > charsPerLine) {
        lines.add(current.substring(0, charsPerLine));
        current = current.substring(charsPerLine);
      }
    }
    if (current.isNotEmpty) lines.add(current);
    if (lines.isEmpty) return const <String>[];
    if (lines.length <= maxLines) return lines;
    final capped = lines.take(maxLines).toList();
    capped[maxLines - 1] = '${capped[maxLines - 1]}…';
    return capped;
  }

  /// An ARGB int as an SVG colour, or [fallback] when there is no colour.
  ///
  /// A note carrying its own `colorRgb` — an author's session colour — keeps
  /// it. Only the absent case falls back, and the fallback is the theme's
  /// primary, which is exactly what the canvas draws such a note in.
  String _argbToSvgColor(int? argb, {String fallback = '#7AA2F7'}) {
    if (argb == null) return fallback;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return 'rgb($r,$g,$b)';
  }

  /// Signal-label text: truncated to fit the label gutter, then escaped.
  ///
  /// Truncation is a *label* concern and must not leak onto annotation bodies,
  /// which are prose the user wrote and expects to read back — see
  /// [_escapeXml], which does the escaping without shortening anything.
  String _sanitizeSvgText(String value) {
    const maxLen = 10;
    final truncated = value.length > maxLen
        ? '${value.substring(0, maxLen - 1)}…'
        : value;
    return _escapeXml(truncated);
  }

  /// Escapes arbitrary user text for an SVG text node *or* attribute value.
  ///
  /// Annotation bodies are free prose about a design: they routinely contain
  /// `<`, `&`, `>` and both kinds of quote (`a < b`, `req && ack`, `the "ack"
  /// that never arrives`). Emitting any of those raw produces a document that
  /// silently fails to parse in a browser, which is exactly where a shared SVG
  /// gets opened. Quotes are escaped as well as the three text-node
  /// metacharacters so the same helper is safe in an attribute.
  static String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

/// Thrown when PNG capture fails (e.g., no RepaintBoundary, render error).
class ImageCaptureException implements Exception {
  const ImageCaptureException(this.message);

  final String message;

  @override
  String toString() => 'ImageCaptureException: $message';
}

/// Thrown when writing an image file to disk fails.
class ImageWriteException implements Exception {
  const ImageWriteException(this.path, this.reason);

  final String path;
  final String reason;

  @override
  String toString() => 'ImageWriteException($path): $reason';
}
