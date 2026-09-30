// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/beta_expiry/widgets/beta_expiry_blocking_overlay.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Widget _wrap({
  Locale locale = const Locale('en'),
  DeviceClass deviceClass = DeviceClass.desktop,
  VoidCallback? onDownload,
  VoidCallback? onQuit,
}) {
  return MaterialApp(
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ],
    locale: locale,
    home: Scaffold(
      body: BetaExpiryBlockingOverlay(
        deviceClass: deviceClass,
        onDownload: onDownload ?? () {},
        onQuit: onQuit ?? () {},
        child: const Text('viewer-content'),
      ),
    ),
  );
}

void main() {
  group('BetaExpiryBlockingOverlay locale sweep', () {
    for (final locale in _locales) {
      testWidgets('renders without exceptions in $locale', (tester) async {
        await tester.pumpWidget(_wrap(locale: locale));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('renders the underlying content behind a blocking barrier', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    // The viewer content is still in the tree (dimmed) behind the modal.
    expect(find.text('viewer-content'), findsOneWidget);
    // A non-dismissable modal barrier (our dimming scrim) blocks all
    // interaction with the content behind it.
    expect(
      find.byWidgetPredicate(
        (w) => w is ModalBarrier && !w.dismissible && w.color == Colors.black54,
      ),
      findsOneWidget,
    );
  });

  testWidgets('download action fires onDownload', (tester) async {
    var downloads = 0;
    await tester.pumpWidget(_wrap(onDownload: () => downloads++));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    expect(downloads, 1);
  });

  testWidgets('quit action fires onQuit', (tester) async {
    // Load-bearing on Windows/Linux: the custom window chrome's close button
    // sits behind the modal barrier, so this button is the only visible way
    // to exit the app once the build has expired.
    var quits = 0;
    await tester.pumpWidget(_wrap(onQuit: () => quits++));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextButton));
    expect(quits, 1);
  });

  testWidgets('blocks the system back gesture (canPop is false)', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((w) => w is PopScope && !w.canPop),
      findsOneWidget,
    );
  });
}
