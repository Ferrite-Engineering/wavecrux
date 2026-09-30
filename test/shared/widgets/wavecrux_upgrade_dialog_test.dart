// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The upgrade funnel counts denials the user saw, not key repeats.
//
// A gated action is usually shortcut-reachable, and the app's shortcut layer
// sits above the Navigator, so a held chord re-dispatches the denial while the
// upgrade dialog is already up. The shared opener's guard keeps those repeats
// from stacking dialogs; these tests hold `WaveCruxUpgradeDialog.show` to
// counting the same way: one dialog, one `tier.gate_hit`, one `badge.click`.

import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/wavecrux_upgrade_dialog.dart';

class _RecordingTelemetry implements TelemetryService {
  final events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);

  List<TelemetryEvent> named(String name) =>
      events.where((e) => e.name == name).toList();
}

class _GatedIntent extends Intent {
  const _GatedIntent();
}

const _chord = SingleActivator(LogicalKeyboardKey.keyK, control: true);

/// An app whose Ctrl+K is a gated action denied at [LicenseTier.pro], bound
/// the way the app binds its shortcuts: above the Navigator, so it still
/// fires while the dialog it opened has focus.
Future<void> _pumpGatedApp(
  WidgetTester tester,
  TelemetryService telemetry, {
  String? gateFeatureId = 'decoder_pack',
}) async {
  late BuildContext home;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        shortcuts: const <ShortcutActivator, Intent>{_chord: _GatedIntent()},
        actions: <Type, Action<Intent>>{
          _GatedIntent: CallbackAction<_GatedIntent>(
            onInvoke: (_) => WaveCruxUpgradeDialog.show(
              home,
              featureLabel: 'Zephyr Probe',
              requiredTier: LicenseTier.pro,
              gateFeatureId: gateFeatureId,
            ),
          ),
        },
        home: Scaffold(
          body: Focus(
            autofocus: true,
            child: Builder(
              builder: (context) {
                home = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Presses Ctrl+K and holds it through [repeats] auto-repeats.
Future<void> _holdChord(WidgetTester tester, {int repeats = 5}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
  await tester.pump();
  for (var i = 0; i < repeats; i++) {
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyK);
    await tester.pump();
  }
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  // MUTATION: deleting the `ModalGuard.isOpen` check in
  // `WaveCruxUpgradeDialog.show` counts every repeat while the dialog still
  // opens once, and this goes red.
  testWidgets('a held gated shortcut opens one dialog and counts one denial', (
    tester,
  ) async {
    final telemetry = _RecordingTelemetry();
    await _pumpGatedApp(tester, telemetry);

    await _holdChord(tester);

    expect(find.byType(CruxUpgradeDialog), findsOneWidget);
    expect(telemetry.named('tier.gate_hit'), hasLength(1));
    expect(telemetry.named('tier.gate_hit').single.properties, {
      'feature': 'decoder_pack',
      'required': 'pro',
    });
    expect(telemetry.named('badge.click'), hasLength(1));
    expect(telemetry.named('badge.click').single.properties, {'tier': 'pro'});
    expect(
      telemetry.events.map((e) => e.name),
      <String>['tier.gate_hit', 'badge.click'],
      reason: 'the gate hit is counted first, then the badge click',
    );
  });

  testWidgets('once the dialog is dismissed, the next denial counts again', (
    tester,
  ) async {
    final telemetry = _RecordingTelemetry();
    await _pumpGatedApp(tester, telemetry);

    await _holdChord(tester);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(CruxUpgradeDialog), findsNothing);

    await _holdChord(tester, repeats: 0);

    expect(find.byType(CruxUpgradeDialog), findsOneWidget);
    expect(telemetry.named('tier.gate_hit'), hasLength(2));
    expect(telemetry.named('badge.click'), hasLength(2));
  });

  testWidgets('a denial with no gate id counts only the badge click', (
    tester,
  ) async {
    final telemetry = _RecordingTelemetry();
    await _pumpGatedApp(tester, telemetry, gateFeatureId: null);

    await _holdChord(tester, repeats: 2);

    expect(find.byType(CruxUpgradeDialog), findsOneWidget);
    expect(telemetry.named('tier.gate_hit'), isEmpty);
    expect(telemetry.named('badge.click'), hasLength(1));
  });
}
