// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/features/stage/providers/stage_config_label_resolver_provider.dart';
import 'package:wavecrux/features/stage/widgets/primitives/builtin_stage_widgets.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/stage_registry.dart';

/// Drift guard for Stage widget display-name localization.
///
/// Every built-in Stage widget shown in the picker / bindings pane /
/// instance tile must declare a `displayNameKey` so the render sites can
/// resolve a localized name instead of falling back to the hard-coded
/// English `displayName`. A new widget that ships without a key (the exact
/// gap this test was written to catch) fails here.
///
/// **Board widgets are exempt.** Their display names are vendor product
/// names (e.g. "Digilent Basys 3", "Terasic DE10-Lite") that are not
/// localized — the same reasoning that keeps board silk-screen slot labels
/// in English. Boards may still declare a key, but they are not required to.
void main() {
  setUp(registerBuiltinStageWidgets);
  tearDown(clearBuiltinStageWidgets);

  test('every non-board built-in Stage widget declares a displayNameKey', () {
    final missing = StageRegistry.instance
        .listAll()
        .where((w) => w.category != StageWidgetCategory.board)
        .where((w) => w.displayNameKey == null)
        .map((w) => w.id)
        .toList();

    expect(
      missing,
      isEmpty,
      reason:
          'These non-board Stage widgets render a hard-coded English '
          'displayName because they lack a displayNameKey: $missing. Add an '
          'ARB key (5 locales) + a case in stageConfigLabelResolverFactory.',
    );
  });

  // Locale sweep: every declared displayNameKey must resolve through the
  // open-core config-label resolver to a real localized string — not the
  // raw key (which is what renders when the ARB key or resolver case is
  // missing) and not empty.
  for (final locale in const [
    Locale('en'),
    Locale('zh', 'CN'),
    Locale('ja'),
    Locale('ko'),
  ]) {
    testWidgets('displayNameKeys resolve in $locale', (tester) async {
      late String Function(String) resolve;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                resolve = ref.watch(stageConfigLabelResolverFactoryProvider)(
                  context,
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      for (final widget in StageRegistry.instance.listAll()) {
        final key = widget.displayNameKey;
        if (key == null) continue;
        final resolved = resolve(key);
        expect(
          resolved,
          isNotEmpty,
          reason: '${widget.id}: key "$key" resolved to empty in $locale',
        );
        expect(
          resolved,
          isNot(key),
          reason:
              '${widget.id}: key "$key" did not resolve in $locale (rendered '
              'the raw key — missing ARB entry or resolver case).',
        );
      }
    });
  }
}
