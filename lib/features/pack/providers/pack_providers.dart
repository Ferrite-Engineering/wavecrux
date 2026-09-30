// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wavecrux/core/providers/browser_download_provider.dart';
import 'package:wavecrux/core/providers/system_dialog_provider.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/pack/widgets/pack_disclosure_dialog.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/export_providers.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/export/image_export_service.dart';
import 'package:wavecrux/services/pack/pack_disclosure.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_failure.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_reader.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_spec.dart';
import 'package:wavecrux/services/pack/wavecrux_pack_writer.dart';
import 'package:wavecrux/services/vcd_writer/vcd_writer_service.dart';

part 'pack_providers.g.dart';

/// Feeds a failed pack open into the issue-reporter buffer. The user sees a
/// short explanation; a bug report needs the path and the stack.
final _log = Logger('wavecrux.pack');

/// Provides the [WaveCruxPackWriter]. Override in tests to avoid disk writes.
final packWriterProvider = Provider<WaveCruxPackWriter>(
  (ref) => const WaveCruxPackWriter(),
);

/// Provides the [WaveCruxPackReader]. Override in tests to inject a decoder.
final packReaderProvider = Provider<WaveCruxPackReader>(
  (ref) => WaveCruxPackReader(),
);

/// Predicts a bundle's size before it is built.
///
/// A provider rather than a constant because the two size guards are the only
/// thing standing between a user and a multi-gigabyte attachment, and a
/// threshold nothing can reach in a test is a threshold nobody has checked.
final packSizeEstimatorProvider = Provider<PackSizeEstimator>(
  (ref) => const PackSizeEstimator(),
);

/// Where opened packs are expanded.
///
/// Application **support**, not the temp directory: a tab restored on the next
/// launch reopens its session by path, and an OS that swept the extraction
/// would turn a restored tab into a missing-file error for a pack the user
/// still has sitting in their downloads folder.
final packCacheRootProvider = Provider<Future<String>>((ref) async {
  final support = await getApplicationSupportDirectory();
  return p.join(support.path, 'packs');
});

/// Drives the `.wavecruxpack` share bundle — writing one, and opening one.
///
/// An action coordinator with no state, `keepAlive` for the same reason
/// [ExportNotifier] is: callers `ref.read(...).share(...)` without subscribing
/// and then await, and an auto-dispose notifier's own `ref` unmounts mid-call.
@Riverpod(keepAlive: true)
class SharePackNotifier extends _$SharePackNotifier {
  @override
  void build() {}

  static const _spanResolver = PackSpanResolver();

  // ── writing ────────────────────────────────────────────────────────────────

  /// Runs the whole share flow: resolve what would be sent, disclose it, ask
  /// where to put it, then write one self-contained file.
  ///
  /// [waveformRepaintKey] is the export [RepaintBoundary]'s key. Null (or a
  /// capture failure) costs the pack its preview and nothing else.
  Future<void> shareAnnotatedWaveform(
    BuildContext context, {
    GlobalKey? waveformRepaintKey,
  }) async {
    final l10n = L10N.of(context);
    final source = ref.read(waveformSourceProvider).value;
    if (source == null) {
      showCruxErrorSnack(context, l10n.packErrorNoFile);
      return;
    }

    final annotations = ref.read(annotationsProvider);
    final mapper = ref.read(timeMapperProvider);
    final span = _spanResolver.resolve(
      annotations: annotations,
      sourceStart: source.startTime,
      sourceEnd: source.endTime,
      fallbackStart: mapper.visibleStartTime,
      fallbackEnd: mapper.visibleEndTime,
    );

    final config = VcdExportConfig.fromSignalGroup(
      signalGroup: ref.read(signalGroupsProvider),
      signalMap: ref.read(signalVariablesMapProvider),
      startTime: span.startTime,
      endTime: span.endTime,
    );
    if (config.signalRefs.isEmpty) {
      showCruxErrorSnack(context, l10n.packErrorNoSignals);
      return;
    }

    final disclosure = PackDisclosure(
      signalPaths: [
        for (final signalRef in config.signalRefs)
          config.signalMap[signalRef]?.fullPath ?? signalRef,
      ],
      span: span,
      authorNames: _authorNames(annotations),
      annotationCount: annotations.length,
      estimatedBytes: ref
          .read(packSizeEstimatorProvider)
          .estimateBytes(
            source: source,
            config: config,
          ),
    );

    // A hard stop, not a third warning. The estimate exists precisely so a
    // bundle nobody can send is caught before the VCD is built in memory, and
    // an "export anyway" button on a multi-gigabyte attachment is not a
    // choice anybody benefits from having.
    if (disclosure.exceedsRefuseThreshold) {
      showCruxErrorSnack(context, l10n.packErrorTooLarge);
      return;
    }

    if (!context.mounted) return;
    final decision = await PackDisclosureDialog.show(
      context,
      disclosure: disclosure,
      timescale: source.timescale,
    );
    if (decision == null || !context.mounted) return;

    // On the web the pack downloads under its default name: a browser has no
    // save dialog that returns a path to write to.
    final download = ref.read(browserDownloadProvider);
    final fileName = _defaultFileName();
    final String? path;
    if (download != null) {
      path = fileName;
    } else {
      if (ref.read(systemDialogInFlightProvider)) return;
      // Read before the await; see [SystemDialogInFlight.end].
      final inFlight = ref.read(systemDialogInFlightProvider.notifier)..begin();
      try {
        path = await ref.read(saveFilePickerProvider)(
          dialogTitle: l10n.packShareDialogTitle,
          fileName: fileName,
          allowedExtensions: const ['wavecruxpack'],
          type: FileType.custom,
        );
      } finally {
        inFlight.end();
      }
    }
    if (path == null || !context.mounted) return;

    try {
      final contents = await _buildContents(
        config: config,
        stripAuthorNames: decision.stripAuthorNames,
        repaintKey: waveformRepaintKey,
        // Resolved here, before the capture's async gap.
        previewBackground: Theme.of(context).colorScheme.surface,
      );
      final writer = ref.read(packWriterProvider);
      if (download != null) {
        // One download, not two: the preview stays inside the pack, because a
        // browser may block a second download the page starts on its own.
        await download(fileName: fileName, bytes: writer.buildBytes(contents));
        ref
            .read(telemetryServiceProvider)
            .record(TelemetryEvent('pack.exported'));
        if (context.mounted) {
          showCruxInfoSnack(context, l10n.packShareSuccess(fileName));
        }
        return;
      }
      await writer.writeToFile(path: path, contents: contents);
      // The preview lands beside the pack as well as inside it, so the image
      // the sender wants to post is a file they can drag rather than something
      // they have to unzip their own share bundle to reach.
      final preview = await writer.writePreviewBeside(
        packPath: path,
        contents: contents,
      );
      ref
          .read(telemetryServiceProvider)
          .record(TelemetryEvent('pack.exported'));
      if (context.mounted) {
        showCruxInfoSnack(
          context,
          preview == null
              ? l10n.packShareSuccess(path)
              : l10n.packShareSuccessWithPreview(path),
        );
      }
    } on WaveCruxPackWriteException catch (e) {
      if (context.mounted) {
        showCruxErrorSnack(context, l10n.packShareError(e.reason));
      }
    } on Object catch (e) {
      if (download == null) rethrow;
      if (context.mounted) {
        showCruxErrorSnack(context, l10n.packShareError('$e'));
      }
    }
  }

  /// Renders the four entries.
  ///
  /// The session's `sourceFilePath` is rewritten to the bundled dump's
  /// **relative** name, which is the whole reason the pack opens on a machine
  /// that has never seen the original: `SessionService.loadSession` resolves a
  /// relative source against the session file's own directory, so the
  /// extracted `session.wavecrux` finds the extracted `waveform.vcd`.
  Future<WaveCruxPackContents> _buildContents({
    required VcdExportConfig config,
    required bool stripAuthorNames,
    required GlobalKey? repaintKey,
    required Color previewBackground,
  }) async {
    final source = ref.read(waveformSourceProvider).value!;
    final snapshot = ref.read(sessionProvider.notifier).snapshot();
    final annotations = stripAuthorNames
        ? [
            for (final a in snapshot.annotations) a.copyWith(authorName: ''),
          ]
        : snapshot.annotations;

    final sessionJson = ref
        .read(sessionServiceProvider)
        .encodeDocument(
          snapshot.copyWith(
            sourceFilePath: WaveCruxPackSpec.waveformEntryName,
            annotations: annotations,
          ),
        );

    return WaveCruxPackContents(
      sessionJson: sessionJson,
      waveformVcd: const VcdWriterService().generateVcd(source, config),
      readme: buildReadme(
        signalCount: config.signalRefs.length,
        annotationCount: annotations.length,
      ),
      previewPng: await _capturePreview(repaintKey, previewBackground),
    );
  }

  /// Captures the annotated render, or null when there is nothing to capture.
  ///
  /// Annotations are forced visible for the captured frame and restored
  /// afterwards — the inverse of `_exportPng`'s hide-for-capture, and for the
  /// same reason it exists: the preview is *the annotated render* by
  /// definition, and a pack whose thumbnail shows a bare waveform because the
  /// author happened to have notes toggled off misrepresents what is inside.
  Future<Uint8List?> _capturePreview(
    GlobalKey? repaintKey,
    Color background,
  ) async {
    if (repaintKey == null) return null;
    final visibility = ref.read(annotationsVisibleProvider.notifier);
    final wasVisible = visibility.visible;
    try {
      if (!wasVisible) {
        visibility.visible = true;
        await WidgetsBinding.instance.endOfFrame;
      }
      return await ref
          .read(imageExportServiceProvider)
          // Flattened onto the viewer's surface. `toImage` leaves a hole
          // wherever a widget leaves its background to an ancestor outside the
          // boundary, and this is the image that sells the app: a preview with
          // transparent gaps shows white boxes anywhere it lands on a light
          // ground, which is most mail clients.
          .capturePng(repaintKey, background: background);
    } on ImageCaptureException {
      // A pack without a preview is still a complete, openable pack. Failing
      // the whole share because a boundary was not mounted would be the wrong
      // trade.
      return null;
    } finally {
      if (!wasVisible) visibility.visible = false;
    }
  }

  // ── reading ────────────────────────────────────────────────────────────────

  /// Expands the pack at [packPath] and returns where its session landed.
  ///
  /// Returns null after showing a localized explanation; the caller opens
  /// [ExtractedPack.sessionPath] through the ordinary session loader, so a
  /// pack is not a second way to restore a view — it is the same way, fed a
  /// different file.
  Future<ExtractedPack?> openPack(
    String packPath, {
    BuildContext? context,
  }) async {
    try {
      final cacheRoot = await ref.read(packCacheRootProvider);
      final extracted = await ref
          .read(packReaderProvider)
          .extract(packPath: packPath, cacheRoot: cacheRoot);
      ref.read(telemetryServiceProvider).record(TelemetryEvent('pack.opened'));
      return extracted;
    } on WaveCruxPackException catch (e) {
      if (context != null && context.mounted) {
        showCruxErrorSnack(
          context,
          packFailureMessage(L10N.of(context), e.kind),
        );
      }
      return null;
    } on Object catch (error, stack) {
      // Resolving the cache root goes through `path_provider`, which is a
      // platform channel: it throws on a headless host rather than returning a
      // pack failure. Report it as the I/O failure it is instead of letting an
      // unhandled error take the open silently.
      _log.warning('Pack could not be opened: $packPath', error, stack);
      if (context != null && context.mounted) {
        showCruxErrorSnack(
          context,
          packFailureMessage(L10N.of(context), WaveCruxPackFailureKind.ioError),
        );
      }
      return null;
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  static List<String> _authorNames(List<Annotation> annotations) {
    final names = <String>{
      for (final a in annotations)
        if (a.authorName.trim().isNotEmpty) a.authorName.trim(),
    };
    return names.toList()..sort();
  }

  /// `<dump name>-annotated.wavecruxpack`, so a recipient's downloads folder
  /// says what the file is about rather than `session (3)`.
  String _defaultFileName() {
    final current = ref.read(waveformSourceProvider.notifier).currentFilePath;
    final stem = current == null
        ? 'waveform'
        : p.basenameWithoutExtension(current);
    return '$stem-annotated${WaveCruxPackSpec.fileExtension}';
  }
}

/// The plain-text note a recipient sees if they unzip the pack by hand.
///
/// English only, deliberately: it travels to someone who may not have the app,
/// on a machine whose locale we do not know, and a README localized to the
/// *sender's* locale would be less readable than one that is not localized at
/// all. The in-app strings around it are localized normally.
String buildReadme({required int signalCount, required int annotationCount}) =>
    '''
WaveCrux annotated waveform pack
================================

This file is a WaveCrux share bundle: a waveform excerpt ($signalCount
signals) together with $annotationCount annotation(s) anchored to specific
signal transitions, and a preview image of what the sender was looking at.

To open it, install WaveCrux and open this .wavecruxpack file:

    ${WaveCruxPackSpec.landingPageUrl}

Contents:
  ${WaveCruxPackSpec.sessionEntryName}   the view and its annotations
  ${WaveCruxPackSpec.waveformEntryName}     the waveform excerpt the notes refer to
  ${WaveCruxPackSpec.previewEntryName}      a rendered image of the annotated view
''';

/// Maps a read failure onto a localized explanation.
///
/// A closed switch rather than a map so a new [WaveCruxPackFailureKind] fails
/// to compile until it has a message — the failure mode otherwise is a user
/// staring at an empty error.
String packFailureMessage(L10N l10n, WaveCruxPackFailureKind kind) =>
    switch (kind) {
      WaveCruxPackFailureKind.fileMissing => l10n.packOpenErrorMissing,
      WaveCruxPackFailureKind.ioError => l10n.packOpenErrorIo,
      WaveCruxPackFailureKind.notAnArchive => l10n.packOpenErrorNotAPack,
      WaveCruxPackFailureKind.symlinkRejected ||
      WaveCruxPackFailureKind.unsafeEntryName => l10n.packOpenErrorUnsafe,
      WaveCruxPackFailureKind.tooLarge => l10n.packOpenErrorTooLarge,
      WaveCruxPackFailureKind.missingSession => l10n.packOpenErrorNoSession,
    };
