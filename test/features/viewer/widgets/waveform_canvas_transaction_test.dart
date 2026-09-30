// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wavecrux/domain/interfaces/waveform_data_source.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/features/cursors/providers/cursor_providers.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/viewer/providers/selected_transaction_provider.dart';
import 'package:wavecrux/features/viewer/providers/waveform_source_provider.dart';
import 'package:wavecrux/features/viewer/widgets/waveform_canvas.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

// ── fakes ─────────────────────────────────────────────────────────────────────

class _MockSource extends Mock implements WaveformDataSource {}

class _LoadedSourceNotifier extends WaveformSourceNotifier {
  _LoadedSourceNotifier(this._source);
  final WaveformDataSource _source;

  @override
  AsyncValue<WaveformDataSource?> build() => AsyncData(_source);
}

/// Overrides [ActiveDecodersNotifier] with a pre-populated list of decoders so
/// tests can verify transaction lane rendering without going through [decodeAll].
class _FixedActiveDecodersNotifier extends ActiveDecodersNotifier {
  _FixedActiveDecodersNotifier(this._decoders);
  final List<ActiveDecoder> _decoders;

  @override
  List<ActiveDecoder> build() => _decoders;
}

// ── helpers ───────────────────────────────────────────────────────────────────

_MockSource _makeSource() {
  final s = _MockSource();
  when(() => s.startTime).thenReturn(0);
  when(() => s.endTime).thenReturn(1000);
  when(() => s.timescale).thenReturn(null);
  when(() => s.rootScopes).thenReturn([]);
  when(() => s.isSignalLoaded(any())).thenReturn(false);
  when(() => s.changesInRange(any(), any(), any())).thenReturn([]);
  when(() => s.valueAt(any(), any())).thenReturn(null);
  return s;
}

ActiveDecoder _makeDecoder({
  String id = 'decoder_0',
  int instanceNumber = 1,
  List<DecodedTransaction> transactions = const [],
}) => ActiveDecoder(
  id: id,
  decoderId: 'spi',
  config: const DecoderConfig(signalBindings: {}),
  instanceNumber: instanceNumber,
  transactions: transactions,
);

Widget _buildApp({
  List<Override> overrides = const [],
  bool withSource = false,
}) {
  final allOverrides = [
    if (withSource)
      waveformSourceProvider.overrideWith(
        () => _LoadedSourceNotifier(_makeSource()),
      ),
    ...overrides,
  ];

  return ProviderScope(
    overrides: allOverrides,
    child: const MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: WaveformCanvas(),
        ),
      ),
    ),
  );
}

// ── tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('WaveformCanvas — transaction overlay', () {
    // ── locale sweep ─────────────────────────────────────────────────────────

    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets(
        'locale sweep ($locale) with active decoder — no exceptions',
        (tester) async {
          final decoder = _makeDecoder(
            transactions: const [
              DecodedTransaction(
                startTime: 100,
                endTime: 300,
                label: 'Write 0xFF',
              ),
            ],
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                waveformSourceProvider.overrideWith(
                  () => _LoadedSourceNotifier(_makeSource()),
                ),
                activeDecodersProvider.overrideWith(
                  () => _FixedActiveDecodersNotifier([decoder]),
                ),
              ],
              child: MaterialApp(
                locale: Locale(locale),
                localizationsDelegates: L10N.localizationsDelegates,
                supportedLocales: L10N.supportedLocales,
                home: const Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 600,
                    child: WaveformCanvas(),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }

    // ── transaction lane appears ──────────────────────────────────────────────

    testWidgets('renders without exception when decoder has transactions', (
      tester,
    ) async {
      final decoder = _makeDecoder(
        transactions: const [
          DecodedTransaction(startTime: 100, endTime: 300, label: 'Write 0xFF'),
          DecodedTransaction(startTime: 400, endTime: 600, label: 'Read 0x00'),
        ],
      );

      await tester.pumpWidget(
        _buildApp(
          withSource: true,
          overrides: [
            activeDecodersProvider.overrideWith(
              () => _FixedActiveDecodersNotifier([decoder]),
            ),
          ],
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'renders transaction lane with error transactions without exception',
      (tester) async {
        final decoder = _makeDecoder(
          transactions: const [
            DecodedTransaction(
              startTime: 100,
              endTime: 200,
              label: 'ERR',
              isError: true,
              errorMessage: 'NAK received',
            ),
          ],
        );

        await tester.pumpWidget(
          _buildApp(
            withSource: true,
            overrides: [
              activeDecodersProvider.overrideWith(
                () => _FixedActiveDecodersNotifier([decoder]),
              ),
            ],
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('renders multiple decoder lanes without exception', (
      tester,
    ) async {
      final decoders = [
        _makeDecoder(
          transactions: const [
            DecodedTransaction(startTime: 0, endTime: 100, label: 'SPI A'),
          ],
        ),
        _makeDecoder(
          id: 'decoder_1',
          transactions: const [
            DecodedTransaction(startTime: 200, endTime: 400, label: 'I2C B'),
          ],
        ),
      ];

      await tester.pumpWidget(
        _buildApp(
          withSource: true,
          overrides: [
            activeDecodersProvider.overrideWith(
              () => _FixedActiveDecodersNotifier(decoders),
            ),
          ],
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('no transaction lane when decoders list is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildApp(
          withSource: true,
          overrides: [
            activeDecodersProvider.overrideWith(
              () => _FixedActiveDecodersNotifier(const []),
            ),
          ],
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    // ── no-file state unaffected ──────────────────────────────────────────────

    testWidgets(
      'shows no-file placeholder even when decoders are active but no source',
      (tester) async {
        final decoder = _makeDecoder(
          transactions: const [
            DecodedTransaction(startTime: 0, endTime: 100, label: 'X'),
          ],
        );

        // No withSource: true — source remains null.
        await tester.pumpWidget(
          _buildApp(
            overrides: [
              activeDecodersProvider.overrideWith(
                () => _FixedActiveDecodersNotifier([decoder]),
              ),
            ],
          ),
        );
        await tester.pump();
        expect(
          find.text('Open a waveform file to view signals'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    // ── selectedTransactionProvider starts null ───────────────────────────────

    testWidgets('selectedTransaction is null at startup', (tester) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(body: WaveformCanvas());
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        container.read(selectedTransactionProvider),
        isNull,
      );
      expect(tester.takeException(), isNull);
    });

    // ── tap on transaction lane sets cursor ───────────────────────────────────

    testWidgets('tap on canvas does not throw with active decoder', (
      tester,
    ) async {
      final decoder = _makeDecoder(
        transactions: const [
          DecodedTransaction(startTime: 100, endTime: 300, label: 'Write 0xFF'),
        ],
      );

      await tester.pumpWidget(
        _buildApp(
          withSource: true,
          overrides: [
            activeDecodersProvider.overrideWith(
              () => _FixedActiveDecodersNotifier([decoder]),
            ),
          ],
        ),
      );
      await tester.pump();

      // Tap somewhere in the canvas area — verifies no crash regardless of
      // whether the tap lands on a transaction block.
      await tester.tapAt(const Offset(200, 14));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'tap on transaction block selects transaction and updates provider',
      (tester) async {
        const tx = DecodedTransaction(
          startTime: 100,
          endTime: 300,
          label: 'Write 0xFF',
        );
        final decoder = _makeDecoder(transactions: const [tx]);

        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              waveformSourceProvider.overrideWith(
                () => _LoadedSourceNotifier(_makeSource()),
              ),
              activeDecodersProvider.overrideWith(
                () => _FixedActiveDecodersNotifier([decoder]),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const Scaffold(
                    body: SizedBox(
                      width: 800,
                      height: 600,
                      child: WaveformCanvas(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        // Flush initState postFrameCallback and LayoutBuilder postFrameCallback
        // so TimeMapper is initialised: startTime=0, endTime=1000, viewportWidth=800
        // → ticksPerPixel = 1000/800 = 1.25
        await tester.pump();
        await tester.pump();

        // Layout confirmed: tx spans ticks 100–300 → pixels 80–240.
        // Transaction lane: y=0, height=28 (no signal lanes above it).
        // Tap at (160, 14) — x=160→time=200, y=14 is within [0, 28].
        await tester.tapAt(const Offset(160, 14));
        await tester.pump();

        expect(tester.takeException(), isNull);

        // Transaction must be selected.
        final selected = container.read(selectedTransactionProvider);
        expect(
          selected,
          isNotNull,
          reason: 'Tap on transaction block should select it',
        );
        expect(selected!.$1.label, equals('Write 0xFF'));
        expect(selected.$2, equals('decoder_0'));
      },
    );

    testWidgets(
      'tap on transaction block moves primary cursor to transaction startTime',
      (tester) async {
        const tx = DecodedTransaction(
          startTime: 100,
          endTime: 300,
          label: 'SPI Write',
        );
        final decoder = _makeDecoder(transactions: const [tx]);

        late ProviderContainer container;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              waveformSourceProvider.overrideWith(
                () => _LoadedSourceNotifier(_makeSource()),
              ),
              activeDecodersProvider.overrideWith(
                () => _FixedActiveDecodersNotifier([decoder]),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) {
                  container = ProviderScope.containerOf(context);
                  return const Scaffold(
                    body: SizedBox(
                      width: 800,
                      height: 600,
                      child: WaveformCanvas(),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        // Tap in the middle of the transaction block (x=160 → time≈200, within
        // tx [100, 300]).  The canvas should override the cursor to tx.startTime.
        await tester.tapAt(const Offset(160, 14));
        await tester.pump();

        expect(tester.takeException(), isNull);
        final cursorTime = container
            .read(cursorStateProvider)
            .primaryCursorTime;
        expect(
          cursorTime,
          equals(tx.startTime),
          reason:
              'Cursor should jump to transaction startTime, not tap position',
        );
      },
    );

    testWidgets('tap in gap between transaction blocks clears selection', (
      tester,
    ) async {
      // Two transactions with a gap between them: [100,200] and [400,500].
      // A tap at x=300 (time≈375, in the gap) should clear selection.
      const tx1 = DecodedTransaction(
        startTime: 100,
        endTime: 200,
        label: 'First',
      );
      const tx2 = DecodedTransaction(
        startTime: 400,
        endTime: 500,
        label: 'Second',
      );
      final decoder = _makeDecoder(transactions: const [tx1, tx2]);

      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            waveformSourceProvider.overrideWith(
              () => _LoadedSourceNotifier(_makeSource()),
            ),
            activeDecodersProvider.overrideWith(
              () => _FixedActiveDecodersNotifier([decoder]),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const Scaffold(
                  body: SizedBox(
                    width: 800,
                    height: 600,
                    child: WaveformCanvas(),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // First select tx1 by tapping it.
      await tester.tapAt(const Offset(120, 14)); // time≈150, in tx1 [100,200]
      await tester.pump();
      expect(container.read(selectedTransactionProvider), isNotNull);

      // Now tap in the gap (x=300 → time=375, between tx1 end 200 and tx2 start 400).
      await tester.tapAt(const Offset(300, 14));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        container.read(selectedTransactionProvider),
        isNull,
        reason: 'Tapping gap between blocks should clear selection',
      );
    });
  });
}
