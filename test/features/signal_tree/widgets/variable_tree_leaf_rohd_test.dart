// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/domain/enums/var_direction.dart';
import 'package:wavecrux/domain/enums/var_type.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/domain/models/variable.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/signal_tree/providers/rohd_wave_map_provider.dart';
import 'package:wavecrux/features/signal_tree/widgets/variable_tree_leaf.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/remote/cxp/cxp_inbound_handlers.dart';
import 'package:wavecrux/services/rohd/rohd_sidecar.dart';
import 'package:wavecrux/services/rohd/rohd_wave_map.dart';

import '../../../support/rohd_fixture_package.dart';

class _Settings extends AppSettingsNotifier {
  _Settings(this._settings);
  final AppSettings _settings;
  @override
  Future<AppSettings> build() async => _settings;
}

RohdWaveMap _map() => RohdWaveMap.fromSidecar(
  parseRohdSidecar(
    File('$kRohdFixtureDir/Top.flc.json').readAsStringSync(),
  ).sidecar!,
  resolveFile: (raw) => '/p/${raw.replaceFirst('.dart_tool/../', '')}',
);

Variable _var(String scope, String name) => Variable(
  name: name,
  varType: VarType.wire,
  direction: VarDirection.unknown,
  signalRef: 'ref_${scope}_$name',
  scopePath: scope,
  bitWidth: 1,
);

Future<List<(String, String)>> _pump(
  WidgetTester tester,
  Variable variable, {
  RohdWaveMap? map,
  String editor = 'code -g',
  Locale locale = const Locale('en'),
  bool runnerFails = false,
}) async {
  final calls = <(String, String)>[];
  final overrides = <Override>[
    rohdWaveMapProvider.overrideWith((ref) async => map),
    appSettingsProvider.overrideWith(
      () => _Settings(AppSettings(cxpEditorCommand: editor)),
    ),
    cxpEditorCommandRunnerProvider.overrideWithValue((command, target) async {
      calls.add((command, target));
      return runnerFails
          ? const CruxCxpHandlerResult(honored: false, reason: 'no such editor')
          : CruxCxpHandlerResult.ok;
    }),
  ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: VariableTreeLeaf(variable: variable)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(VariableTreeLeaf), buttons: kSecondaryButton);
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('a signal ROHD traced offers Go to Dart Source', (tester) async {
    await _pump(tester, _var('top', 'gated'), map: _map());
    final l10n = L10N.of(tester.element(find.byType(Scaffold)));
    expect(find.text(l10n.signalTreeGoToDartSource), findsOneWidget);
    // The existing items are still there.
    expect(find.text(l10n.signalTreeCopyPath), findsOneWidget);
  });

  testWidgets('choosing it opens the editor at the Dart line', (tester) async {
    final calls = await _pump(tester, _var('top', 'gated'), map: _map());
    final l10n = L10N.of(tester.element(find.byType(Scaffold)));
    await tester.tap(find.text(l10n.signalTreeGoToDartSource));
    await tester.pumpAndSettle();
    expect(calls, [('code -g', '/p/lib/design.dart:59:19')]);
  });

  testWidgets('a keyword-renamed instance resolves from the menu too', (
    tester,
  ) async {
    final calls = await _pump(tester, _var('top.reg_', 'q'), map: _map());
    final l10n = L10N.of(tester.element(find.byType(Scaffold)));
    await tester.tap(find.text(l10n.signalTreeGoToDartSource));
    await tester.pumpAndSettle();
    expect(calls.single.$2, '/p/lib/design.dart:36:15');
  });

  testWidgets('a signal the trace does not name offers nothing', (
    tester,
  ) async {
    await _pump(tester, _var('top', 'inner_pkt'), map: _map());
    final l10n = L10N.of(tester.element(find.byType(Scaffold)));
    expect(find.text(l10n.signalTreeGoToDartSource), findsNothing);
    expect(find.text(l10n.signalTreeCopyPath), findsOneWidget);
  });

  testWidgets('with no source-trace file the menu is unchanged', (
    tester,
  ) async {
    await _pump(tester, _var('top', 'gated'));
    final l10n = L10N.of(tester.element(find.byType(Scaffold)));
    expect(find.text(l10n.signalTreeGoToDartSource), findsNothing);
    expect(find.text(l10n.signalTreeAddToViewer), findsOneWidget);
  });

  testWidgets('with no editor set, it says where to set one', (tester) async {
    final calls = await _pump(
      tester,
      _var('top', 'gated'),
      map: _map(),
      editor: '',
    );
    final l10n = L10N.of(tester.element(find.byType(Scaffold)));
    await tester.tap(find.text(l10n.signalTreeGoToDartSource));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.text(l10n.signalTreeGoToDartNoEditor), findsOneWidget);
  });

  testWidgets('an editor that cannot start is reported with its reason', (
    tester,
  ) async {
    await _pump(tester, _var('top', 'gated'), map: _map(), runnerFails: true);
    final l10n = L10N.of(tester.element(find.byType(Scaffold)));
    await tester.tap(find.text(l10n.signalTreeGoToDartSource));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.signalTreeGoToDartFailed('no such editor')),
      findsOneWidget,
    );
  });

  for (final code in ['en', 'zh_CN', 'ja', 'ko']) {
    testWidgets('$code menu renders without exceptions', (tester) async {
      await _pump(
        tester,
        _var('top', 'gated'),
        map: _map(),
        locale: Locale(code),
      );
      final l10n = L10N.of(tester.element(find.byType(Scaffold)));
      expect(find.text(l10n.signalTreeGoToDartSource), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
