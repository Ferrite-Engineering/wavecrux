// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/settings/providers/extra_settings_categories_provider.dart';

void main() {
  group('extraSettingsCategoriesProvider', () {
    test('defaults to an empty list (open-core contributes no categories)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(extraSettingsCategoriesProvider), isEmpty);
    });

    testWidgets(
      'can be overridden to contribute extra categories (overlay seam, '
      'suite-shared CruxSettingsExtraCategory shape)',
      (tester) async {
        final extra = CruxSettingsExtraCategory(
          id: 'pro.collaboration',
          icon: Icons.group,
          labelBuilder: (_) => 'Collaboration',
          bodyBuilder: (_) => const SizedBox.shrink(),
        );

        late List<CruxSettingsExtraCategory> extras;
        late BuildContext capturedContext;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              extraSettingsCategoriesProvider.overrideWithValue([extra]),
            ],
            child: Consumer(
              builder: (context, ref, _) {
                capturedContext = context;
                extras = ref.watch(extraSettingsCategoriesProvider);
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(extras, hasLength(1));
        expect(extras.single.id, 'pro.collaboration');
        // toCategory resolves the localized title with the live context.
        final category = extras.single.toCategory(capturedContext);
        expect(category.title, 'Collaboration');
        expect(category.icon, Icons.group);
      },
    );
  });
}
