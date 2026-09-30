// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/rtl_source/providers/rtl_source_provider.dart';
import 'package:wavecrux/features/rtl_source/widgets/generate_stems_dialog.dart';
import 'package:wavecrux/features/rtl_source/widgets/import_verilator_ast_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Committed Verilator 5.048 dumps — see the fixtures README.
final _fixtureRoot =
    '${Directory.current.path}/test/fixtures/rtl_source/verilator_ast';

Widget _host({
  required void Function(GenerateStemsOutcome?) onResult,
  AstFilePicker? astPicker,
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
                await ImportVerilatorAstDialog.show(
                  context,
                  astPicker: astPicker,
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

/// Taps the confirm button and waits out the real-IO import inside runAsync
/// (the busy spinner means pumpAndSettle would never settle).
Future<void> _tapImport(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.byType(FilledButton));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('import_ast_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('ImportVerilatorAstDialog — locale sweep', () {
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
                  onPressed: () => ImportVerilatorAstDialog.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(ImportVerilatorAstDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // The OS picker is its own window. Where the app window stays live behind
  // it — a portal or zenity process on Linux, the browser — the dialog can
  // close first, and the picker's answer then arrives at a disposed State.
  testWidgets('an AST picker answering after the dialog closed does not '
      'touch the disposed dialog', (tester) async {
    final picked = Completer<String?>();
    await tester.pumpWidget(
      _host(onResult: (_) {}, astPicker: () => picked.future),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.data_object));
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(ImportVerilatorAstDialog), findsNothing);

    picked.complete('$_fixtureRoot/cpu/Vtop.tree.json');
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('imports the cpu AST dump, writes a stems file, and the result '
      'loads into RtlSourceState', (tester) async {
    GenerateStemsOutcome? result;
    String? writtenPath;

    await tester.pumpWidget(
      _host(
        onResult: (r) => result = r,
        astPicker: () async => '$_fixtureRoot/cpu/Vtop.tree.json',
        savePicker: (suggested) async => '${tmp.path}/$suggested',
        fileSink: (path, contents) async {
          writtenPath = path;
          await File(path).writeAsString(contents);
        },
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.data_object));
    await tester.pumpAndSettle();
    expect(find.textContaining('Vtop.tree.json'), findsWidgets);

    await _tapImport(tester);

    expect(result, isNotNull);
    expect(result!.topModule, 'top');
    expect(result!.mappingCount, 18);
    expect(result!.stemsPath, endsWith('top.stems'));
    expect(writtenPath, result!.stemsPath);

    // The written stems file feeds the exact pipeline the stems parser feeds
    // today: load it into RtlSourceState and resolve an elaborated path.
    await tester.runAsync(() async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(rtlSourceProvider.notifier)
          .loadStemsFile(result!.stemsPath);
      final state = container.read(rtlSourceProvider);
      expect(state.status, RtlStemsStatus.ready);
      expect(state.hasStems, isTrue);
      final hit = state.stems!.lookup('top.u_regfile.mem');
      expect(hit, isNotNull);
      expect(hit!.sourceFile, endsWith('regfile.v'));
      expect(hit.lineNumber, 8);
    });
  });

  testWidgets('genloop AST dump produces unrolled generate paths in the '
      'written stems', (tester) async {
    String? written;
    await tester.pumpWidget(
      _host(
        onResult: (_) {},
        astPicker: () async => '$_fixtureRoot/genloop/Vtop.tree.json',
        savePicker: (suggested) async => '${tmp.path}/$suggested',
        fileSink: (path, contents) async => written = contents,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.data_object));
    await tester.pumpAndSettle();
    await _tapImport(tester);

    expect(written, isNotNull);
    expect(written, contains('top.gen_blink[0].u_blink.led'));
    expect(written, contains('top.gen_blink[3].u_blink'));
  });

  testWidgets('shows an inline error when no AST file is picked', (
    tester,
  ) async {
    var hasResult = false;
    await tester.pumpWidget(_host(onResult: (_) => hasResult = true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(hasResult, isFalse);
    expect(find.byType(ImportVerilatorAstDialog), findsOneWidget);
    final l10n = await L10N.delegate.load(const Locale('en'));
    expect(find.text(l10n.rtlImportAstNoFileYet), findsWidgets);
  });

  testWidgets('ambiguous top surfaces the candidates; typing one resolves '
      'the import', (tester) async {
    // Two uninstantiated modules → the importer cannot auto-pick a top.
    // Real file IO must run inside runAsync — the FakeAsync test zone never
    // completes dart:io futures.
    final treePath = '${tmp.path}/Vtwo.tree.json';
    await tester.runAsync(() async {
      await File(treePath).writeAsString(
        jsonEncode({
          'type': 'NETLIST',
          'modulesp': [
            {
              'type': 'MODULE',
              'name': 'alpha',
              'addr': '(A)',
              'loc': 'e,1:8,1:11',
              'stmtsp': [
                {
                  'type': 'VAR',
                  'name': 'x',
                  'loc': 'e,2:3,2:4',
                  'varType': 'WIRE',
                },
              ],
            },
            {
              'type': 'MODULE',
              'name': 'beta',
              'addr': '(B)',
              'loc': 'e,5:8,5:11',
              'stmtsp': [
                {
                  'type': 'VAR',
                  'name': 'y',
                  'loc': 'e,6:3,6:4',
                  'varType': 'WIRE',
                },
              ],
            },
          ],
        }),
      );
      await File('${tmp.path}/Vtwo.tree.meta.json').writeAsString(
        jsonEncode({
          'files': {
            'e': {'filename': 'two.v', 'realpath': 'two.v'},
          },
        }),
      );
    });

    GenerateStemsOutcome? result;
    await tester.pumpWidget(
      _host(
        onResult: (r) => result = r,
        astPicker: () async => treePath,
        savePicker: (suggested) async => '${tmp.path}/$suggested',
        fileSink: (path, contents) async {},
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.data_object));
    await tester.pumpAndSettle();

    await _tapImport(tester);

    // Same UX as Generate RTL Stems: inline candidates + top-module field.
    expect(result, isNull);
    expect(find.byType(ImportVerilatorAstDialog), findsOneWidget);
    expect(find.textContaining('alpha, beta'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'beta');
    await _tapImport(tester);

    expect(result, isNotNull);
    expect(result!.topModule, 'beta');
    expect(result!.stemsPath, endsWith('beta.stems'));
  });

  testWidgets('a missing meta file shows the diagnostic inline and pops '
      'nothing', (tester) async {
    // A tree with no sibling meta. Real file IO must run inside runAsync —
    // the FakeAsync test zone never completes dart:io futures.
    final orphan = '${tmp.path}/Vtop.tree.json';
    await tester.runAsync(() async {
      await File('$_fixtureRoot/cpu/Vtop.tree.json').copy(orphan);
    });

    var hasResult = false;
    await tester.pumpWidget(
      _host(
        onResult: (_) => hasResult = true,
        astPicker: () async => orphan,
        savePicker: (suggested) async => '${tmp.path}/$suggested',
        fileSink: (path, contents) async {},
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.data_object));
    await tester.pumpAndSettle();

    await _tapImport(tester);

    expect(hasResult, isFalse);
    expect(find.byType(ImportVerilatorAstDialog), findsOneWidget);
    expect(find.textContaining('Vtop.tree.meta.json'), findsOneWidget);
  });

  testWidgets('dirty cancel prompts to discard; keep editing stays open', (
    tester,
  ) async {
    await tester.pumpWidget(_host(onResult: (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Dirty the form by typing a top module.
    await tester.enterText(find.byType(TextField), 'beta');
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
    expect(find.byType(ImportVerilatorAstDialog), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);

    // "Discard" closes the dialog.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('editorDiscardConfirmDiscard')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ImportVerilatorAstDialog), findsNothing);
  });

  testWidgets('clean cancel closes without a prompt', (tester) async {
    await tester.pumpWidget(_host(onResult: (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(ImportVerilatorAstDialog), findsNothing);
  });
}
