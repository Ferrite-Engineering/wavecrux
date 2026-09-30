// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Stage widget picker — section-ordering invariant test across locales.
//
// Closes the `[Coverage: WIDGET — pending]` "Stage widget picker section
// ordering" gap in `verification/VERIFICATION_CHECKLIST.md` §8 (Stage
// built-in widgets):
//
//   "Section order: Primitive → Peripheral → Instrument → Board →
//    Protocol → Custom, locale-independent (verified across en /
//    zh-CN / ja / ko). On open-core only Primitive, Instrument, and
//    Board sections render — Peripheral, Protocol, Custom are empty
//    in open core"
//
// The companion `stage_widget_picker_dialog_test.dart` covers locale
// rendering, category grouping, and badge behavior for individual
// widgets but does not assert vertical ordering of the populated
// sections under each locale. This file covers exactly that gap.
//
// The test mirrors the structural pattern used by the decoder picker
// section-ordering tests (`decoder_picker_dialog_open_core_set_test.dart`
// and its Pro overlay mirror):
// register stub widgets across the categories of interest, render the
// picker, then read the y-coordinate of each section's stable ValueKey
// and assert ascending order.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/stage_widget_category.dart';
import 'package:wavecrux/domain/interfaces/stage_widget.dart';
import 'package:wavecrux/domain/models/signal_binding.dart';
import 'package:wavecrux/features/stage/widgets/stage_widget_picker_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/stage_registry.dart';

class _StubWidget extends StageWidget {
  const _StubWidget({
    required this.id,
    required this.displayName,
    required this.category,
  });

  @override
  final String id;
  @override
  final String displayName;
  @override
  String get description => 'Stub $id';
  @override
  final StageWidgetCategory category;
  @override
  List<SignalBinding> get requiredSignals => const [];
}

Widget _wrap({required Locale locale}) {
  return ProviderScope(
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: const Scaffold(body: StageWidgetPickerDialog()),
    ),
  );
}

void main() {
  setUp(StageRegistry.instance.clear);
  tearDown(StageRegistry.instance.clear);

  group('StageWidgetPickerDialog — section ordering across locales', () {
    // Open-core ships widgets in Primitive, Instrument, and Board
    // categories. Peripheral, Protocol, and Custom are empty until
    // Stage Pro contributes to them, so they should not render.
    final openCorePopulatedOrder = [
      StageWidgetCategory.primitive,
      StageWidgetCategory.instrument,
      StageWidgetCategory.board,
    ];

    /// Register one stub widget per category we want populated.
    void registerOpenCoreShape() {
      StageRegistry.instance
        ..register(
          const _StubWidget(
            id: 'led',
            displayName: 'LED',
            category: StageWidgetCategory.primitive,
          ),
        )
        ..register(
          const _StubWidget(
            id: 'gauge',
            displayName: 'Gauge',
            category: StageWidgetCategory.instrument,
          ),
        )
        ..register(
          const _StubWidget(
            id: 'basys3',
            displayName: 'Basys 3',
            category: StageWidgetCategory.board,
          ),
        );
    }

    for (final tag in const ['en', 'zh', 'ja', 'ko']) {
      testWidgets(
        'open-core populated sections render Primitive → Instrument → '
        'Board top-to-bottom in $tag',
        (tester) async {
          registerOpenCoreShape();

          await tester.pumpWidget(_wrap(locale: Locale(tag)));
          await tester.pumpAndSettle();

          final ys = <(StageWidgetCategory, double)>[];
          for (final c in openCorePopulatedOrder) {
            final finder = find.byKey(ValueKey('stage_category_${c.name}'));
            expect(
              finder,
              findsOneWidget,
              reason: 'category ${c.name} missing in locale $tag',
            );
            ys.add((c, tester.getTopLeft(finder).dy));
          }

          for (var i = 1; i < ys.length; i++) {
            expect(
              ys[i].$2,
              greaterThan(ys[i - 1].$2),
              reason:
                  '${ys[i].$1.name} should appear below '
                  '${ys[i - 1].$1.name} (locale $tag); '
                  'got y=${ys[i].$2} vs prior y=${ys[i - 1].$2}',
            );
          }
        },
      );

      testWidgets(
        'unpopulated open-core categories (Peripheral, Protocol, Custom) '
        'do not render in $tag',
        (tester) async {
          registerOpenCoreShape();

          await tester.pumpWidget(_wrap(locale: Locale(tag)));
          await tester.pumpAndSettle();

          for (final c in const [
            StageWidgetCategory.peripheral,
            StageWidgetCategory.protocol,
            StageWidgetCategory.custom,
          ]) {
            expect(
              find.byKey(ValueKey('stage_category_${c.name}')),
              findsNothing,
              reason:
                  'category ${c.name} should not render on open-core '
                  '(empty category — `omits empty categories` invariant); '
                  'failed in locale $tag',
            );
          }
        },
      );
    }

    testWidgets(
      'with all 6 categories populated, sections render in '
      'StageWidgetCategory.values declaration order top-to-bottom '
      '(simulates the Stage Pro shipped state)',
      (tester) async {
        // Register one stub per category so every section is populated
        // and the full ordering invariant can be asserted.
        for (final c in StageWidgetCategory.values) {
          StageRegistry.instance.register(
            _StubWidget(
              id: 'stub_${c.name}',
              displayName: 'Stub ${c.name}',
              category: c,
            ),
          );
        }

        await tester.pumpWidget(_wrap(locale: const Locale('en')));
        await tester.pumpAndSettle();

        final ys = <(StageWidgetCategory, double)>[];
        for (final c in StageWidgetCategory.values) {
          final finder = find.byKey(ValueKey('stage_category_${c.name}'));
          expect(
            finder,
            findsOneWidget,
            reason: 'category ${c.name} should render when populated',
          );
          ys.add((c, tester.getTopLeft(finder).dy));
        }

        for (var i = 1; i < ys.length; i++) {
          expect(
            ys[i].$2,
            greaterThan(ys[i - 1].$2),
            reason:
                '${ys[i].$1.name} should appear below '
                '${ys[i - 1].$1.name} (full-set ordering); '
                'got y=${ys[i].$2} vs prior y=${ys[i - 1].$2}',
          );
        }
      },
    );
  });
}
