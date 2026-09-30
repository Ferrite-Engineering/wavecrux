// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_workspace/crux_workspace.dart' as crux;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/tabs/wavecrux_viewer_tab_bar_strings.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

Future<crux.ViewerTabBarStrings> _resolveEn(WidgetTester tester) async {
  late crux.ViewerTabBarStrings strings;
  await tester.pumpWidget(
    Localizations(
      locale: const Locale('en'),
      delegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: Builder(
        builder: (context) {
          strings = WaveCruxViewerTabBarStrings(L10N.of(context));
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return strings;
}

Future<crux.ViewerTabBarStrings> _resolveLocale(
  WidgetTester tester,
  Locale locale,
) async {
  late crux.ViewerTabBarStrings strings;
  await tester.pumpWidget(
    Localizations(
      locale: locale,
      delegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: Builder(
        builder: (context) {
          strings = WaveCruxViewerTabBarStrings(L10N.of(context));
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return strings;
}

void main() {
  testWidgets('English getters return expected non-empty strings', (
    tester,
  ) async {
    final strings = await _resolveEn(tester);
    expect(strings.closeTabTooltip, equals('Close tab'));
    expect(strings.newTabTooltip, equals('New Tab'));
    expect(strings.newTabDefaultDisplayName, equals('New Tab'));
    expect(strings.unnamedTabFallback, equals('(unnamed tab)'));
    expect(strings.closeTabMenuItem, equals('Close Tab'));
    expect(strings.closeOtherTabsMenuItem, equals('Close Other Tabs'));
    expect(
      strings.closeTabsToTheRightMenuItem,
      equals('Close Tabs to the Right'),
    );
    expect(strings.moveToNewWindowMenuItem, equals('Move to New Window'));
    expect(
      strings.multiWindowUnavailableTooltip,
      equals('Available when Flutter multi-window reaches stable'),
    );
    expect(strings.activePaneAccessibilityLabel, equals('Active pane'));
    expect(
      strings.dragToPaneAccessibilityHint,
      equals('Drop here to move the tab into this pane'),
    );
    expect(strings.reorderHandleTooltip, equals('Drag to reorder'));
    // Parameterized close tooltip carries the tab name (vs the param-less
    // closeTabTooltip default).
    expect(strings.closeTabTooltipFor('cpu.vcd'), equals('Close cpu.vcd'));
  });

  testWidgets('Simplified Chinese (zh_CN) getters resolve to localized text', (
    tester,
  ) async {
    final strings = await _resolveLocale(
      tester,
      const Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
    );
    expect(strings.closeTabTooltip, equals('关闭标签页'));
    expect(strings.newTabDefaultDisplayName, equals('新标签页'));
    expect(strings.reorderHandleTooltip, equals('拖动以重新排序'));
    expect(strings.activePaneAccessibilityLabel, equals('活动窗格'));
  });

  testWidgets('Japanese (ja) getters resolve to localized text', (
    tester,
  ) async {
    final strings = await _resolveLocale(tester, const Locale('ja'));
    expect(strings.closeTabTooltip, equals('タブを閉じる'));
    expect(strings.reorderHandleTooltip, equals('ドラッグして並べ替え'));
    expect(strings.activePaneAccessibilityLabel, equals('アクティブなペイン'));
  });

  testWidgets('Korean (ko) getters resolve to localized text', (tester) async {
    final strings = await _resolveLocale(tester, const Locale('ko'));
    expect(strings.closeTabTooltip, equals('탭 닫기'));
    expect(strings.reorderHandleTooltip, equals('끌어서 순서 변경'));
    expect(strings.activePaneAccessibilityLabel, equals('활성 창'));
  });

  testWidgets(
    'is a crux.ViewerTabBarStrings (assignable to the package type)',
    (tester) async {
      final strings = await _resolveEn(tester);
      expect(strings, isA<crux.ViewerTabBarStrings>());
    },
  );
}
