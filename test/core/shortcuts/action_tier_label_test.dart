// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/shortcuts/action_tier_label.dart';
import 'package:wavecrux/l10n/generated/l10n.dart';

void main() {
  group('tierLabelSuffix', () {
    late L10N l10n;

    setUp(() async {
      l10n = await L10N.delegate.load(const Locale('en'));
    });

    test('open-core and edu produce no suffix', () {
      expect(tierLabelSuffix(LicenseTier.openCore, l10n), isEmpty);
      expect(tierLabelSuffix(LicenseTier.edu, l10n), isEmpty);
    });

    test('pro and enterprise produce parenthetical tier suffixes', () {
      final pro = tierLabelSuffix(LicenseTier.pro, l10n);
      final ent = tierLabelSuffix(LicenseTier.enterprise, l10n);
      expect(pro, contains(l10n.tierBadgePro));
      expect(pro, startsWith(' '));
      expect(ent, contains(l10n.tierBadgeEnterprise));
      expect(pro, isNot(equals(ent)));
    });
  });
}
