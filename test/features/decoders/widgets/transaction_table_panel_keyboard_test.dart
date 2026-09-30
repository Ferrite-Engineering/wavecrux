// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The transaction table's decoder filter from the keyboard. It was a bare
// gesture detector: Tab skipped it, so filtering to one decoder, configuring
// one or removing one had no keyboard route at all.

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/providers/transaction_table_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_config_dialog.dart';
import 'package:wavecrux/features/decoders/widgets/transaction_table_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';

class _FixedDecoders extends ActiveDecodersNotifier {
  @override
  List<ActiveDecoder> build() => [
    for (final (id, number, label) in const [
      ('d1', 1, 'R 0x08 → 0xFF'),
      ('d2', 2, 'W 0x04 = 0x01'),
    ])
      ActiveDecoder(
        id: id,
        decoderId: 'apb',
        config: const DecoderConfig(signalBindings: {}),
        instanceNumber: number,
        transactions: [
          DecodedTransaction(
            startTime: number,
            endTime: number + 5,
            label: label,
          ),
        ],
      ),
  ];
}

Future<ProviderContainer> _pump(WidgetTester tester, {Locale? locale}) async {
  DecoderRegistry.instance.register(
    const DecoderDefinition(
      id: 'apb',
      displayName: 'APB',
      description: '',
      requiredSignals: [],
    ),
    (_) => throw UnimplementedError(),
  );
  addTearDown(DecoderRegistry.instance.clear);
  tester.view
    ..physicalSize = const Size(1200, 500)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [activeDecodersProvider.overrideWith(_FixedDecoders.new)],
      child: MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        locale: locale,
        home: const Scaffold(body: TransactionTablePanel()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(TransactionTablePanel)),
  );
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

/// What a screen reader calls the focused control: its label, or its
/// tooltip when a tooltip is its only name (an icon button).
String _spokenName(WidgetTester tester) {
  final stop = describeFocus(tester);
  return stop.name.isEmpty ? stop.description : stop.name;
}

/// Tab from nothing focused to the decoder filter, the first control.
Future<void> _tabToFilter(WidgetTester tester) async {
  final name = L10N
      .of(
        tester.element(find.byType(TransactionTablePanel)),
      )
      .transactionTableDecoderFilterLabel;
  for (var i = 0; i < 20; i++) {
    await _key(tester, LogicalKeyboardKey.tab);
    if (_spokenName(tester) == name) return;
  }
  fail('Tab never reached the decoder filter');
}

/// Tab inside the open menu until [name] has focus.
Future<void> _tabToItem(WidgetTester tester, String name) async {
  for (var i = 0; i < 12; i++) {
    if (_spokenName(tester) == name) return;
    await _key(tester, LogicalKeyboardKey.tab);
  }
  fail('Tab never reached "$name" in the menu');
}

void main() {
  group('TransactionTablePanel decoder filter — locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('opens from the keyboard in $locale without exceptions', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, locale: locale);
        await _tabToFilter(tester);
        await _key(tester, LogicalKeyboardKey.enter);
        expectFocusAnnounced(tester, context: 'decoder menu in $locale');
        expect(tester.takeException(), isNull);
        await _key(tester, LogicalKeyboardKey.escape);
        handle.dispose();
      });
    }
  });

  group('TransactionTablePanel decoder filter — keyboard', () {
    testWidgets('is a named button that says the current filter', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _tabToFilter(tester);

      expect(describeFocus(tester).line, 'Decoder filter button All Decoders');
      handle.dispose();
    });

    testWidgets(
      'Enter opens the menu on its first item; a decoder chosen by keyboard '
      'filters, and focus comes back to the button',
      (tester) async {
        final handle = tester.ensureSemantics();
        final container = await _pump(tester);
        await _tabToFilter(tester);

        await _key(tester, LogicalKeyboardKey.enter);
        expectFocusAnnounced(tester, named: 'All Decoders');
        expect(describeFocus(tester).states, contains('selected'));

        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(_spokenName(tester), 'APB #1');
        expect(describeFocus(tester).role, 'button');
        await _key(tester, LogicalKeyboardKey.enter);

        expect(
          container.read(transactionTableFilterProvider).decoderIdFilter,
          'd1',
        );
        expect(describeFocus(tester).line, 'Decoder filter button APB #1');
        handle.dispose();
      },
    );

    testWidgets('Space opens it too, and Escape returns to the button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await _tabToFilter(tester);

      await _key(tester, LogicalKeyboardKey.space);
      expectFocusAnnounced(tester, named: 'All Decoders');
      await _key(tester, LogicalKeyboardKey.escape);

      expect(describeFocus(tester).name, 'Decoder filter');
      handle.dispose();
    });

    testWidgets('Configure and Remove are named for their decoder and work', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final container = await _pump(tester);
      await _tabToFilter(tester);

      await _key(tester, LogicalKeyboardKey.enter);
      await _tabToItem(tester, 'Remove APB #2');
      await _key(tester, LogicalKeyboardKey.enter);
      expect(container.read(activeDecodersProvider).map((d) => d.id), ['d1']);
      expect(describeFocus(tester).name, 'Decoder filter');

      await _key(tester, LogicalKeyboardKey.enter);
      await _tabToItem(tester, 'Configure APB #1');
      await _key(tester, LogicalKeyboardKey.enter);
      expect(find.byType(DecoderConfigDialog), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the menu opens below the button, not at the window corner', (
      tester,
    ) async {
      await _pump(tester);
      final button = tester.getRect(find.text('All Decoders'));
      await _tabToFilter(tester);
      await _key(tester, LogicalKeyboardKey.enter);

      final item = tester.getRect(find.text('APB #1').last);
      expect(item.top, greaterThan(button.top));
      expect(item.top - button.bottom, lessThan(120));
    });
  });
}
