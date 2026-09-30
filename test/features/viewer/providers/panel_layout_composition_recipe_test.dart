// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/collab_view_composition.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';

void main() {
  group('PanelLayoutNotifier view-composition recipe seams', () {
    late ProviderContainer c;
    setUp(() => c = ProviderContainer());
    tearDown(() => c.dispose());

    test(
      'toCompositionRecipe captures the four composition-relevant flags',
      () {
        c.read(panelLayoutProvider.notifier)
          ..setStageViewVisible(visible: true)
          ..setTransactionViewVisible(visible: true)
          ..setValueColumnVisible(visible: false);
        final recipe = c
            .read(panelLayoutProvider.notifier)
            .toCompositionRecipe();
        expect(recipe.signalTreeVisible, isTrue);
        expect(recipe.valueColumnVisible, isFalse);
        expect(recipe.transactionViewVisible, isTrue);
        expect(recipe.stageViewVisible, isTrue);
      },
    );

    test(
      'round-trip: apply sets the four flags, leaves diagnostics untouched',
      () {
        // Follower has a local diagnostic panel open that must survive.
        c.read(panelLayoutProvider.notifier).setRtlSourceVisible(visible: true);
        const recipe = CollabPanelVisibility(
          signalTreeVisible: false,
          transactionViewVisible: true,
          stageViewVisible: true,
        );
        c.read(panelLayoutProvider.notifier).applyCompositionRecipe(recipe);

        final state = c.read(panelLayoutProvider);
        expect(state.signalTreeVisible, isFalse);
        expect(state.transactionViewVisible, isTrue);
        expect(state.stageViewVisible, isTrue);
        // Local-only diagnostic surface is not part of the shared composition.
        expect(state.rtlSourceVisible, isTrue);
      },
    );
  });
}
