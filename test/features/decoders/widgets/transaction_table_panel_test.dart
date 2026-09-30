// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/providers/browser_download_provider.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/providers/transaction_table_provider.dart';
import 'package:wavecrux/features/decoders/widgets/decoder_config_dialog.dart';
import 'package:wavecrux/features/decoders/widgets/transaction_table_body.dart';
import 'package:wavecrux/features/decoders/widgets/transaction_table_panel.dart';
import 'package:wavecrux/features/viewer/providers/selected_transaction_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';
import 'package:wavecrux/plugins/transaction_table_exporters_provider.dart';
import 'package:wavecrux/shared/widgets/wavecrux_feature_tier_badge.dart';

import '../../../helpers/product_telemetry_config.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

const _config = DecoderConfig(signalBindings: {});

DecoderDefinition _def(String id, String name) => DecoderDefinition(
  id: id,
  displayName: name,
  description: '',
  requiredSignals: const [],
);

DecodedTransaction _tx(
  int start,
  int end,
  String label, {
  Map<String, String> fields = const {},
  bool isError = false,
}) => DecodedTransaction(
  startTime: start,
  endTime: end,
  label: label,
  fields: fields,
  isError: isError,
);

ActiveDecoder _decoder(
  String id,
  String decoderId,
  List<DecodedTransaction> txs, {
  int instanceNumber = 1,
}) => ActiveDecoder(
  id: id,
  decoderId: decoderId,
  config: _config,
  instanceNumber: instanceNumber,
  transactions: txs,
);

class _FixedDecodersNotifier extends ActiveDecodersNotifier {
  _FixedDecodersNotifier(this._initial);
  final List<ActiveDecoder> _initial;
  @override
  List<ActiveDecoder> build() => _initial;
}

Widget _wrap(
  Widget child, {
  List<ActiveDecoder> decoders = const [],
  List<Override> extra = const [],
}) => ProviderScope(
  overrides: [
    productTelemetryConfig,
    activeDecodersProvider.overrideWith(() => _FixedDecodersNotifier(decoders)),
    ...extra,
  ],
  child: const MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(body: TransactionTablePanel()),
  ),
);

Widget _wrapLocale(
  String languageTag, {
  List<ActiveDecoder> decoders = const [],
}) {
  final parts = languageTag.split('_');
  final locale = parts.length == 2
      ? Locale(parts[0], parts[1])
      : Locale(parts[0]);
  return ProviderScope(
    overrides: [
      productTelemetryConfig,
      activeDecodersProvider.overrideWith(
        () => _FixedDecodersNotifier(decoders),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: const Scaffold(body: TransactionTablePanel()),
    ),
  );
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(DecoderRegistry.instance.clear);
  tearDown(DecoderRegistry.instance.clear);

  // ── locale sweep ────────────────────────────────────────────────────────────

  group('TransactionTablePanel — locale sweep', () {
    for (final locale in ['en', 'zh_CN', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(_wrapLocale(locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── empty states ─────────────────────────────────────────────────────────────

  group('TransactionTablePanel — empty states', () {
    testWidgets('shows no-decoders message when decoder list is empty', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const TransactionTablePanel()));
      await tester.pumpAndSettle();
      final l10n = tester
          .element(find.byType(TransactionTablePanel))
          .let(L10N.of);
      expect(find.text(l10n.transactionTableEmptyNoDecoders), findsOneWidget);
    });

    testWidgets(
      'shows no-transactions message when decoder has no transactions',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const TransactionTablePanel(),
            decoders: [_decoder('d0', 'spi', [])],
          ),
        );
        await tester.pumpAndSettle();
        final l10n = tester
            .element(find.byType(TransactionTablePanel))
            .let(L10N.of);
        expect(
          find.text(l10n.transactionTableEmptyNoTransactions),
          findsOneWidget,
        );
      },
    );
  });

  // ── table renders ─────────────────────────────────────────────────────────

  group('TransactionTablePanel — table content', () {
    testWidgets('renders rows with label text', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TransactionTablePanel(),
          decoders: [
            _decoder('d0', 'spi', [
              _tx(0, 10, 'Write 0xFF'),
              _tx(20, 30, 'Read 0x50'),
            ]),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Write 0xFF'), findsOneWidget);
      expect(find.text('Read 0x50'), findsOneWidget);
    });

    testWidgets('error row shows error icon', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TransactionTablePanel(),
          decoders: [
            _decoder('d0', 'spi', [
              _tx(0, 10, 'NACK', isError: true),
            ]),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('dynamic field column appears when transactions have fields', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TransactionTablePanel(),
          decoders: [
            _decoder('d0', 'i2c', [
              _tx(
                0,
                10,
                'Transfer',
                fields: {'address': '0x50', 'rw': 'W'},
              ),
            ]),
          ],
        ),
      );
      await tester.pumpAndSettle();
      // Both field keys should appear as column headers.
      expect(find.text('address'), findsOneWidget);
      expect(find.text('rw'), findsOneWidget);
      // Field values should appear in cells.
      expect(find.text('0x50'), findsOneWidget);
      expect(find.text('W'), findsOneWidget);
    });

    testWidgets('no spurious checkbox column in header or rows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TransactionTablePanel(),
          decoders: [
            _decoder('d0', 'spi', [
              _tx(0, 10, 'Write 0xFF'),
              _tx(20, 30, 'Read 0x50'),
            ]),
          ],
        ),
      );
      await tester.pumpAndSettle();
      // showCheckboxColumn: false must suppress every Checkbox Flutter would
      // otherwise inject into the DataTable header and rows.
      expect(find.byType(Checkbox), findsNothing);
    });
  });

  // ── row tap → selection ──────────────────────────────────────────────────

  testWidgets('tapping a row marks transaction as selected', (tester) async {
    final tx = _tx(100, 200, 'Frame A');
    await tester.pumpWidget(
      _wrap(
        const TransactionTablePanel(),
        decoders: [
          _decoder('d0', 'uart', [tx]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Frame A'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TransactionTablePanel)),
    );
    final selected = container.read(selectedTransactionProvider);
    expect(selected, isNotNull);
    expect(selected!.$1, tx);
    expect(selected.$2, 'd0');
  });

  testWidgets(
    'tapping a row also places primary cursor at transaction startTime '
    '(closes verification gap §3 — Row click → cursor jumps; the canvas '
    'highlight half is downstream of selectedTransactionProvider '
    'whose change is asserted in the test above)',
    (tester) async {
      final tx = _tx(450, 550, 'Frame B');
      await tester.pumpWidget(
        _wrap(
          const TransactionTablePanel(),
          decoders: [
            _decoder('d0', 'uart', [tx]),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TransactionTablePanel)),
      );

      // Subscribe to keep the autoDispose provider alive across the
      // widget's `ref.read(...notifier).placePrimary(...)` and the test's
      // post-tap state read. Without this subscription, the provider would
      // dispose between the widget's call and the test's read, returning a
      // fresh default state instead of the placement.
      // ignore: cascade_invocations
      container.listen(cursorStateProvider, (_, _) {});

      await tester.tap(find.text('Frame B'));
      await tester.pumpAndSettle();

      // Row tap dispatches both select() and cursor.placePrimary(startTime).
      // The canvas listens to cursorStateProvider and re-paints the
      // cursor line at the new position; the per-row highlight is driven by
      // selectedTransactionProvider, asserted in the prior test.
      expect(
        container.read(cursorStateProvider).primaryCursorTime,
        tx.startTime,
        reason:
            'tapping a row should snap the primary cursor to the '
            'transaction startTime so the canvas line lands on the row',
      );
    },
  );

  testWidgets('cursor state is accessible and settable within widget scope', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const TransactionTablePanel()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TransactionTablePanel)),
    );
    container.read(cursorStateProvider.notifier).placePrimary(250);
    expect(
      container.read(cursorStateProvider).primaryCursorTime,
      250,
    );
  });

  // ── decoder filter dropdown ───────────────────────────────────────────────

  testWidgets('decoder filter dropdown hides non-matching decoder rows', (
    tester,
  ) async {
    DecoderRegistry.instance
      ..register(_def('spi', 'SPI'), (_) => throw UnimplementedError())
      ..register(_def('uart', 'UART'), (_) => throw UnimplementedError());

    await tester.pumpWidget(
      _wrap(
        const TransactionTablePanel(),
        decoders: [
          _decoder('d0', 'spi', [_tx(0, 10, 'SPI Write')]),
          _decoder('d1', 'uart', [_tx(0, 10, 'UART Frame')]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Both rows visible initially.
    expect(find.text('SPI Write'), findsOneWidget);
    expect(find.text('UART Frame'), findsOneWidget);

    // Set decoder filter via provider directly.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TransactionTablePanel)),
    );
    container
        .read(transactionTableFilterProvider.notifier)
        .setDecoderFilter('d0');
    await tester.pumpAndSettle();

    expect(find.text('SPI Write'), findsOneWidget);
    expect(find.text('UART Frame'), findsNothing);
  });

  // ── search query ──────────────────────────────────────────────────────────

  testWidgets('typing in search field filters rows by label', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const TransactionTablePanel(),
        decoders: [
          _decoder('d0', 'spi', [
            _tx(0, 10, 'Write 0xFF'),
            _tx(20, 30, 'Read 0x50'),
          ]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Write 0xFF'), findsOneWidget);
    expect(find.text('Read 0x50'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'read');
    await tester.pumpAndSettle();

    expect(find.text('Write 0xFF'), findsNothing);
    expect(find.text('Read 0x50'), findsOneWidget);
  });

  // ── sort by column ────────────────────────────────────────────────────────

  testWidgets('setSortColumn updates sortColumn in filter state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const TransactionTablePanel(),
        decoders: [
          _decoder('d0', 'spi', [
            _tx(30, 40, 'C'),
            _tx(10, 20, 'A'),
          ]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TransactionTablePanel)),
    );
    container
        .read(transactionTableFilterProvider.notifier)
        .setSortColumn(TransactionSortColumn.startTime);
    await tester.pumpAndSettle();

    expect(
      container.read(transactionTableFilterProvider).sortColumn,
      TransactionSortColumn.startTime,
    );
  });

  // ── CSV content ──────────────────────────────────────────────────────────

  group('TransactionTablePanel.buildCsvContent', () {
    test('hex field values are quoted to prevent spreadsheet conversion', () {
      final tx = _tx(
        100,
        500,
        'I2C 0x50 W',
        fields: {'address': '0x50', 'data': '0xFF', 'rw': 'W'},
      );
      final rows = [
        TableTransaction(
          rowIndex: 1,
          decoderInstanceId: 'd0',
          decoderDisplayName: 'I2C #1',
          transaction: tx,
        ),
      ];
      final csv = TransactionTablePanel.buildCsvContent(
        rows,
        ['address', 'data', 'rw'],
      );
      // Hex values must be quoted so Numbers/Excel treat them as text.
      expect(csv, contains('"0x50"'));
      expect(csv, contains('"0xFF"'));
    });

    test('embedded quotes in field values are escaped', () {
      final tx = _tx(0, 10, 'A "quoted" label', fields: {'note': 'say "hi"'});
      final rows = [
        TableTransaction(
          rowIndex: 1,
          decoderInstanceId: 'd0',
          decoderDisplayName: 'D',
          transaction: tx,
        ),
      ];
      final csv = TransactionTablePanel.buildCsvContent(rows, ['note']);
      expect(csv, contains('"say ""hi"""'));
    });

    test('header row has correct fixed and dynamic column names', () {
      final rows = [
        TableTransaction(
          rowIndex: 1,
          decoderInstanceId: 'd0',
          decoderDisplayName: 'SPI #1',
          transaction: _tx(0, 10, 'SPI 0xFF', fields: {'mosi': '0xFF'}),
        ),
      ];
      final csv = TransactionTablePanel.buildCsvContent(rows, ['mosi']);
      final header = csv.split('\n').first;
      expect(header, startsWith('#,Decoder,Start,End,Label,Error'));
      expect(header, contains('"mosi"'));
    });

    test('missing field for a row produces empty quoted cell', () {
      final tx = _tx(0, 10, 'X');
      final rows = [
        TableTransaction(
          rowIndex: 1,
          decoderInstanceId: 'd0',
          decoderDisplayName: 'D',
          transaction: tx,
        ),
      ];
      final csv = TransactionTablePanel.buildCsvContent(rows, ['address']);
      // address not in fields → empty string, still quoted.
      expect(csv, contains(',""'));
    });
  });

  // ── export button ─────────────────────────────────────────────────────────

  testWidgets('Export CSV button is disabled when no transactions', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const TransactionTablePanel()));
    await tester.pumpAndSettle();
    final l10n = tester
        .element(find.byType(TransactionTablePanel))
        .let(L10N.of);
    // TextButton with null onPressed renders as disabled.
    final button = tester.widget<TextButton>(
      find.ancestor(
        of: find.text(l10n.transactionTableExportCsv),
        matching: find.byType(TextButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('in the browser Export CSV downloads the table', (tester) async {
    DecoderRegistry.instance.register(
      _def('spi', 'SPI'),
      (_) => throw UnimplementedError(),
    );
    final downloads = <String, List<int>>{};
    await tester.pumpWidget(
      _wrap(
        const TransactionTablePanel(),
        decoders: [
          _decoder('d1', 'spi', [_tx(10, 20, 'MOSI 0x5A')]),
        ],
        extra: [
          browserDownloadProvider.overrideWithValue(({
            required fileName,
            required bytes,
          }) async {
            downloads[fileName] = bytes;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final l10n = tester
        .element(find.byType(TransactionTablePanel))
        .let(L10N.of);

    await tester.tap(find.text(l10n.transactionTableExportCsv));
    await tester.pumpAndSettle();

    expect(downloads.keys, ['transactions.csv']);
    expect(utf8.decode(downloads['transactions.csv']!), contains('MOSI 0x5A'));
    expect(
      find.text(l10n.transactionTableExportCsvSaved('transactions.csv')),
      findsOneWidget,
    );
  });

  // ── extra-exporter overflow menu (open-core extension point) ──────────────

  group('TransactionTablePanel — extra exporters overflow menu', () {
    /// Builds an exporter override that records every applicability check
    /// and remembers which entries were "exported".
    ({
      List<String> applicabilityChecks,
      List<String> exportedDecoderIds,
      Override override,
    })
    makeFakeExporters({required bool applies}) {
      final applicabilityChecks = <String>[];
      final exportedDecoderIds = <String>[];
      final exporter = (
        id: 'fake_pcap',
        requiredTier: LicenseTier.pro,
        labelFor: (BuildContext _, ActiveDecoder d) => 'Export ${d.id} as Fake',
        isApplicable: (ActiveDecoder d) {
          applicabilityChecks.add(d.id);
          return applies;
        },
        export:
            ({
              required BuildContext context,
              required WidgetRef ref,
              required ActiveDecoder decoder,
            }) async {
              exportedDecoderIds.add(decoder.id);
            },
      );
      return (
        applicabilityChecks: applicabilityChecks,
        exportedDecoderIds: exportedDecoderIds,
        override: transactionTableExportersProvider.overrideWithValue(
          <TransactionTableExporter>[exporter],
        ),
      );
    }

    testWidgets('overflow icon hidden when no exporter is registered', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const TransactionTablePanel(),
          decoders: [
            _decoder('d0', 'ethernet_axis', [_tx(0, 10, 'F')]),
          ],
        ),
      );
      await tester.pumpAndSettle();
      // No PopupMenuButton<TransactionTableExporter-entry> is built when the
      // open-core default (empty list) is in effect.
      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('overflow icon hidden when exporter is registered but no '
        'visible decoder applies', (tester) async {
      final fake = makeFakeExporters(applies: false);
      await tester.pumpWidget(
        _wrap(
          const TransactionTablePanel(),
          decoders: [
            _decoder('d0', 'ethernet_axis', [_tx(0, 10, 'F')]),
          ],
          extra: [fake.override],
        ),
      );
      await tester.pumpAndSettle();
      // applicability ran but returned false → no menu icon.
      expect(fake.applicabilityChecks, ['d0']);
      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('overflow menu shows one entry per applicable decoder with '
        'a tier badge', (tester) async {
      final fake = makeFakeExporters(applies: true);
      await tester.pumpWidget(
        _wrap(
          const TransactionTablePanel(),
          decoders: [
            _decoder('d0', 'ethernet_axis', [_tx(0, 10, 'F0')]),
            _decoder(
              'd1',
              'ethernet_mii',
              [_tx(20, 30, 'F1')],
              instanceNumber: 2,
            ),
          ],
          extra: [fake.override],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // One menu item per applicable (decoder, exporter) pair.
      expect(find.text('Export d0 as Fake'), findsOneWidget);
      expect(find.text('Export d1 as Fake'), findsOneWidget);
      // PRO badge appears next to each entry (Pro requiredTier).
      expect(find.byType(WaveCruxFeatureTierBadge), findsAtLeast(2));
    });

    testWidgets('tapping a menu entry invokes that exporter on its decoder', (
      tester,
    ) async {
      final fake = makeFakeExporters(applies: true);
      await tester.pumpWidget(
        _wrap(
          const TransactionTablePanel(),
          decoders: [
            _decoder('d0', 'ethernet_axis', [_tx(0, 10, 'F0')]),
          ],
          extra: [fake.override],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export d0 as Fake'));
      await tester.pumpAndSettle();

      expect(fake.exportedDecoderIds, ['d0']);
    });

    testWidgets('decoder filter narrows the overflow menu to one entry', (
      tester,
    ) async {
      final fake = makeFakeExporters(applies: true);
      await tester.pumpWidget(
        _wrap(
          const TransactionTablePanel(),
          decoders: [
            _decoder('d0', 'ethernet_axis', [_tx(0, 10, 'F0')]),
            _decoder(
              'd1',
              'ethernet_mii',
              [_tx(20, 30, 'F1')],
              instanceNumber: 2,
            ),
          ],
          extra: [fake.override],
        ),
      );
      await tester.pumpAndSettle();

      // Filter to only d0.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TransactionTablePanel)),
      );
      container
          .read(transactionTableFilterProvider.notifier)
          .setDecoderFilter('d0');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Export d0 as Fake'), findsOneWidget);
      expect(find.text('Export d1 as Fake'), findsNothing);
    });
  });

  // ── decoder filter popup menu (interactive _showDecoderMenu path) ─────────

  group('TransactionTablePanel — decoder filter popup menu', () {
    testWidgets('tapping the filter button opens the menu listing decoders', (
      tester,
    ) async {
      DecoderRegistry.instance
        ..register(_def('spi', 'SPI'), (_) => throw UnimplementedError())
        ..register(_def('uart', 'UART'), (_) => throw UnimplementedError());
      await tester.pumpWidget(
        _wrap(
          const TransactionTablePanel(),
          decoders: [
            _decoder('d0', 'spi', [_tx(0, 10, 'SPI Write')]),
            _decoder('d1', 'uart', [_tx(0, 10, 'UART Frame')]),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final l10n = tester
          .element(find.byType(TransactionTablePanel))
          .let(L10N.of);

      // Tap the current-filter label to open the popup menu.
      await tester.tap(find.text(l10n.transactionTableFilterAllDecoders));
      await tester.pumpAndSettle();

      // Each decoder row in the menu has configure + remove icon buttons —
      // these icons are menu-only, so two of each proves both rows rendered.
      expect(find.byIcon(Icons.settings_outlined), findsNWidgets(2));
      expect(find.byIcon(Icons.close), findsNWidgets(2));
      // The menu's "All decoders" entry coexists with the button label.
      expect(
        find.text(l10n.transactionTableFilterAllDecoders),
        findsNWidgets(2),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('selecting a decoder in the menu sets the decoder filter', (
      tester,
    ) async {
      DecoderRegistry.instance
        ..register(_def('spi', 'SPI'), (_) => throw UnimplementedError())
        ..register(_def('uart', 'UART'), (_) => throw UnimplementedError());
      await tester.pumpWidget(
        _wrap(
          const TransactionTablePanel(),
          decoders: [
            _decoder('d0', 'spi', [_tx(0, 10, 'SPI Write')]),
            _decoder('d1', 'uart', [_tx(0, 10, 'UART Frame')]),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TransactionTablePanel)),
      );
      final l10n = tester
          .element(find.byType(TransactionTablePanel))
          .let(L10N.of);

      await tester.tap(find.text(l10n.transactionTableFilterAllDecoders));
      await tester.pumpAndSettle();
      // Tap the SPI decoder label inside the menu (the overlay copy is last in
      // the widget tree; the first copy is the table's Decoder-column cell).
      await tester.tap(find.text('SPI #1').last);
      await tester.pumpAndSettle();

      expect(
        container.read(transactionTableFilterProvider).decoderIdFilter,
        'd0',
      );
      // UART row is now filtered out of the table.
      expect(find.text('UART Frame'), findsNothing);
    });

    testWidgets('selecting "All decoders" clears an active filter', (
      tester,
    ) async {
      DecoderRegistry.instance.register(
        _def('spi', 'SPI'),
        (_) => throw UnimplementedError(),
      );
      await tester.pumpWidget(
        _wrap(
          const TransactionTablePanel(),
          decoders: [
            _decoder('d0', 'spi', [_tx(0, 10, 'SPI Write')]),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TransactionTablePanel)),
      );
      container
          .read(transactionTableFilterProvider.notifier)
          .setDecoderFilter('d0');
      await tester.pumpAndSettle();
      final l10n = tester
          .element(find.byType(TransactionTablePanel))
          .let(L10N.of);

      // Open the menu via the filter button (the dropdown arrow uniquely
      // identifies it; the label text also appears in the table cell).
      await tester.tap(find.byIcon(Icons.arrow_drop_down));
      await tester.pumpAndSettle();
      // Tap the menu's "All decoders" entry.
      await tester.tap(find.text(l10n.transactionTableFilterAllDecoders).last);
      await tester.pumpAndSettle();

      expect(
        container.read(transactionTableFilterProvider).decoderIdFilter,
        isNull,
      );
    });

    testWidgets('remove icon in the menu removes the decoder', (tester) async {
      DecoderRegistry.instance.register(
        _def('spi', 'SPI'),
        (_) => throw UnimplementedError(),
      );
      await tester.pumpWidget(
        _wrap(
          const TransactionTablePanel(),
          decoders: [
            _decoder('d0', 'spi', [_tx(0, 10, 'SPI Write')]),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TransactionTablePanel)),
      );
      final l10n = tester
          .element(find.byType(TransactionTablePanel))
          .let(L10N.of);

      await tester.tap(find.text(l10n.transactionTableFilterAllDecoders));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(container.read(activeDecodersProvider), isEmpty);
    });

    testWidgets('configure icon in the menu opens the decoder config dialog', (
      tester,
    ) async {
      DecoderRegistry.instance.register(
        _def('spi', 'SPI'),
        (_) => throw UnimplementedError(),
      );
      await tester.pumpWidget(
        _wrap(
          const TransactionTablePanel(),
          decoders: [
            _decoder('d0', 'spi', [_tx(0, 10, 'SPI Write')]),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final l10n = tester
          .element(find.byType(TransactionTablePanel))
          .let(L10N.of);

      await tester.tap(find.text(l10n.transactionTableFilterAllDecoders));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      // The edit dialog mounts; the menu's configure action ran without error.
      expect(find.byType(DecoderConfigDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ── search clear button ────────────────────────────────────────────────────

  testWidgets('search clear button empties the field and resets the filter', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const TransactionTablePanel(),
        decoders: [
          _decoder('d0', 'spi', [
            _tx(0, 10, 'Write 0xFF'),
            _tx(20, 30, 'Read 0x50'),
          ]),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TransactionTablePanel)),
    );

    await tester.enterText(find.byType(TextField), 'read');
    await tester.pumpAndSettle();
    expect(find.text('Write 0xFF'), findsNothing);
    // Clear (suffix) icon now visible.
    expect(find.byIcon(Icons.clear), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(container.read(transactionTableFilterProvider).searchQuery, '');
    // Both rows visible again.
    expect(find.text('Write 0xFF'), findsOneWidget);
    expect(find.text('Read 0x50'), findsOneWidget);
  });

  // ── sort by tapping a column header ─────────────────────────────────────────

  testWidgets('tapping the Start column header sorts by startTime', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const TransactionTablePanel(),
        decoders: [
          _decoder('d0', 'spi', [
            _tx(30, 40, 'C'),
            _tx(10, 20, 'A'),
          ]),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TransactionTablePanel)),
    );
    final l10n = tester
        .element(find.byType(TransactionTablePanel))
        .let(L10N.of);

    // Tap the Start column header — drives DataColumn.onSort → setSort.
    await tester.tap(find.text(l10n.transactionTableColumnStartTime));
    await tester.pumpAndSettle();

    expect(
      container.read(transactionTableFilterProvider).sortColumn,
      TransactionSortColumn.startTime,
    );
  });

  testWidgets('tapping the Decoder column header sorts by decoder', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const TransactionTablePanel(),
        decoders: [
          _decoder('d0', 'spi', [_tx(0, 10, 'A')]),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TransactionTablePanel)),
    );
    final l10n = tester
        .element(find.byType(TransactionTablePanel))
        .let(L10N.of);

    await tester.tap(find.text(l10n.transactionTableColumnDecoder));
    await tester.pumpAndSettle();

    expect(
      container.read(transactionTableFilterProvider).sortColumn,
      TransactionSortColumn.decoder,
    );
  });

  // ── selected-row highlight ──────────────────────────────────────────────────

  testWidgets('selected row renders as a selected DataRow', (tester) async {
    final tx = _tx(100, 200, 'Frame A');
    await tester.pumpWidget(
      _wrap(
        const TransactionTablePanel(),
        decoders: [
          _decoder('d0', 'uart', [tx]),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TransactionTablePanel)),
    );

    // Select the transaction directly via the provider, then re-pump. This
    // exercises the isSelected branch of the row color-resolver and rebuilds
    // _TableBody with a non-null selectedRow.
    container.read(selectedTransactionProvider.notifier).select(tx, 'd0');
    await tester.pumpAndSettle();

    expect(container.read(selectedTransactionProvider)!.$2, 'd0');
    // The selected row still renders without exception.
    expect(find.text('Frame A'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Configure hands the dialog the ACTIVE TAB container, not the root',
    (tester) async {
      // Regression for the route-mounted per-tab scope leak (a defect class
      // NetCrux hit first, surfaced here by crux-shared's
      // `route_mounted_scope_leak_test` guard).
      //
      // A dialog route is a child of the Navigator, which sits ABOVE the
      // per-tab UncontrolledProviderScope. So `ref` inside
      // DecoderConfigDialog resolves the ROOT container, where no file is
      // loaded. Two of the three call sites already pre-read from their own
      // per-tab ref and pass the values in; this panel did not, so
      // configuring a decoder from the transaction table wrote the edit to
      // the root notifier and the active tab silently kept its old config.
      //
      // Every other test in this file uses ONE ProviderScope, which is why
      // none of them could see this: panel and dialog shared a container.
      // This test builds the real two-container shape.
      // The Configure handler early-returns unless the registry knows the
      // decoder, so register it before pumping.
      DecoderRegistry.instance.register(
        _def('spi', 'SPI'),
        (_) => throw UnimplementedError(),
      );

      final rootContainer = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          // Root has NO decoders — mirroring "no file loaded at root".
          activeDecodersProvider.overrideWith(
            () => _FixedDecodersNotifier(const []),
          ),
        ],
      );
      addTearDown(rootContainer.dispose);

      final tabContainer = ProviderContainer(
        parent: rootContainer,
        overrides: [
          activeDecodersProvider.overrideWith(
            () => _FixedDecodersNotifier([_decoder('d0', 'spi', const [])]),
          ),
        ],
      );
      addTearDown(tabContainer.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: rootContainer,
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              // The panel lives inside the per-tab scope, exactly as it does
              // under ViewerScreen.
              body: UncontrolledProviderScope(
                container: tabContainer,
                child: const TransactionTablePanel(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open the decoder menu, then Configure….
      // The decoder filter button is the GestureDetector wrapping the
      // dropdown arrow; tap it to open the decoder menu.
      await tester.tapAt(
        tester.getCenter(find.byIcon(Icons.arrow_drop_down).first),
      );
      await tester.pumpAndSettle();
      // The Configure entry in the decoder menu is an icon button
      // (settings gear), tooltipped rather than labelled.
      final configure = find.byIcon(Icons.settings_outlined);
      expect(configure, findsOneWidget);
      await tester.tap(configure);
      await tester.pumpAndSettle();

      final dialog = tester.widget<DecoderConfigDialog>(
        find.byType(DecoderConfigDialog),
      );

      // The assertion that bites. Before the fix both were null, the dialog
      // fell back to `ref.read(...)` off the root container, and the edit
      // landed nowhere the user could see.
      expect(
        dialog.decodersNotifier,
        same(tabContainer.read(activeDecodersProvider.notifier)),
        reason: 'the dialog must write to the active tab notifier, not root',
      );
      expect(
        dialog.decodersNotifier,
        isNot(same(rootContainer.read(activeDecodersProvider.notifier))),
      );
      expect(dialog.signalMap, isNotNull);
    },
  );

  testWidgets(
    'Configure lands on the tab container even with no arguments passed',
    (tester) async {
      // Closes the CLASS, not just the one call site.
      //
      // `signalMap` / `decodersNotifier` are optional, and the `??`
      // fallbacks behind them read the dialog's own `ref` — which resolves
      // ROOT, because a dialog route is a child of the Navigator, above the
      // per-tab scope. Fixing the transaction-table caller (22231934) fixed
      // one instance; any new call site that omitted an argument would have
      // reintroduced it just as silently.
      //
      // DecoderConfigDialog.show/showEdit now bind the launching context's
      // container to the dialog subtree, so the fallback is correct by
      // construction. This test pushes the dialog from inside a tab scope
      // passing NEITHER argument, and asserts the fallback still resolves
      // the tab — which is what a future forgetful caller will rely on.
      DecoderRegistry.instance.register(
        _def('spi', 'SPI'),
        (_) => throw UnimplementedError(),
      );

      final rootContainer = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          activeDecodersProvider.overrideWith(
            () => _FixedDecodersNotifier(const []),
          ),
        ],
      );
      addTearDown(rootContainer.dispose);
      final tabContainer = ProviderContainer(
        parent: rootContainer,
        overrides: [
          activeDecodersProvider.overrideWith(
            () => _FixedDecodersNotifier([_decoder('d0', 'spi', const [])]),
          ),
        ],
      );
      addTearDown(tabContainer.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: rootContainer,
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.macOS),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(
              body: UncontrolledProviderScope(
                container: tabContainer,
                child: Builder(
                  builder: (ctx) => TextButton(
                    // Deliberately passes no signalMap and no
                    // decodersNotifier — the forgetful-caller shape.
                    onPressed: () => DecoderConfigDialog.show(
                      ctx,
                      definition: _def('spi', 'SPI'),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The dialog's own ref must see the TAB's decoder list (one entry),
      // not root's (empty).
      final dialogElement = tester.element(find.byType(DecoderConfigDialog));
      final container = ProviderScope.containerOf(dialogElement, listen: false);
      expect(
        container.read(activeDecodersProvider),
        hasLength(1),
        reason: 'the dialog subtree must resolve the launching tab container',
      );
      expect(
        container.read(activeDecodersProvider.notifier),
        same(tabContainer.read(activeDecodersProvider.notifier)),
      );
    },
  );

  // ── render cap ──────────────────────────────────────────────────────────

  group('TransactionTablePanel — render cap', () {
    // Decoders run over the WHOLE trace, so the row count is a property of
    // the capture, not of the pane: a UART at 115 200 baud over one second
    // is ~11 500 transactions. `DataTable` materializes a row per
    // transaction and sizes its columns intrinsically; measured on this
    // machine the pane's first frame costs ~1.8 s at 100 rows, 8.5 s at
    // 2 000, and 20 000 rows had not finished laying out after fifteen
    // minutes. The panel therefore renders at most `renderLimit` rows and
    // says so.
    //
    // PRIMARY MUTATION TARGET: passing the full `rows` to
    // `TransactionTableBody` again renders every row and drops the notice.
    Widget wrapLimited(List<ActiveDecoder> decoders, int limit) =>
        ProviderScope(
          overrides: [
            productTelemetryConfig,
            activeDecodersProvider.overrideWith(
              () => _FixedDecodersNotifier(decoders),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Scaffold(body: TransactionTablePanel(renderLimit: limit)),
          ),
        );

    testWidgets('renders at most the cap, and says how many it is showing', (
      tester,
    ) async {
      final txs = <DecodedTransaction>[
        for (var i = 0; i < 40; i++) _tx(i * 10, i * 10 + 5, 'tx$i'),
      ];
      await tester.pumpWidget(
        wrapLimited([_decoder('d1', 'uart', txs)], 5),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final body = tester.widget<TransactionTableBody>(
        find.byType(TransactionTableBody),
      );
      expect(body.rows, hasLength(5));
      final l10n = tester
          .element(find.byType(TransactionTablePanel))
          .let(L10N.of);
      expect(find.text(l10n.transactionTableTruncated(5, 40)), findsOneWidget);
      // The rows shown are the head of the active sort order.
      expect(find.text('tx0'), findsOneWidget);
      expect(find.text('tx39'), findsNothing);
    });

    testWidgets('no notice when everything fits', (tester) async {
      final txs = <DecodedTransaction>[
        for (var i = 0; i < 3; i++) _tx(i * 10, i * 10 + 5, 'tx$i'),
      ];
      await tester.pumpWidget(
        wrapLimited([_decoder('d1', 'uart', txs)], 5),
      );
      await tester.pumpAndSettle();
      final body = tester.widget<TransactionTableBody>(
        find.byType(TransactionTableBody),
      );
      expect(body.rows, hasLength(3));
      final l10n = tester
          .element(find.byType(TransactionTablePanel))
          .let(L10N.of);
      expect(find.text(l10n.transactionTableTruncated(3, 3)), findsNothing);
    });
  });
}

// Small extension to avoid creating a named helper just for BuildContext lookup.
extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}
