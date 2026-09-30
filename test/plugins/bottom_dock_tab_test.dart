// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';
import 'package:wavecrux/plugins/bottom_dock_tab.dart';

final _stubVisibility = Provider<bool>((_) => false);

void main() {
  group('BottomDockTab', () {
    test('defaults requiredTier to openCore', () {
      final tab = BottomDockTab(
        id: 'test',
        labelResolver: (_) => 'Test',
        icon: Icons.list,
        builder: (_) => const SizedBox.shrink(),
        visibilityProvider: _stubVisibility,
      );
      expect(tab.requiredTier, LicenseTier.openCore);
    });

    test('equality is by id only', () {
      final a = BottomDockTab(
        id: 'sva',
        labelResolver: (_) => 'A',
        icon: Icons.check,
        builder: (_) => const SizedBox.shrink(),
        visibilityProvider: _stubVisibility,
      );
      final b = BottomDockTab(
        id: 'sva',
        labelResolver: (_) => 'B',
        icon: Icons.flag,
        builder: (_) => const SizedBox(width: 1),
        visibilityProvider: _stubVisibility,
        requiredTier: LicenseTier.pro,
      );
      final c = BottomDockTab(
        id: 'cocotb',
        labelResolver: (_) => 'C',
        icon: Icons.list,
        builder: (_) => const SizedBox.shrink(),
        visibilityProvider: _stubVisibility,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    testWidgets(
      'labelResolver receives a BuildContext that reaches Localizations '
      '(seam contract: overlay packages resolve their own bundles)',
      (tester) async {
        // The resolver's context must support Localizations lookups so a
        // contributed tab can read from its own delegate (L10NPro in the
        // Pro overlay). Regression guard for the original L10N-typed
        // signature, which made overlay-owned strings unreachable and
        // forced hardcoded English labels.
        final tab = BottomDockTab(
          id: 'localized',
          labelResolver: (context) =>
              Localizations.localeOf(context).languageCode,
          icon: Icons.list,
          builder: (_) => const SizedBox.shrink(),
          visibilityProvider: _stubVisibility,
        );

        late String resolved;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ja'),
            localizationsDelegates: L10N.localizationsDelegates,
            supportedLocales: L10N.supportedLocales,
            home: Builder(
              builder: (context) {
                resolved = tab.labelResolver(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(resolved, 'ja');
      },
    );
  });
}
