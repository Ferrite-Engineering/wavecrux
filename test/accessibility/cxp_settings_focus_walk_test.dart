// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// What a keyboard and screen reader user meets in Settings > CXP Cross-Probe.
//
// The section is the suite-shared `CruxCxpSettingsSection`, the same in every
// product, so its controls (the enable switch, the port field, the two
// preference switches, the status line) are walked here the way they sit in
// WaveCrux's Settings screen. The transcript under `goldens/` is what the focus
// walk records, as text and so independent of the renderer; a change in what is
// announced shows up as a diff there. Rewrite it with
// `flutter test --update-goldens test/accessibility/cxp_settings_focus_walk_test.dart`
// and read the diff before committing it.

import 'package:crux_a11y/crux_a11y_testing.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/settings/screens/settings_screen.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/remote/cxp/wavecrux_cxp_binding.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

class _MockSettingsService extends Mock implements WaveCruxSettingsService {}

void main() {
  const goldens = 'test/accessibility/goldens';

  setUpAll(() => registerFallbackValue(const AppSettings()));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the CXP section is walked as named controls', (tester) async {
    final handle = tester.ensureSemantics();
    final service = _MockSettingsService();
    when(service.load).thenAnswer((_) async => const AppSettings());
    when(() => service.save(any())).thenAnswer((_) async {});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cruxCxpProductBindingProvider.overrideWithValue(kWaveCruxCxpBinding),
          // The server is on, so every control is live and a Tab stop, but
          // nothing starts: this test has no transport.
          cruxCxpTransportAvailableProvider.overrideWithValue(false),
          cruxCxpLaunchSettingsProvider.overrideWithValue(
            const CruxCxpSettings(enabled: true, port: 54322),
          ),
          settingsServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.text('CXP Cross-Probe').first;
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('CXP port'), findsOneWidget);

    final walk = await walkFocus(tester);
    expectCleanFocusWalk(walk, context: 'Settings > CXP Cross-Probe');
    expect(
      walk.stops.map((s) => s.line).join('\n'),
      allOf(contains('Enable CXP server'), contains('CXP port')),
      reason: 'the shared controls are Tab stops with their names',
    );
    expectFocusWalkGolden(walk, '$goldens/settings_cxp.txt');
    handle.dispose();
  });
}
