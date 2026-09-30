// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/annotation.dart';
import 'package:wavecrux/domain/models/session_state.dart';
import 'package:wavecrux/features/annotations/providers/annotation_providers.dart';
import 'package:wavecrux/features/viewer/providers/session_providers.dart';
import 'package:wavecrux/features/viewer/widgets/export_dialog.dart';

/// Annotation visibility and its export contract.
///
/// Visibility is a *view* setting: hiding notes to read the raw waveform must
/// never lose them, and the state has to survive a reopen. Export honours it
/// so what you exported is what you were looking at.

Annotation _ann() => Annotation(
  id: 'a1',
  shape: AnnotationShape.callout,
  anchor: const PointAnchor(time: 100, rowId: 'top.bus'),
  authorName: 'Martin',
  createdAt: DateTime.utc(2026, 8, 12),
  text: 'note',
);

void main() {
  group('the visibility toggle', () {
    test('defaults to showing them', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(annotationsVisibleProvider), isTrue);
    });

    test('hiding does not delete', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(annotationsProvider.notifier).add(_ann());

      c.read(annotationsVisibleProvider.notifier).toggle();

      expect(c.read(annotationsVisibleProvider), isFalse);
      expect(
        c.read(annotationsProvider),
        hasLength(1),
        reason: 'hiding is a view state, not an edit',
      );
    });
  });

  group('session round-trip', () {
    test('a hidden state is captured and restored', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
        ..listen(annotationsVisibleProvider, (_, _) {})
        ..listen(sessionProvider, (_, _) {});

      c.read(annotationsVisibleProvider.notifier).visible = false;
      final snapshot = c.read(sessionProvider.notifier).snapshot();
      expect(snapshot.annotationsVisible, isFalse);

      c.read(annotationsVisibleProvider.notifier).visible = true;
      await c.read(sessionProvider.notifier).restoreFromState(snapshot);

      expect(c.read(annotationsVisibleProvider), isFalse);
    });

    test('a session that predates the setting restores visible', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c
        ..listen(annotationsVisibleProvider, (_, _) {})
        ..listen(sessionProvider, (_, _) {});

      c.read(annotationsVisibleProvider.notifier).visible = false;
      await c
          .read(sessionProvider.notifier)
          .restoreFromState(const SessionState());

      expect(
        c.read(annotationsVisibleProvider),
        isTrue,
        reason: 'the default must be shown, not inherited from the last file',
      );
    });
  });

  group('the export dialog result', () {
    test('includes annotations by default', () {
      const result = ExportDialogResult(
        format: ExportFormat.png,
        timeRange: ExportTimeRange.visible,
        signals: ExportSignals.visible,
        pixelRatio: 2,
      );
      expect(result.includeAnnotations, isTrue);
    });

    test('carries the opt-out', () {
      const result = ExportDialogResult(
        format: ExportFormat.png,
        timeRange: ExportTimeRange.visible,
        signals: ExportSignals.visible,
        pixelRatio: 2,
        includeAnnotations: false,
      );
      expect(result.includeAnnotations, isFalse);
    });
  });
}
