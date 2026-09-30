// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:crux_settings_ui/crux_settings_ui.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_config.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_storage.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_strings.dart';
import 'package:wavecrux/domain/enums/display_format.dart';
import 'package:wavecrux/domain/models/app_settings.dart';
import 'package:wavecrux/features/settings/providers/settings_providers.dart';
import 'package:wavecrux/features/settings/screens/settings_screen.dart';
import 'package:wavecrux/features/settings/widgets/color_theme_section.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/services/settings/settings_service.dart';

// ── Mock ─────────────────────────────────────────────────────────────────────

class _MockSettingsService extends Mock implements WaveCruxSettingsService {}

// ── Helpers ──────────────────────────────────────────────────────────────────

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('ja'),
  Locale('ko'),
];

Widget _wrap({WaveCruxSettingsService? service, Locale? locale}) {
  final mock = service ?? _defaultMock();
  return ProviderScope(
    overrides: [
      settingsServiceProvider.overrideWithValue(mock),
    ],
    child: MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      locale: locale,
      home: const SettingsScreen(),
    ),
  );
}

/// Minimal app with a button that calls [SettingsScreen.openAdaptive].
Widget _wrapWithTrigger({WaveCruxSettingsService? service}) {
  final mock = service ?? _defaultMock();
  return ProviderScope(
    overrides: [
      settingsServiceProvider.overrideWithValue(mock),
    ],
    child: MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: const [Locale('en')],
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => SettingsScreen.openAdaptive(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

_MockSettingsService _defaultMock() {
  final mock = _MockSettingsService();
  when(mock.load).thenAnswer((_) async => const AppSettings());
  when(() => mock.save(any())).thenAnswer((_) async {});
  return mock;
}

/// Taps the category rail row carrying [title] (the rail row is the first
/// occurrence of the text — the detail title, if any, comes later in the tree).
///
/// Scrolls the row into view first: the rail is longer than the test surface
/// once the Privacy category is offered, which it is whenever telemetry
/// follows consent.
Future<void> _selectCategory(WidgetTester tester, String title) async {
  final row = find.text(title).first;
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(const AppSettings());
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ── SettingsScreen (full-screen route, wide → dual-pane) ─────────────────────

  group('SettingsScreen dual-pane', () {
    for (final locale in _locales) {
      testWidgets('locale sweep — renders in $locale without exceptions', (
        tester,
      ) async {
        await tester.pumpWidget(_wrap(locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shows AppBar with Settings title', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets(
      'renders a category rail beside a detail pane (VerticalDivider)',
      (tester) async {
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        // The side-by-side layout separates rail and detail with a
        // VerticalDivider; the single-column (narrow) layout does not.
        expect(find.byType(VerticalDivider), findsOneWidget);
      },
    );

    testWidgets('rail lists the platform-independent categories', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      for (final label in [
        // Suite-canonical order: General leads.
        'General',
        'Appearance',
        'Waveform Defaults',
        'File Handling',
        // Dedicated Editors section, as in every Crux app.
        'Editors',
        'Remote Control',
        'CXP Cross-Probe',
        // Decoder plugins / custom translators / custom Stage widgets merged
        // into one Extensions category, as in every Crux app.
        'Extensions',
        'Keyboard Shortcuts',
      ]) {
        expect(find.text(label), findsWidgets, reason: 'missing rail: $label');
      }
    });

    testWidgets('no About category', (tester) async {
      // The About box is reached from the viewer menu, not Settings.
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.text('About'), findsNothing);
    });

    testWidgets(
      'defaults to the General detail (suite-canonical order), with '
      'Appearance one click away hosting the language selector',
      (
        tester,
      ) async {
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        // General is the first category and is selected by default: the
        // update toggle, the restore-tabs toggle, and the log-verbosity
        // dropdown (absorbed from the retired Diagnostics category).
        expect(
          find.byKey(const Key('settingsAutoCheckUpdatesSwitch')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('settingsRestoreTabsSwitch')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('settingsLogVerbosityDropdown')),
          findsOneWidget,
        );

        // Appearance hosts the shared Language selector.
        await _selectCategory(tester, 'Appearance');
        expect(find.text('Language'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('cruxLocaleDropdown')),
          findsOneWidget,
        );
      },
    );

    testWidgets('selecting Waveform Defaults reveals the format dropdown', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButton<DisplayFormat>), findsNothing);
      await _selectCategory(tester, 'Waveform Defaults');
      expect(find.byType(DropdownButton<DisplayFormat>), findsOneWidget);
    });

    testWidgets('Waveform Defaults hosts the natural-sort toggle, ON by '
        'default, and toggling persists the setting', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _selectCategory(tester, 'Waveform Defaults');

      final toggle = find.byKey(
        const Key('settings_signal_tree_natural_sort'),
      );
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
      expect(
        container.read(appSettingsProvider).value?.signalTreeNaturalSort,
        isFalse,
      );
    });

    testWidgets('selecting File Handling reveals the auto-reload segments', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _selectCategory(tester, 'File Handling');
      final segmented = find.byType(
        SegmentedButton<AutoReloadMode>,
        skipOffstage: false,
      );
      expect(segmented, findsOneWidget);
      expect(
        find.descendant(of: segmented, matching: find.text('Prompt')),
        findsOneWidget,
      );
      // The "Auto-Convert Large VCD to FST" switch persisted a value nothing
      // read; a control with no effect is not offered.
      expect(
        find.text('Auto-Convert Large VCD to FST', skipOffstage: false),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('selecting Keyboard Shortcuts reveals the editable list', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _selectCategory(tester, 'Keyboard Shortcuts');
      // The editable section exposes import/export/reset-all controls.
      expect(find.text('Import…'), findsOneWidget);
      expect(find.text('Export…'), findsOneWidget);
      expect(find.text('Reset all'), findsOneWidget);
    });

    testWidgets('selecting Remote Control (enabled) shows port + status rows', (
      tester,
    ) async {
      final mock = _MockSettingsService();
      when(mock.load).thenAnswer(
        (_) async => const AppSettings(
          remoteControlEnabled: true,
          remoteControlPort: 12345,
        ),
      );
      when(() => mock.save(any())).thenAnswer((_) async {});

      await tester.pumpWidget(_wrap(service: mock));
      await tester.pumpAndSettle();
      await _selectCategory(tester, 'Remote Control');

      expect(find.text('Port'), findsOneWidget);
      final portField = tester.widget<TextField>(
        find
            .descendant(
              of: find.byWidgetPredicate(
                (w) => w is SizedBox && w.width == 100,
              ),
              matching: find.byType(TextField),
            )
            .first,
      );
      expect(portField.controller?.text, '12345');
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Stopped'), findsWidgets);
    });

    testWidgets('selecting CXP Cross-Probe shows its rows (enabled default)', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _selectCategory(tester, 'CXP Cross-Probe');
      expect(find.text('CXP port'), findsOneWidget);
      expect(find.text('CXP Status'), findsOneWidget);
      // The editor-command field lives in the dedicated Editors section.
      expect(find.text('Editor Command'), findsNothing);
    });

    testWidgets('selecting Editors shows the editor-command field', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _selectCategory(tester, 'Editors');
      expect(find.text('Editor Command'), findsOneWidget);
    });

    testWidgets('groups detail content into bordered Cards', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsWidgets);
    });

    testWidgets(
      'General → auto-check toggle round-trips through the provider',
      (tester) async {
        final mock =
            _defaultMock(); // loads default (autoCheckForUpdates: true)
        await tester.pumpWidget(_wrap(service: mock));
        await tester.pumpAndSettle();
        await _selectCategory(tester, 'General');

        final switchFinder = find.byKey(
          const Key('settingsAutoCheckUpdatesSwitch'),
        );
        expect(switchFinder, findsOneWidget);
        expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);

        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        // The toggle flipped and persisted via the notifier.
        expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);
        verify(
          () => mock.save(
            any(
              that: predicate<AppSettings>((s) => !s.autoCheckForUpdates),
            ),
          ),
        ).called(1);
      },
    );

    testWidgets(
      'Appearance → legibility-boost toggle round-trips through the provider',
      (tester) async {
        final mock = _defaultMock(); // canvasLegibilityBoost defaults to false
        await tester.pumpWidget(_wrap(service: mock));
        await tester.pumpAndSettle();
        await _selectCategory(tester, 'Appearance');

        final switchFinder = find.byKey(
          const Key('settingsCanvasLegibilityBoostSwitch'),
        );
        expect(switchFinder, findsOneWidget);
        expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

        await tester.tap(switchFinder);
        await tester.pumpAndSettle();

        // The toggle flipped on and persisted via the notifier.
        expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
        verify(
          () => mock.save(
            any(
              that: predicate<AppSettings>((s) => s.canvasLegibilityBoost),
            ),
          ),
        ).called(1);
      },
    );

    testWidgets(
      'Appearance no longer shows the legacy light/dark/system selector',
      (tester) async {
        // The redundant theme-mode SegmentedButton was removed: brightness is
        // now driven by the color-theme preset picker (see ColorThemeSection),
        // not a separate AppThemeMode flag. None of its segment labels should
        // render in the Appearance detail.
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();
        await _selectCategory(tester, 'Appearance');
        expect(find.byType(SegmentedButton<AppThemeMode>), findsNothing);
        expect(find.text('System'), findsNothing);
        // The preset picker (which carries brightness) renders instead.
        expect(find.byType(ColorThemeSection), findsOneWidget);
      },
    );
  });

  // ── Narrow layout (list → detail with back) ──────────────────────────────────

  group('SettingsScreen narrow layout', () {
    testWidgets('shows the category list, then detail with a back button', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 800));
      addTearDown(() async => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // Narrow → single column: no side-by-side divider, and the detail
      // content (the Appearance Language selector) is not visible until a
      // category is opened.
      expect(find.byType(VerticalDivider), findsNothing);
      expect(find.text('Language'), findsNothing);
      // The category rail still lists the categories.
      expect(find.text('Appearance'), findsOneWidget);

      await _selectCategory(tester, 'Appearance');

      // Detail now shows its content plus an in-pane back affordance.
      expect(find.text('Language'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsWidgets);

      // Tapping the in-pane back (last back icon in the tree) returns to list.
      await tester.tap(find.byIcon(Icons.arrow_back).last);
      await tester.pumpAndSettle();
      expect(find.text('Language'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // ── openAdaptive — desktop: shows dialog ─────────────────────────────────────

  group('SettingsScreen.openAdaptive — desktop', () {
    testWidgets(
      'shows a Dialog widget',
      (tester) async {
        await tester.pumpWidget(_wrapWithTrigger());
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }),
    );

    testWidgets(
      'dialog contains Settings title',
      (tester) async {
        await tester.pumpWidget(_wrapWithTrigger());
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('Settings'), findsOneWidget);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }),
    );

    testWidgets(
      'dialog has a close button that dismisses it',
      (tester) async {
        await tester.pumpWidget(_wrapWithTrigger());
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }),
    );

    testWidgets(
      'barrier tap does NOT dismiss the dialog (barrierDismissible: false)',
      (tester) async {
        await tester.pumpWidget(_wrapWithTrigger());
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        // Tap the top-left corner — the scrim, well outside the dialog card.
        // A modal Settings dialog must close only via its X (or Esc), so a
        // stray barrier click must leave it open.
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }),
    );

    testWidgets(
      'dialog shows the Appearance category',
      (tester) async {
        await tester.pumpWidget(_wrapWithTrigger());
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        // Appears in the rail and (as the default selection) the detail title.
        expect(find.text('Appearance'), findsWidgets);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }),
    );

    // Issue 9: dialog fits a small viewport (iPad split / narrow desktop) and
    // collapses to the single-column layout without overflow.
    testWidgets(
      'dialog adapts to small viewports (Issue 9)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(500, 500));
        addTearDown(() async => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(_wrapWithTrigger());
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(Dialog), findsOneWidget);
        final dialogBox = tester.renderObject(find.byType(Dialog)).paintBounds;
        expect(dialogBox.width, lessThanOrEqualTo(500));
        expect(dialogBox.height, lessThanOrEqualTo(500));
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }),
    );
  });

  // ── openAdaptive — mobile: pushes full-screen route ──────────────────────────

  group('SettingsScreen.openAdaptive — mobile', () {
    testWidgets(
      'pushes the full-screen route shell (no dialog)',
      (tester) async {
        await tester.pumpWidget(_wrapWithTrigger());
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        // openAdaptive pushes the suite-shared CruxSettingsRouteShell
        // directly (crux_settings_ui); SettingsScreen remains only as the
        // widget for direct route mounts.
        expect(find.byType(CruxSettingsRouteShell), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );

    testWidgets(
      'pushed screen shows Settings title in AppBar',
      (tester) async {
        await tester.pumpWidget(_wrapWithTrigger());
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('Settings'), findsOneWidget);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  });

  // ── Privacy category (telemetry consent) ────────────────────────────────────

  group('Privacy category', () {
    Widget wrapGated({required bool beta, required bool dev}) => ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(_defaultMock()),
        // The Privacy section is `crux_telemetry`'s, so the package's config
        // and storage seams have to be bound the way `bootstrap` binds them.
        cruxTelemetryConfigProvider.overrideWithValue(wavecruxTelemetryConfig),
        telemetryStorageProvider.overrideWithValue(
          const WavecruxTelemetryStorage(),
        ),
        telemetryBetaPeriodProvider.overrideWithValue(beta),
        telemetryDevModeProvider.overrideWithValue(dev),
      ],
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        // `app.dart` binds the strings bundle from inside MaterialApp, where
        // L10N.of resolves; the Settings screen sits under that.
        home: Builder(
          builder: (context) => ProviderScope(
            overrides: [
              cruxTelemetryStringsProvider.overrideWithValue(
                WavecruxTelemetryStrings(L10N.of(context)),
              ),
            ],
            child: const SettingsScreen(),
          ),
        ),
      ),
    );

    testWidgets('is absent during the beta with no dev flag', (tester) async {
      await tester.pumpWidget(wrapGated(beta: true, dev: false));
      await tester.pumpAndSettle();

      // The beta Settings screen is exactly what it was before telemetry
      // existed — no category, and no way to reach the toggle.
      expect(find.text('Privacy'), findsNothing);
      expect(find.byKey(const Key('settingsTelemetrySwitch')), findsNothing);
    });

    testWidgets('appears post-beta, third in the rail', (tester) async {
      await tester.pumpWidget(wrapGated(beta: false, dev: false));
      await tester.pumpAndSettle();

      expect(find.text('Privacy'), findsWidgets);

      await _selectCategory(tester, 'Privacy');
      expect(find.byKey(const Key('settingsTelemetrySwitch')), findsOneWidget);
    });

    testWidgets('appears during the beta under the dev flag', (tester) async {
      await tester.pumpWidget(wrapGated(beta: true, dev: true));
      await tester.pumpAndSettle();

      expect(find.text('Privacy'), findsWidgets);
    });
  });
}
