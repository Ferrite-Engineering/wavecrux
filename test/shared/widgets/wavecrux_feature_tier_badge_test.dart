// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/license/tier_badge_impression_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/shared/widgets/wavecrux_feature_tier_badge.dart';

import '../../helpers/product_telemetry_config.dart';

/// Captures recorded events for the `badge.impression` assertions.
class _RecordingTelemetry implements TelemetryService {
  final events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);

  List<TelemetryEvent> named(String name) =>
      events.where((e) => e.name == name).toList();
}

Widget _harness(
  Widget child, {
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [productTelemetryConfig, ...overrides],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('FeatureTierBadge', () {
    testWidgets('open-core tier renders nothing (zero-size SizedBox)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const WaveCruxFeatureTierBadge(requiredTier: LicenseTier.openCore),
        ),
      );
      expect(find.text('PRO'), findsNothing);
      expect(find.text('ENT'), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('Pro tier renders the PRO chip', (tester) async {
      await tester.pumpWidget(
        _harness(const WaveCruxFeatureTierBadge(requiredTier: LicenseTier.pro)),
      );
      expect(find.text('PRO'), findsOneWidget);
      expect(find.text('ENT'), findsNothing);
    });

    testWidgets('Enterprise tier renders the ENT chip', (tester) async {
      await tester.pumpWidget(
        _harness(
          const WaveCruxFeatureTierBadge(requiredTier: LicenseTier.enterprise),
        ),
      );
      expect(find.text('ENT'), findsOneWidget);
      expect(find.text('PRO'), findsNothing);
    });

    testWidgets('EDU tier renders nothing (no feature is gate-labeled as EDU; '
        'EDU is a license edition surfaced by EditionBadge instead)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(const WaveCruxFeatureTierBadge(requiredTier: LicenseTier.edu)),
      );
      expect(find.text('EDU'), findsNothing);
      expect(find.text('PRO'), findsNothing);
      expect(find.text('ENT'), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('locale sweep — renders without exceptions in en/zh_CN/ja/ko', (
      tester,
    ) async {
      const locales = [
        Locale('en'),
        Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
        Locale('ja'),
        Locale('ko'),
      ];
      for (final locale in locales) {
        await tester.pumpWidget(
          _harness(
            const WaveCruxFeatureTierBadge(requiredTier: LicenseTier.pro),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'FeatureTierBadge raised in locale ${locale.toLanguageTag()}',
        );
      }
    });
  });

  // The badge is the funnel's impression point. The
  // unit is (tier, session) — see `TierBadgeImpressionNotifier` for why not
  // per badge and certainly not per build.
  group('badge.impression', () {
    testWidgets('a mounted PRO badge records one impression', (tester) async {
      final telemetry = _RecordingTelemetry();
      await tester.pumpWidget(
        _harness(
          const WaveCruxFeatureTierBadge(requiredTier: LicenseTier.pro),
          overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
        ),
      );
      await tester.pumpAndSettle();
      expect(telemetry.named('badge.impression'), hasLength(1));
      expect(
        telemetry.named('badge.impression').single.properties['tier'],
        'pro',
      );
    });

    testWidgets('forty PRO badges in one session record one impression', (
      tester,
    ) async {
      // The decoder picker's real shape: a list of Pro-badged rows. One
      // person learning that Pro decoders exist is one impression, not forty
      // — otherwise the ratio against `badge.click` measures catalogue size.
      final telemetry = _RecordingTelemetry();
      await tester.pumpWidget(
        _harness(
          SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List<Widget>.generate(
                40,
                (_) => const WaveCruxFeatureTierBadge(
                  requiredTier: LicenseTier.pro,
                ),
              ),
            ),
          ),
          overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
        ),
      );
      await tester.pumpAndSettle();
      expect(telemetry.named('badge.impression'), hasLength(1));
    });

    testWidgets('PRO and ENT are separate impressions', (tester) async {
      final telemetry = _RecordingTelemetry();
      await tester.pumpWidget(
        _harness(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WaveCruxFeatureTierBadge(requiredTier: LicenseTier.pro),
              WaveCruxFeatureTierBadge(requiredTier: LicenseTier.enterprise),
            ],
          ),
          overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        telemetry.named('badge.impression').map((e) => e.properties['tier']),
        containsAll(<String>['pro', 'enterprise']),
      );
      expect(telemetry.named('badge.impression'), hasLength(2));
    });

    testWidgets('a tier that renders no badge records no impression', (
      tester,
    ) async {
      final telemetry = _RecordingTelemetry();
      await tester.pumpWidget(
        _harness(
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WaveCruxFeatureTierBadge(requiredTier: LicenseTier.openCore),
              WaveCruxFeatureTierBadge(requiredTier: LicenseTier.edu),
            ],
          ),
          overrides: [telemetryServiceProvider.overrideWithValue(telemetry)],
        ),
      );
      await tester.pumpAndSettle();
      expect(telemetry.named('badge.impression'), isEmpty);
    });

    test('the notifier reports whether it recorded, and refuses repeats', () {
      final telemetry = _RecordingTelemetry();
      final container = ProviderContainer(
        overrides: [
          productTelemetryConfig,
          telemetryServiceProvider.overrideWithValue(telemetry),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(tierBadgeImpressionProvider.notifier);

      expect(notifier.recordImpression(LicenseTier.pro), isTrue);
      expect(notifier.recordImpression(LicenseTier.pro), isFalse);
      expect(notifier.recordImpression(LicenseTier.enterprise), isTrue);
      expect(notifier.recordImpression(LicenseTier.openCore), isFalse);
      expect(notifier.recordImpression(LicenseTier.edu), isFalse);
      expect(telemetry.named('badge.impression'), hasLength(2));
    });
  });
}
