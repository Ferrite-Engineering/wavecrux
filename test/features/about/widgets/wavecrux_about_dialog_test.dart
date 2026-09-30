// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/app_info/application_branding.dart';
import 'package:wavecrux/core/app_info/application_branding_provider.dart';
import 'package:wavecrux/core/app_info/application_build_info.dart';
import 'package:wavecrux/core/app_info/application_build_info_provider.dart';
import 'package:wavecrux/core/updates/wavecrux_update_config.dart';
import 'package:wavecrux/features/about/widgets/wavecrux_about_dialog.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Spy notifier: records manual checks and returns a fixed "current" state
/// without the real launch-check / timer side effects.
class _SpyUpdateStatusNotifier extends UpdateStatusNotifier {
  int checkNowCalls = 0;

  @override
  UpdateStatus build() => const UpdateStatusCurrent();

  @override
  Future<void> checkNow() async => checkNowCalls++;
}

// ── Shared stub data ──────────────────────────────────────────────────────────

const _stubBuildInfo = ApplicationBuildInfo(
  version: '1.2.3',
  buildNumber: '42',
  gitSha: 'abc1234',
  os: 'macOS 15.0',
  architecture: 'arm64',
  flutterVersion: '3.29.0',
  dartVersion: '3.7.0',
);

const _stubBranding = ApplicationBranding(
  companyName: 'Ferrite Engineering',
  logoAsset: 'assets/branding/ferrite_engineering_logo.png',
  logoSquareAsset: 'assets/branding/ferrite_engineering_logo_square.png',
  copyrightYear: '2025',
  websiteUrl: 'https://ferriteengineering.com',
);

// ── Shared overrides ──────────────────────────────────────────────────────────

List<Override> _baseOverrides({LicenseTier tier = LicenseTier.openCore}) => [
  applicationBuildInfoProvider.overrideWith((_) async => _stubBuildInfo),
  applicationBrandingProvider.overrideWith((_) => _stubBranding),
  // The About box's "Check for Updates" action runs the shared
  // `runManualUpdateCheck`, which reads `cruxUpdateStringsProvider` — whose
  // package default resolves the product name from the update config. Bind the
  // real WaveCrux config so that read does not hit the unconfigured throw.
  cruxUpdateConfigProvider.overrideWithValue(wavecruxUpdateConfig),
  if (tier != LicenseTier.openCore)
    licenseTierProvider.overrideWith((_) => tier),
];

// ── Host that triggers WaveCruxAboutDialog.openAdaptive ───────────────────────

/// Renders a single button that opens the About dialog. Since the dialog is now
/// the shared [CruxAboutDialog] presented via `openAdaptive`, the test opens it
/// and asserts WaveCrux's mapping (title, build info, attribution, actions).
Widget _buildApp({
  String locale = 'en',
  LicenseTier tier = LicenseTier.openCore,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    ..._baseOverrides(tier: tier),
    ...overrides,
  ],
  child: MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: L10N.localizationsDelegates,
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(
      body: Consumer(
        builder: (context, ref, _) => Center(
          child: ElevatedButton(
            onPressed: () => WaveCruxAboutDialog.openAdaptive(context, ref),
            child: const Text('open-about'),
          ),
        ),
      ),
    ),
  ),
);

// ── Pump + open helper ────────────────────────────────────────────────────────

/// Opens the dialog and advances enough frames to resolve the awaited build
/// info future and the route push.
///
/// Does NOT use pumpAndSettle — the header's GlowingAppIcon runs perpetual
/// AnimationControllers (.repeat) so pumpAndSettle never completes.
Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('open-about'));
  await tester.pump(); // run handler up to the build-info await
  await tester.pump(); // resolve the build-info future microtask
  await tester.pump(const Duration(milliseconds: 300)); // route transition
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── locale sweeps ───────────────────────────────────────────────────────────

  group('locale sweeps', () {
    for (final locale in ['en', 'zh', 'ja', 'ko']) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(_buildApp(locale: locale));
        await _openDialog(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── responsive sizes ────────────────────────────────────────────────────────

  group('responsive surface sizes', () {
    for (final entry in [
      ('phone', const Size(400, 800)),
      ('tablet', const Size(800, 1024)),
      ('desktop', const Size(1400, 900)),
    ]) {
      testWidgets('renders without overflow on ${entry.$1}', (tester) async {
        tester.view.physicalSize = entry.$2;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_buildApp());
        await _openDialog(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── content checks ──────────────────────────────────────────────────────────

  group('content', () {
    testWidgets('shows dialog title', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      expect(find.text('About WaveCrux'), findsWidgets);
    });

    testWidgets('shows tagline text', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      expect(find.textContaining('waveform'), findsWidgets);
    });

    testWidgets('shows version number from stub build info', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      expect(find.text('1.2.3'), findsWidgets);
    });

    testWidgets('shows git SHA from stub build info', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      expect(find.text('abc1234'), findsWidgets);
    });

    testWidgets('shows company name in branding banner', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      expect(find.text('Ferrite Engineering'), findsWidgets);
    });
  });

  // ── beta indicator ─────────────────────────────────────────────────────────

  group('beta indicator', () {
    testWidgets('beta chip is present when kBetaPeriod is true', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);

      if (kBetaPeriod) {
        expect(find.text('Public Beta'), findsOneWidget);
      } else {
        expect(find.text('Public Beta'), findsNothing);
      }
    });

    testWidgets('beta chip is suppressed when the beta provider is off', (
      tester,
    ) async {
      // On a mobile store build `bootstrap` overrides `betaPeriodProvider` to
      // false (see app.dart): consumer app stores forbid shipping pre-release
      // software — App Store Review Guideline 2.2, which rejected WaveCrux
      // 0.1.0 (2) — and the mobile builds carry no beta expiry, so there is no
      // beta for the chip to describe. Desktop keeps the real chip.
      //
      // Asserted through the provider rather than a platform override because
      // that is the actual mechanism; `bootstrap`'s host branch is covered in
      // app-level tests.
      await tester.pumpWidget(
        _buildApp(overrides: [betaPeriodProvider.overrideWithValue(false)]),
      );
      await _openDialog(tester);

      expect(find.text('Public Beta'), findsNothing);
    });
  });

  // ── edition chip ────────────────────────────────────────────────────────────

  group('edition chip', () {
    testWidgets('no edition chip shown for openCore tier', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);

      // The edition chip only renders for Pro/Enterprise; openCore is hidden.
      expect(find.text('Pro'), findsNothing);
      expect(find.text('Enterprise'), findsNothing);
    });

    testWidgets('EditionBadge shown for edu tier', (tester) async {
      await tester.pumpWidget(_buildApp(tier: LicenseTier.edu));
      await _openDialog(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('EDU'), findsWidgets);
    });
  });

  // ── action buttons ──────────────────────────────────────────────────────────

  group('action buttons', () {
    testWidgets('shows "Copy Version Info" button', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      expect(find.text('Copy Version Info'), findsOneWidget);
    });

    testWidgets('shows "Acknowledgments" button', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      expect(find.text('Acknowledgments'), findsOneWidget);
    });

    testWidgets('shows "Visit Website" button', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      expect(find.text('Visit Website'), findsOneWidget);
    });

    testWidgets('shows "Report Issue" button', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      expect(find.text('Report Issue'), findsOneWidget);
    });

    testWidgets('shows "Check for Updates" button', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      expect(find.text('Check for Updates'), findsOneWidget);
    });

    testWidgets('tapping "Check for Updates" invokes checkNow()', (
      tester,
    ) async {
      final spy = _SpyUpdateStatusNotifier();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._baseOverrides(),
            updateStatusProvider.overrideWith(() => spy),
          ],
          child: MaterialApp(
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Center(
                  child: ElevatedButton(
                    onPressed: () =>
                        WaveCruxAboutDialog.openAdaptive(context, ref),
                    child: const Text('open-about'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _openDialog(tester);

      final button = find.ancestor(
        of: find.text('Check for Updates'),
        matching: find.byType(OutlinedButton),
      );
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump(); // run the async handler

      expect(spy.checkNowCalls, 1);
    });

    testWidgets('"Copy Version Info" button is enabled once build info loads', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);

      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Copy Version Info'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets(
      'tapping "Copy Version Info" writes the structured build info to the '
      'clipboard',
      (tester) async {
        // Capture the platform clipboard channel so we can assert the exact
        // payload the host wires into `aboutVersionInfoText`. The string
        // *format* is unit-tested in the crux_about_dialog package; this guards
        // the WaveCrux-side wiring (app name + edition + the stub build info)
        // and the "Copy Version Info clipboard content is correctly
        // structured" verification row.
        final copied = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        await tester.pumpWidget(_buildApp());
        await _openDialog(tester);

        // The action buttons sit below the fold in the default 800×600 test
        // viewport — scroll the button into view before tapping it.
        final copyButton = find.ancestor(
          of: find.text('Copy Version Info'),
          matching: find.byType(OutlinedButton),
        );
        await tester.ensureVisible(copyButton);
        await tester.pump();
        await tester.tap(copyButton);
        await tester.pump(); // run the async copy handler

        expect(copied, hasLength(1));
        final text = copied.single;
        // The product name and every field from `_stubBuildInfo` must appear.
        expect(text, contains('WaveCrux'));
        expect(text, contains('1.2.3')); // version
        expect(text, contains('42')); // build number
        expect(text, contains('abc1234')); // git SHA
        expect(text, contains('macOS 15.0')); // OS
        expect(text, contains('arm64')); // architecture
        expect(text, contains('3.29.0')); // Flutter version
        expect(text, contains('3.7.0')); // Dart version
      },
    );
  });

  // ── wellen attribution ──────────────────────────────────────────────────────

  group('wellen attribution', () {
    testWidgets('shows wellen section header', (tester) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);
      expect(find.textContaining('wellen'), findsWidgets);
    });

    testWidgets('license expander reveals the license text on tap', (
      tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _openDialog(tester);

      final header = find.text('BSD 3-Clause License');
      await tester.ensureVisible(header);
      await tester.pump();
      await tester.tap(header);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SelectableText &&
              (w.data?.contains('Kevin Laeufer') ?? false),
        ),
        findsOneWidget,
      );
    });
  });
}
