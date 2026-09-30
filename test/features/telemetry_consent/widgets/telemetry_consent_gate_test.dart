// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/core/mobile_metrics.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_config.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_storage.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_strings.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/layouts/device_class_provider.dart';
import 'package:wavecrux/shared/widgets/display_size_feed.dart';

// ── Harness ──────────────────────────────────────────────────────────────────
//
// The gate and the disclosure are `crux_telemetry`'s; their own behaviour is
// tested there against an in-memory store. This file exercises the WaveCrux
// *wiring* end to end and against the real plugin: `WavecruxTelemetryStorage`
// over SharedPreferences under the suite-fixed key, `WavecruxTelemetryStrings`
// over the ARB, and the real `DisplaySizeFeed` -> `deviceClassProvider` ->
// `isPhoneLayout` chain that decides sheet vs dialog at real device sizes.

/// Real device sizes rather than round numbers, so the classification under
/// test is the one a user's device actually produces.
const _phone = Size(390, 844);
const _tablet = Size(834, 1112);
const _desktop = Size(1440, 900);

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

/// Every URL the surface asked to open.
late List<Uri> launched;

/// Constrains the test surface to [size] so `deviceClassProvider` — fed
/// through the production `DisplaySizeFeed` — classifies it for real.
void _setSurface(WidgetTester tester, Size size) {
  tester.view
    ..devicePixelRatio = 1.0
    ..physicalSize = size;
  addTearDown(tester.view.reset);
}

Widget _wrap({
  bool beta = false,
  bool dev = false,
  Locale? locale,
  Widget child = const SizedBox.shrink(),
}) {
  launched = <Uri>[];
  return ProviderScope(
    overrides: [
      cruxTelemetryConfigProvider.overrideWithValue(wavecruxTelemetryConfig),
      telemetryStorageProvider.overrideWithValue(
        const WavecruxTelemetryStorage(),
      ),
      telemetryBetaPeriodProvider.overrideWithValue(beta),
      telemetryDevModeProvider.overrideWithValue(dev),
      telemetryUrlLauncherProvider.overrideWithValue((uri) async {
        launched.add(uri);
        return true;
      }),
    ],
    child: MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      locale: locale,
      home: DisplaySizeFeed(
        // Exactly what `app.dart` mounts: the strings bundle bound from inside
        // MaterialApp (where L10N.of resolves), and the layout idiom handed to
        // the shared widget rather than re-derived inside it.
        child: Consumer(
          builder: (context, ref, _) {
            final deviceClass = ref.watch(deviceClassProvider);
            final metrics = MobileMetrics.of(context, deviceClass);
            return ProviderScope(
              overrides: [
                cruxTelemetryStringsProvider.overrideWithValue(
                  WavecruxTelemetryStrings(L10N.of(context)),
                ),
              ],
              child: TelemetryConsentGate(
                isPhoneLayout: deviceClass.isPhoneClass,
                metrics: CruxTelemetryConsentMetrics(
                  touchTarget: metrics.touchTarget,
                  iconSize: metrics.iconSize,
                  bodyFontSize: metrics.bodyText,
                ),
                child: child,
              ),
            );
          },
        ),
      ),
    ),
  );
}

Finder get _disclosure => find.byType(TelemetryConsentDisclosure);
Finder get _switch => find.byKey(const Key('telemetryConsentSwitch'));
Finder get _continue => find.byKey(const Key('telemetryConsentContinueButton'));

Future<TelemetryConsentState> _storedConsent() async {
  final prefs = await SharedPreferences.getInstance();
  return TelemetryConsentState.tryParse(
        prefs.getString(TelemetryConsentStore.storageKey),
      ) ??
      TelemetryConsentState.unset;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // ── When it mounts ─────────────────────────────────────────────────────────

  group('TelemetryConsentGate mounting', () {
    testWidgets('mounts once on a fresh post-beta installation', (
      tester,
    ) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(_disclosure, findsOneWidget);
    });

    testWidgets('does not mount for an installation that already answered', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'telemetry.consent': 'disabled',
      });
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(_disclosure, findsNothing);
    });

    testWidgets('never flashes before the persisted consent has settled', (
      tester,
    ) async {
      // The store publishes `unset` synchronously and loads afterwards. A gate
      // keyed on the state alone would mount here — and re-ask a user who
      // answered on a previous launch.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'telemetry.consent': 'enabled',
      });
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());

      await tester.pump();
      expect(_disclosure, findsNothing);
      await tester.pumpAndSettle();
      expect(_disclosure, findsNothing);
    });

    testWidgets('leaves the wrapped content alone when it does not mount', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'telemetry.consent': 'enabled',
      });
      _setSurface(tester, _desktop);
      await tester.pumpWidget(
        _wrap(child: const Text('routed', textDirection: TextDirection.ltr)),
      );
      await tester.pumpAndSettle();

      expect(find.text('routed'), findsOneWidget);
      expect(_disclosure, findsNothing);
    });

    testWidgets('shows exactly once per installation', (tester) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(_disclosure, findsOneWidget);

      await tester.tap(_continue);
      await tester.pumpAndSettle();
      expect(_disclosure, findsNothing);

      // A second launch reads the same preferences store back.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(_disclosure, findsNothing);
    });
  });

  // ── What Continue writes ───────────────────────────────────────────────────

  group('the decision', () {
    testWidgets('the toggle arrives pre-armed on', (tester) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(_switch).value, isTrue);
    });

    testWidgets('pre-armed on + Continue writes enabled', (tester) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(_continue);
      await tester.pumpAndSettle();

      expect(await _storedConsent(), TelemetryConsentState.enabled);
    });

    testWidgets('toggled off + Continue writes disabled', (tester) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(_switch);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(_switch).value, isFalse);

      await tester.tap(_continue);
      await tester.pumpAndSettle();

      expect(await _storedConsent(), TelemetryConsentState.disabled);
    });

    testWidgets('off is exactly as reachable as on — one visible switch, one '
        'button, both on screen without scrolling', (tester) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // No "advanced", no second confirmation step, no hidden affordance:
      // declining is flip-then-Continue, accepting is Continue.
      expect(_switch, findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(
        tester.getRect(_switch).overlaps(tester.getRect(_continue)),
        isFalse,
      );
    });

    testWidgets('the documentation link opens the suite telemetry page', (
      tester,
    ) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('telemetryConsentLearnMoreButton')),
      );
      await tester.pumpAndSettle();

      expect(launched, [Uri.parse('https://edacrux.app/telemetry')]);
      // Reading the docs is not an answer — the disclosure stays up.
      expect(_disclosure, findsOneWidget);
    });

    testWidgets('the system back gesture cannot dismiss it unanswered', (
      tester,
    ) async {
      _setSurface(tester, _phone);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final popScope = tester.widget<PopScope<dynamic>>(
        find.descendant(
          of: _disclosure,
          matching: find.byType(PopScope<dynamic>),
        ),
      );
      expect(popScope.canPop, isFalse);
      expect(await _storedConsent(), TelemetryConsentState.unset);
    });
  });

  // ── Layout ─────────────────────────────────────────────────────────────────

  group('mobile parity', () {
    testWidgets('phone width renders the full-screen sheet', (tester) async {
      _setSurface(tester, _phone);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('telemetryConsentSheet')), findsOneWidget);
      expect(find.byKey(const Key('telemetryConsentDialog')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet width renders the dialog card', (tester) async {
      _setSurface(tester, _tablet);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('telemetryConsentDialog')), findsOneWidget);
      expect(find.byKey(const Key('telemetryConsentSheet')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('desktop width renders the dialog card', (tester) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('telemetryConsentDialog')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final (name, size) in [
      ('phone', _phone),
      ('tablet', _tablet),
      ('desktop', _desktop),
    ]) {
      testWidgets('every control clears 44 dp at $name width', (tester) async {
        _setSurface(tester, size);
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        for (final target in [
          _switch,
          _continue,
          find.byKey(const Key('telemetryConsentLearnMoreButton')),
        ]) {
          final rect = tester.getSize(target);
          expect(
            rect.height,
            greaterThanOrEqualTo(kTelemetryConsentMinTarget),
            reason: '$target is under the 44 dp floor at $name width',
          );
          expect(rect.width, greaterThanOrEqualTo(kTelemetryConsentMinTarget));
        }
      });
    }
  });

  // ── Locale sweep ───────────────────────────────────────────────────────────

  group('locale sweep', () {
    for (final locale in _locales) {
      for (final (name, size) in [('phone', _phone), ('tablet', _tablet)]) {
        testWidgets('renders in $locale at $name width without exceptions', (
          tester,
        ) async {
          _setSurface(tester, size);
          await tester.pumpWidget(_wrap(locale: locale));
          await tester.pumpAndSettle();

          expect(_disclosure, findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
