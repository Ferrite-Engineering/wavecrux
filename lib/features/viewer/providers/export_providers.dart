// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math' as math;

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/providers/browser_download_provider.dart';
import 'package:wavecrux/core/providers/system_dialog_provider.dart';
import 'package:wavecrux/core/theme/wavecrux_colors.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/signal_group.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/export_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/annotations/annotation_witness_service.dart';
import 'package:wavecrux/services/export/image_export_service.dart';
import 'package:wavecrux/services/export/saif_statistics.dart';
import 'package:wavecrux/services/export/saif_writer.dart';
import 'package:wavecrux/services/time_format/time_format_service.dart';
import 'package:wavecrux/services/vcd_writer/vcd_writer_service.dart';
import 'package:wavecrux/services/waveform_geom/time_mapper.dart';

part 'export_providers.g.dart';

/// Type signature for the OS save-file picker used by the export flows.
///
/// `file_picker` 12 made `FilePicker.saveFile` a static method, so it can no
/// longer be replaced via `FilePicker.platform = mock`. Tests inject a stub
/// through [saveFilePickerProvider] instead — the same injectable-function
/// pattern the workspace commands (`SaveAsPicker`/`OpenWorkspacePicker`) use.
typedef SaveFilePicker =
    Future<String?> Function({
      required String dialogTitle,
      required String fileName,
      required List<String> allowedExtensions,
      required FileType type,
    });

/// Default [SaveFilePicker] backed by the static `FilePicker.saveFile`.
///
/// `file_picker` 12 made `bytes` a required argument and writes the file for
/// you. We pass an empty list so the dialog returns the chosen path *without*
/// writing anything — `saveBytesToFile` is a no-op for empty bytes — and the
/// export then streams the real content to that path via its writer service
/// (`VcdWriterService` / `ImageExportService`), preserving the prior
/// pick-path-then-write architecture and avoiding buffering large exports in
/// memory.
Future<String?> defaultSaveFilePicker({
  required String dialogTitle,
  required String fileName,
  required List<String> allowedExtensions,
  required FileType type,
}) => FilePicker.saveFile(
  dialogTitle: dialogTitle,
  fileName: fileName,
  allowedExtensions: allowedExtensions,
  type: type,
  bytes: Uint8List(0),
);

/// Provides the [SaveFilePicker] used by [ExportNotifier]. Override in tests to
/// avoid touching the native OS save dialog.
final saveFilePickerProvider = Provider<SaveFilePicker>(
  (ref) => defaultSaveFilePicker,
);

/// Drives all export actions (VCD, PNG, SVG) for the waveform viewer.
///
/// Call [showExportDialog] with a [BuildContext] to open the export settings
/// dialog and trigger the file-save flow. The notifier holds no persistent
/// state — it is a thin action coordinator.
///
/// `keepAlive: true` because Riverpod 3 disposes auto-dispose notifiers
/// immediately on the absence of a listener. Callers read this via
/// `ref.read(exportProvider.notifier).showExportDialog(…)` without
/// subscribing, then await; under default auto-dispose the notifier's
/// own `ref` becomes unmounted mid-call and throws
/// `UnmountedRefException`. An action-coordinator notifier with no state
/// has no reason to be auto-dispose anyway.
@Riverpod(keepAlive: true)
class ExportNotifier extends _$ExportNotifier {
  @override
  void build() {}

  // ── public API ────────────────────────────────────────────────────────────────

  /// Opens the export dialog, collects user settings, and runs the export.
  ///
  /// [waveformRepaintKey] is the [GlobalKey] attached to the waveform
  /// [RepaintBoundary]; it is needed only for PNG capture.
  Future<void> showExportDialog(
    BuildContext context, {
    GlobalKey? waveformRepaintKey,
  }) async {
    final source = ref.read(waveformSourceProvider).value;
    if (source == null) {
      if (context.mounted) {
        showCruxErrorSnack(context, L10N.of(context).exportErrorNoFile);
      }
      return;
    }

    if (!context.mounted) return;
    final result = await ExportDialog.show(context);
    if (result == null || !context.mounted) return;

    switch (result.format) {
      case ExportFormat.vcd:
        await _exportVcd(context, source, result);
      case ExportFormat.saif:
        await _exportSaif(context, source, result);
      case ExportFormat.png:
        await _exportPng(context, result, waveformRepaintKey);
      case ExportFormat.svg:
        await _exportSvg(context, source, result);
    }
  }

  /// Copies the formatted value of [signalRef] at cursor time to clipboard.
  ///
  /// Reads the value from the currently active [WaveformDataSource] and
  /// formats it via the `TranslatorRegistry` (built-in translator) using the
  /// signal's current format from [SignalGroupsNotifier]. The already-formatted
  /// [formattedValue] is passed in by the caller.
  Future<void> copySignalValue(
    BuildContext context,
    String signalRef,
    String formattedValue,
  ) async {
    await Clipboard.setData(ClipboardData(text: formattedValue));
    if (context.mounted) {
      showCruxInfoSnack(context, L10N.of(context).signalListCopied);
    }
  }

  /// Copies the full hierarchical path of [signalRef] to clipboard.
  Future<void> copySignalPath(
    BuildContext context,
    String fullPath,
  ) async {
    await Clipboard.setData(ClipboardData(text: fullPath));
    if (context.mounted) {
      showCruxInfoSnack(context, L10N.of(context).signalListCopied);
    }
  }

  // ── telemetry ─────────────────────────────────────────────────────────────────

  /// Records `export.completed` after a writer has returned without throwing.
  ///
  /// Deliberately not recorded from [showExportDialog]'s switch, which is
  /// reached by every *attempt*: the three writers all end in a cancelled save
  /// picker or a write exception often enough that counting dispatches would
  /// answer a different question from "which export paths earn investment".
  /// Called before the success snack and outside its `context.mounted` guard —
  /// the export happened whether or not the tab survived long enough to say so.
  ///
  /// [ExportFormat]'s constants are already lowercase, so `.name` satisfies the
  /// ingestion Worker's property-value class without a snake-casing pass.
  void _recordExportCompleted(ExportFormat kind) {
    ref
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'export.completed',
            properties: <String, Object?>{'kind': kind.name},
          ),
        );
  }

  // ── VCD export ────────────────────────────────────────────────────────────────

  Future<void> _exportVcd(
    BuildContext context,
    WaveformDataSource source,
    ExportDialogResult result,
  ) async {
    const fileName = 'export.vcd';
    final download = ref.read(browserDownloadProvider);
    final path = download != null
        ? fileName
        : await _pickSavePath(context, fileName: fileName, extension: 'vcd');
    if (path == null || !context.mounted) return;

    try {
      final config = _buildVcdConfig(source, result);
      final service = ref.read(vcdWriterServiceProvider);
      if (download != null) {
        await download(
          fileName: fileName,
          bytes: utf8.encode(service.generateVcd(source, config)),
        );
      } else {
        await service.writeVcd(source, config, path);
      }
      _recordExportCompleted(ExportFormat.vcd);
      if (context.mounted) {
        showCruxInfoSnack(context, L10N.of(context).exportSuccessVcd(path));
      }
    } on VcdWriteException catch (e) {
      if (context.mounted) {
        showCruxErrorSnack(context, L10N.of(context).exportErrorVcd(e.reason));
      }
    } on Object catch (e) {
      if (download == null) rethrow;
      if (context.mounted) {
        showCruxErrorSnack(context, L10N.of(context).exportErrorVcd('$e'));
      }
    }
  }

  /// Asks the OS save dialog where an export goes. `null` when the user
  /// cancels, or when another system dialog is already up.
  Future<String?> _pickSavePath(
    BuildContext context, {
    required String fileName,
    required String extension,
  }) async {
    if (ref.read(systemDialogInFlightProvider)) return null;
    // Read before the await; see [SystemDialogInFlight.end].
    final inFlight = ref.read(systemDialogInFlightProvider.notifier)..begin();
    try {
      return await ref.read(saveFilePickerProvider)(
        dialogTitle: L10N.of(context).exportDialogTitle,
        fileName: fileName,
        allowedExtensions: [extension],
        type: FileType.custom,
      );
    } finally {
      inFlight.end();
    }
  }

  // ── SAIF export ───────────────────────────────────────────────────────────────

  /// Writes a backward-SAIF switching-activity file for the chosen signals and
  /// time range.
  ///
  /// Shares the dialog's signal/range selection with the VCD path deliberately:
  /// "the signals I am looking at, over the window I am looking at" is the same
  /// question for both, and a second set of controls would be a second place to
  /// get it wrong.
  ///
  /// Real-valued signals are skipped rather than approximated — SAIF describes
  /// bit-level dwell time and a `real` has no bits, so emitting anything for one
  /// would be inventing data for a power tool to weight.
  Future<void> _exportSaif(
    BuildContext context,
    WaveformDataSource source,
    ExportDialogResult result,
  ) async {
    const fileName = 'activity.saif';
    final download = ref.read(browserDownloadProvider);
    final path = download != null
        ? fileName
        : await _pickSavePath(context, fileName: fileName, extension: 'saif');
    if (path == null || !context.mounted) return;

    try {
      final config = _buildVcdConfig(source, result);
      const stats = SaifStatisticsService();
      final activities = <SaifSignalActivity>[];
      for (final signalRef in config.signalRefs) {
        final variable = config.signalMap[signalRef];
        if (variable == null || variable.isReal) continue;
        activities.add(
          stats.analyze(
            signalPath: signalRef,
            name: variable.name,
            width: variable.bitWidth ?? 1,
            source: source,
            startTime: config.startTime,
            endTime: config.endTime,
          ),
        );
      }
      final document = const SaifWriter().render(
        signals: activities,
        duration: config.endTime - config.startTime,
        timescale: source.timescale,
      );
      if (download != null) {
        await download(fileName: fileName, bytes: utf8.encode(document));
      } else {
        await File(path).writeAsString(document);
      }
      _recordExportCompleted(ExportFormat.saif);
      if (context.mounted) {
        showCruxInfoSnack(context, L10N.of(context).exportSuccessSaif(path));
      }
    } on Object catch (e) {
      if (context.mounted) {
        showCruxErrorSnack(context, L10N.of(context).exportErrorSaif('$e'));
      }
    }
  }

  // ── PNG export ────────────────────────────────────────────────────────────────

  Future<void> _exportPng(
    BuildContext context,
    ExportDialogResult result,
    GlobalKey? repaintKey,
  ) async {
    if (repaintKey == null) {
      if (context.mounted) {
        showCruxErrorSnack(
          context,
          L10N.of(context).exportErrorImage('RepaintBoundary not set'),
        );
      }
      return;
    }

    const fileName = 'waveform.png';
    final download = ref.read(browserDownloadProvider);
    final path = download != null
        ? fileName
        : await _pickSavePath(context, fileName: fileName, extension: 'png');
    if (path == null || !context.mounted) return;

    // Annotations are widgets inside the captured RepaintBoundary, so the
    // only way to leave them out is to hide them for the frame we capture and
    // put them back afterwards. Restored in the finally below so a failed
    // export never leaves the canvas silently stripped of the user's notes.
    final visibility = ref.read(annotationsVisibleProvider.notifier);
    final wasVisible = visibility.visible;
    final hideForCapture = !result.includeAnnotations && wasVisible;

    // Resolved before the frame wait below, so the capture cannot reach for a
    // theme across an async gap.
    final captureBackground = Theme.of(context).colorScheme.surface;

    try {
      if (hideForCapture) {
        visibility.visible = false;
        // One frame for the overlay to drop out before the boundary is read.
        await WidgetsBinding.instance.endOfFrame;
      }
      final service = ref.read(imageExportServiceProvider);
      // Flatten onto the viewer's own surface. The capture is transparent
      // wherever a widget leaves its background to an ancestor outside the
      // boundary, and those holes read as white boxes on a light ground.
      if (download != null) {
        await download(
          fileName: fileName,
          bytes: await service.capturePng(
            repaintKey,
            pixelRatio: result.pixelRatio,
            background: captureBackground,
          ),
        );
      } else {
        await service.exportPng(
          repaintKey,
          path,
          pixelRatio: result.pixelRatio,
          background: captureBackground,
        );
      }
      _recordExportCompleted(ExportFormat.png);
      if (context.mounted) {
        showCruxInfoSnack(context, L10N.of(context).exportSuccessImage(path));
      }
    } on ImageCaptureException catch (e) {
      if (context.mounted) {
        showCruxErrorSnack(
          context,
          L10N.of(context).exportErrorImage(e.message),
        );
      }
    } on ImageWriteException catch (e) {
      if (context.mounted) {
        showCruxErrorSnack(
          context,
          L10N.of(context).exportErrorImage(e.reason),
        );
      }
    } on Object catch (e) {
      if (download == null) rethrow;
      if (context.mounted) {
        showCruxErrorSnack(context, L10N.of(context).exportErrorImage('$e'));
      }
    } finally {
      if (hideForCapture) visibility.visible = true;
    }
  }

  // ── SVG export ────────────────────────────────────────────────────────────────

  Future<void> _exportSvg(
    BuildContext context,
    WaveformDataSource source,
    ExportDialogResult result,
  ) async {
    const fileName = 'waveform.svg';
    final download = ref.read(browserDownloadProvider);
    final path = download != null
        ? fileName
        : await _pickSavePath(context, fileName: fileName, extension: 'svg');
    if (path == null || !context.mounted) return;

    try {
      final signalMap = ref.read(signalVariablesMapProvider);
      final signalGroup = _svgSignalGroup(source, result, signalMap);
      final timeMapper = _svgTimeMapper(source, result);

      // Lanes cannot overlap, so the document has to grow with the signal
      // count. Width stays fixed: an SVG is vector and the reader zooms, but
      // a lane drawn on top of another is wrong at every zoom.
      const laneHeight = 30.0;
      const rulerHeight = 24.0;
      final laneCount = _countSignalLanes(signalGroup.entries);
      final svgHeight = math.max<double>(
        200,
        rulerHeight + laneCount * laneHeight + 8,
      );

      // Annotations follow the same two switches PNG does: the dialog's
      // checkbox and the session's own visibility toggle. What you exported is
      // what you were looking at.
      final includeAnnotations =
          result.includeAnnotations && ref.read(annotationsVisibleProvider);

      // The document takes the viewer's own colours. A note carrying an
      // author's session colour keeps it either way; this decides the
      // fallback and the chrome, and a baked palette meant an export never
      // looked like the app it came from.
      final palette = SvgExportPalette.fromScheme(
        Theme.of(context).colorScheme,
      );
      // Ruler labels as ticks alone cannot say ns from ps. The viewer's own
      // formatter is the only thing that knows the file's timescale.
      final formatTime = TimeFormatService(
        timescale: ref.read(currentTimescaleProvider),
      ).format;
      final annotations = includeAnnotations
          ? ref.read(annotationsProvider)
          : const <Annotation>[];
      final annotationStatuses = includeAnnotations
          ? ref.read(annotationStatusesProvider)
          : const <String, AnnotationStatus>{};

      final service = ref.read(imageExportServiceProvider);
      if (download != null) {
        final document = service.generateSvg(
          source: source,
          signalGroup: signalGroup,
          signalMap: signalMap,
          timeMapper: timeMapper,
          svgHeight: svgHeight,
          palette: palette,
          formatTime: formatTime,
          annotations: annotations,
          annotationStatuses: annotationStatuses,
        );
        await download(fileName: fileName, bytes: utf8.encode(document));
      } else {
        await service.exportSvg(
          source: source,
          signalGroup: signalGroup,
          signalMap: signalMap,
          timeMapper: timeMapper,
          path: path,
          svgHeight: svgHeight,
          palette: palette,
          formatTime: formatTime,
          annotations: annotations,
          annotationStatuses: annotationStatuses,
        );
      }
      _recordExportCompleted(ExportFormat.svg);
      if (context.mounted) {
        showCruxInfoSnack(context, L10N.of(context).exportSuccessImage(path));
      }
    } on ImageWriteException catch (e) {
      if (context.mounted) {
        showCruxErrorSnack(
          context,
          L10N.of(context).exportErrorImage(e.reason),
        );
      }
    } on Object catch (e) {
      if (download == null) rethrow;
      if (context.mounted) {
        showCruxErrorSnack(context, L10N.of(context).exportErrorImage('$e'));
      }
    }
  }

  // ── helpers ───────────────────────────────────────────────────────────────────

  /// The signal set an SVG export should draw.
  ///
  /// This is the honesty fix the PNG path could not have: `exportSvg` is a
  /// parameterised emitter, so unlike a `RepaintBoundary` capture it really can
  /// honour "All signals" instead of silently drawing whatever happens to be on
  /// screen. "All" means all **loaded** signals, matching `_buildVcdConfig`
  /// exactly — one selector must not mean two different things depending on
  /// which format is chosen, and an unloaded signal has no samples to draw.
  SignalGroup _svgSignalGroup(
    WaveformDataSource source,
    ExportDialogResult result,
    Map<String, Variable> signalMap,
  ) {
    if (result.signals == ExportSignals.visible) {
      return ref.read(signalGroupsProvider);
    }

    // Carry the lane colour a signal already has on the canvas.
    //
    // This branch synthesises entries for signals that are *loaded* rather than
    // displayed, and it used to build them bare — so every trace in a
    // "loaded signals" export fell through to the emitter's fallback and the
    // document came out uniformly green, whatever the viewer showed. A signal
    // that is on the canvas keeps its colour; one that is only loaded has never
    // had a lane and so has none, and takes the next palette entry by position
    // exactly as the canvas would have assigned it.
    final onCanvas = <String, int>{};
    void collect(List<SignalEntry> entries) {
      for (final e in entries) {
        if (e.kind == SignalEntryKind.signal) {
          final colour = e.argbColor;
          final ref_ = e.signalRef;
          if (colour != null && ref_ != null) onCanvas[ref_] = colour;
        } else if (e.kind == SignalEntryKind.group) {
          collect(e.children);
        }
      }
    }

    collect(ref.read(signalGroupsProvider).entries);

    const palette = WavecruxColors.signalPalette;
    var next = 0;
    return SignalGroup(
      entries: [
        for (final entry in signalMap.entries)
          if (source.isSignalLoaded(entry.key))
            SignalEntry.signal(
              signalRef: entry.key,
              signalPath: entry.value.fullPath,
              displayName: entry.value.name,
              argbColor:
                  onCanvas[entry.key] ??
                  palette[next++ % palette.length].toARGB32(),
            ),
      ],
    );
  }

  /// The time window an SVG export should cover.
  ///
  /// The live mapper for "Visible"; a fit-all mapper over the whole trace for
  /// "Full simulation". This is the only export path that can reach beyond the
  /// viewport at all — PNG is bounded by what is on screen by construction.
  TimeMapper _svgTimeMapper(
    WaveformDataSource source,
    ExportDialogResult result,
  ) {
    final live = ref.read(timeMapperProvider);
    if (result.timeRange == ExportTimeRange.visible) return live;
    return TimeMapper.fitAll(
      startTime: source.startTime,
      endTime: source.endTime,
      viewportWidth: live.viewportWidth,
    );
  }

  /// Signal lanes in [entries], recursing into groups — the rows `exportSvg`
  /// will draw, and therefore what the document's height must accommodate.
  static int _countSignalLanes(List<SignalEntry> entries) {
    var count = 0;
    for (final entry in entries) {
      if (entry.kind == SignalEntryKind.signal) {
        count++;
      } else if (entry.kind == SignalEntryKind.group) {
        count += _countSignalLanes(entry.children);
      }
    }
    return count;
  }

  VcdExportConfig _buildVcdConfig(
    WaveformDataSource source,
    ExportDialogResult result,
  ) {
    final signalGroup = ref.read(signalGroupsProvider);
    final signalMap = ref.read(signalVariablesMapProvider);
    final timeMapper = ref.read(timeMapperProvider);

    final int startTime;
    final int endTime;
    if (result.timeRange == ExportTimeRange.visible) {
      startTime = timeMapper.visibleStartTime.clamp(
        source.startTime,
        source.endTime,
      );
      endTime = timeMapper.visibleEndTime.clamp(
        source.startTime,
        source.endTime,
      );
    } else {
      startTime = source.startTime;
      endTime = source.endTime;
    }

    if (result.signals == ExportSignals.visible) {
      return VcdExportConfig.fromSignalGroup(
        signalGroup: signalGroup,
        signalMap: signalMap,
        startTime: startTime,
        endTime: endTime,
      );
    }

    // All loaded signals
    final allRefs = <String>[];
    final allMap = <String, Variable>{};
    for (final entry in signalMap.entries) {
      if (source.isSignalLoaded(entry.key)) {
        allRefs.add(entry.key);
        allMap[entry.key] = entry.value;
      }
    }
    return VcdExportConfig(
      signalRefs: allRefs,
      signalMap: allMap,
      startTime: startTime,
      endTime: endTime,
    );
  }
}

/// Convenience provider that exposes the [SignalGroup] flattened to a
/// [Map<String, Variable>] — re-exported here so export code has one import.
///
/// The canonical definition lives in [signalVariablesMapProvider] (signal_tree_providers).
@riverpod
Map<String, Variable> exportSignalMap(Ref ref) =>
    ref.watch(signalVariablesMapProvider);

/// Provides the [VcdWriterService] instance used by [ExportNotifier].
/// Override in tests to avoid real dart:io file writes.
final vcdWriterServiceProvider = Provider<VcdWriterService>(
  (ref) => const VcdWriterService(),
);

/// Provides the [ImageExportService] instance used by [ExportNotifier].
/// Override in tests to avoid real dart:io file writes.
final imageExportServiceProvider = Provider<ImageExportService>(
  (ref) => const ImageExportService(),
);
