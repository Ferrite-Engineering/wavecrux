// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/device_class.dart';
import 'package:wavecrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:wavecrux/features/viewer/widgets/bottom_dock.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/bottom_dock_tab.dart';
import 'package:wavecrux/plugins/extra_bottom_dock_tabs_provider.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';

/// A contributed tab's visibility flag, writable so the test can stand in for
/// an overlay's own notifier.
class _Visible extends Notifier<bool> {
  @override
  bool build() => true;

  void hide() => state = false;
}

final _visibleA = NotifierProvider<_Visible, bool>(_Visible.new);
final _visibleB = NotifierProvider<_Visible, bool>(_Visible.new);

/// State the contributed panel owns, standing in for loaded SVA results or an
/// AI Advisor conversation. The `×` must leave it alone.
class _PanelState extends Notifier<String> {
  @override
  String build() => 'loaded';

  String get value => state;

  set value(String value) => state = value;
}

final _panelState = NotifierProvider<_PanelState, String>(_PanelState.new);

BottomDockTab _tab(
  String id,
  NotifierProvider<_Visible, bool> visibility, {
  LicenseTier tier = LicenseTier.openCore,
}) => BottomDockTab(
  id: id,
  labelResolver: (_) => 'Tab $id',
  icon: Icons.extension_outlined,
  builder: (_) => Text('panel $id'),
  visibilityProvider: visibility,
  onDismiss: (ref) => ref.read(visibility.notifier).hide(),
  requiredTier: tier,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  List<BottomDockTab> tabs, {
  bool sheet = false,
  Locale? locale,
}) async {
  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceClassProvider.overrideWithValue(DeviceClass.desktop),
        extraBottomDockTabsProvider.overrideWithValue(tabs),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return sheet
                  ? const WaveCruxBottomDockSheet()
                  : const WaveCruxBottomDock();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('contributed bottom-dock tabs', () {
    testWidgets('every contributed tab renders a ×', (tester) async {
      await _pump(tester, [_tab('a', _visibleA), _tab('b', _visibleB)]);

      for (final id in ['a', 'b']) {
        expect(find.byKey(ValueKey('cruxDockTab-$id')), findsOneWidget);
        expect(
          find.byKey(ValueKey('cruxDockClose-$id')),
          findsOneWidget,
          reason: 'contributed tab "$id" must be closable like FSM/X-Trace',
        );
      }
    });

    testWidgets('the × calls onDismiss, which hides the tab', (tester) async {
      final container = await _pump(tester, [
        _tab('a', _visibleA),
        _tab('b', _visibleB),
      ]);

      await tester.tap(find.byKey(const ValueKey('cruxDockClose-a')));
      await tester.pumpAndSettle();

      expect(container.read(_visibleA), isFalse);
      expect(find.byKey(const ValueKey('cruxDockTab-a')), findsNothing);
      // Only the tab whose × was pressed goes away.
      expect(container.read(_visibleB), isTrue);
      expect(find.byKey(const ValueKey('cruxDockTab-b')), findsOneWidget);
    });

    testWidgets('the × hides without touching the panel state', (
      tester,
    ) async {
      final container = await _pump(tester, [_tab('a', _visibleA)]);
      container.read(_panelState.notifier).value = 'three assertions';

      await tester.tap(find.byKey(const ValueKey('cruxDockClose-a')));
      await tester.pumpAndSettle();

      expect(container.read(_visibleA), isFalse);
      expect(container.read(_panelState), 'three assertions');
    });

    testWidgets('the phone sheet renders the same × for contributed tabs', (
      tester,
    ) async {
      await _pump(tester, [_tab('a', _visibleA)], sheet: true);
      expect(find.byKey(const ValueKey('cruxDockClose-a')), findsOneWidget);
    });

    testWidgets('a contributed tab appearing later auto-reveals', (
      tester,
    ) async {
      final container = await _pump(tester, [_tab('a', _visibleA)]);
      await tester.tap(find.byKey(const ValueKey('cruxDockClose-a')));
      await tester.pumpAndSettle();
      container
          .read(panelLayoutProvider.notifier)
          .setBottomDockTab(kBottomDockTabTransactions);
      await tester.pumpAndSettle();

      // Re-show it from elsewhere (the overlay's toggler): now that the tab
      // is closable, the dock's own auto-reveal selects it.
      container.invalidate(_visibleA);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('cruxDockTab-a')), findsOneWidget);
      expect(container.read(panelLayoutProvider).effectiveBottomDockTab, 'a');
    });

    for (final locale in L10N.supportedLocales) {
      testWidgets('renders the contributed × in $locale without exceptions', (
        tester,
      ) async {
        await _pump(tester, [_tab('a', _visibleA)], locale: locale);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('cruxDockClose-a')), findsOneWidget);
      });
    }
  });
}
