// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/viewer/providers/signal_load_progress_provider.dart';
import 'package:wavecrux/features/viewer/widgets/signal_load_indicator.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

Widget _host(
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: const Scaffold(body: Center(child: SignalLoadIndicator())),
    ),
  );
}

void main() {
  testWidgets('renders nothing while idle', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_host(container));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const Key('signalLoadCancelButton')), findsNothing);
  });

  testWidgets('shows a determinate bar, count, and cancel while active', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(signalLoadProgressProvider.notifier)
      ..begin(40)
      ..advance(10);

    await tester.pumpWidget(_host(container));
    await tester.pump();

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(10 / 40, 1e-9));
    expect(find.text('10/40'), findsOneWidget);
    expect(find.byKey(const Key('signalLoadCancelButton')), findsOneWidget);
  });

  testWidgets('a batch with no size yet shows a moving bar and no count', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(signalLoadProgressProvider.notifier)
        .beginIndeterminate(phase: SignalLoadPhase.adding);

    await tester.pumpWidget(_host(container));
    await tester.pump();

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(
      bar.value,
      isNull,
      reason: 'indeterminate while the scope is walked',
    );
    expect(find.text('0/0'), findsNothing);
    expect(find.byKey(const Key('signalLoadCancelButton')), findsOneWidget);
  });

  testWidgets('cancel button requests cancellation', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(signalLoadProgressProvider.notifier).begin(40);

    await tester.pumpWidget(_host(container));
    await tester.pump();

    await tester.tap(find.byKey(const Key('signalLoadCancelButton')));
    await tester.pump();

    expect(
      container.read(signalLoadProgressProvider).cancelRequested,
      isTrue,
    );
  });

  for (final code in ['en', 'zh_CN', 'ja', 'ko']) {
    testWidgets('renders without exception in $code', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(signalLoadProgressProvider.notifier)
        ..begin(7)
        ..advance(3);
      final locale = code.contains('_')
          ? Locale(code.split('_')[0], code.split('_')[1])
          : Locale(code);
      await tester.pumpWidget(_host(container, locale: locale));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('3/7'), findsOneWidget);
    });
  }
}
