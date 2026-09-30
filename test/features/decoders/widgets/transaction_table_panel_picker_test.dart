// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The CSV export's save picker outliving the panel that opened it.
//
// On Windows and Linux the app stays live behind an OS picker, so the bottom
// dock tab holding this panel can be closed while the picker is up. The
// `finally` that clears systemDialogInFlightProvider used to read the
// panel's `ref`, which throws once the panel is gone: the flag stayed set and
// the viewer's AbsorbPointer swallowed every click for the rest of the
// session. test/static/finally_after_await_guard_test.dart keeps the shape
// out of lib/; this pins the behaviour at one site.
//
// LOCALE_SWEEP_EXEMPT: a lifecycle regression test (a flag cleared after the
// widget is disposed); it asserts on provider state, not on rendered text.
// The panel's own locale sweep is in transaction_table_panel_test.dart.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wavecrux/core/providers/system_dialog_provider.dart';
import 'package:wavecrux/domain/models/active_decoder.dart';
import 'package:wavecrux/domain/models/decoded_transaction.dart';
import 'package:wavecrux/domain/models/decoder_config.dart';
import 'package:wavecrux/domain/models/decoder_definition.dart';
import 'package:wavecrux/features/decoders/providers/active_decoders_provider.dart';
import 'package:wavecrux/features/decoders/widgets/transaction_table_panel.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/decoder_registry.dart';

/// A save picker that answers only when the test says so.
class _PendingSavePicker extends FilePickerPlatform {
  final answer = Completer<String?>();

  @override
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    bool lockParentWindow = false,
  }) => answer.future;
}

class _FixedDecodersNotifier extends ActiveDecodersNotifier {
  @override
  List<ActiveDecoder> build() => const [
    ActiveDecoder(
      id: 'd1',
      decoderId: 'spi',
      config: DecoderConfig(signalBindings: {}),
      instanceNumber: 1,
      transactions: [
        DecodedTransaction(startTime: 10, endTime: 20, label: 'MOSI 0x5A'),
      ],
    ),
  ];
}

void main() {
  late FilePickerPlatform realPicker;
  setUp(() => realPicker = FilePickerPlatform.instance);
  tearDown(() => FilePickerPlatform.instance = realPicker);

  testWidgets('closing the panel under its save picker still clears the '
      'system-dialog flag', (tester) async {
    DecoderRegistry.instance.register(
      const DecoderDefinition(
        id: 'spi',
        displayName: 'SPI',
        description: '',
        requiredSignals: [],
      ),
      (_) => throw UnimplementedError(),
    );
    addTearDown(() => DecoderRegistry.instance.unregister('spi'));
    final picker = _PendingSavePicker();
    FilePickerPlatform.instance = picker;

    // The container outlives the panel, as the root scope does in the app.
    final container = ProviderContainer(
      overrides: [
        activeDecodersProvider.overrideWith(_FixedDecodersNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    final showPanel = ValueNotifier(true);
    addTearDown(showPanel.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showPanel,
              builder: (_, show, _) =>
                  show ? const TransactionTablePanel() : const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = L10N.of(tester.element(find.byType(TransactionTablePanel)));

    await tester.tap(find.text(l10n.transactionTableExportCsv));
    await tester.pump();
    expect(container.read(systemDialogInFlightProvider), isTrue);

    showPanel.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(TransactionTablePanel), findsNothing);

    final path = p.join(Directory.systemTemp.path, 'wcx_panel_gone.csv');
    picker.answer.complete(path);
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Left set, the viewer's pointer absorber stays on for the session.
    expect(container.read(systemDialogInFlightProvider), isFalse);
    // The answer is dropped with the panel: nothing is written.
    expect(File(path).existsSync(), isFalse);
  });
}
