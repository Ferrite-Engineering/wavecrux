// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';
import 'package:wavecrux/features/collaboration/providers/collab_composition_degradation_provider.dart';

void main() {
  group('collabCompositionDegradationProvider', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('defaults to none', () {
      expect(
        container.read(collabCompositionDegradationProvider),
        CollabCompositionDegradation.none,
      );
    });

    test('report records the degradation', () {
      const degradation = CollabCompositionDegradation(
        missingSignalPaths: ['top.missing'],
        missingDecoderIds: ['axi4_full'],
      );
      container
          .read(collabCompositionDegradationProvider.notifier)
          .report(degradation);
      expect(
        container.read(collabCompositionDegradationProvider),
        degradation,
      );
    });

    test('clear resets to none', () {
      container.read(collabCompositionDegradationProvider.notifier)
        ..report(
          const CollabCompositionDegradation(missingWidgetIds: ['gauge']),
        )
        ..clear();
      expect(
        container.read(collabCompositionDegradationProvider),
        CollabCompositionDegradation.none,
      );
    });
  });
}
