// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/signal_tree_providers.dart';
import 'package:wavecrux/features/viewer/providers/time_providers.dart';
import 'package:wavecrux/features/viewer/providers/translate_filter_provider.dart';
import 'package:wavecrux/services/session/gtkw_import_service.dart';

// The result type is part of this library's signature, so callers get it here.
export 'package:wavecrux/services/session/gtkw_import_service.dart';

/// Applies a GTKWave import to a tab's providers in [container].
///
/// This is the whole of what an imported `.gtkw` changes in the viewer, and
/// the screen's import command calls nothing else, so the tests that drive it
/// fail when a field stops being applied:
///
/// - the trace list, with groups, colors, formats and analog rendering
///   (replaced wholesale);
/// - named markers, and GTKWave's primary marker as the primary cursor;
/// - the zoom and the time at the left edge of the view. With no waveform laid
///   out yet they are staged for the viewport's first initialization, the
///   same way a session restore stages them;
/// - the expanded scopes, added to those already open in the hierarchy tree;
/// - each matched trace's translate filter file.
///
/// The canvas background (`[bgcolor]`) is not applied: the WaveCrux theme
/// owns it.
Future<void> applyGtkwImport(
  ProviderContainer container,
  GtkwImportResult result,
) async {
  final session = result.sessionState;

  container
      .read(signalGroupsProvider.notifier)
      .restoreFromSession(session.signalGroup);

  final markers = container.read(markerStateProvider.notifier);
  for (final entry in session.markerState.getAllMarkers()) {
    markers.setMarker(entry.key, entry.value);
  }

  final primaryCursor = session.cursorState.primaryCursorTime;
  if (primaryCursor != null) {
    container.read(cursorStateProvider.notifier).placePrimary(primaryCursor);
  }

  _applyViewport(container, result);

  if (session.expandedScopePaths.isNotEmpty) {
    final expanded = container.read(expandedScopesProvider);
    container.read(expandedScopesProvider.notifier).applyExpanded({
      ...expanded,
      ...session.expandedScopePaths,
    });
  }

  final filters = container.read(translateFilterProvider.notifier);
  for (final entry in session.translateFilterPaths.entries) {
    await filters.assignFilter(entry.key, entry.value);
  }
}

void _applyViewport(ProviderContainer container, GtkwImportResult result) {
  final ticksPerPixel = result.ticksPerPixel;
  final panOffsetTicks = result.panOffsetTicks;
  final notifier = container.read(timeMapperProvider.notifier);
  if (container.read(timeMapperProvider).isEmpty) {
    // Nothing laid out to zoom yet: stage both for the first initialize. A
    // `.gtkw` with a start time but no zoom has nothing to stage, since the
    // staged zoom is what turns off fit-all.
    if (ticksPerPixel != null) {
      notifier.setPendingZoomPan(
        ticksPerPixel: ticksPerPixel,
        panOffsetTicks: panOffsetTicks ?? 0,
      );
    }
    return;
  }
  if (ticksPerPixel != null) notifier.setZoom(ticksPerPixel);
  if (panOffsetTicks != null) notifier.setPanOffsetTicks(panOffsetTicks);
}
