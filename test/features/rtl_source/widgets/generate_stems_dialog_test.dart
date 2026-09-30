// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/rtl_source/widgets/generate_stems_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

const _topV = '''
module top(
  input wire clk,
  output [7:0] q
);
  wire [3:0] cnt;
  cpu u_cpu (.clk(clk), .q(q));
endmodule
''';

const _cpuV = '''
module cpu(input clk, output [7:0] q);
  reg [7:0] acc;
endmodule
''';

Widget _host({
  required void Function(GenerateStemsOutcome?) onResult,
  SourceFilesPicker? filesPicker,
  SourceFolderPicker? folderPicker,
  StemsSavePicker? savePicker,
  StemsFileSink? fileSink,
}) {
  return MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              onResult(
                await GenerateStemsDialog.show(
                  context,
                  filesPicker: filesPicker,
                  folderPicker: folderPicker,
                  savePicker: savePicker,
                  fileSink: fileSink,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late Directory tmp;
  late String topPath;
  late String cpuPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('gen_stems_test_');
    topPath = '${tmp.path}/top.v';
    cpuPath = '${tmp.path}/cpu.v';
    await File(topPath).writeAsString(_topV);
    await File(cpuPath).writeAsString(_cpuV);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('GenerateStemsDialog — locale sweep', () {
    for (final pair in const [
      ('en', null),
      ('zh', 'CN'),
      ('ja', null),
      ('ko', null),
    ]) {
      testWidgets('opens without exception in ${pair.$1}', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(pair.$1, pair.$2),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => GenerateStemsDialog.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(GenerateStemsDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // The OS picker is its own window. Where the app window stays live behind it
  // — a portal or zenity process on Linux, the browser — the dialog can close
  // while the picker is still up, and the picker's answer then arrives at a
  // disposed State.
  group('GenerateStemsDialog — a picker answering after the dialog closed', () {
    testWidgets('the files picker does not touch the disposed dialog', (
      tester,
    ) async {
      final picked = Completer<List<String>>();
      await tester.pumpWidget(
        _host(onResult: (_) {}, filesPicker: () => picked.future),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.note_add_outlined));
      await tester.pump();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(GenerateStemsDialog), findsNothing);

      picked.complete([topPath]);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('the folder picker does not touch the disposed dialog', (
      tester,
    ) async {
      final picked = Completer<String?>();
      await tester.pumpWidget(
        _host(onResult: (_) {}, folderPicker: () => picked.future),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.pump();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(GenerateStemsDialog), findsNothing);

      // The folder walk is real directory IO: its events arrive in the real
      // async zone and its continuations run when the test zone pumps, so
      // alternate the two until the walk has finished.
      picked.complete(tmp.path);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('generates a stems file and pops an outcome', (tester) async {
    GenerateStemsOutcome? result;
    var hasResult = false;
    String? written;

    await tester.pumpWidget(
      _host(
        onResult: (r) {
          result = r;
          hasResult = true;
        },
        filesPicker: () async => [topPath, cpuPath],
        savePicker: (suggested) async => '${tmp.path}/$suggested',
        fileSink: (path, contents) async => written = contents,
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Add the (injected) sources, then generate.
    await tester.tap(find.byIcon(Icons.note_add_outlined));
    await tester.pumpAndSettle();
    expect(find.textContaining('top.v'), findsWidgets);

    // Generation reads the temp source files via dart:io, which only completes
    // in the real async zone — and the busy spinner means pumpAndSettle would
    // never settle. Run the tap + real IO inside runAsync, then pump the pop.
    await tester.runAsync(() async {
      await tester.tap(find.byType(FilledButton));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(hasResult, isTrue);
    expect(result, isNotNull);
    expect(result!.topModule, 'top');
    expect(result!.mappingCount, greaterThan(0));
    expect(result!.stemsPath, endsWith('top.stems'));
    // The written stems file is in the on-disk format the parser reads.
    expect(written, contains('++ scope top'));
    expect(written, contains('++ var top.clk'));
  });

  testWidgets('shows an inline error when no sources are selected', (
    tester,
  ) async {
    var hasResult = false;
    await tester.pumpWidget(
      _host(onResult: (_) => hasResult = true),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // Stays open, no outcome, shows the empty-sources guidance.
    expect(hasResult, isFalse);
    expect(find.byType(GenerateStemsDialog), findsOneWidget);
    final l10n = await L10N.delegate.load(const Locale('en'));
    expect(find.text(l10n.rtlGenerateNoSourcesYet), findsWidgets);
  });

  testWidgets('dirty cancel prompts to discard; keep editing stays open', (
    tester,
  ) async {
    await tester.pumpWidget(_host(onResult: (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Dirty the form by typing a top module.
    await tester.enterText(find.byType(TextField), 'top');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);

    // "Keep editing" returns to the dialog with input intact.
    await tester.tap(
      find.byKey(const ValueKey('editorDiscardConfirmKeepEditing')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(GenerateStemsDialog), findsOneWidget);
    expect(find.text('top'), findsOneWidget);

    // "Discard" closes the dialog.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('editorDiscardConfirmDiscard')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GenerateStemsDialog), findsNothing);
  });

  testWidgets('clean cancel closes without a prompt', (tester) async {
    await tester.pumpWidget(_host(onResult: (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(GenerateStemsDialog), findsNothing);
  });
}
