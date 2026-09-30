// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/workspace/widgets/file_drop_overlay.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

Widget _host({Locale locale = const Locale('en'), VoidCallback? onTapBelow}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: TextButton(
                onPressed: onTapBelow,
                child: const Text('below'),
              ),
            ),
            const FileDropOverlay(),
          ],
        ),
      ),
    );

void main() {
  testWidgets('says what a drop will do', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.text('Drop to open'), findsOneWidget);
    expect(
      find.text(
        'Each file opens in its own tab. A GTKWave .gtkw session is '
        'imported into the current tab.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('never takes a pointer from what is under it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(onTapBelow: () => taps++));
    await tester.tap(find.text('below'), warnIfMissed: false);
    expect(taps, 1);
  });

  testWidgets('fits a minimum-size desktop window', (tester) async {
    // 800 x 500 is the OS-enforced minimum desktop window.
    await tester.binding.setSurfaceSize(const Size(800, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host());
    expect(tester.takeException(), isNull);
  });

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders in $locale without overflow', (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 500));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_host(locale: locale));
        await tester.pump();
        expect(find.byKey(const Key('fileDropOverlay')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
