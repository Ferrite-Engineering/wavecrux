// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/models/named_enum_config.dart';
import 'package:wavecrux/domain/models/q_format_config.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/named_enum_table_form.dart';
import 'package:wavecrux/shared/widgets/q_format_form.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 420, child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Hosts a [NamedEnumTableForm] over rows it keeps, as the Inspector does.
class _TableHost extends StatefulWidget {
  const _TableHost({required this.initial, required this.onRows});

  final List<NamedEnumRow> initial;
  final ValueChanged<List<NamedEnumRow>> onRows;

  @override
  State<_TableHost> createState() => _TableHostState();
}

class _TableHostState extends State<_TableHost> {
  late List<NamedEnumRow> _rows = widget.initial;
  int _revision = 0;

  @override
  Widget build(BuildContext context) => NamedEnumTableForm(
    rows: _rows,
    revision: _revision,
    onChanged: (rows) {
      setState(() => _rows = rows);
      widget.onRows(rows);
    },
    onReplaced: (rows) {
      setState(() {
        _rows = rows;
        _revision++;
      });
      widget.onRows(rows);
    },
  );
}

void main() {
  group('QFormatForm', () {
    testWidgets('shows two sliders, a signed checkbox and the notation', (
      tester,
    ) async {
      await _pump(
        tester,
        QFormatForm(
          value: const QFormatConfig(m: 4, n: 12, signed: false),
          onChanged: (_) {},
        ),
      );
      expect(find.byType(Slider), findsNWidgets(2));
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.textContaining('UQ4.12'), findsOneWidget);
    });

    testWidgets('reports a change of signedness', (tester) async {
      QFormatConfig? changed;
      await _pump(
        tester,
        QFormatForm(
          value: const QFormatConfig(),
          onChanged: (v) => changed = v,
        ),
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(changed?.signed, isFalse);
      expect(changed?.m, const QFormatConfig().m);
    });

    for (final locale in _locales) {
      testWidgets('renders in ${locale.toLanguageTag()}', (tester) async {
        await _pump(
          tester,
          QFormatForm(value: const QFormatConfig(), onChanged: (_) {}),
          locale: locale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('NamedEnumTableForm', () {
    final rows = namedEnumRowsOf(
      NamedEnumConfig(
        entries: [
          NamedEnumEntry(value: BigInt.zero, label: 'IDLE'),
          NamedEnumEntry(value: BigInt.one, label: 'ACTIVE'),
        ],
      ),
    );

    testWidgets('shows each entry as a row', (tester) async {
      await _pump(tester, _TableHost(initial: rows, onRows: (_) {}));
      expect(find.widgetWithText(TextField, 'IDLE'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'ACTIVE'), findsOneWidget);
    });

    testWidgets('add appends a row and delete removes one', (tester) async {
      List<NamedEnumRow>? last;
      await _pump(tester, _TableHost(initial: rows, onRows: (r) => last = r));
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(last, hasLength(3));
      expect(last!.last.value, '0');
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(last, hasLength(2));
      expect(last!.first.label, 'ACTIVE');
    });

    testWidgets('an edit reaches the host, and an invalid value says so', (
      tester,
    ) async {
      List<NamedEnumRow>? last;
      await _pump(tester, _TableHost(initial: rows, onRows: (r) => last = r));
      await tester.enterText(find.byType(TextField).first, 'notanumber');
      await tester.pumpAndSettle();
      expect(last!.first.isValid, isFalse);
      expect(namedEnumConfigOf(last!), isNull);
      final l10n = L10N.of(tester.element(find.byType(NamedEnumTableForm)));
      expect(find.text(l10n.namedEnumEditorInvalidValue), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '42');
      await tester.pumpAndSettle();
      expect(namedEnumConfigOf(last!)!.entries.first.value, BigInt.from(42));
    });

    test('a GTKWave filter file parses decimal, hex and binary keys', () {
      final parsed = parseNamedEnumFilter(
        '# states\n0 IDLE\n0x1 BUSY\n0b10  DONE\n// end\nbad\n',
      );
      expect(parsed, const [
        NamedEnumRow(value: '0', label: 'IDLE'),
        NamedEnumRow(value: '1', label: 'BUSY'),
        NamedEnumRow(value: '2', label: 'DONE'),
      ]);
    });

    for (final locale in _locales) {
      testWidgets('renders in ${locale.toLanguageTag()}', (tester) async {
        await _pump(
          tester,
          _TableHost(initial: rows, onRows: (_) {}),
          locale: locale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
