// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart'
    show betaPeriodProvider, kBetaPeriod;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_config.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_storage.dart';
import 'package:wavecrux/core/telemetry/wavecrux_telemetry_strings.dart';
import 'package:wavecrux/features/settings/screens/settings_screen.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// WaveCrux's half of the telemetry gating guarantee.
///
/// The 12-cell `beta × dev × consent` gating matrix and the traffic-level
/// beta-inert test live in `crux_telemetry` — they exercise the gate itself,
/// which is now shared. What cannot move, and is asserted here, is that
/// **this build** is wired so the gate actually holds:
///
///  * the real `kBetaPeriod` / `kTelemetryDev` constants this release ships
///    with let the user's consent decide, through WaveCrux's own configuration
///    and preferences adapter: nothing is constructed that could send until
///    the user opts in;
///  * during a beta, an opt-in does not override the beta gate, and
///    `app.dart`'s mobile `betaPeriodProvider` override — a *badging*
///    decision — does not activate telemetry;
///  * neither consent surface mounts in a beta build's UI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// The root container `bootstrap` builds, minus the network.
  ProviderContainer wavecruxContainer({List<Override> extra = const []}) {
    final container = ProviderContainer(
      overrides: [
        cruxTelemetryConfigProvider.overrideWithValue(wavecruxTelemetryConfig),
        telemetryStorageProvider.overrideWithValue(
          const WavecruxTelemetryStorage(),
        ),
        telemetryHttpClientProvider.overrideWithValue(
          MockClient((_) async => http.Response('{}', 202)),
        ),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group("THE BETA-INERT TEST — WaveCrux's side of the dark launch", () {
    test('the shipping build has ended the beta, so consent decides', () async {
      // The flip that activates telemetry is this constant, and nothing else:
      // a release passes no BETA_PERIOD define, so it ships the default.
      expect(kBetaPeriod, isFalse);
      expect(kTelemetryDev, isFalse);

      // Neither the beta nor the dev seam is overridden, so both read the
      // shipping defaults. Consent is read through WaveCrux's own preferences
      // adapter; the HTTP client is a mock, so nothing leaves the test.
      Future<ProviderContainer> shipping(TelemetryConsentState stored) async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          if (stored != TelemetryConsentState.unset)
            'flutter.telemetry.consent': stored.name,
        });
        final container = wavecruxContainer(
          extra: [
            telemetryAppVersionProvider.overrideWith((_) async => '1.0.0'),
          ],
        );
        await container.read(telemetryConsentReadyProvider.future);
        return container;
      }

      // Not answered is not consent: nothing is constructed that could send.
      // The disclosure is on screen, so the launch's events wait for its
      // answer — a pending service, which transmits exactly as much as the
      // no-op does.
      final unanswered = await shipping(TelemetryConsentState.unset);
      expect(unanswered.read(telemetryBetaPeriodProvider), isFalse);
      expect(unanswered.read(telemetryEnabledProvider), isFalse);
      expect(
        unanswered.read(telemetryServiceProvider),
        isA<PendingTelemetryService>(),
      );

      // A user who opted in is counted, with no define and no dev flag.
      final consented = await shipping(TelemetryConsentState.enabled);
      expect(consented.read(telemetryEnabledProvider), isTrue);
      expect(
        consented.read(telemetryServiceProvider),
        isA<LiveTelemetryService>(),
      );
    });

    test('during a beta, an explicit `enabled` consent does not override the '
        'beta gate', () {
      final container = wavecruxContainer(
        extra: [telemetryBetaPeriodProvider.overrideWithValue(true)],
      );
      container.read(telemetryConsentStoreProvider.notifier).state =
          TelemetryConsentState.enabled;

      expect(container.read(telemetryEnabledProvider), isFalse);
      expect(
        container.read(telemetryServiceProvider),
        isA<NoopTelemetryService>(),
      );
    });

    test(
      "app.dart's mobile betaPeriodProvider override does NOT activate "
      'telemetry',
      () {
        // `lib/app.dart` sets betaPeriodProvider=false on mobile hosts so a
        // store build does not advertise a public beta (App Store Review
        // Guideline 2.2). That is a badging decision. If telemetry read that
        // provider, every iOS and Android beta build would start transmitting
        // while desktop stayed inert — and would do it before the store privacy
        // declarations shipped.
        //
        // So the beta is pinned on here rather than taken from the default:
        // the question is whether the badging override leaks into telemetry
        // while the beta is still running, and a build that has ended the
        // beta cannot ask it.
        final container = wavecruxContainer(
          extra: [
            telemetryBetaPeriodProvider.overrideWithValue(true),
            betaPeriodProvider.overrideWithValue(false),
          ],
        );
        container.read(telemetryConsentStoreProvider.notifier).state =
            TelemetryConsentState.enabled;

        expect(container.read(telemetryEnabledProvider), isFalse);
        expect(
          container.read(telemetryServiceProvider),
          isA<NoopTelemetryService>(),
        );
      },
    );

    testWidgets(
      'during beta with no dev flag, neither consent surface mounts',
      (tester) async {
        // The dark launch covers the UI too. A beta build must not show the
        // first-launch disclosure or the Settings → Privacy toggle: there is
        // nothing to consent to, and asking would advertise collection this
        // build is structurally incapable of doing.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              cruxTelemetryConfigProvider.overrideWithValue(
                wavecruxTelemetryConfig,
              ),
              telemetryStorageProvider.overrideWithValue(
                const WavecruxTelemetryStorage(),
              ),
              telemetryBetaPeriodProvider.overrideWithValue(true),
              telemetryDevModeProvider.overrideWithValue(false),
              telemetryHttpClientProvider.overrideWithValue(
                MockClient((_) async => http.Response('{}', 202)),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Builder(
                builder: (context) => ProviderScope(
                  overrides: [
                    cruxTelemetryStringsProvider.overrideWithValue(
                      WavecruxTelemetryStrings(L10N.of(context)),
                    ),
                  ],
                  child: const TelemetryConsentGate(child: SettingsScreen()),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TelemetryConsentDisclosure), findsNothing);
        expect(find.text('Privacy'), findsNothing);
        expect(find.byKey(const Key('settingsTelemetrySwitch')), findsNothing);
      },
    );
  });

  group("WaveCrux's envelope wiring", () {
    test('reports the wavecrux slug and a Worker-legal envelope', () async {
      // The product slug is the one field `crux_telemetry` cannot supply, and
      // a slug the Worker does not know rejects every batch WaveCrux ever
      // sends with a 400 the client never sees.
      final container = wavecruxContainer(
        extra: [telemetryAppVersionProvider.overrideWith((_) async => '0.6.0')],
      );

      final envelope = await container.read(
        telemetryEnvelopeResolverProvider,
      )();

      expect(envelope, isNotNull);
      expect(envelope!.product, 'wavecrux');
      expect(envelope.userAgent, 'WaveCrux/0.6.0');
      expect(kTelemetryOperatingSystems, contains(envelope.os));
      expect(kTelemetryFormFactors, contains(envelope.formFactor));
      expect(kTelemetryLicenseTiers, contains(envelope.licenseTier));
      expect(
        kTelemetryInstallationIdPattern.hasMatch(envelope.installationId),
        isTrue,
      );
    });

    test(
      'the installation id persists under the suite-fixed prefs key',
      () async {
        final id = await wavecruxContainer().read(
          telemetryInstallationIdProvider.future,
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('telemetry.installationId'), id);
        expect(kTelemetryInstallationIdKey, 'telemetry.installationId');
      },
    );

    test('the endpoint is the production suite ingest', () {
      // Not a dev build, so not the staging dataset. The path selects the
      // dataset; nothing WaveCrux sends can move it.
      expect(
        wavecruxContainer().read(telemetryEndpointProvider).toString(),
        'https://telemetry.edacrux.app/v1/events',
      );
    });
  });

  group('D3 — a stored refusal, through the real preferences adapter', () {
    // The defect was found on this product, on this storage adapter: with
    // `flutter.telemetry.consent = disabled` on disk and a TELEMETRY_DEV build,
    // two launches put a real row in the staging dataset from the very
    // installation that had refused. `crux_telemetry` now holds the gate's own
    // pre-load cells against a synthetic store; this holds the same guarantee
    // against `WavecruxTelemetryStorage` and `SharedPreferences`, because the
    // window that mattered was the one that adapter's async read opens.

    test('a stored `disabled` never transmits under the dev flag', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.telemetry.consent': TelemetryConsentState.disabled.name,
      });
      final sent = <http.BaseRequest>[];
      final container = ProviderContainer(
        overrides: [
          cruxTelemetryConfigProvider.overrideWithValue(
            wavecruxTelemetryConfig,
          ),
          telemetryStorageProvider.overrideWithValue(
            const WavecruxTelemetryStorage(),
          ),
          telemetryBetaPeriodProvider.overrideWithValue(true),
          telemetryDevModeProvider.overrideWithValue(true),
          telemetryAppVersionProvider.overrideWith((_) async => '0.6.0'),
          telemetryHttpClientProvider.overrideWithValue(
            MockClient((request) async {
              sent.add(request);
              return http.Response('{"accepted":1,"dropped":0}', 202);
            }),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Read the service the way a feature does — at the very first frame,
      // before anything has awaited the store. This is the cold start, and it
      // is `pending` rather than `noop`: the question is genuinely still open,
      // and the events recorded here are buffered rather than discarded. What
      // matters for D3 is that pending is exactly as silent as noop, which the
      // request assertion below is what actually checks.
      final service = container.read(telemetryServiceProvider);
      expect(service, isA<PendingTelemetryService>());
      for (var i = 0; i < 50; i++) {
        service.record(
          TelemetryEvent(
            'workspace.restored',
            properties: const <String, Object?>{'panes': 1, 'tabs': 0},
          ),
        );
      }

      await container.read(telemetryConsentReadyProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(telemetryEnabledProvider), isFalse);
      expect(
        container.read(telemetryServiceProvider),
        isA<NoopTelemetryService>(),
      );
      expect(
        sent,
        isEmpty,
        reason:
            'an installation that stored `disabled` may not produce a row, and '
            'the dev flag is not a licence to ignore the answer it stored',
      );
      expect(
        container.read(telemetryPendingBufferProvider),
        isEmpty,
        reason:
            'and the buffer the pending window collected is dropped, not held '
            'against a decision that might change',
      );
    });

    test('a genuinely un-answered installation still transmits', () async {
      // The fix is "wait for the answer", not "treat unset as disabled". Under
      // the dev flag `unset` really does count as consent — that is what lets
      // the staging verification run with no UI at all.
      final container = wavecruxContainer(
        extra: [
          telemetryBetaPeriodProvider.overrideWithValue(true),
          telemetryDevModeProvider.overrideWithValue(true),
        ],
      );

      expect(container.read(telemetryEnabledProvider), isFalse);
      await container.read(telemetryConsentReadyProvider.future);
      expect(container.read(telemetryEnabledProvider), isTrue);
      expect(
        container.read(telemetryServiceProvider),
        isA<LiveTelemetryService>(),
      );
    });
  });

  group('the seam itself', () {
    test('can be overridden with a recording fake', () {
      final recorder = _RecordingTelemetryService();
      final container = ProviderContainer(
        overrides: [telemetryServiceProvider.overrideWithValue(recorder)],
      );
      addTearDown(container.dispose);

      container
          .read(telemetryServiceProvider)
          .record(TelemetryEvent('debug_advisor.suggestion.accepted'));

      expect(recorder.events, hasLength(1));
      expect(recorder.events.first.name, 'debug_advisor.suggestion.accepted');
    });
  });
}

class _RecordingTelemetryService implements TelemetryService {
  final events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);
}
