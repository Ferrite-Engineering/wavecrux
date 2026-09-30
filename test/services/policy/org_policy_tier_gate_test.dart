// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:crux_license/crux_license.dart';
import 'package:crux_policy/crux_policy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wavecrux/core/policy/wavecrux_policy_keys.dart';
import 'package:wavecrux/services/policy/org_decoder_settings.dart';
import 'package:wavecrux/services/policy/org_policy_tier_gate.dart';
import 'package:wavecrux/services/policy/org_signal_groups.dart';
import 'package:wavecrux/services/policy/org_theme_and_templates.dart';

/// The four organization keys that GRANT something are honoured only on a
/// seat whose tier includes the Enterprise administration surface.
///
/// Until this gate existed every key was honoured in open core at every
/// tier: the code could not reach a licence, the pricing page sold the keys
/// as Enterprise, and a downloader of the free build who dropped a policy
/// file at the well-known path got the whole surface. The refusal-shaped keys
/// beside them (`approvedPlugins`, the server switches) stay ungated on
/// purpose and are not tested here.
Map<String, Object?> _fullPolicy() => <String, Object?>{
  'schema': 1,
  'products': <String, Object?>{
    WaveCruxPolicyKeys.productId: <String, Object?>{
      WaveCruxPolicyKeys.signalGroups: <Object?>[
        <String, Object?>{
          'name': 'Clocks',
          'patterns': <Object?>['*.clk*'],
        },
      ],
      WaveCruxPolicyKeys.decoderSettings: <String, Object?>{
        'uart': <String, Object?>{'baud': 115200},
      },
      WaveCruxPolicyKeys.sessionTemplates: <Object?>[
        <String, Object?>{'path': '/share/wavecrux/template.json'},
      ],
      WaveCruxPolicyKeys.themePacks: <Object?>[
        <String, Object?>{'path': '/share/wavecrux/theme.json'},
      ],
    },
  },
};

ProviderContainer _container({
  required bool beta,
  required LicenseTier tier,
  Map<String, Object?>? policy,
}) {
  final container = ProviderContainer(
    overrides: <Override>[
      betaPeriodProvider.overrideWithValue(beta),
      licenseTierProvider.overrideWithValue(tier),
      cruxPolicyProvider.overrideWithValue(
        PolicyLoadResult(
          document: PolicyDocument.parse(jsonEncode(policy ?? _fullPolicy())),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('post-beta at Open Core, every granting key resolves to nothing', () {
    late ProviderContainer c;
    setUp(() => c = _container(beta: false, tier: LicenseTier.openCore));

    test('signal groups', () {
      expect(c.read(orgSignalGroupsProvider).isEmpty, isTrue);
    });
    test('decoder settings', () {
      expect(
        c.read(orgDecoderSettingsProvider).valueFor('uart', 'baud'),
        isNull,
      );
    });
    test('session template', () {
      expect(c.read(orgSessionTemplateProvider), isNull);
    });
    test('theme pack', () {
      expect(c.read(orgThemePackProvider), isNull);
    });
    test('and the withheld set names all four, so the refusal is legible', () {
      expect(
        c.read(orgPolicyWithheldByTierProvider),
        unorderedEquals(kWaveCruxTierGatedPolicyKeys),
      );
    });
  });

  for (final tier in <LicenseTier>[LicenseTier.pro, LicenseTier.edu]) {
    test(
      'post-beta at $tier is withheld too — this is Enterprise, not Pro',
      () {
        final c = _container(beta: false, tier: tier);
        expect(c.read(orgThemePackProvider), isNull);
        expect(c.read(orgSignalGroupsProvider).isEmpty, isTrue);
        expect(c.read(orgPolicyWithheldByTierProvider), isNotEmpty);
      },
    );
  }

  group('post-beta at Enterprise, every key is honoured', () {
    late ProviderContainer c;
    setUp(() => c = _container(beta: false, tier: LicenseTier.enterprise));

    test('signal groups', () {
      expect(c.read(orgSignalGroupsProvider).groups.single.name, 'Clocks');
    });
    test('decoder settings', () {
      expect(
        c.read(orgDecoderSettingsProvider).valueFor('uart', 'baud'),
        115200,
      );
    });
    test('session template', () {
      expect(
        c.read(orgSessionTemplateProvider)?.resource.path,
        '/share/wavecrux/template.json',
      );
    });
    test('theme pack', () {
      expect(
        c.read(orgThemePackProvider)?.resource.path,
        '/share/wavecrux/theme.json',
      );
    });
    test('and nothing is reported withheld', () {
      expect(c.read(orgPolicyWithheldByTierProvider), isEmpty);
    });
  });

  test('during the beta every tier is honoured', () {
    final c = _container(beta: true, tier: LicenseTier.openCore);
    expect(c.read(orgThemePackProvider), isNotNull);
    expect(c.read(orgSessionTemplateProvider), isNotNull);
    expect(c.read(orgSignalGroupsProvider).isEmpty, isFalse);
    expect(
      c.read(orgDecoderSettingsProvider).valueFor('uart', 'baud'),
      115200,
    );
    expect(c.read(orgPolicyWithheldByTierProvider), isEmpty);
  });

  test('the withheld set names only keys the file actually sets', () {
    // A free seat with no policy carries no warning about a policy nobody
    // wrote, and a file that sets one key is reported for that one key.
    final none = _container(
      beta: false,
      tier: LicenseTier.openCore,
      policy: <String, Object?>{'schema': 1},
    );
    expect(none.read(orgPolicyWithheldByTierProvider), isEmpty);

    final one = _container(
      beta: false,
      tier: LicenseTier.openCore,
      policy: <String, Object?>{
        'schema': 1,
        'products': <String, Object?>{
          WaveCruxPolicyKeys.productId: <String, Object?>{
            WaveCruxPolicyKeys.themePacks: <Object?>[
              <String, Object?>{'path': '/share/wavecrux/theme.json'},
            ],
          },
        },
      },
    );
    expect(one.read(orgPolicyWithheldByTierProvider), <String>{
      WaveCruxPolicyKeys.themePacks,
    });
  });

  test('a licence activated mid-session takes effect without a restart', () {
    final tierState = NotifierProvider<_TierNotifier, LicenseTier>(
      _TierNotifier.new,
    );
    final c = ProviderContainer(
      overrides: <Override>[
        betaPeriodProvider.overrideWithValue(false),
        licenseTierProvider.overrideWith((ref) => ref.watch(tierState)),
        cruxPolicyProvider.overrideWithValue(
          PolicyLoadResult(
            document: PolicyDocument.parse(jsonEncode(_fullPolicy())),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(orgThemePackProvider), isNull);
    c.read(tierState.notifier).tier = LicenseTier.enterprise;
    expect(c.read(orgThemePackProvider), isNotNull);
    expect(c.read(orgPolicyWithheldByTierProvider), isEmpty);
  });
}

/// A tier a test can move, the way an activated licence moves the real one.
class _TierNotifier extends Notifier<LicenseTier> {
  @override
  LicenseTier build() => LicenseTier.openCore;

  LicenseTier get tier => state;

  set tier(LicenseTier tier) => state = tier;
}
