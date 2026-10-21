// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/links/widgets/open_link_confirm_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/links/wavecrux_link.dart';
import 'package:wavecrux/services/links/wavecrux_link_handler.dart';

/// The confirmation a link raises for a file the user has not opened: it
/// names the file and its full path, starts with focus on Cancel so Enter or
/// Space on arrival opens nothing, treats Escape as Cancel, and opens only on
/// Open. And the messages the outcome of a link turns into.

const String _path = '/home/me/sim/uart_tx.vcd';

/// The dialog's eventual answer, held so a test can act before awaiting it.
class _Answer {
  Future<bool>? future;
}

Future<_Answer> _open(WidgetTester tester, {Locale? locale}) async {
  final answer = _Answer();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: ThemeData(
        extensions: const <ThemeExtension<dynamic>>[CruxDesktopTokens()],
      ),
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open'),
              onPressed: () =>
                  answer.future = OpenLinkConfirmDialog.show(context, _path),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return answer;
}

Key? _focusedAction() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<CruxDialogAction>()
    ?.key;

void main() {
  SemanticsOrphanTestBinding.ensureInitialized();

  group('the dialog', () {
    testWidgets('names the file and the full path it will open', (
      tester,
    ) async {
      await _open(tester);
      expect(find.text('Open a waveform from a link?'), findsOneWidget);
      expect(find.textContaining('uart_tx.vcd'), findsWidgets);
      expect(find.text(_path), findsOneWidget);
    });

    testWidgets('focus starts on Cancel, and Enter there opens nothing', (
      tester,
    ) async {
      final answer = await _open(tester);
      expect(_focusedAction(), const ValueKey('linkConfirmCancel'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(await answer.future, isFalse);
      expect(find.text(_path), findsNothing);
    });

    testWidgets('Space on arrival opens nothing', (tester) async {
      final answer = await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(await answer.future, isFalse);
    });

    testWidgets('Escape is Cancel', (tester) async {
      final answer = await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await answer.future, isFalse);
    });

    testWidgets('a click outside does not answer', (tester) async {
      await _open(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text(_path), findsOneWidget);
    });

    testWidgets('Open answers yes', (tester) async {
      final answer = await _open(tester);
      await tester.tap(find.byKey(const ValueKey('linkConfirmOpen')));
      await tester.pumpAndSettle();
      expect(await answer.future, isTrue);
    });

    testWidgets('Tab reaches Open from Cancel; activating it answers yes', (
      tester,
    ) async {
      final answer = await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_focusedAction(), const ValueKey('linkConfirmOpen'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(await answer.future, isTrue);
    });

    testWidgets('opens, answers and closes without an orphan semantics node', (
      tester,
    ) async {
      SemanticsOrphanGuard.instance.reset();
      final handle = tester.ensureSemantics();
      final answer = await _open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await answer.future, isFalse);
      handle.dispose();
      SemanticsOrphanGuard.instance.check(context: 'link confirmation');
      expect(SemanticsOrphanGuard.instance.updates, greaterThan(1));
    });

    testWidgets('lays out in every locale at the minimum window size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final locale in L10N.supportedLocales) {
        await _open(tester, locale: locale);
        expect(tester.takeException(), isNull, reason: '$locale');
        expect(find.text(_path), findsOneWidget, reason: '$locale');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
    });
  });

  group('outcome messages', () {
    final l10n = lookupL10N(const Locale('en'));

    test('a refusal is an error that says why', () {
      final malformed = waveCruxLinkOutcomeMessage(
        l10n,
        const WaveCruxLinkOutcome.failed(
          WaveCruxLinkFailure.malformed,
          parseRefusal: WaveCruxLinkRefusal.unknownKey,
        ),
      )!;
      expect(malformed.error, isTrue);
      expect(malformed.message, l10n.linkRefusedMalformed);

      final missing = waveCruxLinkOutcomeMessage(
        l10n,
        const WaveCruxLinkOutcome.failed(
          WaveCruxLinkFailure.fileNotFound,
          fileName: 'gone.vcd',
        ),
      )!;
      expect(missing.error, isTrue);
      expect(missing.message, contains('gone.vcd'));

      for (final failure in WaveCruxLinkFailure.values) {
        expect(
          waveCruxLinkOutcomeMessage(
            l10n,
            WaveCruxLinkOutcome.failed(failure, fileName: 'x.vcd'),
          )?.error,
          isTrue,
          reason: '$failure',
        );
      }
    });

    test('a clean open and a cancel say nothing', () {
      expect(
        waveCruxLinkOutcomeMessage(
          l10n,
          const WaveCruxLinkOutcome.opened(path: _path, openedTab: true),
        ),
        isNull,
      );
      expect(
        waveCruxLinkOutcomeMessage(
          l10n,
          const WaveCruxLinkOutcome.declined(path: _path),
        ),
        isNull,
      );
    });

    test('what an open could not do is said in one message', () {
      final shown = waveCruxLinkOutcomeMessage(
        l10n,
        const WaveCruxLinkOutcome.opened(
          path: _path,
          openedTab: false,
          signal: 'top.nope',
          signalNotFound: true,
          timeClamped: true,
        ),
      )!;
      expect(shown.error, isFalse);
      expect(shown.message, contains('top.nope'));
      expect(shown.message, contains(l10n.linkTimeClamped('uart_tx.vcd')));
    });

    test('a long signal name is shortened before it is shown', () {
      final shown = waveCruxLinkOutcomeMessage(
        l10n,
        WaveCruxLinkOutcome.opened(
          path: _path,
          openedTab: true,
          signal: 's' * 1000,
          signalNotFound: true,
        ),
      )!;
      expect(shown.message.length, lessThan(300));
    });
  });
}
