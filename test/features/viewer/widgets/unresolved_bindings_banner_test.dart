// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/viewer/providers/unresolved_bindings_provider.dart';
import 'package:wavecrux/features/viewer/widgets/unresolved_bindings_banner.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/session/binding_paths.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

const _two = [
  UnresolvedBinding(owner: 'spi #1', slot: 'clk', path: 'top.spi.clk'),
  UnresolvedBinding(owner: 'rvfi', slot: 'valid', path: 'top.cpu.rvfi_valid'),
];

ProviderContainer _container({
  DeviceClass deviceClass = DeviceClass.desktop,
}) {
  final c = ProviderContainer(
    overrides: [deviceClassProvider.overrideWith((ref) => deviceClass)],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  Locale locale = const Locale('en'),
}) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: const Scaffold(body: UnresolvedBindingsBanner()),
    ),
  ),
);

void main() {
  testWidgets('renders nothing when every binding resolved', (tester) async {
    await _pump(tester, _container());
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('names the missing paths and their count', (tester) async {
    final c = _container();
    c.read(unresolvedBindingsProvider.notifier).report(_two);
    await _pump(tester, c);

    expect(find.byType(MaterialBanner), findsOneWidget);
    expect(
      find.text(
        '2 saved decoder or Stage bindings were not found in this waveform: '
        'top.spi.clk, top.cpu.rvfi_valid',
      ),
      findsOneWidget,
    );
  });

  testWidgets('one missing binding reads in the singular', (tester) async {
    final c = _container();
    c.read(unresolvedBindingsProvider.notifier).report(_two.take(1).toList());
    await _pump(tester, c);

    expect(
      find.text(
        '1 saved decoder or Stage binding was not found in this waveform: '
        'top.spi.clk',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Dismiss clears the notice', (tester) async {
    final c = _container();
    c.read(unresolvedBindingsProvider.notifier).report(_two);
    await _pump(tester, c);

    await tester.tap(
      find.byKey(const Key('unresolvedBindingsBannerDismissButton')),
    );
    await tester.pumpAndSettle();

    expect(c.read(unresolvedBindingsProvider), isEmpty);
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('Dismiss meets the 44 dp touch target on a phone', (
    tester,
  ) async {
    final c = _container(deviceClass: DeviceClass.phone);
    c.read(unresolvedBindingsProvider.notifier).report(_two);
    await _pump(tester, c);

    final size = tester.getSize(
      find.byKey(const Key('unresolvedBindingsBannerDismissButton')),
    );
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('a long list is cut short and counted', (tester) async {
    late L10N l10n;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = L10N.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    final many = [
      for (var i = 0; i < 8; i++)
        UnresolvedBinding(owner: 'o', slot: 's$i', path: 'top.p$i'),
      // A path two bindings share is listed once.
      const UnresolvedBinding(owner: 'o2', slot: 's', path: 'top.p0'),
    ];
    expect(
      UnresolvedBindingsBanner.listedPaths(l10n, many),
      'top.p0, top.p1, top.p2, top.p3, top.p4, and 3 more',
    );
  });

  testWidgets('focus walk: Dismiss is a named stop', (tester) async {
    final semantics = tester.ensureSemantics();
    final c = _container();
    c.read(unresolvedBindingsProvider.notifier).report(_two);
    await _pump(tester, c);

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'unresolved bindings banner');
    expect(walk.transcript, contains('Dismiss'));
    semantics.dispose();
  });

  group('locale sweep', () {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      for (final deviceClass in const [
        DeviceClass.desktop,
        DeviceClass.phone,
      ]) {
        testWidgets('renders in $locale on ${deviceClass.name}', (
          tester,
        ) async {
          final c = _container(deviceClass: deviceClass);
          c.read(unresolvedBindingsProvider.notifier).report([
            ..._two,
            for (var i = 0; i < 6; i++)
              UnresolvedBinding(
                owner: 'o',
                slot: 's$i',
                path: 'top.a_rather_long_hierarchy.instance_$i.signal',
              ),
          ]);
          await _pump(tester, c, locale: locale);
          expect(find.byType(MaterialBanner), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
