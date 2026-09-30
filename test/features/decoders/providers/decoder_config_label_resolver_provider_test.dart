// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/features/decoders/providers/decoder_config_label_resolver_provider.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

/// Pumps a host that exposes the open-core resolver bound to a real
/// localized [BuildContext], then hands it to [body].
Future<void> _withResolver(
  WidgetTester tester,
  Locale locale,
  void Function(DecoderConfigLabelResolver resolve, L10N l10n) body,
) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) {
            final resolve = ref.watch(
              decoderConfigLabelResolverFactoryProvider,
            )(context);
            body(resolve, L10N.of(context));
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('decoderConfigLabelResolverFactoryProvider — open-core default', () {
    testWidgets('resolves a known param label key to the localized string', (
      tester,
    ) async {
      await _withResolver(tester, const Locale('en'), (resolve, l10n) {
        expect(resolve('spiParamCpol'), l10n.spiParamCpol);
        expect(resolve('spiParamCpol'), 'CPOL');
      });
    });

    testWidgets('resolves a known enum choice key to the localized string', (
      tester,
    ) async {
      await _withResolver(tester, const Locale('en'), (resolve, l10n) {
        expect(resolve('spiChoiceCpol0'), l10n.spiChoiceCpol0);
        expect(resolve('spiChoiceCpol0'), '0 (Idle Low)');
      });
    });

    testWidgets('resolves a description key', (tester) async {
      await _withResolver(tester, const Locale('en'), (resolve, l10n) {
        expect(
          resolve('spiParamCpolDescription'),
          l10n.spiParamCpolDescription,
        );
      });
    });

    testWidgets('resolves a reused SPI-Flash vendor choice key', (
      tester,
    ) async {
      await _withResolver(tester, const Locale('en'), (resolve, l10n) {
        expect(
          resolve('spiFlashChoiceVendorWinbond'),
          l10n.spiFlashChoiceVendorWinbond,
        );
      });
    });

    testWidgets('unknown key returns identity (the raw key)', (tester) async {
      await _withResolver(tester, const Locale('en'), (resolve, _) {
        expect(resolve('totallyUnknownKey'), 'totallyUnknownKey');
        // A Pro decoder key the open-core catalog does not know about.
        expect(resolve('axi4FullParamBurstType'), 'axi4FullParamBurstType');
      });
    });

    testWidgets('localizes across the locale sweep', (tester) async {
      for (final code in ['en', 'zh', 'ja', 'ko']) {
        await _withResolver(tester, Locale(code), (resolve, l10n) {
          // Known key resolves to that locale's value; unknown stays identity.
          expect(
            resolve('wishboneChoiceRevisionB3'),
            l10n.wishboneChoiceRevisionB3,
          );
          expect(resolve('nopeNotAKey'), 'nopeNotAKey');
        });
      }
    });
  });
}
